import 'package:flutter_test/flutter_test.dart';
import 'package:proclan_app/article.dart';
import 'package:proclan_app/feed_client.dart';

void main() {
  test('tilde and longer fences keep chart markers and code intact', () {
    for (final fence in ['~~~', '````']) {
      final body = '$fence\n```\n[[chart:0]]\na\nb\n$fence\n[[chart:1]]';
      final pieces = articlePieces(body);
      expect(pieces, hasLength(2));
      expect((pieces.first as ArticleHtml).html, contains('[[chart:0]]'));
      expect((pieces.first as ArticleHtml).html, isNot(contains('a  \nb')));
      expect((pieces.last as ArticleChartMark).index, 1);
      expect(shareBody(body), '$fence\n```\n[[chart:0]]\na\nb\n$fence');
    }
  });

  test('an oversized chart index stays text instead of throwing', () {
    final body = '[[chart:${'9' * 100}]]';
    expect(articlePieces(body).single, isA<ArticleHtml>());
  });

  test('a chart line splits the body and a fenced line stays text', () {
    final pieces = articlePieces('''
甲

[[chart:0]]

```
[[chart:1]]
```

乙
''');

    expect(pieces, hasLength(3));
    expect(pieces[0], isA<ArticleHtml>());
    expect((pieces[0] as ArticleHtml).html, contains('甲'));
    expect(pieces[1], isA<ArticleChartMark>());
    expect((pieces[1] as ArticleChartMark).index, 0);
    final fenced = (pieces[2] as ArticleHtml).html;
    expect(fenced, contains('[[chart:1]]'));
    expect(fenced, contains('乙'));
  });

  test('a plain newline becomes a break and raw html stays text', () {
    final html = articleHtml('普通段\n换行仍在。\n\n<script>alert(1)</script>');
    expect(html, contains('<br'));
    expect(html, contains('普通段'));
    expect(html, contains('换行仍在。'));
    expect(html, isNot(contains('<script')));
    expect(html, contains('alert(1)'));
  });

  test('share body drops a lone chart line and keeps a fenced one', () {
    expect(
      shareBody('甲\n[[chart:0]]\n```\n[[chart:1]]\n```\n乙'),
      '甲\n```\n[[chart:1]]\n```\n乙',
    );
  });

  test('a direct video is a file suffix and a watch page is not', () {
    expect(isDirectVideo('https://1.1.1.1/a.mp4'), isTrue);
    expect(isDirectVideo('https://1.1.1.1/a.MP4?x=1'), isTrue);
    expect(isDirectVideo('https://1.1.1.1/a.mov'), isTrue);
    expect(isDirectVideo('https://1.1.1.1/a.m4v'), isTrue);
    expect(isDirectVideo('https://1.1.1.1/a.webm'), isTrue);
    expect(isDirectVideo('https://1.1.1.1/a.m3u8'), isTrue);
    expect(isDirectVideo('https://www.youtube.com/watch?v=abc'), isFalse);
    expect(isDirectVideo('https://1.1.1.1/watch?file=a.mp4'), isFalse);
    expect(isDirectVideo('file:///tmp/a.mp4'), isFalse);
  });

  test('old cache drops a missing or bad chart and keeps a valid one', () {
    final stored = FeedCard.fromJson(const {'id': 'old', 'title': '旧'});
    expect(stored.charts, isEmpty);
    expect(stored.videoUrls, isEmpty);

    final card = FeedCard.fromJson({
      'id': 'mixed',
      'charts': [
        {'type': 'scatter'},
        {
          'type': 'pie',
          'labels': ['甲', '乙'],
          'series': [
            {
              'name': '一组',
              'data': [1, 2],
            },
            {
              'name': '二组',
              'data': [3, 4],
            },
          ],
        },
        {
          'type': 'bar',
          'labels': ['甲'],
          'series': [
            {
              'name': '产量',
              'data': [double.nan],
            },
          ],
        },
        {
          'type': 'bar',
          'title': '本周',
          'labels': ['甲', '乙'],
          'series': [
            {
              'name': '产量',
              'data': [1, 2],
            },
          ],
        },
      ],
    });
    expect(card.charts, hasLength(1));
    expect(card.charts.single.title, '本周');
    expect(card.charts.single.series.single.data, [1, 2]);
  });
}
