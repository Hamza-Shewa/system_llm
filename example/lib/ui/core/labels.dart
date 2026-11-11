import 'package:flutter/material.dart';
import 'package:system_llm/providers.dart';

/// Short status text for a model's availability.
String availabilityLabel(AiAvailability availability) => switch (availability) {
  AiAvailability.available => 'Ready',
  AiAvailability.modelNotReady => 'Model still downloading',
  AiAvailability.disabled => 'Turned off in system settings',
  AiAvailability.unsupportedLanguage => 'Language not supported',
  AiAvailability.unsupported => 'Model not available',
  AiAvailability.unreachable => 'Server unreachable',
  AiAvailability.unauthorized => 'API key rejected',
};

IconData availabilityIcon(AiAvailability availability) =>
    switch (availability) {
      AiAvailability.available => Icons.check_circle_outline,
      AiAvailability.modelNotReady => Icons.downloading,
      AiAvailability.unreachable => Icons.cloud_off_outlined,
      AiAvailability.unauthorized => Icons.key_off_outlined,
      _ => Icons.error_outline,
    };

/// A sentence explaining a [SystemLlmException] code to the user.
String errorMessage(String code) => switch (code) {
  SystemLlmException.busy => 'The model is busy with another request.',
  SystemLlmException.cancelled => 'Stopped.',
  SystemLlmException.contextTooLong =>
    'The conversation is too long for this model. Clear the chat and try again.',
  SystemLlmException.unsupportedLanguage =>
    'The model does not support this language.',
  SystemLlmException.invalidResponse =>
    'The model answered in an unexpected format.',
  SystemLlmException.unsupported =>
    'The on-device model is not available on this device.',
  SystemLlmException.modelNotReady =>
    'The on-device model is still downloading.',
  SystemLlmException.disabled =>
    'The on-device model is turned off in system settings.',
  SystemLlmException.timeout => 'The model took too long to answer.',
  SystemLlmException.unauthorized =>
    'The provider rejected the API key. Check it under Models.',
  SystemLlmException.rateLimited =>
    'The provider is limiting requests. Wait a moment and try again.',
  SystemLlmException.network =>
    'Could not reach the provider. Check the connection and the address.',
  SystemLlmException.modelNotFound =>
    'The provider does not serve this model. Pick another under Models.',
  SystemLlmException.notConfigured =>
    'The selected provider is incomplete. Finish it under Models.',
  _ => 'The model could not answer.',
};

String configErrorLabel(ProviderConfigError error) => switch (error) {
  ProviderConfigError.nameMissing => 'Enter a name.',
  ProviderConfigError.baseUrlInvalid =>
    'Enter an address starting with https:// or http://.',
  ProviderConfigError.insecureBaseUrl =>
    'Use https:// for internet hosts. Plain http:// is only allowed on '
        'your own network.',
  ProviderConfigError.modelMissing => 'Enter or pick a model.',
};

String protocolLabel(ProviderProtocol protocol) => switch (protocol) {
  ProviderProtocol.openAiCompatible => 'OpenAI-compatible',
  ProviderProtocol.anthropic => 'Anthropic',
};

String structuredOutputLabel(StructuredOutputMode mode) => switch (mode) {
  StructuredOutputMode.jsonSchema => 'JSON schema',
  StructuredOutputMode.jsonObject => 'JSON object',
  StructuredOutputMode.prompt => 'Schema in prompt',
};
