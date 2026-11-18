import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_api.dart';
import 'chrome.dart';
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
    this.copiesOwnerId,
    this.copiesName,
    this.guestOwnerId,
    this.guestName,
    this.onCardOpened,
    this.onCardResult,
  });

  final CommunityClient client;
  final FeedClient? feed;
  final String? copiesOwnerId;
  final String? copiesName;
  final String? guestOwnerId;
  final String? guestName;
  final void Function(FeedCard card)? onCardOpened;
  final void Function(FeedCard card, DetailResult result)? onCardResult;

  bool get fromBots =>
      copiesOwnerId != null &&
      copiesOwnerId!.isNotEmpty &&
      copiesName != null &&
      copiesName!.isNotEmpty;

  bool get fromGuest =>
      guestOwnerId != null &&
      guestOwnerId!.isNotEmpty &&
      guestName != null &&
      guestName!.isNotEmpty;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

enum _Section { likes, follows }

enum _Kind { board, guest, copies }

class _Place {
  const _Place.board()
    : kind = _Kind.board,
      guest = null,
      copies = null,
      following = false;

  const _Place.guest(this.guest)
    : kind = _Kind.guest,
      copies = null,
      following = false;

  const _Place.copies(this.copies, {required this.following})
    : kind = _Kind.copies,
      guest = null;

  final _Kind kind;
  final CommunityBot? guest;
  final CommunityCopies? copies;
  final bool following;
}

class _CommunityPageState extends State<CommunityPage> {
  final _search = TextEditingController();
  var _section = _Section.likes;
  var _query = '';
  var _busy = false;
  var _epoch = 0;
  var _listedCount = 0;
  String? _error;
  List<CommunityBot> _bots = const [];
  List<_Place> _stack = const [_Place.board()];

