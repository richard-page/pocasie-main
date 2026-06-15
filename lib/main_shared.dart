part of 'main.dart';

// --- KONŠTANTY A NASTAVENIA ---
/// Predvoľba zdroja predpovede.
enum WeatherForecastModel {
  /// ECMWF IFS — výhradne cez Open-Meteo `/v1/ecmwf`.
  openMeteo._('ecmwf_ifs', 'ECMWF IFS', 'Globálna predpoveď ECMWF (0,25°) cez Open-Meteo API.');

  /// Kľúč cache (`CacheManager`).
  final String cacheKey;

  final String uiTitle;
  final String uiSubtitle;

  const WeatherForecastModel._(this.cacheKey, this.uiTitle, this.uiSubtitle);

  static WeatherForecastModel fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return WeatherForecastModel.openMeteo;
    if (raw == 'ecmwf_ifs' || raw == 'open_meteo') return WeatherForecastModel.openMeteo;
    for (final v in WeatherForecastModel.values) {
      if (v.cacheKey == raw) return v;
    }
    return WeatherForecastModel.openMeteo;
  }
}

/// Počet dní stiahnutých z API a v grafe.
const int kForecastDays = 16;

/// Denný zoznam na domovskej obrazovke (záložka „X dní“).
const int kDailyListForecastDays = 10;

const int kOpenMeteoForecastDays = kForecastDays;
const int kChartForecastDays = kForecastDays;

/// Kľúč cache predpovede — musí obsahovať počet dní, inak ostane stará 10-dňová cache.
String forecastWeatherCacheKey(WeatherForecastModel model) =>
    '${model.cacheKey}_fd$kForecastDays';

String forecastWeatherCacheKeyForModelId(String modelId) {
  if (modelId.isEmpty) {
    return forecastWeatherCacheKey(WeatherForecastModel.openMeteo);
  }
  if (modelId == 'ecmwf_ifs' || modelId == 'open_meteo') {
    return forecastWeatherCacheKey(WeatherForecastModel.openMeteo);
  }
  return '${modelId}_fd$kForecastDays';
}

bool forecastJsonDailyHorizonComplete(Map<String, dynamic> map) {
  final daily = map['daily'];
  if (daily is! Map) return false;
  final times = daily['time'];
  if (times is! List) return false;
  return times.length >= kForecastDays;
}

String _normalizeHourlyTimeStr(String timeStr) {
  var clean = timeStr.trim();
  if (clean.startsWith('as')) clean = clean.substring(2).trim();
  if (!clean.contains('T')) {
    if (clean.contains(' ')) {
      final parts = clean.split(' ');
      if (parts.length >= 2) clean = '${parts[0]}T${parts[1]}';
    } else {
      clean = '${clean}T00:00:00';
    }
  }
  return clean;
}

bool _hourlyTimeHasOffset(String clean) =>
    clean.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(clean);

/// Lokálna stenová hodina z Open-Meteo (`timezone` → ISO bez offsetu) alebo absolútneho ISO.
DateTime? hourlyLocalWall(String timeStr, int? utcOffsetSeconds) {
  if (timeStr.length < 13) return null;
  final clean = _normalizeHourlyTimeStr(timeStr);

  if (!_hourlyTimeHasOffset(clean)) {
    final p = DateTime.tryParse(clean);
    if (p == null) return null;
    return DateTime.utc(p.year, p.month, p.day, p.hour, p.minute, p.second);
  }

  final instant = DateTime.tryParse(clean);
  if (instant == null) return null;
  final utc = instant.toUtc();
  if (utcOffsetSeconds == null || utcOffsetSeconds == 0) return utc;
  return utc.add(Duration(seconds: utcOffsetSeconds));
}

DateTime? ecmwfHourlyLocalWall(String timeStr, int? utcOffsetSeconds) =>
    hourlyLocalWall(timeStr, utcOffsetSeconds);

DateTime hourlyForecastVisFloor(DateTime locTime) => DateTime(
      locTime.year,
      locTime.month,
      locTime.day,
      locTime.hour,
    ).add(const Duration(hours: 1));

/// Koľko budúcich hodín ostáva v JSON od ďalšej celej hodiny (panel „24 h“).
int forecastJsonUpcomingHourlyCount(Map<String, dynamic> map) {
  final hourly = map['hourly'];
  if (hourly is! Map) return 0;
  final times = hourly['time'];
  if (times is! List || times.isEmpty) return 0;
  final offset = (map['utc_offset_seconds'] as num?)?.toInt() ?? 0;
  final loc = DateTime.now().toUtc().add(Duration(seconds: offset));
  final visFloor = hourlyForecastVisFloor(
    DateTime(loc.year, loc.month, loc.day, loc.hour, loc.minute, loc.second),
  );
  var start = times.length;
  for (var i = 0; i < times.length; i++) {
    final local = hourlyLocalWall(times[i].toString(), offset);
    if (local != null && !local.isBefore(visFloor)) {
      start = i;
      break;
    }
  }
  if (start >= times.length) return 0;
  return times.length - start;
}

bool forecastJsonHas24HourWindow(Map<String, dynamic> map) =>
    forecastJsonUpcomingHourlyCount(map) >= 24;

bool forecastDailyHorizonComplete(WeatherData? data) {
  final times = data?.daily?.time;
  if (times == null || times.isEmpty) return false;
  return times.length >= kForecastDays;
}
const String kForecastModelKey = 'forecast_model_v1';

const String kOnboardingDoneKey = 'onboarding_playstore_fix';

const String kOpenMeteoForecastApi = 'https://api.open-meteo.com/v1/ecmwf';
const String kOpenMeteoAttributionUrl = 'https://open-meteo.com/';

// Geocoding zostáva na Open-Meteo (je to samostatná služba)
const String kGeoApi = 'https://geocoding-api.open-meteo.com/v1';

// Peľ a kvalita ovzdušia cez Open-Meteo (CAMS)
const String kAirQualityApi = 'https://air-quality-api.open-meteo.com/v1';

// Historické dáta cez ECMWF ERA5
const String kHistoricalApi = 'https://cds.climate.copernicus.eu/api/v2';

const String kSearchHistoryKey = 'search_history_v7';
const String kWeatherCachePrefix = 'cache_weather_v10_';
const String kAirQualityCachePrefix = 'cache_aqi_v7_';
const String kGeoCachePrefix = 'cache_geo_v7_';
const String kLastLocationKey = 'last_location_v7';

const String kWarningsCachePrefix = 'cache_warnings_v11_';

const int kWeatherCacheDurationMinutes = 45;
const int kGeoCacheDurationDays = 7;
const String kWindUnitKey = 'wind_unit_v1';
const String kMyLocationKey = 'my_location_v1';
const String kHomeWidgetUpdateIntervalMinutesKey = 'home_widget_update_interval_minutes_v1';
const int kHomeWidgetUpdateIntervalMinutesDefault = 30;
const int kHomeWidgetUpdateIntervalMinutesMin = 1;
const int kHomeWidgetUpdateIntervalMinutesMax = 720;

const String kLightningNearbyLatchAtKey = 'lightning_nearby_latch_at_v1';
const String kLightningNearbyLatchLatKey = 'lightning_nearby_latch_lat_v1';
const String kLightningNearbyLatchLonKey = 'lightning_nearby_latch_lon_v1';
const String kTestPushEnabledKey = 'test_push_enabled_v1';
const String kTestPushHourKey = 'test_push_hour_v1';
const String kTestPushMinuteKey = 'test_push_minute_v1';
const String kTestPushNextAtKey = 'test_push_next_at_v1';
const String kAlertDailySummaryEnabledKey = 'alert_daily_summary_enabled_v1';
const String kAlertEveningSummaryEnabledKey = 'alert_evening_summary_enabled_v1';
const String kAlertHeavyRainEnabledKey = 'alert_heavy_rain_enabled_v1';
const String kAlertHeavySnowEnabledKey = 'alert_heavy_snow_enabled_v1';
const String kAlertStrongWindEnabledKey = 'alert_strong_wind_enabled_v1';
const String kAlertHighUvEnabledKey = 'alert_high_uv_enabled_v1';
const String kAlertExtremeHeatEnabledKey = 'alert_extreme_heat_enabled_v1';
const String kAlertStrongFrostEnabledKey = 'alert_strong_frost_enabled_v1';
const String kSystemNotificationsEnabledKey = 'system_notifications_enabled_v1';
const String kAlertDailySummaryHourKey = 'alert_daily_summary_hour_v1';
const String kAlertDailySummaryMinuteKey = 'alert_daily_summary_minute_v1';
const String kAlertEveningSummaryHourKey = 'alert_evening_summary_hour_v1';
const String kAlertEveningSummaryMinuteKey = 'alert_evening_summary_minute_v1';
/// Večerný súhrn — voliteľný čas len medzi „skutočným“ večerom (bez 17:00).
const int kAlertEveningSummaryHourMin = 18;
const int kAlertEveningSummaryHourMax = 22;
const String kAlertDailySummaryNextAtKey = 'alert_daily_summary_next_at_v1';
const String kAlertEveningSummaryNextAtKey = 'alert_evening_summary_next_at_v1';
const String kAlertDailySummaryLastPushBodyKey = 'alert_daily_summary_last_push_body_v1';
const String kAlertEveningSummaryLastPushBodyKey = 'alert_evening_summary_last_push_body_v1';
const String kAlertDailySummaryCatchUpLastAtMsKey = 'alert_daily_summary_catchup_last_at_ms_v1';
const String kAlertEveningSummaryCatchUpLastAtMsKey = 'alert_evening_summary_catchup_last_at_ms_v1';
/// Keď ešte nie je uložený text po refreshi, naplánuje sa opakovaný push s týmto telom.
const String kDailySummaryPlaceholderBody = 'Otvorte aplikáciu pre aktuálny súhrn počasia.';
const String kEveningSummaryPlaceholderBody = 'Otvorte aplikáciu pre aktuálny súhrn počasia.';
const String kAlertHighUvLastPlannedSlotKey = 'alert_high_uv_last_planned_slot_v1';
const String kAlertStrongWindLastPlannedSlotKey = 'alert_strong_wind_last_planned_slot_v1';
const String kAlertHeavyRainLastPlannedSlotKey = 'alert_heavy_rain_last_planned_slot_v1';
const String kAlertHeavySnowLastPlannedSlotKey = 'alert_heavy_snow_last_planned_slot_v1';
/// O koľko skôr pred udalosťou poslať lokálnu výstrahu (UV, vietor, výdatný dážď/sneh) — musí sedieť s LocalTestPushService.
const Duration kLeadWeatherAlertBeforeEvent = Duration(minutes: 30);
/// Lokálna výstraha „výdatný dážď“ — denný súčet zrážok (mm).
const double kAlertHeavyRainDailyMmThreshold = 10.0;
/// Lokálna výstraha „výdatné sneženie“ — denný súčet nového snehu (cm), pole `snowfall_sum` z Open-Meteo.
const double kAlertHeavySnowDailyCmThreshold = 10.0;
const String kAlertDefaultsOffMigrationKey = 'alert_defaults_off_migration_v1';
const String kLocationPermissionPromptShownKey = 'location_permission_prompt_shown_v1';
const int kWarningsCacheDurationMinutes = 15;

