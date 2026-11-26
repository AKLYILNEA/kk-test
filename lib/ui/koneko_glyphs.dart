import 'package:prism_ui/icons/icons.dart';

/// Native 24x24 prism_ui [Glyph] definitions for Koneko navigation destinations
/// and chrome controls, matching prism_ui's 1.8dp rounded stroke geometry.
abstract final class KonekoGlyphs {
  static const home = Glyph([
    GlyphPath('M3 10.5L12 3L21 10.5'),
    GlyphPath('M5.5 9.5V19.5A1.5 1.5 0 0 0 7 21H17A1.5 1.5 0 0 0 18.5 19.5V9.5'),
    GlyphPath('M9.5 21V14.5H14.5V21', role: GlyphRole.detail),
  ]);

  static const calendar = Glyph([
    GlyphBox(3.5, 5, 20.5, 20.5, 3.5),
    GlyphPath('M8 3V6.5M16 3V6.5', role: GlyphRole.line),
    GlyphPath('M3.5 10H20.5', role: GlyphRole.detail),
    GlyphCircle(9, 14.5, 1.0, role: GlyphRole.detail, solid: true),
    GlyphCircle(15, 14.5, 1.0, role: GlyphRole.detail, solid: true),
  ]);

  static const heart = Glyph([
    GlyphPath(
      'M12 20.2C12 20.2 4 15.2 4 9.5C4 6.5 6.4 4.4 9 4.4C10.6 4.4 11.5 5.2 12 6.2'
      'C12.5 5.2 13.4 4.4 15 4.4C17.6 4.4 20 6.5 20 9.5C20 15.2 12 20.2 12 20.2Z',
    ),
  ]);

  static const history = Glyph([
    GlyphPath('M4 12A8 8 0 1 0 6.5 6.2'),
    GlyphPath('M4 4V8H8', role: GlyphRole.line),
    GlyphPath('M12 7.5V12L15 14', role: GlyphRole.detail),
  ]);

  static const user = Glyph([
    GlyphCircle(12, 8, 3.8),
    GlyphPath('M5 19.8C5.8 16.5 8.5 14.8 12 14.8C15.5 14.8 18.2 16.5 19 19.8'),
  ]);

  static const puzzle = Glyph([
    GlyphPath(
      'M6 6H10A2 2 0 1 1 14 6H18V10A2 2 0 1 1 18 14V18H14A2 2 0 1 0 10 18H6V14A2 2 0 1 0 6 10Z',
    ),
  ]);

  static const palette = Glyph([
    GlyphPath(
      'M12 3.5A8.5 8.5 0 1 0 15.2 19.8C16.2 19.3 16 18 15.2 17.3C14.5 16.7 15 15.5 16 15.5H17.8'
      'A2.7 2.7 0 0 0 20.5 12.8C20.5 7.7 16.7 3.5 12 3.5Z',
    ),
    GlyphCircle(8.3, 10.5, 1.1, role: GlyphRole.detail, solid: true),
    GlyphCircle(11.5, 7.8, 1.1, role: GlyphRole.detail, solid: true),
    GlyphCircle(15.5, 9.2, 1.1, role: GlyphRole.detail, solid: true),
  ]);

