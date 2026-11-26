import 'dart:math' as math;

import 'package:koneko_contract/koneko_contract.dart';

class MockCatalogRepository implements CatalogRepository {
  MockCatalogRepository();

  static final List<AnimeSubject> _subjects = [
    const AnimeSubject(
      subjectId: 1001,
      title: '星海旅人：北境编年史',
      originalTitle: 'Hoshiumi no Tabibito: Hokkyou Chronicle',
      summary: '在群星坠落后的北境海港，年轻测绘师与失忆星灵搭乘旧式飞艇穿越冰雾航路，寻找被遗忘的观星台与失落星图。',
      score: 9.2,
      rank: 1,
      year: 2026,
      seasonLabel: '2026 秋季新番',
      weekday: 3,
      airedEpisodes: 14,
      totalEpisodes: 24,
      tags: ['奇幻', '冒险', '治愈'],
      studio: 'Studio Astral',
      poster: PosterPalette(
        primaryHex: 0xFF28437A,
        secondaryHex: 0xFF4F7AC7,
        accentHex: 0xFFE9C97B,
        motifIndex: 0,
      ),
      relatedIds: [1004, 1007, 1009],
    ),
    const AnimeSubject(
      subjectId: 1002,
      title: '流光协奏曲！',
      originalTitle: 'Ryukou Concerto!',
      summary: '濒临废部的海滨中学室内乐团迎来转校大提琴手，四位性格迥异的少女用一整个夏秋的合奏，在夕阳礼堂奏响属于她们的青春乐章。',
      score: 8.9,
      rank: 2,
      year: 2026,
      seasonLabel: '2026 秋季新番',
      weekday: 3,
      airedEpisodes: 9,
      totalEpisodes: 12,
      tags: ['音乐', '校园', '日常'],
      studio: 'Lumen Works',
      poster: PosterPalette(
        primaryHex: 0xFF7B336C,
        secondaryHex: 0xFFD9729E,
        accentHex: 0xFFFCE2A6,
        motifIndex: 1,
      ),
      relatedIds: [1004, 1008],
    ),
    const AnimeSubject(
      subjectId: 1003,
      title: '青瓷药铺物语 第二季',
      originalTitle: 'Seiji Yakuya Monogatari II',
      summary: '古都巷尾的青瓷药铺再开新篇。擅长草木配方的药师少女凭借敏锐洞察，解开王城内外的奇闻谜案与季节风物秘密。',
      score: 8.7,
      rank: 3,
      year: 2026,
      seasonLabel: '2026 秋季新番',
      weekday: 3,
      airedEpisodes: 18,
      totalEpisodes: 24,
      tags: ['古风', '悬疑', '日常'],
      studio: 'Celadon Film',
      poster: PosterPalette(
        primaryHex: 0xFF1F5D4E,
        secondaryHex: 0xFF5FA68C,
        accentHex: 0xFFF4D98E,
        motifIndex: 2,
      ),
      relatedIds: [1005, 1009],
    ),
    const AnimeSubject(
      subjectId: 1004,
      title: '微风书屋的夏日来信',
      originalTitle: 'Soyokaze Shoten no Natsu',
      summary: '在电车终点站的旧书屋里，每当有人归还夹着明信片的旧书，一段跨越二十年的温柔记忆便悄然展开。',
      score: 8.5,
      rank: 4,
      year: 2026,
      seasonLabel: '2026 夏季新番',
      weekday: 1,
      airedEpisodes: 12,
      totalEpisodes: 12,
      tags: ['日常', '治愈', '恋爱'],
      studio: 'Breeze Pictures',
      poster: PosterPalette(
        primaryHex: 0xFF215B9C,
        secondaryHex: 0xFF6BB2E8,
        accentHex: 0xFFFFE7A0,
        motifIndex: 3,
      ),
      relatedIds: [1002, 1007],
    ),
    const AnimeSubject(
      subjectId: 1005,
      title: '异界餐桌巡礼记',
      originalTitle: 'Isekai Shokutaku Junrei',
      summary: '带着便携铸铁锅穿越大陆的料理旅人，与精灵学徒一路收集稀有香料，为每个落脚的城镇端上热气腾腾的治愈晚餐。',
      score: 8.6,
      rank: 5,
      year: 2025,
      seasonLabel: '2025 秋季番',
      weekday: 2,
      airedEpisodes: 24,
      totalEpisodes: 24,
      tags: ['美食', '奇幻', '日常'],
      studio: 'Hearth Animation',
      poster: PosterPalette(
        primaryHex: 0xFF8C461E,
        secondaryHex: 0xFFDD8A4B,
        accentHex: 0xFFFFE5B4,
        motifIndex: 4,
      ),
      relatedIds: [1003, 1001],
    ),
    const AnimeSubject(
      subjectId: 1006,
      title: '霓虹信号：第九区异闻',
      originalTitle: 'Neon Signal: District 9',
      summary: '雨夜不眠的浮空都会第九区，无线电修复师截获来自旧时代轨道站的异常频段，卷入跨越赛博迷雾的真相追逐。',
      score: 8.4,
      rank: 6,
      year: 2026,
      seasonLabel: '2026 秋季新番',
      weekday: 4,
      airedEpisodes: 7,
      totalEpisodes: 12,
      tags: ['科幻', '悬疑', '动作'],
      studio: 'Prism Frame',
      poster: PosterPalette(
        primaryHex: 0xFF3E206D,
        secondaryHex: 0xFFC43B87,
        accentHex: 0xFF62E6FF,
        motifIndex: 5,
      ),
      relatedIds: [1008, 1010],
    ),
    const AnimeSubject(
      subjectId: 1007,
      title: '白昼回响与时光邮差',
      originalTitle: 'Hakuchuu no Zankyou',
      summary: '专门投递“迟到信件”的时光邮差穿行于钟楼林立的河畔小城，替人们把未曾说出口的告别与承诺送往彼岸。',
      score: 9.0,
      rank: 7,
      year: 2025,
      seasonLabel: '2025 春季番',
      weekday: 5,
      airedEpisodes: 13,
      totalEpisodes: 13,
      tags: ['治愈', '剧情', '奇幻'],
      studio: 'Clocktower Studio',
      poster: PosterPalette(
        primaryHex: 0xFF3A4F7A,
        secondaryHex: 0xFF8FA7D6,
        accentHex: 0xFFF7D58B,
        motifIndex: 6,
      ),
      relatedIds: [1001, 1004],
    ),
    const AnimeSubject(
      subjectId: 1008,
      title: '绯色天文台的约定',
      originalTitle: 'Hiiro Tenmondai no Yakusoku',
      summary: '高二夏夜重启山顶废弃天文台的一群少年少女，为了拍摄十年一遇的赤色彗星，在星轨下许下各自的未来约定。',
      score: 8.5,
      rank: 8,
      year: 2026,
      seasonLabel: '2026 秋季新番',
      weekday: 6,
      airedEpisodes: 6,
      totalEpisodes: 12,
      tags: ['校园', '科幻', '恋爱'],
      studio: 'Starlight Lab',
      poster: PosterPalette(
        primaryHex: 0xFF8E294C,
        secondaryHex: 0xFFD9647A,
        accentHex: 0xFFFFDFB0,
        motifIndex: 7,
      ),
      relatedIds: [1002, 1006],
    ),
    const AnimeSubject(
      subjectId: 1009,
      title: '苍穹织梦者 第三季',
      originalTitle: 'Soukyuu no Yumetsumugi III',
      summary: '云海列岛的织梦学徒正式启程，跨越风之边界的浮岛航道，用风铃与云纱修补逐渐裂解的天空穹顶。',
      score: 8.8,
      rank: 9,
      year: 2026,
      seasonLabel: '2026 秋季新番',
      weekday: 7,
      airedEpisodes: 13,
      totalEpisodes: 24,
      tags: ['奇幻', '冒险', '动作'],
      studio: 'Skyward Works',
      poster: PosterPalette(
        primaryHex: 0xFF285943,
        secondaryHex: 0xFF73B079,
        accentHex: 0xFFEFF5B8,
        motifIndex: 0,
      ),
      relatedIds: [1001, 1003],
    ),
    const AnimeSubject(
      subjectId: 1010,
      title: '雪原机巧工坊',
      originalTitle: 'Setsugen Kikou Koubou',
      summary: '极地蒸汽列车上的见习技师与人偶管家，在漫长极夜里守护每节车厢的灯火与乘客的秘密委托。',
      score: 8.3,
      rank: 10,
      year: 2026,
      seasonLabel: '2026 秋季新番',
      weekday: 3,
      airedEpisodes: 8,
      totalEpisodes: 12,
      tags: ['科幻', '冒险', '悬疑'],
      studio: 'Gear & Frost',
      poster: PosterPalette(
        primaryHex: 0xFF2A4D69,
        secondaryHex: 0xFF639FAB,
        accentHex: 0xFFFFD180,
        motifIndex: 5,
      ),
      relatedIds: [1006, 1001],
    ),
  ];