  @override
  void initState() {
    super.initState();
    if (widget.fromBots) {
      _stack = const [];
      _openInitialCopies();
    } else if (widget.fromGuest) {
      _stack = const [];
      _openGuest(widget.guestOwnerId!, widget.guestName!);
    } else {
      _loadBoard();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _searching => _query.isNotEmpty;

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
      setState(() {
        _bots = bots;
        _listedCount = bots.length;
      });
    } on AccountException catch (error) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = accountMessage(AppLocalizations.of(context), error),
        );
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = AppLocalizations.of(context).offline);
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
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = accountMessage(AppLocalizations.of(context), error),
        );
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = AppLocalizations.of(context).offline);
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
    if (query.isEmpty) {
      _loadBoard();
    } else {
      _loadSearch(query);
    }
  }

  void _clearSearch() {
    _search.clear();
    _onSearch('');
  }

  void _pick(_Section section) {
    if (_section == section) {
      return;
    }
    setState(() => _section = section);
    if (_query.isEmpty) {
      _loadBoard();
    }
  }

  Future<void> _openInitialCopies() async {
    final ownerId = widget.copiesOwnerId;
    final name = widget.copiesName;
    if (ownerId == null || name == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final copies = await widget.client.copies(ownerId: ownerId, name: name);
      if (!mounted) {
        return;
      }
      setState(() {
        _stack = [_Place.copies(copies, following: true)];
      });
    } on AccountException catch (error) {
      if (mounted) {
        showRedNotice(
          context,
          accountMessage(AppLocalizations.of(context), error),
        );
      }
    } catch (_) {
      if (mounted) {
        showRedNotice(context, AppLocalizations.of(context).offline);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openGuest(String ownerId, String name) async {
    setState(() => _busy = true);
    try {
      final bot = await widget.client.bot(ownerId: ownerId, name: name);
      if (!mounted) {
        return;
      }
      setState(() => _stack = [..._stack, _Place.guest(bot)]);
    } on AccountException catch (error) {
      if (mounted) {
        showRedNotice(
          context,
          accountMessage(AppLocalizations.of(context), error),
        );
      }
    } catch (_) {
      if (mounted) {
        showRedNotice(context, AppLocalizations.of(context).offline);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openCopies(CommunityBot bot) async {
    setState(() => _busy = true);
    try {
      final copies = await widget.client.copies(
        ownerId: bot.ownerId,
        name: bot.name,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _stack = [..._stack, _Place.copies(copies, following: bot.following)];
      });
    } on AccountException catch (error) {
      if (mounted) {
        showRedNotice(
          context,
          accountMessage(AppLocalizations.of(context), error),
        );
      }
    } catch (_) {
      if (mounted) {
        showRedNotice(context, AppLocalizations.of(context).offline);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshGuest() async {
    final guest = _top?.guest;
    if (guest == null) {
      return;
    }
    final bot = await widget.client.bot(
      ownerId: guest.ownerId,
      name: guest.name,
    );
    if (!mounted ||
        _top?.guest?.ownerId != guest.ownerId ||
        _top?.guest?.name != guest.name) {
      return;
    }
    final next = [..._stack];
    next[next.length - 1] = _Place.guest(bot);
    setState(() => _stack = next);
  }

  Future<void> _toggleFollow() async {
    final guest = _top?.guest;
    if (_busy || guest == null || guest.mine) {
      return;
    }
    final wasFollowing = guest.following;
    if (wasFollowing) {
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
    } else if (!guest.listed && !guest.direct) {
      return;
    }
    await _runAction(() async {
      if (wasFollowing) {
        await widget.client.unfollow(ownerId: guest.ownerId, name: guest.name);
      } else {
        await widget.client.follow(ownerId: guest.ownerId, name: guest.name);
      }
      if (!mounted) {
        return;
      }
      final l = AppLocalizations.of(context);
      showRedNotice(
        context,
        wasFollowing ? l.communityUnfollowed : l.communityFollowed,
      );
      await _refreshGuest();
    });
  }

  Future<void> _vote(int vote) async {
    final guest = _top?.guest;
    if (guest == null || guest.mine || !guest.listed) {
      return;
    }
    final next = guest.vote == vote ? 0 : vote;
    await _runAction(() async {
      await widget.client.vote(
        ownerId: guest.ownerId,
        name: guest.name,
        vote: next,
      );
      await _refreshGuest();
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } on AccountException catch (error) {
      if (mounted) {
        showRedNotice(
          context,
          accountMessage(AppLocalizations.of(context), error),
        );
      }
    } catch (_) {
      if (mounted) {
        showRedNotice(context, AppLocalizations.of(context).offline);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copyCode(String code) async {
    if (code.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) {
      return;
    }
    showRedNotice(context, AppLocalizations.of(context).communityCopied);
  }

  _Place? get _top => _stack.isEmpty ? null : _stack.last;

  void _back() {
    if (_stack.length > 1) {
      final leaving = _stack.last;
      final under = _stack[_stack.length - 2];
      final next = _stack.sublist(0, _stack.length - 1);
      final guest = leaving.guest;
      final copies = under.copies;
      if (leaving.kind == _Kind.guest &&
          under.kind == _Kind.copies &&
          guest != null &&
          copies != null) {
        next[next.length - 1] = _Place.copies(
          copies,
          following: guest.following,
        );
      }
      setState(() => _stack = next);
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
    final top = _top;
    final title = switch (top?.kind) {
      _Kind.guest => top!.guest!.name,
      _Kind.copies => top!.copies!.name,
      _ => l.community,
    };
    final backTip = _stack.length == 1 && (widget.fromBots || widget.fromGuest)
        ? l.bots
        : l.communityBack;
    return PopScope(
      canPop: _stack.length <= 1,
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
            _Bar(title: title, tooltip: backTip, onBack: _back),
            Expanded(
              child: RedCenter(
                maxWidth: Red.articleColumn,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(pad, 24, pad, 72),
                  children: [
                    if (top?.kind == _Kind.guest)
                      _Guest(
                        bot: top!.guest!,
                        busy: _busy,
                        onFollow: _toggleFollow,
                        onVote: _vote,
                        onCopy: () => _copyCode(top.guest!.code),
                        onOpenCard: _openPreview,
                        onAll: top.guest!.following
                            ? () => _openCopies(top.guest!)
                            : null,
                      )
                    else if (top?.kind == _Kind.copies)
                      _Copies(
                        page: top!.copies!,
                        following: top.following,
                        busy: _busy,
                        onUnfollow: _unfollowFromCopies,
                        onOpenGuest: () =>
                            _openGuest(top.copies!.ownerId, top.copies!.name),
                        onOpenCard: _openOwned,
                      )
                    else if (top?.kind == _Kind.board)
                      ..._board(l)
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _board(AppLocalizations l) {
    final countLabel = _section == _Section.follows
        ? l.communityFollowerCount
        : l.communityLike;
    final status = _searching
        ? l.communityResults(_query, _bots.length)
        : _section == _Section.follows
        ? l.communitySortFollows
        : l.communitySortLikes;
    return [
      _SearchBox(
        controller: _search,
        hint: l.communitySearchHint,
        label: l.communitySearchLabel,
        clearLabel: l.communityClear,
        showClear: _search.text.isNotEmpty,
        onChanged: _onSearch,
        onClear: _clearSearch,
      ),
      const SizedBox(height: 16),
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Red.border)),
        ),
        child: Row(
          children: [
            _Tab(
              key: const Key('community-likes'),
              label: l.communityLikes,
              count: '$_listedCount',
              selected: _section == _Section.likes,
              onTap: () => _pick(_Section.likes),
            ),
            _Tab(
              key: const Key('community-follows'),
              label: l.communityFollows,
              count: '$_listedCount',
              selected: _section == _Section.follows,
              onTap: () => _pick(_Section.follows),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Text(
        status.toUpperCase(),
        style: Red.text(
          size: 10.5,
          height: 1.4,
          letterSpacing: 0.8,
          color: Red.meta,
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        Text(
          _error!,
          style: Red.text(size: 14, height: 1.5, color: Red.dangerFg),
        ),
      ] else if (_bots.isEmpty && !_busy)
        _EmptyBoard(query: _searching ? _query : null)
      else
        for (var i = 0; i < _bots.length; i++)
          _BotRow(
            bot: _bots[i],
            index: i,
            count: _section == _Section.follows
                ? _bots[i].follows
                : _bots[i].likes,
            countLabel: countLabel,
            first: i == 0,
            onTap: () => _openGuest(_bots[i].ownerId, _bots[i].name),
          ),
      if (!_searching) ...[
        const SizedBox(height: 20),
        Text(
          l.communityBoardNote,
          style: Red.text(size: 10, height: 1.6, color: Red.meta),
        ),
      ],
    ];
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
    final place = _top;
    final copies = place?.copies;
    if (place == null || copies == null || !place.following) {
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
    await _runAction(() async {
      await widget.client.unfollow(ownerId: copies.ownerId, name: copies.name);
      if (!mounted || _top != place) {
        return;
      }
      final next = [..._stack];
      next[next.length - 1] = _Place.copies(copies, following: false);
      setState(() => _stack = next);
      showRedNotice(context, l.communityUnfollowed);
    });
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.hint,
    required this.label,
    required this.clearLabel,
    required this.showClear,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final String label;
  final String clearLabel;
  final bool showClear;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Red.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Red.border),
      ),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search, size: 17, color: Red.meta, semanticLabel: label),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const Key('community-search'),
                controller: controller,
                onChanged: onChanged,
                style: Red.text(size: 15, height: 1.4),
                cursorColor: Red.fg,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: Red.text(size: 15, height: 1.4, color: Red.muted),
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (showClear)
              IconButton(
                key: const Key('community-clear'),
                tooltip: clearLabel,
                onPressed: onClear,
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  fixedSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(Icons.close, size: 15, color: Red.muted),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.query});

  final String? query;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final searching = query != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 48, 14, 0),
      child: Column(
        children: [
          Text(
            searching ? l.communityEmptySearch(query!) : l.communityEmpty,
            textAlign: TextAlign.center,
            style: Red.text(size: 15, height: 1.5, weight: FontWeight.w500),
          ),
          if (!searching) ...[
            const SizedBox(height: 8),
            Text(
              l.communityBoardNote,
              textAlign: TextAlign.center,
              style: Red.text(size: 11, height: 1.65, color: Red.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Guest extends StatelessWidget {
  const _Guest({
    required this.bot,
    required this.busy,
    required this.onFollow,
    required this.onVote,
    required this.onCopy,
    required this.onOpenCard,
    required this.onAll,
  });

  final CommunityBot bot;
  final bool busy;
  final VoidCallback onFollow;
  final ValueChanged<int> onVote;
  final VoidCallback onCopy;
  final ValueChanged<FeedCard> onOpenCard;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final card = bot.card;
    final canVote = bot.listed && !bot.mine && !busy;
    final canFollow =
        !bot.mine && !busy && (bot.listed || bot.direct || bot.following);
    final owner = bot.mine
        ? '${bot.ownerName} · ${l.communityMine}'
        : bot.ownerName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Red.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Red.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Mark(text: bot.name, large: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bot.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Red.text(
                              size: 20,
                              height: 1.25,
                              weight: FontWeight.w500,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            owner,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Red.text(
                              size: 11,
                              height: 1.4,
                              color: Red.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!bot.listed && !bot.direct)
                      Text(
                        l.communityOffline.toUpperCase(),
                        key: const Key('community-offline'),
                        style: Red.text(
                          size: 10,
                          height: 1.3,
                          letterSpacing: 0.6,
                          color: Red.dangerFg,
                        ),
                      ),
                  ],
                ),
                if (bot.botDesc.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    bot.botDesc,
                    style: Red.text(size: 14, height: 1.6, color: Red.fg2),
                  ),
                ],
                const SizedBox(height: 18),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Red.borderSoft)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        _Stat(value: bot.likes, label: l.communityLike),
                        _Stat(value: bot.dislikes, label: l.communityDislike),
                        _Stat(
                          value: bot.follows,
                          label: l.communityFollowerCount,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!bot.mine) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _IconAction(
                        key: const Key('community-follow'),
                        tooltip: bot.following
                            ? l.communityUnfollow
                            : l.communityFollow,
                        kind: _LineKind.eye,
                        color: bot.following ? Red.followFg : Red.meta,
                        onPressed: canFollow ? onFollow : null,
                      ),
                      const SizedBox(width: 4),
                      _IconAction(
                        key: const Key('community-like'),
                        tooltip: l.communityLike,
                        kind: _LineKind.up,
                        color: bot.vote == 1 ? Red.likeFg : Red.meta,
                        onPressed: canVote ? () => onVote(1) : null,
                      ),
                      const SizedBox(width: 4),
                      _IconAction(
                        key: const Key('community-dislike'),
                        tooltip: l.communityDislike,
                        kind: _LineKind.down,
                        color: bot.vote == -1 ? Red.fg : Red.meta,
                        onPressed: canVote ? () => onVote(-1) : null,
                      ),
                    ],
                  ),
                ],
                if (bot.code.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _CodeRow(code: bot.code, onCopy: onCopy),
                ],
              ],
            ),
          ),
        ),
        _SectionLabel(l.communityLatest),
        if (card == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              l.communityGuestEmpty,
              style: Red.text(size: 13, height: 1.6, color: Red.muted),
            ),
          )
        else
          _CardPreview(card: card, onTap: () => onOpenCard(card)),
        if (onAll != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('community-all-cards'),
            onPressed: busy ? null : onAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: Red.fg2,
              side: BorderSide(color: Red.border),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              l.communityAllCards,
              style: Red.text(
                size: 12,
                height: 1,
                weight: FontWeight.w500,
                color: Red.fg2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Copies extends StatelessWidget {
  const _Copies({
    required this.page,
    required this.following,
    required this.busy,
    required this.onUnfollow,
    required this.onOpenGuest,
    required this.onOpenCard,
  });

  final CommunityCopies page;
  final bool following;
  final bool busy;
  final VoidCallback onUnfollow;
  final VoidCallback onOpenGuest;
  final ValueChanged<FeedCard> onOpenCard;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Red.borderSoft)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    page.ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Red.text(size: 12, height: 1.4, color: Red.muted),
                  ),
                ),
                if (!page.listed && !page.direct)
                  Text(
                    l.communityOffline.toUpperCase(),
                    key: const Key('community-offline'),
                    style: Red.text(
                      size: 10,
                      height: 1.3,
                      letterSpacing: 0.6,
                      color: Red.dangerFg,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            if (following) ...[
              _Action(
                key: const Key('community-unfollow'),
                label: l.communityUnfollow,
                danger: true,
                onPressed: busy ? null : onUnfollow,
              ),
              const SizedBox(width: 8),
            ],
            _Action(
              key: const Key('community-open-guest'),
              label: l.communityOpenBot,
              onPressed: onOpenGuest,
            ),
          ],
        ),
        _SectionLabel(l.communityAllCards),
        if (page.cards.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              l.communityCopiesEmpty,
              style: Red.text(size: 13, height: 1.6, color: Red.muted),
            ),
          )
        else
          for (var i = 0; i < page.cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _CardPreview(
              card: page.cards[i],
              onTap: () => onOpenCard(page.cards[i]),
            ),
          ],
      ],
    );
  }
}

class _BotRow extends StatelessWidget {
  const _BotRow({
    required this.bot,
    required this.index,
    required this.count,
    required this.countLabel,
    required this.first,
    required this.onTap,
  });

  final CommunityBot bot;
  final int index;
  final int count;
  final String countLabel;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rank = index + 1;
    final top = index < 3;
    final sub = [
      bot.ownerName,
      if (bot.botDesc.isNotEmpty) bot.botDesc,
    ].join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: Red.borderSoft)),
      ),
      child: InkWell(
        key: Key('community-row-${bot.ownerId}-${bot.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  rank < 10 ? '0$rank' : '$rank',
                  style: Red.text(
                    size: 11.5,
                    height: 1.2,
                    letterSpacing: 0.6,
                    color: top ? Red.fg : Red.meta,
                    weight: top ? FontWeight.w600 : FontWeight.w400,
                    tabular: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _Mark(text: bot.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Red.text(
                        size: 15,
                        height: 1.35,
                        weight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        style: Red.text(
                          size: 11.5,
                          height: 1.45,
                          color: Red.muted,
                        ),
                        children: [
                          TextSpan(text: sub),
                          if (!bot.listed && !bot.direct)
                            TextSpan(
                              text: ' · ${l.communityOffline}',
                              style: Red.text(
                                size: 11.5,
                                height: 1.45,
                                color: Red.dangerFg,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$count',
                    style: Red.text(
                      size: 15,
                      height: 1.1,
                      weight: FontWeight.w500,
                      tabular: true,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    countLabel.toUpperCase(),
                    style: Red.text(
                      size: 9,
                      height: 1.2,
                      letterSpacing: 0.6,
                      color: Red.meta,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardPreview extends StatelessWidget {
  const _CardPreview({required this.card, required this.onTap});

  final FeedCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final when = detailWhen(l, card.createdAt);
    return Material(
      color: Red.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Red.border),
      ),
      child: InkWell(
        key: Key('community-card-${card.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (when.isNotEmpty)
                Text(
                  when.toUpperCase(),
                  style: Red.text(
                    size: 10,
                    height: 1.4,
                    weight: FontWeight.w500,
                    letterSpacing: 1,
                    color: Red.meta,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                card.title,
                style: Red.text(size: 15, height: 1.4, weight: FontWeight.w500),
              ),
              if (card.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  card.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Red.text(size: 12.5, height: 1.55, color: Red.muted),
                ),
              ],
              if (card.source.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  card.source,
                  style: Red.text(size: 10.5, height: 1.4, color: Red.meta),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.text, this.large = false});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 54.0 : 38.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: large ? Red.surfaceWarm : Red.surface,
        borderRadius: BorderRadius.circular(large ? 10 : 8),
        border: Border.all(color: Red.border),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            nameMark(text),
            style: Red.text(
              size: large ? 21 : 15,
              height: 1,
              color: large ? Red.fg : Red.fg2,
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: Red.text(
              size: 19,
              height: 1.1,
              weight: FontWeight.w500,
              tabular: true,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: Red.text(
              size: 10,
              height: 1.3,
              letterSpacing: 0.5,
              color: Red.meta,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Red.surfaceWarm,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Red.border),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Text(
              l.communityCode.toUpperCase(),
              style: Red.text(
                size: 9.5,
                height: 1.3,
                letterSpacing: 1,
                color: Red.meta,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                code,
                key: const Key('community-code'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Red.text(
                  size: 13,
                  height: 1.3,
                  letterSpacing: 0.8,
                  color: Red.fg2,
                  tabular: true,
                ),
              ),
            ),
            TextButton(
              onPressed: onCopy,
              child: Text(
                l.communityCopy,
                style: Red.text(size: 11, height: 1.2, weight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Text(
        text.toUpperCase(),
        style: Red.text(
          size: 10,
          height: 1.4,
          letterSpacing: 1,
          color: Red.meta,
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Red.fg : Red.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? Red.fg : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Red.text(
                    size: 12.5,
                    height: 1.2,
                    weight: FontWeight.w500,
                    color: color,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  count,
                  style: Red.text(
                    size: 10.5,
                    height: 1.2,
                    color: selected ? Red.fg2 : Red.meta,
                    tabular: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _LineKind { eye, up, down }

class _IconAction extends StatelessWidget {
  const _IconAction({
    Key? key,
    required this.tooltip,
    required this.kind,
    required this.color,
    required this.onPressed,
  }) : buttonKey = key,
       super();

  final Key? buttonKey;
  final String tooltip;
  final _LineKind kind;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final shown = onPressed == null ? color.withValues(alpha: 0.45) : color;
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: shown,
        disabledForegroundColor: shown,
        minimumSize: const Size(44, 44),
        fixedSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        overlayColor: Red.dark
            ? const Color(0x0FFFFFFF)
            : const Color(0x0D09090B),
      ),
      icon: _LineIcon(kind, color: shown),
    );
  }
}

class _LineIcon extends StatelessWidget {
  const _LineIcon(this.kind, {required this.color});

  final _LineKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(21, 21),
      painter: _LineIconPainter(kind, color),
    );
  }
}

class _LineIconPainter extends CustomPainter {
  const _LineIconPainter(this.kind, this.color);

  final _LineKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.scale(size.width / 24, size.height / 24);
    if (kind == _LineKind.eye) {
      canvas.drawPath(_eye(), paint);
      canvas.drawCircle(const Offset(12, 12), 3, paint);
      return;
    }
    final stem = Path();
    final body = Path();
    if (kind == _LineKind.up) {
      stem.moveTo(7, 10);
      stem.lineTo(7, 22);
      body.moveTo(7, 10);
      body.relativeLineTo(3.2, 0);
      body.relativeArcToPoint(
        const Offset(1.9, -1.4),
        radius: const Radius.elliptical(2, 2),
        clockwise: false,
      );
      body.relativeLineTo(1.6, -5.2);
      body.arcToPoint(
        const Offset(18, 5.5),
        radius: const Radius.elliptical(2.4, 2.4),
      );
      body.lineTo(18, 10);
      body.relativeLineTo(2.2, 0);
      body.relativeArcToPoint(
        const Offset(1.95, 2.45),
        radius: const Radius.elliptical(2, 2),
      );
      body.relativeLineTo(-1.4, 6.3);
      body.arcToPoint(const Offset(17.8, 21), radius: const Radius.circular(3));
      body.lineTo(7, 21);
    } else {
      stem.moveTo(17, 14);
      stem.lineTo(17, 2);
      body.moveTo(17, 14);
      body.relativeLineTo(-3.2, 0);
      body.relativeArcToPoint(
        const Offset(-1.9, 1.4),
        radius: const Radius.elliptical(2, 2),
        clockwise: false,
      );
      body.relativeLineTo(-1.6, 5.2);
      body.arcToPoint(
        const Offset(6, 18.5),
        radius: const Radius.elliptical(2.4, 2.4),
      );
      body.lineTo(6, 14);
      body.relativeLineTo(-2.2, 0);
      body.relativeArcToPoint(
        const Offset(-1.95, -2.45),
        radius: const Radius.elliptical(2, 2),
      );
      body.relativeLineTo(1.4, -6.3);
      body.arcToPoint(const Offset(6.2, 3), radius: const Radius.circular(3));
      body.lineTo(17, 3);
    }
    canvas.drawPath(stem, paint);
    canvas.drawPath(body, paint);
  }

  @override
  bool shouldRepaint(_LineIconPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}

Path _eye() {
  return Path()
    ..moveTo(2.5, 12)
    ..cubicTo(2.5, 12, 6, 5.5, 12, 5.5)
    ..cubicTo(18, 5.5, 21.5, 12, 21.5, 12)
    ..cubicTo(21.5, 12, 18, 18.5, 12, 18.5)
    ..cubicTo(6, 18.5, 2.5, 12, 2.5, 12)
    ..close();
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = !enabled
        ? Red.muted
        : danger
        ? Red.dangerFg
        : Red.fg2;
    final side = !enabled
        ? Red.borderSoft
        : danger
        ? Red.dangerLine
        : Red.border;
    return Expanded(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: Colors.transparent,
          disabledForegroundColor: Red.muted,
          side: BorderSide(color: side),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Red.text(
            size: 12,
            height: 1,
            weight: FontWeight.w500,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.title,
    required this.tooltip,
    required this.onBack,
  });

  final String title;
  final String tooltip;
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
                  key: const Key('community-back'),
                  tooltip: tooltip,
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
                    size: 16,
                    height: 1.35,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: Red.text(size: 14, height: 1.5, color: Red.muted),
                ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
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
