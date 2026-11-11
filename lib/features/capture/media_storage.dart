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
  static String _key(String id,String? owner){final scope=owner==''?activeOwner:owner;return scope==null?id:'owned:${base64Url.encode(utf8.encode(scope))}:$id';}
  static Future<void> write(String id, Uint8List bytes,{String? owner=''}) {final key=_key(id,owner);return _box().then((box)=>box.put(key,bytes));}
  static Future<Uint8List?> read(String id,{String? owner=''}) {final key=_key(id,owner);return _box().then((box)=>box.get(key));}
  static Future<void> delete(String id,{String? owner=''}) {final key=_key(id,owner);return _box().then((box)=>box.delete(key));}
  static Future<void> clear({String? owner=''}) async {final prefix=_key('',owner);final box=await _box();await box.deleteAll(box.keys.where((key)=>prefix.isEmpty?!key.toString().startsWith('owned:'):key.toString().startsWith(prefix)).toList());}
}
