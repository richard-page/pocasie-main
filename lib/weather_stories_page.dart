part of 'main.dart';

/// Jedna „storka" — snímok počasia pre konkrétny časový bod.
class _StoryFrame {
  final DateTime time;
  final int weatherCode;
  final double? temperature;
  final double? apparentTemperature;
  final double? gustsKmh;
  final bool isDay;

  const _StoryFrame({
    required this.time,
    required this.weatherCode,
    required this.temperature,
    required this.apparentTemperature,
    required this.gustsKmh,
    required this.isDay,
  });
}

/// Full-screen Instagram-style storky — prvých 6 snímok z toho istého pásu ako zoznam „24 h“.
class WeatherStoriesPage extends StatefulWidget {
  final GeoCity city;
  final WeatherData data;
  final WindUnit windUnit;

  const WeatherStoriesPage({
    super.key,
    required this.city,
    required this.data,
    required this.windUnit,
  });

  @override
  State<WeatherStoriesPage> createState() => _WeatherStoriesPageState();
}

class _WeatherStoriesPageState extends State<WeatherStoriesPage>
    with SingleTickerProviderStateMixin {
  static const Duration _slideDuration = Duration(seconds: 5);

  late final List<_StoryFrame> _frames;
  late final AnimationController _progressCtrl;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _frames = _buildFrames();
    _progressCtrl = AnimationController(vsync: this, duration: _slideDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _next();
        }
      });
    if (_frames.isNotEmpty) {
      _progressCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  List<_StoryFrame> _buildFrames() {
    final hourly = widget.data.hourly;
    final current = widget.data.current;
    final daily = widget.data.daily;
    if (hourly == null || hourly.time.isEmpty) return const [];

    // Rovnaká lokálna stena a rovnaký začiatok ako `_buildHourly` (prvá hodina = nasledujúci celý hodinový slot).
    final DateTime locTime = widget.data.utcOffsetSeconds != null
        ? () {
            final loc = DateTime.now()
                .toUtc()
                .add(Duration(seconds: widget.data.utcOffsetSeconds!));
            return DateTime(
                loc.year, loc.month, loc.day, loc.hour, loc.minute, loc.second);
          }()
        : DateTime.now();

    final DateTime slotTime = DateTime(
      locTime.year,
      locTime.month,
      locTime.day,
      locTime.hour,
    ).add(const Duration(hours: 1));

    int start = 0;
    for (var i = 0; i < hourly.time.length; i++) {
      final forecastTime = DateTime.tryParse(hourly.time[i]);
      if (forecastTime != null && !forecastTime.isBefore(slotTime)) {
        start = i;
        break;
      }
    }

    final end = math.min(start + 24, hourly.time.length);
    if (start >= end) return const [];

    final smoothed =
        _smoothHourlyData(hourly, start, end, current, daily, locTime);
    final frameCount = math.min(6, end - start);

    final rawIcons = List<int>.generate(
      frameCount,
      (i) => _hourlySlotRawDisplayIconCode(hourly, start + i, smoothed, i),
    );
    final displayIcons = _smoothFairWeatherHourlyIconCodes(rawIcons);

    final List<_StoryFrame> out = [];
    for (var i = 0; i < frameCount; i++) {
      final idx = start + i;
      final DateTime? t = DateTime.tryParse(hourly.time[idx]);
      if (t == null) continue;
      final wallHour =
          DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
      out.add(_StoryFrame(
        time: wallHour,
        weatherCode: displayIcons[i],
        temperature: smoothed.temperatures[i],
        apparentTemperature: smoothed.apparentTemperature[i],
        gustsKmh: hourly.windGusts != null && idx < hourly.windGusts!.length
            ? hourly.windGusts![idx]
            : null,
        isDay: _resolveIsDay(wallHour, null, daily),
      ));
    }
    return out;
  }

  bool _resolveIsDay(
      DateTime t, CurrentWeather? current, DailyForecast? daily) {
    if (current?.isDay != null) return current!.isDay == 1;
    if (daily?.sunrise == null || daily?.sunset == null) {
      return t.hour >= 6 && t.hour < 20;
    }
    final stamp =
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    for (var i = 0; i < daily!.time.length; i++) {
      if (daily.time[i] != stamp) continue;
      final sr = (daily.sunrise != null && i < daily.sunrise!.length)
          ? DateTime.tryParse(daily.sunrise![i])
          : null;
      final ss = (daily.sunset != null && i < daily.sunset!.length)
          ? DateTime.tryParse(daily.sunset![i])
          : null;
      if (sr != null && ss != null) {
        return !t.isBefore(sr) && t.isBefore(ss);
      }
    }
    return t.hour >= 6 && t.hour < 20;
  }

  void _next() {
    if (_index < _frames.length - 1) {
      setState(() => _index++);
      _progressCtrl.forward(from: 0);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
    }
    _progressCtrl.forward(from: 0);
  }

  void _pause() => _progressCtrl.stop();
  void _resume() => _progressCtrl.forward();

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              const Positioned.fill(
                child: WeatherHeroAmbient(
                  weatherCode: 0,
                  isDay: true,
                  blendColor: kAmbientBlendColor,
                ),
              ),
              const Center(
                child: Text(
                  'Nie sú dostupné údaje pre storky.',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final frame = _frames[_index];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 250) {
            Navigator.of(context).maybePop();
          }
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        child: Stack(
          children: [
            Positioned.fill(
              child: WeatherHeroAmbient(
                weatherCode: frame.weatherCode,
                isDay: frame.isDay,
                blendColor: kAmbientBlendColor,
              ),
            ),
            // Tap zóny pre prev/next — pod ovládacími prvkami, aby ich
            // close/share tlačidlá v hlavičke prebíjali.
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _prev,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProgressBars(),
                    const SizedBox(height: 14),
                    _buildHeader(),
                    const SizedBox(height: 8),
                    _buildBrandBadge(),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: true,
                        child: _buildBody(frame),
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

  Widget _buildProgressBars() {
    return Row(
      children: List.generate(_frames.length, (i) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: i < _index
                    ? Container(color: Colors.white)
                    : i == _index
                        ? AnimatedBuilder(
                            animation: _progressCtrl,
                            builder: (_, __) => LinearProgressIndicator(
                              value: _progressCtrl.value,
                              backgroundColor: Colors.white24,
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Container(color: Colors.white24),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.city.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                '${_frames.length} snímok · po hodine',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _buildIconCircle(Icons.close,
            onTap: () => Navigator.of(context).maybePop()),
      ],
    );
  }

  Widget _buildIconCircle(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildBrandBadge() {
    const double dim = 40;
    return Center(
      child: Semantics(
        label: 'Meteo počasie',
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              circleAppIconAsset(
                dim,
                borderColor: Colors.white.withValues(alpha: 0.24),
              ),
              const SizedBox(width: 10),
              const Text(
                'Meteo počasie',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.15,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(_StoryFrame frame) {
    final String timeStr = _formatTime(frame.time);
    final String dateStr = _formatDate(frame.time);
    final String desc =
        weatherDescriptionSk(frame.weatherCode);
    final String? feelTitle = frame.apparentTemperature != null ? 'Pocitová teplota' : null;
    final String? feelValue = frame.apparentTemperature != null
        ? '${frame.apparentTemperature!.round()}°'
        : null;
    final String? gustTitle = frame.gustsKmh != null ? 'Nárazy vetra' : null;
    final String? gustValue =
        frame.gustsKmh != null ? widget.windUnit.format(frame.gustsKmh!) : null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          timeStr,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 72,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.0,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.35),
                offset: const Offset(0, 2),
                blurRadius: 18,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          dateStr,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: getWeatherIcon(
            frame.weatherCode,
            size: 148,
            forceDay: frame.isDay,
            forceNight: !frame.isDay,
          ),
        ),
        const SizedBox(height: 22),
        _buildStoryTemperature(frame),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _capitalizeFirst(desc),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.96),
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.25,
            ),
          ),
        ],
        const SizedBox(height: 26),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            if (feelTitle != null && feelValue != null)
              _buildStatChip(icon: Icons.thermostat_rounded, title: feelTitle, value: feelValue),
            if (gustTitle != null && gustValue != null)
              _buildStatChip(icon: Icons.air_rounded, title: gustTitle, value: gustValue),
          ],
        ),
      ],
    );
  }

  Widget _buildStoryTemperature(_StoryFrame frame) {
    final tempShadows = [
      Shadow(
        color: Colors.black.withValues(alpha: 0.42),
        offset: const Offset(0, 4),
        blurRadius: 22,
      ),
    ];
    final base = storyTemperatureMonoStyle().merge(
      TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
        height: 1.02,
        letterSpacing: -2,
        shadows: tempShadows,
      ),
    );

    if (frame.temperature == null) {
      return Center(
        child: Text(
          '--°',
          style: base.merge(const TextStyle(fontSize: 84)),
        ),
      );
    }

    final n = '${frame.temperature!.round()}';
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            n,
            style: base.merge(const TextStyle(fontSize: 84)),
          ),
          Text(
            '°',
            style: base.merge(const TextStyle(fontSize: 84)),
          ),
        ],
      ),
    );
  }
  Widget _buildStatChip({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 156),
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.35,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatDate(DateTime t) {
    const skDays = <String>[
      'Pondelok',
      'Utorok',
      'Streda',
      'Štvrtok',
      'Piatok',
      'Sobota',
      'Nedeľa',
    ];
    const skMonths = <String>[
      'januára',
      'februára',
      'marca',
      'apríla',
      'mája',
      'júna',
      'júla',
      'augusta',
      'septembra',
      'októbra',
      'novembra',
      'decembra',
    ];
    return '${skDays[t.weekday - 1]} ${t.day}. ${skMonths[t.month - 1]}';
  }

  String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

}
