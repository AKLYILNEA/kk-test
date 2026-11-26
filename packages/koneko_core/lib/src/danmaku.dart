import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:koneko_contract/koneko_contract.dart';

import 'bangumi.dart';

class DandanplaySource implements DanmakuSource {
  DandanplaySource(this._vault, {Dio? client})
    : _client = client ?? _danmakuClient();

  static Dio _danmakuClient() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 18),
      sendTimeout: const Duration(seconds: 12),
      headers: {
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      },
    ),
  );

  // Default DanDanPlay credentials aligned with Kazumi so danmaku works out of
  // the box without requiring manual API setup. CI/users may still override.
  static const _defaultAppId = 'qb998n8g3u';
  static const _defaultAppKey = '4y2waS6A6yb4uw7Dhd9pmdTzvrF7YUsg';
  static const _envAppId = String.fromEnvironment('DANDANAPI_APPID');
  static const _envAppKey = String.fromEnvironment('DANDANAPI_KEY');

  final SettingsVault _vault;
  final Dio _client;
  final _cache = <String, List<DanmakuItem>>{};

  Future<SecretSettings> _safeSettings() async {
    try {
      return await _vault.read();
    } on Object {
      // Never block danmaku if secure storage is unavailable/locked.
      return const SecretSettings();
    }
  }

  ({String appId, String key}) _credentials(SecretSettings settings) {
    final appId = settings.danmakuAppId.isNotEmpty
        ? settings.danmakuAppId
        : (_envAppId.isNotEmpty ? _envAppId : _defaultAppId);
    final key = settings.danmakuKey.isNotEmpty
        ? settings.danmakuKey
        : (_envAppKey.isNotEmpty ? _envAppKey : _defaultAppKey);
    return (appId: appId, key: key);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    SecretSettings settings, [
    Map<String, Object?>? query,
  ]) async {
    final creds = _credentials(settings);
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signature = base64Encode(
      sha256
          .convert(utf8.encode('${creds.appId}$timestamp$path${creds.key}'))
          .bytes,
    );
    final response = await _client.get<dynamic>(
      'https://api.dandanplay.net$path',
      queryParameters: query,
      options: Options(
        headers: {
          'referer': '',
          'X-Auth': '1',
          'X-AppId': creds.appId,
          'X-Timestamp': '$timestamp',
          'X-Signature': signature,
        },
      ),
    );
    final data = response.data;
    if (data is String) {
      return jsonObject(jsonDecode(data));
    }
    return jsonObject(data);
  }

  List<DanmakuItem> _parseComments(
    Map<String, dynamic> raw,
    List<String> blocked,
  ) {
    final items = <DanmakuItem>[];
    for (final comment in jsonList(raw['comments']).map(jsonObject)) {
      final parameters = jsonString(comment['p']).split(',');
      final text = jsonString(comment['m']).trim();
      if (parameters.length < 3 || text.isEmpty) continue;
      final seconds = double.tryParse(parameters.first);
      if (seconds == null || !seconds.isFinite || seconds < 0) continue;
      final mode = int.tryParse(parameters[1]) ?? 1;
      final source = parameters.length > 3 ? parameters[3].trim() : '';
      items.add(
        DanmakuItem(
          timeSeconds: seconds,
          text: text,
          colorHex: 0xff000000 | (int.tryParse(parameters[2]) ?? 0xffffff),
          lane: mode == 5
              ? -1
              : mode == 4
              ? -2
              : items.length % 6,
          source: source,
        ),
      );
    }
    items.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    return _applyBlocked(items, blocked);
  }

  List<DanmakuItem> _applyBlocked(
    List<DanmakuItem> items,
    List<String> blocked,
  ) {
    if (blocked.isEmpty) return items;
    return items
        .where(
          (item) => !blocked.any(
            (word) => word.isNotEmpty && item.text.contains(word),
          ),
        )
        .toList();
  }

  @override
  Future<List<DanmakuItem>> load(AnimeSubject subject, int episode) async {
    final settings = await _safeSettings();
    final cacheKey = 'sub:${subject.subjectId}:ep:$episode';
    final cached = _cache[cacheKey];
    if (cached != null) {
      return _applyBlocked(cached, settings.blockedDanmaku);
    }

    var animeId = 0;
    var episodes = <dynamic>[];

    // 1. Primary lookup: match via Bangumi subject ID (aligned with Kazumi).
    try {
      final match = await _get(
        '/api/v2/bangumi/bgmtv/${subject.subjectId}',
        settings,
      );
      final bangumiObj = jsonObject(match['bangumi']);
      animeId = jsonInt(match['bangumiId'] ?? bangumiObj['animeId']);
      episodes = jsonList(bangumiObj['episodes']);
    } on Object {
      // Fallback to title search below.
    }

    // 2. Fallback lookup: search DanDanPlay by Chinese or original title.
    if (animeId <= 0) {
      final queries = <String>{
        if (subject.title.trim().isNotEmpty) subject.title.trim(),
        if (subject.originalTitle.trim().isNotEmpty)
          subject.originalTitle.trim(),
      };
      for (final query in queries) {
        try {
          final search = await _get('/api/v2/search/episodes', settings, {
            'anime': query,
            'v2': 'true',
          });
          final animes = jsonList(search['animes']);
          if (animes.isNotEmpty) {
            final first = jsonObject(animes.first);
            animeId = jsonInt(first['animeId']);
            episodes = jsonList(first['episodes']);
            if (animeId > 0) break;
          }
        } on Object {
          // Try next query candidate.
        }
      }
    }

    if (animeId <= 0) return const [];

    if (episodes.isEmpty) {
      try {
        final info = await _get('/api/v2/bangumi/$animeId', settings);
        episodes = jsonList(jsonObject(info['bangumi'])['episodes']);
      } on Object {
        // Proceed with Kazumi's episode ID convention if episode list fails.
      }
    }

    final matches = episodes
        .map(jsonObject)
        .where(
          (item) =>
              jsonInt(item['episodeNumber']) == episode ||
              RegExp(
                r'^\s*(?:第\s*)?'
                '$episode'
                r'(?:\s*[集话話]|\s*$)',
              ).hasMatch(jsonString(item['episodeTitle'])),
        );
    final episodeId = jsonInt(matches.firstOrNull?['episodeId']);
    final id = episodeId > 0
        ? '$episodeId'
        : '$animeId${episode.toString().padLeft(4, '0')}';

    final raw = await _get('/api/v2/comment/$id', settings, {
      'withRelated': 'true',
      'chConvert': '1',
    });
    final parsed = _parseComments(raw, const []);
    if (_cache.length >= 20) _cache.remove(_cache.keys.first);
    _cache[cacheKey] = parsed;
    return _applyBlocked(parsed, settings.blockedDanmaku);
  }

  @override
  Future<List<DanmakuAnimeMatch>> searchAnimes(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];
    final settings = await _safeSettings();
    final raw = await _get('/api/v2/search/episodes', settings, {
      'anime': trimmed,
      'v2': 'true',
    });
    final results = <DanmakuAnimeMatch>[];
    for (final entry in jsonList(raw['animes']).map(jsonObject)) {
      final animeId = jsonInt(entry['animeId']);
      final title = jsonString(entry['animeTitle']).trim();
      if (animeId <= 0 || title.isEmpty) continue;
      final eps = <DanmakuEpisodeMatch>[];
      var idx = 0;
      for (final epRaw in jsonList(entry['episodes']).map(jsonObject)) {
        idx++;
        final epId = jsonInt(epRaw['episodeId']);
        if (epId <= 0) continue;
        final epNum = jsonInt(epRaw['episodeNumber']);
        eps.add(
          DanmakuEpisodeMatch(
            episodeId: epId,
            episodeNumber: epNum > 0 ? epNum : idx,
            title: jsonString(epRaw['episodeTitle']).trim().isNotEmpty
                ? jsonString(epRaw['episodeTitle']).trim()
                : '第 ${epNum > 0 ? epNum : idx} 话',
          ),
        );
      }
      results.add(
        DanmakuAnimeMatch(
          animeId: animeId,
          title: title,
          typeDescription: jsonString(entry['typeDescription']),
          episodes: eps,
        ),
      );
    }
    return results;
  }

  @override
  Future<List<DanmakuItem>> loadByEpisodeId(int episodeId) async {
    if (episodeId <= 0) return const [];
    final settings = await _safeSettings();
    final cacheKey = 'ep:$episodeId';
    final cached = _cache[cacheKey];
    if (cached != null) {
      return _applyBlocked(cached, settings.blockedDanmaku);
    }
    final raw = await _get('/api/v2/comment/$episodeId', settings, {
      'withRelated': 'true',
      'chConvert': '1',
    });
    final parsed = _parseComments(raw, const []);
    if (_cache.length >= 20) _cache.remove(_cache.keys.first);
    _cache[cacheKey] = parsed;
    return _applyBlocked(parsed, settings.blockedDanmaku);
  }
}