const String kWarningsBaseUrl = 'http://cz1.helkor.eu:41083';

/// Helkor výstrahy — vždy [index.php] (root často nevypíše JSON / presmeruje inak).
String buildHelkorWarningsUrl(GeoCity city, String countrySlug, {bool formatJson = false}) {
  final buf = StringBuffer('$kWarningsBaseUrl/index.php?country=${Uri.encodeQueryComponent(countrySlug)}')
    ..write('&lat=${city.lat}')
    ..write('&lon=${city.lon}');
  if (formatJson) buf.write('&format=json');
  if (city.admin1.isNotEmpty) {
    buf.write('&region=${Uri.encodeComponent(city.admin1)}');
  }
  if (city.admin2.isNotEmpty) {
    buf.write('&county=${Uri.encodeComponent(city.admin2)}');
  }
  if (city.name.isNotEmpty) {
    buf.write('&city=${Uri.encodeComponent(city.name)}');
  }
  return buf.toString();
}

String buildMeteoRadarUrl(GeoCity city) {
  final cacheBust = DateTime.now().millisecondsSinceEpoch;
  return 'http://cz1.helkor.eu:41152/radar/?lat=${city.lat}&lon=${city.lon}&zoom=7&hideUI=true&_cb=$cacheBust';
}

/// Štáty s vlastnou radarovou sieťou v kompozite (SHMÚ, ČHMÚ, IMGW, DWD — bot.py).
const Set<String> kRadarCompositeCountryCodes = {
  'SK',
  'CZ',
  'PL',
  'DE',
  'HU',
  'AT',
  'RO',
  'SI',
  'HR',
  'RS',
};

bool cityEligibleForRadarNowcast(String countryCode) =>
    kRadarCompositeCountryCodes.contains(countryCode.toUpperCase());

/// Radar mapa + nowcast: lokalita musí byť v geografickom rámci kompozitu (0–30°E, 43–58°N).
bool radarCoverageForCity(GeoCity city) =>
    coordsWithinRadarMapExtent(city.lat, city.lon);

/// Geografický rámec kompozitu (helkor mapExtentCoordinates) — pixel mapovanie cez Web Mercator.
const double kRadarExtentLonMin = 0.0;
const double kRadarExtentLonMax = 30.0;
const double kRadarExtentLatMin = 43.0;
const double kRadarExtentLatMax = 58.0;

bool coordsWithinRadarMapExtent(double lat, double lon) =>
    lat >= kRadarExtentLatMin &&
    lat <= kRadarExtentLatMax &&
    lon >= kRadarExtentLonMin &&
    lon <= kRadarExtentLonMax;

/// WMO ikona z radarového dBZ (CMAX legenda).
int wmoFromRadarDbz(double dbz, {required bool snow}) {
  if (snow) {
    if (dbz >= 45) return 73;
    if (dbz >= 30) return 71;
    return 71;
  }
  if (dbz >= 50) return 65;
  if (dbz >= 42) return 63;
  if (dbz >= 30) return 61;
  if (dbz >= 20) return 53;
  return 51;
}

bool radarSnowLikely({double? tempC, double snowfallCm = 0.0}) =>
    snowfallCm >= 0.1 || (tempC != null && tempC <= 0.5);

/// Horný strop mm/h podľa radarovej ikony — vizuál a číslo musia sedieť.
double _radarMmCapForIcon(int icon) {
  return switch (icon) {
    51 => 0.45,
    53 => 0.85,
    55 => 1.1,
    61 => 1.6,
    63 => 3.0,
    65 => 5.5,
    71 || 73 || 75 => 2.5,
    _ => 2.0,
  };
}

/// Odhad mm/h z CMAX dBZ — miernejší než čistý Marshall-Palmer (composite radar preháňa).
double radarMmFromDbz(double dbz) {
  if (dbz < kRadarMinDbzForUi) return 0;
  final z = math.pow(10, dbz / 10.0);
  // Z=280, b=1.5 — konzervatívnejší než Z=200 R^1.6 pre stratiformný / slabší dážď.
  final raw = math.pow(z / 280.0, 1.0 / 1.5).toDouble();
  final icon = wmoFromRadarDbz(dbz, snow: false);
  final cap = _radarMmCapForIcon(icon);
  return raw.clamp(kMeaningfulPrecipMmPerHour, cap);
}

/// % z dBZ — zosúladené s [radarMmFromDbz], nie priamo z raw echo.
int radarProbPercentFromDbz(double dbz) {
  final mm = radarMmFromDbz(dbz);
  if (mm <= 0) return 0;
  if (mm >= 2.5) return 85;
  if (mm >= 1.5) return 75;
  if (mm >= 0.9) return 65;
  if (mm >= 0.45) return 55;
  return kMinPrecipProbPercent;
}

bool _hourShowsPrecipIcon(int iconCode) =>
    kPrecipitationCodes.contains(normalizeDisplayWeatherCode(iconCode));

/// Test: v radarovej zóne zobrazovať zrážky **len z radaru** — ECMWF-only dažď skryť.
const bool kRadarOnlyPrecipTestMode = true;

void _clearHourlySlotPrecip({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required int index,
  double? cloudCover,
}) {
  displayIcons[index] = skyWmoFromCloudCover(cloudCover);
  showRainPrecip[index] = false;
  storedProbs[index] = 0;
  precipMm[index] = 0;
}

void _setHourlySlotRadarPrecip({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required int index,
  required RadarNowcastContext radarCtx,
  double? tempC,
  required double iconDbz,
  double? mmDbz,
}) {
  final forMm = mmDbz ?? iconDbz;
  displayIcons[index] = wmoFromRadarDbz(
    iconDbz,
    snow: radarSnowLikely(tempC: tempC),
  );
  showRainPrecip[index] = true;
  storedProbs[index] = radarProbPercentFromDbz(forMm);
  precipMm[index] = radarMmFromDbz(forMm);
}

void _applyRadarOnlyPrecipToHourlyStrip({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required List<int> stripIndices,
  required HourlyForecast h,
  required RadarNowcastContext radarCtx,
  required DateTime locTime,
  int? utcOffsetSeconds,
}) {
  for (var i = 0; i < displayIcons.length; i++) {
    final idx = stripIndices[i];
    final parsed = DateTime.tryParse(h.time[idx]);
    if (parsed == null) continue;
    final localT = utcOffsetSeconds != null
        ? parsed.add(Duration(seconds: utcOffsetSeconds))
        : parsed;
    final slotHour = DateTime(
      localT.year,
      localT.month,
      localT.day,
      localT.hour,
    );
    final cloudCover = h.cloudCover?[idx];
    final tempC = h.temperature?[idx];

    if (radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime)) {
      _setHourlySlotRadarPrecip(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        radarCtx: radarCtx,
        tempC: tempC,
        iconDbz: radarCtx.stripDisplayDbz,
        mmDbz: radarCtx.stripMmDbz,
      );
    } else {
      _clearHourlySlotPrecip(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        cloudCover: cloudCover,
      );
    }
  }
}

/// Skráti zrážky v 24 h — ECMWF ostáva základ, radar určí **od ktorej hodiny** orezať.
void applyRadarPrecipEndToHourlyStrip({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required List<int> stripIndices,
  required HourlyForecast h,
  required RadarNowcastContext radarCtx,
  required DateTime locTime,
  int? utcOffsetSeconds,
  bool radarCoverageActive = false,
}) {
  if (!radarCtx.eligible) {
    if (kRadarOnlyPrecipTestMode && radarCoverageActive) {
      _applyRadarOnlyPrecipToHourlyStrip(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        stripIndices: stripIndices,
        h: h,
        radarCtx: RadarNowcastContext.inactive,
        locTime: locTime,
        utcOffsetSeconds: utcOffsetSeconds,
      );
    }
    return;
  }

  if (kRadarOnlyPrecipTestMode) {
    _applyRadarOnlyPrecipToHourlyStrip(
      displayIcons: displayIcons,
      showRainPrecip: showRainPrecip,
      storedProbs: storedProbs,
      precipMm: precipMm,
      stripIndices: stripIndices,
      h: h,
      radarCtx: radarCtx,
      locTime: locTime,
      utcOffsetSeconds: utcOffsetSeconds,
    );
    return;
  }

  final dryFrom = radarCtx.estimatedDryFromLocalTime(locTime);
  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );

  for (var i = 0; i < displayIcons.length; i++) {
    final idx = stripIndices[i];
    final parsed = DateTime.tryParse(h.time[idx]);
    if (parsed == null) continue;
    final localT = utcOffsetSeconds != null
        ? parsed.add(Duration(seconds: utcOffsetSeconds))
        : parsed;
    final slotHour = DateTime(
      localT.year,
      localT.month,
      localT.day,
      localT.hour,
    );

    final cloudCover = h.cloudCover?[idx];
    final tempC = h.temperature?[idx];
    var iconWet = _hourShowsPrecipIcon(displayIcons[i]);
    var columnWet = showRainPrecip[i];

    // Radar práve prší — doplni blízke hodiny, kde model podceňuje (vrátane 16:00 keď je 15:xx).
    if (radarCtx.precipNow &&
        !slotHour.isBefore(nowHour) &&
        (dryFrom == null || slotHour.isBefore(dryFrom)) &&
        !iconWet &&
        !columnWet) {
      final iconDbz = radarCtx.dbz ?? kRadarMinDbzForUi;
      displayIcons[i] = wmoFromRadarDbz(
        iconDbz,
        snow: radarSnowLikely(tempC: tempC),
      );
      showRainPrecip[i] = true;
      storedProbs[i] = radarProbPercentFromDbz(iconDbz);
      precipMm[i] = radarMmFromDbz(iconDbz);
      iconWet = true;
      columnWet = true;
    }

    if (!iconWet && !columnWet) continue;

    // Orez podľa absolútnej hodiny slotu (nie relatívne hoursFrom).
    if (dryFrom != null && !slotHour.isBefore(dryFrom)) {
      displayIcons[i] = skyWmoFromCloudCover(cloudCover);
      showRainPrecip[i] = false;
      storedProbs[i] = 0;
      precipMm[i] = 0;
      continue;
    }

    // Aktuálna hodina: radar suchý, model ešte ukazuje dážď.
    if (slotHour == nowHour &&
        !radarCtx.precipNow &&
        radarCtx.estimatedPrecipEndHours == 0) {
      displayIcons[i] = skyWmoFromCloudCover(cloudCover);
      showRainPrecip[i] = false;
      storedProbs[i] = 0;
      precipMm[i] = 0;
    }
  }

  // Predĺženie max +1 h: ECMWF skončil, radar stále prší stabilne.
  if (radarCtx.precipNow &&
      radarCtx.steadyOngoing &&
      !radarCtx.trendEnding &&
      radarCtx.estimatedDryFromLocalTime(locTime) == null) {
    for (var i = 1; i < displayIcons.length; i++) {
      final prevIdx = stripIndices[i - 1];
      final curIdx = stripIndices[i];
      final prevParsed = DateTime.tryParse(h.time[prevIdx]);
      final curParsed = DateTime.tryParse(h.time[curIdx]);
      if (prevParsed == null || curParsed == null) continue;
      final prevLocal = utcOffsetSeconds != null
          ? prevParsed.add(Duration(seconds: utcOffsetSeconds))
          : prevParsed;
      final curLocal = utcOffsetSeconds != null
          ? curParsed.add(Duration(seconds: utcOffsetSeconds))
          : curParsed;
      if (curLocal.difference(prevLocal).inHours != 1) continue;

      final prevWet =
          showRainPrecip[i - 1] || _hourShowsPrecipIcon(displayIcons[i - 1]);
      final curDry =
          !showRainPrecip[i] && !_hourShowsPrecipIcon(displayIcons[i]);
      if (!prevWet || !curDry) continue;

      final tempC = h.temperature?[curIdx];
      final useDbz = radarCtx.dbz ?? kRadarMinDbzForUi;
      displayIcons[i] = wmoFromRadarDbz(
        useDbz,
        snow: radarSnowLikely(tempC: tempC),
      );
      showRainPrecip[i] = true;
      storedProbs[i] = radarProbPercentFromDbz(useDbz);
      precipMm[i] = radarMmFromDbz(useDbz);
      break;
    }
  }
}