  @override
  List<AnimeSubject> getAllSubjects() => List.unmodifiable(_subjects);

  @override
  AnimeSubject? getSubjectById(int subjectId) {
    for (final s in _subjects) {
      if (s.subjectId == subjectId) return s;
    }
    return null;
  }

  @override
  List<AnimeSubject> getTrending({String? tag}) {
    if (tag == null || tag.isEmpty || tag == '全部') {
      return List.unmodifiable(_subjects);
    }
    return _subjects.where((s) => s.tags.contains(tag)).toList();
  }

  @override
  List<AnimeSubject> getByWeekday(int weekday) {
    final exact = _subjects.where((s) => s.weekday == weekday).toList();
    if (exact.length >= 3) return exact;
    // Pad weekday view with rotating seasonal titles so every day looks rich.
    final result = <AnimeSubject>[...exact];
    for (var i = 0; i < _subjects.length && result.length < 4; i++) {
      final candidate = _subjects[(weekday * 2 + i) % _subjects.length];
      if (!result.any((s) => s.subjectId == candidate.subjectId)) {
        result.add(candidate);
      }
    }
    return result;
  }

  @override
  List<AnimeSubject> search(String query, {String? tag}) {
    final q = query.trim().toLowerCase();
    return _subjects.where((s) {
      final matchesTag = tag == null || tag.isEmpty || tag == '全部' || s.tags.contains(tag);
      if (!matchesTag) return false;
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) ||
          s.originalTitle.toLowerCase().contains(q) ||
          s.studio.toLowerCase().contains(q) ||
          s.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  @override
  List<EpisodeItem> getEpisodes(
    int subjectId, {
    int watchedCount = 0,
    int? currentEp,
  }) {
    final subject = getSubjectById(subjectId) ?? _subjects.first;
    final total = math.max(subject.totalEpisodes, 12);
    return List.generate(total, (index) {
      final ep = index + 1;
      final EpisodeWatchState state;
      if (ep > subject.airedEpisodes) {
        state = EpisodeWatchState.unaired;
      } else if (currentEp != null && ep == currentEp) {
        state = EpisodeWatchState.current;
      } else if (ep <= watchedCount) {
        state = EpisodeWatchState.watched;
      } else {
        state = EpisodeWatchState.aired;
      }
      return EpisodeItem(
        episodeNumber: ep,
        title: _episodeTitles[index % _episodeTitles.length],
        durationSeconds: 1425,
        airDate: '${subject.year}-${((index ~/ 4) + 10).clamp(1, 12).toString().padLeft(2, '0')}-${((index % 4) * 7 + 2).toString().padLeft(2, '0')}',
        state: state,
      );
    });
  }

  static const _episodeTitles = [
    '启程的微风',
    '星轨下的航路',
    '灯塔与旧信笺',
    '雨夜电车',
    '潮汐回响',
    '未寄出的旋律',
    '雾海观星台',
    '金色黄昏',
    '风铃的约定',
    '白昼残影',
    '北境来客',
    '跨越云端',
    '群星归途',
    '霜月茶会',
    '青瓷秘方',
    '浮空回廊',
    '终章序曲',
    '下一站黎明',
  ];

  @override
  List<RuleSourceProbe> probeSources(int subjectId) {
    final seed = subjectId % 5;
    return [
      RuleSourceProbe(
        ruleId: 'rule_yhdmp',
        ruleName: '樱花源 · XPath',
        lineLabel: '主线 HLS · 1080P',
        resolutionLabel: '1080P',
        latencyMs: 68 + seed * 9,
        availableEpisodes: getSubjectById(subjectId)?.airedEpisodes ?? 12,
        available: true,
      ),
      RuleSourceProbe(
        ruleId: 'rule_agedm',
        ruleName: 'AGE 番剧 · API',
        lineLabel: '直连线路 · 1080P+',
        resolutionLabel: '1080P+',
        latencyMs: 112 + seed * 11,
        availableEpisodes: getSubjectById(subjectId)?.airedEpisodes ?? 12,
        available: true,
      ),
      RuleSourceProbe(
        ruleId: 'rule_girigiri',
        ruleName: 'GiriGiri · 蓝光',
        lineLabel: 'HEVC 高码率',
        resolutionLabel: '4K/HDR',
        latencyMs: 146 + seed * 14,
        availableEpisodes: math.max(1, (getSubjectById(subjectId)?.airedEpisodes ?? 12) - 1),
        available: true,
      ),
      RuleSourceProbe(
        ruleId: 'rule_mikan',
        ruleName: '备用镜像 · WebView',
        lineLabel: '嗅探备用源',
        resolutionLabel: '720P',
        latencyMs: 285 + seed * 18,
        availableEpisodes: getSubjectById(subjectId)?.airedEpisodes ?? 12,
        available: true,
      ),
    ];
  }

  @override
  List<DanmakuItem> getDanmaku(int subjectId, int episodeNumber) {
    return [
      const DanmakuItem(timeSeconds: 2, text: '前方高能，OP 响起来了！✨', colorHex: 0xFFFFFFFF, lane: 0),
      const DanmakuItem(timeSeconds: 5, text: '这季作画质量也太稳了吧', colorHex: 0xFFAEE6FF, lane: 1),
      const DanmakuItem(timeSeconds: 8, text: 'prism_ui 播放器 HUD 质感真舒服', colorHex: 0xFFFFE082, lane: 2),
      const DanmakuItem(timeSeconds: 12, text: '空镜绝美，截图当壁纸了 🌌', colorHex: 0xFFFFFFFF, lane: 0),
      const DanmakuItem(timeSeconds: 16, text: 'BGM 一响起鸡皮疙瘩都起来了', colorHex: 0xFFFFC1E3, lane: 3),
      const DanmakuItem(timeSeconds: 21, text: '从樱花源无缝切到 AGE 源进度直接保留！', colorHex: 0xFFB9F6CA, lane: 1),
      const DanmakuItem(timeSeconds: 26, text: '名场面打卡 23333', colorHex: 0xFFFFFFFF, lane: 2),
      const DanmakuItem(timeSeconds: 31, text: '这一话节奏好舒服，完全看不够', colorHex: 0xFFFFE57F, lane: 0),
    ];
  }
}

class MockRuleRepository implements RuleRepository {
  MockRuleRepository();

  List<RulePluginMeta> _rules = const [
    RulePluginMeta(
      id: 'rule_yhdmp',
      name: '樱花源 · XPath',
      version: '1.8.2',
      baseUrl: 'https://yhdmp.example',
      apiType: 'Kazumi XPath',
      enabled: true,
      useNativePlayer: true,
      supportsDanmaku: true,
      latencyMs: 74,
      lastCheckedLabel: '刚刚测速',
    ),
    RulePluginMeta(
      id: 'rule_agedm',
      name: 'AGE 番剧 · API',
      version: '2.1.0',
      baseUrl: 'https://agedm.example',
      apiType: 'Kazumi JSON',
      enabled: true,
      useNativePlayer: true,
      supportsDanmaku: true,
      latencyMs: 118,
      lastCheckedLabel: '刚刚测速',
    ),
    RulePluginMeta(
      id: 'rule_girigiri',
      name: 'GiriGiri · 蓝光',
      version: '1.4.5',
      baseUrl: 'https://girigiri.example',
      apiType: 'Kazumi XPath',
      enabled: true,
      useNativePlayer: true,
      supportsDanmaku: true,
      latencyMs: 152,
      lastCheckedLabel: '5 分钟前',
    ),
    RulePluginMeta(
      id: 'rule_mikan',
      name: '备用镜像 · WebView',
      version: '1.1.0',
      baseUrl: 'https://mirror.example',
      apiType: 'WebView Sniff',
      enabled: false,
      useNativePlayer: false,
      supportsDanmaku: true,
      latencyMs: 310,
      lastCheckedLabel: '1 小时前',
    ),
  ];

  @override
  List<RulePluginMeta> getAllRules() => List.unmodifiable(_rules);

  @override
  List<RulePluginMeta> toggleRule(String ruleId, bool enabled) {
    _rules = [
      for (final rule in _rules)
        if (rule.id == ruleId) rule.copyWith(enabled: enabled) else rule,
    ];
    return List.unmodifiable(_rules);
  }

  @override
  Future<List<RulePluginMeta>> testAllLatencies() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final rng = math.Random();
    _rules = [
      for (final rule in _rules)
        rule.copyWith(
          latencyMs: rule.enabled ? 55 + rng.nextInt(140) : 260 + rng.nextInt(120),
          lastCheckedLabel: '刚刚测速',
        ),
    ];
    return List.unmodifiable(_rules);
  }
}

/// Seed data for initial library collections & Animeko merged multi-source history.
abstract final class MockSeedData {
  static List<CollectionEntry> initialCollections() {
    final now = DateTime.now();
    return [
      CollectionEntry(subjectId: 1001, status: CollectionStatus.watching, watchedEpisodes: 14, updatedAt: now.subtract(const Duration(minutes: 18))),
      CollectionEntry(subjectId: 1002, status: CollectionStatus.watching, watchedEpisodes: 9, updatedAt: now.subtract(const Duration(hours: 2))),
      CollectionEntry(subjectId: 1003, status: CollectionStatus.watching, watchedEpisodes: 18, updatedAt: now.subtract(const Duration(hours: 5))),
      CollectionEntry(subjectId: 1006, status: CollectionStatus.watching, watchedEpisodes: 7, updatedAt: now.subtract(const Duration(days: 1))),
      CollectionEntry(subjectId: 1004, status: CollectionStatus.wish, watchedEpisodes: 0, updatedAt: now.subtract(const Duration(days: 2))),
      CollectionEntry(subjectId: 1008, status: CollectionStatus.wish, watchedEpisodes: 0, updatedAt: now.subtract(const Duration(days: 3))),
      CollectionEntry(subjectId: 1009, status: CollectionStatus.watching, watchedEpisodes: 13, updatedAt: now.subtract(const Duration(days: 3))),
      CollectionEntry(subjectId: 1005, status: CollectionStatus.watched, watchedEpisodes: 24, updatedAt: now.subtract(const Duration(days: 6))),
      CollectionEntry(subjectId: 1007, status: CollectionStatus.watched, watchedEpisodes: 13, updatedAt: now.subtract(const Duration(days: 11))),
      CollectionEntry(subjectId: 1010, status: CollectionStatus.onHold, watchedEpisodes: 3, updatedAt: now.subtract(const Duration(days: 14))),
    ];
  }

