import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:video_player/video_player.dart';

import 'feed_client.dart';
import 'red.dart';

/// One block of the article column. A chart marker is split out before
/// Markdown runs, so the chart is a sibling of the HTML and not a platform
/// view inside it.
sealed class ArticlePiece {
  const ArticlePiece();
}

class ArticleHtml extends ArticlePiece {
  const ArticleHtml(this.html);

  final String html;
}

class ArticleChartMark extends ArticlePiece {
  const ArticleChartMark(this.index);

  final int index;
}

final _chartLine = RegExp(r'^\[\[chart:(\d+)\]\]$');

bool _fenceLine(String trimmed) => trimmed.startsWith('```');

/// A line that can take a hard break. Block markers stay untouched so a list
/// or a heading is not glued to the next line.
bool _plainLine(String trimmed) {
  if (trimmed.isEmpty || _fenceLine(trimmed)) {
    return false;
  }
  if (trimmed.startsWith('#') ||
      trimmed.startsWith('>') ||
      trimmed.startsWith('|')) {
    return false;
  }
  if (RegExp(r'^([-*_])\1{2,}\s*$').hasMatch(trimmed)) {
    return false;
  }
  if (RegExp(r'^([-*+]|\d+[.)])\s').hasMatch(trimmed)) {
    return false;
  }
  return true;
}

String _hardBreaks(String markdown) {
  final lines = markdown.split('\n');
  var fence = false;
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final trimmed = line.trim();
    if (_fenceLine(trimmed)) {
      fence = !fence;
      out.add(line);
      continue;
    }
    if (!fence && i + 1 < lines.length) {
      final next = lines[i + 1].trim();
      final broken = line.endsWith('  ') || line.endsWith('\\');
      if (_plainLine(trimmed) && _plainLine(next) && !broken) {
        line = '$line  ';
      }
    }
    out.add(line);
  }
  return out.join('\n');
}

/// GitHub-flavored Markdown, with raw HTML left as text.
///
/// The stock flavor keeps `<script>`, `<video>`, and `<iframe>` as real tags.
/// Those tags are omitted here so a submitted body cannot become a player or
/// a frame. The app draws charts and video from their own fields.
String articleHtml(String markdown) {
  return md.markdownToHtml(
    _hardBreaks(markdown),
    blockSyntaxes: const [
      md.FencedCodeBlockSyntax(),
      md.TableSyntax(),
      md.EmptyBlockSyntax(),
      md.SetextHeaderSyntax(),
      md.HeaderSyntax(),
      md.CodeBlockSyntax(),
      md.BlockquoteSyntax(),
      md.HorizontalRuleSyntax(),
      md.UnorderedListWithCheckboxSyntax(),
      md.OrderedListWithCheckboxSyntax(),
      md.UnorderedListSyntax(),
      md.OrderedListSyntax(),
      md.LinkReferenceDefinitionSyntax(),
      md.FootnoteDefSyntax(),
      md.ParagraphSyntax(),
    ],
    inlineSyntaxes: [md.StrikethroughSyntax(), md.AutolinkExtensionSyntax()],
    extensionSet: md.ExtensionSet(const [], const []),
    withDefaultBlockSyntaxes: false,
    encodeHtml: true,
    enableTagfilter: true,
  );
}

List<ArticlePiece> articlePieces(String body) {
  final pieces = <ArticlePiece>[];
  final buffer = StringBuffer();
  var fence = false;

  void flush() {
    final text = buffer.toString();
    buffer.clear();
    if (text.trim().isEmpty) {
      return;
    }
    pieces.add(ArticleHtml(articleHtml(text)));
  }

  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    if (_fenceLine(trimmed)) {
      fence = !fence;
      buffer.writeln(line);
      continue;
    }
    if (!fence) {
      final match = _chartLine.firstMatch(trimmed);
      if (match != null) {
        flush();
        pieces.add(ArticleChartMark(int.parse(match.group(1)!)));
        continue;
      }
    }
    buffer.writeln(line);
  }
  flush();
  return pieces;
}

/// Drops a lone `[[chart:N]]` line. The same line inside a fence stays.
String shareBody(String body) {
  final out = <String>[];
  var fence = false;
  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    if (_fenceLine(trimmed)) {
      fence = !fence;
      out.add(line);
      continue;
    }
    if (!fence && _chartLine.hasMatch(trimmed)) {
      continue;
    }
    out.add(line);
  }
  return out.join('\n');
}

