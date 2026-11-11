import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/providers.dart';
import 'package:system_llm_example/data/settings_repository.dart';
import 'package:system_llm_example/ui/features/models/view_models/models_view_model.dart';

import 'support/fakes.dart';

void main() {
  final ollama = ProviderPresets.ollama.toConfig(id: 'o');
  final claude = ProviderPresets.anthropic.toConfig(id: 'c');
  late InMemorySettingsRepository repository;
  late InMemoryApiKeyStore keys;
  late FakeProbe probe;
  late FakeLanguageModel onDevice;

  ModelsViewModel build([SettingsRepository? repo]) => ModelsViewModel(
    repository: repo ?? repository,
    keyStore: keys,
    probe: probe,
    onDevice: onDevice,
    newId: () => 'new-id',
  );

  setUp(() {
    repository = InMemorySettingsRepository(
      const ModelSettings().withProvider(ollama).withProvider(claude),
    );
    keys = InMemoryApiKeyStore({'c': 'sk-saved'});
    probe = FakeProbe();
    onDevice = FakeLanguageModel(
      availabilityResult: AiAvailability.modelNotReady,
    );
  });

  test('load reads settings, saved keys and on-device availability', () async {
    final vm = build();
    expect(vm.loading, isTrue);
    await vm.load();
    expect(vm.loading, isFalse);
    expect(vm.settings.providers, [ollama, claude]);
    expect(vm.hasSavedKey('c'), isTrue);
    expect(vm.hasSavedKey('o'), isFalse);
    expect(vm.onDeviceAvailability, AiAvailability.modelNotReady);
  });

  test('a load failure keeps defaults and is reported', () async {
    final vm = build(_ThrowingRepository());
    await vm.load();
    expect(vm.loadFailed, isTrue);
    expect(vm.settings.providers, isEmpty);
  });

  test('a successful retry clears the load failure', () async {
    final flaky = _ThrowingRepository(
      failures: 1,
      settings: repository.settings,
    );
    final vm = build(flaky);
    await vm.load();
    expect(vm.loadFailed, isTrue);
    await vm.load();
    expect(vm.loadFailed, isFalse);
    expect(vm.settings.providers, [ollama, claude]);
  });

  test('a failed key write leaves the settings unchanged', () async {
    final vm = ModelsViewModel(
      repository: repository,
      keyStore: ThrowingKeyStore(),
      probe: probe,
      onDevice: onDevice,
    );
    await vm.load();
    final before = repository.settings;
    final groq = ProviderPresets.groq.toConfig(id: 'g');
    await expectLater(vm.saveProvider(groq, apiKey: 'gsk'), throwsStateError);
    expect(repository.settings.providers, before.providers);
    expect(vm.settings.providers, before.providers);
  });

  test('a failed settings save leaves the saved key unchanged', () async {
    final failing = FailingSettingsRepository()..settings = repository.settings;
    final vm = build(failing);
    await vm.load();
    await expectLater(
      vm.saveProvider(claude, apiKey: 'sk-new'),
      throwsStateError,
    );
    expect(await keys.read('c'), 'sk-saved');
    await expectLater(vm.deleteProvider('c'), throwsStateError);
    expect(await keys.read('c'), 'sk-saved');
  });

  test('testing an edited draft does not change the saved status', () async {
    final vm = build();
    await vm.load();
    probe.result = AiAvailability.available;
    await vm.check(claude);
    probe.result = AiAvailability.unsupported;
    await vm.check(claude.copyWith(model: 'other'));
    expect(vm.availabilityOf('c'), AiAvailability.available);
  });

  test('saveProvider stores the key apart from the settings', () async {
    final vm = build();
    await vm.load();
    final groq = ProviderPresets.groq.toConfig(id: 'g');
    await vm.saveProvider(groq, apiKey: ' gsk-1 ');
    expect(await keys.read('g'), 'gsk-1');
    expect(repository.settings.providers.last, groq);
    expect(repository.settings.toJson().toString(), isNot(contains('gsk-1')));
    expect(vm.hasSavedKey('g'), isTrue);
  });

  test('a null key keeps the saved key; an empty one removes it', () async {
    final vm = build();
    await vm.load();
    await vm.saveProvider(claude.copyWith(name: 'Claude work'));
    expect(await keys.read('c'), 'sk-saved');
    await vm.saveProvider(claude, apiKey: '');
    expect(await keys.read('c'), isNull);
    expect(vm.hasSavedKey('c'), isFalse);
  });

  test('deleteProvider removes the entry and its key', () async {
    final vm = build();
    await vm.load();
    await vm.deleteProvider('c');
    expect(repository.settings.providers, [ollama]);
    expect(await keys.read('c'), isNull);
  });

  test('check uses the saved key and remembers the result', () async {
    final vm = build();
    await vm.load();
    probe.result = AiAvailability.unauthorized;
    expect(await vm.check(claude), AiAvailability.unauthorized);
    expect(probe.checkedKeys.last, 'sk-saved');
    expect(vm.availabilityOf('c'), AiAvailability.unauthorized);
    expect(vm.isChecking('c'), isFalse);
  });

  test('the toggle is saved, and reverted when saving fails', () async {
    final vm = build();
    await vm.load();
    await vm.setUseThirdParty(true);
    expect(repository.settings.useThirdParty, isTrue);
    expect(vm.destination, 'Ollama (local) · ${ollama.model}');

    final failing = build(FailingSettingsRepository());
    await failing.load();
    await expectLater(failing.setUseThirdParty(true), throwsStateError);
    expect(failing.settings.useThirdParty, isFalse);
    expect(failing.destination, 'On-device model');
  });
}

class _ThrowingRepository extends InMemorySettingsRepository {
  _ThrowingRepository({this.failures = 1 << 30, ModelSettings? settings})
    : super(settings ?? const ModelSettings());

  int failures;

  @override
  Future<ModelSettings> load() async {
    if (failures-- > 0) throw StateError('corrupt');
    return settings;
  }
}
