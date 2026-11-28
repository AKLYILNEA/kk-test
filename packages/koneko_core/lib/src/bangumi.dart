import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:koneko_contract/koneko_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

Dio networkClient() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 9),
    receiveTimeout: const Duration(seconds: 16),
    sendTimeout: const Duration(seconds: 12),
    headers: {
      'user-agent':
          'AKLYILNEA/Koneko/0.0.34 (https://github.com/AKLYILNEA/kk-test)',
    },
  ),
);

Map<String, dynamic> jsonObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
List<dynamic> jsonList(Object? value) => value is List ? value : const [];
int jsonInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String jsonString(Object? value) => value is String ? value : '';

typedef _CatalogEpisode = ({
  int number,
  String title,
  String airDate,
  DateTime? airTime,
});

class BangumiCatalog implements OnlineCatalog {
  BangumiCatalog(this._preferences, {Dio? client})
    : _client = client ?? networkClient() {
    final raw = _preferences.getString(_cacheKey);
    if (raw == null) return;
    try {
      final cache = jsonObject(jsonDecode(raw));
      for (final data in jsonList(cache['subjects'])) {
        final item = jsonObject(data);
        final id = jsonInt(item['id']);
        if (id > 0) _subjects[id] = item;
      }
      _trending = jsonList(cache['trending']).map(jsonInt).toList();
      for (final day in jsonObject(cache['week']).entries) {
        _week[jsonInt(day.key)] = jsonList(day.value).map(jsonInt).toList();
      }
      _indexTrending();
      _indexWeek();
    } on FormatException {
      // A damaged cache never prevents an online refresh.
    }
  }

  static const _base = 'https://api.bgm.tv';
  static const _nextBase = 'https://next.bgm.tv';
  static const _cacheKey = 'koneko_bangumi_cache_v1';
  static const _profileCacheKey = 'koneko_bangumi_profile_v1';
  final SharedPreferences _preferences;
  final Dio _client;
  final _changes = StreamController<void>.broadcast();
  final _subjects = <int, Map<String, dynamic>>{};
  final _subjectViews =
      <int, ({int day, int rank, int? weekday, AnimeSubject subject})>{};
  final _trendingRanks = <int, int>{};
  final _weekdays = <int, int>{};
  final _details = <int, Future<void>>{};
  final _episodeLoads = <int, Future<void>>{};
  final _episodesLoaded = <int>{};
  final _episodes = <int, List<_CatalogEpisode>>{};
  final _episodeViews =
      <
        int,
        ({
          int watched,
          int? current,
          DateTime? expires,
          List<EpisodeItem> items,
        })
      >{};
  final _related = <int, List<int>>{};
  final _relations = <int, Future<List<SubjectRelation>>>{};
  final _characters = <int, Future<List<SubjectCharacter>>>{};
  final _credits = <int, Future<List<SubjectPerson>>>{};
  final _comments = <int, List<SubjectComment>>{};
  final _commentTotals = <int, int>{};
  final _week = <int, List<int>>{};
  final _seasonCalendars = <String, Map<int, List<int>>>{};
  final _queries = <String, List<int>>{};
  final _tagFeeds = <String, List<int>>{};
  final _tagOffsets = <String, int>{};
  List<int> _trending = [];
  int _trendingOffset = 0;
  bool _usedNextTrending = true;
  Future<void>? _refresh;
  bool _saving = false;
  bool _savePending = false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  String get seasonTitle {
    final start = (DateTime.now().month - 1) ~/ 3;
    return '${DateTime.now().year} ${const ['冬', '春', '夏', '秋'][start]}季新番';
  }

  Future<dynamic> get(
    String endpoint, {
    Map<String, Object?>? query,
    String? token,
  }) async {
    final result = await _client.get<dynamic>(
      '$_base$endpoint',
      queryParameters: query,
      options: token == null
          ? null
          : Options(
              headers: {'authorization': 'Bearer $token'},
              followRedirects: false,
            ),
    );
    return result.data;
  }

  Future<dynamic> write(
    String endpoint,
    String method,
    String token,
    Map<String, Object?> data,
  ) async {
    final result = await _client.request<dynamic>(
      '$_base$endpoint',
      data: data,
      options: Options(
        method: method,
        headers: {'authorization': 'Bearer $token'},
        followRedirects: false,
      ),
    );
    return result.data;
  }

  @override
  Future<void> refresh() =>
      _refresh ??= _fetchHome().whenComplete(() => _refresh = null);

