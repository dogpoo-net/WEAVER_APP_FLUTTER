import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../capture/media_storage.dart';
import 'document_video_file.dart'
    if (dart.library.js_interop) 'document_video_file_web.dart';

String? videoLinkSource(String input, String provider) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || !{'https', 'http'}.contains(uri.scheme)) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.)'), '');
  final parts = uri.pathSegments;
  if (provider == 'YouTube') {
    final id = host == 'youtu.be'
        ? parts.firstOrNull
        : host != 'youtube.com'
        ? null
        : uri.path == '/watch'
        ? uri.queryParameters['v']
        : parts.length == 2 && {'shorts', 'embed', 'live'}.contains(parts.first)
        ? parts.last
        : null;
    return id != null && RegExp(r'^[\w-]{11}$').hasMatch(id)
        ? 'youtube:$id'
        : null;
  }
  if (host != 'vimeo.com' && host != 'player.vimeo.com') return null;
  final path = parts.skip(parts.firstOrNull == 'video' ? 1 : 0).toList();
  if (path.isEmpty || path.length > 2 || !RegExp(r'^\d+$').hasMatch(path.first))
    return null;
  final hash = path.length == 2 ? path.last : uri.queryParameters['h'];
  if (hash != null && !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(hash)) return null;
  return 'vimeo:${path.first}${hash == null ? '' : '/$hash'}';
}

Future<String?> chooseDocumentVideo(BuildContext context) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('영상 첨부'),
      children: [
        for (final name in ['YouTube', 'Vimeo', '파일 업로드'])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, name),
            child: Text(name),
          ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice == '파일 업로드') {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'webm', 'mov'],
      );
      if (files.isEmpty) return null;
      final file = files.single;
      final extension = file.name.split('.').last.toLowerCase();
      if (!{'mp4', 'mov', 'webm'}.contains(extension))
        throw const FormatException();
      final random = Random.secure();
      final id =
          'video-${List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join()}.$extension';
      await MediaStorage.write(id, await file.readAsBytes());
      return 'file:$id';
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('영상 파일을 첨부하지 못했습니다.')));
      return null;
    }
  }
  var input = '';
  String? error;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        void submit() {
          final source = videoLinkSource(input, choice);
          if (source == null) {
            update(() => error = '$choice 영상 링크를 확인해주세요.');
            return;
          }
          Navigator.pop(context, source);
        }

        return AlertDialog(
          title: Text('$choice 링크'),
          content: TextField(
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: '영상 URL', errorText: error),
            onChanged: (value) => input = value,
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(onPressed: submit, child: const Text('삽입')),
          ],
        );
      },
    ),
  );
}

class DocumentVideo extends StatelessWidget {
  const DocumentVideo(this.source, {super.key});
  final String source;
  @override
  Widget build(BuildContext context) {
    final id = source.substring(source.indexOf(':') + 1);
    final file = source.startsWith('file:');
    final youtube = source.startsWith('youtube:');
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.video_library_outlined),
        label: Text(
          file
              ? '첨부 영상 다운로드'
              : youtube
              ? 'YouTube 영상 열기'
              : 'Vimeo 영상 열기',
        ),
        onPressed: () async {
          try {
            if (file) {
              final bytes = await MediaStorage.read(id);
              if (bytes == null) throw StateError('missing');
              await openVideoFile(id, bytes);
            } else if (!await launchUrl(
              Uri.parse(
                youtube
                    ? 'https://www.youtube.com/watch?v=$id'
                    : 'https://vimeo.com/$id',
              ),
            )) {
              throw StateError('unavailable');
            }
          } catch (_) {
            if (context.mounted)
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('영상을 열 수 없습니다.')));
          }
        },
      ),
    );
  }
}
