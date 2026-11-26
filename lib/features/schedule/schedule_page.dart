import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key, this.bottomPadding = 0});

  final double bottomPadding;

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  static const _weekdays = [
    (1, '月', '周一'),
    (2, '火', '周二'),
    (3, '水', '周三'),
    (4, '木', '周四'),
    (5, '金', '周五'),
    (6, '土', '周六'),
    (7, '日', '周日'),
  ];

  int _selectedDay = DateTime.now().weekday;
  bool _sortByScore = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final catalog = ref.watch(catalogRepositoryProvider);
    final library = ref.watch(libraryProvider);
    final watchingIds = {
      for (final e in library)
        if (e.status == CollectionStatus.watching) e.subjectId,
    };

    final items = List<AnimeSubject>.from(catalog.getByWeekday(_selectedDay));
    if (_sortByScore) {
      items.sort((a, b) => b.score.compareTo(a.score));
    } else {
      items.sort((a, b) => b.airedEpisodes.compareTo(a.airedEpisodes));
    }

    return KonekoScaffold(
      title: '2026 秋季新番',
      actions: [
        IconButtonData(
          glyph: Glyphs.sort,
          tooltip: _sortByScore ? '当前：评分优先' : '当前：更新优先',
          onPressed: () => setState(() => _sortByScore = !_sortByScore),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          return CustomScrollView(
            slivers: [
              const KonekoScrollStart(),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: _weekdays.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final (dayNum, jp, cn) = _weekdays[index];
                      final count = catalog.getByWeekday(dayNum).length;
                      final selected = dayNum == _selectedDay;
                      return KonekoChip(
                        label: '$jp · $cn  $count',
                        height: 36,
                        fontSize: 13,
                        selected: selected,
                        backgroundColor: selected
                            ? colorScheme.primary
                            : SurfaceLevel.card.colorOf(colorScheme),
                        onPressed: () => setState(() => _selectedDay = dayNum),
                      );
                    },
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  24 + widget.bottomPadding,
                ),
                sliver: isWide
                    ? SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              mainAxisExtent: 124,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _ScheduleCard(
                            subject: items[index],
                            isWatching: watchingIds.contains(
                              items[index].subjectId,
                            ),
                            onTap: () => BaseNavigator.push<void>(
                              context,
                              SubjectDetailPage(
                                subjectId: items[index].subjectId,
                              ),
                            ),
                          ),
                          childCount: items.length,
                        ),
                      )
                    : SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => _ScheduleCard(
                          subject: items[index],
                          isWatching: watchingIds.contains(
                            items[index].subjectId,
                          ),
                          onTap: () => BaseNavigator.push<void>(
                            context,
                            SubjectDetailPage(
                              subjectId: items[index].subjectId,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.subject,
    required this.isWatching,
    required this.onTap,
  });

  final AnimeSubject subject;
  final bool isWatching;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 26,
      padding: const EdgeInsets.all(12),
      onPressed: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 100,
            child: KonekoPosterArt(
              subject: subject,
              borderRadius: AppRadius.all(16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  subject.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 3),
                Text(
                  '${subject.studio} · ${subject.tags.join(" / ")}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    KonekoChip(
                      label: subject.score.toStringAsFixed(1),
                      height: 24,
                      fontSize: 11.5,
                      leading: const GlyphIcon(
                        KonekoGlyphs.star,
                        size: 11,
                        color: Color(0xFFE09F24),
                      ),
                    ),
                    KonekoChip(
                      label: '更至 ${subject.airedEpisodes} 话',
                      height: 24,
                      fontSize: 11.5,
                    ),
                    if (isWatching)
                      KonekoChip(
                        label: '在追',
                        height: 24,
                        fontSize: 11.5,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.14,
                        ),
                        foregroundColor: colorScheme.primary,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
