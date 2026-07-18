part of 'main.dart';

const String kRadarServerBase = 'http://cz1.helkor.eu:41152';

const int kRadarImageCols = 4000;
const int kRadarImageRows = 2000;

const double kRadarMinDbzForUi = 8.0;
const double kRadarMinDbzSignificantEcho = 10.0;
const double kRadarMinDbzCoherentEcho = 10.0;
const double kRadarMinDbzTrackerIncoming = 10.0;
const double kRadarMinDbzDistantApproach = 8.0;
const int kRadarNoiseMinPersistFrames = 1;
const int kRadarMinCoherentAreaPx = 1;
const double kRadarMinDbzTrackerFront = 12.0;
const int kRadarMinCoherentCorePx = 1;
/// „Už prší u mňa“ — slabší prah, bez filtrácie šumu.
const double kRadarMinDbzPrecipNow = 8.0;
const double kRadarMinDbzEcho = 8.0;
const int kRadarCoreSampleRadiusPx = 6;
const int kRadarPeakCompareRadiusPx = 28;
const int kRadarSampleRadiusPx = 56;
const int kRadarNowcastOuterRadiusPx = 96;
const int kRadarDirectionalSampleRadiusPx = 20;

/// CMAX legenda — `/radar/data.cmax.png` (SHMÚ kompozit), 8–56 dBZ.
class _RadarCmaxStop {
  const _RadarCmaxStop(this.dbz, this.r, this.g, this.b);
  final double dbz;
  final int r;
  final int g;
  final int b;
}

const List<_RadarCmaxStop> _kRadarCmaxLegendStops = [
  _RadarCmaxStop(8, 200, 216, 240),
  _RadarCmaxStop(11, 176, 200, 216),
  _RadarCmaxStop(14, 136, 168, 200),
  _RadarCmaxStop(18, 64, 116, 184),
  _RadarCmaxStop(21, 4, 72, 168),
  _RadarCmaxStop(24, 0, 132, 116),
  _RadarCmaxStop(27, 0, 196, 48),
  _RadarCmaxStop(30, 72, 240, 0),
  _RadarCmaxStop(34, 244, 224, 0),
  _RadarCmaxStop(37, 252, 168, 0),
  _RadarCmaxStop(40, 252, 68, 0),
  _RadarCmaxStop(43, 220, 8, 0),
  _RadarCmaxStop(46, 148, 24, 36),
  _RadarCmaxStop(50, 204, 72, 200),
  _RadarCmaxStop(53, 252, 128, 252),
  _RadarCmaxStop(56, 252, 176, 252),
];

/// Počet snímok z [radar_history_cmax.json] — server ~5 min interval.
const int kRadarHistoryFramesMin = 3;
const int kRadarHistoryFramesMax = 24;
/// Počet snímok na prvý fetch — menej RAM / menej paralelných PNG dekódov.
const int kRadarHistoryFramesToSample = 5;
/// Trend / transient — len posledných N snímok, aby stará dažďová hodina neskresľovala stav.
const int kRadarNowcastTrendFrames = 10;
const Duration _kRadarNowcastCacheTtl = Duration(seconds: 90);
const Duration kRadarTrackerPhaseHoldInterval = Duration(minutes: 5);
const Duration kRadarTrackerIncomingToActiveHold = Duration(minutes: 5);
const int kRadarTrackerArrivalSmoothMinutes = 15;
/// Koniec aktívneho dažďa — po zamknutí sa už nemení (len odpočet času).
const Duration kRadarTrackerEndHoldInterval = Duration(minutes: 30);
const int kRadarTrackerEndSmoothMinutes = 30;
const int kRadarTrackerEndSoonerAdoptMinutes = 999;
const int kRadarTrackerEndMaxStepMinutes = 0;
const int kRadarTrackerEndEmergencyAdoptMinutes = 999;

/// Obmedzená paralelizácia — inak desiatky PNG dekódov naraz = OOM na emulátore / slabších telefónoch.
Future<List<T?>> _mapRadarSamplesWithConcurrency<T>(
  int length,
  Future<T?> Function(int index) mapper, {
  int concurrency = 1,
}) async {
  if (length <= 0) return const [];
  final results = List<T?>.filled(length, null);
  var nextIndex = 0;
  Future<void> worker() async {
    while (true) {
      final i = nextIndex;
      nextIndex++;
      if (i >= length) return;
      results[i] = await mapper(i);
      await Future<void>.delayed(Duration.zero);
    }
  }
  final workers = math.min(concurrency, length);
  await Future.wait(List.generate(workers, (_) => worker()));
  return results;
}

class RadarFrameSample {
  const RadarFrameSample({
    required this.unix,
    required this.precip,
    this.precipAtPoint = false,
    this.dbz,
    this.peakDbz,
    this.innerPeakDbz,
    this.coherentPx14 = 0,
    this.coherentCorePx = 0,
    this.northDbz,
    this.southDbz,
    this.eastDbz,
    this.westDbz,
  });

  final int unix;
  /// Echo v širšom okolí (bunka blízko).
  final bool precip;
  /// Prší priamo nad súradnicami (jadro bodu).
  final bool precipAtPoint;
  /// dBZ priamo nad pinom (stredový pixel).
  final double? dbz;
  /// Max dBZ v okolí ~14 px — intenzita blížiacej sa bunky.
  final double? peakDbz;
  /// Max dBZ v okruhu ~64 px — čo mapa ukáže pri pine (nie 140 px v diali).
  final double? innerPeakDbz;
  /// Počet pixelov ≥18 dBZ v okolí 14 px.
  final int coherentPx14;
  /// Počet pixelov ≥16 dBZ v jadre ~3 px.
  final int coherentCorePx;
  final double? northDbz;
  final double? southDbz;
  final double? eastDbz;
  final double? westDbz;

  double? dbzInDirection(String dir) => switch (dir) {
        'n' => northDbz,
        's' => southDbz,
        'e' => eastDbz,
        'w' => westDbz,
        _ => null,
      };
}
 
/// Fáza karty sledovača — ovplyvňuje layout (kompaktný vs. rozšírený).
enum RadarPrecipTrackerPhase { idle, loading, watching, active, incoming }

const String kRadarTrackerCardTitle = 'Sledovač radaru';
/// Horizont textu sledovača + pás 24 h — radar nowcast má zmysel cca do 4 h
/// (RainViewer snímky ~2 h; 2–4 h = trajektória/ETA, ďalej už len model).
const int kRadarTrackerHorizonHours = 4;
/// Alias — rovnaký strop pre zrážkové ikony v pásme 24 h.
const int kRadarNowcastStripHorizonHours = kRadarTrackerHorizonHours;
const String kRadarTrackerDryHorizonDetail =
    'V najbližších $kRadarTrackerHorizonHours hodinách sa neočakávajú žiadne zrážky.';
/// Spätná kompatibilita stabilizátora (starý text v cache).
const String kRadarTrackerDryNextHourDetail = kRadarTrackerDryHorizonDetail;

String _radarTrackerCardDetail(String headline, String body) {
  final h = headline.trim();
  final b = body.trim();
  if (h.isEmpty) return b;
  if (b.isEmpty) return h;
  return '$h. $b';
}

String _trackerDurationLabel(int minutes) {
  if (minutes < 55) return '$minutes minút';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return h == 1 ? '1 hodinu' : '$h hodiny';
  if (h == 0) return '$m minút';
  if (h == 1) return '1 hodinu a $m minút';
  return '$h hodiny a $m minút';
}

String _trackerPrecipSubject({required bool snow}) =>
    snow ? 'Sneženie' : 'Dážď';

String _trackerPrecipSubjectLower({required bool snow}) =>
    snow ? 'sneženie' : 'dážď';

String _trackerLastsDetail({
  required bool snow,
  required String endLabel,
  int? approxMinutes,
  bool approxOneHour = false,
}) {
  final subj = _trackerPrecipSubject(snow: snow);
  if (approxMinutes != null && approxMinutes < 55) {
    return '$subj potrvá približne ${_trackerDurationLabel(approxMinutes)}, do $endLabel.';
  }
  if (approxOneHour ||
      (approxMinutes != null && approxMinutes <= 75)) {
    return '$subj potrvá približne hodinu, do $endLabel.';
  }
  return '$subj potrvá do $endLabel.';
}

String _trackerIncomingTimingDetail({
  required bool snow,
  required String startLabel,
  required String endLabel,
  required int minsToStart,
  required int durationMin,
}) {
  final subj = _trackerPrecipSubjectLower(snow: snow);
  final effectiveMins = math.max(minsToStart, 0);
  final startPhrase = effectiveMins <= 20
      ? 'Začiatok o $startLabel'
      : 'Začiatok okolo $startLabel';

  if (effectiveMins <= 20) {
    return '$startPhrase, $subj potrvá do $endLabel.';
  }
  if (durationMin < 55) {
    return '$startPhrase, $subj potrvá približne ${_trackerDurationLabel(durationMin)}.';
  }
  if (durationMin <= 75) {
    return '$startPhrase, $subj potrvá približne hodinu.';
  }
  return '$startPhrase, $subj ustúpi okolo $endLabel.';
}

String _trackerActiveHeadline(double dbz, {required bool snow}) {
  if (snow) return 'Aktuálne sneží';
  return 'Aktuálne prší';
}

String _trackerIncomingHeadline(double dbz, {required bool snow}) {
  if (snow) return 'Blíži sa sneh';
  return 'Blížia sa zrážky';
}

String _incomingTrackerStatusTitle({
  required bool atPinNow,
  required bool snow,
  required double intensityDbz,
}) {
  if (atPinNow) return _trackerActiveHeadline(intensityDbz, snow: snow);
  return _trackerIncomingHeadline(intensityDbz, snow: snow);
}

DateTime _roundLocalTimeToMinutes(DateTime dt, {int step = 5}) {
  final total = dt.hour * 60 + dt.minute;
  final rounded = ((total + step ~/ 2) ~/ step) * step;
  final dayOffset = rounded ~/ (24 * 60);
  final mins = rounded % (24 * 60);
  return DateTime(
    dt.year,
    dt.month,
    dt.day,
  ).add(Duration(days: dayOffset, hours: mins ~/ 60, minutes: mins % 60));
}

String _trackerClockLabel(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Zostávajúce minúty — plynulý odpočet od zamknutého času konca.
int _trackerDisplayRemainingMinutes(DateTime endAt, DateTime locNow) {
  final roundedNow = _roundLocalTimeToMinutes(locNow);
  return endAt.difference(roundedNow).inMinutes.clamp(0, 180);
}

DateTime _trackerDisplayEndTime(DateTime endAt) =>
    _roundLocalTimeToMinutes(endAt, step: 5);

RadarPrecipTrackerInfo _activeTrackerWithEnd(
  RadarPrecipTrackerInfo base,
  DateTime endAt,
  DateTime locNow, {
  bool locked = false,
}) {
  final snow = kSnowWeatherCodes.contains(base.iconCode);
  final displayEnd = locked ? endAt : _trackerDisplayEndTime(endAt);
  final rawRemaining = _trackerDisplayRemainingMinutes(displayEnd, locNow);
  final remainingMin = rawRemaining <= 0
      ? 0
      : (rawRemaining < 55 ? rawRemaining.clamp(1, 180) : rawRemaining.clamp(5, 180));
  final endLabel = _trackerClockLabel(displayEnd);
  final body = remainingMin <= 0
      ? '${_trackerPrecipSubject(snow: snow)} by mal ustúpiť do $endLabel.'
      : _trackerLastsDetail(
          snow: snow,
          endLabel: endLabel,
          approxMinutes: remainingMin < 55 ? remainingMin : null,
          approxOneHour: remainingMin >= 52 && remainingMin <= 75,
        );
  final headline = _trackerActiveHeadline(0, snow: snow);
  return RadarPrecipTrackerInfo(
    phase: base.phase,
    title: base.title,
    detail: _radarTrackerCardDetail(headline, body),
    iconCode: base.iconCode,
    startLocal: base.startLocal,
    endLocal: displayEnd,
  );
}

DateTime? _trackerHardLockedEnd(String cityKey) =>
    _trackerHardLockedEndByCity[cityKey];

void _lockTrackerEnd(String cityKey, DateTime endAt) {
  final display = _trackerDisplayEndTime(endAt);
  final existing = _trackerHardLockedEndByCity[cityKey];
  if (existing == null) {
    _trackerHardLockedEndByCity[cityKey] = display;
    return;
  }
  if (display.isBefore(existing)) {
    _trackerHardLockedEndByCity[cityKey] = display;
  }
}

void _clearTrackerHardEnd(String cityKey) {
  _trackerHardLockedEndByCity.remove(cityKey);
}

RadarPrecipTrackerInfo _applyHardLockedEnd(
  RadarPrecipTrackerInfo info,
  String cityKey,
  DateTime locNow,
) {
  if (info.phase != RadarPrecipTrackerPhase.active) {
    if (info.phase == RadarPrecipTrackerPhase.idle ||
        info.detail.contains(kRadarTrackerDryHorizonDetail)) {
      _clearTrackerHardEnd(cityKey);
    }
    return info;
  }
  final hard = _trackerHardLockedEnd(cityKey);
  if (hard != null) {
    return _activeTrackerWithEnd(info, hard, locNow, locked: true);
  }
  if (info.endLocal != null) {
    _lockTrackerEnd(cityKey, info.endLocal!);
    final locked = _trackerHardLockedEnd(cityKey)!;
    return _activeTrackerWithEnd(info, locked, locNow, locked: true);
  }
  return info;
}

/// Drží [endLocal] — vždy použije hard-lock ak existuje.
RadarPrecipTrackerInfo? _stabilizeActiveTrackerEnd(
  RadarPrecipTrackerInfo prev,
  RadarPrecipTrackerInfo next,
  DateTime locNow,
  DateTime now, {
  required String cityKey,
  DateTime? stablePhaseAt,
}) {
  if (prev.phase != RadarPrecipTrackerPhase.active ||
      next.phase != RadarPrecipTrackerPhase.active) {
    return null;
  }
  final hard = _trackerHardLockedEnd(cityKey);
  if (hard != null) {
    return _activeTrackerWithEnd(next, hard, locNow, locked: true);
  }
  final prevEnd = prev.endLocal;
  if (prevEnd != null) {
    return _activeTrackerWithEnd(next, prevEnd, locNow);
  }
  return next;
}

/// Krátky text pre kartu „Sledovač zrážok“.
class RadarPrecipTrackerInfo {
  const RadarPrecipTrackerInfo({
    required this.phase,
    required this.title,
    required this.detail,
    required this.iconCode,
    this.startLocal,
    this.endLocal,
  });

  final RadarPrecipTrackerPhase phase;
  final String title;
  final String detail;
  final int iconCode;
  final DateTime? startLocal;
  final DateTime? endLocal;

  bool get isExpanded =>
      phase == RadarPrecipTrackerPhase.active ||
      phase == RadarPrecipTrackerPhase.incoming;
}

final Map<String, RadarPrecipTrackerInfo> _trackerStableByCity = {};
final Map<String, DateTime> _trackerStablePhaseAtByCity = {};
final Map<String, DateTime> _trackerStableEndAtByCity = {};
final Map<String, DateTime> _trackerHardLockedEndByCity = {};

String _trackerCityKey(double lat, double lon) =>
    '${lat.toStringAsFixed(4)}:${lon.toStringAsFixed(4)}';

String _trackerStabilizerKey(double? cityLat, double? cityLon) =>
    (cityLat != null && cityLon != null)
        ? _trackerCityKey(cityLat, cityLon)
        : '__unknown__';

void _saveTrackerStable(
  String cityKey,
  RadarPrecipTrackerInfo info, {
  bool touchPhase = true,
  bool touchEnd = false,
}) {
  final prevInfo = _trackerStableByCity[cityKey];
  _trackerStableByCity[cityKey] = info;
  if (touchPhase) {
    _trackerStablePhaseAtByCity[cityKey] = DateTime.now();
  }
  if (touchEnd || prevInfo?.endLocal != info.endLocal) {
    _trackerStableEndAtByCity[cityKey] = DateTime.now();
  }
}

/// Stabilizuje kartu sledovača — menej skokov v ETA a fáze pri každom snímke radaru.
RadarPrecipTrackerInfo stabilizeRadarTrackerInfo(
  RadarPrecipTrackerInfo next,
  DateTime locNow, {
  double? cityLat,
  double? cityLon,
}) {
  final cityKey = _trackerStabilizerKey(cityLat, cityLon);
  final prev = _trackerStableByCity[cityKey];
  final stablePhaseAt = _trackerStablePhaseAtByCity[cityKey];
  final now = DateTime.now();

  final hardEnd = _trackerHardLockedEnd(cityKey);
  // Hard lock len pri stále mokrom/incoming — pri suchom pine nesmie držať „Aktuálne prší“.
  if (hardEnd != null &&
      prev != null &&
      prev.phase == RadarPrecipTrackerPhase.active &&
      next.phase == RadarPrecipTrackerPhase.incoming) {
    final locked = _activeTrackerWithEnd(prev, hardEnd, locNow, locked: true);
    _saveTrackerStable(cityKey, locked, touchPhase: false);
    return locked;
  }

  if (prev == null) {
    final locked = _applyHardLockedEnd(next, cityKey, locNow);
    _saveTrackerStable(cityKey, locked, touchEnd: locked.phase == RadarPrecipTrackerPhase.active);
    return locked;
  }

  final upgraded = next.phase == RadarPrecipTrackerPhase.active ||
      next.phase == RadarPrecipTrackerPhase.incoming;
  final prevWet = prev.phase == RadarPrecipTrackerPhase.active ||
      prev.phase == RadarPrecipTrackerPhase.incoming;

  if (upgraded && !prevWet) {
    final locked = _applyHardLockedEnd(next, cityKey, locNow);
    _saveTrackerStable(cityKey, locked, touchEnd: locked.phase == RadarPrecipTrackerPhase.active);
    return locked;
  }

  if (prev.phase == RadarPrecipTrackerPhase.active &&
      next.phase == RadarPrecipTrackerPhase.watching &&
      next.detail.contains(kRadarTrackerDryHorizonDetail) ||
      next.detail.contains('Nasledujúcu hodinu sa neočakávajú')) {
    _saveTrackerStable(cityKey, next);
    return next;
  }

  if (prev.phase == RadarPrecipTrackerPhase.active &&
      next.phase == RadarPrecipTrackerPhase.incoming) {
    if (hardEnd != null) {
      final locked = _activeTrackerWithEnd(prev, hardEnd, locNow, locked: true);
      _saveTrackerStable(cityKey, locked, touchPhase: false);
      return locked;
    }
    _saveTrackerStable(cityKey, next);
    return next;
  }

  if (prev.phase == RadarPrecipTrackerPhase.active &&
      next.phase == RadarPrecipTrackerPhase.watching) {
    // Suchý výhľad na pine → uvoľni lock (mapa bez echa pri lokalite).
    final dryNow = next.detail.contains(kRadarTrackerDryHorizonDetail) ||
        next.detail.contains('Nasledujúcu hodinu sa neočakávajú');
    if (hardEnd != null && !dryNow) {
      final locked = _activeTrackerWithEnd(prev, hardEnd, locNow, locked: true);
      _saveTrackerStable(cityKey, locked, touchPhase: false);
      return locked;
    }
    _saveTrackerStable(cityKey, next);
    return next;
  }

  if (prevWet &&
      prev.phase == RadarPrecipTrackerPhase.active &&
      next.phase == RadarPrecipTrackerPhase.idle &&
      stablePhaseAt != null &&
      now.difference(stablePhaseAt) < kRadarTrackerPhaseHoldInterval) {
    return prev;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase != RadarPrecipTrackerPhase.incoming &&
      next.phase != RadarPrecipTrackerPhase.active &&
      stablePhaseAt != null &&
      now.difference(stablePhaseAt) < kRadarTrackerPhaseHoldInterval) {
    return prev;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase == RadarPrecipTrackerPhase.active) {
    final etaOk = prev.startLocal == null ||
        !locNow.isBefore(
          prev.startLocal!.subtract(const Duration(minutes: 2)),
        );
    final heldIncoming = stablePhaseAt == null ||
        now.difference(stablePhaseAt) >= kRadarTrackerIncomingToActiveHold;
    if (!etaOk || !heldIncoming) {
      return prev;
    }
    final locked = prev.endLocal != null
        ? _applyHardLockedEnd(
            _activeTrackerWithEnd(next, prev.endLocal!, locNow),
            cityKey,
            locNow,
          )
        : _applyHardLockedEnd(next, cityKey, locNow);
    _saveTrackerStable(cityKey, locked, touchEnd: true);
    return locked;
  }

  if (next.phase == RadarPrecipTrackerPhase.active &&
      prev.phase != RadarPrecipTrackerPhase.incoming &&
      prev.phase != RadarPrecipTrackerPhase.active) {
    final locked = _applyHardLockedEnd(next, cityKey, locNow);
    _saveTrackerStable(cityKey, locked, touchEnd: true);
    return locked;
  }

  final stabilizedEnd = _stabilizeActiveTrackerEnd(
    prev,
    next,
    locNow,
    now,
    cityKey: cityKey,
    stablePhaseAt: stablePhaseAt,
  );
  if (stabilizedEnd != null) {
    final locked = _applyHardLockedEnd(stabilizedEnd, cityKey, locNow);
    final adoptedNewEnd = locked.endLocal != prev.endLocal;
    _saveTrackerStable(
      cityKey,
      locked,
      touchPhase: adoptedNewEnd,
      touchEnd: adoptedNewEnd,
    );
    return locked;
  }

  if (next.phase == RadarPrecipTrackerPhase.active &&
      prev.phase == RadarPrecipTrackerPhase.active) {
    if (hardEnd != null) {
      final locked = _activeTrackerWithEnd(next, hardEnd, locNow, locked: true);
      _saveTrackerStable(cityKey, locked, touchPhase: false);
      return locked;
    }
    if (prev.endLocal != null) {
      final held = _applyHardLockedEnd(
        _activeTrackerWithEnd(next, prev.endLocal!, locNow),
        cityKey,
        locNow,
      );
      _saveTrackerStable(cityKey, held, touchPhase: false);
      return held;
    }
    _saveTrackerStable(cityKey, next, touchPhase: false);
    return next;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase == RadarPrecipTrackerPhase.incoming &&
      prev.startLocal != null &&
      !prev.startLocal!.isAfter(locNow)) {
    _saveTrackerStable(cityKey, next);
    return next;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase == RadarPrecipTrackerPhase.incoming &&
      prev.startLocal != null &&
      next.startLocal != null &&
      !next.startLocal!.isAfter(prev.startLocal!)) {
    _saveTrackerStable(cityKey, next);
    return next;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase == RadarPrecipTrackerPhase.incoming &&
      prev.startLocal != null &&
      next.startLocal != null) {
    final delta =
        next.startLocal!.difference(prev.startLocal!).inMinutes.abs();
    if (next.startLocal!.isBefore(prev.startLocal!)) {
      _saveTrackerStable(cityKey, next);
      return next;
    }
    if (delta <= kRadarTrackerArrivalSmoothMinutes) {
      final keepStart = prev.startLocal!;
      if (!keepStart.isAfter(locNow)) {
        _saveTrackerStable(cityKey, next);
        return next;
      }
      final startLabel =
          '${keepStart.hour.toString().padLeft(2, '0')}:${keepStart.minute.toString().padLeft(2, '0')}';
      final detail = next.detail.contains('Očakávaný')
          ? next.detail.replaceFirst(
              RegExp(r'Očakávaný začiatok o \d{2}:\d{2}'),
              'Očakávaný začiatok o $startLabel',
            )
          : next.detail;
      final stabilized = RadarPrecipTrackerInfo(
        phase: next.phase,
        title: next.title,
        detail: detail,
        iconCode: next.iconCode,
        startLocal: keepStart,
        endLocal: next.endLocal,
      );
      _saveTrackerStable(cityKey, stabilized, touchPhase: false);
      return stabilized;
    }
  }

  _saveTrackerStable(cityKey, next, touchPhase: prev.phase != next.phase);
  return _applyHardLockedEnd(next, cityKey, locNow);
}

void resetRadarTrackerStabilizer({bool clearHardEndLock = true}) {
  _trackerStableByCity.clear();
  _trackerStablePhaseAtByCity.clear();
  _trackerStableEndAtByCity.clear();
  _pinEndStableByCity.clear();
  if (clearHardEndLock) {
    _trackerHardLockedEndByCity.clear();
  }
}

/// Stabilný odhad konca dažďa na pine — nemení sa každú snímku.
class _PinEndStable {
  const _PinEndStable({
    required this.absoluteEndLocal,
    required this.lockedAt,
  });
  final DateTime absoluteEndLocal;
  final DateTime lockedAt;
}

final Map<String, _PinEndStable> _pinEndStableByCity = {};

/// Stabilizuj endMinutes: podľa veľkosti bunky, ale bez skokov každú minútu.
/// Predĺženie hneď; skrátenie až po ~2,5 min a len pri väčšom rozdiele.
int stabilizePinEndMinutes({
  required String cityKey,
  required bool wetAtPin,
  required int rawEndMins,
  required DateTime locNow,
}) {
  if (!wetAtPin || rawEndMins <= 0) {
    _pinEndStableByCity.remove(cityKey);
    return rawEndMins;
  }

  final now = DateTime.now();
  final rawAbsolute = locNow.add(Duration(minutes: rawEndMins));
  final prev = _pinEndStableByCity[cityKey];

  if (prev == null) {
    _pinEndStableByCity[cityKey] = _PinEndStable(
      absoluteEndLocal: rawAbsolute,
      lockedAt: now,
    );
    return rawEndMins;
  }

  final heldMins = prev.absoluteEndLocal.difference(locNow).inMinutes;
  if (heldMins <= 2) {
    // Predošlý odhad už vypršal / vyprší — vezmi nový.
    _pinEndStableByCity[cityKey] = _PinEndStable(
      absoluteEndLocal: rawAbsolute,
      lockedAt: now,
    );
    return rawEndMins;
  }

  final elapsed = now.difference(prev.lockedAt);
  final delta = rawEndMins - heldMins;

  // Predĺženie (väčšia / dlhšia bunka) — hneď, aspoň +8 min.
  if (delta >= 8) {
    _pinEndStableByCity[cityKey] = _PinEndStable(
      absoluteEndLocal: rawAbsolute,
      lockedAt: now,
    );
    return rawEndMins;
  }

  // Skrátenie — až po 2,5 min a len ak kleslo o ≥ 15 min (reálny ústup).
  if (delta <= -15 && elapsed >= const Duration(seconds: 150)) {
    _pinEndStableByCity[cityKey] = _PinEndStable(
      absoluteEndLocal: rawAbsolute,
      lockedAt: now,
    );
    return rawEndMins;
  }

  // Drž stabilný absolútny koniec (nech tiká čas, nie skáče ETA).
  return heldMins.clamp(5, 180);
}

/// Pločný matematický nowcast — vypočítaný **raz** pri každom radar fetchi
/// (centroidová trajektória, nowcast ETA/koniec, šanca doraziť). Žiadne gettery.
class RadarPinForecastSnapshot {
  const RadarPinForecastSnapshot({
    required this.wetAtPinNow,
    required this.approaching,
    required this.uiDbz,
    required this.rainViewer,
    required this.wetHourStartsMs,
    required this.nearTermEndExclusiveMs,
    required this.clearEcmwfNearTerm,
    this.etaMinutes,
    this.endMinutes,
    this.approachChancePercent = 0,
    this.distanceKmEstimate,
    this.motionSpeedKmH,
    this.towardPin = false,
    this.peakDbz = 0,
  });

  static const empty = RadarPinForecastSnapshot(
    wetAtPinNow: false,
    approaching: false,
    uiDbz: 0,
    rainViewer: false,
    wetHourStartsMs: <int>[],
    nearTermEndExclusiveMs: 0,
    clearEcmwfNearTerm: false,
  );

  final bool wetAtPinNow;
  final bool approaching;
  final double uiDbz;
  final bool rainViewer;
  /// Lokálne začiatky hodín (ms since epoch, wall-clock floor).
  final List<int> wetHourStartsMs;
  final int nearTermEndExclusiveMs;
  final bool clearEcmwfNearTerm;

  /// Minúty do príchodu zrážok na pin (0 = prší teraz). Null = neznáme.
  final int? etaMinutes;
  /// Minúty do konca zrážok na pine. Null = neznáme / neprší.
  final int? endMinutes;
  /// Šanca, že zrážky dorazia (0–100) — z trajektórie + nowcast + intenzity.
  final int approachChancePercent;
  /// Odhad vzdialenosti jadra bunky od pinu (km).
  final double? distanceKmEstimate;
  /// Rýchlosť priblíženia jadra k pinu (km/h); záporné = odchádza.
  final double? motionSpeedKmH;
  /// Centroid sa pohybuje smerom k pinu.
  final bool towardPin;
  /// Vrchol dBZ v okolí pinu (červené pásmo) — na mm/% v 24 h páse.
  final double peakDbz;

  /// Intenzita pre UI — max(pin, vrchol v okolí).
  double get intensityDbz => math.max(uiDbz, peakDbz);

  bool authorizesLocalHour(DateTime slotHour) {
    final key = DateTime(
      slotHour.year,
      slotHour.month,
      slotHour.day,
      slotHour.hour,
    ).millisecondsSinceEpoch;
    return wetHourStartsMs.contains(key);
  }

  bool isNearTermHour(DateTime slotHour, DateTime locNow) {
    final nowHour = DateTime(locNow.year, locNow.month, locNow.day, locNow.hour);
    final slot = DateTime(slotHour.year, slotHour.month, slotHour.day, slotHour.hour);
    if (slot.isBefore(nowHour)) return false;
    if (nearTermEndExclusiveMs <= 0) return false;
    return slot.millisecondsSinceEpoch < nearTermEndExclusiveMs;
  }
}

/// ~km na jednotku kardinalného centroidu (offset ~110 px RainViewer).
const double _kRadarCardinalUnitKm = 18.0;

bool _flatFrameWetAtPin(RadarFrameSample f, {required bool rainViewer}) {
  final center = f.dbz ?? 0.0;
  if (rainViewer) {
    // Len stred pinu — peak / nearbyEcho ≠ dážď na lokalite (mapa by bola suchá).
    return f.precipAtPoint || center >= kRainViewerLegendMinDbz;
  }
  // Helkor: `precip` = echo v okolí, nie na pine — nesmie spustiť „prší tu“.
  return f.precipAtPoint || center >= kRainViewerLegendMinDbz;
}

bool _flatFrameNearbyApproach(RadarFrameSample f, {required bool rainViewer}) {
  if (_flatFrameWetAtPin(f, rainViewer: rainViewer)) return false;
  final center = f.dbz ?? 0.0;
  final peak = f.innerPeakDbz ?? f.peakDbz ?? center;
  if (rainViewer) {
    return peak >= 18 &&
        center < kRainViewerLegendMinDbz &&
        (f.coherentPx14 >= 2 || f.coherentCorePx >= 1);
  }
  return peak >= 22 &&
      center < 14 &&
      (f.coherentPx14 >= 2 || f.precip || peak >= 28);
}

double _flatFrameUiDbz(RadarFrameSample f, {required bool rainViewer}) {
  final center = f.dbz ?? 0.0;
  final peak = f.innerPeakDbz ?? f.peakDbz ?? center;
  final raw = math.max(center, math.min(peak, center + 12));
  return rainViewer ? rainViewerDbzForUi(raw) : raw;
}

DateTime _flatLocalFromUnix(int unix, Duration tzOffset) =>
    DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true).add(tzOffset);

DateTime _flatHourFloor(DateTime t) =>
    DateTime(t.year, t.month, t.day, t.hour);

