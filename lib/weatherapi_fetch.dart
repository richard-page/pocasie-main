part of 'main.dart';

Future<List<GeoCity>> _searchWeatherApi(String q) async {
  if (kWeatherApiKey.isEmpty || q.trim().isEmpty) return [];
  try {
    final uri = Uri.parse('$kWeatherApiBase/search.json').replace(
      queryParameters: <String, String>{
        'key': kWeatherApiKey,
        'q': q.trim(),
      },
    );
    final r = await http.get(uri).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return [];
    final data = json.decode(r.body);
    if (data is! List) return [];
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) _geoCityFromWeatherApiSearch(item),
    ];
  } catch (e) {
    debugPrint('WeatherAPI search failed: $e');
    return [];
  }
}

GeoCity _geoCityFromWeatherApiSearch(Map<String, dynamic> json) {
  final country = json['country']?.toString() ?? '';
  final rawCode = json['country_code']?.toString() ??
      json['countryCode']?.toString() ??
      '';
  final countryCode = rawCode.trim().isNotEmpty
      ? rawCode.trim().toUpperCase()
      : weatherApiCountryCodeFromName(country);
  return GeoCity(
    name: json['name']?.toString() ?? '',
    lat: (weatherApiNum(json['lat']) ?? 0).toDouble(),
    lon: (weatherApiNum(json['lon']) ?? 0).toDouble(),
    country: country,
    countryCode: countryCode,
    admin1: json['region']?.toString() ?? '',
    admin2: '',
    timezone: 'auto',
  );
}

/// Maximálna vzdialenosť GPS ↔ WeatherAPI hit; inak null → Open-Meteo reverse.
const double _kWeatherApiReverseMaxDistanceM = 75000;

Future<GeoCity?> _reverseGeocodeWeatherApi(double lat, double lon) async {
  if (kWeatherApiKey.isEmpty) return null;
  try {
    final uri = Uri.parse('$kWeatherApiBase/search.json').replace(
      queryParameters: <String, String>{
        'key': kWeatherApiKey,
        'q': '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}',
      },
    );
    final r = await http
        .get(uri)
        .timeout(const Duration(seconds: 4));
    if (r.statusCode != 200) return null;
    final data = json.decode(r.body);
    if (data is! List || data.isEmpty) return null;

    // Ber najbližší hit podľa lat/lon mesta — nie slepo data.first.
    GeoCity? best;
    var bestDist = double.infinity;
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final candidate = _geoCityFromWeatherApiSearch(item);
      if (candidate.name.trim().isEmpty) continue;
      if (candidate.lat == 0 && candidate.lon == 0) continue;
      final dist = Geolocator.distanceBetween(
        lat,
        lon,
        candidate.lat,
        candidate.lon,
      );
      if (dist < bestDist) {
        bestDist = dist;
        best = candidate;
      }
    }
    if (best == null || bestDist > _kWeatherApiReverseMaxDistanceM) {
      return null;
    }

    return GeoCity(
      name: best.name,
      lat: lat,
      lon: lon,
      country: best.country,
      countryCode: best.countryCode,
      admin1: best.admin1,
      admin2: best.admin2,
      timezone: 'auto',
    );
  } catch (e) {
    debugPrint('WeatherAPI reverse geocode failed: $e');
    return null;
  }
}

int? _weatherApiUtcOffsetSeconds(String? tzId) {
  if (tzId == null || tzId.isEmpty) return null;
  try {
    final loc = tz.getLocation(tzId);
    final now = tz.TZDateTime.now(loc);
    return now.timeZoneOffset.inSeconds;
  } catch (_) {
    return null;
  }
}

bool _weatherApiJsonHasHourlyWindow(Map<String, dynamic> map) {
  final hourly = map['hourly'];
  if (hourly is! Map) return false;
  final times = hourly['time'];
  if (times is! List || times.isEmpty) return false;
  if (map['source_provider'] == 'weatherapi') {
    return times.length >= 24;
  }
  return forecastJsonHas24HourWindow(map);
}

/// Stiahne predpoveď z WeatherAPI a vráti ju v Open-Meteo tvare.
Future<Map<String, dynamic>?> _downloadWeatherApiForecast(
  double lat,
  double lon,
  String timezone, {
  required bool forceRefresh,
}) async {
  final cacheKey = weatherApiForecastCacheKey(lat, lon);
  debugPrint('WeatherAPI: cache key $cacheKey for lat=$lat, lon=$lon');

  if (!forceRefresh) {
    final cachedJson = await CacheManager.getWeather(lat, lon, cacheKey);
    if (cachedJson != null) {
      try {
        final cached = json.decode(cachedJson) as Map<String, dynamic>;
        if (cached['error'] != true &&
            cached.containsKey('hourly') &&
            forecastJsonDailyHorizonComplete(cached) &&
            _weatherApiJsonHasHourlyWindow(cached)) {
          debugPrint('WeatherAPI: using cached data for $lat,$lon');
          return cached;
        }
      } catch (_) {}
    }
  }

  try {
    final map = await downloadWeatherApiForecastMap(lat, lon);
    if (map == null) {
      debugPrint('WeatherAPI: fetch failed for $lat,$lon');
      return null;
    }

    final tzId = map['timezone']?.toString();
    if (map['utc_offset_seconds'] == null) {
      map['utc_offset_seconds'] = _weatherApiUtcOffsetSeconds(
        tzId == 'auto' ? null : tzId,
      );
    }

    await CacheManager.saveWeather(lat, lon, cacheKey, json.encode(map));
    debugPrint(
      'WeatherAPI: OK '
      '${forecastJsonUpcomingHourlyCount(map)} budúcich hodín, '
      '${(map['daily'] as Map?)?['time']?.length ?? 0} dní',
    );
    return map;
  } catch (e) {
    debugPrint('WeatherAPI fetch failed: $e');
    return null;
  }
}
