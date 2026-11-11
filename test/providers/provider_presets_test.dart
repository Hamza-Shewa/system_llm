import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/providers.dart';

void main() {
  test('preset ids are unique and resolvable', () {
    final ids = ProviderPresets.all.map((p) => p.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final preset in ProviderPresets.all) {
      expect(ProviderPresets.byId(preset.id), same(preset));
    }
    expect(ProviderPresets.byId('nope'), isNull);
    expect(ProviderPresets.byId(null), isNull);
  });

  test('every preset produces a valid config', () {
    for (final preset in ProviderPresets.all) {
      final config = preset.toConfig(id: 'x', model: 'some-model');
      expect(config.validate(), isEmpty, reason: preset.id);
      expect(config.presetId, preset.id);
      expect(config.protocol, preset.protocol);
    }
  });

  test('cloud presets use https and need a key; local ones do not', () {
    for (final preset in ProviderPresets.all) {
      final scheme = Uri.parse(preset.baseUrl).scheme;
      if (preset.isLocal) {
        expect(preset.requiresApiKey, isFalse, reason: preset.id);
      } else {
        expect(scheme, 'https', reason: preset.id);
        expect(preset.requiresApiKey, isTrue, reason: preset.id);
      }
    }
  });

  test('toConfig defaults to the first suggested model', () {
    final config = ProviderPresets.ollama.toConfig(id: 'o');
    expect(config.model, ProviderPresets.ollama.suggestedModels.first);
    expect(config.name, 'Ollama (local)');
    expect(ProviderPresets.lmStudio.toConfig(id: 'l').model, '');
  });
}
