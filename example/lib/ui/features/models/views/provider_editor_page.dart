import 'package:flutter/material.dart';
import 'package:system_llm/providers.dart';

import '../../../core/labels.dart';
import '../view_models/models_view_model.dart';

/// Adds a provider from a preset or from scratch, or edits a saved one.
class ProviderEditorPage extends StatefulWidget {
  const ProviderEditorPage({super.key, required this.viewModel, this.initial});

  final ModelsViewModel viewModel;

  /// The provider being edited; null to add a new one.
  final ProviderConfig? initial;

  @override
  State<ProviderEditorPage> createState() => _ProviderEditorPageState();
}

class _ProviderEditorPageState extends State<ProviderEditorPage> {
  static const _custom = 'custom';

  late final String _id;
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();

  ProviderPreset? _preset;
  var _protocol = ProviderProtocol.openAiCompatible;
  var _structuredOutput = StructuredOutputMode.jsonSchema;
  var _maxTokensField = MaxTokensField.maxTokens;

  var _obscureKey = true;
  var _submitted = false;
  var _saving = false;
  var _testing = false;
  var _fetching = false;
  AiAvailability? _testResult;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) {
      _id = widget.viewModel.newProviderId();
      _applyPreset(ProviderPresets.all.first);
    } else {
      _id = initial.id;
      _preset = ProviderPresets.byId(initial.presetId);
      _name.text = initial.name;
      _baseUrl.text = initial.baseUrl;
      _model.text = initial.model;
      _protocol = initial.protocol;
      _structuredOutput = initial.structuredOutput;
      _maxTokensField = initial.maxTokensField;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  void _applyPreset(ProviderPreset? preset) {
    _preset = preset;
    _testResult = null;
    if (preset == null) {
      _name.text = '';
      _baseUrl.text = 'https://';
      _model.text = '';
      _protocol = ProviderProtocol.openAiCompatible;
      _structuredOutput = StructuredOutputMode.jsonSchema;
      _maxTokensField = MaxTokensField.maxTokens;
      return;
    }
    final config = preset.toConfig(id: 'preview');
    _name.text = config.name;
    _baseUrl.text = config.baseUrl;
    _model.text = config.model;
    _protocol = config.protocol;
    _structuredOutput = config.structuredOutput;
    _maxTokensField = config.maxTokensField;
  }

  ProviderConfig get _draft => ProviderConfig(
    id: _id,
    name: _name.text.trim(),
    protocol: _protocol,
    baseUrl: _baseUrl.text.trim(),
    model: _model.text.trim(),
    presetId: _preset?.id,
    structuredOutput: _structuredOutput,
    maxTokensField: _maxTokensField,
  );

  /// The key typed in the field; null keeps the saved one.
  String? get _typedKey => _apiKey.text.trim().isEmpty ? null : _apiKey.text;

  bool get _keyMissing =>
      (_preset?.requiresApiKey ?? false) &&
      _typedKey == null &&
      !widget.viewModel.hasSavedKey(_id);

  List<ProviderConfigError> get _errors => _draft.validate();

  String? _errorFor(List<ProviderConfigError> kinds) {
    if (!_submitted) return null;
    final error = _errors.where(kinds.contains).firstOrNull;
    return error == null ? null : configErrorLabel(error);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_errors.isNotEmpty || _keyMissing) return;
    setState(() => _saving = true);
    try {
      await widget.viewModel.saveProvider(_draft, apiKey: _typedKey);
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the provider.')),
      );
    }
  }

  Future<void> _test() async {
    setState(() => _submitted = true);
    if (_errors.isNotEmpty || _keyMissing) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await widget.viewModel.check(_draft, apiKey: _typedKey);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _fetchModels() async {
    final urlErrors = _errors.where(
      (e) =>
          e == ProviderConfigError.baseUrlInvalid ||
          e == ProviderConfigError.insecureBaseUrl,
    );
    if (urlErrors.isNotEmpty) {
      setState(() => _submitted = true);
      return;
    }
    setState(() => _fetching = true);
    List<String>? models;
    String? failure;
    try {
      models = await widget.viewModel.fetchModels(_draft, apiKey: _typedKey);
    } on SystemLlmException catch (error) {
      failure = errorMessage(error.code);
    }
    if (!mounted) return;
    setState(() => _fetching = false);
    if (failure != null || models == null || models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure ?? 'The provider listed no models.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ModelPicker(models: models!),
    );
    if (picked != null) setState(() => _model.text = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _preset;
    final requiresKey = preset?.requiresApiKey ?? false;
    final savedKey = widget.viewModel.hasSavedKey(_id);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add provider' : 'Edit provider'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(16),
        children: [
          if (_isNew)
            DropdownButtonFormField<String>(
              initialValue: preset?.id ?? _custom,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: [
                for (final p in ProviderPresets.all)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
                const DropdownMenuItem(
                  value: _custom,
                  child: Text('Custom endpoint'),
                ),
              ],
              onChanged: (id) =>
                  setState(() => _applyPreset(ProviderPresets.byId(id))),
            )
          else
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Provider'),
              child: Text(preset?.name ?? 'Custom endpoint'),
            ),
          if (preset?.note case final note?) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _errorFor([ProviderConfigError.nameMissing]),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseUrl,
            decoration: InputDecoration(
              labelText: 'Base URL',
              helperText: 'The API root, for example https://api.openai.com/v1',
              errorText: _errorFor([
                ProviderConfigError.baseUrlInvalid,
                ProviderConfigError.insecureBaseUrl,
              ]),
              errorMaxLines: 3,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _testResult = null),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKey,
            obscureText: _obscureKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: requiresKey ? 'API key' : 'API key (optional)',
              helperText: savedKey
                  ? 'A key is saved. Leave empty to keep it.'
                  : preset?.apiKeyUrl == null
                  ? 'Stored in the device keychain, never in settings.'
                  : 'Create one at ${preset!.apiKeyUrl}',
              helperMaxLines: 2,
              errorText: _submitted && _keyMissing
                  ? 'This provider needs an API key.'
                  : null,
              suffixIcon: IconButton(
                tooltip: _obscureKey ? 'Show key' : 'Hide key',
                icon: Icon(
                  _obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            onChanged: (_) => setState(() => _testResult = null),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Model',
              errorText: _errorFor([ProviderConfigError.modelMissing]),
              suffixIcon: _fetching
                  ? const Padding(
                      padding: EdgeInsetsDirectional.all(14),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Fetch models',
                      icon: const Icon(Icons.list_alt_outlined),
                      onPressed: _fetchModels,
                    ),
            ),
            onChanged: (_) => setState(() => _testResult = null),
          ),
          if (preset != null && preset.suggestedModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final model in preset.suggestedModels)
                  ChoiceChip(
                    label: Text(model),
                    selected: _model.text.trim() == model,
                    onSelected: (_) => setState(() {
                      _model.text = model;
                      _testResult = null;
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsetsDirectional.zero,
            title: const Text('Advanced'),
            children: [
              if (preset == null) ...[
                SegmentedButton<ProviderProtocol>(
                  segments: [
                    for (final protocol in ProviderProtocol.values)
                      ButtonSegment(
                        value: protocol,
                        label: Text(protocolLabel(protocol)),
                      ),
                  ],
                  selected: {_protocol},
                  onSelectionChanged: (value) =>
                      setState(() => _protocol = value.single),
                ),
                const SizedBox(height: 16),
              ],
              if (_protocol == ProviderProtocol.openAiCompatible) ...[
                DropdownButtonFormField<StructuredOutputMode>(
                  initialValue: _structuredOutput,
                  decoration: const InputDecoration(
                    labelText: 'Structured output',
                    helperText: 'How JSON answers are requested.',
                  ),
                  items: [
                    for (final mode in StructuredOutputMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(structuredOutputLabel(mode)),
                      ),
                  ],
                  onChanged: (mode) => setState(
                    () => _structuredOutput = mode ?? _structuredOutput,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<MaxTokensField>(
                  initialValue: _maxTokensField,
                  decoration: const InputDecoration(
                    labelText: 'Token limit field',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: MaxTokensField.maxTokens,
                      child: Text('max_tokens'),
                    ),
                    DropdownMenuItem(
                      value: MaxTokensField.maxCompletionTokens,
                      child: Text('max_completion_tokens'),
                    ),
                  ],
                  onChanged: (field) => setState(
                    () => _maxTokensField = field ?? _maxTokensField,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: const Text('Test connection'),
          ),
          if (_testResult case final result?) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  availabilityIcon(result),
                  color: result.canGenerate
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.canGenerate
                        ? 'Connected. The model is available.'
                        : availabilityLabel(result),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A searchable list of the provider's models.
class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models});

  final List<String> models;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.models
        .where((m) => m.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
              child: TextField(
                autofocus: widget.models.length > 12,
                decoration: const InputDecoration(
                  labelText: 'Search models',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(visible[index]),
                  onTap: () => Navigator.pop(context, visible[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
