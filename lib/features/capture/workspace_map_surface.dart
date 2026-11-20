import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart';

import 'google_map_loader_stub.dart'
    if (dart.library.js_interop) 'google_map_loader_web.dart';

typedef WorkspaceMapRequest = Future<Map<String, dynamic>> Function(
  String,
  Map<String, Object?>,
);

WorkspaceMapRequest? _workspaceRequest;
Future<bool>? _configuration;

set workspaceMapRequest(WorkspaceMapRequest? request) {
  _workspaceRequest = request;
  _configuration = null;
}

Future<bool> _loadConfiguration(WorkspaceMapRequest request) async {
  try {
    final response = await request('map/config', {});
    final key = response['key'];
    return request == _workspaceRequest &&
        key is String &&
        key.isNotEmpty &&
        await loadGoogleMaps(key);
  } catch (_) {
    return false;
  }
}

google.LatLng googlePoint(LatLng point) =>
    google.LatLng(point.latitude, point.longitude);

class WorkspaceMapSurface extends StatefulWidget {
  const WorkspaceMapSurface({
    super.key,
    required this.googleMap,
    required this.osmMap,
  });

  final WidgetBuilder googleMap;
  final WidgetBuilder osmMap;

  @override
  State<WorkspaceMapSurface> createState() => _WorkspaceMapSurfaceState();
}

class _WorkspaceMapSurfaceState extends State<WorkspaceMapSurface> {
  late final Future<bool>? _available;

  @override
  void initState() {
    super.initState();
    final request = _workspaceRequest;
    _available = kIsWeb && request != null
        ? (_configuration ??= _loadConfiguration(request))
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_available == null) return widget.osmMap(context);
    return FutureBuilder<bool>(
      future: _available,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data != true) return widget.osmMap(context);
        return ValueListenableBuilder<bool>(
          valueListenable: googleMapsAuthFailed,
          builder: (context, failed, _) =>
              failed ? widget.osmMap(context) : widget.googleMap(context),
        );
      },
    );
  }
}
