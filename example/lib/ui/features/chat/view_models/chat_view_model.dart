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

  /// Bumped by stop, clear and dispose, so an answer whose model is still
  /// being chosen knows it was abandoned.
  int _run = 0;
  bool _disposed = false;

  List<AiMessage> get messages => List.unmodifiable(_messages);

  /// The answer so far while [streaming].
  String get partial => _partial;
  bool get streaming => _streaming;

  /// [SystemLlmException] code of the last failure, cleared on the next send.
  String? get errorCode => _errorCode;

  /// Whether the last question can be asked again: it got no answer (an
  /// error, or Stop before any text), or its answer failed part-way.
  bool get canRetry =>
      !_streaming &&
      _messages.isNotEmpty &&
      (_messages.last.role == AiRole.user || _errorCode != null);

  /// Sends [text]; false when it was not accepted (blank, or an answer is
  /// still running), so the caller can keep what the user typed.
  Future<bool> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _streaming || _disposed) return false;
    _messages.add(AiMessage.user(message));
    await _answer();
    return true;
  }

  Future<void> retry() async {
    if (!canRetry) return;
    // A partial answer from the failed attempt is replaced, not kept.
    if (_messages.last.role == AiRole.assistant) _messages.removeLast();
    await _answer();
  }

  Future<void> _answer() async {
    final run = ++_run;
    _errorCode = null;
    _partial = '';
    _streaming = true;
    _notify();
    final LanguageModel model;
    try {
      model = await _resolve(models.settings);
    } on SystemLlmException catch (error) {
      if (run == _run) _finish(error: error.code);
      return;
    } on Object catch (error) {
      debugPrint('Could not choose the model: $error');
      if (run == _run) _finish(error: SystemLlmException.generationFailed);
      return;
    }
    if (run != _run) {
      // Stopped, cleared or disposed while the model was being chosen.
      _release(model);
      return;
    }
    _active = model;
    final Stream<String> answer;
    try {
      answer = model.streamText(
        instructions: instructions,
        messages: List.of(_messages),
        maxTokens: maxTokens,
      );
    } on Object catch (error) {
      _finish(
        error: error is SystemLlmException
            ? error.code
            : SystemLlmException.generationFailed,
      );
      return;
    }
    _subscription = answer.listen(
      (chunk) {
        _partial += chunk;
        _notify();
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
    _run++;
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
    _notify();
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
    if (model != null) _release(model);
    _notify();
  }

  void _release(LanguageModel model) {
    if (model is RemoteLanguageModel) model.close();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    unawaited(_subscription?.cancel());
    final model = _active;
    if (model != null) _release(model);
    super.dispose();
  }
}
