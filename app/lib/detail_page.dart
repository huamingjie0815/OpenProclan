import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'article.dart';
import 'chrome.dart';
import 'feed_client.dart';
import 'l10n/app_localizations.dart';
import 'red.dart';
import 'share_image.dart';

enum DetailResult { deleted, markedUnread }

/// Title, summary, body, source, source links, and video URLs.
/// A lone `[[chart:N]]` line is left out. The same line inside a fence stays.
/// Image URLs stay out: `/media` needs the session and expires with the card.
String cardShareText(FeedCard card) {
  final parts = <String>[];
  void add(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      parts.add(trimmed);
    }
  }

  void addLines(List<String> lines) {
    final kept = [
      for (final line in lines)
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (kept.isNotEmpty) {
      parts.add(kept.join('\n'));
    }
  }

  add(card.title);
  add(card.summary);
  add(shareBody(card.body));
  add(card.source);
  addLines(card.sourceUrls);
  addLines(card.videoUrls);
  return parts.join('\n\n');
}

Future<DetailResult?> openCardDetail(
  BuildContext context, {
  required FeedCard card,
  required FeedClient client,
  String? backTooltip,
  bool manage = true,
}) {
  return Navigator.push<DetailResult>(
    context,
    PageRouteBuilder<DetailResult>(
      pageBuilder: (_, _, _) => DetailPage(
        card: card,
        client: client,
        backTooltip: backTooltip,
        manage: manage,
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
  );
}

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.card,
    required this.client,
    this.backTooltip,
    this.manage = true,
  });

  final FeedCard card;
  final FeedClient client;

  final String? backTooltip;

  /// False when this is someone else's original card.
  final bool manage;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _scroll = ScrollController();
  final _shareKey = GlobalKey();
  var _progress = 0.0;
  var _deleting = false;
  var _sharing = false;
  int? _activeVideo;
  late final List<ArticlePiece> _pieces = articlePieces(widget.card.body);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncProgress);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncProgress());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncProgress() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    final max = _scroll.position.maxScrollExtent;
    final ratio = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((ratio - _progress).abs() < 0.001) {
      return;
    }
    setState(() => _progress = ratio);
  }

  void _markUnread() {
    Navigator.pop(context, DetailResult.markedUnread);
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Red.scrim,
      builder: (context) {
        return Dialog(
          backgroundColor: Red.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
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
                    l.deleteTitle,
                    style: Red.text(
                      size: 22,
                      height: 1.3,
                      weight: FontWeight.w500,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.deleteBody,
                    style: Red.text(size: 14, color: Red.fg2, height: 1.65),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _SoftButton(
                          label: l.cancel,
                          onPressed: () => Navigator.pop(context, false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DangerButton(
                          label: l.delete,
                          onPressed: () => Navigator.pop(context, true),
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
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _deleting = true);
    try {
      await widget.client.deleteCard(widget.card.id);
      if (mounted) {
        Navigator.pop(context, DetailResult.deleted);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        showRedNotice(context, AppLocalizations.of(context).deleteFailed);
      }
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _share(BuildContext anchor) async {
    if (_sharing) return;
    _sharing = true;
    try {
      await _shareCard(anchor);
    } finally {
      _sharing = false;
    }
  }

  Future<void> _shareCard(BuildContext anchor) async {
    final card = widget.card;
    final text = cardShareText(card);
    final box = anchor.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final title = card.title.trim();
    // 卡片整张画成长图；截不到就退回只发文字。
    final png = await captureBoundaryPng(_shareKey);
    final file = png == null ? null : await writeShareImage(png, card.id);
    if (!mounted) return;
    if (text.isEmpty && file == null) {
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text.isEmpty ? null : text,
          subject: title.isEmpty ? null : title,
          files: file == null
              ? null
              : [XFile(file.path, mimeType: 'image/png')],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) {
        showRedNotice(context, AppLocalizations.of(context).shareFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final l = AppLocalizations.of(context);
    final card = widget.card;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 690;
    final pad = Red.gutter(width);
    final time = detailWhen(l, card.createdAt);
    final imageHeight = wide ? 460.0 : 440.0;
    final slots = articleSlots(
      pieces: _pieces,
      charts: card.charts,
      wide: wide,
      imageMaxHeight: imageHeight,
      imageHeadersFor: widget.client.imageHeadersFor,
      onOpen: _open,
    );
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Red.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: Red.bg,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Red.border)),
              ),
              child: SafeArea(
                bottom: false,
                child: RedCenter(
                  maxWidth: Red.articleColumn,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 60,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: pad > 8 ? pad - 8 : 0,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                key: const Key('detail-back'),
                                tooltip: widget.backTooltip ?? l.back,
                                onPressed: () => Navigator.maybePop(context),
                                icon: const Icon(Icons.chevron_left, size: 22),
                                style: IconButton.styleFrom(
                                  foregroundColor: Red.fg2,
                                  fixedSize: const Size(44, 44),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  time,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Red.text(
                                    size: 12,
                                    color: Red.fg2,
                                    height: 1.4,
                                    tabular: true,
                                  ),
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  return IconButton(
                                    key: const Key('detail-share'),
                                    tooltip: l.share,
                                    onPressed: () => _share(context),
                                    icon: const Icon(Icons.ios_share, size: 18),
                                    style: IconButton.styleFrom(
                                      foregroundColor: Red.fg2,
                                      fixedSize: const Size(44, 44),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      Semantics(
                        label: l.readProgress,
                        value: '${(_progress * 100).round()}%',
                        child: SizedBox(
                          height: 2,
                          child: ColoredBox(
                            color: Colors.transparent,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: _progress,
                                child: ColoredBox(
                                  color: Red.accent,
                                  child: const SizedBox(height: 2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: RedCenter(
              maxWidth: Red.articleColumn,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  pad,
                  wide ? 24 : 14,
                  pad,
                  40 + bottom,
                ),
                children: [
                  RepaintBoundary(
                    key: _shareKey,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Red.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Red.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final url in card.images)
                              ArticleFigure(
                                url: url,
                                headers: widget.client.imageHeadersFor(url),
                                maxHeight: imageHeight,
                              ),
                            Padding(
                              padding: wide
                                  ? const EdgeInsets.fromLTRB(48, 40, 48, 46)
                                  : const EdgeInsets.fromLTRB(22, 26, 22, 30),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (
                                    var i = 0;
                                    i < card.videoUrls.length;
                                    i++
                                  ) ...[
                                    if (i > 0) const SizedBox(height: 12),
                                    ArticleVideo(
                                      url: card.videoUrls[i],
                                      index: i,
                                      active: _activeVideo == i,
                                      onActivate: () {
                                        setState(() => _activeVideo = i);
                                      },
                                      onOpen: _open,
                                    ),
                                  ],
                                  SelectionArea(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (card.videoUrls.isNotEmpty)
                                          const SizedBox(height: 20),
                                        Text(
                                          card.title,
                                          style: Red.text(
                                            size: wide ? 40 : 30,
                                            height: wide ? 1.2 : 1.25,
                                            letterSpacing: Red.em(
                                              wide ? 40 : 30,
                                              -0.028,
                                            ),
                                            weight: FontWeight.w500,
                                          ),
                                        ),
                                        if (card.summary.isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            card.summary,
                                            style: Red.text(
                                              size: wide ? 16 : 15,
                                              color: Red.muted,
                                              height: 1.7,
                                            ),
                                          ),
                                        ],
                                        if (slots.isNotEmpty) ...[
                                          const SizedBox(height: 20),
                                          ColoredBox(
                                            color: Red.border,
                                            child: const SizedBox(height: 1),
                                          ),
                                          const SizedBox(height: 20),
                                          ...slots,
                                        ],
                                        if (card.tags.isNotEmpty) ...[
                                          const SizedBox(height: 20),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (final tag in card.tags)
                                                DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: Red.border,
                                                    ),
                                                  ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 9,
                                                          vertical: 6,
                                                        ),
                                                    child: Text(
                                                      tag.toUpperCase(),
                                                      style: Red.text(
                                                        size: 10,
                                                        color: Red.muted,
                                                        height: 1.2,
                                                        letterSpacing: 0.7,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                        if (card.source.isNotEmpty ||
                                            card.sourceUrls.isNotEmpty) ...[
                                          const SizedBox(height: 20),
                                          _SourceBox(card: card, onOpen: _open),
                                        ],
                                        if (card.createdBot.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            card.sourceUsername.isEmpty
                                                ? card.createdBot.toUpperCase()
                                                : '${card.createdBot.toUpperCase()} · ${card.sourceUsername}',
                                            style: Red.text(
                                              size: 10.5,
                                              color: Red.meta,
                                              height: 1.4,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (widget.manage) ...[
                                    const SizedBox(height: 20),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: _GhostButton(
                                        label: l.markUnread,
                                        onPressed: _markUnread,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: _deleting ? null : _delete,
                                      icon: Icon(
                                        Icons.delete_outline,
                                        size: 15,
                                        color: Red.dangerFg,
                                      ),
                                      label: Text(l.deleteCard.toUpperCase()),
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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

class _SourceBox extends StatelessWidget {
  const _SourceBox({required this.card, required this.onOpen});

  final FeedCard card;
  final Future<void> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mark = sourceMark(card.source);
    final urls = card.sourceUrls;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Red.surfaceWarm,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Red.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mark.isNotEmpty) ...[
              MarkAvatar(text: mark, size: 32, fontSize: 12),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (card.source.isNotEmpty)
                    Text(
                      card.source,
                      style: Red.text(
                        size: 12.5,
                        height: 1.4,
                        weight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    l.sourceNote,
                    style: Red.text(size: 10.5, color: Red.meta, height: 1.5),
                  ),
                  for (var i = 0; i < urls.length; i++)
                    TextButton(
                      onPressed: () => onOpen(urls[i]),
                      style: TextButton.styleFrom(
                        foregroundColor: Red.fg,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        i == 0 ? l.openOriginal : urls[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Red.text(
                          size: 12,
                          height: 1.4,
                        ).copyWith(decoration: TextDecoration.underline),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Red.fg,
        side: BorderSide(color: Red.border),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: Red.text(
          size: 11,
          height: 1,
          weight: FontWeight.w500,
          letterSpacing: 0.4,
        ),
      ),
      child: Text(label.toUpperCase()),
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Red.fg,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: Red.border),
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: Red.text(size: 14, height: 1, weight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Red.onDanger,
        backgroundColor: Red.danger,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: Red.text(
          size: 11,
          height: 1,
          weight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Red.onDanger,
        ),
      ),
      child: Text(label),
    );
  }
}
