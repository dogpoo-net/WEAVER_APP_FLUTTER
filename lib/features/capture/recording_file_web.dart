import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;
Future<String> recordingPath() async => 'weaver-recording';
Future<Uint8List> finishRecordingFile(String path) async {
  try { return (await http.get(Uri.parse(path))).bodyBytes; }
  finally { if(path.startsWith('blob:'))web.URL.revokeObjectURL(path); }
}
Future<void> discardRecordingPath(String path) async {}
