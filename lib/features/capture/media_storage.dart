import 'dart:typed_data';
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
  static Future<void> write(String id, Uint8List bytes) async => (await _box()).put(id, bytes);
  static Future<Uint8List?> read(String id) async => (await _box()).get(id);
  static Future<void> delete(String id) async => (await _box()).delete(id);
  static Future<void> clear() async { await (await _box()).clear(); }
}
