part of 'main.dart';

const String _kOpenMeteoHourlyVars =
    'temperature_2m,cloud_cover,precipitation,precipitation_probability,weather_code,wind_speed_10m,wind_direction_10m,relative_humidity_2m,apparent_temperature,pressure_msl,uv_index,wind_gusts_10m,dew_point_2m';

const String _kOpenMeteoDailyVars =
    'temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset,precipitation_sum,precipitation_probability_max,uv_index_max,wind_speed_10m_max';

const String _kOpenMeteoCurrentVars =
    'temperature_2m,is_day,weather_code,cloud_cover,precipitation,wind_speed_10m,wind_direction_10m,relative_humidity_2m,apparent_temperature,pressure_msl,uv_index';

String _openMeteoCacheKey(
  double lat,
  double lon,
  WeatherForecastModel model,
) =>
    'om_${model.cacheKey}_v${kForecastCacheSchemaVersion}_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}_fd$kOpenMeteoForecastDays';

Map<String, dynamic> _normalizeOpenMeteoForecast(
  Map<String, dynamic> raw,
  WeatherForecastModel model,
) {
  return {
    ...raw,
    'precipitation_probability_available': true,
    'source': model.uiTitle,
    'model': model.cacheKey,
  };
}

Uri _openMeteoForecastUri(
  double lat,
  double lon,
  String timezone,
  WeatherForecastModel model,
) {
  final tz = _normalizeApiTimezone(timezone);
  final params = <String, String>{
    'latitude': lat.toStringAsFixed(4),
    'longitude': lon.toStringAsFixed(4),
    'hourly': _kOpenMeteoHourlyVars,
    'daily': _kOpenMeteoDailyVars,
    'current': _kOpenMeteoCurrentVars,
    'forecast_days': kOpenMeteoForecastDays.toString(),
    'timezone': tz,
  };
  // Najlepší výber = predvolené API bez `models` (Open-Meteo seamless mix).
  if (model.apiModels != null && model.apiModels!.isNotEmpty) {
    params['models'] = model.apiModels!;
  }
  return Uri.parse(model.apiBase).replace(queryParameters: params);
}

/// Stiahne predpoveď z Open-Meteo API podľa zvoleného modelu.
Future<Map<String, dynamic>?> _downloadOpenMeteoForecast(
  double lat,
  double lon,
  String timezone, {
  required WeatherForecastModel model,
  required bool forceRefresh,
}) async {
  final cacheKey = _openMeteoCacheKey(lat, lon, model);
  debugPrint(
    'Open-Meteo (${model.uiTitle}): cache key $cacheKey for lat=$lat, lon=$lon',
  );

  if (!forceRefresh) {
    final cachedJson = await CacheManager.getWeather(lat, lon, cacheKey);
    if (cachedJson != null) {
      try {
        final cached = json.decode(cachedJson) as Map<String, dynamic>;
        if (cached['error'] != true &&
            cached.containsKey('hourly') &&
            forecastJsonDailyHorizonComplete(cached) &&
            forecastJsonHas24HourWindow(cached)) {
          debugPrint('Open-Meteo (${model.uiTitle}): using cached data for $lat,$lon');
          return cached;
        }
        if (cached.containsKey('hourly') &&
            !forecastJsonHas24HourWindow(cached)) {
          debugPrint(
            'Open-Meteo (${model.uiTitle}): cache bez 24 h '
            '(${forecastJsonUpcomingHourlyCount(cached)} h) — sťahujem znova',
          );
        }
      } catch (_) {}
    }
  }

  try {
    final uri = _openMeteoForecastUri(lat, lon, timezone, model);
    debugPrint('Open-Meteo (${model.uiTitle}): GET $uri');
    final r = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'pocasie-app/1.0 (flutter)',
      },
    ).timeout(const Duration(seconds: 30));

    if (r.statusCode != 200) {
      debugPrint('Open-Meteo HTTP ${r.statusCode} (${model.uiTitle})');
      return null;
    }

    final raw = json.decode(r.body) as Map<String, dynamic>;
    if (!raw.containsKey('hourly')) {
      debugPrint('Open-Meteo: chýba hourly v odpovedi');
      return null;
    }

    final map = _normalizeOpenMeteoForecast(raw, model);
    await CacheManager.saveWeather(lat, lon, cacheKey, json.encode(map));
    debugPrint(
      'Open-Meteo (${model.uiTitle}): OK '
      '${forecastJsonUpcomingHourlyCount(map)} budúcich hodín, '
      '${(map['daily'] as Map?)?['time']?.length ?? 0} dní',
    );
    return map;
  } catch (e) {
    debugPrint('Open-Meteo fetch failed (${model.uiTitle}): $e');
    return null;
  }
}
