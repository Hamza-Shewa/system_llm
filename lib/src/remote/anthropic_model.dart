part of 'remote_model.dart';

/// Speaks Anthropic's Messages API (`POST /messages`).
///
/// Structured output uses `output_config.format` (JSON outputs), because the
/// current Claude models reject a forced tool choice. Array length limits are
/// not supported there, so they are moved into the field description.
/// Sampling settings (`temperature` and the like) are never sent: API version
/// `2026-10-21` rejects them.
final class AnthropicModel extends RemoteLanguageModel {
  AnthropicModel({
    required super.config,
    String? apiKey,
    super.client,
    super.timeout,
  }) : super._(
         headers: {
           if (apiKey != null && apiKey.trim().isNotEmpty)
             'x-api-key': apiKey.trim(),
           'anthropic-version': apiVersion,
         },
       );

  /// The `anthropic-version` header sent with every request.
  static const apiVersion = '2026-10-21';

  @override
  String get _modelsPath => '/models?limit=1000';

  Map<String, Object?> _body({
    required String instructions,
    required List<AiMessage> messages,
    required int maxTokens,
  }) => {
    'model': config.model.trim(),
    'max_tokens': maxTokens,
    if (instructions.isNotEmpty) 'system': instructions,
    'messages': [
      for (final message in messages)
        {'role': message.role.name, 'content': message.text},
    ],
  };

  @override
  Future<Object?> _requestObject({
    required String instructions,
    required List<AiMessage> messages,
    required AiObjectSchema schema,
    required int maxTokens,
  }) async {
    final json = await _transport.postJson(
      config.endpoint('/messages'),
      _headers,
      {
        ..._body(
          instructions: instructions,
          messages: messages,
          maxTokens: maxTokens,
        ),
        'output_config': {
          'format': {
            'type': 'json_schema',
            'schema': _withoutArrayLimits(schema.toJsonSchema()),
          },
        },
      },
    );
    if (_at(json, ['stop_reason']) == 'refusal') {
      throw const SystemLlmException(SystemLlmException.generationFailed);
    }
    final content = _at(json, ['content']);
    final text = content is List
        ? content
              .whereType<Map>()
              .where((block) => block['type'] == 'text')
              .map((block) => block['text'])
              .whereType<String>()
              .join()
        : null;
    return _decodeAnswer(text);
  }

  @override
  Stream<String> streamText({
    required String instructions,
    required List<AiMessage> messages,
    String locale = 'en',
    int maxTokens = 512,
  }) {
    _checkMessages(messages);
    final events = _transport.postSse(config.endpoint('/messages'), _headers, {
      ..._body(
        instructions: instructions,
        messages: messages,
        maxTokens: maxTokens,
      ),
      'stream': true,
    });
    return _textStream(events, (event) {
      final json = _eventJson(event);
      switch (_at(json, ['type'])) {
        case 'content_block_delta'
            when _at(json, ['delta', 'type']) == 'text_delta':
          final text = _at(json, ['delta', 'text']);
          return (text: text is String ? text : null, done: false);
        case 'message_delta'
            when _at(json, ['delta', 'stop_reason']) == 'refusal':
          throw const SystemLlmException(SystemLlmException.generationFailed);
        case 'message_stop':
          return (text: null, done: true);
        case 'error':
          throw SystemLlmException(switch (_at(json, ['error', 'type'])) {
            'rate_limit_error' => SystemLlmException.rateLimited,
            'authentication_error' ||
            'permission_error' => SystemLlmException.unauthorized,
            _ => SystemLlmException.generationFailed,
          });
      }
      return (text: null, done: false);
    });
  }

  /// [schema] with `maxItems` removed and stated in the description instead.
  /// Walks only `properties` and `items`, so a field named `maxItems` stays.
  static Map<String, Object?> _withoutArrayLimits(Map<String, Object?> schema) {
    final result = {...schema};
    if (result['properties'] case final Map<String, Object?> properties) {
      result['properties'] = {
        for (final MapEntry(:key, :value) in properties.entries)
          key: value is Map<String, Object?>
              ? _withoutArrayLimits(value)
              : value,
      };
    }
    if (result['items'] case final Map<String, Object?> items) {
      result['items'] = _withoutArrayLimits(items);
    }
    final maxItems = result.remove('maxItems');
    if (maxItems != null) {
      final description = result['description'];
      result['description'] = [
        if (description is String && description.isNotEmpty) description,
        'At most $maxItems items.',
      ].join(' ');
    }
    return result;
  }
}
