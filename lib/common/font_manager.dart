import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A user-imported custom font copied into Koneko's local fonts directory.
@immutable
class CustomFont {
  const CustomFont({required this.name, required this.path});

  final String name;
  final String path;

  Map<String, String> toJson() => {'name': name, 'path': path};

  static CustomFont? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final path = json['path'];
    if (name is! String || path is! String || name.isEmpty || path.isEmpty) {
      return null;
    }
    return CustomFont(name: name, path: path);
  }
}

class _FontMetrics {
  const _FontMetrics({required this.isVariable, required this.baseWeight});

  final bool isVariable;
  final int baseWeight;
}

class _ProcessedFontData {
  const _ProcessedFontData({
    required this.bytes,
    required this.isVariable,
    required this.baseWeight,
  });

  final Uint8List bytes;
  final bool isVariable;
  final int baseWeight;
}

/// Ported 1:1 from FlClash's custom font management system:
/// imports local TTF/OTF files, normalizes static bold OS/2 weights for Skia,
/// registers fonts via [FontLoader], and switches the entire app instantly with
/// zero restart via [fontFamilyNotifier].
class FontManager {
  static final ValueNotifier<String?> fontFamilyNotifier =
      ValueNotifier<String?>(null);

  static List<CustomFont> _fonts = const [];
  static final Map<String, String> _families = {};
  static final Map<String, _FontMetrics> _metrics = {};
  static String? _selectedPath;

  static const String _prefKeyFonts = 'koneko_custom_fonts';
  static const String _prefKeySelected = 'koneko_custom_font_selected';

  static List<CustomFont> get fonts => List.unmodifiable(_fonts);

  static CustomFont? get selectedFont {
    final selectedPath = _selectedPath;
    if (selectedPath == null) return null;
    for (final font in _fonts) {
      if (font.path == selectedPath) return font;
    }
    return null;
  }

  static String? get selectedName => selectedFont?.name;
  static String? get customFontFamily => fontFamilyNotifier.value;
  static bool get isLoaded => fontFamilyNotifier.value != null;
  static bool get isVariableFont => _selectedMetrics?.isVariable ?? false;
  static int get fontBaseWeight => _selectedMetrics?.baseWeight ?? 400;

  static _FontMetrics? get _selectedMetrics {
    final selectedPath = _selectedPath;
    return selectedPath == null ? null : _metrics[selectedPath];
  }

  static String? familyOf(CustomFont font) => _families[font.path];

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fonts = <CustomFont>[];
      final stored = prefs.getString(_prefKeyFonts);
      if (stored != null && stored.isNotEmpty) {
        for (final font in _decode(stored)) {
          if (File(font.path).existsSync()) {
            fonts.add(font);
          }
        }
      }
      _fonts = fonts;
      final storedSelection = prefs.getString(_prefKeySelected);
      _selectedPath = fonts.any((f) => f.path == storedSelection)
          ? storedSelection
          : null;
      fontFamilyNotifier.value = null;

