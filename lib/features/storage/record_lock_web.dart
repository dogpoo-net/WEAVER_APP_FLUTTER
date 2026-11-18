import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

class RecordLock {
  static const _key = 'weaver.records.revision.v1';
  String get revision => web.window.localStorage.getItem(_key) ?? '';
  Future<T> exclusive<T>(Future<T> Function() action) async {
    late T result;
    Object? failure;
    StackTrace? trace;
    await web.window.navigator.locks
        .request(
          'weaver-workspace-records-v1',
          ((JSAny? _) {
            return (() async {
              try {
                result = await action();
              } catch (e, s) {
                failure = e;
                trace = s;
              }
              return null;
            })().toJS;
          }).toJS,
        )
        .toDart;
    if (failure != null) Error.throwWithStackTrace(failure!, trace!);
    return result;
  }

  void changed() => web.window.localStorage.setItem(
    _key,
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}',
  );
}
