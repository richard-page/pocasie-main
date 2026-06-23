part of 'main.dart';

/// Voľné RainViewer API — zdroj zrážkovej predpovede (mapa v UI ostáva SHMÚ/Helkor).
const String kRainViewerMapsApiUrl =
    'https://api.rainviewer.com/public/weather-maps.json';
const int kRainViewerColorScheme = 2; // Universal Blue
const int kRainViewerTileZoom = 7;
const int kRainViewerTileSize = 512;
const int kRainViewerMaxPastFrames = 13; // ~2 h histórie po 10 min
const Duration _kRainViewerMapsCacheTtl = Duration(seconds: 90);

/// Vzorkovacie okná na 512 px tile (RainViewer lat/lon tile).
const int kRainViewerCoreRadiusPx = 12;
const int kRainViewerPeakRadiusPx = 48;
const int kRainViewerOuterRadiusPx = 96;
const int kRainViewerDirectionalOffsetPx = 72;
const double kRainViewerMinDbzEcho = 15.0;
const double kRainViewerMinDbzAtPin = 15.0;
/// RainViewer legenda — pod 15 dBZ / 0,3 mm/h = žiadne zrážky.
const double kRainViewerLegendMinDbz = 15.0;
const double kRainViewerLegendDrizzleDbz = 15.0;
const double kRainViewerLegendLightRainDbz = 20.0;
const double kRainViewerLegendModerateRainDbz = 30.0;
const double kRainViewerLegendHeavyRainDbz = 40.0;
const double kRainViewerLegendLightSnowDbz = 15.0;
const double kRainViewerLegendModerateSnowDbz = 22.0;
const double kRainViewerLegendHeavySnowDbz = 30.0;

/// mm/h podľa RainViewer legendy (15→0,3 · 20→1,3 · 30→3 · 40→12).
double rainViewerMmFromDbz(double dbz) {
  if (dbz < kRainViewerLegendMinDbz) return 0;
  if (dbz < kRainViewerLegendLightRainDbz) {
    return 0.3 +
        (dbz - kRainViewerLegendDrizzleDbz) /
            (kRainViewerLegendLightRainDbz - kRainViewerLegendDrizzleDbz) *
            (1.3 - 0.3);
  }
  if (dbz < kRainViewerLegendModerateRainDbz) {
    return 1.3 +
        (dbz - kRainViewerLegendLightRainDbz) /
            (kRainViewerLegendModerateRainDbz - kRainViewerLegendLightRainDbz) *
            (3.0 - 1.3);
  }
  if (dbz < kRainViewerLegendHeavyRainDbz) {
    return 3.0 +
        (dbz - kRainViewerLegendModerateRainDbz) /
            (kRainViewerLegendHeavyRainDbz - kRainViewerLegendModerateRainDbz) *
            (12.0 - 3.0);
  }
  return (12.0 + (dbz - kRainViewerLegendHeavyRainDbz) * 0.35)
      .clamp(12.0, 25.0);
}

/// % šanca — od 15 dBZ (mrholenie) min. 50 %; stupne po 10 % podľa legendy.
int rainViewerProbPercentFromDbz(double dbz) {
  if (dbz < kRainViewerLegendMinDbz) return 0;
  if (dbz < kRainViewerLegendLightRainDbz) return kMinPrecipProbPercent;
  if (dbz < kRainViewerLegendModerateRainDbz) return 60;
  if (dbz < kRainViewerLegendHeavyRainDbz) return 80;
  return 90;
}

/// dBZ z palety — bez umelého znižovania (legenda mapy).
double rainViewerDbzForUi(double rawDbz) => rawDbz.clamp(0.0, 60.0);

/// Intenzita pri pine — stred pinu; ak je slabý, peak v okolí (legenda od 15 dBZ).
double rainViewerIntensityDbz({
  required double? center,
  required double? peak,
  required bool atPoint,
}) {
  final c = center ?? 0;
  final p = peak ?? c;
  if (c >= kRainViewerLegendMinDbz) return c;
  if (atPoint && p >= kRainViewerLegendMinDbz) return p;
  if (p >= kRainViewerLegendMinDbz) {
    return math.max(c, math.min(p, c + 5));
  }
  return math.max(c, p);
}

/// RainViewer neodlišuje dážď od snehu — sneh len pri mraze a silnejšom echo.
bool rainViewerSnowLikely({
  double? tempC,
  double snowfallCm = 0.0,
  double uiDbz = 0,
}) {
  if (snowfallCm >= 0.1) return true;
  return tempC != null && tempC <= -1.5 && uiDbz >= 20;
}

