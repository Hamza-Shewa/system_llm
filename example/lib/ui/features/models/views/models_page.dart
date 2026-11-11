import 'package:flutter/material.dart';
import 'package:system_llm/providers.dart';

import '../../../core/labels.dart';
import '../view_models/models_view_model.dart';
import 'provider_editor_page.dart';

/// Chooses which model features run on: the on-device model, or one of the
/// user's third-party providers.
class ModelsPage extends StatelessWidget {
  const ModelsPage({super.key, required this.viewModel});

  final ModelsViewModel viewModel;

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action, {
    String failure = 'Could not save the change. Try again.',
  }) async {
    try {
      await action();
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _openEditor(BuildContext context, [ProviderConfig? config]) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProviderEditorPage(viewModel: viewModel, initial: config),
        ),
      );

  Future<void> _confirmDelete(
    BuildContext context,
    ProviderConfig config,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${config.name}?'),
        content: const Text(
          'The provider and its saved API key are removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _guard(context, () => viewModel.deleteProvider(config.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Models')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Add provider'),
      ),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          if (viewModel.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final settings = viewModel.settings;
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsetsDirectional.only(bottom: 96),
            children: [
              if (viewModel.loadFailed)
                MaterialBanner(
                  content: const Text(
                    'Saved settings could not be read. Defaults are shown.',
                  ),
                  leading: const Icon(Icons.warning_amber_outlined),
                  actions: [
                    TextButton(
                      onPressed: viewModel.load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('On-device model'),
                subtitle: const Text(
                  'Private: prompts never leave the device.',
                ),
                trailing: _AvailabilityChip(
                  availability: viewModel.onDeviceAvailability,
                  checking: viewModel.onDeviceAvailability == null,
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.cloud_outlined),
                title: const Text('Use a third-party provider'),
                subtitle: Text(
                  settings.useThirdParty
                      ? 'Prompts are sent to the selected provider.'
                      : 'Off: everything runs on the on-device model.',
                ),
                value: settings.useThirdParty,
                onChanged: (value) =>
                    _guard(context, () => viewModel.setUseThirdParty(value)),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
                child: Text('Providers', style: theme.textTheme.titleSmall),
              ),
              if (settings.providers.isEmpty)
                const _EmptyProviders()
              else
                RadioGroup<String>(
                  groupValue: settings.selectedProviderId,
                  onChanged: (id) {
                    if (id != null) _guard(context, () => viewModel.select(id));
                  },
                  child: Column(
                    children: [
                      for (final provider in settings.providers)
                        _ProviderTile(
                          provider: provider,
                          availability: viewModel.availabilityOf(provider.id),
                          checking: viewModel.isChecking(provider.id),
                          onEdit: () => _openEditor(context, provider),
                          onCheck: () => _guard(
                            context,
                            () => viewModel.check(provider),
                            failure: 'Could not check the connection.',
                          ),
                          onDelete: () => _confirmDelete(context, provider),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyProviders extends StatelessWidget {
  const _EmptyProviders();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 16,
        vertical: 24,
      ),
      child: Column(
        children: [
          Icon(
            Icons.hub_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No providers yet',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Add OpenAI, Claude, Gemini, Qwen, a local Ollama server or '
            'your own endpoint.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

enum _ProviderAction { edit, check, delete }

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.availability,
    required this.checking,
    required this.onEdit,
    required this.onCheck,
    required this.onDelete,
  });

  final ProviderConfig provider;
  final AiAvailability? availability;
  final bool checking;
  final VoidCallback onEdit;
  final VoidCallback onCheck;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      value: provider.id,
      title: Text(provider.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${provider.model} · ${provider.host}'),
          if (availability != null || checking) ...[
            const SizedBox(height: 4),
            _AvailabilityChip(availability: availability, checking: checking),
          ],
        ],
      ),
      isThreeLine: availability != null || checking,
      secondary: PopupMenuButton<_ProviderAction>(
        tooltip: 'Actions for ${provider.name}',
        onSelected: (action) => switch (action) {
          _ProviderAction.edit => onEdit(),
          _ProviderAction.check => onCheck(),
          _ProviderAction.delete => onDelete(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _ProviderAction.edit, child: Text('Edit')),
          PopupMenuItem(
            value: _ProviderAction.check,
            child: Text('Check connection'),
          ),
          PopupMenuItem(value: _ProviderAction.delete, child: Text('Delete')),
        ],
      ),
    );
  }
}

/// Icon plus text, so the state never relies on colour alone.
class _AvailabilityChip extends StatelessWidget {
  const _AvailabilityChip({required this.availability, required this.checking});

  final AiAvailability? availability;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final availability = this.availability;
    if (checking || availability == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text('Checking…', style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      );
    }
    final color = availability.canGenerate ? scheme.primary : scheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(availabilityIcon(availability), size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            availabilityLabel(availability),
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