/// Ťažisko echo z N/S/E/W dBZ — vážené dbz² (čistá matematika, bez getterov).
(double x, double y, double weight) _flatEchoCentroid(RadarFrameSample f) {
  double x = 0, y = 0, w = 0;
  void add(double sx, double sy, double? dbz) {
    if (dbz == null || dbz < 14) return;
    final wt = dbz * dbz;
    x += sx * wt;
    y += sy * wt;
    w += wt;
  }

  add(0, -1, f.northDbz);
  add(0, 1, f.southDbz);
  add(1, 0, f.eastDbz);
  add(-1, 0, f.westDbz);
  if (w <= 0) return (0.0, 0.0, 0.0);
  return (x / w, y / w, w);
}

/// Lineárna regresia dBZ stredu vs. čas (dBZ / min).
double? _flatCenterDbzSlopePerMin(List<RadarFrameSample> history) {
  if (history.length < 3) return null;
  var sumT = 0.0, sumD = 0.0, sumTT = 0.0, sumTD = 0.0;
  final t0 = history.first.unix.toDouble();
  var usable = 0;
  for (final f in history) {
    final d = f.dbz;
    if (d == null) continue;
    final t = (f.unix - t0) / 60.0;
    sumT += t;
    sumD += d;
    sumTT += t * t;
    sumTD += t * d;
    usable++;
  }
  if (usable < 3) return null;
  final denom = usable * sumTT - sumT * sumT;
  if (denom.abs() < 1e-6) return null;
  return (usable * sumTD - sumT * sumD) / denom;
}

/// Trajektória + nowcast → ETA / koniec / šanca / vzdialenosť / rýchlosť.
///
/// Okno zrážok je v **minútach od teraz** a pri každom fetchi sa prepočíta
/// (ústup, nowcast sucho, slope dBZ) — nie natvrdo +1/+2 h.
({
  int? etaMinutes,
  int? endMinutes,
  int approachChancePercent,
  double? distanceKm,
  double? speedKmH,
  bool towardPin,
  bool approaching,
  bool departing,
}) _flatRadarMotionMath({
  required List<RadarFrameSample> history,
  required List<RadarFrameSample> nowcastHistory,
  required List<RadarFrameSample> helkorHistory,
  required bool fromRainViewer,
  required bool wetAtPinNow,
  required DateTime locNow,
}) {
  final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
  final frames = history.isNotEmpty ? history : helkorHistory;
  final rv = fromRainViewer && history.isNotEmpty;
  final latest = frames.isNotEmpty ? frames.last : null;
  final slope = _flatCenterDbzSlopePerMin(frames);

  double? distanceKm;
  double? speedKmH;
  var toward = false;
  var departingMotion = false;

  if (frames.length >= 3) {
    final first = frames.first;
    final last = frames.last;
    final c0 = _flatEchoCentroid(first);
    final c1 = _flatEchoCentroid(last);
    if (c1.$3 >= 100) {
      final distUnits = math.sqrt(c1.$1 * c1.$1 + c1.$2 * c1.$2);
      distanceKm = distUnits * _kRadarCardinalUnitKm;
      final spanMin = math.max(1.0, (last.unix - first.unix) / 60.0);
      final vx = (c1.$1 - c0.$1) / spanMin;
      final vy = (c1.$2 - c0.$2) / spanMin;
      final towardSpeed = (-c1.$1 * vx + -c1.$2 * vy);
      speedKmH = towardSpeed * _kRadarCardinalUnitKm * 60.0;
      toward = towardSpeed >= 0.012;
      departingMotion = towardSpeed <= -0.012;
    }
  }

  // Nowcast timeline: prvá mokrá / medzera / **posledná** mokrá (prehánka + front).
  int? firstWetNowcastMins;
  int? firstDryAfterWetMins;
  int? lastWetNowcastMins;
  var sawWetInNowcast = false;
  double lastWetDbz = kRainViewerLegendMinDbz;
  for (final f in nowcastHistory) {
    if (f.unix <= nowSec) continue;
    final mins = math.max(
      1,
      _flatLocalFromUnix(f.unix, locNow.timeZoneOffset)
          .difference(locNow)
          .inMinutes,
    );
    final wet = _flatFrameWetAtPin(f, rainViewer: true);
    if (wet) {
      sawWetInNowcast = true;
      firstWetNowcastMins ??= mins;
      lastWetNowcastMins = mins;
      lastWetDbz = f.dbz ?? lastWetDbz;
    } else if (sawWetInNowcast && firstDryAfterWetMins == null) {
      firstDryAfterWetMins = mins;
    } else if (wetAtPinNow && !sawWetInNowcast && firstDryAfterWetMins == null) {
      // Prší teraz, hneď najbližší nowcast je suchý → skorý koniec.
      firstDryAfterWetMins = mins;
    }
  }
  // Prehánka → sucho → front: lastWet je za firstDry → koniec = posledný mokrý beh.
  final multiCellNowcast = firstDryAfterWetMins != null &&
      lastWetNowcastMins != null &&
      lastWetNowcastMins > firstDryAfterWetMins;

  int? etaFromTrajectory;
  if (!wetAtPinNow && toward && distanceKm != null && speedKmH != null) {
    final distUnits = distanceKm / _kRadarCardinalUnitKm;
    final towardSpeed = speedKmH / (_kRadarCardinalUnitKm * 60.0);
    if (distUnits >= 0.06 && towardSpeed >= 0.01) {
      etaFromTrajectory = (distUnits / towardSpeed).ceil().clamp(5, 120);
    }
  }
  if (!wetAtPinNow &&
      slope != null &&
      slope > 0.03 &&
      latest != null &&
      (latest.dbz ?? 0) > 0 &&
      (latest.dbz ?? 0) < kRainViewerLegendMinDbz) {
    final slopeMins =
        ((kRainViewerLegendMinDbz - (latest.dbz ?? 0)) / slope).ceil().clamp(5, 90);
    etaFromTrajectory = etaFromTrajectory == null
        ? slopeMins
        : ((etaFromTrajectory + slopeMins) / 2).round();
  }

  int? etaFromGap;
  if (!wetAtPinNow &&
      latest != null &&
      !_flatFrameWetAtPin(latest, rainViewer: rv)) {
    final center = latest.dbz ?? 0;
    final peak = latest.innerPeakDbz ?? latest.peakDbz ?? center;
    final gap = peak - center;
    if (peak >= (rv ? 18.0 : 22.0) &&
        center < (rv ? kRainViewerLegendMinDbz : 14)) {
      etaFromGap = gap >= 22
          ? 12
          : (gap >= 14 ? 22 : (gap >= 8 ? 32 : 42));
    }
  }

  // ——— PRŠÍ TERAZ: koniec podľa nowcastu + veľkosti bunky; stabilizácia mimo ———
  if (wetAtPinNow) {
    int endMins;
    final px = latest?.coherentPx14 ?? 0;
    // Veľká bunka → dlhší odhad; malá → kratší.
    final sizeBoost = px >= 100
        ? 40
        : (px >= 50 ? 28 : (px >= 20 ? 16 : (px >= 8 ? 8 : 0)));

    final drizzleTail = lastWetDbz < 18
        ? 8
        : (lastWetDbz < 26 ? 12 : (lastWetDbz < 34 ? 16 : 22));
    if (lastWetNowcastMins != null && multiCellNowcast) {
      // Druhá (ďalšia) bunka v nowcaste — koniec podľa posledného mokrého, nie medzery.
      endMins = (lastWetNowcastMins + drizzleTail + sizeBoost).clamp(35, 180);
    } else if (firstDryAfterWetMins != null &&
        lastWetNowcastMins != null &&
        !multiCellNowcast) {
      // Jedna súvislá prehánka, potom sucho.
      endMins = math
          .max(
            firstDryAfterWetMins + 5 + sizeBoost ~/ 2,
            lastWetNowcastMins + drizzleTail,
          )
          .clamp(25, 160);
    } else if (firstDryAfterWetMins != null && !sawWetInNowcast) {
      endMins = math.max(firstDryAfterWetMins + 8, 25 + sizeBoost ~/ 2)
          .clamp(25, 90);
    } else if (lastWetNowcastMins != null) {
      endMins = (lastWetNowcastMins + drizzleTail + sizeBoost).clamp(30, 180);
      // Nowcast ešte stále mokrý na konci horizontu → dážď pokračuje.
      if (firstDryAfterWetMins == null) {
        endMins = math.max(endMins, lastWetNowcastMins + 25 + sizeBoost ~/ 2);
      }
    } else {
      final ui = latest == null
          ? kRainViewerLegendMinDbz
          : _flatFrameUiDbz(latest, rainViewer: rv);
      var guess = ui >= 35
          ? 70
          : (ui >= 26 ? 55 : (ui >= 18 ? 40 : 28));
      guess += sizeBoost;
      if (departingMotion && slope != null && slope < -0.08) {
        guess = math.min(guess, 28);
      }
      endMins = guess.clamp(25, 160);
    }
    // Ústup skráti koniec len pri jednej bunke — nie keď hneď ide ďalší front.
    if (departingMotion &&
        firstDryAfterWetMins != null &&
        !multiCellNowcast) {
      endMins = math.min(endMins, math.max(firstDryAfterWetMins + 10, 20));
    }
    return (
      etaMinutes: 0,
      endMinutes: endMins,
      approachChancePercent: 100,
      distanceKm: 0.0,
      speedKmH: speedKmH,
      towardPin: toward,
      approaching: false,
      departing: departingMotion &&
          slope != null &&
          slope < -0.06 &&
          firstDryAfterWetMins != null,
    );
  }

  // ——— PRÍCHOD: preferuj nowcast ETA, trajektória ako korekcia ———
  int? eta;
  if (firstWetNowcastMins != null && etaFromTrajectory != null) {
    final diff = (firstWetNowcastMins - etaFromTrajectory).abs();
    eta = diff <= 20
        ? ((firstWetNowcastMins * 2 + etaFromTrajectory) / 3).round()
        : firstWetNowcastMins;
  } else {
    eta = firstWetNowcastMins ?? etaFromTrajectory ?? etaFromGap;
  }

  if (departingMotion && firstWetNowcastMins == null) {
    eta = null;
  }

  int? endMins;
  if (lastWetNowcastMins != null && multiCellNowcast) {
    // Front za prehánkou — koniec podľa poslednej mokrej snímky.
    endMins = (lastWetNowcastMins + 10).clamp(
      eta != null ? eta + 15 : 20,
      180,
    );
  } else if (firstDryAfterWetMins != null && !multiCellNowcast) {
    endMins = firstDryAfterWetMins.clamp(eta != null ? eta + 5 : 8, 160);
  } else if (lastWetNowcastMins != null) {
    endMins = (lastWetNowcastMins + 8).clamp(
      eta != null ? eta + 8 : 10,
      180,
    );
  } else if (eta != null) {
    final ui = latest == null
        ? 18.0
        : _flatFrameUiDbz(latest, rainViewer: rv);
    // Dostatočné trvanie prechodu — radšej dlhšie než predčasný koniec.
    final duration = ui >= 30 ? 45 : (ui >= 22 ? 35 : 25);
    endMins = (eta + duration).clamp(eta + 15, 160);
  }

  final nearby =
      latest != null && _flatFrameNearbyApproach(latest, rainViewer: rv);
  var approaching = (eta != null && !departingMotion) ||
      (nearby && !departingMotion) ||
      (toward && !departingMotion && eta != null);

  var chance = 0;
  if (firstWetNowcastMins != null) chance += 50;
  if (etaFromTrajectory != null && toward) chance += 30;
  if (nearby && !departingMotion) chance += 15;
  if (slope != null && slope > 0.04) chance += 12;
  if (speedKmH != null && speedKmH > 12) chance += 8;
  if (distanceKm != null && distanceKm < 30) chance += 8;
  if (distanceKm != null && distanceKm > 70) chance -= 20;
  if (departingMotion) chance -= 50;
  if (slope != null && slope < -0.04) chance -= 20;
  chance = chance.clamp(0, 95);
  if (!approaching || eta == null) {
    if (nearby && !departingMotion && etaFromGap != null) {
      approaching = true;
      eta ??= etaFromGap;
      chance = math.max(chance, 35);
      endMins ??= (eta + 15).clamp(eta + 8, 50);
    } else {
      chance = 0;
      approaching = false;
      eta = null;
      endMins = null;
    }
  }
  if (chance > 0 && chance < 30) chance = 30;
  // UI: šanca vždy po 10 % (50, 60, 70…).
  if (chance > 0) {
    chance = ((chance / 10.0).round() * 10).clamp(30, 100);
  }

  return (
    etaMinutes: eta,
    endMinutes: endMins,
    approachChancePercent: chance,
    distanceKm: distanceKm,
    speedKmH: speedKmH,
    towardPin: toward,
    approaching: approaching && chance >= 30,
    departing: departingMotion,
  );
}

/// Hodina sa prekrýva s minútovým oknom zrážok aspoň [minOverlap] minút.
bool _flatHourOverlapsWetWindow({
  required DateTime hourFloor,
  required DateTime locNow,
  required int wetStartMins,
  required int wetEndMins,
  int minOverlap = 10,
}) {
  if (wetEndMins <= wetStartMins) return false;
  final hourStart = hourFloor.difference(locNow).inMinutes;
  final hourEnd = hourStart + 60;
  final a = math.max(hourStart, wetStartMins);
  final b = math.min(hourEnd, wetEndMins);
  return (b - a) >= minOverlap;
}

/// Profesionálny nowcast snapshot — matematika pri každom fetchi.
RadarPinForecastSnapshot buildRadarPinForecastSnapshot({
  required List<RadarFrameSample> history,
  required List<RadarFrameSample> nowcastHistory,
  required List<RadarFrameSample> helkorHistory,
  required bool fromRainViewer,
  DateTime? at,
  double? cityLat,
  double? cityLon,
}) {
  final locNow = at ?? DateTime.now();
  final nowHour = _flatHourFloor(locNow);

  var wetAtPin = false;
  var uiDbz = 0.0;
  var peakDbz = 0.0;
  var rainViewer = fromRainViewer;

  void noteFrameIntensity(RadarFrameSample f, {required bool rv}) {
    final center = f.dbz ?? 0.0;
    final peak = f.innerPeakDbz ?? f.peakDbz ?? center;
    peakDbz = math.max(peakDbz, math.max(center, peak));
    uiDbz = math.max(uiDbz, _flatFrameUiDbz(f, rainViewer: rv));
  }

  if (history.isNotEmpty) {
    final f = history.last;
    if (_flatFrameWetAtPin(f, rainViewer: fromRainViewer)) {
      wetAtPin = true;
      rainViewer = fromRainViewer;
    }
    noteFrameIntensity(f, rv: fromRainViewer);
    for (final older in history) {
      noteFrameIntensity(older, rv: fromRainViewer);
    }
  }

  // Helkor / Meteo Radar = len zobrazenie mapy. Detekcia pinu len cez RainViewer,
  // Helkor iba keď RV históriu nemáme (fallback mimo/bez RV dát).
  if (!fromRainViewer && helkorHistory.isNotEmpty) {
    final f = helkorHistory.last;
    if (_flatFrameWetAtPin(f, rainViewer: false)) {
      wetAtPin = true;
      rainViewer = false;
    }
    noteFrameIntensity(f, rv: false);
  }

  final motion = _flatRadarMotionMath(
    history: history,
    nowcastHistory: nowcastHistory,
    helkorHistory: helkorHistory,
    fromRainViewer: fromRainViewer,
    wetAtPinNow: wetAtPin,
    locNow: locNow,
  );

  final approaching = motion.approaching;
  final eta = motion.etaMinutes;
  var endMins = motion.endMinutes;
  final chance = motion.approachChancePercent;
  final departing = motion.departing;

  // Stabilný koniec — veľká bunka môže ísť ďalej, ale ETA neskáče každú snímku.
  if (wetAtPin && endMins != null && cityLat != null && cityLon != null) {
    endMins = stabilizePinEndMinutes(
      cityKey: _trackerCityKey(cityLat, cityLon),
      wetAtPin: true,
      rawEndMins: endMins,
      locNow: locNow,
    );
  } else if (!wetAtPin && cityLat != null && cityLon != null) {
    stabilizePinEndMinutes(
      cityKey: _trackerCityKey(cityLat, cityLon),
      wetAtPin: false,
      rawEndMins: 0,
      locNow: locNow,
    );
  }

  final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
  for (final f in nowcastHistory) {
    if (f.unix <= nowSec) continue;
    if (!_flatFrameWetAtPin(f, rainViewer: true)) continue;
    noteFrameIntensity(f, rv: true);
    rainViewer = true;
  }

  final wetHours = <int>{};
  void authorizeHour(DateTime hour) {
    wetHours.add(_flatHourFloor(hour).millisecondsSinceEpoch);
  }

  final int? windowStart = wetAtPin
      ? 0
      : (approaching && eta != null && chance >= 25 ? eta : null);
  // Pri daždi na pine — okno podľa endMins; dlhá bunka môže ísť aj cez 2–3 h.
  final int? windowEnd = windowStart == null
      ? null
      : math.max(
          endMins ?? (windowStart + (wetAtPin ? 70 : 30)),
          wetAtPin ? 55 : (windowStart + 25),
        );

  if (windowStart != null && windowEnd != null && windowEnd > windowStart) {
    for (var h = 0; h <= 6; h++) {
      final hour = nowHour.add(Duration(hours: h));
      if (wetAtPin && h == 0) {
        authorizeHour(hour);
        continue;
      }
      if (_flatHourOverlapsWetWindow(
        hourFloor: hour,
        locNow: locNow,
        wetStartMins: windowStart,
        wetEndMins: windowEnd,
        minOverlap: wetAtPin ? 5 : 8,
      )) {
        authorizeHour(hour);
      }
    }
  }

  // Ďalšia hodina: pás 24 h začína na +1 h — pri daždi na pine ju vždy autorizuj.
  // Ďalšie hodiny podľa endMins (prehánka + front môže ísť 3–5 h).
  if (wetAtPin) {
    authorizeHour(nowHour);
    authorizeHour(nowHour.add(const Duration(hours: 1)));
    final hold = math.max(endMins ?? 55, 55);
    final minsToNextHour = 60 - locNow.minute;
    if (hold > minsToNextHour + 10) {
      authorizeHour(nowHour.add(const Duration(hours: 2)));
    }
    if (hold > minsToNextHour + 70) {
      authorizeHour(nowHour.add(const Duration(hours: 3)));
    }
    if (hold > minsToNextHour + 130) {
      authorizeHour(nowHour.add(const Duration(hours: 4)));
    }
    if (hold > minsToNextHour + 190) {
      authorizeHour(nowHour.add(const Duration(hours: 5)));
    }
  }

  // Nowcast snímky s dažďom na pine → autorizuj danú hodinu (aj druhý front po medzere).
  final tzGuess = locNow.timeZoneOffset;
  DateTime? lastNowcastWetHour;
  for (final f in nowcastHistory) {
    if (f.unix <= nowSec) continue;
    if (!_flatFrameWetAtPin(f, rainViewer: true)) continue;
    final local = _flatLocalFromUnix(f.unix, tzGuess);
    final hour = _flatHourFloor(local);
    authorizeHour(hour);
    lastNowcastWetHour = hour;
    noteFrameIntensity(f, rv: true);
    rainViewer = true;
  }

  if (departing && !wetAtPin && !approaching) {
    wetHours.clear();
  }

  if (uiDbz < kRainViewerLegendMinDbz &&
      (wetAtPin || (approaching && chance >= 25))) {
    uiDbz = kRainViewerLegendMinDbz;
  }
  if (peakDbz < uiDbz) peakDbz = uiDbz;

  var nearTermEnd = windowEnd != null
      ? _flatHourFloor(locNow.add(Duration(minutes: windowEnd)))
          .add(const Duration(hours: 1))
      : nowHour.add(const Duration(hours: 4));
  // Nowcast mokré hodiny (aj za medzerou) nesmú vypadnúť z filtra.
  if (lastNowcastWetHour != null) {
    final fromFrames = lastNowcastWetHour.add(const Duration(hours: 1));
    if (fromFrames.isAfter(nearTermEnd)) nearTermEnd = fromFrames;
  }
  // Dlhá bunka / multi-cell nowcast — až 6 h.
  final longHold = (endMins ?? 0) >= 70 || lastNowcastWetHour != null;
  final hardCapHours = (wetAtPin && longHold) || lastNowcastWetHour != null ? 6 : 4;
  final hardCap = nowHour.add(Duration(hours: hardCapHours));
  final cappedEnd = nearTermEnd.isAfter(hardCap) ? hardCap : nearTermEnd;
  // Inkluzívny koniec: hodina, ktorá sa ešte prekrýva s oknom, musí ostať.
  final nearEndMs =
      cappedEnd.add(const Duration(hours: 1)).millisecondsSinceEpoch;

  final filtered = wetHours
      .where((ms) =>
          ms >= nowHour.millisecondsSinceEpoch && ms < nearEndMs)
      .toList()
    ..sort();

  // Čisti ECMWF fantómy keď je pin suchý a nič neprichádza — aj keď bunka práve odchádza.
  final clearEcmwf = !wetAtPin &&
      !approaching &&
      (history.isNotEmpty || nowcastHistory.isNotEmpty || helkorHistory.isNotEmpty) &&
      (chance < 25 || departing);

  return RadarPinForecastSnapshot(
    wetAtPinNow: wetAtPin,
    approaching: approaching,
    uiDbz: uiDbz,
    rainViewer: rainViewer,
    wetHourStartsMs: filtered,
    nearTermEndExclusiveMs: nearEndMs,
    clearEcmwfNearTerm: clearEcmwf,
    etaMinutes: wetAtPin ? 0 : eta,
    endMinutes: wetAtPin ? math.max(endMins ?? 55, 55) : endMins,
    approachChancePercent: wetAtPin ? 100 : chance,
    distanceKmEstimate: motion.distanceKm,
    motionSpeedKmH: motion.speedKmH,
    towardPin: motion.towardPin,
    peakDbz: peakDbz,
  );
}

/// Radarový kontext — trend z posledných ~2 h histórie (podľa servera). Cieľ: odhad **kedy zrážky skončia**.
class RadarNowcastContext {
  const RadarNowcastContext({
    required this.eligible,
    required this.history, 
    this.fromRainViewer = false,
    this.nowcastHistory = const [],
    this.helkorHistory = const [],
    this.pinForecast = RadarPinForecastSnapshot.empty,
  });

  final bool eligible;
  final List<RadarFrameSample> history;
  /// História z RainViewer API (iná paleta / rozlíšenie než SHMÚ CMAX).
  final bool fromRainViewer;
  /// RainViewer nowcast snímky (budúce časy).
  final List<RadarFrameSample> nowcastHistory;
  /// Meteo Radar (SHMÚ CMAX cez Helkor) — poistka keď RainViewer nič neukáže.
  final List<RadarFrameSample> helkorHistory;
  /// Profesionálny flat snapshot + matematika pre UI (hero / 24 h).
  final RadarPinForecastSnapshot pinForecast;

  /// Helkor backup — len keď nie je RainViewer (mapa Meteo nie je detekcia).
  bool get meteoRadarBackupPrecipSignal =>
      !fromRainViewer && _helkorTrackerPrecipSignal;

  RadarFrameSample? get _helkorLatest =>
      helkorHistory.isNotEmpty ? helkorHistory.last : null;

  bool _helkorFrameWetAtPin(RadarFrameSample f) {
    if (f.precipAtPoint || f.precip) return true;
    final center = f.dbz ?? 0;
    final peak = f.peakDbz ?? center;
    if (center >= 14 && peak >= 18) return true;
    if (peak >= 22 && f.coherentPx14 >= kRadarMinCoherentAreaPx - 2) {
      return true;
    }
    return false;
  }

  bool _helkorNearbyPrecipField(RadarFrameSample f) {
    final center = f.dbz ?? 0;
    final peak = f.peakDbz ?? center;
    final strength = math.max(center, peak);
    return strength >= 22 &&
        (f.coherentPx14 >= 2 || peak >= 26 || f.precip);
  }

  /// Helkor CMAX — len fallback bez RainViewer; pri RV sa nepočíta do detekcie.
  bool get _helkorTrackerPrecipSignal {
    if (fromRainViewer || helkorHistory.isEmpty) return false;
    for (final f in helkorHistory.reversed.take(4)) {
      if (_helkorFrameWetAtPin(f) || _helkorNearbyPrecipField(f)) {
        return true;
      }
    }
    return false;
  }

  double get _helkorIntensityDbz {
    final f = _helkorLatest;
    if (f == null) return kRadarMinDbzForUi;
    final center = f.dbz ?? 0;
    final peak = f.peakDbz ?? center;
    return math.max(center, peak).clamp(12.0, 56.0);
  }

  static bool _authorizesPrecipDepthGuard = false;

  /// Bez filtrácie šumu — dôverujeme vzorkovaniu radaru (RainViewer aj CMAX).
  bool get _skipCmaxNoiseFilters => true;

  double _calibrateUiDbz(double raw) =>
      fromRainViewer ? rainViewerDbzForUi(raw) : raw;

  /// dBZ pre pás / predpoveď — len pri pine alebo nowcast pri pine.
  double get _rainViewerStripDbz => stripDbzForLocalHour(
        _localHourFloor(DateTime.now()),
        DateTime.now(),
      );

  /// Echo lokálne na pine — nie peak z bunky 50+ km v diali.
  bool _rainViewerLocalEchoAtPin(RadarFrameSample f) {
    final center = f.dbz ?? 0;
    if (center >= kRainViewerLegendMinDbz) return true;
    final inner = f.innerPeakDbz ?? f.peakDbz ?? center;
    final gap = inner - center;
    if (center >= kRainViewerLegendTraceDbz && f.coherentCorePx >= 1) {
      return true;
    }
    if (center >= kRainViewerLegendTraceDbz &&
        inner >= 12 &&
        gap <= 10) {
      return true;
    }
    if (center >= 10 &&
        f.coherentPx14 >= 2 &&
        gap <= 14) {
      return true;
    }
    return false;
  }

  /// Mrholenie priamo na pine (zelené na mape, pod 15 dBZ).
  bool _rainViewerLightPrecipAtPin(RadarFrameSample f) {
    if ((f.dbz ?? 0) >= kRainViewerLegendMinDbz) return false;
    return _rainViewerLocalEchoAtPin(f);
  }

  /// Bunka priamo nad pinom — stred pinu alebo súvislé jadro v 64 px (nie echo v diali).
  bool _rainViewerCellEngulfsPin(RadarFrameSample f) {
    if (f.precipAtPoint) return true;
    if (_rainViewerLocalEchoAtPin(f)) return true;
    final center = f.dbz ?? 0;
    if (center >= kRainViewerLegendMinDbz) return true;
    final inner = f.innerPeakDbz ?? f.peakDbz ?? center;
    if (inner < kRainViewerLegendMinDbz) return false;
    if (f.coherentCorePx >= 2 && inner >= 18) return true;
    if (center >= 10 && inner >= 20 && (inner - center) <= 18) return true;
    return false;
  }

  /// Prší priamo na pine — **len stred pinu** (≥ 15 dBZ), nie bunka v okolí.
  bool _rainViewerFrameWetAtPin(RadarFrameSample f) =>
      _rainViewerFrameRainAtPinCore(f);

  /// Prší priamo na pine (stred ≥ 15 dBZ) — pre odhad konca, nie široké echo v diali.
  bool _rainViewerFrameRainAtPinCore(RadarFrameSample f) {
    if (f.precipAtPoint) return true;
    return (f.dbz ?? 0) >= kRainViewerLegendMinDbz;
  }

  /// Budúce nowcast snímky s dažďom na pine — **vrátane medzier** (prehánka + front).
  int _rainViewerRainCoreFramesAhead(DateTime locNow) {
    if (!fromRainViewer || nowcastHistory.isEmpty) return 0;
    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    var count = 0;
    for (final f in nowcastHistory) {
      if (f.unix <= nowSec) continue;
      if (_rainViewerFrameRainAtPinCore(f)) count++;
      // NEbreak pri suchu — druhá bunka za medzerou sa musí rátať.
    }
    return count;
  }

  /// Minúty do poslednej mokrej nowcast snímky na pine (cez suché medzery).
  int _rainViewerMinutesToLastCoreWet(DateTime locNow) {
    if (!fromRainViewer || nowcastHistory.isEmpty) return 0;
    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    int lastMins = 0;
    for (final f in nowcastHistory) {
      if (f.unix <= nowSec) continue;
      if (!_rainViewerFrameRainAtPinCore(f)) continue;
      lastMins = math.max(
        lastMins,
        DateTime.fromMillisecondsSinceEpoch(f.unix * 1000, isUtc: true)
            .add(locNow.timeZoneOffset)
            .difference(locNow)
            .inMinutes,
      );
    }
    return lastMins.clamp(0, 180);
  }

  int _rainViewerNowcastFrameIntervalMinutes(DateTime locNow) {
    if (nowcastHistory.length < 2) return 10;
    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    int? prevUnix;
    for (final f in nowcastHistory) {
      if (f.unix <= nowSec) continue;
      if (prevUnix != null) {
        final delta = ((f.unix - prevUnix) / 60).round();
        if (delta > 0) return delta.clamp(5, 15);
      }
      prevUnix = f.unix;
    }
    return 10;
  }

  /// RainViewer nowcast — aspoň 1 budúca mokrás snímka pri pine.
  bool _rainViewerFutureWetAtPin(DateTime locNow) {
    if (!fromRainViewer || nowcastHistory.isEmpty) return false;
    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    for (final f in nowcastHistory) {
      if (f.unix <= nowSec) continue;
      if (_rainViewerFrameWetAtPin(f)) return true;
    }
    return false;
  }

  /// RainViewer nowcast — zrážky v budúcnosti pri pine (≥2 po sebe idúce snímky).
  bool _rainViewerNowcastWetAheadAtPin(DateTime locNow) {
    if (!fromRainViewer || nowcastHistory.isEmpty) return false;
    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    var consecutive = 0;
    for (final f in nowcastHistory) {
      if (f.unix <= nowSec) continue;
      if (_rainViewerFrameWetAtPin(f)) {
        consecutive++;
        if (consecutive >= 2) return true;
      } else {
        consecutive = 0;
      }
    }
    return false;
  }

  /// RainViewer nowcast — zrážky v [slotHour] pri pine (jadro, nie fringe).
  bool _rainViewerNowcastWetAtHour(DateTime slotHour, DateTime locNow) =>
      _rainViewerMaxDbzInHourSlot(
            slotHour,
            locNow,
            nowcastHistory,
            frameWetAtPin: _rainViewerFrameRainAtPinCore,
          ) !=
          null;

  /// Koniec okna zrážok — výhradne RainViewer nowcast pri pine (bez umelého minima podľa dBZ).
  DateTime rainViewerNearTermWetEndExclusive(DateTime locNow) {
    final minuteEnd = _rainViewerStripRainMinuteEndAt(locNow);
    if (minuteEnd != null) {
      return _firstDryHourAfter(minuteEnd);
    }

    final nowHour = _localHourFloor(locNow);
    return nowHour.add(const Duration(hours: 1));
  }

  /// Posledná hodina pokrytá RainViewer nowcast snímkami (exkluzívne).
  DateTime? rainViewerNowcastCoverageEndExclusive(DateTime locNow) {
    if (!fromRainViewer || nowcastHistory.isEmpty) return null;
    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    DateTime? lastFrameLocal;
    for (final f in nowcastHistory) {
      if (f.unix <= nowSec) continue;
      lastFrameLocal = DateTime.fromMillisecondsSinceEpoch(
        f.unix * 1000,
        isUtc: true,
      ).add(locNow.timeZoneOffset);
    }
    if (lastFrameLocal == null) return null;
    return _localHourFloor(lastFrameLocal).add(const Duration(hours: 1));
  }

