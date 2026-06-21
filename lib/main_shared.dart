part of 'main.dart';

// --- KONŠTANTY A NASTAVENIA ---
/// Predvoľba zdroja predpovede (aktuálne len ECMWF cez Open-Meteo).
enum WeatherForecastModel {
  /// ECMWF IFS — výhradne cez Open-Meteo `/v1/ecmwf`.
  openMeteo._('ecmwf_ifs', 'ECMWF IFS', 'Globálna predpoveď ECMWF (0,25°) cez Open-Meteo API.');

  /// Kľúč cache (`CacheManager`).
  final String cacheKey;

  final String uiTitle;
  final String uiSubtitle;

  const WeatherForecastModel._(this.cacheKey, this.uiTitle, this.uiSubtitle);

  static WeatherForecastModel fromStorage(String? raw) {
    if (raw == 'bestmatch' || raw == 'best_match') {
      return WeatherForecastModel.openMeteo;
    }
    if (raw == null || raw.isEmpty) return WeatherForecastModel.openMeteo;
    if (raw == 'ecmwf_ifs' || raw == 'open_meteo') {
      return WeatherForecastModel.openMeteo;
    }
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
  if (modelId == 'ecmwf_ifs' || modelId == 'open_meteo' || modelId == 'ecmwf_ifs025') {
    return forecastWeatherCacheKey(WeatherForecastModel.openMeteo);
  }
  if (modelId == 'bestmatch' || modelId == 'best_match') {
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
const String kNominatimSearchApi = 'https://nominatim.openstreetmap.org/search';
const String kNominatimUserAgent = 'pocasie-app/1.0 (flutter)';

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
const String kDailyPrecipDisplayLatchKey = 'daily_precip_display_latch_v1';

/// Denný úhrn mm/% — po daždi API často klesne; držíme maximum v rámci relácie aj medzi spusteniami.
class DailyPrecipDisplayLatch {
  DailyPrecipDisplayLatch._();

  static final Map<String, double> _mm = {};
  static final Map<String, int> _prob = {};
  static bool _storageLoaded = false;
  static Future<void>? _loadFuture;

  static String _key(double lat, double lon, String dateStr) =>
      '${lat.toStringAsFixed(3)}_${lon.toStringAsFixed(3)}_$dateStr';

  static Future<void> ensureLoaded() {
    _loadFuture ??= _loadFromStorage();
    return _loadFuture!;
  }

  static Future<void> _loadFromStorage() async {
    if (_storageLoaded) return;
    _storageLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kDailyPrecipDisplayLatchKey);
      if (raw == null || raw.isEmpty) return;
      final map = json.decode(raw);
      if (map is! Map) return;
      for (final entry in map.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if (v is! Map) continue;
        _mm[k] = (v['mm'] as num?)?.toDouble() ?? 0.0;
        _prob[k] = (v['prob'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, dynamic>{};
      final keys = {..._mm.keys, ..._prob.keys};
      for (final k in keys) {
        final mm = _mm[k] ?? 0.0;
        final prob = _prob[k] ?? 0;
        if (mm <= 0 && prob <= 0) continue;
        out[k] = {'mm': mm, 'prob': prob};
      }
      await prefs.setString(kDailyPrecipDisplayLatchKey, json.encode(out));
    } catch (_) {}
  }

  static void observe({
    required double lat,
    required double lon,
    required String dateStr,
    required double precipMm,
    required int precipProb,
  }) {
    if (dateStr.isEmpty || precipMm <= 0 && precipProb <= 0) return;
    final k = _key(lat, lon, dateStr);
    final curMm = _mm[k] ?? 0.0;
    final curProb = _prob[k] ?? 0;
    var changed = false;
    if (precipMm > curMm) {
      _mm[k] = precipMm;
      changed = true;
    }
    if (precipProb > curProb) {
      _prob[k] = precipProb;
      changed = true;
    }
    if (changed) unawaited(_persist());
  }

  static double mmFor({
    required double lat,
    required double lon,
    required String dateStr,
  }) =>
      _mm[_key(lat, lon, dateStr)] ?? 0.0;

  static int probFor({
    required double lat,
    required double lon,
    required String dateStr,
  }) =>
      _prob[_key(lat, lon, dateStr)] ?? 0;
}

void observeDailyPrecipDisplayLatch({
  required double lat,
  required double lon,
  required String dateStr,
  required double apiDailyPrecip,
  required int dailyApiProb,
  HourlyForecast? hourly,
  double expandedSumMm = 0,
  double partsSumMm = 0,
}) {
  final latchedMm = DailyPrecipDisplayLatch.mmFor(
    lat: lat,
    lon: lon,
    dateStr: dateStr,
  );
  final ecmwfSum = ecmwfDayPrecipSumMm(hourly, dateStr);
  final mm = resolveDailyCardPrecipDisplayMm(
    apiDailyPrecip: apiDailyPrecip,
    expandedSumMm: expandedSumMm,
    partsSumMm: partsSumMm,
    ecmwfHourlyDaySumMm: ecmwfSum,
    latchedPrecipMm: latchedMm,
  );
  final latchedProb = DailyPrecipDisplayLatch.probFor(
    lat: lat,
    lon: lon,
    dateStr: dateStr,
  );
  final prob = math.max(
    latchedProb,
    dailyPrecipProbForIconIntensity(
      dailyApiProb: dailyApiProb,
      hourlyDayMaxProb: hourlyDayMaxPrecipProb(hourly, dateStr),
    ),
  );
  DailyPrecipDisplayLatch.observe(
    lat: lat,
    lon: lon,
    dateStr: dateStr,
    precipMm: mm,
    precipProb: prob,
  );
}

Future<void> observeDailyPrecipDisplayLatchForWeatherData({
  required double lat,
  required double lon,
  required WeatherData data,
}) async {
  await DailyPrecipDisplayLatch.ensureLoaded();
  final daily = data.daily;
  final hourly = data.hourly;
  if (daily == null || daily.time.isEmpty) return;
  for (var i = 0; i < daily.time.length; i++) {
    final dateStr = daily.time[i];
    final apiDailyPrecip = (daily.precipSum != null && daily.precipSum!.length > i)
        ? (daily.precipSum![i] ?? 0.0)
        : 0.0;
    final dailyApiProb = daily.precipProbMax?[i] ?? 0;
    observeDailyPrecipDisplayLatch(
      lat: lat,
      lon: lon,
      dateStr: dateStr,
      apiDailyPrecip: apiDailyPrecip,
      dailyApiProb: dailyApiProb,
      hourly: hourly,
    );
  }
}
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

/// Štáty s voľne dostupnými radarovými open dátami (SHMÚ, ČHMÚ, IMGW, DWD, …).
const Set<String> kRadarOpenDataCountryCodes = {
  'SK',
  'CZ',
  'RO',
  'PL',
  'DE',
};

bool cityEligibleForRadarNowcast(String countryCode) =>
    kRadarOpenDataCountryCodes.contains(countryCode.toUpperCase());

/// SHMÚ/Helkor radar mapa v UI — len open-data štáty v rámci kompozitu (0–30°E, 43–58°N).
bool radarCoverageForCity(GeoCity city) =>
    cityEligibleForRadarNowcast(city.countryCode) &&
    coordsWithinRadarMapExtent(city.lat, city.lon);

/// RainViewer API nowcast — globálne pokrytie (nezávisle od Helkor mapy).
bool rainViewerNowcastForCity(GeoCity city) =>
    city.lat >= -60.0 &&
    city.lat <= 72.0 &&
    city.lon >= -180.0 &&
    city.lon <= 180.0;

/// Zrážkový nowcast + ECMWF sync — RainViewer kdekoľvek, Helkor fallback len v [radarCoverageForCity].
bool radarNowcastActiveForCity(GeoCity city) => rainViewerNowcastForCity(city);

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

/// WMO ikona z radarového dBZ — prahy podľa CMAX legendy (oranžová ~30, červená ~40 dBZ).
int wmoFromRadarDbz(double dbz, {required bool snow}) {
  if (snow) {
    if (dbz >= 45) return 75;
    if (dbz >= 32) return 73;
    return 71;
  }
  if (dbz >= 40) return 65;
  if (dbz >= 30) return 63;
  if (dbz >= 22) return 61;
  if (dbz >= 18) return 53;
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

/// mm/h z radarového dBZ — RainViewer legenda vs. CMAX.
double effectiveRadarMmFromDbz(double dbz, RadarNowcastContext ctx) =>
    ctx.fromRainViewer ? rainViewerMmFromDbz(dbz) : radarMmFromDbz(dbz);

/// % z radarového dBZ — RainViewer od 15 dBZ min. 50 %.
int effectiveRadarProbFromDbz(double dbz, RadarNowcastContext ctx) =>
    ctx.fromRainViewer
        ? rainViewerProbPercentFromDbz(dbz)
        : radarProbPercentFromDbz(dbz);

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

double _ecmwfHourlyPrecipMm(HourlyForecast h, int idx) =>
    h.precipitation?[idx] ?? 0.0;

int _ecmwfHourlyPrecipProb(HourlyForecast h, int idx) =>
    h.precipitationProbability?[idx] ?? 0;

bool _neighborSamePrecipMm(HourlyForecast h, int idx, int delta) {
  final other = idx + delta;
  if (other < 0 || other >= h.time.length) return false;
  final a = h.precipitation?[idx];
  final b = h.precipitation?[other];
  if (a == null || b == null) return false;
  return a >= kMeaningfulPrecipMmPerHour && (a - b).abs() < 0.01;
}

/// Reprezentatívne mm pre % keď model nemá hodnotu alebo radar nesmie kopírovať.
double displayMmFromPrecipProbability(int prob) {
  if (prob >= 90) return 1.4;
  if (prob >= 80) return 1.0;
  if (prob >= 70) return 0.6;
  if (prob >= 60) return 0.35;
  if (prob >= 50) return 0.2;
  return kMeaningfulPrecipMmPerHour;
}

/// Finálne mm pre riadok 24 h — vždy per-hodina, nie radarová kópia.
double resolveHourlyStripPrecipMm(
  HourlyForecast h,
  int idx, {
  double? radarPinMm,
  int? stripProb,
  bool wetDisplayIcon = false,
  int? displayIconCode,
}) {
  if (radarPinMm != null && radarPinMm >= kMeaningfulPrecipMmPerHour) {
    return radarPinMm;
  }

  final mm = _ecmwfHourlyPrecipMm(h, idx);
  var prob = _ecmwfHourlyPrecipProb(h, idx);
  if (stripProb != null && stripProb > prob) {
    prob = stripProb;
  }
  if (wetDisplayIcon && prob < kMinPrecipProbPercent) {
    prob = kMinPrecipProbPercent;
  }

  if (prob < kMinPrecipProbPercent && mm < kMeaningfulPrecipMmPerHour) {
    return mm > 0 ? mm : 0.0;
  }

  final probBased = displayMmFromPrecipProbability(prob);

  if (mm < kMeaningfulPrecipMmPerHour) {
    return _finalizeHourlyStripPrecipMm(probBased, displayIconCode: displayIconCode);
  }

  // ECMWF niekedy opakuje rovnaké mm v susedných hodinách — moduluj podľa %.
  if (_neighborSamePrecipMm(h, idx, -1) || _neighborSamePrecipMm(h, idx, 1)) {
    final scaled = mm * prob / 100.0;
    if (scaled >= kMeaningfulPrecipMmPerHour) {
      return _finalizeHourlyStripPrecipMm(
        double.parse(scaled.toStringAsFixed(1)),
        displayIconCode: displayIconCode,
      );
    }
    return _finalizeHourlyStripPrecipMm(probBased, displayIconCode: displayIconCode);
  }

  return _finalizeHourlyStripPrecipMm(mm, displayIconCode: displayIconCode);
}

double _finalizeHourlyStripPrecipMm(
  double mm, {
  int? displayIconCode,
}) {
  final code = displayIconCode != null
      ? normalizeDisplayWeatherCode(displayIconCode)
      : null;
  if (code != null && kThunderWeatherCodes.contains(code)) {
    return math.max(mm, kThunderMinMmPerHour);
  }
  return mm;
}

/// Každá hodina má vlastné mm z ECMWF — radar len pri pine / bez modelového mm.
void _syncHourlyStripPrecipMmFromEcmwf({
  required List<double> precipMm,
  required List<int> storedProbs,
  required List<bool> showRainPrecip,
  required List<int> displayIcons,
  required List<int> stripIndices,
  required HourlyForecast h,
  required RadarNowcastContext radarCtx,
  required DateTime locTime,
  int? utcOffsetSeconds,
}) {
  final hybridRadar = radarCtx.eligible;
  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );

  for (var i = 0; i < stripIndices.length; i++) {
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

    if (radarCtx.suppressEcmwfStripPrecipAtHour(slotHour, locTime)) {
      precipMm[i] = 0;
      storedProbs[i] = 0;
      showRainPrecip[i] = false;
      displayIcons[i] = skyWmoFromCloudCover(h.cloudCover?[idx]);
      continue;
    }

    final wet =
        showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i]);
    if (!wet) continue;

    final pinNow = slotHour == nowHour && radarCtx.precipNow;
    final radarAuth = radarCtx.eligible &&
        radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime);
    final existingMm = precipMm[i];

    if (hybridRadar && wet) {
      final hoursAhead = slotHour.difference(nowHour).inHours;
      final nearTerm = hoursAhead >= 0 &&
          hoursAhead <= _kRadarEcmwfTrimMaxHoursWhenWet;
      if (!radarAuth && nearTerm) {
        _clearHourlySlotPrecip(
          displayIcons: displayIcons,
          showRainPrecip: showRainPrecip,
          storedProbs: storedProbs,
          precipMm: precipMm,
          index: i,
          cloudCover: h.cloudCover?[idx],
        );
        continue;
      }
      if (!radarAuth) {
        storedProbs[i] = kMinPrecipProbPercent;
        precipMm[i] = math.min(
          precipMm[i],
          displayMmFromPrecipProbability(kMinPrecipProbPercent),
        );
        continue;
      }
    }

    if (useRadarOnlyNearTermPrecip(radarCtx) && !radarAuth) continue;

    if (radarAuth && existingMm >= kMeaningfulPrecipMmPerHour) {
      if (!hybridRadar) {
        final apiProb = _ecmwfHourlyPrecipProb(h, idx);
        if (apiProb > 0) {
          final next = apiProb >= kMinPrecipProbPercent
              ? apiProb
              : math.max(apiProb, kMinPrecipProbPercent);
          storedProbs[i] = math.max(storedProbs[i], next);
        }
      }
      storedProbs[i] = _boostHourlyStripWetProb(
        storedProb: storedProbs[i],
        precipMm: existingMm,
        iconCode: displayIcons[i],
        cloudCoverPercent: h.cloudCover?[idx],
        radarCtx: radarCtx,
        slotHour: slotHour,
        locTime: locTime,
      );
      continue;
    }

    precipMm[i] = resolveHourlyStripPrecipMm(
      h,
      idx,
      radarPinMm: (pinNow || radarAuth) ? existingMm : null,
      stripProb: storedProbs[i],
      wetDisplayIcon: _hourShowsPrecipIcon(displayIcons[i]),
      displayIconCode: displayIcons[i],
    );

    if (!hybridRadar && !useRadarOnlyNearTermPrecip(radarCtx)) {
      final apiProb = _ecmwfHourlyPrecipProb(h, idx);
      if (apiProb > 0) {
        final next = apiProb >= kMinPrecipProbPercent
            ? apiProb
            : math.max(apiProb, kMinPrecipProbPercent);
        storedProbs[i] = math.max(storedProbs[i], next);
      }
    }

    storedProbs[i] = _boostHourlyStripWetProb(
      storedProb: storedProbs[i],
      precipMm: precipMm[i],
      iconCode: displayIcons[i],
      cloudCoverPercent: h.cloudCover?[idx],
      radarCtx: radarCtx,
      slotHour: slotHour,
      locTime: locTime,
    );
  }
}

/// % pri zrážkovej hodine — mm a radar majú prioritu nad ECMWF minimum 50 %.
int _boostHourlyStripWetProb({
  required int storedProb,
  required double precipMm,
  required int iconCode,
  double? cloudCoverPercent,
  required RadarNowcastContext radarCtx,
  required DateTime slotHour,
  required DateTime locTime,
}) {
  var prob = storedProb;

  if (precipMm >= kMeaningfulPrecipMmPerHour) {
    prob = math.max(
      prob,
      precipProbabilityFromMm(
        precipMm,
        precipWeatherCode: true,
        weatherCode: iconCode,
        cloudCoverPercent: cloudCoverPercent,
      ),
    );
  }

  if (!radarCtx.eligible) return prob;

  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );
  if (slotHour.isBefore(nowHour)) return prob;