const _videoSuffixes = ['.mp4', '.mov', '.m4v', '.webm', '.m3u8'];

/// A direct file URL. The query is ignored. A watch page is not direct.
bool isDirectVideo(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  final path = uri.path.toLowerCase();
  for (final suffix in _videoSuffixes) {
    if (path.endsWith(suffix)) {
      return true;
    }
  }
  return false;
}

String _hex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

Map<String, String>? _articleStyles(dynamic element, bool wide, double size) {
  final name = element.localName as String?;
  final heading = switch (name) {
    'h1' => wide ? 28.0 : 24.0,
    'h2' => wide ? 22.0 : 20.0,
    'h3' => wide ? 18.0 : 17.0,
    'h4' => size,
    'h5' => size - 1,
    'h6' => size - 2,
    _ => null,
  };
  if (heading != null) {
    return {
      'color': _hex(Red.fg),
      'font-size': '${heading}px',
      'font-weight': '500',
      'line-height': '1.3',
      'margin': '0 0 12px 0',
    };
  }
  return switch (name) {
    'p' => {'margin': '0 0 16px 0'},
    'ul' || 'ol' => {'margin': '0 0 16px 0', 'padding-left': '24px'},
    'blockquote' => {
      'border-left': '2px solid ${_hex(Red.lineStrong)}',
      'color': _hex(Red.muted),
      'margin': '0 0 16px 0',
      'padding': '0 0 0 14px',
    },
    'pre' => {
      'background-color': _hex(Red.surfaceWarm),
      'border': '1px solid ${_hex(Red.border)}',
      'border-radius': '4px',
      'margin': '0 0 16px 0',
      'padding': '12px',
      'white-space': 'pre',
    },
    'code' => {
      'background-color': _hex(Red.surfaceWarm),
      'font-family': 'monospace',
      'font-size': '${size * 0.88}px',
    },
    'a' => {'color': _hex(Red.fg), 'text-decoration': 'underline'},
    'strong' => {'color': _hex(Red.fg), 'font-weight': '600'},
    'table' || 'td' || 'th' => {
      'border': '1px solid ${_hex(Red.border)}',
      if (name == 'th') 'font-weight': '600',
      if (name != 'table') 'padding': '8px 10px',
    },
    _ => null,
  };
}

class ArticleFigure extends StatelessWidget {
  const ArticleFigure({
    super.key,
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

class ArticleHtmlView extends StatelessWidget {
  const ArticleHtmlView({
    super.key,
    required this.html,
    required this.wide,
    required this.imageMaxHeight,
    required this.imageHeadersFor,
    required this.onOpen,
  });

  final String html;
  final bool wide;
  final double imageMaxHeight;
  final Map<String, String> Function(String url) imageHeadersFor;
  final Future<void> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final size = wide ? 17.0 : 16.0;
    return HtmlWidget(
      html,
      buildAsync: false,
      textStyle: Red.text(size: size, height: 1.8, color: Red.fg2),
      customStylesBuilder: (element) => _articleStyles(element, wide, size),
      customWidgetBuilder: (element) {
        final name = element.localName;
        if (name == 'hr') {
          return ColoredBox(
            color: Red.border,
            child: const SizedBox(height: 1, width: double.infinity),
          );
        }
        if (name == 'script' || name == 'video' || name == 'iframe') {
          final text = element.text.trim();
          if (text.isEmpty) {
            return const SizedBox.shrink();
          }
          return Text(
            text,
            style: Red.text(size: size, height: 1.8, color: Red.fg2),
          );
        }
        if (name != 'img') {
          return null;
        }
        final src = element.attributes['src'] ?? '';
        final uri = Uri.tryParse(src);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ArticleFigure(
            url: src,
            headers: imageHeadersFor(src),
            maxHeight: imageMaxHeight,
          ),
        );
      },
      onTapUrl: (url) async {
        await onOpen(url);
        return true;
      },
    );
  }
}

/// Body HTML, then each placed chart, then charts the body did not place.
/// The same index is drawn once. An index past the list is skipped.
List<Widget> articleSlots({
  required List<ArticlePiece> pieces,
  required List<CardChart> charts,
  required bool wide,
  required double imageMaxHeight,
  required Map<String, String> Function(String url) imageHeadersFor,
  required Future<void> Function(String url) onOpen,
}) {
  final used = <int>{};
  final children = <Widget>[];

  void add(Widget child) {
    if (children.isNotEmpty) {
      children.add(const SizedBox(height: 12));
    }
    children.add(child);
  }

  void addChart(int index) {
    if (index < 0 || index >= charts.length || !used.add(index)) {
      return;
    }
    add(ArticleChart(chart: charts[index]));
  }

  for (final piece in pieces) {
    switch (piece) {
      case ArticleHtml(:final html):
        add(
          ArticleHtmlView(
            html: html,
            wide: wide,
            imageMaxHeight: imageMaxHeight,
            imageHeadersFor: imageHeadersFor,
            onOpen: onOpen,
          ),
        );
      case ArticleChartMark(:final index):
        addChart(index);
    }
  }
  for (var i = 0; i < charts.length; i++) {
    addChart(i);
  }
  return children;
}

class ArticleChart extends StatelessWidget {
  const ArticleChart({super.key, required this.chart});

