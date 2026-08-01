import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pocasie/app_theme.dart';

/// Pozadie podľa `weather_code` ako v `_weatherCodeMap`.
///
/// **Beží staticky** (žiadny `AnimationController`) – pohyblivé pozadie brzdilo celú apku pri 60 Hz.
enum WeatherAmbientKind {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  thunder,
}

WeatherAmbientKind ambientKindForWeatherCode(int code) {
  switch (code) {
    case 0:
      return WeatherAmbientKind.clear;
    case 1:
    case 2:
      return WeatherAmbientKind.partlyCloudy;
    case 3:
    case 45:
    case 48:
      return WeatherAmbientKind.cloudy;
    case 51:
    case 53:
    case 55:
    case 61:
    case 63:
    case 80:
      return WeatherAmbientKind.drizzle;
    case 65:
    case 66:
    case 67:
    case 81:
    case 82:
      return WeatherAmbientKind.rain;
    case 56:
    case 57:
    case 71:
    case 73:
    case 75:
    case 77:
    case 85:
    case 86:
      return WeatherAmbientKind.snow;
    case 95:
    case 96:
    case 99:
      return WeatherAmbientKind.thunder;
    default:
      return WeatherAmbientKind.cloudy;
  }
}

class _Palette {
  static Color skyTop(WeatherAmbientKind kind, bool isDay) {
    if (isDay) {
      return switch (kind) {
        WeatherAmbientKind.clear => const Color(0xFF346490),
        WeatherAmbientKind.partlyCloudy => const Color(0xFF386A98),
        WeatherAmbientKind.cloudy => const Color(0xFF3C6280),
        WeatherAmbientKind.fog => const Color(0xFF406484),
        WeatherAmbientKind.drizzle => const Color(0xFF346088),
        WeatherAmbientKind.rain => const Color(0xFF2E5A7C),
        WeatherAmbientKind.snow => const Color(0xFF446C88),
        WeatherAmbientKind.thunder => const Color(0xFF2C5074),
      };
    }
    // Noc = rovnaký canvas ako scroll (bez zlomu).
    return Color.lerp(kAmbientBlendColor, kAppCardNavy, 0.15)!;
  }

  static Color skyUpper(WeatherAmbientKind kind, bool isDay) {
    if (isDay) {
      return switch (kind) {
        WeatherAmbientKind.clear => const Color(0xFF2E5A84),
        WeatherAmbientKind.partlyCloudy => const Color(0xFF32608C),
        WeatherAmbientKind.cloudy => const Color(0xFF385A78),
        WeatherAmbientKind.fog => const Color(0xFF3C5E7C),
        WeatherAmbientKind.drizzle => const Color(0xFF2E5680),
        WeatherAmbientKind.rain => const Color(0xFF2A5074),
        WeatherAmbientKind.snow => const Color(0xFF3C627C),
        WeatherAmbientKind.thunder => const Color(0xFF28486C),
      };
    }
    return kAmbientBlendColor;
  }

  static Color skyLower(WeatherAmbientKind kind, bool isDay) {
    if (isDay) {
      // Spodok ambientu = canvas → plynulý prechod do scroll oblasti.
      return Color.lerp(kAmbientBlendColor, const Color(0xFF2A5478), 0.30)!;
    }
    return kAmbientBlendColor;
  }

