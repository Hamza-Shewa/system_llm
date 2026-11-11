import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'data/provider_probe.dart';
import 'data/secure_api_key_store.dart';
import 'data/settings_repository.dart';
import 'ui/features/console/views/console_page.dart';
import 'ui/features/models/view_models/models_view_model.dart';
import 'ui/features/models/views/models_page.dart';

/// Composition root: the only place concrete storage and HTTP are chosen.
void main() {
  final client = http.Client();
  const storage = FlutterSecureStorage();
  final models = ModelsViewModel(
    repository: const SecureSettingsRepository(storage),
    keyStore: const SecureApiKeyStore(storage),
    probe: HttpProviderProbe(client: client),
  )..load();
  runApp(ExampleApp(models: models));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.models});

  final ModelsViewModel models;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'system_llm example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: AppShell(models: models),
  );
}

/// Bottom navigation between the example's screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.models});

  final ModelsViewModel models;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        ModelsPage(viewModel: widget.models),
        const ConsolePage(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (tab) => setState(() => _tab = tab),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.tune_outlined),
          selectedIcon: Icon(Icons.tune),
          label: 'Models',
        ),
        NavigationDestination(
          icon: Icon(Icons.terminal_outlined),
          selectedIcon: Icon(Icons.terminal),
          label: 'Console',
        ),
      ],
    ),
  );
}
