import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'feed_client.dart';

/// Local copies of cards this device has already fetched.
/// The server only keeps about a day; read state stays here.
class Inbox {
  Inbox(this.prefs);

  static const key = 'proclan.inbox';
  static const cacheKey = 'proclan.cacheMode';
  static const syncedKey = 'proclan.settingsSynced';

  final SharedPreferences? prefs;
  List<FeedCard> cards = [];
  Set<String> read = {};
  Set<String> gone = {};
  String cacheMode = '7d';

  void load() {
    final store = prefs;
    if (store == null) {
      return;
    }
    final savedMode = store.getString(cacheKey);
    if (savedMode != null) {
      cacheMode = normalizeCacheMode(savedMode);
    }
    final raw = store.getString(key);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) {
        return;
      }
      final list = parsed['cards'];
      if (list is List) {
        final loaded = <FeedCard>[];
        for (final item in list) {
          if (item is! Map) {
            continue;
          }
          try {
            loaded.add(FeedCard.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
        cards = loaded;
      }
      read = _ids(parsed['read']);
      gone = _ids(parsed['gone']);
      if (savedMode == null) {
        cacheMode = normalizeCacheMode(parsed['cacheMode'] as String?);
      }
      _prune(DateTime.now());
      _keepLiveReads();
      _persist();
    } catch (_) {
      cards = [];
      read = {};
      gone = {};
    }
  }

  /// Keep cards the server has already dropped, and skip tombstones.
  void merge(List<FeedCard> remote) {
    final remoteIds = {for (final card in remote) card.id};
    gone.removeWhere((id) => !remoteIds.contains(id));
    final byId = {for (final card in cards) card.id: card};
    for (final card in remote) {
      if (gone.contains(card.id)) {
        continue;
      }
      byId[card.id] = card;
    }
    cards = byId.values.toList()..sort(_byNewest);
    _prune(DateTime.now());
    _keepLiveReads();
    _persist();
  }

  void markRead(String id) {
    if (cacheMode == 'after_read') {
      cards.removeWhere((card) => card.id == id);
      read.remove(id);
      gone.add(id);
    } else {
      read.add(id);
    }
    _persist();
  }

  void markAllRead() {
    if (cacheMode == 'after_read') {
      gone.addAll(cards.map((card) => card.id));
      cards = [];
      read = {};
    } else {
      read = {for (final card in cards) card.id};
    }
    _persist();
  }

  void markUnread(FeedCard card) {
    gone.remove(card.id);
    read.remove(card.id);
    if (!cards.any((item) => item.id == card.id)) {
      cards = [...cards, card]..sort(_byNewest);
    }
    _persist();
  }

  void delete(String id) {
    cards.removeWhere((card) => card.id == id);
    read.remove(id);
    gone.add(id);
    _persist();
  }

  void setCacheMode(String mode) {
    cacheMode = normalizeCacheMode(mode);
    _prune(DateTime.now());
    _keepLiveReads();
    _persist();
  }

  void _prune(DateTime now) {
    final window = switch (cacheMode) {
      '1d' => const Duration(days: 1),
      '7d' => const Duration(days: 7),
      _ => null,
    };
    if (window == null) {
      return;
    }
    final cutoff = now.toUtc().subtract(window);
    final kept = <FeedCard>[];
    for (final card in cards) {
      final time = DateTime.tryParse(card.createdAt)?.toUtc();
      if (time != null && time.isBefore(cutoff)) {
        gone.add(card.id);
        read.remove(card.id);
        continue;
      }
      kept.add(card);
    }
    cards = kept;
  }

  void _keepLiveReads() {
    final live = {for (final card in cards) card.id};
    read.removeWhere((id) => !live.contains(id));
  }

  void _persist() {
    final store = prefs;
    if (store == null) {
      return;
    }
    store.setString(cacheKey, cacheMode);
    store.setString(
      key,
      jsonEncode({
        'cards': [for (final card in cards) card.toJson()],
        'read': read.toList(),
        'gone': gone.toList(),
        'cacheMode': cacheMode,
      }),
    );
  }
}

String normalizeCacheMode(String? value) {
  return switch (value) {
    '1d' || 'after_read' || '7d' => value!,
    _ => '7d',
  };
}

Set<String> _ids(Object? raw) {
  if (raw is! List) {
    return {};
  }
  return {
    for (final item in raw)
      if (item is String) item,
  };
}

int _byNewest(FeedCard a, FeedCard b) {
  final left = DateTime.tryParse(a.createdAt);
  final right = DateTime.tryParse(b.createdAt);
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return right.compareTo(left);
}
