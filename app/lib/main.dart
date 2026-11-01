import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_api.dart';
import 'feed_client.dart';
import 'feed_page.dart';
import 'l10n/app_localizations.dart';
import 'login_page.dart';
import 'red.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  const base = String.fromEnvironment('API_BASE');
  if (base.isEmpty) {
    throw StateError(
      'API_BASE is empty. Set it in app/.env and pass --dart-define-from-file=.env',
    );
  }
  runApp(AppRoot(baseUrl: base, prefs: prefs));
}

const sessionKey = 'proclan.session';

/// No stored value follows the platform brightness.
/// `dark` and `light` are explicit choices from settings.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs);

  static const key = 'proclan.theme';
  final SharedPreferences _prefs;

  /// `true` is dark, `false` is light. Null follows the system.
  bool? get override {
    return switch (_prefs.getString(key)) {
      'dark' => true,
      'light' => false,
      _ => null,
    };
  }

  bool isDark(Brightness platform) => override ?? platform == Brightness.dark;

  Future<void> setDark(bool value) async {
    await _prefs.setString(key, value ? 'dark' : 'light');
    notifyListeners();
  }
}

/// Null [override] follows the system language until settings picks one.
class LocaleController extends ChangeNotifier {
  LocaleController(this._prefs);

  static const key = 'proclan.locale';
  final SharedPreferences _prefs;

  Locale? get override {
    final code = _prefs.getString(key);
    if (code == 'zh' || code == 'en') {
      return Locale(code!);
    }
    return null;
  }

  Future<void> set(String code) async {
    await _prefs.setString(key, code);
    notifyListeners();
  }

  Future<void> clear() async {
    await _prefs.remove(key);
    notifyListeners();
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.baseUrl, required this.prefs});

  final String baseUrl;
  final SharedPreferences prefs;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late String? _token = widget.prefs.getString(sessionKey);
  late final LocaleController _locales = LocaleController(widget.prefs);
  late final ThemeController _themes = ThemeController(widget.prefs);
  HttpFeedClient? _feed;
  AccountClient? _account;

  @override
  void initState() {
    super.initState();
    final token = _token;
    if (token == null || token.isEmpty) {
      _token = null;
      return;
    }
    _open(token);
  }

  /// The feed and settings routes keep the first clients. A new session
  /// updates those instances; rebuilding [MaterialApp.home] does not.
  void _open(String token) {
    final feed = _feed;
    final account = _account;
    if (feed == null || account == null) {
      _feed = HttpFeedClient(baseUrl: widget.baseUrl, token: token);
      _account = AccountClient(baseUrl: widget.baseUrl, token: token);
      return;
    }
    feed.token = token;
    account.token = token;
  }

  Future<void> _setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await widget.prefs.remove(sessionKey);
      token = null;
    } else {
      await widget.prefs.setString(sessionKey, token);
      _open(token);
    }
    if (!mounted) {
      return;
    }
    final stay = (_token != null) == (token != null);
    _token = token;
    if (token == null) {
      _feed = null;
      _account = null;
    }
    if (stay) {
      return;
    }
    setState(() {});
  }

  Future<void> _logout() async {
    final account = _account;
    if (account != null && account.token.isNotEmpty) {
      try {
        await account.logout();
      } catch (_) {}
    }
    await _setToken(null);
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    final feed = _feed;
    final account = _account;
    if (token == null || feed == null || account == null) {
      return ProclanShell(
        locales: _locales,
        themes: _themes,
        home: LoginPage(
          client: AccountClient(baseUrl: widget.baseUrl),
          onSignedIn: (next) => _setToken(next),
          onLocale: (code) => _locales.set(code),
        ),
      );
    }
    return ProclanApp(
      client: feed,
      locales: _locales,
      themes: _themes,
      prefs: widget.prefs,
      account: account,
      onLogout: _logout,
    );
  }
}

class ProclanApp extends StatelessWidget {
  const ProclanApp({
    super.key,
    required this.client,
    this.pollEvery = const Duration(seconds: 5),
    this.locale,
    this.locales,
    this.themes,
    this.prefs,
    this.account,
    this.onLogout,
  });

  final FeedClient client;
  final Duration? pollEvery;
  final Locale? locale;
  final LocaleController? locales;
  final ThemeController? themes;
  final SharedPreferences? prefs;
  final AccountClient? account;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) {
    final controller = locales;
    final fixed = locale != null || controller == null;
    final theme = themes;
    return ProclanShell(
      locale: locale,
      locales: locales,
      themes: themes,
      home: FeedPage(
        client: client,
        pollEvery: pollEvery,
        prefs: prefs,
        account: account,
        onLogout: onLogout,
        onTheme: theme == null ? null : (value) => theme.setDark(value),
        onLocale: fixed ? null : (code) => controller.set(code),
        onLocaleClear: fixed ? null : () => controller.clear(),
      ),
    );
  }
}

class ProclanShell extends StatefulWidget {
  const ProclanShell({
    super.key,
    required this.home,
    this.locale,
    this.locales,
    this.themes,
  });

  final Widget home;
  final Locale? locale;
  final LocaleController? locales;
  final ThemeController? themes;

  @override
  State<ProclanShell> createState() => _ProclanShellState();
}

class _ProclanShellState extends State<ProclanShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (widget.themes != null && widget.themes!.override == null) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.locales;
    final theme = widget.themes;
    final listenLocale = controller != null && widget.locale == null;
    if (!listenLocale && theme == null) {
      Red.apply(true);
      return _material(widget.locale, widget.home);
    }
    final listenable = listenLocale && theme != null
        ? Listenable.merge([controller, theme])
        : listenLocale
        ? controller
        : theme!;
    return ListenableBuilder(
      listenable: listenable,
      builder: (_, _) {
        final platform =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        Red.apply(theme?.isDark(platform) ?? true);
        final next = listenLocale ? controller.override : widget.locale;
        return _material(next, widget.home);
      },
    );
  }
}

Widget _material(Locale? locale, Widget home) {
  final body = Red.text();
  return MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    localeResolutionCallback: (device, supported) {
      if (device == null) {
        return const Locale('zh');
      }
      for (final item in supported) {
        if (item.languageCode == device.languageCode) {
          return item;
        }
      }
      return const Locale('zh');
    },
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Red.dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: Red.bg,
      colorScheme:
          (Red.dark ? const ColorScheme.dark() : const ColorScheme.light())
              .copyWith(
                primary: Red.accent,
                onPrimary: Red.accentOn,
                surface: Red.surface,
                onSurface: Red.fg,
                error: Red.danger,
                onError: Red.onDanger,
              ),
      fontFamily: 'PingFang SC',
      fontFamilyFallback: Red.sansFallback,
      textTheme: TextTheme(bodyMedium: body),
      splashColor: Red.accentSoft,
      highlightColor: Red.accentSoft,
    ),
    builder: (context, child) {
      final lightIcons = !Red.dark;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (lightIcons
                    ? SystemUiOverlayStyle.dark
                    : SystemUiOverlayStyle.light)
                .copyWith(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: lightIcons
                      ? Brightness.dark
                      : Brightness.light,
                  statusBarBrightness: lightIcons
                      ? Brightness.light
                      : Brightness.dark,
                  systemNavigationBarColor: Red.bg,
                  systemNavigationBarIconBrightness: lightIcons
                      ? Brightness.dark
                      : Brightness.light,
                ),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: home,
  );
}
