import 'dart:async';

/// One Server-Sent Event.
final class SseEvent {
  const SseEvent(this.data, {this.event = 'message'});

  /// The `event:` field, `message` when absent.
  final String event;

  /// The `data:` lines joined with `\n`.
  final String data;

  @override
  bool operator ==(Object other) =>
      other is SseEvent && other.event == event && other.data == data;

  @override
  int get hashCode => Object.hash(event, data);

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Turns decoded response text into [SseEvent]s. Text may be split anywhere,
/// including mid-line. An event still pending when the stream ends is emitted,
/// because some servers omit the final blank line.
///
/// Built on a plain controller rather than `async*`, so cancelling stops at
/// once even while the server is silent.
final class SseDecoder extends StreamTransformerBase<String, SseEvent> {
  const SseDecoder();

  @override
  Stream<SseEvent> bind(Stream<String> stream) {
    final parser = _SseParser();
    StreamSubscription<String>? subscription;
    late final StreamController<SseEvent> controller;
    controller = StreamController<SseEvent>(
      onListen: () {
        subscription = stream.listen(
          (chunk) => parser.add(chunk).forEach(controller.add),
          onError: controller.addError,
          onDone: () {
            parser.close().forEach(controller.add);
            controller.close();
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}

final class _SseParser {
  var _buffer = '';
  String? _event;
  final _data = <String>[];

  List<SseEvent> add(String chunk) {
    _buffer += chunk;
    final events = <SseEvent>[];
    var newline = _buffer.indexOf('\n');
    while (newline >= 0) {
      final event = _line(_buffer.substring(0, newline));
      if (event != null) events.add(event);
      _buffer = _buffer.substring(newline + 1);
      newline = _buffer.indexOf('\n');
    }
    return events;
  }

  List<SseEvent> close() {
    final events = <SseEvent>[];
    if (_buffer.isNotEmpty) {
      final event = _line(_buffer);
      if (event != null) events.add(event);
      _buffer = '';
    }
    final last = _dispatch();
    if (last != null) events.add(last);
    return events;
  }

  SseEvent? _line(String raw) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        _data.add(value);
    }
    return null;
  }

  SseEvent? _dispatch() {
    final event = _data.isEmpty
        ? null
        : SseEvent(_data.join('\n'), event: _event ?? 'message');
    _event = null;
    _data.clear();
    return event;
  }
}
