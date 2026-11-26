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
  static const officialRepository =
      'https://raw.githubusercontent.com/Predidit/KazumiRules/main/';
  final SharedPreferences _preferences;
  final Dio _client;
  final _installed = <String, ({Plugin plugin, bool enabled})>{};
  final _latencies = <String, ({int elapsed, String status})>{};
  Future<void> _saveQueue = Future.value();

  Plugin? enabledPlugin(String id) {
    final rule = _installed[id];
    return rule?.enabled == true ? rule!.plugin : null;
  }

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
      ),
  ];

  @override
  Future<List<RuleListing>> browse({String? repository}) async {
    final configured =
        (repository ??
                _preferences.getString('koneko_rules_repository') ??
                officialRepository)
            .trim();
    final root = networkUri(configured);
    final index = root.path.endsWith('index.json')
        ? root
        : root.replace(
            path:
                '${root.path.endsWith('/') ? root.path : '${root.path}/'}index.json',
          );
    final response = await _client.getUri<dynamic>(index);
    if (response.data is! List) throw const FormatException('规则仓库索引格式无效');
    final results = <RuleListing>[];
    for (final raw in jsonList(response.data)) {
      final item = jsonObject(raw);
      final name = jsonString(item['name']).trim();
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains('\\')) {
        continue;
      }
      results.add(
        RuleListing(
          name: name,
          version: '${item['version'] ?? ''}',
          url: index.resolve('${Uri.encodeComponent(name)}.json'),
        ),
      );
    }
    if (repository != null) {
      await _preferences.setString('koneko_rules_repository', configured);
    }
    return results;
  }

  @override
  Future<List<RulePluginMeta>> install(Uri url) async {
    final response = await _client.getUri<String>(
      networkUri('$url'),
      options: Options(responseType: ResponseType.plain),
    );
    return importRules(response.data ?? '');
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
