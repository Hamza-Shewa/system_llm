import 'package:http/http.dart' as http;
import 'package:system_llm/providers.dart';

/// Checks a provider entry before or after it is saved.
abstract interface class ProviderProbe {
  Future<AiAvailability> availability(ProviderConfig config, String? apiKey);

  /// Throws [SystemLlmException] when the provider cannot list its models.
  Future<List<String>> listModels(ProviderConfig config, String? apiKey);
}

/// Talks to the provider over HTTP.
final class HttpProviderProbe implements ProviderProbe {
  const HttpProviderProbe({this.client});

  final http.Client? client;

  Future<T> _with<T>(
    ProviderConfig config,
    String? apiKey,
    Future<T> Function(RemoteLanguageModel model) action,
  ) async {
    final model = RemoteLanguageModel.create(
      config,
      apiKey: apiKey,
      client: client,
    );
    try {
      return await action(model);
    } finally {
      model.close();
    }
  }

  @override
  Future<AiAvailability> availability(ProviderConfig config, String? apiKey) =>
      _with(config, apiKey, (model) => model.availability());

  @override
  Future<List<String>> listModels(ProviderConfig config, String? apiKey) =>
      _with(
        config,
        apiKey,
        (model) =>
            model.listModels(timeout: RemoteLanguageModel.availabilityTimeout),
      );
}
