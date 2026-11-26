import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/detail/subject_detail_page.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/prism_ui.dart';

/// 06B · Discover & Search Page with full-pill SearchField & unified anime cards.
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({
    super.key,
    this.showBack = true,
    this.bottomPadding = 0,
  });

  final bool showBack;
  final double bottomPadding;

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  static const _hotQueries = ['星海旅人', '青瓷药铺', '流光协奏曲', '科幻', '治愈'];
  static const _tags = ['全部', '奇幻', '治愈', '日常', '科幻', '悬疑', '音乐', '美食'];

  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String _tag = '全部';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyQuery(String q) {
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    setState(() => _query = q);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final catalog = ref.watch(catalogRepositoryProvider);
    final library = ref.watch(libraryProvider);
    final trackingIds = {
      for (final e in library)
        if (e.status == CollectionStatus.watching) e.subjectId,
    };
    final results = catalog.search(_query, tag: _tag);

    return Surface(
      color: SurfaceLevel.page.colorOf(colorScheme),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 1020
                ? 5
                : width >= 760
                    ? 4
                    : width >= 500
                        ? 3
                        : 2;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: KonekoPageHeader(
                    title: '发现搜索',
                    subtitle: '跨 Bangumi 目录与 Kazumi 规则源聚合检索',
                    showBack: widget.showBack,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: SearchField(
                      controller: _controller,
                      fill: SurfaceLevel.card.colorOf(colorScheme),
                      hintText: '搜索番名、原名、制作社或标签...',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final hot in _hotQueries)
                          KonekoChip(
                            label: '# $hot',
                            height: 28,
                            fontSize: 12,
                            backgroundColor:
                                SurfaceLevel.card.colorOf(colorScheme),
                            onPressed: () => _applyQuery(hot),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 36,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _tags.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final t = _tags[index];
                        final selected = t == _tag;
                        return KonekoChip(
                          label: t,
                          height: 34,
                          fontSize: 13,
                          selected: selected,
                          backgroundColor: selected
                              ? colorScheme.primary
                              : SurfaceLevel.card.colorOf(colorScheme),
                          onPressed: () => setState(() => _tag = t),
                        );
                      },
                    ),
                  ),
                ),
                if (results.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        '未找到匹配「$_query」的番剧',
                        style: AppTextStyle.subheadline.of(context).copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      14,
                      16,
                      24 + widget.bottomPadding,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.56,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final subject = results[index];
                          return UnifiedAnimeCard(
                            subject: subject,
                            isTracking: trackingIds.contains(subject.subjectId),
                            onTap: () => Navigator.of(context).push(
                              CardPageRoute<void>(
                                builder: (_) => SubjectDetailPage(
                                  subjectId: subject.subjectId,
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: results.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