  static List<MergedHistoryEntry> initialMergedHistory() {
    final now = DateTime.now();
    return [
      MergedHistoryEntry(
        subjectId: 1001,
        lastEpisode: 14,
        lastPositionSeconds: 882,
        lastDurationSeconds: 1425,
        lastRuleId: 'rule_yhdmp',
        lastRuleName: '樱花源 · XPath',
        updatedAt: now.subtract(const Duration(minutes: 18)),
        sourceRecords: [
          SourceProgressRecord(
            ruleId: 'rule_yhdmp',
            ruleName: '樱花源 · XPath',
            episodeNumber: 14,
            positionSeconds: 882,
            durationSeconds: 1425,
            watchedAt: now.subtract(const Duration(minutes: 18)),
          ),
          SourceProgressRecord(
            ruleId: 'rule_agedm',
            ruleName: 'AGE 番剧 · API',
            episodeNumber: 13,
            positionSeconds: 1402,
            durationSeconds: 1425,
            watchedAt: now.subtract(const Duration(days: 2)),
          ),
          SourceProgressRecord(
            ruleId: 'rule_girigiri',
            ruleName: 'GiriGiri · 蓝光',
            episodeNumber: 12,
            positionSeconds: 1410,
            durationSeconds: 1425,
            watchedAt: now.subtract(const Duration(days: 6)),
          ),
        ],
      ),
      MergedHistoryEntry(
        subjectId: 1002,
        lastEpisode: 9,
        lastPositionSeconds: 1197,
        lastDurationSeconds: 1425,
        lastRuleId: 'rule_agedm',
        lastRuleName: 'AGE 番剧 · API',
        updatedAt: now.subtract(const Duration(hours: 2)),
        sourceRecords: [
          SourceProgressRecord(
            ruleId: 'rule_agedm',
            ruleName: 'AGE 番剧 · API',
            episodeNumber: 9,
            positionSeconds: 1197,
            durationSeconds: 1425,
            watchedAt: now.subtract(const Duration(hours: 2)),
          ),
          SourceProgressRecord(
            ruleId: 'rule_yhdmp',
            ruleName: '樱花源 · XPath',
            episodeNumber: 8,
            positionSeconds: 1420,
            durationSeconds: 1425,
            watchedAt: now.subtract(const Duration(days: 4)),
          ),
        ],
      ),
      MergedHistoryEntry(
        subjectId: 1003,
        lastEpisode: 18,
        lastPositionSeconds: 641,
        lastDurationSeconds: 1425,
        lastRuleId: 'rule_girigiri',
        lastRuleName: 'GiriGiri · 蓝光',
        updatedAt: now.subtract(const Duration(hours: 5)),
        sourceRecords: [
          SourceProgressRecord(
            ruleId: 'rule_girigiri',
            ruleName: 'GiriGiri · 蓝光',
            episodeNumber: 18,
            positionSeconds: 641,
            durationSeconds: 1425,
            watchedAt: now.subtract(const Duration(hours: 5)),
          ),
          SourceProgressRecord(
            ruleId: 'rule_yhdmp',
            ruleName: '樱花源 · XPath',
            episodeNumber: 17,
            positionSeconds: 1390,
            durationSeconds: 1425,
            watchedAt: now.subtract(const Duration(days: 5)),
          ),
        ],
      ),
      MergedHistoryEntry(
        subjectId: 1006,
        lastEpisode: 7,
        lastPositionSeconds: 498,
        lastDurationSeconds: 1425,
        lastRuleId: 'rule_yhdmp',
        lastRuleName: '樱花源 · XPath',
        updatedAt: now.subtract(const Duration(days: 1)),
        sourceRecords: [
          SourceProgressRecord(
            ruleId: 'rule_yhdmp',
            ruleName: '樱花源 · XPath',
            episodeNumber: 7,
            positionSeconds: 498,
            durationSeconds: 1425,
            watchedAt: now.subtract(const Duration(days: 1)),
          ),
        ],
      ),
    ];
  }