      for (final font in _fonts) {
        await _register(font.path);
      }
      final selectedPath = _selectedPath;
      if (selectedPath != null) {
        final family = _families[selectedPath];
        if (family == null) {
          _selectedPath = null;
        } else {
          fontFamilyNotifier.value = family;
        }
      }
      await _persist();
    } catch (_) {
      // Safe fallback in headless tests or restricted sandboxes.
    }
  }

  static List<CustomFont> _decode(String raw) {
    final result = <CustomFont>[];
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          final font = CustomFont.fromJson(item);
          if (font != null) result.add(font);
        }
      }
    } catch (_) {
      return const [];
    }
    return result;
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKeyFonts,
        json.encode([for (final f in _fonts) f.toJson()]),
      );
      final selectedPath = _selectedPath;
      if (selectedPath == null) {
        await prefs.remove(_prefKeySelected);
      } else {
        await prefs.setString(_prefKeySelected, selectedPath);
      }
    } catch (_) {
      // Ignore persistence errors in test environment.
    }
  }

  static Future<bool> select(CustomFont font) async {
    final family = await _register(font.path);
    if (family == null) return false;
    _selectedPath = font.path;
    fontFamilyNotifier.value = family;
    await _persist();
    return true;
  }

  static Future<void> selectDefault() async {
    _selectedPath = null;
    fontFamilyNotifier.value = null;
    await _persist();
  }

  static Future<void> delete(CustomFont font) async {
    _fonts = [
      for (final item in _fonts)
        if (item.path != font.path) item,
    ];
    _families.remove(font.path);
    _metrics.remove(font.path);
    if (_selectedPath == font.path) {
      _selectedPath = null;
      fontFamilyNotifier.value = null;
    }
    try {
      final file = File(font.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    await _persist();
  }

  static Future<bool> importAndSelect() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
      );
      if (picked == null) return false;
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) return false;

      final extension = p.extension(picked.name).toLowerCase();
      if (extension != '.ttf' && extension != '.otf') return false;

      final bytes = await File(sourcePath).readAsBytes();
      if (bytes.isEmpty) return false;

      final supportDir = await getApplicationSupportDirectory();
      final fontsDir = Directory(p.join(supportDir.path, 'fonts'));
      if (!await fontsDir.exists()) {
        await fontsDir.create(recursive: true);
      }

      final target = await _uniqueTarget(fontsDir, picked.name, extension);
      await File(target).writeAsBytes(bytes, flush: true);

      var name = picked.name;
      if (_fonts.any((f) => f.name == name)) {
        name =
            '${p.basenameWithoutExtension(name)} (${_fonts.length + 1})$extension';
      }
      final font = CustomFont(name: name, path: target);
      _fonts = [..._fonts, font];
      return await select(font);
    } catch (_) {
      return false;
    }
  }

  static Future<String> _uniqueTarget(
    Directory directory,
    String name,
    String extension,
  ) async {
    final base = p.basenameWithoutExtension(name).trim();
    final stem = base.isEmpty
        ? 'font'
        : base.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    var candidate = p.join(directory.path, '$stem$extension');
    var index = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(directory.path, '$stem ($index)$extension');
      index++;
    }
    return candidate;
  }

  static Future<String?> _register(String filePath) async {
    final cached = _families[filePath];
    if (cached != null) return cached;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final rawBytes = await file.readAsBytes();
      if (rawBytes.isEmpty) return null;

      final processed = _analyzeAndProcessFont(rawBytes);
      final familyName = 'KonekoCustomFont_${filePath.hashCode.abs()}';
      final loader = FontLoader(familyName);
      loader.addFont(
        Future.value(
          ByteData.view(
            processed.bytes.buffer,
            processed.bytes.offsetInBytes,
            processed.bytes.lengthInBytes,
          ),
        ),
      );
      await loader.load();
      _metrics[filePath] = _FontMetrics(
        isVariable: processed.isVariable,
        baseWeight: processed.baseWeight,
      );
      _families[filePath] = familyName;
      return familyName;
    } catch (_) {
      return null;
    }
  }

  static int _calcTableChecksum(
    Uint8List bytes,
    ByteData byteData,
    int offset,
    int length,
  ) {
    var sum = 0;
    final nLongs = (length + 3) ~/ 4;
    for (var i = 0; i < nLongs; i++) {
      final pos = offset + i * 4;
      var word = 0;
      if (pos + 4 <= bytes.length) {
        word = byteData.getUint32(pos, Endian.big);
      } else {
        for (var b = 0; b < 4; b++) {
          final idx = pos + b;
          final bVal =
              (idx < offset + length && idx < bytes.length) ? bytes[idx] : 0;
          word = (word << 8) | bVal;
        }
      }
      sum = (sum + word) & 0xFFFFFFFF;
    }
    return sum;
  }

  static _ProcessedFontData _analyzeAndProcessFont(Uint8List rawBytes) {
    if (rawBytes.length < 12) {
      return _ProcessedFontData(
        bytes: rawBytes,
        isVariable: false,
        baseWeight: 400,
      );
    }

    final bytes = Uint8List.fromList(rawBytes);
    final byteData = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );

    final magic = byteData.getUint32(0, Endian.big);
    final isTtc = magic == 0x74746366;
    final fontOffsets = <int>[];
    if (isTtc) {
      final numFonts = byteData.getUint32(8, Endian.big);
      for (var i = 0; i < numFonts; i++) {
        final off = 12 + i * 4;
        if (off + 4 <= bytes.length) {
          fontOffsets.add(byteData.getUint32(off, Endian.big));
        }
      }
    } else {
      fontOffsets.add(0);
    }

    var isVariable = false;
    var originalWeight = 400;
    var modified = false;

    for (final base in fontOffsets) {
      if (base + 12 > bytes.length) continue;
      final numTables = byteData.getUint16(base + 4, Endian.big);
      int? os2RecOffset;
      int? os2Offset;
      int? os2Length;
      int? headOffset;

      for (var i = 0; i < numTables; i++) {
        final rec = base + 12 + i * 16;
        if (rec + 16 > bytes.length) break;
        final tag = byteData.getUint32(rec, Endian.big);
        final offset = byteData.getUint32(rec + 8, Endian.big);
        final length = byteData.getUint32(rec + 12, Endian.big);
        if (tag == 0x66766172) {
          isVariable = true;
        } else if (tag == 0x4F532F32) {
          os2RecOffset = rec;
          os2Offset = offset;
          os2Length = length;
        } else if (tag == 0x68656164) {
          headOffset = offset;
        }
      }

      if (os2Offset != null && os2Offset + 6 <= bytes.length) {
        final weight = byteData.getUint16(os2Offset + 4, Endian.big);
        originalWeight = weight;
        if (!isVariable &&
            weight > 400 &&
            os2RecOffset != null &&
            os2Length != null) {
          byteData.setUint16(os2Offset + 4, 400, Endian.big);
          if (os2Offset + 64 <= bytes.length) {
            var fsSel = byteData.getUint16(os2Offset + 62, Endian.big);
            if ((fsSel & 0x0020) != 0) {
              fsSel = (fsSel & ~0x0020) | 0x0040;
              byteData.setUint16(os2Offset + 62, fsSel, Endian.big);
            }
          }
          final newCksum = _calcTableChecksum(
            bytes,
            byteData,
            os2Offset,
            os2Length,
          );
          byteData.setUint32(os2RecOffset + 4, newCksum, Endian.big);
          if (headOffset != null && headOffset + 12 <= bytes.length && !isTtc) {
            byteData.setUint32(headOffset + 8, 0, Endian.big);
            final totalCksum = _calcTableChecksum(
              bytes,
              byteData,
              0,
              bytes.length,
            );
            final adj = (0xB1B0AFBA - totalCksum) & 0xFFFFFFFF;
            byteData.setUint32(headOffset + 8, adj, Endian.big);
          }
          modified = true;
        }
      }
    }

    return _ProcessedFontData(
      bytes: modified ? bytes : rawBytes,
      isVariable: isVariable,
      baseWeight: originalWeight,
    );
  }
}
