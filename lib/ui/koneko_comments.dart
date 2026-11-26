import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/constants.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_image.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Reusable Bangumi 吐槽箱 comments panel used in both SubjectDetailPage and PlayerPage.
/// Both modes present comments inside clean FlClash elevated cards.
class KonekoCommentsPanel extends ConsumerStatefulWidget {
  const KonekoCommentsPanel({
    super.key,
    required this.subjectId,
    this.embedded = false,
    this.bottomPadding = 20,
  });

  final int subjectId;

  /// When true, renders as a scrollable list of elevated [KonekoCard] items
  /// (e.g. inside PlayerPage's Comments tab); when false, wraps inside a single
  /// outer [KonekoCard] section.
  final bool embedded;
  final double bottomPadding;

  @override
  ConsumerState<KonekoCommentsPanel> createState() =>
      _KonekoCommentsPanelState();
}

class _KonekoCommentsPanelState extends ConsumerState<KonekoCommentsPanel> {
  List<SubjectComment>? _overrideItems;
  int? _overrideTotal;
  bool? _overrideHasMore;
  bool _loadingMore = false;

  @override
  void didUpdateWidget(covariant KonekoCommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId) {
      _overrideItems = null;
      _overrideTotal = null;
      _overrideHasMore = null;
      _loadingMore = false;
    }
  }

  void _refresh() {
    setState(() {
      _overrideItems = null;
      _overrideTotal = null;
      _overrideHasMore = null;
    });
    ref.invalidate(subjectCommentsProvider(widget.subjectId));
  }

  Future<void> _loadMore(int offset) async {
    final online = ref.read(onlineCatalogProvider);
    if (online == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await online.loadComments(
        widget.subjectId,
        offset: offset,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _overrideItems = page.items;
        _overrideTotal = page.total;
        _overrideHasMore = page.hasMore;
      });
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '加载更多评论失败', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final commentsAsync = ref.watch(subjectCommentsProvider(widget.subjectId));
    final basePage = commentsAsync.value;
    final items = _overrideItems ?? basePage?.items ?? const <SubjectComment>[];
    final total = _overrideTotal ?? basePage?.total ?? items.length;
    final hasMore = _overrideHasMore ?? basePage?.hasMore ?? false;

    final header = Row(
      children: [
        Expanded(
          child: Text(
            total > 0 ? 'Bangumi 吐槽箱 ($total)' : 'Bangumi 吐槽箱',
            style: AppTextStyle.headline
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurface),
          ),
        ),
        KonekoChip(
          label: '刷新',
          height: 28,
          fontSize: 12,
          elevated: widget.embedded,
          backgroundColor: widget.embedded
              ? SurfaceLevel.card.colorOf(colorScheme)
              : null,
          leading: GlyphIcon(
            KonekoGlyphs.refresh,
            size: 13,
            color: colorScheme.primary,
          ),
          onPressed: _refresh,
        ),
      ],
    );

    Widget buildEmptyOrLoading() {
      if (commentsAsync.isLoading && items.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: ActivityIndicator()),
        );
      }
      if (commentsAsync.hasError && items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Column(
              spacing: 10,
              children: [
                Text(
                  '评论加载失败，请检查网络后重试',
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
                KonekoChip(
                  label: '重新加载',
                  height: 32,
                  fontSize: 12.5,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            '暂时还没有吐槽评论',
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    if (widget.embedded) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, widget.bottomPadding),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: header,
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            KonekoCard(
              corner: 24,
              padding: const EdgeInsets.all(16),
              child: buildEmptyOrLoading(),
            )
          else ...[
            for (var i = 0; i < items.length; i++) ...[
              _KonekoCommentTile(comment: items[i], cardized: true),
              if (i < items.length - 1) const SizedBox(height: 10),
            ],
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: KonekoChip(
                    label: _loadingMore ? '正在加载...' : '加载更多评论',
                    height: 36,
                    fontSize: 13,
                    elevated: true,
                    backgroundColor: SurfaceLevel.card.colorOf(colorScheme),
                    foregroundColor: colorScheme.primary,
                    onPressed: _loadingMore
                        ? null
                        : () => _loadMore(items.length),
                  ),
                ),
              ),
          ],
        ],
      );
    }

    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          if (items.isEmpty)
            buildEmptyOrLoading()
          else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                for (final comment in items)
                  _KonekoCommentTile(comment: comment, cardized: false),
              ],
            ),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Center(
                  child: KonekoChip(
                    label: _loadingMore ? '正在加载...' : '加载更多评论',
                    height: 36,
                    fontSize: 13,
                    backgroundColor: colorScheme.primary.withValues(
                      alpha: 0.14,
                    ),
                    foregroundColor: colorScheme.primary,
                    onPressed: _loadingMore
                        ? null
                        : () => _loadMore(items.length),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _KonekoCommentTile extends StatefulWidget {
  const _KonekoCommentTile({required this.comment, required this.cardized});

  final SubjectComment comment;
  final bool cardized;

  @override
  State<_KonekoCommentTile> createState() => _KonekoCommentTileState();
}

class _KonekoCommentTileState extends State<_KonekoCommentTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final c = widget.comment;
    final isLong =
        c.content.length > 140 || '\n'.allMatches(c.content).length >= 3;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KonekoAvatar(
              name: c.userName,
              avatarUrl: c.avatarUrl,
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline
                        .of(context, emphasized: true)
                        .copyWith(color: colorScheme.onSurface),
                  ),
                  Text(
                    formatRelativeTime(c.updatedAt),
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (c.rate > 0)
              KonekoChip(
                label: '${c.rate}',
                height: 22,
                fontSize: 11,
                leading: const GlyphIcon(
                  KonekoGlyphs.star,
                  size: 11,
                  color: Color(0xFFE09F24),
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          c.content,
          maxLines: _expanded ? null : 4,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(color: colorScheme.onSurface, height: 1.5),
        ),
        if (isLong) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: PressSurface(
              fill: Colors.transparent,
              shape: AppShape.full,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? '收起' : '展开全文',
                style: AppTextStyle.caption1
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.primary),
              ),
            ),
          ),
        ],
      ],
    );

    if (widget.cardized) {
      return KonekoCard(
        corner: 22,
        padding: const EdgeInsets.all(14),
        child: body,
      );
    }

    return KonekoBlock(
      corner: 18,
      padding: const EdgeInsets.all(13),
      child: body,
    );
  }
}
