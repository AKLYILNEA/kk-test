import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_image.dart';
import 'package:koneko/ui/koneko_skeleton.dart';
import 'package:koneko/ui/koneko_surfaces.dart';
import 'package:koneko_contract/koneko_contract.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

final _characters = FutureProvider.autoDispose
    .family<List<SubjectCharacter>, int>((ref, id) async {
      return await ref.watch(onlineCatalogProvider)?.loadCharacters(id) ??
          const [];
    });

final _credits = FutureProvider.autoDispose.family<List<SubjectPerson>, int>((
  ref,
  id,
) async {
  return await ref.watch(onlineCatalogProvider)?.loadCredits(id) ?? const [];
});

final _relations = FutureProvider.autoDispose
    .family<List<SubjectRelation>, int>((ref, id) async {
      final online = ref.watch(onlineCatalogProvider);
      if (online != null) return online.loadRelations(id);
      final catalog = ref.watch(catalogRepositoryProvider);
      final related = catalog.getSubjectById(id)?.relatedIds ?? const [];
      return [
        for (final subject
            in related.map(catalog.getSubjectById).whereType<AnimeSubject>())
          SubjectRelation(
            id: subject.subjectId,
            title: subject.title,
            originalTitle: subject.originalTitle,
            relation: '关联系列',
            isAnime: true,
            imageUrl: subject.coverUrl,
          ),
      ];
    });

Future<void> _openBangumi(BuildContext context, String section, int id) async {
  try {
    if (await launchUrl(
      Uri.https('bgm.tv', '/$section/$id'),
      mode: LaunchMode.externalApplication,
    )) {
      return;
    }
  } on Object {
    // The external browser may be unavailable.
  }
  if (context.mounted) {
    showKonekoBanner(context, '无法打开 Bangumi', level: BannerLevel.error);
  }
}

class SubjectPeopleSliver extends ConsumerWidget {
  const SubjectPeopleSliver({super.key, required this.subjectId});

  final int subjectId;

  static void retain(WidgetRef ref, int subjectId) {
    ref.listen(_characters(subjectId), (_, _) {});
    ref.listen(_credits(subjectId), (_, _) {});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charactersProvider = _characters(subjectId);
    final creditsProvider = _credits(subjectId);
    final characters = ref.watch(charactersProvider);
    final credits = ref.watch(creditsProvider);
    if ((characters.isLoading || credits.isLoading) &&
        !characters.hasValue &&
        !credits.hasValue &&
        !characters.hasError &&
        !credits.hasError) {
      return const _MetadataSkeletonSliver(
        key: ValueKey('people-loading-skeleton'),
        count: 5,
        isPoster: false,
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        _MetadataList(
          data: characters,
          label: '角色',
          onRetry: () => ref.invalidate(charactersProvider),
          itemBuilder: (character) => _MetadataCard(
            title: character.name,
            subtitle: [
              if (character.relation.isNotEmpty) character.relation,
              if (character.actors.isNotEmpty)
                '声优  ${character.actors.map((actor) => actor.name).join('、')}',
            ].join('\n'),
            leading: KonekoAvatar(
              name: character.name,
              avatarUrl: character.imageUrl,
              size: 46,
            ),
            onTap: () => _openBangumi(context, 'character', character.id),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        _MetadataList(
          data: credits,
          label: '制作人员',
          onRetry: () => ref.invalidate(creditsProvider),
          itemBuilder: (person) => _MetadataCard(
            title: person.name,
            subtitle: person.credits.join('、'),
            leading: KonekoAvatar(
              name: person.name,
              avatarUrl: person.imageUrl,
              size: 46,
            ),
            onTap: () => _openBangumi(context, 'person', person.id),
          ),
        ),
      ],
    );
  }
}

class SubjectRelationsSliver extends ConsumerWidget {
  const SubjectRelationsSliver({
    super.key,
    required this.subjectId,
    required this.onOpenAnime,
  });

  final int subjectId;
  final ValueChanged<int> onOpenAnime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = _relations(subjectId);
    return _MetadataList(
      data: ref.watch(provider),
      label: '关联条目',
      loadingSliver: const _MetadataSkeletonSliver(
        key: ValueKey('relations-loading-skeleton'),
        count: 4,
        isPoster: true,
      ),
      onRetry: () => ref.invalidate(provider),
      itemBuilder: (related) => _MetadataCard(
        title: related.title,
        subtitle: [
          if (related.relation.isNotEmpty) related.relation,
          if (related.originalTitle != related.title) related.originalTitle,
        ].join('\n'),
        leading: ClipRSuperellipse(
          borderRadius: AppRadius.all(7),
          child: SizedBox(
            width: 42,
            height: 58,
            child: KonekoNetworkImage(
              url: related.imageUrl ?? '',
              memCacheWidth: kAvatarCacheWidth,
              placeholder: ColoredBox(
                color: SurfaceLevel.block.colorOf(context.colorScheme),
                child: const Center(child: GlyphIcon(Glyphs.chevronForward)),
              ),
            ),
          ),
        ),
        onTap: related.isAnime
            ? () => onOpenAnime(related.id)
            : () => _openBangumi(context, 'subject', related.id),
      ),
    );
  }
}

class _MetadataSkeletonSliver extends StatelessWidget {
  const _MetadataSkeletonSliver({
    super.key,
    required this.count,
    required this.isPoster,
  });

