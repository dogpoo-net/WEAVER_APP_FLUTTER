import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'workspace_map_surface.dart';
import 'google_thought_map.dart';
import 'voice_transcription.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'capture_models.dart';
import 'media_storage.dart';
import 'voice_dialog.dart';
import 'voice_player.dart';

import 'package:image_picker/image_picker.dart';

import 'location_capture.dart';
import 'regional_tiles.dart';
import 'map_attribution.dart';
import 'map_marker_style.dart';

class LocationEntry {
  const LocationEntry(
    this.location,
    this.text, {
    this.important = false,
    this.photos = const [],
    this.recordings = const [],
  });
  final ThoughtLocation location;
  final String text;
  final bool important;
  final List<PhotoAttachment> photos;
  final List<VoiceAttachment> recordings;
}

Future<LocationEntry?> showLocationEditor(
  BuildContext context, {
  ThoughtLocation? initial,
  bool compose = false,
  bool locateInitially = true,
  String confirmLabel = '저장',
  String? Function(String)? validate,
  Future<ThoughtLocation> Function()? locate,
}) => showDialog<LocationEntry>(
  context: context,
  builder: (_) => LocationEditor(
    initial: initial,
    compose: compose,
    locateInitially: locateInitially,
    confirmLabel: confirmLabel,
    validate: validate,
    locate: locate ?? captureLocation,
  ),
);

class LocationEditor extends StatefulWidget {
  const LocationEditor({
    super.key,
    this.initial,
    this.compose = false,
    this.locateInitially = true,
    this.confirmLabel = '저장',
    this.validate,
    required this.locate,
  });
  final ThoughtLocation? initial;
  final bool compose, locateInitially;
  final String confirmLabel;
  final String? Function(String)? validate;
  final Future<ThoughtLocation> Function() locate;
  @override
  State<LocationEditor> createState() => _LocationEditorState();
}

class _LocationEditorState extends State<LocationEditor> {
  final map = MapController();
  google.GoogleMapController? _googleMap;
  bool _osmReady = false;
  final text = TextEditingController();
  Timer? locateTimer;
  final owner = MediaStorage.activeOwner;
  final photos = <PhotoDraft>[];
  VoiceDraft? voice;
  bool attaching = false, saving = false;
  int? markerColor;
  Future<void> recordVoice() async {
    setState(() => attaching = true);
    try {
      final draft = await showVoiceRecorder(context);
      if (mounted && draft != null) setState(() => voice = draft);
    } finally {
      if (mounted) setState(() => attaching = false);
    }
  }

