import 'package:http/http.dart' as http;

import '../ai_exception.dart';
import '../language_model.dart';
import '../on_device_model.dart';
import '../remote/remote_model.dart';
import 'model_settings.dart';
import 'provider_presets.dart';

/// Turns the user's [ModelSettings] into the [LanguageModel] features run on.
///
/// There is no silent fallback in either direction: with third-party
/// providers off, the on-device model is used even if it is unavailable; with
/// them on, an incomplete selection fails with
/// [SystemLlmException.notConfigured] instead of quietly using another model.
final class ModelResolver {
  const ModelResolver({
    required this.keyStore,
    this.onDevice = const OnDeviceModel(),
    this.client,
    this.timeout = const Duration(seconds: 90),
  });

  final ApiKeyStore keyStore;
  final OnDeviceModel onDevice;

  /// Shared HTTP client for remote models; the caller owns and closes it.
  /// Without one, each remote model creates its own and releases it in
  /// [RemoteLanguageModel.close].
  final http.Client? client;
  final Duration timeout;

  Future<LanguageModel> resolve(ModelSettings settings) async {
    if (!settings.useThirdParty) return onDevice;
    final config = settings.selected;
    if (config == null || config.validate().isNotEmpty) {
      throw const SystemLlmException(SystemLlmException.notConfigured);
    }
    final apiKey = await keyStore.read(config.id);
    final needsKey =
        ProviderPresets.byId(config.presetId)?.requiresApiKey ?? false;
    if (needsKey && (apiKey == null || apiKey.trim().isEmpty)) {
      throw const SystemLlmException(SystemLlmException.notConfigured);
    }
    return RemoteLanguageModel.create(
      config,
      apiKey: apiKey,
      client: client,
      timeout: timeout,
    );
  }
}