  final CardChart chart;

  static const plotHeight = 220.0;

  @override
  Widget build(BuildContext context) {
    if (chart.labels.isEmpty || chart.series.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = [Red.fg, Red.followFg, Red.green, Red.likeFg];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chart.title.trim().isNotEmpty) ...[
            Text(
              chart.title,
              style: Red.text(size: 13, height: 1.3, weight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(height: plotHeight, child: _plot(colors)),
          _legend(colors),
        ],
      ),
    );
  }

  Widget _plot(List<Color> colors) {
    return switch (chart.type) {
      'line' => _line(colors),
      'pie' => _pie(colors),
      _ => _bars(colors),
    };
  }

  (double, double) _bounds(Iterable<double> values) {
    var minY = 0.0;
    var maxY = 0.0;
    for (final value in values) {
      if (value < minY) {
        minY = value;
      }
      if (value > maxY) {
        maxY = value;
      }
    }
    if (minY == maxY) {
      maxY = minY + 1;
    }
    final pad = (maxY - minY) * 0.08;
    if (maxY > 0) {
      maxY += pad;
    }
    if (minY < 0) {
      minY -= pad;
    }
    return (minY, maxY);
  }

  FlTitlesData _titles({required bool left, required bool bottom}) {
    final style = Red.text(size: 10, height: 1.2, color: Red.muted);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: left,
          reservedSize: 36,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            space: 4,
            child: Text(_tick(value), style: style),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: bottom,
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: (value, meta) {
            final index = value.round();
            if ((value - index).abs() > 0.01 ||
                index < 0 ||
                index >= chart.labels.length) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              space: 4,
              child: Text(
                chart.labels[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bars(List<Color> colors) {
    final values = [for (final series in chart.series) ...series.data];
    final (minY, maxY) = _bounds(values);
    return BarChart(
      BarChartData(
        minY: minY,
        maxY: maxY,
        alignment: BarChartAlignment.spaceEvenly,
        barTouchData: const BarTouchData(enabled: false),
        gridData: _grid(),
        borderData: _border(),
        titlesData: _titles(left: true, bottom: true),
        barGroups: [
          for (var i = 0; i < chart.labels.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                for (var s = 0; s < chart.series.length; s++)
                  if (i < chart.series[s].data.length)
                    BarChartRodData(
                      toY: chart.series[s].data[i],
                      color: colors[s % colors.length],
                      width: chart.series.length > 2 ? 6 : 10,
                      borderRadius: BorderRadius.zero,
                    ),
              ],
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  Widget _line(List<Color> colors) {
    final values = [for (final series in chart.series) ...series.data];
    final (minY, maxY) = _bounds(values);
    final last = (chart.labels.length - 1).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: last <= 0 ? 1 : last,
        minY: minY,
        maxY: maxY,
        lineTouchData: const LineTouchData(enabled: false),
        gridData: _grid(),
        borderData: _border(),
        titlesData: _titles(left: true, bottom: true),
        lineBarsData: [
          for (var s = 0; s < chart.series.length; s++)
            LineChartBarData(
              spots: [
                for (var i = 0; i < chart.labels.length; i++)
                  if (i < chart.series[s].data.length)
                    FlSpot(i.toDouble(), chart.series[s].data[i]),
              ],
              color: colors[s % colors.length],
              barWidth: 2,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: false),
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  Widget _pie(List<Color> colors) {
    final raw = chart.series.first.data;
    final values = <double>[
      for (var i = 0; i < chart.labels.length && i < raw.length; i++)
        raw[i] < 0 ? 0 : raw[i],
    ];
    final sum = values.fold<double>(0, (total, value) => total + value);
    if (sum == 0) {
      return const SizedBox.expand();
    }
    return PieChart(
      PieChartData(
        centerSpaceRadius: 0,
        sectionsSpace: 2,
        startDegreeOffset: -90,
        pieTouchData: PieTouchData(enabled: false),
        sections: [
          for (var i = 0; i < values.length; i++)
            PieChartSectionData(
              value: values[i],
              color: colors[i % colors.length],
              radius: 78,
              showTitle: false,
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  FlGridData _grid() {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: Red.border, strokeWidth: 1),
    );
  }

  FlBorderData _border() {
    return FlBorderData(
      show: true,
      border: Border(
        left: BorderSide(color: Red.border),
        bottom: BorderSide(color: Red.border),
      ),
    );
  }

  Widget _legend(List<Color> colors) {
    final entries = <(Color, String)>[];
    if (chart.type == 'pie') {
      final name = chart.series.first.name.trim();
      if (name.isNotEmpty) {
        entries.add((colors.first, name));
      }
      for (var i = 0; i < chart.labels.length; i++) {
        entries.add((colors[i % colors.length], chart.labels[i]));
      }
    } else {
      for (var i = 0; i < chart.series.length; i++) {
        final name = chart.series[i].name.trim();
        if (name.isNotEmpty) {
          entries.add((colors[i % colors.length], name));
        }
      }
    }
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final (color, label) in entries)
            _Swatch(color: color, label: label),
        ],
      ),
    );
  }

  String _tick(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Red.text(size: 11, height: 1.2, color: Red.fg2)),
      ],
    );
  }
}

/// A direct file plays here. The controller is created on the first tap.
/// A watch-page URL, or a file that fails to open, is a link.
class ArticleVideo extends StatefulWidget {
  const ArticleVideo({
    super.key,
    required this.url,
    required this.index,
    required this.active,
    required this.onActivate,
    required this.onOpen,
  });

  final String url;
  final int index;
  final bool active;
  final VoidCallback onActivate;
  final Future<void> Function(String url) onOpen;

  @override
  State<ArticleVideo> createState() => _ArticleVideoState();
}

class _ArticleVideoState extends State<ArticleVideo> {
  VideoPlayerController? _controller;
  var _starting = false;
  var _failed = false;
  var _gone = false;

  @override
  void didUpdateWidget(ArticleVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (!widget.active && controller.value.isPlaying) {
      controller.pause();
    }
  }

  @override
  void dispose() {
    _gone = true;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    widget.onActivate();
    final existing = _controller;
    if (existing != null) {
      if (existing.value.isInitialized && !existing.value.isPlaying) {
        await existing.play();
      }
      return;
    }
    if (_starting || _failed) {
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _starting = true;
    if (mounted) {
      setState(() {});
    }
    try {
      await controller.initialize();
      if (_gone) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _starting = false;
      });
      if (widget.active) {
        await controller.play();
      }
    } catch (_) {
      await controller.dispose();
      if (_gone) {
        return;
      }
      setState(() {
        _failed = true;
        _starting = false;
        _controller = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDirectVideo(widget.url) || _failed) {
      return _link(ValueKey('article-video-link-${widget.index}'));
    }
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return KeyedSubtree(
      key: ValueKey('article-video-${widget.index}'),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(color: Red.surfaceWarm),
            child: ready ? _player(controller) : _playFace(),
          ),
        ),
      ),
    );
  }

  Widget _player(VideoPlayerController controller) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final playing = controller.value.isPlaying;
        return Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            if (!playing)
              _playButton()
            else
              Positioned.fill(
                child: GestureDetector(
                  onTap: controller.pause,
                  behavior: HitTestBehavior.translucent,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _playFace() {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_starting)
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2, color: Red.fg2),
          )
        else
          _playButton(),
      ],
    );
  }

  Widget _playButton() {
    return IconButton(
      onPressed: _start,
      icon: Icon(Icons.play_arrow, size: 36, color: Red.fg),
      style: IconButton.styleFrom(
        backgroundColor: Red.surface,
        foregroundColor: Red.fg,
        fixedSize: const Size(64, 64),
      ),
    );
  }

  Widget _link(Key key) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: key,
        onPressed: () => widget.onOpen(widget.url),
        style: TextButton.styleFrom(
          foregroundColor: Red.fg,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
        ),
        child: Text(
          widget.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Red.text(
            size: 14,
            height: 1.4,
          ).copyWith(decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}
