import 'package:flutter/widgets.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Opens a native FlClash / prism_ui sheet:
/// - Mobile: floating rounded bottom sheet with drag handle & snap detents.
/// - Desktop / Wide: right-hand modal side sheet.
Future<T?> showKonekoSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  List<IconButtonData> actions = const [],
  required WidgetBuilder bodyBuilder,
  WidgetBuilder? footerBuilder,
  List<double> detents = const [0.68, 0.92],
}) {
  return showSheet<T>(
    context: context,
    props: SheetProps(detents: detents),
    builder: (sheetContext) => KonekoSheetFrame(
      title: title,
      subtitle: subtitle,
      actions: actions,
      footer: footerBuilder?.call(sheetContext),
      child: bodyBuilder(sheetContext),
    ),
  );
}

/// FlClash-styled inner scaffold for modal sheets (bottom sheet or side sheet).
class KonekoSheetFrame extends StatelessWidget {
  const KonekoSheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.footer,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final List<IconButtonData> actions;
  final Widget? footer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final sheetType = SheetProvider.of(context)?.type;
    final isBottom = sheetType == SheetType.bottomSheet;
    final bg = SurfaceLevel.page.colorOf(colorScheme);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final content = SurfaceScope(
      level: SurfaceLevel.page,
      child: ColoredBox(
        color: bg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isBottom) const Center(child: SheetDragHandle()),
            Padding(
              padding: EdgeInsets.fromLTRB(20, isBottom ? 10 : 18, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 8,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.title3
                              .of(context, emphasized: true)
                              .copyWith(color: colorScheme.onSurface),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  TonalButtonTheme(
                    size: TonalButtonSize.section,
                    glass: LiquidGlassScope.of(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        for (final action in actions)
                          AppBarActionButton(data: action),
                        AppBarActionButton(
                          data: IconButtonData(
                            glyph: Glyphs.close,
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
            if (footer != null)
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  14 + (isBottom ? bottomInset : 0),
                ),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                    top: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.28),
                    ),
                  ),
                ),
                child: footer!,
              )
            else if (isBottom && bottomInset > 0)
              SizedBox(height: bottomInset),
          ],
        ),
      ),
    );

    if (isBottom) {
      return ClipRSuperellipse(
        borderRadius: bottomSheetRadiusOf(context),
        child: content,
      );
    }
    return content;
  }
}

/// Sentinel result for [showKonekoStatusSheet].
class CollectionStatusChoice {
  const CollectionStatusChoice.set(this.status) : remove = false;
  const CollectionStatusChoice.remove() : status = null, remove = true;

  final CollectionStatus? status;
  final bool remove;
}

/// Opens a FlClash-styled Sheet for explicitly picking a Bangumi/Kazumi
/// collection status (or removing from library), replacing accidental cycling.
Future<CollectionStatusChoice?> showKonekoStatusSheet({
  required BuildContext context,
  required String subjectTitle,
  required CollectionStatus? currentStatus,
}) {
  const descriptions = <CollectionStatus, String>{
    CollectionStatus.watching: '正在追更，优先展示在追番列表',
    CollectionStatus.wish: '先加入计划清单，稍后观看',
    CollectionStatus.watched: '已经看完并归档记录',
    CollectionStatus.onHold: '暂时搁置，之后继续补番',
    CollectionStatus.dropped: '已弃番，不再继续追更',
  };

  return showKonekoSheet<CollectionStatusChoice>(
    context: context,
    title: '修改追番状态',
    subtitle: subjectTitle,
    detents: const [0.58, 0.8],
    bodyBuilder: (sheetContext) {
      final colorScheme = sheetContext.colorScheme;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          KonekoGroup(
            items: [
              for (final status in CollectionStatus.values)
                DecorationListItem(
                  leading: GlyphIcon(
                    konekoStatusGlyph(status),
                    fill: currentStatus == status ? 1 : 0,
                    color: konekoStatusColor(status),
                  ),
                  title: Text(status.label),
                  subtitle: Text(descriptions[status] ?? ''),
                  trailing: currentStatus == status
                      ? GlyphIcon(Glyphs.check, color: colorScheme.primary)
                      : null,
                  onPressed: () => Navigator.of(
                    sheetContext,
                  ).pop(CollectionStatusChoice.set(status)),
                ),
            ],
          ),
          if (currentStatus != null) ...[
            const SizedBox(height: 12),
            KonekoBlock(
              corner: 20,
              color: colorScheme.errorContainer.withValues(alpha: 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              onPressed: () => Navigator.of(
                sheetContext,
              ).pop(const CollectionStatusChoice.remove()),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  GlyphIcon(
                    KonekoGlyphs.trash,
                    size: 16,
                    color: colorScheme.onErrorContainer,
                  ),
                  Text(
                    '移出追番列表',
                    style: AppTextStyle.subheadline
                        .of(sheetContext, emphasized: true)
                        .copyWith(color: colorScheme.onErrorContainer),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}
