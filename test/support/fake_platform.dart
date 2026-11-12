import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:system_llm/system_llm.dart';

class FakePlatform extends SystemLlmPlatform with MockPlatformInterfaceMixin {
  Future<String?> Function(String locale) onAvailability = (_) async =>
      'available';
  Future<String?> Function() onGenerate = () async => '{"queries":["a"]}';
  Future<bool?> Function() onSpeechAvailable = () async => true;
  Future<Map<Object?, Object?>?> Function(List<String>) onEnvironment =
      (_) async => null;
  Stream<String> Function() onStream = () => const Stream.empty();
  int cancelCalls = 0;
  Map<String, Object?>? lastSchema;
  int? lastMaxTokens;
  String? lastInstructions;
  String? lastInput;
  String? lastLocale;

  @override
  Future<String?> availability(String locale) => onAvailability(locale);

  @override
  Future<String?> generateObject({
    required String instructions,
    required String input,
    required String locale,
    required Map<String, Object?> schema,
    required int maxTokens,
  }) {
    lastSchema = schema;
    lastMaxTokens = maxTokens;
    lastInstructions = instructions;
    lastInput = input;
    lastLocale = locale;
    return onGenerate();
  }

  @override
  Stream<String> streamText({
    required String instructions,
    required String input,
    required String locale,
    required int maxTokens,
  }) {
    lastMaxTokens = maxTokens;
    lastInstructions = instructions;
    lastInput = input;
    lastLocale = locale;
    return onStream();
  }

  @override
  Future<bool?> speechAvailable(String locale) => onSpeechAvailable();

  @override
  Future<String?> listen(String locale) async => 'hello';

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<Map<Object?, Object?>?> environment(List<String> directories) =>
      onEnvironment(directories);
}
