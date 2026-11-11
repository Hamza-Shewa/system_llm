part of 'remote_model.dart';

/// Speaks `POST /chat/completions`, the API most providers and local servers
/// copy: OpenAI, Ollama (`/v1`), LM Studio, Gemini's OpenAI endpoint, Qwen
/// (DashScope compatible mode), OpenRouter, Groq, DeepSeek, Mistral.
final class OpenAiCompatibleModel extends RemoteLanguageModel {
  OpenAiCompatibleModel({
    required super.config,
    String? apiKey,
    super.client,
    super.timeout,
  }) : super._(
         headers: {
           if (apiKey != null && apiKey.trim().isNotEmpty)
             'authorization': 'Bearer ${apiKey.trim()}',
         },
       );

  Map<String, Object?> _body({
    required String instructions,
    required List<AiMessage> messages,
    required int maxTokens,
  }) => {
    'model': config.model.trim(),
    'messages': [
      if (instructions.isNotEmpty) {'role': 'system', 'content': instructions},
      for (final message in messages)
        {'role': message.role.name, 'content': message.text},
    ],
    switch (config.maxTokensField) {
      MaxTokensField.maxTokens => 'max_tokens',
      MaxTokensField.maxCompletionTokens => 'max_completion_tokens',
    }: maxTokens,
  };

  @override
  Future<Object?> _requestObject({
    required String instructions,
    required List<AiMessage> messages,
    required AiObjectSchema schema,
    required int maxTokens,
  }) async {
    final mode = config.structuredOutput;
    final prompt = mode == StructuredOutputMode.jsonSchema
        ? instructions
        : [
            if (instructions.isNotEmpty) instructions,
            _schemaInstruction(schema),
          ].join('\n\n');
    final json = await _transport.postJson(
      config.endpoint('/chat/completions'),
      _headers,
      {
        ..._body(
          instructions: prompt,
          messages: messages,
          maxTokens: maxTokens,
        ),
        if (mode == StructuredOutputMode.jsonSchema)
          'response_format': {
            'type': 'json_schema',
            'json_schema': {
              'name': 'response',
              'strict': true,
              'schema': schema.toJsonSchema(),
            },
          },
        if (mode == StructuredOutputMode.jsonObject)
          'response_format': {'type': 'json_object'},
      },
    );
    return _decodeAnswer(_at(json, ['choices', 0, 'message', 'content']));
  }

  @override
  Stream<String> streamText({
    required String instructions,
    required List<AiMessage> messages,
    String locale = 'en',
    int maxTokens = 512,
  }) {
    _checkMessages(messages);
    final events = _transport
        .postSse(config.endpoint('/chat/completions'), _headers, {
          ..._body(
            instructions: instructions,
            messages: messages,
            maxTokens: maxTokens,
          ),
          'stream': true,
        });
    return _textStream(events, (event) {
      if (event.data.trim() == '[DONE]') return (text: null, done: true);
      final json = _eventJson(event);
      if (json is Map && json['error'] != null) {
        throw const SystemLlmException(SystemLlmException.generationFailed);
      }
      final content = _at(json, ['choices', 0, 'delta', 'content']);
      return (text: content is String ? content : null, done: false);
    });
  }
}
