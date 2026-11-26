import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemChrome, SystemUiMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/my/service_settings_page.dart';
import 'package:koneko/features/rules/rules_page.dart';
import 'package:koneko/ui/koneko_comments.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

enum _PanelTab { episodes, sources, comments }

enum _DrawerTab { episodes, sources, danmaku }

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
  PlaybackStatus _status = const PlaybackStatus();
  StreamSubscription<PlaybackStatus>? _subscription;
  Timer? _saveTimer;
  Timer? _brightnessTimer;
  SourceEpisode? _source;
  List<SourceEpisode> _choices = const [];
  List<DanmakuItem> _danmaku = const [];
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
  bool _changingBrightness = false;
  _PanelTab _panelTab = _PanelTab.episodes;
  _DrawerTab _drawer = _DrawerTab.episodes;
  int _epPageIndex = 0;
  String? _error;
  String? _danmakuError;
  int _request = 0;
  int _danmakuRequest = 0;
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
    _danmakuRequest++;
    _saveTimer?.cancel();
    _brightnessTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_session?.dispose());
    super.dispose();
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
        await _openEpisode(_episode);
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
    setState(() => _status = status);
    if (completed) _checkpoint();
  }

  bool _isCurrent(int request) => mounted && request == _request;

  Duration _resumeAt(int episode) {
    final history = ref
        .read(historyProvider.notifier)
        .positionFor(widget.subjectId, episode);
    if (history == null || history.isCompleted) return Duration.zero;
    return Duration(seconds: history.positionSeconds);
  }

  Future<void> _startOffline(Uri uri) async {
    final request = ++_request;
    final session = _session!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await session.open(PlayableMedia(uri), startAt: _resumeAt(_episode));
      if (!_isCurrent(request)) return;
      if (!_pageActive) await session.setPlaying(false);
      if (!_isCurrent(request)) return;
      setState(() {
        _loaded = true;
        _loading = false;
      });
      _loadDanmaku();
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
  }) async {
    final session = _session;
    if (session == null) return;
    _checkpoint();
    final initialPosition = episode == _episode && _loaded
        ? _status.position
        : _resumeAt(episode);
    final request = ++_request;
    ++_danmakuRequest;
    setState(() {
      _episode = episode;
      _loaded = false;
      _loading = true;
      _error = null;
      _scrub = null;
      _danmaku = const [];
      _danmakuError = null;
    });
    try {
      await session.setPlaying(false);
      final resolver = ref.read(playbackSourcesProvider);
      if (resolver == null) throw StateError('规则播放服务不可用');
      var subject = _subject;
      if (subject == null) {
        await ref.read(onlineCatalogProvider)?.loadSubject(widget.subjectId);
        if (!_isCurrent(request)) return;
        subject = _subject;
      }
      if (subject == null) throw StateError('未能加载番剧资料');

      final rules = ref
          .read(rulesProvider)
          .where((rule) => rule.enabled)
          .toList();
      if (rules.isEmpty) throw StateError('请先添加并启用一条 Kazumi 规则');
      final ids = (ruleId != null
          ? [ruleId]
          : {
              if (_ruleId.isNotEmpty && rules.any((rule) => rule.id == _ruleId))
                _ruleId,
              ...rules.map((rule) => rule.id),
            }.toList());
      Object? problem;
      for (final id in ids.take(4)) {
        if (!_isCurrent(request)) return;
        try {
          final options = await resolver.lookup(subject, id);
          if (!_isCurrent(request)) return;
          final available = options
              .where((item) => item.number == episode)
              .toList();
          if (available.isEmpty) throw StateError('这条规则没有第 $episode 话');
          setState(() {
            _choices = options;
            _ruleId = id;
            _ruleName = options.first.ruleName;
          });
          final currentLine = _source?.line;
          final episodeSource =
              choice ??
              available.where((item) => item.line == currentLine).firstOrNull ??
              available.first;
          final media = await resolver.resolve(episodeSource);
          if (!_isCurrent(request)) return;
          await session.open(media, startAt: initialPosition);
          if (!_isCurrent(request)) return;
          if (!_pageActive) await session.setPlaying(false);
          if (!_isCurrent(request)) return;
          setState(() {
            _episode = episode;
            _source = episodeSource;
            _ruleId = episodeSource.ruleId;
            _ruleName = episodeSource.ruleName;
            _status = session.status;
            _loading = false;
            _loaded = true;
            _lastCheckpoint = -1;
            _lastCompleted = false;
          });
          _loadDanmaku();
          return;
        } on Object catch (error) {
          problem = error;
        }
      }
      throw problem ?? StateError('暂时没有可播放的线路');
    } on Object catch (error) {
      if (!_isCurrent(request)) return;
      setState(() {
        _loading = false;
        _error = featureError(error, '无法播放这一话，请切换线路或规则');
      });
    }
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

  Future<void> _loadDanmaku() async {
    final token = ++_danmakuRequest;
    if (!_showDanmaku) return;
    final subject = _subject;
    final source = ref.read(danmakuProvider);
    if (source == null || subject == null) return;
    try {
      final items = await source.load(subject, _episode);
      if (mounted && token == _danmakuRequest) {
        setState(() {
          _danmaku = items;
          _danmakuError = null;
        });
      }
    } on Object catch (error) {
      if (mounted && token == _danmakuRequest) {
        setState(() => _danmakuError = featureError(error, '暂时取不到弹幕'));
      }
    }
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
      showKonekoBanner(context, '已标记为「${status.label}」', level: BannerLevel.success);
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

  void _drawerTo(_DrawerTab tab) {
    if (_fullscreen) {
      setState(() {
        _drawer = tab;
        _drawerOpen = true;
      });
    } else {
      setState(() {
        _panelTab = tab == _DrawerTab.episodes
            ? _PanelTab.episodes
            : _PanelTab.sources;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogUpdatesProvider);
    ref.watch(loadCatalogSubjectProvider(widget.subjectId));
    final catalog = ref.watch(catalogRepositoryProvider);
    final subject = _subject;
    final title = subject?.title ?? widget.offline?.subjectTitle ?? 'Koneko';
    final rules = ref.watch(rulesProvider);
    final library = ref.watch(libraryProvider);
    final collection = library
        .where((e) => e.subjectId == widget.subjectId)
        .firstOrNull;
    final session = _session;
    final viewport = ref.watch(videoViewportProvider);
    final overlay = ref.watch(danmakuViewportProvider);
    final status = _status;
    final error =
        _error ??
        (_loaded && status.duration == Duration.zero && status.error != null
            ? '媒体播放失败，请切换线路'
            : null);
    final offline = widget.offline != null;

    final videoStage = _buildVideoStage(
      context: context,
      subject: subject,
      title: title,
      rules: rules,
      session: session,
      viewport: viewport,
      overlay: overlay,
      status: status,
      error: error,
      offline: offline,
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
          ? ColoredBox(color: Colors.black, child: videoStage)
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
                              child: SafeArea(
                                right: false,
                                child: videoStage,
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.25,
                            ),
                          ),
                          SizedBox(
                            width: math.min(400, constraints.maxWidth * 0.36),
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

                // Portrait mode (Kazumi-style split): 16:9 video on top,
                // episodes / sources / comments tabs below.
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
    required AnimeSubject? subject,
    required String title,
    required List<RulePluginMeta> rules,
    required PlaybackSession? session,
    required Widget Function(PlaybackSession)? viewport,
    required Widget Function(List<DanmakuItem>, PlaybackStatus)? overlay,
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
          onTap: () => setState(() {
            if (_drawerOpen) {
              _drawerOpen = false;
            } else {
              _showHud = !_showHud;
            }
          }),
          onDoubleTap: !_loaded
              ? null
              : () => session?.setPlaying(!status.playing),
          onVerticalDragUpdate: (event) =>
              _adjustBrightness(-event.delta.dy * .004),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (session != null && viewport != null)
                IgnorePointer(child: viewport(session))
              else if (subject != null)
                Opacity(opacity: .35, child: KonekoPosterArt(subject: subject)),
              if (_brightness < 1)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 1 - _brightness),
                  ),
                ),
              if (_showDanmaku && _danmaku.isNotEmpty && overlay != null)
                IgnorePointer(child: overlay(_danmaku, status)),
            ],
          ),
        ),
        if (_loading || (_loaded && status.buffering))
          const Center(child: ActivityIndicator(color: Colors.white)),
        if (error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _GlassPill(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _style(context),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        _HudAction(label: '重试', onTap: _start),
                        if (!offline)
                          _HudAction(
                            label: rules.any((rule) => rule.enabled)
                                ? '切换播放源'
                                : '添加规则',
                            onTap: () async {
                              if (rules.any((rule) => rule.enabled)) {
                                _drawerTo(_DrawerTab.sources);
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
            top: safe.top + (_fullscreen ? 68 : 48),
            left: 16,
            right: 16,
            child: Center(
              child: _GlassPill(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: Text(
                  '亮度 ${(_brightness * 100).round()}%',
                  style: _style(context),
                ),
              ),
            ),
          ),
        if (_showHud)
          Positioned(
            top: safe.top + 8,
            left: safe.left + 8,
            right: safe.right + 8,
            child: _GlassPill(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                spacing: 4,
                children: [
                  _round(
                    glyph: Glyphs.backFor(Theme.of(context).platform),
                    tooltip: _fullscreen ? '退出全屏' : '返回',
                    onPressed: () {
                      if (_fullscreen) {
                        unawaited(_setFullscreen(false));
                      } else {
                        Navigator.of(context).maybePop();
                      }
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$title · 第 $_episode 话',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _style(context),
                        ),
                        if (_fullscreen)
                          Text(
                            offline
                                ? '离线缓存'
                                : (_ruleName.isEmpty ? '等待匹配线路' : _ruleName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _style(context, small: true),
                          ),
                      ],
                    ),
                  ),
                  _round(
                    glyph: KonekoGlyphs.danmaku,
                    tooltip: _showDanmaku ? '关闭弹幕' : '开启弹幕',
                    active: _showDanmaku,
                    onPressed: () {
                      setState(() => _showDanmaku = !_showDanmaku);
                      _loadDanmaku();
                    },
                  ),
                  if (_fullscreen)
                    _round(
                      glyph: KonekoGlyphs.layers,
                      tooltip: '选集与播放源',
                      onPressed: () =>
                          setState(() => _drawerOpen = !_drawerOpen),
                    ),
                ],
              ),
            ),
          ),
        if (_showHud)
          Positioned(
            left: safe.left + 8,
            right: safe.right + 8,
            bottom: safe.bottom + 8,
            child: _controls(context, status, session, offline),
          ),
        if (_fullscreen)
          AnimatedPositioned(
            duration: context.motionDuration(
              const Duration(milliseconds: 230),
            ),
            curve: Curves.easeOutCubic,
            top: safe.top + 12,
            bottom: safe.bottom + 12,
            right: _drawerOpen ? safe.right + 12 : -360,
            width: math.min(330, MediaQuery.sizeOf(context).width - 24),
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
    final commentsCount =
        ref.watch(subjectCommentsProvider(widget.subjectId)).value?.total ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact FlClash title & action bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                    const SizedBox(height: 2),
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
                height: 30,
                fontSize: 12,
                backgroundColor: collection != null
                    ? colorScheme.primary.withValues(alpha: 0.14)
                    : SurfaceLevel.card.colorOf(colorScheme),
                foregroundColor: collection != null
                    ? colorScheme.primary
                    : colorScheme.onSurface,
                trailing: GlyphIcon(
                  Glyphs.chevronDown,
                  size: 12,
                  color: collection != null
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                onPressed: () =>
                    _pickCollectionStatus(title, collection?.status),
              ),
              if (!offline)
                KonekoCircleButton(
                  size: 32,
                  iconSize: 15,
                  glyph: KonekoGlyphs.importFile,
                  tooltip: '离线缓存当前话',
                  onPressed: _loaded && _source != null ? _download : null,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedControl<_PanelTab>(
            segments: [
              const (_PanelTab.episodes, '选集'),
              const (_PanelTab.sources, '换源与弹幕'),
              (
                _PanelTab.comments,
                commentsCount > 0 ? '评论 ($commentsCount)' : '评论',
              ),
            ],
            value: _panelTab,
            onChanged: (tab) => setState(() => _panelTab = tab),
          ),
        ),
        Expanded(
          child: switch (_panelTab) {
            _PanelTab.episodes => _buildEpisodesPanel(
              context: context,
              catalog: catalog,
              collection: collection,
              offline: offline,
              bottomPadding: bottomPadding,
            ),
            _PanelTab.sources => _buildSourcesAndDanmakuPanel(
              context: context,
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

  Widget _buildEpisodesPanel({
    required BuildContext context,
    required CatalogRepository catalog,
    required CollectionEntry? collection,
    required bool offline,
    required double bottomPadding,
  }) {
    final colorScheme = context.colorScheme;
    final lines = _choices.where((item) => item.number == _episode).toList();

    final sourceEpNums = <int>{for (final item in _choices) item.number}.toList()
      ..sort();
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
    final safePage = _epPageIndex
        .clamp(0, math.max(0, totalPages - 1))
        .toInt();
    final visibleEps = epNumbers
        .skip(safePage * _pageSize)
        .take(_pageSize)
        .toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPadding),
      children: [
        if (!offline && lines.length > 1) ...[
          Text(
            '播放线路',
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final line in lines)
                KonekoChip(
                  label: line.line,
                  height: 30,
                  fontSize: 12,
                  selected: line.page == _source?.page,
                  backgroundColor: line.page == _source?.page
                      ? colorScheme.primary
                      : SurfaceLevel.card.colorOf(colorScheme),
                  onPressed: _loading
                      ? null
                      : () => _openEpisode(
                          _episode,
                          ruleId: line.ruleId,
                          choice: line,
                        ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '剧集列表',
                      style: AppTextStyle.headline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                  Text(
                    epNumbers.isEmpty ? '加载中' : '共 ${epNumbers.length} 话',
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (totalPages > 1) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: totalPages,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, idx) {
                      final from = idx * _pageSize + 1;
                      final to = ((idx + 1) * _pageSize).clamp(
                        1,
                        epNumbers.length,
                      );
                      return KonekoChip(
                        label: '$from-$to',
                        height: 28,
                        fontSize: 11.5,
                        selected: idx == safePage,
                        onPressed: () => setState(() => _epPageIndex = idx),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (visibleEps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      offline
                          ? '正在播放离线缓存的第 $_episode 话'
                          : '匹配规则后将自动显示可选剧集',
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final number in visibleEps)
                      _EpisodeChipButton(
                        number: number,
                        current: number == _episode,
                        watched:
                            (collection?.watchedEpisodes ?? 0) >= number &&
                            number != _episode,
                        onPressed: _loading || offline
                            ? null
                            : () => _openEpisode(number, ruleId: _ruleId),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesAndDanmakuPanel({
    required BuildContext context,
    required List<RulePluginMeta> rules,
    required bool offline,
    required double bottomPadding,
  }) {
    final colorScheme = context.colorScheme;
    final enabledRules = rules.where((r) => r.enabled).toList();
    final lines = _choices.where((item) => item.number == _episode).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPadding),
      children: [
        // Danmaku status card
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                children: [
                  const GlyphIcon(KonekoGlyphs.danmaku, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '弹幕（弹弹Play）',
                          style: AppTextStyle.headline
                              .of(context, emphasized: true)
                              .copyWith(color: colorScheme.onSurface),
                        ),
                        Text(
                          _danmakuError ??
                              (_showDanmaku
                                  ? (_danmaku.isNotEmpty
                                      ? '已加载 ${_danmaku.length} 条弹幕'
                                      : '等待弹幕加载或当前话暂无弹幕')
                                  : '弹幕已关闭'),
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _showDanmaku,
                    onChanged: (value) {
                      setState(() => _showDanmaku = value);
                      if (value) _loadDanmaku();
                    },
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  KonekoChip(
                    label: '重新拉取弹幕',
                    height: 30,
                    fontSize: 12,
                    leading: GlyphIcon(
                      KonekoGlyphs.refresh,
                      size: 13,
                      color: colorScheme.primary,
                    ),
                    onPressed: _loadDanmaku,
                  ),
                  KonekoChip(
                    label: '屏蔽词与高级设置',
                    height: 30,
                    fontSize: 12,
                    onPressed: () => BaseNavigator.push<void>(
                      context,
                      const ServiceSettingsPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!offline)
          KonekoCard(
            corner: 24,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '切换规则与线路',
                        style: AppTextStyle.headline
                            .of(context, emphasized: true)
                            .copyWith(color: colorScheme.onSurface),
                      ),
                    ),
                    KonekoChip(
                      label: '规则管理',
                      height: 28,
                      fontSize: 12,
                      onPressed: () async {
                        await BaseNavigator.push<void>(
                          context,
                          const RulesPage(showBack: true),
                        );
                        if (mounted && !_loaded) await _start();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (enabledRules.isEmpty)
                  TextButton(
                    onPressed: () async {
                      await BaseNavigator.push<void>(
                        context,
                        const RulesPage(showBack: true),
                      );
                      if (mounted) await _start();
                    },
                    child: const Text('去规则仓库安装 Kazumi 播放规则'),
                  )
                else
                  Column(
                    spacing: 8,
                    children: [
                      for (final rule in enabledRules)
                        KonekoBlock(
                          selected: _ruleId == rule.id,
                          onPressed: _loading
                              ? null
                              : () => _openEpisode(_episode, ruleId: rule.id),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rule.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.subheadline
                                      .of(context, emphasized: true)
                                      .copyWith(color: colorScheme.onSurface),
                                ),
                              ),
                              KonekoChip(
                                label: rule.apiType,
                                height: 22,
                                fontSize: 10.5,
                              ),
                              if (_ruleId == rule.id) ...[
                                const SizedBox(width: 6),
                                GlyphIcon(
                                  Glyphs.check,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '当前规则线路',
                    style: AppTextStyle.caption1
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final line in lines)
                        KonekoChip(
                          label: line.line,
                          height: 30,
                          fontSize: 12,
                          selected: line.page == _source?.page,
                          onPressed: _loading
                              ? null
                              : () => _openEpisode(
                                  _episode,
                                  ruleId: line.ruleId,
                                  choice: line,
                                ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _controls(
    BuildContext context,
    PlaybackStatus status,
    PlaybackSession? session,
    bool offline,
  ) {
    final duration = status.duration.inSeconds;
    final position = status.position.inSeconds;
    final max = math.max(1, duration).toDouble();
    final value = (_scrub ?? position.toDouble()).clamp(0.0, max);
    final canAdvance = _choices.any(
      (episode) => episode.number == _episode + 1,
    );
    return _GlassPill(
      padding: EdgeInsets.fromLTRB(
        10,
        _fullscreen ? 8 : 4,
        10,
        _fullscreen ? 10 : 6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                formatDurationShort(value.round()),
                style: _style(context, small: true),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Slider(
                    min: 0,
                    max: max,
                    value: value,
                    onChanged: duration > 0 && _loaded
                        ? (value) => setState(() => _scrub = value)
                        : null,
                    onChangeEnd: (value) {
                      setState(() => _scrub = null);
                      unawaited(
                        session?.seek(Duration(seconds: value.round())),
                      );
                    },
                  ),
                ),
              ),
              Text(
                formatDurationShort(duration),
                style: _style(context, small: true),
              ),
            ],
          ),
          Row(
            spacing: 4,
            children: [
              _round(
                glyph: status.playing ? KonekoGlyphs.pause : KonekoGlyphs.play,
                tooltip: status.playing ? '暂停' : '播放',
                onPressed: !_loaded
                    ? null
                    : () => session?.setPlaying(!status.playing),
              ),
              if (!offline)
                _round(
                  glyph: KonekoGlyphs.skipNext,
                  tooltip: '下一话',
                  onPressed: canAdvance && !_loading
                      ? () => _openEpisode(_episode + 1)
                      : null,
                ),
              const Spacer(),
              _HudAction(
                label: '${_speed.toStringAsFixed(2)}x',
                active: _speed != 1,
                onTap: !_loaded
                    ? null
                    : () {
                        const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
                        setState(
                          () => _speed =
                              speeds[(speeds.indexOf(_speed) + 1) %
                                  speeds.length],
                        );
                        unawaited(session?.setRate(_speed));
                      },
              ),
              if (_fullscreen)
                _HudAction(
                  label: '超分',
                  active: _upscale,
                  onTap: !_loaded ? null : () => _setUpscale(!_upscale),
                ),
              _round(
                glyph: _fullscreen
                    ? KonekoGlyphs.fullscreenExit
                    : KonekoGlyphs.fullscreen,
                tooltip: _fullscreen ? '退出全屏' : '全屏播放',
                onPressed: () => unawaited(_setFullscreen(!_fullscreen)),
              ),
            ],
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

    return _GlassPill(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedControl<_DrawerTab>(
                  segments: const [
                    (_DrawerTab.episodes, '选集'),
                    (_DrawerTab.sources, '切源'),
                    (_DrawerTab.danmaku, '弹幕'),
                  ],
                  value: _drawer,
                  onChanged: (tab) => setState(() => _drawer = tab),
                ),
              ),
              _round(
                glyph: Glyphs.close,
                tooltip: '关闭面板',
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
                            active: number == _episode,
                            onTap: _loading
                                ? null
                                : () => _openEpisode(number, ruleId: _ruleId),
                          );
                        },
                      ),
              _DrawerTab.sources => ListView(
                children: [
                  if (offline)
                    Text('当前正在离线播放', style: _style(context))
                  else ...[
                    for (final rule in rules.where((rule) => rule.enabled))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: _HudAction(
                          label: rule.name,
                          active: _ruleId == rule.id,
                          onTap: _loading
                              ? null
                              : () => _openEpisode(_episode, ruleId: rule.id),
                        ),
                      ),
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: _HudAction(
                          label: line.line,
                          active: line.page == _source?.page,
                          onTap: _loading
                              ? null
                              : () => _openEpisode(
                                  _episode,
                                  ruleId: line.ruleId,
                                  choice: line,
                                ),
                        ),
                      ),
                    _HudAction(
                      label: '管理规则',
                      onTap: () => BaseNavigator.push<void>(
                        context,
                        const RulesPage(showBack: true),
                      ),
                    ),
                  ],
                ],
              ),
              _DrawerTab.danmaku => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Text(
                    _danmakuError ??
                        (_danmaku.isEmpty
                            ? '当前话暂无弹幕'
                            : '已加载 ${_danmaku.length} 条弹幕'),
                    style: _style(context),
                  ),
                  _HudAction(
                    label: _showDanmaku ? '隐藏弹幕' : '显示弹幕',
                    active: _showDanmaku,
                    onTap: () {
                      setState(() => _showDanmaku = !_showDanmaku);
                      _loadDanmaku();
                    },
                  ),
                  _HudAction(label: '重新加载弹幕', onTap: _loadDanmaku),
                  _HudAction(
                    label: '弹幕屏蔽词设置',
                    onTap: () => BaseNavigator.push<void>(
                      context,
                      const ServiceSettingsPage(),
                    ),
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
            color: small
                ? Colors.white.withValues(alpha: 0.72)
                : Colors.white,
          );

  Widget _round({
    required Glyph glyph,
    required String tooltip,
    VoidCallback? onPressed,
    bool active = false,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox(
      width: 34,
      height: 34,
      child: PressSurface(
        fill: active
            ? context.colorScheme.primary.withValues(alpha: .85)
            : Colors.white.withValues(alpha: .14),
        shape: AppShape.full,
        onPressed: onPressed,
        child: Center(
          child: GlyphIcon(
            glyph,
            size: 16,
            color: onPressed == null
                ? Colors.white.withValues(alpha: 0.38)
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
      height: 38,
      child: PressSurface(
        fill: bg,
        shape: AppShape.md,
        clipsChild: true,
        onPressed: onPressed,
        child: Center(
          child: Text(
            current ? '▶ $number' : '$number',
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

class _HudAction extends StatelessWidget {
  const _HudAction({required this.label, this.active = false, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = active
        ? context.colorScheme.primary.withValues(alpha: .85)
        : Colors.white.withValues(alpha: .16);
    return PressSurface(
      fill: fill,
      shape: AppShape.full,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      onPressed: onTap,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption1
              .of(context, emphasized: true)
              .copyWith(
                color: onTap == null
                    ? Colors.white.withValues(alpha: 0.38)
                    : Colors.white,
              ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: AppRadius.all(18),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .54),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