  final radarAuth = radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime);
  if (radarAuth) {
    final dbz = slotHour == nowHour && radarCtx.precipNow
        ? radarCtx.precipIntensityDbz
        : (radarCtx.fromRainViewer
            ? radarCtx.stripDbzForLocalHour(slotHour, locTime)
            : radarCtx.stripMmDbz);
    prob = math.max(prob, effectiveRadarProbFromDbz(dbz, radarCtx));
  } else if (radarCtx.eligible && precipMm >= kMeaningfulPrecipMmPerHour) {
    prob = math.min(prob, kMinPrecipProbPercent);
  } else if (radarCtx.incomingPrecip) {
    final hoursUntil = slotHour.difference(nowHour).inHours;
    if (hoursUntil >= 0 && hoursUntil <= 4) {
      final dbz =
          radarCtx.incomingIntensityDbz ?? radarCtx.stripDisplayDbz;
      final incomingProb = effectiveRadarProbFromDbz(dbz, radarCtx);
      prob = math.max(
        prob,
        math.max(incomingProb, kMinPrecipProbPercent),
      );
    }
  }

  return prob;
}

/// `false` = hybrid len ak radar nie je k dispozícii.
/// Keď [useRadarOnlyNearTermPrecip] — 24 h pás / hero = výhradne radar + nowcast.
const bool kRadarOnlyPrecipTestMode = false;