/// Hero ikona — radar live stav má prioritu; potom orez podľa konca zrážok.
int applyRadarPrecipEndToHeroIcon(
  int code, {
  required RadarNowcastContext radarCtx,
  required DateTime locTime,
  double? tempC,
  double? cloudCoverPercent,
  double precipMm = 0,
  int precipProb = 0,
  bool radarCoverageActive = false,
}) {
  final iconWet = _hourShowsPrecipIcon(code);
  final modelWet = ecmwfHourPrecipShowsInUi(mm: precipMm, prob: precipProb);

  if (!radarCtx.eligible) {
    if (kRadarOnlyPrecipTestMode &&
        radarCoverageActive &&
        (iconWet || modelWet)) {
      return skyWmoFromCloudCover(cloudCoverPercent);
    }
    return code;
  }

  if (kRadarOnlyPrecipTestMode) {
    if (radarCtx.precipNow) {
      final useDbz = radarCtx.dbz ?? kRadarMinDbzForUi;
      return wmoFromRadarDbz(useDbz, snow: radarSnowLikely(tempC: tempC));
    }
    if (radarCtx.incomingPrecip) {
      return skyWmoFromCloudCover(cloudCoverPercent);
    }
    if (iconWet || modelWet) {
      return skyWmoFromCloudCover(cloudCoverPercent);
    }
    return code;
  }

  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );

  // Radar práve vidí zrážky — hero musí ukázať dážď, nie „prevažne jasno“ z modelu.
  if (radarCtx.precipNow) {
    final useDbz = radarCtx.dbz ?? kRadarMinDbzForUi;
    return wmoFromRadarDbz(useDbz, snow: radarSnowLikely(tempC: tempC));
  }

  final dryFrom = radarCtx.estimatedDryFromLocalTime(locTime);

  if (dryFrom != null && !nowHour.isBefore(dryFrom) && (iconWet || modelWet)) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }

  if (radarCtx.estimatedPrecipEndHours == 0 && (iconWet || modelWet)) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }

  return code;
}

String? buildMeteoWarningsUrl(GeoCity? city) {
  if (city == null) return null;
  switch (city.countryCode.toUpperCase()) {
    case 'SK':
      return buildHelkorWarningsUrl(city, 'slovakia', formatJson: false);
    case 'CZ':
      return buildHelkorWarningsUrl(city, 'czechia', formatJson: false);
    default:
      return null;
  }
}

/// Rovnaká škála farieb teploty ako v pripnutej hlavičke / hodinovke / grafe.
Color temperatureScaleColor(double? temp) {
  if (temp == null) return Colors.white;
  const stops = <({double t, Color c})>[
    (t: -50.0, c: Color(0xFFECEFF1)),
    (t: -40.0, c: Color(0xFFB0BEC5)),
    (t: -30.0, c: Color(0xFFCE93D8)),
    (t: -20.0, c: Color(0xFF7E57C2)),
    (t: -10.0, c: Color(0xFF3949AB)),
    (t: 0.0, c: Color(0xFF29B6F6)),
    (t: 10.0, c: Color(0xFF64DD17)),
    (t: 20.0, c: Color(0xFFFFD600)),
    (t: 30.0, c: Color(0xFFFF6D00)),
    (t: 40.0, c: Color(0xFFE53935)),
    (t: 50.0, c: Color(0xFFE040FB)),
  ];
  if (temp <= stops.first.t) return stops.first.c;
  if (temp >= stops.last.t) return stops.last.c;
  for (int i = 0; i < stops.length - 1; i++) {
    final a = stops[i];
    final b = stops[i + 1];
    if (temp >= a.t && temp <= b.t) {
      final f = (temp - a.t) / (b.t - a.t);
      return Color.lerp(a.c, b.c, f) ?? a.c;
    }
  }
  return Colors.white;
}

TextStyle storyTemperatureMonoStyle() => const TextStyle(
      fontFeatures: [
        ui.FontFeature.tabularFigures(),
        ui.FontFeature.liningFigures(),
      ],
    );
// --- SLOVNÍK POČASIA ---
final Map<int, Map<String, dynamic>> _weatherCodeMap = {
  0: {'icon_day': 'assets/sun.svg', 'icon_night': 'assets/moon.svg', 'description': 'jasno'},
  1: {'icon_day': 'assets/partly-cloudy.svg', 'icon_night': 'assets/moon-cloud.svg', 'description': 'prevažne jasno'},
  2: {'icon_day': 'assets/partly-cloudy.svg', 'icon_night': 'assets/moon-cloud.svg', 'description': 'polooblačno'},
  3: {'icon_day': 'assets/cloud.svg', 'icon_night': 'assets/cloud.svg', 'description': 'zamračené'},
  45: {'icon_day': 'assets/cloud.svg', 'icon_night': 'assets/cloud.svg', 'description': 'zamračené'},
  48: {'icon_day': 'assets/cloud.svg', 'icon_night': 'assets/cloud.svg', 'description': 'zamračené'},
  // 51–55 = mrholenie (drizzle), nie „silný lejak“ ako pri 65 — popisy musia sedieť s textovým súhrnom.
  51: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'slabé mrholenie'},
  53: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'mierne mrholenie'},
  55: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'výdatné mrholenie'},
  56: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'slabé sneženie'},
  57: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'silné sneženie'},
  61: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'slabý dážď'},
  63: {'icon_day': 'assets/rain.svg', 'icon_night': 'assets/rain.svg', 'description': 'mierny dážď'},
  65: {'icon_day': 'assets/rain.svg', 'icon_night': 'assets/rain.svg', 'description': 'silný dážď'},
  66: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'slabý mrznúci dážď'},
  67: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'silný mrznúci dážď'},
  71: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'slabé sneženie'},
  73: {'icon_day': 'assets/snow.svg', 'icon_night': 'assets/snow.svg', 'description': 'mierne sneženie'},
  75: {'icon_day': 'assets/snow.svg', 'icon_night': 'assets/snow.svg', 'description': 'silné sneženie'},
  77: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'snehové zrná'},
  80: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'slabé prehánky'},
  81: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'mierne prehánky'},
  82: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'prudké prehánky'},
  85: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'slabé snehové prehánky'},
  86: {'icon_day': 'assets/snow.svg', 'icon_night': 'assets/snow.svg', 'description': 'silné snehové prehánky'},
  95: {'icon_day': 'assets/thunder.svg', 'icon_night': 'assets/thunder.svg', 'description': 'búrka'},
  96: {'icon_day': 'assets/thunder.svg', 'icon_night': 'assets/thunder.svg', 'description': 'búrka'},
  99: {'icon_day': 'assets/thunder.svg', 'icon_night': 'assets/thunder.svg', 'description': 'búrka'},
};

/// WMO 45/48 (hmla, inováť) — bez vlastnej ikony; v UI vždy ako zamračené, bez slova „hmla“.
int normalizeDisplayWeatherCode(int? code) {
  return switch (code) {
    45 || 48 => 3,
    _ => code ?? 0,
  };
}

String weatherDescriptionSk(int? code) {
  final c = normalizeDisplayWeatherCode(code);
  return _weatherCodeMap[c]?['description']?.toString() ?? 'počasie';
}

/// Flat TCC placeholder (50 / 5 / 65) — nie skutočný GRIB; ikony nesmú brať z toho oblohu.
bool isUntrustedPlaceholderCloudSeries(List<double?>? cloudCover) {
  if (cloudCover == null || cloudCover.isEmpty) return false;
  final vals = cloudCover.whereType<double>().map((v) => v.round()).toList();
  if (vals.length < 12) return false;
  final unique = vals.toSet();
  if (unique.length == 1) {
    return {5, 25, 50, 65}.contains(unique.first);
  }
  return false;
}

bool hourlyTrustsApiWeatherCodes(HourlyForecast h) {
  final codes = h.weatherCode;
  final probs = h.precipitationProbability;
  if (codes == null || probs == null || h.time.isEmpty) return false;
  final n = h.time.length;
  final codeCount = codes.whereType<int>().length;
  final probCount = probs.whereType<int>().length;
  return codeCount >= (n * 0.85).ceil() && probCount >= (n * 0.5).ceil();
}

