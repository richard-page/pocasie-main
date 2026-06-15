part of 'main.dart';

const String kRadarServerBase = 'http://cz1.helkor.eu:41152';

const int kRadarImageCols = 4000;
const int kRadarImageRows = 2000;

const double kRadarMinDbzForUi = 10.0;
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

const int kRadarHistoryFramesToSample = 6;
const Duration _kRadarNowcastCacheTtl = Duration(seconds: 30);

class RadarFrameSample {
  const RadarFrameSample({
    required this.unix,
    required this.precip,
    this.precipAtPoint = false,
    this.dbz,
    this.peakDbz,
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

/// Krátky text pre kartu „Sledovač zrážok podľa radaru“.
class RadarPrecipTrackerInfo {
  const RadarPrecipTrackerInfo({
    required this.title,
    required this.detail,
    required this.iconCode,
    this.startLocal,
    this.endLocal,
  });

  final String title;
  final String detail;
  final int iconCode;
  final DateTime? startLocal;
  final DateTime? endLocal;
}

/// Radarový kontext — trend z ~30 min histórie. Cieľ: odhad **kedy zrážky skončia**.
class RadarNowcastContext {
  const RadarNowcastContext({
    required this.eligible,
    required this.history,
  });

  final bool eligible;
  final List<RadarFrameSample> history;

  static const inactive = RadarNowcastContext(eligible: false, history: []);

  RadarFrameSample? get latest => history.isEmpty ? null : history.last;

  bool get precipNow => latest?.precipAtPoint ?? false;

  int get wetScore {
    if (history.isEmpty) return -1;
    var score = 0;
    for (final frame in history) {
      if (frame.precip) score += 10;
      final dbz = frame.dbz;
      if (dbz != null) score += (dbz / 5).round();
    }
    final last = latest;
    if (last != null) {
      if (last.precipAtPoint) score += 50;
      final dbz = last.dbz;
      if (dbz != null) score += (dbz / 2).round();
    }
    return score;
  }

  /// UI reaguje len na **poslednú** radarovú snímku — nie na starú mokrú históriu.
  bool get showsPrecipForUi => precipNow;

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

  bool get _hasActiveNearbyEcho =>
      (_maxNearbyDbz ?? 0) >= 20 || (latest?.precip ?? false);

  /// Radar-only pás: echo v okolí, ale ešte nie priamo nad pinom.
  bool get nearbyEcho => !precipNow && _hasActiveNearbyEcho;

  /// Intenzita blížiacej sa / okolitej bunky pre 24 h pás.
  double? get incomingIntensityDbz {
    if (precipNow) return dbz;
    final frame = latest;
    if (frame == null) return null;

    final nearby = _maxNearbyDbz;
    if (nearby != null && nearby >= 20) return nearby;

    if (frame.peakDbz != null && frame.peakDbz! >= 20) {
      return frame.peakDbz;
    }

    final approach = _incomingApproach;
    if (approach != null && approach.dbz >= 20) return approach.dbz;

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

  bool get _hadRecentRainAtPoint => history.any((f) => f.precipAtPoint);

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

    // Aktuálne silné echo v niektorom smere = ešte prichádza (napr. z opaku).
    if (_hasActiveNearbyEcho) return false;

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
    if (precipNow) return dbz ?? kRadarMinDbzForUi;

    final center = latest?.dbz;
    if (center != null && center >= kRadarMinDbzPrecipNow) return center;

    final incoming = incomingIntensityDbz;
    if (incoming != null && incoming >= 20) {
      return math.min(incoming, 27.0);
    }
    return math.min(stripDisplayDbz, 27.0);
  }

  /// dBZ pre 24 h pás — pri blížiacej sa bunke neber max echo 48 km ďaleko.
  double get stripDisplayDbz {
    if (precipNow) return dbz ?? kRadarMinDbzForUi;

    final center = latest?.dbz;
    if (center != null && center >= kRadarMinDbzPrecipNow) return center;

    final nearby = _maxNearbyDbz;
    if (nearby != null && nearby >= 20) {
      // Pri pinom ešte sucho — miernejšia intenzita ako priamo v bunke.
      if (center == null || center < kRadarMinDbzPrecipNow) {
        return math.min(nearby, 32.0);
      }
      return nearby;
    }

    return kRadarMinDbzForUi;
  }

  /// Úzka prechádzajúca bunka (~≤30 min echo v histórii) — max 1 h v pásme.
  bool get _transientPassingCell {
    if (precipNow && steadyOngoing) return false;
    if (history.length < 2) return true;

    var echoFrames = 0;
    for (final f in history) {
      if (f.precipAtPoint || (f.peakDbz ?? 0) >= 20) echoFrames++;
    }
    if (echoFrames <= 3) return true;

    final peaks = history.map((f) => f.peakDbz).whereType<double>().toList();
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

  /// Odhad: o koľko hodín od **teraz** dorazí bunka (0 = už prší).
  int _incomingArrivalHoursFromNow() {
    if (precipNow || _nearbyEchoReceding) return -1;

    final peak = latest?.peakDbz;
    final center = latest?.dbz ?? 0;

    if (center >= kRadarMinDbzPrecipNow - 2) return 0;

    // Echo už v tesnom okolí pinu (~14 px) — typicky do 1 h, nie o polnoci.
    if (peak != null && peak >= 20 && center < kRadarMinDbzPrecipNow) {
      return 1;
    }

    final slope = _centerDbzSlopePerMin;
    if (slope != null && slope > 0.12) {
      final need = kRadarMinDbzPrecipNow - center;
      final mins = need / slope;
      return (mins / 60).ceil().clamp(1, 3);
    }

    final approach = _incomingApproach;
    if (approach == null) return -1;

    final dir = approach.dir;
    if (dir != null && history.length >= 3) {
      final oldest = history.first;
      final oldDir = oldest.dbzInDirection(dir) ?? approach.dbz;
      final newDir = approach.dbz;
      final spanMin = math.max(
        1.0,
        (history.last.unix - oldest.unix) / 60.0,
      );
      final dirSlope = (newDir - oldDir) / spanMin;
      if (dirSlope > 0.08) {
        final gap = (approach.dbz - center).clamp(8.0, 35.0);
        final mins = gap / dirSlope;
        return (mins / 60).ceil().clamp(1, 3);
      }
      if (newDir < oldDir - 4) return -1;
    }

    if (approach.dbz >= 22) return 1;
    return 1;
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
    if (endH != null) return endH.clamp(0, 3);

    if (!steadyOngoing) return 1;
    return 2;
  }

  /// Trvanie zrážok po príchode blížiacej sa bunky [h].
  int _incomingPassageHours() {
    if (_nearbyEchoReceding) return 0;
    if (precipNow) return _ongoingPassageHours();

    final intensity = incomingIntensityDbz ?? 0;
    if (intensity < 20) return 0;

    if (_transientPassingCell) return 1;

    final center = latest?.dbz ?? 0;
    final peak = latest?.peakDbz ?? intensity;

    if (center < kRadarMinDbzPrecipNow) {
      if (peak >= 40 || intensity >= 40) return 2;
      return 1;
    }
    if (intensity >= 38) return 2;
    return 1;
  }

  /// Aktívne okno zrážok pre 24 h pás (lokálne hodiny, [start, end)).
  ({DateTime start, DateTime end})? _activePrecipWindow(DateTime locNow) {
    final nowHour = DateTime(
      locNow.year,
      locNow.month,
      locNow.day,
      locNow.hour,
    );
    final stripStart = nowHour.add(const Duration(hours: 1));

    if (precipNow) {
      final passageH = _ongoingPassageHours();
      if (passageH <= 0) return null;
      return (
        start: stripStart,
        end: stripStart.add(Duration(hours: passageH)),
      );
    }

    if (_nearbyEchoReceding) return null;
    if (!incomingPrecip && !nearbyEcho) return null;

    final arrivalH = _incomingArrivalHoursFromNow();
    if (arrivalH < 0) return null;

    final passageH = _incomingPassageHours();
    if (passageH <= 0) return null;

    // Prvá hodina pásu = stripStart (22:00 pri 21:xx) — zarovnaj s riadkami UI.
    final rainStart = arrivalH <= 1
        ? stripStart
        : nowHour.add(Duration(hours: arrivalH));
    var rainEnd = rainStart.add(Duration(hours: passageH));

    if (_transientPassingCell) {
      rainEnd = rainStart.add(const Duration(hours: 1));
    } else {
      final peak = latest?.peakDbz ?? 0;
      if (peak > 0 && peak < 34) {
        final maxEnd = stripStart.add(const Duration(hours: 2));
        if (rainEnd.isAfter(maxEnd)) rainEnd = maxEnd;
      }
    }

    if (!rainEnd.isAfter(rainStart)) return null;
    return (start: rainStart, end: rainEnd);
  }

  ({String? dir, double dbz})? get _incomingApproach {
    if (precipNow || history.length < 2) return null;
    final latestFrame = latest;
    if (latestFrame == null || latestFrame.precipAtPoint) return null;

    const dirs = ['n', 's', 'e', 'w'];
    String? bestDir;
    var bestDbz = 0.0;
    for (final dir in dirs) {
      final v = latestFrame.dbzInDirection(dir);
      if (v != null && v > bestDbz) {
        bestDbz = v;
        bestDir = dir;
      }
    }
    if (bestDir != null && bestDbz >= 20) {
      return (dir: bestDir, dbz: bestDbz);
    }
    final peak = latestFrame.peakDbz;
    if (peak != null && peak >= 20) {
      return (dir: null, dbz: peak);
    }
    return null;
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
  bool get _precipDeparting {
    if (!precipNow) return false;
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

    if (!precipNow) return dryFromNextHour();

    if (_trailingDryAtPointFrames >= 1 && _hadRecentRainAtPoint) {
      return dryFromNextHour();
    }

    if (_precipDeparting && _hadRecentRainAtPoint) {
      return dryFromNextHour();
    }

    if (trendEndingAtPoint) {
      return dryFromNextHour();
    }

    final passage = _ongoingPassageHours();
    if (passage <= 0) return dryFromNextHour();
    if (passage <= 2) return dryFromHours(passage - 1);

    // Prechodná bunka (nie trvalá fronta) — ECMWF nesmie natiahnuť dážď na celé hodiny modelu.
    if (precipNow && !steadyOngoing && !incomingPrecip) {
      final wetFrames = history.where((f) => f.precipAtPoint).length;
      if (wetFrames <= 3) return dryFromNextHour();
      if (wetFrames <= 4) return dryFromHours(1);
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

    final window = _activePrecipWindow(locNow);
    if (window == null) return false;
    return !slotHour.isBefore(window.start) && slotHour.isBefore(window.end);
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
    if (precipNow || history.length < 2) return false;
    if (_nearbyEchoReceding) return false;
    final latestFrame = latest;
    if (latestFrame == null || latestFrame.precipAtPoint) return false;

    final approach = _incomingApproach;
    if (approach == null || approach.dbz < 20) return false;

    final dir = approach.dir;
    if (dir != null && history.length >= 3) {
      final oldest = history.first;
      final oldDir = oldest.dbzInDirection(dir) ?? approach.dbz;
      if (approach.dbz < oldDir - 5) return false;
    }

    final slope = _centerDbzSlopePerMin;
    if (slope != null && slope < -0.2) return false;

    if (approach.dbz >= 25) return true;

    if (!nearbyEcho) return false;

    if (dir == null) return approach.dbz >= 22;

    var approachFrames = 0;
    for (var i = history.length - 2; i >= 0 && i >= history.length - 5; i--) {
      final f = history[i];
      if (f.precipAtPoint) return false;
      final dirDbz = f.dbzInDirection(dir);
      if (dirDbz != null && dirDbz >= 16) {
        approachFrames++;
      } else {
        break;
      }
    }
    return approachFrames >= 1;
  }

  String _trackerClockLabel(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _trackerIntensityTitle(double dbz, {required bool snow}) {
    if (snow) {
      if (dbz >= 40) return 'Silné sneženie';
      if (dbz >= 28) return 'Mierne sneženie';
      return 'Slabé sneženie';
    }
    if (dbz >= 42) return 'Výdatný dážď';
    if (dbz >= 34) return 'Mierny dážď';
    if (dbz >= 26) return 'Slabý dážď';
    return 'Mrholenie';
  }

  DateTime _localHourFloor(DateTime locNow) => DateTime(
        locNow.year,
        locNow.month,
        locNow.day,
        locNow.hour,
      );

  /// Karta sledovača — aktuálny alebo blížiaci sa dážď/sneh podľa radaru.
  RadarPrecipTrackerInfo? precipTrackerInfo(
    DateTime locNow, {
    double? tempC,
  }) {
    if (!eligible || history.isEmpty) return null;
    if (_nearbyEchoReceding && !precipNow) return null;

    final snow = radarSnowLikely(tempC: tempC);
    final intensityDbz = precipNow
        ? (dbz ?? kRadarMinDbzForUi)
        : (incomingIntensityDbz ?? stripDisplayDbz);
    final iconCode = wmoFromRadarDbz(intensityDbz, snow: snow);
    final title = _trackerIntensityTitle(intensityDbz, snow: snow);
    final nowHour = _localHourFloor(locNow);
    final window = _activePrecipWindow(locNow);

    if (precipNow) {
      final passage = _ongoingPassageHours();
      if (passage <= 0 && trendEndingAtPoint) return null;

      final endAt = estimatedDryFromLocalTime(locNow) ??
          nowHour.add(Duration(hours: math.max(1, passage + 1)));
      final remainingH = endAt.difference(nowHour).inHours.clamp(1, 12);
      final endLabel = _trackerClockLabel(endAt);

      final detail = remainingH <= 1
          ? 'Potrvá približne do $endLabel.'
          : 'Bude trvať dlhšie ako hodinu, očakávaný ústup o $endLabel.';

      return RadarPrecipTrackerInfo(
        title: title,
        detail: detail,
        iconCode: iconCode,
        startLocal: nowHour,
        endLocal: endAt,
      );
    }

    if (!incomingPrecip || window == null) return null;

    final startAt = window.start;
    final endAt = window.end;
    final startLabel = _trackerClockLabel(startAt);
    final endLabel = _trackerClockLabel(endAt);
    final durationH = endAt.difference(startAt).inHours.clamp(1, 12);

    final arrivalH = _incomingArrivalHoursFromNow();
    final String detail;
    if (arrivalH <= 0) {
      detail = durationH <= 1
          ? 'Začína, potrvá približne do $endLabel.'
          : 'Začína, očakávaný ústup o $endLabel.';
    } else if (durationH <= 1) {
      detail =
          'Očakávaný začiatok o $startLabel, potrvá približne hodinu.';
    } else {
      detail =
          'Očakávaný začiatok o $startLabel, ústup okolo $endLabel.';
    }

    return RadarPrecipTrackerInfo(
      title: snow
          ? 'Blíži sa sneh'
          : (intensityDbz >= 24
              ? 'Blíži sa — ${title.toLowerCase()}'
              : 'Blíži sa dážď'),
      detail: detail,
      iconCode: iconCode,
      startLocal: startAt,
      endLocal: endAt,
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
    // Test: sucho vždy prever znova (bunka odíde); mokrý stav max 30 s.
    if (!kRadarOnlyPrecipTestMode || cached.precipNow) {
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
  const MIN_DBZ = 10, MIN_NOW = 22, PEAK = 14, OUTER = 48;
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
    if (bd > 55 * 55) return null;
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
  function isPrecipAtPoint(centerDbz, peakDbz) {
    return centerDbz !== null && centerDbz >= MIN_NOW;
  }
  function sampleCenter(img, px, py) {
    return sampleImage(img, px, py, 0);
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
    const n = Math.max(3, Math.min(frameCount || 6, 8));
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
        const peak = sampleImage(img, px, py, PEAK);
        const dbz = sampleCenter(img, px, py);
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
      final peakDbz = peakWide.dbz;
      final nearbyEcho = peakDbz != null && peakDbz >= kRadarMinDbzForUi;
      final atPoint = _isPrecipAtPoint(centerDbz: centerDbz, peakDbz: peakDbz);

      return RadarFrameSample(
        unix: frameUnix,
        precip: nearbyEcho,
        precipAtPoint: atPoint,
        dbz: centerDbz,
        peakDbz: peakDbz,
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

({double? dbz}) _sampleCenterDbz(
  Uint8List rgba,
  int width,
  int height,
  int centerPx,
  int centerPy,
) {
  return _sampleNeighborhoodMaxDbz(rgba, width, height, centerPx, centerPy, 0);
}

/// Prší priamo nad pinom — stredový pixel ≥ 22 dBZ (peak v okolí neovplyvňuje).
bool _isPrecipAtPoint({required double? centerDbz, double? peakDbz}) {
  return centerDbz != null && centerDbz >= kRadarMinDbzPrecipNow;
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
  if (bestDist > 55 * 55) return null;
  return bestDbz;
}

bool _isRadarCoverageBorderPixel(int r, int g, int b, int a) {
  if (a < 40) return true;
  if (r > 230 && g > 230 && b > 230) return true;
  if (r < 25 && g < 25 && b < 35) return true;
  if (r > 90 && b > 90 && g < 60) return true;
  return false;
}