/// Krátkodobá predpoveď — hybrid ECMWF (max 50 %) + radar potvrdenie.
bool useRadarOnlyNearTermPrecip(RadarNowcastContext ctx) => false;

/// ECMWF zrážková hodina v 24 h — dážď / sneh / búrka z modelu.
bool _ecmwfHourlySlotModelWet(HourlyForecast h, int idx) {
  final rawMm = h.precipitation?[idx] ?? 0.0;
  final rawProb = h.precipitationProbability?[idx] ?? 0;
  final cloudCover = h.cloudCover?[idx];
  final code = effectiveWmoWeatherCode(
    apiCode: h.weatherCode?[idx],
    precipMm: rawMm,
    precipProbPercent: rawProb,
    cloudCoverPercent: cloudCover,
    snowfallCm: 0.0,
  );
  return kPrecipitationCodes.contains(code) ||
      ecmwfHourPrecipShowsInUi(mm: rawMm, prob: rawProb);
}

/// Náznak z ECMWF — vždy presne 50 %, bez radarového potvrdenia.
void _setEcmwfPrecipHintHourlySlot({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required int index,
  required int iconCode,
  required HourlyForecast h,
  required int dataIdx,
}) {
  final prob = kMinPrecipProbPercent;
  final mm = math.min(
    precipMm[index],
    displayMmFromPrecipProbability(prob),
  );
  final icon = _clampPrecipitationIconIntensity(
    iconCode,
    prob,
    mm,
    isDailyContext: false,
  );
  displayIcons[index] = icon;
  showRainPrecip[index] = true;
  storedProbs[index] = prob;
  precipMm[index] = displayMmFromPrecipProbability(prob);
}

/// 24 h pás — ECMWF max 50 %; radar potvrdí → vyššie; nepotvrdí → ikona preč.
void _applyEcmwfRadarHybridHourlyStrip({
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
    final ecmwfMm = _ecmwfHourlyPrecipMm(h, idx);
    final ecmwfProb = _ecmwfHourlyPrecipProb(h, idx);
    final ecmwfCode = effectiveWmoWeatherCode(
      apiCode: h.weatherCode?[idx],
      precipMm: ecmwfMm,
      precipProbPercent: ecmwfProb,
      cloudCoverPercent: cloudCover,
      snowfallCm: 0.0,
    );
    final ecmwfWet = _ecmwfHourlySlotModelWet(h, idx);

    if (radarCtx.suppressEcmwfStripPrecipAtHour(slotHour, locTime)) {
      _clearHourlySlotPrecip(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        cloudCover: cloudCover,
      );
      continue;
    }

    final hoursAhead = slotHour.difference(nowHour).inHours;
    final nearTerm = hoursAhead >= 0 &&
        hoursAhead <= _kRadarEcmwfTrimMaxHoursWhenWet;
    final radarAuth =
        radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime);

    if (radarAuth) {
      _applyRadarAuthorizedHourlySlot(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        slotHour: slotHour,
        locTime: locTime,
        nowHour: nowHour,
        radarCtx: radarCtx,
        tempC: tempC,
        ecmwfMm: ecmwfMm,
        ecmwfProb: ecmwfProb,
      );
      continue;
    }

    if (nearTerm && ecmwfWet) {
      _clearHourlySlotPrecip(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        cloudCover: cloudCover,
      );
      continue;
    }

    if (ecmwfWet) {
      _setEcmwfPrecipHintHourlySlot(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        iconCode: ecmwfCode,
        h: h,
        dataIdx: idx,
      );
      continue;
    }

    if (_hourShowsPrecipIcon(displayIcons[i]) || showRainPrecip[i]) {
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
  int? probPercent,
  double? mmOverride,
}) {
  final forMm = mmDbz ?? iconDbz;
  final mm = mmOverride ?? effectiveRadarMmFromDbz(forMm, radarCtx);
  final prob = math.max(
    kMinPrecipProbPercent,
    probPercent ?? effectiveRadarProbFromDbz(forMm, radarCtx),
  );
  var icon = radarCtx.fromRainViewer
      ? wmoFromRainViewerDbz(
          iconDbz,
          snow: rainViewerSnowLikely(
            tempC: tempC,
            uiDbz: iconDbz,
          ),
        )
      : wmoFromRadarDbz(
          iconDbz,
          snow: radarSnowLikely(tempC: tempC),
        );
  icon = _clampPrecipitationIconIntensity(
    icon,
    prob,
    mm,
    isDailyContext: false,
  );
  displayIcons[index] = icon;
  showRainPrecip[index] = true;
  storedProbs[index] = prob;
  precipMm[index] = mm;
}

