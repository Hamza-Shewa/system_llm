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

  Future<void> pumpStream(
    WidgetTester tester,
    void Function(MockStreamHandlerEventSink sink) onListen,
  ) async {
    const channel = EventChannel('system_llm/stream');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(onListen: (_, sink) => onListen(sink)),
    );
    addTearDown(() => messenger.setMockStreamHandler(channel, null));
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Stream'));
    // Platform-channel events need real time, not fake-async time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  testWidgets('stream joins the chunks as they arrive', (tester) async {
    await pumpStream(tester, (sink) {
      sink.success('Hel');
      sink.success('lo');
      sink.endOfStream();
    });
    expect(find.text('stream -> Hello'), findsOneWidget);
  });

  testWidgets('stream shows the error code from the platform', (tester) async {
    await pumpStream(tester, (sink) => sink.error(code: 'context_too_long'));
    expect(find.text('stream -> error: context_too_long'), findsOneWidget);
  });
}
