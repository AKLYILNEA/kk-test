import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show GestureDisposition, HorizontalDragGestureRecognizer;
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemChrome, SystemUiMode, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/player/rule_verify_page.dart';
import 'package:koneko/features/player/source_race.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/ui/koneko_comments.dart';
import 'package:koneko/ui/koneko_danmaku_sheet.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_polygon.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _PanelTab { play, comments }

enum _DrawerTab { episodes, sources, danmaku }

typedef _ResolvedSource = ({
  RuleSearchHit hit,
  List<SourceEpisode> options,
  SourceEpisode line,
  PlayableMedia media,
});

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.subjectId,
    required this.initialEpisode,
    required this.initialRuleId,
    required this.initialRuleName,
    this.offline,
  });

  final int subjectId;
  final int initialEpisode;
  final String initialRuleId;
  final String initialRuleName;
  final OfflineEpisode? offline;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with RouteSettledMixin<PlayerPage>, WidgetsBindingObserver {
  static const _pageSize = 24;

  late int _episode = widget.initialEpisode;
  late String _ruleId = widget.initialRuleId;
  late String _ruleName = widget.initialRuleName;
  PlaybackSession? _session;
  final _viewportKey = GlobalKey();
  final _playbackStatus = ValueNotifier(const PlaybackStatus());

  PlaybackStatus get _status => _playbackStatus.value;
  StreamSubscription<PlaybackStatus>? _subscription;
  Timer? _saveTimer;
  Timer? _brightnessTimer;
  Timer? _hudTimer;
  Timer? _bufferTimer;
  Timer? _probeFlushTimer;
  bool _bufferDelayed = false;
  Duration? _positionAtOpen;
  Completer<void>? _sourceCancellation;
  SourceEpisode? _source;
  List<SourceEpisode> _choices = const [];
  List<DanmakuItem> _danmaku = const [];
  final Map<String, RuleProbeResult> _probes = {};
  final _sourcesRevision = ValueNotifier<int>(0);
  final _pendingProbes = <(String, String?), Future<RuleProbeResult>>{};
  final TextEditingController _sourceKeywordController =
      TextEditingController();

  bool _loading = true;
  bool _loaded = false;
  bool _pageActive = true;
  bool _showHud = true;
  bool _showDanmaku = true;
  bool _fullscreen = false;
  bool _drawerOpen = false;
  bool _upscale = false;
  double _speed = 1;
  double _brightness = 1;
  double? _scrub;
  double? _scrubStart;
  bool _changingBrightness = false;
  _PanelTab _panelTab = _PanelTab.play;
  _DrawerTab _drawer = _DrawerTab.episodes;
  late int _epPageIndex = ((widget.initialEpisode - 1) ~/ _pageSize).clamp(
    0,
    999,
  );
  String? _error;
  Uri? _errorVerifyUrl;
  RuleVerifyHint? _errorVerifyHint;
  String? _errorVerifyRuleId;
  String? _errorVerifyRuleName;
  String? _activeHitUrl;
  late String? _loadingHint = widget.offline != null
      ? '正在打开离线缓存…'
      : (widget.initialRuleName.isNotEmpty
            ? '正在加载 ${widget.initialRuleName}…'
            : '正在准备播放…');
  String? _danmakuError;
  bool _danmakuLoading = false;
  int _request = 0;
  int _danmakuRequest = 0;
  int _probeGeneration = 0;
  int _lastCheckpoint = -1;
  bool _lastCompleted = false;

  AnimeSubject? get _subject =>
      ref.read(catalogRepositoryProvider).getSubjectById(widget.subjectId);

  bool get _isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didSettleRoute() => unawaited(_start());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = PageActivityScope.isActiveOf(context);
    if (_pageActive && !active) unawaited(_session?.setPlaying(false));
    _pageActive = active;
    _watchBuffering();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _checkpoint();
    }
  }

  @override
  void dispose() {
    if (_fullscreen) {
      unawaited(_restoreSystemUi());
    }
    WidgetsBinding.instance.removeObserver(this);
    _request++;
    _sourceCancellation?.complete();
    _bufferTimer?.cancel();
    _probeFlushTimer?.cancel();
    _danmakuRequest++;
    _probeGeneration++;
    _saveTimer?.cancel();
    _brightnessTimer?.cancel();
    _hudTimer?.cancel();
    _sourceKeywordController.dispose();
    _sourcesRevision.dispose();
    unawaited(_subscription?.cancel());
    _playbackStatus.dispose();
    unawaited(_session?.dispose());
    super.dispose();
  }

  void _bumpSources({bool immediate = false}) {
    if (!mounted) return;
    if (immediate) {
      _probeFlushTimer?.cancel();
      _probeFlushTimer = null;
      _sourcesRevision.value++;
      return;
    }
    _probeFlushTimer ??= Timer(const Duration(milliseconds: 80), () {
      _probeFlushTimer = null;
      if (mounted) _sourcesRevision.value++;
    });
  }

  void _syncEpisodePage(int episode) {
    _epPageIndex = ((episode - 1) ~/ _pageSize).clamp(0, 999);
  }

  String _formatSpeed(double speed) =>
      '${speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : speed}x';

  void _armHudAutoHide() {
    _hudTimer?.cancel();
    if (!_showHud || !_status.playing || _drawerOpen) return;
    _hudTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _status.playing && !_drawerOpen) {
        setState(() => _showHud = false);
      }
    });
  }

  void _toggleHud() {
    setState(() {
      if (_drawerOpen) {
        _drawerOpen = false;
      } else {
        _showHud = !_showHud;
      }
    });
    if (_showHud) _armHudAutoHide();
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (_fullscreen == enabled) return;
    setState(() {
      _fullscreen = enabled;
      if (!enabled) _drawerOpen = false;
    });
    if (_isMobilePlatform) {
      if (enabled) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await _restoreSystemUi();
      }
    }
  }

  Future<void> _restoreSystemUi() async {
    if (!_isMobilePlatform) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _start() async {
    try {
      if (_session == null) {
        final factory = ref.read(playbackFactoryProvider);
        if (factory == null) throw StateError('播放器服务不可用');
        final session = factory();
        _subscription = session.changes.listen(_onStatus);
        setState(() => _session = session);
        _saveTimer ??= Timer.periodic(
          const Duration(seconds: 10),
          (_) => _checkpoint(),
        );
      }
      final offline = widget.offline;
      if (offline?.media case final uri?) {
        await _startOffline(uri);
      } else {
        // Resolve remembered rule before opening (from explicit arg, history, or store).
        final sources = ref.read(playbackSourcesProvider);
        final historyRule = ref
            .read(historyProvider.notifier)
            .entryFor(widget.subjectId)
            ?.lastRuleId;
        final remembered = _ruleId.isNotEmpty
            ? _ruleId
            : (sources?.lastSelectedRuleId(widget.subjectId) ??
                  historyRule ??
                  '');
        if (remembered.isNotEmpty) {
          _ruleId = remembered;
        }
        unawaited(_probeAllEnabledRules());
        await _openEpisode(
          _episode,
          strictPreferredRule: remembered.isNotEmpty,
          autoSelectFastest: remembered.isEmpty,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = featureError(error, '播放器初始化失败');
        _loading = false;
      });
    }
  }

  void _onStatus(PlaybackStatus status) {
    if (!mounted) return;
    final completed = status.completed && !_status.completed;
    final startedPlaying = status.playing && !_status.playing;
    final startingPosition = _positionAtOpen;
    final started =
        _loaded &&
        startingPosition != null &&
        !status.buffering &&
        status.error == null &&
        (status.position > startingPosition || status.completed);
    if (started) _positionAtOpen = null;
    _playbackStatus.value = status;
    if (_source case final source? when started) {
      unawaited(
        ref
            .read(playbackSourcesProvider)
            ?.rememberSelectedRule(widget.subjectId, source.ruleId)
            .onError((Object _, StackTrace _) {}),
      );
    }
    _watchBuffering();
    if (completed) _checkpoint();
    if (startedPlaying) _armHudAutoHide();
  }

  bool _isCurrent(int request) => mounted && request == _request;

  int _beginSourceRequest() {
    _sourceCancellation?.complete();
    _sourceCancellation = Completer<void>();
    _bufferTimer?.cancel();
    _bufferTimer = null;
    _bufferDelayed = false;
    _positionAtOpen = null;
    return ++_request;
  }

  bool get _waitingForPlayback =>
      _loaded &&
      _status.error == null &&
      (_status.buffering || _positionAtOpen != null);

  void _playbackOpened(PlaybackSession session, SourceEpisode? source) {
    setState(() {
      _source = source;
      if (source != null) {
        _ruleId = source.ruleId;
        _ruleName = source.ruleName;
      }
      _playbackStatus.value = session.status;
      _positionAtOpen = _status.position;
      _loading = false;
      _loadingHint = null;
      _loaded = true;
      _lastCheckpoint = -1;
      _lastCompleted = false;
    });
    _bumpSources(immediate: true);
    _watchBuffering();
    _armHudAutoHide();
    unawaited(_loadDanmaku());
  }

  void _watchBuffering({Duration delay = const Duration(seconds: 8)}) {
    if (!_pageActive || !_waitingForPlayback) {
      _bufferTimer?.cancel();
      _bufferTimer = null;
      if (_bufferDelayed) setState(() => _bufferDelayed = false);
      return;
    }
    _bufferTimer ??= Timer(delay, () {
      if (mounted) setState(() => _bufferDelayed = true);
    });
  }

  void _continueWaiting() {
    _bufferTimer?.cancel();
    _bufferTimer = null;
    if (_bufferDelayed) {
      setState(() => _bufferDelayed = false);
    }
    _watchBuffering(delay: const Duration(seconds: 12));
  }

  Future<RuleProbeResult> _probe(
    PlaybackSources resolver,
    AnimeSubject subject,
    RulePluginMeta rule, {
    String? keyword,
  }) {
    final key = (rule.id, keyword);
    return _pendingProbes.putIfAbsent(key, () async {
      try {
        return await resolver.probeRule(subject, rule.id, keyword: keyword);
      } on Object {
        return RuleProbeResult(
          ruleId: rule.id,
          ruleName: rule.name,
          state: RuleProbeState.error,
          message: '连接失败',
        );
      } finally {
        _pendingProbes.remove(key);
      }
    });
  }

  Duration _resumeAt(int episode) {
    final history = ref
        .read(historyProvider.notifier)
        .positionFor(widget.subjectId, episode);
    if (history == null || history.isCompleted) return Duration.zero;
    return Duration(seconds: history.positionSeconds);
  }

  /// Probes ALL enabled rules in parallel so the user can see exact search hits
  /// for every source without triggering full-page rebuild storms on startup.
  Future<void> _probeAllEnabledRules({
    String? customKeyword,
    bool forceRefresh = false,
  }) async {
    final resolver = ref.read(playbackSourcesProvider);
    if (resolver == null) return;
    var subject = _subject;
    if (subject == null) {
      await ref
          .read(onlineCatalogProvider)
          ?.loadSubject(widget.subjectId, includeExtras: false);
      subject = _subject;
    }
    if (!mounted || subject == null) return;

    final enabledRules = ref
        .read(rulesProvider)
        .where((r) => r.enabled)
        .toList();
    if (enabledRules.isEmpty) return;

    final gen = ++_probeGeneration;
    final toProbe = <RulePluginMeta>[];
    for (final rule in enabledRules) {
      final existing = _probes[rule.id];
      final reuseExisting =
          !forceRefresh &&
          customKeyword == null &&
          existing != null &&
          existing.state != RuleProbeState.searching;
      if (reuseExisting) continue;
      toProbe.add(rule);
      _probes[rule.id] = RuleProbeResult(
        ruleId: rule.id,
        ruleName: rule.name,
        state: RuleProbeState.searching,
        message: '正在搜索...',
      );
    }
    _bumpSources(immediate: true);
    if (toProbe.isEmpty) return;

    final targetSubject = subject;
    await Future.wait(
      toProbe.map((rule) async {
        final result = await _probe(
          resolver,
          targetSubject,
          rule,
          keyword: customKeyword,
        );
        if (!mounted || gen != _probeGeneration) return;
        _probes[rule.id] = result;
        _bumpSources();
      }),
    );
    if (mounted && gen == _probeGeneration) {
      _bumpSources(immediate: true);
    }
  }

  Future<void> _verifyRule(
    String ruleId,
    String ruleName,
    Uri verifyUrl, {
    RuleVerifyHint? verifyHint,
  }) async {
    if (_fullscreen) {
      await _setFullscreen(false);
    }
    if (!mounted) return;
    final verified = await showRuleVerifySheet(
      context: context,
      ruleId: ruleId,
      ruleName: ruleName,
      verifyUrl: verifyUrl,
      verifyHint: verifyHint,
    );
    if (!mounted || verified != true) return;
    showKonekoBanner(
      context,
      '$ruleName 验证已保存，正在重新搜索',
      level: BannerLevel.success,
    );
    final resolver = ref.read(playbackSourcesProvider);
    final subject = _subject;
    if (resolver != null && subject != null) {
      _probes[ruleId] = RuleProbeResult(
        ruleId: ruleId,
        ruleName: ruleName,
        state: RuleProbeState.searching,
        message: '验证通过，重新搜索中...',
      );
      _bumpSources(immediate: true);
      final result = await resolver.probeRule(
        subject,
        ruleId,
        keyword: _sourceKeywordController.text.trim().isEmpty
            ? null
            : _sourceKeywordController.text.trim(),
      );
      if (mounted) {
        _probes[ruleId] = result;
        _bumpSources(immediate: true);
        if (result.state == RuleProbeState.found) {
          await _openEpisode(_episode, ruleId: ruleId);
        }
      }
    }
  }

  static String _normTitle(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
    '',
  );

  Future<void> _openHit(
    String ruleId,
    String ruleName,
    RuleSearchHit hit,
  ) async {
    final session = _session;
    final resolver = ref.read(playbackSourcesProvider);
    if (session == null || resolver == null) return;
    _checkpoint();
    final prevEpisode = _episode;
    final wasLoaded = _loaded;
    final prevPosition = _status.position;
    final request = _beginSourceRequest();
    final cancelled = _sourceCancellation!.future;
    ++_danmakuRequest;
    setState(() {
      _loading = true;
      _loadingHint = '正在加载 $ruleName…';
      _loaded = false;
      _error = null;
      _errorVerifyUrl = null;
      _errorVerifyHint = null;
      _errorVerifyRuleId = null;
      _errorVerifyRuleName = null;
      _scrub = null;
      _scrubStart = null;
      _danmaku = const [];
      _danmakuError = null;
      _ruleId = ruleId;
      _ruleName = ruleName;
      _activeHitUrl = hit.sourceUrl;
    });
    _bumpSources(immediate: true);
    try {
      await session.setPlaying(false).timeout(const Duration(seconds: 4));
      if (!_isCurrent(request)) return;
      final options = await resolver.loadEpisodesFromHit(ruleId, hit);
      if (!_isCurrent(request)) return;
      if (options.isEmpty) throw StateError('该结果暂无可选剧集');
      final available = options.where((e) => e.number == prevEpisode).toList();
      final targetLines = available.isNotEmpty ? available : [options.first];
      final targetNumber = targetLines.first.number;
      setState(() {
        _choices = options;
        _episode = targetNumber;
        _syncEpisodePage(targetNumber);
      });
      _bumpSources(immediate: true);
      if (available.isEmpty && targetNumber != prevEpisode && mounted) {
        showKonekoBanner(
          context,
          '该源暂无第 $prevEpisode 话，已切换至第 $targetNumber 话',
        );
      }
      final resumeAt =
          targetNumber == prevEpisode &&
              wasLoaded &&
              prevPosition > Duration.zero
          ? prevPosition
          : _resumeAt(targetNumber);
      Object? lastErr;
      for (final episodeSource in targetLines) {
        if (!_isCurrent(request)) return;
        try {
          final media = await resolver
              .resolve(episodeSource, cancelled: cancelled)
              .timeout(const Duration(seconds: 15));
          if (!_isCurrent(request)) return;
          await session
              .open(media, startAt: resumeAt)
              .timeout(const Duration(seconds: 8));
          if (!_isCurrent(request)) return;
          if (!_pageActive) await session.setPlaying(false);
          if (!_isCurrent(request)) return;
          _playbackOpened(session, episodeSource);
          return;
        } on Object catch (err) {
          lastErr = err;
        }
      }
      throw lastErr ?? StateError('该结果暂无可用线路');
    } on Object catch (error) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _loadingHint = null;
        _error = featureError(error, '加载失败');
      });
    }
  }

  Future<void> _startOffline(Uri uri) async {
    final request = _beginSourceRequest();
    final session = _session!;
    setState(() {
      _loading = true;
      _loaded = false;
      _loadingHint = null;
      _error = null;
      _errorVerifyUrl = null;
    });
    try {
      await session
          .open(PlayableMedia(uri), startAt: _resumeAt(_episode))
          .timeout(const Duration(seconds: 8));
      if (!_isCurrent(request)) return;
      if (!_pageActive) await session.setPlaying(false);
      if (!_isCurrent(request)) return;
      _playbackOpened(session, null);
    } on Object catch (error) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _error = featureError(error, '离线文件播放失败');
      });
    }
  }

  Future<void> _openEpisode(
    int episode, {
    String? ruleId,
    SourceEpisode? choice,
    bool strictPreferredRule = false,
    bool autoSelectFastest = false,
    String? excludeRuleId,
  }) async {
    final session = _session;
    if (session == null) return;
    _checkpoint();
    final initialPosition = episode == _episode && _loaded
        ? _status.position
        : _resumeAt(episode);
    final request = _beginSourceRequest();
    final cancelled = _sourceCancellation!.future;
    ++_danmakuRequest;
    setState(() {
      _episode = episode;
      _syncEpisodePage(episode);
      _loaded = false;
      _loading = true;
      _loadingHint = autoSelectFastest ? '正在并发优选最快播放源…' : '正在加载第 $episode 话…';
      _error = null;
      _errorVerifyUrl = null;
      _errorVerifyHint = null;
      _errorVerifyRuleId = null;
      _errorVerifyRuleName = null;
      _scrub = null;
      _scrubStart = null;
      _danmaku = const [];
      _danmakuError = null;
    });
    try {
      await session.setPlaying(false).timeout(const Duration(seconds: 4));
      if (!_isCurrent(request)) return;
      final resolver = ref.read(playbackSourcesProvider);
      if (resolver == null) throw StateError('播放服务不可用');
      var subject = _subject;
      if (subject == null) {
        await ref
            .read(onlineCatalogProvider)
            ?.loadSubject(widget.subjectId, includeExtras: false);
        if (!_isCurrent(request)) return;
        subject = _subject;
      }
      if (subject == null) throw StateError('番剧资料加载失败');

      final rules = ref
          .read(rulesProvider)
          .where((rule) => rule.enabled)
          .toList();
      if (rules.isEmpty) throw StateError('请先添加播放规则');

      if (autoSelectFastest) {
        await _autoSelectFastestPlayable(
          request: request,
          episode: episode,
          initialPosition: initialPosition,
          subject: subject,
          rules: rules,
          resolver: resolver,
          session: session,
          cancelled: cancelled,
          excludeRuleId: excludeRuleId,
        );
        return;
      }

      // If remembered/preferred rule was removed or disabled, immediately
      // surface the 3 choices (重试 / 自动选择 / 手动切换源).
      if (strictPreferredRule &&
          ruleId == null &&
          _ruleId.isNotEmpty &&
          !rules.any((r) => r.id == _ruleId)) {
        final missingName = _ruleName.isNotEmpty ? _ruleName : _ruleId;
        throw StateError('上次使用的「$missingName」已不可用');
      }

      final hasPreferred =
          ruleId != null || (strictPreferredRule && _ruleId.isNotEmpty);
      final ids = ruleId != null
          ? [ruleId]
          : hasPreferred
          ? [_ruleId]
          : [for (final r in rules) r.id];

      Object? problem;
      RuleProbeResult? captchaProbe;

      for (final id in ids) {
        if (!_isCurrent(request)) return;
        final ruleMeta = rules.where((r) => r.id == id).firstOrNull;
        if (mounted) {
          setState(() => _loadingHint = '正在加载 ${ruleMeta?.name ?? id}...');
        }
        try {
          final existingProbe = _probes[id];
          if (existingProbe?.state == RuleProbeState.captchaRequired) {
            captchaProbe = existingProbe;
            if (hasPreferred) break;
            continue;
          }

          final options = await resolver.lookup(subject, id);
          if (!_isCurrent(request)) return;
          final available = options
              .where((item) => item.number == episode)
              .toList();
          if (available.isEmpty) throw StateError('暂无第 $episode 话');
          setState(() {
            _choices = options;
            _ruleId = id;
            _ruleName = options.first.ruleName;
          });
          _bumpSources(immediate: true);
          final currentLine = _source?.line;
          final orderedLines = choice != null
              ? [choice]
              : [
                  ...available.where((item) => item.line == currentLine),
                  ...available.where((item) => item.line != currentLine),
                ];

          Object? lineProblem;
          for (final episodeSource in orderedLines) {
            if (!_isCurrent(request)) return;
            try {
              final media = await resolver
                  .resolve(episodeSource, cancelled: cancelled)
                  .timeout(const Duration(seconds: 15));
              if (!_isCurrent(request)) return;
              await session
                  .open(media, startAt: initialPosition)
                  .timeout(const Duration(seconds: 8));
              if (!_isCurrent(request)) return;
              if (!_pageActive) await session.setPlaying(false);
              if (!_isCurrent(request)) return;
              _playbackOpened(session, episodeSource);
              return;
            } on Object catch (err) {
              lineProblem = err;
            }
          }
          throw lineProblem ?? StateError('线路不可用');
        } on Object catch (error) {
          problem = error;
          final probe = _probes[id];
          if (probe?.state == RuleProbeState.captchaRequired) {
            captchaProbe = probe;
          }
        }
      }

      if (captchaProbe != null && captchaProbe.verifyUrl != null) {
        if (!_isCurrent(request)) return;
        setState(() {
          _loading = false;
          _loadingHint = null;
          _error = '${captchaProbe!.ruleName} 需要验证';
          _errorVerifyUrl = captchaProbe.verifyUrl;
          _errorVerifyHint = captchaProbe.verifyHint;
          _errorVerifyRuleId = captchaProbe.ruleId;
          _errorVerifyRuleName = captchaProbe.ruleName;
        });
        return;
      }

      if (hasPreferred) {
        final preferredName =
            rules.where((r) => r.id == ids.first).firstOrNull?.name ??
            (_ruleName.isNotEmpty ? _ruleName : ids.first);
        throw StateError('「$preferredName」暂时不可用');
      }
      throw problem ?? StateError('暂无可用播放源');
    } on Object catch (error) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _loadingHint = null;
        _error = featureError(error, '无法播放');
      });
    }
  }

  Future<void> _autoSelectFastestPlayable({
    required int request,
    required int episode,
    required Duration initialPosition,
    required AnimeSubject subject,
    required List<RulePluginMeta> rules,
    required PlaybackSources resolver,
    required PlaybackSession session,
    required Future<void> cancelled,
    String? excludeRuleId,
  }) async {
    final alternatives = rules.where((r) => r.id != excludeRuleId).toList();
    final targetRules = alternatives.isEmpty ? rules : alternatives;
    final generation = _probeGeneration;
    final resolving = <Future<void>>[];
    final preparation = Completer<void>();
    var searching = true;
    RuleProbeResult? captcha;
    final titleKeys = {
      _normTitle(subject.title),
      _normTitle(subject.originalTitle),
    }..remove('');

    bool isSearching() => searching && _isCurrent(request);

    Future<PlayableMedia?> resolveLine(SourceEpisode line) async {
      while (resolving.length >= 3) {
        await Future.any(resolving);
        if (!isSearching()) return null;
      }
      if (!isSearching()) return null;
      final slot = Completer<void>();
      resolving.add(slot.future);
      final abandoned = Completer<void>();
      try {
        return await resolver
            .resolve(
              line,
              cancelled: Future.any([preparation.future, abandoned.future]),
            )
            .timeout(const Duration(seconds: 7));
      } finally {
        abandoned.complete();
        resolving.remove(slot.future);
        slot.complete();
      }
    }

    final selection = await racePlaybackSources<_ResolvedSource>(
      targetRules.map(
        (rule) => (offer) async {
          final cached = _probes[rule.id];
          final probe =
              cached?.state == RuleProbeState.found &&
                  _sourceKeywordController.text.trim().isEmpty
              ? cached!
              : await _probe(resolver, subject, rule);
          if (!isSearching()) return;
          if (generation == _probeGeneration &&
              _sourceKeywordController.text.trim().isEmpty) {
            _probes[rule.id] = probe;
            _bumpSources();
          }
          if (probe.state == RuleProbeState.captchaRequired) {
            if (probe.verifyUrl != null) captcha ??= probe;
            return;
          }
          if (probe.state != RuleProbeState.found) return;

          final exact = probe.hits.where(
            (hit) => titleKeys.contains(_normTitle(hit.title)),
          );
          final hits = exact.isEmpty ? probe.hits.take(1) : exact.take(2);
          for (final hit in hits) {
            if (!isSearching()) return;
            final List<SourceEpisode> options;
            try {
              options = await resolver.loadEpisodesFromHit(rule.id, hit);
            } on Object {
              continue;
            }
            for (final line in options.where(
              (item) => item.number == episode,
            )) {
              if (!isSearching()) return;
              try {
                final media = await resolveLine(line);
                if (media == null || !isSearching()) return;
                final mediaStatus = await resolver
                    .probeMedia(media, cancelled: preparation.future)
                    .timeout(
                      const Duration(seconds: 2),
                      onTimeout: () => MediaProbeStatus.inconclusive,
                    );
                if (!isSearching()) return;
                if (mediaStatus == MediaProbeStatus.invalid) continue;
                final verified = mediaStatus == MediaProbeStatus.reachable;
                offer((
                  options: options,
                  line: line,
                  media: media,
                  hit: hit,
                ), verified: verified);
                if (verified) return;
              } on Object {
                continue;
              }
            }
          }
        },
      ),
      cancelled,
    );
    searching = false;
    preparation.complete();
    if (!_isCurrent(request)) return;

    if (selection == null) {
      if (captcha case final required?) {
        setState(() {
          _loading = false;
          _loadingHint = null;
          _error = '${required.ruleName} 需要验证';
          _errorVerifyUrl = required.verifyUrl;
          _errorVerifyHint = required.verifyHint;
          _errorVerifyRuleId = required.ruleId;
          _errorVerifyRuleName = required.ruleName;
        });
        return;
      }
      throw StateError('暂未找到可播放的线路');
    }
    final line = selection.line;
    setState(() {
      _choices = selection.options;
      _ruleId = line.ruleId;
      _ruleName = line.ruleName;
      _activeHitUrl = selection.hit.sourceUrl;
      _loadingHint = '正在打开 ${line.ruleName}…';
    });
    _bumpSources(immediate: true);
    await session
        .open(selection.media, startAt: initialPosition)
        .timeout(const Duration(seconds: 8));
    if (!_isCurrent(request)) return;
    if (!_pageActive) await session.setPlaying(false);
    if (!_isCurrent(request)) return;
    _playbackOpened(session, line);
  }

  void _checkpoint() {
    if (!_loaded) return;
    final position = _status.position.inSeconds;
    final total = _status.duration.inSeconds;
    if (total <= 0 || position <= 0 || _ruleId.isEmpty) return;
    final complete = _status.completed || position / total >= 0.94;
    if (position == _lastCheckpoint && complete == _lastCompleted) return;
    _lastCheckpoint = position;
    _lastCompleted = complete;
    ref
        .read(historyProvider.notifier)
        .recordProgress(
          subjectId: widget.subjectId,
          episodeNumber: _episode,
          positionSeconds: position,
          durationSeconds: total,
          ruleId: _ruleId,
          ruleName: _ruleName,
          completed: complete,
        );
    if (complete) {
      ref
          .read(libraryProvider.notifier)
          .markEpisodeWatched(
            widget.subjectId,
            _episode,
            _subject?.totalEpisodes ?? 0,
          );
    }
  }

  String _danmakuSummary() {
    var bili = 0;
    var gamer = 0;
    var other = 0;
    for (final item in _danmaku) {
      final s = item.source.toLowerCase();
      if (s.contains('bilibili')) {
        bili++;
      } else if (s.contains('gamer') || s.contains('bahamut')) {
        gamer++;
      } else {
        other++;
      }
    }
    final parts = <String>[
      if (bili > 0) 'B站 $bili',
      if (gamer > 0) '巴哈 $gamer',
      if (other > 0) '弹弹 $other',
    ];
    return parts.isEmpty
        ? '已加载 ${_danmaku.length} 条弹幕'
        : '共 ${_danmaku.length} 条 · ${parts.join(' / ')}';
  }

  Future<void> _loadDanmaku({int? overrideEpisodeId}) async {
    final token = ++_danmakuRequest;
    if (!_showDanmaku) return;
    final subject = _subject;
    final source = ref.read(danmakuProvider);
    if (source == null || (subject == null && overrideEpisodeId == null)) {
      return;
    }
    setState(() {
      _danmakuLoading = true;
      _danmakuError = null;
    });
    try {
      final items = overrideEpisodeId != null
          ? await source.loadByEpisodeId(overrideEpisodeId)
          : await source.load(subject!, _episode);
      if (mounted && token == _danmakuRequest) {
        setState(() {
          _danmaku = items;
          _danmakuLoading = false;
          _danmakuError = items.isEmpty ? '当前话暂未匹配到弹幕，可点击下方手动匹配' : null;
        });
      }
    } on Object catch (error) {
      if (mounted && token == _danmakuRequest) {
        setState(() {
          _danmakuLoading = false;
          _danmakuError = featureError(error, '弹幕加载失败，请重试或手动匹配');
        });
      }
    }
  }

  Widget _buildSheetSearchBar({
    required BuildContext context,
    required TextEditingController controller,
    required String hintText,
    required String actionLabel,
    required bool busy,
    required VoidCallback onSubmit,
    VoidCallback? onClear,
  }) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 20,
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(
            Glyphs.search,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => Row(
                spacing: 4,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autocorrect: false,
                      textInputAction: TextInputAction.search,
                      style: AppTextStyle.subheadline
                          .of(context)
                          .copyWith(color: colorScheme.onSurface),
                      decoration: InputDecoration.collapsed(
                        hintText: hintText,
                        hintStyle: AppTextStyle.subheadline
                            .of(context)
                            .copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.72,
                              ),
                            ),
                      ),
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                  if (value.text.isNotEmpty)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: PressSurface(
                        fill: Colors.transparent,
                        shape: AppShape.full,
                        onPressed: () {
                          controller.clear();
                          onClear?.call();
                        },
                        child: Center(
                          child: GlyphIcon(
                            Glyphs.close,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          KonekoChip(
            label: busy ? '搜索中' : actionLabel,
            height: 32,
            fontSize: 12.5,
            backgroundColor: SurfaceLevel.block.colorOf(colorScheme),
            foregroundColor: busy
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface,
            onPressed: busy ? null : onSubmit,
          ),
        ],
      ),
    );
  }

  Future<void> _openDanmakuSearchSheet() async {
    final source = ref.read(danmakuProvider);
    if (source == null) return;
    final initialQuery = _subject?.title.trim() ?? '';
    final searchController = TextEditingController(text: initialQuery);
    List<DanmakuAnimeMatch> matches = const [];
    DanmakuAnimeMatch? selectedAnime;
    bool searching = false;
    bool autoTriggered = false;
    String? error;

    await showKonekoSheet<void>(
      context: context,
      title: '手动匹配弹幕',
      subtitle: '搜索弹弹Play 番剧并选择对应集数',
      detents: const [0.74, 0.92],
      bodyBuilder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colorScheme = sheetContext.colorScheme;
            Future<void> doSearch() async {
              final q = searchController.text.trim();
              if (q.isEmpty || searching) return;
              setSheetState(() {
                searching = true;
                error = null;
                selectedAnime = null;
              });
              try {
                final res = await source.searchAnimes(q);
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  matches = res;
                  searching = false;
                  if (res.isEmpty) error = '未找到匹配的弹幕番剧，可尝试精简关键词';
                });
              } on Object {
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  searching = false;
                  error = '弹幕库搜索失败，请检查网络后重试';
                });
              }
            }

            if (!autoTriggered && initialQuery.isNotEmpty) {
              autoTriggered = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (sheetContext.mounted) unawaited(doSearch());
              });
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _buildSheetSearchBar(
                    context: sheetContext,
                    controller: searchController,
                    hintText: '输入番剧名称搜索弹幕…',
                    actionLabel: '搜索',
                    busy: searching,
                    onSubmit: () => unawaited(doSearch()),
                  ),
                ),
                if (selectedAnime != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: KonekoCard(
                      corner: 18,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        spacing: 10,
                        children: [
                          KonekoChip(
                            label: '返回列表',
                            height: 28,
                            fontSize: 12,
                            leading: GlyphIcon(
                              Glyphs.backFor(Theme.of(sheetContext).platform),
                              size: 12,
                              color: colorScheme.onSurface,
                            ),
                            backgroundColor: SurfaceLevel.block.colorOf(
                              colorScheme,
                            ),
                            foregroundColor: colorScheme.onSurface,
                            onPressed: () =>
                                setSheetState(() => selectedAnime = null),
                          ),
                          Expanded(
                            child: Text(
                              selectedAnime!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.footnote
                                  .of(sheetContext, emphasized: true)
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: searching
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 10,
                            children: [
                              const ActivityIndicator.page(),
                              Text(
                                '正在检索弹弹Play 弹幕库…',
                                style: AppTextStyle.footnote
                                    .of(sheetContext)
                                    .copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        )
                      : error != null
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: KonekoCard(
                              corner: 22,
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 12,
                                children: [
                                  Text(
                                    error!,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyle.subheadline
                                        .of(sheetContext)
                                        .copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  KonekoChip(
                                    label: '重新搜索',
                                    height: 32,
                                    fontSize: 12.5,
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    onPressed: () => unawaited(doSearch()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : selectedAnime != null
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          children: [
                            KonekoGroup(
                              items: [
                                for (final ep in selectedAnime!.episodes)
                                  DecorationListItem(
                                    title: Text(ep.title),
                                    subtitle: Text('第 ${ep.episodeNumber} 话'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      spacing: 6,
                                      children: [
                                        if (ep.episodeNumber == _episode)
                                          KonekoChip(
                                            label: '当前话',
                                            height: 22,
                                            fontSize: 10.5,
                                            backgroundColor: colorScheme.primary
                                                .withValues(alpha: 0.14),
                                            foregroundColor:
                                                colorScheme.primary,
                                          ),
                                        const GlyphIcon(Glyphs.chevronForward),
                                      ],
                                    ),
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      setState(() => _showDanmaku = true);
                                      unawaited(
                                        _loadDanmaku(
                                          overrideEpisodeId: ep.episodeId,
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ],
                        )
                      : matches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: KonekoCard(
                              corner: 22,
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                '输入番剧名称并点击「搜索」，从弹弹Play 匹配对应番剧与剧集',
                                textAlign: TextAlign.center,
                                style: AppTextStyle.footnote
                                    .of(sheetContext)
                                    .copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          children: [
                            KonekoGroup(
                              items: [
                                for (final anime in matches)
                                  DecorationListItem(
                                    title: Text(anime.title),
                                    subtitle: Text(
                                      '${anime.typeDescription.isNotEmpty ? '${anime.typeDescription} · ' : ''}共 ${anime.episodes.length} 集',
                                    ),
                                    trailing: const GlyphIcon(
                                      Glyphs.chevronForward,
                                    ),
                                    onPressed: () => setSheetState(
                                      () => selectedAnime = anime,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();
  }

  Future<void> _setUpscale(bool enabled) async {
    final session = _session;
    if (session == null) return;
    try {
      await session.setUpscaling(enabled);
      if (mounted) setState(() => _upscale = enabled);
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '当前设备无法启用超分'),
          level: BannerLevel.error,
        );
      }
    }
  }

  Future<void> _download() async {
    final source = _source;
    final subject = _subject;
    final library = ref.read(offlineLibraryProvider);
    if (source == null || subject == null || library == null) return;
    showKonekoBanner(context, '正在准备缓存第 $_episode 话');
    try {
      await library.download(subject, source);
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '未能创建下载任务'),
          level: BannerLevel.error,
        );
      }
    }
  }

  Future<void> _pickCollectionStatus(
    String title,
    CollectionStatus? currentStatus,
  ) async {
    final choice = await showKonekoStatusSheet(
      context: context,
      subjectTitle: title,
      currentStatus: currentStatus,
    );
    if (!mounted || choice == null) return;
    if (choice.remove) {
      ref.read(libraryProvider.notifier).removeSubject(widget.subjectId);
      showKonekoBanner(context, '已移出追番列表');
    } else if (choice.status case final status?) {
      ref.read(libraryProvider.notifier).setStatus(widget.subjectId, status);
      showKonekoBanner(
        context,
        '已标记为「${status.label}」',
        level: BannerLevel.success,
      );
    }
  }

  void _adjustBrightness(double delta) {
    setState(() {
      _brightness = (_brightness + delta).clamp(.15, 1);
      _changingBrightness = true;
    });
    _brightnessTimer?.cancel();
    _brightnessTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) setState(() => _changingBrightness = false);
    });
  }

  void _switchToSources() {
    if (_fullscreen) {
      setState(() {
        _drawer = _DrawerTab.sources;
        _drawerOpen = true;
      });
    } else {
      if (_panelTab != _PanelTab.play) {
        setState(() => _panelTab = _PanelTab.play);
      }
      unawaited(_openSourcesSheet(ref.read(rulesProvider)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.subjectId;
    ref.listen(loadCatalogSubjectProvider(id), (_, _) {});
    if (routeSettled && _panelTab == _PanelTab.play) {
      ref.watch(
        loadCatalogEpisodesProvider(id).select((result) => result.isLoading),
      );
    }
    final catalog = ref.watch(catalogRepositoryProvider);
    final subject = ref.watch(catalogSubjectProvider(id));
    final title = subject?.title ?? widget.offline?.subjectTitle ?? 'Koneko';
    final rules = ref.watch(rulesProvider);
    final collection = ref.watch(
      libraryProvider.select(
        (entries) => entries.where((e) => e.subjectId == id).firstOrNull,
      ),
    );
    final session = _session;
    final viewport = ref.watch(videoViewportProvider);
    final overlay = ref.watch(danmakuViewportProvider);
    final danmakuSettings = ref.watch(danmakuSettingsProvider);
    final offline = widget.offline != null;
    final videoStage = ValueListenableBuilder<PlaybackStatus>(
      valueListenable: _playbackStatus,
      child: RepaintBoundary(
        key: _viewportKey,
        child: session != null && viewport != null
            ? IgnorePointer(child: viewport(session))
            : subject != null
            ? Opacity(opacity: .35, child: KonekoPosterArt(subject: subject))
            : const SizedBox.expand(),
      ),
      builder: (context, status, picture) {
        final error =
            _error ??
            (_loaded &&
                    status.error != null &&
                    (status.duration == Duration.zero ||
                        _positionAtOpen != null)
                ? '播放失败'
                : _bufferDelayed
                ? '缓冲时间较长'
                : null);
        return _buildVideoStage(
          context: context,
          title: title,
          rules: rules,
          session: session,
          picture: picture!,
          overlay: overlay,
          danmakuSettings: danmakuSettings,
          status: status,
          error: error,
          offline: offline,
        );
      },
    );

    return PopScope<void>(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) {
          unawaited(_setFullscreen(false));
          return;
        }
        if (didPop) _checkpoint();
      },
      child: _fullscreen
          ? ColoredBox(
              color: Colors.black,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final safe = MediaQuery.paddingOf(context);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      videoStage,
                      AnimatedPositioned(
                        duration: context.motionDuration(
                          const Duration(milliseconds: 230),
                        ),
                        curve: Curves.easeOutCubic,
                        top: safe.top + 12,
                        bottom: safe.bottom + 12,
                        right: _drawerOpen ? safe.right + 12 : -360,
                        width: math.min(
                          330,
                          MediaQuery.sizeOf(context).width - 24,
                        ),
                        child: ExcludeFocus(
                          excluding: !_drawerOpen,
                          child: IgnorePointer(
                            ignoring: !_drawerOpen,
                            child: _buildDrawer(context, rules, offline),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final colorScheme = context.colorScheme;
                final pageBg = SurfaceLevel.page.colorOf(colorScheme);
                final safe = MediaQuery.paddingOf(context);
                final isWide = constraints.maxWidth >= 840;

                final panel = _buildSideOrBottomPanel(
                  context: context,
                  catalog: catalog,
                  title: title,
                  collection: collection,
                  rules: rules,
                  offline: offline,
                  bottomPadding: safe.bottom + 20,
                );

                if (isWide) {
                  return SurfaceScope(
                    level: SurfaceLevel.page,
                    child: ColoredBox(
                      color: pageBg,
                      child: Row(
                        children: [
                          Expanded(
                            child: ColoredBox(
                              color: Colors.black,
                              child: SafeArea(right: false, child: videoStage),
                            ),
                          ),
                          Container(
                            width: 1,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.25,
                            ),
                          ),
                          SizedBox(
                            width: math.min(380, constraints.maxWidth * 0.34),
                            child: SafeArea(
                              left: false,
                              bottom: false,
                              child: panel,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Portrait split layout: crisp 16:9 video on top, tabs below.
                return SurfaceScope(
                  level: SurfaceLevel.page,
                  child: ColoredBox(
                    color: pageBg,
                    child: Column(
                      children: [
                        ColoredBox(
                          color: Colors.black,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: safe.top),
                              AspectRatio(
                                aspectRatio: 16 / 9,
                                child: videoStage,
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: panel),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildVideoStage({
    required BuildContext context,
    required String title,
    required List<RulePluginMeta> rules,
    required PlaybackSession? session,
    required Widget picture,
    required Widget Function(
      List<DanmakuItem>,
      PlaybackStatus,
      DanmakuSettings,
    )?
    overlay,
    required DanmakuSettings danmakuSettings,
    required PlaybackStatus status,
    required String? error,
    required bool offline,
  }) {
    final safe = _fullscreen ? MediaQuery.paddingOf(context) : EdgeInsets.zero;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleHud,
          onDoubleTap: !_loaded
              ? null
              : () => session?.setPlaying(!status.playing),
          onVerticalDragUpdate: _fullscreen
              ? (event) => _adjustBrightness(-event.delta.dy * .004)
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              picture,
              if (_brightness < 1)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 1 - _brightness),
                  ),
                ),
              if (_showDanmaku && _danmaku.isNotEmpty && overlay != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: overlay(_danmaku, status, danmakuSettings),
                  ),
                ),
            ],
          ),
        ),
        // Centered frosted play button when paused and HUD is visible
        if (error == null &&
            !_loading &&
            !_waitingForPlayback &&
            _loaded &&
            !status.playing &&
            _scrub == null)
          Center(
            child: IgnorePointer(
              ignoring: !_showHud,
              child: AnimatedOpacity(
                opacity: _showHud ? 1.0 : 0.0,
                duration: context.motionDuration(
                  const Duration(milliseconds: 180),
                ),
                curve: Curves.easeOutCubic,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: PressSurface(
                    fill: Colors.black.withValues(alpha: 0.50),
                    shape: SuperellipseBorder(
                      borderRadius: AppRadius.all(99),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 1,
                      ),
                    ),
                    onPressed: () {
                      session?.setPlaying(true);
                      _armHudAutoHide();
                    },
                    child: const Center(
                      child: GlyphIcon(
                        KonekoGlyphs.play,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (error == null && (_loading || _waitingForPlayback))
          Center(
            child: _HudSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 24,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: ActivityIndicator.page(color: Colors.white),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      (_loading && (_loadingHint?.isNotEmpty ?? false))
                          ? _loadingHint!
                          : '正在缓冲…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(context, small: true),
                    ),
                  ),
                  if (!offline && rules.any((rule) => rule.enabled)) ...[
                    Container(
                      width: 1,
                      height: 12,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                    PressSurface(
                      fill: Colors.transparent,
                      shape: AppShape.full,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      onPressed: _switchToSources,
                      child: Text(
                        '换源',
                        style: _style(context, small: true).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _HudSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _style(context, small: !_fullscreen),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_bufferDelayed &&
                            _error == null &&
                            status.error == null)
                          _HudAction(
                            label: '继续等待',
                            onTap: _continueWaiting,
                          ),
                        if (_errorVerifyUrl != null &&
                            _errorVerifyRuleId != null)
                          _HudAction(
                            label: '去验证',
                            prominent: true,
                            onTap: () => _verifyRule(
                              _errorVerifyRuleId!,
                              _errorVerifyRuleName ?? _errorVerifyRuleId!,
                              _errorVerifyUrl!,
                              verifyHint: _errorVerifyHint,
                            ),
                          ),
                        _HudAction(
                          label: '重试',
                          onTap: () {
                            if (widget.offline?.media case final uri?) {
                              unawaited(_startOffline(uri));
                            } else {
                              unawaited(
                                _openEpisode(
                                  _episode,
                                  ruleId: _ruleId.isEmpty ? null : _ruleId,
                                  strictPreferredRule: _ruleId.isNotEmpty,
                                  autoSelectFastest: _ruleId.isEmpty,
                                ),
                              );
                            }
                          },
                        ),
                        if (!offline && rules.any((rule) => rule.enabled))
                          _HudAction(
                            label: '自动选择',
                            prominent: _errorVerifyUrl == null,
                            onTap: () => _openEpisode(
                              _episode,
                              autoSelectFastest: true,
                              excludeRuleId: _ruleId.isEmpty ? null : _ruleId,
                            ),
                          ),
                        if (!offline)
                          _HudAction(
                            label: rules.any((rule) => rule.enabled)
                                ? '手动切换源'
                                : '添加规则',
                            onTap: () async {
                              if (rules.any((rule) => rule.enabled)) {
                                _switchToSources();
                              } else {
                                await BaseNavigator.push<void>(
                                  context,
                                  const RulesPage(showBack: true),
                                );
                                if (mounted) await _start();
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_changingBrightness)
          Positioned(
            top: safe.top + (_fullscreen ? 64 : 40),
            left: 16,
            right: 16,
            child: Center(
              child: _HudSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 10,
                  children: [
                    Text(
                      '亮度',
                      style: _style(context, small: true).copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    SizedBox(
                      width: 82,
                      height: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: 0.22),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: _brightness.clamp(0.0, 1.0),
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '${(_brightness * 100).round()}%',
                      style: _style(context, small: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_scrub != null && status.duration.inSeconds > 0)
          Center(
            child: _HudSurface(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 3,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: formatDurationShort(_scrub!.round()),
                          style: AppTextStyle.title3
                              .of(context, emphasized: true)
                              .copyWith(
                                color: Colors.white,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        TextSpan(
                          text:
                              '  /  ${formatDurationShort(status.duration.inSeconds)}',
                          style: AppTextStyle.footnote
                              .of(context)
                              .copyWith(
                                color: Colors.white.withValues(alpha: 0.60),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (_scrubStart != null)
                    Builder(
                      builder: (context) {
                        final delta = (_scrub! - _scrubStart!).round();
                        if (delta == 0) return const SizedBox.shrink();
                        final sign = delta > 0 ? '+' : '-';
                        return Text(
                          '$sign${formatDurationShort(delta.abs())}',
                          style: AppTextStyle.caption1
                              .of(context, emphasized: true)
                              .copyWith(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        // Top HUD bar — pure borderless white cinema iconography over smooth vignette
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_showHud,
            child: AnimatedOpacity(
              opacity: _showHud ? 1.0 : 0.0,
              duration: context.motionDuration(
                const Duration(milliseconds: 180),
              ),
              curve: Curves.easeOutCubic,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  safe.left + (_fullscreen ? 12 : 4),
                  safe.top + (_fullscreen ? 8 : 4),
                  safe.right + (_fullscreen ? 12 : 4),
                  _fullscreen ? 26 : 18,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.52, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.black.withValues(alpha: 0.24),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  spacing: 2,
                  children: [
                    _bareIcon(
                      glyph: Glyphs.backFor(Theme.of(context).platform),
                      tooltip: _fullscreen ? '退出全屏' : '返回',
                      size: _fullscreen ? 21 : 19,
                      onPressed: () {
                        if (_fullscreen) {
                          unawaited(_setFullscreen(false));
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: title,
                                    style: _style(
                                      context,
                                      small: !_fullscreen,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '  第 $_episode 话',
                                    style: _style(context, small: true)
                                        .copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.70,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_fullscreen && !offline && _ruleName.isNotEmpty)
                              Text(
                                _source != null
                                    ? '$_ruleName · ${_source!.line}'
                                    : _ruleName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _style(context, small: true).copyWith(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.56),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_fullscreen)
                      _bareIcon(
                        glyph: KonekoGlyphs.layers,
                        tooltip: '选集与播放源',
                        size: 20,
                        onPressed: () =>
                            setState(() => _drawerOpen = !_drawerOpen),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Bottom HUD bar with smooth fade and cinema scrubber
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !_showHud,
            child: AnimatedOpacity(
              opacity: _showHud ? 1.0 : 0.0,
              duration: context.motionDuration(
                const Duration(milliseconds: 180),
              ),
              curve: Curves.easeOutCubic,
              child: _controls(context, status, session, offline, safe),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSideOrBottomPanel({
    required BuildContext context,
    required CatalogRepository catalog,
    required String title,
    required CollectionEntry? collection,
    required List<RulePluginMeta> rules,
    required bool offline,
    required double bottomPadding,
  }) {
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.headline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      offline
                          ? '正在播放离线缓存 · 第 $_episode 话'
                          : '第 $_episode 话 · ${_ruleName.isEmpty ? '匹配线路中' : _ruleName}${_source != null ? ' · ${_source!.line}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              KonekoChip(
                label: collection?.status.label ?? '追番',
                height: 32,
                fontSize: 12,
                leading: collection != null
                    ? GlyphIcon(
                        konekoStatusGlyph(collection.status),
                        size: 13,
                        fill: 1,
                        color: konekoStatusColor(collection.status),
                      )
                    : GlyphIcon(
                        KonekoGlyphs.bookmark,
                        size: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                backgroundColor: collection != null
                    ? konekoStatusColor(
                        collection.status,
                      ).withValues(alpha: 0.14)
                    : SurfaceLevel.card.colorOf(colorScheme),
                foregroundColor: collection != null
                    ? konekoStatusColor(collection.status)
                    : colorScheme.onSurface,
                trailing: GlyphIcon(
                  Glyphs.chevronDown,
                  size: 12,
                  color: collection != null
                      ? konekoStatusColor(collection.status)
                      : colorScheme.onSurfaceVariant,
                ),
                onPressed: () =>
                    _pickCollectionStatus(title, collection?.status),
              ),
              if (!offline)
                KonekoCircleButton(
                  size: 34,
                  iconSize: 15,
                  glyph: KonekoGlyphs.importFile,
                  tooltip: '离线缓存当前话',
                  onPressed: _loaded && _source != null ? _download : null,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: KonekoSegmentedBar<_PanelTab>(
            segments: const [
              (_PanelTab.play, '选集'),
              (_PanelTab.comments, '评论'),
            ],
            value: _panelTab,
            onChanged: (tab) => setState(() => _panelTab = tab),
          ),
        ),
        Expanded(
          child: switch (_panelTab) {
            _PanelTab.play => _buildPlayPanel(
              context: context,
              catalog: catalog,
              collection: collection,
              rules: rules,
              offline: offline,
              bottomPadding: bottomPadding,
            ),
            _PanelTab.comments => KonekoCommentsPanel(
              subjectId: widget.subjectId,
              embedded: true,
              bottomPadding: bottomPadding,
            ),
          },
        ),
      ],
    );
  }

  List<RulePluginMeta> _prioritizedRules(List<RulePluginMeta> enabledRules) {
    final sorted = List<RulePluginMeta>.of(enabledRules);
    int rankOf(RulePluginMeta rule) {
      if (rule.id == _ruleId) return 0;
      return switch (_probes[rule.id]?.state) {
        RuleProbeState.found => 1,
        RuleProbeState.searching => 2,
        RuleProbeState.captchaRequired => 3,
        RuleProbeState.noResult => 4,
        RuleProbeState.error => 5,
        null => 2,
      };
    }

    sorted.sort((a, b) {
      final r = rankOf(a).compareTo(rankOf(b));
      if (r != 0) return r;
      final la = _probes[a.id]?.latencyMs ?? 99999;
      final lb = _probes[b.id]?.latencyMs ?? 99999;
      return la.compareTo(lb);
    });
    return sorted;
  }

  Future<void> _openSourcesSheet(List<RulePluginMeta> rules) async {
    await showKonekoSheet<void>(
      context: context,
      title: '切换播放源',
      subtitle: _ruleName.isEmpty ? '选择可用线路或自定义搜索' : '当前：$_ruleName',
      detents: const [0.78, 0.94],
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.refresh,
          tooltip: '重新检索',
          onPressed: () => unawaited(
            _probeAllEnabledRules(
              customKeyword: _sourceKeywordController.text.trim().isEmpty
                  ? null
                  : _sourceKeywordController.text.trim(),
              forceRefresh: true,
            ),
          ),
        ),
      ],
      bodyBuilder: (sheetContext) {
        return ListenableBuilder(
          listenable: _sourcesRevision,
          builder: (sheetContext, _) {
            final colorScheme = sheetContext.colorScheme;
            final enabledRules = _prioritizedRules(
              rules.where((r) => r.enabled).toList(),
            );
            final lines = _choices
                .where((item) => item.number == _episode)
                .toList();
            final foundCount = enabledRules
                .where((r) => _probes[r.id]?.state == RuleProbeState.found)
                .length;
            final doneCount = enabledRules.where((r) {
              final state = _probes[r.id]?.state;
              return state != null && state != RuleProbeState.searching;
            }).length;
            final anySearching = enabledRules.any(
              (r) => _probes[r.id]?.state == RuleProbeState.searching,
            );

            void runKeywordProbe() {
              final kw = _sourceKeywordController.text.trim();
              unawaited(
                _probeAllEnabledRules(
                  customKeyword: kw.isEmpty ? null : kw,
                  forceRefresh: true,
                ),
              );
            }

            return ArrivalCacheExtentBuilder(
              builder: (context, cacheExtent) => CustomScrollView(
                scrollCacheExtent: cacheExtent,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: _buildSheetSearchBar(
                        context: sheetContext,
                        controller: _sourceKeywordController,
                        hintText: '自定义搜索词（默认：${_subject?.title ?? ''}）',
                        actionLabel: '检索',
                        busy: false,
                        onSubmit: runKeywordProbe,
                        onClear: runKeywordProbe,
                      ),
                    ),
                  ),
                  if (enabledRules.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: KonekoCard(
                          corner: 22,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            spacing: 10,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: ShapeDecoration(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: SuperellipseBorder(
                                    borderRadius: AppRadius.all(10),
                                  ),
                                ),
                                child: Center(
                                  child: anySearching
                                      ? const SizedBox(
                                          width: 15,
                                          height: 15,
                                          child: ActivityIndicator(),
                                        )
                                      : GlyphIcon(
                                          KonekoGlyphs.puzzle,
                                          size: 15,
                                          color: colorScheme.primary,
                                        ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      anySearching
                                          ? '正在并发检测播放源 ($doneCount/${enabledRules.length})'
                                          : doneCount > 0
                                          ? '共 ${enabledRules.length} 个播放源 · $foundCount 个可用'
                                          : '共 ${enabledRules.length} 个已启用播放源',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyle.footnote
                                          .of(sheetContext, emphasized: true)
                                          .copyWith(
                                            color: colorScheme.onSurface,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _ruleName.isEmpty
                                          ? '点击任意结果即可立即切换播放'
                                          : '当前：$_ruleName${_source != null ? ' · ${_source!.line}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyle.caption1
                                          .of(sheetContext)
                                          .copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              KonekoChip(
                                label: '自动优选',
                                height: 30,
                                fontSize: 12,
                                leading: GlyphIcon(
                                  KonekoGlyphs.speed,
                                  size: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                backgroundColor: SurfaceLevel.block.colorOf(
                                  colorScheme,
                                ),
                                foregroundColor: colorScheme.onSurface,
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  unawaited(
                                    _openEpisode(
                                      _episode,
                                      autoSelectFastest: true,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (lines.length > 1)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: KonekoCard(
                          corner: 22,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 10,
                            children: [
                              Text(
                                _ruleName.isNotEmpty
                                    ? '当前源线路 · $_ruleName'
                                    : '当前源线路',
                                style: AppTextStyle.footnote
                                    .of(sheetContext, emphasized: true)
                                    .copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final line in lines)
                                    KonekoChip(
                                      label: line.line,
                                      height: 32,
                                      fontSize: 12.5,
                                      selected:
                                          line.line == _source?.line &&
                                          line.page == _source?.page,
                                      backgroundColor:
                                          line.line == _source?.line &&
                                              line.page == _source?.page
                                          ? colorScheme.primary
                                          : SurfaceLevel.block.colorOf(
                                              colorScheme,
                                            ),
                                      foregroundColor:
                                          line.line == _source?.line &&
                                              line.page == _source?.page
                                          ? colorScheme.onPrimary
                                          : colorScheme.onSurface,
                                      onPressed: () {
                                        Navigator.of(sheetContext).pop();
                                        unawaited(
                                          _openEpisode(
                                            _episode,
                                            ruleId: line.ruleId,
                                            choice: line,
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (enabledRules.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      sliver: SliverToBoxAdapter(
                        child: KonekoCard(
                          corner: 24,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 12,
                            children: [
                              Text(
                                '暂未启用任何播放规则',
                                style: AppTextStyle.subheadline
                                    .of(sheetContext, emphasized: true)
                                    .copyWith(color: colorScheme.onSurface),
                              ),
                              KonekoChip(
                                label: '添加播放规则',
                                height: 34,
                                fontSize: 13,
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                onPressed: () async {
                                  Navigator.of(sheetContext).pop();
                                  await BaseNavigator.push<void>(
                                    context,
                                    const RulesPage(showBack: true),
                                  );
                                  if (mounted) await _start();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: enabledRules.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (itemContext, index) =>
                            _buildRuleProbeCard(
                              itemContext,
                              enabledRules[index],
                              onDismissSheet: () {
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                            ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlayPanel({
    required BuildContext context,
    required CatalogRepository catalog,
    required CollectionEntry? collection,
    required List<RulePluginMeta> rules,
    required bool offline,
    required double bottomPadding,
  }) {
    final colorScheme = context.colorScheme;
    final lines = _choices.where((item) => item.number == _episode).toList();

    final sourceEpNums = <int>{
      for (final item in _choices) item.number,
    }.toList()..sort();
    final catalogEps = catalog.getEpisodes(
      widget.subjectId,
      watchedCount: collection?.watchedEpisodes ?? 0,
      currentEp: _episode,
    );
    final epNumbers = sourceEpNums.isNotEmpty
        ? sourceEpNums
        : [for (final e in catalogEps) e.episodeNumber];

    final totalPages = epNumbers.isEmpty
        ? 1
        : (epNumbers.length + _pageSize - 1) ~/ _pageSize;
    final safePage = _epPageIndex.clamp(0, math.max(0, totalPages - 1)).toInt();
    final visibleEps = epNumbers
        .skip(safePage * _pageSize)
        .take(_pageSize)
        .toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 2, 16, bottomPadding + 12),
      children: [
        // 1. Sleek, airy Danmaku card on top
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: 10,
                children: [
                  KonekoPolygonBadge(
                    glyph: KonekoGlyphs.danmaku,
                    shape: KonekoPolygons.flower,
                    size: 36,
                    iconSize: 16,
                    backgroundColor: colorScheme.primary.withValues(
                      alpha: 0.13,
                    ),
                    foregroundColor: colorScheme.primary,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '弹幕',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.headline
                              .of(context, emphasized: true)
                              .copyWith(color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _danmakuLoading
                              ? '正在拉取弹幕…'
                              : _danmakuError ??
                                    (_showDanmaku
                                        ? (_danmaku.isNotEmpty
                                              ? _danmakuSummary()
                                              : '暂无弹幕')
                                        : '弹幕已关闭'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  KonekoDanmakuSwitch(
                    value: _showDanmaku,
                    onChanged: (value) {
                      setState(() => _showDanmaku = value);
                      if (value) unawaited(_loadDanmaku());
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                spacing: 10,
                children: [
                  Expanded(
                    child: _buildDanmakuActionTile(
                      context: context,
                      glyph: KonekoGlyphs.tune,
                      label: '弹幕设置',
                      onPressed: () =>
                          unawaited(openKonekoDanmakuSettingsPage(context)),
                    ),
                  ),
                  Expanded(
                    child: _buildDanmakuActionTile(
                      context: context,
                      glyph: Glyphs.search,
                      label: '手动匹配',
                      onPressed: _openDanmakuSearchSheet,
                    ),
                  ),
                  Expanded(
                    child: _buildDanmakuActionTile(
                      context: context,
                      glyph: KonekoGlyphs.refresh,
                      icon: KonekoSpinningRefreshIcon(
                        spinning: _danmakuLoading,
                        size: 13.5,
                        color: _danmakuLoading
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      label: _danmakuLoading ? '拉取中' : '重新拉取',
                      onPressed: _danmakuLoading
                          ? null
                          : () => unawaited(_loadDanmaku()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 2. Episodes card (spacious primary section)
        KonekoCard(
          corner: 26,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: 10,
                children: [
                  KonekoPolygonBadge(
                    glyph: KonekoGlyphs.layers,
                    shape: KonekoPolygons.gem,
                    size: 36,
                    iconSize: 16,
                    backgroundColor: colorScheme.primary.withValues(
                      alpha: 0.13,
                    ),
                    foregroundColor: colorScheme.primary,
                  ),
                  Expanded(
                    child: Text(
                      '选集',
                      style: AppTextStyle.headline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                  if (totalPages > 1)
                    KonekoPopupTrigger<int>(
                      options: [for (var idx = 0; idx < totalPages; idx++) idx],
                      value: safePage,
                      textBuilder: (idx) =>
                          '${idx * _pageSize + 1}-${((idx + 1) * _pageSize).clamp(1, epNumbers.length)} 话',
                      onChanged: (idx) => setState(() => _epPageIndex = idx),
                    )
                  else
                    Text(
                      epNumbers.isEmpty ? '匹配中' : '共 ${epNumbers.length} 话',
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
              if (!offline && lines.length > 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final line = lines[index];
                      final selected =
                          line.line == _source?.line &&
                          line.page == _source?.page;
                      return KonekoChip(
                        label: line.line,
                        height: 30,
                        fontSize: 12,
                        selected: selected,
                        backgroundColor: selected
                            ? colorScheme.primary
                            : SurfaceLevel.block.colorOf(colorScheme),
                        foregroundColor: selected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                        onPressed: () => unawaited(
                          _openEpisode(
                            _episode,
                            ruleId: line.ruleId,
                            choice: line,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (visibleEps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      offline ? '正在播放离线缓存的第 $_episode 话' : '匹配规则后将自动显示可选剧集',
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final number in visibleEps)
                      _EpisodeChipButton(
                        number: number,
                        current: number == _episode,
                        watched:
                            (collection?.watchedEpisodes ?? 0) >= number &&
                            number != _episode,
                        onPressed: offline
                            ? null
                            : () => unawaited(
                                _openEpisode(
                                  number,
                                  ruleId: _ruleId.isEmpty ? null : _ruleId,
                                  autoSelectFastest:
                                      _ruleId.isEmpty ||
                                      (_error != null && !_loaded),
                                ),
                              ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (!offline) ...[
          const SizedBox(height: 14),
          // 3. Live Playback Sources card (scoped ValueListenableBuilder avoids full-page churn)
          ListenableBuilder(
            listenable: _sourcesRevision,
            builder: (context, _) {
              final enabledRules = _prioritizedRules(
                rules.where((r) => r.enabled).toList(),
              );
              return KonekoCard(
                corner: 26,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      spacing: 10,
                      children: [
                        KonekoPolygonBadge(
                          glyph: KonekoGlyphs.puzzle,
                          shape: KonekoPolygons.clover4Leaf,
                          size: 36,
                          iconSize: 16,
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.13,
                          ),
                          foregroundColor: colorScheme.primary,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '播放源',
                                style: AppTextStyle.headline
                                    .of(context, emphasized: true)
                                    .copyWith(color: colorScheme.onSurface),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _ruleName.isEmpty
                                    ? '自动匹配最快线路'
                                    : '当前：$_ruleName${_source != null ? ' · ${_source!.line}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.caption1
                                    .of(context)
                                    .copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        KonekoChip(
                          label: '全部 / 搜索',
                          height: 30,
                          fontSize: 12,
                          backgroundColor: SurfaceLevel.block.colorOf(
                            colorScheme,
                          ),
                          foregroundColor: colorScheme.onSurface,
                          onPressed: () => unawaited(_openSourcesSheet(rules)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (enabledRules.isEmpty)
                      Center(
                        child: KonekoChip(
                          label: '添加播放规则',
                          height: 34,
                          fontSize: 13,
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          onPressed: () async {
                            await BaseNavigator.push<void>(
                              context,
                              const RulesPage(showBack: true),
                            );
                            if (mounted) await _start();
                          },
                        ),
                      )
                    else ...[
                      Column(
                        spacing: 10,
                        children: [
                          for (final rule in enabledRules.take(4))
                            _buildCompactSourceRow(context, rule),
                        ],
                      ),
                      if (enabledRules.length > 4) ...[
                        const SizedBox(height: 10),
                        PressSurface(
                          fill: SurfaceLevel.block.colorOf(colorScheme),
                          shape: SuperellipseBorder(
                            borderRadius: AppRadius.all(14),
                          ),
                          clipsChild: true,
                          onPressed: () => unawaited(_openSourcesSheet(rules)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: Text(
                                '查看全部 ${enabledRules.length} 个播放源与自定义搜索',
                                style: AppTextStyle.footnote
                                    .of(context, emphasized: true)
                                    .copyWith(color: colorScheme.primary),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDanmakuActionTile({
    required BuildContext context,
    required Glyph glyph,
    Widget? icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = context.colorScheme;
    final fg = onPressed == null
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
        : colorScheme.onSurface;
    return PressSurface(
      fill: SurfaceLevel.block.colorOf(colorScheme),
      shape: SuperellipseBorder(borderRadius: AppRadius.all(14)),
      clipsChild: true,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 5,
          children: [
            icon ??
                GlyphIcon(
                  glyph,
                  size: 13.5,
                  color: onPressed == null
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
                      : colorScheme.onSurfaceVariant,
                ),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactSourceRow(BuildContext context, RulePluginMeta rule) {
    final colorScheme = context.colorScheme;
    final probe = _probes[rule.id];
    final state = probe?.state;
    final isCurrent = _ruleId == rule.id;

    final (badgeText, badgeBg, badgeFg) = switch (state) {
      RuleProbeState.searching => (
        '检测中',
        SurfaceLevel.card.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
      RuleProbeState.found => (
        probe!.latencyMs > 0
            ? '${probe.latencyMs}ms'
            : '${probe.hits.length} 条',
        colorScheme.successContainer,
        colorScheme.onSuccessContainer,
      ),
      RuleProbeState.noResult => (
        '无结果',
        SurfaceLevel.card.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
      RuleProbeState.captchaRequired => (
        '需验证',
        colorScheme.warningContainer,
        colorScheme.onWarningContainer,
      ),
      RuleProbeState.error => (
        '不可用',
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      null => (
        '待检测',
        SurfaceLevel.card.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
    };

    return KonekoSourceSurface(
      selected: isCurrent,
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      onPressed: () {
        if (state == RuleProbeState.captchaRequired &&
            probe?.verifyUrl != null) {
          unawaited(
            _verifyRule(
              rule.id,
              rule.name,
              probe!.verifyUrl!,
              verifyHint: probe.verifyHint,
            ),
          );
        } else if (state == RuleProbeState.found &&
            probe != null &&
            probe.hits.isNotEmpty) {
          unawaited(_openHit(rule.id, rule.name, probe.hits.first));
        } else {
          unawaited(_openEpisode(_episode, ruleId: rule.id));
        }
      },
      child: Row(
        spacing: 10,
        children: [
          if (isCurrent) const KonekoSourceCheckBadge(),
          Expanded(
            child: Text(
              rule.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline
                  .of(context, emphasized: true)
                  .copyWith(
                    color: isCurrent
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
            ),
          ),
          if (isCurrent)
            KonekoChip(
              label: '当前',
              height: 20,
              fontSize: 10,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              foregroundColor: colorScheme.primary,
            ),
          KonekoChip(
            label: badgeText,
            height: 22,
            fontSize: 10.5,
            backgroundColor: badgeBg,
            foregroundColor: badgeFg,
          ),
        ],
      ),
    );
  }

  Widget _buildRuleProbeCard(
    BuildContext context,
    RulePluginMeta rule, {
    VoidCallback? onDismissSheet,
  }) {
    final colorScheme = context.colorScheme;
    final probe = _probes[rule.id];
    final state = probe?.state;
    final isCurrent = _ruleId == rule.id;

    final (badgeText, badgeBg, badgeFg) = switch (state) {
      RuleProbeState.searching => (
        '检测中',
        SurfaceLevel.block.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
      RuleProbeState.found => (
        probe!.latencyMs > 0
            ? '${probe.latencyMs}ms · ${probe.hits.length} 条'
            : '${probe.hits.length} 条',
        colorScheme.successContainer,
        colorScheme.onSuccessContainer,
      ),
      RuleProbeState.noResult => (
        '无结果',
        SurfaceLevel.block.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
      RuleProbeState.captchaRequired => (
        '需验证',
        colorScheme.warningContainer,
        colorScheme.onWarningContainer,
      ),
      RuleProbeState.error => (
        '不可用',
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      null => (
        '待检测',
        SurfaceLevel.block.colorOf(colorScheme),
        colorScheme.onSurfaceVariant,
      ),
    };

    void handleSelectRule() {
      if (state == RuleProbeState.captchaRequired && probe?.verifyUrl != null) {
        onDismissSheet?.call();
        unawaited(
          _verifyRule(
            rule.id,
            rule.name,
            probe!.verifyUrl!,
            verifyHint: probe.verifyHint,
          ),
        );
      } else if (state == RuleProbeState.found &&
          probe != null &&
          probe.hits.isNotEmpty) {
        onDismissSheet?.call();
        unawaited(_openHit(rule.id, rule.name, probe.hits.first));
      } else {
        onDismissSheet?.call();
        unawaited(_openEpisode(_episode, ruleId: rule.id));
      }
    }

    return KonekoSourceSurface(
      selected: isCurrent,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          PressSurface(
            fill: Colors.transparent,
            shape: AppShape.sm,
            onPressed: handleSelectRule,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                spacing: 10,
                children: [
                  if (isCurrent) const KonekoSourceCheckBadge(),
                  Expanded(
                    child: Text(
                      rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.subheadline
                          .of(context, emphasized: true)
                          .copyWith(
                            color: isCurrent
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                    ),
                  ),
                  if (isCurrent)
                    KonekoChip(
                      label: '当前',
                      height: 20,
                      fontSize: 10,
                      backgroundColor: colorScheme.primary.withValues(
                        alpha: 0.12,
                      ),
                      foregroundColor: colorScheme.primary,
                    ),
                  KonekoChip(
                    label: badgeText,
                    height: 22,
                    fontSize: 10.5,
                    backgroundColor: badgeBg,
                    foregroundColor: badgeFg,
                  ),
                ],
              ),
            ),
          ),
          if (state == RuleProbeState.found && probe != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hit in probe.hits.take(6))
                  KonekoChip(
                    label: hit.title,
                    height: 30,
                    fontSize: 12,
                    selected: isCurrent && _activeHitUrl == hit.sourceUrl,
                    backgroundColor: isCurrent && _activeHitUrl == hit.sourceUrl
                        ? colorScheme.primary
                        : SurfaceLevel.block.colorOf(colorScheme),
                    foregroundColor: isCurrent && _activeHitUrl == hit.sourceUrl
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    onPressed: () {
                      onDismissSheet?.call();
                      unawaited(_openHit(rule.id, rule.name, hit));
                    },
                  ),
              ],
            )
          else if (state == RuleProbeState.captchaRequired &&
              probe?.verifyUrl != null)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    probe!.message,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                KonekoChip(
                  label: '去验证',
                  height: 28,
                  fontSize: 12,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  onPressed: () {
                    onDismissSheet?.call();
                    unawaited(
                      _verifyRule(
                        rule.id,
                        rule.name,
                        probe.verifyUrl!,
                        verifyHint: probe.verifyHint,
                      ),
                    );
                  },
                ),
              ],
            )
          else if ((state == RuleProbeState.error ||
                  state == RuleProbeState.noResult) &&
              (probe?.message.isNotEmpty ?? false))
            Text(
              probe!.message,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    PlaybackStatus status,
    PlaybackSession? session,
    bool offline,
    EdgeInsets safe,
  ) {
    final duration = status.duration.inSeconds;
    final position = status.position.inSeconds;
    final max = math.max(1, duration).toDouble();
    final value = (_scrub ?? position.toDouble()).clamp(0.0, max);
    final progress = duration > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    final canAdvance = _choices.any(
      (episode) => episode.number == _episode + 1,
    );

    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    void selectSpeed(double next) {
      setState(() => _speed = next);
      unawaited(session?.setRate(next));
      _armHudAutoHide();
    }

    Widget buildSpeedMenu({required String label}) => PopupAnchor(
      targetBuilder: (open) => _HudTextButton(
        label: label,
        active: _speed != 1,
        onTap: !_loaded
            ? null
            : () {
                _hudTimer?.cancel();
                open();
              },
      ),
      popupBuilder: (_) => PopupMenu(
        items: [
          for (final s in speeds)
            PopupMenuItem(
              label: _formatSpeed(s),
              checked: s == _speed,
              onPressed: () => selectSpeed(s),
            ),
        ],
      ),
    );

    final scrubber = _VideoProgressBar(
      progress: progress,
      enabled: duration > 0 && _loaded,
      scrubbing: _scrub != null,
      onScrubStart: (ratio) {
        _hudTimer?.cancel();
        setState(() {
          _scrubStart = position.toDouble();
          _scrub = ratio * max;
        });
      },
      onScrubUpdate: (ratio) {
        _hudTimer?.cancel();
        setState(() => _scrub = ratio * max);
      },
      onScrubEnd: (ratio, {required bool cancelled}) {
        setState(() {
          _scrub = null;
          _scrubStart = null;
        });
        if (!cancelled) {
          unawaited(session?.seek(Duration(seconds: (ratio * max).round())));
        }
        _armHudAutoHide();
      },
    );

    // Pure cinema minimal portrait bottom bar
    if (!_fullscreen) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 22, 10, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            stops: const [0.0, 0.56, 1.0],
            colors: [
              Colors.black.withValues(alpha: 0.80),
              Colors.black.withValues(alpha: 0.30),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: scrubber,
            ),
            SizedBox(
              height: 38,
              child: Row(
                children: [
                  _bareIcon(
                    glyph: status.playing
                        ? KonekoGlyphs.pause
                        : KonekoGlyphs.play,
                    tooltip: status.playing ? '暂停' : '播放',
                    size: 20,
                    onPressed: !_loaded
                        ? null
                        : () {
                            session?.setPlaying(!status.playing);
                            _armHudAutoHide();
                          },
                  ),
                  const SizedBox(width: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: formatDurationShort(value.round()),
                          style: _style(context, small: true).copyWith(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: ' / ${formatDurationShort(duration)}',
                          style: _style(context, small: true).copyWith(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.56),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  buildSpeedMenu(label: _formatSpeed(_speed)),
                  _bareIcon(
                    glyph: KonekoGlyphs.fullscreen,
                    tooltip: '全屏播放',
                    size: 19,
                    onPressed: () => unawaited(_setFullscreen(true)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Pure cinema fullscreen transport bar
    return Container(
      padding: EdgeInsets.fromLTRB(
        safe.left + 18,
        28,
        safe.right + 18,
        safe.bottom + 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0.0, 0.54, 1.0],
          colors: [
            Colors.black.withValues(alpha: 0.84),
            Colors.black.withValues(alpha: 0.34),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          Row(
            spacing: 12,
            children: [
              Text(
                formatDurationShort(value.round()),
                style: _style(
                  context,
                  small: true,
                ).copyWith(color: Colors.white),
              ),
              Expanded(child: scrubber),
              Text(
                formatDurationShort(duration),
                style: _style(
                  context,
                  small: true,
                ).copyWith(color: Colors.white.withValues(alpha: 0.68)),
              ),
            ],
          ),
          SizedBox(
            height: 42,
            child: Row(
              spacing: 4,
              children: [
                _bareIcon(
                  glyph: status.playing ? KonekoGlyphs.pause : KonekoGlyphs.play,
                  tooltip: status.playing ? '暂停' : '播放',
                  size: 22,
                  onPressed: !_loaded
                      ? null
                      : () {
                          session?.setPlaying(!status.playing);
                          _armHudAutoHide();
                        },
                ),
                if (!offline)
                  _bareIcon(
                    glyph: KonekoGlyphs.skipNext,
                    tooltip: '下一话',
                    size: 22,
                    onPressed: canAdvance && !_loading
                        ? () => _openEpisode(_episode + 1, ruleId: _ruleId)
                        : null,
                  ),
                const Spacer(),
                buildSpeedMenu(
                  label: _speed == 1 ? '倍速' : _formatSpeed(_speed),
                ),
                _HudTextButton(
                  label: '超分',
                  active: _upscale,
                  onTap: !_loaded ? null : () => _setUpscale(!_upscale),
                ),
                _HudTextButton(
                  label: '选集',
                  active: _drawerOpen && _drawer == _DrawerTab.episodes,
                  onTap: () => setState(() {
                    _drawer = _DrawerTab.episodes;
                    _drawerOpen = true;
                  }),
                ),
                if (!offline)
                  _HudTextButton(
                    label: '切源',
                    active: _drawerOpen && _drawer == _DrawerTab.sources,
                    onTap: () => setState(() {
                      _drawer = _DrawerTab.sources;
                      _drawerOpen = true;
                    }),
                  ),
                _bareIcon(
                  glyph: KonekoGlyphs.fullscreenExit,
                  tooltip: '退出全屏',
                  size: 21,
                  onPressed: () => unawaited(_setFullscreen(false)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    List<RulePluginMeta> rules,
    bool offline,
  ) {
    final lines = _choices.where((item) => item.number == _episode).toList();
    final uniqueEpisodes = <int, SourceEpisode>{};
    for (final item in _choices) {
      uniqueEpisodes.putIfAbsent(item.number, () => item);
    }
    final episodes = uniqueEpisodes.keys.toList()..sort();

    return _HudSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 6,
            children: [
              Expanded(
                child: _HudDarkSegmentBar<_DrawerTab>(
                  segments: const [
                    (_DrawerTab.episodes, '选集'),
                    (_DrawerTab.sources, '切源'),
                    (_DrawerTab.danmaku, '弹幕'),
                  ],
                  value: _drawer,
                  onChanged: (tab) => setState(() => _drawer = tab),
                ),
              ),
              _bareIcon(
                glyph: Glyphs.close,
                tooltip: '关闭面板',
                size: 18,
                onPressed: () => setState(() => _drawerOpen = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: switch (_drawer) {
              _DrawerTab.episodes =>
                episodes.isEmpty
                    ? Center(
                        child: Text(
                          offline ? '正在播放已缓存的第 $_episode 话' : '匹配播放源后即可选集',
                          style: _style(context),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 1.32,
                            ),
                        itemCount: episodes.length,
                        itemBuilder: (context, index) {
                          final number = episodes[index];
                          return _HudAction(
                            label: '$number',
                            selected: number == _episode,
                            onTap: () => unawaited(
                              _openEpisode(
                                number,
                                ruleId: _ruleId.isEmpty ? null : _ruleId,
                                autoSelectFastest: _ruleId.isEmpty,
                              ),
                            ),
                          );
                        },
                      ),
              _DrawerTab.sources => ListenableBuilder(
                listenable: _sourcesRevision,
                builder: (context, _) {
                  final enabledRules = _prioritizedRules(
                    rules.where((rule) => rule.enabled).toList(),
                  );
                  return ListView(
                    children: [
                      if (offline)
                        Text('离线播放中', style: _style(context))
                      else ...[
                        if (enabledRules.isNotEmpty) ...[
                          _HudAction(
                            label: '自动优选最快源',
                            leading: GlyphIcon(
                              KonekoGlyphs.speed,
                              size: 13.5,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                            onTap: () {
                              setState(() => _drawerOpen = false);
                              unawaited(
                                _openEpisode(_episode, autoSelectFastest: true),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 6),
                          child: Text(
                            '播放源',
                            style: _style(context, small: true).copyWith(
                              color: Colors.white.withValues(alpha: 0.54),
                            ),
                          ),
                        ),
                        for (final rule in enabledRules)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _HudAction(
                              label: () {
                                final probe = _probes[rule.id];
                                final suffix = switch (probe?.state) {
                                  RuleProbeState.found =>
                                    probe!.latencyMs > 0
                                        ? ' (${probe.latencyMs}ms)'
                                        : ' (${probe.hits.length})',
                                  RuleProbeState.noResult => ' (无)',
                                  RuleProbeState.captchaRequired => ' (需验证)',
                                  RuleProbeState.error => ' (不可用)',
                                  _ => '',
                                };
                                return '${rule.name}$suffix';
                              }(),
                              selected: _ruleId == rule.id,
                              onTap: () {
                                final probe = _probes[rule.id];
                                if (probe?.state ==
                                        RuleProbeState.captchaRequired &&
                                    probe?.verifyUrl != null) {
                                  unawaited(
                                    _verifyRule(
                                      rule.id,
                                      rule.name,
                                      probe!.verifyUrl!,
                                      verifyHint: probe.verifyHint,
                                    ),
                                  );
                                } else if (probe?.state ==
                                        RuleProbeState.found &&
                                    probe != null &&
                                    probe.hits.isNotEmpty) {
                                  unawaited(
                                    _openHit(
                                      rule.id,
                                      rule.name,
                                      probe.hits.first,
                                    ),
                                  );
                                } else {
                                  unawaited(
                                    _openEpisode(_episode, ruleId: rule.id),
                                  );
                                }
                              },
                            ),
                          ),
                        if (lines.isNotEmpty) ...[
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 6),
                            child: Text(
                              _ruleName.isNotEmpty
                                  ? '播放线路 · $_ruleName'
                                  : '播放线路',
                              style: _style(context, small: true).copyWith(
                                color: Colors.white.withValues(alpha: 0.54),
                              ),
                            ),
                          ),
                          for (final line in lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _HudAction(
                                label: line.line,
                                selected:
                                    line.line == _source?.line &&
                                    line.page == _source?.page,
                                onTap: () => unawaited(
                                  _openEpisode(
                                    _episode,
                                    ruleId: line.ruleId,
                                    choice: line,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ],
                  );
                },
              ),
              _DrawerTab.danmaku => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Row(
                    spacing: 10,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            Text('显示弹幕', style: _style(context)),
                            Text(
                              _danmakuError ??
                                  (_danmaku.isEmpty
                                      ? '当前话暂无弹幕'
                                      : _danmakuSummary()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style(context, small: true).copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                      KonekoDanmakuSwitch(
                        value: _showDanmaku,
                        onChanged: (value) {
                          setState(() => _showDanmaku = value);
                          if (value) unawaited(_loadDanmaku());
                        },
                      ),
                    ],
                  ),
                  _HudAction(
                    label: '弹幕设置',
                    onTap: () async {
                      setState(() => _drawerOpen = false);
                      await _setFullscreen(false);
                      if (context.mounted) {
                        unawaited(openKonekoDanmakuSettingsPage(context));
                      }
                    },
                  ),
                  _HudAction(
                    label: _danmakuLoading ? '正在拉取弹幕…' : '重新加载弹幕',
                    leading: KonekoSpinningRefreshIcon(
                      spinning: _danmakuLoading,
                      size: 13,
                      color: Colors.white,
                    ),
                    onTap: _danmakuLoading
                        ? null
                        : () => unawaited(_loadDanmaku()),
                  ),
                  _HudAction(
                    label: '手动匹配弹幕',
                    onTap: () async {
                      setState(() => _drawerOpen = false);
                      await _setFullscreen(false);
                      if (mounted) unawaited(_openDanmakuSearchSheet());
                    },
                  ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }

  TextStyle _style(BuildContext context, {bool small = false}) =>
      (small ? AppTextStyle.caption1 : AppTextStyle.subheadline)
          .of(context, emphasized: !small)
          .copyWith(
            color: small ? Colors.white.withValues(alpha: 0.85) : Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          );

  Widget _bareIcon({
    required Glyph glyph,
    required String tooltip,
    VoidCallback? onPressed,
    double size = 19,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 38,
      height: 38,
      child: PressSurface(
        fill: Colors.transparent,
        shape: AppShape.full,
        onPressed: onPressed,
        child: Center(
          child: GlyphIcon(
            glyph,
            size: size,
            color: onPressed == null
                ? Colors.white.withValues(alpha: 0.34)
                : Colors.white,
          ),
        ),
      ),
    ),
  );
}

class _EpisodeChipButton extends StatelessWidget {
  const _EpisodeChipButton({
    required this.number,
    required this.current,
    required this.watched,
    required this.onPressed,
  });

  final int number;
  final bool current;
  final bool watched;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final bg = current
        ? colorScheme.primary
        : watched
        ? colorScheme.primary.withValues(alpha: 0.14)
        : SurfaceLevel.block.colorOf(colorScheme);
    final fg = current
        ? colorScheme.onPrimary
        : watched
        ? colorScheme.primary
        : colorScheme.onSurface;
    return SizedBox(
      width: 58,
      height: 40,
      child: PressSurface(
        fill: bg,
        shape: AppShape.md,
        clipsChild: true,
        onPressed: onPressed,
        child: Center(
          child: Text(
            '$number',
            style: AppTextStyle.footnote
                .of(context, emphasized: true)
                .copyWith(
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ),
      ),
    );
  }
}

class _HudTextButton extends StatelessWidget {
  const _HudTextButton({
    required this.label,
    this.active = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressSurface(
      fill: Colors.transparent,
      shape: AppShape.full,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppTextStyle.footnote
                .of(context, emphasized: active)
                .copyWith(
                  fontSize: 12.5,
                  color: onTap == null
                      ? Colors.white.withValues(alpha: 0.34)
                      : active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.84),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          if (active) ...[
            const SizedBox(height: 2),
            Container(
              width: 12,
              height: 2,
              decoration: const ShapeDecoration(
                color: Colors.white,
                shape: AppShape.full,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HudAction extends StatelessWidget {
  const _HudAction({
    required this.label,
    this.leading,
    this.selected = false,
    this.prominent = false,
    this.onTap,
  });

  final String label;
  final Widget? leading;
  final bool selected;
  final bool prominent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = prominent
        ? Colors.white
        : selected
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.11);
    final fg = onTap == null
        ? Colors.white.withValues(alpha: 0.36)
        : prominent
        ? Colors.black
        : Colors.white;
    final shape = SuperellipseBorder(
      borderRadius: AppRadius.all(12),
      side: selected
          ? BorderSide(color: Colors.white.withValues(alpha: 0.55), width: 1.2)
          : BorderSide.none,
    );
    return PressSurface(
      fill: fill,
      shape: shape,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 6,
        children: [
          if (selected && leading == null)
            const GlyphIcon(Glyphs.check, size: 13, color: Colors.white),
          ?leading,
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context, emphasized: true)
                  .copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _HudDarkSegmentBar<T> extends StatelessWidget {
  const _HudDarkSegmentBar({
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: SuperellipseBorder(borderRadius: AppRadius.all(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final (tab, label) in segments)
              Expanded(
                child: PressSurface(
                  fill: tab == value
                      ? Colors.white.withValues(alpha: 0.20)
                      : Colors.transparent,
                  shape: SuperellipseBorder(borderRadius: AppRadius.all(9)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  onPressed: () => onChanged(tab),
                  child: Center(
                    child: Text(
                      label,
                      style: AppTextStyle.caption1
                          .of(context, emphasized: tab == value)
                          .copyWith(
                            color: tab == value
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.62),
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeekDragRecognizer extends HorizontalDragGestureRecognizer {
  bool cancelled = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    cancelled = false;
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerCancelEvent) cancelled = true;
    super.handleEvent(event);
  }

  @override
  String get debugDescription => 'koneko seek drag';
}

/// Cinema-grade luminous white video scrubber: slim translucent rail that
/// smoothly expands while scrubbing, crisp shadowed white thumb, and instant
/// drag-capture with zero gesture-arena lag.
class _VideoProgressBar extends StatefulWidget {
  const _VideoProgressBar({
    required this.progress,
    required this.enabled,
    required this.scrubbing,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  final double progress;
  final bool enabled;
  final bool scrubbing;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final void Function(double ratio, {required bool cancelled}) onScrubEnd;

  @override
  State<_VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<_VideoProgressBar> {
  double _lastRatio = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(1.0, constraints.maxWidth);
        const horizontalPad = 6.0;
        final span = math.max(1.0, width - horizontalPad * 2);
        double ratioFor(double dx) =>
            ((dx - horizontalPad) / span).clamp(0.0, 1.0);

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: widget.enabled
              ? {
                  _SeekDragRecognizer:
                      GestureRecognizerFactoryWithHandlers<_SeekDragRecognizer>(
                        _SeekDragRecognizer.new,
                        (recognizer) {
                          recognizer.onStart = (details) {
                            _lastRatio = ratioFor(details.localPosition.dx);
                            widget.onScrubStart(_lastRatio);
                          };
                          recognizer.onUpdate = (details) {
                            _lastRatio = ratioFor(details.localPosition.dx);
                            widget.onScrubUpdate(_lastRatio);
                          };
                          recognizer.onEnd = (_) {
                            widget.onScrubEnd(
                              _lastRatio,
                              cancelled: recognizer.cancelled,
                            );
                          };
                        },
                      ),
                }
              : const {},
          child: SizedBox(
            height: 26,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(width, 26),
                painter: _VideoProgressPainter(
                  progress: widget.progress.clamp(0.0, 1.0),
                  scrubbing: widget.scrubbing,
                  enabled: widget.enabled,
                  inset: horizontalPad,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VideoProgressPainter extends CustomPainter {
  const _VideoProgressPainter({
    required this.progress,
    required this.scrubbing,
    required this.enabled,
    required this.inset,
  });

  final double progress;
  final bool scrubbing;
  final bool enabled;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final startX = inset;
    final endX = math.max(startX, size.width - inset);
    final span = math.max(0.0, endX - startX);
    final trackH = scrubbing ? 6.0 : 3.5;
    final trackR = Radius.circular(trackH / 2);

    // Translucent frosted rail
    canvas.drawRRect(
      RRect.fromLTRBR(
        startX,
        cy - trackH / 2,
        endX,
        cy + trackH / 2,
        trackR,
      ),
      Paint()..color = Colors.white.withValues(alpha: scrubbing ? 0.30 : 0.24),
    );

    final playedX = startX + span * (enabled ? progress : 0.0);
    if (enabled && playedX > startX) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          startX,
          cy - trackH / 2,
          playedX,
          cy + trackH / 2,
          trackR,
        ),
        Paint()..color = Colors.white,
      );
    }

    // Crisp shadowed white thumb (expands cleanly when dragging)
    final thumbR = scrubbing ? 7.5 : 5.2;
    final thumbCenter = Offset(playedX.clamp(startX, endX), cy);
    if (scrubbing) {
      canvas.drawCircle(
        thumbCenter,
        thumbR + 5.5,
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
    }
    canvas.drawCircle(
      thumbCenter.translate(0, 1),
      thumbR + 0.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawCircle(
      thumbCenter,
      thumbR,
      Paint()..color = enabled ? Colors.white : Colors.white.withValues(alpha: 0.60),
    );
  }

  @override
  bool shouldRepaint(covariant _VideoProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.scrubbing != scrubbing ||
      oldDelegate.enabled != enabled ||
      oldDelegate.inset != inset;
}

/// Crisp frosted-obsidian video HUD surface with continuous superellipse
/// corners and zero live-video BackdropFilter GPU overhead.
class _HudSurface extends StatelessWidget {
  const _HudSurface({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: const Color(0xD9101217),
      shape: SuperellipseBorder(
        borderRadius: AppRadius.all(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
    ),
    child: Padding(padding: padding, child: child),
  );
}
