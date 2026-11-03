import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/system_llm.dart';
import 'package:system_llm/src/method_channel_system_llm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelSystemLlm();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'availability' => 'available',
            'generateObject' => '{"a":1}',
            'speechAvailable' => true,
            'environment' => {'supported': true},
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, null);
  });

  test('uses the system_llm channel', () {
    expect(platform.methodChannel.name, 'system_llm');
  });

  test('sends the documented arguments for every method', () async {
    await platform.availability('ar');
    await platform.generateObject(
      instructions: 'i',
      input: 'x',
      locale: 'ar',
      schema: const AiSchema.object({'a': AiSchema.integer()}).toJson(),
      maxTokens: 64,
    );
    await platform.speechAvailable('fr');
    await platform.listen('fr');
    await platform.stopListening();
    await platform.cancel();
    await platform.environment(['models']);

    expect(calls.map((c) => c.method), [
      'availability',
      'generateObject',
      'speechAvailable',
      'listen',
      'stopListening',
      'cancel',
      'environment',
    ]);
    expect(calls[0].arguments, {'locale': 'ar'});
    final generate = calls[1].arguments as Map;
    expect(generate['instructions'], 'i');
    expect(generate['input'], 'x');
    expect(generate['locale'], 'ar');
    expect(generate['maxTokens'], 64);
    expect((generate['schema'] as Map)['type'], 'object');
    expect(calls[2].arguments, {'locale': 'fr'});
    expect(calls[6].arguments, {
      'directories': ['models'],
    });
  });

  test('environment returns a typed map', () async {
    expect(await platform.environment([]), {'supported': true});
  });

  test('streamText listens on the stream channel with its arguments', () async {
    Object? listenArguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          platform.streamChannel,
          MockStreamHandler.inline(
            onListen: (arguments, sink) {
              listenArguments = arguments;
              sink.success('Hel');
              sink.success('lo');
              sink.endOfStream();
            },
          ),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(platform.streamChannel, null),
    );

    final chunks = await platform
        .streamText(instructions: 'i', input: 'x', locale: 'ar', maxTokens: 7)
        .toList();

    expect(platform.streamChannel.name, 'system_llm/stream');
    expect(chunks, ['Hel', 'lo']);
    final arguments = listenArguments! as Map;
    expect(arguments['instructions'], 'i');
    expect(arguments['input'], 'x');
    expect(arguments['locale'], 'ar');
    expect(arguments['maxTokens'], 7);
  });

  group('SystemLlm.streamText over the real event channel', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void mockNative(void Function(MockStreamHandlerEventSink sink) onListen) {
      messenger.setMockStreamHandler(
        platform.streamChannel,
        MockStreamHandler.inline(onListen: (_, sink) => onListen(sink)),
      );
      addTearDown(
        () => messenger.setMockStreamHandler(platform.streamChannel, null),
      );
    }

    setUp(() => SystemLlmPlatform.instance = platform);

    test('joins chunks until the native side ends the stream', () async {
      mockNative((sink) {
        sink.success('Hel');
        sink.success('lo');
        sink.endOfStream();
      });
      final text = await const SystemLlm()
          .streamText(instructions: 'i', input: 'x')
          .join();
      expect(text, 'Hello');
    });

    test('turns a native error code into SystemLlmException', () async {
      mockNative((sink) => sink.error(code: 'context_too_long'));
      await expectLater(
        const SystemLlm().streamText(instructions: 'i', input: 'x'),
        emitsError(
          isA<SystemLlmException>().having(
            (e) => e.code,
            'code',
            SystemLlmException.contextTooLong,
          ),
        ),
      );
    });
  });
}
