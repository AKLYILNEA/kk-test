import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bangumi.dart';
import 'kazumi/plugins/plugins.dart';
import 'kazumi/services/plugin/plugin_import_parser.dart';

Uri networkUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('请输入有效的 HTTP 或 HTTPS 地址');
  }
  return uri;
}

class KazumiRules implements ManagedRules {
  KazumiRules(this._preferences, {Dio? client})
    : _client = client ?? networkClient() {
    final raw = _preferences.getString(_storeKey);
    if (raw == null) return;
    try {
      for (final entry in jsonList(jsonDecode(raw))) {
        final record = jsonObject(entry);
        try {
          final rule = Plugin.fromJson(jsonObject(record['rule']));
          if (rule.name.isNotEmpty && !rule.requiresNewerClient) {
            _installed[pluginNameKey(rule.name)] = (
              plugin: rule,
              enabled: record['enabled'] != false,
            );
          }
        } on Object {
          // Keep other installed rules when one record cannot be parsed.
        }
      }
    } on FormatException {
      // A fresh store can still import rules.
    }
  }

  static const _storeKey = 'koneko_kazumi_rules_v1';
  static const _repoKey = 'koneko_rules_repository';
  static const officialRepository =
      'https://raw.githubusercontent.com/Predidit/KazumiRules/main/';
  static const ghProxyMirror =
      'https://gh-proxy.org/https://raw.githubusercontent.com/Predidit/KazumiRules/main/';
  static const ghfastMirror =
      'https://ghfast.top/https://raw.githubusercontent.com/Predidit/KazumiRules/main/';
  static const gitcodeMirror =
      'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/';

  /// Mirror order aligned with Kazumi (`gh-proxy` default, with automatic
  /// fallback to `ghfast`, `GitCode`, and direct `raw.githubusercontent.com`).
  static const officialMirrors = <String>[
    ghProxyMirror,
    ghfastMirror,
    gitcodeMirror,
    officialRepository,
  ];

  final SharedPreferences _preferences;
  final Dio _client;
  final _installed = <String, ({Plugin plugin, bool enabled})>{};
  final _latencies = <String, ({int elapsed, String status})>{};
  String? _preferredOfficialBase;
  Future<void> _saveQueue = Future.value();

  Plugin? enabledPlugin(String id) {
    final rule = _installed[id];
    return rule?.enabled == true ? rule!.plugin : null;
  }

  @override
  String get currentRepository => (_preferences.getString(_repoKey) ?? '').trim();

  @override
  List<RulePluginMeta> getAllRules() => [
    for (final entry in _installed.entries)
      RulePluginMeta(
        id: entry.key,
        name: entry.value.plugin.name,
        version: entry.value.plugin.version,
        baseUrl: entry.value.plugin.baseUrl,
        apiType: entry.value.plugin.usesApiSearch ? 'API' : 'XPath',
        enabled: entry.value.enabled,
        useNativePlayer: entry.value.plugin.useNativePlayer,
        supportsDanmaku: true,
        latencyMs: _latencies[entry.key]?.elapsed ?? 0,
        lastCheckedLabel: _latencies[entry.key]?.status ?? '尚未测速',
        antiCrawlerEnabled: entry.value.plugin.antiCrawlerConfig.enabled,
        adBlocker: entry.value.plugin.adBlocker,
        multiSources: entry.value.plugin.muliSources,
      ),
  ];

  @override
  Future<List<RuleListing>> browse({String? repository}) async {
    final rawConfigured = repository != null
        ? repository.trim()
        : (_preferences.getString(_repoKey) ?? officialRepository).trim();
    final normalizedBase = _normalizeRepositoryBase(rawConfigured);
    final candidates = _repositoryCandidates(normalizedBase);
    Object? lastError;

    for (final base in candidates) {
      final indexUri = _joinRepoFile(base, 'index.json');
      try {
        final response = await _client.getUri<dynamic>(
          indexUri,
          options: Options(responseType: ResponseType.plain),
        );
        final results = _parseIndex(response.data, base);
        if (officialMirrors.contains(base)) {
          _preferredOfficialBase = base;
        }
        if (repository != null) {
          if (rawConfigured.isEmpty) {
            await _preferences.remove(_repoKey);
          } else {
            await _preferences.setString(_repoKey, normalizedBase);
          }
        }
        return results;
      } on FormatException catch (error) {
        lastError = error;
      } on DioException catch (error) {
        lastError = error;
      }
    }

    throw _describeRepoFailure(lastError, multiMirror: candidates.length > 1);
  }

  @override
  Future<List<RulePluginMeta>> install(Uri url) async {
    final validUrl = networkUri('$url');
    final candidates = _fileCandidates(validUrl);
    Object? lastError;

    for (final candidate in candidates) {
      try {
        final response = await _client.getUri<dynamic>(
          candidate,
          options: Options(responseType: ResponseType.plain),
        );
        final rawText = _stringifyResponse(response.data);
        final installed = await importRules(rawText);
        final matchedBase = _matchOfficialBase('$candidate');
        if (matchedBase != null) {
          _preferredOfficialBase = matchedBase;
        }
        return installed;
      } on FormatException catch (error) {
        lastError = error;
      } on DioException catch (error) {
        lastError = error;
      }
    }

    throw _describeRepoFailure(lastError, multiMirror: candidates.length > 1);
  }

