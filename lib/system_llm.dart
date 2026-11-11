/// Bridge to the operating system's built-in language model and on-device
/// speech recognition (Apple Foundation Models, Android AICore / ML Kit GenAI).
///
/// Nothing imported from here sends data off the device. Remote providers
/// that implement the same [LanguageModel] interface live in
/// `package:system_llm/providers.dart`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'src/ai_availability.dart';
import 'src/ai_exception.dart';
import 'src/ai_schema.dart';
import 'src/device_environment.dart';
import 'src/platform_interface.dart';

export 'src/ai_availability.dart';
export 'src/ai_exception.dart';
export 'src/ai_schema.dart';
export 'src/device_environment.dart';
export 'src/language_model.dart';
export 'src/on_device_model.dart';
export 'src/platform_interface.dart' show SystemLlmPlatform;

/// Entry point of the plugin.
///
/// Each generation creates a fresh model session: nothing is remembered
/// between calls, so callers pass any conversation context in [generateObject]'s
/// `input`.
class SystemLlm {
  /// [timeout] bounds each native call; on expiry the call is cancelled and
  /// [SystemLlmException.timeout] is thrown.
  const SystemLlm({this.timeout = const Duration(seconds: 90)});

  final Duration timeout;

  SystemLlmPlatform get _platform => SystemLlmPlatform.instance;

  /// Maps platform failures to [SystemLlmException]; other errors pass through.
  Object _convert(Object error) {
    if (error is MissingPluginException) {
      return const SystemLlmException(SystemLlmException.unsupported);
    }
    if (error is PlatformException) return SystemLlmException(error.code);
    return error;
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(
        timeout,
        onTimeout: () {
          unawaited(_platform.cancel().then((_) {}, onError: (_) {}));
          throw const SystemLlmException(SystemLlmException.timeout);
        },
      );
    } on MissingPluginException {
      throw const SystemLlmException(SystemLlmException.unsupported);
    } on PlatformException catch (error) {
      throw SystemLlmException(error.code);
    }
  }

  /// Whether the built-in model can answer in [locale] (for example `en`,
  /// `ar-SA`). Never throws: an absent plugin reports [AiAvailability.unsupported].
  Future<AiAvailability> availability(String locale) async {
    try {
      return AiAvailability.parse(
        await _guard(() => _platform.availability(locale)),
      );
    } on SystemLlmException {
      return AiAvailability.unsupported;
    }
  }

  /// Asks the model for one JSON object shaped like [schema], whose root must
  /// be [AiSchema.object].
  ///
  /// [instructions] are trusted prompt text; [input] is data. Throws
  /// [SystemLlmException] with [SystemLlmException.contextTooLong] when the
  /// prompt is too large, and [SystemLlmException.invalidResponse] when the
  /// answer does not match [schema].
  Future<Map<String, Object?>> generateObject({
    required String instructions,
    required String input,
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
    final text = await _guard(
      () => _platform.generateObject(
        instructions: instructions,
        input: input,
        locale: locale,
        schema: schema.toJson(),
        maxTokens: maxTokens,
      ),
    );
    if (text == null) {
      throw const SystemLlmException(SystemLlmException.invalidResponse);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const SystemLlmException(SystemLlmException.invalidResponse);
    }
    if (decoded is! Map || !schema.matches(decoded)) {
      throw const SystemLlmException(SystemLlmException.invalidResponse);
    }
    return Map<String, Object?>.from(decoded);
  }

  /// Streams a free-text answer from the model, chunk by chunk.
  ///
  /// Every event is new text to append (not the text so far). The stream ends
  /// when the answer is complete. Cancelling the subscription, or calling
  /// [cancel], stops the generation. Errors are [SystemLlmException]s with the
  /// same codes as [generateObject]; if the model produces nothing for
  /// [timeout], the stream fails with [SystemLlmException.timeout].
  ///
  /// There is no schema: use [generateObject] when you need structured data.
  Stream<String> streamText({
    required String instructions,
    required String input,
    String locale = 'en',
    int maxTokens = 512,
  }) => _platform
      .streamText(
        instructions: instructions,
        input: input,
        locale: locale,
        maxTokens: maxTokens,
      )
      .timeout(
        timeout,
        onTimeout: (sink) {
          sink.addError(const SystemLlmException(SystemLlmException.timeout));
          sink.close();
        },
      )
      .transform(
        StreamTransformer<String, String>.fromHandlers(
          handleError: (error, stackTrace, sink) =>
              sink.addError(_convert(error), stackTrace),
        ),
      );

  /// Whether on-device (offline) speech recognition works for [locale].
  /// Never throws.
  Future<bool> speechAvailable(String locale) async {
    try {
      return await _guard<bool?>(() => _platform.speechAvailable(locale)) ??
          false;
    } on SystemLlmException {
      return false;
    }
  }

  /// Listens to the microphone and returns the transcript (at most 1000
  /// characters) once speech ends, [stopListening] is called, or 45 seconds
  /// pass. The host app must declare the microphone and speech permissions.
  Future<String> listen(String locale) async =>
      await _guard<String?>(() => _platform.listen(locale)) ?? '';

  Future<void> stopListening() => _guard(_platform.stopListening);

  /// Cancels a running generation and any running speech request.
  Future<void> cancel() => _guard(_platform.cancel);

  /// Creates [directories] (names, not paths) in app-private storage that is
  /// excluded from backup, and reports device capacity.
  ///
  /// Never throws: an absent plugin returns [DeviceEnvironment.unsupported].
  Future<DeviceEnvironment> environment({
    List<String> directories = const [],
  }) async {
    try {
      return DeviceEnvironment.fromMap(
        await _guard(() => _platform.environment(directories)),
      );
    } on SystemLlmException {
      return DeviceEnvironment.unsupported;
    }
  }
}
