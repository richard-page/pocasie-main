part of 'main.dart';

Color _chartTemperatureColor(double? temp) {
  if (temp == null) return Colors.white;
  const stops = <({double t, Color c})>[
    (t: -50.0, c: Color(0xFFECEFF1)),
    (t: -40.0, c: Color(0xFFB0BEC5)),
    (t: -30.0, c: Color(0xFFCE93D8)),
    (t: -20.0, c: Color(0xFF7E57C2)),
    (t: -10.0, c: Color(0xFF3949AB)),
    (t: 0.0, c: Color(0xFF29B6F6)),
    (t: 10.0, c: Color(0xFF64DD17)),
    (t: 20.0, c: Color(0xFFFFD600)),
    (t: 30.0, c: Color(0xFFFF6D00)),
    (t: 40.0, c: Color(0xFFE53935)),
    (t: 50.0, c: Color(0xFFE040FB)),
  ];
  if (temp <= stops.first.t) return stops.first.c;
  if (temp >= stops.last.t) return stops.last.c;
  for (int i = 0; i < stops.length - 1; i++) {
    final a = stops[i];
    final b = stops[i + 1];
    if (temp >= a.t && temp <= b.t) {
      final f = (temp - a.t) / (b.t - a.t);
      return Color.lerp(a.c, b.c, f) ?? a.c;
    }
  }
  return Colors.white;
}

Color _chartTextOn(Color background) =>
    background.computeLuminance() > 0.52 ? const Color(0xFF1A2433) : Colors.white;

const _kChartTextPrimary = Color(0xFFF2F6FA);
const _kChartTextSecondary = Color(0xFFD4DEE9);
const _kChartTextMuted = Color(0xFFAEBBCC);

const _kChartLineBlue = Color(0xFF42A5F5);
const _kChartIconBlue = Color(0xFF64B5F6);

/// Malé dlaždice v grafe (Najteplejšie, legenda teploty) — nie pozadie celej stránky.
BoxDecoration _chartStatTileDecoration({double radius = 12}) {
  return BoxDecoration(
    color: Color.alphaBlend(
      Colors.white.withValues(alpha: 0.18),
      const Color(0xFF152433),
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.18),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

Widget _chartSectionDivider() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Divider(
      height: 1,
      thickness: 1,
      color: Colors.white.withValues(alpha: 0.14),
    ),
  );
}

TextStyle _chartLabelStyle({double size = 12, FontWeight weight = FontWeight.w600}) {
  return TextStyle(
    color: _kChartTextSecondary,
    fontSize: size,
    fontWeight: weight,
    height: 1.2,
  );
}

TextStyle _chartValueStyle({double size = 20}) {
  return TextStyle(
    color: _kChartTextPrimary,
    fontSize: size,
    fontWeight: FontWeight.w800,
    height: 1,
    letterSpacing: -0.3,
  );
}

TextStyle _chartCaptionStyle({double size = 11.5}) {
  return TextStyle(
    color: _kChartTextMuted,
    fontSize: size,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}

const _kChartDayStripHeight = 292.0;

const _kThunderWmoCodes = <int>{95, 96, 99};

bool _isThunderWmoCode(int code) => _kThunderWmoCodes.contains(code);

/// Rovnaká denná ikona ako v zozname predpovede — podľa nej rozhodneme búrkovú pill.
/// Má aspoň jedna hodina v kalendárnom dni radarom potvrdené zrážky?
bool _chartCalendarDayHasRadarPrecip(
  HourlyForecast hourly,
  String datePrefix,
  DateTime locTime,
  RadarNowcastContext radarCtx, {
  int? utcOffsetSeconds,
}) {
  if (!radarCtx.eligible) return false;
  for (var i = 0; i < hourly.time.length; i++) {
    if (!hourly.time[i].startsWith(datePrefix)) continue;
    final parsed = _tryParseHourlyTimestamp(hourly.time[i]);
    if (parsed == null) continue;
    final localParsed = _hourlyParsedLocal(parsed, utcOffsetSeconds);
    final slotHour = DateTime(
      localParsed.year,
      localParsed.month,
      localParsed.day,
      localParsed.hour,
    );
    if (radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime)) return true;
  }
  return false;
}

