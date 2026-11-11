import 'package:flutter/material.dart';
import 'package:system_llm/providers.dart';

import '../../../core/labels.dart';
import '../view_models/chat_view_model.dart';

/// A chat that runs on the model chosen under Models.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.viewModel, this.onOpenModels});

  final ChatViewModel viewModel;

  /// Shows the Models screen, from the banner that says where prompts go.
  final VoidCallback? onOpenModels;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    widget.viewModel.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.viewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, chat.models]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Chat'),
          actions: [
            IconButton(
              tooltip: 'Clear chat',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: chat.messages.isEmpty && !chat.streaming
                  ? null
                  : chat.clear,
            ),
          ],
        ),
        body: Column(
          children: [
            _DestinationBanner(
              settings: chat.models.settings,
              onTap: widget.onOpenModels,
            ),
            Expanded(
              child: chat.messages.isEmpty && !chat.streaming
                  ? const _EmptyChat()
                  : _Transcript(chat: chat),
            ),
            if (chat.errorCode case final code?)
              _ErrorBar(
                message: errorMessage(code),
                onRetry: chat.canRetry ? chat.retry : null,
              ),
            _Composer(
              controller: _input,
              streaming: chat.streaming,
              onSend: _send,
              onStop: chat.stop,
            ),
          ],
        ),
      ),
    );
  }
}

/// Says where prompts are sent, so the user always knows.
class _DestinationBanner extends StatelessWidget {
  const _DestinationBanner({required this.settings, this.onTap});

  final ModelSettings settings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = settings.selected;
    final (icon, text) = switch ((settings.useThirdParty, selected)) {
      (false, _) => (
        Icons.phone_android,
        'On-device model · messages stay on this device',
      ),
      (true, null) => (Icons.warning_amber_outlined, 'No provider selected'),
      (true, final provider?) => (
        Icons.cloud_outlined,
        '${provider.name} · ${provider.model} · messages are sent to '
            '${provider.host}',
      ),
    };
    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              if (onTap != null)
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('Start a conversation', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Switch models under Models at any time; the conversation '
              'carries over.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.chat});

  final ChatViewModel chat;

  @override
  Widget build(BuildContext context) {
    final messages = chat.messages;
    final count = messages.length + (chat.streaming ? 1 : 0);
    // Reversed so the newest message stays in view as text arrives.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (chat.streaming && index == 0) {
          return _Bubble(
            message: AiMessage.assistant(chat.partial),
            pending: true,
          );
        }
        final offset = chat.streaming ? 1 : 0;
        return _Bubble(message: messages[messages.length - 1 - index + offset]);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.pending = false});

  final AiMessage message;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.role == AiRole.user;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Container(
          margin: const EdgeInsetsDirectional.symmetric(vertical: 4),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: pending && message.text.isEmpty
              ? Semantics(
                  label: 'Waiting for the answer',
                  child: SizedBox(
                    width: 32,
                    child: LinearProgressIndicator(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )
              : SelectableText(
                  message.text,
                  style: TextStyle(
                    color: mine ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.streaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool streaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            streaming
                ? IconButton.filledTonal(
                    tooltip: 'Stop',
                    icon: const Icon(Icons.stop),
                    onPressed: onStop,
                  )
                : IconButton.filled(
                    tooltip: 'Send',
                    icon: const Icon(Icons.send),
                    onPressed: onSend,
                  ),
          ],
        ),
      ),
    );
  }
}
