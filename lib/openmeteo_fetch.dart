part of 'main.dart';

const String _kOpenMeteoHourlyVars =
    'temperature_2m,cloud_cover,precipitation,precipitation_probability,weather_code,wind_speed_10m,wind_direction_10m,relative_humidity_2m,apparent_temperature,pressure_msl,uv_index,wind_gusts_10m,dew_point_2m';

const String _kOpenMeteoDailyVars =
    'temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset,precipitation_sum,precipitation_probability_max,uv_index_max,wind_speed_10m_max';

const String _kOpenMeteoCurrentVars =
    'temperature_2m,is_day,weather_code,cloud_cover,precipitation,wind_speed_10m,wind_direction_10m,relative_humidity_2m,apparent_temperature,pressure_msl,uv_index';

/// Best Match — len oblačnosť / sky WMO z ECMWF (ľahký request).
const String _kEcmwfCloudHourlyVars = 'cloud_cover,weather_code';
const String _kEcmwfCloudCurrentVars = 'cloud_cover,weather_code';

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

Uri _ecmwfCloudCoverUri(double lat, double lon, String timezone) {
  final tz = _normalizeApiTimezone(timezone);
  return Uri.parse(WeatherForecastModel.openMeteo.apiBase).replace(
    queryParameters: <String, String>{
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': _kEcmwfCloudHourlyVars,
      'current': _kEcmwfCloudCurrentVars,
      'forecast_days': kOpenMeteoForecastDays.toString(),
      'timezone': tz,
    },
  );
}

num? _asNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

/// Best Match + ECMWF oblačnosť — jasno/polooblačno podľa ECMWF `cloud_cover`.
Map<String, dynamic> _mergeEcmwfCloudIntoBestMatch(
  Map<String, dynamic> bestMatch,
  Map<String, dynamic> ecmwf,
) {
  final bmHourly = bestMatch['hourly'];
  final ecHourly = ecmwf['hourly'];
  if (bmHourly is! Map || ecHourly is! Map) {
    return {...bestMatch, 'ecmwf_cloud_overlay': false};
  }

  final bmTimes = (bmHourly['time'] as List?)?.map((e) => e.toString()).toList();
  final ecTimes = (ecHourly['time'] as List?)?.map((e) => e.toString()).toList();
  final ecCloud = ecHourly['cloud_cover'] as List?;
  final ecCodes = ecHourly['weather_code'] as List?;
  if (bmTimes == null ||
      ecTimes == null ||
      ecCloud == null ||
      bmTimes.isEmpty ||
      ecTimes.isEmpty) {
    return {...bestMatch, 'ecmwf_cloud_overlay': false};
  }

  final ecByTime = <String, int>{};
  for (var i = 0; i < ecTimes.length; i++) {
    ecByTime[ecTimes[i]] = i;
  }

  final bmCloud = List<dynamic>.from(
    (bmHourly['cloud_cover'] as List?) ??
        List<dynamic>.filled(bmTimes.length, null),
  );
  final bmCodes = List<dynamic>.from(
    (bmHourly['weather_code'] as List?) ??
        List<dynamic>.filled(bmTimes.length, null),
  );
  if (bmCloud.length < bmTimes.length) {
    bmCloud.addAll(List<dynamic>.filled(bmTimes.length - bmCloud.length, null));
  }
  if (bmCodes.length < bmTimes.length) {
    bmCodes.addAll(List<dynamic>.filled(bmTimes.length - bmCodes.length, null));
  }

  var mergedHours = 0;
  for (var i = 0; i < bmTimes.length; i++) {
    final ecIdx = ecByTime[bmTimes[i]];
    if (ecIdx == null || ecIdx >= ecCloud.length) continue;
    final cloud = _asNum(ecCloud[ecIdx])?.toDouble();
    if (cloud == null) continue;
    bmCloud[i] = cloud;
    mergedHours++;

    // Suché sky WMO (0–3): ber oblačnejší z Best Match vs ECMWF.
    final bmCode = _asNum(bmCodes[i])?.toInt();
    final ecCode =
        (ecCodes != null && ecIdx < ecCodes.length) ? _asNum(ecCodes[ecIdx])?.toInt() : null;
    if (bmCode != null && isSkyOnlyWmoCode(bmCode)) {
      final fromCloud = skyWmoFromCloudCover(cloud);
      final fromEcmwfSky = (ecCode != null && isSkyOnlyWmoCode(ecCode)) ? ecCode : fromCloud;
      bmCodes[i] = math.max(bmCode, math.max(fromCloud, fromEcmwfSky));
    } else if (bmCode == null) {
      bmCodes[i] = skyWmoFromCloudCover(cloud);
    }
  }

  final mergedHourly = Map<String, dynamic>.from(bmHourly)
    ..['cloud_cover'] = bmCloud
    ..['weather_code'] = bmCodes;

  final merged = Map<String, dynamic>.from(bestMatch)
    ..['hourly'] = mergedHourly
    ..['ecmwf_cloud_overlay'] = true
    ..['ecmwf_cloud_hours'] = mergedHours;

  final bmCurrent = bestMatch['current'];
  final ecCurrent = ecmwf['current'];
  if (bmCurrent is Map && ecCurrent is Map) {
    final current = Map<String, dynamic>.from(bmCurrent);
    final ecCc = _asNum(ecCurrent['cloud_cover'])?.toDouble();
    if (ecCc != null) {
      current['cloud_cover'] = ecCc;
      final bmCurCode = _asNum(current['weather_code'])?.toInt();
      if (bmCurCode == null || isSkyOnlyWmoCode(bmCurCode)) {
        final fromCloud = skyWmoFromCloudCover(ecCc);
        final ecCurCode = _asNum(ecCurrent['weather_code'])?.toInt();
        final fromEcmwfSky =
            (ecCurCode != null && isSkyOnlyWmoCode(ecCurCode)) ? ecCurCode : fromCloud;
        current['weather_code'] = math.max(bmCurCode ?? 0, math.max(fromCloud, fromEcmwfSky));
      }
      merged['current'] = current;
    }
  }

  return merged;
}