void _applyRadarAuthorizedHourlySlot({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required int index,
  required DateTime slotHour,
  required DateTime locTime,
  required DateTime nowHour,
  required RadarNowcastContext radarCtx,
  double? tempC,
  required double ecmwfMm,
  required int ecmwfProb,
}) {
  final isCurrentHour = slotHour == nowHour;
  final atPinNow =
      radarCtx.precipNow || radarCtx.rainActiveAtPinForUi;
  final fraction = (isCurrentHour && atPinNow)
      ? 1.0
      : radarCtx.precipHourFractionAt(slotHour, locTime);

  final baseDbz = isCurrentHour && atPinNow
      ? radarCtx.precipIntensityDbz
      : (radarCtx.fromRainViewer
          ? radarCtx.stripDbzForLocalHour(slotHour, locTime)
          : radarCtx.stripMmDbz);
  final iconDbz = isCurrentHour && atPinNow
      ? radarCtx.precipIntensityDbz
      : (radarCtx.fromRainViewer
          ? radarCtx.stripDbzForLocalHour(slotHour, locTime)
          : radarCtx.stripDisplayDbz);

  final fullMm = effectiveRadarMmFromDbz(baseDbz, radarCtx);
  final fullProb = effectiveRadarProbFromDbz(baseDbz, radarCtx);
  final radarMm = fraction <= 0
      ? 0.0
      : (fullMm * fraction).clamp(0.0, fullMm);
  final radarProb = fraction <= 0
      ? 0
      : math.max(
          kMinPrecipProbPercent,
          fraction >= 0.85
              ? fullProb
              : math.max(
                  kMinPrecipProbPercent,
                  (fullProb * fraction).round(),
                ),
        );

  // Pri pine alebo radarom autorizovanej hodine: mm z intenzity radaru.
  final double mergedMm;
  if (isCurrentHour && atPinNow) {
    mergedMm = math.max(ecmwfMm, radarMm);
  } else if (radarMm >= kMeaningfulPrecipMmPerHour) {
    mergedMm = math.max(ecmwfMm, radarMm);
  } else if (ecmwfMm >= kMeaningfulPrecipMmPerHour) {
    mergedMm = ecmwfMm;
  } else if (ecmwfProb >= kMinPrecipProbPercent) {
    mergedMm = math.max(
      displayMmFromPrecipProbability(ecmwfProb),
      radarMm,
    );
  } else {
    mergedMm = math.max(ecmwfMm, radarMm);
  }

  final mmProb = mergedMm >= kMeaningfulPrecipMmPerHour && !radarCtx.fromRainViewer
      ? precipProbabilityFromMm(mergedMm, precipWeatherCode: true)
      : 0;
  final mergedProb = math.max(
    math.max(
      ecmwfProb >= kMinPrecipProbPercent
          ? ecmwfProb
          : math.max(
              math.max(ecmwfProb, kMinPrecipProbPercent),
              radarProb,
            ),
      radarProb,
    ),
    mmProb,
  );

  _setHourlySlotRadarPrecip(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMm,
    index: index,
    radarCtx: radarCtx,
    tempC: tempC,
    iconDbz: iconDbz,
    probPercent: mergedProb,
    mmOverride: mergedMm,
  );
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

    if (radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime)) {
      _applyRadarAuthorizedHourlySlot(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        slotHour: slotHour,
        locTime: locTime,
        nowHour: nowHour,
        radarCtx: radarCtx,
        tempC: tempC,
        ecmwfMm: 0,
        ecmwfProb: 0,
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

/// Radar môže meniť ECMWF len v blízkom okne — nie na celý zvyšok 24 h (zajtrajšie poobede atď.).
const int _kRadarEcmwfTrimMaxHoursWhenDry = 4;
const int _kRadarEcmwfTrimMaxHoursWhenWet = 12;

DateTime _radarEcmwfTrimHardStop(
  DateTime nowHour,
  RadarNowcastContext radarCtx,
) {
  final hours = (radarCtx.precipNow ||
          radarCtx.incomingPrecip ||
          radarCtx.authorizesPrecipAtLocalHour(
            nowHour.add(const Duration(hours: 1)),
            nowHour,
          ))
      ? _kRadarEcmwfTrimMaxHoursWhenWet
      : _kRadarEcmwfTrimMaxHoursWhenDry;
  return nowHour.add(Duration(hours: hours));
}

bool _radarMayTrimEcmwfAtHour(
  DateTime slotHour,
  DateTime nowHour,
  DateTime? dryFrom,
  RadarNowcastContext radarCtx,
) {
  final effectiveDryFrom = dryFrom ??
      (radarCtx.eligible &&
              !radarCtx.precipNow &&
              !radarCtx.incomingPrecip
          ? nowHour
          : null);
  if (effectiveDryFrom == null) return false;
  if (slotHour.isBefore(effectiveDryFrom)) return false;
  if (slotHour.isAfter(_radarEcmwfTrimHardStop(nowHour, radarCtx))) return false;
  return true;
}

DateTime radarEcmwfTrimHardStopLocal(
  DateTime locNow,
  RadarNowcastContext radarCtx,
) {
  final nowHour = DateTime(
    locNow.year,
    locNow.month,
    locNow.day,
    locNow.hour,
  );
  return _radarEcmwfTrimHardStop(nowHour, radarCtx);
}

/// Po radare obnoví ECMWF zrážky v budúcich hodinách, ktoré radar nepotvrdil ani neorezal.
void _restoreEcmwfPrecipInHourlyStrip({
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
  if (!radarCtx.eligible) return;

  if (radarCtx.radarOverridesDryEcmwfNearTerm) return;

  if (radarCtx.radarPrecipBandPassedPin && !radarCtx.incomingPrecip) {
    return;
  }

  final trimFrom = radarCtx.hourlyStripEcmwfTrimDryFromHour(locTime);
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

    if (radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime)) continue;
    if (radarCtx.suppressEcmwfStripPrecipAtHour(slotHour, locTime)) continue;
    if (slotHour == nowHour && !radarCtx.precipNow) continue;
    if (trimFrom != null &&
        !slotHour.isBefore(trimFrom) &&
        _radarMayTrimEcmwfAtHour(slotHour, nowHour, trimFrom, radarCtx)) {
      continue;
    }

    final rawMm = h.precipitation?[idx] ?? precipMm[i];
    final rawProb = h.precipitationProbability?[idx] ?? storedProbs[i];
    final cloudCover = h.cloudCover?[idx];
    const snowfall = 0.0;
    final ecmwfIcon = effectiveWmoWeatherCode(
      apiCode: h.weatherCode?[idx],
      precipMm: rawMm,
      precipProbPercent: rawProb,
      cloudCoverPercent: cloudCover,
      snowfallCm: snowfall,
    );

    if (!kPrecipitationCodes.contains(ecmwfIcon)) continue;

    displayIcons[i] = _clampPrecipitationIconIntensity(
      ecmwfIcon,
      rawProb,
      rawMm,
      isDailyContext: false,
    );
    showRainPrecip[i] = hourlyStripShowRainPrecip(
      iconCode: ecmwfIcon,
      precipMm: rawMm,
      precipProb: rawProb,
    );
    if (showRainPrecip[i]) {
      storedProbs[i] = rawProb >= kMinPrecipProbPercent
          ? rawProb
          : math.max(rawProb, kMinPrecipProbPercent);
      precipMm[i] = resolveHourlyStripPrecipMm(
        h,
        idx,
        displayIconCode: displayIcons[i],
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
    for (var i = 0; i < displayIcons.length; i++) {
      final idx = stripIndices[i];
      if (!_ecmwfHourlySlotModelWet(h, idx)) continue;
      final cloudCover = h.cloudCover?[idx];
      final ecmwfMm = _ecmwfHourlyPrecipMm(h, idx);
      final ecmwfProb = _ecmwfHourlyPrecipProb(h, idx);
      final ecmwfCode = effectiveWmoWeatherCode(
        apiCode: h.weatherCode?[idx],
        precipMm: ecmwfMm,
        precipProbPercent: ecmwfProb,
        cloudCoverPercent: cloudCover,
        snowfallCm: 0.0,
      );
      _setEcmwfPrecipHintHourlySlot(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        iconCode: ecmwfCode,
        h: h,
        dataIdx: idx,
      );
    }
    _syncHourlyStripPrecipMmFromEcmwf(
      precipMm: precipMm,
      storedProbs: storedProbs,
      showRainPrecip: showRainPrecip,
      displayIcons: displayIcons,
      stripIndices: stripIndices,
      h: h,
      radarCtx: radarCtx,
      locTime: locTime,
      utcOffsetSeconds: utcOffsetSeconds,
    );
    return;
  }

  if (radarCtx.eligible) {
    _applyEcmwfRadarHybridHourlyStrip(
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
    _syncHourlyStripPrecipMmFromEcmwf(
      precipMm: precipMm,
      storedProbs: storedProbs,
      showRainPrecip: showRainPrecip,
      displayIcons: displayIcons,
      stripIndices: stripIndices,
      h: h,
      radarCtx: radarCtx,
      locTime: locTime,
      utcOffsetSeconds: utcOffsetSeconds,
    );
    return;
  }

  if (useRadarOnlyNearTermPrecip(radarCtx)) {
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
    _syncHourlyStripPrecipMmFromEcmwf(
      precipMm: precipMm,
      storedProbs: storedProbs,
      showRainPrecip: showRainPrecip,
      displayIcons: displayIcons,
      stripIndices: stripIndices,
      h: h,
      radarCtx: radarCtx,
      locTime: locTime,
      utcOffsetSeconds: utcOffsetSeconds,
    );
    return;
  }

  final dryFrom = radarCtx.hourlyStripEcmwfTrimDryFromHour(locTime);
  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );
  final radarWetNow = radarCtx.precipNow;

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

    // Bunka už prešla — ECMWF dážď v blízkom okne zruš (aj aktuálna hodina).
    if (radarCtx.radarPrecipBandPassedPin &&
        !slotHour.isBefore(nowHour) &&
        _radarMayTrimEcmwfAtHour(
          slotHour,
          nowHour,
          nowHour,
          radarCtx,
        )) {
      displayIcons[i] = skyWmoFromCloudCover(cloudCover);
      showRainPrecip[i] = false;
      storedProbs[i] = 0;
      precipMm[i] = 0;
      continue;
    }

    // Radar priorita — potvrdené okno; ECMWF nesmie slot prepísať na sucho.
    if (radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime)) {
      _applyRadarAuthorizedHourlySlot(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        slotHour: slotHour,
        locTime: locTime,
        nowHour: nowHour,
        radarCtx: radarCtx,
        tempC: tempC,
        ecmwfMm: _ecmwfHourlyPrecipMm(h, idx),
        ecmwfProb: _ecmwfHourlyPrecipProb(h, idx),
      );
      continue;
    }

    var iconWet = _hourShowsPrecipIcon(displayIcons[i]);
    var columnWet = showRainPrecip[i];

    // Radar práve prší — doplni blízke hodiny, kde ECMWF ešte nehlási zrážky.
    if (radarWetNow &&
        !slotHour.isBefore(nowHour) &&
        (dryFrom == null ||
            slotHour.isBefore(dryFrom) ||
            !_radarMayTrimEcmwfAtHour(
              slotHour,
              nowHour,
              dryFrom,
              radarCtx,
            )) &&
        !iconWet &&
        !columnWet) {
      _applyRadarAuthorizedHourlySlot(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        slotHour: slotHour,
        locTime: locTime,
        nowHour: nowHour,
        radarCtx: radarCtx,
        tempC: tempC,
        ecmwfMm: _ecmwfHourlyPrecipMm(h, idx),
        ecmwfProb: _ecmwfHourlyPrecipProb(h, idx),
      );
      continue;
    }

    // Aktuálna hodina: radar suchý — orez ECMWF dážď (aj keď blíži sa fronta).
    if (slotHour == nowHour && !radarWetNow) {
      displayIcons[i] = skyWmoFromCloudCover(cloudCover);
      showRainPrecip[i] = false;
      storedProbs[i] = 0;
      precipMm[i] = 0;
      continue;
    }

    if (radarCtx.suppressEcmwfStripPrecipAtHour(slotHour, locTime)) {
      displayIcons[i] = skyWmoFromCloudCover(cloudCover);
      showRainPrecip[i] = false;
      storedProbs[i] = 0;
      precipMm[i] = 0;
      continue;
    }

    if (!iconWet && !columnWet) continue;

    // Orez ECMWF — len v blízkom okne; zajtrajšie hodiny model ponechaj.
    if (_radarMayTrimEcmwfAtHour(slotHour, nowHour, dryFrom, radarCtx)) {
      displayIcons[i] = skyWmoFromCloudCover(cloudCover);
      showRainPrecip[i] = false;
      storedProbs[i] = 0;
      precipMm[i] = 0;
      continue;
    }

    // Radar suchý, model ešte ukazuje dážď v budúcnosti — ponechaj ECMWF.
    if (slotHour == nowHour &&
        !radarWetNow &&
        !radarCtx.incomingPrecip &&
        radarCtx.estimatedPrecipEndHours == 0) {
      displayIcons[i] = skyWmoFromCloudCover(cloudCover);
      showRainPrecip[i] = false;
      storedProbs[i] = 0;
      precipMm[i] = 0;
    }
  }

  // Predĺženie max +1 h: ECMWF skončil, radar stále prší stabilne.
  if (radarWetNow &&
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
      final slotHour = DateTime(
        curLocal.year,
        curLocal.month,
        curLocal.day,
        curLocal.hour,
      );
      _applyRadarAuthorizedHourlySlot(
        displayIcons: displayIcons,
        showRainPrecip: showRainPrecip,
        storedProbs: storedProbs,
        precipMm: precipMm,
        index: i,
        slotHour: slotHour,
        locTime: locTime,
        nowHour: nowHour,
        radarCtx: radarCtx,
        tempC: tempC,
        ecmwfMm: _ecmwfHourlyPrecipMm(h, curIdx),
        ecmwfProb: _ecmwfHourlyPrecipProb(h, curIdx),
      );
      break;
    }
  }

  _restoreEcmwfPrecipInHourlyStrip(
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

  _syncHourlyStripPrecipMmFromEcmwf(
    precipMm: precipMm,
    storedProbs: storedProbs,
    showRainPrecip: showRainPrecip,
    displayIcons: displayIcons,
    stripIndices: stripIndices,
    h: h,
    radarCtx: radarCtx,
    locTime: locTime,
    utcOffsetSeconds: utcOffsetSeconds,
  );
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

  // Radar-only: ECMWF dážď pri „teraz“ nikdy — len živý radar / nowcast pri pine.
  if (useRadarOnlyNearTermPrecip(radarCtx) &&
      !radarCtx.precipNow &&
      !radarCtx.incomingPrecip) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }

  // Prší pri pine — radar; blíži sa bunka — náznak z radaru.
  if (radarCtx.rainActiveAtPinForUi) {
    final useDbz = radarCtx.precipIntensityDbz;
    final radarMm = effectiveRadarMmFromDbz(useDbz, radarCtx);
    final radarProb = effectiveRadarProbFromDbz(useDbz, radarCtx);
    final snow = radarCtx.fromRainViewer
        ? rainViewerSnowLikely(tempC: tempC, uiDbz: useDbz)
        : radarSnowLikely(tempC: tempC);
    var radarIcon = radarCtx.fromRainViewer
        ? wmoFromRainViewerDbz(useDbz, snow: snow)
        : wmoFromRadarDbz(useDbz, snow: snow);
    // ECMWF často podhodnotí mm/% oproti CMAX — pri živom daždi veríme radaru.
    radarIcon = _clampPrecipitationIconIntensity(
      radarIcon,
      math.max(precipProb, radarProb),
      math.max(precipMm, radarMm),
      isDailyContext: false,
    );
    return radarIcon;
  }

  if (radarCtx.incomingPrecip && radarCtx.fromRainViewer) {
    final useDbz = math.max(
      radarCtx.stripDbzForLocalHour(
        DateTime(
          locTime.year,
          locTime.month,
          locTime.day,
          locTime.hour,
        ),
        locTime,
      ),
      kRainViewerLegendMinDbz,
    );
    final radarProb = kMinPrecipProbPercent;
    final radarMm = effectiveRadarMmFromDbz(useDbz, radarCtx);
    final snow = rainViewerSnowLikely(tempC: tempC, uiDbz: useDbz);
    var radarIcon = wmoFromRainViewerDbz(useDbz, snow: snow);
    radarIcon = _clampPrecipitationIconIntensity(
      radarIcon,
      radarProb,
      radarMm,
      isDailyContext: false,
    );
    return radarIcon;
  }

  if (iconWet || modelWet) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }

  return code;
}

