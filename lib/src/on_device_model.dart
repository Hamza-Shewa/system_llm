import 'ai_availability.dart';
import 'ai_schema.dart';
import 'language_model.dart';
import '../system_llm.dart' show SystemLlm;

/// The operating system's built-in model behind the [LanguageModel] interface.
///
/// The system model keeps no session, so the conversation is sent as one
/// transcript. Only the newest turns that fit in [maxInputChars] are sent
/// (the latest message always is), because the system models have small
/// context windows (about 4,000 tokens).
class OnDeviceModel implements LanguageModel {
  const OnDeviceModel({
    this.llm = const SystemLlm(),
    this.maxInputChars = 6000,
  });

  /// The bridge to the system model; its timeout applies to every call.
  final SystemLlm llm;

  /// Character budget for the transcript sent as input.
  final int maxInputChars;

  @override
  String get id => 'on-device';

  @override
  String get displayName => 'On-device model';

  @override
  bool get isOnDevice => true;

  @override
  Future<AiAvailability> availability({String locale = 'en'}) =>
      llm.availability(locale);

  @override
  Future<Map<String, Object?>> generateObject({
    required String instructions,
    required List<AiMessage> messages,
    required AiSchema schema,
    String locale = 'en',
    int maxTokens = 512,
  }) => llm.generateObject(
    instructions: instructions,
    input: transcript(messages),
    schema: schema,
    locale: locale,
    maxTokens: maxTokens,
  );

  @override
  Stream<String> streamText({
    required String instructions,
    required List<AiMessage> messages,
    String locale = 'en',
    int maxTokens = 512,
  }) => llm.streamText(
    instructions: instructions,
    input: transcript(messages),
    locale: locale,
    maxTokens: maxTokens,
  );

  @override
  Future<void> cancel() => llm.cancel();

  /// The input sent to the system model: the text itself for a single user
  /// message, otherwise a `User:` / `Assistant:` transcript of the newest
  /// turns that fit in [maxInputChars].
  String transcript(List<AiMessage> messages) {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'Must not be empty.');
    }
    if (messages.length == 1 && messages.single.role == AiRole.user) {
      return messages.single.text;
    }
    final kept = <String>[];
    var length = 0;
    for (final message in messages.reversed) {
      final line = switch (message.role) {
        AiRole.user => 'User: ${message.text}',
        AiRole.assistant => 'Assistant: ${message.text}',
      };
      final added = line.length + (kept.isEmpty ? 0 : 2);
      if (kept.isNotEmpty && length + added > maxInputChars) break;
      kept.add(line);
      length += added;
    }
    return kept.reversed.join('\n\n');
  }
}
