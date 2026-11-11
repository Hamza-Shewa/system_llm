import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/providers.dart';
import 'package:system_llm_example/data/settings_repository.dart';
import 'package:system_llm_example/ui/features/chat/view_models/chat_view_model.dart';
import 'package:system_llm_example/ui/features/chat/views/chat_page.dart';
import 'package:system_llm_example/ui/features/models/view_models/models_view_model.dart';

import 'support/fakes.dart';

void main() {
  final claude = ProviderPresets.anthropic.toConfig(id: 'c');
  late FakeLanguageModel model;
  late InMemorySettingsRepository repository;
  late ChatViewModel chat;
  var openedModels = 0;

  Future<void> pump(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
  }) async {
    final models = ModelsViewModel(
      repository: repository,
      keyStore: InMemoryApiKeyStore(),
      probe: FakeProbe(),
      onDevice: FakeLanguageModel(),
    );
    await models.load();
    chat = ChatViewModel(models: models, resolve: (_) async => model);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: ChatPage(viewModel: chat, onOpenModels: () => openedModels++),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.widgetWithText(TextField, 'Message'), text);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
  }

  setUp(() {
    model = FakeLanguageModel();
    repository = InMemorySettingsRepository();
    openedModels = 0;
  });

  testWidgets('empty state says the chat runs on the device', (tester) async {
    await pump(tester);
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(
      find.text('On-device model · messages stay on this device'),
      findsOneWidget,
    );
    await tester.tap(find.textContaining('On-device model'));
    expect(openedModels, 1);
  });

  testWidgets('names the host prompts are sent to', (tester) async {
    repository.settings = const ModelSettings(
      useThirdParty: true,
    ).withProvider(claude);
    await pump(tester);
    expect(
      find.text(
        'Anthropic (Claude) · ${claude.model} · messages are sent to '
        'api.anthropic.com',
      ),
      findsOneWidget,
    );
  });

  testWidgets('streams the answer, with Stop while it runs', (tester) async {
    final controller = StreamController<String>();
    model.onStream = (_) => controller.stream;
    await pump(tester);
    await type(tester, 'Hello?');
    expect(find.text('Hello?'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.bySemanticsLabel('Waiting for the answer'), findsOneWidget);

    controller.add('Hi ');
    await tester.pump();
    controller.add('there');
    await tester.pump();
    expect(find.text('Hi there'), findsOneWidget);

    await controller.close();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.text('Hi there'), findsOneWidget);
  });

  testWidgets('Stop ends the answer and keeps its text', (tester) async {
    final controller = StreamController<String>();
    model.onStream = (_) => controller.stream;
    await pump(tester);
    await type(tester, 'Long story');
    controller.add('Once upon');
    await tester.pump();
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Once upon'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(model.cancelCalls, 1);
    // Not awaited: after a cancel, the done future settles outside the fake clock.
    unawaited(controller.close());
  });

  testWidgets('shows a readable error with Retry', (tester) async {
    model.onStream = (_) =>
        Stream.error(const SystemLlmException(SystemLlmException.unauthorized));
    await pump(tester);
    await type(tester, 'hi');
    await tester.pumpAndSettle();
    expect(
      find.text('The provider rejected the API key. Check it under Models.'),
      findsOneWidget,
    );
    model.onStream = (_) => Stream.value('fixed');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('fixed'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('keeps the partial answer next to the error', (tester) async {
    model.onStream = (_) async* {
      yield 'Half an ans';
      throw const SystemLlmException(SystemLlmException.network);
    };
    await pump(tester);
    await type(tester, 'q');
    await tester.pumpAndSettle();
    expect(find.text('Half an ans'), findsOneWidget);
    expect(
      find.text(
        'Could not reach the provider. Check the connection and the address.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('offers Retry after stopping before any answer', (tester) async {
    final controller = StreamController<String>();
    model.onStream = (_) => controller.stream;
    await pump(tester);
    await type(tester, 'q');
    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Stopped before an answer.'), findsOneWidget);
    model.onStream = (_) => Stream.value('now');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('now'), findsOneWidget);
    unawaited(controller.close());
  });

  testWidgets('keeps typed text that cannot be sent while answering', (
    tester,
  ) async {
    final controller = StreamController<String>();
    model.onStream = (_) => controller.stream;
    await pump(tester);
    await type(tester, 'first');
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'second');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    expect(chat.messages, const [AiMessage.user('first')]);
    unawaited(controller.close());
  });

  testWidgets('tells screen readers who wrote each message', (tester) async {
    model.onStream = (_) => Stream.value('Hi');
    await pump(tester);
    await type(tester, 'Hello');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^You')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Assistant')), findsOneWidget);
  });

  testWidgets('clears the conversation', (tester) async {
    model.onStream = (_) => Stream.value('answer');
    await pump(tester);
    await type(tester, 'q');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear chat'));
    await tester.pumpAndSettle();
    expect(find.text('Start a conversation'), findsOneWidget);
  });

  testWidgets('right-to-left puts the user bubble on the left', (tester) async {
    model.onStream = (_) => Stream.value('أهلاً');
    await pump(tester, direction: TextDirection.rtl);
    await type(tester, 'مرحبا');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final width = tester.getSize(find.byType(ChatPage)).width;
    expect(tester.getCenter(find.text('مرحبا')).dx, lessThan(width / 2));
    expect(tester.getCenter(find.text('أهلاً')).dx, greaterThan(width / 2));
  });
}