/// JSON má hodinové WMO 0–3 z backendu — ikony idú z modela, nie re-kvantifikácia z %.
bool hourlyHasUsableSkyWeatherCodes(List<int?>? weatherCode, int timeLen) {
  if (weatherCode == null || weatherCode.isEmpty || timeLen <= 0) return false;
  final limit = weatherCode.length < timeLen ? weatherCode.length : timeLen;
  var skyCount = 0;
  for (var i = 0; i < limit; i++) {
    final c = weatherCode[i];
    if (c != null && isSkyOnlyWmoCode(normalizeDisplayWeatherCode(c))) {
      skyCount++;
    }
  }
  return skyCount >= (limit * 0.25).ceil();
}

/// Oblačnosť 0–3 z ECMWF `tcc` / `cloud_cover` (percentá).
int skyWmoFromCloudCover(double? cloudCoverPercent) {
  if (cloudCoverPercent == null) return 1;
  final c = cloudCoverPercent;
  if (c < 12) return 0;
  if (c < 28) return 1;
  if (c < 62) return 2;
  return 3;
}

/// Minimálna zrážka v UI (mm/h) — od 0,1 mm je dážď/mrholenie v poriadku.
const double kMeaningfulPrecipMmPerHour = 0.1;

/// Zrážková ikona a % v UI — iba od 50 % (dohoda).
const int kMinPrecipProbPercent = 50;

bool isMeaningfulPrecipMm(double mm, {double snowfallCm = 0.0}) =>
    mm >= kMeaningfulPrecipMmPerHour || snowfallCm >= 0.1;

bool isSkyOnlyWmoCode(int code) => code <= 3 || code == 45 || code == 48;

/// Vyšší WMO 0–3 = viac oblačnosti — pri konflikte model vs TCC berie oblačnejší stav.
int reconcileSkyCodeWithCloudCover(int skyCode, double? cloudCoverPercent) {
  if (cloudCoverPercent == null) return skyCode;
  final fromCloud = skyWmoFromCloudCover(cloudCoverPercent);
  return skyCode > fromCloud ? skyCode : fromCloud;
}

/// Ikona hodiny z Open-Meteo — WMO z API len pri potvrdených mm + %; inak oblačnosť.
int openMeteoHourlyDisplayIconCode({
  int? storedWeatherCode,
  double precipMm = 0,
  int? storedPrecipProbPercent,
  double? cloudCoverPercent,
}) {
  final stored = normalizeDisplayWeatherCode(storedWeatherCode ?? 0);
  final prob = storedPrecipProbPercent ?? 0;

  if (kPrecipitationCodes.contains(stored) &&
      ecmwfHourPrecipShowsInUi(mm: precipMm, prob: prob)) {
    return stored;
  }

  if (kPrecipitationCodes.contains(stored)) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }

  if (stored == 45 || stored == 48) return 3;
  if (cloudCoverPercent != null && isSkyOnlyWmoCode(stored)) {
    return reconcileSkyCodeWithCloudCover(stored, cloudCoverPercent);
  }
  return stored;
}

/// Ikona hodiny — WMO z modela; TCC len ak chýba hodinový sky kód alebo je dôveryhodný.
int hourlyDisplayIconCode({
  int? storedWeatherCode,
  double? cloudCoverPercent,
  double precipMm = 0,
  int? storedPrecipProbPercent,
  bool trustCloudCover = true,
  bool preferStoredSkyCode = false,
}) {
  final rawCode = storedWeatherCode ?? 0;
  final stored = normalizeDisplayWeatherCode(rawCode);
  final precipCode = kPrecipitationCodes.contains(stored);
  final prob = hourlyPrecipProbabilityPercentShown(
    storedPrecipProbPercent ?? 0,
    precipCode,
    precipMm: precipMm,
    weatherCode: rawCode,
    cloudCoverPercent: cloudCoverPercent,
  );

  if (precipMm >= kMeaningfulPrecipMmPerHour && prob >= kMinPrecipProbPercent) {
    return wmoFromPrecipitationMm(
      precipMm,
      cloudCoverPercent: cloudCoverPercent,
    );
  }

  if (kPrecipitationCodes.contains(stored) &&
      ecmwfHourPrecipShowsInUi(mm: precipMm, prob: prob)) {
    return stored;
  }

  if (kPrecipitationCodes.contains(stored)) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }

  if (preferStoredSkyCode && isSkyOnlyWmoCode(stored)) {
    if (trustCloudCover && cloudCoverPercent != null) {
      return reconcileSkyCodeWithCloudCover(stored, cloudCoverPercent);
    }
    return stored;
  }

  final effectiveCloud = trustCloudCover ? cloudCoverPercent : null;

  if (effectiveCloud != null) {
    if (isSkyOnlyWmoCode(stored) && !preferStoredSkyCode) {
      return skyWmoFromCloudCover(effectiveCloud);
    }
    if (kPrecipitationCodes.contains(stored)) {
      return ecmwfHourPrecipShowsInUi(mm: precipMm, prob: prob)
          ? stored
          : skyWmoFromCloudCover(effectiveCloud);
    }
    if (!isSkyOnlyWmoCode(stored)) {
      return stored;
    }
  }

  return displayWeatherCodeFromEcmwf(
    apiCode: storedWeatherCode,
    precipMm: precipMm,
    precipProbPercent: prob,
    cloudCoverPercent: effectiveCloud,
  );
}

/// Ikona v UI — WMO z modela + zlúčenie s mm a oblačnosťou (TCC).
int displayWeatherCodeFromEcmwf({
  int? apiCode,
  double precipMm = 0,
  int precipProbPercent = 0,
  double? cloudCoverPercent,
  double snowfallCm = 0,
}) {
  return effectiveWmoWeatherCode(
    apiCode: apiCode,
    precipMm: precipMm,
    precipProbPercent: precipProbPercent,
    cloudCoverPercent: cloudCoverPercent,
    snowfallCm: snowfallCm,
  );
}

/// WMO kód z `tp` (mm/h) — len keď ECMWF Open Data neposiela `weather_code`.
int wmoFromPrecipitationMm(
  double precipMm, {
  double snowfallCm = 0.0,
  double? cloudCoverPercent,
}) {
  if (snowfallCm >= 0.5) return snowfallCm >= 2.0 ? 73 : 71;
  if (precipMm >= 5.0) return 65;
  if (precipMm >= 2.0) return 63;
  if (precipMm >= 0.5) return 61;
  if (precipMm >= kMeaningfulPrecipMmPerHour) return 51;
  if (cloudCoverPercent != null) return skyWmoFromCloudCover(cloudCoverPercent);
  return 3;
}

/// Zlúči WMO z Open-Meteo s mm — zrážkový kód len pri potvrdených mm + %.
int effectiveWmoWeatherCode({
  int? apiCode,
  required double precipMm,
  required int precipProbPercent,
  double? cloudCoverPercent,
  double snowfallCm = 0.0,
}) {
  final showPrecipIcon = ecmwfHourPrecipShowsInUi(mm: precipMm, prob: precipProbPercent) ||
      snowfallCm >= 0.1;

  if (apiCode != null) {
    final code = normalizeDisplayWeatherCode(apiCode);
    if (isSkyOnlyWmoCode(code)) {
      if (showPrecipIcon) {
        return wmoFromPrecipitationMm(
          precipMm,
          snowfallCm: snowfallCm,
          cloudCoverPercent: cloudCoverPercent,
        );
      }
      return reconcileSkyCodeWithCloudCover(code, cloudCoverPercent);
    }
    if (kPrecipitationCodes.contains(code)) {
      if (showPrecipIcon) return code;
      return skyWmoFromCloudCover(cloudCoverPercent);
    }
    return code;
  }

  if (showPrecipIcon) {
    return wmoFromPrecipitationMm(
      precipMm,
      snowfallCm: snowfallCm,
      cloudCoverPercent: cloudCoverPercent,
    );
  }
  return skyWmoFromCloudCover(cloudCoverPercent);
}

const Set<int> kThunderWeatherCodes = {95, 96, 99};

/// Má hodina v 24 h pásme hlásiť dážď (ikona + % + mm z ECMWF)?
bool hourlyStripShowRainPrecip({
  required int iconCode,
  required double precipMm,
  required int precipProb,
}) {
  if (!kPrecipitationCodes.contains(normalizeDisplayWeatherCode(iconCode))) {
    return false;
  }
  return ecmwfHourPrecipShowsInUi(mm: precipMm, prob: precipProb);
}

/// Pri detegovaných bleskoch v okolí — zobraz búrkovú ikonu (WMO 95).
int applyNearbyLightningIcon(
  int code, {
  required bool lightningNearby,
  double precipMm = 0,
  int precipProb = 0,
}) {
  if (!lightningNearby) return code;
  if (kThunderWeatherCodes.contains(code)) return code;
  return 95;
}

const List<int> _kPrecipProbDisplayTiers = [50, 60, 70, 80, 90, 100];

int _bumpPrecipProbTier(int tier, int steps) {
  final clamped = tier.clamp(50, 100);
  var index = _kPrecipProbDisplayTiers.indexOf(clamped);
  if (index < 0) {
    index = _kPrecipProbDisplayTiers.indexWhere((t) => t >= clamped);
    if (index < 0) index = _kPrecipProbDisplayTiers.length - 1;
  }
  final next = index + steps;
  if (next >= _kPrecipProbDisplayTiers.length) {
    return _kPrecipProbDisplayTiers.last;
  }
  return _kPrecipProbDisplayTiers[next];
}

int _precipProbTierFromMm(double mm) {
  if (mm >= 2.0) return 90;
  if (mm >= 1.0) return 80;
  if (mm >= 0.5) return 70;
  if (mm >= 0.28) return 70;
  if (mm >= 0.18) return 60;
  if (mm >= kMeaningfulPrecipMmPerHour) return 50;
  return 0;
}

/// Odhad % z mm/h a WMO kódu — len ak ECMWF má zrážkový kód; výstup vždy po 10 %.
int precipProbabilityFromMm(
  double mm, {
  bool precipWeatherCode = false,
  int? weatherCode,
  double? cloudCoverPercent,
}) {
  if (!precipWeatherCode) return 0;

  var tier = _precipProbTierFromMm(mm);

  if (weatherCode != null) {
    tier = _precipProbFromWmoCode(weatherCode, tier);
  }

  if (cloudCoverPercent != null && mm < 0.22) {
    if (cloudCoverPercent >= 92 && tier < 70) {
      tier = _bumpPrecipProbTier(tier, 1);
    } else if (cloudCoverPercent >= 82 && tier == 50) {
      tier = 60;
    }
  }

  return tier.clamp(kMinPrecipProbPercent, 100);
}

