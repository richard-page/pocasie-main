part of 'main.dart';

const String kRadarServerBase = 'http://cz1.helkor.eu:41152';

const int kRadarImageCols = 4000;
const int kRadarImageRows = 2000;

const double kRadarMinDbzForUi = 10.0;
/// Min. dBZ pre zmysluplné echo — pod tým ide o šum / slabý artefakt.
const double kRadarMinDbzSignificantEcho = 20.0;
/// Jedna snímka bez histórie — musí byť aspoň takto silná.
const double kRadarMinDbzCoherentEcho = 24.0;
/// Sledovač „blíži sa“ — len pri reálnom echo, nie izolovaných bodoch.
const double kRadarMinDbzTrackerIncoming = 22.0;
/// Slabšie vzdialené echo — stále sledovať, ak smeruje k pinu.
const double kRadarMinDbzDistantApproach = 20.0;
/// Koľko posledných snímok musí echo potvrdiť (odfiltruje mŕtve pixely).
const int kRadarNoiseMinPersistFrames = 3;
/// Min. pixelov ≥18 dBZ v okolí 14 px — súvislá oblasť, nie bodka.
const int kRadarMinCoherentAreaPx = 9;
/// Min. dBZ pre potvrdenie blížiacej sa bunky v sledovači.
const double kRadarMinDbzTrackerFront = 26.0;
/// Min. pixelov ≥16 dBZ v jadre 3 px pri pine.
const int kRadarMinCoherentCorePx = 2;
/// „Už prší u mňa“ — nie len okraj blížiacej sa bunky.
const double kRadarMinDbzPrecipNow = 22.0;
const int kRadarCoreSampleRadiusPx = 3;
const int kRadarPeakCompareRadiusPx = 14;
const int kRadarSampleRadiusPx = 28;
const int kRadarNowcastOuterRadiusPx = 48;

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

/// Počet snímok z [radar_history_cmax.json] — server ~5 min interval, typicky až ~24 (= cca 2 h).
const int kRadarHistoryFramesMin = 3;
const int kRadarHistoryFramesMax = 24;
const int kRadarHistoryFramesToSample = kRadarHistoryFramesMax;
/// Trend / transient — len posledných N snímok, aby stará dažďová hodina neskresľovala stav.
const int kRadarNowcastTrendFrames = 10;
const Duration _kRadarNowcastCacheTtl = Duration(seconds: 50);
const Duration kRadarTrackerPhaseHoldInterval = Duration(minutes: 2);
const int kRadarTrackerArrivalSmoothMinutes = 15;

