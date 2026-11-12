import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/providers.dart';

import '../support/http_fakes.dart';

void main() {
  final client = respond((_) => jsonResponse({}));
  final claude = ProviderPresets.anthropic.toConfig(id: 'c');
  final ollama = ProviderPresets.ollama.toConfig(id: 'o');

  Future<SystemLlmException> failure(Future<Object?> call) async {
    try {
      await call;
    } on SystemLlmException catch (error) {
      return error;
    }
    throw StateError('expected SystemLlmException');
  }

  ModelResolver resolver([Map<String, String>? keys]) =>
      ModelResolver(keyStore: InMemoryApiKeyStore(keys), client: client);

  test(
    'uses the on-device model while third-party providers are off',
    () async {
      final settings = const ModelSettings().withProvider(claude);
      final model = await resolver({'c': 'key'}).resolve(settings);
      expect(model, isA<OnDeviceModel>());
      expect(model.isOnDevice, isTrue);
    },
  );

  test('builds the selected remote model with its key', () async {
    final settings = const ModelSettings(
      useThirdParty: true,
    ).withProvider(claude);
    final model = await resolver({'c': 'key'}).resolve(settings);
    expect(model, isA<AnthropicModel>());
    expect(model.id, 'c');
    expect(model.isOnDevice, isFalse);
  });

  test('a local server needs no key', () async {
    final settings = const ModelSettings(
      useThirdParty: true,
    ).withProvider(ollama);
    expect(await resolver().resolve(settings), isA<OpenAiCompatibleModel>());
  });

  test('refuses a cloud provider without a key', () async {
    final settings = const ModelSettings(
      useThirdParty: true,
    ).withProvider(claude);
    expect(
      (await failure(resolver({'c': ' '}).resolve(settings))).code,
      SystemLlmException.notConfigured,
    );
  });

  test('refuses when nothing is selected or the entry is invalid', () async {
    const none = ModelSettings(useThirdParty: true);
    expect(
      (await failure(resolver().resolve(none))).code,
      SystemLlmException.notConfigured,
    );
    final invalid = none.withProvider(ollama.copyWith(model: ''));
    expect(
      (await failure(resolver().resolve(invalid))).code,
      SystemLlmException.notConfigured,
    );
  });
}
