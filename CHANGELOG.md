## 0.2.0

* **`LanguageModel` interface** so features run on any model:
  `OnDeviceModel` wraps the system model and sends a conversation
  (`List<AiMessage>`) as a transcript that fits its context window.
* **Third-party and local providers** in the new
  `package:system_llm/providers.dart`: `OpenAiCompatibleModel` (OpenAI, Ollama,
  LM Studio, Gemini, Qwen, OpenRouter, Groq, DeepSeek, Mistral, any
  `/chat/completions` server) and `AnthropicModel` (Claude), with streaming,
  cancel, timeouts and schema-validated structured output.
* `ProviderPresets`, `ProviderConfig` (refuses plain HTTP to public hosts),
  `ModelSettings`, `ApiKeyStore` and `ModelResolver` (no silent fallback).
* `AiSchema.toJsonSchema()` for standard JSON Schema.
* New exception codes: `unauthorized`, `rate_limited`, `network`,
  `model_not_found`, `not_configured`.
* **Breaking:** `AiAvailability` gains `unreachable` and `unauthorized`;
  exhaustive `switch`es over it need the two new cases.
* Adds the `http` dependency. Code that imports only `system_llm.dart` sends
  nothing off the device.
* Example app: Chat, Models and Console tabs.

## 0.1.1

* License the package under MIT. 0.1.0 shipped without an open-source license.
* Declare Flutter 3.44.2 as the minimum, matching the Dart SDK the package
  already required. The example app now declares the same SDK range.

## 0.1.0

* Initial version: availability check, schema-constrained structured generation
  with the system language model, streamed free-text generation (`streamText`),
  on-device speech recognition, and a small device-environment helper.
