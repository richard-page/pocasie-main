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

const _kDayColumnHeight = 346.0;

const _kThunderWmoCodes = <int>{95, 96, 99};

bool _isThunderWmoCode(int code) => _kThunderWmoCodes.contains(code);

/// Rovnaká denná ikona ako v zozname predpovede — podľa nej rozhodneme búrkovú pill.
bool _chartDayShowsThunderIcon(WeatherData data, int dayIndex) =>
    _isThunderWmoCode(_dailyMainIconSkyTextCode(data, dayIndex));

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
}) {
  final h = data.hourly;
  final daily = data.daily!;
  if (!_chartDayShowsThunderIcon(data, dayIndex)) return 0;

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
  final rain = _chartPercentForChip(rainRaw);

  if (rain <= 0 || !_chartDayShowsThunderIcon(data, dayIndex)) {
    return (rain: rain, thunder: null);
  }

  final thunderRaw = _chartThunderRaw(
    data: data,
    dayIndex: dayIndex,
    dayKey: dayKey,
    dailyProb: dailyProb,
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

Color _warningSeverityAccent(String severity) {
  final s = severity.toLowerCase();
  if (s.contains('red') || s.contains('cerven') || s.contains('červen')) {
    return const Color(0xFFE53935);
  }
  if (s.contains('orange') || s.contains('oranz') || s.contains('oranž')) {
    return const Color(0xFFFF9800);
  }
  if (s.contains('green') || s.contains('zelen')) {
    return const Color(0xFF66BB6A);
  }
  return const Color(0xFFFDD835);
}

String _warningPhenomenonLabel(String phenomenon) {
  final p = phenomenon.toLowerCase();
  // Map raw codes to readable Slovak labels
  if (p.contains('teploty_vysoke') || p.contains('vysoke_teploty')) {
    return 'Vysoké teploty';
  }
  if (p.contains('teploty_nizke') || p.contains('nizke_teploty')) {
    return 'Nízke teploty';
  }
  if (p.contains('vietor') || p.contains('wind')) {
    return 'Vietor';
  }
  if (p.contains('burk') || p.contains('storm')) {
    return 'Búrky';
  }
  if (p.contains('dazd') || p.contains('rain') || p.contains('zrazk')) {
    return 'Dážď';
  }
  if (p.contains('sneH') || p.contains('snow')) {
    return 'Sneh';
  }
  if (p.contains('povoden') || p.contains('flood')) {
    return 'Povodeň';
  }
  if (p.contains('hmla') || p.contains('fog')) {
    return 'Hmla';
  }
  if (p.contains('klzkost') || p.contains('ice')) {
    return 'Klzkosť';
  }
  // Fallback: remove underscores and capitalize
  return phenomenon.replaceAll('_', ' ');
}

IconData _warningPhenomenonIcon(String phenomenon) {
  final p = phenomenon.toLowerCase();
  if (p.contains('temp') || p.contains('teplot') || p.contains('horuc')) {
    return Icons.wb_sunny_outlined;
  }
  if (p.contains('rain') || p.contains('dazd') || p.contains('dažd')) {
    return Icons.water_drop_outlined;
  }
  if (p.contains('wind') || p.contains('vietor')) {
    return Icons.air_rounded;
  }
  if (p.contains('snow') || p.contains('sneh')) {
    return Icons.ac_unit;
  }
  if (p.contains('storm') || p.contains('burk')) {
    return Icons.thunderstorm_outlined;
  }
  return Icons.warning_amber_rounded;
}

class WarningsListPage extends StatelessWidget {
  final List<WarningData> warnings;
  final GeoCity? city;
  final String? webFallbackUrl;

  const WarningsListPage({
    super.key,
    required this.warnings,
    this.city,
    this.webFallbackUrl,
  });

  @override
  Widget build(BuildContext context) {
    final title = warnings.length == 1 ? 'Výstraha' : 'Výstrahy';

    return ForecastSubpageScaffold(
      title: title,
      body: warnings.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  city != null
                      ? 'Pre ${city!.name} momentálne nie sú aktívne výstrahy.'
                      : 'Momentálne nie sú aktívne výstrahy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
              itemCount: warnings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                return _WarningNativeCard(warning: warnings[index]);
              },
            ),
    );
  }
}

class _WarningNativeCard extends StatelessWidget {
  final WarningData warning;

  const _WarningNativeCard({required this.warning});


  String get _severityLabel {
    final s = warning.severity.toLowerCase();
    if (s.contains('red') || s.contains('cerven') || s.contains('červen')) {
      return 'Červená výstraha';
    }
    if (s.contains('orange') || s.contains('oranz') || s.contains('oranž')) {
      return 'Oranžová výstraha';
    }
    if (s.contains('yellow') || s.contains('zlta') || s.contains('žltá') || s.contains('zlty')) {
      return 'Žltá výstraha';
    }
    return 'Výstraha';
  }