double? _chartDayTempC(WeatherData data, int dayIndex) {
  final d = data.daily!;
  final h = data.hourly;
  final dateStr = d.time[dayIndex];
  if (h != null) {
    for (var i = 0; i < h.time.length; i++) {
      if (!h.time[i].startsWith(dateStr)) continue;
      final parsed = _tryParseHourlyTimestamp(h.time[i]);
      if (parsed == null) continue;
      final local = _hourlyParsedLocal(parsed, data.utcOffsetSeconds);
      if (local.hour == 12 || local.hour == 13) {
        return h.temperature?[i];
      }
    }
  }
  final max = d.tempMax?[dayIndex];
  final min = d.tempMin?[dayIndex];
  if (max != null && min != null) return (max + min) / 2;
  return max ?? min;
}

/// Denná ikona v grafe — ECMWF + radar (dážď / sneh) keď mapa potvrdí zrážky.
int _chartDayDisplayIconCode(
  WeatherData data,
  int dayIndex, {
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
}) {
  var code = _dailyMainIconSkyTextCode(data, dayIndex);
  if (!radarCtx.eligible) return code;

  final daily = data.daily;
  final h = data.hourly;
  if (daily == null || h == null || dayIndex < 0 || dayIndex >= daily.time.length) {
    return code;
  }

  final locTime = DateTime.now().toUtc().add(
        Duration(seconds: data.utcOffsetSeconds ?? 0),
      );
  final dateStr = daily.time[dayIndex];
  if (!_chartCalendarDayHasRadarPrecip(
    h,
    dateStr,
    locTime,
    radarCtx,
    utcOffsetSeconds: data.utcOffsetSeconds,
  )) {
    return code;
  }

  return applyRadarPrecipToDayPartIcon(
    code,
    radarCtx: radarCtx,
    partHasRadarPrecip: true,
    tempC: _chartDayTempC(data, dayIndex),
  );
}

/// Nočná ikona v grafe — mesiac, alebo zrážky podľa radaru v nočnom úseku.
int _chartNightDisplayIconCode(
  WeatherData data,
  int dayIndex, {
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
}) {
  const moonCode = 0;
  if (!radarCtx.eligible) return moonCode;

  final daily = data.daily;
  final h = data.hourly;
  if (daily == null || h == null || dayIndex < 0 || dayIndex >= daily.time.length) {
    return moonCode;
  }

  final locTime = DateTime.now().toUtc().add(
        Duration(seconds: data.utcOffsetSeconds ?? 0),
      );
  final dateStr = daily.time[dayIndex];
  final nightRadar = _dayPartHasRadarPrecip(
    h,
    dateStr,
    'night',
    locTime,
    radarCtx,
    utcOffsetSeconds: data.utcOffsetSeconds,
  );
  if (!nightRadar) return moonCode;

  double? nightTemp;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(dateStr)) continue;
    final parsed = _tryParseHourlyTimestamp(h.time[i]);
    if (parsed == null) continue;
    final local = _hourlyParsedLocal(parsed, data.utcOffsetSeconds);
    if (local.hour >= 22 || local.hour <= 4) {
      nightTemp = h.temperature?[i];
      break;
    }
  }
  nightTemp ??= _chartDayTempC(data, dayIndex);

  return applyRadarPrecipToDayPartIcon(
    moonCode,
    radarCtx: radarCtx,
    partHasRadarPrecip: true,
    tempC: nightTemp,
  );
}

int _chartRadarProbForDay(
  WeatherData data,
  int dayIndex,
  RadarNowcastContext radarCtx,
) {
  if (!radarCtx.eligible) return 0;
  final h = data.hourly;
  final daily = data.daily;
  if (h == null || daily == null || dayIndex < 0 || dayIndex >= daily.time.length) {
    return 0;
  }
  final locTime = DateTime.now().toUtc().add(
        Duration(seconds: data.utcOffsetSeconds ?? 0),
      );
  if (!_chartCalendarDayHasRadarPrecip(
    h,
    daily.time[dayIndex],
    locTime,
    radarCtx,
    utcOffsetSeconds: data.utcOffsetSeconds,
  )) {
    return 0;
  }
  final dbz = radarCtx.precipNow || radarCtx.rainAtPinNow
      ? radarCtx.precipIntensityDbz
      : radarCtx.stripDisplayDbz;
  return effectiveRadarProbFromDbz(dbz, radarCtx);
}

