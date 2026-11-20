import 'package:flutter/material.dart';

import '../capture/media_storage.dart';

class DocumentPhoto extends StatefulWidget {
  const DocumentPhoto(this.id, {super.key});

  final String id;

  @override
  State<DocumentPhoto> createState() => _DocumentPhotoState();
}

class _DocumentPhotoState extends State<DocumentPhoto> {
  late var _load = MediaStorage.read(widget.id);

  @override
  void didUpdateWidget(covariant DocumentPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _load = MediaStorage.read(widget.id);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _load,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes != null) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Image.memory(bytes, height: 280, fit: BoxFit.contain),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const LinearProgressIndicator();
      }
      return const Text('사진을 불러올 수 없습니다.');
    },
  );
}
