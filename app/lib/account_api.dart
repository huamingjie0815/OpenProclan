import 'dart:convert';

import 'package:http/http.dart' as http;

import 'feed_client.dart';
import 'l10n/app_localizations.dart';

class AccountException implements Exception {
  const AccountException(this.status, this.detail);
  final int status;
  final String detail;
}

class AuthSession {
  const AuthSession({required this.token, required this.userId});

  final String token;
  final String userId;
}

class AccountUser {
  const AccountUser({required this.id, required this.username});

  final String id;
  final String username;

  factory AccountUser.fromJson(Map<String, dynamic> json) {
    return AccountUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
    );
  }
}

class BotProfile {
  const BotProfile({
    required this.name,
    required this.firstSeen,
    required this.botDesc,
    required this.cards,
    this.listed = false,
    this.code = '',
    this.likes = 0,
    this.dislikes = 0,
    this.follows = 0,
  });

  final String name;
  final String firstSeen;
  final String botDesc;
  final List<FeedCard> cards;
  final bool listed;
  final String code;
  final int likes;
  final int dislikes;
  final int follows;

  factory BotProfile.fromJson(Map<String, dynamic> json) {
    final raw = json['cards'];
    final cards = <FeedCard>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          cards.add(FeedCard.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final community = json['community'];
    final stamp = community is Map ? Map<String, dynamic>.from(community) : const {};
    return BotProfile(
      name: json['name'] as String? ?? '',
      firstSeen: json['first_seen'] as String? ?? '',
      botDesc: json['bot_desc'] as String? ?? '',
      cards: cards,
      listed: stamp['listed'] == true,
      code: stamp['code'] as String? ?? '',
      likes: stamp['likes'] as int? ?? 0,
      dislikes: stamp['dislikes'] as int? ?? 0,
      follows: stamp['follows'] as int? ?? 0,
    );
  }
}

class AccountSettings {
  const AccountSettings({
    required this.cacheMode,
    required this.locale,
    required this.unreadOnly,
  });

  final String cacheMode;
  final String locale;
  final bool unreadOnly;

  factory AccountSettings.fromJson(Map<String, dynamic> json) {
    return AccountSettings(
      cacheMode: json['cache_mode'] as String? ?? '7d',
      locale: json['locale'] as String? ?? 'system',
      unreadOnly: json['unread_only'] as bool? ?? false,
    );
  }
}

String accountMessage(AppLocalizations l, AccountException error) {
  return switch (error.detail) {
    'invalid credentials' => l.invalidCredentials,
    'username taken' => l.usernameTaken,
    'wrong password' => l.wrongPassword,
    'retry later' => l.retryLater,
    'invalid username' => l.invalidUsername,
    'invalid password' => l.invalidPassword,
    'invalid token' => l.sessionExpired,
    'bot not found' => l.botMissing,
    _ => l.authFailed,
  };
}

class AccountClient {
  AccountClient({
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

  Future<AuthSession> register({
    required String username,
    required String password,
  }) async {
    final body = await _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/auth/register'),
        headers: _headers,
        body: jsonEncode({'username': username, 'password': password}),
      ),
      const {200},
    );
    return _session(body);
  }

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final body = await _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/auth/login'),
        headers: _headers,
        body: jsonEncode({'username': username, 'password': password}),
      ),
      const {200},
    );
    return _session(body);
  }

  Future<void> logout() {
    return _send(
      () => _http.post(Uri.parse('$baseUrl/v1/auth/logout'), headers: _headers),
      const {204},
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/auth/password'),
        headers: _headers,
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      ),
      const {204},
    );
  }

  Future<AccountUser> me() async {
    final body = await _send(
      () => _http.get(Uri.parse('$baseUrl/v1/me'), headers: _headers),
      const {200},
    );
    return AccountUser.fromJson(body);
  }

  Future<AccountUser> patchUsername(String username) async {
    final body = await _send(
      () => _http.patch(
        Uri.parse('$baseUrl/v1/me'),
        headers: _headers,
        body: jsonEncode({'username': username}),
      ),
      const {200},
    );
    return AccountUser.fromJson(body);
  }

  Future<AccountSettings> settings() async {
    final body = await _send(
      () => _http.get(Uri.parse('$baseUrl/v1/me/settings'), headers: _headers),
      const {200},
    );
    return AccountSettings.fromJson(body);
  }

  Future<AccountSettings> patchSettings({
    String? cacheMode,
    String? locale,
    bool? unreadOnly,
  }) async {
    final body = await _send(
      () => _http.patch(
        Uri.parse('$baseUrl/v1/me/settings'),
        headers: _headers,
        body: jsonEncode({
          'cache_mode': ?cacheMode,
          'locale': ?locale,
          'unread_only': ?unreadOnly,
        }),
      ),
      const {200},
    );
    return AccountSettings.fromJson(body);
  }

  Future<String> botToken() async {
    final body = await _send(
      () => _http.get(Uri.parse('$baseUrl/v1/me/bot-token'), headers: _headers),
      const {200},
    );
    return body['token'] as String? ?? '';
  }

  Future<String> rotateBotToken() async {
    final body = await _send(
      () =>
          _http.post(Uri.parse('$baseUrl/v1/me/bot-token'), headers: _headers),
      const {200},
    );
    return body['token'] as String? ?? '';
  }

  Future<List<String>> bots() async {
    final body = await _send(
      () => _http.get(Uri.parse('$baseUrl/v1/bots'), headers: _headers),
      const {200},
    );
    final list = body['bots'];
    if (list is! List) {
      return const [];
    }
    return [
      for (final item in list)
        if (item is Map && item['name'] is String) item['name'] as String,
    ];
  }

  Future<BotProfile> botProfile(String name) async {
    final body = await _send(
      () => _http.get(_profileUri(name), headers: _headers),
      const {200},
    );
    return BotProfile.fromJson(body);
  }

  Future<void> deleteBot(String name) {
    return _send(
      () => _http.delete(_profileUri(name), headers: _headers),
      const {204},
    );
  }

  Future<void> shareBot(String name) {
    return _send(
      () => _http.post(
        Uri.parse('$baseUrl/v1/community/share'),
        headers: _headers,
        body: jsonEncode({'name': name}),
      ),
      const {200},
    );
  }

  Future<void> unshareBot(String name) {
    return _send(
      () => _http.delete(
        Uri.parse('$baseUrl/v1/community/share').replace(
          queryParameters: {'name': name},
        ),
        headers: _headers,
      ),
      const {200},
    );
  }

  Uri _profileUri(String name) {
    return Uri.parse('$baseUrl/v1/bots/profile')
        .replace(queryParameters: {'name': name});
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() send,
    Set<int> ok,
  ) async {
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
    if (parsed is Map) {
      return Map<String, dynamic>.from(parsed);
    }
    return {};
  }
}

AuthSession _session(Map<String, dynamic> body) {
  final raw = body['user'];
  final id = raw is Map ? raw['id'] as String? ?? '' : '';
  return AuthSession(token: body['token'] as String? ?? '', userId: id);
}

String _detail(String body) {
  try {
    final parsed = jsonDecode(body);
    if (parsed is Map && parsed['detail'] is String) {
      return parsed['detail'] as String;
    }
  } catch (_) {}
  return '';
}
