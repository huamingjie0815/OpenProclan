import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proclan_app/account_api.dart';
import 'package:proclan_app/detail_page.dart';
import 'package:proclan_app/feed_client.dart';
import 'package:proclan_app/l10n/app_localizations.dart';
import 'package:proclan_app/login_page.dart';
import 'package:proclan_app/main.dart';
import 'package:proclan_app/red.dart';

class FakeFeedClient implements FeedClient {
  FakeFeedClient(this.cards);
  final List<FeedCard> cards;
  final deleted = <String>[];

  @override
  Future<List<String>> categories() async => const [
    '科技',
    '财经',
    '国际',
    '社会',
    '生活',
    '其他',
  ];

  @override
  Future<List<FeedCard>> feed() async {
    return cards.where((card) => !deleted.contains(card.id)).toList();
  }

  @override
  Future<void> deleteCard(String id) async {
    deleted.add(id);
  }

  @override
  Map<String, String> imageHeadersFor(String url) {
    if (url.startsWith('http://test/media/')) {
      return const {'Authorization': 'Bearer session'};
    }
    return const {};
  }
}

TextStyle? _styleOf(WidgetTester tester, String snippet) {
  TextStyle? style;
  void walk(InlineSpan span) {
    if (span is! TextSpan) {
      return;
    }
    final text = span.text;
    if (text != null && text.contains(snippet)) {
      final next = span.style;
      if (next?.fontSize != null || style == null) {
        style = next;
      }
    }
    final children = span.children;
    if (children == null) {
      return;
    }
    for (final child in children) {
      walk(child);
    }
  }

  for (final widget in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    final span = widget.textSpan;
    if (span != null) {
      walk(span);
    }
  }
  return style;
}

FeedCard _card({
  required String id,
  required String title,
  required String category,
  List<String> images = const [],
  String body = '正文',
  String? createdAt,
}) {
  return FeedCard(
    id: id,
    title: title,
    summary: '摘要',
    body: body,
    category: category,
    tags: const ['AI'],
    images: images,
    source: 'Hacker News',
    sourceUrls: const ['https://1.1.1.1/story'],
    createdBot: '北风',
    read: false,
    createdAt: createdAt ?? DateTime.now().toIso8601String(),
  );
}