  Future<void> _fetchHome() async {
    final requests = <Future<void>>[
      _fetchTrendingPage(offset: 0, limit: 36).then<void>((ids) {
        if (ids.isNotEmpty) {
          _trending = ids;
          _indexTrending();
          _trendingOffset = ids.length;
        }
      }),
      _fetchCurrentCalendar().then<void>((days) {
        if (days.isNotEmpty) {
          _week
            ..clear()
            ..addAll(days);
          _indexWeek();
        }
      }),
    ];
    final errors = <Object>[];
    await Future.wait(
      requests.map(
        (request) => request.catchError((Object error) {
          errors.add(error);
        }),
      ),
    );
    _notify();
    if (errors.length == requests.length ||
        (_trending.isEmpty && _week.isEmpty && errors.isNotEmpty)) {
      throw errors.first;
    }
  }

  Future<List<int>> _fetchTrendingPage({
    required int offset,
    required int limit,
  }) async {
    // Primary: Kazumi's next.bgm.tv /p1/trending/subjects (rich global trending feed).
    if (_usedNextTrending || offset == 0) {
      try {
        final response = await _client.get<dynamic>(
          '$_nextBase/p1/trending/subjects',
          queryParameters: {'type': 2, 'limit': limit, 'offset': offset},
        );
        final rows = jsonList(jsonObject(response.data)['data']);
        final rawSubjects = <Object?>[
          for (final item in rows)
            if (jsonObject(item)['subject'] is Map) jsonObject(item)['subject'],
        ];
        final ids = _readSubjects(rawSubjects);
        if (ids.isNotEmpty) {
          _usedNextTrending = true;
          return ids;
        }
      } on Object {
        if (offset == 0) _usedNextTrending = false;
      }
    }

    // Fallback: Bangumi v0 search sorted by heat across all anime (not 1-quarter only).
    final response = await _client.post<dynamic>(
      '$_base/v0/search/subjects',
      queryParameters: {'limit': limit, 'offset': offset},
      data: {
        'keyword': '',
        'sort': 'heat',
        'filter': {
          'type': [2],
          'nsfw': false,
        },
      },
    );
    return _readSubjects(jsonObject(response.data)['data']);
  }

  @override
  Future<bool> loadMoreTrending({String? tag}) async {
    final cleanedTag = tag?.trim() ?? '';
    if (cleanedTag.isEmpty || cleanedTag == '全部') {
      final offset = _trendingOffset > 0 ? _trendingOffset : _trending.length;
      final page = await _fetchTrendingPage(offset: offset, limit: 24);
      if (page.isEmpty) return false;
      final merged = <int>{..._trending, ...page}.toList();
      _trending = merged;
      _indexTrending();
      _trendingOffset = offset + page.length;
      _notify();
      return page.length >= 16;
    }

    final existing = _tagFeeds[cleanedTag] ?? const <int>[];
    final offset = _tagOffsets[cleanedTag] ?? existing.length;
    final response = await _client.post<dynamic>(
      '$_base/v0/search/subjects',
      queryParameters: {'limit': 30, 'offset': offset},
      data: {
        'keyword': '',
        'sort': 'heat',
        'filter': {
          'type': [2],
          'tag': [cleanedTag],
          'nsfw': false,
        },
      },
    );
    final ids = _readSubjects(jsonObject(response.data)['data']);
    if (ids.isEmpty) return false;
    _tagFeeds[cleanedTag] = <int>{...existing, ...ids}.toList();
    _tagOffsets[cleanedTag] = offset + ids.length;
    _notify();
    return ids.length >= 20;
  }

  @override
  Future<BangumiProfile?> loadProfile(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return null;
    try {
      final account = jsonObject(await get('/v0/me', token: trimmed));
      final username = jsonString(account['username']).trim();
      final nickname = jsonString(account['nickname']).trim();
      final id = jsonInt(account['id']);
      if (username.isEmpty && nickname.isEmpty && id <= 0) {
        return _readCachedProfile();
      }
      final avatar = jsonObject(account['avatar']);
      final avatarUrl = _normalizeImageUrl(
        jsonString(avatar['large']).isNotEmpty
            ? jsonString(avatar['large'])
            : jsonString(avatar['medium']),
      );
      final profile = BangumiProfile(
        id: id,
        username: username,
        nickname: nickname.isNotEmpty ? nickname : username,
        sign: jsonString(account['sign']).trim(),
        avatarUrl: avatarUrl,
      );
      unawaited(
        _preferences.setString(
          _profileCacheKey,
          jsonEncode({
            'id': profile.id,
            'username': profile.username,
            'nickname': profile.nickname,
            'sign': profile.sign,
            'avatarUrl': profile.avatarUrl,
          }),
        ),
      );
      return profile;
    } on Object {
      return _readCachedProfile();
    }
  }

  BangumiProfile? _readCachedProfile() {
    final raw = _preferences.getString(_profileCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonObject(jsonDecode(raw));
      final username = jsonString(map['username']);
      final nickname = jsonString(map['nickname']);
      final id = jsonInt(map['id']);
      if (username.isEmpty && nickname.isEmpty && id <= 0) return null;
      return BangumiProfile(
        id: id,
        username: username,
        nickname: nickname.isNotEmpty ? nickname : username,
        sign: jsonString(map['sign']),
        avatarUrl: jsonString(map['avatarUrl']),
      );
    } on FormatException {
      return null;
    }
  }

