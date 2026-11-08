import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'chrome.dart';
import 'feed_client.dart';
import 'l10n/app_localizations.dart';
import 'red.dart';

enum DetailResult { deleted, markedUnread }

Future<DetailResult?> openCardDetail(
  BuildContext context, {
  required FeedCard card,
  required FeedClient client,
  String? backTooltip,
}) {
  return Navigator.push<DetailResult>(
    context,
    PageRouteBuilder<DetailResult>(
      pageBuilder: (_, _, _) =>
          DetailPage(card: card, client: client, backTooltip: backTooltip),
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
  });

  final FeedCard card;
  final FeedClient client;

  final String? backTooltip;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _scroll = ScrollController();
  var _progress = 0.0;
  var _deleting = false;

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

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final l = AppLocalizations.of(context);
    final card = widget.card;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 690;
    final pad = Red.gutter(width);
    final time = detailWhen(l, card.createdAt);
    final body = card.body.trim();
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
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: categoryLabel(l, card.category),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (time.isNotEmpty) ...[
                                        TextSpan(
                                          text: ' · ',
                                          style: TextStyle(color: Red.meta),
                                        ),
                                        TextSpan(text: time),
                                      ],
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Red.text(
                                    size: 12,
                                    color: Red.fg2,
                                    height: 1.4,
                                    tabular: true,
                                  ),
                                ),
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
                  DecoratedBox(
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
                            _Figure(
                              url: url,
                              headers: widget.client.imageHeadersFor(url),
                              maxHeight: wide ? 460 : 440,
                            ),
                          Padding(
                            padding: wide
                                ? const EdgeInsets.fromLTRB(48, 40, 48, 46)
                                : const EdgeInsets.fromLTRB(22, 26, 22, 30),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
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
                                if (body.isNotEmpty) ...[
                                  const SizedBox(height: 20),
                                  ColoredBox(
                                    color: Red.border,
                                    child: const SizedBox(height: 1),
                                  ),
                                  const SizedBox(height: 20),
                                  MarkdownBody(
                                    data: body,
                                    selectable: true,
                                    softLineBreak: true,
                                    fitContent: false,
                                    styleSheet: _articleSheet(wide),
                                    onTapLink: (_, href, _) {
                                      if (href != null) {
                                        _open(href);
                                      }
                                    },
                                    imageBuilder: (uri, _, _) {
                                      if (uri.scheme != 'http' &&
                                          uri.scheme != 'https') {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: _Figure(
                                          url: uri.toString(),
                                          headers: widget.client
                                              .imageHeadersFor(uri.toString()),
                                          maxHeight: wide ? 460 : 440,
                                        ),
                                      );
                                    },
                                    builders: {'hr': _HairlineBuilder()},
                                  ),
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
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: Red.border,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
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
                                if (card.createdBot.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    card.createdBot.toUpperCase(),
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
                        ],
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

class _Figure extends StatelessWidget {
  const _Figure({
    required this.url,
    required this.headers,
    required this.maxHeight,
  });

  final String url;
  final Map<String, String> headers;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Red.surfaceWarm,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 120, maxHeight: maxHeight),
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: headers.isEmpty ? null : headers,
            fit: BoxFit.contain,
            width: double.infinity,
            alignment: Alignment.center,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
            placeholder: (_, _) => const SizedBox(height: 180),
            errorWidget: (_, _, _) => SizedBox(
              height: 180,
              child: Icon(Icons.image_not_supported_outlined, color: Red.meta),
            ),
          ),
        ),
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

class _HairlineBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: Red.border),
    );
  }
}

MarkdownStyleSheet _articleSheet(bool wide) {
  final size = wide ? 17.0 : 16.0;
  final body = Red.text(size: size, height: 1.8, color: Red.fg2);
  TextStyle heading(double headingSize) {
    return Red.text(
      size: headingSize,
      height: 1.3,
      weight: FontWeight.w500,
      letterSpacing: Red.em(headingSize, -0.028),
      color: Red.fg,
    );
  }

  return MarkdownStyleSheet(
    p: body,
    pPadding: EdgeInsets.zero,
    h1: heading(wide ? 28 : 24),
    h1Padding: EdgeInsets.zero,
    h2: heading(wide ? 22 : 20),
    h2Padding: EdgeInsets.zero,
    h3: heading(wide ? 18 : 17),
    h3Padding: EdgeInsets.zero,
    h4: heading(size),
    h4Padding: EdgeInsets.zero,
    h5: heading(size - 1),
    h5Padding: EdgeInsets.zero,
    h6: heading(size - 2),
    h6Padding: EdgeInsets.zero,
    a: TextStyle(
      color: Red.fg,
      decoration: TextDecoration.underline,
      decorationColor: Red.fg,
    ),
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: TextStyle(fontWeight: FontWeight.w600, color: Red.fg),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    blockquote: body.copyWith(color: Red.muted),
    blockquotePadding: const EdgeInsets.only(left: 14),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: Red.lineStrong, width: 2)),
    ),
    code: Red.text(
      size: size * 0.88,
      height: 1.5,
      color: Red.fg,
    ).copyWith(fontFamily: 'monospace', backgroundColor: Red.surfaceWarm),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: Red.surfaceWarm,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Red.border),
    ),
    blockSpacing: 16,
    listIndent: 24,
    listBullet: body,
    listBulletPadding: const EdgeInsets.only(right: 8),
    checkbox: body.copyWith(color: Red.fg),
    tableHead: body.copyWith(color: Red.fg, fontWeight: FontWeight.w600),
    tableBody: body,
    tableHeadAlign: TextAlign.left,
    tableBorder: TableBorder.all(color: Red.border),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    tableCellsDecoration: const BoxDecoration(),
  );
}
