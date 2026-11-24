import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<void> openVideoFile(String name, Uint8List bytes) async {
  await FilePicker.saveFile(fileName: name, bytes: bytes);
}
