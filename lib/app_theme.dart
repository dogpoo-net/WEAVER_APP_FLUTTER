import 'package:flutter/material.dart';

/// Add light color sets here; brightness remains a separate user choice.
enum LightPalette { neutral, beige }

ColorScheme get weaverDarkColors => ColorScheme.fromSeed(
  seedColor: const Color(0xFF536DFE), brightness: Brightness.dark);

extension LightPaletteColors on LightPalette {
  String get label => switch (this) { LightPalette.neutral => '화이트·그레이', LightPalette.beige => '베이지' };
  ColorScheme get colors {
    if (this == LightPalette.beige) { return ColorScheme.fromSeed(seedColor: const Color(0xFF876747), brightness: Brightness.light).copyWith(
            primary: const Color(0xFF795A39),
            onPrimary: const Color(0xFFFFFFFF),
            primaryContainer: const Color(0xFFEDDDC7),
            onPrimaryContainer: const Color(0xFF30200E),
            secondary: const Color(0xFF74644E),
            onSecondary: const Color(0xFFFFFFFF),
            secondaryContainer: const Color(0xFFEADFCF),
            onSecondaryContainer: const Color(0xFF2D251B),
            tertiary: const Color(0xFF5E6E55),
            onTertiary: const Color(0xFFFFFFFF),
            surface: const Color(0xFFF8F4EC),
            surfaceDim: const Color(0xFFE4DCCD),
            surfaceBright: const Color(0xFFFDF9F1),
            surfaceContainerLowest: const Color(0xFFFFFBF5),
            surfaceContainerLow: const Color(0xFFF5EEE2),
            surfaceContainer: const Color(0xFFEFE6D8),
            surfaceContainerHigh: const Color(0xFFE9DFD0),
            surfaceContainerHighest: const Color(0xFFE3D7C6),
            onSurface: const Color(0xFF302B25),
            onSurfaceVariant: const Color(0xFF645B4D),
            outline: const Color(0xFF8C7F6B),
            outlineVariant: const Color(0xFFD5C8B5),
          ); }
    return ColorScheme.fromSeed(seedColor: const Color(0xFF666666), brightness: Brightness.light,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome).copyWith(
        primary: const Color(0xFF484848), onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFE6E6E6), onPrimaryContainer: const Color(0xFF242424),
        secondary: const Color(0xFF606060), onSecondary: const Color(0xFFFFFFFF),
        secondaryContainer: const Color(0xFFEEEEEE), onSecondaryContainer: const Color(0xFF292929),
        tertiary: const Color(0xFF666666), onTertiary: const Color(0xFFFFFFFF),
        tertiaryContainer: const Color(0xFFECECEC), onTertiaryContainer: const Color(0xFF292929),
        surface: const Color(0xFFFAFAFA), surfaceDim: const Color(0xFFDDDDDD),
        surfaceBright: const Color(0xFFFFFFFF), surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF5F5F5), surfaceContainer: const Color(0xFFF0F0F0),
        surfaceContainerHigh: const Color(0xFFEBEBEB), surfaceContainerHighest: const Color(0xFFE5E5E5),
        onSurface: const Color(0xFF242424), onSurfaceVariant: const Color(0xFF606060),
        outline: const Color(0xFF939393), outlineVariant: const Color(0xFFD6D6D6),
        surfaceTint: const Color(0xFF666666),
      );
  }
  List<Color> get swatches => [colors.surface, colors.surfaceContainerHighest, colors.primary];
}

class PaletteSwatches extends StatelessWidget {
  const PaletteSwatches({super.key, required this.colors});
  final List<Color> colors;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    for (final color in colors) Container(width: 17, height: 20,
      margin: const EdgeInsetsDirectional.only(start: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant))),
  ]);
}

enum DarkPalette { classic, charcoal, navy, forest }
extension DarkPaletteColors on DarkPalette {
  String get label => switch (this) {
    DarkPalette.classic => '기본 다크', DarkPalette.charcoal => '차콜', DarkPalette.navy => '네이비', DarkPalette.forest => '포레스트',
  };
  ColorScheme get colors => switch (this) {
    DarkPalette.classic => weaverDarkColors,
    DarkPalette.charcoal => ColorScheme.fromSeed(seedColor: const Color(0xFF7C838A), brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome).copyWith(
        surface: const Color(0xFF17191B), surfaceContainerLowest: const Color(0xFF111315),
        surfaceContainerLow: const Color(0xFF1E2124), surfaceContainer: const Color(0xFF25292D),
        surfaceContainerHigh: const Color(0xFF2B3035), surfaceContainerHighest: const Color(0xFF343A40),
        primary: const Color(0xFFD3D7DC), onPrimary: const Color(0xFF282C30),
        primaryContainer: const Color(0xFF3F464D), onPrimaryContainer: const Color(0xFFE2E7EC)),
    DarkPalette.navy => ColorScheme.fromSeed(seedColor: const Color(0xFF657DAA), brightness: Brightness.dark).copyWith(
      surface: const Color(0xFF111A2B), surfaceContainerLowest: const Color(0xFF0B1220),
      surfaceContainerLow: const Color(0xFF172339), surfaceContainer: const Color(0xFF1D2C45),
      surfaceContainerHigh: const Color(0xFF253651), surfaceContainerHighest: const Color(0xFF2D405F)),
    DarkPalette.forest => ColorScheme.fromSeed(seedColor: const Color(0xFF4F8063), brightness: Brightness.dark).copyWith(
      surface: const Color(0xFF12221C), surfaceContainerLowest: const Color(0xFF0C1813),
      surfaceContainerLow: const Color(0xFF192E25), surfaceContainer: const Color(0xFF20382D),
      surfaceContainerHigh: const Color(0xFF284338), surfaceContainerHighest: const Color(0xFF314F40)),
  };
  List<Color> get swatches => [colors.surface, colors.surfaceContainerHighest, colors.primary];
}