  /// Koniec okna pre pás 24 h — nowcast má zmysel do [kRadarNowcastStripHorizonHours] h.
  /// RainViewer snímky ~2 h; zvyšok okna = trajektória (ETA / koniec bunky).
  DateTime nowcastStripGateEndExclusive(DateTime locNow) {
    final nowHour = _localHourFloor(locNow);
    return nowHour.add(const Duration(hours: kRadarNowcastStripHorizonHours));
  }

  /// Zrážková ikona v pásme podľa nowcastu (do 4 h):
  /// - aktuálna hodina = živý pin
  /// - v okne RV snímkov (~2 h) = len mokrý pixel na pine v tej hodine
  /// - za snímkami do 4 h = trajektória (pinForecast)
  bool nowcastAuthorizesStripPrecipHour(DateTime slotHour, DateTime locNow) {
    final nowHour = _localHourFloor(locNow);
    final slot = _localHourFloor(slotHour);
    if (slot.isBefore(nowHour)) return false;
    if (!slot.isBefore(nowcastStripGateEndExclusive(locNow))) return false;

    // Aktuálna hodina — živý pin.
    if (slot == nowHour) {
      return precipNow || rainAtPinNow || pinForecast.wetAtPinNow;
    }

    if (fromRainViewer && nowcastHistory.isNotEmpty) {
      // 1) Skutočná nowcast snímka na tú hodinu.
      if (_rainViewerNowcastWetAtHour(slot, locNow)) return true;
      final cov = rainViewerNowcastCoverageEndExclusive(locNow);
      // V okne snímkov: suchá snímka = suchá hodina (nič nevymýšľať).
      if (cov != null && slot.isBefore(cov)) return false;
      // 2) Za poslednou snímkou → do 4 h: ETA / pohyb bunky.
      return pinForecast.authorizesLocalHour(slot);
    }

    // Bez RV nowcastu — flat snapshot (helkor / trajektória).
    return pinForecast.authorizesLocalHour(slot);
  }

  /// Minútový koniec dažďa pre pás 24 h — len nowcast snímky (bez getter reťazcov → Stack Overflow).
  DateTime? stripRainMinuteEndAt(DateTime locNow) =>
      _rainViewerStripRainMinuteEndAt(locNow);

  DateTime? _rainViewerStripRainMinuteEndAt(DateTime locNow) {
    if (!fromRainViewer) return null;

    final nowcastEnd = _rainViewerDryAtFromNowcast(locNow);
    if (nowcastEnd != null) return nowcastEnd;

    if (precipNow || rainAtPinNow) {
      final mins = _rainViewerIntensityFallbackMinutes(locNow);
      return _roundLocalTimeToMinutes(
        locNow.add(Duration(minutes: mins)),
      );
    }

    return null;
  }

  /// Budúce nowcast snímky (lokálny čas).
  List<RadarFrameSample> _rainViewerFutureNowcastFrames(DateTime locNow) {
    if (!fromRainViewer || nowcastHistory.isEmpty) return const [];
    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    return nowcastHistory.where((f) => f.unix > nowSec).toList(growable: false);
  }

  /// Kedy dBZ pri pine klesne pod prah — extrapolácia z nowcast trendu.
  int? _rainViewerDbzFadeMinutesFromNowcast(DateTime locNow) {
    final future = _rainViewerFutureNowcastFrames(locNow);
    if (future.isEmpty) return null;

    final interval = _rainViewerNowcastFrameIntervalMinutes(locNow).toDouble();

    for (var i = 0; i < future.length; i++) {
      final center = future[i].dbz ?? 0;
      if (center < kRainViewerLegendMinDbz) {
        return math.max(2, (i * interval).round());
      }
    }

    if (future.length >= 2) {
      final centers = future.map((f) => f.dbz ?? 0.0).toList();
      final last = centers.last;
      final prev = centers[centers.length - 2];
      final slope = (last - prev) / interval;
      if (slope < -0.12 && last > kRainViewerLegendTraceDbz) {
        final mins =
            ((last - kRainViewerLegendTraceDbz) / (-slope)).ceil();
        return mins.clamp(3, 60);
      }
    }
    return null;
  }

  /// Koniec zrážok z nowcast časovej osi — posledný dážď pri pine (+ medzery / druhý front).
  /// Bez [_echoDepartingFromPin] / [_precipBandPassedPin] (Stack Overflow v getter reťazci).
  int? _rainViewerEndMinutesFromNowcastTimeline(DateTime locNow) {
    final future = _rainViewerFutureNowcastFrames(locNow);
    if (future.isEmpty) {
      if (precipNow || rainAtPinNow) return 25;
      return null;
    }

    DateTime? lastRainAtPin;
    RadarFrameSample? lastRainFrame;
    for (final f in future) {
      if (!_rainViewerFrameRainAtPinCore(f)) continue;
      lastRainAtPin = DateTime.fromMillisecondsSinceEpoch(
        f.unix * 1000,
        isUtc: true,
      ).add(locNow.timeZoneOffset);
      lastRainFrame = f;
    }

    if (lastRainAtPin == null) {
      if (!precipNow && !rainAtPinNow) return 0;
      return 12;
    }

    final tailMins =
        lastRainAtPin.difference(locNow).inMinutes.clamp(0, 180);
    final lastCenter = lastRainFrame?.dbz ?? kRainViewerLegendMinDbz;
    final drizzleTail = lastCenter < 18
        ? 1
        : (lastCenter < 26 ? 2 : (lastCenter < 34 ? 3 : 5));
    return (tailMins + drizzleTail).clamp(3, 180);
  }

  /// Koniec zrážok z nowcastu — čas poslednej mokrej snímky pri pine (ako RainViewer „ústup“).
  DateTime? _rainViewerDryAtFromNowcast(DateTime locNow) {
    final mins = _rainViewerEndMinutesFromNowcastTimeline(locNow);
    if (mins == null) return null;
    if (mins <= 0) {
      return _roundLocalTimeToMinutes(locNow.add(const Duration(minutes: 5)));
    }
    return _roundLocalTimeToMinutes(locNow.add(Duration(minutes: mins)));
  }

  /// Zostávajúce minúty do sucha — fúzia nowcast + ústup bunky + trend dBZ.
  int? _rainViewerMinutesUntilDryAtPin(DateTime locNow) {
    if (!fromRainViewer) return null;
    if (!precipNow && !rainAtPinNow && !_trackerRainActiveAtPin) return 0;
    return _trackerEndMinutesFusion(locNow);
  }

  /// Najlepší odhad konca — nowcast snímky + trend dBZ (bez cyklických getterov).
  int _trackerEndMinutesFusion(DateTime locNow) {
    final estimates = <int>[];

    final timeline = _rainViewerEndMinutesFromNowcastTimeline(locNow);
    if (timeline != null && timeline > 0) estimates.add(timeline);

    final lastCoreMins = _rainViewerMinutesToLastCoreWet(locNow);
    if (lastCoreMins > 0) {
      estimates.add(lastCoreMins + 8);
    } else if (precipNow || rainAtPinNow) {
      final center = latest?.dbz ?? 0;
      final slope = _centerDbzSlopePerMin;
      if (slope != null && slope < -0.05 && center > 10) {
        estimates.add(((center - 8) / (-slope)).ceil().clamp(3, 25));
      } else {
        estimates.add(center >= 28 ? 35 : (center >= 18 ? 22 : 12));
      }
    }

    final fade = _rainViewerDbzFadeMinutesFromNowcast(locNow);
    // Fade len ako horný strop, keď nie je ďalší mokrý nowcast ďalej.
    if (fade != null &&
        fade > 0 &&
        (lastCoreMins <= 0 || fade + 15 >= lastCoreMins)) {
      estimates.add(fade);
    }

    if (estimates.isEmpty) {
      return _rainViewerIntensityFallbackMinutes(locNow).clamp(3, 90);
    }

    estimates.sort();
    if (estimates.length == 1) {
      return estimates.first.clamp(5, 180);
    }
    if (estimates.length == 2) {
      return ((estimates[0] + estimates[1]) / 2).round().clamp(5, 180);
    }
    // Medián — nie minimum (ústup prvej prehánky by zabil druhý front).
    return estimates[estimates.length ~/ 2].clamp(5, 180);
  }

  int _rainViewerIntensityFallbackMinutes([DateTime? locNow]) {
    final at = locNow ?? DateTime.now();
    final wetFrames = _rainViewerRainCoreFramesAhead(at);
    if (wetFrames > 0) {
      final interval = _rainViewerNowcastFrameIntervalMinutes(at);
      // Celý moký nowcast horizont + chvost — nie strop 60 min.
      return (wetFrames * interval + 15).clamp(15, 150);
    }
    if (_echoDepartingFromPin || _trailingEdgeAtPin) {
      return _departingRainMinutesLeft(at).clamp(3, 20);
    }
    final dbz = precipIntensityDbz;
    if (dbz >= kRainViewerLegendHeavyRainDbz) return 55;
    if (dbz >= kRainViewerLegendModerateRainDbz) return 40;
    if (dbz >= kRainViewerLegendLightRainDbz) return 28;
    if (dbz >= kRainViewerLegendMinDbz) return 18;
    return 12;
  }

  double _rainViewerIntensityFromFrame(RadarFrameSample f) =>
      rainViewerIntensityDbz(
        center: f.dbz,
        peak: f.peakDbz,
        atPoint: true,
      );

  /// Max. dBZ pri pine zo snímok, ktoré padajú do [slotHour, slotHour+1).
  double? _rainViewerMaxDbzInHourSlot(
    DateTime slotHour,
    DateTime locNow,
    Iterable<RadarFrameSample> frames, {
    bool Function(RadarFrameSample f)? frameWetAtPin,
  }) {
    final isWet = frameWetAtPin ?? _rainViewerFrameWetAtPin;
    final slotEnd = slotHour.add(const Duration(hours: 1));
    double? maxDbz;
    for (final f in frames) {
      if (!isWet(f)) continue;
      final frameLocal = DateTime.fromMillisecondsSinceEpoch(
        f.unix * 1000,
        isUtc: true,
      ).add(locNow.timeZoneOffset);
      if (frameLocal.isBefore(slotHour) || !frameLocal.isBefore(slotEnd)) {
        continue;
      }
      final d = _rainViewerIntensityFromFrame(f);
      if (d < kRainViewerLegendMinDbz) continue;
      maxDbz = maxDbz == null ? d : math.max(maxDbz, d);
    }
    return maxDbz;
  }

  /// Intenzita blížiacej sa bunky — smer príchodu alebo peak v okolí (~64 px).
  double get _rainViewerApproachDbz {
    final frame = latest;
    if (frame == null) return 0;
    final approach = _incomingApproach;
    if (approach != null && approach.dbz >= kRainViewerLegendMinDbz) {
      return rainViewerDbzForUi(approach.dbz);
    }
    final inner = frame.innerPeakDbz ?? frame.peakDbz ?? 0;
    final cardinal = _maxCardinalDbz(frame);
    return rainViewerDbzForUi(math.max(inner, cardinal));
  }

  /// RainViewer — signál pre sledovač: prší, nowcast pri pine, alebo bunka v okolí.
  bool get _rainViewerTrackerPrecipSignal {
    if (!fromRainViewer) return false;
    final locNow = DateTime.now();
    if (_rainViewerEchoBypassesPinAt(locNow)) return precipNow;
    return precipNow ||
        nowcastHistory.any((f) => _rainViewerFrameWetAtPin(f)) ||
        _rainViewerNearbyPrecipField;
  }

  bool _rainViewerIncomingLikelyAt(DateTime locNow) {
    if (!fromRainViewer) return false;
    if (precipNow) return true;
    if (_rainViewerEchoBypassesPinAt(locNow)) return false;
    if (!_rainViewerTrajectoryHeadingToPinAt(locNow)) return false;
    if (_rainViewerFutureWetAtPin(locNow)) return true;
    if (_rainViewerNearbyPrecipField && !_rainViewerNearbyFieldRecedingRaw()) {
      return true;
    }
    return _rainViewerTrajectoryIncomingCore();
  }

  bool _rainViewerTrackerPrecipSignalAt(DateTime locNow) =>
      _rainViewerIncomingLikelyAt(locNow);

  /// Ústup echo — len snímka + história (žiadne zdieľané gettery, Stack Overflow).
  bool _rainViewerNearbyFieldRecedingRaw() {
    if (history.length < 2) return false;
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    if (_rainViewerCellEngulfsPin(frame)) return false;

    final peaks = history.map((f) => f.peakDbz ?? f.dbz ?? 0).toList();
    if (peaks.length >= 3) {
      final tail = peaks.sublist(peaks.length - 3);
      if (tail[2] <= tail[1] &&
          tail[1] <= tail[0] &&
          tail[0] - tail[2] >= 6 &&
          center < kRainViewerLegendMinDbz) {
        return true;
      }
    }

    final slope = _centerDbzSlopePerMin;
    if (slope != null &&
        slope < -0.25 &&
        center < kRainViewerLegendMinDbz) {
      return true;
    }
    return false;
  }

  /// Suchý pin + bunka/pole pri pine na mape — aj bez potvrdeného pohybu.
  bool get _rainViewerNearbyPrecipField {
    if (!fromRainViewer || precipNow) return false;
    if (_rainViewerNearbyFieldRecedingRaw()) return false;

    final frame = latest;
    if (frame == null) return false;
    if (frame.precipAtPoint) return false;

    final center = frame.dbz ?? 0;
    if (center >= kRainViewerLegendMinDbz) return false;

    final inner = frame.innerPeakDbz ?? frame.peakDbz ?? 0;
    if (inner < kRainViewerLegendMinDbz) return false;

    final cardinal = _maxCardinalDbz(frame);
    final strength = rainViewerDbzForUi(math.max(inner, cardinal));
    return strength >= kRainViewerLegendMinDbz;
  }

  /// ETA blízkej bunky — intenzita/gap peak vs. stred (bez [_incomingArrivalMinutesRaw]).
  int _rainViewerNearbyArrivalMinutes() {
    final frame = latest;
    if (frame == null) return 35;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    final gap = peak - center;
    if (gap >= 25 || peak >= 40) return 15;
    if (gap >= 15 || peak >= 30) return 25;
    if (gap >= 8 || peak >= 22) return 35;
    return 45;
  }

  /// Blížiaca sa bunka — pohyb radaru + echo v smere pinu (bez cyklických getterov).
  bool get _rainViewerTrajectoryIncoming => _rainViewerTrajectoryIncomingCore();

  bool _rainViewerTrajectoryIncomingCore() {
    if (!fromRainViewer || precipNow) return false;
    final locNow = DateTime.now();
    if (_rainViewerEchoBypassesPinAt(locNow)) return false;
    if (!_rainViewerTrajectoryHeadingToPinAt(locNow)) return false;
    final frame = latest;
    if (frame == null) return false;

    if (nowcastHistory.any((f) => _rainViewerFrameWetAtPin(f))) return true;

    if (_rainViewerNearbyFieldRecedingRaw()) return false;
    if (history.length >= 3 && _rawCentroidMovingAwayFromPin()) return false;

    final center = frame.dbz ?? 0;
    if (center >= kRainViewerLegendMinDbz) return false;

    final strength = _rainViewerApproachDbz;
    if (strength < kRainViewerLegendMinDbz) return false;

    if (_echoApproachingPin ||
        _echoClosingFromDirection ||
        _echoMovingTowardPinOrClosing) {
      return true;
    }

    final approach = _incomingApproach;
    if (approach != null &&
        approach.dbz >= kRainViewerLegendMinDbz &&
        approach.dir != null) {
      final slope = _directionalDbzSlopePerMin(approach.dir!);
      if (slope != null && slope > 0.015) return true;
    }

    if (history.length >= 3 && strength >= 20) {
      final peaks = history
          .map((f) => f.innerPeakDbz ?? f.peakDbz ?? f.dbz ?? 0)
          .toList();
      final tail = peaks.sublist(peaks.length - 3);
      if (tail[2] > tail[0] + 2) return true;
    }

    return false;
  }

  /// Bunka na oboch opačných stranách — typický obchvat (Prešov W+E), nie príchod.
  bool _rainViewerClearOppositeFlankBypass(RadarFrameSample frame) {
    if (_rainViewerLightPrecipAtPin(frame)) return false;
    final center = frame.dbz ?? 0;
    if (center >= 10) return false;
    final w = frame.westDbz ?? 0;
    final e = frame.eastDbz ?? 0;
    final n = frame.northDbz ?? 0;
    final s = frame.southDbz ?? 0;
    const flankStrong = kRainViewerLegendLightRainDbz;
    return (w >= flankStrong && e >= flankStrong) ||
        (n >= flankStrong && s >= flankStrong);
  }

  /// Bunky obchádzajú pin — len jednoznačný obchvat; nie keď nowcast potvrdí príchod.
  bool _rainViewerEchoBypassesPinAt(DateTime locNow) {
    if (!fromRainViewer || precipNow) return false;
    final frame = latest;
    if (frame == null) return false;
    if (_rainViewerLocalEchoAtPin(frame)) return false;
    if (_rainViewerCellEngulfsPin(frame)) return false;

    if (_rainViewerClearOppositeFlankBypass(frame)) return true;

    final nowcastConfirmed = _rainViewerNowcastWetAheadAtPin(locNow);

    final center = frame.dbz ?? 0;
    if (center >= kRainViewerLegendMinDbz) return false;

    final w = frame.westDbz ?? 0;
    final e = frame.eastDbz ?? 0;
    final n = frame.northDbz ?? 0;
    final s = frame.southDbz ?? 0;
    const sideMin = kRainViewerLegendMinDbz;
    const sideStrong = 22.0;

    final oppositeFlanks =
        (w >= sideStrong && e >= sideStrong) ||
        (n >= sideStrong && s >= sideStrong);
    if (oppositeFlanks && center < 10 && !nowcastConfirmed) {
      final centerSlope = _centerDbzSlopePerMin;
      if (centerSlope == null || centerSlope < 0.05) return true;
    }

    if (nowcastConfirmed) return false;

    if (history.length >= 3 && !_echoMovingTowardPinOrClosing) {
      final first = history.first;
      final last = history.last;
      final c0 = _echoCentroid(first);
      final c1 = _echoCentroid(last);
      if (c1.$3 >= 120) {
        final spanMin = math.max(1.0, (last.unix - first.unix) / 60.0);
        final vx = (c1.$1 - c0.$1) / spanMin;
        final vy = (c1.$2 - c0.$2) / spanMin;
        final towardSpeed = (-c1.$1 * vx + -c1.$2 * vy);
        final lateralSpeed = (c1.$1 * vy - c1.$2 * vx).abs();
        if (towardSpeed < 0.008 && lateralSpeed >= 0.02) return true;
        if (lateralSpeed >= 0.03 && lateralSpeed > towardSpeed * 2.5) {
          return true;
        }
      }
      if (_rawCentroidMovingAwayFromPin()) return true;
    }

    final strongDirs = _strongEchoDirections(frame, minDbz: sideMin);
    if (strongDirs >= 2 &&
        center < kRainViewerLegendTraceDbz &&
        !_echoMovingTowardPin &&
        !_rainViewerLocalEchoAtPin(frame)) {
      final approach = _incomingApproach ?? _dominantEchoDirection();
      if (approach != null && approach.dbz >= sideStrong) {
        final slope = _directionalDbzSlopePerMin(approach.dir!);
        if (slope != null && slope > 0.02) return false;
      }
      final centerSlope = _centerDbzSlopePerMin;
      if (centerSlope == null || centerSlope < 0.04) return true;
    }

    return false;
  }

  /// Trajektória smeruje k pinu — nowcast + dominujúca bunka, alebo pohyb centroidu.
  bool _rainViewerTrajectoryHeadingToPinAt(DateTime locNow) {
    if (!fromRainViewer) return false;
    if (precipNow) return true;
    final frame = latest;
    if (frame == null) return false;
    if (_rainViewerCellEngulfsPin(frame)) return true;
    if (_rainViewerClearOppositeFlankBypass(frame)) return false;

    if (_rainViewerNowcastWetAheadAtPin(locNow)) return true;

    if (_rainViewerFutureWetAtPin(locNow)) {
      final approach = _incomingApproach ?? _dominantEchoDirection();
      if (approach != null && approach.dbz >= kRainViewerLegendMinDbz) {
        return true;
      }
      if (_echoMovingTowardPinOrClosing || _echoApproachingPin) return true;
    }

    if (_rainViewerEchoBypassesPinAt(locNow)) return false;

    if (_echoMovingTowardPinOrClosing || _echoApproachingPin) return true;

    if (history.length >= 3) {
      final first = history.first;
      final last = history.last;
      final c0 = _echoCentroid(first);
      final c1 = _echoCentroid(last);
      if (c1.$3 >= 120) {
        final spanMin = math.max(1.0, (last.unix - first.unix) / 60.0);
        final vx = (c1.$1 - c0.$1) / spanMin;
        final vy = (c1.$2 - c0.$2) / spanMin;
        final towardSpeed = (-c1.$1 * vx + -c1.$2 * vy);
        if (towardSpeed >= 0.015) return true;
      }
    }

    final center = frame.dbz ?? 0;
    final centerSlope = _centerDbzSlopePerMin;
    if (centerSlope != null &&
        centerSlope > 0.04 &&
        center < kRainViewerLegendMinDbz) {
      return true;
    }

    final approach = _incomingApproach ?? _dominantEchoDirection();
    if (approach != null && approach.dbz >= kRainViewerLegendMinDbz) {
      final slope = _directionalDbzSlopePerMin(approach.dir!);
      if (slope != null && slope > 0.02) return true;
      if (_strongEchoDirections(frame, minDbz: kRainViewerLegendMinDbz) == 1 &&
          (centerSlope ?? 0) > 0.015) {
        return true;
      }
    }

    return false;
  }

  /// Bunka na mape, pin ešte suchý — nowcast často príliš optimistický.
  bool _rainViewerIncomingCellSeparatedFromPin() {
    final frame = latest;
    if (frame == null) return false;
    if (_rainViewerCellEngulfsPin(frame)) return false;
    final center = frame.dbz ?? 0;
    if (center >= kRainViewerLegendMinDbz) return false;
    final inner = frame.innerPeakDbz ?? frame.peakDbz ?? 0;
    if (inner < kRainViewerLegendMinDbz &&
        _rainViewerApproachDbz < kRainViewerLegendMinDbz) {
      return false;
    }
    return center < 12 ||
        (inner >= kRainViewerLegendMinDbz && frame.coherentCorePx < 2) ||
        _incomingCellSeparatedFromPin;
  }

  /// ETA z pohybu bunky v histórii RainViewer (centroid + smer príchodu).
  int? _rainViewerTrajectoryArrivalMinutesFromHistory() {
    if (!fromRainViewer || history.length < 3) return null;
    final locNow = DateTime.now();
    if (_rainViewerEchoBypassesPinAt(locNow) ||
        !_rainViewerTrajectoryHeadingToPinAt(locNow)) {
      return null;
    }
    final frame = latest;
    if (frame == null) return null;
    if (_rainViewerCellEngulfsPin(frame)) return 0;
    if (_rawCentroidMovingAwayFromPin()) return null;

    final strength = _rainViewerApproachDbz;
    if (strength < kRainViewerLegendMinDbz) return null;

    final first = history.first;
    final last = history.last;
    final c0 = _echoCentroid(first);
    final c1 = _echoCentroid(last);
    if (c1.$3 < 150) return null;

    final spanMin = math.max(1.0, (last.unix - first.unix) / 60.0);
    final vx = (c1.$1 - c0.$1) / spanMin;
    final vy = (c1.$2 - c0.$2) / spanMin;
    final towardSpeed = (-c1.$1 * vx + -c1.$2 * vy);

    var dist = math.sqrt(c1.$1 * c1.$1 + c1.$2 * c1.$2);
    if (dist < 0.12) return 5;

    final center = frame.dbz ?? 0;
    if (center < kRainViewerLegendMinDbz) {
      final gap = _incomingEchoGapDbz();
      dist += (gap / 45).clamp(0.08, 0.55);
    }

    int? mins;
    if (towardSpeed >= 0.01) {
      mins = (dist / towardSpeed).ceil();
    }

    final centerSlope = _centerDbzSlopePerMin;
    if (centerSlope != null &&
        centerSlope > 0.025 &&
        center < kRainViewerLegendMinDbz) {
      final slopeMins =
          ((kRainViewerLegendMinDbz - center) / centerSlope).ceil();
      if (slopeMins >= 8) {
        mins = mins == null ? slopeMins : math.max(mins, slopeMins);
      }
    }

    final approach = _incomingApproach ?? _dominantEchoDirection();
    if (approach?.dir != null && history.length >= 3) {
      final dirSlope = _directionalDbzSlopePerMin(approach!.dir!);
      if (dirSlope != null && dirSlope > 0.02) {
        final gap = _incomingEchoGapDbz().clamp(6.0, 35.0);
        final dirMins = (gap / dirSlope).ceil();
        if (dirMins >= 8) {
          mins = mins == null ? dirMins : math.max(mins, dirMins);
        }
      }
    }

    if (mins == null) {
      if (!_echoMovingTowardPinOrClosing && towardSpeed < 0.015) {
        return null;
      }
      mins = _incomingEchoApproachMinutes();
    }

    return mins.clamp(10, 120);
  }

  int? _rainViewerNowcastArrivalMinutes(DateTime locNow) {
    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    for (final f in nowcastHistory) {
      if (f.unix <= nowSec || !_rainViewerFrameWetAtPin(f)) continue;
      final frameLocal = DateTime.fromMillisecondsSinceEpoch(
        f.unix * 1000,
        isUtc: true,
      ).add(locNow.timeZoneOffset);
      return math.max(5, frameLocal.difference(locNow).inMinutes);
    }
    return null;
  }

  int _rainViewerIncomingEtaFloor(int minutes) {
    if (!_rainViewerIncomingCellSeparatedFromPin()) {
      return minutes.clamp(5, 150);
    }
    final visual = _trackerVisualApproachMinutes();
    final gap = _incomingEchoGapDbz();
    final gapFloor = (12 + gap * 0.45).round().clamp(12, 45);
    return math.max(minutes, math.max(visual, gapFloor)).clamp(10, 150);
  }

  /// Minúty do príchodu — trajektória z histórie má prioritu pred optimistickým nowcastom.
  int _rainViewerIncomingArrivalMinutes(DateTime locNow) {
    if (precipNow) return 0;
    if (_rainViewerEchoBypassesPinAt(locNow) ||
        !_rainViewerTrajectoryHeadingToPinAt(locNow)) {
      return -1;
    }

    final trajectoryMins = _rainViewerTrajectoryArrivalMinutesFromHistory();
    final nowcastMins = _rainViewerNowcastArrivalMinutes(locNow);
    final separated = _rainViewerIncomingCellSeparatedFromPin();

    if (trajectoryMins != null || nowcastMins != null) {
      late final int mins;
      if (trajectoryMins != null && nowcastMins != null) {
        // Nowcast často skorší než skutočný pohyb bunky — pri oddelenej bunke ber neskorší odhad.
        mins = separated
            ? math.max(trajectoryMins, nowcastMins)
            : math.max(trajectoryMins, (nowcastMins * 0.85).round());
      } else {
        mins = trajectoryMins ?? nowcastMins!;
      }
      return _rainViewerIncomingEtaFloor(mins);
    }

    if (_rainViewerNearbyPrecipField && !_rainViewerTrajectoryIncomingCore()) {
      return _rainViewerIncomingEtaFloor(
        _rainViewerNearbyArrivalMinutes(),
      );
    }

    if (!_rainViewerTrajectoryIncomingCore()) return -1;

    var raw = _incomingArrivalMinutesRaw();
    if (raw < 0) raw = _trackerVisualApproachMinutes();
    if (raw < 0) return -1;
    return _rainViewerIncomingEtaFloor(raw);
  }

  /// Okno zrážok pre 24 h pás — živý dážď, nowcast pri pine, trajektória.
  ({DateTime start, DateTime end})? _rainViewerPrecipWindow(
    DateTime locNow,
  ) {
    final nowHour = _localHourFloor(locNow);

    if (precipNow) {
      return (
        start: nowHour,
        end: rainViewerNearTermWetEndExclusive(locNow),
      );
    }

    final nowSec = locNow.millisecondsSinceEpoch ~/ 1000;
    DateTime? wetStart;
    DateTime? wetEnd;
    var consecutive = 0;
    for (final f in nowcastHistory) {
      if (f.unix <= nowSec) continue;
      if (!_rainViewerFrameRainAtPinCore(f)) {
        consecutive = 0;
        continue;
      }
      consecutive++;
      if (consecutive < 2) continue;
      final frameLocal = DateTime.fromMillisecondsSinceEpoch(
        f.unix * 1000,
        isUtc: true,
      ).add(locNow.timeZoneOffset);
      final hour = _localHourFloor(frameLocal);
      if (wetStart == null || hour.isBefore(wetStart)) {
        wetStart = hour;
      }
      final hourEnd = hour.add(const Duration(hours: 1));
      if (wetEnd == null || hourEnd.isAfter(wetEnd)) {
        wetEnd = hourEnd;
      }
    }
    if (wetStart != null && wetEnd != null) {
      final start = wetStart.isBefore(nowHour) ? nowHour : wetStart;
      return (start: start, end: wetEnd);
    }

    return null;
  }

  /// dBZ pre konkrétny hodinový slot — živý radar alebo nowcast snímka.
  /// Nikdy nevracia flat intenzitu na cudzie hodiny (to kopírovalo mm).
  double stripDbzForLocalHour(DateTime slotHour, DateTime locNow) {
    final nowHour = _localHourFloor(locNow);
    final slot = _localHourFloor(slotHour);

    if (!fromRainViewer) {
      // Helkor: len aktuálna hodina, inak 0.
      if (slot != nowHour || !precipNow) return 0;
      return precipIntensityDbz;
    }

    final fromNowcast =
        _rainViewerMaxDbzInHourSlot(slot, locNow, nowcastHistory);
    if (fromNowcast != null) return fromNowcast;

    // Históriu len pre aktuálnu/minulú hodinu — nie na budúce sloty.
    if (!slot.isAfter(nowHour)) {
      final fromHistory =
          _rainViewerMaxDbzInHourSlot(slot, locNow, history);
      if (fromHistory != null) return fromHistory;
    }

    if (slot == nowHour && precipNow) {
      return precipIntensityDbz;
    }

    return 0;
  }

  bool _radarSnowLikely({double? tempC, double? uiDbz}) {
    if (fromRainViewer) {
      return rainViewerSnowLikely(
        tempC: tempC,
        uiDbz: uiDbz ?? precipIntensityDbz,
      );
    }
    return radarSnowLikely(tempC: tempC);
  }

  int _wmoFromRadarIntensity(double dbz, {required bool snow}) =>
      fromRainViewer
          ? wmoFromRainViewerDbz(dbz, snow: snow)
          : wmoFromRadarDbz(dbz, snow: snow);

  static const inactive = RadarNowcastContext(eligible: false, history: []);

  RadarFrameSample? get latest => history.isEmpty ? null : history.last;

  /// Posledných [kRadarNowcastTrendFrames] snímok — motion / „práve prestalo“ / transient.
  List<RadarFrameSample> get _recentHistory {
    if (history.length <= kRadarNowcastTrendFrames) return history;
    return history.sublist(history.length - kRadarNowcastTrendFrames);
  }

  /// Surový stav pixelu — trend v histórii; UI používa [precipNow].
  bool get _rawPrecipAtPoint => latest?.precipAtPoint ?? false;

  /// Prší pri pinom — len echo priamo nad bodkou (nie bunka v diaľke na mape).
  bool get precipNow {
    final frame = latest;
    if (frame == null) return false;
    if (fromRainViewer) {
      return _rainViewerFrameRainAtPinCore(frame);
    }
    // Helkor `precip` = nearbyEcho — pre „teraz“ berieme len stred pinu.
    return frame.precipAtPoint ||
        (frame.dbz ?? 0) >= kRainViewerLegendMinDbz;
  }

