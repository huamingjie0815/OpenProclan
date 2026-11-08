import 'dart:convert';

import 'package:http/http.dart' as http;

class FeedCard {
  const FeedCard({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.category,
    required this.tags,
    required this.images,
    required this.source,
    required this.sourceUrls,
    required this.createdBot,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String summary;
  final String body;
  final String category;
  final List<String> tags;
  final List<String> images;

  /// Publication or site name, such as Hacker News. Not the bot name.
  final String source;
  final List<String> sourceUrls;

  /// Name of the bot that submitted the card.
  final String createdBot;
  final bool read;
  final String createdAt;

  factory FeedCard.fromJson(Map<String, dynamic> json) {
    return FeedCard(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      body: json['body'] as String? ?? '',
      category: json['category'] as String? ?? '其他',
      tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
      images: (json['images'] as List<dynamic>? ?? const []).cast<String>(),
      source: json['source'] as String? ?? '',
      sourceUrls: (json['source_urls'] as List<dynamic>? ?? const [])
          .cast<String>(),
      createdBot: json['created_bot'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'body': body,
      'category': category,
      'tags': tags,
      'images': images,
      'source': source,
      'source_urls': sourceUrls,
      'created_bot': createdBot,
      'created_at': createdAt,
    };
  }
}

/// Wikimedia and similar hosts refuse the default Dart user agent.
const imageUserAgent =
    'Proclan (https://github.com/huamingjie0815/OpenProclan)';

class FeedException implements Exception {
  const FeedException(this.code);
  final String code;
  static const offline = 'offline';
  static const deleteFailed = 'delete_failed';
}

abstract class FeedClient {
  Future<List<String>> categories();
  Future<List<FeedCard>> feed();
  Future<void> deleteCard(String id);

  /// Session header for this server's `/media` files. Remote URLs get none.
  Map<String, String> imageHeadersFor(String url) => const {};
}

class HttpFeedClient implements FeedClient {
  HttpFeedClient({
    required String baseUrl,
    this.token = '',
    http.Client? httpClient,
  }) : baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _http = httpClient ?? http.Client();

  final String baseUrl;

  /// Routes keep this instance, so a rotated session writes the field in place.
  String token;
  final http.Client _http;

  Map<String, String> get _headers =>
      token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};

  @override
  Map<String, String> imageHeadersFor(String url) {
    final headers = <String, String>{'User-Agent': imageUserAgent};
    if (token.isNotEmpty && url.startsWith('$baseUrl/media/')) {
      headers.addAll(_headers);
    }
    return headers;
  }

  @override
  Future<List<String>> categories() async {
    final response = await _http.get(
      Uri.parse('$baseUrl/v1/categories'),
      headers: _headers,
    );
    final body = _decode(response);
    return (body['categories'] as List<dynamic>).cast<String>();
  }

  static const _page = 100;

  @override
  Future<List<FeedCard>> feed() async {
    final cards = <FeedCard>[];
    final seen = <String>{};
    var offset = 0;
    while (true) {
      final uri = Uri.parse('$baseUrl/v1/feed')
          .replace(queryParameters: {'limit': '$_page', 'offset': '$offset'});
      final response = await _http.get(uri, headers: _headers);
      final page = (_decode(response)['cards'] as List<dynamic>)
          .map((item) => FeedCard.fromJson(item as Map<String, dynamic>))
          .toList();
      final fresh = <FeedCard>[];
      for (final card in page) {
        if (seen.add(card.id)) {
          fresh.add(card);
        }
      }
      cards.addAll(fresh);
      if (fresh.isEmpty || page.length < _page) {
        return cards;
      }
      offset += page.length;
    }
  }

  @override
  Future<void> deleteCard(String id) async {
    final response = await _http.delete(
      Uri.parse('$baseUrl/v1/feed/$id'),
      headers: _headers,
    );
    if (response.statusCode != 204) {
      throw FeedException(FeedException.deleteFailed);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode != 200) {
      throw FeedException(FeedException.offline);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
