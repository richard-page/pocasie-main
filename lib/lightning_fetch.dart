part of 'main.dart';

const String kLightningGeoJsonUrl =
    'https://meteopocasie.sk/data/eumet/blesky.json';

/// Okruh okolo lokality (km) — EUMET blesky pre celú EU.
const double kLightningNearbyRadiusKm = 60;

/// V JSON berieme len výboje mladšie ako N minút — staršie už nie sú „aktuálna búrka“.
const int kLightningFreshStrikeMaxAgeMinutes = 12;

/// Pri výpadku siete krátka rezerva od posledného výboja (nie hodina).
const int kLightningOfflineGraceMinutes = 10;

const Duration _kLightningCacheTtl = Duration(minutes: 2);

/// Približný rozsah EUMET detekcie bleskov (mimo EU sa JSON nepoužíva).
bool isInEuLightningRegion(double lat, double lon) {
  return lat >= 34.0 && lat <= 72.0 && lon >= -12.0 && lon <= 45.0;
}

List<Map<String, dynamic>>? _lightningFeaturesCache;
DateTime? _lightningCacheFetchedAt;

Future<void> _ensureLightningGeoJsonLoaded() async {
  final cachedAt = _lightningCacheFetchedAt;
  if (_lightningFeaturesCache != null &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < _kLightningCacheTtl) {
    return;
  }

  final response = await http.get(
    Uri.parse(kLightningGeoJsonUrl),
    headers: const {
      'Accept': 'application/json',
      'User-Agent': 'pocasie-app/1.0 (flutter)',
    },
  ).timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    throw HttpException('Lightning HTTP ${response.statusCode}');
  }

  final decoded = json.decode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Lightning JSON root is not an object');
  }

  final rawFeatures = decoded['features'];
  if (rawFeatures is! List) {
    _lightningFeaturesCache = const [];
  } else {
    _lightningFeaturesCache = rawFeatures
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
  _lightningCacheFetchedAt = DateTime.now();
}

int? _lightningStrikeEpochSec(Map<String, dynamic> feature) {
  final props = feature['properties'];
  if (props is! Map) return null;
  final map = Map<String, dynamic>.from(props);
  final timeSec = map['time_sec'];
  if (timeSec is num) return timeSec.toInt();
  final unix = map['unixTime'] ?? map['time'];
  if (unix is num) {
    final v = unix.toInt();
    return v > 9999999999 ? v ~/ 1000 : v;
  }
  return null;
}

(double lon, double lat)? _lightningStrikeLonLat(Map<String, dynamic> feature) {
  final geometry = feature['geometry'];
  if (geometry is! Map) return null;
  final coords = geometry['coordinates'];
  if (coords is! List || coords.length < 2) return null;
  final lon = coords[0];
  final lat = coords[1];
  if (lon is! num || lat is! num) return null;
  return (lon.toDouble(), lat.toDouble());
}

Future<void> _persistLastNearbyStrike(int strikeSec, double lat, double lon) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kLightningNearbyLatchAtKey, strikeSec);
  await prefs.setDouble(kLightningNearbyLatchLatKey, lat);
  await prefs.setDouble(kLightningNearbyLatchLonKey, lon);
}

Future<void> _clearLightningNearbyLatch([SharedPreferences? prefs]) async {
  final p = prefs ?? await SharedPreferences.getInstance();
  await p.remove(kLightningNearbyLatchAtKey);
  await p.remove(kLightningNearbyLatchLatKey);
  await p.remove(kLightningNearbyLatchLonKey);
}

Future<bool> _lightningOfflineGraceActive(double lat, double lon) async {
  final prefs = await SharedPreferences.getInstance();
  final strikeSec = prefs.getInt(kLightningNearbyLatchAtKey);
  if (strikeSec == null) return false;

  final latchLat = prefs.getDouble(kLightningNearbyLatchLatKey);
  final latchLon = prefs.getDouble(kLightningNearbyLatchLonKey);
  if (latchLat == null || latchLon == null) return false;

  final maxDistM = kLightningNearbyRadiusKm * 1000.0 * 1.5;
  if (Geolocator.distanceBetween(lat, lon, latchLat, latchLon) > maxDistM) {
    return false;
  }

  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final ageMinutes = (nowSec - strikeSec) / 60.0;
  if (ageMinutes > kLightningOfflineGraceMinutes) {
    await _clearLightningNearbyLatch(prefs);
    return false;
  }
  return true;
}

bool _lightningStrikeNearLocation(
  Map<String, dynamic> feature,
  double lat,
  double lon,
  int nowSec,
  int minSec,
  double radiusM,
) {
  final strikeSec = _lightningStrikeEpochSec(feature);
  if (strikeSec == null || strikeSec < minSec) return false;

  final point = _lightningStrikeLonLat(feature);
  if (point == null) return false;

  final strikeLat = point.$2;
  final strikeLon = point.$1;
  final latDelta = radiusM / 111000.0;
  final lonDelta =
      radiusM / (111000.0 * math.cos(lat * math.pi / 180.0)).abs().clamp(0.25, 1.0);

  if (strikeLat < lat - latDelta ||
      strikeLat > lat + latDelta ||
      strikeLon < lon - lonDelta ||
      strikeLon > lon + lonDelta) {
    return false;
  }

  return Geolocator.distanceBetween(lat, lon, strikeLat, strikeLon) <= radiusM;
}

/// Najnovší výboj v okruhu za posledných [maxAgeMinutes] minút, alebo `null`.
int? _newestNearbyStrikeEpochSec(
  List<Map<String, dynamic>> features,
  double lat,
  double lon, {
  required int maxAgeMinutes,
  required double radiusKm,
}) {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final minSec = nowSec - maxAgeMinutes * 60;
  final radiusM = radiusKm * 1000.0;
  int? newest;

  for (final feature in features) {
    if (!_lightningStrikeNearLocation(feature, lat, lon, nowSec, minSec, radiusM)) {
      continue;
    }
    final strikeSec = _lightningStrikeEpochSec(feature);
    if (strikeSec == null) continue;
    if (newest == null || strikeSec > newest) newest = strikeSec;
  }
  return newest;
}

/// `true` ak je v okruhu čerstvý blesk z [kLightningGeoJsonUrl] (EUMET, len EU).
/// Ikona zmizne, keď v JSON už nie sú nové výboje — nie po hodine.
Future<bool> lightningDetectedNear(
  double lat,
  double lon, {
  double radiusKm = kLightningNearbyRadiusKm,
  int maxAgeMinutes = kLightningFreshStrikeMaxAgeMinutes,
}) async {
  if (!isInEuLightningRegion(lat, lon)) {
    await _clearLightningNearbyLatch();
    return false;
  }

  try {
    await _ensureLightningGeoJsonLoaded();
  } catch (e) {
    debugPrint('Lightning fetch failed: $e');
    return _lightningOfflineGraceActive(lat, lon);
  }

  final features = _lightningFeaturesCache;
  if (features == null || features.isEmpty) {
    await _clearLightningNearbyLatch();
    return false;
  }

  final newestStrikeSec = _newestNearbyStrikeEpochSec(
    features,
    lat,
    lon,
    maxAgeMinutes: maxAgeMinutes,
    radiusKm: radiusKm,
  );

  if (newestStrikeSec != null) {
    await _persistLastNearbyStrike(newestStrikeSec, lat, lon);
    return true;
  }

  await _clearLightningNearbyLatch();
  return false;
}