  /// Verejný prístup — RainViewer nowcast / blížiaca sa bunka pri pine.
  bool get rainViewerPredictsPrecip =>
      fromRainViewer &&
      (precipNow ||
          nowcastHistory.any((f) => _rainViewerFrameRainAtPinCore(f)) ||
          _rainViewerNearbyPrecipField ||
          _rainViewerTrajectoryIncoming);

  bool rainViewerPredictsPrecipAt(DateTime locNow) =>
      _rainViewerIncomingLikelyAt(locNow);

  /// Verejný prístup pre UI — radar potvrdil zrážky pri pine.
  bool get rainAtPinNow => _rainAtPinCore;

  /// Zrážky priamo nad pinom.
  bool get _rainAtPinCore {
    final frame = latest;
    if (frame == null) return false;
    if (fromRainViewer) return _rainViewerFrameRainAtPinCore(frame);
    return frame.precipAtPoint ||
        (frame.dbz ?? 0) >= kRainViewerLegendMinDbz;
  }

  /// Alias — interné volania.
  bool get _rainAtPinNow => _rainAtPinCore;

  bool peakDbzGapFringeOnly(double center, double peak) =>
      peak - center >= 14 && center < 14;

  /// dBZ pre hero / sledovač — intenzita pri pine; peak keď bunka prekrýva pin (červená na mape).
  double get precipIntensityDbz {
    final frame = latest;
    if (frame == null) return kRadarMinDbzForUi;

    if (fromRainViewer) {
      final center = frame.dbz ?? 0;
      return rainViewerIntensityDbz(
        center: center,
        peak: frame.innerPeakDbz ?? frame.peakDbz,
        atPoint: _rainViewerCellEngulfsPin(frame),
      );
    }

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    final wetAtPin = precipNow || _trackerRainActiveAtPin;

    if (!wetAtPin) {
      return center > 0
          ? center
          : (peak > 0 ? math.min(peak, 24.0) : kRadarMinDbzForUi);
    }

    // Stredný pixel môže byť slabší než vizuál bunky okolo bodky.
    if (_echoEngulfsPin || peak - center >= 6) {
      return math.max(center, peak).clamp(12.0, 56.0);
    }
    if (center >= 20) {
      return math.max(center, math.min(peak, center + 12)).clamp(12.0, 56.0);
    }
    return math.max(center, math.min(peak, center + 8)).clamp(12.0, 48.0);
  }

  int get wetScore {
    if (history.isEmpty) return -1;
    var score = 0;
    for (final frame in history) {
      if (frame.precip) score += 10;
      final dbz = frame.dbz;
      if (dbz != null) score += (dbz / 5).round();
      final peak = frame.peakDbz;
      if (peak != null) score += (peak / 4).round();
    }
    final last = latest;
    if (last != null) {
      if (last.precipAtPoint) score += 50;
      final dbz = last.dbz;
      if (dbz != null) score += (dbz / 2).round();
      final peak = last.peakDbz;
      if (peak != null) score += (peak / 2).round();
      final nearby = _maxNearbyDbz;
      if (nearby != null) score += (nearby / 3).round();
    }
    return score;
  }

  /// Echo priamo zasahuje pin (stred a peak blízko seba).
  bool get _echoEngulfsPin {
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    return peak >= 16 && (peak - center) <= 8;
  }

  /// Radar vidí zrážky pri lokalite — ešte nie priamo nad pinom.
  bool get _nearbyRainLikely {
    if (_rainAtPinCore || _isIsolatedSpeckleNoise) return false;
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    final nearby = _maxNearbyDbz ?? peak;

    if (_rainBandNearPin) return true;
    if (_echoClosingFromDirection && nearby >= 18 && center < 14) {
      return true;
    }
    if (!_echoMovingTowardPin || !_echoPersistedOrStrong) return false;

    if (center < 10 && nearby >= 24) return true;
    if (center < 12 && peak >= 24) return true;
    if (nearby >= 26 && peak >= 20) return true;
    return false;
  }

  /// Zrážky z viacerých strán okolo pinu — fronta/bunka v oblasti, nie „mimo“.
  bool get _rainBandNearPin {
    if (_isIsolatedSpeckleNoise) return false;
    final frame = latest;
    if (frame == null) return false;
    if (_strongEchoDirections(frame, minDbz: 20) >= 3 &&
        _echoPersistedOrStrong &&
        _echoMovingTowardPin) {
      return true;
    }
    final nearby = _maxNearbyDbz ?? 0;
    return nearby >= 28 &&
        _echoMovingTowardPin &&
        _echoPersistedOrStrong;
  }

  int _strongEchoDirections(RadarFrameSample f, {double minDbz = 20}) {
    var n = 0;
    for (final v in [f.northDbz, f.southDbz, f.eastDbz, f.westDbz]) {
      if (v != null && v >= minDbz) n++;
    }
    return n;
  }

  /// Centroid echo sa vzďaľuje — bez volania [_echoMovingAwayFromPin] (stack overflow).
  bool _rawCentroidMovingAwayFromPin() {
    if (history.length < 3) return false;
    final frame = latest;
    if (frame == null) return false;
    if ((frame.dbz ?? 0) >= kRadarMinDbzPrecipNow) return false;
    if (_strongEchoDirections(frame) >= 2) return false;

    final first = history.first;
    final last = history.last;
    final c0 = _echoCentroid(first);
    final c1 = _echoCentroid(last);
    if (c0.$3 < 280 || c1.$3 < 280) return false;

    final spanMin = math.max(1.0, (last.unix - first.unix) / 60.0);
    final vx = (c1.$1 - c0.$1) / spanMin;
    final vy = (c1.$2 - c0.$2) / spanMin;
    final away = (c1.$1 * vx + c1.$2 * vy);
    if (away <= 0.025) return false;

    final dist0 = c0.$1 * c0.$1 + c0.$2 * c0.$2;
    final dist1 = c1.$1 * c1.$1 + c1.$2 * c1.$2;
    if (dist1 > dist0 + 0.06 && (last.dbz ?? 0) < 14) return true;

    return away > 0.04 && (last.dbz ?? 0) < 12;
  }

  /// Signály ústupu bunky — bez [_nearbyEchoReceding] / [_echoPassingBy] (stack overflow).
  bool _rawPrecipBandRecedingSignals() {
    if (precipNow || history.length < 2) return false;

    if (_hadRecentRainAtPoint) {
      final center = latest?.dbz ?? 0;
      if (center < 18 && (latest?.peakDbz ?? 0) < 22) return true;
    }

    final peaks = history.map((f) => f.peakDbz).whereType<double>().toList();
    if (peaks.length >= 3) {
      final tail = peaks.sublist(peaks.length - 3);
      if (tail[2] <= tail[1] &&
          tail[1] <= tail[0] &&
          tail[0] - tail[2] >= 6) {
        return true;
      }
    }

    final slope = _centerDbzSlopePerMin;
    if (slope != null &&
        slope < -0.25 &&
        (latest?.dbz ?? 0) < kRadarMinDbzPrecipNow) {
      return true;
    }

    return _rawCentroidMovingAwayFromPin();
  }

  /// Echo v diaľke na mape, ale sucho pri pine a bez pohybu k nám (BA ≠ Trnava).
  bool get _staticDistantCellNearMap {
    if (_skipCmaxNoiseFilters) return false;
    if (precipNow || _confirmedRainAtPinCore) return false;
    final frame = latest;
    if (frame == null) return false;

    final center = frame.dbz ?? 0;
    if (center >= 14) return false;

    final strength = _frameEchoStrength(frame);
    if (strength < kRadarMinDbzSignificantEcho) return false;

    if (_echoMovingTowardPin || _echoClosingFromDirection) return false;
    if (_rainBandNearPin) return false;

    final dirs20 = _strongEchoDirections(frame, minDbz: 20);
    if (dirs20 <= 1 &&
        center < 10 &&
        frame.coherentPx14 < kRadarMinCoherentAreaPx + 3) {
      return true;
    }

    if (history.length >= 3) {
      final slope = _centerDbzSlopePerMin;
      if (center < 8 &&
          (slope == null || slope < 0.02) &&
          strength < 32) {
        return true;
      }
    }

    return false;
  }

  /// Echo, ktoré mapa zobrazí pri pine — RainViewer + Meteo Radar poistka.
  bool get _trackerMapEchoVisible {
    final frame = latest;
    if (frame != null && fromRainViewer) {
      if (_rainViewerFrameWetAtPin(frame)) return true;
    } else if (frame != null) {
      if (_skipCmaxNoiseFilters) {
        if (frame.precipAtPoint || frame.precip) return true;
      } else {
        final center = frame.dbz ?? 0;
        final peak = frame.peakDbz ?? center;
        if (_rawPrecipAtPoint && center >= 10) return true;
        if (center >= 14 && peak >= 18) return true;
        if (peak >= 22 && frame.coherentPx14 >= kRadarMinCoherentAreaPx - 2) {
          return true;
        }
        if (_coherentEchoNearPinRaw() || _realDirectionalFrontApproaching) {
          return true;
        }
      }
    }
    if (_helkorTrackerPrecipSignal) return true;
    return false;
  }

  /// Suchý pin + zelené/žlté echo v dosahu — prehánky smerujúce k lokalite.
  bool get _trackerNearbyApproachLikely {
    if (precipNow ||
        _trackerPrecipAtPinForCard ||
        _radarPrecipAlreadyAtPin) {
      return false;
    }
    if (fromRainViewer) {
      final frame = latest;
      if (frame == null) return false;
      final center = frame.dbz ?? 0;
      if (center >= kRainViewerLegendMinDbz) return false;
      if (_rainViewerNearbyFieldRecedingRaw()) return false;
      if (_echoClosingFromDirection ||
          _echoMovingTowardPinOrClosing ||
          _echoApproachingPin) {
        return true;
      }
      if (!_rainViewerNearbyPrecipField &&
          !_rainViewerTrajectoryIncomingCore()) {
        return false;
      }
      return _rainViewerApproachDbz >= kRainViewerLegendMinDbz;
    }
    if (!_trackerIncomingConfirmed && !_realDirectionalFrontApproaching) {
      return false;
    }
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    if (center >= kRadarMinDbzPrecipNow) return false;

    if (_echoClosingFromDirection ||
        _echoMovingTowardPinOrClosing ||
        _echoApproachingPin) {
      return true;
    }

    if (_echoMovingAwayFromPin || _cellTailPassedPin()) return false;

    final nearby = _maxNearbyDbz ?? 0;
    final cardinal = _maxCardinalDbz(frame);
    final strength = math.max(nearby, cardinal);

    // Bunka viditeľná na mape, pin ešte suchý — blíži sa.
    if (_trackerMapEchoVisible && center < 14 && strength >= 16) {
      return true;
    }

    if (strength < 16) return false;

    if (center < 12 && strength >= 18) {
      final dom = _dominantEchoDirection();
      if (dom != null) {
        final dirSlope = _directionalDbzSlopePerMin(dom.dir);
        if (dirSlope != null && dirSlope >= 0.02) return true;
      }
    }

    return false;
  }

  /// Bunka už prešla / odchádza — suchý pin, echo v jednom smere, bez príchodu.
  bool get _precipBandPassedPin {
    if (precipNow || _rainAtPinCore || _confirmedRainAtPinCore) return false;
    if (!eligible || history.isEmpty) return false;

    if (_echoClosingFromDirection ||
        _echoMovingTowardPinOrClosing ||
        _echoApproachingPin) {
      return false;
    }
    if (_trackerNearbyApproachLikely) return false;

    if (_cellTailPassedPin()) return true;

    if (_trackerPrecipAtPinForCard) return false;

    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (center >= kRadarMinDbzPrecipNow) return false;

    if (fromRainViewer) {
      if (_rainViewerTrajectoryIncoming ||
          _rainViewerNearbyPrecipField ||
          _trackerNearbyApproachLikely) {
        return false;
      }
      if (nowcastHistory.any((f) => _rainViewerFrameWetAtPin(f))) return false;
      final peak = frame.peakDbz ?? center;
      final nearby = _maxNearbyDbz ?? 0;
      if (center < kRainViewerLegendMinDbz &&
          math.max(peak, nearby) >= kRainViewerLegendLightRainDbz &&
          !_rainViewerNearbyFieldRecedingRaw()) {
        return false;
      }
      if (_rawPrecipBandRecedingSignals()) return true;
      return false;
    }

    if (_rawPrecipBandRecedingSignals()) return true;

    final nearby = _maxNearbyDbz ?? 0;
    if (nearby < 18) return false;

    if (_echoClosingFromDirection || _echoMovingTowardPinOrClosing) {
      return false;
    }

    // Suchý stred, silné echo v jednom smere — typicky už za pinom (východ/západ).
    if (center < 12) {
      final east = frame.eastDbz ?? 0;
      final west = frame.westDbz ?? 0;
      final north = frame.northDbz ?? 0;
      final south = frame.southDbz ?? 0;
      final maxCard = math.max(math.max(east, west), math.max(north, south));
      if (maxCard >= 20 && center < 10 && maxCard - center >= 12) {
        return true;
      }
      if (center < 10 && east >= 20 && east > west + 6) {
        if (!_echoClosingFromDirection && !_echoMovingTowardPinOrClosing) {
          return true;
        }
      }
      if (center < 10 && west >= 20 && west > east + 6) {
        if (!_echoClosingFromDirection && !_echoMovingTowardPinOrClosing) {
          return true;
        }
      }

      final strongDirs = _strongEchoDirections(frame, minDbz: 18);
      if (strongDirs == 1 && peak >= 20) return true;
      final dom = _dominantEchoDirection(frame);
      if (dom != null && dom.dbz >= 22) return true;
      if (peak >= 24 && peak - center >= 10) return true;
    }

    if (_hadRecentRainAtPoint && center < 14) {
      final slope = _centerDbzSlopePerMin;
      if (slope != null && slope < -0.05) return true;
    }

    return false;
  }

  /// Verejný prístup pre 24 h pás — radar hovorí, že zrážky už prešli / nejdú na pin.
  bool get radarPrecipBandPassedPin => _precipBandPassedPin;

  /// Hero / aktuálna hodina — prší len pri pine (rovnaké pravidlo ako sledovač).
  bool get rainActiveAtPinForUi => _trackerRainActiveAtPin;

  /// RainViewer — echo pri pine alebo nowcast nad pinom (verejné pre hero).
  bool get rainViewerTrackerPrecipSignal => _rainViewerTrackerPrecipSignal;

  /// Po prejdení bunky / suchom pine — v pásme 24 h neukazovať falošné % z ECMWF.
  bool hourlyStripSuppressPhantomApproachPercents(DateTime locNow) {
    if (!eligible) return false;
    if (precipNow || _trackerRainActiveAtPin) return false;
    if (_trackerUiAuthorizesStripPrecip(locNow)) return false;
    return true;
  }

  /// Počíta sa do „pred/po daždi“ len ak radar slot potvrdí.
  bool hourlyStripSlotCountsAsRainForApproach(
    DateTime slotHour,
    DateTime locNow, {
    required bool stripShowsRain,
  }) {
    if (!eligible) return stripShowsRain;
    // ECMWF už ukazuje dážď v pásme — prístupové % (20→30→40) nesmú zmiznúť kvôli radaru.
    if (stripShowsRain) return true;
    if (fromRainViewer) {
      return authorizesPrecipAtLocalHour(slotHour, locNow);
    }
    return authorizesPrecipAtLocalHour(slotHour, locNow);
  }

  /// Prší priamo nad pinom — striktne RainViewer stred pinu.
  bool get _trackerRainActiveAtPin {
    if (fromRainViewer) {
      return precipNow || _rainAtPinCore;
    }
    final frame = latest;
    if (frame == null) return false;
    if (_precipBandPassedPin) return false;
    return precipNow || frame.precipAtPoint;
  }

  /// Časová verzia — aktívny dážď len pri potvrdenom echo na pine (aktuálna snímka).
  bool _trackerRainActiveAtPinAt(DateTime locNow) {
    if (!fromRainViewer) return _trackerRainActiveAtPin;
    // Len živý pin — nie staré nowcast snímky (tie by držali falošné „prší“).
    return precipNow || _rainAtPinCore;
  }

  /// „Blíži sa…“ — RainViewer nowcast pri pine alebo bunka smerujúca k pinu.
  bool _trackerIncomingConfirmedAt(DateTime locNow) {
    if (fromRainViewer) {
      return _rainViewerIncomingLikelyAt(locNow);
    }
    return _trackerIncomingConfirmed;
  }

  /// Silné echo zo strany [dir] smeruje k pinu — nie „bunka prešla“.
  bool _cardinalEchoIsApproachingSide(String dir, double sideDbz) {
    if (sideDbz < 16) return false;
    final approach = _incomingApproach;
    if (approach != null && approach.dir == dir && approach.dbz >= 16) {
      return true;
    }
    final slope = _directionalDbzSlopePerMin(dir);
    if (slope != null && slope > 0.015) return true;
    if (_echoClosingFromDirection && approach?.dir == dir) return true;
    final centerSlope = _centerDbzSlopePerMin;
    if (centerSlope != null && centerSlope > 0.025) return true;
    return false;
  }

  /// Bunka už prešla / pin je len na okraji mapy — nie aktívny dážď pri lokalite.
  bool _cellTailPassedPin() {
    if (precipNow || _confirmedRainAtPinCore) return false;
    final frame = latest;
    if (frame == null) return false;

    if (_echoClosingFromDirection ||
        _echoMovingTowardPinOrClosing ||
        _echoApproachingPin) {
      return false;
    }

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;

    if (_echoDepartingFromPin && center < kRadarMinDbzPrecipNow) return true;
    if (_echoDepartingFromPin &&
        center < 16 &&
        (_echoMovingAwayFromPin || _rawCentroidMovingAwayFromPin())) {
      return true;
    }

    if (_hadRecentRainAtPoint) {
      if (center < 11) return true;
      if (center < 14 && peak < 20) return true;
      final slope = _centerDbzSlopePerMin;
      if (center < 16 && slope != null && slope < -0.05) return true;
    }

    final n = frame.northDbz ?? 0;
    final s = frame.southDbz ?? 0;
    final e = frame.eastDbz ?? 0;
    final w = frame.westDbz ?? 0;

    bool passedOnSide(String dir, double strong, double weak) {
      if (center >= 16) return false;
      if (strong < 20 || strong <= weak + 5 || center >= strong - 6) {
        return false;
      }
      if (_cardinalEchoIsApproachingSide(dir, strong)) return false;
      return _echoDepartingFromPin ||
          _rawCentroidMovingAwayFromPin() ||
          (_hadRecentRainAtPoint && center < 14);
    }

    if (passedOnSide('w', w, e)) return true;
    if (passedOnSide('e', e, w)) return true;
    if (passedOnSide('n', n, s)) return true;
    if (passedOnSide('s', s, n)) return true;

    if (_hadRecentRainAtPoint &&
        center < kRadarMinDbzPrecipNow &&
        frame.coherentCorePx < kRadarMinCoherentCorePx &&
        peak - center >= 8 &&
        _echoDepartingFromPin) {
      return true;
    }

    return false;
  }

  /// Radarová mapa už zobrazuje zrážky priamo nad pinom (stredný pixel, nie len peak v okolí).
  bool get _radarPrecipAlreadyAtPin {
    if (_cellTailPassedPin()) return false;
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;

    if (center < 12 && !_rawPrecipAtPoint) {
      if (_incomingCellSeparatedFromPin || _incomingEchoGapDbz() >= 10) {
        return false;
      }
    }

    if (_rawPrecipAtPoint && center >= 10) return true;
    if (center >= 14 && peak >= 16) return true;
    if (center >= 12 && peak >= 18 && frame.coherentCorePx >= 2) return true;
    if (_echoEngulfsPin && center >= 12 && peak >= 16) return true;
    return false;
  }

  /// Bunka už opúšťa lokalitu — slabnúce echo / pohyb preč od pinu (viditeľné na mape).
  bool get _echoDepartingFromPin {
    if (!eligible || history.length < 2) return false;
    final frame = latest;
    if (frame == null) return false;

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (center < 8 && peak < 16 && !_rawPrecipAtPoint) return false;

    // Bez [_echoPassingBy] — môže ťahať iné gettery späť sem (Stack Overflow).
    if (_rawEchoPassingByPin()) return true;

    final slope = _centerDbzSlopePerMin;
    if (slope != null && slope < -0.05) {
      // Bez [_localizedShowerAtPin] — ťahá [_steadyWideFront] → Stack Overflow.
      if (center < 32 || _wetAtPinRaw()) {
        final dbzTail = history.map((f) => f.dbz).whereType<double>().toList();
        if (dbzTail.length >= 2 &&
            dbzTail.last < dbzTail[dbzTail.length - 2] - 0.3) {
          return true;
        }
      }
    }

    final peaks =
        history.map((f) => f.peakDbz ?? f.dbz).whereType<double>().toList();
    if (peaks.length >= 3) {
      final tail = peaks.sublist(peaks.length - 3);
      if (tail[2] <= tail[1] &&
          tail[1] <= tail[0] &&
          tail[0] - tail[2] >= 4 &&
          (center < 28 || (slope != null && slope < 0))) {
        return true;
      }
    }

    bool tailLeaving(double? upwind, double? downwind) =>
        upwind != null &&
        upwind >= 16 &&
        (downwind == null || downwind < math.max(12, center - 2)) &&
        center <= upwind;

    if (tailLeaving(frame.westDbz, frame.eastDbz) ||
        tailLeaving(frame.eastDbz, frame.westDbz) ||
        tailLeaving(frame.northDbz, frame.southDbz) ||
        tailLeaving(frame.southDbz, frame.northDbz)) {
      return true;
    }

    if (_rawCentroidMovingAwayFromPin() &&
        (center < 32 || _wetAtPinRaw())) {
      return true;
    }

    if (_wetAtPinRaw()) {
      if (_cellAsymmetricEcho(frame)) return true;
      if (peak - center >= 5) return true;
      if (peaks.length >= 3) {
        final maxP = peaks.reduce(math.max);
        if (maxP >= 26 && peak <= maxP - 4) return true;
      }
    }

    final approach = _incomingApproach;
    final dir = approach?.dir;
    if (dir != null) {
      final vals = <double>[];
      for (final f in history) {
        final v = f.dbzInDirection(dir);
        if (v != null) vals.add(v);
      }
      if (vals.length >= 3) {
        final tail = vals.sublist(vals.length - 3);
        if (tail[2] < tail[0] - 4 && center < 24) return true;
      }
    }

    return false;
  }

  bool _cellAsymmetricEcho(RadarFrameSample frame) {
    final vals = [
      frame.northDbz,
      frame.southDbz,
      frame.eastDbz,
      frame.westDbz,
    ].whereType<double>().toList();
    if (vals.length < 3) return false;
    final maxD = vals.reduce(math.max);
    final active = vals.where((v) => v >= 14).toList();
    if (active.length < 2) return false;
    final minActive = active.reduce(math.min);
    return maxD >= 18 && maxD - minActive >= 8;
  }

  bool get _cellEdgeAtPin {
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (peak - center >= 5) return true;
    return _cellAsymmetricEcho(frame);
  }

  /// Pin na chvoste prechádzajúcej bunky — silné echo „za“ pinom, slabé vpred.
  bool get _trailingEdgeAtPin {
    final frame = latest;
    if (frame == null || !_wetAtPinRaw()) return false;

    final center = frame.dbz ?? 0;
    final w = frame.westDbz ?? 0;
    final e = frame.eastDbz ?? 0;
    final n = frame.northDbz ?? 0;
    final s = frame.southDbz ?? 0;

    bool onExitTail(double upwind, double downwind) {
      if (upwind < 16) return false;
      if (upwind < center) return false;
      if (upwind >= downwind + 6) return true;
      return downwind < 14 && upwind >= 18;
    }

    return onExitTail(w, e) ||
        onExitTail(e, w) ||
        onExitTail(n, s) ||
        onExitTail(s, n);
  }

  /// Zostávajúce minúty keď bunka odchádza — pin už na okraji/chvoste.
  int _trailingEdgeMinutesRemaining([DateTime? locNow]) {
    final at = locNow ?? DateTime.now();
    final frame = latest;
    final center = frame?.dbz ?? 0;
    final wet = _wetFramesAtPinTail();

    var mins = center < 16 ? 6 : (center < 22 ? 10 : 13);
    if (wet >= 5) mins = math.min(mins, 10);
    if (wet >= 7) mins = math.min(mins, 7);

    final slope = _centerDbzSlopePerMin;
    if (slope != null && slope < -0.02) {
      mins = math.min(mins, ((center - 6) / (-slope)).ceil());
    }
    if (_echoWeakening) mins = math.min(mins, 8);

    final peaks = history.map((f) => f.peakDbz ?? f.dbz ?? 0).toList();
    if (peaks.length >= 3) {
      final maxP = peaks.reduce(math.max);
      if (maxP >= 24 && peaks.last <= maxP - 4) {
        mins = math.min(mins, 6);
      }
    }

    if (fromRainViewer && _rainViewerRainCoreFramesAhead(at) == 0) {
      mins = math.min(mins, 7);
    }

    return mins.clamp(4, 16);
  }

  /// Surový stav pri pine — bez [precipNow] (predchádza stack overflow v reťazci getterov).
  bool _wetAtPinRaw() {
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    return frame.precipAtPoint ||
        center >= kRadarMinDbzPrecipNow ||
        _confirmedRainAtPinCore;
  }

  /// Široká ustálená fronta — jediný prípad, kde dážď môže trvať hodinu+.
  bool get _steadyWideFront {
    if (!_wetAtPinRaw()) return false;
    final frame = latest;
    if (frame == null) return false;

    // Prechádzajúca bunka na výjazde — nie fronta na hodinu.
    if (_trailingEdgeAtPin) return false;
    if (_cellAsymmetricEcho(frame)) return false;

    if (_rainBandNearPin) return true;

    if (frame.coherentPx14 >= 28) return true;

    if (_strongEchoDirections(frame, minDbz: 22) >= 3 &&
        steadyOngoing &&
        (_maxNearbyDbz ?? 0) >= 28) {
      return true;
    }

    if (_wetFramesAtPinTail() > 15 && !_hadDrySpellBeforeWetTail()) {
      return true;
    }

    return false;
  }

  /// Lokálna bunka / prehánka na mape — predvolene krátke trvanie (ako RainView).
  bool get _localizedShowerAtPin {
    if (!_wetAtPinRaw() && !_rainAtPinCore) return false;
    return !_steadyWideFront;
  }

