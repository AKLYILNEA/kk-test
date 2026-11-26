import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koneko/main.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:koneko_mock/koneko_mock.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test('Animeko multi-source history merges legacy Kazumi records by subjectId', () {
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
  });

  testWidgets('KonekoApp renders mobile shell and switches tabs', (tester) async {
    tester.view.physicalSize = const Size(420, 880);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const ProviderScope(child: KonekoApp()));
    await tester.pumpAndSettle();

    expect(find.text('推荐'), findsWidgets);
    expect(find.text('追番'), findsOneWidget);

    await tester.tap(find.text('追番'));
    await tester.pumpAndSettle();
    expect(find.text('星海旅人：北境编年史'), findsWidgets);
  });
}