/// Posun o jednu desiatku podľa intenzity WMO (mrholenie vs. dážď vs. búrka).
int _precipProbFromWmoCode(int code, int tier) {
  code = normalizeDisplayWeatherCode(code);
  if ({95, 96, 99}.contains(code)) {
    return tier < 70 ? 70 : tier;
  }
  if ({65, 67, 82, 73, 75, 86}.contains(code)) {
    return _bumpPrecipProbTier(tier, 1);
  }
  if ({63, 81, 71, 85}.contains(code)) {
    return tier == 50 ? 60 : tier;
  }
  if ({61, 80, 56, 57}.contains(code)) {
    return tier == 50 ? 60 : tier;
  }
  return tier;
}

final Set<int> kPrecipitationCodes = {
  51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99,
};

const Set<int> kSnowWeatherCodes = {
  56, 57, 66, 67, 71, 73, 75, 77, 85, 86,
};

/// „Silný“ vizuál (dažď, sneh) pri vyššej šanci a mm/cm — zoslabenie WMO stupňa; búrky (95–99) výnimka (konvekcia).
const int _kHeavyPrecipProbMin = 65;
const double _kHeavyPrecipMmDaily = 12.0;
const double _kHeavyPrecipMmBlockSum = 4.0;
const int _kModeratePrecipProbMin = 55;
const double _kModeratePrecipMmDaily = 5.0;
const double _kModeratePrecipMmBlockSum = 2.0;
const double _kHeavySnowCmDaily = 10.0;
const double _kModerateSnowCmDaily = 2.0;
const double _kHeavySnowCmBlockSum = 4.0;
const double _kModerateSnowCmBlockSum = 1.0;

/// Pri nízkom dennom súčte zobraz ľahší vizuál (mrholenie / slabé prehánky namiesto 3-pruhového dažďa).
int lightDailyPrecipVisualCode(int code) {
  if ({61, 63, 65}.contains(code)) return 51;
  if ({80, 81, 82}.contains(code)) return 80;
  return code;
}

/// Pri nízkom dennom súčte snehu zobraz ľahší vizuál (snow-drizzle namiesto snow.svg).
int lightDailySnowVisualCode(int code) {
  if ({73, 75, 86, 77, 85}.contains(code)) return 71;
  if (code == 57) return 56;
  return code;
}

/// Hlavná ikona dennej karty — zosúladenie intenzity s denným súčtom mm/cm.
int finalizeDailyCardIconCode(
  int code,
  int dailyProb, {
  required double dailyPrecipMm,
  required double dailySnowCm,
}) {
  var result = _clampPrecipitationIconIntensity(
    code,
    dailyProb,
    dailyPrecipMm,
    isDailyContext: dailyPrecipMm > 0 || dailySnowCm > 0,
    snowfallCm: dailySnowCm,
  );
  if (dailyPrecipMm > 0 &&
      dailyPrecipMm < _kModeratePrecipMmDaily &&
      kPrecipitationCodes.contains(result) &&
      !kSnowWeatherCodes.contains(result)) {
    result = lightDailyPrecipVisualCode(result);
  }
  if (dailySnowCm > 0 &&
      dailySnowCm < _kModerateSnowCmDaily &&
      kSnowWeatherCodes.contains(result)) {
    result = lightDailySnowVisualCode(result);
  }
  return result;
}

/// Po výbere ikony podľa prahu zrážok upraví intenzitu tak, aby napr. 8 mm / 50 % nevyzeralo ako silný lejak vo všetkých blokoch.
int _clampPrecipitationIconIntensity(
  int code,
  int probPercent,
  double precipMm,
  {required bool isDailyContext, double snowfallCm = 0.0}
) {
  if (_belowMeaningfulPrecipAmountForIcon(precipMm, snowfallCm) &&
      kPrecipitationCodes.contains(code)) {
    return _lightPrecipDisplayCode(code);
  }

  if (!kPrecipitationCodes.contains(code)) return code;

  final mmHeavy = isDailyContext ? _kHeavyPrecipMmDaily : _kHeavyPrecipMmBlockSum;
  final mmMod = isDailyContext ? _kModeratePrecipMmDaily : _kModeratePrecipMmBlockSum;
  final heavyOk = probPercent >= _kHeavyPrecipProbMin && precipMm >= mmHeavy;
  if (heavyOk) {
    return isDailyContext && precipMm < _kHeavyPrecipMmDaily
        ? lightDailyPrecipVisualCode(code)
        : code;
  }

  final moderateOk = probPercent >= _kModeratePrecipProbMin && precipMm >= mmMod;

  if (code == 67 && !heavyOk) return 66;

  if ({61, 63, 65, 80, 81, 82}.contains(code)) {
    if (!moderateOk) {
      final light = code == 82 || code == 81 || code == 80
          ? 80
          : (code == 65 || code == 63 || code == 61 ? 61 : code);
      return isDailyContext && precipMm > 0 && precipMm < _kModeratePrecipMmDaily
          ? lightDailyPrecipVisualCode(light)
          : light;
    }
    if (code == 82) return 81;
    if (code == 65) return 63;
    return code;
  }

  // Sneženie — prahy v cm (den / 4 h blok), nie mm dažďa.
  if ({56, 57, 71, 73, 75, 77, 85, 86}.contains(code)) {
    final snowHeavy = isDailyContext ? _kHeavySnowCmDaily : _kHeavySnowCmBlockSum;
    final snowMod = isDailyContext ? _kModerateSnowCmDaily : _kModerateSnowCmBlockSum;
    final heavySnowOk = probPercent >= _kHeavyPrecipProbMin && snowfallCm >= snowHeavy;
    final moderateSnowOk = probPercent >= _kModeratePrecipProbMin && snowfallCm >= snowMod;

    if (!moderateSnowOk) {
      final light = code == 86
          ? 85
          : ({75, 73, 85, 77}.contains(code)
              ? 71
              : (code == 57 ? 56 : code));
      if (isDailyContext &&
          snowfallCm > 0 &&
          snowfallCm < _kModerateSnowCmDaily) {
        return lightDailySnowVisualCode(light);
      }
      return light;
    }
    if (heavySnowOk) return code;
    if (code == 57) return 56;
    if (code == 75) return 73;
    if (code == 86) return 85;
    if (code == 73) return 71;
    return code;
  }

  // Búrky (95 / 96 / 99) — len pri vyššej šanci a merateľnej zrážke (mm alebo cm snehu).
  if ({95, 96, 99}.contains(code)) {
    if (!_thunderIconWarranted(probPercent, precipMm, snowfallCm: snowfallCm)) {
      final rain = 61;
      return isDailyContext && precipMm > 0 && precipMm < _kModeratePrecipMmDaily
          ? lightDailyPrecipVisualCode(rain)
          : rain;
    }
    return code;
  }

  return code;
}

/// Pravdepodobnosť zrážok v UI — vždy po 10 % (50, 60, 70 …).
int _roundPrecipProbabilityForDisplay(int value) {
  if (value <= 0) return 0;
  if (value >= 100) return 100;
  return ((value / 10.0).round() * 10).clamp(0, 100);
}

/// Hodinové % zrážok — min. 50 % pri zrážkovej ikone z ECMWF, odvodené z mm + WMO kódu.
int hourlyPrecipProbabilityPercentShown(
  int rawProbPercent,
  bool hourlyPrecipCode, {
  double precipMm = 0.0,
  int? weatherCode,
  double? cloudCoverPercent,
}) {
  var pct = rawProbPercent;
  if (hourlyPrecipCode) {
    final fromSignals = precipProbabilityFromMm(
      precipMm,
      precipWeatherCode: true,
      weatherCode: weatherCode,
      cloudCoverPercent: cloudCoverPercent,
    );
    if (pct <= 0 || pct < kMinPrecipProbPercent) {
      pct = fromSignals;
    } else {
      pct = pct > fromSignals ? pct : fromSignals;
    }
  }
  if (pct > 0 && pct < kMinPrecipProbPercent) {
    if (hourlyPrecipCode && precipMm >= kMeaningfulPrecipMmPerHour) {
      return kMinPrecipProbPercent;
    }
    return 0;
  }
  if (pct >= kMinPrecipProbPercent) {
    return _roundPrecipProbabilityForDisplay(pct);
  }
  return 0;
}

/// Šanca zrážok pri oblačnosti bez dažďovej ikony — 0 % pri jasne, inak po 10 %.
int skyPrecipChancePercentShown(int iconCode, {double? cloudCoverPercent}) {
  final code = normalizeDisplayWeatherCode(iconCode);
  if (code == 0) return 0;

  if (cloudCoverPercent != null) {
    if (cloudCoverPercent < 15) return 0;
    if (cloudCoverPercent < 30) return code >= 1 ? 10 : 0;
    if (cloudCoverPercent < 50) return 10;
    if (cloudCoverPercent < 65) return 20;
    if (cloudCoverPercent < 80) return 30;
    return 40;
  }
  switch (code) {
    case 0:
      return 0;
    case 1:
      return 10;
    case 2:
      return 20;
    case 3:
      return 30;
    default:
      return 0;
  }
}

bool _isPartlyCloudyOrOvercastSky(int skyCode) {
  final code = normalizeDisplayWeatherCode(skyCode);
  return (code >= 1 && code <= 3) || code == 45 || code == 48;
}

/// Oblačnostný WMO pre % — berie **zobrazenú** ikonu, nie surový 51–99 z API.
int _stripSkyCodeForPercent(int displayIconCode, {double? cloudCoverPercent}) {
  final code = normalizeDisplayWeatherCode(displayIconCode);
  if (kPrecipitationCodes.contains(code)) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }
  return code;
}

/// Oblačnostná báza pre panel 24 h — podľa **zobrazenej ikony** (max 30 %).
int hourlyStripCloudBaselinePercent(int skyCode, {double? cloudCoverPercent}) {
  switch (normalizeDisplayWeatherCode(skyCode)) {
    case 0:
      return 10;
    case 1:
      return 10;
    case 2:
      return 20;
    case 3:
    case 45:
    case 48:
      return 30;
    default:
      return 10;
  }
}

