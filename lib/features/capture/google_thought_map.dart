import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

class GoogleThoughtPin {
  const GoogleThoughtPin({
    required this.id,
    required this.position,
    required this.color,
    this.label,
    this.onTap,
  });

  final String id;
  final google.LatLng position;
  final Color color;
  final String? label;
  final VoidCallback? onTap;
}

typedef _PinAppearance = ({Color color, String? label});

class GoogleThoughtMap extends StatefulWidget {
  const GoogleThoughtMap({
    super.key,
    required this.initialCameraPosition,
    required this.pins,
    this.polylines = const {},
    this.onMapCreated,
    this.onTap,
  });

  final google.CameraPosition initialCameraPosition;
  final List<GoogleThoughtPin> pins;
  final Set<google.Polyline> polylines;
  final google.MapCreatedCallback? onMapCreated;
  final ValueChanged<google.LatLng>? onTap;

  @override
  State<GoogleThoughtMap> createState() => _GoogleThoughtMapState();
}

class _GoogleThoughtMapState extends State<GoogleThoughtMap> {
  final _icons = <_PinAppearance, Future<google.BitmapDescriptor>>{};
  Future<Map<_PinAppearance, google.BitmapDescriptor>>? _readyIcons;

  _PinAppearance _appearance(GoogleThoughtPin pin) => (
    color: pin.color,
    label: pin.label?.trim().replaceAll(RegExp(r'\s+'), ' '),
  );

  @override
  Widget build(BuildContext context) {
    final appearances = widget.pins.map(_appearance).toSet();
    if (_readyIcons == null || !setEquals(appearances, _icons.keys.toSet())) {
      _icons.removeWhere((appearance, _) => !appearances.contains(appearance));
      for (final appearance in appearances) {
        _icons.putIfAbsent(appearance, () => _drawPin(appearance));
      }
      _readyIcons = Future.wait(
        _icons.entries.map(
          (entry) async => MapEntry(entry.key, await entry.value),
        ),
      ).then(Map.fromEntries);
    }
    return FutureBuilder(
      future: _readyIcons,
      builder: (context, snapshot) => google.GoogleMap(
        initialCameraPosition: widget.initialCameraPosition,
        onMapCreated: widget.onMapCreated,
        onTap: widget.onTap,
        polylines: widget.polylines,
        markers: {
          for (final pin in widget.pins)
            if (snapshot.data?[_appearance(pin)] case final icon?)
              google.Marker(
                markerId: google.MarkerId(pin.id),
                position: pin.position,
                icon: icon,
                consumeTapEvents: pin.onTap != null,
                onTap: pin.onTap,
              ),
        },
      ),
    );
  }
}

Future<google.BitmapDescriptor> _drawPin(_PinAppearance appearance) async {
  const scale = 2;
  final label = appearance.label;
  final text = label == null || label.isEmpty
      ? null
      : (TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Color(0xff202124),
              fontSize: 11,
              fontFamily: 'Pretendard',
              fontFamilyFallback: ['Noto Sans'],
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 112));
  final width = text == null ? 24 : (text.width + 16).ceil().clamp(24, 128);
  final height = text == null ? 26 : 49;
  final center = width / 2;
  final pinTop = height - 25.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale.toDouble());
  if (text != null) {
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, width - 2.0, 19),
      const Radius.circular(6),
    );
    canvas.drawRRect(bubble, Paint()..color = const Color(0xcfffffff));
    canvas.drawRRect(
      bubble,
      Paint()
        ..color = const Color(0x30000000)
        ..style = PaintingStyle.stroke,
    );
    text.paint(canvas, Offset(center - text.width / 2, 10.5 - text.height / 2));
    text.dispose();
  }

  final pin = Path()
    ..moveTo(center, height - 1)
    ..cubicTo(
      center - 5,
      height - 8,
      center - 10,
      pinTop + 15,
      center - 10,
      pinTop + 10,
    )
    ..arcToPoint(
      Offset(center + 10, pinTop + 10),
      radius: const Radius.circular(10),
    )
    ..cubicTo(
      center + 10,
      pinTop + 15,
      center + 5,
      height - 8,
      center,
      height - 1,
    )
    ..close();
  canvas.drawPath(pin, Paint()..color = appearance.color);
  canvas.drawPath(
    pin,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
  canvas.drawCircle(
    Offset(center, pinTop + 10),
    3,
    Paint()..color = Colors.white,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width * scale, height * scale);
  picture.dispose();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return google.BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      width: width.toDouble(),
      height: height.toDouble(),
    );
  } finally {
    image.dispose();
  }
}
