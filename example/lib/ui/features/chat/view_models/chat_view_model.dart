import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:system_llm/providers.dart';

import '../../models/view_models/models_view_model.dart';

/// A conversation that runs on whichever [LanguageModel] the user picked.
/// The model is resolved on every send, so switching models mid-chat works:
/// the next answer comes from the new model, with the same history.
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required this.models,
    required this._resolve,
    this.instructions =
        'You are a helpful assistant. Answer clearly and '
        'briefly, in the language the user writes in.',
    this.maxTokens = 4096,
  });

  final ModelsViewModel models;
  final Future<LanguageModel> Function(ModelSettings settings) _resolve;
  final String instructions;
  final int maxTokens;

  final _messages = <AiMessage>[];
  String _partial = '';
  bool _streaming = false;
  String? _errorCode;
  StreamSubscription<String>? _subscription;
  LanguageModel? _active;

  List<AiMessage> get messages => List.unmodifiable(_messages);

  /// The answer so far while [streaming].
  String get partial => _partial;
  bool get streaming => _streaming;

  /// [SystemLlmException] code of the last failure, cleared on the next send.
  String? get errorCode => _errorCode;

  /// Whether the last message still waits for an answer (after an error).
  bool get canRetry =>
      !_streaming && _messages.isNotEmpty && _messages.last.role == AiRole.user;

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _streaming) return;
    _messages.add(AiMessage.user(message));
    await _answer();
  }

  Future<void> retry() async {
    if (canRetry) await _answer();
  }

  Future<void> _answer() async {
    _errorCode = null;
    _partial = '';
    _streaming = true;
    notifyListeners();
    final LanguageModel model;
    try {
      model = await _resolve(models.settings);
    } on SystemLlmException catch (error) {
      _finish(error: error.code);
      return;
    }
    _active = model;
    _subscription = model
        .streamText(
          instructions: instructions,
          messages: List.of(_messages),
          maxTokens: maxTokens,
        )
        .listen(
          (chunk) {
            _partial += chunk;
            notifyListeners();
          },
          onError: (Object error) => _finish(
            error: error is SystemLlmException
                ? error.code
                : SystemLlmException.generationFailed,
          ),
          onDone: _finish,
          cancelOnError: true,
        );
  }

  /// Stops the answer; the text received so far is kept.
  Future<void> stop() async {
    if (!_streaming) return;
    final subscription = _subscription;
    final model = _active;
    _finish();
    // Stop the model first; the subscription cancel may only settle later.
    await model?.cancel();
    await subscription?.cancel();
  }

  Future<void> clear() async {
    await stop();
    _messages.clear();
    _errorCode = null;
    notifyListeners();
  }

  void _finish({String? error}) {
    if (!_streaming) return;
    if (_partial.isNotEmpty) _messages.add(AiMessage.assistant(_partial));
    _partial = '';
    _streaming = false;
    _errorCode = error;
    _subscription = null;
    final model = _active;
    _active = null;
    if (model is RemoteLanguageModel) model.close();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
