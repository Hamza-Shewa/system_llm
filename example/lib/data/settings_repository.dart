import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:system_llm/providers.dart';

/// Loads and saves the user's [ModelSettings].
abstract interface class SettingsRepository {
  Future<ModelSettings> load();

  Future<void> save(ModelSettings settings);
}

/// Keeps settings in the platform's secure storage. They hold no secrets,
/// but this keeps the example to one storage dependency.
final class SecureSettingsRepository implements SettingsRepository {
  const SecureSettingsRepository(this._storage);

  static const _key = 'system_llm.model_settings';

  final FlutterSecureStorage _storage;

  @override
  Future<ModelSettings> load() async {
    final text = await _storage.read(key: _key);
    if (text == null) return const ModelSettings();
    try {
      final json = jsonDecode(text);
      return json is Map
          ? ModelSettings.fromJson(Map<String, Object?>.from(json))
          : const ModelSettings();
    } on FormatException {
      return const ModelSettings();
    }
  }

  @override
  Future<void> save(ModelSettings settings) =>
      _storage.write(key: _key, value: jsonEncode(settings.toJson()));
}

/// Keeps settings in memory; for tests and previews.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this.settings = const ModelSettings()]);

  ModelSettings settings;
  int saves = 0;

  @override
  Future<ModelSettings> load() async => settings;

  @override
  Future<void> save(ModelSettings settings) async {
    this.settings = settings;
    saves++;
  }
}
