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

class _RuleStorePreset {
  const _RuleStorePreset({required this.label, required this.repository});

  final String label;
  final String repository;
}

const _ruleStorePresets = <_RuleStorePreset>[
  _RuleStorePreset(label: '自动优选', repository: ''),
  _RuleStorePreset(
    label: 'gh-proxy',
    repository:
        'https://gh-proxy.org/https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
  ),
  _RuleStorePreset(
    label: 'ghfast',
    repository:
        'https://ghfast.top/https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
  ),
  _RuleStorePreset(
    label: 'GitCode',
    repository:
        'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/',
  ),
  _RuleStorePreset(
    label: 'GitHub 直连',
    repository:
        'https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
  ),
];

class _RuleStorePage extends ConsumerStatefulWidget {
  const _RuleStorePage({required this.repository});

  final ManagedRules repository;

  @override
  ConsumerState<_RuleStorePage> createState() => _RuleStorePageState();
}

class _RuleStorePageState extends ConsumerState<_RuleStorePage> {
  final _address = TextEditingController();
  final _filter = TextEditingController();
  late Future<List<RuleListing>> _rules = widget.repository.browse();
  final _installing = <Uri>{};
  int _selectedPreset = 0;

  @override
  void dispose() {
    _address.dispose();
    _filter.dispose();
    super.dispose();
  }

  void _reload({String? repository}) {
    setState(() {
      _rules = widget.repository.browse(repository: repository);
    });
  }

  void _selectPreset(int index) {
    final preset = _ruleStorePresets[index];
    setState(() {
      _selectedPreset = index;
      if (index == 0) {
        _address.clear();
      } else {
        _address.text = preset.repository;
      }
      _rules = widget.repository.browse(repository: preset.repository);
    });
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
    final query = _filter.text.trim().toLowerCase();
    return KonekoScaffold(
      title: '规则仓库',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.refresh,
          tooltip: '重新加载',
          onPressed: () {
            final url = _address.text.trim();
            _reload(repository: url.isEmpty ? null : url);
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
                hintText: '自定义仓库 Raw URL（留空使用官方仓库与镜像自动优选）',
              ),
              onSubmitted: (text) {
                final trimmed = text.trim();
                setState(() {
                  _selectedPreset = trimmed.isEmpty ? 0 : -1;
                  _rules = widget.repository.browse(
                    repository: trimmed.isEmpty ? '' : trimmed,
                  );
                });
              },
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  for (var i = 0; i < _ruleStorePresets.length; i++)
                    KonekoChip(
                      label: _ruleStorePresets[i].label,
                      height: 30,
                      fontSize: 12,
                      selected: _selectedPreset == i,
                      onPressed: () => _selectPreset(i),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<RuleListing>>(
              future: _rules,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(child: ActivityIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  final message = featureError(
                    snapshot.error!,
                    '仓库读取失败，请检查网络或切换上方镜像源。',
                  );
                  return KonekoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        Text(
                          '规则仓库暂时无法加载',
                          style: AppTextStyle.headline.of(context),
                        ),
                        Text(message, style: context.listSubtitleStyle),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                final url = _address.text.trim();
                                _reload(repository: url.isEmpty ? null : url);
                              },
                              icon: const GlyphIcon(KonekoGlyphs.refresh),
                              label: const Text('重新加载'),
                            ),
                            if (_address.text.trim().isNotEmpty)
                              TextButton.icon(
                                onPressed: () => _selectPreset(0),
                                icon: const GlyphIcon(KonekoGlyphs.reset),
                                label: const Text('恢复官方自动优选'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }
                final allItems = snapshot.data ?? const [];
                if (allItems.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('仓库中暂无可用规则')),
                  );
                }
                final items = query.isEmpty
                    ? allItems
                    : allItems
                          .where(
                            (item) => item.name.toLowerCase().contains(query),
                          )
                          .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    TextField(
                      controller: _filter,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText: '筛选规则（共 ${allItems.length} 条）',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text('没有匹配的规则')),
                      )
                    else
                      generateGroup([
                        for (final item in items)
                          Builder(
                            builder: (context) {
                              final key = item.name.trim().toLowerCase();
                              RulePluginMeta? current;
                              for (final rule in installed) {
                                if (rule.id == key) {
                                  current = rule;
                                  break;
                                }
                              }
                              final upToDate =
                                  current != null &&
                                  current.version == item.version;
                              final statusText = upToDate
                                  ? 'v${item.version} · 已安装'
                                  : current != null
                                  ? 'v${current.version} → v${item.version} · 可更新'
                                  : 'v${item.version}';
                              return DecorationListItem(
                                title: Text(item.name),
                                subtitle: Text(statusText),
                                trailing: _installing.contains(item.url)
                                    ? const ActivityIndicator()
                                    : GlyphIcon(
                                        upToDate
                                            ? Glyphs.check
                                            : KonekoGlyphs.addCircle,
                                      ),
                                onPressed: _installing.contains(item.url)
                                    ? null
                                    : () => _install(item),
                              );
                            },
                          ),
                      ]),
                  ],
                );
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
