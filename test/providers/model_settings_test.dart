import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/providers.dart';

void main() {
  final ollama = ProviderPresets.ollama.toConfig(id: 'a');
  final claude = ProviderPresets.anthropic.toConfig(id: 'b');

  test('defaults to the on-device model with no providers', () {
    const settings = ModelSettings();
    expect(settings.useThirdParty, isFalse);
    expect(settings.selected, isNull);
  });

  test('the first provider added becomes selected', () {
    final settings = const ModelSettings()
        .withProvider(ollama)
        .withProvider(claude);
    expect(settings.providers, [ollama, claude]);
    expect(settings.selected, ollama);
  });

  test('withProvider replaces an entry with the same id', () {
    final renamed = ollama.copyWith(name: 'Home server');
    final settings = const ModelSettings()
        .withProvider(ollama)
        .withProvider(renamed);
    expect(settings.providers, [renamed]);
  });

  test('removing the selected provider clears the selection', () {
    final settings = const ModelSettings()
        .withProvider(ollama)
        .withProvider(claude)
        .withoutProvider('a');
    expect(settings.providers, [claude]);
    expect(settings.selectedProviderId, isNull);
  });

  test('JSON round-trips and skips unreadable entries', () {
    final settings = const ModelSettings(useThirdParty: true)
        .withProvider(ollama)
        .withProvider(claude)
        .copyWith(selectedProviderId: 'b');
    final json = settings.toJson();
    (json['providers']! as List).add({'name': 'broken'});
    final restored = ModelSettings.fromJson(json);
    expect(restored.useThirdParty, isTrue);
    expect(restored.providers, [ollama, claude]);
    expect(restored.selected, claude);
  });

  test('InMemoryApiKeyStore reads, writes and deletes', () async {
    final store = InMemoryApiKeyStore({'a': 'k1'});
    expect(await store.read('a'), 'k1');
    await store.write('b', 'k2');
    await store.delete('a');
    expect(await store.read('a'), isNull);
    expect(await store.read('b'), 'k2');
  });
}