/// Ikona denného úseku (ráno / popoludnie / večer / noc) — radar má prioritu pred ECMWF oblačnosťou.
int applyRadarPrecipToDayPartIcon(
  int code, {
  required RadarNowcastContext radarCtx,
  required bool partHasRadarPrecip,
  double? tempC,
}) {
  if (!radarCtx.eligible || !partHasRadarPrecip) return code;
  final dbz = radarCtx.precipNow
      ? radarCtx.precipIntensityDbz
      : radarCtx.stripDisplayDbz;
  final snow = radarCtx.fromRainViewer
      ? rainViewerSnowLikely(tempC: tempC, uiDbz: dbz)
      : radarSnowLikely(tempC: tempC);
  final radarIcon = radarCtx.fromRainViewer
      ? wmoFromRainViewerDbz(dbz, snow: snow)
      : wmoFromRadarDbz(dbz, snow: snow);
  if (!kPrecipitationCodes.contains(code)) return radarIcon;
  if (!kPrecipitationCodes.contains(radarIcon)) return code;
  return radarIcon;
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
  63: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'mierny dážď'},
  65: {'icon_day': 'assets/rain.svg', 'icon_night': 'assets/rain.svg', 'description': 'silný dážď'},
  66: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'slabý mrznúci dážď'},
  67: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'silný mrznúci dážď'},
  71: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'slabé sneženie'},
  73: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'mierne sneženie'},
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

/// Búrková ikona — min. šanca a mm/h (konvekcia = výraznejší súčet).
const double kThunderMinMmPerHour = 2.0;

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
  if (snowfallCm >= 0.5) {
    return snowfallCm >= _kHeavySnowCmBlockSum
        ? 75
        : (snowfallCm >= _kModerateSnowCmBlockSum ? 73 : 71);
  }
  if (precipMm >= _kHeavyPrecipMmBlockSum) return 65;
  if (precipMm >= _kModeratePrecipMmBlockSum) return 63;
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
  final norm = normalizeDisplayWeatherCode(iconCode);
  if (!kPrecipitationCodes.contains(norm)) {
    return false;
  }
  if (kThunderWeatherCodes.contains(norm) &&
      !_thunderIconWarranted(precipProb, precipMm)) {
    return false;
  }
  return ecmwfHourPrecipShowsInUi(mm: precipMm, prob: precipProb);
}

/// Pri detegovaných bleskoch v JSON — búrková ikona (pinned aj aktuálna hodina).
int applyNearbyLightningIcon(
  int code, {
  required bool lightningNearby,
  double precipMm = 0,
  int precipProb = 0,
}) {
  if (!lightningNearby) return code;
  final norm = normalizeDisplayWeatherCode(code);
  if (kThunderWeatherCodes.contains(norm)) return code;
  return 95;
}

