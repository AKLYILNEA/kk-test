import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
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

enum _RuleFilter { all, enabled, updates }

enum _CatalogFilter { all, installed, updates }

enum _CatalogSort { lastUpdate, name }

String _formatEpochDate(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

String _hostOf(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  final host = Uri.tryParse(trimmed)?.host ?? '';
  return host.isEmpty ? trimmed : host;
}

/// Kazumi-parity Rules Manager in pure FlClash style:
/// - Inline spring search, drag-and-drop reorder mode, rich rule metadata
///   tags (`version`, `API/XPath`, `内置播放/WebView`, `含验证`, `去广告`,
///   latency & update detection), silky `⋯` anchored menu (edit, check update,
///   copy JSON, move up/down, delete), and dialog-based paste/file/repo import.
class RulesPage extends ConsumerStatefulWidget {
  const RulesPage({super.key, this.showBack = false});

  final bool showBack;

  @override
  ConsumerState<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends ConsumerState<RulesPage> {
  String _query = '';
  _RuleFilter _filter = _RuleFilter.all;
  bool _sorting = false;
  bool _testing = false;
  bool _updatingAll = false;
  final Set<String> _updatingIds = {};
  Map<String, RuleListing> _catalogByKey = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCatalogIndex());
  }

  Future<void> _refreshCatalogIndex() async {
    final repo = ref.read(ruleRepositoryProvider);
    if (repo is! ManagedRules) return;
    try {
      final listings = await repo.browse();
      if (!mounted) return;
      setState(() {
        _catalogByKey = {
          for (final item in listings) item.name.toLowerCase(): item,
        };
      });
    } on Object {
      // Quietly keep installed rules usable offline.
    }
  }

  bool _hasUpdate(RulePluginMeta rule) {
    final listing = _catalogByKey[rule.id] ??
        _catalogByKey[rule.name.toLowerCase()];
    if (listing == null || listing.version.isEmpty) return false;
    return listing.version != rule.version;
  }

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

  Future<void> _updateSingle(ManagedRules managed, RulePluginMeta rule) async {
    if (_updatingIds.contains(rule.id)) return;
    setState(() => _updatingIds.add(rule.id));
    try {
      if (_catalogByKey.isEmpty) await _refreshCatalogIndex();
      final listing = _catalogByKey[rule.id] ??
          _catalogByKey[rule.name.toLowerCase()];
      if (listing == null) {
        if (mounted) {
          showKonekoBanner(context, '规则仓库中未找到「${rule.name}」');
        }
        return;
      }
      if (listing.version == rule.version) {
        if (mounted) {
          showKonekoBanner(context, '「${rule.name}」已是最新版本');
        }
        return;
      }
      final updated = await managed.install(listing.url);
      if (!mounted) return;
      ref.read(rulesProvider.notifier).replace(updated);
      showKonekoBanner(
        context,
        '「${rule.name}」已更新至 v${listing.version}',
        level: BannerLevel.success,
      );
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '检查更新失败'),
          level: BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(rule.id));
    }
  }

  Future<void> _updateAll(ManagedRules managed) async {
    if (_updatingAll) return;
    setState(() => _updatingAll = true);
    try {
      if (_catalogByKey.isEmpty) await _refreshCatalogIndex();
      final entries = ref.read(rulesProvider);
      final targets = entries.where(_hasUpdate).toList();
      if (targets.isEmpty) {
        if (mounted) showKonekoBanner(context, '所有已安装规则均已是最新');
        return;
      }
      var updatedCount = 0;
      for (final rule in targets) {
        final listing = _catalogByKey[rule.id] ??
            _catalogByKey[rule.name.toLowerCase()];
        if (listing == null) continue;
        try {
          final list = await managed.install(listing.url);
          if (mounted) ref.read(rulesProvider.notifier).replace(list);
          updatedCount++;
        } on Object {
          // Continue updating remaining rules.
        }
      }
      if (mounted) {
        showKonekoBanner(
          context,
          '已更新 $updatedCount / ${targets.length} 条规则',
          level: updatedCount > 0 ? BannerLevel.success : BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
  }

  Future<void> _importFromDialog(ManagedRules managed) async {
    String initial = '';
    try {
      final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      if (clip.trim().startsWith('{') ||
          clip.trim().startsWith('[') ||
          clip.trim().startsWith('http')) {
        initial = clip.trim();
      }
    } on Object {
      // Clipboard unavailable.
    }
    if (!mounted) return;
    final text = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: '粘贴导入规则',
        value: initial,
        hintText: '粘贴规则 JSON、Base64 或直链地址',
        validator: (v) =>
            v == null || v.trim().isEmpty ? '请输入规则 JSON 或链接' : null,
      ),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    try {
      final trimmed = text.trim();
      final list =
          trimmed.startsWith('http://') || trimmed.startsWith('https://')
          ? await managed.install(Uri.parse(trimmed))
          : await managed.importRules(trimmed);
      if (!mounted) return;
      ref.read(rulesProvider.notifier).replace(list);
      showKonekoBanner(context, '规则导入成功', level: BannerLevel.success);
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '无法导入规则，请检查格式'),
          level: BannerLevel.error,
        );
      }
    }
  }

  Future<void> _importFile(ManagedRules managed) async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
      );
      final path = picked?.path;
      if (path == null) return;
      final list = await managed.importRules(await File(path).readAsString());
      if (!mounted) return;
      ref.read(rulesProvider.notifier).replace(list);
      showKonekoBanner(context, '规则文件已导入', level: BannerLevel.success);
    } on Object catch (error) {
      if (mounted) {
        showKonekoBanner(
          context,
          featureError(error, '无法导入规则文件'),
          level: BannerLevel.error,
        );
      }
    }
  }

  Future<void> _confirmDelete(RulePluginMeta rule) async {
    final confirmed = await showFloatingDialog<bool>(
      context: context,
      child: Builder(
        builder: (dialogContext) => AlertDialog(
          title: '删除「${rule.name}」？',
          destructive: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
          ],
          child: const Text('删除后将从播放源列表中移除，可随时从在线仓库重新安装。'),
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await ref.read(rulesProvider.notifier).remove(rule.id);
      if (mounted) {
        showKonekoBanner(
          context,
          '已删除「${rule.name}」',
          level: BannerLevel.success,
        );
      }
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '删除规则失败', level: BannerLevel.error);
      }
    }
  }

  Future<void> _copyRuleJson(ManagedRules managed, RulePluginMeta rule) async {
    try {
      final jsonText = managed.exportRule(rule.id);
      await Clipboard.setData(ClipboardData(text: jsonText));
      if (mounted) {
        showKonekoBanner(
          context,
          '已复制「${rule.name}」规则 JSON',
          level: BannerLevel.success,
        );
      }
    } on Object {
      if (mounted) {
        showKonekoBanner(context, '导出规则失败', level: BannerLevel.error);
      }
    }
  }

  Future<void> _openAddMenu(ManagedRules managed) async {
    final choice = await showFloatingDialog<String>(
      context: context,
      child: Builder(
        builder: (dialogContext) => AlertDialog(
          title: '添加播放规则',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
          ],
          child: KonekoGroup(
            items: [
              DecorationListItem(
                leading: GlyphIcon(
                  KonekoGlyphs.resources,
                  color: dialogContext.colorScheme.primary,
                ),
                title: const Text('从在线规则仓库安装'),
                trailing: const GlyphIcon(Glyphs.chevronForward),
                onPressed: () => Navigator.pop(dialogContext, 'store'),
              ),
              DecorationListItem(
                leading: GlyphIcon(
                  KonekoGlyphs.code,
                  color: dialogContext.colorScheme.primary,
                ),
                title: const Text('粘贴 JSON / 链接导入'),
                trailing: const GlyphIcon(Glyphs.chevronForward),
                onPressed: () => Navigator.pop(dialogContext, 'paste'),
              ),
              DecorationListItem(
                leading: GlyphIcon(
                  KonekoGlyphs.importFile,
                  color: dialogContext.colorScheme.primary,
                ),
                title: const Text('从本地文件导入'),
                trailing: const GlyphIcon(Glyphs.chevronForward),
                onPressed: () => Navigator.pop(dialogContext, 'file'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'store':
        await BaseNavigator.push<void>(
          context,
          _RuleStorePage(repository: managed),
        );
        if (mounted) unawaited(_refreshCatalogIndex());
      case 'paste':
        await _importFromDialog(managed);
      case 'file':
        await _importFile(managed);
    }
  }

  Widget _buildRuleTag(
    BuildContext context,
    String label, {
    Color? background,
    Color? foreground,
  }) {
    final colorScheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: ShapeDecoration(
        color: background ?? SurfaceLevel.block.colorOf(colorScheme),
        shape: SuperellipseBorder(borderRadius: AppRadius.all(7)),
      ),
      child: Text(
        label,
        style: AppTextStyle.caption2
            .of(context, emphasized: true)
            .copyWith(color: foreground ?? colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildRuleCard(
    BuildContext context, {
    required RulePluginMeta rule,
    required int index,
    required int totalCount,
    required ManagedRules? managed,
    required bool canReorder,
  }) {
    final colorScheme = context.colorScheme;
    final hasUpdate = _hasUpdate(rule);
    final isUpdating = _updatingIds.contains(rule.id);
    final host = _hostOf(rule.baseUrl);
    final subtitleParts = <String>[
      if (host.isNotEmpty) host,
      if (rule.lastCheckedLabel.isNotEmpty && rule.lastCheckedLabel != '尚未测速')
        rule.lastCheckedLabel,
    ];

    final card = Padding(
      key: ValueKey(rule.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: KonekoCard(
        corner: 24,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onPressed: _sorting || managed == null
            ? null
            : () => BaseNavigator.push<void>(
                context,
                _RuleEditorPage(repository: managed, id: rule.id),
              ),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: ShapeDecoration(
                color: rule.enabled
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : SurfaceLevel.block.colorOf(colorScheme),
                shape: SuperellipseBorder(borderRadius: AppRadius.all(13)),
              ),
              child: Center(
                child: GlyphIcon(
                  KonekoGlyphs.puzzle,
                  size: 18,
                  color: rule.enabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
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
                        _buildRuleTag(
                          context,
                          '${rule.latencyMs} ms',
                          background: rule.latencyMs < 150
                              ? colorScheme.successContainer
                              : colorScheme.warningContainer,
                          foreground: rule.latencyMs < 150
                              ? colorScheme.onSuccessContainer
                              : colorScheme.onWarningContainer,
                        ),
                    ],
                  ),
                  if (subtitleParts.isNotEmpty)
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      if (rule.version.isNotEmpty)
                        _buildRuleTag(context, 'v${rule.version}'),
                      _buildRuleTag(context, rule.apiType),
                      _buildRuleTag(
                        context,
                        rule.useNativePlayer ? '内置播放' : 'WebView',
                      ),
                      if (rule.antiCrawlerEnabled)
                        _buildRuleTag(
                          context,
                          '含验证',
                          background: colorScheme.warningContainer,
                          foreground: colorScheme.onWarningContainer,
                        ),
                      if (rule.adBlocker) _buildRuleTag(context, '去广告'),
                      if (hasUpdate)
                        _buildRuleTag(
                          context,
                          '可更新',
                          background: colorScheme.primary.withValues(
                            alpha: 0.14,
                          ),
                          foreground: colorScheme.primary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_sorting && canReorder)
              ReorderDragStartListener(
                index: index,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: GlyphIcon(
                      Glyphs.dragHandle,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              if (isUpdating)
                const SizedBox.square(
                  dimension: 18,
                  child: ActivityIndicator(size: 18),
                )
              else
                Switch(
                  value: rule.enabled,
                  onChanged: (enabled) => ref
                      .read(rulesProvider.notifier)
                      .toggle(rule.id, enabled),
                ),
              PopupAnchor(
                targetBuilder: (open) => PressSurface(
                  fill: Colors.transparent,
                  shape: AppShape.circle,
                  onPressed: open,
                  child: SizedBox.square(
                    dimension: 34,
                    child: Center(
                      child: GlyphIcon(
                        Glyphs.more,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                popupBuilder: (_) => PopupMenu(
                  items: [
                    if (managed != null)
                      PopupMenuItem(
                        glyph: KonekoGlyphs.edit,
                        label: '编辑规则',
                        onPressed: () => BaseNavigator.push<void>(
                          context,
                          _RuleEditorPage(repository: managed, id: rule.id),
                        ),
                      ),
                    if (managed != null)
                      PopupMenuItem(
                        glyph: KonekoGlyphs.refresh,
                        label: hasUpdate ? '更新规则' : '检查更新',
                        onPressed: () =>
                            unawaited(_updateSingle(managed, rule)),
                      ),
                    if (managed != null)
                      PopupMenuItem(
                        glyph: KonekoGlyphs.code,
                        label: '复制规则 JSON',
                        onPressed: () => unawaited(_copyRuleJson(managed, rule)),
                      ),
                    PopupMenuItem(
                      glyph: KonekoGlyphs.chevronUp,
                      label: '上移一位',
                      section: const PopupMenuSection(),
                      onPressed: index == 0
                          ? null
                          : () => unawaited(
                              ref
                                  .read(rulesProvider.notifier)
                                  .reorder(index, index - 1),
                            ),
                    ),
                    PopupMenuItem(
                      glyph: Glyphs.chevronDown,
                      label: '下移一位',
                      onPressed: index >= totalCount - 1
                          ? null
                          : () => unawaited(
                              ref
                                  .read(rulesProvider.notifier)
                                  .reorder(index, index + 2),
                            ),
                    ),
                    PopupMenuItem(
                      danger: true,
                      glyph: KonekoGlyphs.trash,
                      label: '删除规则',
                      section: const PopupMenuSection(),
                      onPressed: () => unawaited(_confirmDelete(rule)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (_sorting && canReorder) {
      return SortableItem(key: ValueKey(rule.id), index: index, child: card);
    }
    return card;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final repository = ref.watch(ruleRepositoryProvider);
    final managed = repository is ManagedRules ? repository : null;
    final allEntries = ref.watch(rulesProvider);
    final enabledCount = allEntries.where((r) => r.enabled).length;
    final updatesCount = allEntries.where(_hasUpdate).length;

    final q = _query.trim().toLowerCase();
    final visible = allEntries.where((rule) {
      final matchesQuery =
          q.isEmpty ||
          rule.name.toLowerCase().contains(q) ||
          rule.baseUrl.toLowerCase().contains(q);
      if (!matchesQuery) return false;
      return switch (_filter) {
        _RuleFilter.all => true,
        _RuleFilter.enabled => rule.enabled,
        _RuleFilter.updates => _hasUpdate(rule),
      };
    }).toList();

    final canReorder = q.isEmpty && _filter == _RuleFilter.all;

    return PopScope<void>(
      canPop: !_sorting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _sorting) setState(() => _sorting = false);
      },
      child: KonekoScaffold(
        title: _sorting ? '拖动调整顺序' : '规则管理',
        showBack: widget.showBack,
        loading: _testing || _updatingAll,
        searchConfig: _sorting
            ? null
            : KonekoSearchConfig(
                tooltip: '搜索规则',
                hintText: '搜索规则名称或站点域名...',
                onChanged: (v) => setState(() => _query = v),
              ),
        actions: [
          if (_sorting)
            IconButtonData(
              glyph: Glyphs.check,
              tooltip: '完成排序',
              onPressed: () => setState(() => _sorting = false),
            )
          else ...[
            if (allEntries.length > 1)
              IconButtonData(
                glyph: Glyphs.dragHandle,
                tooltip: '调整规则排序',
                onPressed: () => setState(() {
                  _query = '';
                  _filter = _RuleFilter.all;
                  _sorting = true;
                }),
              ),
            IconButtonData(
              glyph: KonekoGlyphs.speed,
              tooltip: '全部测速',
              isLoading: _testing,
              onPressed: allEntries.isEmpty ? null : _test,
            ),
            if (managed != null)
              IconButtonData(
                glyph: KonekoGlyphs.add,
                tooltip: '添加规则',
                onPressed: () => _openAddMenu(managed),
              ),
          ],
        ],
        body: SortModeScope(
          sorting: _sorting,
          child: CustomScrollView(
            slivers: [
              const KonekoScrollStart(),
              if (!_sorting && managed != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: KonekoGroup(
                      items: [
                        DecorationListItem(
                          leading: GlyphIcon(
                            KonekoGlyphs.resources,
                            color: colorScheme.primary,
                          ),
                          title: const Text('在线规则仓库'),
                          subtitle: Text(
                            managed.currentRepository.isEmpty
                                ? '官方规则库 · 支持多镜像自动加速'
                                : '自定义仓库 · ${_hostOf(managed.currentRepository)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const GlyphIcon(Glyphs.chevronForward),
                          onPressed: () async {
                            await BaseNavigator.push<void>(
                              context,
                              _RuleStorePage(repository: managed),
                            );
                            if (mounted) unawaited(_refreshCatalogIndex());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              if (allEntries.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              spacing: 6,
                              children: [
                                for (final (tab, label) in [
                                  (_RuleFilter.all, '全部 ${allEntries.length}'),
                                  (_RuleFilter.enabled, '已启用 $enabledCount'),
                                  if (updatesCount > 0)
                                    (_RuleFilter.updates, '可更新 $updatesCount'),
                                ])
                                  KonekoChip(
                                    label: label,
                                    height: 30,
                                    fontSize: 12,
                                    selected: _filter == tab,
                                    backgroundColor: _filter == tab
                                        ? colorScheme.primary
                                        : SurfaceLevel.card.colorOf(
                                            colorScheme,
                                          ),
                                    foregroundColor: _filter == tab
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurface,
                                    onPressed: _sorting
                                        ? null
                                        : () => setState(() => _filter = tab),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (managed != null && updatesCount > 0 && !_sorting)
                          KonekoRefreshChip(
                            label: '更新全部',
                            loadingLabel: '更新中',
                            loading: _updatingAll,
                            elevated: true,
                            onPressed: () => unawaited(_updateAll(managed)),
                          ),
                      ],
                    ),
                  ),
                ),
              if (allEntries.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  sliver: SliverToBoxAdapter(
                    child: KonekoCard(
                      corner: 24,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          Text(
                            '还没有安装播放规则',
                            style: AppTextStyle.headline
                                .of(context, emphasized: true)
                                .copyWith(color: colorScheme.onSurface),
                          ),
                          Text(
                            '安装一条播放规则后即可自动搜索剧集与线路。可从上方在线规则仓库一键安装，或点击右上角「+」导入。',
                            style: AppTextStyle.subheadline
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      '没有符合条件的规则',
                      style: AppTextStyle.subheadline
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else if (_sorting && canReorder)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    28 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverReorderableList(
                    itemCount: visible.length,
                    onReorder: (oldIndex, newIndex) => unawaited(
                      ref.read(rulesProvider.notifier).reorder(
                        oldIndex,
                        newIndex,
                      ),
                    ),
                    itemBuilder: (context, index) => _buildRuleCard(
                      context,
                      rule: visible[index],
                      index: index,
                      totalCount: visible.length,
                      managed: managed,
                      canReorder: true,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    28 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final rule = visible[index];
                      final actualIndex = allEntries.indexOf(rule);
                      return _buildRuleCard(
                        context,
                        rule: rule,
                        index: actualIndex,
                        totalCount: allEntries.length,
                        managed: managed,
                        canReorder: false,
                      );
                    },
                  ),
                ),
            ],
          ),
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

/// Kazumi-parity Online Rule Repository:
/// - Custom repository URL moved to top AppBar button opening FlClash [InputDialog]
///   (zero ugly bare input box sitting at the bottom of the list!).
/// - Right-anchored silky [KonekoPopupTrigger] for mirror acceleration & sorting.
/// - Detailed Kazumi rule cards showing author, version, player mode, captcha
///   support tag, update date, and install/update status.
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
  String _customRepoUrl = '';
  String _query = '';
  _CatalogFilter _filter = _CatalogFilter.all;
  _CatalogSort _sort = _CatalogSort.lastUpdate;
  List<RuleListing>? _loadedRules;
  Object? _loadError;
  bool _loading = true;
  bool _updatingAll = false;
  int _loadToken = 0;
  final _installing = <Uri>{};
  int _selectedPreset = 0;

  @override
  void initState() {
    super.initState();
    final saved = widget.repository.currentRepository;
    if (saved.isNotEmpty) {
      final presetIndex = _ruleStorePresets.indexWhere(
        (p) => p.repository == saved,
      );
      if (presetIndex >= 0) {
        _selectedPreset = presetIndex;
        _customRepoUrl = presetIndex == 0 ? '' : saved;
      } else {
        _selectedPreset = -1;
        _customRepoUrl = saved;
      }
    }
  }

  @override
  void didSettleRoute() {
    unawaited(_fetchRules());
  }

  @override
  void dispose() {
    _loadToken++;
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

  void _selectPreset(int index) {
    final preset = _ruleStorePresets[index];
    setState(() {
      _selectedPreset = index;
      _customRepoUrl = index == 0 ? '' : preset.repository;
    });
    unawaited(_fetchRules(repository: preset.repository));
  }

  Future<void> _editCustomRepository() async {
    final value = await showFloatingDialog<String>(
      context: context,
      child: InputDialog(
        title: '自定义规则仓库地址',
        value: _selectedPreset == -1 ? _customRepoUrl : '',
        hintText: '输入仓库 Raw 地址，留空恢复官方仓库',
        keyboardType: TextInputType.url,
        resetValue: '',
        validator: (raw) {
          final text = raw?.trim() ?? '';
          if (text.isEmpty) return null;
          final uri = Uri.tryParse(text);
          if (uri == null ||
              !(uri.scheme == 'https' || uri.scheme == 'http') ||
              uri.host.isEmpty) {
            return '请输入有效的 HTTP 或 HTTPS 仓库地址';
          }
          return null;
        },
      ),
    );
    if (!mounted || value == null) return;
    final trimmed = value.trim();
    setState(() {
      _customRepoUrl = trimmed;
      _selectedPreset = trimmed.isEmpty ? 0 : -1;
    });
    unawaited(_fetchRules(repository: trimmed));
  }

  Future<void> _install(RuleListing listing) async {
    setState(() => _installing.add(listing.url));
    try {
      final rules = await widget.repository.install(listing.url);
      if (!mounted) return;
      ref.read(rulesProvider.notifier).replace(rules);
      showKonekoBanner(
        context,
        '${listing.name} 已安装 (v${listing.version})',
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

  Future<void> _updateAllFromCatalog(
    List<RuleListing> updatable,
  ) async {
    if (_updatingAll || updatable.isEmpty) return;
    setState(() => _updatingAll = true);
    var done = 0;
    try {
      for (final item in updatable) {
        try {
          final rules = await widget.repository.install(item.url);
          if (mounted) ref.read(rulesProvider.notifier).replace(rules);
          done++;
        } on Object {
          // Continue updating other rules.
        }
      }
      if (mounted) {
        showKonekoBanner(
          context,
          '已更新 $done / ${updatable.length} 条规则',
          level: done > 0 ? BannerLevel.success : BannerLevel.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
  }

  Widget _tag(
    BuildContext context,
    String label, {
    Color? background,
    Color? foreground,
  }) {
    final colorScheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: ShapeDecoration(
        color: background ?? SurfaceLevel.block.colorOf(colorScheme),
        shape: SuperellipseBorder(borderRadius: AppRadius.all(7)),
      ),
      child: Text(
        label,
        style: AppTextStyle.caption2
            .of(context, emphasized: true)
            .copyWith(color: foreground ?? colorScheme.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final installed = ref.watch(rulesProvider);
    final installedById = {for (final rule in installed) rule.id: rule};
    final query = _query.trim().toLowerCase();

    final allItems = _loadedRules ?? const <RuleListing>[];
    final installedCount = allItems
        .where((item) => installedById.containsKey(item.name.toLowerCase()))
        .length;
    final updatableItems = allItems.where((item) {
      final current = installedById[item.name.toLowerCase()];
      return current != null &&
          item.version.isNotEmpty &&
          current.version != item.version;
    }).toList();

    final filtered = allItems.where((item) {
      final matches =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.author.toLowerCase().contains(query);
      if (!matches) return false;
      final current = installedById[item.name.toLowerCase()];
      final hasUpdate =
          current != null &&
          item.version.isNotEmpty &&
          current.version != item.version;
      return switch (_filter) {
        _CatalogFilter.all => true,
        _CatalogFilter.installed => current != null,
        _CatalogFilter.updates => hasUpdate,
      };
    }).toList();

    switch (_sort) {
      case _CatalogSort.lastUpdate:
        filtered.sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
      case _CatalogSort.name:
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }

    final isCustomRepo = _selectedPreset == -1 && _customRepoUrl.isNotEmpty;

    return KonekoScaffold(
      title: '在线规则仓库',
      showBack: true,
      loading: _loading || _updatingAll,
      searchConfig: KonekoSearchConfig(
        tooltip: '搜索规则或作者',
        hintText: '搜索规则名称或作者...',
        onChanged: (v) => setState(() => _query = v),
      ),
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.externalLink,
          tooltip: '自定义仓库地址',
          onPressed: _editCustomRepository,
        ),
        IconButtonData(
          glyph: KonekoGlyphs.refresh,
          tooltip: '刷新仓库',
          onPressed: _loading
              ? null
              : () => unawaited(
                  _fetchRules(
                    repository: _customRepoUrl.isEmpty ? null : _customRepoUrl,
                  ),
                ),
        ),
      ],
      body: CustomScrollView(
        slivers: [
          const KonekoScrollStart(),
          // Top compact repository summary + silky mirror & sort popups
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  KonekoCard(
                    corner: 22,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      spacing: 8,
                      children: [
                        GlyphIcon(
                          KonekoGlyphs.resources,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 1,
                            children: [
                              Text(
                                isCustomRepo ? '自定义仓库' : '官方规则仓库',
                                style: AppTextStyle.footnote
                                    .of(context, emphasized: true)
                                    .copyWith(color: colorScheme.onSurface),
                              ),
                              Text(
                                isCustomRepo
                                    ? _hostOf(_customRepoUrl)
                                    : '已安装 $installedCount / ${allItems.length} 条',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.caption2
                                    .of(context)
                                    .copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (isCustomRepo)
                          KonekoChip(
                            label: '恢复默认',
                            height: 28,
                            fontSize: 11.5,
                            onPressed: () => _selectPreset(0),
                          )
                        else
                          KonekoPopupTrigger<int>(
                            options: [
                              for (var i = 0; i < _ruleStorePresets.length; i++)
                                i,
                            ],
                            value: _selectedPreset.clamp(
                              0,
                              _ruleStorePresets.length - 1,
                            ),
                            textBuilder: (i) => _ruleStorePresets[i].label,
                            backgroundColor: SurfaceLevel.block.colorOf(
                              colorScheme,
                            ),
                            foregroundColor: colorScheme.onSurface,
                            onChanged: _selectPreset,
                          ),
                      ],
                    ),
                  ),
                  Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            spacing: 6,
                            children: [
                              for (final (tab, label) in [
                                (_CatalogFilter.all, '全部 ${allItems.length}'),
                                (
                                  _CatalogFilter.installed,
                                  '已安装 $installedCount',
                                ),
                                (
                                  _CatalogFilter.updates,
                                  '可更新 ${updatableItems.length}',
                                ),
                              ])
                                KonekoChip(
                                  label: label,
                                  height: 30,
                                  fontSize: 12,
                                  selected: _filter == tab,
                                  backgroundColor: _filter == tab
                                      ? colorScheme.primary
                                      : SurfaceLevel.card.colorOf(colorScheme),
                                  foregroundColor: _filter == tab
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                  onPressed: () =>
                                      setState(() => _filter = tab),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (updatableItems.isNotEmpty)
                        KonekoRefreshChip(
                          label: '更新全部',
                          loadingLabel: '更新中',
                          loading: _updatingAll,
                          elevated: true,
                          onPressed: () =>
                              unawaited(_updateAllFromCatalog(updatableItems)),
                        ),
                      KonekoPopupTrigger<_CatalogSort>(
                        options: _CatalogSort.values,
                        value: _sort,
                        textBuilder: (s) =>
                            s == _CatalogSort.lastUpdate ? '最近更新' : '按名称',
                        onChanged: (s) => setState(() => _sort = s),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: ActivityIndicator.page()),
            )
          else if (_loadError != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                          KonekoRefreshChip(
                            label: '重试',
                            height: 34,
                            fontSize: 12.5,
                            prominent: true,
                            onPressed: () => unawaited(
                              _fetchRules(
                                repository: _customRepoUrl.isEmpty
                                    ? null
                                    : _customRepoUrl,
                              ),
                            ),
                          ),
                          KonekoChip(
                            label: '自定义地址',
                            height: 34,
                            fontSize: 12.5,
                            onPressed: _editCustomRepository,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  allItems.isEmpty ? '仓库内暂无可用规则' : '没有符合条件的规则',
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final current = installedById[item.name.toLowerCase()];
                  final upToDate =
                      current != null &&
                      (item.version.isEmpty || current.version == item.version);
                  final hasUpdate =
                      current != null &&
                      item.version.isNotEmpty &&
                      current.version != item.version;
                  final busy = _installing.contains(item.url);
                  final updatedDate = _formatEpochDate(item.lastUpdate);

                  return KonekoCard(
                    corner: 22,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    onPressed: busy || upToDate ? null : () => _install(item),
                    child: Row(
                      spacing: 12,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: ShapeDecoration(
                            color: upToDate
                                ? colorScheme.successContainer
                                : colorScheme.primary.withValues(alpha: 0.12),
                            shape: SuperellipseBorder(
                              borderRadius: AppRadius.all(13),
                            ),
                          ),
                          child: Center(
                            child: GlyphIcon(
                              upToDate ? Glyphs.check : KonekoGlyphs.puzzle,
                              size: 18,
                              color: upToDate
                                  ? colorScheme.onSuccessContainer
                                  : colorScheme.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 4,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.headline
                                    .of(context, emphasized: true)
                                    .copyWith(color: colorScheme.onSurface),
                              ),
                              if (item.author.isNotEmpty)
                                Text(
                                  '作者 · ${item.author}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.caption1
                                      .of(context)
                                      .copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: [
                                  if (item.version.isNotEmpty)
                                    _tag(
                                      context,
                                      hasUpdate
                                          ? 'v${current.version} → v${item.version}'
                                          : 'v${item.version}',
                                      background: hasUpdate
                                          ? colorScheme.primary.withValues(
                                              alpha: 0.14,
                                            )
                                          : null,
                                      foreground: hasUpdate
                                          ? colorScheme.primary
                                          : null,
                                    ),
                                  _tag(
                                    context,
                                    item.useNativePlayer ? '内置播放' : 'WebView',
                                  ),
                                  if (item.antiCrawlerEnabled)
                                    _tag(
                                      context,
                                      '含验证支持',
                                      background: colorScheme.warningContainer,
                                      foreground:
                                          colorScheme.onWarningContainer,
                                    ),
                                ],
                              ),
                              if (updatedDate.isNotEmpty)
                                Text(
                                  '更新于 $updatedDate',
                                  style: AppTextStyle.caption2
                                      .of(context)
                                      .copyWith(
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.8),
                                      ),
                                ),
                            ],
                          ),
                        ),
                        if (busy)
                          const SizedBox.square(
                            dimension: 20,
                            child: ActivityIndicator(size: 20),
                          )
                        else
                          KonekoChip(
                            label: upToDate
                                ? '已安装'
                                : hasUpdate
                                ? '更新'
                                : '安装',
                            height: 30,
                            fontSize: 12,
                            backgroundColor: upToDate
                                ? SurfaceLevel.block.colorOf(colorScheme)
                                : hasUpdate
                                ? colorScheme.primary.withValues(alpha: 0.14)
                                : colorScheme.primary,
                            foregroundColor: upToDate
                                ? colorScheme.onSurfaceVariant
                                : hasUpdate
                                ? colorScheme.primary
                                : colorScheme.onPrimary,
                            onPressed: upToDate ? null : () => _install(item),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
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
    body: CustomScrollView(
      slivers: [
        const KonekoScrollStart(),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverToBoxAdapter(
            child: KonekoCard(
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
          ),
        ),
      ],
    ),
  );
}
