import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_availability.dart';
import '../ai_exception.dart';
import '../ai_schema.dart';
import '../language_model.dart';
import '../providers/provider_config.dart';
import 'http_transport.dart';
import 'sse.dart';

part 'anthropic_model.dart';
part 'openai_compatible_model.dart';

/// A [LanguageModel] served over HTTP by a third-party provider or a local
/// server. Prompts leave the device: show the user [config]'s host.
///
/// Remote providers ignore the `locale` argument; ask for a language in the
/// instructions if it matters. Construct one with [RemoteLanguageModel.create]
/// or a concrete class, and call [close] when done.
sealed class RemoteLanguageModel implements LanguageModel {
  RemoteLanguageModel._({
    required this.config,
    required this._headers,
    http.Client? client,
    Duration timeout = const Duration(seconds: 90),
  }) : _transport = HttpTransport(client: client, timeout: timeout);

  /// The adapter for [config]'s protocol. [apiKey] may be null for servers
  /// that need none (a local Ollama). Pass a shared [client] to reuse
  /// connections; otherwise one is created and released by [close].
  factory RemoteLanguageModel.create(
    ProviderConfig config, {
    String? apiKey,
    http.Client? client,
    Duration timeout = const Duration(seconds: 90),
  }) => switch (config.protocol) {
    ProviderProtocol.openAiCompatible => OpenAiCompatibleModel(
      config: config,
      apiKey: apiKey,
      client: client,
      timeout: timeout,
    ),
    ProviderProtocol.anthropic => AnthropicModel(
      config: config,
      apiKey: apiKey,
      client: client,
      timeout: timeout,
    ),
  };

  final ProviderConfig config;

  /// Request headers, including the credential. Never exposed or printed.
  final Map<String, String> _headers;
  final HttpTransport _transport;

  /// Bounds the model listing used by [availability].
  static const availabilityTimeout = Duration(seconds: 10);

  @override
  String get id => config.id;

  @override
  String get displayName => config.name;

  @override
  bool get isOnDevice => false;

  /// Path of the model listing, relative to [ProviderConfig.baseUrl].
  String get _modelsPath => '/models';

  /// Model identifiers the provider serves, sorted.
  Future<List<String>> listModels({Duration? timeout}) async {
    final json = await _transport.getJson(
      config.endpoint(_modelsPath),
      _headers,
      timeout: timeout,
    );
    final data = json is Map ? json['data'] : null;
    if (data is! List) {
      throw const SystemLlmException(SystemLlmException.invalidResponse);
    }
    return [
      for (final entry in data)
        if (entry is Map && entry['id'] is String) entry['id'] as String,
    ]..sort();
  }

  /// Checks the key and that the provider serves [ProviderConfig.model], by
  /// listing models. A server without a model listing counts as available.
  @override
  Future<AiAvailability> availability({String locale = 'en'}) async {
    if (config.model.trim().isEmpty) return AiAvailability.unsupported;
    try {
      final models = await listModels(timeout: availabilityTimeout);
      final model = config.model.trim();
      final served =
          models.isEmpty ||
          models.any((id) => id == model || id.endsWith('/$model'));
      return served ? AiAvailability.available : AiAvailability.unsupported;
    } on SystemLlmException catch (error) {
      return switch (error.code) {
        SystemLlmException.unauthorized => AiAvailability.unauthorized,
        SystemLlmException.modelNotFound ||
        SystemLlmException.invalidResponse => AiAvailability.available,
        _ => AiAvailability.unreachable,
      };
    }
  }

  @override
  Future<Map<String, Object?>> generateObject({
    required String instructions,
    required List<AiMessage> messages,
    required AiSchema schema,
    String locale = 'en',
    int maxTokens = 512,
  }) async {
    if (schema is! AiObjectSchema) {
      throw ArgumentError.value(
        schema,
        'schema',
        'The root must be an object.',
      );
    }
    _checkMessages(messages);
    // One retry, as on Android: models occasionally break the shape.
    for (var attempt = 0; attempt < 2; attempt++) {
      final value = await _requestObject(
        instructions: instructions,
        messages: messages,
        schema: schema,
        maxTokens: maxTokens,
      );
      if (value is Map && schema.matches(value)) {
        return Map<String, Object?>.from(value);
      }
    }
    throw const SystemLlmException(SystemLlmException.invalidResponse);
  }

  /// One structured request; the decoded object, or null when the answer is
  /// not JSON.
  Future<Object?> _requestObject({
    required String instructions,
    required List<AiMessage> messages,
    required AiObjectSchema schema,
    required int maxTokens,
  });

  @override
  Future<void> cancel() async => _transport.cancelAll();

  /// Stops running requests and releases the HTTP client if this model
  /// created it.
  void close() => _transport.close();

  @override
  String toString() => '$runtimeType(${config.id}, ${config.host})';
}

/// What one streamed event contributes: text to append, and whether the
/// answer is complete.
typedef _Step = ({String? text, bool done});

/// Maps provider events to text chunks. [read] throws [SystemLlmException]
/// for an error event. Built on a controller rather than `async*` so that
/// cancelling the subscription aborts the request at once.
Stream<String> _textStream(
  Stream<SseEvent> events,
  _Step Function(SseEvent event) read,
) {
  StreamSubscription<SseEvent>? subscription;
  late final StreamController<String> controller;

  void end() {
    unawaited(subscription?.cancel());
    if (!controller.isClosed) controller.close();
  }

  controller = StreamController<String>(
    onListen: () {
      subscription = events.listen(
        (event) {
          if (controller.isClosed) return;
          final _Step step;
          try {
            step = read(event);
          } on SystemLlmException catch (error) {
            controller.addError(error);
            end();
            return;
          }
          final text = step.text;
          if (text != null && text.isNotEmpty) controller.add(text);
          if (step.done) end();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (controller.isClosed) return;
          controller.addError(error, stackTrace);
          end();
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () => unawaited(subscription?.cancel()),
  );
  return controller.stream;
}

/// Decoded JSON of an event, or null when it is not JSON.
Object? _eventJson(SseEvent event) {
  try {
    return jsonDecode(event.data);
  } on FormatException {
    return null;
  }
}

void _checkMessages(List<AiMessage> messages) {
  if (messages.isEmpty) {
    throw ArgumentError.value(messages, 'messages', 'Must not be empty.');
  }
}

/// The value at [path] (map keys and list indexes) inside decoded JSON.
Object? _at(Object? json, List<Object> path) {
  var current = json;
  for (final key in path) {
    current = switch ((current, key)) {
      (final Map map, final String name) => map[name],
      (final List list, final int index) when index < list.length =>
        list[index],
      _ => null,
    };
    if (current == null) return null;
  }
  return current;
}

/// Decodes a JSON answer, tolerating a Markdown code fence around it.
Object? _decodeAnswer(Object? text) {
  if (text is! String) return null;
  var answer = text.trim();
  if (answer.startsWith('```')) {
    final firstLine = answer.indexOf('\n');
    if (firstLine < 0) return null;
    answer = answer.substring(firstLine + 1);
    if (answer.trimRight().endsWith('```')) {
      answer = answer.trimRight();
      answer = answer.substring(0, answer.length - 3);
    }
  }
  try {
    return jsonDecode(answer);
  } on FormatException {
    return null;
  }
}

/// Appended to the instructions when the schema travels in the prompt.
String _schemaInstruction(AiObjectSchema schema) =>
    'Answer with only a JSON object, no other text, that matches this JSON '
    'Schema:\n${jsonEncode(schema.toJsonSchema())}';