/// Búrková ikona len pri živých bleskoch v JSON — inak dážď / obloha podľa ECMWF.
int suppressThunderWithoutLightning(
  int code, {
  required bool lightningNearby,
  required int precipProb,
  required double precipMm,
  double? cloudCoverPercent,
}) {
  final norm = normalizeDisplayWeatherCode(code);
  if (lightningNearby) {
    if (kThunderWeatherCodes.contains(norm)) return norm;
    if (code == 95) return 95;
    return code;
  }
  if (!kThunderWeatherCodes.contains(norm)) return code;

  if (ecmwfHourPrecipShowsInUi(mm: precipMm, prob: precipProb)) {
    if (precipMm >= 1.0 || norm == 99) return 65;
    if (precipMm >= 0.45) return 63;
    return 61;
  }
  return _drySkyIconTierFromModel(
    precipProbabilityPercent: precipProb,
    hourlyPrecipitationMm: precipMm,
    cloudCoverPercent: cloudCoverPercent,
  );
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
/// 10 dní — silný dážď (rain.svg) až od denného súčtu.
const double _kHeavyPrecipMmDaily = 15.0;
/// 24 h — silný dážď (rain.svg) za jednu hodinu.
const double _kHeavyPrecipMmBlockSum = 3.0;
const int _kModeratePrecipProbMin = 55;
/// 10 dní — mierny dážď; pod týmto súčtom denná karta vždy ľahká ikona.
const double _kModeratePrecipMmDaily = 10.0;
/// 24 h — mierny dážď (drizzle.svg) za hodinu.
const double _kModeratePrecipMmBlockSum = 2.0;
const double _kHeavySnowCmDaily = 15.0;
/// Pod 2 cm/deň denná karta zjemní snehovú ikonu.
const double _kModerateSnowCmDaily = 2.0;
/// 24 h — silný sneh (snow.svg) za hodinu.
const double _kHeavySnowCmBlockSum = 3.0;
/// 24 h — mierny sneh za hodinu.
const double _kModerateSnowCmBlockSum = 1.5;

/// Výdatný denný lejak — silná ikona (rain.svg / WMO 65).
bool dailyHeavyPrecipWarranted(double precipMm, int probPercent) =>
    probPercent >= _kHeavyPrecipProbMin && precipMm >= _kHeavyPrecipMmDaily;

/// Zosilnenie zrážkovej ikony podľa denného súčtu mm a šance.
int applyHeavyDailyPrecipIconFloor(
  int code, {
  required double precipMm,
  required int probPercent,
  required bool isDailyContext,
}) {
  if (!kPrecipitationCodes.contains(code) || kSnowWeatherCodes.contains(code)) {
    return code;
  }
  final mmHeavy =
      isDailyContext ? _kHeavyPrecipMmDaily : _kHeavyPrecipMmBlockSum;
  if (probPercent >= _kHeavyPrecipProbMin && precipMm >= mmHeavy) {
    if ({51, 53, 55, 61, 63}.contains(code)) return 65;
    if (code == 80 || code == 81) return 82;
  }
  return code;
}

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
  if (dailyHeavyPrecipWarranted(dailyPrecipMm, dailyProb)) {
    result = applyHeavyDailyPrecipIconFloor(
      result,
      precipMm: dailyPrecipMm,
      probPercent: dailyProb,
      isDailyContext: true,
    );
    if (!kPrecipitationCodes.contains(result)) {
      result = 65;
    }
  }
  return result;
}

/// Po výbere ikony podľa prahu zrážok upraví intenzitu — napr. 12 mm/deň = mrholenie, nie rain.svg (až od 15 mm).
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
    var next = code;
    if ({51, 53, 55, 61, 63}.contains(next)) next = 65;
    if (next == 80 || next == 81) next = 82;
    if (isDailyContext && precipMm < _kHeavyPrecipMmDaily) {
      return lightDailyPrecipVisualCode(next);
    }
    return next;
  }

  final moderateOk = probPercent >= _kModeratePrecipProbMin && precipMm >= mmMod;

  if (code == 67 && !heavyOk) return 66;

  if ({51, 53, 55}.contains(code)) {
    if (heavyOk) return 65;
    if (moderateOk) return 63;
    return code;
  }

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
    if (code == 65 && precipMm < mmHeavy) return 63;
    if (code == 63 && precipMm < mmMod) return 61;
    if (code == 65) return 65;
    if (moderateOk && code == 61) return 63;
    if (moderateOk && code == 80) return 81;
    return code;
  }

  // Sneženie — prahy v cm (den / hodina), nie mm dažďa.
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
    if (code == 75 && snowfallCm < snowHeavy) return 73;
    if (code == 73 && snowfallCm < snowMod) return 71;
    if (code == 86) return 85;
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

/// Pravdepodobnosť zrážok v UI — dažď po 10 %; pri suchu aj 5 % kroky.
int _roundPrecipProbabilityForDisplay(int value) {
  if (value <= 0) return 0;
  if (value >= 100) return 100;
  return ((value / 10.0).round() * 10).clamp(0, 100);
}

/// Suché nebo — 0 / 5 / 10 / 15 … podľa modelu a oblačnosti.
int _snapDrySkyPercentStep(int value) {
  if (value <= 0) return 0;
  if (value <= 7) return 5;
  if (value <= 12) return 10;
  if (value <= 17) return 15;
  if (value <= 22) return 20;
  if (value <= 27) return 25;
  return ((value / 10.0).round() * 10).clamp(0, 40);
}

/// % v 24 h pásme podľa zobrazenej oblačnostnej ikony (bez dažďa).
int hourlyStripSkyIconPercent(int iconCode, {double? cloudCoverPercent}) {
  final sky = normalizeDisplayWeatherCode(
    _stripSkyCodeForPercent(iconCode, cloudCoverPercent: cloudCoverPercent),
  );
  switch (sky) {
    case 0:
      return 10; // Jasno
    case 1:
      return 20; // Prevažne jasno
    case 2:
      if (cloudCoverPercent != null && cloudCoverPercent < 55) {
        return 20;
      }
      return 30; // Polooblačno
    case 3:
    case 45:
    case 48:
      return 40; // Zamračené / hmla
    default:
      return 10;
  }
}

/// Koľko hodín od poslednej zrážkovej hodiny (ikona alebo stĺpec dažďa).
int? _hoursSinceLastRainInStrip(
  int index,
  List<bool> isRainHour, {
  int rainHoursBeforeStrip = 0,
}) {
  for (var j = 1; j <= index; j++) {
    if (isRainHour[index - j]) return j;
  }
  if (rainHoursBeforeStrip >= 1) {
    return rainHoursBeforeStrip + index;
  }
  return null;
}

/// Pás 24 h začína až od ďalšej hodiny — doplní vzdialenosť od dažďa pred prvým slotom.
int rainHoursBeforeHourlyStrip({
  required DateTime locTime,
  required DateTime firstSlotHour,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
  HourlyForecast? h,
  int? firstStripDataIndex,
  int? utcOffsetSeconds,
}) {
  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );

  DateTime? lastRainHour;

  if (radarCtx.eligible) {
    if (radarCtx.precipNow || radarCtx.rainAtPinNow) {
      final endAt = radarCtx.fromRainViewer
          ? radarCtx.stripRainMinuteEndAt(locTime)
          : radarCtx.precipMinuteEndAt(locTime);
      if (endAt != null && endAt.isAfter(firstSlotHour)) {
        return 0;
      }
      lastRainHour = nowHour;
    } else if (radarCtx.fromRainViewer) {
      final endExclusive =
          radarCtx.rainViewerNearTermWetEndExclusive(locTime);
      lastRainHour = endExclusive.subtract(const Duration(hours: 1));
      if (lastRainHour.isAfter(nowHour)) lastRainHour = nowHour;
    } else if (radarCtx.radarPrecipBandPassedPin ||
        radarCtx.hourlyStripSuppressPhantomApproachPercents(locTime)) {
      lastRainHour = nowHour.subtract(const Duration(hours: 1));
    }
  }

  if (lastRainHour == null &&
      h != null &&
      firstStripDataIndex != null &&
      firstStripDataIndex > 0) {
    for (var prevIdx = firstStripDataIndex - 1;
        prevIdx >= 0 && prevIdx >= firstStripDataIndex - 6;
        prevIdx--) {
      final code = h.weatherCode?[prevIdx] ?? 0;
      final mm = h.precipitation?[prevIdx] ?? 0.0;
      final prob = h.precipitationProbability?[prevIdx] ?? 0;
      final wet = _hourHasEcmwfPrecipUiSignal(code, mm) ||
          (kPrecipitationCodes.contains(normalizeDisplayWeatherCode(code)) &&
              prob >= kMinPrecipProbPercent);
      if (!wet) break;
      final parsed = DateTime.tryParse(h.time[prevIdx]);
      if (parsed == null) break;
      final localT = utcOffsetSeconds != null
          ? parsed.add(Duration(seconds: utcOffsetSeconds))
          : parsed;
      lastRainHour = DateTime(
        localT.year,
        localT.month,
        localT.day,
        localT.hour,
      );
    }
  }

  if (lastRainHour == null) return 0;
  final gap = firstSlotHour.difference(lastRainHour).inHours;
  if (gap >= 1 && gap <= 6) return gap;
  return 0;
}