void main() {
  testWidgets('login page switches between sign in and register', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginPage(
          client: AccountClient(baseUrl: 'http://127.0.0.1:9'),
          onSignedIn: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录后，只看属于你的日报。'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('忘记密码'), findsNothing);
    expect(find.text('验证码'), findsNothing);

    await tester.ensureVisible(find.text('创建账号'));
    await tester.pump();
    await tester.tap(find.text('创建账号'));
    await tester.pumpAndSettle();
    expect(find.text('起一个用户名，建一份只属于你的日报。'), findsOneWidget);
    expect(find.text('这是登录名，不能和别人重复，之后可以修改。'), findsOneWidget);

    await tester.ensureVisible(find.text('返回登录'));
    await tester.pump();
    await tester.tap(find.text('返回登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录后，只看属于你的日报。'), findsOneWidget);
    expect(find.text('忘记密码'), findsNothing);
  });

  testWidgets('empty feed explains how content arrives', (tester) async {
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: FakeFeedClient(const []),
        pollEvery: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有卡片'), findsOneWidget);
    expect(find.text('有新内容时会出现在这里。'), findsOneWidget);
  });

  testWidgets('category filter and detail delete', (tester) async {
    final client = FakeFeedClient([
      _card(id: 'a', title: '模型降价', category: '科技'),
      _card(id: 'b', title: '汇率波动', category: '财经', body: '美元走弱'),
    ]);
    await tester.pumpWidget(
      ProclanApp(locale: const Locale('zh'), client: client, pollEvery: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('模型降价'), findsOneWidget);
    expect(find.text('汇率波动'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '财经'));
    await tester.pumpAndSettle();
    expect(find.text('汇率波动'), findsOneWidget);
    expect(find.text('模型降价'), findsNothing);

    await tester.tap(find.text('汇率波动'));
    await tester.pumpAndSettle();
    expect(find.text('美元走弱'), findsOneWidget);

    await tester.ensureVisible(find.text('删除卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(client.deleted, ['b']);
    expect(find.text('本栏还没有卡片'), findsOneWidget);
  });

  testWidgets(
    'feed thumb sits beside the title and the article image is above the summary',
    (tester) async {
      final client = FakeFeedClient([
        _card(
          id: 'c',
          title: '带图',
          category: '科技',
          images: const ['https://1.1.1.1/a.jpg'],
        ),
      ]);
      await tester.pumpWidget(
        ProclanApp(locale: const Locale('zh'), client: client, pollEvery: null),
      );
      await tester.pumpAndSettle();
      expect(find.text('摘要'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(
        tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .httpHeaders,
        isNull,
      );
      expect(
        tester.getTopLeft(find.byType(CachedNetworkImage)).dx,
        greaterThan(tester.getTopLeft(find.text('带图')).dx),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DetailPage(card: client.cards.first, client: client),
        ),
      );
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(
        tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .httpHeaders,
        isNull,
      );
      expect(
        tester.getTopLeft(find.byType(CachedNetworkImage)).dy,
        lessThan(tester.getTopLeft(find.text('摘要')).dy),
      );
      expect(
        tester.getTopLeft(find.text('摘要')).dy,
        lessThan(tester.getTopLeft(find.text('正文')).dy),
      );
    },
  );

  testWidgets(
    'a stored media file sends the session and a remote url does not',
    (tester) async {
      const media = 'http://test/media/keep.jpg';
      final client = FakeFeedClient([
        _card(
          id: 'm',
          title: '旧图',
          category: '科技',
          images: const [media],
          body: '![图](https://1.1.1.1/a.jpg)',
        ),
      ]);
      await tester.pumpWidget(
        ProclanApp(locale: const Locale('zh'), client: client, pollEvery: null),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .httpHeaders,
        {'Authorization': 'Bearer session'},
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DetailPage(card: client.cards.first, client: client),
        ),
      );
      await tester.pump();
      final images = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .toList();
      expect(images.map((image) => image.imageUrl), [
        media,
        'https://1.1.1.1/a.jpg',
      ]);
      expect(images.map((image) => image.httpHeaders), [
        {'Authorization': 'Bearer session'},
        null,
      ]);
    },
  );

  testWidgets('detail body renders markdown', (tester) async {
    final client = FakeFeedClient([
      _card(
        id: 'md',
        title: '标记',
        category: '科技',
        body: '''
## 小节

普通段
换行仍在。

**重点** 与 [这篇报道](https://example.com/a)

- 第一
- 第二
''',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DetailPage(card: client.cards.first, client: client),
      ),
    );
    await tester.pump();

    expect(find.text('小节'), findsOneWidget);
    expect(find.textContaining('普通段\n换行仍在。'), findsOneWidget);
    expect(find.textContaining('重点'), findsOneWidget);
    expect(find.textContaining('这篇报道'), findsOneWidget);
    expect(find.textContaining('第一'), findsOneWidget);
    expect(find.textContaining('第二'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('##'), findsNothing);
    expect(_styleOf(tester, '小节')?.fontSize, 22);
    expect(_styleOf(tester, '小节')?.fontWeight, FontWeight.w500);
    expect(_styleOf(tester, '普通段')?.fontFamily, 'PingFang SC');
    expect(_styleOf(tester, '普通段')?.fontSize, 17);
    expect(_styleOf(tester, '普通段')?.color, Red.fg2);
    expect(_styleOf(tester, '重点')?.fontWeight, FontWeight.w600);
  });

  testWidgets('opening a card marks it read', (tester) async {
    final client = FakeFeedClient([
      _card(id: 'a', title: '模型降价', category: '科技'),
    ]);
    await tester.pumpWidget(
      ProclanApp(locale: const Locale('zh'), client: client, pollEvery: null),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 条未读'), findsOneWidget);

    await tester.tap(find.text('模型降价'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回信息流'));
    await tester.pumpAndSettle();

    expect(find.text('已读'), findsOneWidget);
    expect(find.text('全部已读'), findsOneWidget);

    await tester.tap(find.text('模型降价'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('标记为未读'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标记为未读'));
    await tester.pumpAndSettle();
    expect(find.text('1 条未读'), findsOneWidget);
    expect(find.text('已读'), findsNothing);
  });

  testWidgets('theme uses the editorial palette', (tester) async {
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: FakeFeedClient(const []),
        pollEvery: null,
      ),
    );
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.text('还没有卡片')));
    expect(theme.colorScheme.primary, Red.accent);
    expect(theme.scaffoldBackgroundColor, Red.bg);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'PingFang SC');
  });

  testWidgets('english empty state', (tester) async {
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('en'),
        client: FakeFeedClient(const []),
        pollEvery: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No cards yet'), findsOneWidget);
    expect(find.text('New stories will appear here.'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.text('EN'), findsNothing);
    expect(find.text('ALL'), findsOneWidget);
  });

  testWidgets('settings language toggle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProclanApp(
        client: FakeFeedClient(const []),
        pollEvery: null,
        locales: LocaleController(prefs),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-prefs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lang-zh')));
    await tester.pumpAndSettle();
    expect(find.text('界面语言'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('还没有卡片'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-prefs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lang-en')));
    await tester.pumpAndSettle();
    expect(prefs.getString(LocaleController.key), 'en');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('No cards yet'), findsOneWidget);
  });

  testWidgets('first launch follows the system theme and language', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final themes = ThemeController(prefs);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(() {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.platformDispatcher.clearLocalesTestValue();
    });

    await tester.pumpWidget(
      ProclanApp(
        client: FakeFeedClient(const []),
        pollEvery: null,
        locales: LocaleController(prefs),
        themes: themes,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No cards yet'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('No cards yet')))
          .scaffoldBackgroundColor,
      const Color(0xFFF4F4F5),
    );
    expect(prefs.getString(ThemeController.key), isNull);
    expect(prefs.getString(LocaleController.key), isNull);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    await tester.pumpAndSettle();
    expect(find.text('还没有卡片'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('还没有卡片'))).scaffoldBackgroundColor,
      const Color(0xFF000000),
    );

    await themes.setDark(false);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('还没有卡片'))).scaffoldBackgroundColor,
      const Color(0xFFF4F4F5),
    );
    expect(prefs.getString(ThemeController.key), 'light');
  });

  testWidgets('saved theme and locale stay put', (tester) async {
    SharedPreferences.setMockInitialValues({
      ThemeController.key: 'dark',
      LocaleController.key: 'zh',
    });
    final prefs = await SharedPreferences.getInstance();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(() {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.platformDispatcher.clearLocalesTestValue();
    });

    await tester.pumpWidget(
      ProclanApp(
        client: FakeFeedClient(const []),
        pollEvery: null,
        locales: LocaleController(prefs),
        themes: ThemeController(prefs),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有卡片'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('还没有卡片'))).scaffoldBackgroundColor,
      const Color(0xFF000000),
    );
  });

  testWidgets('unread filter inside a category keeps that category', (
    tester,
  ) async {
    final client = FakeFeedClient([
      _card(id: 'a', title: '模型降价', category: '科技'),
      _card(id: 'b', title: '汇率波动', category: '财经'),
    ]);
    await tester.pumpWidget(
      ProclanApp(locale: const Locale('zh'), client: client, pollEvery: null),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('汇率波动'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回信息流'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '财经'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-prefs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unread-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('没有未读卡片了'), findsOneWidget);
    expect(find.text('本栏还没有卡片'), findsNothing);

    await tester.tap(find.byKey(const Key('empty-action')));
    await tester.pumpAndSettle();
    expect(find.text('汇率波动'), findsOneWidget);
    expect(find.text('模型降价'), findsNothing);
  });

  testWidgets('older day groups start collapsed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final yesterday = DateTime.now().subtract(
      const Duration(days: 1, hours: 2),
    );
    final client = FakeFeedClient([
      _card(id: 'a', title: '今天的卡片', category: '科技'),
      _card(
        id: 'b',
        title: '昨天的卡片',
        category: '科技',
        createdAt: yesterday.toIso8601String(),
      ),
    ]);
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: client,
        pollEvery: null,
        prefs: prefs,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天的卡片'), findsOneWidget);
    expect(find.text('昨天的卡片'), findsNothing);

    await tester.tap(find.text('昨天'));
    await tester.pumpAndSettle();
    expect(find.text('昨天的卡片'), findsOneWidget);
    final stored = jsonDecode(
      prefs.getString('proclan.collapsed.v2')!,
    ) as Map<String, dynamic>;
    expect(stored.values, contains(false));
  });

  testWidgets('list shows the publication and detail shows the bot', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: FakeFeedClient([_card(id: 'a', title: '模型降价', category: '科技')]),
        pollEvery: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('HACKER NEWS'), findsOneWidget);
    expect(find.text('北风'), findsNothing);

    await tester.tap(find.text('模型降价'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('北风'));
    expect(find.text('北风'), findsOneWidget);
    expect(find.text('Hacker News'), findsOneWidget);
  });

  testWidgets('mark all read clears the unread list', (tester) async {
    final client = FakeFeedClient([
      _card(id: 'a', title: '模型降价', category: '科技'),
      _card(id: 'b', title: '汇率波动', category: '财经'),
    ]);
    await tester.pumpWidget(
      ProclanApp(locale: const Locale('zh'), client: client, pollEvery: null),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-prefs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unread-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('只看未读 · 2'), findsOneWidget);
    expect(find.byKey(const Key('mark-all-read')), findsOneWidget);
    final chip = tester.getTopLeft(find.text('只看未读 · 2'));
    final action = tester.getTopLeft(find.byKey(const Key('mark-all-read')));
    expect(action.dx, greaterThan(chip.dx));

    await tester.tap(find.byKey(const Key('mark-all-read')));
    await tester.pumpAndSettle();
    expect(find.text('模型降价'), findsNothing);
    expect(find.text('汇率波动'), findsNothing);
    expect(find.text('没有未读卡片了'), findsOneWidget);
  });

  testWidgets('masthead avatar follows the username', (tester) async {
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: FakeFeedClient(const []),
        pollEvery: null,
        account: AccountClient(
          baseUrl: 'http://127.0.0.1:9',
          httpClient: _MeClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('settings')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '林',
    );
  });

  testWidgets('bots page copies an mcp setup prompt', (tester) async {
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('zh'),
        client: FakeFeedClient(const []),
        pollEvery: null,
        account: AccountClient(
          baseUrl: 'http://127.0.0.1:9',
          httpClient: _BotsClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bot 与接入'));
    await tester.pumpAndSettle();

    expect(find.text('复制 MCP 安装提示词'), findsOneWidget);
    expect(find.textContaining('请在你当前使用的客户端里'), findsNothing);
    expect(find.textContaining('bot-secret'), findsNothing);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.byKey(const Key('copy-mcp-prompt')));
    await tester.pumpAndSettle();

    expect(copied, contains('请在你当前使用的客户端里添加下面这个远程 MCP'));
    expect(copied, contains('Bearer bot-secret'));
    expect(copied, contains('http://127.0.0.1:9/mcp'));
    expect(copied, contains('submit_cards'));
    expect(copied, contains('inputSchema'));
    expect(copied, isNot(contains('bot_desc')));
    expect(copied, isNot(contains('grok')));
    expect(copied, isNot(contains('Add the remote MCP server below')));
  });

  testWidgets('mcp setup prompt follows the english locale', (tester) async {
    await tester.pumpWidget(
      ProclanApp(
        locale: const Locale('en'),
        client: FakeFeedClient(const []),
        pollEvery: null,
        account: AccountClient(
          baseUrl: 'http://127.0.0.1:9',
          httpClient: _BotsClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bots and access'));
    await tester.pumpAndSettle();

    expect(find.text('Copy MCP install prompt'), findsOneWidget);
    expect(
      find.textContaining('Add the remote MCP server below'),
      findsNothing,
    );
    expect(find.textContaining('请在你当前使用的客户端里'), findsNothing);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.byKey(const Key('copy-mcp-prompt')));
    await tester.pumpAndSettle();

    expect(copied, contains('Add the remote MCP server below'));
    expect(copied, contains('Bearer bot-secret'));
    expect(copied, contains('http://127.0.0.1:9/mcp'));
    expect(copied, contains('inputSchema'));
    expect(copied, isNot(contains('bot_desc')));
    expect(copied, isNot(contains('grok')));
    expect(copied, isNot(contains('请在你当前使用的客户端里')));
  });

  testWidgets('bot detail shows the latest card and delete removes the name', (
    tester,
  ) async {
    final httpClient = _BotPagesClient();
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
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bot 与接入'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bot-日报')), findsOneWidget);
    expect(find.byKey(const Key('bot-空')), findsOneWidget);

    await tester.tap(find.byKey(const Key('bot-空')));
    await tester.pumpAndSettle();
    expect(find.text('首次出现'), findsOneWidget);
    expect(find.text('还没有功能介绍。下次推送时会写上。'), findsOneWidget);
    expect(find.text('服务端没有这个 bot 还留着的消息。'), findsOneWidget);
    expect(find.text('编辑资料'), findsNothing);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('复制 MCP 安装提示词'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bot-日报')));
    await tester.pumpAndSettle();
    expect(find.text('盯着模型价格。'), findsOneWidget);
    expect(find.text('模型降价'), findsOneWidget);
    expect(find.text('汇率波动'), findsOneWidget);
    expect(find.text('价格下调'), findsOneWidget);
    expect(find.textContaining('Hacker News'), findsWidgets);

    await tester.tap(find.byKey(const Key('bot-card-c1')));
    await tester.pumpAndSettle();
    expect(find.text('正文'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('detail-back'))).tooltip,
      '返回',
    );

    await tester.tap(find.byKey(const Key('detail-back')));
    await tester.pumpAndSettle();
    expect(find.text('正文'), findsNothing);
    expect(find.text('汇率波动'), findsOneWidget);
    expect(find.text('编辑资料'), findsNothing);

    await tester.tap(find.byKey(const Key('bot-card-c2')));
    await tester.pumpAndSettle();
    expect(find.text('另一篇'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('另一篇'), findsNothing);
    expect(find.text('模型降价'), findsOneWidget);
    expect(find.text('编辑资料'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copy-mcp-prompt')), findsOneWidget);
    expect(find.text('编辑资料'), findsNothing);
    expect(find.text('模型降价'), findsNothing);

    await tester.tap(find.byKey(const Key('bot-日报')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-bot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-bot')));
    await tester.pumpAndSettle();
    expect(find.text('删除这个 bot？'), findsOneWidget);
    expect(find.textContaining('已经收到的卡片还在'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bot-日报')), findsNothing);
    expect(find.byKey(const Key('bot-空')), findsOneWidget);
    expect(find.text('复制 MCP 安装提示词'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('编辑资料'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('stat-bots'))).data, '1');
  });
}

class _BotsClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = switch (request.method == 'GET' ? path : '') {
      '/v1/me' => '{"id":"u","username":"林间"}',
      '/v1/bots' => '{"bots":[]}',
      '/v1/me/bot-token' => '{"token":"bot-secret"}',
      _ => null,
    };
    if (body == null) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _MeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path == '/v1/me') {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"id":"u","username":"林间"}')),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(const Stream.empty(), 404);
  }
}

class _BotPagesClient extends http.BaseClient {
  var _names = ['日报', '空'];

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
      final items = [for (final name in _names) '{"name":"$name"}'].join(',');
      return _json('{"bots":[$items]}');
    }
    if (path == '/v1/bots/profile') {
      final name = request.url.queryParameters['name'];
      if (request.method == 'DELETE') {
        _names = [
          for (final item in _names)
            if (item != name) item,
        ];
        return http.StreamedResponse(const Stream.empty(), 204);
      }
      if (name == '日报') {
        return _json(
          '{"name":"日报","first_seen":"2026-10-27T01:02:03Z","bot_desc":"盯着模型价格。","cards":[{"id":"c1","title":"模型降价","summary":"价格下调","body":"正文","category":"科技","source":"Hacker News","created_bot":"日报","created_at":"2026-10-27T02:00:00Z"},{"id":"c2","title":"汇率波动","summary":"美元走弱","body":"另一篇","category":"财经","source":"Hacker News","created_bot":"日报","created_at":"2026-10-27T01:00:00Z"}]}',
        );
      }
      if (name == '空') {
        return _json(
          '{"name":"空","first_seen":"2026-10-27T01:02:03Z","bot_desc":"","cards":[]}',
        );
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"detail":"bot not found"}')),
        404,
        headers: {'content-type': 'application/json'},
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
