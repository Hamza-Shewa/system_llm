import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_interface.dart';

/// [SystemLlmPlatform] backed by a [MethodChannel].
class MethodChannelSystemLlm extends SystemLlmPlatform {
  @visibleForTesting
  static const channelName = 'system_llm';

  @visibleForTesting
  static const streamChannelName = 'system_llm/stream';

  @visibleForTesting
  final methodChannel = const MethodChannel(channelName);

  @visibleForTesting
  final streamChannel = const EventChannel(streamChannelName);

  @override
  Future<String?> availability(String locale) =>
      methodChannel.invokeMethod<String>('availability', {'locale': locale});

  @override
  Future<String?> generateObject({
    required String instructions,
    required String input,
    required String locale,
    required Map<String, Object?> schema,
    required int maxTokens,
  }) => methodChannel.invokeMethod<String>('generateObject', {
    'instructions': instructions,
    'input': input,
    'locale': locale,
    'schema': schema,
    'maxTokens': maxTokens,
  });

  @override
  Stream<String> streamText({
    required String instructions,
    required String input,
    required String locale,
    required int maxTokens,
  }) => streamChannel.receiveBroadcastStream({
    'instructions': instructions,
    'input': input,
    'locale': locale,
    'maxTokens': maxTokens,
  }).cast<String>();

  @override
  Future<bool?> speechAvailable(String locale) =>
      methodChannel.invokeMethod<bool>('speechAvailable', {'locale': locale});

  @override
  Future<String?> listen(String locale) =>
      methodChannel.invokeMethod<String>('listen', {'locale': locale});

  @override
  Future<void> stopListening() =>
      methodChannel.invokeMethod<void>('stopListening');

  @override
  Future<void> cancel() => methodChannel.invokeMethod<void>('cancel');

  @override
  Future<Map<Object?, Object?>?> environment(List<String> directories) =>
      methodChannel.invokeMapMethod<Object?, Object?>('environment', {
        'directories': directories,
      });
}