/// Suchá hodina v 24 h pásme — pred dažďom 20→30→40, po daždi 40→30→20.
int hourlyStripDryPercent({
  required int index,
  required int iconCode,
  required List<bool> isRainHour,
  List<bool>? pastRainHour,
  double? cloudCoverPercent,
  bool suppressApproachFloors = false,
  int rainHoursBeforeStrip = 0,
}) {
  final pastRain = pastRainHour ?? isRainHour;
  final sinceRain = _hoursSinceLastRainInStrip(
    index,
    pastRain,
    rainHoursBeforeStrip: rainHoursBeforeStrip,
  );

  // Po daždi — vždy (aj keď radar orezal falošné ECMWF % pred dažďom).
  if (sinceRain == 1) return 40;
  if (sinceRain == 2) return 30;
  if (sinceRain == 3) return 20;

  if (!suppressApproachFloors) {
    final hoursUntil = _hoursUntilNextRainInStrip(index, isRainHour);
    if (hoursUntil != null && hoursUntil <= 3) {
      return _preRainApproachFloor(hoursUntil);
    }
  }

  final skyPct = hourlyStripCloudBaselinePercent(
    _stripSkyCodeForPercent(iconCode, cloudCoverPercent: cloudCoverPercent),
    cloudCoverPercent: cloudCoverPercent,
  );
  if (suppressApproachFloors) return math.min(skyPct, 30);

  final rainAhead =
      index < isRainHour.length && isRainHour.sublist(index).any((w) => w);
  return rainAhead ? skyPct : math.min(skyPct, 30);
}

