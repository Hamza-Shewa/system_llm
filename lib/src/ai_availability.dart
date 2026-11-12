/// Whether a language model can answer now.
enum AiAvailability {
  /// The model is installed, enabled and supports the requested language.
  available,

  /// The model exists but is still downloading or preparing.
  modelNotReady,

  /// The model is supported but switched off by the user (for example Apple
  /// Intelligence is disabled in Settings).
  disabled,

  /// The model works, but not for the requested locale.
  unsupportedLanguage,

  /// This device, OS version or platform has no built-in model, or a remote
  /// provider does not serve the configured model.
  unsupported,

  /// A remote provider could not be reached (offline, wrong URL, server down).
  unreachable,

  /// A remote provider rejected the API key.
  unauthorized;

  /// Whether a generation can be expected to succeed.
  bool get canGenerate => this == available;

  /// Parses the status string sent by the native side.
  static AiAvailability parse(String? status) => switch (status) {
    'available' => available,
    'model_not_ready' => modelNotReady,
    'disabled' => disabled,
    'unsupported_language' => unsupportedLanguage,
    _ => unsupported,
  };
}
