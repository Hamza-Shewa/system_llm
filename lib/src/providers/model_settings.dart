import 'provider_config.dart';

/// Where API keys live, keyed by [ProviderConfig.id]. Apps back this with the
/// platform's secure storage (Keychain, Keystore); keys never go into
/// [ModelSettings] or [ProviderConfig].
abstract interface class ApiKeyStore {
  Future<String?> read(String providerId);

  Future<void> write(String providerId, String apiKey);

  Future<void> delete(String providerId);
}

/// Keeps keys in memory only; for tests and previews.
final class InMemoryApiKeyStore implements ApiKeyStore {
  InMemoryApiKeyStore([Map<String, String>? keys]) : _keys = {...?keys};

  final Map<String, String> _keys;

  @override
  Future<String?> read(String providerId) async => _keys[providerId];

  @override
  Future<void> write(String providerId, String apiKey) async =>
      _keys[providerId] = apiKey;

  @override
  Future<void> delete(String providerId) async => _keys.remove(providerId);
}

/// The user's model choice: the on-device model, or one of their providers.
final class ModelSettings {
  const ModelSettings({
    this.useThirdParty = false,
    this.providers = const [],
    this.selectedProviderId,
  });

  /// Restores settings written by [toJson]. Entries that cannot be read are
  /// skipped rather than failing the whole settings.
  factory ModelSettings.fromJson(Map<String, Object?> json) {
    final providers = <ProviderConfig>[];
    final entries = json['providers'];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        try {
          providers.add(
            ProviderConfig.fromJson(Map<String, Object?>.from(entry)),
          );
        } on FormatException {
          continue;
        }
      }
    }
    final selected = json['selectedProviderId'];
    return ModelSettings(
      useThirdParty: json['useThirdParty'] == true,
      providers: List.unmodifiable(providers),
      selectedProviderId: selected is String ? selected : null,
    );
  }

  /// Off: features run on the on-device model and nothing leaves the device.
  final bool useThirdParty;
  final List<ProviderConfig> providers;
  final String? selectedProviderId;

  /// The chosen provider, if it still exists.
  ProviderConfig? get selected =>
      providers.where((p) => p.id == selectedProviderId).firstOrNull;

  ModelSettings copyWith({bool? useThirdParty, String? selectedProviderId}) =>
      ModelSettings(
        useThirdParty: useThirdParty ?? this.useThirdParty,
        providers: providers,
        selectedProviderId: selectedProviderId ?? this.selectedProviderId,
      );

  /// Adds [config], or replaces the entry with the same id. The first
  /// provider added becomes the selected one.
  ModelSettings withProvider(ProviderConfig config) {
    final index = providers.indexWhere((p) => p.id == config.id);
    final next = [...providers];
    if (index < 0) {
      next.add(config);
    } else {
      next[index] = config;
    }
    return ModelSettings(
      useThirdParty: useThirdParty,
      providers: List.unmodifiable(next),
      selectedProviderId: selectedProviderId ?? config.id,
    );
  }

  /// Removes the provider [id]; clears the selection if it was selected.
  ModelSettings withoutProvider(String id) => ModelSettings(
    useThirdParty: useThirdParty,
    providers: List.unmodifiable(providers.where((p) => p.id != id)),
    selectedProviderId: selectedProviderId == id ? null : selectedProviderId,
  );

  Map<String, Object?> toJson() => {
    'useThirdParty': useThirdParty,
    'providers': [for (final provider in providers) provider.toJson()],
    'selectedProviderId': ?selectedProviderId,
  };
}
