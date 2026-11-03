import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/system_llm.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePlatform extends SystemLlmPlatform with MockPlatformInterfaceMixin {
  Future<String?> Function(String locale) onAvailability = (_) async =>
      'available';
  Future<String?> Function() onGenerate = () async => '{"queries":["a"]}';
  Future<bool?> Function() onSpeechAvailable = () async => true;
  Future<Map<Object?, Object?>?> Function(List<String>) onEnvironment =
      (_) async => null;
  Stream<String> Function() onStream = () => const Stream.empty();
  int cancelCalls = 0;
  Map<String, Object?>? lastSchema;
  int? lastMaxTokens;

  @override
  Future<String?> availability(String locale) => onAvailability(locale);

  @override
  Future<String?> generateObject({
    required String instructions,
    required String input,
    required String locale,
    required Map<String, Object?> schema,
    required int maxTokens,
  }) {
    lastSchema = schema;
    lastMaxTokens = maxTokens;
    return onGenerate();
  }

  @override
  Stream<String> streamText({
    required String instructions,
    required String input,
    required String locale,
    required int maxTokens,
  }) {
    lastMaxTokens = maxTokens;
    return onStream();
  }

  @override
  Future<bool?> speechAvailable(String locale) => onSpeechAvailable();

  @override
  Future<String?> listen(String locale) async => 'hello';

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<Map<Object?, Object?>?> environment(List<String> directories) =>
      onEnvironment(directories);
}

