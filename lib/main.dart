import 'features/inbox/workspace_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/inbox/workspace_storage.dart';

import 'features/inbox/inbox_page.dart';
import 'features/inbox/element_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the complete Korean font before any editable text is rendered.
  final font = FontLoader('NotoSansKR')
    ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'));
  await font.load();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Noto Sans KR',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  WorkspaceStorage? storage;
  try {
    storage = WorkspaceStorage(await SharedPreferences.getInstance());
  } catch (_) {
    /* Show storage availability in the workspace. */
  }
  runApp(MyApp(storage: storage));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.storage});
  final WorkspaceStorage? storage;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _mode = ThemeMode.dark;
  @override
  void initState() {
    super.initState();
    elements.clear();
  }

  ThemeData _theme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF536DFE),
      brightness: brightness,
    );
    final border = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: colors.outlineVariant),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansKR',
      splashFactory: InkRipple.splashFactory,
      splashColor: colors.primary.withValues(alpha: 0.12),
      highlightColor: colors.primary.withValues(alpha: 0.04),
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: colors.surfaceContainerLow,
        shape: border,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          splashFactory: InkRipple.splashFactory,
          overlayColor: colors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary.withValues(alpha: 0.45)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WEAVER',
    navigatorObservers: [workspaceRouteObserver],
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: _mode,
    home: InboxPage(
      storage: widget.storage,
      themeMode: _mode,
      onThemeChanged: (mode) => setState(() => _mode = mode),
    ),
  );
}
