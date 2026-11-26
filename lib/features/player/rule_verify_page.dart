import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_sheet.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Presents a sleek FlClash modal Sheet where the user themselves completes
/// a rule site's human verification right in place (without navigating away
/// to a full-screen browser page), then saves the resulting session cookies.
Future<bool?> showRuleVerifySheet({
  required BuildContext context,
  required String ruleId,
  required String ruleName,
  required Uri verifyUrl,
}) {
  return showKonekoSheet<bool>(
    context: context,
    title: '站点验证 · $ruleName',
    subtitle: '完成下方验证后点击底部按钮，将自动保存状态并继续检索',
    detents: const [0.78, 0.94],
    bodyBuilder: (sheetContext) => _RuleVerifySheetBody(
      ruleId: ruleId,
      ruleName: ruleName,
      verifyUrl: verifyUrl,
    ),
  );
}

class _RuleVerifySheetBody extends ConsumerStatefulWidget {
  const _RuleVerifySheetBody({
    required this.ruleId,
    required this.ruleName,
    required this.verifyUrl,
  });

  final String ruleId;
  final String ruleName;
  final Uri verifyUrl;

  @override
  ConsumerState<_RuleVerifySheetBody> createState() =>
      _RuleVerifySheetBodyState();
}

class _RuleVerifySheetBodyState extends ConsumerState<_RuleVerifySheetBody> {
  Future<({String cookies, String userAgent})> Function()? _harvest;
  bool _saving = false;

  Future<void> _complete() async {
    final harvest = _harvest;
    final sources = ref.read(playbackSourcesProvider);
    if (harvest == null || sources == null || _saving) return;
    setState(() => _saving = true);
    try {
      final session = await harvest();
      await sources.saveVerificationCookies(
        widget.ruleId,
        widget.verifyUrl,
        session.cookies,
        userAgent: session.userAgent,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '读取验证状态失败，请重试', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final builder = ref.watch(verifyWebViewBuilderProvider);
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: KonekoCard(
              corner: 22,
              padding: EdgeInsets.zero,
              clip: true,
              child: builder == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '当前环境不支持内嵌网页验证',
                          style: AppTextStyle.subheadline
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : builder(
                      widget.verifyUrl,
                      (harvester) {
                        if (mounted) setState(() => _harvest = harvester);
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            spacing: 10,
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              Expanded(
                child: PressSurface(
                  fill: _harvest == null || _saving
                      ? colorScheme.primary.withValues(alpha: 0.45)
                      : colorScheme.primary,
                  shape: AppShape.full,
                  clipsChild: true,
                  onPressed: _harvest == null || _saving ? null : _complete,
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 6,
                      children: [
                        if (_saving)
                          const ActivityIndicator(color: Colors.white)
                        else
                          GlyphIcon(
                            Glyphs.check,
                            size: 16,
                            color: colorScheme.onPrimary,
                          ),
                        Text(
                          _saving ? '正在保存验证状态...' : '我已完成验证，继续检索',
                          style: AppTextStyle.subheadline
                              .of(context, emphasized: true)
                              .copyWith(color: colorScheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
