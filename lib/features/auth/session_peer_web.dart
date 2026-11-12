import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'package:web/web.dart' as web;

/// Only a live, same-origin tab can authorize a new independent HttpOnly session.
/// Cookie tokens and the source tab's proof never travel through this channel.
class SessionPeer {
  SessionPeer({required this.available, required this.attach}) {
    try {
      _channel = web.BroadcastChannel('weaver.invitation-session.v1');
      _channel!.onmessage = ((web.MessageEvent event) {
        try {
          final value = jsonDecode((event.data as JSString).toDart);
          if (value is Map<String, dynamic>) unawaited(_receive(value));
        } catch (_) { /* Ignore unrelated or malformed messages. */ }
      }).toJS;
    } catch (_) { /* Unsupported browsers fall back to normal login. */ }
  }
  final bool Function() available;
  final Future<void> Function(String, String) attach;
  final String _id = _nonce();
  web.BroadcastChannel? _channel;
  Completer<bool>? _pending;
  String? _request, _selected, _tab, _proof;
  final Map<String, DateTime> _offers = {};
  static String _nonce() => base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)));
  void _send(Map<String, Object?> message) => _channel?.postMessage(jsonEncode(message).toJS);
  Future<void> _receive(Map<String, dynamic> message) async {
    final request = message['request'];
    if (request is! String || request.length > 64) return;
    switch (message['type']) {
      case 'request':
        if (!available()) return;
        _offers.removeWhere((_, time) => DateTime.now().difference(time).inSeconds > 10);
        if (_offers.length >= 16) return;
        _offers[request] = DateTime.now();
        _send({'type':'offer', 'request':request, 'peer':_id});
      case 'offer':
        if (request != _request || _selected != null || _pending == null) return;
        final peer = message['peer'];
        if (peer is! String) return;
        _selected = peer;
        _send({'type':'attach', 'request':request, 'peer':peer, 'tab':_tab, 'proof':_proof});
      case 'attach':
        if (message['peer'] != _id || !available()) return;
        final offered = _offers.remove(request);
        if (offered == null || DateTime.now().difference(offered).inSeconds > 10) return;
        final tab = message['tab'], proof = message['proof'];
        if (tab is! String || proof is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(tab) || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(proof)) return;
        var success = false;
        try { await attach(tab, proof); success = true; } catch (_) {}
        _send({'type':'done', 'request':request, 'peer':_id, 'success':success});
      case 'done':
        if (request == _request && message['peer'] == _selected && _pending?.isCompleted == false) {
          _pending!.complete(message['success'] == true);
        }
    }
  }
  Future<bool> request(String tab, String proof) async {
    if (_channel == null || _pending != null) return false;
    final pending = _pending = Completer<bool>();
    _request = _nonce(); _selected = null; _tab = tab; _proof = proof;
    _send({'type':'request', 'request':_request});
    try { return await pending.future.timeout(const Duration(seconds: 4), onTimeout: () => false); }
    finally { _pending = null; _request = null; _selected = null; _tab = null; _proof = null; }
  }
  void dispose() {
    if (_pending?.isCompleted == false) _pending!.complete(false);
    _channel?.close(); _channel = null; _offers.clear();
  }
}