void _assignDryStripBlockPercents(
  List<int> result, {
  required List<bool> isRainHour,
  required List<bool> rawRainHour,
  List<double>? precipMm,
  required List<int> storedProbs,
  required List<int> iconCodes,
  required List<double?>? cloudCoverPercents,
  required List<bool> showRainPrecip,
  List<bool>? suppressApproachFloors,
  List<bool>? pastRainHour,
  int rainHoursBeforeStrip = 0,
}) {
  final n = result.length;
  final decayPastRain = pastRainHour ?? rawRainHour;
  for (var i = 0; i < n; i++) {
    final mm = precipMm != null && i < precipMm.length ? precipMm[i] : 0.0;
    if (rawRainHour[i] || mm >= kMeaningfulPrecipMmPerHour) continue;

    final cloud = cloudCoverPercents != null ? cloudCoverPercents[i] : null;
    result[i] = hourlyStripDryPercent(
      index: i,
      iconCode: iconCodes[i],
      isRainHour: isRainHour,
      pastRainHour: decayPastRain,
      cloudCoverPercent: cloud,
      suppressApproachFloors:
          suppressApproachFloors != null && suppressApproachFloors[i],
      rainHoursBeforeStrip: rainHoursBeforeStrip,
    );
  }
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

/// Šanca zrážok pri oblačnosti bez dažďovej ikony — pre graf / denný riadok.
int skyPrecipChancePercentShown(int iconCode, {double? cloudCoverPercent}) {
  final code = normalizeDisplayWeatherCode(iconCode);
  if (code == 0) return 0;

  if (cloudCoverPercent != null) {
    if (cloudCoverPercent < 15) return code >= 1 ? 5 : 0;
    if (cloudCoverPercent < 30) return code >= 1 ? 10 : 5;
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

/// Oblačnostná báza pre panel 24 h — podľa ikony a oblačnosti (0 % pri jasne).
int hourlyStripCloudBaselinePercent(int skyCode, {double? cloudCoverPercent}) {
  final code = normalizeDisplayWeatherCode(skyCode);
  if (cloudCoverPercent != null) {
    return skyPrecipChancePercentShown(code, cloudCoverPercent: cloudCoverPercent);
  }
  switch (code) {
    case 0:
      return 0;
    case 1:
      return 10;
    case 2:
      return 20;
    case 3:
    case 45:
    case 48:
      return 30;
    default:
      return 0;
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

/// Koľko hodín do najbližšej zrážkovej hodiny v pásme.
int? _hoursUntilNextRainInStrip(int index, List<bool> isRainHour) {
  for (var j = 1; j + index < isRainHour.length; j++) {
    if (isRainHour[index + j]) return j;
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

/// % bez dažďa — deleguje na [hourlyStripDryPercent] (potrebný index v pásme).
int hourlyStripSkyBaselinePercent({
  required int iconCode,
  required int storedProb,
  double? cloudCoverPercent,
  int? hoursUntilNextRain,
  int index = 0,
  List<bool>? isRainHour,
}) {
  if (isRainHour != null) {
    return hourlyStripDryPercent(
      index: index,
      iconCode: iconCode,
      isRainHour: isRainHour,
      cloudCoverPercent: cloudCoverPercent,
    );
  }
  if (hoursUntilNextRain != null && hoursUntilNextRain <= 3) return 40;
  return hourlyStripSkyIconPercent(
    iconCode,
    cloudCoverPercent: cloudCoverPercent,
  );
}

/// % v paneli „24 h“ — dažď 50+; pri mm/radare vyššie podľa intenzity.
int hourlyStripPrecipPercentShown({
  required int storedProb,
  required bool showRainPrecip,
  required int iconCode,
  int? apiWeatherCode,
  double? cloudCoverPercent,
  int? hoursUntilNextRain,
  double precipMm = 0.0,
  bool radarOnlyPrecip = false,
}) {
  if (radarOnlyPrecip && !showRainPrecip) return 0;

  if (showRainPrecip ||
      _hourShowsPrecipIcon(iconCode) ||
      precipMm >= kMeaningfulPrecipMmPerHour) {
    var effective = math.max(storedProb, kMinPrecipProbPercent);
    if (!radarOnlyPrecip && precipMm >= kMeaningfulPrecipMmPerHour) {
      effective = math.max(
        effective,
        precipProbabilityFromMm(
          precipMm,
          precipWeatherCode: true,
          weatherCode: apiWeatherCode ?? iconCode,
          cloudCoverPercent: cloudCoverPercent,
        ),
      );
    }
    final rounded = _roundPrecipProbabilityForDisplay(effective);
    return math.max(kMinPrecipProbPercent, rounded);
  }

  return hourlyStripSkyBaselinePercent(
    iconCode: iconCode,
    storedProb: storedProb,
    cloudCoverPercent: cloudCoverPercent,
    hoursUntilNextRain: hoursUntilNextRain,
  );
}

/// % pre celý hodinový pás 24 h — dažď priamo, sucho po 3 h blokoch (5 / 10 / …).
List<int> hourlyStripPrecipPercentsForHours({
  required List<int> storedProbs,
  required List<bool> showRainPrecip,
  required List<int> iconCodes,
  List<int?>? apiWeatherCodes,
  List<double?>? cloudCoverPercents,
  List<double>? precipMm,
  bool radarOnlyPrecip = false,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
  DateTime? locTime,
  List<DateTime>? slotHours,
  int rainHoursBeforeStrip = 0,
}) {
  final n = storedProbs.length;
  final rawRainHour = List<bool>.generate(
    n,
    (i) => showRainPrecip[i] || _hourShowsPrecipIcon(iconCodes[i]),
  );

  final suppressApproach = List<bool>.filled(n, false);
  final isRainHour = List<bool>.from(rawRainHour);
  if (radarCtx.eligible && locTime != null) {
    final globalSuppress =
        radarCtx.hourlyStripSuppressPhantomApproachPercents(locTime);
    if (globalSuppress) {
      suppressApproach.fillRange(0, n, true);
    }
    if (slotHours != null) {
      for (var i = 0; i < n; i++) {
        if (i >= slotHours.length) continue;
        isRainHour[i] = radarCtx.hourlyStripSlotCountsAsRainForApproach(
          slotHours[i],
          locTime,
          stripShowsRain: rawRainHour[i],
        );
      }
    } else if (globalSuppress) {
      isRainHour.fillRange(0, n, false);
    }
  }

  final result = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    if (radarOnlyPrecip && !showRainPrecip[i]) {
      result[i] = 0;
      continue;
    }
    final mm = precipMm != null ? precipMm[i] : 0.0;
    final countsAsWetHour = rawRainHour[i];
    if (countsAsWetHour) {
      result[i] = hourlyStripPrecipPercentShown(
        storedProb: storedProbs[i],
        showRainPrecip: showRainPrecip[i] || mm >= kMeaningfulPrecipMmPerHour,
        iconCode: iconCodes[i],
        apiWeatherCode: apiWeatherCodes != null ? apiWeatherCodes[i] : null,
        cloudCoverPercent:
            cloudCoverPercents != null ? cloudCoverPercents[i] : null,
        hoursUntilNextRain: _hoursUntilNextRainInStrip(i, isRainHour),
        precipMm: mm,
        radarOnlyPrecip: radarOnlyPrecip,
      );
    }
  }

  if (!radarOnlyPrecip) {
    final pastRainForDecay = List<bool>.generate(
      n,
      (i) => rawRainHour[i] || isRainHour[i],
    );
    var beforeStrip = rainHoursBeforeStrip;
    if (beforeStrip <= 0 &&
        locTime != null &&
        slotHours != null &&
        slotHours.isNotEmpty) {
      beforeStrip = rainHoursBeforeHourlyStrip(
        locTime: locTime,
        firstSlotHour: slotHours.first,
        radarCtx: radarCtx,
      );
    }
    _assignDryStripBlockPercents(
      result,
      isRainHour: isRainHour,
      rawRainHour: rawRainHour,
      precipMm: precipMm,
      storedProbs: storedProbs,
      iconCodes: iconCodes,
      cloudCoverPercents: cloudCoverPercents,
      showRainPrecip: showRainPrecip,
      suppressApproachFloors: suppressApproach,
      pastRainHour: pastRainForDecay,
      rainHoursBeforeStrip: beforeStrip,
    );
  }

  return result;
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
    if (stored < kMinPrecipProbPercent) {
      return hourlyPrecipCode ? kMinPrecipProbPercent : stored;
    }
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

/// Denný mm pre intenzitu ikon — API súčet má prioritu oproti orezanému 24 h pásmu.
double dailyPrecipMmForIconIntensity({
  required double apiDailyPrecip,
  required double hourlySumMm,
}) =>
    math.max(apiDailyPrecip, hourlySumMm);

/// Max % zrážok v kalendárnom dni — doplnenie k dennej agregácii z API.
int hourlyDayMaxPrecipProb(HourlyForecast? h, String dateStr) {
  if (h == null || h.time.isEmpty) return 0;
  var maxP = 0;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(dateStr)) continue;
    final p = h.precipitationProbability?[i] ?? 0;
    if (p > maxP) maxP = p;
  }
  return maxP;
}

/// Denná šanca pre ikony — rovnaký signál ako „Šanca: X %“ v pätičke karty.
int dailyPrecipProbForIconIntensity({
  required int dailyApiProb,
  int hourlyStripMaxProb = 0,
  int hourlyDayMaxProb = 0,
}) => math.max(dailyApiProb, math.max(hourlyStripMaxProb, hourlyDayMaxProb));

/// Súčet mm z ECMWF hodinovky pre kalendárny deň (bez radaru).
double ecmwfDayPrecipSumMm(HourlyForecast? h, String dateStr) {
  if (h == null || h.time.isEmpty) return 0.0;
  var sum = 0.0;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(dateStr)) continue;
    sum += h.precipitation?[i] ?? 0.0;
  }
  return sum;
}

/// Úhrn v pätičke dennej karty — max(API, ECMWF hodiny, úseky); API po daždi často klesne.
double resolveDailyCardPrecipDisplayMm({
  required double apiDailyPrecip,
  required double expandedSumMm,
  required double partsSumMm,
  double ecmwfHourlyDaySumMm = 0,
  double latchedPrecipMm = 0,
}) {
  return math.max(
    latchedPrecipMm,
    math.max(
      apiDailyPrecip,
      math.max(
        ecmwfHourlyDaySumMm,
        math.max(expandedSumMm, partsSumMm),
      ),
    ),
  );
}

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

    if (stripIcons != null) {
      if (!stripIcons.containsKey(i)) continue;
      final icon = normalizeDisplayWeatherCode(stripIcons[i] ?? 0);
      if (!kPrecipitationCodes.contains(icon)) continue;
      any = true;
      var hourMm = stripPrecipMm?[i] ?? h.precipitation?[i] ?? 0.0;
      final prob = stripProbs?[i] ?? h.precipitationProbability?[i] ?? 0;
      if (hourMm < kMeaningfulPrecipMmPerHour && prob >= kMinPrecipProbPercent) {
        hourMm = displayMmFromPrecipProbability(prob);
      }
      sum += hourMm;
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

/// Denný súčet mm v rozbalenej karte — celý kalendárny deň; v pásme 24 h radarové mm.
({double sumMm, int maxProb, bool any}) dayExpandedPrecipSummary(
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
      var hourMm = stripPrecipMm?[i] ?? h.precipitation?[i] ?? 0.0;
      final prob = stripProbs?[i] ?? h.precipitationProbability?[i] ?? 0;
      if (hourMm < kMeaningfulPrecipMmPerHour && prob >= kMinPrecipProbPercent) {
        hourMm = displayMmFromPrecipProbability(prob);
      }
      sum += hourMm;
      if (prob > maxProb) maxProb = prob;
      continue;
    }

    final mm = h.precipitation?[i] ?? 0.0;
    final prob = h.precipitationProbability?[i] ?? 0;
    final wc = h.weatherCode?[i];
    if (!hourlyHourShowsPrecipInUi(mm: mm, prob: prob, weatherCode: wc)) continue;
    any = true;
    sum += mm >= kMeaningfulPrecipMmPerHour
        ? mm
        : (prob >= kMinPrecipProbPercent
            ? displayMmFromPrecipProbability(prob)
            : mm);
    if (prob > maxProb) maxProb = prob;
  }
  return (sumMm: sum, maxProb: maxProb, any: any);
}

/// Minimálny úhrn pre denný úsek (ráno/poobede/…) podľa zobrazenej ikony.
double dailySegmentMmFloorFromIcon(int iconCode, {int prob = 0}) {
  final c = normalizeDisplayWeatherCode(iconCode);
  if ({95, 96, 99}.contains(c)) return 5.0;
  if (c == 82 || c == 85 || c == 86) return 4.0;
  if (c == 65 || c == 75) return 3.5;
  if (c == 63 || c == 73 || c == 67) return 2.5;
  if (c == 61 || c == 80 || c == 81) return 1.5;
  if (prob >= kMinPrecipProbPercent) {
    return displayMmFromPrecipProbability(prob);
  }
  return 0;
}

/// Súčet mm z viditeľných úsekov dňa — sedí s ikonami ráno/poobede/večer/noc.
double dayPrecipMmFromVisibleDayParts(
  Iterable<Map<String, dynamic>> parts,
) {
  var sum = 0.0;
  for (final part in parts) {
    final code = part['iconCode'] as int?;
    if (code == null ||
        !kPrecipitationCodes.contains(normalizeDisplayWeatherCode(code))) {
      continue;
    }
    final prob = (part['prob'] as int?) ?? 0;
    final rawSum = (part['partSumMm'] as num?)?.toDouble() ?? 0.0;
    final rawMax = (part['partMaxMm'] as num?)?.toDouble() ?? 0.0;
    var segment = rawSum >= kMeaningfulPrecipMmPerHour
        ? rawSum
        : math.max(
            rawMax,
            prob >= kMinPrecipProbPercent
                ? displayMmFromPrecipProbability(prob)
                : 0.0,
          );
    segment = math.max(
      segment,
      dailySegmentMmFloorFromIcon(code, prob: prob),
    );
    sum += segment;
  }
  return sum;
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
  int dailyApiProb, {
  HourlyStripDisplayState? stripState,
  double latchedDailyPrecipMm = 0,
  int latchedDailyProb = 0,
  int? dailyWeatherCode,
}) {
  // ECMWF denný súčet — radar nesmie celý deň vytrieť; po daždi API sum často klesne.
  if (apiDailySnow >= 0.1) return false;
  if (apiDailyPrecip >= kMeaningfulPrecipMmPerHour &&
      dailyApiProb >= kMinPrecipProbPercent) {
    return false;
  }
  if (latchedDailyPrecipMm >= kMeaningfulPrecipMmPerHour &&
      latchedDailyProb >= kMinPrecipProbPercent) {
    return false;
  }
  if (dailyWeatherCode != null &&
      kPrecipitationCodes.contains(normalizeDisplayWeatherCode(dailyWeatherCode)) &&
      math.max(dailyApiProb, latchedDailyProb) >= kMinPrecipProbPercent &&
      math.max(apiDailyPrecip, latchedDailyPrecipMm) >= kMeaningfulPrecipMmPerHour) {
    return false;
  }
  if (h != null) {
    final hourlySum = ecmwfDayPrecipSumMm(h, dateStr);
    final hourlyMaxProb = hourlyDayMaxPrecipProb(h, dateStr);
    if (hourlySum >= kMeaningfulPrecipMmPerHour &&
        hourlyMaxProb >= kMinPrecipProbPercent) {
      return false;
    }
  }

  if (stripState != null && h != null) {
    for (final entry in stripState.icons.entries) {
      final i = entry.key;
      if (i < 0 || i >= h.time.length) continue;
      if (!h.time[i].startsWith(dateStr)) continue;
      final mm = stripState.precipMm[i] ?? h.precipitation?[i] ?? 0.0;
      final prob = stripState.probs[i] ?? h.precipitationProbability?[i] ?? 0;
      if (kPrecipitationCodes.contains(entry.value) ||
          ecmwfHourPrecipShowsInUi(mm: mm, prob: prob)) {
        return false;
      }
    }
  }
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

