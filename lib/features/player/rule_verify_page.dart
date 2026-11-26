import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

/// Visible interactive WebView page where the user completes a site's
/// human-verification prompt directly, then saves session cookies back to Koneko.
class RuleVerifyPage extends ConsumerStatefulWidget {
  const RuleVerifyPage({
    super.key,
    required this.ruleId,
    required this.ruleName,
    required this.verifyUrl,
  });

  final String ruleId;
  final String ruleName;
  final Uri verifyUrl;

  @override
  ConsumerState<RuleVerifyPage> createState() => _RuleVerifyPageState();
}

class _RuleVerifyPageState extends ConsumerState<RuleVerifyPage> {
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

    return KonekoScaffold(
      title: '${widget.ruleName} · 网页验证',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: Glyphs.check,
          tooltip: '完成验证',
          isLoading: _saving,
          onPressed: _harvest == null ? null : _complete,
        ),
      ],
      body: Builder(
        builder: (context) => Column(
          children: [
            SizedBox(height: context.contentTopPadding),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: KonekoBlock(
                corner: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: Text(
                        '请在下方网页中亲自完成验证，看到正常页面后点击右上角「✓」继续搜索。',
                        style: AppTextStyle.caption1
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    KonekoChip(
                      label: _saving ? '保存中...' : '我已完成',
                      height: 28,
                      fontSize: 12,
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      onPressed: _harvest == null || _saving ? null : _complete,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: builder == null
                  ? const Center(child: Text('当前环境不支持内嵌网页验证'))
                  : builder(
                      widget.verifyUrl,
                      (harvester) {
                        if (mounted) setState(() => _harvest = harvester);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