  Future<void> pickPhotos() async {
    setState(() => attaching = true);
    try {
      final picker = ImagePicker();
      final remaining = 5 - photos.length;
      final List<XFile> files;
      if (remaining == 1) {
        final file = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        );
        files = file == null ? [] : [file];
      } else {
        files = await picker.pickMultiImage(
          limit: remaining,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
        );
      }
      for (final file in files.take(remaining)) {
        if (await file.length() > 10 * 1024 * 1024) {
          throw StateError('사진 한 장은 10MB 이하로 선택해주세요.');
        }
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() => photos.add(PhotoDraft(bytes, file.name)));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = '사진을 가져오지 못했습니다. 사진 권한과 파일 크기(최대 10MB)를 확인해주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => attaching = false);
    }
  }

  Future<void> save() async {
    final point = selected;
    if (point == null || saving || attaching) return;
    final problem = widget.validate?.call(text.text.trim());
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    generation++;
    locateTimer?.cancel();
    setState(() { saving = true; busy = false; });
    final written = <String>[];
    try {
      if (owner != MediaStorage.activeOwner) {
        throw StateError('Workspace changed');
      }
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final images = <PhotoAttachment>[];
      final recordings = <VoiceAttachment>[];
      if (voice != null) {
        final id = 'voice-$stamp';
        written.add(id);
        await MediaStorage.write(id, voice!.bytes, owner: owner);
        recordings.add(attachVoiceDraft(id, voice!));
      }
      for (var i = 0; i < photos.length; i++) {
        final id = 'photo-$stamp-$i';
        written.add(id);
        await MediaStorage.write(id, photos[i].bytes, owner: owner);
        images.add(PhotoAttachment(id, photos[i].name));
      }
      if (!mounted || owner != MediaStorage.activeOwner) {
        throw StateError('Workspace changed');
      }
      final latest = widget.validate?.call(text.text.trim());
      if (latest != null) throw StateError(latest);
      setState(() => saving = false);
      Navigator.pop(
        context,
        LocationEntry(
          point,
          text.text.trim(),
          photos: images,
          recordings: recordings,
        ),
      );
    } catch (_) {
      for (final id in written) {
        try {
          await MediaStorage.delete(id, owner: owner);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => error = '저장하지 못했습니다. 작성한 내용과 첨부는 유지됩니다. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget action(String tooltip, IconData icon, VoidCallback? onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          maximumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        visualDensity: VisualDensity.standard,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 19),
      );
  Future<void> color() async {
    final value = await showMarkerPalette(
      context,
      selected == null ? activeMapMarkerColor : locationMarkerColor(selected!),
    );
    if (mounted && value != null) {
      setState(() {
        markerColor = value;
        if (selected != null) selected = selected!.withMarkerColor(value);
      });
    }
  }

  ThoughtLocation? selected;
  bool busy = false;
  int generation = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    selected = widget.initial;
    markerColor = selected?.markerColor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && selected == null && widget.locateInitially) locate();
    });
  }

  Future<void> locate() async {
    final request = ++generation;
    locateTimer?.cancel();
    setState(() {
      busy = true;
      error = null;
    });
    locateTimer = Timer(const Duration(seconds: 25), () {
      if (mounted && request == generation) {
        setState(() {
          generation++;
          busy = false;
          error = '현재 위치를 찾지 못했습니다. 지도에서 원하는 위치를 선택해주세요.';
        });
      }
    });
    try {
      final point = await widget.locate();
      if (!mounted || request != generation) return;
      setState(
        () => selected = markerColor == null
            ? point
            : point.withMarkerColor(markerColor!),
      );
      final position = LatLng(point.latitude, point.longitude);
      if (_googleMap case final controller?) {
        await controller.moveCamera(google.CameraUpdate.newLatLngZoom(googlePoint(position), 16));
      } else if (_osmReady) {
        map.move(position, 16);
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = '현재 위치를 찾지 못했습니다. 지도에서 원하는 위치를 선택해주세요.');
      }
    } finally {
      if (mounted && request == generation) {
        locateTimer?.cancel();
        setState(() => busy = false);
      }
    }
  }

  void select(LatLng point) {
    setState(() {
      generation++;
      locateTimer?.cancel();
      busy = false;
      error = null;
      selected = ThoughtLocation(
        point.latitude,
        ((point.longitude + 180) % 360) - 180,
        0,
        DateTime.now(),
        isCurrentLocation: false,
        markerColor: markerColor,
      );
    });
  }

  @override
  void dispose() {
    generation++;
    locateTimer?.cancel();
    map.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = selected;
    final height = math.max(
      240.0,
      math.min(
        660.0,
        MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            48,
      ),
    );
    return PopScope(
      canPop: !saving,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 640,
          height: height,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.compose ? '지오로그 남기기' : '위치 선택',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '마커 색상',
                      style: IconButton.styleFrom(
                        fixedSize: const Size(32, 32),
                        minimumSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      visualDensity: VisualDensity.standard,
                      onPressed: saving ? null : color,
                      icon: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: point == null
                              ? Color(
                                  markerColor ??
                                      activeMapMarkerColor.toARGB32(),
                                )
                              : locationMarkerColor(point),
                        ),
                      ),
                    ),
                    action(
                      '현재 위치',
                      Icons.my_location,
                      busy || saving ? null : locate,
                    ),
                  ],
                ),
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!, style: Theme.of(context).textTheme.bodySmall),
                Expanded(
                  child: ClipRect(
                    child: WorkspaceMapSurface(
                      googleMap: (_) => GoogleThoughtMap(
                        initialCameraPosition: google.CameraPosition(
                          target: point == null
                              ? const google.LatLng(20, 0)
                              : google.LatLng(point.latitude, point.longitude),
                          zoom: point == null ? 2 : 16,
                        ),
                        onMapCreated: (controller) => _googleMap = controller,
                        onTap: saving ? null : (position) =>
                            select(LatLng(position.latitude, position.longitude)),
                        pins: [
                          if (point != null)
                            GoogleThoughtPin(
                              id: 'location',
                              position: google.LatLng(point.latitude, point.longitude),
                              color: locationMarkerColor(point),
                            ),
                        ],
                      ),
                      osmMap: (_) => FlutterMap(
                          mapController: map,
                          options: MapOptions(
                            initialCenter: point == null
                                ? const LatLng(20, 0)
                                : LatLng(point.latitude, point.longitude),
                            initialZoom: point == null ? 2 : 16,
                            minZoom: 2,
                            maxZoom: 19,
                            onMapReady: () {
                              _googleMap = null;
                              _osmReady = true;
                            },
                            onTap: saving ? null : (_, position) => select(position),
                          ),
                          children: [
                            const RegionalTileLayer(),
                            MarkerLayer(
                              markers: [
                                if (point != null)
                                  Marker(
                                    point: LatLng(
                                      point.latitude,
                                      point.longitude,
                                    ),
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.topCenter,
                                    child: Icon(
                                      Icons.location_on,
                                      size: 40,
                                      color: locationMarkerColor(point),
                                    ),
                                  ),
                              ],
                            ),
                            const MapAttribution(),
                          ],
                        ),
                    ),
                  ),
                ),
                if (point != null)
                  Text(
                    '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (widget.compose)
                  Row(
                    children: [
                      const Expanded(child: Text('생각')),
                      action(
                        '음성 메모',
                        Icons.mic_none,
                        saving || attaching ? null : recordVoice,
                      ),
                      const SizedBox(width: 2),
                      action(
                        '사진 업로드 (최대 5장)',
                        Icons.add_photo_alternate_outlined,
                        saving || attaching || photos.length >= 5
                            ? null
                            : pickPhotos,
                      ),
                    ],
                  ),
                if (widget.compose)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height * .45),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (voice != null)
                            Row(
                              children: [
                                Expanded(
                                  child: VoicePlayer(
                                    load: () async => voice!.bytes,
                                    durationMs: voice!.durationMs, transcript:voice!.transcript,transcription:voice!.transcription,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '음성 삭제',
                                  onPressed: saving
                                      ? null
                                      : () => setState(() => voice = null),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          if (photos.isNotEmpty)
                            SizedBox(
                              height: 72,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final photo in photos)
                                    SizedBox(
                                      width: 72,
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: Image.memory(
                                              photo.bytes,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: IconButton(
                                              tooltip: '사진 삭제',
                                              onPressed: saving
                                                  ? null
                                                  : () => setState(
                                                      () =>
                                                          photos.remove(photo),
                                                    ),
                                              icon: const Icon(
                                                Icons.close,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextField(
                              key: const ValueKey('geolog-memo-input'),
                              controller: text,
                              readOnly: saving,
                              minLines: 3,
                              maxLines: 4,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: '이 위치에 남길 생각',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed:
                          saving ||
                              attaching ||
                              point == null ||
                              widget.compose && text.text.trim().isEmpty
                          ? null
                          : save,
                      child: Text(saving ? '저장 중…' : widget.confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