  /// Demonstrates merging legacy Kazumi multi-source history records into
  /// Koneko's unified per-anime history list by [subjectId].
  static List<MergedHistoryEntry> mergeLegacyKazumiRecords(
    List<MergedHistoryEntry> existing,
    List<LegacyKazumiHistoryRecord> legacyRecords,
  ) {
    final map = <int, Map<String, SourceProgressRecord>>{};
    for (final entry in existing) {
      map[entry.subjectId] = {
        for (final rec in entry.sourceRecords) rec.ruleName: rec,
      };
    }
    for (final raw in legacyRecords) {
      final bucket = map.putIfAbsent(raw.subjectId, () => {});
      final prev = bucket[raw.pluginName];
      if (prev == null || raw.watchedAt.isAfter(prev.watchedAt)) {
        bucket[raw.pluginName] = SourceProgressRecord(
          ruleId: 'kazumi_${raw.pluginName.hashCode.abs()}',
          ruleName: raw.pluginName,
          episodeNumber: raw.episodeNumber,
          positionSeconds: raw.positionSeconds,
          durationSeconds: raw.durationSeconds,
          watchedAt: raw.watchedAt,
        );
      }
    }
    final merged = <MergedHistoryEntry>[];
    for (final item in map.entries) {
      final records = item.value.values.toList()
        ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
      final latest = records.first;
      merged.add(
        MergedHistoryEntry(
          subjectId: item.key,
          lastEpisode: latest.episodeNumber,
          lastPositionSeconds: latest.positionSeconds,
          lastDurationSeconds: latest.durationSeconds,
          lastRuleId: latest.ruleId,
          lastRuleName: latest.ruleName,
          updatedAt: latest.watchedAt,
          sourceRecords: records,
        ),
      );
    }
    merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged;
  }
}