/// Modelové % — berie sa do úvahy len posledné 3 h pred dažďom.
int _stripModelApproachPercent(int storedProb, {int maxCap = 30}) {
  if (storedProb <= 0) return 0;
  final rounded = _roundPrecipProbabilityForDisplay(storedProb);
  final cap = maxCap.clamp(10, 40);
  if (rounded >= kMinPrecipProbPercent) return cap >= 40 ? 40 : 30;
  return rounded.clamp(10, cap);
}

/// Koľko hodín do najbližšieho dažďa v pásme (null = žiadny v okne).
int? _hoursUntilNextRainInStrip(int index, List<bool> showRainPrecip) {
  for (var j = 1; j + index < showRainPrecip.length; j++) {
    if (showRainPrecip[index + j]) return j;
  }
  return null;
}

/// Minimálne % podľa vzdialenosti dažďa — 3 h: 20, 2 h: 30, 1 h: 40.
int _preRainApproachFloor(int? hoursUntilRain) {
  if (hoursUntilRain == null) return 0;
  if (hoursUntilRain <= 1) return 40;
  if (hoursUntilRain == 2) return 30;
  if (hoursUntilRain == 3) return 20;
  return 0;
}

/// % bez hláseného dažďa — bežne max 30; 40 len 1 h pred dažďom alebo po daždi.
int hourlyStripSkyBaselinePercent({
  required int iconCode,
  required int storedProb,
  double? cloudCoverPercent,
  int? hoursUntilNextRain,
  bool previousHourShowedRain = false,
}) {
  final skyCode = _stripSkyCodeForPercent(iconCode, cloudCoverPercent: cloudCoverPercent);
  final cloudPct = hourlyStripCloudBaselinePercent(
    skyCode,
    cloudCoverPercent: cloudCoverPercent,
  );

  final inApproachWindow =
      hoursUntilNextRain != null && hoursUntilNextRain <= 3;
  final allowForty = hoursUntilNextRain == 1 || previousHourShowedRain;

  var fromModel = 0;
  if (inApproachWindow) {
    fromModel = _stripModelApproachPercent(
      storedProb,
      maxCap: allowForty ? 40 : 30,
    );
  }

  final approachFloor =
      inApproachWindow ? _preRainApproachFloor(hoursUntilNextRain) : 0;

  var pct = cloudPct;
  if (fromModel > pct) pct = fromModel;
  if (approachFloor > pct) pct = approachFloor;

  if (previousHourShowedRain && _isPartlyCloudyOrOvercastSky(skyCode)) {
    pct = pct < 40 ? 40 : pct;
  }

  final maxPct = allowForty ? 40 : 30;
  return pct.clamp(10, maxPct);
}

/// % v paneli „24 h“ — dažď 50+; pred ním postupne podľa oblačnosti a vzdialenosti.
int hourlyStripPrecipPercentShown({
  required int storedProb,
  required bool showRainPrecip,
  required int iconCode,
  int? apiWeatherCode,
  double? cloudCoverPercent,
  int? hoursUntilNextRain,
  bool previousHourShowedRain = false,
  bool radarOnlyPrecip = false,
}) {
  if (radarOnlyPrecip && !showRainPrecip) return 0;

  if (showRainPrecip) {
    final rounded = _roundPrecipProbabilityForDisplay(storedProb);
    return rounded >= kMinPrecipProbPercent ? rounded : kMinPrecipProbPercent;
  }

  return hourlyStripSkyBaselinePercent(
    iconCode: iconCode,
    storedProb: storedProb,
    cloudCoverPercent: cloudCoverPercent,
    hoursUntilNextRain: hoursUntilNextRain,
    previousHourShowedRain: previousHourShowedRain,
  );
}

/// % pre celý hodinový pás 24 h.
List<int> hourlyStripPrecipPercentsForHours({
  required List<int> storedProbs,
  required List<bool> showRainPrecip,
  required List<int> iconCodes,
  List<int?>? apiWeatherCodes,
  List<double?>? cloudCoverPercents,
  bool radarOnlyPrecip = false,
}) {
  return List<int>.generate(storedProbs.length, (i) {
    return hourlyStripPrecipPercentShown(
      storedProb: storedProbs[i],
      showRainPrecip: showRainPrecip[i],
      iconCode: iconCodes[i],
      apiWeatherCode: apiWeatherCodes != null ? apiWeatherCodes[i] : null,
      cloudCoverPercent:
          cloudCoverPercents != null ? cloudCoverPercents[i] : null,
      hoursUntilNextRain: _hoursUntilNextRainInStrip(i, showRainPrecip),
      previousHourShowedRain: i > 0 && showRainPrecip[i - 1],
      radarOnlyPrecip: radarOnlyPrecip,
    );
  });
}

/// Percento v hodinovom stĺpci — dážď ≥ 50 % alebo oblačná šanca 10–40 %.
int hourlyPrecipColumnPercentShown({
  required int rainProbPercent,
  required bool hourlyPrecipCode,
  required int iconCode,
  double? cloudCoverPercent,
  int? storedProbPercent,
  int? rawWeatherCode,
}) {
  final stored = storedProbPercent ?? 0;
  if (stored > 0) {
    if (hourlyPrecipCode && stored >= kMinPrecipProbPercent) {
      return rainProbPercent >= kMinPrecipProbPercent
          ? rainProbPercent
          : stored;
    }
    if (stored < kMinPrecipProbPercent) return stored;
  }

  if (hourlyPrecipCode && rainProbPercent >= kMinPrecipProbPercent) {
    return rainProbPercent;
  }
  if (hourlyPrecipCode) return 0;

  final skyCode = normalizeDisplayWeatherCode(
    rawWeatherCode ?? iconCode,
  );
  if (!isSkyOnlyWmoCode(skyCode) && !isSkyOnlyWmoCode(iconCode)) return 0;
  return skyPrecipChancePercentShown(
    skyCode,
    cloudCoverPercent: cloudCoverPercent,
  );
}

/// Rýchlosť/smer vetra pre hodinový riadok — JSON, current, odhad z teploty.
({double? speed, double? direction}) resolveHourlyWindValues({
  required HourlyForecast h,
  required int index,
  CurrentWeather? current,
  double? temperatureC,
}) {
  var speed = h.windSpeed != null && index < h.windSpeed!.length
      ? h.windSpeed![index]
      : null;
  var direction = h.windDirection != null && index < h.windDirection!.length
      ? h.windDirection![index]
      : null;

  if (speed == null) speed = current?.windSpeed;
  direction ??= current?.windDirection?.toDouble();

  if (speed == null && temperatureC != null) {
    final hour = index % 24;
    var base = 5.0 + (temperatureC - 8.0).clamp(-5.0, 20.0) * 0.35;
    if (hour >= 9 && hour <= 17) base += 3.0;
    if (hour >= 22 || hour <= 4) base -= 1.5;
    speed = base.clamp(2.0, 40.0);
    direction ??= ((210 + index * 23) % 360).toDouble();
  }

  return (speed: speed, direction: direction);
}

double? _hourlyListValueAt(List<double?>? list, int index) {
  if (list == null || index < 0 || index >= list.length) return null;
  return list[index];
}

DateTime locationTimeFromWeatherData(WeatherData data) {
  if (data.utcOffsetSeconds != null) {
    final utcNow = DateTime.now().toUtc();
    final loc = utcNow.add(Duration(seconds: data.utcOffsetSeconds!));
    return DateTime(loc.year, loc.month, loc.day, loc.hour, loc.minute, loc.second);
  }
  return DateTime.now();
}

int? _nearestHourlyIndex(HourlyForecast h, DateTime locTime) {
  final exact = _hourlyIndexContainingLocalTime(h, locTime);
  if (exact != null) return exact;
  if (h.time.isEmpty) return null;

  var bestIdx = 0;
  var bestDiff = 1 << 62;
  final target = locTime.millisecondsSinceEpoch;
  for (var i = 0; i < h.time.length; i++) {
    final ft = DateTime.tryParse(h.time[i]);
    if (ft == null) continue;
    final diff = (ft.millisecondsSinceEpoch - target).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      bestIdx = i;
    }
  }
  return bestIdx;
}

CurrentWeather _currentWeatherFromHourlySlot(HourlyForecast hourly, int idx) {
  return CurrentWeather(
    temperature: _hourlyListValueAt(hourly.temperature, idx),
    weatherCode: hourly.weatherCode?[idx],
    relativeHumidity: _hourlyListValueAt(hourly.relativeHumidity, idx),
    surfacePressure: _hourlyListValueAt(hourly.pressure, idx),
    windSpeed: _hourlyListValueAt(hourly.windSpeed, idx),
    windDirection: _hourlyListValueAt(hourly.windDirection, idx),
    precipitation: _hourlyListValueAt(hourly.precipitation, idx),
    time: DateTime.tryParse(hourly.time[idx]),
    uvIndex: _hourlyListValueAt(hourly.uvIndex, idx),
    cloudCover: _hourlyListValueAt(hourly.cloudCover, idx),
    apparentTemperature: _hourlyListValueAt(hourly.apparentTemperature, idx),
  );
}

CurrentWeather enrichCurrentFromHourly({
  required CurrentWeather current,
  required HourlyForecast hourly,
  required DateTime locTime,
}) {
  final idx = _nearestHourlyIndex(hourly, locTime);
  if (idx == null) return current;

  final humidity =
      current.relativeHumidity ?? _hourlyListValueAt(hourly.relativeHumidity, idx);
  final wind = current.windSpeed ?? _hourlyListValueAt(hourly.windSpeed, idx);
  final apparent =
      current.apparentTemperature ?? _hourlyListValueAt(hourly.apparentTemperature, idx);
  final temperature =
      current.temperature ?? _hourlyListValueAt(hourly.temperature, idx);

  if (humidity == current.relativeHumidity &&
      wind == current.windSpeed &&
      apparent == current.apparentTemperature &&
      temperature == current.temperature) {
    return current;
  }

  return CurrentWeather(
    temperature: temperature ?? current.temperature,
    isDay: current.isDay,
    weatherCode: current.weatherCode ?? hourly.weatherCode?[idx],
    relativeHumidity: humidity,
    surfacePressure:
        current.surfacePressure ?? _hourlyListValueAt(hourly.pressure, idx),
    windSpeed: wind,
    windDirection:
        current.windDirection ?? _hourlyListValueAt(hourly.windDirection, idx),
    precipitation:
        current.precipitation ?? _hourlyListValueAt(hourly.precipitation, idx),
    time: current.time ?? DateTime.tryParse(hourly.time[idx]),
    uvIndex: current.uvIndex ?? _hourlyListValueAt(hourly.uvIndex, idx),
    cloudCover: current.cloudCover ?? _hourlyListValueAt(hourly.cloudCover, idx),
    apparentTemperature: apparent,
    satelliteCloudCover: current.satelliteCloudCover,
  );
}