int wmoFromRainViewerDbz(double dbz, {required bool snow}) {
  if (snow) {
    if (dbz >= kRainViewerLegendHeavySnowDbz) return 75;
    if (dbz >= kRainViewerLegendModerateSnowDbz) return 73;
    if (dbz >= kRainViewerLegendLightSnowDbz) return 71;
    return 51;
  }
  if (dbz >= kRainViewerLegendHeavyRainDbz) return 65;
  if (dbz >= kRainViewerLegendModerateRainDbz) return 63;
  if (dbz >= kRainViewerLegendLightRainDbz) return 61;
  if (dbz >= kRainViewerLegendMinDbz) return 53;
  return 51;
}

class _RainViewerBlueStop {
  const _RainViewerBlueStop(this.dbz, this.r, this.g, this.b);
  final double dbz;
  final int r;
  final int g;
  final int b;
}

/// Universal Blue paleta — https://www.rainviewer.com/files/rainviewer_api_colors_table.csv
const List<_RainViewerBlueStop> _kRainViewerBlueStops = [
  _RainViewerBlueStop(-5, 114, 110, 97),
  _RainViewerBlueStop(0, 130, 123, 105),
  _RainViewerBlueStop(3, 139, 130, 89),
  _RainViewerBlueStop(5, 146, 136, 113),
  _RainViewerBlueStop(8, 182, 168, 130),
  _RainViewerBlueStop(10, 206, 192, 135),
  _RainViewerBlueStop(12, 214, 200, 143),
  _RainViewerBlueStop(15, 136, 221, 238),
  _RainViewerBlueStop(17, 81, 197, 232),
  _RainViewerBlueStop(20, 0, 163, 224),
  _RainViewerBlueStop(22, 0, 145, 202),
  _RainViewerBlueStop(25, 0, 119, 170),
  _RainViewerBlueStop(28, 0, 98, 149),
  _RainViewerBlueStop(30, 0, 85, 136),
  _RainViewerBlueStop(33, 56, 143, 4),
  _RainViewerBlueStop(35, 255, 238, 0),
  _RainViewerBlueStop(38, 255, 197, 0),
  _RainViewerBlueStop(40, 255, 170, 0),
  _RainViewerBlueStop(43, 255, 139, 0),
  _RainViewerBlueStop(45, 255, 68, 0),
  _RainViewerBlueStop(50, 193, 0, 0),
  _RainViewerBlueStop(55, 255, 170, 255),
];

Map<String, dynamic>? _rainViewerMapsJson;
DateTime? _rainViewerMapsJsonAt;
final Map<String, Uint8List> _rainViewerTileBytesCache = {};

class _RainViewerApiMeta {
  const _RainViewerApiMeta({
    required this.host,
    required this.pastFrames,
    required this.nowcastFrames,
  });

  final String host;
  final List<Map<String, dynamic>> pastFrames;
  final List<Map<String, dynamic>> nowcastFrames;
}

Future<_RainViewerApiMeta?> _fetchRainViewerApiMeta() async {
  final cachedAt = _rainViewerMapsJsonAt;
  if (_rainViewerMapsJson != null &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < _kRainViewerMapsCacheTtl) {
    return _parseRainViewerApiMeta(_rainViewerMapsJson!);
  }

  final response = await http
      .get(
        Uri.parse(kRainViewerMapsApiUrl),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'pocasie-app/1.0 (flutter)',
        },
      )
      .timeout(const Duration(seconds: 12));

  if (response.statusCode != 200) {
    throw HttpException('RainViewer maps HTTP ${response.statusCode}');
  }

  final decoded = json.decode(response.body);
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);
  _rainViewerMapsJson = map;
  _rainViewerMapsJsonAt = DateTime.now();
  return _parseRainViewerApiMeta(map);
}

_RainViewerApiMeta? _parseRainViewerApiMeta(Map<String, dynamic> map) {
  final host = map['host']?.toString();
  if (host == null || host.isEmpty) return null;

  final radar = map['radar'];
  if (radar is! Map) return null;
  final past = radar['past'];
  if (past is! List || past.isEmpty) return null;

  final frames = past
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((e) =>
          e['path']?.toString().isNotEmpty == true &&
          e['time'] != null)
      .toList();
  if (frames.isEmpty) return null;

  final nowcastRaw = radar['nowcast'];
  final nowcastFrames = nowcastRaw is List
      ? nowcastRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) =>
              e['path']?.toString().isNotEmpty == true &&
              e['time'] != null)
          .toList()
      : <Map<String, dynamic>>[];

  return _RainViewerApiMeta(
    host: host,
    pastFrames: frames,
    nowcastFrames: nowcastFrames,
  );
}