  Future<Map<int, List<int>>> _fetchCurrentCalendar() async {
    // Primary: Kazumi's next.bgm.tv /p1/calendar (returns full HTTPS covers & scores).
    try {
      final response = await _client.get<dynamic>('$_nextBase/p1/calendar');
      final payload = jsonObject(response.data);
      final days = <int, List<int>>{};
      for (var day = 1; day <= 7; day++) {
        final entries = jsonList(payload['$day']);
        final rawSubjects = <Object?>[
          for (final item in entries)
            if (jsonObject(item)['subject'] is Map) jsonObject(item)['subject'],
        ];
        if (rawSubjects.isNotEmpty) {
          days[day] = _readSubjects(rawSubjects);
        }
      }
      if (days.isNotEmpty) return days;
    } on Object {
      // Fallback to v0 /calendar below.
    }

    final data = await get('/calendar');
    final days = <int, List<int>>{};
    for (final value in jsonList(data)) {
      final day = jsonObject(value);
      final index = jsonInt(jsonObject(day['weekday'])['id']);
      if (index >= 1 && index <= 7) {
        days[index] = _readSubjects(day['items']);
      }
    }
    return days;
  }

  static String _normalizeImageUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }
    return trimmed.startsWith('https://') ? trimmed : '';
  }

  @override
  Future<void> searchOnline(String query) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return;
    final response = await _client.post<dynamic>(
      '$_base/v0/search/subjects',
      queryParameters: {'limit': 40},
      data: {
        'keyword': query.trim(),
        'sort': 'match',
        'filter': {
          'type': [2],
          'nsfw': false,
        },
      },
    );
    _queries[key] = _readSubjects(jsonObject(response.data)['data']);
    if (_queries.length > 40) _queries.remove(_queries.keys.first);
    _notify();
  }

  @override
  Future<List<AnimeSubject>> searchFiltered(
    SearchFilter filter, {
    int offset = 0,
    int limit = 30,
  }) async {
    final filterMap = <String, Object?>{
      'type': [2],
      'nsfw': false,
    };
    if (filter.tags.isNotEmpty) {
      filterMap['tag'] = filter.tags;
    }
    if (filter.sort == 'rank') {
      filterMap['rank'] = ['>0', '<=99999'];
    }
    if (filter.season case final season?) {
      final (start, end) = season.dateRange;
      filterMap['air_date'] = ['>=$start', '<$end'];
    } else if (filter.year case final year?) {
      filterMap['air_date'] = ['>=$year-01-01', '<${year + 1}-01-01'];
    }
    if (filter.minScore case final minScore? when minScore > 0) {
      filterMap['rating'] = ['>=$minScore', '<=10'];
    }
    if (filter.weekdays.isNotEmpty) {
      final days = filter.weekdays.toSet().toList()..sort();
      filterMap['air_weekday'] = days;
    }

    final response = await _client.post<dynamic>(
      '$_base/v0/search/subjects',
      queryParameters: {'limit': limit, 'offset': offset},
      data: {
        'keyword': filter.keyword.trim(),
        'sort': filter.sort,
        'filter': filterMap,
      },
    );
    final ids = _readSubjects(jsonObject(response.data)['data']);
    _notify();
    return _items(ids);
  }

  @override
  Future<Map<int, List<AnimeSubject>>> loadSeasonCalendar(
    AnimeSeason season,
  ) async {
    if (season.isCurrent) {
      if (_week.isEmpty) {
        await refresh();
      }
      return {for (var d = 1; d <= 7; d++) d: _items(_week[d] ?? const [])};
    }

    final cached = _seasonCalendars[season.code];
    if (cached != null) {
      return {for (var d = 1; d <= 7; d++) d: _items(cached[d] ?? const [])};
    }

    final (start, end) = season.dateRange;
    final response = await _client.post<dynamic>(
      '$_base/v0/search/subjects',
      queryParameters: {'limit': 100, 'offset': 0},
      data: {
        'keyword': '',
        'sort': 'rank',
        'filter': {
          'type': [2],
          'tag': ['日本'],
          'air_date': ['>=$start', '<$end'],
          'rank': ['>0', '<=99999'],
          'nsfw': false,
        },
      },
    );
    final ids = _readSubjects(jsonObject(response.data)['data']);
    final grouped = <int, List<int>>{for (var d = 1; d <= 7; d++) d: []};
    for (final id in ids) {
      final raw = _subjects[id];
      final dateStr = jsonString(raw?['date']).isNotEmpty
          ? jsonString(raw?['date'])
          : jsonString(raw?['air_date']);
      final parsed = DateTime.tryParse(dateStr);
      final day = parsed?.weekday ?? 1;
      grouped[day]!.add(id);
    }
    _seasonCalendars[season.code] = grouped;
    if (_seasonCalendars.length > 12) {
      _seasonCalendars.remove(_seasonCalendars.keys.first);
    }
    _notify();
    return {for (var d = 1; d <= 7; d++) d: _items(grouped[d] ?? const [])};
  }

  @override
  Future<void> loadSubject(int id, {bool includeExtras = true}) async {
    await _ensureSubjectCore(id);
    if (!includeExtras) return;
    await Future.wait<void>([
      loadEpisodes(id).onError((Object _, StackTrace _) {}),
      loadRelations(
        id,
      ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ]);
  }

  Future<void> _ensureSubjectCore(int id) async {
    final existing = _details[id];
    if (existing != null) {
      await existing;
      return;
    }
    final task = _fetchSubjectCore(id);
    _details[id] = task;
    try {
      await task;
    } on Object {
      if (identical(_details[id], task)) {
        _details.remove(id);
      }
      rethrow;
    }
  }

  Future<void> _fetchSubjectCore(int id) async {
    final detail = await get('/v0/subjects/$id');
    final subject = jsonObject(detail);
    if (jsonInt(subject['id']) != id) throw const FormatException('番剧详情格式无效');
    _remember(subject);
    _notify();
  }

  @override
  Future<void> loadEpisodes(int id) async {
    if (_episodesLoaded.contains(id) && (_episodes[id]?.isNotEmpty ?? false)) {
      return;
    }
    final existing = _episodeLoads[id];
    if (existing != null) {
      await existing;
      return;
    }
    final task = _fetchEpisodes(id);
    _episodeLoads[id] = task;
    try {
      await task;
    } finally {
      if (identical(_episodeLoads[id], task)) {
        _episodeLoads.remove(id);
      }
    }
  }

  Future<void> _fetchEpisodes(int id) async {
    var items = <Map<String, dynamic>>[];
    Object? primaryError;
    try {
      for (var offset = 0; offset < 1000; offset += 100) {
        final response = jsonObject(
          await get(
            '/v0/episodes',
            query: {
              'subject_id': id,
              'type': 0,
              'limit': 100,
              'offset': offset,
            },
          ),
        );
        final page = jsonList(response['data']);
        items.addAll(page.map(jsonObject));
        if (page.isEmpty ||
            page.length < 100 ||
            offset + page.length >= jsonInt(response['total'])) {
          break;
        }
      }
    } on Object catch (error) {
      primaryError = error;
    }

    // Fallback to next.bgm.tv/p1/subjects/$id/episodes if v0 failed or returned empty.
    if (items.isEmpty) {
      try {
        final nextItems = <Map<String, dynamic>>[];
        for (var offset = 0; offset < 1000; offset += 100) {
          final response = await _client.get<dynamic>(
            '$_nextBase/p1/subjects/$id/episodes',
            queryParameters: {'limit': 100, 'offset': offset},
          );
          final payload = jsonObject(response.data);
          final page = jsonList(payload['data']).map(jsonObject).toList();
          nextItems.addAll(page);
          if (page.isEmpty ||
              page.length < 100 ||
              offset + page.length >= jsonInt(payload['total'])) {
            break;
          }
        }
        final mainOnly = nextItems
            .where((ep) => jsonInt(ep['type']) == 0)
            .toList();
        items = mainOnly.isNotEmpty ? mainOnly : nextItems;
      } on Object {
        if (primaryError != null) rethrow;
      }
    }

    if (items.isEmpty && primaryError != null) {
      throw primaryError;
    }
    _episodes[id] = items.map(_parseEpisode).toList(growable: false);
    _episodeViews.remove(id);
    _episodesLoaded.add(id);
    _subjectViews.remove(id);
    _changes.add(null);
  }

  _CatalogEpisode _parseEpisode(Map<String, dynamic> item) {
    final rawSort = item['sort'];
    final sort = jsonInt(rawSort);
    final number = rawSort is num && rawSort % 1 != 0
        ? 0
        : sort > 0
        ? sort
        : jsonInt(item['ep']);
    final localized = jsonString(item['name_cn']);
    final alternate = jsonString(item['nameCN']);
    final airDate = jsonString(item['airdate']);
    return (
      number: number,
      title: localized.isNotEmpty
          ? localized
          : alternate.isNotEmpty
          ? alternate
          : jsonString(item['name']),
      airDate: airDate,
      airTime: DateTime.tryParse(airDate),
    );
  }

  int _episodeCount(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final total = jsonInt(data['total_episodes']);
    return total > 0
        ? total
        : math.max(jsonInt(data['eps']), jsonInt(data['episodes']));
  }

  Future<List<T>> _loadSubjectItems<T>(
    Map<int, Future<List<T>>> cache,
    int id,
    Future<List<T>> Function() fetch,
  ) {
    if (cache.length >= 48 && !cache.containsKey(id)) {
      cache.remove(cache.keys.first);
    }
    return cache.putIfAbsent(id, () async {
      try {
        return List.unmodifiable(await fetch());
      } on Object {
        cache.remove(id);
        rethrow;
      }
    });
  }

  String? _itemImage(Map<String, dynamic> item) {
    final images = jsonObject(item['images']);
    for (final key in ['medium', 'common', 'grid', 'small', 'large']) {
      final value = jsonString(images[key]);
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  SubjectPerson _person(
    Map<String, dynamic> item, {
    List<String> credits = const [],
  }) => SubjectPerson(
    id: jsonInt(item['id']),
    name: jsonString(item['name']),
    imageUrl: _itemImage(item),
    credits: credits,
  );

  @override
  Future<List<SubjectCharacter>> loadCharacters(int id) =>
      _loadSubjectItems(_characters, id, () async {
        final rows = jsonList(
          await get('/v0/subjects/$id/characters'),
        ).map(jsonObject);
        return [
          for (final row in rows)
            if (jsonInt(row['id']) > 0 && jsonString(row['name']).isNotEmpty)
              SubjectCharacter(
                id: jsonInt(row['id']),
                name: jsonString(row['name']),
                relation: jsonString(row['relation']),
                imageUrl: _itemImage(row),
                actors: [
                  for (final actor in jsonList(row['actors']).map(jsonObject))
                    if (jsonInt(actor['id']) > 0 &&
                        jsonString(actor['name']).isNotEmpty)
                      _person(actor),
                ],
              ),
        ];
      });

  @override
  Future<List<SubjectPerson>> loadCredits(int id) => _loadSubjectItems(
    _credits,
    id,
    () async {
      final rows = jsonList(
        await get('/v0/subjects/$id/persons'),
      ).map(jsonObject);
      final people = <int, Map<String, dynamic>>{};
      final credits = <int, Set<String>>{};
      for (final row in rows) {
        final personId = jsonInt(row['id']);
        if (personId <= 0 || jsonString(row['name']).isEmpty) continue;
        people.putIfAbsent(personId, () => row);
        final relation = jsonString(row['relation']);
        final episodes = jsonString(row['eps']).trim();
        if (relation.isEmpty) continue;
        (credits[personId] ??= {}).add(
          episodes.isEmpty ? relation : '$relation · $episodes',
        );
      }
      return [
        for (final entry in people.entries)
          _person(
            entry.value,
            credits: List.unmodifiable(credits[entry.key] ?? const <String>{}),
          ),
      ];
    },
  );

  @override
  Future<List<SubjectRelation>> loadRelations(int id) =>
      _loadSubjectItems(_relations, id, () async {
        final entries = jsonList(await get('/v0/subjects/$id/subjects'));
        final rows = entries
            .map(jsonObject)
            .where((row) => jsonInt(row['id']) > 0);
        _related[id] = _readSubjects(
          rows.where((row) => jsonInt(row['type']) == 2).toList(),
        );
        _subjectViews.remove(id);
        _notify();
        return [
          for (final row in rows)
            SubjectRelation(
              id: jsonInt(row['id']),
              title: jsonString(row['name_cn']).trim().isEmpty
                  ? jsonString(row['name'])
                  : jsonString(row['name_cn']),
              originalTitle: jsonString(row['name']),
              relation: jsonString(row['relation']),
              isAnime: jsonInt(row['type']) == 2,
              imageUrl: _itemImage(row),
            ),
        ];
      });

  void rememberExternal(Iterable<Map<String, dynamic>> subjects) {
    for (final subject in subjects) {
      _remember(subject);
    }
    if (subjects.isEmpty) return;
    _notify();
  }

  void _remember(Map<String, dynamic> item) {
    final id = jsonInt(item['id']);
    if (id == 0) return;
    final old = _subjects.remove(id);
    // The calendar and search responses omit some of the fields in detail.
    final merged = {...?old, ...item};
    if (old != null && const DeepCollectionEquality().equals(old, merged)) {
      _subjects[id] = old;
    } else {
      _subjects[id] = merged;
      _subjectViews.remove(id);
      if (_episodeCount(old) != _episodeCount(merged)) _episodeViews.remove(id);
    }
  }

  List<int> _readSubjects(Object? data) {
    final ids = <int>{};
    for (final entry in jsonList(data)) {
      final item = jsonObject(entry);
      final id = jsonInt(item['id']);
      if (id <= 0) continue;
      _remember(item);
      ids.add(id);
    }
    return ids.toList();
  }

  void _indexTrending() {
    _trendingRanks.clear();
    for (var index = 0; index < _trending.length; index++) {
      _trendingRanks.putIfAbsent(_trending[index], () => index + 1);
    }
  }

  void _indexWeek() {
    _weekdays.clear();
    for (final entry in _week.entries) {
      for (final id in entry.value) {
        _weekdays.putIfAbsent(id, () => entry.key);
      }
    }
  }

  void _notify() {
    _changes.add(null);
    _savePending = true;
    if (!_saving) unawaited(_saveCache());
  }

  Future<void> _saveCache() async {
    _saving = true;
    try {
      while (_savePending) {
        _savePending = false;
        final subjects = _subjects.values.skip(
          math.max(0, _subjects.length - 600),
        );
        final payload = {
          'subjects': subjects.toList(growable: false),
          'trending': List<int>.of(_trending),
          'week': _week.map((day, ids) => MapEntry('$day', ids)),
        };
        try {
          final encoded = _subjects.length <= 64
              ? jsonEncode(payload)
              : await compute(jsonEncode, payload);
          await _preferences.setString(_cacheKey, encoded);
        } on Object {
          // The catalog is still available in memory.
        }
      }
    } finally {
      _saving = false;
    }
  }

  List<AnimeSubject> _items(Iterable<int> ids, [String? tag]) => [
    for (final id in ids)
      if (getSubjectById(id) case final subject?)
        if (tag == null ||
            tag == '全部' ||
            subject.tags.any((item) => item.contains(tag)))
          subject,
  ];

  @override
  List<AnimeSubject> getAllSubjects() => _items(_subjects.keys);
  @override
  List<AnimeSubject> getTrending({String? tag}) {
    final cleanedTag = tag?.trim() ?? '';
    if (cleanedTag.isNotEmpty && cleanedTag != '全部') {
      final tagIds = _tagFeeds[cleanedTag];
      if (tagIds != null && tagIds.isNotEmpty) {
        return _items(tagIds);
      }
    }
    return _items(
      _trending.isEmpty ? _week.values.expand((day) => day).toSet() : _trending,
      tag,
    );
  }

  @override
  List<AnimeSubject> getByWeekday(int weekday) =>
      _items(_week[weekday] ?? const []);
  @override
  List<AnimeSubject> search(String query, {String? tag}) {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return getTrending(tag: tag);
    return _items(_queries[key] ?? const [], tag);
  }

  @override
  AnimeSubject? getSubjectById(int id) {
    final data = _subjects[id];
    if (data == null) return null;
    final now = DateTime.now();
    final today = now.year * 10000 + now.month * 100 + now.day;
    final rank = math.max(4, _trendingRanks[id] ?? 0);
    final weekday = _weekdays[id];
    final cached = _subjectViews[id];
    if (cached != null &&
        cached.day == today &&
        cached.rank == rank &&
        cached.weekday == weekday) {
      return cached.subject;
    }
    final rating = jsonObject(data['rating']);
    final cover = jsonObject(data['images']);
    // Exact Kazumi cover resolution: normalize http:// -> https://, prefer
    // `large` -> `common` -> `medium` -> `small`, and fall back to top-level `image`.
    final url = <String>[
      for (final key in const ['large', 'common', 'medium', 'small'])
        _normalizeImageUrl(jsonString(cover[key])),
      _normalizeImageUrl(jsonString(data['image'])),
    ].firstWhere((candidate) => candidate.isNotEmpty, orElse: () => '');
    var studio = '';
    for (final entry in jsonList(data['infobox'])) {
      final map = jsonObject(entry);
      final key = jsonString(map['key']);
      if (key == '动画制作' || key == '制作') {
        final rawVal = map['value'];
        if (rawVal is String && rawVal.trim().isNotEmpty) {
          studio = rawVal.trim();
          break;
        }
        if (rawVal is List && rawVal.isNotEmpty) {
          final first = rawVal.first;
          final text = first is Map ? jsonString(first['v']) : '$first';
          if (text.trim().isNotEmpty) {
            studio = text.trim();
            break;
          }
        }
      }
    }
    final airtime = jsonObject(data['airtime']);
    final date = DateTime.tryParse(
      jsonString(data['date']).isNotEmpty
          ? jsonString(data['date'])
          : jsonString(data['air_date']).isNotEmpty
          ? jsonString(data['air_date'])
          : jsonString(airtime['date']),
    );
    final original = jsonString(data['name']);
    final chinese = jsonString(data['name_cn']).isNotEmpty
        ? jsonString(data['name_cn'])
        : jsonString(data['nameCN']);
    final total = _episodeCount(data);
    final aired = (_episodes[id] ?? const []).where((episode) {
      final airTime = episode.airTime;
      return airTime != null && airTime.isBefore(now);
    }).length;
    final tags = jsonList(data['tags'])
        .map((tag) => jsonString(jsonObject(tag)['name']))
        .where((tag) => tag.isNotEmpty)
        .toList();
    final subject = AnimeSubject(
      subjectId: id,
      title: chinese.isEmpty
          ? (original.isEmpty ? 'Bangumi #$id' : original)
          : chinese,
      originalTitle: original,
      summary: jsonString(data['summary']),
      score: (rating['score'] as num?)?.toDouble() ?? 0,
      rank: jsonInt(rating['rank']) > 0 ? jsonInt(rating['rank']) : rank,
      year: date?.year ?? 0,
      seasonLabel: date == null ? '' : '${date.year} 年 ${date.month} 月',
      weekday: weekday ?? date?.weekday ?? 1,
      airedEpisodes: aired,
      totalEpisodes: total,
      tags: tags.isEmpty ? const ['动画'] : List.unmodifiable(tags),
      studio: studio,
      poster: const PosterPalette(
        primaryHex: 0xff35426a,
        secondaryHex: 0xff6578a4,
        accentHex: 0xffcfddfb,
        motifIndex: 6,
      ),
      coverUrl: url.isEmpty ? null : url,
      relatedIds: List.unmodifiable(_related[id] ?? const []),
    );
    _subjectViews[id] = (
      day: today,
      rank: rank,
      weekday: weekday,
      subject: subject,
    );
    return subject;
  }

  @override
  List<EpisodeItem> getEpisodes(
    int subjectId, {
    int watchedCount = 0,
    int? currentEp,
  }) {
    final now = DateTime.now();
    final cached = _episodeViews[subjectId];
    if (cached != null &&
        cached.watched == watchedCount &&
        cached.current == currentEp &&
        (cached.expires == null || now.isBefore(cached.expires!))) {
      return cached.items;
    }

    DateTime? expires;
    final result = <EpisodeItem>[];
    for (final episode in _episodes[subjectId] ?? const <_CatalogEpisode>[]) {
      final number = episode.number;
      if (number <= 0) continue;
      final airTime = episode.airTime;
      final unaired = airTime != null && airTime.isAfter(now);
      if (unaired && (expires == null || airTime.isBefore(expires))) {
        expires = airTime;
      }
      result.add(
        EpisodeItem(
          episodeNumber: number,
          title: episode.title,
          durationSeconds: 0,
          airDate: episode.airDate,
          state: number == currentEp
              ? EpisodeWatchState.current
              : number <= watchedCount
              ? EpisodeWatchState.watched
              : unaired
              ? EpisodeWatchState.unaired
              : EpisodeWatchState.aired,
        ),
      );
    }
    if (result.isEmpty && _episodesLoaded.contains(subjectId)) {
      final total = _episodeCount(_subjects[subjectId]);
      if (total > 0 && total <= 500) {
        for (var i = 1; i <= total; i++) {
          result.add(
            EpisodeItem(
              episodeNumber: i,
              title: '第 $i 话',
              durationSeconds: 0,
              airDate: '',
              state: i == currentEp
                  ? EpisodeWatchState.current
                  : i <= watchedCount
                  ? EpisodeWatchState.watched
                  : EpisodeWatchState.aired,
            ),
          );
        }
      }
    }

    if (_episodeViews.length >= 64 && cached == null) {
      _episodeViews.remove(_episodeViews.keys.first);
    }
    final items = List<EpisodeItem>.unmodifiable(result);
    _episodeViews[subjectId] = (
      watched: watchedCount,
      current: currentEp,
      expires: expires,
      items: items,
    );
    return items;
  }

  @override
  List<RuleSourceProbe> probeSources(int subjectId) => const [];

  @override
  List<DanmakuItem> getDanmaku(int subjectId, int episodeNumber) => const [];

  @override
  List<SubjectComment> getComments(int subjectId) =>
      List.unmodifiable(_comments[subjectId] ?? const []);

  @override
  Future<SubjectCommentsPage> loadComments(
    int subjectId, {
    int offset = 0,
    int limit = 20,
  }) async {
    var total = 0;
    var parsed = <SubjectComment>[];
    Object? primaryError;

    // Primary: next.bgm.tv JSON API.
    try {
      final response = await _client.get<dynamic>(
        '$_nextBase/p1/subjects/$subjectId/comments',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final payload = jsonObject(response.data);
      total = jsonInt(payload['total']);
      for (final raw in jsonList(payload['data'])) {
        final item = jsonObject(raw);
        final content = jsonString(item['comment']).trim();
        if (content.isEmpty) continue;
        final user = jsonObject(item['user']);
        final avatar = jsonObject(user['avatar']);
        final avatarUrl = const ['medium', 'large', 'small']
            .map((k) => _normalizeImageUrl(jsonString(avatar[k])))
            .firstWhere((u) => u.startsWith('http'), orElse: () => '');
        final nickname = jsonString(user['nickname']).trim();
        final username = jsonString(user['username']).trim();
        final updatedSec = jsonInt(item['updatedAt']);
        parsed.add(
          SubjectComment(
            userName: nickname.isNotEmpty
                ? nickname
                : (username.isNotEmpty ? username : 'Bangumi 用户'),
            content: content,
            rate: jsonInt(item['rate']),
            updatedAt: updatedSec > 0
                ? DateTime.fromMillisecondsSinceEpoch(updatedSec * 1000)
                : DateTime.now(),
            avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
          ),
        );
      }
    } on Object catch (error) {
      primaryError = error;
    }

    // Automatic fallback: bgm.tv HTML comments page when next.bgm.tv returns 502/timeout.
    var usedHtmlFallback = false;
    if (parsed.isEmpty && primaryError != null) {
      final page = (offset ~/ 20) + 1;
      final htmlResponse = await _client.get<String>(
        'https://bgm.tv/subject/$subjectId/comments',
        queryParameters: {'page': page},
        options: Options(
          responseType: ResponseType.plain,
          headers: const {
            'accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ),
      );
      final html = htmlResponse.data ?? '';
      parsed = _parseHtmlComments(html);
      usedHtmlFallback = true;
    }

    final existing = offset == 0
        ? <SubjectComment>[]
        : List<SubjectComment>.from(_comments[subjectId] ?? const []);
    existing.addAll(parsed);
    _comments[subjectId] = existing;
    if (total > 0) {
      _commentTotals[subjectId] = math.max(total, existing.length);
    } else if (!usedHtmlFallback) {
      _commentTotals[subjectId] = existing.length;
    }

    final hasMore = usedHtmlFallback
        ? parsed.length >= 15
        : offset + parsed.length < total && parsed.isNotEmpty;
    return SubjectCommentsPage(
      items: List.unmodifiable(existing),
      total: _commentTotals[subjectId] ?? existing.length,
      hasMore: hasMore,
    );
  }

  static final _commentItemPattern = RegExp(
    r'<div class="item clearit"[^>]*>(.*?)<div class="likes_grid"',
    dotAll: true,
  );
  static final _commentAvatarPattern = RegExp(
    r"background-image:url\('([^']+)'\)",
  );
  static final _commentUserPattern = RegExp(
    r'<a href="/user/[^"]+" class="l">([^<]+)</a>',
  );
  static final _commentStarPattern = RegExp(r'class="starlight stars(\d+)"');
  static final _commentTimePattern = RegExp(
    r'<small class="grey">@\s*([^<]+)</small>',
  );
  static final _commentBodyPattern = RegExp(
    r'<p class="comment">(.*?)</p>',
    dotAll: true,
  );

  static List<SubjectComment> _parseHtmlComments(String html) {
    final boxStart = html.indexOf('id="comment_box"');
    final slice = boxStart >= 0 ? html.substring(boxStart) : html;
    final now = DateTime.now();
    final results = <SubjectComment>[];
    for (final match in _commentItemPattern.allMatches(slice)) {
      final block = match.group(1) ?? '';
      final rawBody = _commentBodyPattern.firstMatch(block)?.group(1) ?? '';
      final content = _decodeHtmlText(rawBody).trim();
      if (content.isEmpty) continue;
      final userRaw = _commentUserPattern.firstMatch(block)?.group(1) ?? '';
      final userName = _decodeHtmlText(userRaw).trim();
      final avatarRaw = _commentAvatarPattern.firstMatch(block)?.group(1) ?? '';
      final avatarUrl = _normalizeImageUrl(avatarRaw);
      final rate =
          int.tryParse(_commentStarPattern.firstMatch(block)?.group(1) ?? '') ??
          0;
      final timeRaw = _commentTimePattern.firstMatch(block)?.group(1)?.trim();
      results.add(
        SubjectComment(
          userName: userName.isNotEmpty ? userName : 'Bangumi 用户',
          content: content,
          rate: rate,
          updatedAt: _parseBangumiCommentTime(timeRaw, now),
          avatarUrl: avatarUrl.startsWith('http') ? avatarUrl : null,
        ),
      );
    }
    return results;
  }

  static DateTime _parseBangumiCommentTime(String? raw, DateTime now) {
    if (raw == null || raw.isEmpty) return now;
    final absolute = DateTime.tryParse(raw.replaceAll(' ', 'T'));
    if (absolute != null) return absolute;
    var delta = Duration.zero;
    for (final m in RegExp(r'(\d+)\s*([dhms])').allMatches(raw)) {
      final value = int.tryParse(m.group(1) ?? '') ?? 0;
      switch (m.group(2)) {
        case 'd':
          delta += Duration(days: value);
        case 'h':
          delta += Duration(hours: value);
        case 'm':
          delta += Duration(minutes: value);
        case 's':
          delta += Duration(seconds: value);
      }
    }
    return delta > Duration.zero ? now.subtract(delta) : now;
  }

  static String _decodeHtmlText(String raw) {
    final withBreaks = raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return withBreaks
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&');
  }
}
