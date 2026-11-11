# system_llm

Flutter bridge to the operating system's **built-in language model** and
**on-device speech recognition**, plus optional **third-party and local model
providers** (OpenAI, Claude, Gemini, Qwen, Ollama, LM Studio, any
OpenAI-compatible server) behind the same `LanguageModel` interface, so a chat
or any other feature runs unchanged on whichever model the user picks.

Two imports keep the privacy promise explicit:

| Import | What it can do |
|---|---|
| `package:system_llm/system_llm.dart` | On-device model, speech, storage helpers. Nothing leaves the device. |
| `package:system_llm/providers.dart` | Everything above, plus remote providers. Prompts go to the provider the user configured. |

| Capability | iOS | Android |
|---|---|---|
| Structured generation | Apple Foundation Models (iOS 26+, Apple Intelligence on) | ML Kit GenAI Prompt / AICore |
| Speech to text | `SFSpeechRecognizer`, on-device only | `SpeechRecognizer.createOnDeviceSpeechRecognizer` (API 31+) |
| App-private, backup-excluded folders | Application Support | `noBackupFilesDir` |

On other OS versions the calls report `unsupported` instead of throwing, so the
app can fall back to something else.

## Use

```dart
const ai = SystemLlm();

if ((await ai.availability('en')).canGenerate) {
  final answer = await ai.generateObject(
    instructions: 'Extract up to 5 short search phrases for the goal.',
    input: 'I want a vacation abroad',
    schema: const AiSchema.object({
      'queries': AiSchema.array(AiSchema.string(), maxItems: 5),
    }),
    locale: 'en',
  );
  print(answer['queries']);
}
```

`generateObject` always returns a map that matches the schema, or throws a
`SystemLlmException` whose `code` is one of the constants on that class
(`contextTooLong`, `unsupportedLanguage`, `invalidResponse`, `timeout`, ...).
Every call starts a fresh model session: pass any conversation history in
`input`. Only one generation runs at a time (`busy`).

### Conversations on any model

`LanguageModel` is the interface features should depend on. `OnDeviceModel`
wraps `SystemLlm`; `RemoteLanguageModel` talks HTTP. All of them take the
conversation as `List<AiMessage>`, stream text deltas, return schema-checked
objects, and fail with the same `SystemLlmException` codes.

```dart
LanguageModel model = const OnDeviceModel();
final answer = StringBuffer();
await for (final chunk in model.streamText(
  instructions: 'Answer briefly.',
  messages: const [
    AiMessage.user('What is a visa?'),
    AiMessage.assistant('A permit to enter a country.'),
    AiMessage.user('Do I need one for a short trip?'),
  ],
)) {
  answer.write(chunk);
}
```

The system model keeps no session, so `OnDeviceModel` sends the newest turns
that fit its small context window as one transcript.

### Third-party and local providers

```dart
import 'package:system_llm/providers.dart';

// The user's choice, persisted by the app (the JSON never holds API keys).
var settings = const ModelSettings(useThirdParty: true)
    .withProvider(ProviderPresets.ollama.toConfig(id: 'home', model: 'qwen3:8b'));

// Keys live in secure storage: implement ApiKeyStore over the Keychain /
// Keystore (the example app uses flutter_secure_storage).
final resolver = ModelResolver(keyStore: myKeyStore);
final model = await resolver.resolve(settings); // OnDeviceModel when the toggle is off
```

`ModelResolver` never falls back silently: with the toggle off it returns the
on-device model; with it on, an incomplete selection throws
`SystemLlmException.notConfigured` rather than quietly using another model.

Built-in presets (`ProviderPresets.all`) carry the base URL, protocol, whether a
key is needed and a few suggested models. Model names change often, so offer
`RemoteLanguageModel.listModels()` as well.

| Preset | Protocol | Base URL |
|---|---|---|
| OpenAI | OpenAI-compatible | `https://api.openai.com/v1` |
| Anthropic (Claude) | Anthropic Messages | `https://api.anthropic.com/v1` |
| Google Gemini | OpenAI-compatible | `https://generativelanguage.googleapis.com/v1beta/openai` |
| Qwen (Alibaba Model Studio) | OpenAI-compatible | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` |
| OpenRouter, Groq, DeepSeek, Mistral | OpenAI-compatible | see `ProviderPresets` |
| Ollama (local) | OpenAI-compatible | `http://localhost:11434/v1` |
| LM Studio (local) | OpenAI-compatible | `http://localhost:1234/v1` |

Any other server that speaks `POST /chat/completions` works as a custom
`ProviderConfig`. Notes:

* **Security.** `ProviderConfig.validate()` refuses plain `http://` to public
  hosts; it is only accepted for loopback and private-network addresses.
  Provider error text is never forwarded, only the stable `code`.
* **Structured output.** OpenAI-compatible providers use `json_schema`,
  `json_object` or the schema in the prompt (per preset); Anthropic uses JSON
  outputs (`output_config.format`). Every answer is validated against the
  schema, with one retry.
* **Claude** models think before answering: give `maxTokens` a few thousand.
* **`locale`** is ignored by remote providers; ask for a language in the
  instructions.
* **Ollama** from a device: the Android emulator reaches the host at
  `http://10.0.2.2:11434/v1`; a phone needs the computer's LAN address and
  Ollama started with `OLLAMA_HOST=0.0.0.0`.

### Streaming

`streamText` returns free text as it is produced. Each event is new text to
append, not the text so far. Cancel the subscription (or call `cancel()`) to
stop the model. Errors arrive as `SystemLlmException`s on the stream, and the
stream fails with `timeout` if the model stays silent for the configured
duration.

```dart
final answer = StringBuffer();
await for (final chunk in ai.streamText(
  instructions: 'Answer in one short paragraph.',
  input: 'What documents does a tourist visa usually need?',
)) {
  answer.write(chunk);
}
```

There is no schema on this path. Use `generateObject` when you need data.

Keep prompts short. The system models have small context windows (about 4,000
tokens), so retrieve a shortlist first and send only that.

## Host app setup

**Remote providers** (only if you import `providers.dart`): Android release
builds need `<uses-permission android:name="android.permission.INTERNET" />`.
To reach a local server over plain HTTP, Android needs a network security
config that allows cleartext for that host, and iOS needs
`NSAppTransportSecurity` → `NSAllowsLocalNetworking` (plus
`NSLocalNetworkUsageDescription` for LAN addresses). The example app shows
both.

**iOS** (`ios/Runner/Info.plist`), only if you call `listen`:

```xml
<key>NSMicrophoneUsageDescription</key><string>...</string>
<key>NSSpeechRecognitionUsageDescription</key><string>...</string>
```

Deployment target 15.0 or later. Foundation Models is weak-linked, so the app
still runs on older iOS versions and reports `unsupported`.

**Android**: `minSdk` 26 or later. The plugin's manifest adds `RECORD_AUDIO`;
the user is asked the first time `listen` runs. Structured output is asked for
in the prompt and validated, with one retry, because ML Kit's typed generation
needs a compile-time class.

## Errors

Provider error text is never forwarded, only the stable `code`, because it can
contain private input.

## Example app

`example/` has three tabs: **Chat** (runs on whichever model is selected and
always says where messages go), **Models** (the third-party toggle, presets,
custom endpoints, API keys in secure storage, model listing and a connection
test) and **Console** (one button per native capability). Run it on a real
device to check the native side; the Dart tests use mocks.

```bash
cd example && flutter run
```
