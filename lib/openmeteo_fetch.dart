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

/// Best Match precip blend — ľahké requesty z ďalších modelov (zhoda mm / %).
const String _kPrecipBlendHourlyVars =
    'precipitation,precipitation_probability,weather_code';
const List<String> _kPrecipBlendModels = [
  'icon_seamless',
  'ecmwf_ifs025',
  'gfs_seamless',
];

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

double? _medianDouble(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

int _roundProbTens(int value) {
  if (value <= 0) return 0;
  if (value >= 100) return 100;
  return ((value / 10.0).round() * 10).clamp(10, 100);
}

bool _modelHourWet(double? mm) =>
    mm != null && mm >= kMeaningfulPrecipMmPerHour;

int _wettestPrecipCode(List<int?> codes, double mm) {
  var best = 0;
  for (final c in codes) {
    if (c == null) continue;
    final n = normalizeDisplayWeatherCode(c);
    if (!kPrecipitationCodes.contains(n)) continue;
    if (n > best) best = n;
  }
  if (best > 0) return best;
  return wmoFromPrecipitationMm(mm);
}

/// Konzervatívne % — mokré len pri väčšine modelov; inak suché / nízke.
int _precipBlendProbPercent({
  required int wetCount,
  required int modelCount,
  required List<int> modelProbs,
  required bool consensusWet,
}) {
  if (modelCount <= 0) return 0;
  final medProb = modelProbs.isEmpty
      ? 0
      : (_medianDouble(modelProbs.map((e) => e.toDouble()).toList()) ?? 0)
          .round();

  if (!consensusWet) {
    // Bez väčšiny — max 40 % (suchá obloha), žiadne 50+ z jedného modelu.
    return _roundProbTens(math.min(medProb, 40));
  }

  // Väčšina mokrá: 2/3→60, 3/3→70–80 (nie automaticky 90).
  final fromAgreement = wetCount >= modelCount
      ? 70
      : (wetCount * 2 >= modelCount * 2 - 1 ? 60 : 50);
  final blended = ((fromAgreement * 2 + math.min(medProb, 80)) / 3).round();
  return _roundProbTens(math.max(kMinPrecipProbPercent, blended).clamp(50, 80));
}

Uri _precipBlendModelUri(
  double lat,
  double lon,
  String timezone,
  String modelId,
) {
  final tz = _normalizeApiTimezone(timezone);
  return Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
    queryParameters: <String, String>{
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': _kPrecipBlendHourlyVars,
      'forecast_days': kOpenMeteoForecastDays.toString(),
      'timezone': tz,
      'models': modelId,
    },
  );
}

Future<Map<String, dynamic>?> _downloadPrecipBlendModel(
  double lat,
  double lon,
  String timezone,
  String modelId,
) async {
  try {
    final uri = _precipBlendModelUri(lat, lon, timezone, modelId);
    debugPrint('Open-Meteo (precip blend $modelId): GET $uri');
    final r = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'pocasie-app/1.0 (flutter)',
      },
    ).timeout(const Duration(seconds: 22));
    if (r.statusCode != 200) {
      debugPrint('Precip blend $modelId HTTP ${r.statusCode}');
      return null;
    }
    final raw = json.decode(r.body) as Map<String, dynamic>;
    if (!raw.containsKey('hourly')) return null;
    return raw;
  } catch (e) {
    debugPrint('Precip blend $modelId failed: $e');
    return null;
  }
}

Future<List<({String id, Map<String, dynamic> data})>> _downloadPrecipBlendModels(
  double lat,
  double lon,
  String timezone,
) async {
  final results = await Future.wait(
    _kPrecipBlendModels.map((id) async {
      final data = await _downloadPrecipBlendModel(lat, lon, timezone, id);
      return (id: id, data: data);
    }),
  );
  return [
    for (final r in results)
      if (r.data != null) (id: r.id, data: r.data!),
  ];
}

