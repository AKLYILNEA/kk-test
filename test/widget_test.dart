import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart'
    show debugOnProfilePaint, debugProfilePaintsEnabled;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/about/about_page.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/discover/discover_page.dart';
import 'package:koneko/features/theme/theme_page.dart';
import 'package:koneko/features/theme/theme_preview.dart';
import 'package:koneko/main.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:koneko_mock/koneko_mock.dart';
import 'package:prism_ui/barrier.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'Animeko multi-source history merges legacy Kazumi records by subjectId',
    () {
      final now = DateTime.now();
      final existing = MockSeedData.initialMergedHistory();
      final legacy = [
        LegacyKazumiHistoryRecord(
          subjectId: 1001,
          pluginName: 'Kazumi · 测试新源',
          episodeNumber: 14,
          positionSeconds: 950,
          durationSeconds: 1425,
          watchedAt: now,
        ),
      ];

      final merged = MockSeedData.mergeLegacyKazumiRecords(existing, legacy);
      final entry1001 = merged.firstWhere((e) => e.subjectId == 1001);

      expect(merged.where((e) => e.subjectId == 1001).length, 1);
      expect(entry1001.mergedSourceCount, greaterThanOrEqualTo(4));
      expect(entry1001.lastRuleName, 'Kazumi · 测试新源');
    },
  );

  testWidgets('KonekoApp renders mobile shell and switches tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 880);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('推荐'), findsWidgets);
    expect(find.text('追番'), findsOneWidget);

    await tester.tap(find.text('追番'));
    await tester.pumpAndSettle();
    expect(find.text('星海旅人：北境编年史'), findsWidgets);
  });

  test(
    'system and Han text fonts take precedence, with Twemoji on emoji spans',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final theme = buildKonekoTheme(
        settings: const ThemeSettings(),
        brightness: Brightness.light,
        customFontFamily: null,
      );
      expect(theme.bodyTextStyle.fontFamily, 'Segoe UI');
      expect(theme.bodyTextStyle.fontFamilyFallback, ['Microsoft YaHei UI']);

      final customTheme = buildKonekoTheme(
        settings: const ThemeSettings(),
        brightness: Brightness.light,
        customFontFamily: 'CustomUserFont_test',
      );
      expect(customTheme.bodyTextStyle.fontFamily, 'CustomUserFont_test');
      expect(customTheme.bodyTextStyle.fontFamilyFallback, [
        'Segoe UI',
        'Microsoft YaHei UI',
      ]);
      final text = EmojiText.spanOf(
        '星海 A B 👩🏽‍💻 追番',
        customTheme.bodyTextStyle,
        emojiFamily: 'Twemoji',
        pattern: kEmojiPattern,
      );
      final spans = text.children!.cast<TextSpan>();
      expect(spans.map((span) => span.text), ['星海 A B ', '👩🏽‍💻', ' 追番']);
      expect(spans[1].style?.fontFamily, 'Twemoji');
    },
  );

  testWidgets(
    'narrow toolbar stays above scrolling and uses mobile push and back',
    (tester) async {
      _setViewport(tester, const Size(320, 720));
      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();

      final toolbar = find.byType(ScaffoldBar);
      final origin = tester.getTopLeft(toolbar);
      final scrollable = find.byType(CustomScrollView);
      await tester.drag(scrollable, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(toolbar), origin);
      expect(find.byType(FloatingHeader), findsOneWidget);

      final search = _barAction('发现搜索');
      expect(tester.widget(search), isA<AppBarActionButton>());
      expect(
        find.ancestor(of: search, matching: find.byType(ElasticPress)),
        findsOneWidget,
      );
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(tester.element(find.byType(DiscoverPage))),
        isA<CardPageRoute<void>>(),
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle?.fontSize,
        AppTextStyle.headline.size,
      );
      await tester.tap(_barAction('返回'));
      await tester.pumpAndSettle();
      expect(search, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'schedule and library use FlClash sheets for season/filter/status selection',
    (tester) async {
      _setViewport(tester, const Size(390, 820));
      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();

      Finder dockItem(String label) => find.descendant(
        of: find.byType(NavigationDock),
        matching: find.text(label),
      );

      // Schedule page opens FlClash settings sheet with year/season picker
      await tester.tap(dockItem('时间表'));
      await tester.pumpAndSettle();
      await tester.tap(_barAction('放送设置与季度切换'));
      await tester.pumpAndSettle();
      expect(find.text('放送时间表设置'), findsOneWidget);
      expect(find.text('切换年份与季度'), findsOneWidget);
      await tester.tap(_barAction('关闭'));
      await tester.pumpAndSettle();

      // Library page has FlClash inline expanding search & clean 2-button toolbar
      await tester.tap(dockItem('追番'));
      await tester.pumpAndSettle();
      expect(_barAction('搜索追番库'), findsOneWidget);
      expect(_barAction('排序与同步设置'), findsOneWidget);
      expect(
        tester.widget<AppBarActionButton>(_barAction('排序与同步设置')).data.glyph,
        KonekoGlyphs.tune,
      );

      // Verify FlClash inline AppBar search expands and closes cleanly
      await tester.tap(_barAction('搜索追番库'));
      await tester.pumpAndSettle();
      expect(_barAction('关闭搜索'), findsOneWidget);
      await tester.tap(_barAction('关闭搜索'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('修改「星海旅人：北境编年史」的追番状态'));
      await tester.pumpAndSettle();
      expect(find.text('修改追番状态'), findsOneWidget);
      await tester.tap(find.text('想看').first);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Discover page opens FlClash condition filter sheet (no image search)
      await tester.tap(dockItem('推荐'));
      await tester.pumpAndSettle();
      await tester.tap(_barAction('发现搜索'));
      await tester.pumpAndSettle();
      expect(find.text('以图搜番'), findsNothing);
      await tester.tap(_barAction('按条件筛选'));
      await tester.pumpAndSettle();
      expect(find.text('按条件搜索'), findsOneWidget);
      await tester.tap(_barAction('关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop push fades inside the sidebar content', (tester) async {
    _setViewport(tester, const Size(1100, 800));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(_barAction('发现搜索'));
    await tester.pumpAndSettle();
    final page = find.byType(DiscoverPage);
    expect(ModalRoute.of(tester.element(page)), isA<FadePageRoute<void>>());
    expect(find.byType(NavigationSidebar), findsOneWidget);
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle?.fontSize,
      AppTextStyle.pageTitle.size,
    );
    await tester.tap(_barAction('返回'));
    await tester.pumpAndSettle();
    expect(page, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SubjectDetailPage shows prominent play action, toggleable source and comments tab',
    (tester) async {
      _setViewport(tester, const Size(420, 880));
      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();

      // Home top deck no longer shows cluttery "已启用规则" stat and top-right has History shortcut
      expect(find.text('已启用规则'), findsNothing);
      expect(_barAction('观看历史'), findsOneWidget);

      await tester.tap(find.text('星海旅人：北境编年史').first);
      await tester.pumpAndSettle();

      expect(find.byType(SubjectDetailPage), findsOneWidget);
      expect(find.byType(KonekoStarRating), findsOneWidget);
      expect(find.textContaining('播放 · 第'), findsOneWidget);

      // Selecting and tapping again cancels the specified playback source
      final firstRule = find.text('樱花源 · XPath');
      final detailScroll = find
          .descendant(
            of: find.byType(SubjectDetailPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(firstRule, 160, scrollable: detailScroll);
      await tester.pumpAndSettle();
      await tester.tap(firstRule);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('已指定'), findsOneWidget);

      await tester.tap(firstRule);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('已指定'), findsNothing);

      final relatedTab = find.text('关联');
      await tester.ensureVisible(relatedTab);
      await tester.pumpAndSettle();
      await tester.tap(relatedTab);
      await tester.pumpAndSettle();
      expect(find.textContaining('关联系列'), findsWidgets);

      await tester.tap(find.text('角色'));
      await tester.pumpAndSettle();
      expect(find.text('暂无角色'), findsOneWidget);

      final commentsTab = find.textContaining('评论');
      await tester.ensureVisible(commentsTab.first);
      await tester.pumpAndSettle();
      await tester.tap(commentsTab.first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bangumi 吐槽箱'), findsOneWidget);
      expect(find.text('星屑旅人'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail retains the visible episode grid through the push', (
    tester,
  ) async {
    _setViewport(tester, const Size(420, 880));
    final catalog = _PendingCatalog();
    addTearDown(catalog.events.close);
    await tester.pumpWidget(_testApp(catalog: catalog));
    await tester.pumpAndSettle();

    await tester.tap(find.text('星海旅人：北境编年史').first);
    await tester.pump();
    final detail = find.byType(SubjectDetailPage);
    final route = ModalRoute.of(tester.element(detail))!;
    final overview = tester.renderObject(
      find.descendant(of: detail, matching: find.byType(KonekoStarRating)),
    );
    final episodeSnapshot = find.byKey(
      const ValueKey('episode-arrival-snapshot'),
    );
    final firstReads = catalog.episodeReads;
    expect(firstReads, 1);
    expect(find.text('选集'), findsOneWidget);
    expect(
      tester
          .widget<SnapshotWidget>(episodeSnapshot)
          .controller
          .allowSnapshotting,
      isTrue,
    );
    final oldProfiling = debugProfilePaintsEnabled;
    final oldPaint = debugOnProfilePaint;
    var overviewPaints = 0;
    debugProfilePaintsEnabled = true;
    debugOnProfilePaint = (object) {
      if (identical(object, overview)) overviewPaints++;
    };
    addTearDown(() {
      debugProfilePaintsEnabled = oldProfiling;
      debugOnProfilePaint = oldPaint;
    });

    var motionFrames = 0;
    var episodeReadsDuringMotion = 0;
    var sourceReadsDuringMotion = 0;
    var episodeRequestsDuringMotion = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (route.animation!.isCompleted) break;
      if (route.animation!.value > 0) motionFrames++;
      episodeReadsDuringMotion = catalog.episodeReads;
      sourceReadsDuringMotion = catalog.sourceReads;
      episodeRequestsDuringMotion = catalog.episodeRequests;
    }

    final counts = (
      frames: motionFrames,
      episodeReads: episodeReadsDuringMotion,
      sourceReads: sourceReadsDuringMotion,
      episodeRequests: episodeRequestsDuringMotion,
      overviewPaints: overviewPaints,
    );
    debugPrint('Detail push work $counts');
    expect(motionFrames, greaterThan(2));
    expect(episodeReadsDuringMotion, firstReads, reason: '$counts');
    expect(episodeRequestsDuringMotion, 0, reason: '$counts');
    expect(sourceReadsDuringMotion, lessThanOrEqualTo(1), reason: '$counts');
    expect(overviewPaints, lessThanOrEqualTo(2), reason: '$counts');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SnapshotWidget>(episodeSnapshot)
          .controller
          .allowSnapshotting,
      isFalse,
    );
    expect(catalog.episodeRequests, 1);
    final source = find.text('樱花源 · XPath');
    final scrollable = find
        .descendant(of: detail, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(source, 160, scrollable: scrollable);
    await tester.pumpAndSettle();
    final episodeReads = catalog.episodeReads;
    await tester.tap(source);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(catalog.episodeReads, episodeReads);
    expect(find.text('已指定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail loads one role indicator and retains visited requests', (
    tester,
  ) async {
    _setViewport(tester, const Size(420, 880));
    final catalog = _PendingCatalog();
    addTearDown(catalog.events.close);
    await tester.pumpWidget(_testApp(catalog: catalog));
    await tester.pumpAndSettle();

    await tester.tap(find.text('星海旅人：北境编年史').first);
    await tester.pump();
    expect(catalog.episodeRequests, 0);
    await tester.pumpAndSettle();
    expect(catalog.episodeRequests, 1);
    expect(catalog.characterRequests, 0);
    expect(catalog.creditRequests, 0);
    expect(catalog.relationRequests, 0);
    expect(catalog.commentRequests, 0);

    final peopleSkeleton = find.descendant(
      of: find.byType(SubjectDetailPage),
      matching: find.byKey(const ValueKey('people-loading-skeleton')),
    );
    await tester.ensureVisible(find.text('角色'));
    await tester.tap(find.text('角色'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(peopleSkeleton, findsOneWidget);
    expect(catalog.characterRequests, 1);
    expect(catalog.creditRequests, 1);

    catalog.characters.complete(const [
      SubjectCharacter(id: 1, name: '测试角色', relation: '主角'),
    ]);
    await tester.pumpAndSettle();
    expect(peopleSkeleton, findsNothing);
    expect(find.text('测试角色'), findsOneWidget);

    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('角色'));
    await tester.pumpAndSettle();
    expect(peopleSkeleton, findsNothing);
    expect(catalog.characterRequests, 1);
    expect(catalog.creditRequests, 1);

    catalog.credits.complete(const [SubjectPerson(id: 2, name: '测试制作')]);
    await tester.pumpAndSettle();
    expect(find.text('测试制作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long-title detail starts and stays at the top on arrival', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 460));
    final catalog = _LongTitleCatalog();
    addTearDown(catalog.events.close);
    await tester.pumpWidget(_testApp(catalog: catalog));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_LongTitleCatalog.title).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final detail = find.byType(SubjectDetailPage);
    final scrollable = find
        .descendant(of: detail, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    final expandButton = find.descendant(
      of: detail,
      matching: find.text('展开全部'),
    );
    final commentsTab = find.descendant(of: detail, matching: find.text('评论'));
    expect(expandButton, findsOneWidget);
    final initialTabY = tester.getTopLeft(commentsTab).dy;
    await tester.pumpAndSettle();
    expect(expandButton, findsOneWidget);
    expect(tester.getTopLeft(commentsTab).dy, closeTo(initialTabY, 0.001));

    catalog.detail.complete();
    await tester.pumpAndSettle();
    expect(position.pixels, 0);

    expect(
      find.descendant(of: detail, matching: find.text('展开全部')),
      findsOneWidget,
    );
    final secondRange = find.descendant(
      of: detail,
      matching: find.text('25-25'),
    );
    await tester.scrollUntilVisible(secondRange, 160, scrollable: scrollable);
    await tester.pumpAndSettle();
    expect(secondRange, findsOneWidget);
    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hidden home tab does not refresh its feed', (tester) async {
    _setViewport(tester, const Size(420, 880));
    final catalog = _PendingCatalog();
    addTearDown(catalog.events.close);
    await tester.pumpWidget(_testApp(catalog: catalog));
    await tester.pumpAndSettle();

    final dock = find.byType(NavigationDock);
    await tester.tap(find.descendant(of: dock, matching: find.text('追番')));
    await tester.pumpAndSettle();
    final hiddenReads = catalog.trendingReads;
    catalog.events.add(null);
    catalog.events.add(null);
    await tester.pumpAndSettle();
    expect(catalog.trendingReads, hiddenReads);

    await tester.tap(find.descendant(of: dock, matching: find.text('推荐')));
    await tester.pumpAndSettle();
    expect(catalog.trendingReads, greaterThan(hiddenReads));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'HistoryPage shows latest source with capsule play/next buttons and no multi-source badge',
    (tester) async {
      _setViewport(tester, const Size(1100, 800));
      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();

      final historyTab = find.descendant(
        of: find.byType(NavigationSidebar),
        matching: find.text('观看历史'),
      );
      await tester.tap(historyTab);
      await tester.pumpAndSettle();

      expect(find.textContaining('个播放源'), findsNothing);
      expect(find.text('继续播放'), findsWidgets);
      expect(find.text('下一话'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sheets and dialogs use render-layer barriers and settle cleanly',
    (tester) async {
      _setViewport(tester, const Size(390, 820));
      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();

      // Open schedule bottom sheet -> verify AnimatedBarrierPaint & lazy year list
      final dock = find.byType(NavigationDock);
      await tester.tap(find.descendant(of: dock, matching: find.text('时间表')));
      await tester.pumpAndSettle();
      await tester.tap(_barAction('放送设置与季度切换'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(AnimatedBarrierPaint), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('放送时间表设置'), findsOneWidget);
      await tester.tap(_barAction('关闭'));
      await tester.pumpAndSettle();

      // Push ThemePage -> verify lazy ArrivalCacheExtentBuilder & live preview
      await tester.tap(find.descendant(of: dock, matching: find.text('我的')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观主题'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemePage), findsOneWidget);
      expect(find.byType(ThemeLivePreview), findsOneWidget);
      await tester.tap(_barAction('返回'));
      await tester.pumpAndSettle();

      // Push AboutPage -> verify scroll drives ValueNotifier without errors
      final aboutRow = find.text('关于 Koneko');
      await tester.ensureVisible(aboutRow);
      await tester.pumpAndSettle();
      await tester.tap(aboutRow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AboutPage), findsOneWidget);
      final aboutScroll = find
          .descendant(
            of: find.byType(AboutPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(aboutScroll, const Offset(0, -180));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail renders placeholder skeletons for partial subjects without layout jumping',
    (tester) async {
      _setViewport(tester, const Size(420, 880));
      final catalog = _PartialDetailCatalog();
      addTearDown(catalog.events.close);
      await tester.pumpWidget(_testApp(catalog: catalog));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_PartialDetailCatalog.title).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      final detail = find.byType(SubjectDetailPage);
      expect(detail, findsOneWidget);
      expect(
        find.byKey(const ValueKey('hero-rating-skeleton')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('hero-meta-skeleton')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('hero-synopsis-skeleton')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('episodes-skeleton')), findsOneWidget);

      final tabBar = find.descendant(
        of: detail,
        matching: find.text('评论'),
      );
      final beforeTabY = tester.getTopLeft(tabBar).dy;

      catalog.completeAll();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('hero-rating-skeleton')), findsNothing);
      expect(find.byKey(const ValueKey('hero-meta-skeleton')), findsNothing);
      expect(
        find.byKey(const ValueKey('hero-synopsis-skeleton')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('episodes-skeleton')), findsNothing);
      expect(find.text('共 12 话'), findsWidgets);
      expect(find.byType(KonekoStarRating), findsOneWidget);

      final afterTabY = tester.getTopLeft(tabBar).dy;
      expect((afterTabY - beforeTabY).abs(), lessThan(20));
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _barAction(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is AppBarActionButton && widget.data.tooltip == tooltip,
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _testApp({CatalogRepository? catalog}) => ProviderScope(
  overrides: [
    catalogRepositoryProvider.overrideWithValue(
      catalog ?? MockCatalogRepository(),
    ),
    ruleRepositoryProvider.overrideWithValue(MockRuleRepository()),
    libraryProvider.overrideWith(_FixtureLibrary.new),
    historyProvider.overrideWith(_FixtureHistory.new),
  ],
  child: const KonekoApp(),
);

class _FixtureLibrary extends LibraryNotifier {
  @override
  List<CollectionEntry> build() => MockSeedData.initialCollections();
}

class _FixtureHistory extends HistoryNotifier {
  @override
  List<MergedHistoryEntry> build() => MockSeedData.initialMergedHistory();
}

class _PendingCatalog extends MockCatalogRepository implements OnlineCatalog {
  final events = StreamController<void>.broadcast();
  final characters = Completer<List<SubjectCharacter>>();
  final credits = Completer<List<SubjectPerson>>();
  int episodeRequests = 0;
  int episodeReads = 0;
  int sourceReads = 0;
  int characterRequests = 0;
  int creditRequests = 0;
  int relationRequests = 0;
  int commentRequests = 0;
  int trendingReads = 0;

  @override
  Stream<void> get changes => events.stream;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadSubject(int id, {bool includeExtras = true}) async {
    if (includeExtras) {
      await loadEpisodes(id);
      await loadRelations(id);
    }
  }

  @override
  List<EpisodeItem> getEpisodes(
    int id, {
    int watchedCount = 0,
    int? currentEp,
  }) {
    episodeReads++;
    return super.getEpisodes(
      id,
      watchedCount: watchedCount,
      currentEp: currentEp,
    );
  }

  @override
  List<RuleSourceProbe> probeSources(int id) {
    sourceReads++;
    return super.probeSources(id);
  }

  @override
  Future<void> loadEpisodes(int id) async {
    episodeRequests++;
  }

  @override
  Future<List<SubjectCharacter>> loadCharacters(int id) {
    characterRequests++;
    return characters.future;
  }

  @override
  Future<List<SubjectPerson>> loadCredits(int id) {
    creditRequests++;
    return credits.future;
  }

  @override
  Future<List<SubjectRelation>> loadRelations(int id) async {
    relationRequests++;
    return [];
  }

  @override
  Future<SubjectCommentsPage> loadComments(
    int id, {
    int offset = 0,
    int limit = 20,
  }) async {
    commentRequests++;
    return const SubjectCommentsPage(items: [], total: 0, hasMore: false);
  }

  @override
  List<AnimeSubject> getTrending({String? tag}) {
    trendingReads++;
    return super.getTrending(tag: tag);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LongTitleCatalog extends _PendingCatalog {
  static const title = '乱世千金倪亚‧利斯顿转生为娇弱千金的弑神武人华丽无双录';
  static const id = 624085;
  final detail = Completer<void>();
  bool _loaded = false;

  @override
  List<AnimeSubject> getTrending({String? tag}) => [getSubjectById(id)!];

  @override
  AnimeSubject? getSubjectById(int subjectId) => subjectId != id
      ? super.getSubjectById(subjectId)
      : AnimeSubject(
          subjectId: id,
          title: title,
          originalTitle: '凶乱令嬢ニア・リストン 病弱令嬢に転生した神殺しの武人の華麗なる無双録',
          summary: List.filled(_loaded ? 48 : 32, '转生之后展开的新冒险。').join(),
          score: 6.8,
          rank: 3549,
          year: 2026,
          seasonLabel: '2026 年 10 月',
          weekday: 2,
          airedEpisodes: 9,
          totalEpisodes: 25,
          tags: const ['动画', '转生', '战斗'],
          studio: _loaded ? '动画制作' : '',
          poster: super.getSubjectById(1001)!.poster,
        );

  @override
  Future<void> loadSubject(int subjectId, {bool includeExtras = true}) async {
    await detail.future;
    _loaded = true;
    events.add(null);
  }
}

class _PartialDetailCatalog extends _PendingCatalog {
  static const title = '占位骨架测试番剧';
  static const id = 777001;
  final detail = Completer<void>();
  final episodesGate = Completer<void>();
  bool _detailLoaded = false;
  bool _episodesLoaded = false;

  void completeAll() {
    _detailLoaded = true;
    _episodesLoaded = true;
    if (!detail.isCompleted) detail.complete();
    if (!episodesGate.isCompleted) episodesGate.complete();
    events.add(null);
  }

  @override
  List<AnimeSubject> getTrending({String? tag}) => [getSubjectById(id)!];

  @override
  AnimeSubject? getSubjectById(int subjectId) {
    if (subjectId != id) return super.getSubjectById(subjectId);
    final seed = super.getSubjectById(1001)!;
    return AnimeSubject(
      subjectId: id,
      title: title,
      originalTitle: '',
      summary: _detailLoaded
          ? List.filled(18, '这是一段用于校验详情页占位骨架无缝切换的简介文本。').join()
          : '',
      score: _detailLoaded ? 8.4 : 0,
      rank: _detailLoaded ? 215 : 0,
      year: _detailLoaded ? 2026 : 0,
      seasonLabel: _detailLoaded ? '2026 年 4 月' : '',
      weekday: 5,
      airedEpisodes: _episodesLoaded ? 12 : 0,
      totalEpisodes: _detailLoaded ? 12 : 0,
      tags: const ['动画'],
      studio: _detailLoaded ? '测试动画社' : '',
      poster: seed.poster,
    );
  }

  @override
  List<EpisodeItem> getEpisodes(
    int subjectId, {
    int watchedCount = 0,
    int? currentEp,
  }) {
    if (subjectId != id) {
      return super.getEpisodes(
        subjectId,
        watchedCount: watchedCount,
        currentEp: currentEp,
      );
    }
    if (!_episodesLoaded) return const [];
    return [
      for (var ep = 1; ep <= 12; ep++)
        EpisodeItem(
          episodeNumber: ep,
          title: '第 $ep 话',
          airDate: '2026-04-01',
          state: ep == (currentEp ?? 1)
              ? EpisodeWatchState.current
              : EpisodeWatchState.aired,
        ),
    ];
  }

  @override
  Future<void> loadSubject(int subjectId, {bool includeExtras = true}) async {
    if (subjectId == id) await detail.future;
  }

  @override
  Future<void> loadEpisodes(int subjectId) async {
    if (subjectId == id) await episodesGate.future;
  }
}