  static const info = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphPath('M12 11.2V16.2', role: GlyphRole.detail),
    GlyphCircle(12, 8.1, 0.9, role: GlyphRole.detail, solid: true),
  ]);

  static const play = Glyph([
    GlyphPath('M7.5 5.6L18.5 12L7.5 18.4Z'),
  ]);

  static const pause = Glyph([
    GlyphPath('M8 6V18M16 6V18', role: GlyphRole.line),
  ]);

  static const refresh = Glyph([
    GlyphPath('M19.5 12A7.5 7.5 0 1 1 17.3 6.7'),
    GlyphPath('M17.5 3.5V7.5H13.5', role: GlyphRole.line),
  ]);

  static const sliders = Glyph([
    GlyphPath('M4 7H14M18 7H20M4 17H8M12 17H20', role: GlyphRole.line),
    GlyphCircle(16, 7, 2, role: GlyphRole.detail),
    GlyphCircle(10, 17, 2, role: GlyphRole.detail),
  ]);

  static const add = Glyph([
    GlyphPath('M12 5V19M5 12H19', role: GlyphRole.line),
  ]);

  static const addCircle = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphPath('M12 8.2V15.8M8.2 12H15.8', role: GlyphRole.detail),
  ]);

  static const sun = Glyph([
    GlyphCircle(12, 12, 4.2),
    GlyphPath(
      'M12 3V5M12 19V21M3 12H5M19 12H21M5.6 5.6L7.1 7.1M16.9 16.9L18.4 18.4M18.4 5.6L16.9 7.1M7.1 16.9L5.6 18.4',
      role: GlyphRole.line,
    ),
  ]);

  static const moon = Glyph([
    GlyphPath('M18.6 14.8A7.2 7.2 0 0 1 9.2 5.4A7.6 7.6 0 1 0 18.6 14.8Z'),
  ]);

  static const font = Glyph([
    GlyphPath('M5 18L10 6L15 18M6.8 14H13.2', role: GlyphRole.line),
    GlyphPath('M16.5 11.5C18.8 11.5 19.5 12.8 19.5 14.5V18M19.5 15.2H17.2C16 15.2 15.5 16 15.5 16.7C15.5 17.5 16.2 18 17.2 18H19.5', role: GlyphRole.detail),
  ]);

  static const textSize = Glyph([
    GlyphPath('M4 6H14M9 6V18', role: GlyphRole.line),
    GlyphPath('M14 11H20M17 11V18', role: GlyphRole.detail),
  ]);

  static const motion = Glyph([
    GlyphPath('M4 16C7 9 11 9 14 14C16 17 18.5 15 20 8', role: GlyphRole.line),
  ]);

  static const glass = Glyph([
    GlyphBox(4, 4, 20, 20, 5),
    GlyphPath('M8.5 8.5L13 13M11.5 15.5L15.5 11.5', role: GlyphRole.detail),
  ]);

  static const navBar = Glyph([
    GlyphBox(3.5, 5, 20.5, 19, 4),
    GlyphPath('M7 15H17', role: GlyphRole.detail),
  ]);

  static const trash = Glyph([
    GlyphPath('M5 7H19M9 7V5H15V7', role: GlyphRole.line),
    GlyphPath('M7 7L8 19.5H16L17 7', role: GlyphRole.body),
  ]);

  static const externalLink = Glyph([
    GlyphPath('M14 5H19V10M19 5L11 13', role: GlyphRole.line),
    GlyphPath('M17 14V18.5A1.5 1.5 0 0 1 15.5 20H5.5A1.5 1.5 0 0 1 4 18.5V8.5A1.5 1.5 0 0 1 5.5 7H10'),
  ]);

  static const code = Glyph([
    GlyphPath('M8.5 8L4.5 12L8.5 16M15.5 8L19.5 12L15.5 16M13.2 6.5L10.8 17.5', role: GlyphRole.line),
  ]);

  static const cpu = Glyph([
    GlyphBox(7, 7, 17, 17, 2.5),
    GlyphPath('M9.5 4V7M14.5 4V7M9.5 17V20M14.5 17V20M4 9.5H7M4 14.5H7M17 9.5H20M17 14.5H20', role: GlyphRole.line),
  ]);

  static const cloud = Glyph([
    GlyphPath('M7.5 18H17A3.5 3.5 0 0 0 17.6 11.1A5 5 0 0 0 8 9.2A3.8 3.8 0 0 0 7.5 18Z'),
  ]);

  static const danmaku = Glyph([
    GlyphBox(3.5, 5.5, 20.5, 18.5, 4),
    GlyphPath('M7.5 10H13.5M10.5 14H16.5', role: GlyphRole.detail),
  ]);

  static const star = Glyph([
    GlyphPath('M12 4L14.5 9.1L20 9.9L16 13.8L17 19.3L12 16.6L7 19.3L8 13.8L4 9.9L9.5 9.1Z'),
  ]);

  static const reset = Glyph([
    GlyphPath('M5 12A7 7 0 1 0 7.1 7L4.5 9.2'),
    GlyphPath('M4.5 5V9.5H9', role: GlyphRole.line),
  ]);
}
