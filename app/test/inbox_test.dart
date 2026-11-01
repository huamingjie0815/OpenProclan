import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proclan_app/feed_client.dart';
import 'package:proclan_app/inbox.dart';

FeedCard _card(String id, DateTime created) {
  return FeedCard(
    id: id,
    title: id,
    summary: '',
    body: '',
    category: '科技',
    tags: const [],
    images: const [],
    source: '',
    sourceUrls: const [],
    createdBot: '北风',
    read: false,
    createdAt: created.toUtc().toIso8601String(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'after reading drops the card and a later poll does not restore it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final inbox = Inbox(prefs)..load();
      inbox.setCacheMode('after_read');
      final card = _card('a', DateTime.now());
      inbox.merge([card]);
      inbox.markRead('a');

      expect(inbox.cards, isEmpty);

      inbox.merge([card]);
      expect(inbox.cards, isEmpty);
      expect(inbox.gone, contains('a'));

      inbox.markUnread(card);
      expect(inbox.cards.map((item) => item.id), ['a']);
      expect(inbox.read, isEmpty);
    },
  );

  test(
    'seven day cache keeps a local card the server no longer returns',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final inbox = Inbox(prefs)..load();
      final recent = _card(
        'recent',
        DateTime.now().subtract(const Duration(days: 2)),
      );
      final old = _card(
        'old',
        DateTime.now().subtract(const Duration(days: 8)),
      );
      inbox.merge([recent, old]);

      expect(inbox.cards.map((item) => item.id), ['recent']);

      inbox.merge(const []);
      expect(inbox.cards.map((item) => item.id), ['recent']);

      final again = Inbox(prefs)..load();
      expect(again.cards.map((item) => item.id), ['recent']);
      expect(again.cacheMode, '7d');
    },
  );

  test('load drops cards outside the cache window', () async {
    final now = DateTime.now().toUtc();
    SharedPreferences.setMockInitialValues({
      Inbox.cacheKey: '7d',
      Inbox.key: jsonEncode({
        'cards': [
          _card('recent', now.subtract(const Duration(days: 2))).toJson(),
          _card('old', now.subtract(const Duration(days: 8))).toJson(),
        ],
        'read': ['recent', 'old'],
        'gone': <String>[],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final inbox = Inbox(prefs)..load();

    expect(inbox.cards.map((item) => item.id), ['recent']);
    expect(inbox.read, {'recent'});

    final again = Inbox(prefs)..load();
    expect(again.cards.map((item) => item.id), ['recent']);
    expect(again.read, {'recent'});
  });

  test('one day cache drops cards older than a day', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final inbox = Inbox(prefs)..load();
    inbox.setCacheMode('1d');
    inbox.merge([
      _card('fresh', DateTime.now().subtract(const Duration(hours: 2))),
      _card('stale', DateTime.now().subtract(const Duration(hours: 25))),
    ]);

    expect(inbox.cards.map((item) => item.id), ['fresh']);
  });
}