  static List<Color> skyGradientColors(
    WeatherAmbientKind kind,
    bool isDay,
    Color blendColor,
  ) {
    final rawTop = skyTop(kind, isDay);
    final upper = skyUpper(kind, isDay);
    final lower = skyLower(kind, isDay);
    // Menší ťah ku karte (blendColor) → spodok pozadia hlavičky neostane výrazne tmavší než vrch.
    final nearBody = Color.lerp(lower, blendColor, isDay ? 0.06 : 0.18)!;
    final floor = Color.lerp(lower, blendColor, isDay ? 0.12 : 0.30)!;

    // Pri zamračení/dažďoch: zmierni najbelší horný okraj (rawTop vs upper).
    // Jasno nechávame bez zmiešania — aby nebolo umelo šmudlavo.
    Color top = rawTop;
    if (isDay && kind != WeatherAmbientKind.clear) {
      final pull = switch (kind) {
        WeatherAmbientKind.partlyCloudy => 0.34,
        WeatherAmbientKind.cloudy => 0.12,
        WeatherAmbientKind.fog => 0.14,
        WeatherAmbientKind.drizzle => 0.14,
        WeatherAmbientKind.rain => 0.14,
        WeatherAmbientKind.snow => 0.2,
        WeatherAmbientKind.thunder => 0.1,
        _ => 0.18,
      };
      top = Color.lerp(upper, rawTop, pull)!;
    }

    final gradient = [top, upper, lower, nearBody, floor];
    if (isDay) {
      // Jemné stlmenie — hlbší canvas, stále plynulý prechod do scrollu.
      const dimToBlack = 0.05;
      final adjusted = <Color>[
        Color.lerp(
          Color.lerp(gradient[0], gradient[1], 0.45)!,
          Colors.black,
          dimToBlack,
        )!,
        Color.lerp(
          Color.lerp(gradient[1], gradient[2], 0.25)!,
          Colors.black,
          dimToBlack * 0.7,
        )!,
        Color.lerp(gradient[2], Colors.black, dimToBlack * 0.4)!,
        gradient[3],
        gradient[4],
      ];
      return [
        adjusted[0],
        adjusted[1],
        adjusted[2],
        Color.lerp(adjusted[3], blendColor, 0.35)!,
        blendColor,
      ];
    }
    // Noc – rovnaký canvas ako UI, len veľmi mierne nadvihnutý.
    const nightLift = 0.06;
    const nightTint = Color(0xFF5A7088);
    final lifted = gradient
        .map((c) => Color.lerp(c, nightTint, nightLift)!)
        .toList(growable: false);
    return [
      lifted[0],
      lifted[1],
      Color.lerp(lifted[2], blendColor, 0.25)!,
      Color.lerp(lifted[3], blendColor, 0.55)!,
      blendColor,
    ];
  }
}

double _hash01(int i, int salt) {
  final v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453123;
  return v - v.floorToDouble();
}

/// Jeden statický prechod mraky / dážď / hviezdy – nakreslené raz pri zmene počasia (žiadny ticker).
class _HeroBackdropPainter extends CustomPainter {
  _HeroBackdropPainter({
    required this.kind,
    required this.isDay,
    required this.blendColor,
    this.simplifyForRecents = false,
  });

  final WeatherAmbientKind kind;
  final bool isDay;
  final Color blendColor;
  final bool simplifyForRecents;

  void _grain(Canvas canvas, Rect rect, {required double intensity}) {
    final w = rect.width;
    final h = rect.height;
    final count = math.min<int>(800, math.max<int>(380, (w * h / 5200).round()));
    final p = Paint()..blendMode = BlendMode.overlay;
    for (var i = 0; i < count; i++) {
      final x = rect.left + _hash01(i, 3) * w;
      final y = rect.top + _hash01(i, 5) * h;
      // Len tmavé zrno — biele „výbely“ cez overlay príliš „pália“ obrazovku.
      final a = intensity * (0.018 + _hash01(i, 13) * 0.024);
      p.color = Colors.black.withValues(alpha: a);
      final r = 0.42 + _hash01(i, 17) * 0.45;
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  void _blob(Canvas canvas, Offset c, double radius, Color tint, double peakOpacity) {
    if (peakOpacity <= 0.003 || radius <= 1) return;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        c,
        radius,
        [
          tint.withValues(alpha: peakOpacity * 0.9),
          tint.withValues(alpha: peakOpacity * 0.28),
          tint.withValues(alpha: 0),
        ],
        const [0.0, 0.45, 1.0],
      );
    canvas.drawCircle(c, radius, paint);
  }

  void _cloudMass(
    Canvas canvas,
    Size size,
    double phase,
    Color tint,
    double scale,
    double peakMul,
    List<(double fx, double fy, double fr, double w)> blobs, {
    double extraBaseYFrac = 0,
  }) {
    final baseX = size.width * (0.04 + phase * 0.08);
    final baseY = size.height * (0.04 + extraBaseYFrac + phase * 0.07);
    for (final b in blobs) {
      final cx = baseX + size.width * b.$1;
      final cy = baseY + size.height * b.$2;
      final r = size.shortestSide * b.$3 * b.$4 * scale;
      _blob(canvas, Offset(cx, cy), r, tint, 0.1 * scale * b.$4 * peakMul);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final colors = _Palette.skyGradientColors(kind, isDay, blendColor);
    // Lineárne rozložené stops — bez viditeľného „prahu" medzi pásmi, plynulý prechod.
    const stops = [0.0, 0.25, 0.5, 0.75, 1.0];

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, size.height * 0.94),
          colors,
          stops,
        ),
    );

    // Grain v recentoch = viditeľná mriežka bodiek — pri pause vynechať.
    if (!simplifyForRecents) {
      _grain(canvas, rect, intensity: 0.42);
    }

