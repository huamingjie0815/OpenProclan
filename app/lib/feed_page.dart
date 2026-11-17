import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_api.dart';
import 'account_page.dart';
import 'chrome.dart';
import 'detail_page.dart';
import 'feed_client.dart';
import 'inbox.dart';
import 'l10n/app_localizations.dart';
import 'red.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({
    super.key,
    required this.client,
    this.pollEvery = const Duration(seconds: 5),
    this.onLocale,
    this.onLocaleClear,
    this.onTheme,
    this.prefs,
    this.account,
    this.onLogout,
  });

  final FeedClient client;
  final Duration? pollEvery;
  final ValueChanged<String>? onLocale;
  final VoidCallback? onLocaleClear;
  final ValueChanged<bool>? onTheme;
  final SharedPreferences? prefs;
  final AccountClient? account;
  final Future<void> Function()? onLogout;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _DayGroup {
  _DayGroup(this.key, this.day, this.items);

  final String key;
  final DateTime day;
  final List<FeedCard> items;
}

class _FeedPageState extends State<FeedPage> {
  static const _unreadKey = 'proclan.unreadOnly';
  static const _collapsedKey = 'proclan.collapsed.v2';

  final _feedScroll = ScrollController();
  var _showTop = false;
  var _drawerOpen = false;

  List<FeedCard> _cards = const [];
  Set<String> _read = {};
  Map<String, bool> _collapsed = {};
  var _unreadOnly = false;
  var _loading = true;
  Inbox? _inbox;
  String? _error;
  Timer? _poll;
  var _loadEpoch = 0;
  String? _username;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _feedScroll.addListener(_onFeedScroll);
    final every = widget.pollEvery;
    if (every != null) {
      _poll = Timer.periodic(every, (_) => _load(silent: true));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _feedScroll.removeListener(_onFeedScroll);
    _feedScroll.dispose();
    super.dispose();
  }

  void _onFeedScroll() {
    final show = _feedScroll.hasClients && _feedScroll.offset > 480;
    if (show == _showTop || !mounted) {
      return;
    }
    setState(() => _showTop = show);
  }

  Future<void> _bootstrap() async {
    final prefs = widget.prefs;
    final inbox = prefs == null ? null : (Inbox(prefs)..load());
    if (!mounted) {
      return;
    }
    setState(() {
      _inbox = inbox;
      _unreadOnly = prefs?.getBool(_unreadKey) ?? false;
      _collapsed = _readCollapsed(prefs);
      if (inbox != null) {
        _cards = inbox.cards;
        _read = inbox.read;
        _loading = inbox.cards.isEmpty;
      }
    });
    await Future.wait([_load(), _syncAccountSettings(), _loadUser()]);
  }

  Future<void> _loadUser() async {
    final account = widget.account;
    if (account == null) {
      return;
    }
    try {
      final user = await account.me();
      if (!mounted) {
        return;
      }
      setState(() {
        _username = user.username;
      });
    } catch (_) {}
  }

  String get _avatarMark {
    final name = _username?.trim() ?? '';
    if (name.isEmpty) {
      return '';
    }
    return nameMark(name);
  }