  /// Po sebe idúce snímky s echo pri pine (typicky ~5 min / snímka).
  int _wetFramesAtPinTail() {
    var n = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      final f = history[i];
      if (f.precipAtPoint ||
          (f.dbz ?? 0) >= kRadarMinDbzPrecipNow ||
          (f.peakDbz ?? 0) >= 20) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  bool _hadDrySpellBeforeWetTail() {
    final wet = _wetFramesAtPinTail();
    final idx = history.length - wet;
    if (idx < 2) return false;
    for (var i = idx - 1; i >= math.max(0, idx - 5); i--) {
      final f = history[i];
      if (!f.precipAtPoint &&
          (f.dbz ?? 0) < 12 &&
          (f.peakDbz ?? 0) < 16) {
        return true;
      }
    }
    return false;
  }

  /// Prechádzajúca búrková bunka — nie ustálená fronta; RainView končí skôr.
  bool get _cellCrossingPin {
    if (!_localizedShowerAtPin) return false;
    final wet = _wetFramesAtPinTail();
    if (wet < 1 || wet > 18) return false;

    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;

    if (frame.coherentPx14 > 0 && frame.coherentPx14 <= 16) return true;
    if (peak - center >= 4) return true;
    if (_cellAsymmetricEcho(frame)) return true;
    if (peak >= 24 || center >= 24) return true;

    final peaks = history.map((f) => f.peakDbz ?? f.dbz ?? 0).toList();
    if (peaks.length >= 3) {
      final maxP = peaks.reduce(math.max);
      final maxIdx = peaks.lastIndexOf(maxP);
      if (maxP >= 22 && maxIdx < peaks.length - 1) return true;
    }

    return _hadDrySpellBeforeWetTail() || wet <= 12;
  }

  /// Zostávajúci čas prechodu bunky cez pin — podľa veku echo a trendu dBZ.
  int _passingCellMinutesRemaining() {
    if (_trailingEdgeAtPin) {
      return _trailingEdgeMinutesRemaining();
    }
    if (_cellEdgeAtPin) {
      return _departingRainMinutesLeft();
    }

    final frame = latest;
    final wet = _wetFramesAtPinTail();
    const frameMin = 5;
    final elapsedMin = wet * frameMin;

    final px = frame?.coherentPx14 ?? 0;
    if (px > 0 && px <= 16) {
      // Malá bunka na mape ≈ desiatky minút celkovo, nie hodina.
      final cellPassageMin = (px * 2.5).round().clamp(15, 38);
      final fromFootprint = cellPassageMin - elapsedMin;
      if (fromFootprint > 0) {
        return fromFootprint.clamp(8, 30);
      }
    }

    var totalPassage = 38;
    final peaks = history.map((f) => f.peakDbz ?? f.dbz ?? 0).toList();
    if (peaks.isNotEmpty) {
      final maxP = peaks.reduce(math.max);
      if (maxP >= 40) {
        totalPassage = 30;
      } else if (maxP < 22) {
        totalPassage = 45;
      }
    }

    var remaining = totalPassage - elapsedMin;

    final slope = _centerDbzSlopePerMin;
    final center = frame?.dbz ?? 0;
    if (slope != null && slope < -0.03) {
      remaining = math.min(
        remaining,
        ((center - 10) / (-slope)).ceil(),
      );
    }

    if (_echoWeakening || _precipDepartingCardinalOnly()) {
      remaining = math.min(remaining, _departingRainMinutesLeft());
    }

    if (peaks.length >= 3) {
      final maxP = peaks.reduce(math.max);
      final last = peaks.last;
      if (maxP >= 24 && last <= maxP - 4) {
        remaining = math.min(remaining, 20);
      }
    }

    return remaining.clamp(8, 32);
  }

  int _showerMinutesRemaining() {
    if (_cellCrossingPin || _cellEdgeAtPin) {
      return _passingCellMinutesRemaining();
    }
    return _passingCellMinutesRemaining().clamp(10, 28);
  }

  /// Zostávajúce minúty zrážok pri pine — fúzia nowcastu, ústupu bunky a trendu.
  int _trackerRemainingMinutesAtPin(DateTime locNow) {
    if (fromRainViewer && (precipNow || rainAtPinNow || _trackerRainActiveAtPin)) {
      return _trackerEndMinutesFusion(locNow).clamp(3, 180);
    }

    if (fromRainViewer) {
      final dry = _rainViewerMinutesUntilDryAtPin(locNow);
      if (dry != null) return dry.clamp(0, 180);
    }

    if (_precipBandPassedPin || _cellTailPassedPin()) return 0;

    if (_trailingEdgeAtPin) {
      return _trailingEdgeMinutesRemaining();
    }

    if (_echoDepartingFromPin) {
      return _departingRainMinutesLeft();
    }

    if (_localizedShowerAtPin) {
      return _showerMinutesRemaining();
    }

    if (precipNow) {
      if (trendEndingAtPoint) return 15;
      final frame = latest;
      if (_cellEdgeAtPin ||
          (frame != null && _cellAsymmetricEcho(frame))) {
        return _trailingEdgeMinutesRemaining();
      }
      final mins = _ongoingPassageMinutes();
      if (mins > 0) return mins.clamp(5, 35);
    }

    if (_trackerRainActiveAtPin) {
      final slope = _centerDbzSlopePerMin;
      final center = latest?.dbz ?? 0;
      if (slope != null && slope < -0.04) {
        return _departingRainMinutesLeft();
      }
      if (!precipNow && center < kRadarMinDbzPrecipNow) return 12;
      return 20;
    }

    return 35;
  }

  int _departingRainMinutesLeft([DateTime? locNow]) {
    final at = locNow ?? DateTime.now();
    if (fromRainViewer) {
      final coreAhead = _rainViewerRainCoreFramesAhead(at);
      if (coreAhead == 0) {
        final center = latest?.dbz ?? 0;
        final slope = _centerDbzSlopePerMin;
        if (slope != null && slope < -0.05 && center > 10) {
          return ((center - 8) / (-slope)).ceil().clamp(3, 15);
        }
        if (center < 14) return 4;
        if (center < 20) return 7;
        return 9;
      }
    }

    final center = latest?.dbz ?? 0;
    final slope = _centerDbzSlopePerMin;

    if (slope != null && slope < -0.04) {
      final mins = ((center - 8) / (-slope)).ceil();
      return mins.clamp(3, 18);
    }

    if (center < 14) return 4;
    if (center < 20) return 7;
    if (center < 28) return 10;
    if (center < 36) return 13;
    return 16;
  }

  /// Prší pri pine — mapa a karta sledovača (miernejšie než strict [precipNow]).
  bool get _trackerPrecipAtPinForCard {
    if (_cellTailPassedPin()) return false;
    if (precipNow || _confirmedRainAtPinCore) return true;
    if (_radarPrecipAlreadyAtPin) return true;
    if (_precipDepartingRaw) return false;
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (_rawPrecipAtPoint && center >= 10) return true;
    if (center >= 14 && peak >= 18) return true;
    if (_echoEngulfsPin && peak >= 16) return true;
    if (center >= 12 && peak >= 20) return true;
    return false;
  }

  /// Príchod zrážok — len potvrdená bunka/fronta, nie šum mapy.
  bool get _trackerSoftIncomingConfirmed {
    if (_precipBandPassedPin) return false;
    if (!_trackerIncomingConfirmed) return false;
    if (_nearbyEchoReceding) return false;
    if (_echoClearlyOffPath) return false;
    return true;
  }

  int _trackerSoftArrivalMinutes([DateTime? at]) {
    final locNow = at ?? DateTime.now();
    if (_trackerRainActiveAtPin || _radarPrecipAlreadyAtPin) return 0;
    final strict = _incomingArrivalMinutesFromNow(locNow);
    if (fromRainViewer) {
      if (strict >= 0) return strict;
      if (_rainViewerIncomingLikelyAt(locNow)) {
        final traj = _rainViewerTrajectoryArrivalMinutesFromHistory();
        if (traj != null) return _rainViewerIncomingEtaFloor(traj);
        return _rainViewerIncomingEtaFloor(_trackerVisualApproachMinutes());
      }
      return -1;
    }
    final visual = _trackerVisualApproachMinutes();
    if (strict >= 0) return math.min(strict, visual);
    if (_incomingCellSeparatedFromPin) {
      return math.min(_incomingEchoApproachMinutes(), visual);
    }
    if (_trackerNearbyApproachLikely || _trackerMapEchoVisible) {
      return visual;
    }
    if (!_trackerMapEchoVisible) return -1;
    return _defaultIncomingMinutes();
  }

  /// Roztrúsené slabé echo na viacerých stranách — typický CMAX šum, nie fronta.
  bool get _isDisorganizedMapNoise {
    if (_skipCmaxNoiseFilters) return false;
    if (_confirmedRainAtPinCore || precipNow) return false;
    if (_staticDistantCellNearMap) return true;

    final frame = latest;
    if (frame == null) return true;

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (center < 12 &&
        peak < 22 &&
        (_maxNearbyDbz ?? 0) < kRadarMinDbzTrackerIncoming) {
      return true;
    }
    if (center >= 14 &&
        peak >= 18 &&
        frame.coherentPx14 >= kRadarMinCoherentAreaPx - 2) {
      return false;
    }
    if (peak >= 26 && (_maxNearbyDbz ?? 0) >= 22) return false;
    if (center >= kRadarMinDbzPrecipNow) return false;
    if (_echoClosingFromDirection || _echoMovingTowardPinOrClosing) {
      return false;
    }

    final strength = _frameEchoStrength(frame);
    if (strength < kRadarMinDbzSignificantEcho) return true;

    final weakDirs = _strongEchoDirections(frame, minDbz: 16);
    final midDirs = _strongEchoDirections(frame, minDbz: 20);
    final strongDirs = _strongEchoDirections(frame, minDbz: 24);

    if (weakDirs >= 2 && strongDirs == 0) return true;
    if (weakDirs >= 3 && strongDirs <= 1) return true;
    if (midDirs >= 2 &&
        strongDirs == 0 &&
        frame.coherentPx14 < kRadarMinCoherentAreaPx + 2) {
      return true;
    }

    if (center < 14 &&
        frame.coherentPx14 < kRadarMinCoherentAreaPx &&
        frame.coherentCorePx < kRadarMinCoherentCorePx &&
        strength < kRadarMinDbzCoherentEcho) {
      return true;
    }

    return false;
  }

  /// Jediná brána pre „Blíži sa…“ v sledovači — nie izolovaný šum mapy.
  bool get _trackerIncomingConfirmed {
    if (fromRainViewer) {
      final locNow = DateTime.now();
      if (precipNow) return true;
      if (_rainViewerEchoBypassesPinAt(locNow)) return false;
      if (!_rainViewerTrajectoryHeadingToPinAt(locNow)) return false;
      if (nowcastHistory.any((f) => _rainViewerFrameWetAtPin(f))) return true;
      if (_rainViewerNearbyPrecipField && !_rainViewerNearbyFieldRecedingRaw()) {
        return true;
      }
      return _rainViewerTrajectoryIncomingCore();
    }
    if (precipNow || _confirmedRainAtPinCore) return true;
    if (_staticDistantCellNearMap ||
        _isIsolatedSpeckleNoise ||
        _isDisorganizedMapNoise) {
      return false;
    }
    if (_echoClearlyOffPath ||
        _echoMovingAwayFromPin ||
        _nearbyEchoReceding) {
      return false;
    }

    if (_rainBandNearPin &&
        (_maxNearbyDbz ?? 0) >= 28 &&
        _echoPersistedOrStrong &&
        _incomingArrivalMinutesRaw() >= 0) {
      return true;
    }

    if (!_realDirectionalFrontApproaching) return false;
    return _incomingArrivalMinutesRaw() >= 0;
  }

  /// Echo jednoznačne obchádza pin — nie keď prší v okolí z viacerých strán.
  bool get _echoClearlyOffPath {
    if (_echoClosingFromDirection || _echoMovingTowardPinOrClosing) {
      return false;
    }
    if (!_hasActiveNearbyEcho || _nearbyRainLikely || _rainBandNearPin) {
      return false;
    }
    final frame = latest;
    if (frame == null) return false;
    if (_strongEchoDirections(frame) >= 2) return false;
    return _rawCentroidMovingAwayFromPin() || _rawEchoPassingByPin();
  }

  /// Bunka míňa pin — bez [_echoPassingBySingleCell] (stack overflow).
  bool _rawEchoPassingByPin() {
    if (_echoClosingFromDirection || _echoMovingTowardPinOrClosing) {
      return false;
    }
    if (history.length < 2) return false;
    final frame = latest;
    if (frame == null) return false;
    if (_strongEchoDirections(frame) >= 2) return false;

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    final nearby = _maxNearbyDbz ?? peak;
    if (nearby < 18) return false;

    if (_rawCentroidMovingAwayFromPin()) return true;

    final dom = _dominantEchoDirection();
    if (dom == null) {
      final peaks = history.map((f) => f.peakDbz).whereType<double>().toList();
      if (peaks.length >= 3) {
        final tail = peaks.sublist(peaks.length - 3);
        if (tail[2] <= tail[1] &&
            tail[1] <= tail[0] &&
            tail[0] - tail[2] >= 5 &&
            center < kRadarMinDbzPrecipNow) {
          return true;
        }
      }
      return false;
    }

    final dirSlope = _directionalDbzSlopePerMin(dom.dir);
    if (dirSlope != null && dirSlope < -0.05 && center < kRadarMinDbzPrecipNow) {
      return true;
    }

    return dom.dbz >= 22 && center < kRadarMinDbzPrecipNow;
  }

  /// UI reaguje len na **poslednú** radarovú snímku — nie na starú mokrú históriu.
  bool get showsPrecipForUi => precipNow;

  /// Radar nepotvrdil zrážky pri pine.
  bool get dryAtPin => eligible && !precipNow;

  /// Suchý radar — ECMWF zrážky v blízkom okne skryť (radar-only režim).
  bool get radarOverridesDryEcmwfNearTerm => eligible;

  double? get dbz => latest?.dbz;

  /// Najsilnejšie echo v okolí pinu (peak + N/S/E/W prstenec ~48 px).
  double? get _maxNearbyDbz {
    final frame = latest;
    if (frame == null) return null;
    double? maxDbz;
    for (final v in [
      frame.peakDbz,
      frame.dbz,
      frame.northDbz,
      frame.southDbz,
      frame.eastDbz,
      frame.westDbz,
    ]) {
      if (v == null) continue;
      maxDbz = maxDbz == null ? v : math.max(maxDbz, v);
    }
    return maxDbz;
  }

  /// Koľko posledných snímok má echo ≥ [minDbz] (odfiltruje jednorázový šum).
  int _recentFramesWithEcho({double minDbz = 16}) {
    var n = 0;
    for (final f in _recentHistory) {
      var strength = f.peakDbz ?? f.dbz ?? 0;
      for (final v in [f.northDbz, f.southDbz, f.eastDbz, f.westDbz]) {
        if (v != null && v > strength) strength = v;
      }
      if (strength >= minDbz) n++;
    }
    return n;
  }

  double _maxCardinalDbz(RadarFrameSample f) {
    var m = 0.0;
    for (final v in [f.northDbz, f.southDbz, f.eastDbz, f.westDbz]) {
      if (v != null && v > m) m = v;
    }
    return m;
  }

  double _frameEchoStrength(RadarFrameSample f) {
    var strength = f.peakDbz ?? f.dbz ?? 0;
    for (final v in [f.northDbz, f.southDbz, f.eastDbz, f.westDbz]) {
      if (v != null && v > strength) strength = v;
    }
    return strength;
  }

  /// Izolované bodky mapy — slabý stred, peak z diaľky, bez súvislej oblasti.
  bool get _isScatteredSpeckleAtPin {
    if (_skipCmaxNoiseFilters) return false;
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (_rawPrecipAtPoint && center >= 10) return false;
    if (_echoEngulfsPin && peak >= 16) return false;
    if (center >= 14 && peak >= 16 && frame.coherentPx14 >= 4) return false;
    final gap = peak - center;

    // Silná bunka v okolí, na pine len slabé / fringe echo (typický CMAX šum).
    if (center < kRadarMinDbzPrecipNow &&
        gap >= 12 &&
        frame.coherentCorePx < kRadarMinCoherentCorePx) {
      return true;
    }
    if (center < 22 && gap >= 15) return true;
    if (center < 20 &&
        peak >= 28 &&
        frame.coherentPx14 < kRadarMinCoherentAreaPx &&
        frame.coherentCorePx < kRadarMinCoherentCorePx) {
      return true;
    }

    if (center >= kRadarMinDbzPrecipNow) {
      if (frame.coherentCorePx < kRadarMinCoherentCorePx ||
          frame.coherentPx14 < kRadarMinCoherentAreaPx) {
        return true;
      }
      if (gap >= 14 &&
          frame.coherentPx14 < kRadarMinCoherentAreaPx &&
          frame.coherentCorePx < kRadarMinCoherentCorePx) {
        return true;
      }
      return false;
    }
    if (frame.coherentCorePx >= kRadarMinCoherentCorePx) return false;
    if (frame.coherentPx14 >= kRadarMinCoherentAreaPx && center >= 14) {
      return false;
    }

    if (center < 16 && gap >= 10) return true;
    if (center < 14 && peak >= 24) return true;
    return false;
  }

  /// Silná bunka z jedného smeru (fronta), nie roztrúsený šum okolo pinu.
  bool get _realDirectionalFrontApproaching {
    if (_staticDistantCellNearMap || _isDisorganizedMapNoise) return false;

    final approach = _incomingApproach;
    if (approach == null || approach.dbz < kRadarMinDbzTrackerFront) {
      return false;
    }
    if (history.length < 4) return false;

    final frame = latest;
    if (frame == null) return false;
    if (frame.coherentPx14 < kRadarMinCoherentAreaPx) return false;

    final old = history.first.dbzInDirection(approach.dir!) ?? 0;
    if (approach.dbz < old + 2) return false;

    final dirSlope = _directionalDbzSlopePerMin(approach.dir!);
    if (dirSlope == null || dirSlope < 0.025) return false;

    if (!_echoMovingTowardPin && (frame.dbz ?? 0) < 14) return false;

    return _recentFramesWithEcho(minDbz: 22) >= kRadarNoiseMinPersistFrames;
  }

  /// Vzdialené echo smeruje k pinu — skorá fáza sledovania (rýchlosť / príchod).
  bool get _distantEchoHeadingToPin {
    if (precipNow || _confirmedRainAtPinCore) return false;
    if (_echoClearlyOffPath ||
        _echoMovingAwayFromPin ||
        _nearbyEchoReceding) {
      return false;
    }
    if (_isIsolatedSpeckleNoise || _isDisorganizedMapNoise) return false;
    return _realDirectionalFrontApproaching;
  }

  /// Skutočný dážď pri pine.
  bool get _confirmedRainAtPinCore => _rainAtPinCore;

  /// Izolovaný šum pri pine bez blížiacej sa bunky — bez rekurzie cez noise gettery.
  bool get _isIsolatedSpeckleNoise {
    if (_skipCmaxNoiseFilters) return false;
    return _isScatteredSpeckleAtPin && !_hasStrongNearbyStormRaw();
  }

  /// Silné echo v okolí — len snímka + história, žiadne noise/approaching gettery.
  bool _hasStrongNearbyStormRaw() {
    final frame = latest;
    if (frame == null) return false;
    final nearby = _maxNearbyDbz ?? 0;
    if (nearby < kRadarMinDbzTrackerIncoming) return false;

    final approach = _incomingApproach;
    if (approach != null && approach.dbz >= kRadarMinDbzTrackerIncoming) {
      return true;
    }
    if (_echoClosingFromDirection) return true;
    if (_realDirectionalFrontApproaching) return true;
    if (_strongEchoDirections(frame, minDbz: 20) >= 2 && nearby >= 24) {
      return true;
    }
    return nearby >= 28;
  }

  /// Koherentné echo — bez volania [precipNow] / [_isRadarNoiseOnly] (stack overflow).
  bool _coherentEchoNearPinRaw() {
    final frame = latest;
    if (frame == null) return false;
    if (fromRainViewer) {
      return _rainViewerFrameWetAtPin(frame) ||
          _rainViewerTrajectoryIncomingCore() ||
          _rainViewerNearbyPrecipField;
    }
    if (_skipCmaxNoiseFilters) {
      return frame.precipAtPoint || frame.precip;
    }

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    final nearby = _maxNearbyDbz ?? peak;
    final cardinal = _maxCardinalDbz(frame);
    final strength = math.max(nearby, math.max(peak, cardinal));

    if (_realDirectionalFrontApproaching &&
        (_incomingApproach?.dbz ?? 0) >= kRadarMinDbzTrackerFront) {
      return true;
    }

    if (center >= 14 &&
        peak >= 20 &&
        frame.coherentCorePx >= kRadarMinCoherentCorePx) {
      return true;
    }
    if (strength >= kRadarMinDbzCoherentEcho &&
        frame.coherentPx14 >= kRadarMinCoherentAreaPx) {
      return true;
    }

    if (_strongEchoDirections(frame, minDbz: 20) >= 2 && strength >= 20) {
      return true;
    }

    if (_recentFramesWithEcho(minDbz: 20) >= kRadarNoiseMinPersistFrames &&
        strength >= kRadarMinDbzSignificantEcho &&
        frame.coherentPx14 >= kRadarMinCoherentAreaPx) {
      return true;
    }

    if (_echoEngulfsPin && peak >= 18) return true;

    if (_confirmedRainAtPinCore) return true;

    return false;
  }

  /// Echo nie je izolovaný mŕtvy pixel — priestor + čas.
  bool get _isCoherentEchoNearPin {
    if (_confirmedRainAtPinCore) return true;
    return _coherentEchoNearPinRaw();
  }

  /// Radarový šum — izolované bodky bez súdržnosti (Hlohovec / Košice).
  bool get _isRadarNoiseOnly {
    if (fromRainViewer) {
      if (_confirmedRainAtPinCore || precipNow) return false;
      if (_rainViewerTrajectoryIncoming || _rainViewerNearbyPrecipField) {
        return false;
      }
      final frame = latest;
      if (frame == null) return true;
      if (_rainViewerFrameWetAtPin(frame)) return false;
      if (_trackerMapEchoVisible) return false;
      return true;
    }
    if (_skipCmaxNoiseFilters) return false;
    if (_confirmedRainAtPinCore) return false;
    if (_staticDistantCellNearMap) return true;
    if (_realDirectionalFrontApproaching) return false;
    if (_isDisorganizedMapNoise) return true;
    if (_coherentEchoNearPinRaw()) return false;
    if (_isScatteredSpeckleAtPin) {
      if (_hasStrongNearbyStormRaw()) return false;
      return true;
    }

    final frame = latest;
    if (frame == null) return true;
    final strength = _frameEchoStrength(frame);
    if (strength < kRadarMinDbzSignificantEcho) return true;

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;

    // 20–23 dBZ len v jednej snímke = typický artefakt.
    if (strength < kRadarMinDbzCoherentEcho &&
        _recentFramesWithEcho(minDbz: 18) < kRadarNoiseMinPersistFrames) {
      return true;
    }

    // Suchý stred + peak z diaľky, jeden smer, bez opakovania.
    if (center < 8 &&
        peak >= 18 &&
        _strongEchoDirections(frame, minDbz: 18) < 2 &&
        _recentFramesWithEcho(minDbz: 20) < kRadarNoiseMinPersistFrames) {
      return true;
    }

    if (_trackerMapEchoVisible) return false;
    return true;
  }

  /// @deprecated alias — prefer [_isCoherentEchoNearPin] / [_isRadarNoiseOnly].
  bool get _significantEchoNearPin => _isCoherentEchoNearPin;

  /// Silná bunka smeruje k pinu, ešte nie priamo nad ním.
  bool get _approachingPrecipFront {
    if (_confirmedRainAtPinCore || _isDisorganizedMapNoise) return false;
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;

    if (_isIsolatedSpeckleNoise) return false;
    if (!_realDirectionalFrontApproaching && !_rainBandNearPin) return false;

    if (_coherentEchoNearPinRaw() &&
        center < 14 &&
        (_maxNearbyDbz ?? 0) >= kRadarMinDbzTrackerIncoming &&
        (frame.coherentPx14 >= kRadarMinCoherentAreaPx ||
            _realDirectionalFrontApproaching)) {
      return true;
    }

    final nearby = _maxNearbyDbz ?? 0;
    if (_realDirectionalFrontApproaching &&
        nearby >= kRadarMinDbzTrackerIncoming) {
      return true;
    }
    return _rainBandNearPin;
  }

  /// Echo z dominantného smeru sa približuje (aj keď centroid zlyhá).
  bool get _echoClosingFromDirection {
    if (history.length < 2) return false;
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    if (center >= kRadarMinDbzPrecipNow) return false;

    final approach = _incomingApproach;
    if (approach == null || approach.dbz < kRadarMinDbzDistantApproach) return false;

    final dir = approach.dir!;
    final oldest = history.first;
    final oldDir = oldest.dbzInDirection(dir) ?? 0;
    if (approach.dbz >= oldDir + 2) return true;

    if (history.length >= 3) {
      final peaks = history.map((f) => f.peakDbz ?? f.dbz ?? 0).toList();
      if (peaks.last >= peaks.first + 3 && peaks.last >= 22) return true;
    }

    final dirSlope = _directionalDbzSlopePerMin(dir);
    return dirSlope != null && dirSlope >= 0.03;
  }

  /// Echo nie je izolovaný šum — silné alebo opakované v histórii.
  bool get _echoPersistedOrStrong {
    if (fromRainViewer) {
      final frame = latest;
      if (frame == null) return false;
      if (_rainViewerFrameWetAtPin(frame)) return true;
      if (_rainViewerNearbyPrecipField) return true;
      final inner = frame.innerPeakDbz ?? frame.peakDbz ?? frame.dbz ?? 0;
      if (inner >= kRainViewerLegendMinDbz) return true;
      return nowcastHistory.any((f) => _rainViewerFrameWetAtPin(f));
    }
    if (_skipCmaxNoiseFilters) {
      final frame = latest;
      if (frame == null) return false;
      return frame.precipAtPoint || frame.precip;
    }
    if (_isIsolatedSpeckleNoise) return false;
    final nearby = _maxNearbyDbz ?? 0;
    final peak = latest?.peakDbz ?? latest?.dbz ?? 0;
    final strength = math.max(nearby, peak);
    if (strength >= 28) return true;
    if (strength >= kRadarMinDbzSignificantEcho &&
        _recentFramesWithEcho(minDbz: 20) >= 3) {
      return true;
    }
    return _recentFramesWithEcho(minDbz: kRadarMinDbzSignificantEcho) >= 4;
  }

  bool get _hasActiveNearbyEcho =>
      _isCoherentEchoNearPin && !_isRadarNoiseOnly;

  /// Radar-only pás: echo v okolí, ale ešte nie priamo nad pinom.
  bool get nearbyEcho => !precipNow && _hasActiveNearbyEcho;

  /// Intenzita blížiacej sa bunky — len pri potvrdenom kurze na pin.
  double? get incomingIntensityDbz {
    if (precipNow) return dbz;
    final frame = latest;
    if (frame == null) return null;

    final center = frame.dbz ?? 0;
    if (center >= kRadarMinDbzPrecipNow) return _calibrateUiDbz(center);

    double? raw;
    if (_nearbyRainLikely || _echoApproachingPin || _approachingPrecipFront) {
      final approach = _incomingApproach;
      if (approach != null && approach.dbz >= kRadarMinDbzDistantApproach) {
        raw = math.min(approach.dbz, 40.0);
      } else {
        final peak = frame.peakDbz;
        if (peak != null && peak >= kRadarMinDbzDistantApproach) {
          raw = math.min(peak, 40.0);
        } else {
          final nearby = _maxNearbyDbz;
          if (nearby != null && nearby >= kRadarMinDbzTrackerIncoming) {
            raw = math.min(nearby, 40.0);
          }
        }
      }
    }

    if (raw == null && _trackerNearbyApproachLikely) {
      final nearby = _maxNearbyDbz ?? _maxCardinalDbz(frame);
      if (nearby >= 16) raw = math.min(nearby, 36.0);
    }

    return raw == null ? null : _calibrateUiDbz(raw);
  }

  /// Koľko budúcich hodín v 24 h pásme vyplniť radarovým dažďom/snehom.
  /// (Zastaralé pevné okno — preferuj [_activePrecipWindow].)
  int get incomingStripHours => _incomingPassageHours();

  /// Trend dBZ priamo nad pinom [dBZ/min] — lineárna regresia z histórie.
  double? get _centerDbzSlopePerMin {
    if (history.isEmpty) return null;
    final t0 = history.first.unix.toDouble();
    final samples = <({double min, double dbz})>[];
    for (final f in history) {
      if (f.unix <= 0 || f.dbz == null) continue;
      samples.add((min: (f.unix - t0) / 60.0, dbz: f.dbz!));
    }
    if (samples.length < 2) return null;

    var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
    final n = samples.length.toDouble();
    for (final s in samples) {
      sumX += s.min;
      sumY += s.dbz;
      sumXY += s.min * s.dbz;
      sumX2 += s.min * s.min;
    }
    final denom = n * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-6) return null;
    return (n * sumXY - sumX * sumY) / denom;
  }

  double? _directionalDbzSlopePerMin(String dir) {
    if (history.length < 2) return null;
    final t0 = history.first.unix.toDouble();
    final samples = <({double min, double dbz})>[];
    for (final f in history) {
      if (f.unix <= 0) continue;
      final v = f.dbzInDirection(dir);
      if (v == null) continue;
      samples.add((min: (f.unix - t0) / 60.0, dbz: v));
    }
    if (samples.length < 2) return null;

    var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
    final n = samples.length.toDouble();
    for (final s in samples) {
      sumX += s.min;
      sumY += s.dbz;
      sumXY += s.min * s.dbz;
      sumX2 += s.min * s.min;
    }
    final denom = n * sumX2 - sumX * sumX;
    if (denom.abs() < 1e-6) return null;
    return (n * sumXY - sumX * sumY) / denom;
  }

  ({String dir, double dbz})? _dominantEchoDirection([RadarFrameSample? frame]) {
    final f = frame ?? latest;
    if (f == null) return null;
    const dirs = ['n', 's', 'e', 'w'];
    String? bestDir;
    var bestDbz = 0.0;
    for (final dir in dirs) {
      final v = f.dbzInDirection(dir);
      if (v != null && v > bestDbz) {
        bestDbz = v;
        bestDir = dir;
      }
    }
    if (bestDir == null || bestDbz < kRadarMinDbzDistantApproach) return null;
    return (dir: bestDir, dbz: bestDbz);
  }

  (double x, double y, double weight) _echoCentroid(RadarFrameSample f) {
    double x = 0, y = 0, w = 0;
    void add(double sx, double sy, double? dbz) {
      if (dbz == null || dbz < 14) return;
      final wt = dbz * dbz;
      x += sx * wt;
      y += sy * wt;
      w += wt;
    }
    add(0, -1, f.northDbz);
    add(0, 1, f.southDbz);
    add(1, 0, f.eastDbz);
    add(-1, 0, f.westDbz);
    if (w <= 0) return (0, 0, 0);
    return (x / w, y / w, w);
  }

  /// Posun ťažiska echo smerom k pinu (nie len echo „niekde v okolí“).
  bool get _echoMovingTowardPin {
    if (history.length < 3) return false;

    final first = history.first;
    final last = history.last;
    final c0 = _echoCentroid(first);
    final c1 = _echoCentroid(last);
    if (c0.$3 < 280 || c1.$3 < 280) return false;

    final spanMin = math.max(1.0, (last.unix - first.unix) / 60.0);
    final vx = (c1.$1 - c0.$1) / spanMin;
    final vy = (c1.$2 - c0.$2) / spanMin;
    final toward = (-c1.$1 * vx + -c1.$2 * vy);
    if (toward < 0.012) return false;

    final center = last.dbz ?? 0;
    final centerSlope = _centerDbzSlopePerMin;
    if (centerSlope != null && centerSlope >= 0.06) return true;

    final gaps = history
        .map((f) => (f.peakDbz ?? f.dbz ?? 0) - (f.dbz ?? 0))
        .toList();
    if (gaps.length >= 3) {
      final tail = gaps.sublist(gaps.length - 3);
      if (tail[2] < tail[0] - 1.5 && (centerSlope ?? 0) > 0.02) {
        return true;
      }
    }

    if (toward >= 0.035 &&
        center >= 14 &&
        (c1.$1.abs() + c1.$2.abs()) < 0.6) {
      return true;
    }

    return toward >= 0.025 && center >= 12 && (centerSlope ?? 0) > 0;
  }

  bool get _echoMovingTowardPinOrClosing =>
      _echoMovingTowardPin || _echoClosingFromDirection;

  /// Echo sa vzďaľuje od pinu — len jedna bunka na jednej strane, nie fronta v okolí.
  bool get _echoMovingAwayFromPin {
    if (history.length < 3) return false;
    final frame = latest;
    if (frame == null) return false;
    if ((frame.dbz ?? 0) >= kRadarMinDbzPrecipNow) return false;
    if (_rainBandNearPin || _nearbyRainLikely) return false;
    if (_echoClosingFromDirection) return false;
    if (_strongEchoDirections(frame) >= 2) return false;
    if ((_maxNearbyDbz ?? 0) >= 22) return false;

    final center = frame.dbz ?? 0;
    final cardinal = _maxCardinalDbz(frame);
    if (center < 12 && cardinal >= 18 && (_maxNearbyDbz ?? 0) >= 18) {
      return false;
    }

    return _rawCentroidMovingAwayFromPin();
  }

  /// Echo v okolí, ale bunka nejde cez pin (iný smer / ustupuje).
  bool get _echoPassingBy => _echoPassingBySingleCell;

  bool get _echoPassingBySingleCell {
    if (_echoClosingFromDirection || _echoMovingTowardPinOrClosing) return false;
    if (_echoEngulfsPin || _nearbyRainLikely || _rainBandNearPin) {
      return false;
    }
    if (history.length < 2) return false;
    final frame = latest;
    if (frame == null) return false;
    if (_strongEchoDirections(frame) >= 2) return false;

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    final nearby = _maxNearbyDbz ?? peak;
    if (nearby < 18) return false;

    if (_echoMovingAwayFromPin) return true;

    final dom = _dominantEchoDirection();
    if (dom == null) {
      final peaks = history.map((f) => f.peakDbz).whereType<double>().toList();
      if (peaks.length >= 3) {
        final tail = peaks.sublist(peaks.length - 3);
        if (tail[2] <= tail[1] &&
            tail[1] <= tail[0] &&
            tail[0] - tail[2] >= 5 &&
            center < kRadarMinDbzPrecipNow) {
          return true;
        }
      }
      return false;
    }

    final dir = dom.dir;
    final dirSlope = _directionalDbzSlopePerMin(dir);
    final centerSlope = _centerDbzSlopePerMin;

    if (dirSlope != null && dirSlope < -0.05) {
      if (center < kRadarMinDbzPrecipNow) return true;
      if (center < dom.dbz - 10 && _precipDepartingRaw) return true;
    }

    if (dom.dbz >= 22 && center < kRadarMinDbzPrecipNow) {
      if (dirSlope != null &&
          dirSlope <= 0 &&
          (centerSlope == null || centerSlope <= 0.05)) {
        return true;
      }
    }

    if (history.length >= 3) {
      final midIdx = history.length ~/ 2;
      final oldDom = _dominantEchoDirection(history[midIdx]);
      if (oldDom != null &&
          oldDom.dir != dir &&
          dom.dbz >= 20 &&
          center < kRadarMinDbzPrecipNow &&
          peak - center >= 6) {
        return true;
      }
    }

    return false;
  }

  /// Bunka reálne smeruje k pinu — nie len echo v diaľke.
  bool get _echoApproachingPin {
    if (_confirmedRainAtPinCore) return false;
    if (_isIsolatedSpeckleNoise) return false;
    if (_echoMovingAwayFromPin) return false;

    final frame = latest;
    if (frame == null) return false;

    final center = frame.dbz ?? 0;

    // Bez [_echoPassingBy] — hlboký getter chain (Stack Overflow).
    if (_rawEchoPassingByPin() && !_echoMovingTowardPinOrClosing) return false;

    final approach = _incomingApproach;
    if (approach != null && approach.dbz >= 16 && center < 14) {
      return true;
    }

    if (_trackerMapEchoVisible && center < 14) {
      final nearby = _maxNearbyDbz ?? _maxCardinalDbz(frame);
      if (nearby >= 18) return true;
    }

    if (_echoMovingTowardPinOrClosing) {
      if (approach?.dir != null && approach!.dbz >= 18) return true;
    }

    if (approach == null || approach.dir == null || approach.dbz < 18) {
      return _significantEchoNearPin;
    }

    final dirSlope = _directionalDbzSlopePerMin(approach.dir!);
    if (dirSlope != null && dirSlope < -0.05) return false;

    final centerSlope = _centerDbzSlopePerMin;
    if (centerSlope != null && centerSlope < -0.12) return false;

    return _echoMovingTowardPinOrClosing ||
        (centerSlope != null && centerSlope >= 0.05);
  }

