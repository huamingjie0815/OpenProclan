import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_api.dart';
import 'chrome.dart';
import 'detail_page.dart';
import 'feed_client.dart';
import 'l10n/app_localizations.dart';
import 'red.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.unreadOnly,
    required this.onUnreadOnly,
    required this.unreadCount,
    required this.cacheMode,
    required this.onCacheMode,
    this.onLocale,
    this.onTheme,
    this.syncSeconds,
    this.account,
    this.feed,
    this.onCardOpened,
    this.onCardResult,
    this.onLogout,
  });

  final bool unreadOnly;
  final ValueChanged<bool> onUnreadOnly;
  final int unreadCount;
  final String cacheMode;
  final ValueChanged<String> onCacheMode;
  final ValueChanged<String>? onLocale;
  final ValueChanged<bool>? onTheme;
  final int? syncSeconds;
  final AccountClient? account;
  final FeedClient? feed;
  final void Function(FeedCard card)? onCardOpened;
  final void Function(FeedCard card, DetailResult result)? onCardResult;
  final Future<void> Function()? onLogout;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late var _unread = widget.unreadOnly;
  late var _cache = widget.cacheMode;
  var _screen = _AccountScreen.hub;
  late final AccountClient? _account = widget.account;

  final _username = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();

  String? _token;
  var _tokenShown = false;
  var _busy = false;
  List<String> _bots = const [];
  String? _botName;
  BotProfile? _botProfile;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  @override
  void dispose() {
    _username.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _loadAccount() async {
    final account = _account;
    if (account == null) {
      return;
    }
    try {
      final user = await account.me();
      final bots = await account.bots();
      if (!mounted) {
        return;
      }
      setState(() {
        _username.text = user.username;
        _bots = bots;
      });
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    try {
      await action();
    } on AccountException catch (error) {
      if (!mounted) {
        return;
      }
      showRedNotice(context, accountMessage(l, error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      showRedNotice(context, l.offline);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveUsername() {
    final account = _account;
    if (account == null) {
      return Future.value();
    }
    return _run(() async {
      final user = await account.patchUsername(_username.text);
      if (!mounted) {
        return;
      }
      setState(() => _username.text = user.username);
      showRedNotice(context, AppLocalizations.of(context).saved);
    });
  }

  Future<void> _savePassword() {
    final account = _account;
    if (account == null) {
      return Future.value();
    }
    final l = AppLocalizations.of(context);
    final current = _currentPassword.text;
    final password = _newPassword.text;
    if (current.isEmpty) {
      showRedNotice(context, l.wrongPassword);
      return Future.value();
    }
    if (password.length < 8 || password.length > 128) {
      showRedNotice(context, l.invalidPassword);
      return Future.value();
    }
    return _run(() async {
      await account.changePassword(
        currentPassword: current,
        newPassword: password,
      );
      if (!mounted) {
        return;
      }
      await widget.onLogout?.call();
    });
  }

  Future<String?> _ensureToken() async {
    final existing = _token;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final account = _account;
    if (account == null) {
      return null;
    }
    final token = await account.botToken();
    if (!mounted) {
      return null;
    }
    setState(() => _token = token);
    return token;
  }

  Future<void> _toggleToken() {
    if (_token != null) {
      setState(() => _tokenShown = !_tokenShown);
      return Future.value();
    }
    return _run(() async {
      await _ensureToken();
      if (!mounted) {
        return;
      }
      setState(() => _tokenShown = true);
    });
  }

  Future<void> _copyToken() {
    return _run(() async {
      final token = await _ensureToken();
      if (token == null || token.isEmpty || !mounted) {
        return;
      }
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) {
        return;
      }
      showRedNotice(context, AppLocalizations.of(context).copied);
    });
  }

  Future<void> _copyMcpPrompt() {
    return _run(() async {
      final token = await _ensureToken();
      final account = _account;
      if (token == null || token.isEmpty || account == null || !mounted) {
        return;
      }
      await Clipboard.setData(
        ClipboardData(
          text: mcpSetupPrompt(
            AppLocalizations.of(context),
            url: mcpUrl(account.baseUrl),
            token: token,
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      showRedNotice(context, AppLocalizations.of(context).copied);
    });
  }

  Future<void> _rotate() async {
    final l = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l.rotateTitle,
      body: l.rotateBody,
      action: l.rotateToken,
    );
    if (!ok || !mounted) {
      return;
    }
    await _run(() async {
      final token = await _account!.rotateBotToken();
      if (!mounted) {
        return;
      }
      setState(() {
        _token = token;
        _tokenShown = true;
      });
      showRedNotice(context, AppLocalizations.of(context).rotated);
    });
  }

  Future<void> _logout() async {
    final l = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l.logoutTitle,
      body: l.logoutBody,
      action: l.logout,
    );
    if (!ok || !mounted) {
      return;
    }
    await widget.onLogout?.call();
  }

  void _open(_AccountScreen screen) {
    setState(() => _screen = screen);
  }

  void _back() {
    if (_screen == _AccountScreen.hub) {
      Navigator.pop(context);
      return;
    }
    if (_screen == _AccountScreen.password) {
      _open(_AccountScreen.security);
      return;
    }
    if (_screen == _AccountScreen.bot) {
      _open(_AccountScreen.bots);
      return;
    }
    _open(_AccountScreen.hub);
  }

  Future<void> _openBot(String name) async {
    setState(() {
      _screen = _AccountScreen.bot;
      _botName = name;
      _botProfile = null;
    });
    final account = _account;
    if (account == null) {
      return;
    }
    await _run(() async {
      final profile = await account.botProfile(name);
      if (!mounted || _botName != name) {
        return;
      }
      setState(() => _botProfile = profile);
    });
    if (mounted &&
        _screen == _AccountScreen.bot &&
        _botName == name &&
        _botProfile == null) {
      setState(() => _screen = _AccountScreen.bots);
    }
  }

  Future<void> _openCard(FeedCard card) async {
    final feed = widget.feed;
    if (feed == null) {
      return;
    }
    widget.onCardOpened?.call(card);
    final result = await openCardDetail(
      context,
      card: card,
      client: feed,
      backTooltip: AppLocalizations.of(context).accountBack,
    );
    if (!mounted || result == null) {
      return;
    }
    widget.onCardResult?.call(card, result);
    if (result != DetailResult.deleted) {
      return;
    }
    final profile = _botProfile;
    if (profile == null) {
      return;
    }
    setState(() {
      _botProfile = BotProfile(
        name: profile.name,
        firstSeen: profile.firstSeen,
        botDesc: profile.botDesc,
        cards: [
          for (final item in profile.cards)
            if (item.id != card.id) item,
        ],
      );
    });
  }

  Future<void> _deleteBot() async {
    final name = _botName;
    final account = _account;
    if (name == null || account == null) {
      return;
    }
    final l = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l.botDeleteTitle,
      body: l.botDeleteBody,
      action: l.botDelete,
    );
    if (!ok || !mounted) {
      return;
    }
    await _run(() async {
      await account.deleteBot(name);
      if (!mounted) {
        return;
      }
      setState(() {
        _bots = [
          for (final item in _bots)
            if (item != name) item,
        ];
        _botName = null;
        _botProfile = null;
        _screen = _AccountScreen.bots;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final l = AppLocalizations.of(context);
    final en = Localizations.localeOf(context).languageCode == 'en';
    final width = MediaQuery.sizeOf(context).width;
    final pad = Red.gutter(width);
    final signedIn = _account != null;
    final seconds = widget.syncSeconds;
    final title = switch (_screen) {
      _AccountScreen.hub => l.me,
      _AccountScreen.prefs => l.preferences,
      _AccountScreen.security => l.security,
      _AccountScreen.password => l.passwordSection,
      _AccountScreen.bots => l.bots,
      _AccountScreen.bot => _botName ?? l.bots,
      _AccountScreen.privacy => l.privacy,
    };
    return PopScope(
      canPop: _screen == _AccountScreen.hub,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _back();
      },
      child: Scaffold(
        backgroundColor: Red.bg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Bar(title: title, close: l.accountBack, onBack: _back),
            Expanded(
              child: RedCenter(
                maxWidth: Red.articleColumn,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(pad, 24, pad, 72),
                  children: [
                    if (_screen == _AccountScreen.hub)
                      _Hub(
                        name: _username.text.trim(),
                        bots: _bots.length,
                        unread: widget.unreadCount,
                        cache: switch (_cache) {
                          '1d' => l.cache1d,
                          'after_read' => l.cacheAfterRead,
                          _ => l.cache7d,
                        },
                        signedIn: signedIn,
                        onEdit: () => _open(_AccountScreen.security),
                        onPrefs: () => _open(_AccountScreen.prefs),
                        onSecurity: () => _open(_AccountScreen.security),
                        onBots: () => _open(_AccountScreen.bots),
                        onPrivacy: () => _open(_AccountScreen.privacy),
                        onLogout: signedIn ? _logout : null,
                      ),
                    if (_screen == _AccountScreen.prefs) ...[
                      _Block(
                        title: l.appearance,
                        note: l.appearanceNote,
                        child: _Segmented(
                          children: [
                            _Seg(
                              label: l.themeDark,
                              selected: Red.dark,
                              onTap: () => _setTheme(true),
                            ),
                            _Seg(
                              label: l.themeLight,
                              selected: !Red.dark,
                              onTap: () => _setTheme(false),
                            ),
                          ],
                        ),
                      ),
                      _Panel(
                        children: [
                          _Language(
                            note: l.languageNote,
                            title: l.language,
                            en: en,
                            onLocale: widget.onLocale,
                          ),
                          _SettingRow(
                            title: l.unreadOnly,
                            note: l.unreadNote,
                            trailing: _Switch(
                              key: const Key('unread-switch'),
                              value: _unread,
                              label: l.unreadOnly,
                              onChanged: (value) {
                                setState(() => _unread = value);
                                widget.onUnreadOnly(value);
                              },
                            ),
                          ),
                          if (seconds != null)
                            _SettingRow(
                              title: l.autoSync,
                              note: l.autoSyncNote(seconds),
                              trailing: Text(
                                l.running,
                                style: Red.text(
                                  size: 12,
                                  color: Red.fg2,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          _Cache(
                            title: l.cacheMode,
                            note: l.cacheNote,
                            mode: _cache,
                            labels: (l.cache7d, l.cache1d, l.cacheAfterRead),
                            onChanged: (mode) {
                              setState(() => _cache = mode);
                              widget.onCacheMode(mode);
                            },
                          ),
                        ],
                      ),
                    ],
                    if (_screen == _AccountScreen.security && signedIn) ...[
                      _Block(
                        title: l.account,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _LineField(
                              controller: _username,
                              label: l.username,
                            ),
                            const SizedBox(height: 7),
                            Text(l.usernameNote, style: _formNote),
                            const SizedBox(height: 14),
                            _SaveButton(
                              label: l.save,
                              onPressed: _busy ? null : _saveUsername,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _TocCard(
                        children: [
                          _TocRow(
                            icon: Icons.key_outlined,
                            title: l.passwordSection,
                            subtitle: l.passwordPageSub,
                            onTap: () => _open(_AccountScreen.password),
                          ),
                        ],
                      ),
                    ],
                    if (_screen == _AccountScreen.password && signedIn)
                      _Block(
                        title: l.passwordSection,
                        note: l.passwordLead,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _LineField(
                              controller: _currentPassword,
                              label: l.currentPassword,
                              secret: true,
                            ),
                            const SizedBox(height: 14),
                            _LineField(
                              controller: _newPassword,
                              label: l.newPassword,
                              secret: true,
                            ),
                            const SizedBox(height: 7),
                            Text(l.passwordNote, style: _formNote),
                            const SizedBox(height: 14),
                            _SaveButton(
                              label: l.passwordSection,
                              onPressed: _busy ? null : _savePassword,
                            ),
                          ],
                        ),
                      ),
                    if (_screen == _AccountScreen.bots && signedIn) ...[
                      _Block(
                        title: l.bots,
                        note: l.botsNote,
                        child: _bots.isEmpty
                            ? Text(
                                l.botsEmpty,
                                style: Red.text(size: 14, height: 1.5),
                              )
                            : Column(
                                children: [
                                  for (final name in _bots)
                                    InkWell(
                                      key: Key('bot-$name'),
                                      onTap: _busy
                                          ? null
                                          : () => _openBot(name),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            _Initial(text: name),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: Red.text(
                                                  size: 14,
                                                  height: 1.4,
                                                  weight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right,
                                              size: 16,
                                              color: Red.meta,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Red.surfaceWarm,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Red.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.botToken.toUpperCase(),
                                style: Red.text(
                                  size: 10,
                                  height: 1.4,
                                  weight: FontWeight.w500,
                                  letterSpacing: 1.2,
                                  color: Red.meta,
                                ),
                              ),
                              const SizedBox(height: 14),
                              SelectableText(
                                _tokenShown && _token != null
                                    ? _token!
                                    : '••••••••••••••••',
                                style: Red.text(
                                  size: 13,
                                  height: 1.6,
                                  color: Red.fg2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _TextAction(
                                    label: _tokenShown
                                        ? l.hideToken
                                        : l.showToken,
                                    onPressed: _busy ? null : _toggleToken,
                                  ),
                                  _TextAction(
                                    label: l.copyToken,
                                    onPressed: _busy ? null : _copyToken,
                                  ),
                                  _TextAction(
                                    label: l.rotateToken,
                                    onPressed: _busy ? null : _rotate,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l.tokenNote,
                                style: Red.text(
                                  size: 10,
                                  height: 1.6,
                                  color: Red.meta,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _TextAction(
                                key: const Key('copy-mcp-prompt'),
                                label: l.copyMcpPrompt,
                                onPressed: _busy ? null : _copyMcpPrompt,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_screen == _AccountScreen.bot &&
                        signedIn &&
                        _botProfile != null)
                      _BotBody(
                        profile: _botProfile!,
                        busy: _busy,
                        onDelete: _deleteBot,
                        onOpen: _openCard,
                      ),
                    if (_screen == _AccountScreen.privacy) const _PrivacyBody(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setTheme(bool dark) {
    final onTheme = widget.onTheme;
    if (onTheme != null) {
      onTheme(dark);
      return;
    }
    Red.apply(dark);
    setState(() {});
  }
}

String mcpUrl(String baseUrl) {
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return '$base/mcp';
}

String mcpSetupPrompt(
  AppLocalizations l, {
  required String url,
  required String token,
}) {
  const body =
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"proclan","version":"0"}}}';
  final command = [
    'curl -sS $url \\',
    '  -H "Authorization: Bearer $token" \\',
    '  -H "Accept: application/json, text/event-stream" \\',
    '  -H "Content-Type: application/json" \\',
    "  -d '$body'",
  ].join('\n');
  return '${l.mcpPrompt(url, token)}\n\n$command';
}

enum _AccountScreen { hub, prefs, security, password, bots, bot, privacy }

class _BotBody extends StatelessWidget {
  const _BotBody({
    required this.profile,
    required this.busy,
    required this.onDelete,
    required this.onOpen,
  });

  final BotProfile profile;
  final bool busy;
  final VoidCallback onDelete;
  final ValueChanged<FeedCard> onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final when = detailWhen(l, profile.firstSeen);
    final cards = profile.cards;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: l.botProfile,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Initial(text: profile.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      profile.name,
                      style: Red.text(
                        size: 16,
                        height: 1.35,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Eyebrow(l.botFirstSeen),
              const SizedBox(height: 4),
              Text(when, style: Red.text(size: 14, height: 1.4)),
              const SizedBox(height: 16),
              _Eyebrow(l.botDesc),
              const SizedBox(height: 4),
              Text(
                profile.botDesc.isEmpty ? l.botDescEmpty : profile.botDesc,
                style: Red.text(size: 14, height: 1.5),
              ),
            ],
          ),
        ),
        _Block(
          title: l.botLatest,
          child: cards.isEmpty
              ? Text(l.botLatestEmpty, style: Red.text(size: 14, height: 1.5))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) ...[
                        const SizedBox(height: 12),
                        Divider(height: 1, color: Red.border),
                        const SizedBox(height: 12),
                      ],
                      _PushRow(card: cards[i], onTap: () => onOpen(cards[i])),
                    ],
                  ],
                ),
        ),
        OutlinedButton.icon(
          key: const Key('delete-bot'),
          onPressed: busy ? null : onDelete,
          icon: Icon(Icons.delete_outline, size: 15, color: Red.dangerFg),
          label: Text(l.botDelete.toUpperCase()),
          style: OutlinedButton.styleFrom(
            foregroundColor: Red.dangerFg,
            disabledForegroundColor: Red.muted,
            side: BorderSide(color: Red.dangerLine),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            textStyle: Red.text(
              size: 11,
              height: 1,
              weight: FontWeight.w500,
              letterSpacing: 0.4,
              color: Red.dangerFg,
            ),
          ),
        ),
      ],
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Red.text(
        size: 10,
        height: 1.4,
        weight: FontWeight.w500,
        letterSpacing: 1.2,
        color: Red.meta,
      ),
    );
  }
}

class _PushRow extends StatelessWidget {
  const _PushRow({required this.card, required this.onTap});

  final FeedCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final source = [
      if (card.source.isNotEmpty) card.source,
      detailWhen(l, card.createdAt),
    ].where((item) => item.isNotEmpty).join(' · ');
    return InkWell(
      key: Key('bot-card-${card.id}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Eyebrow(categoryLabel(l, card.category)),
          const SizedBox(height: 8),
          Text(
            card.title,
            style: Red.text(size: 16, height: 1.35, weight: FontWeight.w500),
          ),
          if (card.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              card.summary,
              style: Red.text(size: 13, height: 1.5, color: Red.fg2),
            ),
          ],
          if (source.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              source,
              style: Red.text(size: 11, height: 1.4, color: Red.meta),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hub extends StatelessWidget {
  const _Hub({
    required this.name,
    required this.bots,
    required this.unread,
    required this.cache,
    required this.signedIn,
    required this.onEdit,
    required this.onPrefs,
    required this.onSecurity,
    required this.onBots,
    required this.onPrivacy,
    required this.onLogout,
  });

  final String name;
  final int bots;
  final int unread;
  final String cache;
  final bool signedIn;
  final VoidCallback onEdit;
  final VoidCallback onPrefs;
  final VoidCallback onSecurity;
  final VoidCallback onBots;
  final VoidCallback onPrivacy;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shown = name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Red.surfaceWarm,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Red.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Red.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SizedBox(
                        width: 58,
                        height: 58,
                        child: Center(
                          child: Text(
                            nameMark(shown),
                            style: Red.text(
                              size: 24,
                              height: 1,
                              weight: FontWeight.w500,
                              color: Red.accentOn,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shown,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Red.text(
                              size: 25,
                              height: 1.15,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (signedIn)
                      OutlinedButton(
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Red.fg2,
                          side: BorderSide(color: Red.border),
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          textStyle: Red.text(size: 11, height: 1),
                        ),
                        child: Text(l.profileEdit),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Red.border)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        _Stat(
                          value: '$bots',
                          label: l.statBots,
                          edge: false,
                          valueKey: const Key('stat-bots'),
                        ),
                        _Stat(value: '$unread', label: l.statUnread),
                        _Stat(value: cache, label: l.statCache),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _TocLabel(l.reading),
        _TocCard(
          children: [
            _TocRow(
              key: const Key('account-prefs'),
              icon: Icons.tune,
              title: l.preferences,
              subtitle: l.preferencesSub,
              onTap: onPrefs,
            ),
            if (signedIn) ...[
              _TocRow(
                icon: Icons.person_outline,
                title: l.security,
                subtitle: l.securitySub,
                onTap: onSecurity,
              ),
              _TocRow(
                icon: Icons.smart_toy_outlined,
                title: l.bots,
                subtitle: l.botsSub,
                onTap: onBots,
              ),
            ],
          ],
        ),
        _TocLabel(l.more),
        _TocCard(
          children: [
            _TocRow(
              icon: Icons.lock_outline,
              title: l.privacy,
              subtitle: l.privacySub,
              onTap: onPrivacy,
            ),
            if (onLogout != null)
              _TocRow(
                icon: Icons.logout,
                title: l.logout,
                subtitle: l.logoutSub,
                danger: true,
                onTap: onLogout!,
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          l.accountFoot,
          textAlign: TextAlign.center,
          style: Red.text(size: 10, height: 1.6, color: Red.meta),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.edge = true,
    this.valueKey,
  });

  final String value;
  final String label;
  final bool edge;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: edge
              ? Border(left: BorderSide(color: Red.border))
              : const Border(),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: edge ? 16 : 0, right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                key: valueKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Red.text(size: 18, height: 1.2, weight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                label.toUpperCase(),
                style: Red.text(
                  size: 10,
                  height: 1.2,
                  letterSpacing: 1,
                  color: Red.meta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TocLabel extends StatelessWidget {
  const _TocLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 28, 2, 10),
      child: Text(
        text.toUpperCase(),
        style: Red.text(
          size: 10,
          height: 1.2,
          weight: FontWeight.w500,
          letterSpacing: 1.4,
          color: Red.meta,
        ),
      ),
    );
  }
}

class _TocCard extends StatelessWidget {
  const _TocCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Red.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Red.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, thickness: 1, color: Red.borderSoft),
          ],
        ],
      ),
    );
  }
}

class _TocRow extends StatelessWidget {
  const _TocRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Red.dangerFg : Red.fg;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: danger ? Red.dangerSoft : Red.surfaceWarm,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: danger ? Red.dangerLine : Red.border),
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  icon,
                  size: 18,
                  color: danger ? Red.dangerFg : Red.fg2,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Red.text(
                      size: 14,
                      height: 1.35,
                      weight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Red.text(size: 11, height: 1.4, color: Red.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Red.meta),
          ],
        ),
      ),
    );
  }
}

class _PrivacyBody extends StatelessWidget {
  const _PrivacyBody();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Red.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Red.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 46, 24, 46),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Red.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Red.border),
              ),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(Icons.lock_outline, color: Red.meta),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l.privacyEmpty,
              textAlign: TextAlign.center,
              style: Red.text(size: 20, height: 1.3, weight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              l.privacyText,
              textAlign: TextAlign.center,
              style: Red.text(size: 12, height: 1.7, color: Red.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Red.surfaceWarm,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Red.border),
      ),
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: Text(
            nameMark(text),
            style: Red.text(size: 14, height: 1, weight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.title, required this.close, required this.onBack});

  final String title;
  final String close;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: Red.bg,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Red.border)),
          ),
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                IconButton(
                  tooltip: close,
                  onPressed: onBack,
                  icon: const Icon(Icons.chevron_left, size: 22),
                  style: IconButton.styleFrom(
                    foregroundColor: Red.fg2,
                    fixedSize: const Size(40, 40),
                  ),
                ),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Red.text(
                      size: 12,
                      height: 1.2,
                      weight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle get _formNote => Red.text(size: 10.5, height: 1.55, color: Red.meta);

class _Block extends StatelessWidget {
  const _Block({required this.title, this.note = '', required this.child});

  final String title;
  final String note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Red.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Red.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: Red.text(
                  size: 13,
                  height: 1.4,
                  weight: FontWeight.w500,
                  letterSpacing: 0.8,
                ),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note,
                  style: Red.text(size: 11, height: 1.65, color: Red.muted),
                ),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 6),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Red.surfaceWarm,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Red.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          children: [for (final child in children) Expanded(child: child)],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Red.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Red.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _Language extends StatelessWidget {
  const _Language({
    required this.title,
    required this.note,
    required this.en,
    required this.onLocale,
  });

  final String title;
  final String note;
  final bool en;
  final ValueChanged<String>? onLocale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Red.text(size: 14, height: 1.4, weight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          Text(note, style: Red.text(size: 12, color: Red.fg2, height: 1.55)),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Red.surfaceWarm,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Red.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                    child: _Seg(
                      key: const Key('lang-zh'),
                      label: '中文',
                      selected: !en,
                      onTap: () => onLocale?.call('zh'),
                    ),
                  ),
                  Expanded(
                    child: _Seg(
                      key: const Key('lang-en'),
                      label: 'English',
                      selected: en,
                      onTap: () => onLocale?.call('en'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cache extends StatelessWidget {
  const _Cache({
    required this.title,
    required this.note,
    required this.mode,
    required this.labels,
    required this.onChanged,
  });

  final String title;
  final String note;
  final String mode;
  final (String, String, String) labels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Red.text(size: 14, height: 1.4, weight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          Text(note, style: Red.text(size: 12, color: Red.fg2, height: 1.55)),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Red.surfaceWarm,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Red.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                    child: _Seg(
                      key: const Key('cache-7d'),
                      label: labels.$1,
                      selected: mode == '7d',
                      onTap: () => onChanged('7d'),
                    ),
                  ),
                  Expanded(
                    child: _Seg(
                      key: const Key('cache-1d'),
                      label: labels.$2,
                      selected: mode == '1d',
                      onTap: () => onChanged('1d'),
                    ),
                  ),
                  Expanded(
                    child: _Seg(
                      key: const Key('cache-after-read'),
                      label: labels.$3,
                      selected: mode == 'after_read',
                      onTap: () => onChanged('after_read'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected ? Red.accent : Colors.transparent,
        foregroundColor: selected ? Red.accentOn : Red.muted,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        textStyle: Red.text(
          size: 10.5,
          height: 1,
          weight: FontWeight.w500,
          letterSpacing: 0.5,
          color: selected ? Red.accentOn : Red.muted,
        ),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.note,
    required this.trailing,
  });

  final String title;
  final String note;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Red.text(
                    size: 14,
                    height: 1.4,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  note,
                  style: Red.text(size: 12, color: Red.fg2, height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 46,
          height: 44,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Red.ease,
                width: 44,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? Red.accent : Red.surfaceWarm,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: value ? Red.accent : Red.border),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Red.ease,
                left: value ? 24 : 4,
                top: 10,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: value ? Red.accentOn : Red.meta,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineField extends StatelessWidget {
  const _LineField({
    this.controller,
    this.value,
    required this.label,
    this.secret = false,
    this.readOnly = false,
  });

  final TextEditingController? controller;
  final String? value;
  final String label;
  final bool secret;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final textStyle = Red.text(
      size: 15,
      height: 1.2,
      color: readOnly ? Red.meta : Red.fg,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: Red.text(
            size: 10.5,
            height: 1.2,
            weight: FontWeight.w500,
            letterSpacing: 0.8,
            color: Red.fg2,
          ),
        ),
        const SizedBox(height: 7),
        if (readOnly)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Red.surfaceWarm,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Red.border),
            ),
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(value ?? '', style: textStyle),
                ),
              ),
            ),
          )
        else
          TextField(
            controller: controller,
            obscureText: secret,
            autocorrect: false,
            enableSuggestions: !secret,
            style: textStyle,
            cursorColor: Red.accent,
            decoration: InputDecoration(
              isCollapsed: true,
              filled: true,
              fillColor: Red.surfaceWarm,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Red.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Red.accent),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Red.border),
              ),
            ),
          ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Red.accent,
          disabledBackgroundColor: Red.border,
          foregroundColor: Red.accentOn,
          disabledForegroundColor: Red.meta,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: Red.text(
            size: 10.5,
            height: 1,
            weight: FontWeight.w600,
            letterSpacing: 0.5,
            color: Red.accentOn,
          ),
        ),
        child: Text(label.toUpperCase()),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Red.fg,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: Red.text(size: 13, height: 1.2, weight: FontWeight.w500),
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final l = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Red.scrim,
    builder: (context) {
      return Dialog(
        backgroundColor: Red.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Red.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Red.text(
                    size: 18,
                    height: 1.35,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: Red.text(size: 14, color: Red.fg2, height: 1.65),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          foregroundColor: Red.fg2,
                          minimumSize: const Size(0, 44),
                        ),
                        child: Text(l.cancel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Red.danger,
                          foregroundColor: Red.onDanger,
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: Text(action),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}
