import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> openVideoFile(String name, Uint8List bytes) async {
  final mime = name.endsWith('.mov')
      ? 'video/quicktime'
      : name.endsWith('.webm')
      ? 'video/webm'
      : 'video/mp4';
  final url = web.URL.createObjectURL(
    web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime)),
  );
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  link.click();
  Future.delayed(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(url),
  );
}