  bool get _hadRecentRainAtPoint =>
      _recentHistory.any((f) => f.precipAtPoint);

  int get _trailingDryAtPointFrames {
    var n = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (!history[i].precipAtPoint) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  /// Bunka už odchádza / minula — nepredpovedávať ďalší dážď v pásme.
  bool get _nearbyEchoReceding {
    if (history.length < 2) return false;

    if (_echoDepartingFromPin &&
        (precipNow ||
            _confirmedRainAtPinCore ||
            _hadRecentRainAtPoint)) {
      return true;
    }

    if (precipNow) return false;

    if (_echoPassingBy) return true;

    if (history.length >= 2) {
      final tail = history.sublist(history.length - 2);
      if (tail.every((f) =>
          !f.precipAtPoint && (f.peakDbz ?? 0) < 20)) {
        final hadEcho = history.any((f) =>
            f.precipAtPoint || (f.peakDbz ?? 0) >= 20);
        if (hadEcho) return true;
      }
    }

    if (_hadRecentRainAtPoint && !precipNow) {
      final center = latest?.dbz;
      // Už prestalo pršať pri pinom — nie „ešte len prichádza“.
      if (center == null || center < 18) {
        final peak = latest?.peakDbz ?? 0;
        if (peak < 22) return true;
      }
    }

    final peaks = history.map((f) => f.peakDbz).whereType<double>().toList();
    if (peaks.length >= 3) {
      final tail = peaks.sublist(peaks.length - 3);
      if (tail[2] <= tail[1] &&
          tail[1] <= tail[0] &&
          tail[0] - tail[2] >= 6) {
        return true;
      }
    }

    final approach = _incomingApproach;
    final dir = approach?.dir;
    if (dir != null) {
      final vals = <double>[];
      for (final f in history) {
        final v = f.dbzInDirection(dir);
        if (v != null) vals.add(v);
      }
      if (vals.length >= 3) {
        final tail = vals.sublist(vals.length - 3);
        if (tail[2] < tail[0] - 5 && (latest?.dbz ?? 0) < 20) return true;
      }
    }

    final slope = _centerDbzSlopePerMin;
    if (slope != null &&
        slope < -0.25 &&
        (latest?.dbz ?? 0) < kRadarMinDbzPrecipNow) {
      return true;
    }

    return false;
  }

  /// Prší pri pinom, ale echo už slabne — koniec do ~1 h.
  bool get trendEndingAtPoint {
    if (!precipNow) return true;
    if (_trailingDryAtPointFrames >= 1) return true;
    if (_precipDeparting) return true;
    if (_cellCrossingPin && _echoWeakening) return true;

    final slope = _centerDbzSlopePerMin;
    final current = dbz ?? 0;
    if (_cellCrossingPin && slope != null && slope < -0.05) return true;
    if (slope != null && slope < -0.2 && current < 32) return true;

    final dbzTail = history.map((f) => f.dbz).whereType<double>().toList();
    if (dbzTail.length >= 3) {
      final last3 = dbzTail.sublist(dbzTail.length - 3);
      if (last3[2] <= last3[1] &&
          last3[1] <= last3[0] &&
          last3[0] - last3[2] >= 4) {
        return true;
      }
    }
    return false;
  }

  /// dBZ pre odhad mm/% v pásme — konzervatívnejší než [stripDisplayDbz] pri blížiacej sa bunke.
  double get stripMmDbz {
    if (precipNow) return precipIntensityDbz;

    if (fromRainViewer) {
      return _rainViewerStripDbz;
    }

    final center = latest?.dbz;
    if (center != null && center >= kRadarMinDbzPrecipNow) return center;

    final incoming = incomingIntensityDbz;
    if (incoming != null && incoming >= 20) {
      return math.min(incoming, 27.0);
    }
    if (_trackerSoftIncomingConfirmed) {
      final nearby = _maxNearbyDbz;
      if (nearby != null && nearby >= kRadarMinDbzDistantApproach) {
        return math.min(nearby, 27.0);
      }
    }
    return math.min(stripDisplayDbz, 27.0);
  }

  /// dBZ pre 24 h pás — len pri pinom alebo potvrdenom príchode.
  double get stripDisplayDbz {
    if (precipNow) return precipIntensityDbz;

    if (fromRainViewer) {
      return _rainViewerStripDbz;
    }

    final center = latest?.dbz;
    if (center != null && center >= kRadarMinDbzPrecipNow) {
      return _calibrateUiDbz(center);
    }

    if (!_echoApproachingPin && !_nearbyRainLikely && !_rainBandNearPin &&
        !_approachingPrecipFront && !_significantEchoNearPin &&
        !_trackerSoftIncomingConfirmed) {
      return kRadarMinDbzForUi;
    }

    if (_trackerSoftIncomingConfirmed) {
      final nearby = _maxNearbyDbz;
      if (nearby != null && nearby >= kRadarMinDbzDistantApproach) {
        return _calibrateUiDbz(math.min(nearby, 40.0));
      }
    }

    if (_significantEchoNearPin || _approachingPrecipFront) {
      final approach = _incomingApproach;
      if (approach != null && approach.dbz >= 18) {
        return _calibrateUiDbz(math.min(approach.dbz, 40.0));
      }
      final nearby = _maxNearbyDbz;
      if (nearby != null && nearby >= 18) {
        return _calibrateUiDbz(math.min(nearby, 40.0));
      }
    }

    return kRadarMinDbzForUi;
  }

  /// Úzka prechádzajúca bunka — krátke echo v posledných snímkach, max 1 h v pásme.
  bool get _transientPassingCell {
    if (fromRainViewer) return false;
    if (precipNow && steadyOngoing) {
      if (_cellCrossingPin) return true;
      return false;
    }
    if (history.length < 2) return true;

    final recent = _recentHistory;
    var echoFrames = 0;
    for (final f in recent) {
      if (f.precipAtPoint || (f.peakDbz ?? 0) >= 20) echoFrames++;
    }
    if (echoFrames <= 3) return true;

    final peaks = recent.map((f) => f.peakDbz).whereType<double>().toList();
    if (peaks.length >= 2) {
      final last = peaks.last;
      final maxP = peaks.reduce(math.max);
      if (maxP >= 22 && last < 20) return true;
      if (peaks.length >= 3 && maxP - last >= 6) return true;
    }

    final tail = history.sublist(math.max(0, history.length - 2));
    if (tail.every((f) => !f.precipAtPoint && (f.peakDbz ?? 0) < 20) &&
        echoFrames <= 4 &&
        !_hasActiveNearbyEcho) {
      return true;
    }

    return false;
  }

  /// Echo v histórii slabne — kratšie okno zrážok.
  bool get _echoWeakening {
    if (history.length < 3) return false;
    final peaks = history.map((f) => f.peakDbz ?? f.dbz ?? 0).toList();
    if (peaks.length < 3) return false;
    final tail = peaks.sublist(peaks.length - 3);
    if (tail[2] <= tail[1] && tail[1] <= tail[0] && tail[0] - tail[2] >= 4) {
      return true;
    }
    final centerSeries = history.map((f) => f.dbz).whereType<double>().toList();
    if (centerSeries.length >= 3) {
      final c = centerSeries.sublist(centerSeries.length - 3);
      if (c[2] <= c[1] && c[1] <= c[0] && c[0] - c[2] >= 3) return true;
    }
    return false;
  }

  /// Konzervatívne trvanie — radšej kratšie okno ako natiahnutý dážď.
  int _capPassageHours(int hours, {required bool incoming}) {
    var h = hours.clamp(1, incoming ? 2 : 2);
    if (_transientPassingCell ||
        _nearbyEchoReceding ||
        _echoWeakening ||
        _echoPassingBy) {
      return 1;
    }
    if (!steadyOngoing && !_echoPersistedOrStrong) {
      h = math.min(h, 1);
    }
    if (incoming && !_steadyFrontIncoming) {
      h = math.min(h, 1);
    }
    return h;
  }

  /// Trvalá fronta — dlhšie okno len pri silnom ustáleneom echo.
  bool get _steadyFrontIncoming {
    if (!_echoPersistedOrStrong) return false;
    final intensity = incomingIntensityDbz ?? _maxNearbyDbz ?? 0;
    return intensity >= 32 && steadyOngoing;
  }

  /// Odhad: o koľko **minút** od teraz dorazí bunka (0 = čoskoro / už prší, -1 = neznáme).
  int _incomingArrivalMinutesFromNow(DateTime locNow) {
    if (precipNow || _confirmedRainAtPinCore || _trackerRainActiveAtPin) {
      return 0;
    }
    if (fromRainViewer) {
      return _rainViewerIncomingArrivalMinutes(locNow);
    }
    final raw = _incomingArrivalMinutesRaw();
    if (raw < 0) return -1;
    if (!_trackerIncomingConfirmed) return -1;
    return _applyIncomingEtaFloor(raw);
  }

  /// Bunka na mape je oddelená od pinu — suchý stred, echo v jednom smere (nie pri pine).
  bool get _incomingCellSeparatedFromPin {
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (center >= kRadarMinDbzPrecipNow) return false;
    if (center >= 14 && peak >= 18) return false;
    if (_echoEngulfsPin && center >= 12) return false;
    if (_rawPrecipAtPoint && center >= 10) return false;
    if (frame.coherentCorePx >= kRadarMinCoherentCorePx && center >= 14) {
      return false;
    }

    final gap = _incomingEchoGapDbz();
    if (gap < 12) return false;

    if (center < 10 && gap >= 14) return true;
    if (center < 12 &&
        gap >= 12 &&
        frame.coherentCorePx < kRadarMinCoherentCorePx) {
      return true;
    }
    if (center < 14 &&
        gap >= 16 &&
        _strongEchoDirections(frame, minDbz: 18) == 1) {
      return true;
    }
    return false;
  }

  double _incomingEchoGapDbz() {
    final frame = latest;
    if (frame == null) return 0;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    final approach = _incomingApproach;
    final cardinal = _maxCardinalDbz(frame);
    final approachDbz = approach?.dbz ?? cardinal;
    return math.max(peak - center, approachDbz - center);
  }

  /// ETA podľa vzdialenosti bunky na mape (medzera dBZ + sila echo).
  int _trackerVisualApproachMinutes() {
    final frame = latest;
    if (frame == null) return 25;
    final center = frame.dbz ?? 0;
    final nearby = _maxNearbyDbz ?? 0;
    final cardinal = _maxCardinalDbz(frame);
    final strength = math.max(nearby, cardinal);
    final gap = _incomingEchoGapDbz().clamp(4.0, 35.0);

    final gapFactor = strength >= 30
        ? 0.45
        : strength >= 26
            ? 0.55
            : strength >= 20
                ? 0.65
                : 0.8;
    var fromGap = (6 + gap * gapFactor).round();
    if (strength >= 28 && center < 10) fromGap -= 4;
    if (_echoClosingFromDirection) fromGap -= 3;

    final motion = _incomingEchoApproachMinutes();
    var mins = (_echoClosingFromDirection || _echoMovingTowardPinOrClosing)
        ? math.min(fromGap, motion)
        : ((fromGap * 0.6) + (motion * 0.4)).round();

    return mins.clamp(8, 55);
  }

  /// ETA z pohybu radaru + veľkosti bunky (medzera dBZ, intenzita echo).
  int _incomingEchoApproachMinutes() {
    final frame = latest;
    if (frame == null) return 35;
    final center = frame.dbz ?? 0;
    final gap = _incomingEchoGapDbz().clamp(4.0, 35.0);
    final nearby = _maxNearbyDbz ?? 0;
    final approach = _incomingApproach;
    final intensity = math.max(
      math.max(approach?.dbz ?? 0, nearby),
      frame.peakDbz ?? 0,
    );

    int? motionMins;

    final centerSlope = _centerDbzSlopePerMin;
    if (centerSlope != null &&
        centerSlope > 0.05 &&
        center < kRadarMinDbzPrecipNow) {
      final m = ((kRadarMinDbzPrecipNow - center) / centerSlope).ceil();
      if (m >= 8 && m <= 75) motionMins = m;
    }

    if (motionMins == null &&
        approach?.dir != null &&
        history.length >= 3) {
      final dirSlope = _directionalDbzSlopePerMin(approach!.dir!);
      if (dirSlope != null && dirSlope > 0.03) {
        final m = (gap / dirSlope).ceil();
        if (m >= 8 && m <= 75) motionMins = m;
      }
    }

    final gapFactor = intensity < 26 ? 0.85 : (intensity < 32 ? 1.0 : 1.3);
    final gapMins = (8 + gap * gapFactor).round();
    final minClamp = intensity >= 26 && center < 12 ? 8 : 10;

    if (motionMins != null) {
      if (intensity < 28) {
        return ((motionMins * 0.55) + (gapMins * 0.45)).round().clamp(
          minClamp,
          75,
        );
      }
      return ((motionMins * 0.65) + (gapMins * 0.35)).round().clamp(
        minClamp,
        75,
      );
    }
    return gapMins.clamp(minClamp, 75);
  }

  int _applyIncomingEtaFloor(int minutes) {
    if (minutes < 0) return minutes;
    if (!_incomingCellSeparatedFromPin) return minutes;
    final gap = _incomingEchoGapDbz();
    final strength = math.max(
      _maxNearbyDbz ?? 0,
      latest?.peakDbz ?? latest?.dbz ?? 0,
    );
    final minE = strength >= 28 && gap < 22
        ? (6 + gap * 0.35).round().clamp(6, 16)
        : (8 + gap * 0.38).round().clamp(8, 22);
    if (minutes < minE) return minE;
    if (gap < 18 && minutes > 50) {
      return _trackerVisualApproachMinutes();
    }
    return minutes.clamp(8, 75);
  }

  int _incomingArrivalMinutesRaw() {
    if (precipNow || _nearbyEchoReceding) return -1;
    if (_echoMovingAwayFromPin && !_significantEchoNearPin) return -1;
    if (_isIsolatedSpeckleNoise || _isDisorganizedMapNoise) return -1;

    if (!_significantEchoNearPin &&
        !_rainAtPinCore &&
        _distantEchoHeadingToPin) {
      return _distantIncomingMinutesEstimate();
    }

    final center = latest?.dbz ?? 0;
    if (_significantEchoNearPin && !_rainAtPinCore) {
      if (_incomingCellSeparatedFromPin) {
        if (!_echoMovingTowardPinOrClosing &&
            !_realDirectionalFrontApproaching &&
            !_echoClosingFromDirection) {
          return -1;
        }
        return _incomingEchoApproachMinutes();
      }
      if (_isScatteredSpeckleAtPin) {
        if (_realDirectionalFrontApproaching) {
          return _incomingEchoApproachMinutes();
        }
        return -1;
      }
      if (center >= kRadarMinDbzPrecipNow) return 0;
      if (center >= 16 &&
          (latest?.coherentCorePx ?? 0) >= kRadarMinCoherentCorePx) {
        return 0;
      }
      if ((latest?.peakDbz ?? 0) >= 32 &&
          (latest?.coherentPx14 ?? 0) >= kRadarMinCoherentAreaPx) {
        return 0;
      }
      if (center >= 14 && (latest?.peakDbz ?? 0) >= 18) return 0;
      return _applyIncomingEtaFloor(_defaultIncomingMinutes());
    }

    if (!_echoApproachingPin &&
        !_echoMovingTowardPinOrClosing &&
        !_approachingPrecipFront) {
      return -1;
    }

    if (!_echoPersistedOrStrong && !_approachingPrecipFront) return -1;

    final centerSlope = _centerDbzSlopePerMin;

    if (centerSlope != null && centerSlope > 0.08) {
      final need = kRadarMinDbzPrecipNow - center;
      if (need <= 0) return _rainAtPinNow ? 0 : _defaultIncomingMinutes();
      final mins = (need / centerSlope).ceil();
      final lo = _incomingCellSeparatedFromPin ? 15 : 5;
      return _applyIncomingEtaFloor(mins.clamp(lo, 75));
    }

    final approach = _incomingApproach;
    if (approach?.dir != null && history.length >= 3) {
      final dir = approach!.dir!;
      final oldest = history.first;
      final oldDir = oldest.dbzInDirection(dir) ?? approach.dbz;
      final newDir = approach.dbz;
      final spanMin = math.max(
        1.0,
        (history.last.unix - oldest.unix) / 60.0,
      );
      final dirSlope = (newDir - oldDir) / spanMin;
      if (newDir >= oldDir - 5 &&
          _echoMovingTowardPin &&
          dirSlope > 0.02) {
        if ((centerSlope ?? 0) >= 0.02) {
          final gap = (approach.dbz - center).clamp(6.0, 30.0);
          final rate = math.max(dirSlope, centerSlope ?? 0.02);
          final lo = _incomingCellSeparatedFromPin ? 15 : 10;
          return _applyIncomingEtaFloor((gap / rate).ceil().clamp(lo, 75));
        }
        return _incomingCellSeparatedFromPin
            ? _incomingEchoApproachMinutes()
            : _defaultIncomingMinutes();
      }
    } else if (_echoMovingTowardPin && (centerSlope ?? 0) > 0.02) {
      return _incomingCellSeparatedFromPin
          ? _incomingEchoApproachMinutes()
          : _defaultIncomingMinutes();
    }

    if (_approachingPrecipFront) {
      final nearby = _maxNearbyDbz ?? 0;
      final approachDbz = approach?.dbz ?? 0;
      if (nearby >= kRadarMinDbzDistantApproach ||
          approachDbz >= kRadarMinDbzDistantApproach) {
        return _distantIncomingMinutesEstimate();
      }
    }

    return -1;
  }

  /// ETA pre vzdialenú bunku — podľa smeru, rýchlosti a sily echo.
  int _distantIncomingMinutesEstimate() {
    final approach = _incomingApproach;
    final center = latest?.dbz ?? 0;

    if (approach?.dir != null && history.length >= 3) {
      final dir = approach!.dir!;
      final oldest = history.first;
      final oldDir = oldest.dbzInDirection(dir) ?? approach.dbz;
      final spanMin = math.max(
        1.0,
        (history.last.unix - oldest.unix) / 60.0,
      );
      final dirSlope = (approach.dbz - oldDir) / spanMin;
      final centerSlope = _centerDbzSlopePerMin;
      if (dirSlope > 0.02 || (centerSlope ?? 0) > 0.025) {
        final gap = (approach.dbz - center).clamp(6.0, 35.0);
        final rate = math.max(dirSlope, centerSlope ?? 0.025);
        final m = (gap / rate).ceil();
        if (m >= 8 && m <= 75) return m;
      }
    }

    return _incomingEchoApproachMinutes();
  }

  /// Fallback keď slope nestačí — podľa vzdialenosti/sily echo.
  int _defaultIncomingMinutes() {
    if (_incomingCellSeparatedFromPin || _trackerMapEchoVisible) {
      return _trackerVisualApproachMinutes();
    }
    final center = latest?.dbz ?? 0;
    final nearby = _maxNearbyDbz ?? 0;
    var mins = nearby >= 32
        ? 20
        : nearby >= 28
            ? 28
            : nearby >= 24
                ? 38
                : nearby >= kRadarMinDbzTrackerIncoming
                    ? 48
                    : 60;
    if (center < 12) mins += 5;
    return mins.clamp(10, 70);
  }

  DateTime _incomingArrivalAt(DateTime locNow) {
    final mins = _incomingArrivalMinutesFromNow(locNow);
    if (mins < 0) {
      return _trackerIncomingStartAt(locNow, _trackerSoftArrivalMinutes(locNow));
    }
    return _trackerIncomingStartAt(locNow, mins);
  }

  /// Začiatok príchodu — pri suchom pine vždy v budúcnosti, nie uplynutý čas.
  DateTime _trackerIncomingStartAt(DateTime locNow, int arrivalMins) {
    if (_trackerRainActiveAtPin) {
      return _roundLocalTimeToMinutes(locNow);
    }

    var mins = arrivalMins;
    if (mins < 0) {
      mins = _trackerSoftArrivalMinutes(locNow);
    }
    if (mins < 0 && _incomingCellSeparatedFromPin) {
      mins = _incomingEchoApproachMinutes();
    }
    if (mins < 0) {
      mins = 20;
    }

    if (_incomingCellSeparatedFromPin) {
      final est = math.min(
        _incomingEchoApproachMinutes(),
        _trackerVisualApproachMinutes(),
      );
      if (_echoClosingFromDirection || _echoMovingTowardPinOrClosing) {
        mins = math.min(mins, est);
      } else if (mins < 8 || mins > est + 18) {
        mins = ((mins + est) / 2).round();
      }
      mins = mins.clamp(8, 75);
    } else {
      mins = math.max(mins, 5);
    }

    final start = _roundLocalTimeToMinutes(locNow.add(Duration(minutes: mins)));
    final nowRounded = _roundLocalTimeToMinutes(locNow);
    if (!start.isAfter(nowRounded)) {
      return _roundLocalTimeToMinutes(
        nowRounded.add(const Duration(minutes: 10)),
      );
    }
    return start;
  }

  int _incomingPassageMinutes() =>
      _capPassageHours(_incomingPassageHours(), incoming: true) * 60;

  int _ongoingPassageMinutes() {
    if (!precipNow) return 0;
    if (_trailingDryAtPointFrames >= 1 || _precipDeparting) return 0;
    if (trendEndingAtPoint) return 0;
    if (_cellCrossingPin) return _passingCellMinutesRemaining();
    if (_transientPassingCell) return 45;

    final slope = _centerDbzSlopePerMin;
    final current = dbz ?? 22.0;
    if (slope != null && slope < -0.12) {
      final minsLeft = (current - 18) / (-slope);
      return minsLeft.ceil().clamp(10, 75);
    }

    return math.min(
      _capPassageHours(_ongoingPassageHours(), incoming: false) * 60,
      50,
    );
  }

  DateTime? _ongoingEndAt(DateTime locNow) {
    if (!precipNow && !_trackerRainActiveAtPin) return null;
    final mins = _trackerRemainingMinutesAtPin(locNow);
    if (mins <= 0) {
      return _roundLocalTimeToMinutes(
        locNow.add(const Duration(minutes: 8)),
      );
    }
    return _roundLocalTimeToMinutes(locNow.add(Duration(minutes: mins)));
  }

  /// Prvá hodina, od ktorej už radar neočakáva zrážky (pre orez ECMWF v pásme).
  DateTime _firstDryHourAfter(DateTime rainEndAt) {
    final hourStart = DateTime(
      rainEndAt.year,
      rainEndAt.month,
      rainEndAt.day,
      rainEndAt.hour,
    );
    if (rainEndAt.isAfter(hourStart)) {
      return hourStart.add(const Duration(hours: 1));
    }
    return hourStart;
  }

  /// Hodinový slot [slotHour, slotHour+1) sa prekrýva s radarovým oknom zrážok.
  bool _hourlySlotOverlapsPrecipWindow(
    DateTime slotHour,
    DateTime windowStart,
    DateTime windowEndExclusive,
  ) {
    final slotEnd = slotHour.add(const Duration(hours: 1));
    return slotEnd.isAfter(windowStart) &&
        slotHour.isBefore(windowEndExclusive);
  }

  /// Koniec aktuálnych zrážok podľa radaru (minútová presnosť).
  DateTime? ongoingRainEndAt(DateTime locNow) => _ongoingEndAt(locNow);

  /// Začiatok radarového okna zrážok (príchod bunky alebo aktuálna hodina).
  DateTime? precipWindowStartAt(DateTime locNow) {
    if (precipNow) return _localHourFloor(locNow);
    return _resolvedPrecipWindow(locNow)?.start;
  }

  /// Minútový koniec zrážok v okne — pre zlomok mm v hodinovom slote.
  DateTime? precipMinuteEndAt(DateTime locNow) => _resolvedPrecipMinuteEnd(locNow);

  /// Podiel hodiny [slotHour] pokrytej radarovým oknom (0–1).
  double precipHourFractionAt(DateTime slotHour, DateTime locNow) {
    if (fromRainViewer) {
      if (!authorizesPrecipAtLocalHour(slotHour, locNow)) return 0;
      if (slotHour == _localHourFloor(locNow) && precipNow) return 1.0;
      if (_rainViewerNowcastWetAtHour(slotHour, locNow)) return 0.9;
      if (precipNow) {
        final minuteEnd = _rainViewerStripRainMinuteEndAt(locNow);
        if (minuteEnd != null) {
          final nowHour = _localHourFloor(locNow);
          final rainStart = slotHour.isAfter(nowHour) ? slotHour : locNow;
          return _hourlySlotRainFraction(slotHour, rainStart, minuteEnd);
        }
      }
      if (incomingPrecip && !precipNow) {
        final arrivalMins = _rainViewerIncomingArrivalMinutes(locNow);
        if (arrivalMins > 0) {
          final arrivalAt = locNow.add(Duration(minutes: arrivalMins));
          final arrivalHour = _localHourFloor(arrivalAt);
          if (slotHour.isBefore(arrivalHour)) return 0.55;
        }
      }
      return 0;
    }
    if (precipNow) {
      final nowHour = _localHourFloor(locNow);
      if (slotHour == nowHour) return 1.0;
      final endAt = _ongoingEndAt(locNow);
      if (endAt == null) return 1.0;
      final rainStart = locNow.isAfter(slotHour) ? locNow : slotHour;
      return _hourlySlotRainFraction(slotHour, rainStart, endAt);
    }
    final uiWindow = _trackerUiPrecipWindow(locNow);
    if (uiWindow != null) {
      final rainStart =
          uiWindow.start.isAfter(slotHour) ? uiWindow.start : slotHour;
      return _hourlySlotRainFraction(
        slotHour,
        rainStart,
        uiWindow.minuteEnd,
      );
    }
    final window = _resolvedPrecipWindow(locNow);
    if (window == null) return 1.0;
    final endAt = _resolvedPrecipMinuteEnd(locNow);
    if (endAt == null) return 1.0;
    final rainStart =
        window.start.isAfter(slotHour) ? window.start : slotHour;
    return _hourlySlotRainFraction(slotHour, rainStart, endAt);
  }

  double _hourlySlotRainFraction(
    DateTime slotHour,
    DateTime rainStart,
    DateTime rainEnd,
  ) {
    final slotEnd = slotHour.add(const Duration(hours: 1));
    if (!rainEnd.isAfter(slotHour)) return 0;
    final effectiveStart = rainStart.isAfter(slotHour) ? rainStart : slotHour;
    if (!rainEnd.isAfter(effectiveStart)) return 0;
    final coveredMin = rainEnd.isAfter(slotEnd)
        ? slotEnd.difference(effectiveStart).inMinutes
        : rainEnd.difference(effectiveStart).inMinutes;
    return (coveredMin / 60.0).clamp(0.05, 1.0);
  }

  /// Ako dlho ešte potrvá dažď pri pinom / po príchode bunky [h].
  int _ongoingPassageHours() {
    if (!precipNow) return 0;
    if (_trailingDryAtPointFrames >= 1 || _precipDeparting) return 0;
    if (trendEndingAtPoint) return 0;
    if (_cellCrossingPin) return 0;
    if (_transientPassingCell) return 1;

    final slope = _centerDbzSlopePerMin;
    final current = dbz ?? 22.0;

    if (slope != null && slope < -0.12) {
      final minsLeft = (current - 18) / (-slope);
      return (minsLeft / 60).ceil().clamp(0, 2);
    }

    final endH = estimatedPrecipEndHours;
    if (endH != null) return _capPassageHours(endH.clamp(0, 2), incoming: false);

    if (!steadyOngoing) return 1;
    return _capPassageHours(1, incoming: false);
  }

  /// Trvanie zrážok po príchode blížiacej sa bunky [h].
  int _incomingPassageHours() {
    if (_nearbyEchoReceding) return 0;
    if (!_echoApproachingPin &&
        !_approachingPrecipFront &&
        !_echoMovingTowardPinOrClosing &&
        !_significantEchoNearPin) {
      return 0;
    }
    if (precipNow) return _ongoingPassageHours();

    final intensity = incomingIntensityDbz ?? (_maxNearbyDbz ?? 0);
    if (intensity < 20) return 0;

    if (_steadyFrontIncoming && intensity >= 34) {
      return _capPassageHours(2, incoming: true);
    }
    return _capPassageHours(1, incoming: true);
  }

  /// Aktívne okno zrážok pre 24 h pás (lokálne hodiny, [start, end)).
  ({DateTime start, DateTime end})? _activePrecipWindow(DateTime locNow) {
    final nowHour = _localHourFloor(locNow);

    if (fromRainViewer) {
      return _rainViewerPrecipWindow(locNow);
    }

    if (precipNow) {
      final endAt = _ongoingEndAt(locNow);
      if (endAt == null) return null;
      return (
        start: nowHour,
        end: _firstDryHourAfter(endAt),
      );
    }

    if (precipNow || _trackerPrecipAtPinForCard) {
      final endAt = _roundLocalTimeToMinutes(
        locNow.add(Duration(minutes: _trackerRemainingMinutesAtPin(locNow))),
      );
      return (
        start: _roundLocalTimeToMinutes(locNow),
        end: _firstDryHourAfter(endAt),
      );
    }

    if (_isRadarNoiseOnly && !_trackerMapEchoVisible) return null;

    if (_nearbyEchoReceding || _echoPassingBy || _precipBandPassedPin) {
      return null;
    }
    if (!incomingPrecip &&
        !_approachingPrecipFront &&
        !_significantEchoNearPin &&
        !_trackerSoftIncomingConfirmed) {
      return null;
    }

    var arrivalMins = _incomingArrivalMinutesFromNow(locNow);
    if (arrivalMins < 0 && _trackerSoftIncomingConfirmed) {
      arrivalMins = _trackerSoftArrivalMinutes(locNow);
    }
    if (arrivalMins < 0) return null;

    var passageH = _capPassageHours(_incomingPassageHours(), incoming: true);
    if (passageH <= 0 && _trackerSoftIncomingConfirmed) {
      passageH = 1;
    }
    if (passageH <= 0) return null;

    final arrivalAt = _incomingArrivalAt(locNow);
    final endAt = _roundLocalTimeToMinutes(
      arrivalAt.add(
        Duration(minutes: math.max(_incomingPassageMinutes(), 45)),
      ),
    );
    var rainEnd = _firstDryHourAfter(endAt);

    final maxPassage = _steadyFrontIncoming ? 2 : 1;
    final maxEndAt = _roundLocalTimeToMinutes(
      arrivalAt.add(Duration(hours: maxPassage)),
    );
    final maxDryHour = _firstDryHourAfter(maxEndAt);
    if (rainEnd.isAfter(maxDryHour)) rainEnd = maxDryHour;

    if (!rainEnd.isAfter(_localHourFloor(arrivalAt))) return null;
    return (start: arrivalAt, end: rainEnd);
  }

  /// Radarové okno zrážok — strict + soft príchod (sledovač aj 24 h pás).
  ({DateTime start, DateTime end})? _resolvedPrecipWindow(DateTime locNow) {
    if (fromRainViewer) return _rainViewerPrecipWindow(locNow);
    return _activePrecipWindow(locNow) ?? _softTrackerPrecipWindow(locNow);
  }

  ({DateTime start, DateTime end})? _softTrackerPrecipWindow(DateTime locNow) {
    if (_precipBandPassedPin) return null;
    if (!_trackerSoftIncomingConfirmed) return null;
    final arrivalMins = _trackerSoftArrivalMinutes(locNow);
    if (arrivalMins < 0) return null;

    final startAt = _trackerIncomingStartAt(locNow, arrivalMins);
    final passageMin = math.max(_incomingPassageMinutes(), 45);
    final endAt = _roundLocalTimeToMinutes(
      startAt.add(Duration(minutes: passageMin)),
    );
    final endHour = _firstDryHourAfter(endAt);
    if (!endHour.isAfter(_localHourFloor(startAt))) return null;
    return (start: startAt, end: endHour);
  }

  DateTime? _resolvedPrecipMinuteEnd(DateTime locNow) {
    if (fromRainViewer) {
      final nowcastDry = _rainViewerDryAtFromNowcast(locNow);
      if (nowcastDry != null) return nowcastDry;
    }
    if (precipNow || _trackerRainActiveAtPin) {
      return _roundLocalTimeToMinutes(
        locNow.add(Duration(minutes: _trackerRemainingMinutesAtPin(locNow))),
      );
    }
    final window = _resolvedPrecipWindow(locNow);
    if (window == null) return null;
    final passageMin = math.max(_incomingPassageMinutes(), 45);
    return _roundLocalTimeToMinutes(
      window.start.add(Duration(minutes: passageMin)),
    );
  }

  ({String? dir, double dbz})? get _incomingApproach {
    if (_confirmedRainAtPinCore || history.length < 2) return null;
    final latestFrame = latest;
    if (latestFrame == null) return null;
    if (latestFrame.precipAtPoint && _confirmedRainAtPinCore) return null;

    const dirs = ['n', 's', 'e', 'w'];
    String? bestDir;
    var bestDbz = 0.0;
    var secondDbz = 0.0;
    for (final dir in dirs) {
      final v = latestFrame.dbzInDirection(dir);
      if (v == null) continue;
      if (v > bestDbz) {
        secondDbz = bestDbz;
        bestDbz = v;
        bestDir = dir;
      } else if (v > secondDbz) {
        secondDbz = v;
      }
    }
    if (bestDir == null || bestDbz < kRadarMinDbzDistantApproach) return null;

    final spreadDirs = _strongEchoDirections(latestFrame, minDbz: 16);
    if (spreadDirs >= 3 &&
        bestDbz < kRadarMinDbzCoherentEcho &&
        bestDbz - secondDbz < 6) {
      return null;
    }
    if (bestDbz < kRadarMinDbzTrackerFront && bestDbz - secondDbz < 8) {
      return null;
    }

    return (dir: bestDir, dbz: bestDbz);
  }

  bool get steadyOngoing {
    if (history.length < 4) return precipNow;
    final tail = history.sublist(history.length - 4);
    return tail.where((f) => f.precipAtPoint).length >= 3;
  }

  /// Slabne / mizne — posledné snímky už nepotvrdzujú dážď.
  bool get trendEnding {
    if (history.isEmpty) return false;
    if (!precipNow) return true;

    var dryTail = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      if (!history[i].precip) {
        dryTail++;
      } else {
        break;
      }
    }
    if (dryTail >= 1) return true;

    if (history.length >= 3) {
      final tail = history.sublist(history.length - 3);
      final wetInTail = tail.where((f) => f.precip).length;
      if (wetInTail <= 1) return true;

      final dbzTail = tail.map((f) => f.dbz).whereType<double>().toList();
      if (dbzTail.length >= 3 &&
          dbzTail[2] <= dbzTail[1] &&
          dbzTail[1] <= dbzTail[0] &&
          dbzTail[0] - dbzTail[2] >= 4) {
        return true;
      }
    }
    return false;
  }

