/// The HTTP API a provider speaks.
enum ProviderProtocol {
  /// `POST /chat/completions`: OpenAI, Ollama, LM Studio, Gemini, Qwen,
  /// OpenRouter, Groq, DeepSeek, Mistral and most self-hosted servers.
  openAiCompatible,

  /// Anthropic's `POST /messages`.
  anthropic,
}

/// How an OpenAI-compatible provider is asked for JSON. Anthropic always uses
/// a forced tool call. Every answer is validated against the schema anyway.
enum StructuredOutputMode {
  /// `response_format: json_schema` with `strict: true`.
  jsonSchema,

  /// `response_format: json_object`, with the schema in the prompt.
  jsonObject,

  /// Schema in the prompt only, for servers that reject `response_format`.
  prompt,
}

/// The request field that carries the token limit.
enum MaxTokensField {
  /// `max_tokens`: most OpenAI-compatible servers, and Anthropic.
  maxTokens,

  /// `max_completion_tokens`: OpenAI's current models.
  maxCompletionTokens,
}

/// Why a [ProviderConfig] cannot be used.
enum ProviderConfigError {
  nameMissing,
  baseUrlInvalid,

  /// `http://` to a public host: the API key and prompts would travel in
  /// clear text. Plain HTTP is only accepted for loopback and private
  /// network hosts (a local Ollama or LM Studio).
  insecureBaseUrl,
  modelMissing,
}

/// One provider entry the user configured: where to send requests and which
/// model to use. The API key is not part of it; it lives in an `ApiKeyStore`.
final class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.model,
    this.presetId,
    this.structuredOutput = StructuredOutputMode.jsonSchema,
    this.maxTokensField = MaxTokensField.maxTokens,
  });

  /// Restores a config written by [toJson]. Unknown enum values fall back to
  /// the defaults; a missing `id` or `baseUrl` throws [FormatException].
  factory ProviderConfig.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final baseUrl = json['baseUrl'];
    if (id is! String || id.isEmpty || baseUrl is! String) {
      throw const FormatException('ProviderConfig needs id and baseUrl.');
    }
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((value) => value.name == name).firstOrNull ?? fallback;
    return ProviderConfig(
      id: id,
      name: json['name'] as String? ?? '',
      protocol: pick(
        ProviderProtocol.values,
        json['protocol'],
        ProviderProtocol.openAiCompatible,
      ),
      baseUrl: baseUrl,
      model: json['model'] as String? ?? '',
      presetId: json['presetId'] as String?,
      structuredOutput: pick(
        StructuredOutputMode.values,
        json['structuredOutput'],
        StructuredOutputMode.jsonSchema,
      ),
      maxTokensField: pick(
        MaxTokensField.values,
        json['maxTokensField'],
        MaxTokensField.maxTokens,
      ),
    );
  }

  /// Unique within the app; also the key of the API key in the key store.
  final String id;

  /// Name shown to the user.
  final String name;
  final ProviderProtocol protocol;

  /// API root, for example `https://api.openai.com/v1`.
  final String baseUrl;

  /// Model identifier sent to the provider, for example `qwen3:8b`.
  final String model;

  /// The preset this entry was created from, if any.
  final String? presetId;
  final StructuredOutputMode structuredOutput;
  final MaxTokensField maxTokensField;

  /// Host the prompts are sent to, for showing to the user.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  /// [baseUrl] joined with [path] (which starts with `/`).
  Uri endpoint(String path) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base$path');
  }

  /// Problems that stop this config from being used; empty when it is valid.
  List<ProviderConfigError> validate() {
    final uri = Uri.tryParse(baseUrl.trim());
    final validUrl =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    return [
      if (name.trim().isEmpty) ProviderConfigError.nameMissing,
      if (!validUrl) ProviderConfigError.baseUrlInvalid,
      if (validUrl && uri.scheme == 'http' && !isPrivateHost(uri.host))
        ProviderConfigError.insecureBaseUrl,
      if (model.trim().isEmpty) ProviderConfigError.modelMissing,
    ];
  }

  /// Whether [host] is loopback, link-local, on a private network (RFC 1918,
  /// carrier-grade NAT such as Tailscale, IPv6 unique-local) or a local name,
  /// where plain HTTP is acceptable for a local model server.
  ///
  /// IPv4 octets must be plain decimal: resolvers read a leading zero as
  /// octal, so `010.0.0.1` is really the public `8.0.0.1`.
  static bool isPrivateHost(String host) {
    var name = host.toLowerCase();
    if (name.endsWith('.')) name = name.substring(0, name.length - 1);
    if (name == 'localhost' ||
        name.endsWith('.localhost') ||
        name.endsWith('.local')) {
      return true;
    }
    if (name.contains(':')) return _isPrivateIPv6(name);
    final octets = _ipv4Octets(name);
    return octets != null && _isPrivateIPv4(octets);
  }

  static List<int>? _ipv4Octets(String name) {
    final parts = name.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final part in parts) {
      final valid =
          part.isNotEmpty &&
          part.length <= 3 &&
          part.codeUnits.every((c) => c >= 0x30 && c <= 0x39) &&
          (part.length == 1 || !part.startsWith('0'));
      if (!valid) return null;
      final value = int.parse(part);
      if (value > 255) return null;
      octets.add(value);
    }
    return octets;
  }

  static bool _isPrivateIPv4(List<int> octets) {
    final [a, b, ...] = octets;
    return a == 127 ||
        a == 10 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 169 && b == 254) ||
        (a == 100 && b >= 64 && b <= 127);
  }

  static bool _isPrivateIPv6(String name) {
    final List<int> bytes;
    try {
      bytes = Uri.parseIPv6Address(name);
    } on FormatException {
      return false;
    }
    final zeroPrefix = bytes.take(10).every((b) => b == 0);
    if (zeroPrefix && bytes.skip(10).take(5).every((b) => b == 0)) {
      return bytes[15] == 1; // ::1
    }
    if (zeroPrefix && bytes[10] == 0xff && bytes[11] == 0xff) {
      return _isPrivateIPv4(bytes.sublist(12)); // ::ffff:a.b.c.d
    }
    return (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) || // fe80::/10
        (bytes[0] & 0xfe) == 0xfc; // fc00::/7
  }

  ProviderConfig copyWith({
    String? name,
    ProviderProtocol? protocol,
    String? baseUrl,
    String? model,
    StructuredOutputMode? structuredOutput,
    MaxTokensField? maxTokensField,
  }) => ProviderConfig(
    id: id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    presetId: presetId,
    structuredOutput: structuredOutput ?? this.structuredOutput,
    maxTokensField: maxTokensField ?? this.maxTokensField,
  );

  /// Everything except the API key, which must never be stored with it.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'baseUrl': baseUrl,
    'model': model,
    'presetId': ?presetId,
    'structuredOutput': structuredOutput.name,
    'maxTokensField': maxTokensField.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ProviderConfig &&
      other.id == id &&
      other.name == name &&
      other.protocol == protocol &&
      other.baseUrl == baseUrl &&
      other.model == model &&
      other.presetId == presetId &&
      other.structuredOutput == structuredOutput &&
      other.maxTokensField == maxTokensField;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    protocol,
    baseUrl,
    model,
    presetId,
    structuredOutput,
    maxTokensField,
  );

  @override
  String toString() => 'ProviderConfig($id, $name, $host, $model)';
}
