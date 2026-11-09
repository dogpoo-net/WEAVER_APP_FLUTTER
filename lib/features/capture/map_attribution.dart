import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.bottomRight,
    child: Material(color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
      child: InkWell(onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication),
        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10))))));
}