bool _chartDayShowsThunderIcon(
  WeatherData data,
  int dayIndex, {
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
}) =>
    _isThunderWmoCode(
      _chartDayDisplayIconCode(data, dayIndex, radarCtx: radarCtx),
    );

String _chartCalendarDateKey(String dateStr) {
  final dt = DateTime.tryParse(dateStr);
  if (dt != null) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
  final t = dateStr.indexOf('T');
  return t > 0 ? dateStr.substring(0, t) : dateStr;
}

int _chartHourPrecipProb(HourlyForecast h, int index) {
  final list = h.precipitationProbability;
  if (list == null || index < 0 || index >= list.length) return 0;
  return (list[index] ?? 0).clamp(0, 100);
}

List<int> _chartHourIndicesForDay(
  HourlyForecast h,
  DailyForecast daily,
  int dayIndex,
) {
  final out = <int>[];
  for (var i = 0; i < h.time.length; i++) {
    if (_getDayIndexForHour(h.time[i], daily) == dayIndex) out.add(i);
  }
  return out;
}

/// Zaokrúhlenie na pill; kladná hodnota z API nikdy nespadne na 0 %.
int _chartPercentForChip(int raw) {
  if (raw <= 0) return 0;
  final rounded = _roundPrecipProbabilityForDisplay(raw);
  if (rounded > 0) return rounded;
  return 10;
}

int _chartThunderRaw({
  required WeatherData data,
  required int dayIndex,
  required String dayKey,
  required int dailyProb,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
}) {
  final h = data.hourly;
  final daily = data.daily!;
  if (!_chartDayShowsThunderIcon(data, dayIndex, radarCtx: radarCtx)) return 0;

  var maxThunder = 0;

  if (h != null) {
    for (final i in _chartHourIndicesForDay(h, daily, dayIndex)) {
      final rawCode = h.weatherCode?[i] ?? 0;
      final rawProb = _chartHourPrecipProb(h, i);
      final mm = (h.precipitation != null && i < h.precipitation!.length)
          ? (h.precipitation![i] ?? 0.0)
          : 0.0;
      final cloud = (h.cloudCover != null && i < h.cloudCover!.length)
          ? h.cloudCover![i]
          : null;

      final displayCode = _weatherIconCodeWithPrecipThreshold(
        rawCode,
        rawProb,
        cloudCoverPercent: cloud,
        hourlyPrecipitationMm: mm,
      );
      if (!_isThunderWmoCode(displayCode)) continue;
      if (!_thunderIconWarranted(rawProb, mm)) continue;
      final chip = _chartPercentForChip(rawProb);
      if (chip > maxThunder) maxThunder = chip;
    }

    final current = data.current;
    if (current != null) {
      final loc = DateTime.now().toUtc().add(
            Duration(seconds: data.utcOffsetSeconds ?? 0),
          );
      final fair = _hourlyFairDisplayIconsForCalendarDay(
        h,
        dayKey,
        current,
        daily,
        loc,
      );
      if (fair != null) {
        final (start, icons) = fair;
        for (var j = 0; j < icons.length; j++) {
          if (!_isThunderWmoCode(icons[j])) continue;
          final idx = start + j;
          if (idx < 0 || idx >= h.time.length) continue;
          final rawProb = _chartHourPrecipProb(h, idx);
          final mm = (h.precipitation != null && idx < h.precipitation!.length)
              ? (h.precipitation![idx] ?? 0.0)
              : 0.0;
          if (!_thunderIconWarranted(rawProb, mm)) continue;
          final chip = _chartPercentForChip(rawProb);
          if (chip > maxThunder) maxThunder = chip;
        }
      }
    }
  }

  if (maxThunder == 0 && dailyProb > 0) {
    maxThunder = _chartPercentForChip(dailyProb);
  }

  return maxThunder.clamp(0, 100);
}

