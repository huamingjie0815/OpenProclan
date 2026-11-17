import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:proclan_app/account_api.dart';
import 'package:proclan_app/community_api.dart';
import 'package:proclan_app/community_page.dart';
import 'package:proclan_app/feed_client.dart';
import 'package:proclan_app/main.dart';

import 'widget_test.dart' show FakeFeedClient;

void main() {
  testWidgets('drawer opens the community boards', (tester) async {
    final community = _Community(
      likes: [
        _bot(name: '日报', likes: 9, follows: 4, rank: 1),
        _bot(name: '周报', ownerId: 'u2', likes: 7, follows: 6, rank: 2),
      ],
      followsBoard: [
        _bot(name: '周报', ownerId: 'u2', likes: 7, follows: 6, rank: 1),
        _bot(name: '日报', likes: 9, follows: 4, rank: 2),
      ],
    );
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: FakeFeedClient(const []),
        pollEvery: null,
        community: community,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer-community')), findsOneWidget);

    await tester.tap(find.byKey(const Key('drawer-community')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('community-search')), findsOneWidget);
    expect(find.text('点赞榜'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    await tester.tap(find.byKey(const Key('community-follows')));
    await tester.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(community.lookups, 0);
  });

  testWidgets('search lists matches and does not open a bot', (tester) async {
    final community = _Community(
      likes: [_bot(name: '日报', likes: 3, rank: 1)],
      found: [
        _bot(name: '晚报', code: 'ABCD2345', listed: false, rank: null),
      ],
      details: {
        '晚报': _bot(name: '晚报', code: 'ABCD2345', listed: false),
      },
    );
    await _pump(tester, community);

    await tester.enterText(find.byKey(const Key('community-search')), ' abcd2345 ');
    await tester.pumpAndSettle();

    expect(community.searched, 'abcd2345');
    expect(community.lookups, 0);
    expect(find.byKey(const Key('community-search')), findsOneWidget);
    expect(find.byKey(const Key('community-row-u1-晚报')), findsOneWidget);
    expect(find.textContaining('已下线'), findsOneWidget);
    expect(find.byKey(const Key('community-follow')), findsNothing);

    await tester.tap(find.byKey(const Key('community-row-u1-晚报')));
    await tester.pumpAndSettle();
    expect(community.lookups, 1);
    expect(find.byKey(const Key('community-offline')), findsOneWidget);
    expect(_pressed(tester, 'community-follow'), isNull);
    expect(_pressed(tester, 'community-like'), isNull);
    expect(_pressed(tester, 'community-dislike'), isNull);
  });

  testWidgets('guest actions follow the listing and an original has no delete', (
    tester,
  ) async {
    final card = _card();
    final community = _Community(
      likes: [
        _bot(name: '日报', likes: 4, rank: 1),
        _bot(name: '停更', rank: 2),
        _bot(name: '仍关注', rank: 3),
      ],
      details: {
        '日报': _bot(name: '日报', likes: 4, card: card),
        '停更': _bot(name: '停更', listed: false),
        '仍关注': _bot(name: '仍关注', listed: false, following: true),
      },
    );
    await _pump(tester, community, feed: FakeFeedClient(const []));

    await tester.tap(find.byKey(const Key('community-row-u1-日报')));
    await tester.pumpAndSettle();
    expect(_pressed(tester, 'community-follow'), isNotNull);
    expect(_pressed(tester, 'community-like'), isNotNull);
    expect(find.text('关注'), findsWidgets);
    expect(find.text('已关注'), findsNothing);

    await tester.tap(find.byKey(const Key('community-card-c1')));
    await tester.pumpAndSettle();
    expect(find.text('正文'), findsOneWidget);
    expect(find.text('删除卡片'), findsNothing);
    expect(find.text('标记为未读'), findsNothing);
    expect(find.text('日报 · 林间'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community-back')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('community-row-u1-停更')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('community-offline')), findsOneWidget);
    expect(_pressed(tester, 'community-follow'), isNull);
    expect(_pressed(tester, 'community-like'), isNull);
    expect(_pressed(tester, 'community-dislike'), isNull);

    await tester.tap(find.byKey(const Key('community-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community-row-u1-仍关注')));
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);
    expect(_pressed(tester, 'community-follow'), isNotNull);
    expect(_pressed(tester, 'community-like'), isNull);
    expect(_pressed(tester, 'community-dislike'), isNull);
  });

  testWidgets('following keeps groups while searching and copies stay deletable', (
    tester,
  ) async {
    final community = _Community(
      groups: [
        CommunityGroup(
          ownerId: 'u2',
          ownerName: '林间',
          bots: const [
            FollowedBot(name: '日报', listed: false, botDesc: ''),
            FollowedBot(name: '晚报', listed: true, botDesc: ''),
          ],
        ),
      ],
      copyPage: CommunityCopies(
        ownerId: 'u2',
        ownerName: '林间',
        name: '日报',
        listed: false,
        botDesc: '',
        cards: [_card()],
      ),
    );
    await _pump(tester, community, feed: FakeFeedClient(const []));
    await tester.tap(find.byKey(const Key('community-following')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('community-user-u2')), findsOneWidget);
    expect(find.text('已下线'), findsOneWidget);
    expect(find.byKey(const Key('followed-u2-晚报')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('community-search')), '晚报');
    await tester.pumpAndSettle();
    expect(community.searched, isNull);
    expect(find.byKey(const Key('followed-u2-日报')), findsOneWidget);

    await tester.tap(find.byKey(const Key('followed-u2-日报')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('community-offline')), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-card-c1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('删除卡片'));
    expect(find.text('删除卡片'), findsOneWidget);
    expect(find.text('标记为未读'), findsOneWidget);
  });

  testWidgets('owner share switch confirms only when turning off', (tester) async {
    final httpClient = _ShareAccount();
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: FakeFeedClient(const []),
        pollEvery: null,
        account: AccountClient(
          baseUrl: 'http://127.0.0.1:9',
          httpClient: httpClient,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-bots')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bot-日报')));
    await tester.pumpAndSettle();

    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.text('点赞 3 · 差评 1 · 关注 2'), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const Key('share-community'))).value, isFalse);

    await tester.ensureVisible(find.byKey(const Key('share-community')));
    await tester.tap(find.byKey(const Key('share-community')));
    await tester.pumpAndSettle();
    expect(find.text('停止分享？'), findsNothing);
    expect(httpClient.calls, ['share']);
    expect(tester.widget<Switch>(find.byKey(const Key('share-community'))).value, isTrue);

    await tester.tap(find.byKey(const Key('share-community')));
    await tester.pumpAndSettle();
    expect(find.text('停止分享？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(httpClient.calls, ['share']);
    expect(tester.widget<Switch>(find.byKey(const Key('share-community'))).value, isTrue);

    await tester.tap(find.byKey(const Key('share-community')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停止分享'));
    await tester.pumpAndSettle();
    expect(httpClient.calls, ['share', 'unshare']);
    expect(tester.widget<Switch>(find.byKey(const Key('share-community'))).value, isFalse);
    expect(find.byKey(const Key('community-code')), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);
  });

  testWidgets('a copied card names the bot and its owner', (tester) async {
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: FakeFeedClient([
          _card(createdAt: DateTime.now().toIso8601String()),
        ]),
        pollEvery: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('日报 · 林间'), findsOneWidget);
    expect(find.text('HACKER NEWS'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  CommunityClient client, {
  FeedClient? feed,
}) async {
  await tester.pumpWidget(
    ProclanShell(
      locale: const Locale('zh'),
      home: CommunityPage(client: client, feed: feed),
    ),
  );
  await tester.pumpAndSettle();
}

VoidCallback? _pressed(WidgetTester tester, String key) {
  return tester
      .widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(OutlinedButton),
        ),
      )
      .onPressed;
}

CommunityBot _bot({
  String ownerId = 'u1',
  String ownerName = '林间',
  required String name,
  String code = '',
  bool listed = true,
  int likes = 0,
  int dislikes = 0,
  int follows = 0,
  int? rank = 1,
  bool following = false,
  int vote = 0,
  FeedCard? card,
}) {
  return CommunityBot(
    ownerId: ownerId,
    ownerName: ownerName,
    name: name,
    botDesc: '盯着模型价格。',
    code: code,
    listed: listed,
    likes: likes,
    dislikes: dislikes,
    follows: follows,
    rank: rank,
    following: following,
    card: card,
  );
}

FeedCard _card({
  String title = '模型降价',
  String createdAt = '2026-10-27T02:00:00Z',
}) {
  return FeedCard(
    id: 'c1',
    title: title,
    summary: '价格下调',
    body: '正文',
    category: '科技',
    tags: const ['AI'],
    images: const [],
    source: 'Hacker News',
    sourceUrls: const ['https://1.1.1.1/story'],
    createdBot: '日报',
    read: false,
    createdAt: createdAt,
    sourceUsername: '林间',
  );
}

class _Community implements CommunityClient {
  _Community({
    this.likes = const [],
    this.followsBoard = const [],
    this.found = const [],
    this.details = const {},
    this.groups = const [],
    this.copyPage,
  });

  final List<CommunityBot> likes;
  final List<CommunityBot> followsBoard;
  final List<CommunityBot> found;
  final Map<String, CommunityBot> details;
  final List<CommunityGroup> groups;
  final CommunityCopies? copyPage;
  String? searched;
  var lookups = 0;

  @override
  Future<List<CommunityBot>> board(String kind) async {
    return kind == 'follows' ? followsBoard : likes;
  }

  @override
  Future<List<CommunityBot>> search(String query) async {
    searched = query;
    return found;
  }

  @override
  Future<CommunityBot> bot({required String ownerId, required String name}) async {
    lookups += 1;
    return details[name]!;
  }

  @override
  Future<List<CommunityGroup>> following() async => groups;

  @override
  Future<CommunityCopies> copies({
    required String ownerId,
    required String name,
  }) async {
    return copyPage!;
  }

  @override
  Future<void> follow({required String ownerId, required String name}) async {}

  @override
  Future<void> unfollow({required String ownerId, required String name}) async {}

  @override
  Future<void> vote({
    required String ownerId,
    required String name,
    required int vote,
  }) async {}
}

class _ShareAccount extends http.BaseClient {
  var listed = false;
  final calls = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/v1/me') {
      return _json('{"id":"u","username":"林间"}');
    }
    if (request.method == 'GET' && path == '/v1/me/bot-token') {
      return _json('{"token":"bot-secret"}');
    }
    if (request.method == 'GET' && path == '/v1/bots') {
      return _json('{"bots":[{"name":"日报"}]}');
    }
    if (request.method == 'POST' && path == '/v1/community/share') {
      calls.add('share');
      listed = true;
      return _json('{}');
    }
    if (request.method == 'DELETE' && path == '/v1/community/share') {
      calls.add('unshare');
      listed = false;
      return _json('{}');
    }
    if (request.method == 'GET' && path == '/v1/bots/profile') {
      return _json(
        '{"name":"日报","first_seen":"2026-10-27T01:02:03Z","bot_desc":"盯着模型价格。","cards":[],'
        '"community":{"listed":$listed,"code":"ABCD2345","likes":3,"dislikes":1,"follows":2}}',
      );
    }
    return http.StreamedResponse(const Stream.empty(), 404);
  }

  http.StreamedResponse _json(String body) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
