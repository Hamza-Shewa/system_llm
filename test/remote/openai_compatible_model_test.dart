import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:system_llm/providers.dart';

import '../support/http_fakes.dart';

void main() {
  const schema = AiSchema.object({'tags': AiSchema.array(AiSchema.string())});
  const config = ProviderConfig(
    id: 'p1',
    name: 'Test',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'https://api.example.com/v1/',
    model: 'small-model',
  );
  const messages = [AiMessage.user('hi'), AiMessage.assistant('hello')];

  Map<String, Object?> completion(Object? content) => {
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content},
      },
    ],
  };

  OpenAiCompatibleModel model(
    http.Client client, {
    ProviderConfig config = config,
    String? apiKey = 'sk-test',
    Duration timeout = const Duration(seconds: 5),
  }) => OpenAiCompatibleModel(
    config: config,
    apiKey: apiKey,
    client: client,
    timeout: timeout,
  );

  Future<SystemLlmException> failure(Future<Object?> call) async {
    try {
      await call;
    } on SystemLlmException catch (error) {
      return error;
    }
    throw StateError('expected SystemLlmException');
  }

  Future<Map<String, Object?>> generate(LanguageModel m) => m.generateObject(
    instructions: 'Tag it.',
    messages: messages,
    schema: schema,
    maxTokens: 64,
  );

  group('generateObject', () {
    test('sends the conversation, model, limit and JSON schema', () async {
      final client = respond((_) => jsonResponse(completion('{"tags":["a"]}')));
      expect(await generate(model(client)), {
        'tags': ['a'],
      });
      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(request.headers['authorization'], 'Bearer sk-test');
      expect(request.json, {
        'model': 'small-model',
        'messages': [
          {'role': 'system', 'content': 'Tag it.'},
          {'role': 'user', 'content': 'hi'},
          {'role': 'assistant', 'content': 'hello'},
        ],
        'max_tokens': 64,
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'response',
            'strict': true,
            'schema': schema.toJsonSchema(),
          },
        },
      });
    });

    test('sends no authorization header without a key', () async {
      final client = respond((_) => jsonResponse(completion('{"tags":[]}')));
      await generate(model(client, apiKey: '  '));
      expect(
        client.requests.single.headers.containsKey('authorization'),
        isFalse,
      );
    });

    test('uses max_completion_tokens when configured', () async {
      final client = respond((_) => jsonResponse(completion('{"tags":[]}')));
      await generate(
        model(
          client,
          config: config.copyWith(
            maxTokensField: MaxTokensField.maxCompletionTokens,
          ),
        ),
      );
      final body = client.requests.single.json;
      expect(body['max_completion_tokens'], 64);
      expect(body.containsKey('max_tokens'), isFalse);
    });

    test('json_object mode puts the schema in the system prompt', () async {
      final client = respond((_) => jsonResponse(completion('{"tags":[]}')));
      await generate(
        model(
          client,
          config: config.copyWith(
            structuredOutput: StructuredOutputMode.jsonObject,
          ),
        ),
      );
      final body = client.requests.single.json;
      expect(body['response_format'], {'type': 'json_object'});
      final system = ((body['messages']! as List).first as Map)['content'];
      expect(system, startsWith('Tag it.\n\n'));
      expect(system, contains('"required":["tags"]'));
    });

    test('prompt mode sends no response_format', () async {
      final client = respond((_) => jsonResponse(completion('{"tags":[]}')));
      await generate(
        model(
          client,
          config: config.copyWith(
            structuredOutput: StructuredOutputMode.prompt,
          ),
        ),
      );
      expect(
        client.requests.single.json.containsKey('response_format'),
        isFalse,
      );
    });

    test('accepts an answer wrapped in a code fence', () async {
      final client = respond(
        (_) => jsonResponse(completion('```json\n{"tags":["x"]}\n```')),
      );
      expect(await generate(model(client)), {
        'tags': ['x'],
      });
    });

    test('retries once when the answer breaks the schema', () async {
      final answers = ['{"tags":"oops"}', '{"tags":["ok"]}'];
      final client = respond(
        (_) => jsonResponse(completion(answers.removeAt(0))),
      );
      expect(await generate(model(client)), {
        'tags': ['ok'],
      });
      expect(client.requests, hasLength(2));
    });

    test('gives up with invalidResponse after the retry', () async {
      final client = respond((_) => jsonResponse(completion('not json')));
      expect(
        (await failure(generate(model(client)))).code,
        SystemLlmException.invalidResponse,
      );
      expect(client.requests, hasLength(2));
    });

    test('maps HTTP failures to stable codes', () async {
      const cases = {
        401: SystemLlmException.unauthorized,
        403: SystemLlmException.unauthorized,
        404: SystemLlmException.modelNotFound,
        429: SystemLlmException.rateLimited,
        500: SystemLlmException.generationFailed,
        400: SystemLlmException.generationFailed,
      };
      for (final entry in cases.entries) {
        final client = respond(
          (_) => jsonResponse({
            'error': {'message': 'bad'},
          }, status: entry.key),
        );
        expect(
          (await failure(generate(model(client)))).code,
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('recognises a context-length error', () async {
      final client = respond(
        (_) => jsonResponse({
          'error': {'code': 'context_length_exceeded', 'message': '...'},
        }, status: 400),
      );
      expect(
        (await failure(generate(model(client)))).code,
        SystemLlmException.contextTooLong,
      );
    });

    test('does not follow redirects, so the key stays with the host', () async {
      final client = respond(
        (_) => http.Response('', 302, headers: {'location': 'https://evil/'}),
      );
      expect(
        (await failure(generate(model(client)))).code,
        SystemLlmException.generationFailed,
      );
      expect(client.requests.single.followRedirects, isFalse);
      expect(client.requests, hasLength(1));
    });

    test('streams and model listings do not follow redirects either', () async {
      final client = respond((_) => jsonResponse({'data': []}));
      await model(client).listModels();
      await model(client)
          .streamText(instructions: '', messages: messages)
          .toList()
          .catchError((_) => <String>[]);
      expect(client.requests.map((r) => r.followRedirects), [false, false]);
    });

    test('reports network when the server cannot be reached', () async {
      final client = respond((_) => throw http.ClientException('refused'));
      expect(
        (await failure(generate(model(client)))).code,
        SystemLlmException.network,
      );
    });

    test('times out a silent server', () async {
      final client = RecordingClient((_) => Completer<Never>().future);
      expect(
        (await failure(
          generate(model(client, timeout: const Duration(milliseconds: 50))),
        )).code,
        SystemLlmException.timeout,
      );
    });

    test('cancel stops a running request', () async {
      final client = RecordingClient((_) => Completer<Never>().future);
      final m = model(client);
      final pending = failure(generate(m));
      await Future<void>.delayed(Duration.zero);
      await m.cancel();
      expect((await pending).code, SystemLlmException.cancelled);
    });

    test('rejects a non-object root and an empty conversation', () {
      final m = model(respond((_) => jsonResponse({})));
      expect(
        () => m.generateObject(
          instructions: '',
          messages: messages,
          schema: const AiSchema.string(),
        ),
        throwsArgumentError,
      );
      expect(
        () => m.generateObject(instructions: '', messages: [], schema: schema),
        throwsArgumentError,
      );
    });
  });

  group('streamText', () {
    Stream<String> stream(LanguageModel m) =>
        m.streamText(instructions: '', messages: messages, maxTokens: 20);

    Map<String, Object?> delta(String text) => {
      'choices': [
        {
          'delta': {'content': text},
        },
      ],
    };

    test('yields each delta until [DONE] and asks for a stream', () async {
      final body = sse([delta('Hel'), delta('lo'), '[DONE]', delta('late')]);
      final client = RecordingClient(
        (_) async => chunked([body.substring(0, 17), body.substring(17)]),
      );
      expect(await stream(model(client)).toList(), ['Hel', 'lo']);
      final request = client.requests.single;
      expect(request.json['stream'], isTrue);
      expect(request.json.containsKey('messages'), isTrue);
      expect((request.json['messages']! as List).first, {
        'role': 'user',
        'content': 'hi',
      }, reason: 'no system message for empty instructions');
      expect(request.headers['accept'], 'text/event-stream');
    });

    test('skips keep-alive and role-only events', () async {
      final client = RecordingClient(
        (_) async => chunked([
          ': ping\n\n',
          sse([
            {
              'choices': [
                {
                  'delta': {'role': 'assistant'},
                },
              ],
            },
            delta('x'),
          ]),
        ]),
      );
      expect(await stream(model(client)).toList(), ['x']);
    });

    test('maps an HTTP error before streaming', () async {
      final client = RecordingClient(
        (_) async => chunked(['{"error":{}}'], status: 401),
      );
      await expectLater(
        stream(model(client)),
        emitsError(
          isA<SystemLlmException>().having(
            (e) => e.code,
            'code',
            SystemLlmException.unauthorized,
          ),
        ),
      );
    });

    test('fails on an error event mid-stream', () async {
      final client = RecordingClient(
        (_) async => chunked([
          sse([
            delta('a'),
            {
              'error': {'message': 'boom'},
            },
          ]),
        ]),
      );
      await expectLater(
        stream(model(client)),
        emitsInOrder([
          'a',
          emitsError(
            isA<SystemLlmException>().having(
              (e) => e.code,
              'code',
              SystemLlmException.generationFailed,
            ),
          ),
        ]),
      );
    });

    test('fails with timeout when the server goes silent', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final client = RecordingClient(
        (_) async => http.StreamedResponse(body.stream, 200),
      );
      await expectLater(
        stream(model(client, timeout: const Duration(milliseconds: 50))),
        emitsError(
          isA<SystemLlmException>().having(
            (e) => e.code,
            'code',
            SystemLlmException.timeout,
          ),
        ),
      );
    });

    test('cancelling the subscription stops reading the response', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = RecordingClient(
        (_) async => http.StreamedResponse(body.stream, 200),
      );
      final received = <String>[];
      final subscription = stream(model(client)).listen(received.add);
      body.add(sse([delta('a')]).codeUnits);
      await pumpEventQueue();
      await subscription.cancel();
      expect(received, ['a']);
      expect(cancelled, isTrue);
    });

    test('cancel() ends the stream with cancelled', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final client = RecordingClient(
        (_) async => http.StreamedResponse(body.stream, 200),
      );
      final m = model(client);
      final done = expectLater(
        stream(m),
        emitsInOrder([
          'a',
          emitsError(
            isA<SystemLlmException>().having(
              (e) => e.code,
              'code',
              SystemLlmException.cancelled,
            ),
          ),
          emitsDone,
        ]),
      );
      body.add(sse([delta('a')]).codeUnits);
      await pumpEventQueue();
      await m.cancel();
      await done;
    });
  });

  group('models and availability', () {
    RecordingClient listing(Object? body, {int status = 200}) =>
        respond((_) => jsonResponse(body, status: status));

    Map<String, Object?> models(List<String> ids) => {
      'data': [
        for (final id in ids) {'id': id},
      ],
    };

    test('listModels returns sorted ids from GET /models', () async {
      final client = listing(models(['b', 'a']));
      expect(await model(client).listModels(), ['a', 'b']);
      expect(
        client.requests.single.url.toString(),
        'https://api.example.com/v1/models',
      );
      expect(client.requests.single.method, 'GET');
    });

    test('available when the model is served, also by suffix', () async {
      expect(
        await model(listing(models(['small-model']))).availability(),
        AiAvailability.available,
      );
      expect(
        await model(listing(models(['models/small-model']))).availability(),
        AiAvailability.available,
      );
    });

    test('unsupported when the provider does not serve the model', () async {
      expect(
        await model(listing(models(['other']))).availability(),
        AiAvailability.unsupported,
      );
    });

    test('unauthorized on a rejected key', () async {
      expect(
        await model(listing({}, status: 401)).availability(),
        AiAvailability.unauthorized,
      );
    });

    test('unreachable when the server cannot be reached', () async {
      final client = respond((_) => throw http.ClientException('down'));
      expect(await model(client).availability(), AiAvailability.unreachable);
    });

    test('available when the server has no model listing', () async {
      expect(
        await model(listing({}, status: 404)).availability(),
        AiAvailability.available,
      );
    });
  });

  test('refuses to send a key over plain http to a public host', () {
    expect(
      () => model(
        respond((_) => jsonResponse({})),
        config: config.copyWith(baseUrl: 'http://api.example.com/v1'),
      ),
      throwsArgumentError,
    );
    expect(
      () => RemoteLanguageModel.create(
        config.copyWith(baseUrl: 'not a url'),
        client: respond((_) => jsonResponse({})),
      ),
      throwsArgumentError,
    );
  });

  test('a config without a model can still list models', () async {
    final client = respond((_) => jsonResponse({'data': []}));
    final m = model(client, config: config.copyWith(model: ''));
    expect(await m.listModels(), isEmpty);
  });

  test('toString shows the host but never the key', () {
    final m = model(respond((_) => jsonResponse({})), apiKey: 'sk-secret');
    expect(m.toString(), contains('api.example.com'));
    expect(m.toString(), isNot(contains('sk-secret')));
  });
}
