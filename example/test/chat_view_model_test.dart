import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/providers.dart';
import 'package:system_llm_example/data/settings_repository.dart';
import 'package:system_llm_example/ui/features/chat/view_models/chat_view_model.dart';
import 'package:system_llm_example/ui/features/models/view_models/models_view_model.dart';

import 'support/fakes.dart';

void main() {
  final ollama = ProviderPresets.ollama.toConfig(id: 'o');
  late InMemorySettingsRepository repository;
  late ModelsViewModel models;
  late FakeLanguageModel onDevice;
  late FakeLanguageModel remote;
  late ChatViewModel chat;

  setUp(() async {
    repository = InMemorySettingsRepository(
      const ModelSettings().withProvider(ollama),
    );
    onDevice = FakeLanguageModel(id: 'on-device');
    remote = FakeLanguageModel(id: 'o', isOnDevice: false);
    models = ModelsViewModel(
      repository: repository,
      keyStore: InMemoryApiKeyStore(),
      probe: FakeProbe(),
      onDevice: onDevice,
    );
    await models.load();
    chat = ChatViewModel(
      models: models,
      resolve: (settings) async => settings.useThirdParty ? remote : onDevice,
      instructions: 'Be brief.',
    );
  });

  test('streams an answer and keeps it in the history', () async {
    onDevice.onStream = (_) => Stream.fromIterable(['Hel', 'lo']);
    final partials = <String>[];
    chat.addListener(() => partials.add(chat.partial));
    await chat.send('  hi  ');
    await pumpEventQueue();
    expect(partials, containsAllInOrder(['Hel', 'Hello']));
    expect(chat.messages, const [
      AiMessage.user('hi'),
      AiMessage.assistant('Hello'),
    ]);
    expect(chat.streaming, isFalse);
    expect(onDevice.lastInstructions, 'Be brief.');
  });

  test('a model switch continues the same conversation', () async {
    onDevice.onStream = (_) => Stream.value('first');
    remote.onStream = (_) => Stream.value('second');
    await chat.send('one');
    await pumpEventQueue();
    await models.setUseThirdParty(true);
    await chat.send('two');
    await pumpEventQueue();
    expect(remote.streamRequests.single, const [
      AiMessage.user('one'),
      AiMessage.assistant('first'),
      AiMessage.user('two'),
    ]);
    expect(chat.messages.last, const AiMessage.assistant('second'));
  });

  test('an unusable selection is reported and can be retried', () async {
    var attempts = 0;
    chat = ChatViewModel(
      models: models,
      resolve: (_) async {
        attempts++;
        if (attempts == 1) {
          throw const SystemLlmException(SystemLlmException.notConfigured);
        }
        return onDevice;
      },
    );
    onDevice.onStream = (_) => Stream.value('ok');
    await chat.send('hi');
    expect(chat.errorCode, SystemLlmException.notConfigured);
    expect(chat.canRetry, isTrue);
    expect(chat.messages, const [AiMessage.user('hi')]);

    await chat.retry();
    await pumpEventQueue();
    expect(chat.errorCode, isNull);
    expect(chat.messages, const [
      AiMessage.user('hi'),
      AiMessage.assistant('ok'),
    ]);
  });

  test('an error mid-stream keeps the text received so far', () async {
    onDevice.onStream = (_) async* {
      yield 'part';
      throw const SystemLlmException(SystemLlmException.timeout);
    };
    await chat.send('hi');
    await pumpEventQueue();
    expect(chat.errorCode, SystemLlmException.timeout);
    expect(chat.messages.last, const AiMessage.assistant('part'));
    expect(chat.canRetry, isFalse);
  });

  test('stop keeps the partial answer and cancels the model', () async {
    final controller = StreamController<String>();
    onDevice.onStream = (_) => controller.stream;
    await chat.send('hi');
    controller.add('half');
    await pumpEventQueue();
    expect(chat.streaming, isTrue);
    await chat.stop();
    expect(chat.streaming, isFalse);
    expect(chat.errorCode, isNull);
    expect(chat.messages.last, const AiMessage.assistant('half'));
    expect(onDevice.cancelCalls, 1);
    expect(controller.hasListener, isFalse);
    await controller.close();
  });

  test('ignores blank input and sends while streaming', () async {
    final controller = StreamController<String>();
    addTearDown(controller.close);
    onDevice.onStream = (_) => controller.stream;
    await chat.send('   ');
    expect(chat.messages, isEmpty);
    await chat.send('one');
    await chat.send('two');
    expect(chat.messages, const [AiMessage.user('one')]);
  });

  test('clear empties the conversation', () async {
    onDevice.onStream = (_) => Stream.value('x');
    await chat.send('hi');
    await pumpEventQueue();
    await chat.clear();
    expect(chat.messages, isEmpty);
    expect(chat.errorCode, isNull);
  });
}
