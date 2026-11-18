import 'package:flutter_test/flutter_test.dart';
import 'package:proclan_app/detail_page.dart';
import 'package:proclan_app/feed_client.dart';

FeedCard _card({
  String title = '',
  String summary = '',
  String body = '',
  String source = '',
  List<String> sourceUrls = const [],
  List<String> images = const [],
  List<String> videoUrls = const [],
}) {
  return FeedCard(
    id: 's',
    title: title,
    summary: summary,
    body: body,
    category: '科技',
    tags: const [],
    images: images,
    source: source,
    sourceUrls: sourceUrls,
    videoUrls: videoUrls,
    createdBot: '北风',
    read: false,
    createdAt: '2026-11-16T00:00:00Z',
  );
}

void main() {
  test('share text keeps the submitted fields and drops empty ones', () {
    expect(
      cardShareText(
        _card(
          title: ' 标题 ',
          summary: '摘要',
          body: '正文\n\n第二段',
          source: 'Hacker News',
          sourceUrls: const [
            ' https://example.com/a ',
            '',
            'https://example.com/b',
          ],
          images: const ['http://test/media/keep.jpg'],
        ),
      ),
      '标题\n\n'
      '摘要\n\n'
      '正文\n\n第二段\n\n'
      'Hacker News\n\n'
      'https://example.com/a\n'
      'https://example.com/b',
    );
  });

  test('share text skips missing sections', () {
    expect(
      cardShareText(_card(title: '只有标题', body: '  ', sourceUrls: const ['  '])),
      '只有标题',
    );
  });

  test('share text is empty when the card has nothing to send', () {
    expect(cardShareText(_card(title: ' ')), '');
  });

  test('share text drops a lone chart line and appends video urls', () {
    expect(
      cardShareText(
        _card(
          title: '标题',
          body: '正文\n\n[[chart:0]]\n\n```\n[[chart:1]]\n```',
          source: 'Hacker News',
          sourceUrls: const ['https://example.com/a'],
          videoUrls: const ['https://1.1.1.1/a.mp4', ' https://youtu.be/x '],
        ),
      ),
      '标题\n\n'
      '正文\n\n\n```\n[[chart:1]]\n```\n\n'
      'Hacker News\n\n'
      'https://example.com/a\n\n'
      'https://1.1.1.1/a.mp4\n'
      'https://youtu.be/x',
    );
  });
}
