/// Thrown when a native call fails.
///
/// [code] is a stable, machine readable value. Provider error text is never
/// forwarded because it may contain private user input.
class SystemLlmException implements Exception {
  const SystemLlmException(this.code);

  /// Another generation or speech request is already running.
  static const busy = 'busy';

  /// The request was cancelled by [SystemLlm.cancel] or by the platform.
  static const cancelled = 'cancelled';

  /// The prompt did not fit the model's context window.
  static const contextTooLong = 'context_too_long';

  /// The model does not support the requested locale.
  static const unsupportedLanguage = 'unsupported_language';

  /// The model failed while generating.
  static const generationFailed = 'generation_failed';

  /// The model answered, but not in the requested shape.
  static const invalidResponse = 'invalid_response';

  /// There is no model, or no plugin implementation, on this platform.
  static const unsupported = 'unsupported';

  /// The user denied a microphone or speech permission.
  static const permissionDenied = 'permission_denied';

  /// Speech recognition heard nothing.
  static const noSpeech = 'no_speech';

  /// On-device speech recognition is unavailable.
  static const speechUnavailable = 'speech_unavailable';

  /// The model is still downloading or preparing.
  static const modelNotReady = 'model_not_ready';

  /// The model is switched off in the device settings.
  static const disabled = 'disabled';

  /// The native call took longer than the configured timeout.
  static const timeout = 'timeout';

  /// A required directory could not be created.
  static const storageError = 'storage_error';

  final String code;

  @override
  String toString() => 'SystemLlmException($code)';
}