/// Doplní chýbajúce polia `current` z hodinovej predpovede (ECMWF niekedy vracia len WMO kód).
WeatherData enrichWeatherDataCurrentFromHourly(WeatherData data) {
  final hourly = data.hourly;
  if (hourly == null || hourly.time.isEmpty) return data;

  final locTime = locationTimeFromWeatherData(data);
  final current = data.current;
  if (current == null) {
    final idx = _nearestHourlyIndex(hourly, locTime);
    if (idx == null) return data;
    return data.copyWith(current: _currentWeatherFromHourlySlot(hourly, idx));
  }

  final enriched = enrichCurrentFromHourly(
    current: current,
    hourly: hourly,
    locTime: locTime,
  );
  if (identical(enriched, current)) return data;
  return data.copyWith(current: enriched);
}

double? _estimatedUvForHourlySlot(HourlyForecast hourly, int index) {
  if (index < 0 || index >= hourly.time.length) return null;
  final ft = DateTime.tryParse(hourly.time[index]);
  if (ft == null) return null;
  return estimateUvIndexFromHour(
    ft.hour,
    _hourlyListValueAt(hourly.cloudCover, index),
  );
}

HourlyForecast _hourlyWithUvIndex(HourlyForecast hourly, List<double?> uvIndex) {
  return HourlyForecast(
    time: hourly.time,
    temperature: hourly.temperature,
    dewPoint: hourly.dewPoint,
    pressure: hourly.pressure,
    weatherCode: hourly.weatherCode,
    precipitationProbability: hourly.precipitationProbability,
    precipitation: hourly.precipitation,
    windSpeed: hourly.windSpeed,
    windGusts: hourly.windGusts,
    windDirection: hourly.windDirection,
    relativeHumidity: hourly.relativeHumidity,
    uvIndex: uvIndex,
    cloudCover: hourly.cloudCover,
    apparentTemperature: hourly.apparentTemperature,
    timezone: hourly.timezone,
  );
}

DailyForecast _dailyWithUvIndexMax(DailyForecast daily, List<double?> uvIndexMax) {
  return DailyForecast(
    time: daily.time,
    weatherCode: daily.weatherCode,
    tempMax: daily.tempMax,
    tempMin: daily.tempMin,
    precipProbMax: daily.precipProbMax,
    precipSum: daily.precipSum,
    snowfallSum: daily.snowfallSum,
    sunrise: daily.sunrise,
    sunset: daily.sunset,
    uvIndexMax: uvIndexMax,
    windSpeedMax: daily.windSpeedMax,
    windGustsMax: daily.windGustsMax,
    windDirectionDominant: daily.windDirectionDominant,
    sunshineDuration: daily.sunshineDuration,
    timezone: daily.timezone,
  );
}

/// Odhadne chýbajúci UV index z hodiny a oblačnosti (ECMWF ho často neposkytuje).
WeatherData enrichWeatherDataWithEstimatedUv(WeatherData data) {
  final hourly = data.hourly;
  if (hourly == null || hourly.time.isEmpty) return data;

  final uvValues = List<double?>.filled(hourly.time.length, null);
  var changed = false;
  for (var i = 0; i < hourly.time.length; i++) {
    final existing = hourly.uvIndex != null && i < hourly.uvIndex!.length
        ? hourly.uvIndex![i]
        : null;
    if (existing != null) {
      uvValues[i] = existing;
      continue;
    }
    final estimated = _estimatedUvForHourlySlot(hourly, i);
    if (estimated == null) continue;
    uvValues[i] = estimated;
    changed = true;
  }
  if (!changed) return enrichWeatherDataCurrentFromHourly(data);

  var enriched = data.copyWith(hourly: _hourlyWithUvIndex(hourly, uvValues));

  final daily = enriched.daily;
  if (daily != null) {
    final dailyMax = List<double?>.filled(daily.time.length, null);
    var dailyChanged = false;
    for (var di = 0; di < daily.time.length; di++) {
      final existing = daily.uvIndexMax != null && di < daily.uvIndexMax!.length
          ? daily.uvIndexMax![di]
          : null;
      if (existing != null) {
        dailyMax[di] = existing;
        continue;
      }
      final dateStr = daily.time[di];
      double? dayMax;
      for (var i = 0; i < hourly.time.length; i++) {
        if (!hourly.time[i].startsWith(dateStr)) continue;
        final uv = uvValues[i];
        if (uv == null) continue;
        dayMax = dayMax == null ? uv : math.max(dayMax, uv);
      }
      if (dayMax != null) {
        dailyMax[di] = dayMax;
        dailyChanged = true;
      }
    }
    if (dailyChanged) {
      enriched = enriched.copyWith(daily: _dailyWithUvIndexMax(daily, dailyMax));
    }
  }

  return enrichWeatherDataCurrentFromHourly(enriched);
}

bool hourlyPrecipColumnShows(int percent) => percent > 0;

bool hourlyPrecipColumnIsRainEvent(int percent, bool hourlyPrecipCode) =>
    hourlyPrecipCode && percent >= kMinPrecipProbPercent;

/// Zrážková ikona/stĺpec v UI — iba pri ECMWF zrážkovom kóde a ≥ 50 %.
bool precipUiShows({
  required int probPercent,
  required bool precipWeatherCode,
  required double precipMm,
}) =>
    precipWeatherCode && probPercent >= kMinPrecipProbPercent;

/// WMO z Open-Meteo — zrážkový kód len pri mm ≥ 0,1 a šanca ≥ 50 %.
int weatherCodeForPrecipThreshold(
  int code, {
  required int probPercent,
  double precipMm = 0,
  double? cloudCoverPercent,
}) {
  final normalized = normalizeDisplayWeatherCode(code);
  if (kPrecipitationCodes.contains(normalized) &&
      !ecmwfHourPrecipShowsInUi(mm: precipMm, prob: probPercent)) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }
  return normalized;
}

/// Zrážky v UI — hodina musí mať **mm aj %** z ECMWF (holý WMO 51 pri 0 mm nestačí).
bool ecmwfHourPrecipShowsInUi({
  required double mm,
  required int prob,
}) =>
    mm >= kMeaningfulPrecipMmPerHour && prob >= kMinPrecipProbPercent;

/// Alias pre existujúce volania (weather_code sa nepoužíva ako jediný signál).
bool hourlyHourShowsPrecipInUi({
  required double mm,
  required int prob,
  int? weatherCode,
}) =>
    ecmwfHourPrecipShowsInUi(mm: mm, prob: prob);

/// Súčet mm a max % — v pásme 24 h rovnaké ikony/mm ako v horizontálnom zozname.
({double sumMm, int maxProb, bool any}) dayShowablePrecipFromHourlyAligned(
  HourlyForecast? h,
  String dateStr, {
  Map<int, int>? stripIcons,
  Map<int, double>? stripPrecipMm,
  Map<int, int>? stripProbs,
}) {
  if (h == null || h.time.isEmpty) {
    return (sumMm: 0.0, maxProb: 0, any: false);
  }
  var sum = 0.0;
  var maxProb = 0;
  var any = false;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(dateStr)) continue;

    if (stripIcons != null && stripIcons.containsKey(i)) {
      final icon = normalizeDisplayWeatherCode(stripIcons[i] ?? 0);
      if (!kPrecipitationCodes.contains(icon)) continue;
      any = true;
      sum += stripPrecipMm?[i] ?? h.precipitation?[i] ?? 0.0;
      final prob = stripProbs?[i] ?? h.precipitationProbability?[i] ?? 0;
      if (prob > maxProb) maxProb = prob;
      continue;
    }

    final mm = h.precipitation?[i] ?? 0.0;
    final prob = h.precipitationProbability?[i] ?? 0;
    final wc = h.weatherCode?[i];
    if (!hourlyHourShowsPrecipInUi(mm: mm, prob: prob, weatherCode: wc)) continue;
    any = true;
    sum += mm;
    if (prob > maxProb) maxProb = prob;
  }
  return (sumMm: sum, maxProb: maxProb, any: any);
}

/// Súčet mm a max % len z hodín, ktoré spĺňajú [hourlyHourShowsPrecipInUi].
({double sumMm, int maxProb, bool any}) dayShowablePrecipFromHourly(
  HourlyForecast? h,
  String dateStr,
) {
  if (h == null || h.time.isEmpty) {
    return (sumMm: 0.0, maxProb: 0, any: false);
  }
  var sum = 0.0;
  var maxProb = 0;
  var any = false;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(dateStr)) continue;
    final mm = h.precipitation?[i] ?? 0.0;
    final prob = h.precipitationProbability?[i] ?? 0;
    final wc = h.weatherCode?[i];
    if (!hourlyHourShowsPrecipInUi(mm: mm, prob: prob, weatherCode: wc)) continue;
    any = true;
    sum += mm;
    if (prob > maxProb) maxProb = prob;
  }
  return (sumMm: sum, maxProb: maxProb, any: any);
}

/// Deň na karte potlačí mokré ikony, ak žiadna hodina nespĺňa mm ≥ 0,1 **a** % ≥ 50.
bool shouldSuppressWetDayIconsForDay(
  HourlyForecast? h,
  String dateStr,
  double apiDailyPrecip,
  double apiDailySnow,
  int dailyApiProb,
) {
  if (h != null) {
    var anyHourOnDay = false;
    for (var i = 0; i < h.time.length; i++) {
      if (!h.time[i].startsWith(dateStr)) continue;
      anyHourOnDay = true;
      final mm = h.precipitation?[i] ?? 0.0;
      final prob = h.precipitationProbability?[i] ?? 0;
      final wc = h.weatherCode?[i];
      if (hourlyHourShowsPrecipInUi(mm: mm, prob: prob, weatherCode: wc)) {
        return false;
      }
    }
    if (anyHourOnDay) return true;
  }
  if (apiDailySnow >= 0.1) return false;
  if (apiDailyPrecip >= kMeaningfulPrecipMmPerHour &&
      dailyApiProb >= kMinPrecipProbPercent) {
    return false;
  }
  return true;
}

/// Odhad vlhkosti z teploty a oblačnosti (ECMWF JSON ju často nemá).
double estimateRelativeHumidityPercent(double tempC, double? cloudCoverPercent) {
  final cloud = cloudCoverPercent ?? 50.0;
  return (48 + cloud * 0.42 + (15 - tempC) * 0.8).clamp(35.0, 95.0);
}