/// Best Match + multi-model zrážky — **konzervatívne**:
/// medián mm zo všetkých modelov; mokré len pri väčšine (≥2 z 3).
/// Best Match sa do hlasovania nepočíta (v EÚ často = ICON → dvojitý hlas).
Map<String, dynamic> _mergePrecipBlendIntoBestMatch(
  Map<String, dynamic> bestMatch,
  List<({String id, Map<String, dynamic> data})> extras,
) {
  if (extras.isEmpty) {
    return {...bestMatch, 'precip_blend': false, 'precip_blend_models': 0};
  }

  final bmHourly = bestMatch['hourly'];
  if (bmHourly is! Map) {
    return {...bestMatch, 'precip_blend': false, 'precip_blend_models': 0};
  }

  final bmTimes =
      (bmHourly['time'] as List?)?.map((e) => e.toString()).toList();
  if (bmTimes == null || bmTimes.isEmpty) {
    return {...bestMatch, 'precip_blend': false, 'precip_blend_models': 0};
  }

  // Len extra modely (ICON / ECMWF / GFS) — bez Best Match v hlase.
  final extraByTime = <String, List<({double? mm, int? prob, int? code})>>{};
  for (final extra in extras) {
    final hourly = extra.data['hourly'];
    if (hourly is! Map) continue;
    final times = (hourly['time'] as List?)?.map((e) => e.toString()).toList();
    final mmList = hourly['precipitation'] as List?;
    final probList = hourly['precipitation_probability'] as List?;
    final codeList = hourly['weather_code'] as List?;
    if (times == null || mmList == null) continue;
    for (var i = 0; i < times.length; i++) {
      final t = times[i];
      final mm = i < mmList.length ? _asNum(mmList[i])?.toDouble() : null;
      final prob = (probList != null && i < probList.length)
          ? _asNum(probList[i])?.toInt()
          : null;
      final code = (codeList != null && i < codeList.length)
          ? _asNum(codeList[i])?.toInt()
          : null;
      extraByTime.putIfAbsent(t, () => []).add((mm: mm, prob: prob, code: code));
    }
  }

  final bmMm = List<dynamic>.from(
    (bmHourly['precipitation'] as List?) ??
        List<dynamic>.filled(bmTimes.length, null),
  );
  final bmProb = List<dynamic>.from(
    (bmHourly['precipitation_probability'] as List?) ??
        List<dynamic>.filled(bmTimes.length, null),
  );
  final bmCodes = List<dynamic>.from(
    (bmHourly['weather_code'] as List?) ??
        List<dynamic>.filled(bmTimes.length, null),
  );
  while (bmMm.length < bmTimes.length) {
    bmMm.add(null);
  }
  while (bmProb.length < bmTimes.length) {
    bmProb.add(null);
  }
  while (bmCodes.length < bmTimes.length) {
    bmCodes.add(null);
  }

  var blendedHours = 0;
  var wetHours = 0;
  for (var i = 0; i < bmTimes.length; i++) {
    final t = bmTimes[i];
    final samples = extraByTime[t];
    if (samples == null || samples.length < 2) continue;

    final allMm = <double>[];
    final probs = <int>[];
    final codes = <int?>[];
    var wetCount = 0;
    for (final s in samples) {
      final wet = _modelHourWet(s.mm);
      if (wet) wetCount++;
      allMm.add(s.mm ?? 0);
      if (s.prob != null) probs.add(s.prob!);
      codes.add(s.code);
    }

    final modelCount = samples.length;
    // Väčšina: pri 3 modeloch treba ≥2; pri 2 modeloch treba 2.
    final majorityWet = wetCount * 2 > modelCount;
    // Medián vrátane núl — jeden mokrý model nenaťahuje celé mm.
    final medianMm = _medianDouble(allMm) ?? 0;
    final consensusWet =
        majorityWet && medianMm >= kMeaningfulPrecipMmPerHour;

    final blendedProb = _precipBlendProbPercent(
      wetCount: wetCount,
      modelCount: modelCount,
      modelProbs: probs,
      consensusWet: consensusWet,
    );

    final blendedMm = consensusWet
        ? double.parse(medianMm.toStringAsFixed(2))
        : 0.0;

    bmMm[i] = blendedMm;
    bmProb[i] = blendedProb;
    blendedHours++;

    final bmCode = _asNum(bmCodes[i])?.toInt();
    if (consensusWet) {
      wetHours++;
      if (bmCode == null || isSkyOnlyWmoCode(bmCode)) {
        bmCodes[i] = _wettestPrecipCode(codes, blendedMm);
      }
      // Už mokré BM — neeskaluj intenzitu (nesilniť ikonu).
    } else {
      // Bez väčšiny: zrážkovú ikonu z Best Match zruš (jeden model ju nenaťahuje).
      if (bmCode != null &&
          kPrecipitationCodes.contains(normalizeDisplayWeatherCode(bmCode))) {
        final cloud = (bmHourly['cloud_cover'] as List?) != null &&
                i < (bmHourly['cloud_cover'] as List).length
            ? _asNum((bmHourly['cloud_cover'] as List)[i])?.toDouble()
            : null;
        bmCodes[i] = skyWmoFromCloudCover(cloud);
      }
    }
  }

  final mergedHourly = Map<String, dynamic>.from(bmHourly)
    ..['precipitation'] = bmMm
    ..['precipitation_probability'] = bmProb
    ..['weather_code'] = bmCodes;

  // Denné sumy / max % zo zlúčených hodín.
  final bmDaily = bestMatch['daily'];
  Map<String, dynamic>? mergedDaily;
  if (bmDaily is Map) {
    final dayTimes =
        (bmDaily['time'] as List?)?.map((e) => e.toString()).toList();
    if (dayTimes != null && dayTimes.isNotEmpty) {
      final daySum = List<dynamic>.from(
        (bmDaily['precipitation_sum'] as List?) ??
            List<dynamic>.filled(dayTimes.length, 0),
      );
      final dayProbMax = List<dynamic>.from(
        (bmDaily['precipitation_probability_max'] as List?) ??
            List<dynamic>.filled(dayTimes.length, 0),
      );
      while (daySum.length < dayTimes.length) {
        daySum.add(0);
      }
      while (dayProbMax.length < dayTimes.length) {
        dayProbMax.add(0);
      }

      for (var d = 0; d < dayTimes.length; d++) {
        final date = dayTimes[d].length >= 10
            ? dayTimes[d].substring(0, 10)
            : dayTimes[d];
        var sum = 0.0;
        var maxP = 0;
        for (var i = 0; i < bmTimes.length; i++) {
          if (!bmTimes[i].startsWith(date)) continue;
          sum += _asNum(bmMm[i])?.toDouble() ?? 0;
          maxP = math.max(maxP, _asNum(bmProb[i])?.toInt() ?? 0);
        }
        daySum[d] = double.parse(sum.toStringAsFixed(2));
        dayProbMax[d] = maxP;
      }
      mergedDaily = Map<String, dynamic>.from(bmDaily)
        ..['precipitation_sum'] = daySum
        ..['precipitation_probability_max'] = dayProbMax;
    }
  }

  final merged = Map<String, dynamic>.from(bestMatch)
    ..['hourly'] = mergedHourly
    ..['precip_blend'] = true
    ..['precip_blend_models'] = extras.length
    ..['precip_blend_hours'] = blendedHours
    ..['precip_blend_wet_hours'] = wetHours
    ..['precip_blend_mode'] = 'majority_median';
  if (mergedDaily != null) {
    merged['daily'] = mergedDaily;
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
                (cached['ecmwf_cloud_overlay'] == true &&
                    cached['precip_blend'] == true))) {
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

      // Multi-model zrážky: Best Match + ICON + ECMWF + GFS → zhoda / medián mm / %.
      final precipExtras =
          await _downloadPrecipBlendModels(lat, lon, timezone);
      if (precipExtras.isNotEmpty) {
        map = _mergePrecipBlendIntoBestMatch(map, precipExtras);
        debugPrint(
          'Best Match: precip blend '
          '${map['precip_blend_models']} modelov, '
          '${map['precip_blend_wet_hours'] ?? 0} mokrých h '
          '(${precipExtras.map((e) => e.id).join(', ')})',
        );
      } else {
        map = {...map, 'precip_blend': false, 'precip_blend_models': 1};
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
