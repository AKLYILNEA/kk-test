import 'dart:math' as math;

import 'package:prism_ui/icons/icons.dart';

// Includes GPL-3.0 glyphs from FlClash (chen08209 and contributors)
// and FlClash-Myui (aaANDkk and contributors). See the project README.

/// Native prism_ui glyphs for Koneko navigation and controls.
abstract final class KonekoGlyphs {
  static const home = Glyph([
    GlyphBox(3.5, 3.5, 10.5, 11.5, 2),
    GlyphBox(13.5, 3.5, 20.5, 9.5, 2),
    GlyphBox(3.5, 14.5, 10.5, 20.5, 2),
    GlyphBox(13.5, 12.5, 20.5, 20.5, 2),
  ]);

  static const calendar = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphPolyline([
      GlyphVertex(12, 7.2),
      GlyphVertex(12, 12, 0.6),
      GlyphVertex(15.2, 14),
    ], role: GlyphRole.detail),
  ]);

  static const heart = Glyph([
    GlyphPath(
      'M12 19.6C11.4 19.2 3.8 14.4 3.8 9.2C3.8 6.1 6.2 4.1 8.8 4.1'
      'C10.4 4.1 11.4 5.0 12 6.1C12.6 5.0 13.6 4.1 15.2 4.1'
      'C17.8 4.1 20.2 6.1 20.2 9.2C20.2 14.4 12.6 19.2 12 19.6Z',
    ),
  ]);

  static const bookmark = Glyph([
    GlyphPolyline([
      GlyphVertex(5.4, 4.0, 2.2),
      GlyphVertex(18.6, 4.0, 2.2),
      GlyphVertex(18.6, 20.0, 0.9),
      GlyphVertex(12.0, 15.8, 1.4),
      GlyphVertex(5.4, 20.0, 0.9),
    ], closed: true),
  ]);

  static const checkBold = Glyph([
    GlyphPolyline([
      GlyphVertex(5.2, 12.6),
      GlyphVertex(9.8, 17.2, 0.4),
      GlyphVertex(18.8, 7.2),
    ], role: GlyphRole.line),
  ]);

  static const checkCircle = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphPolyline([
      GlyphVertex(8.3, 12.2),
      GlyphVertex(10.9, 14.8, 0.4),
      GlyphVertex(15.9, 9.5),
    ], role: GlyphRole.detail),
  ]);

  static const hourglass = Glyph([
    GlyphPath(
      'M6.8 4.4H17.2C17.2 8.2 14.4 10.6 13.0 12.0'
      'C14.4 13.4 17.2 15.8 17.2 19.6H6.8'
      'C6.8 15.8 9.6 13.4 11.0 12.0C9.6 10.6 6.8 8.2 6.8 4.4Z',
    ),
  ]);

  static const heartBroken = Glyph([
    GlyphPath(
      'M12 19.6C11.4 19.2 3.8 14.4 3.8 9.2C3.8 6.1 6.2 4.1 8.8 4.1'
      'C10.4 4.1 11.4 5.0 12 6.1C12.6 5.0 13.6 4.1 15.2 4.1'
      'C17.8 4.1 20.2 6.1 20.2 9.2C20.2 14.4 12.6 19.2 12 19.6Z',
    ),
    GlyphPolyline([
      GlyphVertex(12.0, 5.4),
      GlyphVertex(9.8, 10.0),
      GlyphVertex(13.9, 11.8),
      GlyphVertex(11.3, 16.4),
    ], role: GlyphRole.detail),
  ]);

  static const history = Glyph([
    GlyphBox(3, 4.5, 21, 19.5, 3.5),
    GlyphPolyline([
      GlyphVertex(7.3, 9.3),
      GlyphVertex(9.9, 11.9, 0.4),
      GlyphVertex(7.3, 14.5),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(12.2, 14.5),
      GlyphVertex(16.2, 14.5),
    ], role: GlyphRole.detail),
  ]);

  static const user = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphCircle(12, 9.4, 2.8, role: GlyphRole.detail),
    GlyphArc(
      12,
      22.6,
      7,
      math.pi * -0.8087,
      math.pi * 0.6173,
      role: GlyphRole.detail,
    ),
  ]);

  static const puzzle = Glyph([
    GlyphPath(
      'M3 10A2.2 2.2 0 0 1 5.2 7.8H7.94A2.6 2.6 0 1 1 11.26 7.8H14'
      'A2.2 2.2 0 0 1 16.2 10V12.74A2.6 2.6 0 1 1 16.2 16.06V18.8'
      'A2.2 2.2 0 0 1 14 21H5.2A2.2 2.2 0 0 1 3 18.8V17.58'
      'A0.8 0.8 0 0 1 4.08 16.83A2.6 2.6 0 1 0 4.08 11.97'
      'A0.8 0.8 0 0 1 3 11.22Z',
    ),
  ]);

  static const palette = Glyph([
    GlyphPath(
      'M20.59 13.9A8.8 8.8 0 1 0 13.9 20.59A1.2 1.2 0 0 0 14.83 19.28A4 4 0 0 1 19.28 14.83A1.2 1.2 0 0 0 20.59 13.9Z',
    ),
    GlyphCircle(7.54, 13.89, 1.4, role: GlyphRole.detail, solid: true),
    GlyphCircle(7.96, 9.32, 1.4, role: GlyphRole.detail, solid: true),
    GlyphCircle(12, 7.15, 1.4, role: GlyphRole.detail, solid: true),
    GlyphCircle(16.04, 9.32, 1.4, role: GlyphRole.detail, solid: true),
  ]);

  static const info = Glyph([
    GlyphCircle(12, 12, 8.8),
    GlyphCircle(12, 7.5, 1.4, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(12, 11.8),
      GlyphVertex(12, 16.7),
    ], role: GlyphRole.detail),
  ]);

  static const play = Glyph([GlyphPath('M7.5 5.6L18.5 12L7.5 18.4Z')]);

  static const pause = Glyph([
    GlyphPath('M8 6V18M16 6V18', role: GlyphRole.line),
  ]);

  static const refresh = Glyph([
    GlyphArc(
      12,
      12,
      7.78,
      math.pi * 0.19,
      math.pi * 1.666,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(19, 5),
      GlyphVertex(19, 8.6, 0.4),
      GlyphVertex(15.4, 8.6),
    ], role: GlyphRole.line),
  ]);

  static const add = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 5),
      GlyphVertex(12, 19),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5, 12),
      GlyphVertex(19, 12),
    ], role: GlyphRole.line),
  ]);

  static const addCircle = Glyph([
    GlyphCircle(12, 12, 8.8, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 7.8),
      GlyphVertex(12, 16.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(7.8, 12),
      GlyphVertex(16.2, 12),
    ], role: GlyphRole.line),
  ]);

  static const sun = Glyph([
    GlyphPath('M6.6 13.5A5.5 5.5 0 0 1 17.4 13.5Z'),
    GlyphPolyline([
      GlyphVertex(2.5, 13.75),
      GlyphVertex(21.5, 13.75),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(6.5, 16.75),
      GlyphVertex(17.5, 16.75),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(10.0, 19.75),
      GlyphVertex(14.0, 19.75),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12.0, 2.5),
      GlyphVertex(12.0, 4.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5.2, 5.2),
      GlyphVertex(6.8, 6.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(18.8, 5.2),
      GlyphVertex(17.2, 6.8),
    ], role: GlyphRole.line),
  ]);

  static const font = Glyph([
    GlyphPolyline([
      GlyphVertex(5.2, 19.6),
      GlyphVertex(12, 4.4, 0.6),
      GlyphVertex(18.8, 19.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(7.7, 14),
      GlyphVertex(16.3, 14),
    ], role: GlyphRole.line),
  ]);

  static const textSize = Glyph([
    GlyphPolyline([
      GlyphVertex(3.2, 4.4),
      GlyphVertex(14, 4.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8.6, 4.4),
      GlyphVertex(8.6, 19.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(14.8, 10.8),
      GlyphVertex(21, 10.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(17.9, 10.8),
      GlyphVertex(17.9, 19.6),
    ], role: GlyphRole.line),
  ]);

  static const motion = Glyph([
    GlyphCircle(15.6, 12, 5.3),
    GlyphPolyline([
      GlyphVertex(4.4, 8),
      GlyphVertex(7.6, 8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(2.9, 12),
      GlyphVertex(6.5, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4.4, 16),
      GlyphVertex(7.6, 16),
    ], role: GlyphRole.line),
  ]);

  static const glass = Glyph([
    GlyphPath(
      'M12 3.4C14.6 6.2 18.4 10.2 18.4 14.4A6.4 6.4 0 0 1 5.6 14.4'
      'C5.6 10.2 9.4 6.2 12 3.4Z',
    ),
    GlyphArc(
      12,
      14.4,
      3.4,
      math.pi * 0.6,
      math.pi * 0.36,
      role: GlyphRole.detail,
    ),
  ]);

  static const navBar = Glyph([
    GlyphBox(2.5, 6.0, 21.5, 18.0, 3.5),
    GlyphCircle(7.8, 12.0, 1.8, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(11.4, 12.0),
      GlyphVertex(17.2, 12.0),
    ], role: GlyphRole.detail),
  ]);

  static const trash = Glyph([
    GlyphPolyline([
      GlyphVertex(5.8, 6.8),
      GlyphVertex(18.2, 6.8),
      GlyphVertex(17.2, 21, 2.5),
      GlyphVertex(6.8, 21, 2.5),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(10, 10.5),
      GlyphVertex(10, 17.5),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(14, 10.5),
      GlyphVertex(14, 17.5),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(3.8, 6.8),
      GlyphVertex(20.2, 6.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9, 6.8),
      GlyphVertex(9, 3.2, 1.4),
      GlyphVertex(15, 3.2, 1.4),
      GlyphVertex(15, 6.8),
    ], role: GlyphRole.line),
  ]);

  static const externalLink = Glyph([
    GlyphBox(3, 3, 21, 21, 3),
    GlyphPolyline([
      GlyphVertex(7.6, 16.4),
      GlyphVertex(16.4, 7.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(11, 7.6),
      GlyphVertex(16.4, 7.6, 0.4),
      GlyphVertex(16.4, 13),
    ], role: GlyphRole.detail),
  ]);

  static const code = Glyph([
    GlyphPolyline([
      GlyphVertex(7.5, 7.5),
      GlyphVertex(3, 12, 0.5),
      GlyphVertex(7.5, 16.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16.5, 7.5),
      GlyphVertex(21, 12, 0.5),
      GlyphVertex(16.5, 16.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(13.8, 5),
      GlyphVertex(10.2, 19),
    ], role: GlyphRole.line),
  ]);

  static const cpu = Glyph([
    GlyphBox(5.5, 5.5, 18.5, 18.5, 2.2),
    GlyphBox(9.2, 9.2, 14.8, 14.8, 1.2, role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(8.4, 5.5),
      GlyphVertex(8.4, 2.9),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 5.5),
      GlyphVertex(12, 2.9),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15.6, 5.5),
      GlyphVertex(15.6, 2.9),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8.4, 18.5),
      GlyphVertex(8.4, 21.1),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 18.5),
      GlyphVertex(12, 21.1),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15.6, 18.5),
      GlyphVertex(15.6, 21.1),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5.5, 8.4),
      GlyphVertex(2.9, 8.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5.5, 12),
      GlyphVertex(2.9, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5.5, 15.6),
      GlyphVertex(2.9, 15.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(18.5, 8.4),
      GlyphVertex(21.1, 8.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(18.5, 12),
      GlyphVertex(21.1, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(18.5, 15.6),
      GlyphVertex(21.1, 15.6),
    ], role: GlyphRole.line),
  ]);

  static const cloud = Glyph([
    GlyphPath(
      'M7.2 18.2H17.3A4.2 4.2 0 0 0 18.1 9.9A5.8 5.8 0 0 0 6.8 8.7A4.6 4.6 0 0 0 7.2 18.2Z',
    ),
    GlyphPolyline([
      GlyphVertex(9.6, 13.1),
      GlyphVertex(11.3, 14.8),
      GlyphVertex(14.6, 11.4),
    ], role: GlyphRole.detail),
  ]);

  static const danmaku = Glyph([
    GlyphBox(3.5, 5.5, 20.5, 18.5, 4),
    GlyphPath('M7.5 10H13.5M10.5 14H16.5', role: GlyphRole.detail),
  ]);

  static const star = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 3.2, 1.2),
      GlyphVertex(14.41, 9.48, 0.6),
      GlyphVertex(21.13, 9.83, 1.2),
      GlyphVertex(15.9, 14.07, 0.6),
      GlyphVertex(17.64, 20.57, 1.2),
      GlyphVertex(12, 16.9, 0.6),
      GlyphVertex(6.36, 20.57, 1.2),
      GlyphVertex(8.1, 14.07, 0.6),
      GlyphVertex(2.87, 9.83, 1.2),
      GlyphVertex(9.59, 9.48, 0.6),
    ], closed: true),
  ]);

  static const reset = Glyph([
    GlyphArc(
      12,
      13.77,
      7.07,
      math.pi * 1.15,
      math.pi * -1.65,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(12, 6.7),
      GlyphVertex(9.9, 6.7),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(13.7, 10.5),
      GlyphVertex(9.9, 6.7, 0.4),
      GlyphVertex(13.7, 2.9),
    ], role: GlyphRole.line),
  ]);

  static const sync = Glyph([
    GlyphArc(
      12,
      12,
      7.78,
      math.pi * 1.144,
      math.pi * 0.889,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(5, 5),
      GlyphVertex(5, 8.6, 0.4),
      GlyphVertex(8.6, 8.6),
    ], role: GlyphRole.line),
    GlyphArc(
      12,
      12,
      7.78,
      math.pi * 0.144,
      math.pi * 0.889,
      role: GlyphRole.line,
    ),
    GlyphPolyline([
      GlyphVertex(19, 19),
      GlyphVertex(19, 15.4, 0.4),
      GlyphVertex(15.4, 15.4),
    ], role: GlyphRole.line),
  ]);

  static const speed = Glyph([
    GlyphPath(
      'M6.759 19.057 Q5.259 19.057 4.396 17.83 A8.8 8.8 0 1 1 19.604 17.83 '
      'Q18.741 19.057 17.241 19.057 Z',
    ),
    GlyphCircle(12, 13.4, 1.4, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(12, 13.4),
      GlyphVertex(15.47, 9.26),
    ], role: GlyphRole.detail),
  ]);

  static const importFile = Glyph([
    GlyphPolyline([
      GlyphVertex(5, 3, 2.5),
      GlyphVertex(13.5, 3, 1),
      GlyphVertex(19, 8.5, 1),
      GlyphVertex(19, 21, 2.5),
      GlyphVertex(5, 21, 2.5),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(13.5, 3.2),
      GlyphVertex(13.5, 8.5, 1.5),
      GlyphVertex(18.8, 8.5),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(12, 17.6),
      GlyphVertex(12, 11.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(9, 14.4),
      GlyphVertex(12, 11.4, 0.4),
      GlyphVertex(15, 14.4),
    ], role: GlyphRole.detail),
  ]);

  static const resources = Glyph([
    GlyphBox(3, 3.5, 21, 8.5, 1.8),
    GlyphBox(4.5, 10.8, 19.5, 20.5, 2.2),
    GlyphPolyline([
      GlyphVertex(10, 14.2),
      GlyphVertex(14, 14.2),
    ], role: GlyphRole.detail),
  ]);

  static const pureBlack = Glyph([
    GlyphBox(3, 3.5, 21, 16.5, 2.5),
    GlyphPath(
      'M7 6H17A1.5 1.5 0 0 1 18.5 7.5V12.5A1.5 1.5 0 0 1 17 14H7A1.5 1.5 0 0 1 5.5 12.5V7.5A1.5 1.5 0 0 1 7 6Z',
      role: GlyphRole.detail,
      solid: true,
    ),
    GlyphPolyline([
      GlyphVertex(12, 16.5),
      GlyphVertex(12, 20.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8, 20.4),
      GlyphVertex(16, 20.4),
    ], role: GlyphRole.line),
  ]);

  static const layers = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 3, 1.5),
      GlyphVertex(20.8, 7.6, 1.2),
      GlyphVertex(12, 12.2, 1.5),
      GlyphVertex(3.2, 7.6, 1.2),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(3.2, 12),
      GlyphVertex(12, 16.6, 1.5),
      GlyphVertex(20.8, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3.2, 16.4),
      GlyphVertex(12, 21, 1.5),
      GlyphVertex(20.8, 16.4),
    ], role: GlyphRole.line),
  ]);

  static const split = Glyph([
    GlyphPolyline([
      GlyphVertex(4.5, 4),
      GlyphVertex(12, 11.5, 2.5),
      GlyphVertex(12, 20.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(19.5, 4),
      GlyphVertex(12, 11.5, 2.5),
      GlyphVertex(12, 20.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4.5, 9.5),
      GlyphVertex(4.5, 4, 0.5),
      GlyphVertex(10, 4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(14, 4),
      GlyphVertex(19.5, 4, 0.5),
      GlyphVertex(19.5, 9.5),
    ], role: GlyphRole.line),
  ]);

  static const skipNext = Glyph([
    GlyphPath('M6 5.5L15 12L6 18.5Z'),
    GlyphPath('M18 6V18', role: GlyphRole.line),
  ]);

  static const tune = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 7),
      GlyphVertex(20, 7),
    ], role: GlyphRole.line),
    GlyphCircle(9, 7, 2.2, role: GlyphRole.line, solid: true),
    GlyphPolyline([
      GlyphVertex(4, 12),
      GlyphVertex(20, 12),
    ], role: GlyphRole.line),
    GlyphCircle(15.5, 12, 2.2, role: GlyphRole.line, solid: true),
    GlyphPolyline([
      GlyphVertex(4, 17),
      GlyphVertex(20, 17),
    ], role: GlyphRole.line),
    GlyphCircle(10.5, 17, 2.2, role: GlyphRole.line, solid: true),
  ]);

  static const fullscreen = Glyph([
    GlyphPolyline([
      GlyphVertex(4.5, 9),
      GlyphVertex(4.5, 4.5, 0.5),
      GlyphVertex(9, 4.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15, 4.5),
      GlyphVertex(19.5, 4.5, 0.5),
      GlyphVertex(19.5, 9),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(19.5, 15),
      GlyphVertex(19.5, 19.5, 0.5),
      GlyphVertex(15, 19.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9, 19.5),
      GlyphVertex(4.5, 19.5, 0.5),
      GlyphVertex(4.5, 15),
    ], role: GlyphRole.line),
  ]);

  static const fullscreenExit = Glyph([
    GlyphPolyline([
      GlyphVertex(9, 4.5),
      GlyphVertex(9, 9, 0.5),
      GlyphVertex(4.5, 9),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15, 4.5),
      GlyphVertex(15, 9, 0.5),
      GlyphVertex(19.5, 9),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(19.5, 15),
      GlyphVertex(15, 15, 0.5),
      GlyphVertex(15, 19.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4.5, 15),
      GlyphVertex(9, 15, 0.5),
      GlyphVertex(9, 19.5),
    ], role: GlyphRole.line),
  ]);

  static const comment = Glyph([
    GlyphBox(3.5, 4.5, 20.5, 16.5, 3.2),
    GlyphPolyline([
      GlyphVertex(8, 16.5),
      GlyphVertex(6.5, 20.2),
      GlyphVertex(11.8, 16.5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(7.8, 9.2),
      GlyphVertex(16.2, 9.2),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(7.8, 12.6),
      GlyphVertex(13.5, 12.6),
    ], role: GlyphRole.detail),
  ]);

  static const dock = Glyph([
    GlyphBox(2.5, 6.0, 21.5, 18.0, 3.5),
    GlyphCircle(7.8, 12.0, 1.8, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(11.4, 12.0),
      GlyphVertex(17.2, 12.0),
    ], role: GlyphRole.detail),
  ]);

  static const eyedropper = Glyph([
    GlyphPolyline([
      GlyphVertex(4.79, 19.21, 0.9),
      GlyphVertex(8.46, 18.08, 1.2),
      GlyphVertex(14.4, 12.14, 0.5),
      GlyphVertex(16.24, 13.98, 1),
      GlyphVertex(18.79, 11.43, 1),
      GlyphVertex(17.73, 10.37, 0.5),
      GlyphVertex(21.4, 6.7, 2.9),
      GlyphVertex(17.3, 2.6, 2.9),
      GlyphVertex(13.63, 6.27, 0.5),
      GlyphVertex(12.57, 5.21, 1),
      GlyphVertex(10.02, 7.76, 1),
      GlyphVertex(11.86, 9.6, 0.5),
      GlyphVertex(5.92, 15.54, 1.2),
    ], closed: true),
  ]);

  static const edit = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 20, 1),
      GlyphVertex(8.75, 18.75, 1),
      GlyphVertex(20.25, 7.25, 1.5),
      GlyphVertex(16.75, 3.75, 1.5),
      GlyphVertex(5.25, 15.25, 1),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(13.25, 7.25),
      GlyphVertex(16.75, 10.75),
    ], role: GlyphRole.detail),
  ]);

  static const chevronUp = Glyph([
    GlyphPolyline([
      GlyphVertex(5.5, 15.25),
      GlyphVertex(12, 8.75, 0.4),
      GlyphVertex(18.5, 15.25),
    ], role: GlyphRole.line),
  ]);
}
