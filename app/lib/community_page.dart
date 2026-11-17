import 'package:flutter/material.dart';

import 'account_api.dart';
import 'community_api.dart';
import 'detail_page.dart';
import 'feed_client.dart';
import 'l10n/app_localizations.dart';
import 'red.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({
    super.key,
    required this.client,
    this.feed,
    this.onCardOpened,
    this.onCardResult,
  });

  final CommunityClient client;
  final FeedClient? feed;
  final void Function(FeedCard card)? onCardOpened;
  final void Function(FeedCard card, DetailResult result)? onCardResult;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

enum _Section { likes, follows, following }

class _CommunityPageState extends State<CommunityPage> {
  final _search = TextEditingController();
  var _section = _Section.likes;
  var _query = '';
  var _busy = false;
  var _epoch = 0;
  String? _error;
  List<CommunityBot> _bots = const [];
  List<CommunityGroup> _groups = const [];
  CommunityBot? _guest;
  CommunityCopies? _copies;

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _searching => _query.isNotEmpty && _section != _Section.following;

  Future<void> _loadBoard() async {
    final epoch = ++_epoch;
    final kind = _section == _Section.follows ? 'follows' : 'likes';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bots = await widget.client.board(kind);
      if (!mounted || epoch != _epoch) {
        return;
      }
      setState(() => _bots = bots);
    } on AccountException catch (error) {
      if (mounted) {
        setState(() => _error = accountMessage(AppLocalizations.of(context), error));
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadSearch(String query) async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bots = await widget.client.search(query);
      if (!mounted || epoch != _epoch) {
        return;
      }
      setState(() => _bots = bots);
    } on AccountException catch (error) {
      if (mounted) {
        setState(() => _error = accountMessage(AppLocalizations.of(context), error));
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loadFollowing() async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final groups = await widget.client.following();
      if (!mounted || epoch != _epoch) {
        return;
      }
      setState(() => _groups = groups);
    } on AccountException catch (error) {
      if (mounted) {
        setState(() => _error = accountMessage(AppLocalizations.of(context), error));
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() => _busy = false);
      }
    }
  }

  void _onSearch(String value) {
    final query = value.trim();
    setState(() => _query = query);
    if (_section == _Section.following) {
      return;
    }
    if (query.isEmpty) {
      _loadBoard();
    } else {
      _loadSearch(query);
    }
  }

  void _pick(_Section section) {
    setState(() {
      _section = section;
      _guest = null;
      _copies = null;
    });
    if (section == _Section.following) {
      _loadFollowing();
      return;
    }
    if (_query.isEmpty) {
      _loadBoard();
    } else {
      _loadSearch(_query);
    }
  }

