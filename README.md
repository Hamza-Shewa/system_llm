# system_llm

Flutter bridge to the operating system's **built-in language model** and
**on-device speech recognition**. Nothing leaves the device.

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

`example/` has one button per capability. Run it on a real device to check the
native side; the Dart tests use mocks.

```bash
cd example && flutter run
```