  Map<String, bool> _readCollapsed(SharedPreferences? prefs) {
    final raw = prefs?.getString(_collapsedKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) {
        return {};
      }
      return {
        for (final entry in parsed.entries)
          if (entry.key is String && entry.value is bool)
            entry.key as String: entry.value as bool,
      };
    } catch (_) {
      return {};
    }
  }

  /// True when this call applied its result, false when it failed, null when a newer load replaced it.
  Future<bool?> _load({bool silent = false}) async {
    final epoch = ++_loadEpoch;
    if (!silent && _cards.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final cards = await widget.client.feed();
      if (!mounted || epoch != _loadEpoch) {
        return null;
      }
      final inbox = _inbox;
      if (inbox != null) {
        inbox.merge(cards);
      }
      setState(() {
        if (inbox != null) {
          _cards = inbox.cards;
          _read = inbox.read;
        } else {
          _cards = cards;
          final ids = {for (final card in cards) card.id};
          _read = _read.intersection(ids);
        }
        _loading = false;
        _error = null;
      });
      return true;
    } catch (_) {
      if (!mounted || epoch != _loadEpoch) {
        return null;
      }
      setState(() {
        _loading = false;
        _error = FeedException.offline;
      });
      return false;
    }
  }

  void _rememberRead() {
    final inbox = _inbox;
    setState(() {
      if (inbox != null) {
        _cards = inbox.cards;
        _read = inbox.read;
      }
    });
  }

  void _markRead(String id) {
    if (_read.contains(id) && _inbox?.cacheMode != 'after_read') {
      return;
    }
    final inbox = _inbox;
    if (inbox == null) {
      setState(() => _read = {..._read, id});
      return;
    }
    inbox.markRead(id);
    _rememberRead();
  }

  void _markAllRead() {
    final inbox = _inbox;
    if (inbox == null) {
      setState(() => _read = {for (final card in _cards) card.id});
      return;
    }
    inbox.markAllRead();
    _rememberRead();
  }

  void _setUnread(bool value) {
    setState(() => _unreadOnly = value);
    widget.prefs?.setBool(_unreadKey, value);
    _pushSettings(unreadOnly: value);
  }

  void _setLocale(String code) {
    widget.onLocale?.call(code);
    _pushSettings(locale: code);
  }

  void _setCacheMode(String mode) {
    final inbox = _inbox;
    if (inbox == null) {
      widget.prefs?.setString(Inbox.cacheKey, mode);
    } else {
      inbox.setCacheMode(mode);
      _rememberRead();
    }
    _pushSettings(cacheMode: mode);
  }

  Future<void> _pushSettings({
    String? cacheMode,
    String? locale,
    bool? unreadOnly,
  }) async {
    final account = widget.account;
    if (account == null) {
      return;
    }
    try {
      await account.patchSettings(
        cacheMode: cacheMode,
        locale: locale,
        unreadOnly: unreadOnly,
      );
      await widget.prefs?.setBool(Inbox.syncedKey, true);
    } on AccountException catch (error) {
      if (!mounted) {
        return;
      }
      showRedNotice(
        context,
        accountMessage(AppLocalizations.of(context), error),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      showRedNotice(context, AppLocalizations.of(context).offline);
    }
  }

  Future<void> _syncAccountSettings() async {
    final account = widget.account;
    final prefs = widget.prefs;
    if (account == null) {
      return;
    }
    try {
      final remote = await account.settings();
      if (!mounted) {
        return;
      }
      final synced = prefs?.getBool(Inbox.syncedKey) ?? false;
      final localExplicit =
          prefs != null &&
          (prefs.getString('proclan.locale') != null ||
              prefs.containsKey(_unreadKey) ||
              prefs.containsKey(Inbox.cacheKey));
      final remoteDefault =
          remote.cacheMode == '7d' &&
          remote.locale == 'system' &&
          !remote.unreadOnly;
      if (!synced && localExplicit && remoteDefault) {
        await account.patchSettings(
          cacheMode: _inbox?.cacheMode ?? '7d',
          locale: prefs.getString('proclan.locale') ?? 'system',
          unreadOnly: _unreadOnly,
        );
        await prefs.setBool(Inbox.syncedKey, true);
        return;
      }
      await _applyRemote(remote);
      await prefs?.setBool(Inbox.syncedKey, true);
    } catch (_) {}
  }

  Future<void> _applyRemote(AccountSettings remote) async {
    final inbox = _inbox;
    final mode = normalizeCacheMode(remote.cacheMode);
    if (inbox == null) {
      await widget.prefs?.setString(Inbox.cacheKey, mode);
    } else {
      inbox.setCacheMode(mode);
    }
    await widget.prefs?.setBool(_unreadKey, remote.unreadOnly);
    if (remote.locale == 'zh' || remote.locale == 'en') {
      widget.onLocale?.call(remote.locale);
    } else {
      widget.onLocaleClear?.call();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _unreadOnly = remote.unreadOnly;
      if (inbox != null) {
        _cards = inbox.cards;
        _read = inbox.read;
      }
    });
  }

  bool _isCollapsed(String key, DateTime day) {
    final choice = _collapsed[key];
    if (choice != null) {
      return choice;
    }
    final now = DateTime.now();
    return day.year != now.year || day.month != now.month || day.day != now.day;
  }

  void _toggleGroup(String key, bool collapsed) {
    setState(() => _collapsed[key] = !collapsed);
    widget.prefs?.setString(_collapsedKey, jsonEncode(_collapsed));
  }

  Future<void> _open(FeedCard card) async {
    _markRead(card.id);
    if (!mounted) {
      return;
    }
    final result = await openCardDetail(
      context,
      card: card,
      client: widget.client,
    );
    if (result == null) {
      return;
    }
    _applyDetailResult(card, result);
  }

  void _applyDetailResult(FeedCard card, DetailResult result) {
    if (!mounted) {
      return;
    }
    final l = AppLocalizations.of(context);
    final inbox = _inbox;
    if (result == DetailResult.deleted) {
      if (inbox == null) {
        setState(() {
          _cards = _cards.where((item) => item.id != card.id).toList();
          _read = {..._read}..remove(card.id);
        });
      } else {
        inbox.delete(card.id);
        _rememberRead();
      }
      showRedNotice(context, l.deleted);
      return;
    }
    if (inbox == null) {
      setState(() => _read = {..._read}..remove(card.id));
    } else {
      inbox.markUnread(card);
      _rememberRead();
    }
    showRedNotice(context, l.markedUnread);
  }

  void _reveal() {
    _setUnread(false);
  }

  List<FeedCard> get _visible {
    return _cards
        .where((card) => !_unreadOnly || !_read.contains(card.id))
        .toList();
  }

  _EmptyKind get _emptyKind {
    if (_cards.isEmpty) {
      return _EmptyKind.none;
    }
    return _EmptyKind.unread;
  }

  List<_DayGroup> _groups(List<FeedCard> visible) {
    final groups = <_DayGroup>[];
    for (final card in visible) {
      final time = localTime(card.createdAt);
      final day = time == null
          ? DateTime.utc(1970)
          : DateTime(time.year, time.month, time.day);
      final key = '${day.year}-${day.month}-${day.day}';
      if (groups.isEmpty || groups.last.key != key) {
        groups.add(_DayGroup(key, day, [card]));
      } else {
        groups.last.items.add(card);
      }
    }
    return groups;
  }

  void _openAccount(AccountOpen open) {
    setState(() => _drawerOpen = false);
    Navigator.push<void>(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => AccountPage(
          open: open,
          account: widget.account,
          feed: widget.client,
          onCardOpened: (card) => _markRead(card.id),
          onCardResult: _applyDetailResult,
          onLogout: widget.onLogout,
        ),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, animation, _, child) {
          final offset = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Red.ease));
          return SlideTransition(position: offset, child: child);
        },
      ),
    ).then((_) {
      if (mounted) {
        _loadUser();
      }
    });
  }

  void _openSettings() {
    setState(() => _drawerOpen = false);
    showSettingsCard(
      context,
      unreadOnly: _unreadOnly,
      onUnreadOnly: _setUnread,
      cacheMode: _inbox?.cacheMode ?? '7d',
      onCacheMode: _setCacheMode,
      onLocale: _setLocale,
      onTheme: widget.onTheme,
      syncSeconds: widget.pollEvery?.inSeconds,
      account: widget.account,
      onLogout: widget.onLogout,
      onSecurity: () => _openAccount(AccountOpen.security),
      onPrivacy: () => _openAccount(AccountOpen.privacy),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final pad = Red.gutter(width);
    final now = DateTime.now();
    final unread = _cards.where((card) => !_read.contains(card.id)).length;
    return Scaffold(
      backgroundColor: Red.bg,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Masthead(
                pad: pad,
                unread: unread,
                unreadOnly: _unreadOnly,
                meta: editionMeta(l, now),
                onUnread: unread == 0 ? null : () => _setUnread(true),
                onMenu: () => setState(() => _drawerOpen = true),
              ),
              Expanded(child: RedCenter(child: _body(l, pad))),
            ],
          ),
          if (_drawerOpen)
            Positioned.fill(
              child: _FeedDrawer(
                name: _username?.trim() ?? '',
                mark: _avatarMark,
                onClose: () => setState(() => _drawerOpen = false),
                onBots: () => _openAccount(AccountOpen.bots),
                onSettings: _openSettings,
              ),
            ),
          if (_showTop)
            Positioned(
              right: 24,
              bottom: 24,
              child: _ToTop(
                tooltip: l.toTop,
                onPressed: () {
                  _feedScroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 280),
                    curve: Red.ease,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(AppLocalizations l, double pad) {
    if (_loading && _cards.isEmpty && _error == null) {
      return _Skeleton();
    }
    if (_error != null && _cards.isEmpty) {
      return ListView(
        children: [
          _Empty(
            title: l.offline,
            body: l.checkNetwork,
            icon: Icons.cloud_off_outlined,
            action: l.retry,
            onPressed: () => _load(),
          ),
        ],
      );
    }
    final visible = _visible;
    final groups = _groups(visible);
    final showFilter = _unreadOnly && _cards.isNotEmpty;
    return ListView(
      controller: _feedScroll,
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        if (showFilter)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
            child: _FilterRow(
              count: visible.length,
              onClear: () => _setUnread(false),
              onMarkAllRead: _markAllRead,
            ),
          ),
        if (visible.isEmpty)
          _Empty(
            title: _emptyTitle(l),
            body: _emptyBody(l),
            icon: Icons.menu_book_outlined,
            action: _emptyKind == _EmptyKind.none ? null : l.showAll,
            onPressed: _emptyKind == _EmptyKind.none ? null : _reveal,
          )
        else
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Column(
              children: [
                for (var i = 0; i < groups.length; i++)
                  _GroupSection(
                    group: groups[i],
                    first: i == 0,
                    collapsed: _isCollapsed(groups[i].key, groups[i].day),
                    read: _read,
                    imageHeadersFor: widget.client.imageHeadersFor,
                    onToggle: () => _toggleGroup(
                      groups[i].key,
                      _isCollapsed(groups[i].key, groups[i].day),
                    ),
                    onOpen: _open,
                  ),
              ],
            ),
          ),
        if (visible.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: _FeedEnd(count: visible.length),
          ),
      ],
    );
  }

  String _emptyTitle(AppLocalizations l) => switch (_emptyKind) {
    _EmptyKind.none => l.emptyNoneTitle,
    _EmptyKind.unread => l.emptyUnreadTitle,
  };

  String _emptyBody(AppLocalizations l) => switch (_emptyKind) {
    _EmptyKind.none => l.emptyNoneBody,
    _EmptyKind.unread => l.emptyUnreadBody,
  };
}

