import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai_exception.dart';
import 'sse.dart';

/// JSON and Server-Sent-Events calls shared by the remote models.
///
/// Every failure becomes a [SystemLlmException]. The provider's error body is
/// read only to classify the failure and is never forwarded, because it can
/// echo the user's prompt.
final class HttpTransport {
  HttpTransport({http.Client? client, required this.timeout})
    : client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client client;
  final bool _ownsClient;

  /// Bounds a whole JSON call, and the silence between two streamed events.
  final Duration timeout;

  final _calls = <_Call>{};

  /// Aborts every running call with [SystemLlmException.cancelled].
  void cancelAll() {
    for (final call in [..._calls]) {
      call.abort(SystemLlmException.cancelled);
    }
  }

  /// Closes the HTTP client if this transport created it.
  void close() {
    cancelAll();
    if (_ownsClient) client.close();
  }

  Future<Object?> getJson(
    Uri url,
    Map<String, String> headers, {
    Duration? timeout,
  }) => _json('GET', url, headers, null, timeout ?? this.timeout);

  Future<Object?> postJson(
    Uri url,
    Map<String, String> headers,
    Map<String, Object?> body,
  ) => _json('POST', url, headers, body, timeout);

  Future<Object?> _json(
    String method,
    Uri url,
    Map<String, String> headers,
    Map<String, Object?>? body,
    Duration timeout,
  ) async {
    final call = _Call();
    _calls.add(call);
    final timer = Timer(timeout, () => call.abort(SystemLlmException.timeout));
    final int status;
    final String text;
    try {
      final response = await call.race(
        client.send(_request(method, url, headers, body, call)),
      );
      status = response.statusCode;
      text = await call.race(response.stream.bytesToString());
    } on SystemLlmException {
      rethrow;
    } catch (_) {
      throw SystemLlmException(call.reason ?? SystemLlmException.network);
    } finally {
      timer.cancel();
      _calls.remove(call);
    }
    if (status < 200 || status >= 300) throw errorFor(status, text);
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const SystemLlmException(SystemLlmException.invalidResponse);
    }
  }

  /// Sends [body] and streams the response as Server-Sent Events.
  ///
  /// Cancelling the subscription aborts the request. The stream fails with
  /// [SystemLlmException.timeout] when no event arrives for [timeout].
  Stream<SseEvent> postSse(
    Uri url,
    Map<String, String> headers,
    Map<String, Object?> body,
  ) {
    final call = _Call();
    StreamSubscription<SseEvent>? upstream;
    Timer? idle;
    late final StreamController<SseEvent> controller;

    void finish() {
      idle?.cancel();
      _calls.remove(call);
    }

    void fail(Object error) {
      finish();
      if (controller.isClosed) return;
      controller
        ..addError(error)
        ..close();
    }

    void resetIdle() {
      idle?.cancel();
      idle = Timer(timeout, () => call.abort(SystemLlmException.timeout));
    }

    Future<void> start() async {
      _calls.add(call);
      unawaited(
        call.trigger.future.then((_) {
          unawaited(upstream?.cancel());
          fail(SystemLlmException(call.reason!));
        }),
      );
      resetIdle();
      try {
        final response = await call.race(
          client.send(
            _request(
              'POST',
              url,
              {...headers, 'accept': 'text/event-stream'},
              body,
              call,
            ),
          ),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final text = await call.race(response.stream.bytesToString());
          fail(errorFor(response.statusCode, text));
          return;
        }
        resetIdle();
        upstream = response.stream
            .transform(utf8.decoder)
            .transform(const SseDecoder())
            .listen(
              (event) {
                resetIdle();
                controller.add(event);
              },
              onError: (Object _) => fail(
                SystemLlmException(call.reason ?? SystemLlmException.network),
              ),
              onDone: () {
                finish();
                if (!controller.isClosed) controller.close();
              },
            );
      } on SystemLlmException catch (error) {
        fail(error);
      } catch (_) {
        fail(SystemLlmException(call.reason ?? SystemLlmException.network));
      }
    }

    controller = StreamController<SseEvent>(
      onListen: start,
      // A paused consumer is not a silent server: stop the idle timer.
      onPause: () {
        idle?.cancel();
        upstream?.pause();
      },
      onResume: () {
        resetIdle();
        upstream?.resume();
      },
      // The upstream cancel is not awaited: on a silent connection it may
      // only complete when the socket closes, and the caller must not wait.
      onCancel: () {
        call.abort(SystemLlmException.cancelled);
        finish();
        unawaited(upstream?.cancel());
      },
    );
    return controller.stream;
  }

  http.BaseRequest _request(
    String method,
    Uri url,
    Map<String, String> headers,
    Map<String, Object?>? body,
    _Call call,
  ) {
    final request =
        http.AbortableRequest(method, url, abortTrigger: call.trigger.future)
          ..headers.addAll(headers)
          // A redirect would carry the API key header to another host.
          ..followRedirects = false;
    if (body != null) {
      request
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    return request;
  }

  /// Classifies a failed response. Only the status and the provider's error
  /// code or wording are inspected; nothing from [body] is kept.
  static SystemLlmException errorFor(int status, String body) {
    if ((status == 400 || status == 413) && _mentionsContextLimit(body)) {
      return const SystemLlmException(SystemLlmException.contextTooLong);
    }
    return SystemLlmException(switch (status) {
      401 || 403 => SystemLlmException.unauthorized,
      404 => SystemLlmException.modelNotFound,
      408 => SystemLlmException.timeout,
      413 => SystemLlmException.contextTooLong,
      429 => SystemLlmException.rateLimited,
      _ => SystemLlmException.generationFailed,
    });
  }

  static bool _mentionsContextLimit(String body) {
    final text = body.toLowerCase();
    return const [
      'context_length_exceeded',
      'context length',
      'context window',
      'maximum context',
      'prompt is too long',
      'too many tokens',
    ].any(text.contains);
  }
}

/// One running request and how it was stopped, if it was.
final class _Call {
  final trigger = Completer<void>();

  /// The [SystemLlmException] code the call was aborted with.
  String? reason;

  void abort(String code) {
    if (reason != null) return;
    reason = code;
    trigger.complete();
  }

  /// [work], unless the call is aborted first.
  Future<T> race<T>(Future<T> work) {
    if (reason != null) {
      work.ignore();
      return Future.error(SystemLlmException(reason!));
    }
    return Future.any([
      work,
      trigger.future.then<T>((_) => throw SystemLlmException(reason!)),
    ]);
  }
}
