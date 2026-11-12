import 'package:flutter_test/flutter_test.dart';
import 'package:system_llm/src/remote/sse.dart';

Future<List<SseEvent>> decode(List<String> chunks) =>
    Stream.fromIterable(chunks).transform(const SseDecoder()).toList();

void main() {
  test('emits one event per blank-line terminated block', () async {
    expect(await decode(['data: a\n\ndata: b\n\n']), [
      const SseEvent('a'),
      const SseEvent('b'),
    ]);
  });

  test('reassembles lines split across chunks, including CRLF', () async {
    expect(await decode(['da', 'ta: {"x"', ':1}\r', '\n\r\n']), [
      const SseEvent('{"x":1}'),
    ]);
  });

  test('reads event names, joins data lines and skips comments', () async {
    expect(
      await decode([
        ': keep-alive\n',
        'event: content_block_delta\n',
        'data: one\n',
        'data:two\n\n',
      ]),
      [const SseEvent('one\ntwo', event: 'content_block_delta')],
    );
  });

  test('emits a final event that lacks the closing blank line', () async {
    expect(await decode(['data: [DONE]']), [const SseEvent('[DONE]')]);
  });

  test('ignores blocks without data', () async {
    expect(await decode(['event: ping\n\n']), isEmpty);
  });
}