  String _normalizeRepositoryBase(String raw) {
    if (raw.isEmpty) return officialRepository;
    final uri = networkUri(raw);
    if (uri.host.toLowerCase() == 'github.com') {
      final cleanedPath = uri.path.replaceAll(RegExp(r'/+$'), '').toLowerCase();
      if (cleanedPath == '/predidit/kazumirules') {
        return officialRepository;
      }
      throw const FormatException(
        '请填写规则仓库 Raw 地址（如 raw.githubusercontent.com），不要填写 GitHub 网页地址',
      );
    }
    var normalized = raw.trim();
    final lower = normalized.toLowerCase();
    if (lower.endsWith('/index.json')) {
      normalized = normalized.substring(0, normalized.length - 'index.json'.length);
    } else if (lower.endsWith('index.json')) {
      normalized = normalized.substring(0, normalized.length - 'index.json'.length);
    }
    if (!normalized.endsWith('/')) {
      normalized = '$normalized/';
    }
    return normalized;
  }

  List<String> _repositoryCandidates(String normalizedBase) {
    final ordered = <String>[];
    void addUnique(String value) {
      if (!ordered.contains(value)) ordered.add(value);
    }

    if (normalizedBase == officialRepository) {
      if (_preferredOfficialBase != null) {
        addUnique(_preferredOfficialBase!);
      }
      for (final mirror in officialMirrors) {
        addUnique(mirror);
      }
      return ordered;
    }

    if (officialMirrors.contains(normalizedBase)) {
      addUnique(normalizedBase);
      for (final mirror in officialMirrors) {
        addUnique(mirror);
      }
      return ordered;
    }

    addUnique(normalizedBase);
    final uri = Uri.tryParse(normalizedBase);
    if (uri != null && uri.host.toLowerCase() == 'raw.githubusercontent.com') {
      addUnique('https://gh-proxy.org/$normalizedBase');
      addUnique('https://ghfast.top/$normalizedBase');
    }
    return ordered;
  }

  List<Uri> _fileCandidates(Uri url) {
    final raw = '$url';
    final ordered = <Uri>[];
    void addUnique(Uri uri) {
      if (!ordered.any((existing) => '$existing' == '$uri')) {
        ordered.add(uri);
      }
    }

    final matchedBase = _matchOfficialBase(raw);
    if (matchedBase != null) {
      final suffix = raw.substring(matchedBase.length);
      addUnique(url);
      if (_preferredOfficialBase != null) {
        addUnique(Uri.parse('$_preferredOfficialBase$suffix'));
      }
      for (final mirror in officialMirrors) {
        addUnique(Uri.parse('$mirror$suffix'));
      }
      return ordered;
    }

    addUnique(url);
    if (url.host.toLowerCase() == 'raw.githubusercontent.com') {
      addUnique(Uri.parse('https://gh-proxy.org/$raw'));
      addUnique(Uri.parse('https://ghfast.top/$raw'));
    }
    return ordered;
  }

  String? _matchOfficialBase(String url) {
    for (final base in officialMirrors) {
      if (url.startsWith(base)) return base;
    }
    return null;
  }

  Uri _joinRepoFile(String baseWithSlash, String fileName) =>
      Uri.parse('$baseWithSlash${Uri.encodeComponent(fileName)}');

  String _stringifyResponse(Object? data) {
    if (data == null) return '';
    if (data is String) {
      return data.startsWith('\uFEFF') ? data.substring(1) : data;
    }
    return jsonEncode(data);
  }

