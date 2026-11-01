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

  final _tabs = ScrollController();
  final _feedScroll = ScrollController();
  var _showTop = false;
  final _tabKeys = <String, GlobalKey>{};

  List<String> _categories = const [];
  List<FeedCard> _cards = const [];
  Set<String> _read = {};
  Map<String, bool> _collapsed = {};
  String? _category;
  var _unreadOnly = false;
  var _loading = true;
  Inbox? _inbox;
  var _syncing = false;
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
    _tabs.dispose();
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
      final categories = await widget.client.categories();
      final cards = await widget.client.feed();
      if (!mounted || epoch != _loadEpoch) {
        return null;
      }
      final inbox = _inbox;
      if (inbox != null) {
        inbox.merge(cards);
      }
      setState(() {
        _categories = categories;
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

  Future<void> _sync() async {
    if (_syncing) {
      return;
    }
    setState(() => _syncing = true);
    final ok = await _load(silent: true);
    if (!mounted) {
      return;
    }
    setState(() => _syncing = false);
    if (ok == null) {
      return;
    }
    final l = AppLocalizations.of(context);
    showRedNotice(context, ok ? l.refreshDone : l.offline);
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

  void _select(String? category) {
    setState(() => _category = category);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerTab(category));
  }

  void _centerTab(String? category) {
    final target = _tabKeys[category ?? '']?.currentContext;
    if (target == null) {
      return;
    }
    Scrollable.ensureVisible(
      target,
      alignment: 0.5,
      duration: const Duration(milliseconds: 200),
      curve: Red.ease,
    );
  }

  void _reveal() {
    if (_emptyKind == _EmptyKind.unread) {
      _setUnread(false);
      return;
    }
    setState(() => _category = null);
  }

  List<FeedCard> get _visible {
    return _cards.where((card) {
      final inCategory = _category == null || card.category == _category;
      final unreadOk = !_unreadOnly || !_read.contains(card.id);
      return inCategory && unreadOk;
    }).toList();
  }

  List<FeedCard> get _inCategory {
    return _cards
        .where((card) => _category == null || card.category == _category)
        .toList();
  }

  _EmptyKind get _emptyKind {
    if (_cards.isEmpty) {
      return _EmptyKind.none;
    }
    if (_inCategory.isEmpty) {
      return _EmptyKind.category;
    }
    if (_unreadOnly && _inCategory.every((card) => _read.contains(card.id))) {
      return _EmptyKind.unread;
    }
    return _EmptyKind.category;
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

  GlobalKey _tabKey(String id) => _tabKeys.putIfAbsent(id, GlobalKey.new);

  void _openSettings() {
    Navigator.push<void>(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => AccountPage(
          unreadOnly: _unreadOnly,
          onUnreadOnly: _setUnread,
          unreadCount: _cards.where((card) => !_read.contains(card.id)).length,
          onLocale: _setLocale,
          onTheme: widget.onTheme,
          cacheMode: _inbox?.cacheMode ?? '7d',
          onCacheMode: _setCacheMode,
          syncSeconds: widget.pollEvery?.inSeconds,
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
                day: now.day.toString().padLeft(2, '0'),
                meta: editionMeta(l, now),
                count: _cards.length,
                syncing: _syncing,
                mark: _avatarMark,
                onUnread: unread == 0 ? null : () => _setUnread(true),
                onSettings: _openSettings,
                onSync: _sync,
              ),
              Expanded(child: RedCenter(child: _body(l, pad))),
            ],
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
      return const _Skeleton();
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
        if (MediaQuery.sizeOf(context).width > 470)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 18, pad, 0),
            child: Text(
              l.mastheadNote.toUpperCase(),
              style: Red.text(
                size: 10.5,
                height: 1.6,
                weight: FontWeight.w500,
                letterSpacing: 1.05,
                color: Red.muted,
              ),
            ),
          ),
        _TabBar(
          pad: pad,
          controller: _tabs,
          categories: _categories,
          selected: _category,
          tabKey: _tabKey,
          onSelect: _select,
        ),
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
                    imageHeaders: widget.client.imageHeaders,
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
    _EmptyKind.category => l.emptyCategoryTitle,
  };

  String _emptyBody(AppLocalizations l) => switch (_emptyKind) {
    _EmptyKind.none => l.emptyNoneBody,
    _EmptyKind.unread => l.emptyUnreadBody,
    _EmptyKind.category => l.emptyCategoryBody,
  };
}

