import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/providers.dart';
import 'package:system_llm_example/data/settings_repository.dart';
import 'package:system_llm_example/ui/features/models/view_models/models_view_model.dart';
import 'package:system_llm_example/ui/features/models/views/models_page.dart';
import 'package:system_llm_example/ui/features/models/views/provider_editor_page.dart';

import 'support/fakes.dart';

String fieldText(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  final ollama = ProviderPresets.ollama.toConfig(id: 'o');
  late InMemorySettingsRepository repository;
  late InMemoryApiKeyStore keys;
  late FakeProbe probe;

  ModelsViewModel viewModel([SettingsRepository? repo]) => ModelsViewModel(
    repository: repo ?? repository,
    keyStore: keys,
    probe: probe,
    onDevice: FakeLanguageModel(),
    newId: () => 'new-id',
  );

  Future<ModelsViewModel> pump(
    WidgetTester tester, {
    ModelsViewModel? vm,
    TextDirection direction = TextDirection.ltr,
  }) async {
    final model = vm ?? viewModel();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: ModelsPage(viewModel: model),
      ),
    );
    if (vm == null) await model.load();
    await tester.pumpAndSettle();
    return model;
  }

  setUp(() {
    repository = InMemorySettingsRepository();
    keys = InMemoryApiKeyStore();
    probe = FakeProbe();
  });

  testWidgets('shows a loader until settings are read', (tester) async {
    final pending = PendingSettingsRepository();
    final vm = viewModel(pending);
    final load = vm.load();
    await tester.pumpWidget(MaterialApp(home: ModelsPage(viewModel: vm)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete();
    await load;
    await tester.pumpAndSettle();
    expect(find.text('No providers yet'), findsOneWidget);
  });

  testWidgets('empty state, on-device status and the toggle', (tester) async {
    await pump(tester);
    expect(find.text('No providers yet'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(
      find.text('Off: everything runs on the on-device model.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      find.text('Prompts are sent to the selected provider.'),
      findsOneWidget,
    );
    expect(repository.settings.useThirdParty, isTrue);
  });

  testWidgets('reports a settings read failure with a retry', (tester) async {
    final vm = viewModel(_ThrowingRepository());
    await vm.load();
    await pump(tester, vm: vm);
    expect(
      find.text('Saved settings could not be read. Defaults are shown.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('lists providers and selects one', (tester) async {
    final lmStudio = ProviderPresets.lmStudio.toConfig(id: 'l', model: 'm1');
    repository.settings = const ModelSettings()
        .withProvider(ollama)
        .withProvider(lmStudio);
    final vm = await pump(tester);
    expect(find.text('Ollama (local)'), findsOneWidget);
    expect(find.text('${ollama.model} · localhost'), findsOneWidget);
    expect(vm.settings.selectedProviderId, 'o');

    await tester.tap(find.text('LM Studio (local)'));
    await tester.pumpAndSettle();
    expect(repository.settings.selectedProviderId, 'l');
  });

  testWidgets('adds a preset provider, requiring its API key', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'Name'), 'OpenAI');
    expect(fieldText(tester, 'Base URL'), 'https://api.openai.com/v1');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('This provider needs an API key.'), findsOneWidget);
    expect(repository.settings.providers, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'API key'),
      'sk-test',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Models'), findsOneWidget);
    final saved = repository.settings.providers.single;
    expect(saved.presetId, 'openai');
    expect(saved.model, ProviderPresets.openAi.suggestedModels.first);
    expect(await keys.read('new-id'), 'sk-test');
    expect(find.text('OpenAI'), findsOneWidget);
  });

  testWidgets('refuses plain http to a public custom endpoint', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom endpoint').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mine');
    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      'http://8.8.8.8/v1',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'x');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Use https:// for internet hosts'),
      findsOneWidget,
    );
    expect(repository.settings.providers, isEmpty);
  });

  testWidgets('tests the connection and shows the result', (tester) async {
    probe.result = AiAvailability.unreachable;
    await pump(tester);
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ollama (local)').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Test connection'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ProviderEditorPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Server unreachable'), findsOneWidget);
    expect(probe.checkedKeys.single, isNull);
  });

  testWidgets('picks a model from the fetched list', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fetch models'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('model-b'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Model'))
          .controller!
          .text,
      'model-b',
    );
  });

  testWidgets('deletes a provider after confirmation', (tester) async {
    repository.settings = const ModelSettings().withProvider(ollama);
    await pump(tester);
    await tester.tap(find.byTooltip('Actions for Ollama (local)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Ollama (local)?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repository.settings.providers, isEmpty);
    expect(find.text('No providers yet'), findsOneWidget);
  });

  testWidgets('mirrors the layout right-to-left without overflow', (
    tester,
  ) async {
    repository.settings = const ModelSettings().withProvider(ollama);
    await pump(tester, direction: TextDirection.rtl);
    expect(tester.takeException(), isNull);
    final radio = tester.getCenter(find.byType(Radio<String>));
    final title = tester.getCenter(find.text('Ollama (local)'));
    expect(radio.dx, greaterThan(title.dx));
  });
}

class _ThrowingRepository extends InMemorySettingsRepository {
  @override
  Future<ModelSettings> load() async => throw StateError('corrupt');
}
