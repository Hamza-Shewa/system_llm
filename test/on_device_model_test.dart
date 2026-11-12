import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/system_llm.dart';

import 'support/fake_platform.dart';

void main() {
  const schema = AiSchema.object({
    'queries': AiSchema.array(AiSchema.string()),
  });
  late FakePlatform platform;

  setUp(() {
    platform = FakePlatform();
    SystemLlmPlatform.instance = platform;
  });

  test('describes itself as the on-device model', () {
    const model = OnDeviceModel();
    expect(model.id, 'on-device');
    expect(model.isOnDevice, isTrue);
  });

  group('transcript', () {
    test('sends a single user message unchanged', () {
      expect(
        const OnDeviceModel().transcript([const AiMessage.user('hello')]),
        'hello',
      );
    });

    test('labels every turn of a conversation, oldest first', () {
      expect(
        const OnDeviceModel().transcript(const [
          AiMessage.user('hi'),
          AiMessage.assistant('hello'),
          AiMessage.user('bye'),
        ]),
        'User: hi\n\nAssistant: hello\n\nUser: bye',
      );
    });

    test('drops the oldest turns that do not fit the budget', () {
      const model = OnDeviceModel(maxInputChars: 40);
      expect(
        model.transcript(const [
          AiMessage.user('first question here'),
          AiMessage.assistant('answer'),
          AiMessage.user('second'),
        ]),
        'Assistant: answer\n\nUser: second',
      );
    });

    test('always keeps the latest message, even over budget', () {
      const model = OnDeviceModel(maxInputChars: 5);
      expect(
        model.transcript(const [
          AiMessage.assistant('a'),
          AiMessage.user('a long last message'),
        ]),
        'User: a long last message',
      );
    });

    test('rejects an empty conversation', () {
      expect(() => const OnDeviceModel().transcript([]), throwsArgumentError);
    });
  });

  test('generateObject forwards the transcript and options', () async {
    platform.onGenerate = () async => '{"queries":["x"]}';
    final result = await const OnDeviceModel().generateObject(
      instructions: 'extract',
      messages: const [AiMessage.user('a'), AiMessage.assistant('b')],
      schema: schema,
      locale: 'ar',
      maxTokens: 77,
    );
    expect(result, {
      'queries': ['x'],
    });
    expect(platform.lastInstructions, 'extract');
    expect(platform.lastInput, 'User: a\n\nAssistant: b');
    expect(platform.lastLocale, 'ar');
    expect(platform.lastMaxTokens, 77);
  });

  test('streamText forwards chunks from the system model', () async {
    platform.onStream = () => Stream.fromIterable(['a', 'b']);
    final chunks = await const OnDeviceModel()
        .streamText(instructions: 'i', messages: const [AiMessage.user('q')])
        .toList();
    expect(chunks, ['a', 'b']);
    expect(platform.lastInput, 'q');
  });

  test('availability and cancel reach the platform', () async {
    platform.onAvailability = (_) async => 'model_not_ready';
    const model = OnDeviceModel();
    expect(
      await model.availability(locale: 'en'),
      AiAvailability.modelNotReady,
    );
    await model.cancel();
    expect(platform.cancelCalls, 1);
  });
}