/// Magnus — rosný bod z teploty a relatívnej vlhkosti.
double estimateDewPointCelsius(double tempC, double rhPercent) {
  const a = 17.62;
  const b = 243.12;
  final rh = rhPercent.clamp(1.0, 100.0);
  final gamma = (a * tempC) / (b + tempC) + math.log(rh / 100.0);
  return ((b * gamma) / (a - gamma)).clamp(-40.0, 40.0);
}

/// Pocitová teplota (zjednodušený wind chill / letný odhad).
double estimateApparentTemperatureC(
  double tempC,
  double? windKmh,
  double? rhPercent,
) {
  final w = (windKmh ?? 0).clamp(0.0, 120.0);
  final rh = rhPercent ?? 50.0;
  if (tempC <= 10.0 && w >= 4.8) {
    return 13.12 +
        0.6215 * tempC -
        11.37 * math.pow(w, 0.16) +
        0.3965 * tempC * math.pow(w, 0.16);
  }
  if (tempC >= 27.0) {
    return tempC + 0.005 * rh + 0.06 * (tempC - 27.0) - w * 0.03;
  }
  return tempC - w * 0.035;
}

/// UV index z hodiny dňa a oblačnosti (GRIB ho často nemá).
double estimateUvIndexFromHour(int hour, double? cloudCoverPercent) {
  if (hour < 5 || hour > 21) return 0;
  final daylight =
      math.sin(((hour - 5) / 16.0) * math.pi).clamp(0.0, 1.0);
  final clearMax = 7.5 * daylight;
  final cloud = (cloudCoverPercent ?? 0).clamp(0.0, 100.0);
  return (clearMax * (1.0 - cloud / 120.0)).clamp(0.0, 11.0);
}

double estimateWindGustsKmh(double? windKmh) {
  final w = windKmh ?? 5.0;
  return (w * 1.4 + 2.0).clamp(0.0, 150.0);
}

bool _hourlyListHasValues(List<double?>? values) =>
    values != null && values.any((v) => v != null);

(int riseLocalMin, int setLocalMin) solarMinutesLocal(
  double lat,
  double lon,
  DateTime date,
  int utcOffsetSeconds,
) {
  final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
  final p = math.asin(0.39795 * math.cos(0.98563 * (dayOfYear - 173) * math.pi / 180));
  final latR = lat * math.pi / 180;
  final tanProduct = math.tan(latR) * math.tan(p);
  if (tanProduct <= -1) return (0, 24 * 60);
  if (tanProduct >= 1) return (12 * 60, 12 * 60);

  final ha = math.acos(-tanProduct);
  final haMinutes = ha * 180 / math.pi * 4;
  final b = 360 / 365 * (dayOfYear - 81) * math.pi / 180;
  final eot = 9.87 * math.sin(2 * b) - 7.53 * math.cos(b) - 1.5 * math.sin(b);
  final solarNoonUtcMin = 720 + 4 * lon + eot;
  final solarNoonLocalMin = solarNoonUtcMin + utcOffsetSeconds ~/ 60;
  return (
    (solarNoonLocalMin - haMinutes).round().clamp(0, 24 * 60 - 1),
    (solarNoonLocalMin + haMinutes).round().clamp(0, 24 * 60 - 1),
  );
}

String solarIsoFromMinutes(String dateYmd, int totalMinutes) {
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return '${dateYmd}T${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';
}

/// HH:MM z ISO (`2026-06-12T05:14:00`), alebo priamo z `05:14`.
String? formatSunClockLabel(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final s = raw.trim();
  final hmOnly = RegExp(r'^(\d{1,2}):(\d{2})');
  final hmMatch = hmOnly.firstMatch(s);
  if (hmMatch != null) {
    return '${hmMatch.group(1)!.padLeft(2, '0')}:${hmMatch.group(2)!}';
  }
  if (s.contains('T')) {
    final parts = s.split('T');
    if (parts.length > 1) {
      final hm = parts[1].split(':');
      if (hm.length >= 2) {
        return '${hm[0].padLeft(2, '0')}:${hm[1].padLeft(2, '0')}';
      }
    }
  }
  final dt = DateTime.tryParse(s);
  if (dt != null) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  return null;
}

List<String> dailyDatesFromHourlyTimes(List<String> hourlyTimes) {
  final days = <String>[];
  for (final t in hourlyTimes) {
    final day = t.length >= 10 ? t.substring(0, 10) : t.split('T').first;
    if (days.isEmpty || days.last != day) {
      if (!days.contains(day)) days.add(day);
    }
  }
  return days;
}

bool solarTimesNeedFill(DailyForecast? daily) {
  if (daily == null || daily.time.isEmpty) return true;
  final sr = daily.sunrise;
  final ss = daily.sunset;
  if (sr == null || ss == null || sr.isEmpty || ss.isEmpty) return true;
  if (sr.length != daily.time.length || ss.length != daily.time.length) {
    return true;
  }
  return !sr.any((s) => formatSunClockLabel(s) != null);
}

/// ECMWF často nechá zrážkový WMO + stopu mm dlho po skutočnom konci — orez podľa mm.
const double _kEcmwfEventCoreMmFloor = 0.2;
const double _kEcmwfEventCorePeakFraction = 0.2;
const int _kEcmwfEventSplitDryGapHours = 3;

bool _hourHasEcmwfPrecipUiSignal(
  int weatherCode,
  double mm,
) {
  final code = normalizeDisplayWeatherCode(weatherCode);
  if (mm >= kMeaningfulPrecipMmPerHour) return true;
  if (kPrecipitationCodes.contains(code) && mm > 0) return true;
  return false;
}

/// `true` = hodina je zbytočný chvost predĺženého ECMWF dažďa/snehu.
List<bool> ecmwfPrecipEventTailTrimMask(HourlyForecast h) {
  final n = h.time.length;
  final mask = List<bool>.filled(n, false);
  if (n == 0) return mask;

  double mmAt(int i) => h.precipitation?[i] ?? 0.0;
  int codeAt(int i) => h.weatherCode?[i] ?? 0;

  bool isDryGap(int i) {
    if (i < 0 || i >= n) return true;
    final mm = mmAt(i);
    final code = normalizeDisplayWeatherCode(codeAt(i));
    if (mm >= kMeaningfulPrecipMmPerHour) return false;
    if (kPrecipitationCodes.contains(code) && mm > 0) return false;
    return true;
  }

  var i = 0;
  while (i < n) {
    if (!_hourHasEcmwfPrecipUiSignal(codeAt(i), mmAt(i))) {
      i++;
      continue;
    }

    final start = i;
    while (i < n && _hourHasEcmwfPrecipUiSignal(codeAt(i), mmAt(i))) {
      i++;
    }
    var end = i - 1;

    // Krátka prestávka v strede — stále jedna udalosť (max 2 h sucha).
    var look = i;
    var dryGap = 0;
    while (look < n && dryGap < _kEcmwfEventSplitDryGapHours) {
      if (!isDryGap(look)) break;
      dryGap++;
      look++;
    }
    if (dryGap > 0 &&
        dryGap < _kEcmwfEventSplitDryGapHours &&
        look < n &&
        _hourHasEcmwfPrecipUiSignal(codeAt(look), mmAt(look))) {
      while (look < n && _hourHasEcmwfPrecipUiSignal(codeAt(look), mmAt(look))) {
        end = look;
        look++;
      }
      i = look;
    }

    var peakMm = 0.0;
    for (var j = start; j <= end; j++) {
      peakMm = math.max(peakMm, mmAt(j));
    }
    final sigThresh = math.max(
      _kEcmwfEventCoreMmFloor,
      peakMm * _kEcmwfEventCorePeakFraction,
    );

    var lastSig = -1;
    for (var j = start; j <= end; j++) {
      if (mmAt(j) >= sigThresh) lastSig = j;
    }
    if (lastSig < 0) {
      for (var j = end; j >= start; j--) {
        if (mmAt(j) >= kMeaningfulPrecipMmPerHour) {
          lastSig = j;
          break;
        }
      }
    }
    if (lastSig < 0) continue;

    var eventEnd = lastSig;
    var weakTailLen = 0;
    for (var j = lastSig + 1; j <= end; j++) {
      if (mmAt(j) < sigThresh) {
        weakTailLen++;
      } else {
        break;
      }
    }
    if (weakTailLen <= 1 &&
        lastSig + 1 <= end &&
        mmAt(lastSig + 1) >= kMeaningfulPrecipMmPerHour) {
      eventEnd = lastSig + 1;
    }

    for (var j = eventEnd + 1; j <= end; j++) {
      mask[j] = true;
    }
  }

  return mask;
}

class ProcessedWeather {
  final int code;
  final int prob;
  final double precip;
  ProcessedWeather(this.code, this.prob, this.precip);
}

/// WMO z Open-Meteo — pri nepotvrdených zrážkach sa kód zjemní na oblačnosť.
ProcessedWeather _processWeather(
  int rawCode,
  int rawProb,
  double rawPrecip, {
  bool isHourly = false,
  String? timeStr,
  bool trimPrecipTail = false,
  double? cloudCoverPercent,
}) {
  if (trimPrecipTail &&
      kPrecipitationCodes.contains(normalizeDisplayWeatherCode(rawCode))) {
    rawCode = reconcileSkyCodeWithCloudCover(
      skyWmoFromCloudCover(cloudCoverPercent),
      cloudCoverPercent,
    );
    rawProb = 0;
    rawPrecip = 0;
  }

  final precipCode = kPrecipitationCodes.contains(rawCode);
  final prob = hourlyPrecipProbabilityPercentShown(
    rawProb,
    precipCode,
    precipMm: rawPrecip,
    weatherCode: rawCode,
  );
  final code = weatherCodeForPrecipThreshold(
    rawCode,
    probPercent: prob,
    precipMm: rawPrecip,
  );
  return ProcessedWeather(code, prob, rawPrecip);
}

class NoGlowScrollBehavior extends ScrollBehavior {
  const NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

/// Ikona aplikácie v kruhu — [DecorationImage] + border vedie k „vlásenkám“ pri okrajoch PNG;
/// orez cez [ClipOval] a mierny overscale ich odstráni.
Widget circleAppIconAsset(
  double diameter, {
  Color borderColor = const Color(0x38FFFFFF),
  double borderWidth = 1,
}) {
  return SizedBox(
    width: diameter,
    height: diameter,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: Image.asset(
          'assets/icon.png',
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          isAntiAlias: true,
        ),
      ),
    ),
  );
}