/// Dažďová pill vždy; búrková len pri daždi a búrkovej ikone ([thunder] môže byť null).
({int rain, int? thunder}) _chartPrecipProbsForDay({
  required WeatherData data,
  required int dayIndex,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
}) {
  final daily = data.daily!;
  final hourly = data.hourly;
  final dayKey = _chartCalendarDateKey(daily.time[dayIndex]);
  final dailyProb = (daily.precipProbMax?[dayIndex] ?? 0).clamp(0, 100);

  var rainRaw = dailyProb;
  if (hourly != null) {
    for (final i in _chartHourIndicesForDay(hourly, daily, dayIndex)) {
      rainRaw = math.max(rainRaw, _chartHourPrecipProb(hourly, i));
    }
  }
  rainRaw = math.max(rainRaw, _chartRadarProbForDay(data, dayIndex, radarCtx));
  final rain = _chartPercentForChip(rainRaw);

  if (rain <= 0 ||
      !_chartDayShowsThunderIcon(data, dayIndex, radarCtx: radarCtx)) {
    return (rain: rain, thunder: null);
  }

  final thunderRaw = _chartThunderRaw(
    data: data,
    dayIndex: dayIndex,
    dayKey: dayKey,
    dailyProb: dailyProb,
    radarCtx: radarCtx,
  );
  if (thunderRaw <= 0) return (rain: rain, thunder: null);

  var thunder = _chartPercentForChip(thunderRaw);
  if (thunder <= 0) return (rain: rain, thunder: null);
  if (thunder > rain) thunder = rain;

  return (rain: rain, thunder: thunder);
}

BoxDecoration _chartGlassDecoration(double borderRadius) {
  const fillBase = kAmbientBlendColor;
  final fillTop = Color.alphaBlend(Colors.white.withValues(alpha: 0.09), fillBase);
  final fillBottom = Color.alphaBlend(Colors.white.withValues(alpha: 0.045), fillBase);
  return BoxDecoration(
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.14),
      width: 1,
    ),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [fillTop, fillBottom],
    ),
  );
}

Widget _chartGlassPanel({required Widget child}) {
  const radius = 16.0;
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: DecoratedBox(
        decoration: _chartGlassDecoration(radius),
        child: child,
      ),
    ),
  );
}

const _kForecastSubpageSystemUi = SystemUiOverlayStyle(
  systemNavigationBarColor: kAmbientBlendColor,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarDividerColor: kAmbientBlendColor,
  systemNavigationBarContrastEnforced: false,
);

Widget _forecastSubpageBackButton(BuildContext context, {IconData icon = Icons.arrow_back}) {
  return GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Icon(icon, size: 22, color: Colors.white)),
    ),
  );
}

PreferredSizeWidget _forecastSubpageAppBar({
  required String title,
  Widget? leading,
  List<Widget>? actions,
}) {
  return AppBar(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    foregroundColor: Colors.white,
    centerTitle: true,
    automaticallyImplyLeading: false,
    leading: leading,
    leadingWidth: leading != null ? 56 : null,
    title: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    actions: actions,
  );
}

Widget _forecastGlassBody({required Widget child, EdgeInsets? padding}) {
  return Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: _chartGlassPanel(child: child),
  );
}

/// Rovnaké pozadie ako graf — ambient cez app + sklenený panel obsahu.
class ForecastSubpageScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final bool wrapBodyInGlass;
  final Widget? leading;
  final List<Widget>? actions;

  const ForecastSubpageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.wrapBodyInGlass = true,
    this.leading,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _kForecastSubpageSystemUi,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _forecastSubpageAppBar(
          title: title,
          leading: leading ?? _forecastSubpageBackButton(context),
          actions: actions,
        ),
        body: SafeArea(
          bottom: false,
          child: wrapBodyInGlass ? _forecastGlassBody(child: body) : body,
        ),
      ),
    );
  }
}


class WeatherChartPage extends StatelessWidget {
  final GeoCity city;
  final WeatherData data;
  final RadarNowcastContext radarCtx;

  const WeatherChartPage({
    super.key,
    required this.city,
    required this.data,
    this.radarCtx = RadarNowcastContext.inactive,
  });

  String get _modelLabel => 'ECMWF IFS';
  bool get _radarAugmentsChart =>
      radarCtx.eligible && radarNowcastActiveForCity(city);

