import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/features/discover/discover_page.dart';
import 'package:koneko/main.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:koneko_mock/koneko_mock.dart';
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
      await tester.ensureVisible(firstRule);
      await tester.pumpAndSettle();
      await tester.tap(firstRule);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('已指定'), findsOneWidget);

      await tester.tap(firstRule);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('已指定'), findsNothing);

      await tester.tap(find.text('关联'));
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

Widget _testApp() => ProviderScope(
  overrides: [
    catalogRepositoryProvider.overrideWithValue(MockCatalogRepository()),
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
