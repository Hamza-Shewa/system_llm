import 'ai_availability.dart';
import 'ai_exception.dart';
import 'ai_schema.dart';

/// Who wrote a message in a conversation.
enum AiRole { user, assistant }

/// One turn of a conversation sent to a [LanguageModel].
final class AiMessage {
  const AiMessage(this.role, this.text);

  const AiMessage.user(this.text) : role = AiRole.user;

  const AiMessage.assistant(this.text) : role = AiRole.assistant;

  final AiRole role;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is AiMessage && other.role == role && other.text == text;

  @override
  int get hashCode => Object.hash(role, text);

  @override
  String toString() => 'AiMessage(${role.name}, ${text.length} chars)';
}

/// A model that features (a chat, an extractor, ...) run on, so the model
/// behind them can be swapped: the operating system's built-in model, a local
/// server such as Ollama, or a cloud provider.
///
/// Every implementation keeps the same contract:
/// * failures are [SystemLlmException]s with a stable `code`; provider error
///   text is never forwarded because it can contain private input;
/// * [streamText] events are new text to append, not the text so far;
/// * [generateObject] returns a map that matches the schema, or throws
///   [SystemLlmException.invalidResponse].
abstract interface class LanguageModel {
  /// Stable identifier, for example `on-device` or a provider config id.
  String get id;

  /// Name to show to the user.
  String get displayName;

  /// Whether prompts stay on this device.
  bool get isOnDevice;

  /// Whether the model can answer in [locale] now. Never throws.
  Future<AiAvailability> availability({String locale = 'en'});

  /// Asks for one JSON object shaped like [schema], whose root must be
  /// [AiSchema.object] (otherwise throws [ArgumentError]).
  ///
  /// [instructions] are trusted prompt text; [messages] are the conversation,
  /// oldest first, and must not be empty.
  Future<Map<String, Object?>> generateObject({
    required String instructions,
    required List<AiMessage> messages,
    required AiSchema schema,
    String locale = 'en',
    int maxTokens = 512,
  });

  /// Streams a free-text answer to [messages], chunk by chunk. Cancelling the
  /// subscription, or calling [cancel], stops the generation.
  Stream<String> streamText({
    required String instructions,
    required List<AiMessage> messages,
    String locale = 'en',
    int maxTokens = 512,
  });

  /// Stops any running generation of this model.
  Future<void> cancel();
}
