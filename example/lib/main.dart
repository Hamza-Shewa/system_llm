import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:system_llm/providers.dart';

import 'data/provider_probe.dart';
import 'data/secure_api_key_store.dart';
import 'data/settings_repository.dart';
import 'ui/features/chat/view_models/chat_view_model.dart';
import 'ui/features/chat/views/chat_page.dart';
import 'ui/features/console/views/console_page.dart';
import 'ui/features/models/view_models/models_view_model.dart';
import 'ui/features/models/views/models_page.dart';

/// Composition root: the only place concrete storage and HTTP are chosen.
void main() {
  // Storage is read before runApp, which needs the binding for its channel.
  WidgetsFlutterBinding.ensureInitialized();
  final client = http.Client();
  const storage = FlutterSecureStorage();
  const keys = SecureApiKeyStore(storage);
  final models = ModelsViewModel(
    repository: const SecureSettingsRepository(storage),
    keyStore: keys,
    probe: HttpProviderProbe(client: client),
  )..load();
  final resolver = ModelResolver(keyStore: keys, client: client);
  final chat = ChatViewModel(models: models, resolve: resolver.resolve);
  runApp(ExampleApp(models: models, chat: chat));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.models, required this.chat});

  final ModelsViewModel models;
  final ChatViewModel chat;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'system_llm example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: AppShell(models: models, chat: chat),
  );
}

/// Bottom navigation between the example's screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.models, required this.chat});

  final ModelsViewModel models;
  final ChatViewModel chat;

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
        ChatPage(
          viewModel: widget.chat,
          onOpenModels: () => setState(() => _tab = 1),
        ),
        ModelsPage(viewModel: widget.models),
        const ConsolePage(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (tab) => setState(() => _tab = tab),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'Chat',
        ),
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
