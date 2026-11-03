import 'package:flutter/material.dart';
import 'package:system_llm/system_llm.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'system_llm example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const ConsolePage(),
  );
}

/// One button per capability, for checking the native code on a real device.
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key, this.ai = const SystemLlm()});

  final SystemLlm ai;

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  static const _schema = AiSchema.object({
    'queries': AiSchema.array(
      AiSchema.string(),
      maxItems: 5,
      description: 'Short search phrases',
    ),
    'message': AiSchema.string(description: 'One short sentence'),
  });

  final _locale = TextEditingController(text: 'en');
  final _input = TextEditingController(text: 'I want a vacation abroad');
  final _log = <String>[];
  bool _busy = false;

  @override
  void dispose() {
    _locale.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<Object?> Function() action) async {
    setState(() {
      _busy = true;
      _log.insert(0, '$label ...');
    });
    String outcome;
    try {
      outcome = '${await action()}';
    } on SystemLlmException catch (error) {
      outcome = 'error: ${error.code}';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _log[0] = '$label -> $outcome';
    });
  }

  /// Shows the answer growing as chunks arrive.
  Future<void> _stream() async {
    setState(() {
      _busy = true;
      _log.insert(0, 'stream ...');
    });
    final text = StringBuffer();
    String outcome;
    try {
      await for (final chunk in widget.ai.streamText(
        instructions: 'Answer in one short paragraph.',
        input: _input.text,
        locale: _locale.text.trim(),
      )) {
        text.write(chunk);
        if (!mounted) return;
        setState(() => _log[0] = 'stream ... $text');
      }
      outcome = '$text';
    } on SystemLlmException catch (error) {
      outcome = 'error: ${error.code}';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _log[0] = 'stream -> $outcome';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ai = widget.ai;
    final locale = _locale.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('system_llm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _locale,
            decoration: const InputDecoration(labelText: 'Locale'),
          ),
          TextField(
            controller: _input,
            decoration: const InputDecoration(labelText: 'Request'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        'availability',
                        () async => (await ai.availability(locale)).name,
                      ),
                child: const Text('Availability'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        'generate',
                        () => ai.generateObject(
                          instructions:
                              'Extract short search phrases for the goal.',
                          input: _input.text,
                          schema: _schema,
                          locale: locale,
                        ),
                      ),
                child: const Text('Generate'),
              ),
              FilledButton(
                onPressed: _busy ? null : _stream,
                child: const Text('Stream'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        'speechAvailable',
                        () => ai.speechAvailable(locale),
                      ),
                child: const Text('Speech available'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run('listen', () => ai.listen(locale)),
                child: const Text('Listen'),
              ),
              OutlinedButton(
                onPressed: () => _run('stopListening', ai.stopListening),
                child: const Text('Stop listening'),
              ),
              OutlinedButton(
                onPressed: () => _run('cancel', ai.cancel),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run('environment', () async {
                        final env = await ai.environment(
                          directories: const ['system_llm_example'],
                        );
                        return 'supported=${env.supported} '
                            'free=${env.freeBytes} memory=${env.memoryBytes} '
                            '${env.directories}';
                      }),
                child: const Text('Environment'),
              ),
            ],
          ),
          const Divider(height: 32),
          for (final line in _log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText(line),
            ),
        ],
      ),
    );
  }
}