void main() {
  const schema = AiSchema.object({
    'queries': AiSchema.array(AiSchema.string(), maxItems: 12),
  });
  late FakePlatform platform;
  late SystemLlm ai;

  setUp(() {
    platform = FakePlatform();
    SystemLlmPlatform.instance = platform;
    ai = const SystemLlm(timeout: Duration(milliseconds: 200));
  });

  Future<SystemLlmException> failure(Future<Object?> call) async {
    try {
      await call;
    } on SystemLlmException catch (error) {
      return error;
    }
    throw StateError('expected SystemLlmException');
  }

  group('availability', () {
    test('maps every native status', () async {
      const expected = {
        'available': AiAvailability.available,
        'model_not_ready': AiAvailability.modelNotReady,
        'disabled': AiAvailability.disabled,
        'unsupported_language': AiAvailability.unsupportedLanguage,
        'unsupported': AiAvailability.unsupported,
        'something_new': AiAvailability.unsupported,
      };
      for (final entry in expected.entries) {
        platform.onAvailability = (_) async => entry.key;
        expect(await ai.availability('en'), entry.value, reason: entry.key);
      }
    });

    test('only available can generate', () {
      expect(AiAvailability.available.canGenerate, isTrue);
      expect(AiAvailability.modelNotReady.canGenerate, isFalse);
    });

    test('reports unsupported when the plugin is missing', () async {
      platform.onAvailability = (_) => throw MissingPluginException();
      expect(await ai.availability('en'), AiAvailability.unsupported);
    });

    test('reports unsupported on a platform error', () async {
      platform.onAvailability = (_) => throw PlatformException(code: 'x');
      expect(await ai.availability('en'), AiAvailability.unsupported);
    });
  });

  group('generateObject', () {
    Future<Map<String, Object?>> run() => ai.generateObject(
      instructions: 'i',
      input: 'in',
      schema: schema,
      maxTokens: 99,
    );

    test('decodes the answer and sends schema and token limit', () async {
      final result = await run();
      expect(result, {
        'queries': ['a'],
      });
      expect(platform.lastSchema, schema.toJson());
      expect(platform.lastMaxTokens, 99);
    });

    test('rejects an answer that does not match the schema', () async {
      platform.onGenerate = () async => '{"queries":"a"}';
      expect((await failure(run())).code, SystemLlmException.invalidResponse);
    });

    test('rejects malformed JSON and null', () async {
      platform.onGenerate = () async => 'not json';
      expect((await failure(run())).code, SystemLlmException.invalidResponse);
      platform.onGenerate = () async => null;
      expect((await failure(run())).code, SystemLlmException.invalidResponse);
    });

    test('forwards the native error code', () async {
      platform.onGenerate = () =>
          throw PlatformException(code: 'context_too_long');
      expect((await failure(run())).code, SystemLlmException.contextTooLong);
    });

    test('reports unsupported when the plugin is missing', () async {
      platform.onGenerate = () => throw MissingPluginException();
      expect((await failure(run())).code, SystemLlmException.unsupported);
    });

    test('times out, cancels natively and reports timeout', () async {
      final never = Completer<String?>();
      platform.onGenerate = () => never.future;
      expect((await failure(run())).code, SystemLlmException.timeout);
      await Future<void>.delayed(Duration.zero);
      expect(platform.cancelCalls, 1);
    });

    test('requires an object root', () {
      expect(
        () => ai.generateObject(
          instructions: 'i',
          input: 'in',
          schema: const AiSchema.string(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('streamText', () {
    Stream<String> stream() =>
        ai.streamText(instructions: 'i', input: 'in', maxTokens: 42);

    test('forwards chunks in order and completes', () async {
      platform.onStream = () => Stream.fromIterable(['Hel', 'lo', '!']);
      expect(await stream().toList(), ['Hel', 'lo', '!']);
      expect(platform.lastMaxTokens, 42);
    });

    test('maps native error codes to SystemLlmException', () async {
      platform.onStream = () async* {
        yield 'partial';
        throw PlatformException(code: 'context_too_long');
      };
      await expectLater(
        stream(),
        emitsInOrder([
          'partial',
          emitsError(
            isA<SystemLlmException>().having(
              (e) => e.code,
              'code',
              SystemLlmException.contextTooLong,
            ),
          ),
        ]),
      );
    });

    test('reports unsupported when the plugin is missing', () async {
      platform.onStream = () => Stream.error(MissingPluginException());
      await expectLater(
        stream(),
        emitsError(
          isA<SystemLlmException>().having(
            (e) => e.code,
            'code',
            SystemLlmException.unsupported,
          ),
        ),
      );
    });

    test('fails with timeout when the model goes silent', () async {
      final controller = StreamController<String>();
      platform.onStream = () => controller.stream;
      addTearDown(controller.close);
      await expectLater(
        stream(),
        emitsInOrder([
          emitsError(
            isA<SystemLlmException>().having(
              (e) => e.code,
              'code',
              SystemLlmException.timeout,
            ),
          ),
          emitsDone,
        ]),
      );
    });

    test('cancelling the subscription cancels the native stream', () async {
      var cancelled = false;
      final controller = StreamController<String>(
        onCancel: () => cancelled = true,
      );
      platform.onStream = () => controller.stream;
      final subscription = stream().listen((_) {});
      controller.add('x');
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(cancelled, isTrue);
    });
  });

  group('speech and environment', () {
    test('speechAvailable never throws', () async {
      expect(await ai.speechAvailable('en'), isTrue);
      platform.onSpeechAvailable = () => throw MissingPluginException();
      expect(await ai.speechAvailable('en'), isFalse);
    });

    test('listen returns the transcript', () async {
      expect(await ai.listen('en'), 'hello');
    });

    test('environment parses the native map', () async {
      platform.onEnvironment = (names) async => {
        'supported': true,
        'directories': {for (final n in names) n: '/data/$n'},
        'freeBytes': 5,
        'memoryBytes': 7,
      };
      final env = await ai.environment(directories: ['models']);
      expect(env.supported, isTrue);
      expect(env.directories, {'models': '/data/models'});
      expect(env.freeBytes, 5);
      expect(env.memoryBytes, 7);
    });

    test('environment is unsupported when the plugin is missing', () async {
      platform.onEnvironment = (_) => throw MissingPluginException();
      final env = await ai.environment();
      expect(env.supported, isFalse);
      expect(env.directories, isEmpty);
    });
  });
}
