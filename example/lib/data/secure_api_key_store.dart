import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:system_llm/providers.dart';

/// API keys in the Keychain (iOS) or Keystore-backed storage (Android).
final class SecureApiKeyStore implements ApiKeyStore {
  const SecureApiKeyStore(this._storage);

  final FlutterSecureStorage _storage;

  String _key(String providerId) => 'system_llm.api_key.$providerId';

  @override
  Future<String?> read(String providerId) =>
      _storage.read(key: _key(providerId));

  @override
  Future<void> write(String providerId, String apiKey) =>
      _storage.write(key: _key(providerId), value: apiKey);

  @override
  Future<void> delete(String providerId) =>
      _storage.delete(key: _key(providerId));
}
