import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/features/player/player_page.dart';
import 'package:koneko/ui/koneko_glyphs.dart';
import 'package:koneko/ui/koneko_scaffold.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

class SubjectDetailPage extends ConsumerStatefulWidget {
  const SubjectDetailPage({super.key, required this.subjectId});

  final int subjectId;

  @override
  ConsumerState<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends ConsumerState<SubjectDetailPage> {
  String _selectedRuleId = 'rule_yhdmp';
  String _selectedRuleName = '樱花源 · XPath';

  void _playEpisode(AnimeSubject subject, int episodeNumber) {
    BaseNavigator.push<void>(
      context,
      PlayerPage(
        subjectId: subject.subjectId,
        initialEpisode: episodeNumber,
        initialRuleId: _selectedRuleId,
        initialRuleName: _selectedRuleName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogRepositoryProvider);
    final library = ref.watch(libraryProvider);
    final history = ref.watch(historyProvider);

    final subject =
        catalog.getSubjectById(widget.subjectId) ??
        catalog.getAllSubjects().first;
    final entry = library
        .where((e) => e.subjectId == subject.subjectId)
        .firstOrNull;
    final hist = history
        .where((h) => h.subjectId == subject.subjectId)
        .firstOrNull;

    final currentEp =
        hist?.lastEpisode ??
        ((entry?.watchedEpisodes ?? 0) > 0 ? entry!.watchedEpisodes : 1);
    final episodes = catalog.getEpisodes(
      subject.subjectId,
      watchedCount: entry?.watchedEpisodes ?? 0,
      currentEp: currentEp,
    );
    final probes = catalog.probeSources(subject.subjectId);
    final related = subject.relatedIds
        .map(catalog.getSubjectById)
        .whereType<AnimeSubject>()
        .toList();

    return KonekoScaffold(
      title: '番剧详情',
      showBack: true,
      actions: [
        IconButtonData(
          glyph: KonekoGlyphs.play,
          tooltip: '播放第 $currentEp 话',
          onPressed: () => _playEpisode(subject, currentEp),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final heroCard = _HeroCard(
            subject: subject,
            entry: entry,
            currentEp: currentEp,
            mergedSources: hist?.mergedSourceCount ?? 0,
            onPlay: () => _playEpisode(subject, currentEp),
            onStatusChanged: (status) {
              ref
                  .read(libraryProvider.notifier)
                  .setStatus(subject.subjectId, status);
              showKonekoBanner(
                context,
                '已将《${subject.title}》标记为「${status.label}」',
                level: BannerLevel.success,
              );
            },
          );
          final episodeCard = _EpisodeMatrixCard(
            episodes: episodes,
            onSelect: (ep) => _playEpisode(subject, ep.episodeNumber),
          );
          final sourcesCard = _RuleSourcesCard(
            probes: probes,
            selectedRuleId: _selectedRuleId,
            onSelect: (probe) {
              setState(() {
                _selectedRuleId = probe.ruleId;
                _selectedRuleName = probe.ruleName;
              });
              showKonekoBanner(context, '已切换默认播放源：${probe.ruleName}（进度自动同步）');
            },
          );
          final relatedCard = related.isEmpty
              ? null
              : _RelatedSeriesCard(
                  subjects: related,
                  onOpen: (s) => BaseNavigator.push<void>(
                    context,
                    SubjectDetailPage(subjectId: s.subjectId),
                  ),
                );

          return CustomScrollView(
            slivers: [
              const KonekoScrollStart(),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  28 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 12,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 16,
                                children: [heroCard, episodeCard, ?relatedCard],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                spacing: 16,
                                children: [sourcesCard],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 14,
                          children: [
                            heroCard,
                            episodeCard,
                            sourcesCard,
                            ?relatedCard,
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.subject,
    required this.entry,
    required this.currentEp,
    required this.mergedSources,
    required this.onPlay,
    required this.onStatusChanged,
  });

  final AnimeSubject subject;
  final CollectionEntry? entry;
  final int currentEp;
  final int mergedSources;
  final VoidCallback onPlay;
  final ValueChanged<CollectionStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 136,
                child: KonekoPosterArt(
                  subject: subject,
                  borderRadius: AppRadius.all(18),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      style: AppTextStyle.title2
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subject.originalTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        KonekoChip(
                          label: subject.score.toStringAsFixed(1),
                          leading: const GlyphIcon(
                            KonekoGlyphs.star,
                            size: 12,
                            color: Color(0xFFE09F24),
                          ),
                        ),
                        KonekoChip(label: 'Rank #${subject.rank}'),
                        KonekoChip(label: subject.studio),
                        if (mergedSources > 1)
                          KonekoChip(
                            label: '合并 $mergedSources 源',
                            backgroundColor: colorScheme.primary.withValues(
                              alpha: 0.14,
                            ),
                            foregroundColor: colorScheme.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            subject.summary,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              KonekoChip(
                label: '播放第 $currentEp 话',
                height: 38,
                fontSize: 13.5,
                leading: GlyphIcon(
                  KonekoGlyphs.play,
                  size: 14,
                  color: colorScheme.onPrimary,
                ),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                onPressed: onPlay,
              ),
              for (final status in const [
                CollectionStatus.watching,
                CollectionStatus.wish,
                CollectionStatus.watched,
                CollectionStatus.onHold,
              ])
                KonekoChip(
                  label: status.label,
                  height: 38,
                  fontSize: 13,
                  selected: entry?.status == status,
                  onPressed: () => onStatusChanged(status),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EpisodeMatrixCard extends StatelessWidget {
  const _EpisodeMatrixCard({required this.episodes, required this.onSelect});

  final List<EpisodeItem> episodes;
  final ValueChanged<EpisodeItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '选集矩阵（Animeko 四态）',
                  style: AppTextStyle.headline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
              ),
              Text(
                '共 ${episodes.length} 话',
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final ep in episodes) _episodeCell(context, ep)],
          ),
        ],
      ),
    );
  }

  Widget _episodeCell(BuildContext context, EpisodeItem ep) {
    final colorScheme = context.colorScheme;
    final (bg, fg, label) = switch (ep.state) {
      EpisodeWatchState.current => (
        colorScheme.primary,
        colorScheme.onPrimary,
        '▶ ${ep.episodeNumber}',
      ),
      EpisodeWatchState.watched => (
        colorScheme.primary.withValues(alpha: 0.14),
        colorScheme.primary,
        '${ep.episodeNumber}',
      ),
      EpisodeWatchState.aired => (
        SurfaceLevel.block.colorOf(colorScheme),
        colorScheme.onSurface,
        '${ep.episodeNumber}',
      ),
      EpisodeWatchState.unaired => (
        SurfaceLevel.block.colorOf(colorScheme).withValues(alpha: 0.45),
        colorScheme.onSurfaceVariant.withValues(alpha: 0.48),
        '${ep.episodeNumber}',
      ),
    };
    return SizedBox(
      width: 58,
      height: 40,
      child: PressSurface(
        fill: bg,
        shape: AppShape.md,
        clipsChild: true,
        onPressed: ep.state == EpisodeWatchState.unaired
            ? null
            : () => onSelect(ep),
        child: Center(
          child: Text(
            label,
            style: AppTextStyle.footnote
                .of(context, emphasized: true)
                .copyWith(
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ),
      ),
    );
  }
}

class _RuleSourcesCard extends StatelessWidget {
  const _RuleSourcesCard({
    required this.probes,
    required this.selectedRuleId,
    required this.onSelect,
  });

  final List<RuleSourceProbe> probes;
  final String selectedRuleId;
  final ValueChanged<RuleSourceProbe> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '规则播放源',
            style: AppTextStyle.headline
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            '兼容 Kazumi 规则 · 切换源自动保留同一番剧进度',
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Column(
            spacing: 8,
            children: [
              for (final probe in probes)
                KonekoBlock(
                  selected: probe.ruleId == selectedRuleId,
                  onPressed: () => onSelect(probe),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              probe.ruleName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.subheadline
                                  .of(context, emphasized: true)
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${probe.lineLabel} · ${probe.availableEpisodes} 话',
                              style: AppTextStyle.caption1
                                  .of(context)
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      KonekoChip(
                        label: '${probe.latencyMs} ms',
                        height: 24,
                        fontSize: 11,
                        backgroundColor: probe.latencyMs < 130
                            ? colorScheme.successContainer
                            : colorScheme.warningContainer,
                        foregroundColor: probe.latencyMs < 130
                            ? colorScheme.onSuccessContainer
                            : colorScheme.onWarningContainer,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RelatedSeriesCard extends StatelessWidget {
  const _RelatedSeriesCard({required this.subjects, required this.onOpen});

  final List<AnimeSubject> subjects;
  final ValueChanged<AnimeSubject> onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return KonekoCard(
      corner: 30,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联系列',
            style: AppTextStyle.headline
                .of(context, emphasized: true)
                .copyWith(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 205,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: subjects.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, index) {
                final s = subjects[index];
                return SizedBox(
                  width: 120,
                  child: UnifiedAnimeCard(subject: s, onTap: () => onOpen(s)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
