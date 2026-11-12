import 'provider_config.dart';

/// A provider the package knows how to reach: endpoint, protocol and a few
/// suggested models. Users still bring their own API key.
final class ProviderPreset {
  const ProviderPreset({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.requiresApiKey,
    this.suggestedModels = const [],
    this.structuredOutput = StructuredOutputMode.jsonSchema,
    this.maxTokensField = MaxTokensField.maxTokens,
    this.isLocal = false,
    this.apiKeyUrl,
    this.note,
  });

  final String id;
  final String name;
  final ProviderProtocol protocol;
  final String baseUrl;
  final bool requiresApiKey;

  /// Starting points only: model names change often, so offer the live list
  /// from `RemoteLanguageModel.listModels` too.
  final List<String> suggestedModels;
  final StructuredOutputMode structuredOutput;
  final MaxTokensField maxTokensField;

  /// Runs on the user's own machine or network (Ollama, LM Studio).
  final bool isLocal;

  /// Where the user creates an API key.
  final String? apiKeyUrl;

  /// One line of setup advice to show next to the preset.
  final String? note;

  /// A new user entry based on this preset.
  ProviderConfig toConfig({required String id, String? model, String? name}) =>
      ProviderConfig(
        id: id,
        name: name ?? this.name,
        protocol: protocol,
        baseUrl: baseUrl,
        model: model ?? (suggestedModels.isEmpty ? '' : suggestedModels.first),
        presetId: this.id,
        structuredOutput: structuredOutput,
        maxTokensField: maxTokensField,
      );
}

/// Built-in presets. Base URLs were checked against each provider's
/// documentation on 2026-11-11; suggested model IDs are the provider's stable
/// aliases where one exists, and may still go stale.
abstract final class ProviderPresets {
  static const openAi = ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'https://api.openai.com/v1',
    requiresApiKey: true,
    suggestedModels: ['gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.6-sol'],
    maxTokensField: MaxTokensField.maxCompletionTokens,
    apiKeyUrl: 'https://platform.openai.com/api-keys',
  );

  static const anthropic = ProviderPreset(
    id: 'anthropic',
    name: 'Anthropic (Claude)',
    protocol: ProviderProtocol.anthropic,
    baseUrl: 'https://api.anthropic.com/v1',
    requiresApiKey: true,
    suggestedModels: [
      'claude-opus-5-5',
      'claude-sonnet-5-5',
      'claude-haiku-5-5',
    ],
    apiKeyUrl: 'https://platform.claude.com/settings/keys',
    note:
        'Current Claude models think before answering: allow at least a '
        'few thousand max tokens.',
  );

  static const gemini = ProviderPreset(
    id: 'gemini',
    name: 'Google Gemini',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    requiresApiKey: true,
    suggestedModels: ['gemini-flash-latest', 'gemini-pro-latest'],
    apiKeyUrl: 'https://aistudio.google.com/apikey',
  );

  static const qwen = ProviderPreset(
    id: 'qwen',
    name: 'Qwen (Alibaba Model Studio)',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
    requiresApiKey: true,
    suggestedModels: ['qwen-plus', 'qwen-max', 'qwen-flash'],
    structuredOutput: StructuredOutputMode.jsonObject,
    apiKeyUrl: 'https://modelstudio.console.alibabacloud.com/',
    note:
        'International (Singapore) endpoint. Mainland China accounts use '
        'https://dashscope.aliyuncs.com/compatible-mode/v1.',
  );

  static const openRouter = ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'https://openrouter.ai/api/v1',
    requiresApiKey: true,
    suggestedModels: ['openrouter/auto'],
    apiKeyUrl: 'https://openrouter.ai/settings/keys',
    note: 'One key for models from many providers; use Fetch models to pick.',
  );

  static const groq = ProviderPreset(
    id: 'groq',
    name: 'Groq',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'https://api.groq.com/openai/v1',
    requiresApiKey: true,
    suggestedModels: ['llama-3.3-70b-versatile'],
    structuredOutput: StructuredOutputMode.jsonObject,
    apiKeyUrl: 'https://console.groq.com/keys',
  );

  static const deepSeek = ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'https://api.deepseek.com',
    requiresApiKey: true,
    suggestedModels: ['deepseek-chat', 'deepseek-reasoner'],
    structuredOutput: StructuredOutputMode.jsonObject,
    apiKeyUrl: 'https://platform.deepseek.com/api_keys',
  );

  static const mistral = ProviderPreset(
    id: 'mistral',
    name: 'Mistral',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'https://api.mistral.ai/v1',
    requiresApiKey: true,
    suggestedModels: ['mistral-small-latest', 'mistral-large-latest'],
    apiKeyUrl: 'https://console.mistral.ai/api-keys',
  );

  static const ollama = ProviderPreset(
    id: 'ollama',
    name: 'Ollama (local)',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'http://localhost:11434/v1',
    requiresApiKey: false,
    suggestedModels: ['qwen3:8b', 'llama3.2', 'gemma3'],
    isLocal: true,
    note:
        'On the Android emulator use http://10.0.2.2:11434/v1; on a phone '
        "use the computer's LAN address and start Ollama with "
        'OLLAMA_HOST=0.0.0.0.',
  );

  static const lmStudio = ProviderPreset(
    id: 'lmstudio',
    name: 'LM Studio (local)',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'http://localhost:1234/v1',
    requiresApiKey: false,
    isLocal: true,
    note:
        'Load a model in LM Studio, start its server, then use Fetch '
        'models. Same address rules as Ollama.',
  );

  /// Every preset, cloud providers first.
  static const all = [
    openAi,
    anthropic,
    gemini,
    qwen,
    openRouter,
    groq,
    deepSeek,
    mistral,
    ollama,
    lmStudio,
  ];

  static ProviderPreset? byId(String? id) =>
      all.where((preset) => preset.id == id).firstOrNull;
}