  Widget _buildDescriptionWithBlueValues(String text) {
    // Regex to match any numbers (temperatures like "33 - 34 °C" or just "33")
    final regex = RegExp(r'[0-9]+(?:\.[0-9]+)?(?:\s*(?:-|–|—|‑)\s*[0-9]+(?:\.[0-9]+)?)?(?:\s*°[Cc]?)?');
    final matches = regex.allMatches(text).where((m) => m.group(0)?.trim().isNotEmpty == true).toList();

    if (matches.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      );
    }

    final spans = <TextSpan>[];
    var currentIndex = 0;

    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, match.start),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(
          color: Color(0xFF64B5F6),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      ));
      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        children: spans,
      ),
    );
  }

  String _warningSeverityKey(String severity) {
    final s = severity.toLowerCase();
    if (s.contains('red') || s.contains('cerven') || s.contains('červen')) return 'red';
    if (s.contains('orange') || s.contains('oranz') || s.contains('oranž')) return 'orange';
    if (s.contains('green') || s.contains('zelen')) return 'green';
    return 'yellow';
  }

  String? _warningExpectedRangeHint(String label, String severityKey) {
    String? pick(Map<String, String> values) => values[severityKey] ?? values['yellow'];

    if (label.contains('horúc') || label.contains('teplot')) {
      return pick({
        'yellow': '33 – 34 °C',
        'orange': '35 – 37 °C',
        'red': '38 – 40 °C',
      });
    }
    if (label.contains('mraz') || label.contains('niz')) {
      return pick({
        'yellow': '-10 – -15 °C',
        'orange': '-15 – -20 °C',
        'red': '-20 – -25 °C',
      });
    }
    if (label.contains('vietor')) {
      return pick({
        'yellow': 'nárazy 65 – 85 km/h',
        'orange': 'nárazy 80 – 105 km/h',
        'red': 'nárazy 100 – 130 km/h',
      });
    }
    if (label.contains('búrk') || label.contains('burk')) {
      return pick({
        'yellow': 'zrážky 20 – 30 mm, vietor 65 km/h',
        'orange': 'zrážky 30 – 50 mm, vietor 90 km/h',
        'red': 'zrážky 50+ mm, vietor 110 km/h',
      });
    }
    if (label.contains('dážď') || label.contains('dazd')) {
      return pick({
        'yellow': 'úhrn 30 – 50 mm',
        'orange': 'úhrn 50 – 80 mm',
        'red': 'úhrn 80+ mm',
      });
    }
    if (label.contains('sneh')) {
      return pick({
        'yellow': 'nový sneh 10 – 20 cm',
        'orange': 'nový sneh 20 – 35 cm',
        'red': 'nový sneh 35+ cm',
      });
    }
    if (label.contains('povod')) {
      return pick({
        'yellow': 'mierne vzostupy hladín',
        'orange': 'výrazné vzostupy hladín',
        'red': 'extrémne vzostupy hladín',
      });
    }
    if (label.contains('hmla')) {
      return pick({
        'yellow': 'viditeľnosť 200 – 500 m',
        'orange': 'viditeľnosť 50 – 200 m',
        'red': 'viditeľnosť < 50 m',
      });
    }
    if (label.contains('klzk') || label.contains('ľad')) {
      return pick({
        'yellow': 'ľadová vrstva do 1 cm',
        'orange': 'ľadová vrstva 1 – 3 cm',
        'red': 'ľadová vrstva > 3 cm',
      });
    }
    return null;
  }

  String _formatExpectation(String base, String? range) {
    if (range == null || range.isEmpty) {
      return base.endsWith('.') ? base : '$base.';
    }
    return '$base: $range';
  }

  String _warningExpectationText(WarningData warning) {
    final desc = warning.description.trim();
    if (desc.isNotEmpty) return desc;

    final label = _warningPhenomenonLabel(warning.phenomenon).toLowerCase();
    final severityKey = _warningSeverityKey(warning.severity);
    final range = _warningExpectedRangeHint(label, severityKey);

    if (label.contains('horúc') || label.contains('teplot')) {
      return _formatExpectation('Očakávajú sa horúčavy', range);
    }
    if (label.contains('mraz') || label.contains('niz')) {
      return _formatExpectation('Očakávajú sa mrazy', range);
    }
    if (label.contains('vietor')) {
      return _formatExpectation('Očakáva sa silný vietor', range);
    }
    if (label.contains('búrk') || label.contains('burk')) {
      return _formatExpectation('Očakávajú sa búrky', range);
    }
    if (label.contains('dážď') || label.contains('dazd')) {
      return _formatExpectation('Očakáva sa výdatný dážď', range);
    }
    if (label.contains('sneh')) {
      return _formatExpectation('Očakáva sa sneženie', range);
    }
    if (label.contains('povod')) {
      return _formatExpectation('Hrozí povodeň', range);
    }
    if (label.contains('hmla')) {
      return _formatExpectation('Očakáva sa hmla', range);
    }
    if (label.contains('klzk') || label.contains('ľad')) {
      return _formatExpectation('Hrozí poľadovica', range);
    }

    if (label.isEmpty) return '';
    final capitalized = label[0].toUpperCase() + label.substring(1);
    return _formatExpectation('Očakáva sa $capitalized', range);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _warningSeverityAccent(warning.severity);
    final phenomenon = warning.phenomenon.trim();
    final validFrom = warning.validFrom.trim();
    final validTo = warning.validTo.trim();
    final validity = validFrom.isNotEmpty && validTo.isNotEmpty
        ? '$validFrom – $validTo'
        : (validFrom.isNotEmpty ? validFrom : validTo);
    final author = warning.author.trim();
    final expectation = _warningExpectationText(warning);
    final hasExpectation = expectation.isNotEmpty;
    final severityLabel = _severityLabel;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        color: const Color(0xFF3A4551),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon box
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Icon(
                        _warningPhenomenonIcon(phenomenon),
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Title
                    Text(
                      severityLabel + (warning.region.isNotEmpty ? ' - ${warning.region}' : ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Details box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E3844),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Typ javu
                          if (phenomenon.isNotEmpty)
                            Row(
                              children: [
                                const Icon(
                                  Icons.wb_sunny_outlined,
                                  size: 18,
                                  color: Color(0xFF64B5F6),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Typ javu: ',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  _warningPhenomenonLabel(phenomenon),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          // Platnosť
                          if (validity.isNotEmpty)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 18,
                                  color: Color(0xFF64B5F6),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Platnosť:',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      validity,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          const SizedBox(height: 6),
                          // Zdroj dát
                          if (author.isNotEmpty)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.account_balance_outlined,
                                  size: 18,
                                  color: Color(0xFF64B5F6),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Zdroj dát:',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      author,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          if (hasExpectation) ...[
                            const SizedBox(height: 12),
                            Divider(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.show_chart,
                                  size: 18,
                                  color: Color(0xFF64B5F6),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildDescriptionWithBlueValues(expectation),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F3A47),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: const Color(0xFF64B5F6).withValues(alpha: 0.95),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Meteoalarm (EUMETNET) • oficiálne výstrahy pre európske krajiny',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _WarningDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WarningDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.55)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 14,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WeatherChartPage extends StatelessWidget {
  final GeoCity city;
  final WeatherData data;

  const WeatherChartPage({
    super.key,
    required this.city,
    required this.data,
  });

  String get _modelLabel =>
      data.usedFallbackToBestMatch ? 'Best Match' : 'Open-Meteo';

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
                'Denné maximum, minimum, pravdepodobnosť zrážok a typ počasia z aktuálnej predpovede Open-Meteo.',
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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _chartGlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ChartSummaryStrip(data: data),
                        Expanded(
                          child: Center(
                            child: SizedBox(
                              height: _kDayColumnHeight,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: dayCount,
                                separatorBuilder: (_, __) => const SizedBox(width: 6),
                                itemBuilder: (context, index) => SizedBox(
                                  height: _kDayColumnHeight,
                                  child: _ChartDayColumn(
                                    data: data,
                                    dayIndex: index,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const _ChartTempLegend(),
                        if (dayCount > 7)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            child: Text(
                              'Potiahnite vľavo pre ďalšie dni →',
                              textAlign: TextAlign.center,
                              style: _chartLabelStyle(size: 12).copyWith(
                                color: _kChartTextSecondary,
                              ),
                            ),
                          ),
                      ],
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

  factory _ChartPeriodStats.from(WeatherData data) {
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
      final displayProb =
          _chartPrecipProbsForDay(data: data, dayIndex: i).rain;
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

  const _ChartSummaryStrip({required this.data});

  @override
  Widget build(BuildContext context) {
    final stats = _ChartPeriodStats.from(data);
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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

  const _ChartDayColumn({
    required this.data,
    required this.dayIndex,
  });

  static const _weekdayShort = <String>['Po', 'Ut', 'St', 'Št', 'Pi', 'So', 'Ne'];

  @override
  Widget build(BuildContext context) {
    final d = data.daily!;
    final h = data.hourly;
    final dateStr = d.time[dayIndex];
    final dt = DateTime.tryParse(dateStr);

    double? max = d.tempMax?[dayIndex];
    double? min = d.tempMin?[dayIndex];
    if ((max == null || min == null) && h != null) {
      final fb = _chartFallbackTemps(dateStr, h);
      max ??= fb['max'];
      min ??= fb['min'];
    }

    final dayIconCode = _dailyMainIconSkyTextCode(data, dayIndex);
    final precip = _chartPrecipProbsForDay(
      data: data,
      dayIndex: dayIndex,
    );

    final weekday = dt != null ? _weekdayShort[dt.weekday - 1] : '--';
    final dateLabel = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.'
        : '--';

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
            0,
            forceNight: true,
            size: 52,
            daily: d,
            hourTime: '${dateStr}T23:00',
          ),
          const SizedBox(height: 4),
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
          const SizedBox(height: 6),
          Text(
            '$weekday $dateLabel',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
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
