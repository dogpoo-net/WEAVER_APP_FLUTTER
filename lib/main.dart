import 'features/sync/owned_workspace_gate.dart';
import 'features/sync/owned_workspace.dart';
import 'features/auth/google_auth.dart';
import 'features/auth/email_auth.dart';
import 'features/auth/login_page.dart';
import 'features/auth/email_login_page.dart';
import 'features/inbox/thought_settings.dart';
import 'features/inbox/keyboard_dismiss.dart';
import 'dart:convert';
import 'app_theme.dart';
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
  const MyApp({super.key, this.storage, this.requireLogin = true, this.authClient, this.emailApi});
  final WorkspaceStorage? storage;
  final bool requireLogin;
  final GoogleAuthClient? authClient;
  final EmailAuthApi? emailApi;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final GoogleAuthController _auth;
  String? _verificationToken;
  String? _inviteToken;

  ThemeMode _mode = ThemeMode.dark;
  LightPalette _lightPalette = LightPalette.neutral;
  DarkPalette _darkPalette = DarkPalette.classic;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final fragment = Uri.base.fragment;
    if(fragment.startsWith('invite='))_inviteToken=fragment.substring('invite='.length);
    if (fragment.startsWith('verify-email=')) {
      _verificationToken = fragment.substring('verify-email='.length);
    }
    _auth = GoogleAuthController(widget.authClient ?? SdkGoogleAuthClient(), preferences: widget.storage?.preferences, emailApi: widget.emailApi);
    if (widget.requireLogin) {
      final storage=widget.storage;
      (storage==null ? Future<void>.value() : OwnedWorkspaces(storage).initialize()).then((_) {if(mounted)return _auth.initialize();}).catchError((Object error){if(mounted){_auth.error='로컬 작업공간을 준비하지 못했습니다. 자료를 보존했습니다.';setState((){});}});
    }
    elements.clear();
    showClosedThoughts = widget.storage?.preferences.getBool(closedThoughtsPreference) ?? true;
    _restoreTheme();
  }
  void _restoreTheme() {
    try {
      final raw = widget.storage?.readTheme();
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final mode = ThemeMode.values.byName(data['mode'] as String);
        final palette = LightPalette.values.byName(data['palette'] as String);
        _mode = mode; _lightPalette = palette;
        _darkPalette = DarkPalette.values.where((p) => p.name == data['darkPalette']).firstOrNull ?? DarkPalette.classic;
      }
    } catch (_) { /* Invalid settings fall back to the default theme. */ }
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _auth.dispose(); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _auth.resumeEmailSession();
  }

  void _persistTheme() {
    widget.storage?.writeTheme(jsonEncode({'mode': _mode.name, 'palette': _lightPalette.name, 'darkPalette': _darkPalette.name})).catchError((Object _) {
      if (mounted) _messenger.currentState?.showSnackBar(const SnackBar(content: Text('테마 설정을 저장하지 못했습니다.')));
    });
  }

  ThemeData _theme(Brightness brightness) {
    final colors = brightness == Brightness.dark ? _darkPalette.colors : _lightPalette.colors;
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
  Widget build(BuildContext context) => GoogleAuthScope(controller: _auth, child: ListenableBuilder(listenable: _auth, builder: (context, _) => MaterialApp(
    key: ValueKey(widget.requireLogin ? (_auth.isGuest ? 'guest' : _auth.identity?.id) : 'local-test'),
    title: 'WEAVER',
    initialRoute: '/',
    builder: (context, child) => ThemeControls(mode:_mode,light:_lightPalette,dark:_darkPalette,onChanged:(choice){setState((){if(choice is ThemeMode)_mode=choice;if(choice is LightPalette){_lightPalette=choice;_mode=ThemeMode.light;}if(choice is DarkPalette){_darkPalette=choice;_mode=ThemeMode.dark;}});_persistTheme();},child:Actions(actions: <Type, Action<Intent>>{
      EditableTextTapOutsideIntent: CallbackAction<EditableTextTapOutsideIntent>(onInvoke: (intent) {
        intent.focusNode.unfocus();
        dismissKeyboard();
        return null;
      }),
    }, child: child!)),
    scaffoldMessengerKey: _messenger,
    navigatorObservers: [workspaceRouteObserver],
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: _mode,
    home: _verificationToken != null ? EmailLoginPage(auth: _auth, verificationToken: _verificationToken,
      onVerified: () {
        if (kIsWeb) {
          SystemNavigator.routeInformationUpdated(
            uri: Uri(path: Uri.base.path, query: Uri.base.hasQuery ? Uri.base.query : null), replace: true);
        }
        setState(() => _verificationToken = null);
      }) : widget.requireLogin && !_auth.isGuest && _auth.identity == null ? LoginPage(auth: _auth,invitationPending:_inviteToken!=null) : widget.requireLogin && widget.storage != null ? OwnedWorkspaceGate(root:widget.storage!,auth:_auth,builder:_inbox,inviteToken:_inviteToken,onInviteHandled:(){if(kIsWeb)SystemNavigator.routeInformationUpdated(uri:Uri(path:Uri.base.path),replace:true);if(mounted)setState(()=>_inviteToken=null);}) : _inbox(widget.storage),
  )));

  Widget _inbox(WorkspaceStorage? storage) => InboxPage(
      storage: storage,
      onSettingsImported: () => setState(_restoreTheme),
      themeMode: _mode,
      lightPalette: _lightPalette,
      darkPalette: _darkPalette,
      onDarkPaletteChanged: (palette) {
        setState(() { _darkPalette = palette; _mode = ThemeMode.dark; }); _persistTheme();
      },
      onLightPaletteChanged: (palette) {
        setState(() { _lightPalette = palette; _mode = ThemeMode.light; });
        _persistTheme();
      },
      onThemeChanged: (mode) { setState(() => _mode = mode); _persistTheme(); },
    );
}
