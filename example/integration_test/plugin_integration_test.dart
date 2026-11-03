// Runs on a real device or simulator: `flutter test integration_test` from
// the example directory. It only checks calls that need no model or microphone.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:system_llm/system_llm.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const ai = SystemLlm();

  testWidgets('availability answers without throwing', (tester) async {
    expect(AiAvailability.values, contains(await ai.availability('en')));
  });

  testWidgets('environment creates a backup-excluded directory', (
    tester,
  ) async {
    final env = await ai.environment(directories: const ['integration_test']);
    expect(env.directories['integration_test'], isNotEmpty);
    expect(env.memoryBytes, greaterThan(0));
  });

  testWidgets('cancel with nothing running is a no-op', (tester) async {
    await ai.cancel();
  });
}
