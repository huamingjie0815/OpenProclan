import 'dart:convert';

import 'package:http/http.dart' as http;

import 'account_api.dart';
import 'feed_client.dart';

class CommunityBot {
  const CommunityBot({
    required this.ownerId,
    required this.ownerName,
    required this.name,
    required this.botDesc,
    required this.code,
    required this.listed,
    required this.likes,
    required this.dislikes,
    required this.follows,
    this.rank,
    this.following = false,
    this.vote = 0,
    this.mine = false,
    this.direct = false,
    this.card,
  });

  final String ownerId;
  final String ownerName;
  final String name;
  final String botDesc;
  final String code;
  final bool listed;
  final int likes;
  final int dislikes;
  final int follows;
  final int? rank;
  final bool following;
  final int vote;
  final bool mine;
  final bool direct;
  final FeedCard? card;

  factory CommunityBot.fromJson(Map<String, dynamic> json) {
    final raw = json['card'];
    return CommunityBot(
      ownerId: json['owner_id'] as String? ?? '',
      ownerName: json['owner_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      botDesc: json['bot_desc'] as String? ?? '',
      code: json['code'] as String? ?? '',
      listed: json['listed'] == true,
      likes: json['likes'] as int? ?? 0,
      dislikes: json['dislikes'] as int? ?? 0,
      follows: json['follows'] as int? ?? 0,
      rank: json['rank'] as int?,
      following: json['following'] == true,
      vote: json['vote'] as int? ?? 0,
      mine: json['mine'] == true,
      direct: json['direct'] == true,
      card: raw is Map
          ? FeedCard.fromJson(Map<String, dynamic>.from(raw))
          : null,
    );
  }
}

class FollowedBot {
  const FollowedBot({
    required this.name,
    required this.listed,
    required this.botDesc,
    this.direct = false,
  });

  final String name;
  final bool listed;
  final String botDesc;
  final bool direct;
}

class CommunityGroup {
  const CommunityGroup({
    required this.ownerId,
    required this.ownerName,
    required this.bots,
  });

  final String ownerId;
  final String ownerName;
  final List<FollowedBot> bots;

  factory CommunityGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['bots'];
    return CommunityGroup(
      ownerId: json['owner_id'] as String? ?? '',
      ownerName: json['owner_name'] as String? ?? '',
      bots: [
        if (raw is List)
          for (final item in raw)
            if (item is Map)
              FollowedBot(
                name: item['name'] as String? ?? '',
                listed: item['listed'] == true,
                direct: item['direct'] == true,
                botDesc: item['bot_desc'] as String? ?? '',
              ),
      ],
    );
  }
}

class CommunityCopies {
  const CommunityCopies({
    required this.ownerId,
    required this.ownerName,
    required this.name,
    required this.listed,
    required this.botDesc,
    required this.cards,
    this.direct = false,
  });

  final String ownerId;
  final String ownerName;
  final String name;
  final bool listed;
  final bool direct;
  final String botDesc;
  final List<FeedCard> cards;

