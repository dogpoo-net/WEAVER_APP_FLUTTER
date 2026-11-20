import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

final googleMapsAuthFailed = ValueNotifier(false);
Future<bool>? _loading;

Future<bool> loadGoogleMaps(String key) => _loading ??= _load(key);

Future<bool> _load(String key) async {
  final ready = Completer<bool>();
  void complete(bool result) {
    if (!ready.isCompleted) ready.complete(result);
  }

  globalContext['weaverMapsReady'] = (() => complete(true)).toJS;
  globalContext['gm_authFailure'] = (() {
    googleMapsAuthFailed.value = true;
    complete(false);
  }).toJS;
  final script = web.HTMLScriptElement()
    ..async = true
    ..src = Uri.https('maps.googleapis.com', '/maps/api/js', {
      'key': key,
      'loading': 'async',
      'callback': 'weaverMapsReady',
      'v': 'weekly',
    }).toString();
  script.addEventListener('error', ((web.Event _) => complete(false)).toJS);
  web.document.head!.appendChild(script);
  final loaded = await ready.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () => false,
  );
  if (!loaded) {
    script.remove();
    _loading = null;
  }
  return loaded;
}
