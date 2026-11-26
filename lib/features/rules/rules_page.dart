import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/feature_feedback.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

class RulesPage extends ConsumerStatefulWidget {
  const RulesPage({super.key, this.showBack = false});

  final bool showBack;

  @override
  ConsumerState<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends ConsumerState<RulesPage> {
  bool _testing = false;

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await ref.read(rulesProvider.notifier).testLatencies();
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '规则测速失败'),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _importFile(ManagedRules rules) async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
      );
      final path = picked?.path;
      if (path == null) return;
      final list = await rules.importRules(await File(path).readAsString());
      if (!mounted) return;
      ref.read(rulesProvider.notifier).replace(list);
      showKonekoBanner(context, '规则已导入', level: BannerLevel.success);
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '无法导入规则'),
          level: BannerLevel.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(ruleRepositoryProvider);
    final managed = repository is ManagedRules ? repository : null;
    final entries = ref.watch(rulesProvider);
    return KonekoScaffold(
      title: '规则管理',
      showBack: widget.showBack,
      actions: [
        if (managed != null) ...[
          IconButtonData(
            glyph: KonekoGlyphs.resources,
            tooltip: '规则仓库',
            onPressed: () => BaseNavigator.push<void>(
              context,
              _RuleStorePage(repository: managed),
            ),
          ),
          IconButtonData(
            glyph: KonekoGlyphs.importFile,
            tooltip: '导入规则文件',
            onPressed: () => _importFile(managed),
          ),
        ],
        IconButtonData(
          glyph: KonekoGlyphs.speed,
          tooltip: '全部测速',
          isLoading: _testing,
          onPressed: entries.isEmpty ? null : _test,
        ),
      ],
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding,
            16,
            28 + context.bottomInset,
          ),
          children: [
            if (managed != null)
              TextButton.icon(
                onPressed: () => BaseNavigator.push<void>(
                  context,
                  _RuleEditorPage(repository: managed),
                ),
                icon: const GlyphIcon(KonekoGlyphs.addCircle),
                label: const Text('粘贴 JSON 或 Kazumi 规则链接'),
              ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('添加一条播放规则后即可搜索线路。可以从规则仓库安装或导入自己的规则。'),
              ),
            for (final rule in entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: KonekoCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    spacing: 8,
                    children: [
                      const GlyphIcon(KonekoGlyphs.resources),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rule.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.headline.of(context),
                            ),
                            Text(
                              '${rule.apiType} · ${rule.version} · ${rule.lastCheckedLabel}${rule.latencyMs > 0 ? ' ${rule.latencyMs} ms' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.listSubtitleStyle,
                            ),
                          ],
                        ),
                      ),
                      if (managed != null)
                        IconButton(
                          tooltip: '编辑 ${rule.name}',
                          icon: const GlyphIcon(KonekoGlyphs.code),
                          onPressed: () => BaseNavigator.push<void>(
                            context,
                            _RuleEditorPage(repository: managed, id: rule.id),
                          ),
                        ),
                      Switch(
                        value: rule.enabled,
                        onChanged: (enabled) => ref
                            .read(rulesProvider.notifier)
                            .toggle(rule.id, enabled),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RuleStorePage extends ConsumerStatefulWidget {
  const _RuleStorePage({required this.repository});

  final ManagedRules repository;

  @override
  ConsumerState<_RuleStorePage> createState() => _RuleStorePageState();
}

class _RuleStorePageState extends ConsumerState<_RuleStorePage> {
  final _address = TextEditingController();
  late Future<List<RuleListing>> _rules = widget.repository.browse();
  final _installing = <Uri>{};

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _install(RuleListing listing) async {
    setState(() => _installing.add(listing.url));
    try {
      final rules = await widget.repository.install(listing.url);
      if (!mounted) return;
      ref.read(rulesProvider.notifier).replace(rules);
      showKonekoBanner(
        context,
        '${listing.name} 已安装',
        level: BannerLevel.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '规则安装失败'),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _installing.remove(listing.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(rulesProvider);
    return KonekoScaffold(
      title: '规则仓库',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.refresh,
          tooltip: '加载仓库',
          onPressed: () {
            final url = _address.text.trim();
            setState(
              () => _rules = widget.repository.browse(
                repository: url.isEmpty ? null : url,
              ),
            );
          },
        ),
      ],
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding,
            16,
            30 + context.bottomInset,
          ),
          children: [
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: '自定义仓库 URL（留空使用当前仓库）',
              ),
              onSubmitted: (text) => setState(
                () => _rules = widget.repository.browse(
                  repository: text.trim().isEmpty ? null : text.trim(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<RuleListing>>(
              future: _rules,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: ActivityIndicator());
                }
                if (snapshot.hasError) return const Text('仓库读取失败，请检查网络或仓库地址。');
                final items = snapshot.data ?? const [];
                if (items.isEmpty) return const Text('仓库中暂无规则');
                return generateGroup([
                  for (final item in items)
                    DecorationListItem(
                      title: Text(item.name),
                      subtitle: Text(item.version),
                      trailing: _installing.contains(item.url)
                          ? const ActivityIndicator()
                          : GlyphIcon(
                              installed.any(
                                    (rule) =>
                                        rule.id == item.name.toLowerCase() &&
                                        rule.version == item.version,
                                  )
                                  ? Glyphs.check
                                  : KonekoGlyphs.addCircle,
                            ),
                      onPressed: _installing.contains(item.url)
                          ? null
                          : () => _install(item),
                    ),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleEditorPage extends ConsumerStatefulWidget {
  const _RuleEditorPage({required this.repository, this.id});

  final ManagedRules repository;
  final String? id;

  @override
  ConsumerState<_RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends ConsumerState<_RuleEditorPage> {
  late final _editor = TextEditingController(
    text: widget.id == null ? '' : widget.repository.exportRule(widget.id!),
  );
  bool _busy = false;

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final rules = await widget.repository.importRules(_editor.text);
      if (!mounted) return;
      ref.read(rulesProvider.notifier).replace(rules);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '规则保存失败'),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final id = widget.id;
    if (id == null) return;
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: Builder(
        builder: (dialogContext) => AlertDialog(
          title: '移除此规则？',
          destructive: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('移除'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      final list = await widget.repository.removeRule(id);
      if (!mounted) return;
      ref.read(rulesProvider.notifier).replace(list);
      Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '规则移除失败', level: BannerLevel.error);
      }
    }
  }

  Future<void> _export() async {
    try {
      final safeName = (widget.id ?? 'rule').replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      await FilePicker.saveFile(
        fileName: '$safeName.json',
        bytes: Uint8List.fromList(utf8.encode(_editor.text)),
        mimeType: 'application/json',
      );
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '规则导出失败', level: BannerLevel.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => KonekoScaffold(
    title: widget.id == null ? '导入规则' : '编辑规则',
    showBack: true,
    actions: [
      if (widget.id != null) ...[
        IconButtonData(
          glyph: KonekoGlyphs.externalLink,
          tooltip: '导出 JSON',
          onPressed: _export,
        ),
        IconButtonData(
          glyph: KonekoGlyphs.trash,
          tooltip: '移除规则',
          onPressed: _busy ? null : _remove,
        ),
      ],
      IconButtonData(
        glyph: Glyphs.check,
        tooltip: '保存规则',
        isLoading: _busy,
        onPressed: _save,
      ),
    ],
    body: Builder(
      builder: (context) => ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          context.contentTopPadding,
          16,
          24 + context.bottomInset,
        ),
        children: [
          TextField(
            controller: _editor,
            maxLines: null,
            minLines: 12,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'Kazumi JSON 或 kazumi:// 链接',
            ),
          ),
        ],
      ),
    ),
  );
}