  factory CommunityCopies.fromJson(Map<String, dynamic> json) {
    final raw = json['cards'];
    return CommunityCopies(
      ownerId: json['owner_id'] as String? ?? '',
      ownerName: json['owner_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      listed: json['listed'] == true,
      direct: json['direct'] == true,
      botDesc: json['bot_desc'] as String? ?? '',
      cards: [
        if (raw is List)
          for (final item in raw)
            if (item is Map) FeedCard.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }
}

abstract class CommunityClient {
  Future<List<CommunityBot>> board(String kind);
  Future<List<CommunityBot>> search(String query);
  Future<CommunityBot> bot({required String ownerId, required String name});
  Future<List<CommunityGroup>> following();
  Future<List<CommunityBot>> directed();
  Future<CommunityCopies> copies({
    required String ownerId,
    required String name,
  });
  Future<void> follow({required String ownerId, required String name});
  Future<void> unfollow({required String ownerId, required String name});
  Future<void> vote({
    required String ownerId,
    required String name,
    required int vote,
  });
}

class HttpCommunityClient implements CommunityClient {
  HttpCommunityClient({
    required String baseUrl,
    this.token = '',
    http.Client? httpClient,
  }) : baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _http = httpClient ?? http.Client();

  final String baseUrl;
  String token;
  final http.Client _http;

  Map<String, String> get _headers => {
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  @override
  Future<List<CommunityBot>> board(String kind) async {
    final body = await _send(
      () => _http.get(
        Uri.parse('$baseUrl/v1/community/board')
            .replace(queryParameters: {'kind': kind}),
        headers: _headers,
      ),
    );
    return _bots(body);
  }

  @override
  Future<List<CommunityBot>> search(String query) async {
    final body = await _send(
      () => _http.get(
        Uri.parse('$baseUrl/v1/community/search')
            .replace(queryParameters: {'q': query}),
        headers: _headers,
      ),
    );
    return _bots(body);
  }

  @override
  Future<CommunityBot> bot({
    required String ownerId,
    required String name,
  }) async {
    final body = await _send(
      () => _http.get(
        Uri.parse('$baseUrl/v1/community/bot')
            .replace(queryParameters: {'owner_id': ownerId, 'name': name}),
        headers: _headers,
      ),
    );
    return CommunityBot.fromJson(body);
  }

  @override
  Future<List<CommunityGroup>> following() async {
    final body = await _send(
      () => _http.get(
        Uri.parse('$baseUrl/v1/community/following'),
        headers: _headers,
      ),
    );
    final raw = body['users'];
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map)
          CommunityGroup.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  @override
  Future<List<CommunityBot>> directed() async {
    final body = await _send(
      () => _http.get(
        Uri.parse('$baseUrl/v1/community/directed'),
        headers: _headers,
      ),
    );
    return _bots(body);
  }

  @override
  Future<CommunityCopies> copies({
    required String ownerId,
    required String name,
  }) async {
    final body = await _send(
      () => _http.get(
        Uri.parse('$baseUrl/v1/community/copies')
            .replace(queryParameters: {'owner_id': ownerId, 'name': name}),
        headers: _headers,
      ),
    );
    return CommunityCopies.fromJson(body);
  }

  @override
  Future<void> follow({required String ownerId, required String name}) async {
    await _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/community/follow'),
        headers: _headers,
        body: jsonEncode({'owner_id': ownerId, 'name': name}),
      ),
      const {204},
    );
  }

  @override
  Future<void> unfollow({required String ownerId, required String name}) async {
    await _send(
      () => _http.delete(
        Uri.parse('$baseUrl/v1/community/follow')
            .replace(queryParameters: {'owner_id': ownerId, 'name': name}),
        headers: _headers,
      ),
      const {204},
    );
  }

  @override
  Future<void> vote({
    required String ownerId,
    required String name,
    required int vote,
  }) async {
    await _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/community/vote'),
        headers: _headers,
        body: jsonEncode({'owner_id': ownerId, 'name': name, 'vote': vote}),
      ),
      const {204},
    );
  }

  List<CommunityBot> _bots(Map<String, dynamic> body) {
    final raw = body['bots'];
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw)
        if (item is Map) CommunityBot.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() send, [
    Set<int> ok = const {200},
  ]) async {
    final response = await send();
    if (!ok.contains(response.statusCode)) {
      throw AccountException(response.statusCode, _detail(response.body));
    }
    if (response.body.isEmpty) {
      return {};
    }
    final parsed = jsonDecode(response.body);
    if (parsed is Map<String, dynamic>) {
      return parsed;
    }
    return {};
  }
}

String _detail(String body) {
  try {
    final parsed = jsonDecode(body);
    if (parsed is Map && parsed['detail'] is String) {
      return parsed['detail'] as String;
    }
  } catch (_) {}
  return body;
}
