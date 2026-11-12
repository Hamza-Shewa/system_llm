import 'dart:async';

import 'package:system_llm/providers.dart';
import 'package:system_llm_example/data/provider_probe.dart';
import 'package:system_llm_example/data/settings_repository.dart';

/// A [LanguageModel] driven by the test.
class FakeLanguageModel implements LanguageModel {
  FakeLanguageModel({
    this.id = 'fake',
    this.displayName = 'Fake model',
    this.isOnDevice = true,
    this.availabilityResult = AiAvailability.available,
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  final bool isOnDevice;

  AiAvailability availabilityResult;
  Stream<String> Function(List<AiMessage> messages) onStream = (_) =>
      const Stream.empty();
  final streamRequests = <List<AiMessage>>[];
  String? lastInstructions;
  int cancelCalls = 0;

  @override
  Future<AiAvailability> availability({String locale = 'en'}) async =>
      availabilityResult;

  @override
  Future<Map<String, Object?>> generateObject({
    required String instructions,
    required List<AiMessage> messages,
    required AiSchema schema,
    String locale = 'en',
    int maxTokens = 512,
  }) => throw UnimplementedError();

  @override
  Stream<String> streamText({
    required String instructions,
    required List<AiMessage> messages,
    String locale = 'en',
    int maxTokens = 512,
  }) {
    lastInstructions = instructions;
    streamRequests.add(List.of(messages));
    return onStream(messages);
  }

  @override
  Future<void> cancel() async => cancelCalls++;
}

/// A [ProviderProbe] answering from fields.
class FakeProbe implements ProviderProbe {
  AiAvailability result = AiAvailability.available;
  List<String> models = const ['model-a', 'model-b'];
  SystemLlmException? listError;
  final checkedKeys = <String?>[];

  @override
  Future<AiAvailability> availability(
    ProviderConfig config,
    String? apiKey,
  ) async {
    checkedKeys.add(apiKey);
    return result;
  }

  @override
  Future<List<String>> listModels(ProviderConfig config, String? apiKey) async {
    if (listError case final error?) throw error;
    return models;
  }
}

/// A repository whose saves fail.
class FailingSettingsRepository extends InMemorySettingsRepository {
  @override
  Future<void> save(ModelSettings settings) async =>
      throw StateError('disk full');
}

/// A repository whose load never completes until [complete] is called.
class PendingSettingsRepository implements SettingsRepository {
  final _load = Completer<ModelSettings>();

  void complete([ModelSettings settings = const ModelSettings()]) =>
      _load.complete(settings);

  @override
  Future<ModelSettings> load() => _load.future;

  @override
  Future<void> save(ModelSettings settings) async {}
}

/// A key store whose reads and writes fail while [failing], as a locked or
/// broken keychain would.
class ThrowingKeyStore implements ApiKeyStore {
  ThrowingKeyStore({this.failing = true, Map<String, String>? keys})
    : keys = {...?keys};

  bool failing;
  final Map<String, String> keys;

  @override
  Future<String?> read(String providerId) async =>
      failing ? throw StateError('keychain locked') : keys[providerId];

  @override
  Future<void> write(String providerId, String apiKey) async =>
      failing ? throw StateError('keychain locked') : keys[providerId] = apiKey;

  @override
  Future<void> delete(String providerId) async {}
}