String _rainViewerLatLonTileUrl(
  String host,
  String path,
  double lat,
  double lon,
) {
  final latStr = lat.toString();
  final lonStr = lon.toString();
  return '$host$path/$kRainViewerTileSize/$kRainViewerTileZoom/$latStr/$lonStr/$kRainViewerColorScheme/1_1.png';
}

/// História radarových snímok z RainViewer API pre danú lokalitu.
Future<List<RadarFrameSample>> fetchRainViewerFrameHistory(
  double lat,
  double lon,
) async {
  final meta = await _fetchRainViewerApiMeta();
  if (meta == null) return const [];

  final frames = meta.pastFrames;
  final maxFrames = math.min(kRainViewerMaxPastFrames, kRadarHistoryFramesToSample);
  final tail = frames.length > maxFrames
      ? frames.sublist(frames.length - maxFrames)
      : frames;

  final samples = await Future.wait(
    tail.map((entry) async {
      final path = entry['path']?.toString();
      final time = entry['time'] is int
          ? entry['time'] as int
          : int.tryParse('${entry['time']}') ?? 0;
      if (path == null || path.isEmpty || time <= 0) return null;
      final url = _rainViewerLatLonTileUrl(meta.host, path, lat, lon);
      return _sampleRainViewerFrameFromUrl(url, lat, lon, time);
    }),
  );
  return samples.whereType<RadarFrameSample>().toList();
}

/// RainViewer nowcast — krátkodobá predpoveď pohybu zrážok (~2 h dopredu).
Future<List<RadarFrameSample>> fetchRainViewerNowcastHistory(
  double lat,
  double lon,
) async {
  final meta = await _fetchRainViewerApiMeta();
  if (meta == null || meta.nowcastFrames.isEmpty) return const [];

  const maxFrames = 12;
  final tail = meta.nowcastFrames.length > maxFrames
      ? meta.nowcastFrames.sublist(meta.nowcastFrames.length - maxFrames)
      : meta.nowcastFrames;

  final samples = await Future.wait(
    tail.map((entry) async {
      final path = entry['path']?.toString();
      final time = entry['time'] is int
          ? entry['time'] as int
          : int.tryParse('${entry['time']}') ?? 0;
      if (path == null || path.isEmpty || time <= 0) return null;
      final url = _rainViewerLatLonTileUrl(meta.host, path, lat, lon);
      return _sampleRainViewerFrameFromUrl(url, lat, lon, time);
    }),
  );
  return samples.whereType<RadarFrameSample>().toList();
}

Future<RadarFrameSample?> _sampleRainViewerFrameFromUrl(
  String url,
  double lat,
  double lon,
  int frameUnix,
) async {
  try {
    Uint8List bytes;
    final cached = _rainViewerTileBytesCache[url];
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
      if (_rainViewerTileBytesCache.length > 32) {
        _rainViewerTileBytesCache.clear();
      }
      _rainViewerTileBytesCache[url] = bytes;
    }
    return _sampleRainViewerFrameFromBytes(bytes, lat, lon, frameUnix);
  } catch (e) {
    debugPrint('_sampleRainViewerFrameFromUrl: $e');
    return null;
  }
}

