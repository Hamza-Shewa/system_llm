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

/// Opens the editor's provider dropdown and picks [name].
Future<void> pickPreset(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  // The open menu is the last Scrollable; the button keeps hidden copies of
  // every item, so a plain text finder can hit the wrong one.
  final menu = find.byType(Scrollable).last;
  final item = find.descendant(of: menu, matching: find.text(name));
  await tester.scrollUntilVisible(item, 100, scrollable: menu);
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> scrollEditorTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ProviderEditorPage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

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
    await pickPreset(tester, 'Custom endpoint');
    expect(fieldText(tester, 'Name'), '', reason: 'custom starts blank');
    expect(
      find.text('OpenAI-compatible'),
      findsNothing,
      reason: 'protocol choice sits under Advanced',
    );

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
    await pickPreset(tester, 'Ollama (local)');
    await scrollEditorTo(tester, find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Server unreachable'), findsOneWidget);
    expect(probe.checkedKeys.single, '', reason: 'no key for a new entry');
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

  testWidgets('switching preset clears a typed key', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'API key'), 'sk-1');
    await pickPreset(tester, 'Groq');
    expect(fieldText(tester, 'API key'), '');
  });

  testWidgets('a saved key is not reused after the address changes', (
    tester,
  ) async {
    final openAi = ProviderPresets.openAi.toConfig(id: 'c');
    repository.settings = const ModelSettings().withProvider(openAi);
    await keys.write('c', 'sk-saved');
    await pump(tester);
    await tester.tap(find.byTooltip('Actions for OpenAI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      'https://other.example/v1',
    );
    await tester.pump();
    await scrollEditorTo(tester, find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(probe.checkedKeys, isEmpty);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter the API key again for the new address.'),
      findsOneWidget,
    );
    expect(repository.settings.providers.single, openAi);
  });

  testWidgets('removes a saved key', (tester) async {
    repository.settings = const ModelSettings().withProvider(ollama);
    await keys.write('o', 'local-key');
    await pump(tester);
    await tester.tap(find.byTooltip('Actions for Ollama (local)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove saved key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await keys.read('o'), isNull);
  });

  testWidgets('a keychain failure during a test does not leave a spinner', (
    tester,
  ) async {
    repository.settings = const ModelSettings().withProvider(ollama);
    final store = ThrowingKeyStore(failing: false, keys: {'o': 'k'});
    final vm = ModelsViewModel(
      repository: repository,
      keyStore: store,
      probe: probe,
      onDevice: FakeLanguageModel(),
    );
    await vm.load();
    await pump(tester, vm: vm);
    store.failing = true;
    await tester.tap(find.byTooltip('Actions for Ollama (local)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await scrollEditorTo(tester, find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Could not check the connection.'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Test connection'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(button.onPressed, isNotNull);
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
