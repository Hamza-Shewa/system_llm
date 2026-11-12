import 'dart:async';

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

  group('overlapping streams', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    late int listens;
    late int cancels;

    // A native side that, unlike MockStreamHandler, can serve several streams.
    void native(ByteData? envelope) => messenger.handlePlatformMessage(
      platform.streamChannel.name,
      envelope,
      null,
    );
    void send(String text) => native(codec.encodeSuccessEnvelope(text));
    void fail(String code) => native(codec.encodeErrorEnvelope(code: code));
    void end() => native(null);

    final busy = isA<SystemLlmException>().having(
      (e) => e.code,
      'code',
      SystemLlmException.busy,
    );

    Stream<String> stream({Duration timeout = const Duration(seconds: 5)}) =>
        SystemLlm(timeout: timeout).streamText(instructions: 'i', input: 'x');

    setUp(() {
      SystemLlmPlatform.instance = platform;
      listens = 0;
      cancels = 0;
      messenger.setMockMethodCallHandler(
        MethodChannel(platform.streamChannel.name),
        (call) async {
          if (call.method == 'listen') listens++;
          if (call.method == 'cancel') cancels++;
          return null;
        },
      );
    });

    tearDown(
      () => messenger.setMockMethodCallHandler(
        MethodChannel(platform.streamChannel.name),
        null,
      ),
    );

    test(
      'a second listen fails with busy and leaves the first running',
      () async {
        final first = <String>[];
        final firstDone = Completer<void>();
        stream().listen(first.add, onDone: firstDone.complete);
        await pumpEventQueue();

        await expectLater(stream(), emitsError(busy));
        expect(listens, 1);
        expect(cancels, 0);

        send('Hel');
        send('lo');
        end();
        await firstDone.future;
        expect(first, ['Hel', 'lo']);
      },
    );

    test('checks when listened to, not when created', () async {
      final later = stream();
      final running = stream().listen(null);
      await pumpEventQueue();
      await expectLater(later, emitsError(busy));
      expect(listens, 1);
      await running.cancel();
    });

    Future<void> startsAgain() async {
      final second = stream().toList();
      await pumpEventQueue();
      expect(listens, 2);
      send('ok');
      end();
      expect(await second, ['ok']);
    }

    test('a new stream can start after the first ends', () async {
      final first = stream().join();
      await pumpEventQueue();
      end();
      await first;
      await startsAgain();
    });

    test('a new stream can start after the first fails', () async {
      final first = expectLater(
        stream(),
        emitsError(
          isA<SystemLlmException>().having(
            (e) => e.code,
            'code',
            SystemLlmException.generationFailed,
          ),
        ),
      );
      await pumpEventQueue();
      fail('generation_failed');
      end();
      await first;
      await startsAgain();
    });

    test('a new stream can start after the first is cancelled', () async {
      final first = stream().listen(null);
      await pumpEventQueue();
      await first.cancel();
      expect(cancels, 1);
      await startsAgain();
    });

    test('a new stream can start after the first times out', () async {
      await expectLater(
        stream(timeout: const Duration(milliseconds: 10)),
        emitsError(
          isA<SystemLlmException>().having(
            (e) => e.code,
            'code',
            SystemLlmException.timeout,
          ),
        ),
      );
      await pumpEventQueue();
      expect(cancels, 1);
      await startsAgain();
    });

    test('a rejected stream does not release the running one', () async {
      final first = stream().listen(null);
      await pumpEventQueue();
      await expectLater(stream(), emitsError(busy));
      await expectLater(stream(), emitsError(busy));
      expect(listens, 1);
      await first.cancel();
    });
  });
}