  final int count;
  final bool isPoster;

  @override
  Widget build(BuildContext context) {
    final chevronColor = context.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.28,
    );
    return SliverPrismList(
      itemCount: count,
      gap: 8,
      estimatedItemExtent: isPoster ? 78 : 66,
      itemBuilder: (_, index) {
        final titleFraction = index.isEven ? 0.56 : 0.44;
        final subFraction = index.isEven ? 0.72 : 0.62;
        return KonekoCard(
          corner: 18,
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(
            spacing: 12,
            children: [
              if (isPoster)
                const KonekoSkeletonBox(width: 42, height: 58, corner: 7)
              else
                const KonekoSkeletonBox(width: 46, height: 46, circle: true),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 7,
                  children: [
                    FractionallySizedBox(
                      widthFactor: titleFraction,
                      child: const KonekoSkeletonBox(height: 15, corner: 6),
                    ),
                    FractionallySizedBox(
                      widthFactor: subFraction,
                      child: const KonekoSkeletonBox(height: 12, corner: 5),
                    ),
                  ],
                ),
              ),
              GlyphIcon(Glyphs.chevronForward, size: 15, color: chevronColor),
            ],
          ),
        );
      },
    );
  }
}

class _MetadataList<T> extends StatelessWidget {
  const _MetadataList({
    required this.data,
    required this.label,
    required this.onRetry,
    required this.itemBuilder,
    this.loadingSliver,
  });

  final AsyncValue<List<T>> data;
  final String label;
  final VoidCallback onRetry;
  final Widget Function(T) itemBuilder;
  final Widget? loadingSliver;

  @override
  Widget build(BuildContext context) => data.when(
    loading: () => loadingSliver ?? const SliverToBoxAdapter(),
    error: (_, _) => SliverToBoxAdapter(
      child: KonekoCard(
        onPressed: onRetry,
        child: Text('$label加载失败，点此重试', textAlign: TextAlign.center),
      ),
    ),
    data: (items) => items.isEmpty
        ? SliverToBoxAdapter(
            child: KonekoCard(
              child: Text('暂无$label', textAlign: TextAlign.center),
            ),
          )
        : SliverPrismList(
            itemCount: items.length,
            itemBuilder: (_, index) => itemBuilder(items[index]),
            gap: 8,
            estimatedItemExtent: 78,
          ),
  );
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KonekoCard(
    corner: 18,
    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
    onPressed: onTap,
    child: Row(
      spacing: 12,
      children: [
        leading,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                title,
                style: AppTextStyle.callout.of(context, emphasized: true),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const GlyphIcon(Glyphs.chevronForward, size: 15),
      ],
    ),
  );
}