  /// Zrážková bunka odchádza — za bodom ešte silnejší echo, vpred sucho/slabo.
  bool get _precipDeparting => _precipDepartingRaw && precipNow;

  bool get _precipDepartingRaw {
    if (!_rawPrecipAtPoint) return false;
    return _precipDepartingCardinalOnly();
  }

  /// Odchádzajúce echo — len kardinálne smery, bez [_echoDepartingFromPin] (stack overflow).
  bool _precipDepartingCardinalOnly() {
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;

    bool leaving(double? upwind, double? downwind) =>
        upwind != null &&
        upwind >= 20 &&
        (downwind == null || downwind < 14) &&
        center <= upwind - 4;

    return leaving(frame.westDbz, frame.eastDbz) ||
        leaving(frame.southDbz, frame.northDbz) ||
        leaving(frame.eastDbz, frame.westDbz) ||
        leaving(frame.northDbz, frame.southDbz);
  }

  /// Odhad: o koľko hodín od **teraz** zrážky skončia.
  int? get estimatedPrecipEndHours => _estimatePrecipEndHours();

  /// Prvá **lokálna** hodina ( začiatok ), od ktorej má byť sucho — null = neorezávaj ECMWF.
  DateTime? estimatedDryFromLocalTime(DateTime locNow) {
    if (!eligible || history.isEmpty) return null;

    DateTime dryFromNextHour() => DateTime(
          locNow.year,
          locNow.month,
          locNow.day,
          locNow.hour,
        ).add(const Duration(hours: 1));

    DateTime dryFromHours(int h) => DateTime(
          locNow.year,
          locNow.month,
          locNow.day,
          locNow.hour,
        ).add(Duration(hours: h + 1));

    // Radar už suchý — zrážky skončili, orez hneď od ďalšej hodiny.
    if (!precipNow && !incomingPrecip && _hadRecentRainAtPoint) {
      return dryFromNextHour();
    }

    if (!precipNow && _nearbyEchoReceding) {
      return dryFromNextHour();
    }

    // Radar suchý bez blížiacej sa bunky — neorezávaj celý ECMWF pás.
    if (!precipNow &&
        !incomingPrecip &&
        !_approachingPrecipFront &&
        !_significantEchoNearPin) {
      return null;
    }

    if (!precipNow) return null;

    if (_trailingDryAtPointFrames >= 1 && _hadRecentRainAtPoint) {
      return dryFromNextHour();
    }

    if (_precipDeparting && _hadRecentRainAtPoint) {
      return dryFromNextHour();
    }

    if (trendEndingAtPoint) {
      return dryFromNextHour();
    }

    final endAt = _ongoingEndAt(locNow);
    if (endAt != null) {
      return _firstDryHourAfter(endAt);
    }

    final passage = _ongoingPassageHours();
    if (passage <= 0) return dryFromNextHour();
    if (passage <= 2) return dryFromHours(passage - 1);

    // Prechodná bunka (nie trvalá fronta) — ECMWF nesmie natiahnuť dážď na celé hodiny modelu.
    if (precipNow && !steadyOngoing && !incomingPrecip) {
      final wetFrames = _recentHistory.where((f) => f.precipAtPoint).length;
      if (wetFrames <= 3) return dryFromNextHour();
      if (wetFrames <= 4) return dryFromHours(1);
    }

    return null;
  }

  /// Kde môže 24 h pás orezať ECMWF — len blízke hodiny / potvrdený koniec, nie celý model.
  DateTime? hourlyStripEcmwfTrimDryFromHour(DateTime locNow) {
    if (!eligible || history.isEmpty) return null;

    final nowHour = _localHourFloor(locNow);
    DateTime dryUntilHours(int h) => nowHour.add(Duration(hours: h));

    if (_precipBandPassedPin) return nowHour;

    if (fromRainViewer && precipNow) {
      return rainViewerNearTermWetEndExclusive(locNow);
    }

    if (_trackerRainActiveAtPin || _radarPrecipAlreadyAtPin) {
      final endAt = _resolvedPrecipMinuteEnd(locNow);
      if (endAt != null) return _firstDryHourAfter(endAt);
      if (_echoDepartingFromPin || _nearbyEchoReceding) {
        return dryUntilHours(1);
      }
    }

    if (precipNow) {
      final endAt = _ongoingEndAt(locNow);
      if (endAt != null) return _firstDryHourAfter(endAt);
      if (trendEndingAtPoint || (_precipDeparting && _hadRecentRainAtPoint)) {
        return dryUntilHours(1);
      }
      final passage = _ongoingPassageHours();
      if (passage <= 0) return dryUntilHours(1);
      if (passage <= 2) return nowHour.add(Duration(hours: passage));
      if (!steadyOngoing && !incomingPrecip) {
        final wetFrames = _recentHistory.where((f) => f.precipAtPoint).length;
        if (wetFrames <= 3) return dryUntilHours(1);
        if (wetFrames <= 4) return dryUntilHours(2);
      }
      return null;
    }

    if (incomingPrecip ||
        _approachingPrecipFront ||
        _significantEchoNearPin ||
        _trackerSoftIncomingConfirmed) {
      final window = _resolvedPrecipWindow(locNow);
      if (window != null) return window.end;
    }

    if (!precipNow && !incomingPrecip && _hadRecentRainAtPoint) {
      return nowHour;
    }
    if (!precipNow && _nearbyEchoReceding) {
      return nowHour;
    }

    // Suchý radar bez potvrdeného príchodu — ECMWF nesmie meniť najbližšie hodiny.
    if (!precipNow &&
        !incomingPrecip &&
        !_trackerUiAuthorizesStripPrecip(locNow)) {
      return nowHour;
    }

    return null;
  }

  /// Radar-only / orez: môže slot ukazovať zrážky?
  bool authorizesPrecipAtLocalHour(DateTime slotHour, DateTime locNow) {
    if (_authorizesPrecipDepthGuard) return false;
    _authorizesPrecipDepthGuard = true;
    try {
      return _authorizesPrecipAtLocalHourImpl(slotHour, locNow);
    } finally {
      _authorizesPrecipDepthGuard = false;
    }
  }

  bool _authorizesPrecipAtLocalHourImpl(DateTime slotHour, DateTime locNow) {
    if (!eligible) return false;
    if (_precipBandPassedPin && !precipNow) {
      if (!fromRainViewer ||
          (!_rainViewerNearbyPrecipField &&
              !_rainViewerTrajectoryIncoming &&
              !incomingPrecip)) {
        return false;
      }
    }

    final nowHour = DateTime(
      locNow.year,
      locNow.month,
      locNow.day,
      locNow.hour,
    );
    if (slotHour.isBefore(nowHour)) return false;

    if (fromRainViewer) {
      if (slotHour == nowHour && precipNow) return true;

      if (precipNow) {
        final minuteEnd = _rainViewerStripRainMinuteEndAt(locNow);
        if (minuteEnd != null &&
            _hourlySlotOverlapsPrecipWindow(
              slotHour,
              nowHour,
              _firstDryHourAfter(minuteEnd),
            )) {
          return true;
        }
        return _rainViewerNowcastWetAtHour(slotHour, locNow);
      }

      final window = _rainViewerPrecipWindow(locNow);
      if (window != null) {
        return _hourlySlotOverlapsPrecipWindow(
          slotHour,
          window.start,
          window.end,
        );
      }

      return false;
    }

    if (precipNow || _trackerPrecipAtPinForCard) {
      if (slotHour == nowHour) return true;
      final endAt = _ongoingEndAt(locNow) ??
          _resolvedPrecipMinuteEnd(locNow);
      if (endAt == null) return false;
      return _hourlySlotOverlapsPrecipWindow(
        slotHour,
        nowHour,
        _firstDryHourAfter(endAt),
      );
    }

    final uiWindow = _trackerUiPrecipWindow(locNow);
    if (uiWindow != null &&
        _trackerIncomingConfirmed &&
        _trackerUiAuthorizesStripPrecip(locNow)) {
      return _hourlySlotOverlapsPrecipWindow(
        slotHour,
        uiWindow.start,
        _firstDryHourAfter(uiWindow.minuteEnd),
      );
    }

    return false;
  }

  /// Suchý RainViewer radar — ECMWF phantom dážď v najbližších hodinách zrušiť.
  bool suppressEcmwfStripPrecipAtHour(DateTime slotHour, DateTime locNow) {
    if (!radarOverridesDryEcmwfNearTerm) return false;
    if (incomingPrecip) return false;
    if (authorizesPrecipAtLocalHour(slotHour, locNow)) return false;

    final nowHour = _localHourFloor(locNow);
    if (slotHour.isBefore(nowHour)) return false;

    final trimStop = radarEcmwfTrimHardStopLocal(locNow, this);
    if (slotHour.isAfter(trimStop)) return false;

    final dryFrom = hourlyStripEcmwfTrimDryFromHour(locNow);
    if (dryFrom != null && !slotHour.isBefore(dryFrom)) return true;

    if (!precipNow && !incomingPrecip && !_trackerUiAuthorizesStripPrecip(locNow)) {
      return true;
    }

    final hoursAhead = slotHour.difference(nowHour).inHours;
    return hoursAhead <= _kRadarEcmwfTrimMaxHoursWhenDry;
  }

  int? _estimatePrecipEndHours() {
    if (!eligible || history.isEmpty) return null;

    if (!precipNow) {
      if (_hadRecentRainAtPoint) return 0;
      return null;
    }

    if (trendEndingAtPoint) return 0;

    if (_precipDeparting) return 0;

    if (_trailingDryAtPointFrames >= 1) return 0;

    final slope = _centerDbzSlopePerMin;
    final current = dbz ?? 22.0;
    if (slope != null && slope < -0.12) {
      final minsLeft = (current - 18) / (-slope);
      return (minsLeft / 60).ceil().clamp(0, 2);
    }

    if (precipNow && history.length >= 5) {
      final recent = history.sublist(history.length - 3);
      final olderStart = math.max(0, history.length - 6);
      final older = history.sublist(olderStart, history.length - 3);
      final recentWet = recent.where((f) => f.precipAtPoint).length;
      final olderWet = older.where((f) => f.precipAtPoint).length;
      if (olderWet >= 2 && recentWet <= 1) return 0;
    }

    if (precipNow) {
      final currentDbz = dbz;
      if (currentDbz != null && currentDbz < 25) {
        final wetTail = history
            .sublist(math.max(0, history.length - 4))
            .where((f) => f.precipAtPoint)
            .length;
        if (wetTail <= 2) return 0;
        if (wetTail == 3 && currentDbz < 22) return 1;
      }
    }

    final dbzSeries = history.map((f) => f.dbz).whereType<double>().toList();
    if (dbzSeries.length >= 4) {
      final split = dbzSeries.length ~/ 2;
      final older = dbzSeries.sublist(0, split);
      final recent = dbzSeries.sublist(split);
      final oldAvg = older.reduce((a, b) => a + b) / older.length;
      final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
      final drop = oldAvg - recentAvg;

      if (drop >= 10) return 0;
      if (drop >= 5) return 1;
      if (drop >= 2) return 2;

      final peak = dbzSeries.reduce(math.max);
      final latest = dbzSeries.last;
      if (peak - latest >= 8 && precipNow) return 1;
    }

    if (dbzSeries.length >= 3) {
      final last3 = dbzSeries.sublist(dbzSeries.length - 3);
      if (last3[2] <= last3[1] && last3[1] <= last3[0]) {
        final perFrame = (last3[0] - last3[2]) / 2;
        if (perFrame >= 4) return 0;
        if (perFrame >= 2) return 1;
        if (perFrame >= 0.5) return 2;
      }
    }

    if (history.length >= 4) {
      final prev = history.sublist(history.length - 4, history.length - 2);
      final last = history.sublist(history.length - 2);
      if (prev.every((f) => f.precipAtPoint) && last.any((f) => !f.precipAtPoint)) {
        return 1;
      }
    }

    final currentDbz = dbz;
    if (currentDbz != null && currentDbz < 20 && precipNow) return 1;

    return null;
  }

  bool get incomingPrecip => _computeIncomingPrecip();

  bool _computeIncomingPrecip() {
    if (precipNow || _confirmedRainAtPinCore) return true;
    if (_skipCmaxNoiseFilters && fromRainViewer) {
      return nowcastHistory.where((f) => _rainViewerFrameWetAtPin(f)).length >=
          2;
    }
    if (_trackerNearbyApproachLikely) return true;
    if (_echoApproachingPin || _echoClosingFromDirection) return true;
    if (_precipBandPassedPin) return false;
    if (history.length < 2) return false;
    if (_echoClearlyOffPath || _isDisorganizedMapNoise) return false;
    if (_isRadarNoiseOnly && !_trackerMapEchoVisible) return false;
    if (_isScatteredSpeckleAtPin && !_realDirectionalFrontApproaching) {
      return false;
    }
    return _trackerSoftIncomingConfirmed;
  }

  double get _trackerIntensityDbz {
    if (precipNow || _trackerRainActiveAtPin || _rainAtPinNow) {
      return precipIntensityDbz;
    }
    return incomingIntensityDbz ??
        math.max(_maxNearbyDbz ?? kRadarMinDbzForUi, stripDisplayDbz);
  }

  /// Rovnaké minútové okno ako karta sledovača — 24 h pás a denné časti dňa.
  bool _trackerUiAuthorizesStripPrecip(DateTime locNow) {
    if (fromRainViewer) {
      return precipNow || rainViewerPredictsPrecipAt(locNow);
    }
    if (_trackerRainActiveAtPin || _radarPrecipAlreadyAtPin) return true;
    if (!_trackerIncomingConfirmed) return false;
    if (_trackerNearbyApproachLikely) return true;
    if (!_trackerSoftIncomingConfirmed) return false;
    final dbz = math.max(
      _trackerIntensityDbz,
      incomingIntensityDbz ?? _maxNearbyDbz ?? 0,
    );
    return dbz >= kRadarMinDbzForUi;
  }

  ({DateTime start, DateTime minuteEnd})? _trackerUiPrecipWindow(
    DateTime locNow,
  ) {
    if (fromRainViewer) {
      if (_precipBandPassedPin && !precipNow && !_trackerRainActiveAtPinAt(locNow)) {
        return null;
      }
      if (_trackerRainActiveAtPinAt(locNow)) {
        final endAt = _roundLocalTimeToMinutes(
          locNow.add(Duration(minutes: _trackerRemainingMinutesAtPin(locNow))),
        );
        return (
          start: _roundLocalTimeToMinutes(locNow),
          minuteEnd: endAt,
        );
      }
      if (_rainViewerFutureWetAtPin(locNow) ||
          _rainViewerIncomingLikelyAt(locNow)) {
        final arrivalMins = _rainViewerIncomingArrivalMinutes(locNow);
        if (arrivalMins >= 0) {
          final startAt = _trackerIncomingStartAt(locNow, arrivalMins);
          final dryAt = _rainViewerDryAtFromNowcast(locNow);
          final endAt = _roundLocalTimeToMinutes(
            dryAt ?? startAt.add(const Duration(minutes: 45)),
          );
          if (endAt.isAfter(startAt)) {
            return (start: startAt, minuteEnd: endAt);
          }
        }
      }
      if (_rainViewerNearbyPrecipField) {
        final arrivalMins = _rainViewerIncomingArrivalMinutes(locNow);
        if (arrivalMins >= 0 && arrivalMins <= 90) {
          final startAt = _trackerIncomingStartAt(locNow, arrivalMins);
          final endAt = _roundLocalTimeToMinutes(
            startAt.add(const Duration(minutes: 45)),
          );
          if (endAt.isAfter(startAt)) {
            return (start: startAt, minuteEnd: endAt);
          }
        }
      }
      return null;
    }

    if (_precipBandPassedPin &&
        !precipNow &&
        !_trackerRainActiveAtPin) {
      return null;
    }

    if (_trackerRainActiveAtPin) {
      final endAt = _roundLocalTimeToMinutes(
        locNow.add(Duration(minutes: _trackerRemainingMinutesAtPin(locNow))),
      );
      return (
        start: _roundLocalTimeToMinutes(locNow),
        minuteEnd: endAt,
      );
    }

    final window = _resolvedPrecipWindow(locNow);
    DateTime? uiStart;
    DateTime? uiEnd;

    if (window != null && _trackerSoftIncomingConfirmed) {
      final minuteEnd = _resolvedPrecipMinuteEnd(locNow);
      if (minuteEnd != null) {
        uiStart = window.start;
        uiEnd = minuteEnd;
      }
    } else if (_trackerNearbyApproachLikely && _trackerIncomingConfirmed) {
      final arrivalMins = _trackerSoftArrivalMinutes(locNow);
      if (arrivalMins >= 0) {
        uiStart = _trackerIncomingStartAt(locNow, arrivalMins);
        uiEnd = _roundLocalTimeToMinutes(
          uiStart.add(const Duration(minutes: 45)),
        );
      }
    }

    if (uiStart == null || uiEnd == null) return null;

    var startAt = uiStart;
    var endAt = uiEnd;
    final nowRounded = _roundLocalTimeToMinutes(locNow);
    final recomputed =
        _trackerIncomingStartAt(locNow, _trackerSoftArrivalMinutes(locNow));
    if (!startAt.isAfter(nowRounded)) {
      startAt = recomputed;
    } else if (_incomingCellSeparatedFromPin && recomputed.isAfter(startAt)) {
      startAt = recomputed;
    }
    if (window != null && startAt.isAfter(window.start)) {
      final passageMin =
          math.max(endAt.difference(window.start).inMinutes, 45);
      endAt = _roundLocalTimeToMinutes(
        startAt.add(Duration(minutes: passageMin)),
      );
    }

    if (!endAt.isAfter(startAt)) return null;
    return (start: startAt, minuteEnd: endAt);
  }

  RadarPrecipTrackerInfo _buildActiveTrackerInfo(
    DateTime locNow, {
    required double intensityDbz,
    required bool snow,
  }) {
    final headline = _trackerActiveHeadline(intensityDbz, snow: snow);
    final iconCode = _wmoFromRadarIntensity(intensityDbz, snow: snow);
    final rawRemaining = _trackerRemainingMinutesAtPin(locNow).clamp(3, 180);
    final endAt = _trackerDisplayEndTime(
      locNow.add(Duration(minutes: rawRemaining)),
    );
    final remainingMin =
        _trackerDisplayRemainingMinutes(endAt, locNow).clamp(1, 180);
    final endLabel = _trackerClockLabel(endAt);
    final detail = _trackerLastsDetail(
      snow: snow,
      endLabel: endLabel,
      approxMinutes: remainingMin < 55 ? remainingMin : null,
      approxOneHour: remainingMin >= 52 && remainingMin <= 75,
    );

    return RadarPrecipTrackerInfo(
      phase: RadarPrecipTrackerPhase.active,
      title: kRadarTrackerCardTitle,
      detail: _radarTrackerCardDetail(headline, detail),
      iconCode: iconCode,
      startLocal: locNow,
      endLocal: endAt,
    );
  }

  RadarPrecipTrackerInfo _buildIncomingTrackerInfo(
    DateTime locNow, {
    required ({DateTime start, DateTime minuteEnd}) window,
    required double intensityDbz,
    required bool snow,
    bool forceIncomingPhase = false,
  }) {
    final startAt = window.start;
    final endAt = window.minuteEnd;
    final roundedNow = _roundLocalTimeToMinutes(locNow);
    final atPinNow = !forceIncomingPhase &&
        (_trackerRainActiveAtPinAt(locNow) ||
            precipNow ||
            !startAt.isAfter(roundedNow));
    final startLabel = _trackerClockLabel(startAt);
    final endLabel = _trackerClockLabel(endAt);
    final durationMin = endAt.difference(startAt).inMinutes.clamp(15, 180);
    final iconCode = _wmoFromRadarIntensity(intensityDbz, snow: snow);
    final minsToStart =
        startAt.difference(_roundLocalTimeToMinutes(locNow)).inMinutes;

    final String detail;
    if (atPinNow) {
      final remainingMin = endAt.difference(locNow).inMinutes.clamp(5, 180);
      detail = _trackerLastsDetail(
        snow: snow,
        endLabel: endLabel,
        approxMinutes: remainingMin < 55 ? remainingMin : null,
      );
    } else {
      detail = _trackerIncomingTimingDetail(
        snow: snow,
        startLabel: startLabel,
        endLabel: endLabel,
        minsToStart: minsToStart,
        durationMin: durationMin,
      );
    }

    final phase = atPinNow
        ? RadarPrecipTrackerPhase.active
        : RadarPrecipTrackerPhase.incoming;
    final headline = _incomingTrackerStatusTitle(
      atPinNow: atPinNow,
      snow: snow,
      intensityDbz: intensityDbz,
    );

    return RadarPrecipTrackerInfo(
      phase: phase,
      title: kRadarTrackerCardTitle,
      detail: _radarTrackerCardDetail(headline, detail),
      iconCode: iconCode,
      startLocal: startAt,
      endLocal: endAt,
    );
  }

  DateTime _localHourFloor(DateTime locNow) => DateTime(
        locNow.year,
        locNow.month,
        locNow.day,
        locNow.hour,
      );

  /// ECMWF hodina so zrážkami v horizonte sledovača (zarovnané s 24 h pásmom).
  ({DateTime start, DateTime minuteEnd})? _ecmwfWetWindowWithinTrackerHorizon(
    DateTime locNow, {
    HourlyForecast? ecmwfHourly,
    int? utcOffsetSeconds,
  }) {
    if (ecmwfHourly == null || ecmwfHourly.time.isEmpty) return null;
    final until = locNow.add(const Duration(hours: kRadarTrackerHorizonHours));
    ({DateTime start, DateTime minuteEnd})? best;
    for (var i = 0; i < ecmwfHourly.time.length; i++) {
      final parsed = DateTime.tryParse(ecmwfHourly.time[i]);
      if (parsed == null) continue;
      final localT = utcOffsetSeconds != null
          ? parsed.add(Duration(seconds: utcOffsetSeconds))
          : parsed;
      final slotStart = DateTime(
        localT.year,
        localT.month,
        localT.day,
        localT.hour,
      );
      final slotEnd = slotStart.add(const Duration(hours: 1));
      if (slotEnd.isBefore(locNow) || slotStart.isAfter(until)) continue;
      final mm = _ecmwfHourlyPrecipMm(ecmwfHourly, i);
      final prob = _ecmwfHourlyPrecipProb(ecmwfHourly, i);
      if (!ecmwfHourPrecipShowsInUi(mm: mm, prob: prob)) continue;
      if (suppressEcmwfStripPrecipAtHour(slotStart, locNow)) continue;
      final start = slotStart.isBefore(locNow)
          ? _roundLocalTimeToMinutes(locNow)
          : slotStart;
      final window = (start: start, minuteEnd: slotEnd);
      if (best == null || window.start.isBefore(best.start)) {
        best = window;
      }
    }
    return best;
  }

  bool _wetExpectedInTrackerHorizon(
    DateTime locNow, {
    HourlyForecast? ecmwfHourly,
    int? utcOffsetSeconds,
  }) {
    if (precipNow || _trackerRainActiveAtPin) return true;
    if (_helkorTrackerPrecipSignal) return true;
    if (fromRainViewer) {
      if (_rainViewerTrackerPrecipSignalAt(locNow)) return true;
      final nowHour = _localHourFloor(locNow);
      for (var h = 0; h <= kRadarTrackerHorizonHours; h++) {
        final slot = nowHour.add(Duration(hours: h));
        if (authorizesPrecipAtLocalHour(slot, locNow)) return true;
      }
      return _ecmwfWetWindowWithinTrackerHorizon(
            locNow,
            ecmwfHourly: ecmwfHourly,
            utcOffsetSeconds: utcOffsetSeconds,
          ) !=
          null;
    }
    if (_trackerMapEchoVisible) return true;
    if (incomingPrecip) return true;
    final nowHour = _localHourFloor(locNow);
    for (var h = 0; h <= kRadarTrackerHorizonHours; h++) {
      final slot = nowHour.add(Duration(hours: h));
      if (authorizesPrecipAtLocalHour(slot, locNow)) return true;
    }
    return _ecmwfWetWindowWithinTrackerHorizon(
          locNow,
          ecmwfHourly: ecmwfHourly,
          utcOffsetSeconds: utcOffsetSeconds,
        ) !=
        null;
  }

  RadarPrecipTrackerInfo _trackerInfoAvoidingFalseDry(
    DateTime locNow, {
    required bool snow,
    required double intensityDbz,
    double? cloudCoverPercent,
    HourlyForecast? ecmwfHourly,
    int? utcOffsetSeconds,
  }) {
    if (_trackerRainActiveAtPinAt(locNow)) {
      return _buildActiveTrackerInfo(
        locNow,
        intensityDbz: intensityDbz,
        snow: snow,
      );
    }

    if (!fromRainViewer) {
      final nowHour = _localHourFloor(locNow);
      for (var h = 0; h <= kRadarTrackerHorizonHours; h++) {
        final slot = nowHour.add(Duration(hours: h));
        if (!authorizesPrecipAtLocalHour(slot, locNow)) continue;
        final start =
            slot.isBefore(locNow) ? _roundLocalTimeToMinutes(locNow) : slot;
        final endAt = slot.add(const Duration(hours: 1));
        return _buildIncomingTrackerInfo(
          locNow,
          window: (start: start, minuteEnd: endAt),
          intensityDbz: math.max(intensityDbz, kRainViewerLegendMinDbz),
          snow: snow,
          forceIncomingPhase: !slot.isAfter(locNow),
        );
      }

      final ecmwfWindow = _ecmwfWetWindowWithinTrackerHorizon(
        locNow,
        ecmwfHourly: ecmwfHourly,
        utcOffsetSeconds: utcOffsetSeconds,
      );
      if (ecmwfWindow != null) {
        return _buildIncomingTrackerInfo(
          locNow,
          window: ecmwfWindow,
          intensityDbz: math.max(intensityDbz, kRainViewerLegendMinDbz),
          snow: snow,
          forceIncomingPhase: true,
        );
      }
    } else {
      final window = _trackerUiPrecipWindow(locNow);
      if (window != null && _trackerIncomingConfirmedAt(locNow)) {
        final dbz = rainViewerDbzForUi(
          math.max(intensityDbz, _rainViewerApproachDbz),
        );
        return _buildIncomingTrackerInfo(
          locNow,
          window: window,
          intensityDbz: math.max(dbz, kRainViewerLegendMinDbz),
          snow: snow,
        );
      }
    }

    if (_rainViewerTrackerPrecipSignalAt(locNow) || _helkorTrackerPrecipSignal) {
      var dbz = fromRainViewer
          ? rainViewerDbzForUi(
              math.max(intensityDbz, _maxNearbyDbz ?? intensityDbz),
            )
          : math.max(intensityDbz, kRadarMinDbzForUi);
      if (_helkorTrackerPrecipSignal) {
        dbz = math.max(dbz, _helkorIntensityDbz);
      }
      final detail = _helkorTrackerPrecipSignal &&
              !(fromRainViewer && _rainViewerTrackerPrecipSignalAt(locNow))
          ? 'Meteo radar zachytáva zrážky v okolí — sledujem vývoj.'
          : 'Radar zachytáva zrážky v okolí — sledujem vývoj.';
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.watching,
        title: kRadarTrackerCardTitle,
        detail: detail,
        iconCode: _wmoFromRadarIntensity(dbz, snow: snow),
      );
    }