Future<Map<String, dynamic>?> _downloadEcmwfCloudCover(
  double lat,
  double lon,
  String timezone,
) async {
  try {
    final uri = _ecmwfCloudCoverUri(lat, lon, timezone);
    debugPrint('Open-Meteo (ECMWF cloud overlay): GET $uri');
    final r = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'pocasie-app/1.0 (flutter)',
      },
    ).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) {
      debugPrint('ECMWF cloud overlay HTTP ${r.statusCode}');
      return null;
    }
    final raw = json.decode(r.body) as Map<String, dynamic>;
    if (!raw.containsKey('hourly')) return null;
    return raw;
  } catch (e) {
    debugPrint('ECMWF cloud overlay failed: $e');
    return null;
  }
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
            forecastJsonHas24HourWindow(cached) &&
            (model != WeatherForecastModel.bestMatch ||
                cached['ecmwf_cloud_overlay'] == true)) {
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

    var map = _normalizeOpenMeteoForecast(raw, model);

    // Best Match: oblačnosť (jasno / polooblačno) z ECMWF — BM ju často podhodnocuje.
    if (model == WeatherForecastModel.bestMatch) {
      final ecmwfCloud = await _downloadEcmwfCloudCover(lat, lon, timezone);
      if (ecmwfCloud != null) {
        map = _mergeEcmwfCloudIntoBestMatch(map, ecmwfCloud);
        debugPrint(
          'Best Match: ECMWF cloud overlay '
          '(${map['ecmwf_cloud_hours'] ?? 0} h)',
        );
      } else {
        map = {...map, 'ecmwf_cloud_overlay': false};
      }
    }

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