  List<RuleListing> _parseIndex(Object? rawData, String activeBase) {
    final Object? decoded;
    if (rawData is String) {
      final cleaned = (rawData.startsWith('\uFEFF')
              ? rawData.substring(1)
              : rawData)
          .trim();
      if (cleaned.isEmpty) {
        throw const FormatException('规则仓库返回内容为空');
      }
      decoded = jsonDecode(cleaned);
    } else {
      decoded = rawData;
    }
    if (decoded is! List) {
      throw const FormatException('规则仓库索引格式无效');
    }
    final results = <RuleListing>[];
    for (final raw in jsonList(decoded)) {
      final item = jsonObject(raw);
      final name = jsonString(item['name']).trim();
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains('\\')) {
        continue;
      }
      final rawAnti = item['antiCrawlerConfig'];
      final antiCrawlerEnabled = rawAnti is Map
          ? rawAnti['enabled'] == true
          : item['antiCrawlerEnabled'] == true;
      results.add(
        RuleListing(
          name: name,
          version: '${item['version'] ?? ''}',
          url: _joinRepoFile(activeBase, '$name.json'),
          author: jsonString(item['author']).trim(),
          lastUpdate: jsonInt(item['lastUpdate']),
          useNativePlayer: item['useNativePlayer'] != false,
          antiCrawlerEnabled: antiCrawlerEnabled,
        ),
      );
    }
    return results;
  }

  Object _describeRepoFailure(Object? error, {required bool multiMirror}) {
    if (error is FormatException) return error;
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 404) {
        return StateError('未找到规则仓库文件（HTTP 404），请检查仓库地址');
      }
      if (status != null) {
        return StateError('规则仓库返回异常（HTTP $status），请稍后重试或切换镜像');
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return StateError(
          multiMirror
              ? '连接规则仓库超时（已自动尝试官方源与多个镜像），请检查网络'
              : '连接规则仓库超时，请检查网络或切换镜像源',
        );
      }
      return StateError(
        multiMirror
            ? '无法连接规则仓库（已自动尝试官方源与多个镜像），请检查网络设置'
            : '无法连接规则仓库，请检查网络或仓库地址',
      );
    }
    return StateError('规则仓库读取失败，请稍后重试');
  }

  @override
  Future<List<RulePluginMeta>> importRules(String text) async {
    final parsed = PluginImportParser.parse(text);
    if (parsed.plugins.isEmpty) {
      throw FormatException(parsed.failures.join('\n'));
    }
    for (final plugin in parsed.plugins) {
      if (plugin.baseUrl.isNotEmpty) networkUri(plugin.baseUrl);
    }
    for (final plugin in parsed.plugins) {
      final key = pluginNameKey(plugin.name);
      _installed[key] = (
        plugin: plugin,
        enabled: _installed[key]?.enabled ?? true,
      );
      _latencies.remove(key);
    }
    await _persist();
    return getAllRules();
  }

  @override
  String exportRule(String id) {
    final entry = _installed[id];
    if (entry == null) throw StateError('规则已移除');
    return const JsonEncoder.withIndent('  ').convert(entry.plugin.toJson());
  }

  @override
  Future<List<RulePluginMeta>> removeRule(String id) async {
    _installed.remove(id);
    _latencies.remove(id);
    await _persist();
    return getAllRules();
  }

  @override
  Future<List<RulePluginMeta>> removeRules(Set<String> ids) async {
    for (final id in ids) {
      _installed.remove(id);
      _latencies.remove(id);
    }
    await _persist();
    return getAllRules();
  }

  @override
  Future<List<RulePluginMeta>> reorderRules(int oldIndex, int newIndex) async {
    final entries = _installed.entries.toList();
    if (oldIndex < 0 ||
        oldIndex >= entries.length ||
        newIndex < 0 ||
        newIndex > entries.length) {
      return getAllRules();
    }
    var target = newIndex;
    if (oldIndex < target) target -= 1;
    if (target < 0 || target >= entries.length || target == oldIndex) {
      return getAllRules();
    }
    final moved = entries.removeAt(oldIndex);
    entries.insert(target, moved);
    _installed
      ..clear()
      ..addEntries(entries);
    await _persist();
    return getAllRules();
  }

  @override
  List<RulePluginMeta> toggleRule(String ruleId, bool enabled) {
    final entry = _installed[ruleId];
    if (entry != null) {
      _installed[ruleId] = (plugin: entry.plugin, enabled: enabled);
      unawaited(_persist().onError((Object _, StackTrace _) {}));
    }
    return getAllRules();
  }

  Future<void> _persist() {
    final data = jsonEncode([
      for (final entry in _installed.values)
        {'rule': entry.plugin.toJson(), 'enabled': entry.enabled},
    ]);
    return _saveQueue = _saveQueue.onError((Object _, StackTrace _) {}).then((
      _,
    ) async {
      if (!await _preferences.setString(_storeKey, data)) {
        throw StateError('规则保存失败');
      }
    });
  }

  @override
  Future<List<RulePluginMeta>> testAllLatencies() async {
    final active = _installed.entries
        .where((entry) => entry.value.enabled)
        .toList();
    for (var i = 0; i < active.length; i += 4) {
      await Future.wait(
        active.skip(i).take(4).map((entry) async {
          final stopwatch = Stopwatch()..start();
          try {
            final uri = networkUri(entry.value.plugin.baseUrl);
            final response = await _client.headUri<void>(
              uri,
              options: Options(validateStatus: (status) => true),
            );
            if (_installed[entry.key]?.plugin == entry.value.plugin) {
              final code = response.statusCode ?? 0;
              _latencies[entry.key] = (
                elapsed: stopwatch.elapsedMilliseconds,
                status: code >= 200 && code < 400 ? '连通' : 'HTTP $code',
              );
            }
          } on Object {
            if (_installed[entry.key]?.plugin == entry.value.plugin) {
              _latencies[entry.key] = (elapsed: 0, status: '连接失败');
            }
          }
        }),
      );
    }
    return getAllRules();
  }
}
