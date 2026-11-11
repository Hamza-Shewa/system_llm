import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/providers.dart';

void main() {
  const config = ProviderConfig(
    id: 'p1',
    name: 'Ollama',
    protocol: ProviderProtocol.openAiCompatible,
    baseUrl: 'http://localhost:11434/v1/',
    model: 'qwen3:8b',
    presetId: 'ollama',
    structuredOutput: StructuredOutputMode.jsonObject,
    maxTokensField: MaxTokensField.maxCompletionTokens,
  );

  test('JSON round-trips every field', () {
    expect(ProviderConfig.fromJson(config.toJson()), config);
  });

  test('JSON has exactly the non-secret fields', () {
    expect(config.toJson().keys.toSet(), {
      'id',
      'name',
      'protocol',
      'baseUrl',
      'model',
      'presetId',
      'structuredOutput',
      'maxTokensField',
    });
  });

  test('fromJson falls back on unknown enum values', () {
    final restored = ProviderConfig.fromJson({
      'id': 'x',
      'baseUrl': 'https://a.example',
      'protocol': 'carrier-pigeon',
      'structuredOutput': '?',
    });
    expect(restored.protocol, ProviderProtocol.openAiCompatible);
    expect(restored.structuredOutput, StructuredOutputMode.jsonSchema);
    expect(restored.maxTokensField, MaxTokensField.maxTokens);
  });

  test('fromJson rejects entries without id or baseUrl', () {
    expect(
      () => ProviderConfig.fromJson({'baseUrl': 'https://a'}),
      throwsFormatException,
    );
    expect(() => ProviderConfig.fromJson({'id': 'x'}), throwsFormatException);
  });

  test('endpoint joins the path without doubling slashes', () {
    expect(
      config.endpoint('/models').toString(),
      'http://localhost:11434/v1/models',
    );
    expect(config.host, 'localhost');
  });

  group('validate', () {
    ProviderConfig withUrl(String url) => config.copyWith(baseUrl: url);

    test('accepts a complete config', () {
      expect(config.validate(), isEmpty);
    });

    test('reports missing name and model', () {
      expect(config.copyWith(name: ' ', model: '').validate(), [
        ProviderConfigError.nameMissing,
        ProviderConfigError.modelMissing,
      ]);
    });

    test('rejects URLs that are not http(s) with a host', () {
      for (final url in ['', 'not a url', 'ftp://x.example', 'https://']) {
        expect(withUrl(url).validate(), [
          ProviderConfigError.baseUrlInvalid,
        ], reason: url);
      }
    });

    test('rejects plain http to a public host', () {
      for (final url in [
        'http://api.openai.com/v1',
        'http://8.8.8.8/v1',
        'http://172.32.0.1/v1',
        'http://192.169.1.1/v1',
      ]) {
        expect(withUrl(url).validate(), [
          ProviderConfigError.insecureBaseUrl,
        ], reason: url);
      }
    });

    test('allows plain http to loopback and private hosts', () {
      for (final url in [
        'http://localhost:11434/v1',
        'http://127.0.0.1:1234/v1',
        'http://10.0.2.2:11434/v1',
        'http://192.168.1.20:11434/v1',
        'http://172.16.0.5/v1',
        'http://[::1]:11434/v1',
        'http://studio.local:1234/v1',
      ]) {
        expect(withUrl(url).validate(), isEmpty, reason: url);
      }
    });

    test('allows https anywhere', () {
      expect(withUrl('https://api.openai.com/v1').validate(), isEmpty);
    });
  });
}
