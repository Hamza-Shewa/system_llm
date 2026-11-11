import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A streamed response whose body arrives as [chunks], in order.
http.StreamedResponse chunked(List<String> chunks, {int status = 200}) =>
    http.StreamedResponse(Stream.fromIterable(chunks.map(utf8.encode)), status);

/// A JSON response.
http.Response jsonResponse(Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

/// Server-Sent Events text for each payload in [data].
String sse(List<Object?> data) =>
    data.map((d) => 'data: ${d is String ? d : jsonEncode(d)}\n\n').join();

/// What a [http.Request] carried.
extension RequestJson on http.Request {
  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;
}

/// Records every request sent through it, then answers with [handler].
class RecordingClient extends http.BaseClient {
  RecordingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.Request request) handler;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bytes;
    requests.add(copy);
    return handler(copy);
  }
}

/// [RecordingClient] answering with a plain [http.Response].
RecordingClient respond(FutureOr<http.Response> Function(http.Request) fn) =>
    RecordingClient((request) async {
      final response = await fn(request);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
      );
    });

/// [jsonEncode] without whitespace, for building SSE lines.
String jsonEncodeCompact(Object? value) => jsonEncode(value);
