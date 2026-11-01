import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:proclan_app/feed_client.dart';

class _Pages extends http.BaseClient {
  _Pages(this.pages);
  final List<String> pages;
  final urls = <Uri>[];
  var index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    urls.add(request.url);
    final bytes = utf8.encode(pages[index]);
    index += 1;
    return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
  }
}

String _page(List<String> ids) {
  final cards = [
    for (final id in ids)
      {
        'id': id,
        'title': id,
        'category': '科技',
        'created_at': '2026-01-01T00:00:00Z',
      },
  ];
  return jsonEncode({'cards': cards});
}

class _AuthLog extends http.BaseClient {
  _AuthLog(this.auths);
  final List<String?> auths;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    auths.add(request.headers['authorization']);
    final bytes = utf8.encode('{"categories": []}');
    return http.StreamedResponse(Stream<List<int>>.value(bytes), 200);
  }
}

void main() {
  test('requests use the current token', () async {
    final auths = <String?>[];
    final client = HttpFeedClient(
      baseUrl: 'http://127.0.0.1:8787',
      token: 'old',
      httpClient: _AuthLog(auths),
    );

    await client.categories();
    client.token = 'new';
    await client.categories();

    expect(auths, ['Bearer old', 'Bearer new']);
  });

  test('feed walks pages until a short page', () async {
    final first = [for (var i = 0; i < 100; i++) 'a$i'];
    final pages = _Pages([
      _page(first),
      _page(const ['old']),
    ]);
    final client = HttpFeedClient(
      baseUrl: 'http://127.0.0.1:8787',
      httpClient: pages,
    );

    final cards = await client.feed();

    expect(cards.map((card) => card.id), [...first, 'old']);
    expect(pages.urls.map((uri) => uri.queryParameters['offset']), [
      '0',
      '100',
    ]);
  });

  test('feed stops when the next page repeats ids', () async {
    final ids = [for (var i = 0; i < 100; i++) 'a$i'];
    final pages = _Pages([_page(ids), _page(ids)]);
    final client = HttpFeedClient(
      baseUrl: 'http://127.0.0.1:8787',
      httpClient: pages,
    );

    final cards = await client.feed();

    expect(cards.map((card) => card.id), ids);
    expect(pages.index, 2);
  });
}