    return RadarPrecipTrackerInfo(
      phase: RadarPrecipTrackerPhase.idle,
      title: kRadarTrackerCardTitle,
      detail: kRadarTrackerDryHorizonDetail,
      iconCode: skyWmoFromCloudCover(cloudCoverPercent),
    );
  }

  /// Karta sledovača — vždy keď je radar dostupný; pri suchu stav „sucho podľa radaru“.
  RadarPrecipTrackerInfo precipTrackerInfo(
    DateTime locNow, {
    double? tempC,
    double? cloudCoverPercent,
    HourlyForecast? ecmwfHourly,
    int? utcOffsetSeconds,
  }) {
    if (!eligible || history.isEmpty) {
      return _monitoringTrackerInfo(
        locNow,
        cloudCoverPercent: cloudCoverPercent,
        snow: _radarSnowLikely(tempC: tempC),
        intensityDbz: kRadarMinDbzForUi,
        ecmwfHourly: ecmwfHourly,
        utcOffsetSeconds: utcOffsetSeconds,
      );
    }

    if ((_isRadarNoiseOnly ||
            _staticDistantCellNearMap ||
            _isDisorganizedMapNoise) &&
        !_trackerMapEchoVisible &&
        !_trackerRainActiveAtPin) {
      resetRadarTrackerStabilizer(clearHardEndLock: false);
      if (_wetExpectedInTrackerHorizon(
        locNow,
        ecmwfHourly: ecmwfHourly,
        utcOffsetSeconds: utcOffsetSeconds,
      )) {
        return _trackerInfoAvoidingFalseDry(
          locNow,
          snow: _radarSnowLikely(tempC: tempC),
          intensityDbz: kRadarMinDbzForUi,
          cloudCoverPercent: cloudCoverPercent,
          ecmwfHourly: ecmwfHourly,
          utcOffsetSeconds: utcOffsetSeconds,
        );
      }
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.idle,
        title: kRadarTrackerCardTitle,
        detail: kRadarTrackerDryHorizonDetail,
        iconCode: skyWmoFromCloudCover(cloudCoverPercent),
      );
    }

    final snow = _radarSnowLikely(tempC: tempC);
    final intensityDbz = _trackerIntensityDbz;

    // Mrholenie / dážď pri pine — pred obchvatom, aby sa nezobrazilo sucho.
    if (_trackerRainActiveAtPinAt(locNow) ||
        (fromRainViewer &&
            latest != null &&
            _rainViewerLocalEchoAtPin(latest!))) {
      return _buildActiveTrackerInfo(
        locNow,
        intensityDbz: intensityDbz,
        snow: snow,
      );
    }

    if (fromRainViewer &&
        _rainViewerEchoBypassesPinAt(locNow) &&
        !_helkorTrackerPrecipSignal) {
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.idle,
        title: kRadarTrackerCardTitle,
        detail: kRadarTrackerDryHorizonDetail,
        iconCode: skyWmoFromCloudCover(cloudCoverPercent),
      );
    }

    if (_precipBandPassedPin) {
      return _monitoringTrackerInfo(
        locNow,
        cloudCoverPercent: cloudCoverPercent,
        snow: snow,
        intensityDbz: intensityDbz,
        ecmwfHourly: ecmwfHourly,
        utcOffsetSeconds: utcOffsetSeconds,
      );
    }

    // Prší priamo nad pinom — aj mrholenie (zelené na mape).
    if (_trackerRainActiveAtPinAt(locNow)) {
      return _buildActiveTrackerInfo(
        locNow,
        intensityDbz: intensityDbz,
        snow: snow,
      );
    }

    final effectiveDbz = math.max(
      intensityDbz,
      incomingIntensityDbz ?? _maxNearbyDbz ?? 0,
    );
    final uiWindow = _trackerUiPrecipWindow(locNow);
    if (uiWindow != null &&
        !_trackerRainActiveAtPinAt(locNow) &&
        _trackerIncomingConfirmedAt(locNow) &&
        _trackerUiAuthorizesStripPrecip(locNow)) {
      final roundedNow = _roundLocalTimeToMinutes(locNow);
      final shouldBeActive = _trackerRainActiveAtPinAt(locNow) ||
          precipNow ||
          !uiWindow.start.isAfter(roundedNow);
      if (shouldBeActive) {
        return _buildActiveTrackerInfo(
          locNow,
          intensityDbz: math.max(effectiveDbz, kRadarMinDbzForUi),
          snow: snow,
        );
      }
      return _buildIncomingTrackerInfo(
        locNow,
        window: uiWindow,
        intensityDbz: math.max(effectiveDbz, kRadarMinDbzForUi),
        snow: snow,
      );
    }

    return _monitoringTrackerInfo(
      locNow,
      cloudCoverPercent: cloudCoverPercent,
      snow: snow,
      intensityDbz: intensityDbz,
      ecmwfHourly: ecmwfHourly,
      utcOffsetSeconds: utcOffsetSeconds,
    );
  }

  /// Sucho / neisté echo — vždy konkrétna správa, nie prázdne „sledujem“.
  RadarPrecipTrackerInfo _monitoringTrackerInfo(
    DateTime locNow, {
    double? cloudCoverPercent,
    required bool snow,
    required double intensityDbz,
    HourlyForecast? ecmwfHourly,
    int? utcOffsetSeconds,
  }) {
    final icon = skyWmoFromCloudCover(cloudCoverPercent);

    if (_precipBandPassedPin && !_trackerMapEchoVisible) {
      if (_wetExpectedInTrackerHorizon(
        locNow,
        ecmwfHourly: ecmwfHourly,
        utcOffsetSeconds: utcOffsetSeconds,
      )) {
        return _trackerInfoAvoidingFalseDry(
          locNow,
          snow: snow,
          intensityDbz: intensityDbz,
          cloudCoverPercent: cloudCoverPercent,
          ecmwfHourly: ecmwfHourly,
          utcOffsetSeconds: utcOffsetSeconds,
        );
      }
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.watching,
        title: kRadarTrackerCardTitle,
        detail: kRadarTrackerDryHorizonDetail,
        iconCode: icon,
      );
    }

    if (_echoClearlyOffPath ||
        (fromRainViewer &&
            _rainViewerEchoBypassesPinAt(locNow) &&
            !_helkorTrackerPrecipSignal)) {
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.idle,
        title: kRadarTrackerCardTitle,
        detail: kRadarTrackerDryHorizonDetail,
        iconCode: icon,
      );
    }

    if (_hasActiveNearbyEcho && !_significantEchoNearPin && !_rainAtPinCore) {
      if (fromRainViewer &&
          _rainViewerEchoBypassesPinAt(locNow) &&
          !_helkorTrackerPrecipSignal) {
        return RadarPrecipTrackerInfo(
          phase: RadarPrecipTrackerPhase.idle,
          title: kRadarTrackerCardTitle,
          detail: kRadarTrackerDryHorizonDetail,
          iconCode: icon,
        );
      }
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.watching,
        title: kRadarTrackerCardTitle,
        detail: 'Slabé echo v okolí — zatiaľ bez dážďa pri lokalite.',
        iconCode: icon,
      );
    }

    final nearbyWatch = fromRainViewer
        ? (_rainViewerTrackerPrecipSignalAt(locNow) ||
            _helkorTrackerPrecipSignal)
        : (_trackerMapEchoVisible || _helkorTrackerPrecipSignal);

    if (nearbyWatch) {
      var rawDbz = math.max(intensityDbz, _maxNearbyDbz ?? intensityDbz);
      if (_helkorTrackerPrecipSignal &&
          !(fromRainViewer && _rainViewerTrackerPrecipSignalAt(locNow))) {
        rawDbz = math.max(rawDbz, _helkorIntensityDbz);
      }
      final dbz = fromRainViewer ? rainViewerDbzForUi(rawDbz) : rawDbz;
      if (fromRainViewer &&
          _rainViewerIncomingLikelyAt(locNow)) {
        final window = _trackerUiPrecipWindow(locNow);
        if (window != null) {
          return _buildIncomingTrackerInfo(
            locNow,
            window: window,
            intensityDbz: math.max(dbz, kRainViewerLegendMinDbz),
            snow: snow,
          );
        }
      }
      var arrivalMins = fromRainViewer
          ? _rainViewerIncomingArrivalMinutes(locNow)
          : _trackerSoftArrivalMinutes(locNow);
      if (fromRainViewer &&
          arrivalMins < 0 &&
          _rainViewerNearbyPrecipField) {
        arrivalMins = _rainViewerNearbyArrivalMinutes();
      }
      if (arrivalMins >= 0) {
        final startAt = _trackerIncomingStartAt(locNow, arrivalMins);
        final endAt = _roundLocalTimeToMinutes(
          startAt.add(Duration(
            minutes: math.max(45, _incomingPassageMinutes()),
          )),
        );
        final detail = arrivalMins > 60
            ? 'Radar zachytáva zrážky v okolí — možný príchod okolo ${_trackerClockLabel(startAt)}.'
            : 'Radar zachytáva zrážky v okolí — sledujem vývoj.';
        if (arrivalMins <= 90 && _trackerIncomingConfirmed) {
          return _buildIncomingTrackerInfo(
            locNow,
            window: (start: startAt, minuteEnd: endAt),
            intensityDbz: math.max(dbz, kRainViewerLegendMinDbz),
            snow: snow,
            forceIncomingPhase: arrivalMins <= 75,
          );
        }
        return RadarPrecipTrackerInfo(
          phase: RadarPrecipTrackerPhase.watching,
          title: kRadarTrackerCardTitle,
          detail: detail,
          iconCode: _wmoFromRadarIntensity(dbz, snow: snow),
        );
      }
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.watching,
        title: kRadarTrackerCardTitle,
        detail: 'Radar zachytáva zrážky v okolí — sledujem vývoj.',
        iconCode: _wmoFromRadarIntensity(dbz, snow: snow),
      );
    }

    if (_wetExpectedInTrackerHorizon(
      locNow,
      ecmwfHourly: ecmwfHourly,
      utcOffsetSeconds: utcOffsetSeconds,
    )) {
      return _trackerInfoAvoidingFalseDry(
        locNow,
        snow: snow,
        intensityDbz: intensityDbz,
        cloudCoverPercent: cloudCoverPercent,
        ecmwfHourly: ecmwfHourly,
        utcOffsetSeconds: utcOffsetSeconds,
      );
    }

    return RadarPrecipTrackerInfo(
      phase: RadarPrecipTrackerPhase.idle,
      title: kRadarTrackerCardTitle,
      detail: kRadarTrackerDryHorizonDetail,
      iconCode: icon,
    );
  }
}

RadarNowcastContext? _radarNowcastCache;
DateTime? _radarNowcastCacheAt;
String? _radarNowcastCacheKey;

String _radarNowcastCacheKeyFor(GeoCity city) =>
    '${city.lat.toStringAsFixed(3)}:${city.lon.toStringAsFixed(3)}:${city.countryCode}';

Future<RadarNowcastContext> fetchRadarNowcastContextForCity(GeoCity city) async {
  if (!rainViewerNowcastForCity(city)) {
    return RadarNowcastContext.inactive;
  }

  final key = _radarNowcastCacheKeyFor(city);
  if (_radarNowcastCacheKey != null && _radarNowcastCacheKey != key) {
    _radarNowcastCache = null;
    _radarNowcastCacheAt = null;
    _radarNowcastCacheKey = null;
  }
  final cachedAt = _radarNowcastCacheAt;
  final cacheFresh = _radarNowcastCache != null &&
      _radarNowcastCacheKey == key &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < _kRadarNowcastCacheTtl;
  if (cacheFresh) {
    // Krátky TTL pre všetky stavy — pri daždi aj príchode musíme ťahať nové snímky.
    return _radarNowcastCache!;
  }

  try {
    var history = await fetchRainViewerFrameHistory(city.lat, city.lon);
    var fromRainViewer = history.isNotEmpty;
    List<RadarFrameSample> nowcast = const [];
    if (fromRainViewer) {
      nowcast = await fetchRainViewerNowcastHistory(city.lat, city.lon);
    }

    // Helkor len ako fallback keď RainViewer nemá snímky.
    // Meteo Radar WebView ostáva na zobrazenie — nie na detekciu pinu.
    List<RadarFrameSample> helkor = const [];
    if (!fromRainViewer && radarCoverageForCity(city)) {
      helkor = await _fetchRadarFrameHistory(city.lat, city.lon).catchError(
        (Object e) {
          debugPrint('fetchRadarNowcastContextForCity helkor: $e');
          return <RadarFrameSample>[];
        },
      );
      if (helkor.isNotEmpty) {
        history = helkor;
        fromRainViewer = false;
      }
    }

    final ctx = _contextFromHistory(
      history,
      fromRainViewer: fromRainViewer,
      nowcastHistory: nowcast,
      helkorHistory: helkor,
      cityLat: city.lat,
      cityLon: city.lon,
    );
    _storeRadarNowcastCache(city, ctx);
    return ctx;
  } catch (e) {
    debugPrint('fetchRadarNowcastContextForCity: $e');
    if (radarCoverageForCity(city)) {
      try {
        final history = await _fetchRadarFrameHistory(city.lat, city.lon);
        final ctx = _contextFromHistory(history, helkorHistory: history);
        _storeRadarNowcastCache(city, ctx);
        return ctx;
      } catch (fallbackError) {
        debugPrint('fetchRadarNowcastContextForCity helkor fallback: $fallbackError');
      }
    }
    return _radarNowcastCacheKey == key
        ? (_radarNowcastCache ?? RadarNowcastContext.inactive)
        : RadarNowcastContext.inactive;
  }
}

/// Zrážkový nowcast cez RainViewer API (WebView mapa ostáva len na zobrazenie SHMÚ).
Future<RadarNowcastContext> fetchRadarNowcastViaWebView(
  WebViewController controller,
  GeoCity city,
) async {
  return fetchRadarNowcastContextForCity(city);
}

int _radarHistoryWetScore(List<RadarFrameSample> history) {
  if (history.isEmpty) return -1;
  var score = 0;
  for (final frame in history) {
    if (frame.precip) score += 10;
    final dbz = frame.dbz;
    if (dbz != null) score += (dbz / 5).round();
  }
  final latest = history.last;
  if (latest.precipAtPoint) score += 50;
  final latestDbz = latest.dbz;
  if (latestDbz != null) score += (latestDbz / 2).round();
  return score;
}

/// Porovnanie dvoch radarových histórií (HTTP vs WebView).
int radarHistoryWetScore(List<RadarFrameSample> history) =>
    _radarHistoryWetScore(history);

RadarNowcastContext _contextFromHistory(
  List<RadarFrameSample> history, {
  bool fromRainViewer = false,
  List<RadarFrameSample> nowcastHistory = const [],
  List<RadarFrameSample> helkorHistory = const [],
  double? cityLat,
  double? cityLon,
}) {
  if (history.isEmpty && helkorHistory.isEmpty) {
    return RadarNowcastContext.inactive;
  }
  if (history.isEmpty) {
    history = helkorHistory;
    fromRainViewer = false;
  }
  final pinForecast = buildRadarPinForecastSnapshot(
    history: history,
    nowcastHistory: nowcastHistory,
    helkorHistory: helkorHistory,
    fromRainViewer: fromRainViewer,
    cityLat: cityLat,
    cityLon: cityLon,
  );
  return RadarNowcastContext(
    eligible: true,
    history: history,
    fromRainViewer: fromRainViewer,
    nowcastHistory: nowcastHistory,
    helkorHistory: helkorHistory,
    pinForecast: pinForecast,
  );
}

void _storeRadarNowcastCache(GeoCity city, RadarNowcastContext ctx) {
  final key = _radarNowcastCacheKeyFor(city);
  _radarNowcastCache = ctx;
  _radarNowcastCacheAt = DateTime.now();
  _radarNowcastCacheKey = key;
}

Future<void> ensureRadarWebViewSamplerInjected(WebViewController controller) async {
  await controller.runJavaScript(_kRadarWebViewSamplerJs);
}

const String _kRadarWebViewSamplerJs = r'''
window.pocasieSampleRadarHistory = async function(lat, lon, frameCount) {
  const MIN_DBZ = 8, MIN_NOW = 8, CORE = 6, PEAK = 28, PEAK_WIDE = 56, OUTER = 96;
  const MIN_FRAMES = 3, MAX_FRAMES = 24;
  const COLS = 4000, ROWS = 2000;
  const LON_MIN = 0, LON_MAX = 30, LAT_MIN = 43, LAT_MAX = 58;
  const PAL = [
    [8,200,216,240],[11,176,200,216],[14,136,168,200],[18,64,116,184],
    [21,4,72,168],[24,0,132,116],[27,0,196,48],[30,72,240,0],
    [34,244,224,0],[37,252,168,0],[40,252,68,0],[43,220,8,0],
    [46,148,24,36],[50,204,72,200],[53,252,128,252],[56,252,176,252]
  ];
  function mercX(lon) { return lon * Math.PI / 180; }
  function mercY(lat) { return Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360)); }
  function pxPy(lat, lon) {
    const mx = mercX(lon), my = mercY(lat);
    const mxMin = mercX(LON_MIN), mxMax = mercX(LON_MAX);
    const myN = mercY(LAT_MAX), myS = mercY(LAT_MIN);
    const u = (mx - mxMin) / (mxMax - mxMin);
    const v = (myN - my) / (myN - myS);
    const px = Math.round(u * COLS);
    const py = Math.round(v * ROWS);
    return [Math.max(0, Math.min(COLS - 1, px)), Math.max(0, Math.min(ROWS - 1, py))];
  }
  function estimateDbz(r, g, b, a) {
    if (a < 28) return null;
    if (r > 230 && g > 230 && b > 230) return null;
    if (r < 25 && g < 25 && b < 35) return null;
    if (r + g + b < 80) return null;
    let best = PAL[0][0], bd = 1e18;
    for (const p of PAL) {
      const dr = r - p[1], dg = g - p[2], db = b - p[3];
      const d = dr * dr + dg * dg + db * db;
      if (d < bd) { bd = d; best = p[0]; }
    }
    if (bd > 35 * 35) return null;
    if (best <= 11 && bd > 18 * 18) return null;
    if (best < 18 && bd > 22 * 22) return null;
    return best;
  }
  function sampleImage(img, px, py, radius) {
    const canvas = document.createElement('canvas');
    canvas.width = img.width;
    canvas.height = img.height;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    const sx = Math.round(px * canvas.width / COLS);
    const sy = Math.round(py * canvas.height / ROWS);
    const rScreen = radius <= 0 ? 0 : Math.max(2, Math.round(radius * canvas.width / COLS));
    let maxDbz = null;
    for (let dy = -rScreen; dy <= rScreen; dy++) {
      for (let dx = -rScreen; dx <= rScreen; dx++) {
        if (dx * dx + dy * dy > rScreen * rScreen) continue;
        const x = Math.max(0, Math.min(canvas.width - 1, sx + dx));
        const y = Math.max(0, Math.min(canvas.height - 1, sy + dy));
        const d = ctx.getImageData(x, y, 1, 1).data;
        const dbz = estimateDbz(d[0], d[1], d[2], d[3]);
        if (dbz !== null) maxDbz = maxDbz === null ? dbz : Math.max(maxDbz, dbz);
      }
    }
    return maxDbz;
  }
  function countDbzAbove(img, px, py, radiusPx, minDbz) {
    const sx = Math.round(px * img.width / COLS);
    const sy = Math.round(py * img.height / ROWS);
    const rScreen = radiusPx <= 0 ? 0 : Math.max(2, Math.min(80, Math.round(radiusPx * img.width / COLS)));
    const canvas = document.createElement('canvas');
    canvas.width = img.width;
    canvas.height = img.height;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0);
    let count = 0;
    for (let dy = -rScreen; dy <= rScreen; dy++) {
      for (let dx = -rScreen; dx <= rScreen; dx++) {
        if (dx * dx + dy * dy > rScreen * rScreen) continue;
        const x = Math.max(0, Math.min(canvas.width - 1, sx + dx));
        const y = Math.max(0, Math.min(canvas.height - 1, sy + dy));
        const d = ctx.getImageData(x, y, 1, 1).data;
        const dbz = estimateDbz(d[0], d[1], d[2], d[3]);
        if (dbz !== null && dbz >= minDbz) count++;
      }
    }
    return count;
  }
  function isPrecipAtPoint(centerDbz, peakDbz) {
    const center = centerDbz !== null ? centerDbz : 0;
    const peak = peakDbz !== null ? peakDbz : 0;
    return center >= MIN_NOW || peak >= MIN_NOW;
  }
  function sampleCenter(img, px, py) {
    return sampleImage(img, px, py, CORE);
  }
  function loadImage(url) {
    return new Promise(function(resolve, reject) {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = function() { resolve(img); };
      img.onerror = reject;
      img.src = url;
    });
  }
  try {
    const n = Math.max(MIN_FRAMES, Math.min(frameCount || MAX_FRAMES, data.length));
    const resp = await fetch('/radar/radar_history_cmax.json?v=' + Date.now());
    const data = await resp.json();
    if (!data || !data.length) return JSON.stringify({ ok: false });
    const tail = data.slice(-Math.min(n, data.length));
    const pxpy = pxPy(lat, lon);
    const px = pxpy[0], py = pxpy[1];
    const frames = [];
    for (const entry of tail) {
      try {
        const img = await loadImage(entry.url);
        const peak14 = sampleImage(img, px, py, PEAK);
        const peak28 = sampleImage(img, px, py, PEAK_WIDE);
        const peak96 = sampleImage(img, px, py, OUTER);
        let peak = peak14;
        for (const p of [peak28, peak96]) {
          if (p !== null) peak = peak === null ? p : Math.max(peak, p);
        }
        const dbz = sampleCenter(img, px, py);
        const atPoint = isPrecipAtPoint(dbz, peak);
        frames.push({
          unix: entry.unix_time,
          precip: (peak !== null && peak >= MIN_DBZ) || (dbz !== null && dbz >= MIN_DBZ),
          precipAtPoint: atPoint,
          dbz: dbz,
          peakDbz: peak,
          northDbz: sampleImage(img, px, py - OUTER, 10),
          southDbz: sampleImage(img, px, py + OUTER, 10),
          eastDbz: sampleImage(img, px + OUTER, py, 10),
          westDbz: sampleImage(img, px - OUTER, py, 10),
        });
      } catch (e) {
        frames.push({ unix: entry.unix_time, precip: false });
      }
    }
    return JSON.stringify({ ok: true, frames: frames });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
};
''';

Future<List<RadarFrameSample>> _fetchRadarFrameHistory(
  double lat,
  double lon,
) async {
  final response = await http
      .get(
        Uri.parse('$kRadarServerBase/radar/radar_history_cmax.json'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'pocasie-app/1.0 (flutter)',
        },
      )
      .timeout(const Duration(seconds: 15));

  if (response.statusCode != 200) {
    throw HttpException('Radar history HTTP ${response.statusCode}');
  }

  final decoded = json.decode(response.body);
  if (decoded is! List || decoded.isEmpty) return const [];

  final entries = decoded
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  if (entries.isEmpty) return const [];

  final tail = entries.length > kRadarHistoryFramesToSample
      ? entries.sublist(entries.length - kRadarHistoryFramesToSample)
      : entries;

  final samples = await _mapRadarSamplesWithConcurrency<RadarFrameSample>(
    tail.length,
    (i) async {
      final entry = tail[i];
      final url = entry['url']?.toString();
      final unix = entry['unix_time'] is int
          ? entry['unix_time'] as int
          : int.tryParse('${entry['unix_time']}') ?? 0;
      if (url == null || url.isEmpty || unix <= 0) return null;
      return _sampleRadarFrameFromUrl(url, lat, lon, unix);
    },
  );
  return samples.whereType<RadarFrameSample>().toList();
}

final Map<String, Uint8List> _radarPngBytesCache = {};

Future<RadarFrameSample?> _sampleRadarFrameFromUrl(
  String url,
  double lat,
  double lon,
  int frameUnix,
) async {
  try {
    Uint8List bytes;
    final cached = _radarPngBytesCache[url];
    if (cached != null) {
      bytes = cached;
    } else {
      final response = await http
          .get(
            Uri.parse(url),
            headers: const {'User-Agent': 'pocasie-app/1.0 (flutter)'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      bytes = response.bodyBytes;
      if (_radarPngBytesCache.length > 24) _radarPngBytesCache.clear();
      _radarPngBytesCache[url] = bytes;
    }

    return _sampleRadarFrameFromBytes(bytes, lat, lon, frameUnix);
  } catch (e) {
    debugPrint('_sampleRadarFrameFromUrl: $e');
    return null;
  }
}

Future<RadarFrameSample?> _sampleRadarFrameFromBytes(
  Uint8List bytes,
  double lat,
  double lon,
  int frameUnix,
) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      final width = image.width;
      final height = image.height;
      if (width <= 0 || height <= 0) return null;

      final (px, py) = _radarPixelForLatLon(lat, lon);
      final center = _sampleCenterDbz(
        byteData.buffer.asUint8List(),
        width,
        height,
        px,
        py,
      );
      final peakWide = _sampleNeighborhoodMaxDbz(
        byteData.buffer.asUint8List(),
        width,
        height,
        px,
        py,
        kRadarPeakCompareRadiusPx,
      );
      final peakOuter = _sampleNeighborhoodMaxDbz(
        byteData.buffer.asUint8List(),
        width,
        height,
        px,
        py,
        kRadarSampleRadiusPx,
      );
      final peakFar = _sampleNeighborhoodMaxDbz(
        byteData.buffer.asUint8List(),
        width,
        height,
        px,
        py,
        kRadarNowcastOuterRadiusPx,
      );

      double? sampleRing(int dx, int dy) {
        final ring = _sampleNeighborhoodMaxDbz(
          byteData.buffer.asUint8List(),
          width,
          height,
          px + dx,
          py + dy,
          kRadarDirectionalSampleRadiusPx,
        );
        return ring.dbz;
      }

      final centerDbz = center.dbz;
      final p14 = peakWide.dbz;
      final p56 = peakOuter.dbz;
      final p96 = peakFar.dbz;
      var peakDbz = [p14, p56, p96]
          .whereType<double>()
          .fold<double?>(null, (m, v) => m == null ? v : math.max(m, v));

      final rgba = byteData.buffer.asUint8List();
      final coherentPx14 = _countDbzAboveInNeighborhood(
        rgba,
        width,
        height,
        px,
        py,
        kRadarPeakCompareRadiusPx,
        12,
      );
      final coherentCorePx = _countDbzAboveInNeighborhood(
        rgba,
        width,
        height,
        px,
        py,
        kRadarCoreSampleRadiusPx,
        10,
      );

      final nearbyEcho = (peakDbz ?? 0) >= kRadarMinDbzEcho ||
          (centerDbz ?? 0) >= kRadarMinDbzEcho;
      final atPoint = (centerDbz ?? 0) >= kRadarMinDbzPrecipNow ||
          (peakDbz ?? 0) >= kRadarMinDbzPrecipNow ||
          nearbyEcho;

      return RadarFrameSample(
        unix: frameUnix,
        precip: nearbyEcho,
        precipAtPoint: atPoint,
        dbz: centerDbz,
        peakDbz: peakDbz,
        coherentPx14: coherentPx14,
        coherentCorePx: coherentCorePx,
        northDbz: sampleRing(0, -kRadarNowcastOuterRadiusPx),
        southDbz: sampleRing(0, kRadarNowcastOuterRadiusPx),
        eastDbz: sampleRing(kRadarNowcastOuterRadiusPx, 0),
        westDbz: sampleRing(-kRadarNowcastOuterRadiusPx, 0),
      );
    } finally {
      image.dispose();
    }
  } catch (e) {
    debugPrint('_sampleRadarFrameFromBytes: $e');
    return null;
  }
}

(int, int) _radarPixelForLatLon(double lat, double lon) {
  // Mapbox ImageSource — rovnaká Mercator projekcia ako helkor radar mapa.
  final mx = _radarMercatorX(lon);
  final my = _radarMercatorY(lat);
  final mxMin = _radarMercatorX(kRadarExtentLonMin);
  final mxMax = _radarMercatorX(kRadarExtentLonMax);
  final myNorth = _radarMercatorY(kRadarExtentLatMax);
  final mySouth = _radarMercatorY(kRadarExtentLatMin);

  final u = ((mx - mxMin) / (mxMax - mxMin)).clamp(0.0, 1.0);
  final v = ((myNorth - my) / (myNorth - mySouth)).clamp(0.0, 1.0);

  final px = (u * kRadarImageCols).round().clamp(0, kRadarImageCols - 1);
  final py = (v * kRadarImageRows).round().clamp(0, kRadarImageRows - 1);
  return (px, py);
}

double _radarMercatorX(double lon) => lon * math.pi / 180;

double _radarMercatorY(double lat) {
  final latRad = lat * math.pi / 180;
  return math.log(math.tan(math.pi / 4 + latRad / 2));
}

({double? dbz}) _sampleNeighborhoodMaxDbz(
  Uint8List rgba,
  int width,
  int height,
  int centerPx,
  int centerPy,
  int radiusPx,
) {
  final sx = (centerPx * width / kRadarImageCols).round().clamp(0, width - 1);
  final sy = (centerPy * height / kRadarImageRows).round().clamp(0, height - 1);
  final radiusScreen = radiusPx <= 0
      ? 0
      : (radiusPx * width / kRadarImageCols).round().clamp(2, 80);

  double? maxDbz;
  for (var dy = -radiusScreen; dy <= radiusScreen; dy++) {
    for (var dx = -radiusScreen; dx <= radiusScreen; dx++) {
      if (dx * dx + dy * dy > radiusScreen * radiusScreen) continue;
      final x = (sx + dx).clamp(0, width - 1);
      final y = (sy + dy).clamp(0, height - 1);
      final offset = (y * width + x) * 4;
      if (offset + 3 >= rgba.length) continue;
      final r = rgba[offset];
      final g = rgba[offset + 1];
      final b = rgba[offset + 2];
      final a = rgba[offset + 3];
      final dbz = _estimateDbzFromRadarPixel(r, g, b, a);
      if (dbz != null) {
        maxDbz = maxDbz == null ? dbz : math.max(maxDbz, dbz);
      }
    }
  }
  return (dbz: maxDbz);
}

/// Koľko pixelov v okolí má echo ≥ [minDbz] — izolovaný bod = šum.
int _countDbzAboveInNeighborhood(
  Uint8List rgba,
  int width,
  int height,
  int centerPx,
  int centerPy,
  int radiusPx,
  double minDbz,
) {
  final sx = (centerPx * width / kRadarImageCols).round().clamp(0, width - 1);
  final sy = (centerPy * height / kRadarImageRows).round().clamp(0, height - 1);
  final radiusScreen = radiusPx <= 0
      ? 0
      : (radiusPx * width / kRadarImageCols).round().clamp(2, 80);

  var count = 0;
  for (var dy = -radiusScreen; dy <= radiusScreen; dy++) {
    for (var dx = -radiusScreen; dx <= radiusScreen; dx++) {
      if (dx * dx + dy * dy > radiusScreen * radiusScreen) continue;
      final x = (sx + dx).clamp(0, width - 1);
      final y = (sy + dy).clamp(0, height - 1);
      final offset = (y * width + x) * 4;
      if (offset + 3 >= rgba.length) continue;
      final dbz = _estimateDbzFromRadarPixel(
        rgba[offset],
        rgba[offset + 1],
        rgba[offset + 2],
        rgba[offset + 3],
      );
      if (dbz != null && dbz >= minDbz) count++;
    }
  }
  return count;
}

({double? dbz}) _sampleCenterDbz(
  Uint8List rgba,
  int width,
  int height,
  int centerPx,
  int centerPy,
) {
  return _sampleNeighborhoodMaxDbz(
    rgba,
    width,
    height,
    centerPx,
    centerPy,
    kRadarCoreSampleRadiusPx,
  );
}

double? _estimateDbzFromRadarPixel(int r, int g, int b, int a) {
  if (a < 28) return null;
  if (_isRadarCoverageBorderPixel(r, g, b, a)) return null;
  if (r + g + b < 80) return null;

  var bestDbz = _kRadarCmaxLegendStops.first.dbz;
  var bestDist = double.infinity;
  for (final stop in _kRadarCmaxLegendStops) {
    final dr = r - stop.r;
    final dg = g - stop.g;
    final db = b - stop.b;
    final dist = (dr * dr + dg * dg + db * db).toDouble();
    if (dist < bestDist) {
      bestDist = dist;
      bestDbz = stop.dbz;
    }
  }
  // Priveľmi ďaleko od palety = nie radarová farba.
  if (bestDist > 35 * 35) return null;
  // Slabý neistý match = typický šum mapy (8–14 dBZ).
  if (bestDbz <= 11 && bestDist > 18 * 18) return null;
  if (bestDbz < 18 && bestDist > 22 * 22) return null;
  return bestDbz;
}

bool _isRadarCoverageBorderPixel(int r, int g, int b, int a) {
  if (a < 40) return true;
  if (r > 230 && g > 230 && b > 230) return true;
  if (r < 25 && g < 25 && b < 35) return true;
  if (r > 90 && b > 90 && g < 60) return true;
  return false;
}
