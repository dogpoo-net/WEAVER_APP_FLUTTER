import 'dart:typed_data';
import 'dart:convert';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Binary attachments stay outside the JSON/settings snapshot. On the web Hive
/// uses IndexedDB; on Android/iOS it uses the application's documents directory.
class MediaStorage {
  static Future<LazyBox<Uint8List>>? _opening;
  static Future<LazyBox<Uint8List>> _box() => _opening ??= _open();
  static Future<LazyBox<Uint8List>> _open() async {
    try {
      await Hive.initFlutter('weaver-media');
      return await Hive.openLazyBox<Uint8List>('attachments');
    } catch (_) { _opening = null; rethrow; }
  }
  static String? activeOwner;
  static final remoteReaders = <String, Future<Uint8List?> Function(String)>{};
  static final _pendingReads = <(String, Future<Uint8List?> Function(String)), Future<Uint8List?>>{};
  static String _key(String id,String? owner){final scope=owner==''?activeOwner:owner;return scope==null?id:'owned:${base64Url.encode(utf8.encode(scope))}:$id';}
  static Future<void> write(String id, Uint8List bytes,{String? owner=''}) {final key=_key(id,owner);return _box().then((box)=>box.put(key,bytes));}
  /// Check the lazy box index without loading the attachment bytes.
  static Future<bool> contains(String id, {String? owner = ''}) async {
    final key = _key(id, owner);
    return (await _box()).containsKey(key);
  }
  static Future<Uint8List?> read(String id, {String? owner = ''}) async {
    final scope = owner == '' ? activeOwner : owner;
    final key = _key(id, scope);
    final box = await _box();
    final local = await box.get(key);
    if (local != null || scope == null) return local;
    final reader = remoteReaders[scope];
    if (reader == null) return null;
    final request = (key, reader);
    return _pendingReads.putIfAbsent(request, () async {
      try {
        final bytes = await reader(id);
        if (bytes == null || !identical(remoteReaders[scope], reader)) return null;
        final saved = await box.get(key);
        if (saved != null) return saved;
        if (!identical(remoteReaders[scope], reader)) return null;
        await box.put(key, bytes);
        return bytes;
      } finally {
        _pendingReads.remove(request);
      }
    });
  }
  static Future<void> delete(String id,{String? owner=''}) {final key=_key(id,owner);return _box().then((box)=>box.delete(key));}
  static Future<void> clear({String? owner=''}) async {final prefix=_key('',owner);final box=await _box();await box.deleteAll(box.keys.where((key)=>prefix.isEmpty?!key.toString().startsWith('owned:'):key.toString().startsWith(prefix)).toList());}
}