enum _EmptyKind { none, unread }

class _ToTop extends StatelessWidget {
  const _ToTop({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_upward, size: 18),
      style: IconButton.styleFrom(
        foregroundColor: Red.fg2,
        backgroundColor: Red.surface,
        fixedSize: const Size(44, 44),
        side: BorderSide(color: Red.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.count,
    required this.onClear,
    required this.onMarkAllRead,
  });

  final int count;
  final VoidCallback onClear;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Red.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Red.border),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  height: 30,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Red.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l.filterUnread(count).toUpperCase(),
                        style: Red.text(
                          size: 10.5,
                          color: Red.fg2,
                          height: 1.2,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('mark-all-read'),
              onPressed: onMarkAllRead,
              style: TextButton.styleFrom(
                foregroundColor: Red.fg2,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l.markAllRead.toUpperCase(),
                style: Red.text(
                  size: 11,
                  color: Red.muted,
                  height: 1.2,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: Red.fg,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l.showAll.toUpperCase(),
                style: Red.text(size: 12, height: 1.4).copyWith(
                  decoration: TextDecoration.underline,
                  decorationThickness: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.first,
    required this.collapsed,
    required this.read,
    required this.imageHeadersFor,
    required this.onToggle,
    required this.onOpen,
  });

  final _DayGroup group;
  final bool first;
  final bool collapsed;
  final Set<String> read;
  final Map<String, String> Function(String url) imageHeadersFor;
  final VoidCallback onToggle;
  final ValueChanged<FeedCard> onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 690;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(top: first ? 4 : 20),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dayHeading(l, group.day).toUpperCase(),
                          style: Red.text(
                            size: 12,
                            height: 1.4,
                            weight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Text(
                        group.items.length == 1
                            ? l.groupCountOne
                            : l.groupCount(group.items.length),
                        style: Red.text(
                          size: 10.5,
                          color: Red.meta,
                          height: 1.4,
                          letterSpacing: 0.5,
                          tabular: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: collapsed ? -0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Red.ease,
                        child: Icon(
                          Icons.expand_more,
                          size: 16,
                          color: Red.meta,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!collapsed)
          for (var i = 0; i < group.items.length; i++) ...[
            SizedBox(height: wide ? 12 : 10),
            _Card(
              card: group.items[i],
              read: read.contains(group.items[i].id),
              imageHeadersFor: imageHeadersFor,
              onTap: () => onOpen(group.items[i]),
            ),
          ],
      ],
    );
  }
}

class _Card extends StatefulWidget {
  const _Card({
    required this.card,
    required this.read,
    required this.imageHeadersFor,
    required this.onTap,
  });

  final FeedCard card;
  final bool read;
  final Map<String, String> Function(String url) imageHeadersFor;
  final VoidCallback onTap;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final card = widget.card;
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width <= 470
        ? 18.0
        : width <= 680
        ? 19.0
        : 21.0;
    final thumb = width <= 470
        ? 64.0
        : width <= 680
        ? 80.0
        : 104.0;
    final minutes = readingMinutes('${card.title}${card.summary}${card.body}');
    final mark = sourceMark(card.source);
    final image = card.images.isEmpty ? null : card.images.first;
    final imageHeaders = image == null
        ? const <String, String>{}
        : widget.imageHeadersFor(image);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Red.ease,
        decoration: BoxDecoration(
          color: _hover ? Red.surfaceHover : Red.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _hover ? Red.lineStrong : Red.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            hoverColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.all(width <= 680 ? 16 : 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (!widget.read) ...[
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Red.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                            ],
                            Text(
                              widget.read ? l.read : l.minutesRead(minutes),
                              style: Red.text(
                                size: 10.5,
                                color: Red.meta,
                                height: 1.3,
                                letterSpacing: 0.8,
                                tabular: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          card.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Red.text(
                            size: titleSize,
                            height: 1.35,
                            letterSpacing: Red.em(titleSize, -0.015),
                            weight: widget.read
                                ? FontWeight.w400
                                : FontWeight.w500,
                            color: widget.read ? Red.muted : Red.fg,
                          ),
                        ),
                        if (card.summary.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            card.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Red.text(
                              size: width <= 680 ? 14 : 14.5,
                              color: Red.muted,
                              height: width <= 680 ? 1.65 : 1.7,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (mark.isNotEmpty) ...[
                              MarkAvatar(text: mark, size: 22, fontSize: 9),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                card.source.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Red.text(
                                  size: 10.5,
                                  color: Red.fg2,
                                  height: 1.3,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              shortWhen(l, card.createdAt),
                              style: Red.text(
                                size: 10.5,
                                color: Red.meta,
                                height: 1.3,
                                letterSpacing: 0.5,
                                tabular: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (image != null) ...[
                    SizedBox(width: width <= 680 ? 14 : 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ColoredBox(
                        color: Red.surfaceWarm,
                        child: SizedBox(
                          width: thumb,
                          height: thumb,
                          child: CachedNetworkImage(
                            imageUrl: image,
                            httpHeaders: imageHeaders.isEmpty
                                ? null
                                : imageHeaders,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholderFadeInDuration: Duration.zero,
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedEnd extends StatelessWidget {
  const _FeedEnd({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: ColoredBox(
              color: Red.border,
              child: const SizedBox(height: 1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              AppLocalizations.of(context).endEdition(count).toUpperCase(),
              style: Red.text(
                size: 10.5,
                color: Red.meta,
                height: 1.4,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: Red.border,
              child: const SizedBox(height: 1),
            ),
          ),
        ],
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({
    required this.pad,
    required this.unread,
    required this.unreadOnly,
    required this.meta,
    required this.onUnread,
    required this.onMenu,
  });

  final double pad;
  final int unread;
  final bool unreadOnly;
  final String meta;
  final VoidCallback? onUnread;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ColoredBox(
      color: Red.bg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Red.border)),
        ),
        child: SafeArea(
          bottom: false,
          child: RedCenter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 10, pad, 10),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('open-menu'),
                    tooltip: l.openMenu,
                    onPressed: onMenu,
                    style: IconButton.styleFrom(
                      foregroundColor: Red.fg,
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const _SidebarIcon(),
                  ),
                  if (!unreadOnly)
                    _UnreadEntry(
                      label: unread > 0 ? l.unreadCount(unread) : l.allRead,
                      enabled: onUnread != null,
                      onPressed: onUnread,
                    ),
                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Red.text(
                        size: 15,
                        height: 1.2,
                        color: Red.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarIcon extends StatelessWidget {
  const _SidebarIcon();

  @override
  Widget build(BuildContext context) {
    // IconTheme notifies this const icon after a theme change.
    final color = IconTheme.of(context).color ?? Red.fg;
    return CustomPaint(
      size: const Size(22, 22),
      painter: _SidebarIconPainter(color),
    );
  }
}

class _SidebarIconPainter extends CustomPainter {
  const _SidebarIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3.5 * scale, 3.5 * scale, 17 * scale, 17 * scale),
        Radius.circular(2.5 * scale),
      ),
      paint,
    );
    canvas.drawLine(
      Offset(9 * scale, 4 * scale),
      Offset(9 * scale, 20 * scale),
      paint,
    );
    for (final y in const [8.0, 12.0, 16.0]) {
      canvas.drawLine(
        Offset(12.5 * scale, y * scale),
        Offset(16.5 * scale, y * scale),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SidebarIconPainter old) => old.color != color;
}

class _FeedDrawer extends StatelessWidget {
  const _FeedDrawer({
    required this.name,
    required this.mark,
    required this.onClose,
    required this.onBots,
    required this.onSettings,
  });

  final String name;
  final String mark;
  final VoidCallback onClose;
  final VoidCallback onBots;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final panel = width - 52 < 304 ? width - 52 : 304.0;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(
              color: Red.scrim,
              child: Semantics(label: l.closeMenu),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Red.bg,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Red.border)),
              ),
              child: SizedBox(
                width: panel,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Red.border),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Proclan',
                                    style: Red.text(
                                      size: 20,
                                      height: 1.2,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l.drawerCaption,
                                    style: Red.text(
                                      size: 11,
                                      height: 1.4,
                                      color: Red.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          key: const Key('drawer-bots'),
                          onPressed: onBots,
                          style: TextButton.styleFrom(
                            foregroundColor: Red.fg2,
                            alignment: Alignment.centerLeft,
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.smart_toy_outlined, size: 18),
                              const SizedBox(width: 12),
                              Text(
                                l.bots,
                                style: Red.text(size: 14, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Red.border),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Red.surfaceWarm,
                                          borderRadius: BorderRadius.circular(
                                            19,
                                          ),
                                          border: Border.all(color: Red.border),
                                        ),
                                        child: Text(
                                          mark,
                                          key: const Key('drawer-avatar'),
                                          style: Red.text(
                                            size: 14,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Red.text(
                                            size: 12,
                                            height: 1.4,
                                            weight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  key: const Key('settings'),
                                  tooltip: l.settings,
                                  onPressed: onSettings,
                                  style: IconButton.styleFrom(
                                    foregroundColor: Red.muted,
                                    fixedSize: const Size(44, 44),
                                  ),
                                  icon: const Icon(
                                    Icons.settings_outlined,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnreadEntry extends StatelessWidget {
  const _UnreadEntry({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: Red.fg2,
          disabledForegroundColor: Red.fg2,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Red.border),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Red.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: Red.text(
                size: 11,
                height: 1.2,
                weight: FontWeight.w500,
                letterSpacing: 0.5,
                color: Red.fg2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.title,
    required this.body,
    required this.icon,
    this.action,
    this.onPressed,
  });

  final String title;
  final String body;
  final IconData icon;
  final String? action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 76, 28, 40),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Red.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Red.border),
            ),
            child: Icon(icon, size: 24, color: Red.meta),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Red.text(
              size: 22,
              height: 1.3,
              weight: FontWeight.w500,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: Red.text(size: 13, color: Red.muted, height: 1.7),
            ),
          ),
          if (action != null && onPressed != null) ...[
            const SizedBox(height: 20),
            TextButton(
              key: const Key('empty-action'),
              onPressed: onPressed,
              style: TextButton.styleFrom(
                foregroundColor: Red.fg,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: Red.border),
                ),
                textStyle: Red.text(
                  size: 11,
                  height: 1,
                  weight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
              child: Text(action!.toUpperCase()),
            ),
          ],
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final pad = Red.gutter(MediaQuery.sizeOf(context).width);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 24),
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            height: 132,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Red.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Red.border),
            ),
          ),
      ],
    );
  }
}
