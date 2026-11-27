import 'dart:async';
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
    final colorScheme = context.colorScheme;
    final repository = ref.watch(ruleRepositoryProvider);
    final managed = repository is ManagedRules ? repository : null;
    final entries = ref.watch(rulesProvider);
    return KonekoScaffold(
      title: '规则管理',
      showBack: widget.showBack,
      actions: [
        if (managed != null)
          IconButtonData(
            glyph: KonekoGlyphs.importFile,
            tooltip: '导入规则文件',
            onPressed: () => _importFile(managed),
          ),
        IconButtonData(
          glyph: KonekoGlyphs.speed,
          tooltip: '全部测速',
          isLoading: _testing,
          onPressed: entries.isEmpty ? null : _test,
        ),
      ],
      body: ArrivalCacheExtentBuilder(
        builder: (context, cacheExtent) => PrismListView(
          scrollCacheExtent: cacheExtent,
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding + 4,
            16,
            28 + context.bottomInset,
          ),
          estimatedItemExtent: 72,
          gap: 10,
          itemCount:
              (managed == null ? 0 : 1) +
              (entries.isEmpty ? 1 : entries.length + 1),
          itemBuilder: (context, index) {
            if (managed != null && index == 0) {
              return KonekoGroup(
                items: [
                  DecorationListItem(
                    leading: GlyphIcon(
                      KonekoGlyphs.resources,
                      color: colorScheme.primary,
                    ),
                    title: const Text('在线规则仓库'),
                    trailing: const GlyphIcon(Glyphs.chevronForward),
                    onPressed: () => BaseNavigator.push<void>(
                      context,
                      _RuleStorePage(repository: managed),
                    ),
                  ),
                  DecorationListItem(
                    leading: GlyphIcon(
                      KonekoGlyphs.addCircle,
                      color: colorScheme.primary,
                    ),
                    title: const Text('粘贴导入'),
                    trailing: const GlyphIcon(Glyphs.chevronForward),
                    onPressed: () => BaseNavigator.push<void>(
                      context,
                      _RuleEditorPage(repository: managed),
                    ),
                  ),
                ],
              );
            }
            if (entries.isEmpty) {
              return KonekoCard(
                corner: 24,
                padding: const EdgeInsets.all(20),
                child: Text(
                  '添加一条播放规则后即可搜索线路。可从上方规则仓库安装或导入自己的规则。',
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              );
            }
            final rowIndex = index - (managed == null ? 0 : 1);
            if (rowIndex == 0) {
              return ListHeader(title: '已安装规则 (${entries.length})');
            }
            final rule = entries[rowIndex - 1];
            return KonekoCard(
              key: ValueKey(rule.id),
              corner: 24,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                spacing: 10,
                children: [
                  GlyphIcon(
                    KonekoGlyphs.puzzle,
                    size: 20,
                    color: rule.enabled
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Row(
                          spacing: 6,
                          children: [
                            Flexible(
                              child: Text(
                                rule.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.headline
                                    .of(context, emphasized: true)
                                    .copyWith(color: colorScheme.onSurface),
                              ),
                            ),
                            if (rule.latencyMs > 0)
                              KonekoChip(
                                label: '${rule.latencyMs} ms',
                                height: 20,
                                fontSize: 10.5,
                                backgroundColor: rule.latencyMs < 150
                                    ? colorScheme.successContainer
                                    : colorScheme.warningContainer,
                                foregroundColor: rule.latencyMs < 150
                                    ? colorScheme.onSuccessContainer
                                    : colorScheme.onWarningContainer,
                              ),
                          ],
                        ),
                        Text(
                          '${rule.apiType} · v${rule.version} · ${rule.lastCheckedLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (managed != null)
                    KonekoCircleButton(
                      size: 34,
                      iconSize: 15,
                      glyph: KonekoGlyphs.code,
                      tooltip: '编辑 ${rule.name}',
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
            );
          },
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
    repository: 'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/',
  ),
  _RuleStorePreset(
    label: 'GitHub 直连',
    repository: 'https://raw.githubusercontent.com/Predidit/KazumiRules/main/',
  ),
];

class _RuleStorePage extends ConsumerStatefulWidget {
  const _RuleStorePage({required this.repository});

  final ManagedRules repository;

  @override
  ConsumerState<_RuleStorePage> createState() => _RuleStorePageState();
}

class _RuleStorePageState extends ConsumerState<_RuleStorePage>
    with
        RouteMotionHoldMixin<_RuleStorePage>,
        RouteSettledMixin<_RuleStorePage> {
  final TextEditingController _customRepoController = TextEditingController();
  String _customRepoUrl = '';
  String _query = '';
  List<RuleListing>? _loadedRules;
  Object? _loadError;
  bool _loading = true;
  int _loadToken = 0;
  final _installing = <Uri>{};
  int _selectedPreset = 0;

  @override
  void didSettleRoute() {
    unawaited(_fetchRules());
  }

  @override
  void dispose() {
    _loadToken++;
    _customRepoController.dispose();
    super.dispose();
  }

  Future<void> _fetchRules({String? repository}) async {
    final token = ++_loadToken;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final result = await widget.repository.browse(repository: repository);
      if (!mounted || token != _loadToken) return;
      updateWhenRouteSettled(() {
        if (!mounted || token != _loadToken) return;
        setState(() {
          _loadedRules = result;
          _loadError = null;
          _loading = false;
        });
      });
    } on Object catch (error) {
      if (!mounted || token != _loadToken) return;
      updateWhenRouteSettled(() {
        if (!mounted || token != _loadToken) return;
        setState(() {
          _loadError = error;
          _loading = false;
        });
      });
    }
  }

  void _reload({String? repository}) {
    unawaited(_fetchRules(repository: repository));
  }

  void _selectPreset(int index) {
    final preset = _ruleStorePresets[index];
    setState(() {
      _selectedPreset = index;
      _customRepoUrl = index == 0 ? '' : preset.repository;
      if (index == 0) {
        _customRepoController.clear();
      }
    });
    unawaited(_fetchRules(repository: preset.repository));
  }

  void _applyCustomRepo() {
    final url = _customRepoController.text.trim();
    setState(() {
      _customRepoUrl = url;
      _selectedPreset = url.isEmpty ? 0 : -1;
    });
    unawaited(_fetchRules(repository: url));
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

  Widget _buildCustomRepoSection(BuildContext context) {
    final colorScheme = context.colorScheme;
    final hasCustom = _selectedPreset == -1 && _customRepoUrl.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListHeader(title: '自定义仓库'),
        KonekoCard(
          corner: 24,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 8,
                children: [
                  GlyphIcon(
                    KonekoGlyphs.externalLink,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  Expanded(
                    child: Text(
                      '仓库地址',
                      style: AppTextStyle.subheadline
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                  ),
                  if (hasCustom)
                    KonekoChip(
                      label: '已启用',
                      height: 22,
                      fontSize: 11,
                      backgroundColor: colorScheme.primary.withValues(
                        alpha: 0.14,
                      ),
                      foregroundColor: colorScheme.primary,
                    ),
                ],
              ),
              TextField(
                controller: _customRepoController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(hintText: '输入仓库地址，留空恢复默认'),
                onSubmitted: (_) => _applyCustomRepo(),
              ),
              Row(
                spacing: 10,
                children: [
                  KonekoChip(
                    label: '恢复默认',
                    height: 36,
                    fontSize: 13,
                    backgroundColor: SurfaceLevel.block.colorOf(colorScheme),
                    foregroundColor: colorScheme.onSurface,
                    onPressed: () => _selectPreset(0),
                  ),
                  Expanded(
                    child: PressSurface(
                      fill: colorScheme.primary,
                      shape: AppShape.full,
                      clipsChild: true,
                      onPressed: _applyCustomRepo,
                      child: SizedBox(
                        height: 36,
                        child: Center(
                          child: Text(
                            '加载仓库',
                            style: AppTextStyle.subheadline
                                .of(context, emphasized: true)
                                .copyWith(color: colorScheme.onPrimary),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final installed = ref.watch(rulesProvider);
    final query = _query.trim().toLowerCase();

    return KonekoScaffold(
      title: '规则仓库',
      showBack: true,
      searchConfig: KonekoSearchConfig(
        tooltip: '搜索规则',
        hintText: '搜索仓库内的播放规则...',
        onChanged: (v) => setState(() => _query = v),
      ),
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.refresh,
          tooltip: '重新加载',
          onPressed: () {
            final url = _customRepoUrl.trim();
            _reload(repository: url.isEmpty ? null : url);
          },
        ),
      ],
      body: ArrivalCacheExtentBuilder(
        builder: (context, cacheExtent) {
          final allItems = _loadedRules ?? const <RuleListing>[];
          final items = query.isEmpty
              ? allItems
              : allItems
                    .where((item) => item.name.toLowerCase().contains(query))
                    .toList();
          final installedById = {
            for (final rule in installed) rule.id: rule,
          };

          return CustomScrollView(
            scrollCacheExtent: cacheExtent,
            slivers: [
              const KonekoScrollStart(),
              SliverToBoxAdapter(
                child: KonekoAutoScrollChipBar(
                  height: 46,
                  chipHeight: 34,
                  fontSize: 12.5,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  labels: [for (final p in _ruleStorePresets) p.label],
                  selectedIndex: _selectedPreset >= 0 ? _selectedPreset : -1,
                  onSelected: _selectPreset,
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: ActivityIndicator()),
                  ),
                )
              else if (_loadError != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: KonekoCard(
                      corner: 26,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 10,
                        children: [
                          Text(
                            '规则仓库暂时无法加载',
                            style: AppTextStyle.headline
                                .of(context, emphasized: true)
                                .copyWith(color: colorScheme.onSurface),
                          ),
                          Text(
                            featureError(
                              _loadError!,
                              '仓库读取失败，请检查网络或切换上方镜像源。',
                            ),
                            style: AppTextStyle.footnote
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              KonekoChip(
                                label: '重新加载',
                                height: 32,
                                fontSize: 12.5,
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                leading: GlyphIcon(
                                  KonekoGlyphs.refresh,
                                  size: 13,
                                  color: colorScheme.onPrimary,
                                ),
                                onPressed: () {
                                  final url = _customRepoUrl.trim();
                                  _reload(repository: url.isEmpty ? null : url);
                                },
                              ),
                              if (_customRepoUrl.isNotEmpty)
                                KonekoChip(
                                  label: '恢复官方自动优选',
                                  height: 32,
                                  fontSize: 12.5,
                                  onPressed: () => _selectPreset(0),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (allItems.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: KonekoCard(
                      corner: 24,
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          '仓库中暂无可用规则',
                          style: AppTextStyle.subheadline
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                )
              else if (items.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: KonekoCard(
                      corner: 24,
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          '没有匹配「$_query」的规则',
                          style: AppTextStyle.subheadline
                              .of(context)
                              .copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: ListHeader(
                      title: query.isEmpty
                          ? '可用规则 (${allItems.length})'
                          : '筛选结果 (${items.length} / ${allItems.length})',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverPrismList(
                    itemCount: items.length,
                    gap: 8,
                    estimatedItemExtent: 64,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final current =
                          installedById[item.name.trim().toLowerCase()];
                      final upToDate =
                          current != null && current.version == item.version;
                      final hasUpdate = current != null && !upToDate;
                      final busy = _installing.contains(item.url);
                      final statusText = upToDate
                          ? 'v${item.version} · 已是最新'
                          : hasUpdate
                          ? 'v${current.version} → v${item.version}'
                          : 'v${item.version}';

                      return KonekoCard(
                        corner: 20,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        onPressed: busy ? null : () => _install(item),
                        child: Row(
                          spacing: 10,
                          children: [
                            GlyphIcon(
                              KonekoGlyphs.puzzle,
                              color: upToDate
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 2,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.subheadline
                                        .of(context, emphasized: true)
                                        .copyWith(color: colorScheme.onSurface),
                                  ),
                                  Text(
                                    statusText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.caption1
                                        .of(context)
                                        .copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (busy)
                              const ActivityIndicator()
                            else
                              KonekoChip(
                                label: upToDate
                                    ? '已安装'
                                    : hasUpdate
                                    ? '更新'
                                    : '安装',
                                height: 26,
                                fontSize: 11.5,
                                backgroundColor: upToDate
                                    ? colorScheme.successContainer
                                    : hasUpdate
                                    ? colorScheme.primary.withValues(
                                        alpha: 0.14,
                                      )
                                    : colorScheme.primary,
                                foregroundColor: upToDate
                                    ? colorScheme.onSuccessContainer
                                    : hasUpdate
                                    ? colorScheme.primary
                                    : colorScheme.onPrimary,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  30 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: _buildCustomRepoSection(context),
                ),
              ),
            ],
          );
        },
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
          context.contentTopPadding + 4,
          16,
          24 + context.bottomInset,
        ),
        children: [
          KonekoCard(
            corner: 24,
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _editor,
              maxLines: null,
              minLines: 14,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: '粘贴规则 JSON 或链接'),
            ),
          ),
        ],
      ),
    ),
  );
}
