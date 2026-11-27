import 'package:flutter/widgets.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:prism_ui/prism_ui.dart';

class SubjectSynopsis extends StatefulWidget {
  const SubjectSynopsis({super.key, required this.summary});

  final String summary;

  @override
  State<SubjectSynopsis> createState() => _SubjectSynopsisState();
}

class _SubjectSynopsisState extends State<SubjectSynopsis> {
  TextPainter? _paragraph;
  Object? _layoutInputs;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _paragraph?.dispose();
    super.dispose();
  }

  void _fontsChanged() => setState(() => _layoutInputs = null);

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final defaults = DefaultTextStyle.of(context);
    final style = defaults.style.merge(
      AppTextStyle.subheadline
          .of(context)
          .copyWith(color: colors.onSurfaceVariant, height: 1.55),
    );
    final textScale = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final heightBehavior =
        DefaultTextHeightBehavior.maybeOf(context) ??
        defaults.textHeightBehavior;
    return KonekoBlock(
      corner: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inputs = (
            widget.summary,
            style,
            textScale,
            direction,
            locale,
            heightBehavior,
            defaults.textAlign,
            defaults.textWidthBasis,
            constraints.maxWidth,
            _expanded,
          );
          if (_layoutInputs != inputs) {
            _paragraph?.dispose();
            _paragraph =
                TextPainter(
                  text: TextSpan(text: widget.summary, style: style),
                  textDirection: direction,
                  textScaler: textScale,
                  locale: locale,
                  textAlign: defaults.textAlign ?? TextAlign.start,
                  textHeightBehavior: heightBehavior,
                  textWidthBasis: defaults.textWidthBasis,
                  maxLines: _expanded ? null : 3,
                  ellipsis: _expanded ? null : '…',
                )..layout(
                  minWidth: constraints.maxWidth,
                  maxWidth: constraints.maxWidth,
                );
            _layoutInputs = inputs;
          }
          final paragraph = _paragraph!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: context.motionDuration(
                  const Duration(milliseconds: 220),
                ),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Semantics(
                  label: widget.summary,
                  textDirection: direction,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, paragraph.height),
                    painter: _SynopsisPainter(paragraph),
                  ),
                ),
              ),
              if (_expanded || paragraph.didExceedMaxLines) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: PressSurface(
                    fill: Colors.transparent,
                    shape: AppShape.full,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? '收起' : '展开全部',
                      style: AppTextStyle.caption1
                          .of(context, emphasized: true)
                          .copyWith(color: colors.primary),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SynopsisPainter extends CustomPainter {
  const _SynopsisPainter(this.paragraph);

  final TextPainter paragraph;

  @override
  void paint(Canvas canvas, Size size) => paragraph.paint(canvas, Offset.zero);

  @override
  bool shouldRepaint(_SynopsisPainter oldDelegate) =>
      !identical(oldDelegate.paragraph, paragraph);
}
