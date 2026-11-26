// Adapted from Kazumi (GPL-3.0), see the Koneko README for attribution.

import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:koneko_core/src/kazumi/modules/search/plugin_search_module.dart';
import 'package:koneko_core/src/kazumi/plugins/api_rule_config.dart';
import 'package:koneko_core/src/kazumi/services/plugin/api_rule_strategy.dart';
import 'package:koneko_core/src/kazumi/services/plugin/rule_engine_models.dart';
import 'package:koneko_core/src/kazumi/services/plugin/xpath_rule_strategy.dart';

abstract interface class RuleRequestExecutor {
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  });
}

class RuleEngine {
  RuleEngine({
    RuleRequestExecutor? requestExecutor,
    ApiRuleStrategy apiStrategy = const ApiRuleStrategy(),
    XPathRuleStrategy xpathStrategy = const XPathRuleStrategy(),
    bool logFailures = true,
  }) : _requestExecutor = requestExecutor ?? _DefaultRuleRequestExecutor(),
       _apiStrategy = apiStrategy,
       _xpathStrategy = xpathStrategy,
       _logFailures = logFailures;

  final RuleRequestExecutor _requestExecutor;
  final ApiRuleStrategy _apiStrategy;
  final XPathRuleStrategy _xpathStrategy;
  final bool _logFailures;

  Future<RuleSearchTrace> search(
    RuleExecutionConfig config,
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    late final PreparedRuleRequest request;
    try {
      request = config.searchMode == RuleMode.api
          ? _apiStrategy.prepareRequest(
              config.searchApiConfig.request,
              <String, Object?>{'keyword': keyword},
            )
          : _xpathStrategy.prepareSearchRequest(config, keyword);
    } catch (error, stackTrace) {
      _logFailure(config, 'search request preparation', error, stackTrace);
      throw SearchErrorException(config.pluginName, cause: error);
    }

    late final String raw;
    try {
      raw = await _executeRequest(
        request,
        config,
        phase: 'search request',
        wrapError: (error) =>
            SearchErrorException(config.pluginName, cause: error),
        cancelToken: cancelToken,
      );
    } on SearchErrorException catch (error) {
      if (_isCaptchaChallengeResponse(error, config)) {
        throw CaptchaRequiredException(config.pluginName);
      }
      rethrow;
    }
    try {
      final parsed = config.searchMode == RuleMode.api
          ? _apiStrategy.parseSearch(raw, config.searchApiConfig)
          : _xpathStrategy.parseSearch(raw, config);
      if (parsed.items.isEmpty) {
        throw NoResultException(config.pluginName);
      }
      _logDiagnostics(config, 'search', parsed.diagnostics);
      return RuleSearchTrace(
        rawResponse: raw,
        response: PluginSearchResponse(
          pluginName: config.pluginName,
          data: parsed.items,
        ),
        matchedFragments: parsed.matchedFragments,
        diagnostics: parsed.diagnostics,
      );
    } on CaptchaRequiredException {
      rethrow;
    } on NoResultException {
      rethrow;
    } catch (error, stackTrace) {
      if (_isCancellation(error)) rethrow;
      _logFailure(config, 'search response parsing', error, stackTrace);
      throw SearchErrorException(config.pluginName, cause: error);
    }
  }

  /// Parses HTML harvested from the captcha webview as a search result,
  /// skipping one network round trip after verification. Returns null when
  /// not applicable (API/POST rules) or when the page does not parse into
  /// results (still a challenge page, redirect page, or empty list) — the
  /// caller then falls back to a regular re-search.
  PluginSearchResponse? tryParseHarvestedSearch(
    RuleExecutionConfig config,
    String raw,
  ) {
    if (raw.trim().isEmpty) return null;
    // The webview loads the search URL with GET; API-mode and POST-mode
    // rules may render a different page than the real search response.
    if (config.searchMode == RuleMode.api || config.usePost) return null;
    try {
      final parsed = _xpathStrategy.parseSearch(raw, config);
      if (parsed.items.isEmpty) return null;
      _logDiagnostics(config, 'harvested search', parsed.diagnostics);
      return PluginSearchResponse(
        pluginName: config.pluginName,
        data: parsed.items,
      );
    } catch (error) {
      if (_logFailures) {
        developer.log(
          'Plugin: ${config.pluginName} harvested page not parseable, '
          'falling back to re-search ($error)',
        );
      }
      return null;
    }
  }

  Future<RuleChapterTrace> queryChapters(
    RuleExecutionConfig config,
    String source, {
    CancelToken? cancelToken,
  }) async {
    late final PreparedRuleRequest request;
    try {
      request = config.chapterMode == RuleMode.api
          ? _apiStrategy.prepareRequest(
              config.chapterApiConfig.request,
              <String, Object?>{'source': source},
            )
          : _xpathStrategy.prepareChapterRequest(config, source);
    } catch (error, stackTrace) {
      _logFailure(config, 'chapter request preparation', error, stackTrace);
      throw ChapterErrorException(config.pluginName, cause: error);
    }

    final raw = await _executeRequest(
      request,
      config,
      phase: 'chapter request',
      wrapError: (error) =>
          ChapterErrorException(config.pluginName, cause: error),
      cancelToken: cancelToken,
    );
    try {
      final parsed = config.chapterMode == RuleMode.api
          ? _apiStrategy.parseChapters(
              raw,
              config.chapterApiConfig,
              source: source,
              baseUrl: config.baseUrl,
            )
          : _xpathStrategy.parseChapters(raw, config);
      if (parsed.roads.isEmpty) {
        throw ChapterErrorException(config.pluginName);
      }
      _logDiagnostics(config, 'chapter', parsed.diagnostics);
      return RuleChapterTrace(
        rawResponse: raw,
        roads: parsed.roads,
        diagnostics: parsed.diagnostics,
      );
    } on ChapterErrorException {
      rethrow;
    } catch (error, stackTrace) {
      if (_isCancellation(error)) rethrow;
      _logFailure(config, 'chapter response parsing', error, stackTrace);
      throw ChapterErrorException(config.pluginName, cause: error);
    }
  }