    // Oblaky (iba pár mäkkých „bubble“, staticky).
    const cloudTintDayBright = Color(0xFFE2EAF4);
    const cloudTintNight = Color(0xFFB4C9E8);
    final upper = _Palette.skyUpper(kind, isDay);
    // Cez deň oblaky NESMÚ byť takmer biele — vyrábajú svetlé „machule“ ktoré bijú do očí.
    final Color tint = isDay
        ? switch (kind) {
            WeatherAmbientKind.clear => cloudTintDayBright,
            WeatherAmbientKind.partlyCloudy =>
              Color.lerp(upper, const Color(0xFFB6C5D8), 0.30)!,
            WeatherAmbientKind.cloudy =>
              Color.lerp(upper, const Color(0xFF7E94AE), 0.20)!,
            _ => Color.lerp(upper, const Color(0xFF94A8BF), 0.30)!,
          }
        : cloudTintNight;

    final sc = switch (kind) {
      WeatherAmbientKind.clear => 0.42,
      WeatherAmbientKind.partlyCloudy => 0.74,
      WeatherAmbientKind.cloudy => 0.9,
      WeatherAmbientKind.fog => 0.88,
      WeatherAmbientKind.drizzle => 0.8,
      WeatherAmbientKind.rain => 0.84,
      WeatherAmbientKind.snow => 0.82,
      WeatherAmbientKind.thunder => 1.0,
    };

    final peakMul = switch (kind) {
      WeatherAmbientKind.clear => 1.0,
      WeatherAmbientKind.partlyCloudy => isDay ? 0.36 : 0.78,
      WeatherAmbientKind.cloudy => isDay ? 0.22 : 0.4,
      WeatherAmbientKind.fog => 0.42,
      WeatherAmbientKind.drizzle => isDay ? 0.26 : 0.38,
      WeatherAmbientKind.rain => isDay ? 0.28 : 0.42,
      WeatherAmbientKind.snow => isDay ? 0.34 : 0.55,
      WeatherAmbientKind.thunder => 0.42,
    };

    // Cez deň oblaky pri zamračenom / mokrom počasí nekreslíme — vyrábali svetlé fľaky po bokoch a hore.
    // V noci a pri „partlyCloudy“ ostávajú jemné blobs pre atmosféru.
    final bool drawCloudBlobs = kind != WeatherAmbientKind.clear &&
        !(isDay &&
            (kind == WeatherAmbientKind.cloudy ||
                kind == WeatherAmbientKind.drizzle ||
                kind == WeatherAmbientKind.rain ||
                kind == WeatherAmbientKind.thunder ||
                kind == WeatherAmbientKind.fog));
    if (drawCloudBlobs) {
      final extraY = isDay
          ? (kind == WeatherAmbientKind.cloudy
              ? 0.16
              : kind == WeatherAmbientKind.partlyCloudy
                  ? 0.12
                  : 0.10)
          : 0.05;
      final a = <(double, double, double, double)>[
        (-0.02, 0.06, 0.88, 1.0),
        (0.28, 0.02, 0.72, 0.88),
        (0.58, 0.08, 0.62, 0.78),
        (0.2, 0.12, 0.54, 0.68),
      ];
      _cloudMass(canvas, size, 0, tint, sc, peakMul, a,
          extraBaseYFrac: extraY);
      final b = <(double, double, double, double)>[
        (0.06, 0.19, 0.58, 0.54),
        (0.72, 0.15, 0.52, 0.5),
      ];
      _cloudMass(canvas, size, 0.95, tint, sc * 0.75, peakMul, b,
          extraBaseYFrac: extraY);
    }

    if (!simplifyForRecents &&
        !isDay &&
        (kind == WeatherAmbientKind.clear || kind == WeatherAmbientKind.partlyCloudy)) {
      final p = Paint()..style = PaintingStyle.fill;
      for (var i = 0; i < 22; i++) {
        final sx = _hash01(i, 1) * size.width;
        final sy = _hash01(i, 2) * size.height * 0.34;
        p.color = const Color(0xFFE8EEF8).withValues(alpha: 0.09 + _hash01(i, 43) * 0.06);
        canvas.drawCircle(Offset(sx, sy), i % 7 == 0 ? 1.05 : 0.65, p);
      }
    }

    if (kind == WeatherAmbientKind.fog) {
      const mist = Color(0xFFE8EFF8);
      for (var i = 0; i < 4; i++) {
        final cy = size.height * (0.3 + i * 0.12);
        final cx = size.width * (0.5 + (i.isEven ? 0.06 : -0.08));
        _blob(canvas, Offset(cx, cy), size.width * (0.42 + i * 0.04), mist, 0.048 + i * 0.01);
      }
    }

