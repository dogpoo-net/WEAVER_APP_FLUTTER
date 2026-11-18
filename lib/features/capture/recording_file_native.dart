import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
Future<String> recordingPath() async => '${(await getTemporaryDirectory()).path}/weaver-record-${DateTime.now().microsecondsSinceEpoch}.m4a';
Future<Uint8List> finishRecordingFile(String path) async {
  final file=File(path);
  try { return await file.readAsBytes(); } finally { if(await file.exists())await file.delete(); }
}
Future<void> discardRecordingPath(String path) async {final file=File(path);if(await file.exists())await file.delete();}
