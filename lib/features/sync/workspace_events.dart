import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../auth/session_platform.dart';

/// Streaming fetch on web (with cookie + proof headers), HTTP stream on native.
/// A new stream always announces ready: DB revision reads recover missed events.
class WorkspaceEvents {
  WorkspaceEvents({
    required this.open,
    required this.onChange,
    required this.onConnection,
    http.Client Function()? clientFactory,
    this.retryDelay,
    this.idleTimeout = const Duration(seconds: 45),
  }) : clientFactory = clientFactory ?? sessionHttpClient;
  final Future<http.StreamedResponse> Function(http.Client) open;
  final void Function() onChange;
  final void Function(bool) onConnection;
  final http.Client Function() clientFactory;
  final Duration? retryDelay;
  final Duration idleTimeout;
  http.Client? _client;
  StreamSubscription<String>? _subscription;
  Timer? _retry;
  bool _active = false, _disposed = false;
  int _epoch = 0, _failures = 0;
  void resume() {
    if (_disposed || _active) return;
    _active = true;
    _connect();
  }

  void pause() {
    _active = false;
    _epoch++;
    _retry?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    onConnection(false);
  }

  void dispose() {
    if (_disposed) return;
    pause();
    _disposed = true;
  }

  Future<void> _connect() async {
    if (!_active || _disposed) return;
    final epoch = ++_epoch, client = clientFactory();
    _client = client;
    void failed() {
      if (epoch != _epoch || !_active || _disposed) return;
      _epoch++;
      _subscription?.cancel();
      _subscription = null;
      client.close();
      _client = null;
      onConnection(false);
      _failures = min(_failures + 1, 6);
      final delay =
          retryDelay ??
          Duration(
            milliseconds:
                min(30000, 500 * (1 << _failures)) + Random().nextInt(500),
          );
      _retry = Timer(delay, _connect);
    }

    try {
      final response = await open(client).timeout(const Duration(seconds: 15));
      if (epoch != _epoch || !_active || _disposed) {
        client.close();
        return;
      }
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').startsWith(
            'text/event-stream',
          )) {
        failed();
        return;
      }
      _subscription = response.stream
          .timeout(idleTimeout)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .transform(const SseEvents())
          .listen(
            (event) {
              if (epoch != _epoch) return;
              if (event == 'ready' || event == 'ping' || event == 'change') {
                _failures = 0;
                onConnection(true);
                if (event != 'ping') onChange();
              }
            },
            onError: (Object _) => failed(),
            onDone: failed,
          );
    } catch (_) {
      failed();
    }
  }
}

/// Parse complete SSE records, including CRLF and transport chunk boundaries.
class SseEvents extends StreamTransformerBase<String, String> {
  const SseEvents();
  @override
  Stream<String> bind(Stream<String> stream) async* {
    String event = 'message';
    bool data = false;
    await for (final line in stream) {
      if (line.isEmpty) {
        if (data) yield event;
        event = 'message';
        data = false;
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data = true;
      }
    }
  }
}