    if (kind == WeatherAmbientKind.drizzle || kind == WeatherAmbientKind.rain || kind == WeatherAmbientKind.thunder) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..strokeCap = StrokeCap.round;
      final dens = switch (kind) {
        WeatherAmbientKind.drizzle => 0.22,
        _ => 0.4,
      };
      final n = (size.width * size.height / 6500 * dens).round().clamp(14, 48);
      for (var i = 0; i < n; i++) {
        final x = (i * 107.9 + size.width * 0.06) % size.width;
        final baseY = (i * 67.7) % size.height + size.height * 0.06;
        paint.color = const Color(0xFFC9DBF0).withValues(alpha: 0.055 + (i % 4) * 0.017);
        final len = kind == WeatherAmbientKind.drizzle ? 4.5 : 6.8;
        canvas.drawLine(Offset(x, baseY), Offset(x - 1.4, baseY + len), paint);
      }
    }

    if (kind == WeatherAmbientKind.snow) {
      final p = Paint()..style = PaintingStyle.fill;
      final n = (size.width * size.height / 9000).round().clamp(10, 36);
      for (var i = 0; i < n; i++) {
        final x = (_hash01(i, 71) * size.width + _hash01(i, 73) * 8) % size.width;
        final y = _hash01(i, 77) * size.height * 0.95;
        p.color = const Color(0xFFF4F9FF).withValues(alpha: 0.08 + (i % 4) * 0.022);
        canvas.drawCircle(Offset(x, y), 0.9 + (i % 3) * 0.22, p);
      }
    }

    // Bočný vignette — jemné stmavenie pri ľavom a pravom okraji, aby pozadie po bokoch nepôsobilo svetlejšie než stred.
    if (isDay) {
      final sideShader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, 0),
        [
          const Color(0xFF0A1018).withValues(alpha: 0.22),
          Colors.transparent,
          Colors.transparent,
          const Color(0xFF0A1018).withValues(alpha: 0.22),
        ],
        const [0.0, 0.22, 0.78, 1.0],
      );
      canvas.drawRect(rect, Paint()..shader = sideShader);
    }

    // Vrchný tlmiaci overlay — výrazný tmavý nátok zhora, aby status bar / hlavička nepôsobili „pálivo“.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, size.height * 0.45),
          [
            const Color(0xFF0A1018).withValues(alpha: isDay ? 0.58 : 0.34),
            const Color(0xFF0A1018).withValues(alpha: isDay ? 0.42 : 0.22),
            const Color(0xFF0A1018).withValues(alpha: isDay ? 0.18 : 0.08),
            Colors.transparent,
          ],
          const [0.0, 0.3, 0.65, 1.0],
        ),
    );

    // Spodný „nátok" ku karte — výrazne jemnejší, aby pozadie hore a dole bolo vizuálne podobne svetlé.
    final dayMode = isDay;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.04),
          Offset(0, size.height),
          dayMode
              ? [
                  blendColor.withValues(alpha: 0.30),
                  blendColor.withValues(alpha: 0.55),
                  blendColor.withValues(alpha: 0.78),
                  blendColor.withValues(alpha: 0.92),
                  blendColor,
                  blendColor,
                  blendColor,
                ]
              : [
                  blendColor.withValues(alpha: 0.34),
                  blendColor.withValues(alpha: 0.60),
                  blendColor.withValues(alpha: 0.82),
                  blendColor.withValues(alpha: 0.94),
                  blendColor,
                  blendColor,
                  blendColor,
                ],
          const [0.0, 0.18, 0.4, 0.6, 0.8, 0.9, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _HeroBackdropPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.isDay != isDay ||
        oldDelegate.blendColor != blendColor ||
        oldDelegate.simplifyForRecents != simplifyForRecents;
  }
}

/// Pozadie hornej časti obrazovky (ľahké, bez neustálej animácie).
class WeatherHeroAmbient extends StatelessWidget {
  const WeatherHeroAmbient({
    super.key,
    required this.weatherCode,
    required this.isDay,
    required this.blendColor,
    this.simplifyForRecents = false,
  });

  final int weatherCode;
  final bool isDay;
  final Color blendColor;
  final bool simplifyForRecents;

  @override
  Widget build(BuildContext context) {
    final kind = ambientKindForWeatherCode(weatherCode);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HeroBackdropPainter(
          kind: kind,
          isDay: isDay,
          blendColor: blendColor,
          simplifyForRecents: simplifyForRecents,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
