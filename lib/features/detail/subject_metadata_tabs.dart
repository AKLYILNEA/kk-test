import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koneko/common/providers.dart';
import 'package:koneko/ui/koneko_image.dart';
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

class SubjectCharactersSliver extends ConsumerWidget {
  const SubjectCharactersSliver({super.key, required this.subjectId});

  final int subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = _characters(subjectId);
    return _MetadataList(
      data: ref.watch(provider),
      label: '角色',
      onRetry: () => ref.invalidate(provider),
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

class SubjectCreditsSliver extends ConsumerWidget {
  const SubjectCreditsSliver({super.key, required this.subjectId});

  final int subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = _credits(subjectId);
    return _MetadataList(
      data: ref.watch(provider),
      label: '制作人员',
      onRetry: () => ref.invalidate(provider),
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
    );
  }
}

class _MetadataList<T> extends StatelessWidget {
  const _MetadataList({
    required this.data,
    required this.label,
    required this.onRetry,
    required this.itemBuilder,
  });

  final AsyncValue<List<T>> data;
  final String label;
  final VoidCallback onRetry;
  final Widget Function(T) itemBuilder;

  @override
  Widget build(BuildContext context) => data.when(
    loading: () => const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: ActivityIndicator()),
      ),
    ),
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
        : SliverList.separated(
            itemCount: items.length,
            itemBuilder: (_, index) => itemBuilder(items[index]),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
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