  Future<void> _openGuest(String ownerId, String name) async {
    setState(() => _busy = true);
    try {
      final bot = await widget.client.bot(ownerId: ownerId, name: name);
      if (!mounted) {
        return;
      }
      setState(() {
        _guest = bot;
        _copies = null;
      });
    } on AccountException catch (error) {
      if (mounted) {
        showRedNotice(context, accountMessage(AppLocalizations.of(context), error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openCopies(String ownerId, String name) async {
    setState(() => _busy = true);
    try {
      final copies = await widget.client.copies(ownerId: ownerId, name: name);
      if (!mounted) {
        return;
      }
      setState(() {
        _copies = copies;
        _guest = null;
      });
    } on AccountException catch (error) {
      if (mounted) {
        showRedNotice(context, accountMessage(AppLocalizations.of(context), error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshGuest() async {
    final guest = _guest;
    if (guest == null) {
      return;
    }
    final bot = await widget.client.bot(ownerId: guest.ownerId, name: guest.name);
    if (mounted) {
      setState(() => _guest = bot);
    }
  }

  Future<void> _toggleFollow() async {
    final guest = _guest;
    if (guest == null || guest.mine) {
      return;
    }
    if (guest.following) {
      final l = AppLocalizations.of(context);
      final ok = await _confirm(
        context,
        title: l.communityUnfollowTitle,
        body: l.communityUnfollowBody,
        action: l.communityUnfollow,
      );
      if (!ok || !mounted) {
        return;
      }
      await widget.client.unfollow(ownerId: guest.ownerId, name: guest.name);
    } else if (guest.listed) {
      await widget.client.follow(ownerId: guest.ownerId, name: guest.name);
    }
    await _refreshGuest();
  }

  Future<void> _vote(int vote) async {
    final guest = _guest;
    if (guest == null || guest.mine || !guest.listed) {
      return;
    }
    final next = guest.vote == vote ? 0 : vote;
    await widget.client.vote(ownerId: guest.ownerId, name: guest.name, vote: next);
    await _refreshGuest();
  }

  void _back() {
    if (_guest != null) {
      setState(() => _guest = null);
      return;
    }
    if (_copies != null) {
      setState(() => _copies = null);
      if (_section == _Section.following) {
        _loadFollowing();
      }
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final pad = Red.gutter(width);
    final guest = _guest;
    final copies = _copies;
    final title = guest?.name ?? copies?.name ?? l.community;
    return PopScope(
      canPop: guest == null && copies == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _back();
        }
      },
      child: Scaffold(
        backgroundColor: Red.bg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Bar(title: title, onBack: _back),
            Expanded(
              child: RedCenter(
                maxWidth: Red.articleColumn,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(pad, 24, pad, 72),
                  children: [
                    if (guest != null)
                      _Guest(
                        bot: guest,
                        busy: _busy,
                        onFollow: _toggleFollow,
                        onVote: _vote,
                        onOpenCard: _openPreview,
                      )
                    else if (copies != null)
                      _Copies(
                        page: copies,
                        busy: _busy,
                        onUnfollow: _unfollowFromCopies,
                        onOpenGuest: () => _openGuest(copies.ownerId, copies.name),
                        onOpenCard: _openOwned,
                      )
                    else ...[
                      TextField(
                        key: const Key('community-search'),
                        controller: _search,
                        onChanged: _onSearch,
                        style: Red.text(size: 15, height: 1.4),
                        cursorColor: Red.fg,
                        decoration: InputDecoration(
                          hintText: l.communitySearchHint,
                          hintStyle: Red.text(size: 15, height: 1.4, color: Red.meta),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Red.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Red.fg),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _Tab(
                            key: const Key('community-likes'),
                            label: l.communityLikes,
                            selected: _section == _Section.likes,
                            onTap: () => _pick(_Section.likes),
                          ),
                          _Tab(
                            key: const Key('community-follows'),
                            label: l.communityFollows,
                            selected: _section == _Section.follows,
                            onTap: () => _pick(_Section.follows),
                          ),
                          _Tab(
                            key: const Key('community-following'),
                            label: l.communityFollowing,
                            selected: _section == _Section.following,
                            onTap: () => _pick(_Section.following),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_error != null)
                        Text(_error!, style: Red.text(size: 14, height: 1.5, color: Red.dangerFg))
                      else if (_section == _Section.following)
                        _FollowingList(
                          groups: _groups,
                          onOpen: _openCopies,
                        )
                      else if (_bots.isEmpty && !_busy)
                        Text(
                          l.communityEmpty,
                          style: Red.text(size: 14, height: 1.5, color: Red.muted),
                        )
                      else
                        for (final bot in _bots)
                          _BotRow(
                            bot: bot,
                            count: _section == _Section.follows || _searching
                                ? bot.follows
                                : bot.likes,
                            onTap: () => _openGuest(bot.ownerId, bot.name),
                          ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPreview(FeedCard card) {
    final feed = widget.feed;
    if (feed == null) {
      return Future.value();
    }
    return openCardDetail(context, card: card, client: feed, manage: false);
  }

  Future<void> _openOwned(FeedCard card) async {
    final feed = widget.feed;
    if (feed == null) {
      return;
    }
    widget.onCardOpened?.call(card);
    final result = await openCardDetail(context, card: card, client: feed);
    if (result != null) {
      widget.onCardResult?.call(card, result);
    }
  }

  Future<void> _unfollowFromCopies() async {
    final copies = _copies;
    if (copies == null) {
      return;
    }
    final l = AppLocalizations.of(context);
    final ok = await _confirm(
      context,
      title: l.communityUnfollowTitle,
      body: l.communityUnfollowBody,
      action: l.communityUnfollow,
    );
    if (!ok || !mounted) {
      return;
    }
    await widget.client.unfollow(ownerId: copies.ownerId, name: copies.name);
    if (mounted) {
      setState(() => _copies = null);
      _loadFollowing();
    }
  }
}

class _Guest extends StatelessWidget {
  const _Guest({
    required this.bot,
    required this.busy,
    required this.onFollow,
    required this.onVote,
    required this.onOpenCard,
  });

  final CommunityBot bot;
  final bool busy;
  final VoidCallback onFollow;
  final ValueChanged<int> onVote;
  final ValueChanged<FeedCard> onOpenCard;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final card = bot.card;
    final canVote = bot.listed && !bot.mine && !busy;
    final canFollow = !bot.mine && !busy && (bot.listed || bot.following);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bot.ownerName, style: Red.text(size: 13, height: 1.4, color: Red.muted)),
        if (!bot.listed) ...[
          const SizedBox(height: 8),
          Text(
            l.communityOffline,
            key: const Key('community-offline'),
            style: Red.text(size: 12, height: 1.4, color: Red.dangerFg),
          ),
        ],
        if (bot.botDesc.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(bot.botDesc, style: Red.text(size: 15, height: 1.5)),
        ],
        const SizedBox(height: 12),
        Text(
          '${l.communityLike} ${bot.likes} · ${l.communityDislike} ${bot.dislikes} · ${l.communityFollowerCount} ${bot.follows}',
          style: Red.text(size: 13, height: 1.4, color: Red.muted),
        ),
        if (bot.code.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(bot.code, style: Red.text(size: 14, height: 1.4, tabular: true)),
        ],
        if (!bot.mine) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Action(
                key: const Key('community-follow'),
                label: bot.following ? l.communityFollowingLabel : l.communityFollow,
                onPressed: canFollow ? onFollow : null,
              ),
              _Action(
                key: const Key('community-like'),
                label: l.communityLike,
                selected: bot.vote == 1,
                onPressed: canVote ? () => onVote(1) : null,
              ),
              _Action(
                key: const Key('community-dislike'),
                label: l.communityDislike,
                selected: bot.vote == -1,
                onPressed: canVote ? () => onVote(-1) : null,
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        if (card == null)
          Text(l.communityGuestEmpty, style: Red.text(size: 14, height: 1.5, color: Red.muted))
        else
          _CardLine(card: card, onTap: () => onOpenCard(card)),
      ],
    );
  }
}

class _Copies extends StatelessWidget {
  const _Copies({
    required this.page,
    required this.busy,
    required this.onUnfollow,
    required this.onOpenGuest,
    required this.onOpenCard,
  });

  final CommunityCopies page;
  final bool busy;
  final VoidCallback onUnfollow;
  final VoidCallback onOpenGuest;
  final ValueChanged<FeedCard> onOpenCard;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(page.ownerName, style: Red.text(size: 13, height: 1.4, color: Red.muted)),
        if (!page.listed) ...[
          const SizedBox(height: 8),
          Text(
            l.communityOffline,
            key: const Key('community-offline'),
            style: Red.text(size: 12, height: 1.4, color: Red.dangerFg),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _Action(
              key: const Key('community-unfollow'),
              label: l.communityUnfollow,
              onPressed: busy ? null : onUnfollow,
            ),
            _Action(
              key: const Key('community-open-guest'),
              label: l.communityOpen,
              onPressed: onOpenGuest,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (page.cards.isEmpty)
          Text(
            l.communityCopiesEmpty,
            style: Red.text(size: 14, height: 1.5, color: Red.muted),
          )
        else
          for (final card in page.cards) ...[
            _CardLine(card: card, onTap: () => onOpenCard(card)),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _FollowingList extends StatelessWidget {
  const _FollowingList({required this.groups, required this.onOpen});

  final List<CommunityGroup> groups;
  final void Function(String ownerId, String name) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (groups.isEmpty) {
      return Text(l.communityEmpty, style: Red.text(size: 14, height: 1.5, color: Red.muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups) ...[
          Text(
            group.ownerName,
            key: Key('community-user-${group.ownerId}'),
            style: Red.text(size: 13, height: 1.4, color: Red.muted),
          ),
          const SizedBox(height: 8),
          for (final bot in group.bots)
            InkWell(
              key: Key('followed-${group.ownerId}-${bot.name}'),
              onTap: () => onOpen(group.ownerId, bot.name),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(bot.name, style: Red.text(size: 16, height: 1.3)),
                    ),
                    if (!bot.listed)
                      Text(
                        l.communityOffline,
                        style: Red.text(size: 12, height: 1.4, color: Red.dangerFg),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _BotRow extends StatelessWidget {
  const _BotRow({required this.bot, required this.count, required this.onTap});

  final CommunityBot bot;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return InkWell(
      key: Key('community-row-${bot.ownerId}-${bot.name}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            if (bot.rank != null)
              SizedBox(
                width: 28,
                child: Text(
                  '${bot.rank}',
                  style: Red.text(size: 13, height: 1.3, color: Red.meta, tabular: true),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bot.name, style: Red.text(size: 16, height: 1.3, weight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    bot.listed ? bot.ownerName : '${bot.ownerName} · ${l.communityOffline}',
                    style: Red.text(size: 12, height: 1.4, color: Red.muted),
                  ),
                ],
              ),
            ),
            Text('$count', style: Red.text(size: 14, height: 1.3, tabular: true)),
          ],
        ),
      ),
    );
  }
}

class _CardLine extends StatelessWidget {
  const _CardLine({required this.card, required this.onTap});

  final FeedCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('community-card-${card.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card.title, style: Red.text(size: 16, height: 1.35, weight: FontWeight.w500)),
            if (card.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                card.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Red.text(size: 14, height: 1.5, color: Red.muted),
              ),
            ],
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: selected ? Red.fg : Colors.transparent, width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: Red.text(
                size: 13,
                height: 1.3,
                color: selected ? Red.fg : Red.muted,
                weight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Red.bg : Red.fg,
        backgroundColor: selected ? Red.fg : Colors.transparent,
        disabledForegroundColor: Red.muted,
        side: BorderSide(color: onPressed == null ? Red.border : Red.fg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(
        label,
        style: Red.text(
          size: 13,
          height: 1.2,
          color: onPressed == null
              ? Red.muted
              : selected
              ? Red.bg
              : Red.fg,
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              key: const Key('community-back'),
              tooltip: l.accountBack,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Red.text(size: 15, height: 1.2, weight: FontWeight.w500),
              ),
            ),
          ],
        ),
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
                Text(title, style: Red.text(size: 16, height: 1.35, weight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(body, style: Red.text(size: 14, height: 1.5, color: Red.muted)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Red.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      child: Text(action),
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
  return result ?? false;
}