enum _EmptyKind { none, unread, category }

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

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.pad,
    required this.controller,
    required this.categories,
    required this.selected,
    required this.tabKey,
    required this.onSelect,
  });

  final double pad;
  final ScrollController controller;
  final List<String> categories;
  final String? selected;
  final GlobalKey Function(String id) tabKey;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 70,
      child: ListView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(pad, 20, pad, 16),
        children: [
          _Tab(
            key: tabKey(''),
            label: l.all,
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final category in categories)
            _Tab(
              key: tabKey(category),
              label: categoryLabel(l, category),
              selected: selected == category,
              onTap: () => onSelect(category),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
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
    final bg = selected ? Red.accent : Colors.transparent;
    final fg = selected ? Red.accentOn : Red.muted;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: selected ? Red.accent : Red.border),
          ),
          textStyle: Red.text(
            size: 11,
            height: 1,
            weight: FontWeight.w500,
            letterSpacing: 0.7,
          ),
        ),
        child: Text(label.toUpperCase()),
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
    required this.imageHeaders,
    required this.onToggle,
    required this.onOpen,
  });

  final _DayGroup group;
  final bool first;
  final bool collapsed;
  final Set<String> read;
  final Map<String, String> imageHeaders;
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
              imageHeaders: imageHeaders,
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
    required this.imageHeaders,
    required this.onTap,
  });

  final FeedCard card;
  final bool read;
  final Map<String, String> imageHeaders;
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
                            Flexible(
                              child: Text(
                                categoryLabel(l, card.category).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Red.text(
                                  size: 10.5,
                                  color: Red.fg2,
                                  height: 1.3,
                                  weight: FontWeight.w500,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            Text(
                              ' · ',
                              style: Red.text(size: 10.5, color: Red.border),
                            ),
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
                            httpHeaders: widget.imageHeaders.isEmpty
                                ? null
                                : widget.imageHeaders,
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
    required this.day,
    required this.meta,
    required this.count,
    required this.syncing,
    required this.mark,
    required this.onUnread,
    required this.onSettings,
    required this.onSync,
  });

  final double pad;
  final int unread;
  final bool unreadOnly;
  final String day;
  final String meta;
  final int count;
  final bool syncing;
  final String mark;
  final VoidCallback? onUnread;
  final VoidCallback onSettings;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final narrow = MediaQuery.sizeOf(context).width <= 470;
    final daySize = narrow ? 42.0 : 52.0;
    final edition = count == 1 ? l.groupCountOne : l.groupCount(count);
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
              padding: EdgeInsets.fromLTRB(
                pad,
                narrow ? 18 : 20,
                pad,
                narrow ? 14 : 16,
              ),
              child: Row(
                children: [
                  Text(
                    day,
                    style: Red.text(
                      size: daySize,
                      height: 0.88,
                      letterSpacing: daySize * -0.055,
                      weight: FontWeight.w400,
                      tabular: true,
                    ),
                  ),
                  SizedBox(width: narrow ? 10 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meta.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Red.text(
                            size: narrow ? 11 : 12,
                            height: 1.3,
                            weight: FontWeight.w500,
                            letterSpacing: 0.9,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          edition.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Red.text(
                            size: 10.5,
                            height: 1.3,
                            letterSpacing: 0.6,
                            color: Red.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!unreadOnly) ...[
                    const SizedBox(width: 8),
                    _UnreadEntry(
                      label: unread > 0 ? l.unreadCount(unread) : l.allRead,
                      enabled: onUnread != null,
                      onPressed: onUnread,
                    ),
                  ],
                  const SizedBox(width: 6),
                  _RefreshButton(syncing: syncing, onPressed: onSync),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const Key('settings'),
                    tooltip: l.settings,
                    onPressed: onSettings,
                    style: IconButton.styleFrom(
                      backgroundColor: Red.surface,
                      foregroundColor: Red.fg,
                      side: BorderSide(color: Red.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      fixedSize: Size(narrow ? 36 : 38, narrow ? 36 : 38),
                      padding: EdgeInsets.zero,
                    ),
                    icon: Text(
                      mark,
                      style: Red.text(
                        size: 13,
                        height: 1,
                        weight: FontWeight.w500,
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

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.syncing, required this.onPressed});

  final bool syncing;
  final VoidCallback onPressed;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    if (widget.syncing) {
      _spin.repeat();
    }
  }

  @override
  void didUpdateWidget(_RefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.syncing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.syncing && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context).syncNow,
      onPressed: widget.syncing ? null : widget.onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Red.fg2,
        disabledForegroundColor: Red.fg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fixedSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
      icon: RotationTransition(
        turns: _spin,
        child: const Icon(Icons.refresh, size: 19),
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