  @override
  Widget build(BuildContext context) {
    final daily = data.daily;
    final dayCount = math.min(daily?.time.length ?? 0, kChartForecastDays);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      dayCount > 0 ? 'Graf na $kChartForecastDays dní' : 'Graf predpovede',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                _radarAugmentsChart
                    ? 'Denné maximum, minimum a pravdepodobnosť zrážok z Open-Meteo (ECMWF). '
                        'Ak radar detekuje dážď alebo sneh, dnes sa zobrazí zrážková ikona.'
                    : 'Denné maximum, minimum, pravdepodobnosť zrážok a typ počasia z aktuálnej predpovede Open-Meteo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$_modelLabel pre ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Icon(Icons.location_on, color: Color(0xFFFCD34D), size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      city.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (dayCount == 0)
              Expanded(
                child: Center(
                  child: Text(
                    'Predpoveď nie je k dispozícii.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ),
              )
            else
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                    child: _chartGlassPanel(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ChartSummaryStrip(data: data, radarCtx: radarCtx),
                          _ChartDaysScroller(
                            data: data,
                            dayCount: dayCount,
                            radarCtx: radarCtx,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChartPeriodStats {
  final int? warmestDay;
  final double? warmestMax;
  final int? coldestDay;
  final double? coldestMin;
  final int? rainDay;
  final int rainProb;

  const _ChartPeriodStats({
    this.warmestDay,
    this.warmestMax,
    this.coldestDay,
    this.coldestMin,
    this.rainDay,
    this.rainProb = 0,
  });

  factory _ChartPeriodStats.from(
    WeatherData data, {
    RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
  }) {
    final d = data.daily;
    if (d == null || d.time.isEmpty) return const _ChartPeriodStats();

    int? warmIdx;
    double? warmVal;
    int? coldIdx;
    double? coldVal;
    int? rainIdx;
    var rainVal = 0;

    final limit = math.min(d.time.length, kChartForecastDays);
    for (var i = 0; i < limit; i++) {
      final max = d.tempMax?[i];
      if (max != null && (warmVal == null || max > warmVal)) {
        warmVal = max;
        warmIdx = i;
      }
      final min = d.tempMin?[i];
      if (min != null && (coldVal == null || min < coldVal)) {
        coldVal = min;
        coldIdx = i;
      }
      final displayProb = _chartPrecipProbsForDay(
        data: data,
        dayIndex: i,
        radarCtx: radarCtx,
      ).rain;
      if (displayProb > rainVal) {
        rainVal = displayProb;
        rainIdx = i;
      }
    }

    return _ChartPeriodStats(
      warmestDay: warmIdx,
      warmestMax: warmVal,
      coldestDay: coldIdx,
      coldestMin: coldVal,
      rainDay: rainIdx,
      rainProb: rainVal,
    );
  }
}

String _chartDayLabel(DailyForecast d, int? index) {
  if (index == null || index < 0 || index >= d.time.length) return '--';
  final dt = DateTime.tryParse(d.time[index]);
  if (dt == null) return '--';
  const short = <String>['Po', 'Ut', 'St', 'Št', 'Pi', 'So', 'Ne'];
  return '${short[dt.weekday - 1]} ${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.';
}

class _ChartSummaryStrip extends StatelessWidget {
  final WeatherData data;
  final RadarNowcastContext radarCtx;

  const _ChartSummaryStrip({
    required this.data,
    this.radarCtx = RadarNowcastContext.inactive,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _ChartPeriodStats.from(data, radarCtx: radarCtx);
    final d = data.daily!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: _ChartStatTile(
              icon: Icons.wb_sunny_outlined,
              iconColor: const Color(0xFFFFB74D),
              label: 'Najteplejšie',
              value: stats.warmestMax != null ? '${stats.warmestMax!.round()}°' : '--',
              caption: _chartDayLabel(d, stats.warmestDay),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChartStatTile(
              icon: Icons.ac_unit,
              iconColor: const Color(0xFF81D4FA),
              label: 'Najchladnejšie',
              value: stats.coldestMin != null ? '${stats.coldestMin!.round()}°' : '--',
              caption: _chartDayLabel(d, stats.coldestDay),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChartStatTile(
              icon: Icons.water_drop_outlined,
              iconColor: const Color(0xFF64B5F6),
              label: 'Pravdepodobnosť',
              value: '${stats.rainProb}%',
              caption: _chartDayLabel(d, stats.rainDay),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartStatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String caption;

  const _ChartStatTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          Colors.white.withValues(alpha: 0.18),
          const Color(0xFF152433),
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 6),
          SizedBox(
            height: 26,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: _chartLabelStyle(size: 11.5),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: _chartValueStyle(),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _chartCaptionStyle(size: 11.5),
          ),
        ],
      ),
    );
  }
}

class _ChartTempLegend extends StatelessWidget {
  const _ChartTempLegend();

  @override
  Widget build(BuildContext context) {
    final gradientColors = List<Color>.generate(28, (i) {
      final t = -10.0 + (50.0 * i / 27);
      return _chartTemperatureColor(t);
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            Colors.white.withValues(alpha: 0.16),
            const Color(0xFF152433),
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Farba = teplota (max. cez deň)',
              textAlign: TextAlign.center,
              style: _chartLabelStyle(size: 12.5),
            ),
            const SizedBox(height: 10),
            Container(
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                gradient: LinearGradient(colors: gradientColors),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _legendTick('-10°'),
                _legendTick('0°'),
                _legendTick('10°'),
                _legendTick('20°'),
                _legendTick('30°'),
                _legendTick('40°'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendTick(String label) {
    return Text(
      label,
      style: _chartCaptionStyle(size: 11.5).copyWith(
        color: _kChartTextSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ChartDayColumn extends StatelessWidget {
  final WeatherData data;
  final int dayIndex;
  final RadarNowcastContext radarCtx;

  const _ChartDayColumn({
    required this.data,
    required this.dayIndex,
    this.radarCtx = RadarNowcastContext.inactive,
  });

  static const _weekdayShort = <String>['Po', 'Ut', 'St', 'Št', 'Pi', 'So', 'Ne'];

  static String dateLabelFor(DailyForecast d, int dayIndex) {
    final dt = DateTime.tryParse(d.time[dayIndex]);
    if (dt == null) return '--';
    return '${_weekdayShort[dt.weekday - 1]} ${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.';
  }

  @override
  Widget build(BuildContext context) {
    final d = data.daily!;
    final h = data.hourly;
    final dateStr = d.time[dayIndex];

    double? max = d.tempMax?[dayIndex];
    double? min = d.tempMin?[dayIndex];
    if ((max == null || min == null) && h != null) {
      final fb = _chartFallbackTemps(dateStr, h);
      max ??= fb['max'];
      min ??= fb['min'];
    }

    final dayIconCode = _chartDayDisplayIconCode(
      data,
      dayIndex,
      radarCtx: radarCtx,
    );
    final nightIconCode = _chartNightDisplayIconCode(
      data,
      dayIndex,
      radarCtx: radarCtx,
    );
    final precip = _chartPrecipProbsForDay(
      data: data,
      dayIndex: dayIndex,
      radarCtx: radarCtx,
    );

    return SizedBox(
      width: 54,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          getWeatherIcon(
            dayIconCode,
            size: 52,
            daily: d,
            hourTime: '${dateStr}T12:00',
          ),
          const SizedBox(height: 2),
          _TempPill(value: max, tall: true),
          const SizedBox(height: 2),
          _TempPill(value: min, tall: false),
          const SizedBox(height: 3),
          getWeatherIcon(
            nightIconCode,
            forceNight: !kPrecipitationCodes.contains(
              normalizeDisplayWeatherCode(nightIconCode),
            ),
            size: 52,
            daily: d,
            hourTime: '${dateStr}T23:00',
          ),
          const SizedBox(height: 2),
          if (precip.thunder != null) ...[
            _PrecipChip(
              percent: precip.thunder!,
              thunder: true,
            ),
            const SizedBox(height: 3),
          ],
          _PrecipChip(
            percent: precip.rain,
            thunder: false,
          ),
        ],
      ),
    );
  }

  Map<String, double?> _chartFallbackTemps(String dateStr, HourlyForecast h) {
    double? minT;
    double? maxT;
    for (int i = 0; i < h.time.length; i++) {
      if (!h.time[i].startsWith(dateStr)) continue;
      final t = h.temperature?[i];
      if (t == null) continue;
      minT = minT == null ? t : math.min(minT, t);
      maxT = maxT == null ? t : math.max(maxT, t);
    }
    return {'min': minT, 'max': maxT};
  }
}

List<({double? max, double? min})> _chartDailyTempsForCurve(
  WeatherData data,
  int dayCount,
) {
  final d = data.daily!;
  final h = data.hourly;
  final rows = <({double? max, double? min})>[];
  for (var i = 0; i < dayCount; i++) {
    final dateStr = d.time[i];
    double? max = d.tempMax?[i];
    double? min = d.tempMin?[i];
    if ((max == null || min == null) && h != null) {
      double? minT;
      double? maxT;
      for (var j = 0; j < h.time.length; j++) {
        if (!h.time[j].startsWith(dateStr)) continue;
        final t = h.temperature?[j];
        if (t == null) continue;
        minT = minT == null ? t : math.min(minT, t);
        maxT = maxT == null ? t : math.max(maxT, t);
      }
      max ??= maxT;
      min ??= minT;
    }
    rows.add((max: max, min: min));
  }
  return rows;
}

List<double?> _chartDailyMaxTemps(WeatherData data, int dayCount) =>
    _chartDailyTempsForCurve(data, dayCount).map((e) => e.max).toList();

({double yMin, double yMax}) _chartTempYRange(List<double?> temps) {
  final vals = temps.whereType<double>().toList();
  if (vals.isEmpty) return (yMin: 0, yMax: 1);
  var yMin = vals.reduce(math.min);
  var yMax = vals.reduce(math.max);
  if ((yMax - yMin).abs() < 4) {
    yMin -= 2;
    yMax += 2;
  } else {
    yMin -= 1;
    yMax += 1;
  }
  return (yMin: yMin, yMax: yMax);
}

class _ChartDaysScroller extends StatefulWidget {
  final WeatherData data;
  final int dayCount;
  final RadarNowcastContext radarCtx;

  const _ChartDaysScroller({
    required this.data,
    required this.dayCount,
    this.radarCtx = RadarNowcastContext.inactive,
  });

  @override
  State<_ChartDaysScroller> createState() => _ChartDaysScrollerState();
}

class _ChartDaysScrollerState extends State<_ChartDaysScroller> {
  late final ScrollController _columnsCtrl;
  late final ScrollController _datesCtrl;
  late final ScrollController _chartCtrl;
  bool _syncing = false;

  static const _itemWidth = 54.0;
  static const _separator = 6.0;
  static const _hPad = 8.0;
  static const _chartHeight = 84.0;
  static const _chartTopPad = 8.0;
  static const _chartBottomPad = 4.0;

  double _contentWidth(int dayCount) {
    if (dayCount <= 0) return 0;
    return dayCount * _itemWidth + (dayCount - 1) * _separator;
  }

  @override
  void initState() {
    super.initState();
    _columnsCtrl = ScrollController()..addListener(() => _syncScroll(_columnsCtrl));
    _datesCtrl = ScrollController()..addListener(() => _syncScroll(_datesCtrl));
    _chartCtrl = ScrollController()..addListener(() => _syncScroll(_chartCtrl));
  }

  void _syncScroll(ScrollController source) {
    if (_syncing || !source.hasClients) return;
    _syncing = true;
    final offset = source.offset;
    for (final ctrl in [_columnsCtrl, _datesCtrl, _chartCtrl]) {
      if (ctrl != source && ctrl.hasClients && (ctrl.offset - offset).abs() > 0.5) {
        ctrl.jumpTo(offset);
      }
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _columnsCtrl.dispose();
    _datesCtrl.dispose();
    _chartCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data.daily!;
    final maxTemps = _chartDailyMaxTemps(widget.data, widget.dayCount);
    final yRange = _chartTempYRange(maxTemps);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _kChartDayStripHeight,
          child: ListView.separated(
            controller: _columnsCtrl,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _hPad),
            itemCount: widget.dayCount,
            separatorBuilder: (_, __) => const SizedBox(width: _separator),
            itemBuilder: (context, index) => SizedBox(
              width: _itemWidth,
              child: _ChartDayColumn(
                data: widget.data,
                dayIndex: index,
                radarCtx: widget.radarCtx,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 20,
          child: ListView.separated(
            controller: _datesCtrl,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _hPad),
            itemCount: widget.dayCount,
            separatorBuilder: (_, __) => const SizedBox(width: _separator),
            itemBuilder: (context, index) => SizedBox(
              width: _itemWidth,
              child: Text(
                _ChartDayColumn.dateLabelFor(d, index),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            height: _chartHeight,
            child: ListView(
              controller: _chartCtrl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _hPad),
              children: [
                SizedBox(
                  width: _contentWidth(widget.dayCount),
                  height: _chartHeight,
                  child: CustomPaint(
                    painter: _ChartTemperatureCurvePainter(
                      temps: maxTemps,
                      itemWidth: _itemWidth,
                      separator: _separator,
                      yMin: yRange.yMin,
                      yMax: yRange.yMax,
                      topPad: _chartTopPad,
                      bottomPad: _chartBottomPad,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const _ChartTempLegend(),
        if (widget.dayCount > 7)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Potiahnite vľavo pre ďalšie dni →',
              textAlign: TextAlign.center,
              style: _chartLabelStyle(size: 12).copyWith(
                color: _kChartTextSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChartTemperatureCurvePainter extends CustomPainter {
  final List<double?> temps;
  final double itemWidth;
  final double separator;
  final double yMin;
  final double yMax;
  final double topPad;
  final double bottomPad;

  _ChartTemperatureCurvePainter({
    required this.temps,
    required this.itemWidth,
    required this.separator,
    required this.yMin,
    required this.yMax,
    required this.topPad,
    required this.bottomPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (temps.isEmpty || size.width <= 0 || size.height <= 0) return;

    final plotH = size.height - topPad - bottomPad;
    if (plotH <= 0) return;

    double xFor(int i) => i * (itemWidth + separator) + itemWidth / 2;
    double yFor(double t) => topPad + (1 - (t - yMin) / (yMax - yMin)) * plotH;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var g = 0; g < 4; g++) {
      final gy = topPad + (g / 3) * plotH;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    Offset? pointAt(int i) {
      final v = temps[i];
      if (v == null) return null;
      return Offset(xFor(i), yFor(v));
    }

    final linePath = Path();
    var started = false;
    for (var i = 0; i < temps.length; i++) {
      final p = pointAt(i);
      if (p == null) {
        started = false;
        continue;
      }
      if (!started) {
        linePath.moveTo(p.dx, p.dy);
        started = true;
      } else {
        linePath.lineTo(p.dx, p.dy);
      }
    }
    if (!started) return;

    const lineColor = Color(0xFF42A5F5);

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor.withValues(alpha: 0.92)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < temps.length; i++) {
      final p = pointAt(i);
      if (p == null) continue;
      canvas.drawCircle(p, 3, Paint()..color = lineColor);
      canvas.drawCircle(
        p,
        3,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartTemperatureCurvePainter oldDelegate) =>
      oldDelegate.temps != temps ||
      oldDelegate.yMin != yMin ||
      oldDelegate.yMax != yMax;
}

class _TempPill extends StatelessWidget {
  final double? value;
  final bool tall;

  const _TempPill({required this.value, required this.tall});

  @override
  Widget build(BuildContext context) {
    final bg = _chartTemperatureColor(value);
    final fg = _chartTextOn(bg);
    final label = value != null ? '${value!.round()}' : '--';

    return Container(
      width: 34,
      height: tall ? 80 : 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: tall ? 18 : 15,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _PrecipChip extends StatelessWidget {
  final int percent;
  final bool thunder;

  const _PrecipChip({
    required this.percent,
    required this.thunder,
  });

  @override
  Widget build(BuildContext context) {
    final bg = thunder ? const Color(0xFF7E57C2) : const Color(0xFF42A5F5);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            thunder ? Icons.bolt : Icons.water_drop,
            size: 13,
            color: Colors.white,
          ),
          const SizedBox(width: 2),
          Text(
            '$percent%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
