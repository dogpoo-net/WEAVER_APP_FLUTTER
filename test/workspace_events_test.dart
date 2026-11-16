import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weaver/features/sync/workspace_events.dart';

void main() {
  test(
    'SSE handles split UTF8, CRLF, comments and complete records only',
    () async {
      final bytes = utf8.encode(
        ': 연결\r\nevent: ready\r\ndata: {}\r\n\r\nevent: change\ndata: {}\n\nevent: ping\ndata: {}\n\nevent: change\ndata: unfinished',
      );
      final events = await Stream.fromIterable(bytes.map((b) => [b]))
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .transform(const SseEvents())
          .toList();
      expect(events, ['ready', 'change', 'ping']);
    },
  );
  test('ready reconciles, heartbeat does not fetch, dropped stream reconnects; pause cancels', () async {
    final streams = <StreamController<List<int>>>[];
    var opens = 0, changes = 0;
    final connections = <bool>[];
    final events = WorkspaceEvents(
      open: (client) async {
        opens++;
        final stream = StreamController<List<int>>();
        streams.add(stream);
        return http.StreamedResponse(
          stream.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      },
      onChange: () => changes++,
      onConnection: connections.add,
      clientFactory: () => MockClient((_) async => http.Response('', 200)),
      retryDelay: const Duration(milliseconds: 10),
    );
    events.resume();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    void emit(int i, String name) =>
        streams[i].add(utf8.encode('event: $name\ndata: {}\n\n'));
    emit(0, 'ready');
    emit(0, 'ping');
    emit(0, 'change');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(changes, 2);
    expect(connections.last, true);
    await streams[0].close();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(opens, 2);
    emit(1, 'ready');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(changes, 3);
    events.pause();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(opens, 2);
    expect(connections.last, false);
    events.resume();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(opens, 3);
    events.dispose();
    for (final s in streams) {
      unawaited(s.close());
    }
  });
  test('idle stream is discarded and reconnected instead of silently missing updates', () async {
    var opens = 0;
    final streams = <StreamController<List<int>>>[];
    final events = WorkspaceEvents(
      open: (client) async {
        opens++;
        final stream = StreamController<List<int>>();
        streams.add(stream);
        return http.StreamedResponse(
          stream.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      },
      onChange: () {},
      onConnection: (_) {},
      clientFactory: () => MockClient((_) async => http.Response('', 200)),
      retryDelay: const Duration(milliseconds: 10),
      idleTimeout: const Duration(milliseconds: 10),
    );
    events.resume();
    await Future<void>.delayed(const Duration(milliseconds: 45));
    events.dispose();
    expect(opens, greaterThan(1));
    for (final stream in streams) {
      unawaited(stream.close());
    }
  });
}
