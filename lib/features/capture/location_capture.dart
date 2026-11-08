import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'capture_models.dart';

Future<ThoughtLocation> captureLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('기기의 위치 서비스를 켜주세요.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw StateError('위치 권한이 필요합니다. 기기 또는 브라우저 설정에서 허용해주세요.');
  }
  try {
    final position = await Geolocator.getCurrentPosition(locationSettings:
      const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
    return ThoughtLocation(position.latitude, position.longitude, position.accuracy, position.timestamp);
  } on TimeoutException {
    throw StateError('현재 위치를 찾지 못했습니다. 위치 기록을 다시 켜서 시도해주세요.');
  }
}
