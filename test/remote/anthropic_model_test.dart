import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:system_llm/providers.dart';

import '../support/http_fakes.dart';

void main() {
  const schema = AiSchema.object({
    'tags': AiSchema.array(
      AiSchema.string(),
      maxItems: 3,
      description: 'Labels',
    ),
    'maxItems': AiSchema.integer(),
  });
  const config = ProviderConfig(
    id: 'claude',
    name: 'Claude',
    protocol: ProviderProtocol.anthropic,
    baseUrl: 'https://api.anthropic.com/v1',
    model: 'claude-opus-5-5',
  );
  const messages = [AiMessage.user('hi')];

  AnthropicModel model(
    http.Client client, {
    String? apiKey = 'sk-ant-test',
    Duration timeout = const Duration(seconds: 5),
  }) => AnthropicModel(
    config: config,
    apiKey: apiKey,
    client: client,
    timeout: timeout,
  );

  Map<String, Object?> message(String text, {String stop = 'end_turn'}) => {
    'type': 'message',
    'stop_reason': stop,
    'content': [
      {'type': 'thinking', 'thinking': ''},
      {'type': 'text', 'text': text},
    ],
  };

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
    maxTokens: 300,
  );

  test('create picks the adapter for the protocol', () {
    final client = respond((_) => jsonResponse({}));
    expect(
      RemoteLanguageModel.create(config, client: client),
      isA<AnthropicModel>(),
    );
    expect(
      RemoteLanguageModel.create(
        config.copyWith(protocol: ProviderProtocol.openAiCompatible),
        client: client,
      ),
      isA<OpenAiCompatibleModel>(),
    );
  });

  group('generateObject', () {
    test('sends system, messages, headers and a JSON output format', () async {
      final client = respond(
        (_) => jsonResponse(message('{"tags":["a"],"maxItems":1}')),
      );
      expect(await generate(model(client)), {
        'tags': ['a'],
        'maxItems': 1,
      });
      final request = client.requests.single;
      expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(request.headers['x-api-key'], 'sk-ant-test');
      expect(request.headers['anthropic-version'], '2026-10-21');
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.json, {
        'model': 'claude-opus-5-5',
        'max_tokens': 300,
        'system': 'Tag it.',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'output_config': {
          'format': {
            'type': 'json_schema',
            'schema': {
              'type': 'object',
              'properties': {
                'tags': {
                  'type': 'array',
                  'description': 'Labels At most 3 items.',
                  'items': {'type': 'string'},
                },
                'maxItems': {'type': 'integer'},
              },
              'required': ['tags', 'maxItems'],
              'additionalProperties': false,
            },
          },
        },
      });
    });

    test('sends no sampling settings and no forced tool choice', () async {
      final client = respond(
        (_) => jsonResponse(message('{"tags":[],"maxItems":0}')),
      );
      await generate(model(client));
      final body = client.requests.single.json;
      for (final key in ['temperature', 'top_p', 'top_k', 'tool_choice']) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
    });

    test('retries once, then reports invalidResponse', () async {
      final client = respond((_) => jsonResponse(message('{"tags":"x"}')));
      expect(
        (await failure(generate(model(client)))).code,
        SystemLlmException.invalidResponse,
      );
      expect(client.requests, hasLength(2));
    });

    test('reports a refusal without retrying', () async {
      final client = respond((_) => jsonResponse(message('', stop: 'refusal')));
      expect(
        (await failure(generate(model(client)))).code,
        SystemLlmException.generationFailed,
      );
      expect(client.requests, hasLength(1));
    });

    test('does not retry an answer cut off at max_tokens', () async {
      final client = respond(
        (_) => jsonResponse(message('{"tags":["a"', stop: 'max_tokens')),
      );
      expect(
        (await failure(generate(model(client)))).code,
        SystemLlmException.invalidResponse,
      );
      expect(client.requests, hasLength(1));
    });

    test('keeps a cut-off answer that still matches the schema', () async {
      final client = respond(
        (_) => jsonResponse(
          message('{"tags":["a"],"maxItems":1}', stop: 'max_tokens'),
        ),
      );
      expect(await generate(model(client)), {
        'tags': ['a'],
        'maxItems': 1,
      });
      expect(client.requests, hasLength(1));
    });

    test('recognises a prompt that is too long', () async {
      final client = respond(
        (_) => jsonResponse({
          'type': 'error',
          'error': {
            'type': 'invalid_request_error',
            'message': 'prompt is too long: 1200000 tokens > 1000000 maximum',
          },
        }, status: 400),
      );
      expect(
        (await failure(generate(model(client)))).code,
        SystemLlmException.contextTooLong,
      );
    });
  });

  group('streamText', () {
    String event(String name, Map<String, Object?> data) =>
        'event: $name\ndata: ${jsonEncodeCompact(data)}\n\n';

    Map<String, Object?> textDelta(String text) => {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': text},
    };

    test('yields text deltas and stops at message_stop', () async {
      final client = RecordingClient(
        (_) async => chunked([
          event('message_start', {'type': 'message_start'}),
          event('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'thinking_delta', 'thinking': 'hmm'},
          }),
          event('content_block_delta', textDelta('Hel')),
          event('ping', {'type': 'ping'}),
          event('content_block_delta', textDelta('lo')),
          event('message_stop', {'type': 'message_stop'}),
          event('content_block_delta', textDelta('late')),
        ]),
      );
      final chunks = await model(
        client,
      ).streamText(instructions: 'Be brief.', messages: messages).toList();
      expect(chunks, ['Hel', 'lo']);
      final body = client.requests.single.json;
      expect(body['stream'], isTrue);
      expect(body['system'], 'Be brief.');
    });

    test('fails when the stream ends without message_stop', () async {
      final client = RecordingClient(
        (_) async => chunked([event('content_block_delta', textDelta('Hi'))]),
      );
      await expectLater(
        model(client).streamText(instructions: '', messages: messages),
        emitsInOrder([
          'Hi',
          emitsError(
            isA<SystemLlmException>().having(
              (e) => e.code,
              'code',
              SystemLlmException.network,
            ),
          ),
        ]),
      );
    });

    test('maps an error event', () async {
      final client = RecordingClient(
        (_) async => chunked([
          event('content_block_delta', textDelta('a')),
          event('error', {
            'type': 'error',
            'error': {'type': 'rate_limit_error', 'message': 'slow down'},
          }),
        ]),
      );
      await expectLater(
        model(client).streamText(instructions: '', messages: messages),
        emitsInOrder([
          'a',
          emitsError(
            isA<SystemLlmException>().having(
              (e) => e.code,
              'code',
              SystemLlmException.rateLimited,
            ),
          ),
        ]),
      );
    });

    test('fails when the answer stops with a refusal', () async {
      final client = RecordingClient(
        (_) async => chunked([
          event('message_delta', {
            'type': 'message_delta',
            'delta': {'stop_reason': 'refusal'},
          }),
        ]),
      );
      await expectLater(
        model(client).streamText(instructions: '', messages: messages),
        emitsError(
          isA<SystemLlmException>().having(
            (e) => e.code,
            'code',
            SystemLlmException.generationFailed,
          ),
        ),
      );
    });
  });

  test('listModels asks for the full list', () async {
    final client = respond(
      (_) => jsonResponse({
        'data': [
          {'id': 'claude-sonnet-5-5'},
          {'id': 'claude-opus-5-5'},
        ],
        'has_more': false,
      }),
    );
    final m = model(client);
    expect(await m.listModels(), ['claude-opus-5-5', 'claude-sonnet-5-5']);
    expect(
      client.requests.single.url.toString(),
      'https://api.anthropic.com/v1/models?limit=1000',
    );
    expect(await m.availability(), AiAvailability.available);
  });
}