  Future<String> _executeRequest(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    required String phase,
    required Object Function(Object error) wrapError,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _requestExecutor.execute(
        request,
        config,
        cancelToken: cancelToken,
      );
    } catch (error, stackTrace) {
      if (_isCancellation(error)) rethrow;
      _logFailure(config, phase, error, stackTrace);
      throw wrapError(error);
    }
  }

  bool _isCancellation(Object error) {
    return error is DioException && error.type == DioExceptionType.cancel;
  }

  /// Checks whether a failed XPath search request actually returned an
  /// anti-crawler challenge page.
  ///
  /// Dio rejects non-2xx responses before [XPathRuleStrategy.parseSearch]
  /// gets a chance to inspect the response body. Protected sites commonly
  /// return challenge HTML with HTTP 403/429/503, so reuse the configured
  /// captcha detector against the preserved Dio response body and hand the
  /// request over to the existing captcha flow when it matches.
  bool _isCaptchaChallengeResponse(
    SearchErrorException error,
    RuleExecutionConfig config,
  ) {
    if (config.searchMode != RuleMode.xpath ||
        !config.antiCrawlerConfig.enabled) {
      return false;
    }

    final rawError = error.cause;
    if (rawError is! DioException) return false;

    final response = rawError.response;

    // Cloudflare marks managed challenge responses with this header.
    // This is useful when the body is empty, compressed unexpectedly, or
    // otherwise unavailable to Dio on a specific platform.
    final cfMitigated = response?.headers.value('cf-mitigated');
    if (cfMitigated?.toLowerCase() == 'challenge') {
      return true;
    }

    final data = response?.data;
    final raw = data is String ? data : data?.toString() ?? '';
    if (raw.trim().isEmpty) return false;

    try {
      return _xpathStrategy.detectsCaptchaChallenge(
        raw,
        config.antiCrawlerConfig,
      );
    } catch (detectError, stackTrace) {
      _logFailure(
        config,
        'failed response captcha detection',
        detectError,
        stackTrace,
      );
      return false;
    }
  }

  /// Surfaces partially-skipped nodes so incomplete results are traceable
  /// from logs even when the rule succeeds overall.
  void _logDiagnostics(
    RuleExecutionConfig config,
    String phase,
    List<String> diagnostics,
  ) {
    if (!_logFailures || diagnostics.isEmpty) return;
    final preview = diagnostics.take(3).join('; ');
    developer.log(
      'Plugin: ${config.pluginName} $phase skipped ${diagnostics.length} '
      'node(s): $preview',
    );
  }

  void _logFailure(
    RuleExecutionConfig config,
    String phase,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!_logFailures) return;
    developer.log(
      'Plugin: ${config.pluginName} $phase failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// In-memory session cookie & UA store per rule plugin (aligned with Kazumi's
/// `PluginCookieManager`) so user-verified sites share cookies with Dio requests.
class PluginCookieStore {
  PluginCookieStore._();
  static final PluginCookieStore instance = PluginCookieStore._();

  final Map<String, Map<String, String>> _cookiesByPlugin = {};
  final Map<String, String> _userAgentByPlugin = {};

  String _key(String pluginName) => pluginName.trim().toLowerCase();

  void save({
    required String pluginName,
    required String cookieString,
    String? userAgent,
  }) {
    final key = _key(pluginName);
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      _userAgentByPlugin[key] = userAgent.trim();
    }
    final map = _cookiesByPlugin.putIfAbsent(key, () => {});
    for (final part in cookieString.split(';')) {
      final trimmed = part.trim();
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final name = trimmed.substring(0, eq).trim();
      final value = trimmed.substring(eq + 1).trim();
      if (name.isNotEmpty) map[name] = value;
    }
  }

  String? cookieHeaderFor(String pluginName) {
    final map = _cookiesByPlugin[_key(pluginName)];
    if (map == null || map.isEmpty) return null;
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  String? userAgentFor(String pluginName) => _userAgentByPlugin[_key(pluginName)];
}

class _DefaultRuleRequestExecutor implements RuleRequestExecutor {
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      },
    ),
  );

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(request.url);
    if (!const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('规则请求地址必须使用 HTTP 或 HTTPS');
    }
    final cookies = PluginCookieStore.instance.cookieHeaderFor(
      config.pluginName,
    );
    final verifiedUa = PluginCookieStore.instance.userAgentFor(
      config.pluginName,
    );
    final headers = <String, dynamic>{
      'referer': Uri.parse(config.baseUrl).toString(),
      'user-agent': ?verifiedUa,
      'cookie': ?cookies,
      for (final entry in request.headers.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final response = await _dio.request<String>(
      request.url,
      queryParameters: request.query,
      data: request.method == 'POST' ? request.body : null,
      options: Options(
        method: request.method,
        responseType: ResponseType.plain,
        headers: headers,
        contentType: switch (request.bodyType) {
          ApiBodyType.json => 'application/json',
          ApiBodyType.form => 'application/x-www-form-urlencoded',
          _ => null,
        },
      ),
      cancelToken: cancelToken,
    );
    return response.data ?? '';
  }
}
