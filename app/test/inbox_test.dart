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

const _user = 'ada';

Inbox _open(SharedPreferences prefs, [String userId = _user]) {
  return Inbox(prefs, userId: userId)..load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'after reading drops the card and a later poll does not restore it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final inbox = _open(prefs);
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
      final inbox = _open(prefs);
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

      final again = _open(prefs);
      expect(again.cards.map((item) => item.id), ['recent']);
      expect(again.cacheMode, '7d');
    },
  );

  test('load drops cards outside the cache window', () async {
    final now = DateTime.now().toUtc();
    SharedPreferences.setMockInitialValues({
      Inbox.cacheKey: '7d',
      Inbox.storageKey(_user): jsonEncode({
        'cards': [
          _card('recent', now.subtract(const Duration(days: 2))).toJson(),
          _card('old', now.subtract(const Duration(days: 8))).toJson(),
        ],
        'read': ['recent', 'old'],
        'gone': <String>[],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final inbox = _open(prefs);

    expect(inbox.cards.map((item) => item.id), ['recent']);
    expect(inbox.read, {'recent'});

    final again = _open(prefs);
    expect(again.cards.map((item) => item.id), ['recent']);
    expect(again.read, {'recent'});
  });

  test('one account cache does not open for another account', () async {
    SharedPreferences.setMockInitialValues({
      Inbox.legacyKey: jsonEncode({
        'cards': [_card('previous', DateTime.now()).toJson()],
        'read': <String>[],
        'gone': <String>[],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final ada = _open(prefs);
    ada.merge([_card('ada-card', DateTime.now())]);

    final bao = _open(prefs, 'bao');
    expect(bao.cards, isEmpty);

    bao.merge([_card('bao-card', DateTime.now())]);
    expect(_open(prefs).cards.map((item) => item.id), ['ada-card']);
    expect(_open(prefs, 'bao').cards.map((item) => item.id), ['bao-card']);
  });

  test('one day cache drops cards older than a day', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final inbox = _open(prefs);
    inbox.setCacheMode('1d');
    inbox.merge([
      _card('fresh', DateTime.now().subtract(const Duration(hours: 2))),
      _card('stale', DateTime.now().subtract(const Duration(hours: 25))),
    ]);

    expect(inbox.cards.map((item) => item.id), ['fresh']);
  });
}
