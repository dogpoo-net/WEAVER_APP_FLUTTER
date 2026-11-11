import 'dart:typed_data';

import '../capture/media_storage.dart';
import '../capture/voice_player.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../inbox/workspace_storage.dart';
import '../inbox/graph_layout.dart';

class ReadonlyWorkspace extends StatelessWidget {
  const ReadonlyWorkspace({
    super.key,
    required this.storage,
    required this.onHistory,
  });
  final WorkspaceStorage storage;
  final void Function(String) onHistory;
  @override
  Widget build(BuildContext context) {
    final snapshot = WorkspaceSnapshot.decode(storage.read()!);
    final documents = snapshot.notes.where((n) => n.project != null).toList();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('읽기 전용 워크스페이스'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '문서'),
              Tab(text: '생각'),
              Tab(text: '다이어그램'),
              Tab(text: '메모상자'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              children: [
                for (final note in documents)
                  ListTile(
                    title: Text(note.project!.title),
                    trailing: IconButton(
                      tooltip: '변경 이력',
                      icon: const Icon(Icons.history),
                      onPressed: () => onHistory(note.project!.id),
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(note.project!.title),
                        content: SizedBox(
                          width: 700,
                          child: SingleChildScrollView(
                            child: SelectableText(note.project!.content),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final record in snapshot.records)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(record.text),
                          for (final photo in record.photos)
                            FutureBuilder<Uint8List?>(
                              future: MediaStorage.read(
                                photo.id,
                                owner: storage.owner,
                              ),
                              builder: (context, snapshot) =>
                                  snapshot.data == null
                                  ? const SizedBox.shrink()
                                  : Image.memory(
                                      snapshot.data!,
                                      height: 200,
                                      fit: BoxFit.contain,
                                    ),
                            ),
                          for (final clip in record.recordings)
                            VoicePlayer(
                              load: () => MediaStorage.read(
                                clip.id,
                                owner: storage.owner,
                              ),
                              durationMs: clip.durationMs,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            _canvas(snapshot, snapshot.graphLayout ?? GraphLayout()),
            _canvas(
              snapshot,
              (snapshot.graphLayout ?? GraphLayout()).blockLayout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _canvas(WorkspaceSnapshot snapshot, GraphLayout layout) {
    final points = layout.positions;
    final width = points.values.map((p) => p.dx + 300).fold(900.0, math.max),
        height = points.values.map((p) => p.dy + 180).fold(600.0, math.max);
    return InteractiveViewer(
      constrained: false,
      minScale: .15,
      maxScale: 4,
      boundaryMargin: const EdgeInsets.all(300),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            for (var i = 0; i < snapshot.records.length; i++)
              Positioned(
                left: points[snapshot.records[i].id]?.dx ?? (i % 4) * 220.0,
                top: points[snapshot.records[i].id]?.dy ?? (i ~/ 4) * 150.0,
                width: 200,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      snapshot.records[i].text,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
