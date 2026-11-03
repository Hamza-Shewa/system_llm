import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_system_llm.dart';

/// Native operations. All errors surface as [PlatformException]; the public
/// [SystemLlm] class converts them to [SystemLlmException].
abstract class SystemLlmPlatform extends PlatformInterface {
  SystemLlmPlatform() : super(token: _token);

  static final Object _token = Object();
  static SystemLlmPlatform _instance = MethodChannelSystemLlm();

  static SystemLlmPlatform get instance => _instance;

  static set instance(SystemLlmPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// One of: available, model_not_ready, disabled, unsupported_language,
  /// unsupported.
  Future<String?> availability(String locale);

  /// Returns the model's answer as JSON text.
  Future<String?> generateObject({
    required String instructions,
    required String input,
    required String locale,
    required Map<String, Object?> schema,
    required int maxTokens,
  });

  /// Streams the model's free-text answer as incremental chunks (each chunk
  /// is new text to append, not the text so far). Cancelling the subscription
  /// cancels the generation. Errors surface as [PlatformException].
  Stream<String> streamText({
    required String instructions,
    required String input,
    required String locale,
    required int maxTokens,
  });

  Future<bool?> speechAvailable(String locale);

  Future<String?> listen(String locale);

  Future<void> stopListening();

  /// Cancels a running generation and any running speech request.
  Future<void> cancel();

  Future<Map<Object?, Object?>?> environment(List<String> directories);
}