class RadarFrameSample {
  const RadarFrameSample({
    required this.unix,
    required this.precip,
    this.precipAtPoint = false,
    this.dbz,
    this.peakDbz,
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
const String kRadarTrackerDryNextHourDetail =
    'Nasledujúcu hodinu sa neočakávajú žiadne zrážky.';

String _radarTrackerCardDetail(String headline, String body) {
  final h = headline.trim();
  final b = body.trim();
  if (h.isEmpty) return b;
  if (b.isEmpty) return h;
  return '$h. $b';
}

String _incomingTrackerStatusTitle({
  required bool atPinNow,
  required bool snow,
  required double intensityDbz,
  required String intensityTitle,
}) {
  if (atPinNow) return intensityTitle;
  if (snow) return 'Blíži sa sneh';
  if (intensityDbz >= 24) return 'Blíži sa ${intensityTitle.toLowerCase()}';
  return 'Blíži sa dážď';
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

DateTime? _trackerStablePhaseAt;
RadarPrecipTrackerInfo? _trackerStableDisplay;

/// Stabilizuje kartu sledovača — menej skokov v ETA a fáze pri každom snímke radaru.
RadarPrecipTrackerInfo stabilizeRadarTrackerInfo(
  RadarPrecipTrackerInfo next,
  DateTime locNow,
) {
  final prev = _trackerStableDisplay;
  final now = DateTime.now();

  if (prev == null) {
    _trackerStableDisplay = next;
    _trackerStablePhaseAt = now;
    return next;
  }

  final upgraded = next.phase == RadarPrecipTrackerPhase.active ||
      next.phase == RadarPrecipTrackerPhase.incoming;
  final prevWet = prev.phase == RadarPrecipTrackerPhase.active ||
      prev.phase == RadarPrecipTrackerPhase.incoming;

  if (upgraded && !prevWet) {
    _trackerStableDisplay = next;
    _trackerStablePhaseAt = now;
    return next;
  }

  if (prevWet &&
      prev.phase == RadarPrecipTrackerPhase.active &&
      next.phase == RadarPrecipTrackerPhase.idle &&
      _trackerStablePhaseAt != null &&
      now.difference(_trackerStablePhaseAt!) < kRadarTrackerPhaseHoldInterval) {
    return prev;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase != RadarPrecipTrackerPhase.incoming &&
      next.phase != RadarPrecipTrackerPhase.active &&
      _trackerStablePhaseAt != null &&
      now.difference(_trackerStablePhaseAt!) < kRadarTrackerPhaseHoldInterval) {
    return prev;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase == RadarPrecipTrackerPhase.active) {
    _trackerStableDisplay = next;
    _trackerStablePhaseAt = now;
    return next;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase == RadarPrecipTrackerPhase.incoming &&
      prev.startLocal != null &&
      next.startLocal != null &&
      !next.startLocal!.isAfter(prev.startLocal!)) {
    _trackerStableDisplay = next;
    _trackerStablePhaseAt = now;
    return next;
  }

  if (prev.phase == RadarPrecipTrackerPhase.incoming &&
      next.phase == RadarPrecipTrackerPhase.incoming &&
      prev.startLocal != null &&
      next.startLocal != null) {
    final delta =
        next.startLocal!.difference(prev.startLocal!).inMinutes.abs();
    if (delta <= kRadarTrackerArrivalSmoothMinutes) {
      final keepStart = prev.startLocal!;
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
      _trackerStableDisplay = stabilized;
      return stabilized;
    }
  }

  _trackerStableDisplay = next;
  if (prev.phase != next.phase) {
    _trackerStablePhaseAt = now;
  }
  return next;
}

void resetRadarTrackerStabilizer() {
  _trackerStableDisplay = null;
  _trackerStablePhaseAt = null;
}

/// Radarový kontext — trend z posledných ~2 h histórie (podľa servera). Cieľ: odhad **kedy zrážky skončia**.
class RadarNowcastContext {
  const RadarNowcastContext({
    required this.eligible,
    required this.history,
  });

  final bool eligible;
  final List<RadarFrameSample> history;

  static const inactive = RadarNowcastContext(eligible: false, history: []);

  RadarFrameSample? get latest => history.isEmpty ? null : history.last;

  /// Posledných [kRadarNowcastTrendFrames] snímok — motion / „práve prestalo“ / transient.
  List<RadarFrameSample> get _recentHistory {
    if (history.length <= kRadarNowcastTrendFrames) return history;
    return history.sublist(history.length - kRadarNowcastTrendFrames);
  }

  /// Surový stav pixelu — trend v histórii; UI používa [precipNow].
  bool get _rawPrecipAtPoint => latest?.precipAtPoint ?? false;

  /// Prší pri pinom — stredný pixel / engulf; nie len peak z okolia (14 px).
  bool get precipNow {
    if (!_rainAtPinCore) return false;
    if (_isScatteredSpeckleAtPin) return false;
    if (_fringePrecipAtPoint) {
      final center = latest?.dbz ?? 0;
      final peak = latest?.peakDbz ?? center;
      return center >= 10 || peak >= 24 || _echoEngulfsPin;
    }
    return true;
  }

  /// Verejný prístup pre UI — radar potvrdil zrážky pri pine.
  bool get rainAtPinNow => _rainAtPinCore;

  /// Zrážky **priamo** na pine — nie echo v 14 px okolí (Freyung ≠ Znojmo).
  bool get _rainAtPinCore {
    final frame = latest;
    if (frame == null) return false;

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    final gap = peak - center;

    if (_isScatteredSpeckleAtPin) return false;

    if (center >= kRadarMinDbzPrecipNow) {
      if (peakDbzGapFringeOnly(center, peak) &&
          frame.coherentCorePx < kRadarMinCoherentCorePx) {
        return false;
      }
      if (frame.coherentCorePx < kRadarMinCoherentCorePx ||
          frame.coherentPx14 < kRadarMinCoherentAreaPx) {
        return false;
      }
      return true;
    }
    if (_rawPrecipAtPoint &&
        center >= 14 &&
        gap <= 10 &&
        frame.coherentCorePx >= kRadarMinCoherentCorePx &&
        frame.coherentPx14 >= kRadarMinCoherentAreaPx) {
      return true;
    }
    if (_echoEngulfsPin &&
        center >= 14 &&
        frame.coherentPx14 >= kRadarMinCoherentAreaPx) {
      return true;
    }
    if (center >= 14 &&
        peak >= 20 &&
        gap <= 8 &&
        frame.coherentCorePx >= kRadarMinCoherentCorePx) {
      return true;
    }
    if (center >= 12 &&
        peak >= 22 &&
        gap <= 6 &&
        frame.coherentCorePx >= kRadarMinCoherentCorePx) {
      return true;
    }
    return false;
  }

  /// Alias — interné volania.
  bool get _rainAtPinNow => _rainAtPinCore;

  bool peakDbzGapFringeOnly(double center, double peak) =>
      peak - center >= 14 && center < 14;

  /// dBZ pre hero / sledovač — intenzita pri pine, nie peak z okolia.
  double get precipIntensityDbz {
    final frame = latest;
    if (frame == null) return kRadarMinDbzForUi;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (!precipNow) {
      return center > 0 ? center : (peak > 0 ? math.min(peak, 24.0) : kRadarMinDbzForUi);
    }
    if (center >= 20) {
      return math.max(center, math.min(peak, center + 8)).clamp(12.0, 48.0);
    }
    return math.max(center, math.min(peak, center + 6)).clamp(12.0, 40.0);
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

  /// Echo v diaľke na mape, ale sucho pri pine a bez pohybu k nám (BA ≠ Trnava).
  bool get _staticDistantCellNearMap {
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

  /// Echo, ktoré mapa zobrazí pri pine — text sledovača nesmie hovoriť „sucho“.
  bool get _trackerMapEchoVisible {
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (_rawPrecipAtPoint && center >= 10) return true;
    if (center >= 14 && peak >= 18) return true;
    if (peak >= 22 && frame.coherentPx14 >= kRadarMinCoherentAreaPx - 2) {
      return true;
    }
    final nearby = _maxNearbyDbz ?? 0;
    return nearby >= kRadarMinDbzDistantApproach &&
        frame.coherentPx14 >= kRadarMinCoherentAreaPx - 2;
  }

  /// Prší pri pine — mapa a karta sledovača (miernejšie než strict [precipNow]).
  bool get _trackerPrecipAtPinForCard {
    if (precipNow || _confirmedRainAtPinCore) return true;
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

  /// Príchod zrážok — aj keď ešte nie je potvrdená fronta, ale mapa ukazuje echo.
  bool get _trackerSoftIncomingConfirmed {
    if (_trackerIncomingConfirmed) return true;
    if (!_trackerMapEchoVisible) return false;
    if (_echoClearlyOffPath ||
        _echoMovingAwayFromPin ||
        _nearbyEchoReceding) {
      return false;
    }
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    if (_rawPrecipAtPoint || center >= 14) return true;
    return (_maxNearbyDbz ?? 0) >= kRadarMinDbzDistantApproach;
  }

  int _trackerSoftArrivalMinutes() {
    if (_trackerPrecipAtPinForCard) return 0;
    final strict = _incomingArrivalMinutesFromNow();
    if (strict >= 0) return strict;
    if (!_trackerMapEchoVisible) return -1;
    final frame = latest;
    final center = frame?.dbz ?? 0;
    final peak = frame?.peakDbz ?? center;
    if (_rawPrecipAtPoint || center >= 14 || (center >= 12 && peak >= 18)) {
      return 0;
    }
    return _defaultIncomingMinutes();
  }

  /// Roztrúsené slabé echo na viacerých stranách — typický CMAX šum, nie fronta.
  bool get _isDisorganizedMapNoise {
    if (_confirmedRainAtPinCore || precipNow) return false;
    if (_staticDistantCellNearMap) return true;

    final frame = latest;
    if (frame == null) return true;

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
    if (center >= 14 &&
        peak >= 18 &&
        frame.coherentPx14 >= kRadarMinCoherentAreaPx - 2) {
      return false;
    }
    if (peak >= 26 && (_maxNearbyDbz ?? 0) >= 22) return false;
    if (center >= kRadarMinDbzPrecipNow) return false;

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
    if (!_hasActiveNearbyEcho || _nearbyRainLikely || _rainBandNearPin) {
      return false;
    }
    final frame = latest;
    if (frame == null) return false;
    if (_strongEchoDirections(frame) >= 2) return false;
    return _echoMovingAwayFromPin || _echoPassingBySingleCell;
  }

  /// UI reaguje len na **poslednú** radarovú snímku — nie na starú mokrú históriu.
  bool get showsPrecipForUi => precipNow;

  /// Radar nepotvrdil zrážky pri pine.
  bool get dryAtPin => eligible && !precipNow;

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
    final frame = latest;
    if (frame == null) return false;
    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;
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

  /// Skutočný dážď pri pine — nie mapový šum / fringe.
  bool get _confirmedRainAtPinCore =>
      _rainAtPinCore && !_isScatteredSpeckleAtPin;

  /// Izolovaný šum pri pine bez blížiacej sa bunky — bez rekurzie cez noise gettery.
  bool get _isIsolatedSpeckleNoise =>
      _isScatteredSpeckleAtPin && !_hasStrongNearbyStormRaw();

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
    if (center >= kRadarMinDbzPrecipNow) return center;

    if (_nearbyRainLikely || _echoApproachingPin || _approachingPrecipFront) {
      final approach = _incomingApproach;
      if (approach != null && approach.dbz >= kRadarMinDbzDistantApproach) {
        return math.min(approach.dbz, 40.0);
      }
      final peak = frame.peakDbz;
      if (peak != null && peak >= kRadarMinDbzDistantApproach) {
        return math.min(peak, 40.0);
      }
      final nearby = _maxNearbyDbz;
      if (nearby != null && nearby >= kRadarMinDbzTrackerIncoming) {
        return math.min(nearby, 40.0);
      }
    }

    return null;
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
    if (_strongEchoDirections(frame) >= 2) return false;
    if ((_maxNearbyDbz ?? 0) >= 22) return false;

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

  /// Stred zachytí len okraj bunky, hlavná masa je inde / odchádza.
  bool get _fringePrecipAtPoint {
    if (!_rawPrecipAtPoint) return false;
    final frame = latest;
    if (frame == null) return false;

    final center = frame.dbz ?? 0;
    final peak = frame.peakDbz ?? center;

    if (_precipDepartingRaw) return true;

    if (_rainBandNearPin || _echoEngulfsPin) return false;
    if (center >= 14 && peak >= 16) return false;

    if (_echoEngulfsPin && center >= 16) return false;

    if (peak - center >= 7) {
      final dom = _dominantEchoDirection();
      if (dom != null && dom.dbz > center + 5) {
        final wetFrames = _recentHistory.where((f) => f.precipAtPoint).length;
        if (wetFrames <= 2 && peak < 20) return true;
        final slope = _centerDbzSlopePerMin;
        if (slope != null && slope < 0 && peak < 22) return true;
      }
    }

    if (_echoPassingBySingleCell && center < 28 && peak < 22) return true;
    return false;
  }

  /// Echo v okolí, ale bunka nejde cez pin (iný smer / ustupuje).
  bool get _echoPassingBy => _echoPassingBySingleCell;

  bool get _echoPassingBySingleCell {
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

    if (_echoPassingBy && !_echoMovingTowardPinOrClosing) return false;

    final approach = _incomingApproach;
    if (approach != null && approach.dbz >= 18 && center < 14) {
      return true;
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
    if (precipNow || history.length < 2) return false;

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

    final slope = _centerDbzSlopePerMin;
    final current = dbz ?? 0;
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

    final center = latest?.dbz;
    if (center != null && center >= kRadarMinDbzPrecipNow) return center;

    if (!_echoApproachingPin && !_nearbyRainLikely && !_rainBandNearPin &&
        !_approachingPrecipFront && !_significantEchoNearPin &&
        !_trackerSoftIncomingConfirmed) {
      return kRadarMinDbzForUi;
    }

    if (_trackerSoftIncomingConfirmed) {
      final nearby = _maxNearbyDbz;
      if (nearby != null && nearby >= kRadarMinDbzDistantApproach) {
        return math.min(nearby, 40.0);
      }
    }

    if (_significantEchoNearPin || _approachingPrecipFront) {
      final approach = _incomingApproach;
      if (approach != null && approach.dbz >= 18) {
        return math.min(approach.dbz, 40.0);
      }
      final nearby = _maxNearbyDbz;
      if (nearby != null && nearby >= 18) return math.min(nearby, 40.0);
    }

    return kRadarMinDbzForUi;
  }

  /// Úzka prechádzajúca bunka — krátke echo v posledných snímkach, max 1 h v pásme.
  bool get _transientPassingCell {
    if (precipNow && steadyOngoing) return false;
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
  int _incomingArrivalMinutesFromNow() {
    if (precipNow || _confirmedRainAtPinCore || _trackerPrecipAtPinForCard) {
      return 0;
    }
    final raw = _incomingArrivalMinutesRaw();
    if (raw < 0) return -1;
    if (!_trackerIncomingConfirmed) return -1;
    return raw;
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
      if (_isScatteredSpeckleAtPin) {
        if (_realDirectionalFrontApproaching) {
          return _defaultIncomingMinutes();
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
      return _defaultIncomingMinutes();
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
      return mins.clamp(5, 180);
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
          return (gap / rate).ceil().clamp(10, 180);
        }
        return _defaultIncomingMinutes();
      }
    } else if (_echoMovingTowardPin && (centerSlope ?? 0) > 0.02) {
      return _defaultIncomingMinutes();
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
    final nearby = _maxNearbyDbz ?? approach?.dbz ?? 0;
    final approachDbz = approach?.dbz ?? nearby;
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
      if (dirSlope > 0.008 || (centerSlope ?? 0) > 0.015) {
        final gap = (approach.dbz - center).clamp(8.0, 42.0);
        final rate = math.max(dirSlope, centerSlope ?? 0.015);
        return (gap / rate).ceil().clamp(25, 150);
      }
    }

    if (nearby >= 32) return 55;
    if (nearby >= 28) return 70;
    if (nearby >= 24 || approachDbz >= 22) return 85;
    if (approachDbz >= kRadarMinDbzDistantApproach) return 100;
    return 120;
  }

  /// Fallback keď slope nestačí — podľa vzdialenosti/sily echo.
  int _defaultIncomingMinutes() {
    final nearby = _maxNearbyDbz ?? 0;
    if (nearby >= 32) return 25;
    if (nearby >= 28) return 35;
    if (nearby >= 24) return 50;
    if (nearby >= kRadarMinDbzTrackerIncoming) return 65;
    return 90;
  }

  /// Zaokrúhli lokálny čas na [step] minút (pre čitateľný tracker).
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

  DateTime _incomingArrivalAt(DateTime locNow) {
    final mins = _incomingArrivalMinutesFromNow();
    if (mins <= 0) return _roundLocalTimeToMinutes(locNow);
    return _roundLocalTimeToMinutes(locNow.add(Duration(minutes: mins)));
  }

  /// Spätná kompatibilita pre logiku založenú na hodinách (24 h pás).
  int _incomingArrivalHoursFromNow() {
    final mins = _incomingArrivalMinutesFromNow();
    if (mins < 0) return -1;
    if (mins <= 15) return 0;
    return (mins / 60).ceil().clamp(1, 3);
  }

  int _incomingPassageMinutes() =>
      _capPassageHours(_incomingPassageHours(), incoming: true) * 60;

  int _ongoingPassageMinutes() {
    if (!precipNow) return 0;
    if (_trailingDryAtPointFrames >= 1 || _precipDeparting) return 0;
    if (trendEndingAtPoint) return 0;
    if (_transientPassingCell) return 45;

    final slope = _centerDbzSlopePerMin;
    final current = dbz ?? 22.0;
    if (slope != null && slope < -0.12) {
      final minsLeft = (current - 18) / (-slope);
      return minsLeft.ceil().clamp(10, 120);
    }

    return _capPassageHours(_ongoingPassageHours(), incoming: false) * 60;
  }

  DateTime? _ongoingEndAt(DateTime locNow) {
    if (!precipNow) return null;
    final mins = _ongoingPassageMinutes();
    if (mins <= 0) {
      return _roundLocalTimeToMinutes(
        locNow.add(const Duration(minutes: 15)),
      );
    }
    return _roundLocalTimeToMinutes(locNow.add(Duration(minutes: mins)));
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
    if (precipNow) {
      final nowHour = _localHourFloor(locNow);
      if (slotHour == nowHour) return 1.0;
      final endAt = _ongoingEndAt(locNow);
      if (endAt == null) return 1.0;
      final rainStart = locNow.isAfter(slotHour) ? locNow : slotHour;
      return _hourlySlotRainFraction(slotHour, rainStart, endAt);
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
    return _capPassageHours(2, incoming: false);
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

    if (precipNow) {
      final endAt = _ongoingEndAt(locNow);
      if (endAt == null) return null;
      return (
        start: nowHour,
        end: _firstDryHourAfter(endAt),
      );
    }

    if (precipNow || _trackerPrecipAtPinForCard) {
      final endAt = _ongoingEndAt(locNow) ??
          _roundLocalTimeToMinutes(
            locNow.add(Duration(minutes: math.max(_ongoingPassageMinutes(), 45))),
          );
      return (
        start: _roundLocalTimeToMinutes(locNow),
        end: _firstDryHourAfter(endAt),
      );
    }

    if (_isRadarNoiseOnly && !_trackerMapEchoVisible) return null;

    if (_nearbyEchoReceding || _echoPassingBy) return null;
    if (!incomingPrecip &&
        !_approachingPrecipFront &&
        !_significantEchoNearPin &&
        !_trackerSoftIncomingConfirmed) {
      return null;
    }

    var arrivalMins = _incomingArrivalMinutesFromNow();
    if (arrivalMins < 0 && _trackerSoftIncomingConfirmed) {
      arrivalMins = _trackerSoftArrivalMinutes();
    }
    if (arrivalMins < 0) return null;

    var passageH = _capPassageHours(_incomingPassageHours(), incoming: true);
    if (passageH <= 0 && _trackerSoftIncomingConfirmed) {
      passageH = 1;
    }
    if (passageH <= 0) return null;

    final arrivalAt = _incomingArrivalAt(locNow);
    final endAt = _roundLocalTimeToMinutes(
      arrivalAt.add(Duration(minutes: _incomingPassageMinutes())),
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
    return _activePrecipWindow(locNow) ?? _softTrackerPrecipWindow(locNow);
  }

  ({DateTime start, DateTime end})? _softTrackerPrecipWindow(DateTime locNow) {
    if (!_trackerSoftIncomingConfirmed) return null;
    final arrivalMins = _trackerSoftArrivalMinutes();
    if (arrivalMins < 0) return null;

    final startAt = arrivalMins <= 0
        ? _roundLocalTimeToMinutes(locNow)
        : _roundLocalTimeToMinutes(
            locNow.add(Duration(minutes: arrivalMins)),
          );
    final passageMin = math.max(_incomingPassageMinutes(), 45);
    final endAt = _roundLocalTimeToMinutes(
      startAt.add(Duration(minutes: passageMin)),
    );
    final endHour = _firstDryHourAfter(endAt);
    if (!endHour.isAfter(_localHourFloor(startAt))) return null;
    return (start: startAt, end: endHour);
  }

  DateTime? _resolvedPrecipMinuteEnd(DateTime locNow) {
    if (precipNow) return _ongoingEndAt(locNow);
    final window = _resolvedPrecipWindow(locNow);
    if (window == null) return null;
    if (_activePrecipWindow(locNow) != null) {
      return _roundLocalTimeToMinutes(
        window.start.add(Duration(minutes: _incomingPassageMinutes())),
      );
    }
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
      return dryUntilHours(3);
    }
    if (!precipNow && _nearbyEchoReceding) {
      return dryUntilHours(2);
    }

    return null;
  }

  /// Radar-only / orez: môže slot ukazovať zrážky?
  bool authorizesPrecipAtLocalHour(DateTime slotHour, DateTime locNow) {
    if (!eligible) return false;

    final nowHour = DateTime(
      locNow.year,
      locNow.month,
      locNow.day,
      locNow.hour,
    );
    if (slotHour.isBefore(nowHour)) return false;

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

    final window = _resolvedPrecipWindow(locNow);
    if (window == null) return false;
    return _hourlySlotOverlapsPrecipWindow(
      slotHour,
      window.start,
      window.end,
    );
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
    if (history.length < 2) return false;
    if (_echoClearlyOffPath || _isDisorganizedMapNoise) return false;
    if (_isRadarNoiseOnly && !_trackerMapEchoVisible) return false;
    if (_isScatteredSpeckleAtPin && !_realDirectionalFrontApproaching) {
      return false;
    }
    return _trackerSoftIncomingConfirmed;
  }

  /// Potvrdený príchod — nie len echo/šum v okolí.
  bool get _strictIncomingConfirmed => _trackerIncomingConfirmed;

  String _trackerClockLabel(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  double get _trackerIntensityDbz {
    if (precipNow) return precipIntensityDbz;
    if (_rainAtPinNow) {
      final frame = latest;
      if (frame == null) return kRadarMinDbzForUi;
      final center = frame.dbz ?? 0;
      final peak = frame.peakDbz ?? center;
      if (center >= 20) {
        return math.max(center, math.min(peak, center + 8)).clamp(12.0, 48.0);
      }
      return math.max(center, math.min(peak, center + 6)).clamp(12.0, 40.0);
    }
    return incomingIntensityDbz ??
        math.max(_maxNearbyDbz ?? kRadarMinDbzForUi, stripDisplayDbz);
  }

  RadarPrecipTrackerInfo _buildActiveTrackerInfo(
    DateTime locNow, {
    required double intensityDbz,
    required bool snow,
  }) {
    final title = _trackerIntensityTitle(intensityDbz, snow: snow);
    final iconCode = wmoFromRadarDbz(intensityDbz, snow: snow);
    final endAt = _ongoingEndAt(locNow) ??
        estimatedDryFromLocalTime(locNow) ??
        _roundLocalTimeToMinutes(
          locNow.add(Duration(minutes: _ongoingPassageMinutes())),
        );
    final remainingMin = endAt.difference(locNow).inMinutes.clamp(5, 180);
    final endLabel = _trackerClockLabel(endAt);

    final String detail;
    if (remainingMin < 55) {
      detail = 'Dážď potrvá približne ${_trackerDurationLabel(remainingMin)}, do $endLabel.';
    } else if (remainingMin <= 75) {
      detail = 'Dážď potrvá približne hodinu, do $endLabel.';
    } else {
      detail =
          'Dážď potrvá ešte približne ${_trackerDurationLabel(remainingMin)}, ustúpi o $endLabel.';
    }

    return RadarPrecipTrackerInfo(
      phase: RadarPrecipTrackerPhase.active,
      title: kRadarTrackerCardTitle,
      detail: _radarTrackerCardDetail(title, detail),
      iconCode: iconCode,
      startLocal: locNow,
      endLocal: endAt,
    );
  }

  RadarPrecipTrackerInfo _buildIncomingTrackerInfo(
    DateTime locNow, {
    required ({DateTime start, DateTime end}) window,
    required double intensityDbz,
    required bool snow,
  }) {
    final startAt = window.start;
    final endAt = window.end;
    final startLabel = _trackerClockLabel(startAt);
    final endLabel = _trackerClockLabel(endAt);
    final durationMin = endAt.difference(startAt).inMinutes.clamp(15, 180);
    final title = _trackerIntensityTitle(intensityDbz, snow: snow);
    final iconCode = wmoFromRadarDbz(intensityDbz, snow: snow);
    final atPinNow = precipNow ||
        _rainAtPinNow ||
        _trackerPrecipAtPinForCard ||
        !window.start.isAfter(_roundLocalTimeToMinutes(locNow));

    final String detail;
    if (atPinNow) {
      detail = durationMin < 55
          ? 'Dážď potrvá približne ${_trackerDurationLabel(durationMin)}, do $endLabel.'
          : 'Dážď potrvá do $endLabel.';
    } else if (durationMin < 55) {
      detail =
          'Očakávaný začiatok o $startLabel, potrvá približne ${_trackerDurationLabel(durationMin)}.';
    } else if (durationMin <= 75) {
      detail = 'Očakávaný začiatok o $startLabel, potrvá približne hodinu.';
    } else {
      detail =
          'Očakávaný začiatok o $startLabel, ústup okolo $endLabel.';
    }

    final phase = atPinNow
        ? RadarPrecipTrackerPhase.active
        : RadarPrecipTrackerPhase.incoming;
    final headline = _incomingTrackerStatusTitle(
      atPinNow: atPinNow,
      snow: snow,
      intensityDbz: intensityDbz,
      intensityTitle: title,
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

  String _trackerIntensityTitle(double dbz, {required bool snow}) {
    if (snow) {
      return dbz >= 32 ? 'Silné sneženie' : 'Slabé sneženie';
    }
    return dbz >= 36 ? 'Silný dážď' : 'Slabý dážď';
  }

  DateTime _localHourFloor(DateTime locNow) => DateTime(
        locNow.year,
        locNow.month,
        locNow.day,
        locNow.hour,
      );

  /// Karta sledovača — vždy keď je radar dostupný; pri suchu stav „sucho podľa radaru“.
  RadarPrecipTrackerInfo precipTrackerInfo(
    DateTime locNow, {
    double? tempC,
    double? cloudCoverPercent,
  }) {
    if (!eligible || history.isEmpty) {
      return _monitoringTrackerInfo(
        locNow,
        cloudCoverPercent: cloudCoverPercent,
        snow: radarSnowLikely(tempC: tempC),
        intensityDbz: kRadarMinDbzForUi,
      );
    }

    if ((_isRadarNoiseOnly || _staticDistantCellNearMap) &&
        !_trackerMapEchoVisible) {
      resetRadarTrackerStabilizer();
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.idle,
        title: kRadarTrackerCardTitle,
        detail: kRadarTrackerDryNextHourDetail,
        iconCode: skyWmoFromCloudCover(cloudCoverPercent),
      );
    }

    final snow = radarSnowLikely(tempC: tempC);
    final intensityDbz = _trackerIntensityDbz;

    // Prší pri pine — intenzita a do kedy potrvá.
    if (precipNow || _trackerPrecipAtPinForCard) {
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
    final window = _resolvedPrecipWindow(locNow);
    if (window != null &&
        _trackerSoftIncomingConfirmed &&
        effectiveDbz >= kRadarMinDbzForUi) {
      final minuteEnd = _resolvedPrecipMinuteEnd(locNow);
      if (minuteEnd != null) {
        return _buildIncomingTrackerInfo(
          locNow,
          window: (start: window.start, end: minuteEnd),
          intensityDbz: effectiveDbz,
          snow: snow,
        );
      }
    }

    return _monitoringTrackerInfo(
      locNow,
      cloudCoverPercent: cloudCoverPercent,
      snow: snow,
      intensityDbz: intensityDbz,
    );
  }

  /// Sucho / neisté echo — vždy konkrétna správa, nie prázdne „sledujem“.
  RadarPrecipTrackerInfo _monitoringTrackerInfo(
    DateTime locNow, {
    double? cloudCoverPercent,
    required bool snow,
    required double intensityDbz,
  }) {
    final icon = skyWmoFromCloudCover(cloudCoverPercent);

    if (_echoClearlyOffPath) {
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.watching,
        title: kRadarTrackerCardTitle,
        detail: 'Zrážky v okolí, ale zatiaľ mimo lokality.',
        iconCode: icon,
      );
    }

    if (_hasActiveNearbyEcho && !_significantEchoNearPin && !_rainAtPinCore) {
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.watching,
        title: kRadarTrackerCardTitle,
        detail: 'Slabé echo v okolí — zatiaľ bez dážďa pri lokalite.',
        iconCode: icon,
      );
    }

    if (_trackerMapEchoVisible) {
      final dbz = math.max(intensityDbz, _maxNearbyDbz ?? intensityDbz);
      return RadarPrecipTrackerInfo(
        phase: RadarPrecipTrackerPhase.watching,
        title: kRadarTrackerCardTitle,
        detail: 'Radar zachytáva zrážky v okolí — sledujeme vývoj.',
        iconCode: wmoFromRadarDbz(dbz, snow: snow),
      );
    }

    return RadarPrecipTrackerInfo(
      phase: RadarPrecipTrackerPhase.idle,
      title: kRadarTrackerCardTitle,
      detail: kRadarTrackerDryNextHourDetail,
      iconCode: icon,
    );
  }
}

RadarNowcastContext? _radarNowcastCache;
DateTime? _radarNowcastCacheAt;
String? _radarNowcastCacheKey;

Future<RadarNowcastContext> fetchRadarNowcastContextForCity(GeoCity city) async {
  if (!radarCoverageForCity(city)) {
    return RadarNowcastContext.inactive;
  }

  final key =
      '${city.lat.toStringAsFixed(3)}:${city.lon.toStringAsFixed(3)}:${city.countryCode}';
  final cachedAt = _radarNowcastCacheAt;
  final cacheFresh = _radarNowcastCache != null &&
      _radarNowcastCacheKey == key &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < _kRadarNowcastCacheTtl;
  if (cacheFresh) {
    final cached = _radarNowcastCache!;
    // Pri aktívnom daždi stačí cache; príchod / sledovanie vždy obnov.
    if (cached.precipNow) {
      return cached;
    }
  }

  try {
    _radarPngBytesCache.clear();
    final history = await _fetchRadarFrameHistory(city.lat, city.lon);
    final ctx = _contextFromHistory(history);
    _storeRadarNowcastCache(city, ctx);
    return ctx;
  } catch (e) {
    debugPrint('fetchRadarNowcastContextForCity: $e');
    return _radarNowcastCache ?? RadarNowcastContext.inactive;
  }
}

/// Ten istý PNG radar ako vo WebView mape — vzorkovanie v prehliadači (správne farby/súradnice).
Future<RadarNowcastContext> fetchRadarNowcastViaWebView(
  WebViewController controller,
  GeoCity city,
) async {
  if (!radarCoverageForCity(city)) {
    return RadarNowcastContext.inactive;
  }

  try {
    await ensureRadarWebViewSamplerInjected(controller);
    final httpFuture = _fetchRadarFrameHistory(city.lat, city.lon);
    final result = await controller.runJavaScriptReturningResult(
      '(async function(){ return await window.pocasieSampleRadarHistory(${city.lat}, ${city.lon}, $kRadarHistoryFramesToSample); })()',
    );
    final webHistory = _parseWebViewRadarHistory(result);
    final httpHistory = await httpFuture;
    final ctx = _contextFromBestHistories(webHistory, httpHistory);
    if (ctx.eligible) {
      _storeRadarNowcastCache(city, ctx);
    } else if (httpHistory.isNotEmpty) {
      return fetchRadarNowcastContextForCity(city);
    }
    return ctx;
  } catch (e) {
    debugPrint('fetchRadarNowcastViaWebView: $e');
    return fetchRadarNowcastContextForCity(city);
  }
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

RadarNowcastContext _contextFromHistory(List<RadarFrameSample> history) {
  if (history.isEmpty) return RadarNowcastContext.inactive;
  return RadarNowcastContext(eligible: true, history: history);
}

bool _latestFramePrecipAtPoint(List<RadarFrameSample> history) =>
    history.isNotEmpty && history.last.precipAtPoint;

double? _latestCenterDbz(List<RadarFrameSample> history) =>
    history.isEmpty ? null : history.last.dbz;

List<RadarFrameSample> _pickBestRadarHistory(
  List<RadarFrameSample>? webHistory,
  List<RadarFrameSample> httpHistory,
) {
  final web = webHistory ?? const <RadarFrameSample>[];
  final webAtPoint = _latestFramePrecipAtPoint(web);
  final httpAtPoint = _latestFramePrecipAtPoint(httpHistory);

  if (webAtPoint && !httpAtPoint) return web;
  if (httpAtPoint && !webAtPoint) return httpHistory;
  if (webAtPoint && httpAtPoint) {
    final webDbz = _latestCenterDbz(web) ?? 0;
    final httpDbz = _latestCenterDbz(httpHistory) ?? 0;
    return webDbz >= httpDbz ? web : httpHistory;
  }

  final webPeak = web.isEmpty ? 0.0 : (web.last.peakDbz ?? web.last.dbz ?? 0);
  final httpPeak = httpHistory.isEmpty
      ? 0.0
      : (httpHistory.last.peakDbz ?? httpHistory.last.dbz ?? 0);
  if (httpPeak > webPeak + 2) return httpHistory;
  if (webPeak > httpPeak + 2) return web;

  final webScore =
      web.isEmpty ? -1 : _radarHistoryWetScore(web);
  final httpScore =
      httpHistory.isEmpty ? -1 : _radarHistoryWetScore(httpHistory);
  if (httpScore > webScore) return httpHistory;
  if (webScore >= 0 && web.isNotEmpty) return web;
  if (httpHistory.isNotEmpty) return httpHistory;
  return web;
}

RadarNowcastContext _contextFromBestHistories(
  List<RadarFrameSample>? webHistory,
  List<RadarFrameSample> httpHistory,
) {
  final best = _pickBestRadarHistory(webHistory, httpHistory);
  return _contextFromHistory(best);
}

void _storeRadarNowcastCache(GeoCity city, RadarNowcastContext ctx) {
  final key =
      '${city.lat.toStringAsFixed(3)}:${city.lon.toStringAsFixed(3)}:${city.countryCode}';
  _radarNowcastCache = ctx;
  _radarNowcastCacheAt = DateTime.now();
  _radarNowcastCacheKey = key;
}

Future<void> ensureRadarWebViewSamplerInjected(WebViewController controller) async {
  await controller.runJavaScript(_kRadarWebViewSamplerJs);
}

List<RadarFrameSample>? _parseWebViewRadarHistory(Object? result) {
  if (result == null) return null;
  try {
    var raw = result is String ? result : result.toString();
    if (raw.startsWith('"') && raw.endsWith('"')) {
      raw = json.decode(raw) as String;
    }
    final decoded = json.decode(raw);
    if (decoded is! Map) return null;
    if (decoded['ok'] != true) return null;
    final frames = decoded['frames'];
    if (frames is! List) return null;

    final out = <RadarFrameSample>[];
    for (final f in frames) {
      if (f is! Map) continue;
      final m = Map<String, dynamic>.from(f);
      final unix = m['unix'] is int
          ? m['unix'] as int
          : int.tryParse('${m['unix']}') ?? 0;
      if (unix <= 0) continue;
      double? readDbz(dynamic v) =>
          v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
      out.add(RadarFrameSample(
        unix: unix,
        precip: m['precip'] == true,
        precipAtPoint: m['precipAtPoint'] == true,
        dbz: readDbz(m['dbz']),
        peakDbz: readDbz(m['peakDbz']),
        northDbz: readDbz(m['northDbz']),
        southDbz: readDbz(m['southDbz']),
        eastDbz: readDbz(m['eastDbz']),
        westDbz: readDbz(m['westDbz']),
      ));
    }
    return out.isEmpty ? null : out;
  } catch (e) {
    debugPrint('_parseWebViewRadarHistory: $e');
    return null;
  }
}

const String _kRadarWebViewSamplerJs = r'''
window.pocasieSampleRadarHistory = async function(lat, lon, frameCount) {
  const MIN_DBZ = 20, MIN_NOW = 22, CORE = 3, PEAK = 14, PEAK_WIDE = 28, OUTER = 48;
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
    const rScreen = radiusPx <= 0 ? 0 : Math.max(2, Math.min(40, Math.round(radiusPx * img.width / COLS)));
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
    const peak = peakDbz !== null ? peakDbz : centerDbz;
    if (peak === null) return false;
    if (centerDbz === null) return peak >= 32;
    const gap = peak - centerDbz;
    if (centerDbz >= MIN_NOW) {
      if (gap >= 14 && centerDbz < 14) return false;
      return true;
    }
    if (centerDbz >= 14 && peak >= 18 && gap <= 10) return true;
    if (centerDbz >= 12 && peak >= 20 && gap <= 8) return true;
    if (centerDbz >= 10 && peak >= 26 && gap <= 10) return true;
    if (centerDbz >= 8 && peak >= 32 && gap <= 12) return true;
    return false;
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
        let peak = peak14 === null ? peak28 : (peak28 === null ? peak14 : Math.max(peak14, peak28));
        const dbz = sampleCenter(img, px, py);
        if (peak !== null && (dbz === null || dbz < 12)) {
          const coherentPx = countDbzAbove(img, px, py, PEAK, 18);
          if (peak < 26 && coherentPx < 4) peak = null;
        }
        const atPoint = isPrecipAtPoint(dbz, peak);
        frames.push({
          unix: entry.unix_time,
          precip: peak !== null && peak >= MIN_DBZ,
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

  final samples = await Future.wait(
    tail.map((entry) async {
      final url = entry['url']?.toString();
      final unix = entry['unix_time'] is int
          ? entry['unix_time'] as int
          : int.tryParse('${entry['unix_time']}') ?? 0;
      if (url == null || url.isEmpty || unix <= 0) return null;
      return _sampleRadarFrameFromUrl(url, lat, lon, unix);
    }),
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
          .timeout(const Duration(seconds: 12));
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

      double? sampleRing(int dx, int dy) {
        final ring = _sampleNeighborhoodMaxDbz(
          byteData.buffer.asUint8List(),
          width,
          height,
          px + dx,
          py + dy,
          10,
        );
        return ring.dbz;
      }

      final centerDbz = center.dbz;
      final p14 = peakWide.dbz;
      final p28 = peakOuter.dbz;
      var peakDbz = p14 == null
          ? p28
          : p28 == null
              ? p14
              : math.max(p14, p28);

      // Izolovaný peak bez priestorovej súdržnosti = šum (Hlohovec / Košice).
      final rgba = byteData.buffer.asUint8List();
      final coherentPx14 = _countDbzAboveInNeighborhood(
        rgba,
        width,
        height,
        px,
        py,
        kRadarPeakCompareRadiusPx,
        18,
      );
      final coherentCorePx = _countDbzAboveInNeighborhood(
        rgba,
        width,
        height,
        px,
        py,
        kRadarCoreSampleRadiusPx,
        16,
      );
      if (peakDbz != null && (centerDbz ?? 0) < 14) {
        if (peakDbz < 30 && coherentPx14 < kRadarMinCoherentAreaPx + 1) {
          peakDbz = null;
        }
      }

      final nearbyEcho = peakDbz != null &&
          peakDbz >= kRadarMinDbzCoherentEcho &&
          coherentPx14 >= kRadarMinCoherentAreaPx;
      final atPoint = _isPrecipAtPoint(
        centerDbz: centerDbz,
        peakDbz: peakDbz,
        coherentCorePx: coherentCorePx,
        coherentPx14: coherentPx14,
      );

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
      : (radiusPx * width / kRadarImageCols).round().clamp(2, 40);

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
      : (radiusPx * width / kRadarImageCols).round().clamp(2, 40);

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

/// Prší priamo nad pinom — rovnaké pravidlá ako [RadarNowcastContext._rainAtPinNow].
bool _isPrecipAtPoint({
  required double? centerDbz,
  double? peakDbz,
  int coherentCorePx = 0,
  int coherentPx14 = 0,
}) {
  final peak = peakDbz ?? centerDbz;
  if (peak == null) return false;
  if (centerDbz == null) return peak >= 32;

  final gap = peak - centerDbz;

  if (centerDbz >= kRadarMinDbzPrecipNow) {
    if (peak - centerDbz >= 14 &&
        centerDbz < 14 &&
        coherentCorePx < kRadarMinCoherentCorePx) {
      return false;
    }
    if (coherentCorePx < kRadarMinCoherentCorePx ||
        coherentPx14 < kRadarMinCoherentAreaPx) {
      return false;
    }
    return true;
  }
  if (centerDbz >= 14 &&
      peak >= 20 &&
      gap <= 8 &&
      coherentCorePx >= kRadarMinCoherentCorePx &&
      coherentPx14 >= kRadarMinCoherentAreaPx) {
    return true;
  }
  if (centerDbz >= 12 &&
      peak >= 22 &&
      gap <= 6 &&
      coherentCorePx >= kRadarMinCoherentCorePx &&
      coherentPx14 >= kRadarMinCoherentAreaPx) {
    return true;
  }
  if (centerDbz >= 14 &&
      peak >= 18 &&
      gap <= 10 &&
      coherentPx14 >= kRadarMinCoherentAreaPx &&
      coherentCorePx >= kRadarMinCoherentCorePx) {
    return true;
  }
  // Slabý stred + silný peak v okolí = šum / fringe, nie dážď pri pine.
  if (centerDbz < kRadarMinDbzPrecipNow &&
      peak - centerDbz >= 12 &&
      coherentPx14 < kRadarMinCoherentAreaPx) {
    return false;
  }
  return false;
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
