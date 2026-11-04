import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/system_llm.dart';
import 'package:system_llm_example/main.dart';

void main() {
  testWidgets('shows the outcome of a call, including plugin errors', (
    tester,
  ) async {
    const channel = MethodChannel('system_llm');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'availability') return 'model_not_ready';
      throw PlatformException(code: 'busy');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Availability'));
    await tester.pumpAndSettle();
    expect(
      find.text('availability -> ${AiAvailability.modelNotReady.name}'),
      findsOneWidget,
    );

    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(find.text('generate -> error: busy'), findsOneWidget);
  });
}
