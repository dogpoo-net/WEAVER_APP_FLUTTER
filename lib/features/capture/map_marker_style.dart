import 'capture_models.dart';
import 'package:flutter/material.dart';

const activeMapMarkerColor=Color(0xFFB52D39);

const currentLocationMarkerColor=Color(0xFF1976D2);
Color locationMarkerColor(ThoughtLocation location)=>location.isCurrentLocation?currentLocationMarkerColor:activeMapMarkerColor;