Future<RadarFrameSample?> _sampleRainViewerFrameFromBytes(
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

      final px = width ~/ 2;
      final py = height ~/ 2;
      final rgba = byteData.buffer.asUint8List();

      final center = _rainViewerSampleNeighborhoodMaxDbz(
        rgba,
        width,
        height,
        px,
        py,
        kRainViewerCoreRadiusPx,
      );
      final peakWide = _rainViewerSampleNeighborhoodMaxDbz(
        rgba,
        width,
        height,
        px,
        py,
        kRainViewerPeakRadiusPx,
      );
      final peakOuter = _rainViewerSampleNeighborhoodMaxDbz(
        rgba,
        width,
        height,
        px,
        py,
        kRainViewerOuterRadiusPx,
      );

      double? sampleRing(int dx, int dy) {
        final ring = _rainViewerSampleNeighborhoodMaxDbz(
          rgba,
          width,
          height,
          px + dx,
          py + dy,
          24,
        );
        return ring.dbz;
      }

      final centerDbz = center.dbz;
      final p48 = peakWide.dbz;
      final p96 = peakOuter.dbz;
      final peakInner = p48 ?? centerDbz;
      var peakDbz = [peakInner, p96]
          .whereType<double>()
          .fold<double?>(null, (m, v) => m == null ? v : math.max(m, v));

      final coherentPx12 = _rainViewerCountDbzAboveInNeighborhood(
        rgba,
        width,
        height,
        px,
        py,
        kRainViewerPeakRadiusPx,
        12,
      );
      final coherentCorePx = _rainViewerCountDbzAboveInNeighborhood(
        rgba,
        width,
        height,
        px,
        py,
        kRainViewerCoreRadiusPx,
        10,
      );

      // Len jadro / blízke okolie pinu — nie izolované bunky v 96px diali (šum na mape).
      final nearbyEcho = (peakInner ?? 0) >= kRainViewerLegendMinDbz;
      // Len stred pinu (12 px) — nie peak v diali; inak falošný dážď pri suchom mieste.
      final atPoint = (centerDbz ?? 0) >= kRainViewerLegendMinDbz;

      return RadarFrameSample(
        unix: frameUnix,
        precip: nearbyEcho,
        precipAtPoint: atPoint,
        dbz: centerDbz ?? peakDbz,
        peakDbz: peakDbz,
        coherentPx14: coherentPx12,
        coherentCorePx: coherentCorePx,
        northDbz: sampleRing(0, -kRainViewerDirectionalOffsetPx),
        southDbz: sampleRing(0, kRainViewerDirectionalOffsetPx),
        eastDbz: sampleRing(kRainViewerDirectionalOffsetPx, 0),
        westDbz: sampleRing(-kRainViewerDirectionalOffsetPx, 0),
      );
    } finally {
      image.dispose();
    }
  } catch (e) {
    debugPrint('_sampleRainViewerFrameFromBytes: $e');
    return null;
  }
}

int _rainViewerRadiusPx(int radiusPx) => radiusPx.clamp(4, 96);

({double? dbz}) _rainViewerSampleNeighborhoodMaxDbz(
  Uint8List rgba,
  int width,
  int height,
  int sx,
  int sy,
  int radiusPx,
) {
  final radiusScreen = _rainViewerRadiusPx(radiusPx);
  double? maxDbz;
  for (var dy = -radiusScreen; dy <= radiusScreen; dy++) {
    for (var dx = -radiusScreen; dx <= radiusScreen; dx++) {
      if (dx * dx + dy * dy > radiusScreen * radiusScreen) continue;
      final x = (sx + dx).clamp(0, width - 1);
      final y = (sy + dy).clamp(0, height - 1);
      final offset = (y * width + x) * 4;
      if (offset + 3 >= rgba.length) continue;
      final dbz = _estimateDbzFromRainViewerPixel(
        rgba[offset],
        rgba[offset + 1],
        rgba[offset + 2],
        rgba[offset + 3],
      );
      if (dbz != null) {
        maxDbz = maxDbz == null ? dbz : math.max(maxDbz, dbz);
      }
    }
  }
  return (dbz: maxDbz);
}

int _rainViewerCountDbzAboveInNeighborhood(
  Uint8List rgba,
  int width,
  int height,
  int sx,
  int sy,
  int radiusPx,
  double minDbz,
) {
  final radiusScreen = _rainViewerRadiusPx(radiusPx);
  var count = 0;
  for (var dy = -radiusScreen; dy <= radiusScreen; dy++) {
    for (var dx = -radiusScreen; dx <= radiusScreen; dx++) {
      if (dx * dx + dy * dy > radiusScreen * radiusScreen) continue;
      final x = (sx + dx).clamp(0, width - 1);
      final y = (sy + dy).clamp(0, height - 1);
      final offset = (y * width + x) * 4;
      if (offset + 3 >= rgba.length) continue;
      final dbz = _estimateDbzFromRainViewerPixel(
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

double? _estimateDbzFromRainViewerPixel(int r, int g, int b, int a) {
  if (a < 24) return null;
  if (r > 240 && g > 240 && b > 240) return null;
  if (r + g + b < 60) return null;

  var bestDbz = _kRainViewerBlueStops.first.dbz;
  var bestDist = double.infinity;
  for (final stop in _kRainViewerBlueStops) {
    final dr = r - stop.r;
    final dg = g - stop.g;
    final db = b - stop.b;
    final dist = (dr * dr + dg * dg + db * db).toDouble();
    if (dist < bestDist) {
      bestDist = dist;
      bestDbz = stop.dbz;
    }
  }
  if (bestDist > 60 * 60) return null;
  if (bestDbz <= 3 && bestDist > 32 * 32) return null;
  return bestDbz;
}
