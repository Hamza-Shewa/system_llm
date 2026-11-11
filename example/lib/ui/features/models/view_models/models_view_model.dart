import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:system_llm/providers.dart';

import '../../../../data/provider_probe.dart';
import '../../../../data/settings_repository.dart';

/// The single source of the user's model choice, shared by the Models and
/// Chat screens.
class ModelsViewModel extends ChangeNotifier {
  ModelsViewModel({
    required this._repository,
    required this._keyStore,
    required this._probe,
    this._onDevice = const OnDeviceModel(),
    String Function()? newId,
  }) : _newId = newId ?? _randomId;

  final SettingsRepository _repository;
  final ApiKeyStore _keyStore;
  final ProviderProbe _probe;
  final LanguageModel _onDevice;
  final String Function() _newId;

  ModelSettings _settings = const ModelSettings();
  bool _loading = true;
  bool _loadFailed = false;
  AiAvailability? _onDeviceAvailability;
  final _availability = <String, AiAvailability>{};
  final _checking = <String>{};
  final _withKey = <String>{};

  ModelSettings get settings => _settings;
  bool get loading => _loading;

  /// The saved settings could not be read; defaults are shown instead.
  bool get loadFailed => _loadFailed;

  /// Null while it is being checked.
  AiAvailability? get onDeviceAvailability => _onDeviceAvailability;

  /// The last check of provider [id], if any.
  AiAvailability? availabilityOf(String id) => _availability[id];

  bool isChecking(String id) => _checking.contains(id);

  /// Whether provider [id] has an API key in the key store.
  bool hasSavedKey(String id) => _withKey.contains(id);

  /// Where prompts go with the current settings, for the user to see.
  String get destination {
    final selected = _settings.selected;
    if (!_settings.useThirdParty) return 'On-device model';
    if (selected == null) return 'No provider selected';
    return '${selected.name} · ${selected.model}';
  }

  String newProviderId() => _newId();

  Future<void> load() async {
    try {
      _settings = await _repository.load();
      for (final provider in _settings.providers) {
        final key = await _keyStore.read(provider.id);
        if (key != null && key.isNotEmpty) _withKey.add(provider.id);
      }
    } on Object catch (error) {
      // Settings hold no secrets, so the error is safe to log.
      debugPrint('Model settings could not be loaded: $error');
      _loadFailed = true;
    }
    _loading = false;
    notifyListeners();
    await checkOnDevice();
  }

  Future<void> checkOnDevice() async {
    _onDeviceAvailability = null;
    notifyListeners();
    _onDeviceAvailability = await _onDevice.availability();
    notifyListeners();
  }

  Future<void> setUseThirdParty(bool value) =>
      _update(_settings.copyWith(useThirdParty: value));

  Future<void> select(String id) =>
      _update(_settings.copyWith(selectedProviderId: id));

  /// Saves [config]. [apiKey]: null keeps the saved key, empty removes it.
  Future<void> saveProvider(ProviderConfig config, {String? apiKey}) async {
    if (apiKey != null) {
      if (apiKey.trim().isEmpty) {
        await _keyStore.delete(config.id);
        _withKey.remove(config.id);
      } else {
        await _keyStore.write(config.id, apiKey.trim());
        _withKey.add(config.id);
      }
    }
    _availability.remove(config.id);
    await _update(_settings.withProvider(config));
    unawaited(check(config));
  }

  Future<void> deleteProvider(String id) async {
    await _keyStore.delete(id);
    _withKey.remove(id);
    _availability.remove(id);
    await _update(_settings.withoutProvider(id));
  }

  /// Checks [config] with [apiKey], or with its saved key when null. The
  /// result is remembered for saved providers.
  Future<AiAvailability> check(ProviderConfig config, {String? apiKey}) async {
    _checking.add(config.id);
    notifyListeners();
    try {
      final result = await _probe.availability(
        config,
        apiKey ?? await _keyStore.read(config.id),
      );
      if (_settings.providers.any((p) => p.id == config.id)) {
        _availability[config.id] = result;
      }
      return result;
    } finally {
      _checking.remove(config.id);
      notifyListeners();
    }
  }

  /// Models served by [config]; throws [SystemLlmException].
  Future<List<String>> fetchModels(
    ProviderConfig config, {
    String? apiKey,
  }) async =>
      _probe.listModels(config, apiKey ?? await _keyStore.read(config.id));

  Future<void> _update(ModelSettings next) async {
    final previous = _settings;
    _settings = next;
    notifyListeners();
    try {
      await _repository.save(next);
    } on Object {
      _settings = previous;
      notifyListeners();
      rethrow;
    }
  }

  static String _randomId() {
    final random = Random.secure();
    return List.generate(
      12,
      (_) => random.nextInt(36).toRadixString(36),
    ).join();
  }
}
