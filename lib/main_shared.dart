part of 'main.dart';

// --- KONŠTANTY A NASTAVENIA ---
/// Predvoľba zdroja predpovede.
enum WeatherForecastModel {
  /// Open-Meteo seamless mix (bez explicitného `models` parametra).
  bestMatch._(
    'bestmatch',
    'Best Match',
    'Zhoda zrážok (väčšina modelov) — bez natiahnutia jedným modelom.',
    'https://api.open-meteo.com/v1/forecast',
    null,
  ),

  /// ECMWF IFS — výhradne cez Open-Meteo `/v1/ecmwf`.
  openMeteo._(
    'ecmwf_ifs',
    'ECMWF IFS',
    'Globálna predpoveď ECMWF (0,25°) cez Open-Meteo API.',
    'https://api.open-meteo.com/v1/ecmwf',
    null,
  );

  /// Kľúč cache (`CacheManager`).
  final String cacheKey;
  final String uiTitle;
  final String uiSubtitle;
  final String apiBase;
  final String? apiModels;

  const WeatherForecastModel._(
    this.cacheKey,
    this.uiTitle,
    this.uiSubtitle,
    this.apiBase,
    this.apiModels,
  );

  static WeatherForecastModel fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return WeatherForecastModel.bestMatch;
    if (raw == 'bestmatch' || raw == 'best_match') {
      return WeatherForecastModel.bestMatch;
    }
    if (raw == 'ecmwf_ifs' || raw == 'open_meteo' || raw == 'ecmwf_ifs025') {
      return WeatherForecastModel.openMeteo;
    }
    for (final v in WeatherForecastModel.values) {
      if (v.cacheKey == raw) return v;
    }
    return WeatherForecastModel.bestMatch;
  }
}

/// Počet dní stiahnutých z API a v grafe.
const int kForecastDays = 16;

/// Denný zoznam na domovskej obrazovke (záložka „X dní“).
const int kDailyListForecastDays = 10;

const int kOpenMeteoForecastDays = kForecastDays;
const int kChartForecastDays = kForecastDays;

/// Kľúč cache predpovede — obsahuje horizon dní kvôli kompatibilite starších volaní.
String forecastWeatherCacheKey(WeatherForecastModel model, {int days = kForecastDays}) =>
    '${model.cacheKey}_fd$days';

String forecastWeatherCacheKeyForModelId(String modelId) {
  if (modelId.isEmpty) {
    return forecastWeatherCacheKey(WeatherForecastModel.bestMatch);
  }
  if (modelId == 'ecmwf_ifs' || modelId == 'open_meteo' || modelId == 'ecmwf_ifs025') {
    return forecastWeatherCacheKey(WeatherForecastModel.openMeteo);
  }
  if (modelId == 'bestmatch' || modelId == 'best_match') {
    return forecastWeatherCacheKey(WeatherForecastModel.bestMatch);
  }
  return '${modelId}_fd$kForecastDays';
}

bool forecastJsonDailyHorizonComplete(Map<String, dynamic> map) {
  final daily = map['daily'];
  if (daily is! Map) return false;
  final times = daily['time'];
  if (times is! List) return false;
  if (map['source_provider'] == 'weatherapi') {
    return times.length >= kWeatherApiForecastDaysMin;
  }
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
  if (data?.forecastModelId == 'weatherapi') {
    return times.length >= kWeatherApiForecastDaysMin;
  }
  return times.length >= kForecastDays;
}

String weatherApiForecastCacheKey(double lat, double lon) =>
    'wapi_v2_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
const String kForecastModelKey = 'forecast_model_v1';

const String kOnboardingDoneKey = 'onboarding_playstore_fix';
/// Porovnanie s Android firstInstallTime — po reinstalli (aj s Auto Backup) znova onboarding.
const String kAppInstallEpochKey = 'app_first_install_epoch_ms';

const String kOpenMeteoForecastApi = 'https://api.open-meteo.com/v1/ecmwf';
const String kOpenMeteoAttributionUrl = 'https://open-meteo.com/';

// Geocoding — WeatherAPI search (záloha Nominatim v app_pages).
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
const String kDailyPrecipDisplayLatchKey = 'daily_precip_display_latch_v2';

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

  /// Zruší zachytené mm/% keď model už nemá zmysluplný dažďový signál.
  static void releaseIfDry({
    required double lat,
    required double lon,
    required String dateStr,
  }) {
    if (dateStr.isEmpty) return;
    final k = _key(lat, lon, dateStr);
    final had = _mm.remove(k) != null || _prob.remove(k) != null;
    if (had) unawaited(_persist());
  }

  static void observeOrRelease({
    required double lat,
    required double lon,
    required String dateStr,
    required double precipMm,
    required int precipProb,
  }) {
    if (dateStr.isEmpty) return;
    if (precipMm < kMeaningfulPrecipMmPerHour &&
        precipProb < kMinPrecipProbPercent) {
      releaseIfDry(lat: lat, lon: lon, dateStr: dateStr);
      return;
    }
    observe(
      lat: lat,
      lon: lon,
      dateStr: dateStr,
      precipMm: precipMm,
      precipProb: precipProb,
    );
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
  final trustedApiMm = trustedDailyApiPrecipMm(
    apiDailyPrecip: apiDailyPrecip,
    dailyApiProb: dailyApiProb,
    hourly: hourly,
    dateStr: dateStr,
    expandedSumMm: expandedSumMm,
    partsSumMm: partsSumMm,
  );
  final trustedApiProb = trustedDailyApiPrecipProb(
    dailyApiProb: dailyApiProb,
    hourly: hourly,
    dateStr: dateStr,
    expandedMaxProb: 0,
    partsSumMm: partsSumMm,
  );
  final uiEcmwfSum = ecmwfDayUiPrecipSumMm(hourly, dateStr);
  final mm = resolveDailyCardPrecipDisplayMm(
    apiDailyPrecip: trustedApiMm,
    expandedSumMm: expandedSumMm,
    partsSumMm: partsSumMm,
    ecmwfHourlyDaySumMm: uiEcmwfSum,
    latchedPrecipMm: latchedMm,
  );
  final latchedProb = DailyPrecipDisplayLatch.probFor(
    lat: lat,
    lon: lon,
    dateStr: dateStr,
  );
  final prob = math.max(
    latchedProb,
    trustedApiProb,
  );
  DailyPrecipDisplayLatch.observeOrRelease(
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

/// Predvolený zoom náhľadu / fullscreen radaru (mestská úroveň — nie celá SR).
const double kMeteoRadarCityZoom = 7;

const String kMeteoRadarHelkorOrigin = 'http://cz1.helkor.eu:41152';
const String kMeteoRadarMapboxGlJsUrl =
    'https://api.mapbox.com/mapbox-gl-js/v3.2.0/mapbox-gl.js';
const String kMeteoRadarMapboxGlCssUrl =
    'https://api.mapbox.com/mapbox-gl-js/v3.2.0/mapbox-gl.css';

String _helkorRadarPageUrl(GeoCity city, {bool cacheBust = false}) {
  final base =
      '$kMeteoRadarHelkorOrigin/radar/?lat=${city.lat}&lon=${city.lon}&zoom=${kMeteoRadarCityZoom.toStringAsFixed(0)}&hideUI=true';
  if (!cacheBust) return base;
  return '$base&_cb=${DateTime.now().millisecondsSinceEpoch}';
}

/// URL pre WebView — priamo Helkor.
/// Lokálny warm-proxy lámal Mapbox dlaždice (prázdna mapa, len zrážky).
String buildMeteoRadarUrl(GeoCity city, {bool cacheBust = false}) =>
    _helkorRadarPageUrl(city, cacheBust: cacheBust);

/// Pin Mapbox kamery na mesto.
///
/// Helkor pri resize späť do náhľadu (`innerHeight <= 380`) v `requestAnimationFrame`
/// volá `jumpTo(mapCenter, requestedZoom)` z **const pri loade URL** — nie z aktuálneho
/// mesta. Preto pin musíme zopakovať až po ich rAF, inak po panovaní vo full radare
/// náhľad skočí na starý stred (často celá SR ~19.6, 48.7).
///
/// [fullscreen]: `true` / `false` / `null` = nemeniteľ režim, len pin + resize.
/// [aggressiveRepin]: oneskorené pinny po Helkor resize (len návrat z fullscreen).
String buildMeteoRadarPinCityJs({
  required double lat,
  required double lon,
  bool? fullscreen,
  bool removeChrome = false,
  bool hideLayersUntilPinned = false,
  bool aggressiveRepin = false,
}) {
  final fs = fullscreen == null
      ? ''
      : '''
    if (window.setFullscreen) {
      try { window.setFullscreen(${fullscreen ? 'true' : 'false'}); } catch (eF) {}
    }''';
  final chrome = removeChrome
      ? '''
    var chrome = document.getElementById('app-radar-chrome');
    if (chrome) chrome.remove();'''
      : '';
  final hideLayers = hideLayersUntilPinned
      ? "document.documentElement.classList.remove('radar-layers-ready');"
      : '';
  final deferredPins = aggressiveRepin
      ? '''
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        pin();
        setTimeout(pin, 0);
        setTimeout(pin, 48);
        setTimeout(pin, 120);
        setTimeout(pin, 280);
      });
    });'''
      : '''
    requestAnimationFrame(function() {
      requestAnimationFrame(function() { pin(); });
    });''';
  return '''
(function() {
  try {
    document.documentElement.classList.add('hide-ui');
    $hideLayers
    $chrome
    var lat = $lat;
    var lon = $lon;
    var z = $kMeteoRadarCityZoom;
    window.__appRadarHome = { lat: lat, lon: lon, zoom: z };
    function locationDotRoots() {
      var out = [];
      try {
        document.querySelectorAll('.mapboxgl-marker').forEach(function(root) {
          if (root.querySelector('.location-dot') || root.classList.contains('location-dot')) {
            out.push(root);
          }
        });
      } catch (eQ) {}
      return out;
    }
    function keepRootForMarker(marker) {
      if (!marker || typeof marker.getElement !== 'function') return null;
      var el = marker.getElement();
      if (!el) return null;
      if (el.classList && el.classList.contains('mapboxgl-marker')) return el;
      return (el.closest && el.closest('.mapboxgl-marker')) || el.parentElement || el;
    }
    function dedupeLocationDots(keepRoot) {
      locationDotRoots().forEach(function(root) {
        if (keepRoot && root === keepRoot) return;
        if (keepRoot && keepRoot.contains && root.contains(keepRoot)) return;
        try { root.remove(); } catch (eR) {}
      });
    }
    function syncUserMarker() {
      if (typeof userMarker !== 'undefined' && userMarker) {
        try { userMarker.setLngLat([lon, lat]); } catch (eM) {}
        dedupeLocationDots(keepRootForMarker(userMarker));
        return;
      }
      // Žiadny userMarker — zmaž orphan DOM bodky a vytvor jednu na správnom mieste.
      locationDotRoots().forEach(function(root) {
        try { root.remove(); } catch (eR) {}
      });
      if (typeof mapboxgl === 'undefined' || typeof map === 'undefined' || !map) return;
      var el = document.createElement('div');
      el.className = 'location-dot';
      userMarker = new mapboxgl.Marker(el).setLngLat([lon, lat]).addTo(map);
      dedupeLocationDots(keepRootForMarker(userMarker));
    }
    function pin() {
      if (window.__appRadarUserInteracting) return false;
      if (typeof map === 'undefined' || !map || typeof map.jumpTo !== 'function') {
        return false;
      }
      map.jumpTo({ center: [lon, lat], zoom: z });
      syncUserMarker();
      try { window.requestedZoom = z; } catch (eZ) {}
      try { window.requestedLat = lat; window.requestedLon = lon; } catch (eL) {}
      return true;
    }
    if (!window.__appRadarHomeHooked) {
      window.__appRadarHomeHooked = true;
      window.addEventListener('resize', function() {
        if (window.__appRadarUserInteracting) return;
        requestAnimationFrame(function() {
          requestAnimationFrame(function() {
            if (window.__appRadarUserInteracting) return;
            var h = window.__appRadarHome;
            if (!h || typeof map === 'undefined' || !map) return;
            // Po Helkorovom widget-reset jumpTo — vždy naše aktuálne mesto.
            if (window.innerHeight <= 400) {
              try {
                map.jumpTo({ center: [h.lon, h.lat], zoom: h.zoom });
                if (typeof userMarker !== 'undefined' && userMarker) {
                  userMarker.setLngLat([h.lon, h.lat]);
                  dedupeLocationDots(keepRootForMarker(userMarker));
                } else {
                  dedupeLocationDots(locationDotRoots()[0] || null);
                }
              } catch (eH) {}
            }
          });
        });
      });
    }
    $fs
    var ok = pin();
    try { if (map && map.resize) map.resize(); } catch (eR) {}
    ok = pin() || ok;
    try { window.dispatchEvent(new Event('resize')); } catch (eD) {}
    ok = pin() || ok;
    $deferredPins
    // Helkor často pridá bodku až v map.on('load') — zmaž duplicitu po ňom.
    setTimeout(function() { try { syncUserMarker(); } catch (eS) {} }, 0);
    setTimeout(function() { try { syncUserMarker(); } catch (eS2) {} }, 200);
    setTimeout(function() { try { syncUserMarker(); } catch (eS3) {} }, 600);
    // Neodkrývaj vrstvy tu — inak biela Mapbox mapa pred dlaždicami.
    // Odkrýva až radar ready gate / Flutter.
    return ok ? '1' : '0';
  } catch (e) {
    return '0';
  }
})();
''';
}

/// Počas panovania: nepinuj kameru. Hranice SK ostávajú vždy viditeľné.
const String kMeteoRadarPanPerfJs = r'''
(function() {
  try {
    if (window.__appRadarPanPerfV2) return;
    if (typeof map === 'undefined' || !map || typeof map.on !== 'function') return;
    window.__appRadarPanPerfV2 = true;
    window.__appRadarPanPerf = true;
    var borderIds = [
      'sk-borders-glow', 'ro-borders-glow',
      'sk-borders-layer', 'ro-borders-layer'
    ];
    function restoreBorders() {
      for (var i = 0; i < borderIds.length; i++) {
        try {
          if (map.getLayer(borderIds[i])) {
            map.setLayoutProperty(borderIds[i], 'visibility', 'visible');
          }
        } catch (eL) {}
      }
    }
    restoreBorders();
    var endTimer = null;
    function onMoveStart() {
      window.__appRadarUserInteracting = true;
      if (endTimer) { clearTimeout(endTimer); endTimer = null; }
      // Ak stará verzia schovala hranice, hneď ich vráť.
      requestAnimationFrame(restoreBorders);
    }
    function onMoveEnd() {
      if (endTimer) clearTimeout(endTimer);
      endTimer = setTimeout(function() {
        endTimer = null;
        window.__appRadarUserInteracting = false;
        restoreBorders();
      }, 130);
    }
    map.on('movestart', onMoveStart);
    map.on('zoomstart', onMoveStart);
    map.on('moveend', onMoveEnd);
    map.on('zoomend', onMoveEnd);
    try {
      if (map.dragPan && map.dragPan.enable) map.dragPan.enable();
      if (map.touchZoomRotate && map.touchZoomRotate.enable) map.touchZoomRotate.enable();
      if (map.touchZoomRotate.disableRotation) map.touchZoomRotate.disableRotation();
    } catch (eD) {}
  } catch (e) {}
})();
''';

/// Radar WebView.
/// Náhľad (karta): Hybrid — Texture v scrolle často biela diera.
/// Fullscreen: Texture — Flutter kryt ostane nad mapou.
Widget buildMeteoRadarWebView({
  required WebViewController controller,
  bool hybridComposition = false,
  Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
}) {
  final gestures = gestureRecognizers ??
      <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      };
  if (WebViewPlatform.instance is AndroidWebViewPlatform) {
    return WebViewWidget.fromPlatformCreationParams(
      params: AndroidWebViewWidgetCreationParams(
        controller: controller.platform,
        displayWithHybridComposition: hybridComposition,
        gestureRecognizers: gestures,
      ),
    );
  }
  return WebViewWidget(
    controller: controller,
    gestureRecognizers: gestures,
  );
}

/// Hranice SK na Helkor radare — prednačítať + disk cache pre WebView warm-proxy.
const String kMeteoRadarSlovakiaGeoJsonUrl =
    '$kMeteoRadarHelkorOrigin/radar/slovakia.geojson';
const String kMeteoRadarRomaniaGeoJsonUrl =
    '$kMeteoRadarHelkorOrigin/radar/romania.geojson';
const String kMeteoRadarHistoryCmaxUrl =
    '$kMeteoRadarHelkorOrigin/radar/radar_history_cmax.json';

List<String> meteoRadarPrefetchUrls({GeoCity? city}) {
  final lat = city?.lat ?? 48.7;
  final lon = city?.lon ?? 19.5;
  return [
    kMeteoRadarSlovakiaGeoJsonUrl,
    kMeteoRadarRomaniaGeoJsonUrl,
    kMeteoRadarHistoryCmaxUrl,
    // Rovnaká HTML URL ako WebView — DNS/TCP.
    '$kMeteoRadarHelkorOrigin/radar/?lat=$lat&lon=$lon&zoom=7&hideUI=true',
    kMeteoRadarMapboxGlJsUrl,
    kMeteoRadarMapboxGlCssUrl,
  ];
}

class _RadarWarmAsset {
  _RadarWarmAsset(this.bytes, this.savedAt, {required this.contentType});
  final List<int> bytes;
  final DateTime savedAt;
  final String contentType;
}

HttpServer? _radarWarmServer;
int? _radarWarmPort;
Future<void>? _radarWarmStartFuture;
Directory? _radarWarmDir;
final Map<String, _RadarWarmAsset> _radarWarmMem = {};
final Map<String, Future<_RadarWarmAsset?>> _radarWarmInflight = {};
DateTime? _radarPrefetchLastRun;

Duration _radarWarmTtlForKey(String key) {
  if (key.contains('mapbox-gl')) return const Duration(days: 30);
  if (key.endsWith('.geojson')) return const Duration(days: 7);
  if (key.contains('radar_history')) return const Duration(minutes: 5);
  if (key.endsWith('.png') || key.endsWith('.webp')) {
    return const Duration(minutes: 8);
  }
  return const Duration(hours: 6);
}

String _radarWarmDiskName(String key) {
  final safe = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  if (safe.length <= 120) return safe;
  return '${safe.substring(0, 80)}_${safe.hashCode}';
}

bool _radarWarmAssetFresh(_RadarWarmAsset asset, String key) {
  return DateTime.now().difference(asset.savedAt) < _radarWarmTtlForKey(key);
}

Future<Directory> _radarWarmDirectory() async {
  final existing = _radarWarmDir;
  if (existing != null) return existing;
  final root = await getApplicationCacheDirectory();
  final dir = Directory('${root.path}/radar_warm');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  _radarWarmDir = dir;
  return dir;
}

Future<_RadarWarmAsset?> _radarWarmReadDisk(String key) async {
  try {
    final dir = await _radarWarmDirectory();
    final file = File('${dir.path}/${_radarWarmDiskName(key)}');
    final meta = File('${dir.path}/${_radarWarmDiskName(key)}.meta');
    if (!await file.exists() || !await meta.exists()) return null;
    final metaParts = (await meta.readAsString()).split('\n');
    if (metaParts.length < 2) return null;
    final savedAt = DateTime.tryParse(metaParts[0]);
    if (savedAt == null) return null;
    final contentType = metaParts[1].trim();
    final bytes = await file.readAsBytes();
    final asset = _RadarWarmAsset(bytes, savedAt, contentType: contentType);
    if (!_radarWarmAssetFresh(asset, key)) return null;
    _radarWarmMem[key] = asset;
    return asset;
  } catch (_) {
    return null;
  }
}

Future<void> _radarWarmWrite(String key, List<int> bytes, String contentType) async {
  final asset = _RadarWarmAsset(
    bytes,
    DateTime.now(),
    contentType: contentType,
  );
  _radarWarmMem[key] = asset;
  try {
    final dir = await _radarWarmDirectory();
    final file = File('${dir.path}/${_radarWarmDiskName(key)}');
    final meta = File('${dir.path}/${_radarWarmDiskName(key)}.meta');
    await file.writeAsBytes(bytes, flush: false);
    await meta.writeAsString('${asset.savedAt.toIso8601String()}\n$contentType');
  } catch (_) {}
}

Future<_RadarWarmAsset?> _radarWarmGetOrFetch(
  String key,
  String networkUrl, {
  String? contentTypeHint,
}) {
  final mem = _radarWarmMem[key];
  if (mem != null && _radarWarmAssetFresh(mem, key)) {
    return Future<_RadarWarmAsset?>.value(mem);
  }
  final inflight = _radarWarmInflight[key];
  if (inflight != null) return inflight;

  final future = () async {
    final disk = await _radarWarmReadDisk(key);
    if (disk != null) return disk;
    try {
      final r = await http.get(Uri.parse(networkUrl)).timeout(
            const Duration(seconds: 25),
          );
      if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.isEmpty) {
        return null;
      }
      final ct = contentTypeHint ??
          r.headers['content-type'] ??
          'application/octet-stream';
      await _radarWarmWrite(key, r.bodyBytes, ct);
      return _radarWarmMem[key];
    } catch (_) {
      return _radarWarmMem[key];
    } finally {
      _radarWarmInflight.remove(key);
    }
  }();
  _radarWarmInflight[key] = future;
  return future;
}

Future<void> _radarWarmHandleRequest(HttpRequest request) async {
  final response = request.response;
  try {
    final path = request.uri.path;
    if (path == '/cache/mapbox-gl.js') {
      final asset = await _radarWarmGetOrFetch(
        'mapbox-gl.js',
        kMeteoRadarMapboxGlJsUrl,
        contentTypeHint: 'application/javascript; charset=utf-8',
      );
      if (asset == null) {
        response.statusCode = HttpStatus.badGateway;
        return;
      }
      response.headers.set(HttpHeaders.contentTypeHeader, asset.contentType);
      response.headers.set(HttpHeaders.cacheControlHeader, 'public, max-age=2592000');
      response.add(asset.bytes);
      return;
    }
    if (path == '/cache/mapbox-gl.css') {
      final asset = await _radarWarmGetOrFetch(
        'mapbox-gl.css',
        kMeteoRadarMapboxGlCssUrl,
        contentTypeHint: 'text/css; charset=utf-8',
      );
      if (asset == null) {
        response.statusCode = HttpStatus.badGateway;
        return;
      }
      response.headers.set(HttpHeaders.contentTypeHeader, asset.contentType);
      response.headers.set(HttpHeaders.cacheControlHeader, 'public, max-age=2592000');
      response.add(asset.bytes);
      return;
    }

    if (!path.startsWith('/radar') && !path.startsWith('/blesky')) {
      response.statusCode = HttpStatus.notFound;
      return;
    }

    final helkorPath = path;
    final helkorUri = Uri.parse(
      '$kMeteoRadarHelkorOrigin$helkorPath${request.uri.hasQuery ? '?${request.uri.query}' : ''}',
    );

    final isHtmlPage = path == '/radar' || path == '/radar/' || path == '/radar/index.html';
    final isHistoryJson = path.endsWith('radar_history_cmax.json');
    final isStaticWarm = path.endsWith('.geojson') ||
        isHistoryJson ||
        path.endsWith('.png') ||
        path.endsWith('.webp') ||
        path.endsWith('.jpg');

    if (isHtmlPage) {
      final r = await http.get(helkorUri).timeout(const Duration(seconds: 20));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        response.statusCode = r.statusCode;
        response.add(r.bodyBytes);
        return;
      }
      // Mapbox JS/CSS nechávame na CDN — proxy z localhost láme dlaždice štýlu.
      response.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.write(r.body);
      return;
    }

    if (isStaticWarm) {
      final key = path.startsWith('/') ? path.substring(1).replaceAll('/', '_') : path;
      final asset = await _radarWarmGetOrFetch(key, helkorUri.toString());
      if (asset != null) {
        var outBytes = asset.bytes;
        var outType = asset.contentType;
        // Absolútne Helkor URL v histórii → cez proxy (inak WebView míňa disk cache).
        if (isHistoryJson) {
          final port = _radarWarmPort;
          if (port != null) {
            final rewritten = utf8.decode(asset.bytes).replaceAll(
                  kMeteoRadarHelkorOrigin,
                  'http://127.0.0.1:$port',
                );
            outBytes = utf8.encode(rewritten);
            outType = 'application/json; charset=utf-8';
          }
        }
        response.headers.set(HttpHeaders.contentTypeHeader, outType);
        response.headers.set(
          HttpHeaders.cacheControlHeader,
          'public, max-age=${_radarWarmTtlForKey(key).inSeconds}',
        );
        response.add(outBytes);
        return;
      }
    }

    final r = await http.get(helkorUri).timeout(const Duration(seconds: 25));
    response.statusCode = r.statusCode;
    var body = r.bodyBytes;
    final ct = r.headers['content-type'];
    if (isHistoryJson && r.statusCode >= 200 && r.statusCode < 300) {
      final port = _radarWarmPort;
      if (port != null) {
        final rewritten = r.body.replaceAll(
          kMeteoRadarHelkorOrigin,
          'http://127.0.0.1:$port',
        );
        body = utf8.encode(rewritten);
        response.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      } else if (ct != null) {
        response.headers.set(HttpHeaders.contentTypeHeader, ct);
      }
    } else if (ct != null) {
      response.headers.set(HttpHeaders.contentTypeHeader, ct);
    }
    response.add(body);
    if (isStaticWarm && r.statusCode >= 200 && r.statusCode < 300 && r.bodyBytes.isNotEmpty) {
      final key = path.startsWith('/') ? path.substring(1).replaceAll('/', '_') : path;
      // Disk: originálne bajty (bez rewrite), rewrite len pri servírovaní.
      unawaited(_radarWarmWrite(key, r.bodyBytes, ct ?? 'application/octet-stream'));
    }
  } catch (_) {
    response.statusCode = HttpStatus.badGateway;
  } finally {
    await response.close();
  }
}

/// Lokálny HTTP proxy: WebView berie Mapbox/geojson z diskovej cache (nie z Dart http).
Future<void> ensureRadarWarmProxyStarted() {
  final existing = _radarWarmStartFuture;
  if (existing != null) return existing;
  _radarWarmStartFuture = () async {
    if (_radarWarmServer != null) return;
    try {
      await _radarWarmDirectory();
      // Prednačítaj diskové assety do RAM pred prvým requestom.
      await Future.wait([
        _radarWarmReadDisk('mapbox-gl.js'),
        _radarWarmReadDisk('mapbox-gl.css'),
        _radarWarmReadDisk('radar_slovakia.geojson'),
        _radarWarmReadDisk('radar_romania.geojson'),
        _radarWarmReadDisk('radar_radar_history_cmax.json'),
      ]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _radarWarmServer = server;
      _radarWarmPort = server.port;
      server.listen(
        (request) {
          unawaited(_radarWarmHandleRequest(request));
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      _radarWarmServer = null;
      _radarWarmPort = null;
      _radarWarmStartFuture = null;
    }
  }();
  return _radarWarmStartFuture!;
}

/// Epoch náhľadu — Flutter karta sa rebuildne hneď po načítaní CMAX snímky.
final ValueNotifier<int> radarFastPreviewEpoch = ValueNotifier<int>(0);
ui.Image? _radarFastPreviewImage;
String? _radarFastPreviewFrameUrl;
Future<ui.Image?>? _radarFastPreviewInflight;

bool get radarFastPreviewAvailable => _radarFastPreviewImage != null;

ui.Image? peekRadarFastPreviewImage() => _radarFastPreviewImage;

Future<ui.Image?> _decodeRadarPreviewImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Posledný CMAX frame z histórie — disk cache + dekód do [radarFastPreviewEpoch].
/// Toto je rýchla cesta domovskej karty (bez Mapbox WebView).
Future<ui.Image?> ensureRadarFastPreviewFrame() {
  final existing = _radarFastPreviewImage;
  if (existing != null) return Future<ui.Image?>.value(existing);
  final inflight = _radarFastPreviewInflight;
  if (inflight != null) return inflight;

  _radarFastPreviewInflight = () async {
    try {
      await ensureRadarWarmProxyStarted();
      final hist = await _radarWarmGetOrFetch(
        'radar_radar_history_cmax.json',
        kMeteoRadarHistoryCmaxUrl,
        contentTypeHint: 'application/json',
      );
      if (hist == null) return _radarFastPreviewImage;
      final data = jsonDecode(utf8.decode(hist.bytes));
      if (data is! List || data.isEmpty) return _radarFastPreviewImage;
      final lastFrame = data.last;
      if (lastFrame is! Map || lastFrame['url'] is! String) {
        return _radarFastPreviewImage;
      }
      var frameUrl = lastFrame['url'] as String;
      if (frameUrl.startsWith('/')) {
        frameUrl = '$kMeteoRadarHelkorOrigin$frameUrl';
      }
      if (_radarFastPreviewImage != null &&
          _radarFastPreviewFrameUrl == frameUrl) {
        return _radarFastPreviewImage;
      }
      final key =
          'radar_frame_${frameUrl.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
      final asset = await _radarWarmGetOrFetch(
        key,
        frameUrl,
        contentTypeHint: 'image/png',
      );
      if (asset == null || asset.bytes.isEmpty) return _radarFastPreviewImage;
      final image = await _decodeRadarPreviewImage(
        Uint8List.fromList(asset.bytes),
      );
      final old = _radarFastPreviewImage;
      _radarFastPreviewImage = image;
      _radarFastPreviewFrameUrl = frameUrl;
      old?.dispose();
      radarFastPreviewEpoch.value = radarFastPreviewEpoch.value + 1;
      return image;
    } catch (_) {
      return _radarFastPreviewImage;
    } finally {
      _radarFastPreviewInflight = null;
    }
  }();
  return _radarFastPreviewInflight!;
}

/// Domovský náhľad radaru bez WebView — CMAX PNG v Mapbox mercator projekcii.
class RadarHomeFastPreview extends StatelessWidget {
  const RadarHomeFastPreview({
    super.key,
    required this.lat,
    required this.lon,
    this.showLocationDot = true,
  });

  final double lat;
  final double lon;
  final bool showLocationDot;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: radarFastPreviewEpoch,
      builder: (context, _, __) {
        final image = _radarFastPreviewImage;
        return CustomPaint(
          painter: _RadarFastPreviewPainter(
            image: image,
            lat: lat,
            lon: lon,
            showLocationDot: showLocationDot,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _RadarFastPreviewPainter extends CustomPainter {
  _RadarFastPreviewPainter({
    required this.image,
    required this.lat,
    required this.lon,
    required this.showLocationDot,
  });

  final ui.Image? image;
  final double lat;
  final double lon;
  final bool showLocationDot;

  static const double _tileSize = 512;

  double _projectX(double longitude, double world) =>
      ((longitude + 180.0) / 360.0) * world;

  double _projectY(double latitude, double world) {
    final s = math.sin(latitude * math.pi / 180.0);
    final y = 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    return y * world;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = kAmbientBlendColor,
    );
    final img = image;
    if (img == null || size.width <= 0 || size.height <= 0) return;

    final world = _tileSize * math.pow(2.0, kMeteoRadarCityZoom).toDouble();
    final cx = _projectX(lon, world);
    final cy = _projectY(lat, world);
    final x0 = _projectX(kRadarExtentLonMin, world);
    final x1 = _projectX(kRadarExtentLonMax, world);
    final y0 = _projectY(kRadarExtentLatMax, world);
    final y1 = _projectY(kRadarExtentLatMin, world);

    final left = x0 - (cx - size.width / 2);
    final top = y0 - (cy - size.height / 2);
    final dest = Rect.fromLTWH(left, top, x1 - x0, y1 - y0);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dest,
      Paint()..filterQuality = FilterQuality.medium,
    );

    if (!showLocationDot) return;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(
      center,
      7,
      Paint()..color = const Color(0x6622A6F2),
    );
    canvas.drawCircle(
      center,
      4.2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(center, 2.6, Paint()..color = const Color(0xFF22A6F2));
  }

  @override
  bool shouldRepaint(covariant _RadarFastPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.lat != lat ||
        oldDelegate.lon != lon ||
        oldDelegate.showLocationDot != showLocationDot;
  }
}

/// HTTP prefetch radaru (geojson / história / Mapbox) — DNS+TCP ešte pred WebView.
/// Kľúčové: [ensureRadarFastPreviewFrame] — Flutter náhľad bez Mapboxu.
/// WebView ide priamo na Helkor (proxy lámal Mapbox dlaždice).
Future<void> prefetchRadarMapAssets([GeoCity? city]) async {
  final last = _radarPrefetchLastRun;
  if (last != null && DateTime.now().difference(last) < const Duration(seconds: 45)) {
    // Aj pri debounce hneď ťahaj frame náhľadu (môže byť ešte null).
    unawaited(ensureRadarFastPreviewFrame());
    return;
  }
  _radarPrefetchLastRun = DateTime.now();

  unawaited(() async {
    try {
      await ensureRadarWarmProxyStarted();
    } catch (_) {}

    // Najprv frame náhľadu — to je to, čo user vidí do 1 s.
    await ensureRadarFastPreviewFrame();

    await Future.wait([
      _radarWarmGetOrFetch(
        'mapbox-gl.js',
        kMeteoRadarMapboxGlJsUrl,
        contentTypeHint: 'application/javascript',
      ),
      _radarWarmGetOrFetch(
        'mapbox-gl.css',
        kMeteoRadarMapboxGlCssUrl,
        contentTypeHint: 'text/css',
      ),
      _radarWarmGetOrFetch(
        'radar_slovakia.geojson',
        kMeteoRadarSlovakiaGeoJsonUrl,
        contentTypeHint: 'application/geo+json',
      ),
      _radarWarmGetOrFetch(
        'radar_romania.geojson',
        kMeteoRadarRomaniaGeoJsonUrl,
        contentTypeHint: 'application/geo+json',
      ),
      _radarWarmGetOrFetch(
        'radar_radar_history_cmax.json',
        kMeteoRadarHistoryCmaxUrl,
        contentTypeHint: 'application/json',
      ),
    ]);

    final lat = city?.lat ?? 48.7;
    final lon = city?.lon ?? 19.5;
    try {
      await http
          .get(Uri.parse(
            '$kMeteoRadarHelkorOrigin/radar/?lat=$lat&lon=$lon&zoom=7&hideUI=true',
          ))
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }());
}

/// Meteo výstrahy SR (Helkor mapa okresov).
const String kMeteoVystrahyUrl = 'http://cz1.helkor.eu:41083/vystrahy.php';

/// GeoJSON hraníc okresov pre mapu výstrah (načíta vystrahy.php).
const String kMeteoVystrahyOkresyUrl = 'http://cz1.helkor.eu:41083/okresy-hq.json';

/// Rámec mapy výstrah SR (zhodný s vystrahy.php).
const double kVystrahyExtentLatMin = 47.73;
const double kVystrahyExtentLatMax = 49.61;
const double kVystrahyExtentLonMin = 16.83;
const double kVystrahyExtentLonMax = 22.58;

bool coordsWithinSlovakiaVystrahyExtent(double lat, double lon) =>
    lat >= kVystrahyExtentLatMin &&
    lat <= kVystrahyExtentLatMax &&
    lon >= kVystrahyExtentLonMin &&
    lon <= kVystrahyExtentLonMax;

/// Meteo výstrahy — len pre lokality na Slovensku.
bool cityEligibleForVystrahy(GeoCity city) {
  final cc = city.countryCode.toUpperCase().trim();
  if (cc.isNotEmpty && cc != 'SK') return false;
  return coordsWithinSlovakiaVystrahyExtent(city.lat, city.lon);
}

/// Stupeň výstrahy (1–3) podľa Helkor mapy.
Color vystrahyLevelAccentColor(int level) {
  return switch (level) {
    1 => const Color(0xFFFACC15),
    2 => const Color(0xFFF97316),
    3 => const Color(0xFFEF4444),
    _ => const Color(0xFF42A5F5),
  };
}

Color vystrahyRankAccentColor(int rank) => vystrahyLevelAccentColor(rank);

/// Rovnaké ikony ako `javy` v `vystrahy.php` (Font Awesome 6).
class VystrahyJavDef {
  const VystrahyJavDef(this.id, this.icon);
  final String id;
  final FaIconData icon;
}

const List<VystrahyJavDef> kVystrahyJavy = [
  VystrahyJavDef('Búrka', FontAwesomeIcons.cloudBolt),
  VystrahyJavDef('Dážď', FontAwesomeIcons.cloudShowersHeavy),
  VystrahyJavDef('Vietor', FontAwesomeIcons.wind),
  VystrahyJavDef('Poľadovica', FontAwesomeIcons.icicles),
  VystrahyJavDef('Vysoká teplota', FontAwesomeIcons.temperatureHigh),
  VystrahyJavDef('Nízka teplota', FontAwesomeIcons.temperatureLow),
  VystrahyJavDef('Hmla', FontAwesomeIcons.smog),
  VystrahyJavDef('Snehové jazyky', FontAwesomeIcons.snowflake),
];

String? resolveVystrahyJavId(String jav) {
  final raw = jav.trim();
  if (raw.isEmpty) return null;
  for (final def in kVystrahyJavy) {
    if (def.id == raw) return def.id;
  }
  final lower = _normalizeVystrahyJavKey(raw);
  for (final def in kVystrahyJavy) {
    final idLower = _normalizeVystrahyJavKey(def.id);
    if (lower == idLower) return def.id;
    if (lower.startsWith(idLower) || idLower.startsWith(lower)) {
      return def.id;
    }
  }
  if (lower.contains('burk') || lower.contains('búrk')) return 'Búrka';
  if (lower.contains('daz') || lower.contains('dáž')) return 'Dážď';
  if (lower.contains('vietor')) return 'Vietor';
  if (lower.contains('polad') || lower.contains('poľad')) return 'Poľadovica';
  if (lower.contains('vysoka') && lower.contains('teplota')) {
    return 'Vysoká teplota';
  }
  if (lower.contains('nizka') && lower.contains('teplota')) {
    return 'Nízka teplota';
  }
  if (lower.contains('hmla')) return 'Hmla';
  if (lower.contains('sneh')) return 'Snehové jazyky';
  return null;
}

String _normalizeVystrahyJavKey(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('č', 'c')
      .replaceAll('ď', 'd')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ĺ', 'l')
      .replaceAll('ľ', 'l')
      .replaceAll('ň', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ŕ', 'r')
      .replaceAll('š', 's')
      .replaceAll('ť', 't')
      .replaceAll('ú', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ž', 'z');
}

FaIconData vystrahyJavIconForId(String? javId) {
  if (javId == null || javId.isEmpty) {
    return FontAwesomeIcons.triangleExclamation;
  }
  for (final def in kVystrahyJavy) {
    if (def.id == javId) return def.icon;
  }
  return vystrahyJavIcon(javId);
}

FaIconData vystrahyJavIcon(String jav) {
  final id = resolveVystrahyJavId(jav);
  if (id != null) {
    for (final def in kVystrahyJavy) {
      if (def.id == id) return def.icon;
    }
  }
  return FontAwesomeIcons.triangleExclamation;
}

DateTime? parseVystrahySkDateTime(String raw) {
  final cleaned = raw.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final m = RegExp(
    r'^(\d{1,2})\s*\.\s*(\d{1,2})\s*\.\s*(\d{4})\s*(\d{1,2})\s*:\s*(\d{1,2})',
  ).firstMatch(cleaned);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
  );
}

String _formatVystrahyRelativeDurationSk(Duration diff) {
  if (diff.isNegative) diff = Duration.zero;
  final totalMinutes = diff.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return 'o $hours h $minutes min';
  if (hours > 0) return 'o $hours h';
  if (minutes > 0) return 'o $minutes min';
  return 'o chvíľu';
}

String _formatVystrahyClock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

String _formatVystrahyDayWord(DateTime now, DateTime at) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final dayDiff = day.difference(today).inDays;
  return switch (dayDiff) {
    0 => 'dnes',
    1 => 'zajtra',
    2 => 'pozajtra',
    _ => '${at.day}.${at.month}.',
  };
}

String _formatVystrahyDayTime(DateTime now, DateTime at) =>
    '${_formatVystrahyDayWord(now, at)} ${_formatVystrahyClock(at)}';

/// Jedna info-riadok: kedy výstraha začína a kedy končí.
String formatVystrahyTimingLine({
  required DateTime now,
  DateTime? startAt,
  DateTime? endAt,
  required bool isActiveNow,
}) {
  String? rangeLabel() {
    if (startAt == null && endAt == null) return null;
    if (startAt != null && endAt != null) {
      final startLabel = _formatVystrahyDayTime(now, startAt);
      final sameDay = startAt.year == endAt.year &&
          startAt.month == endAt.month &&
          startAt.day == endAt.day;
      if (sameDay) {
        return 'Od $startLabel do ${_formatVystrahyClock(endAt)}';
      }
      return 'Od $startLabel do ${_formatVystrahyDayTime(now, endAt)}';
    }
    if (startAt != null) {
      return 'Od ${_formatVystrahyDayTime(now, startAt)}';
    }
    return 'Do ${_formatVystrahyDayTime(now, endAt!)}';
  }

  if (isActiveNow) {
    final range = rangeLabel();
    if (range != null) return range;
    return 'Práve platí vo vašom okrese';
  }

  if (startAt == null) {
    if (endAt != null) return 'Do ${_formatVystrahyDayTime(now, endAt)}';
    return '';
  }

  final startLabel = _formatVystrahyDayTime(now, startAt);
  final rel = _formatVystrahyRelativeDurationSk(startAt.difference(now));
  final range = rangeLabel();
  if (range != null) return '$range ($rel)';
  return 'Začína $startLabel ($rel)';
}

class VystrahyWarningItem {
  const VystrahyWarningItem({
    required this.rank,
    required this.jav,
    this.javId,
    this.startAt,
    this.endAt,
    this.isActiveNow = false,
  });

  final int rank;
  final String jav;
  final String? javId;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isActiveNow;

  bool get isValid => rank >= 1 && jav.isNotEmpty;

  /// Rovnaká logika ako JS na mape: bez `do` alebo po konci → nezobrazovať.
  bool isRelevantAt(DateTime now) {
    if (!isValid) return false;
    final end = endAt;
    if (end == null) return false;
    return end.isAfter(now);
  }

  bool isActiveAt(DateTime now) {
    if (!isRelevantAt(now)) return false;
    final start = startAt;
    if (start == null) return false;
    return !start.isAfter(now);
  }

  String levelLine(String okres) => '$rank. stupeň • okres $okres';

  /// Jedna výstraha: „Búrky · do dnes 23:59“ / „Dážď · od zajtra 08:00 do 18:00“.
  String scheduleLine(DateTime now) {
    final when = formatVystrahyTimingLine(
      now: now,
      startAt: startAt,
      endAt: endAt,
      isActiveNow: isActiveNow,
    );
    if (when.isEmpty) return '$jav · $rank. st.';
    return '$jav · $when';
  }

  String timingLine(DateTime now) => formatVystrahyTimingLine(
        now: now,
        startAt: startAt,
        endAt: endAt,
        isActiveNow: isActiveNow,
      );

  Color get accentColor => vystrahyLevelAccentColor(rank);

  FaIconData get icon => vystrahyJavIconForId(javId ?? resolveVystrahyJavId(jav));

  static VystrahyWarningItem? fromMap(Map<String, dynamic> map) {
    final rank = (map['rank'] as num?)?.toInt() ??
        (map['uroven'] as num?)?.toInt() ??
        0;
    final jav = (map['jav'] as String?)?.trim() ?? '';
    if (rank < 1 || jav.isEmpty) return null;
    final od = (map['od'] as String?)?.trim() ?? '';
    final doUntil = (map['do'] as String?)?.trim() ?? '';
    final javIdRaw = (map['javId'] as String?)?.trim();
    return VystrahyWarningItem(
      rank: rank,
      jav: jav,
      javId: javIdRaw?.isNotEmpty == true
          ? javIdRaw
          : resolveVystrahyJavId(jav),
      startAt: parseVystrahySkDateTime(od),
      endAt: parseVystrahySkDateTime(doUntil),
      isActiveNow: map['active'] == true,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VystrahyWarningItem &&
        other.rank == rank &&
        other.jav == jav &&
        other.javId == javId &&
        other.startAt == startAt &&
        other.endAt == endAt &&
        other.isActiveNow == isActiveNow;
  }

  @override
  int get hashCode => Object.hash(rank, jav, javId, startAt, endAt, isActiveNow);
}

class VystrahyActiveNotice {
  const VystrahyActiveNotice({
    required this.okres,
    required this.items,
  });

  final String okres;
  final List<VystrahyWarningItem> items;

  int get rank =>
      visibleItems.fold(0, (max, item) => item.rank > max ? item.rank : max);

  bool get shouldShow => shouldShowAt(DateTime.now());

  bool shouldShowAt(DateTime now) =>
      okres.isNotEmpty && visibleItemsAt(now).isNotEmpty;

  List<VystrahyWarningItem> get visibleItems =>
      visibleItemsAt(DateTime.now());

  List<VystrahyWarningItem> visibleItemsAt(DateTime now) => items
      .where((item) => item.isRelevantAt(now))
      .toList(growable: false);

  /// Odstráni uplynuté položky; `null` ak nič neostalo.
  VystrahyActiveNotice? prunedAt(DateTime now) {
    final kept = <VystrahyWarningItem>[];
    for (final item in items) {
      if (!item.isRelevantAt(now)) continue;
      kept.add(
        VystrahyWarningItem(
          rank: item.rank,
          jav: item.jav,
          javId: item.javId,
          startAt: item.startAt,
          endAt: item.endAt,
          isActiveNow: item.isActiveAt(now),
        ),
      );
    }
    if (okres.isEmpty || kept.isEmpty) return null;
    return VystrahyActiveNotice(okres: okres, items: kept);
  }

  Color get accentColor => vystrahyLevelAccentColor(rank);

  FaIconData get icon => visibleItems.isNotEmpty
      ? visibleItems.first.icon
      : FontAwesomeIcons.triangleExclamation;

  VystrahyWarningItem? get primaryItem {
    final list = visibleItems;
    if (list.isEmpty) return null;
    final sorted = [...list]..sort((a, b) {
        if (a.isActiveNow != b.isActiveNow) {
          return a.isActiveNow ? -1 : 1;
        }
        if (b.rank != a.rank) return b.rank.compareTo(a.rank);
        final aStart = a.startAt;
        final bStart = b.startAt;
        if (aStart == null) return 1;
        if (bStart == null) return -1;
        return aStart.compareTo(bStart);
      });
    return sorted.first;
  }

  String countTitleSk() {
    final n = visibleItems.length;
    return switch (n) {
      1 => visibleItems.first.jav,
      2 || 3 || 4 => '$n výstrahy',
      _ => '$n výstrah',
    };
  }

  String multiLevelOkresLine() {
    // Bez „až“ — pri 1. stupni pôsobí divne; pri viacerých stačí najvyšší stupeň.
    if (rank <= 1) return '1. stupeň • okres $okres';
    return 'najvyšší $rank. stupeň • okres $okres';
  }

  String multiTypesLine() {
    return visibleItems
        .map((item) => '${item.jav} (${item.rank}. st.)')
        .join(' · ');
  }

  /// Prehľadný zoznam: každý jav na vlastnom riadku s od–do.
  String multiScheduleLines(DateTime now) {
    final list = [...visibleItems]..sort((a, b) {
        if (a.isActiveNow != b.isActiveNow) {
          return a.isActiveNow ? -1 : 1;
        }
        if (b.rank != a.rank) return b.rank.compareTo(a.rank);
        final aStart = a.startAt;
        final bStart = b.startAt;
        if (aStart == null && bStart == null) return 0;
        if (aStart == null) return 1;
        if (bStart == null) return -1;
        return aStart.compareTo(bStart);
      });
    return list.map((item) => item.scheduleLine(now)).join('\n');
  }

  String multiTimingSummary(DateTime now) => multiScheduleLines(now);

  static VystrahyActiveNotice? fromJsJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == 'null' || trimmed == '""') return null;
    try {
      final decoded = json.decode(trimmed);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final okres = (map['okres'] as String?)?.trim() ?? '';
      if (okres.isEmpty) return null;

      final rawItems = map['items'];
      if (rawItems is List) {
        final items = rawItems
            .whereType<Map>()
            .map((e) => VystrahyWarningItem.fromMap(Map<String, dynamic>.from(e)))
            .whereType<VystrahyWarningItem>()
            .toList(growable: false);
        if (items.isEmpty) return null;
        return VystrahyActiveNotice(okres: okres, items: items)
            .prunedAt(DateTime.now());
      }

      final legacy = VystrahyWarningItem.fromMap(map);
      if (legacy == null) return null;
      return VystrahyActiveNotice(okres: okres, items: [legacy])
          .prunedAt(DateTime.now());
    } catch (_) {
      return null;
    }
  }

  /// Banner / widget z HTTP `vystrahy.json` (bez WebView).
  static VystrahyActiveNotice? fromWidgetSnapshot(
    VystrahyWidgetSnapshot snap, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    if (snap.okres.isEmpty || !snap.hasWarning) return null;
    final items = snap.items
        .map(
          (i) => VystrahyWarningItem(
            rank: i.rank,
            jav: i.jav,
            javId: resolveVystrahyJavId(i.jav),
            startAt: i.od,
            endAt: i.doUntil,
            isActiveNow: i.isActiveNow,
          ),
        )
        .toList(growable: false);
    return VystrahyActiveNotice(okres: snap.okres, items: items).prunedAt(at);
  }

  @override
  bool operator ==(Object other) {
    if (other is! VystrahyActiveNotice) return false;
    if (other.okres != okres || other.items.length != items.length) {
      return false;
    }
    for (var i = 0; i < items.length; i++) {
      if (items[i] != other.items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(okres, Object.hashAll(items));
}

Future<void> syncVystrahyHomeWidgetFromNotice(
  VystrahyActiveNotice? notice, {
  String? fallbackOkres,
  bool showMapHint = true,
}) async {
  try {
    if (notice == null || !notice.shouldShow) {
      await VystrahyHomeWidget.clear(
        okres: fallbackOkres ?? '',
        showMapHint: showMapHint,
      );
      return;
    }
    final primary = notice.primaryItem;
    final now = DateTime.now();
    final single = notice.visibleItems.length == 1;
    await VystrahyHomeWidget.update(
      hasWarning: true,
      title: single ? notice.visibleItems.first.jav : notice.countTitleSk(),
      levelLine: single
          ? notice.visibleItems.first.levelLine(notice.okres)
          : notice.multiLevelOkresLine(),
      // Viac výstrah: každý jav + od–do na vlastnom riadku (nie „2 platí · 1 nadchádza“).
      typesLine: single ? '' : notice.multiScheduleLines(now),
      timing: single ? notice.visibleItems.first.timingLine(now) : '',
      okres: notice.okres,
      rank: notice.rank,
      javId: primary?.javId ?? primary?.jav ?? '',
    );
  } catch (e) {
    debugPrint('syncVystrahyHomeWidgetFromNotice: $e');
  }
}

String buildVystrahyUserLocationMarkerJs(double lat, double lon) => '''
(function() {
  var lat = $lat;
  var lon = $lon;
  if (!window.L) return;
  window.__pocasieUserLat = lat;
  window.__pocasieUserLon = lon;
  window.__pocasieVystrahyRank = 0;
  window.__pocasieVystrahyNotice = null;

  function hookMapCapture() {
    if (!L.Map || window.__pocasieMapProtoHooked) return;
    window.__pocasieMapProtoHooked = true;
    ['invalidateSize', 'fitBounds', 'setView', 'panTo', 'flyTo'].forEach(function(method) {
      var orig = L.Map.prototype[method];
      if (typeof orig !== 'function') return;
      L.Map.prototype[method] = function() {
        window.__pocasieLeafletMap = this;
        return orig.apply(this, arguments);
      };
    });
  }

  function findLeafletMap() {
    if (window.__pocasieLeafletMap && window.__pocasieLeafletMap.invalidateSize) {
      return window.__pocasieLeafletMap;
    }
    hookMapCapture();
    var mapEl = document.getElementById('map');
    if (mapEl) {
      try {
        if (mapEl._leaflet && mapEl._leaflet.invalidateSize) return mapEl._leaflet;
        var keys = Object.keys(mapEl);
        for (var i = 0; i < keys.length; i++) {
          var v = mapEl[keys[i]];
          if (v && v.invalidateSize && v.latLngToLayerPoint) {
            window.__pocasieLeafletMap = v;
            return v;
          }
        }
      } catch (e) {}
    }
    try {
      if (window.__pocasieLeafletMap && window.__pocasieLeafletMap.invalidateSize) {
        return window.__pocasieLeafletMap;
      }
    } catch (e2) {}
    return null;
  }

  function placePin(attempt) {
    var lm = findLeafletMap();
    if (!lm) {
      if (attempt < 12) setTimeout(function() { placePin(attempt + 1); }, 160);
      return;
    }

    if (window.__pocasieUserLocLayers) {
      window.__pocasieUserLocLayers.forEach(function(layer) {
        try { lm.removeLayer(layer); } catch (e3) {}
      });
    }
    window.__pocasieUserLocLayers = [];

    // Farba = stupeň výstrahy; bez výstrahy svetlá modrá z palety (nie tmavá).
    var palette = {
      '1': '#42A5F5',
      '2': '#FFD600',
      '3': '#FF6D00',
      '4': '#E53935'
    };
    var pinColor = palette['1'];
    var bestRank = 0;
    var bestNotice = null;
    try {
      var pt = L.latLng(lat, lon);
      var allowed = {};
      Object.keys(palette).forEach(function(k) { allowed[palette[k].toLowerCase()] = palette[k]; });
      allowed['#1565c0'] = palette['1'];
      var rankOf = {};
      Object.keys(palette).forEach(function(k) { rankOf[palette[k].toLowerCase()] = parseInt(k, 10); });
      var okresId = null;
      lm.eachLayer(function(layer) {
        if (!layer || typeof layer.eachLayer !== 'function') return;
        layer.eachLayer(function(sub) {
          try {
            if (!sub.feature || !sub.getBounds || !sub.getBounds().contains(pt)) return;
            if (sub.feature._bezpecneId) okresId = sub.feature._bezpecneId;
            var c = sub.options && sub.options.fillColor;
            if (!c) return;
            var key = String(c).toLowerCase();
            var hit = allowed[key];
            var rank = rankOf[key] || 0;
            if (hit && rank >= bestRank) {
              bestRank = rank;
              pinColor = hit;
            }
          } catch (e4) {}
        });
      });

      function parseOd(s) {
        if (typeof parseSKDate === 'function') return parseSKDate(s);
        if (!s) return null;
        var c = String(s).replace(/,/g, ' ').replace(/\\s+/g, ' ').trim();
        var m = c.match(/^(\\d{1,2})\\s*\\.\\s*(\\d{1,2})\\s*\\.\\s*(\\d{4})\\s*(\\d{1,2})\\s*:\\s*(\\d{1,2})/);
        return m ? new Date(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10), parseInt(m[4], 10), parseInt(m[5], 10)) : null;
      }

      function resolveJavId(jav) {
        var raw = String(jav || '').trim();
        if (!raw) return '';
        if (typeof javy !== 'undefined' && Array.isArray(javy)) {
          for (var j = 0; j < javy.length; j++) {
            if (javy[j].id === raw) return javy[j].id;
          }
          var lower = raw.toLowerCase();
          for (var k = 0; k < javy.length; k++) {
            var id = String(javy[k].id || '');
            var idLower = id.toLowerCase();
            if (lower === idLower || lower.indexOf(idLower) === 0 || idLower.indexOf(lower) === 0) {
              return javy[k].id;
            }
          }
        }
        return raw;
      }

      if (okresId && typeof dbase !== 'undefined' && Array.isArray(dbase[okresId])) {
        var now = new Date();
        var notices = [];
        dbase[okresId].forEach(function(i) {
          if (!i) return;
          var od = parseOd(i.od);
          var do_ = parseOd(i.do);
          if (!do_ || do_ <= now) return;
          var u = parseInt(i.uroven, 10) || 0;
          if (u < 1) return;
          var active = od && od <= now;
          if (u > bestRank) bestRank = u;
          notices.push({
            jav: i.jav || '',
            javId: resolveJavId(i.jav),
            uroven: u,
            rank: u,
            od: i.od || '',
            do: i.do || '',
            active: active
          });
        });
        notices.sort(function(a, b) {
          if (a.active !== b.active) return a.active ? -1 : 1;
          if (b.uroven !== a.uroven) return b.uroven - a.uroven;
          var aod = parseOd(a.od) || new Date(8640000000000000);
          var bod = parseOd(b.od) || new Date(8640000000000000);
          return aod - bod;
        });
        if (notices.length > 0) {
          bestNotice = {
            okres: okresId,
            rank: bestRank,
            items: notices
          };
        }
      }
    } catch (e5) {}
    window.__pocasieVystrahyRank = bestRank;
    window.__pocasieVystrahyNotice = bestNotice;

    var styleEl = document.getElementById('pocasie-user-pin-style');
    if (styleEl) styleEl.remove();
    var st = document.createElement('style');
    st.id = 'pocasie-user-pin-style';
    // Špička pinu = geografický bod (iconAnchor na tip). Bez prázdneho miesta pod špičkou.
    st.textContent = ''
      + '.pocasie-user-pin{background:transparent!important;border:0!important;}'
      + '.pocasie-user-pin .leaflet-marker-shadow{display:none!important;}'
      + '.pocasie-user-pin-inner{position:relative;width:24px;height:24px;}'
      + '.pocasie-user-pin-head{position:absolute;left:50%;top:50%;width:16px;height:16px;'
      + 'margin:-8px 0 0 -8px;border-radius:50% 50% 50% 0;background:' + pinColor + ';'
      + 'transform:rotate(-45deg);border:2px solid #ffffff;box-sizing:border-box;'
      + 'box-shadow:0 1px 4px rgba(0,0,0,.4)!important;}'
      + '.pocasie-user-pin-head:after{content:"";position:absolute;left:50%;top:50%;'
      + 'width:5px;height:5px;margin:-2.5px 0 0 -2.5px;border-radius:50%;'
      + 'background:#ffffff;transform:rotate(45deg);box-shadow:none!important;}';
    document.head.appendChild(st);

    // Tip ~8*sqrt(2)≈11.3px pod stredom → tip y≈22.
    var icon = L.divIcon({
      className: 'pocasie-user-pin',
      html: '<div class="pocasie-user-pin-inner"><div class="pocasie-user-pin-head"></div></div>',
      iconSize: [24, 24],
      iconAnchor: [12, 22],
      popupAnchor: [0, -20]
    });

    var pin = L.marker([lat, lon], {
      icon: icon,
      interactive: false,
      keyboard: false,
      zIndexOffset: 1200,
      shadowUrl: null,
      shadowPane: null
    }).addTo(lm);

    window.__pocasieUserLocLayers = [pin];
    try { pin.setZIndexOffset(1200); } catch (e6) {}
    // Bez setView / flyTo — mapa ostáva na celom SR.
  }

  placePin(0);
})();
''';

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

/// ISO kód pre radar — WeatherAPI GPS často vráti prázdny countryCode.
String effectiveRadarCountryCode(GeoCity city) {
  final cc = city.countryCode.trim().toUpperCase();
  if (cc.isNotEmpty) return cc;
  return weatherApiCountryCodeFromName(city.country);
}

/// SHMÚ/Helkor radar mapa v UI — open-data štáty v rámci kompozitu (0–30°E, 43–58°N).
/// Pri chýbajúcom ISO (čerstvá GPS po onboardingu) stačí extent + názov krajiny / SK bbox.
bool radarCoverageForCity(GeoCity city) {
  if (!coordsWithinRadarMapExtent(city.lat, city.lon)) return false;
  final cc = effectiveRadarCountryCode(city);
  if (cc.isNotEmpty) return cityEligibleForRadarNowcast(cc);
  // Prázdny kód aj názov (starý cache) — na SK extent ukáž radar.
  return coordsWithinSlovakiaVystrahyExtent(city.lat, city.lon);
}

/// RainViewer API nowcast — globálne pokrytie (nezávisle od Helkor mapy).
bool rainViewerNowcastForCity(GeoCity city) =>
    false;

/// Zrážkový nowcast + ECMWF sync — RainViewer kdekoľvek, Helkor fallback len v [radarCoverageForCity].
bool radarNowcastActiveForCity(GeoCity city) => false;

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

/// Nad touto teplotou vzduchu sa snehová ikona zobrazí ako dážď (4 °C ≠ sneženie).
const double kSnowMaxAirTempC = 0.0;

bool airTempAllowsSnow(double? tempC) =>
    tempC == null || tempC <= kSnowMaxAirTempC;

/// Snehové / mrznúce WMO → ekvivalentný dážď, keď je vzduch nad bodom mrazu.
int wmoPrecipIconForAirTemp(int code, double? tempC) {
  if (airTempAllowsSnow(tempC)) return code;
  final n = normalizeDisplayWeatherCode(code);
  return switch (n) {
    56 => 51,
    57 => 53,
    66 => 61,
    67 => 63,
    71 || 77 || 85 => 61,
    73 => 63,
    // Silný sneh → mierny dážď (nie rain.svg / 65).
    75 || 86 => 63,
    _ => code,
  };
}

/// Radar nikdy nezobrazí silný dážď (`rain.svg` / 65) ani silný sneh (`snow.svg` / 75).
int capRadarPrecipIconNoHeavy(int code) {
  final c = normalizeDisplayWeatherCode(code);
  return switch (c) {
    65 => 63,
    82 => 81,
    67 => 66,
    75 => 73,
    86 => 85,
    57 => 56,
    _ => c,
  };
}

/// 24 h pás — silný dážď (`rain.svg` / 65) od **5 mm/h**; sneh (`snow.svg` / 75) od **5 cm/h**.
///
/// | intenzita | dážď (mm/h) | sneh (cm/h) | WMO |
/// |-----------|-------------|-------------|-----|
/// | silný     | ≥ 5         | ≥ 5         | 65 / 75 |
/// | mierny    | ≥ 2         | ≥ 2         | 63 / 73 |
/// | slabý     | ≥ 0,5       | ≥ 0,5       | 61 / 71 |
/// | stopa     | ≥ 0,1       | ≥ 0,1       | 51 / 71 |
///
/// [allowHeavy]: `false` pre radar — max mierny (63 / 73).
int hourlyStripPrecipIntensityIcon({
  required int baseCode,
  required double precipMm,
  double? tempC,
  double snowfallCm = 0.0,
  bool allowHeavy = true,
}) {
  final normalized = normalizeDisplayWeatherCode(baseCode);
  if ({95, 96, 99}.contains(normalized)) return normalized;

  final wantsSnow = airTempAllowsSnow(tempC) &&
      (kSnowWeatherCodes.contains(normalized) ||
          snowfallCm >= 0.1 ||
          (tempC != null &&
              tempC <= kSnowMaxAirTempC &&
              precipMm >= kMeaningfulPrecipMmPerHour &&
              kPrecipitationCodes.contains(normalized)));

  if (wantsSnow) {
    // Bez hourly snowfall — mm kvapaliny ≈ cm snehu na intenzitu ikony.
    final cm = math.max(snowfallCm, precipMm);
    if (allowHeavy && cm >= _kHeavySnowCmBlockSum) return 75;
    if (cm >= _kModerateSnowCmBlockSum) return 73;
    return 71;
  }

  final rainBase = wmoPrecipIconForAirTemp(normalized, tempC);
  if (allowHeavy && precipMm >= _kHeavyPrecipMmBlockSum) return 65;
  if (precipMm >= _kModeratePrecipMmBlockSum) return 63;
  if (precipMm >= 0.5) return 61;
  if (precipMm >= kMeaningfulPrecipMmPerHour) return 51;
  return rainBase;
}

/// WMO ikona z radarového dBZ — prahy podľa Marshall-Palmer legendy (25/40/50/55 dBZ).
/// Max mierny dážď/sneh — nikdy 65 / 75.
int wmoFromRadarDbz(double dbz, {required bool snow}) {
  if (snow) {
    if (dbz >= kRainViewerLegendModerateSnowDbz) return 73;
    if (dbz >= kRainViewerLegendLightSnowDbz) return 71;
    if (dbz >= kRainViewerLegendMinDbz) return 51;
    return 51;
  }
  if (dbz >= kRainViewerLegendModerateRainDbz) return 63;
  if (dbz >= kRainViewerLegendLightRainDbz) return 61;
  if (dbz >= kRainViewerLegendDrizzleDbz) return 53;
  if (dbz >= kRainViewerLegendMinDbz) return 51;
  return 51;
}

/// Sneh len pri ≤ 0 °C (a radar ≤ −2 °C); nad bodom mrazu vždy dážď.
bool radarSnowLikely({double? tempC, double snowfallCm = 0.0}) {
  if (tempC != null && tempC > kSnowMaxAirTempC) return false;
  if (snowfallCm >= 0.1) return true;
  return tempC != null && tempC <= -2.0;
}

/// Bez dostupného radarového nowcastu / mimo Helkor sledovača → Best Match.
WeatherForecastModel forecastModelForCity(
  GeoCity? city,
  WeatherForecastModel preferred,
) {
  if (city == null) return WeatherForecastModel.bestMatch;
  if (!radarNowcastActiveForCity(city)) {
    return WeatherForecastModel.bestMatch;
  }
  // Sledovač + radar hybrid — stredná Európa; inde Open-Meteo Best Match.
  if (!radarCoverageForCity(city)) {
    return WeatherForecastModel.bestMatch;
  }
  return preferred;
}

/// Horný strop mm/h podľa radarovej ikony — Marshall-Palmer legenda.
double _radarMmCapForIcon(int icon, {bool rainViewerLegend = false}) {
  if (rainViewerLegend) {
    return switch (icon) {
      51 => 0.1,
      53 => 0.6,
      61 => 2.7,
      63 => 5.6,
      65 => 12.0,
      71 => 0.3,
      73 => 1.0,
      75 => 3.0,
      _ => 2.0,
    };
  }
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
  final raw = math.pow(z / 280.0, 1.0 / 1.5).toDouble();
  final icon = wmoFromRadarDbz(dbz, snow: false);
  final cap = _radarMmCapForIcon(icon);
  return raw.clamp(kMeaningfulPrecipMmPerHour, cap);
}

/// mm/h z radarového dBZ — RainViewer legenda vs. CMAX.
double effectiveRadarMmFromDbz(double dbz, RadarNowcastContext ctx) {
  if (ctx.fromRainViewer) {
    final mm = rainViewerMmFromDbz(dbz);
    if (mm <= 0) return 0;
    final icon = wmoFromRainViewerDbz(
      dbz,
      snow: rainViewerSnowLikely(uiDbz: dbz),
    );
    return mm.clamp(kMeaningfulPrecipMmPerHour, _radarMmCapForIcon(icon, rainViewerLegend: true));
  }
  return radarMmFromDbz(dbz);
}

/// % z radarového dBZ — RainViewer od 15 dBZ min. 50 %.
int effectiveRadarProbFromDbz(double dbz, RadarNowcastContext ctx) =>
    ctx.fromRainViewer
        ? rainViewerProbPercentFromDbz(dbz)
        : radarProbPercentFromDbz(dbz);

/// % z dBZ — zosúladené s [radarMmFromDbz], výstup po 10 %.
int radarProbPercentFromDbz(double dbz) {
  final mm = radarMmFromDbz(dbz);
  if (mm <= 0) return 0;
  if (mm >= 2.5) return 90;
  if (mm >= 1.5) return 80;
  if (mm >= 0.9) return 70;
  if (mm >= 0.45) return 60;
  return kMinPrecipProbPercent;
}

bool _hourShowsPrecipIcon(int iconCode) =>
    kPrecipitationCodes.contains(normalizeDisplayWeatherCode(iconCode));

double _ecmwfHourlyPrecipMm(HourlyForecast h, int idx) =>
    h.precipitation?[idx] ?? 0.0;

int _ecmwfHourlyPrecipProb(HourlyForecast h, int idx) =>
    h.precipitationProbability?[idx] ?? 0;

/// Reprezentatívne mm z % — stupne majú padať do rôznych rozmedzí (0-1 / 1-2 / 2-3).
double displayMmFromPrecipProbability(int prob) {
  if (prob >= 90) return 3.2;
  if (prob >= 80) return 2.2;
  if (prob >= 70) return 1.3;
  if (prob >= 60) return 0.7;
  if (prob >= 50) return 0.35;
  return kMeaningfulPrecipMmPerHour;
}

/// Finálne mm pre riadok 24 h — **presne z API / radaru**, bez mm vymyslených z %.
double resolveHourlyStripPrecipMm(
  HourlyForecast h,
  int idx, {
  double? radarPinMm,
  int? stripProb,
  bool wetDisplayIcon = false,
  int? displayIconCode,
}) {
  if (radarPinMm != null && radarPinMm > 0) return radarPinMm;
  return _ecmwfHourlyPrecipMm(h, idx);
}

/// `false` = hybrid len ak radar nie je k dispozícii.
/// Keď [useRadarOnlyNearTermPrecip] — 24 h pás / hero = výhradne radar + nowcast.
const bool kRadarOnlyPrecipTestMode = false;

/// Blízke hodiny: **nowcast do 5 h** má prioritu —
/// bez mokrej snímky/trajektórie na danú hodinu žiadna zrážková ikona.
bool useRadarOnlyNearTermPrecip(RadarNowcastContext ctx) =>
    ctx.eligible && ctx.latest != null;










/// Radar môže meniť ECMWF len v blízkom okne — nie na celý zvyšok 24 h (zajtrajšie poobede atď.).
const int _kRadarEcmwfTrimMaxHoursWhenDry = 5;
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


void applyOpenMeteoPrecipToHourlyStrip({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required List<int> stripIndices,
  required HourlyForecast h,
  List<bool>? tailTrimMask,
}) {
  for (var i = 0; i < displayIcons.length; i++) {
    final idx = stripIndices[i];
    final slot = openMeteoHourSlotUiFromApi(h: h, idx: idx);
    displayIcons[i] = slot.showRainPrecip
        ? hourlyStripPrecipIntensityIcon(
            baseCode: slot.displayIconCode,
            precipMm: slot.precipMm,
            tempC: h.temperature?[idx],
          )
        : slot.displayIconCode;
    showRainPrecip[i] = slot.showRainPrecip;
    storedProbs[i] = slot.displayProbPercent;
    precipMm[i] = slot.precipMm;
  }
}

/// Jediný vstup pre 24 h pás — Open-Meteo základ + **nowcast do 5 h**.
///
/// Pravidlá:
/// - Do 5 h: zrážková ikona len podľa nowcastu (snímky ~2 h, potom trajektória)
/// - Mimo 5 h: ostáva model
/// - Denné karty: radar sa nepoužíva (len tento pás + hero)
void applyUnifiedHourlyStripPrecip({
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
  applyOpenMeteoPrecipToHourlyStrip(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMm,
    stripIndices: stripIndices,
    h: h,
  );
  applyRadarPrecipEndToHourlyStrip(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMm,
    stripIndices: stripIndices,
    h: h,
    radarCtx: radarCtx,
    locTime: locTime,
    utcOffsetSeconds: utcOffsetSeconds,
    radarCoverageActive: radarCoverageActive,
  );
  // Po radare / OM — suchá ikona nikdy nemá ≥ 50 %.
  clampDryHourlyStripPrecipPercents(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    stripIndices: stripIndices,
    h: h,
  );
  // Búrka — v nowcast okne model neprebíja radar (len blesky).
  alignHourlyStripThunderWithProbability(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMm,
    stripIndices: stripIndices,
    h: h,
    utcOffsetSeconds: utcOffsetSeconds,
    radarCtx: radarCtx,
    locTime: locTime,
  );
  // Po zrážke 40→30→20; pred ďalšou zrážkou 20→30→40.
  applyHourlyStripPrecipPercentRamp(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMm,
    stripIndices: stripIndices,
    h: h,
    locTime: locTime,
    utcOffsetSeconds: utcOffsetSeconds,
    radarCtx: radarCtx,
  );
  // Finálna nowcast brána — model po thunder/ramp nesmie nechať falošnú ikonu.
  applyRadarPrecipEndToHourlyStrip(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMm,
    stripIndices: stripIndices,
    h: h,
    radarCtx: radarCtx,
    locTime: locTime,
    utcOffsetSeconds: utcOffsetSeconds,
    radarCoverageActive: radarCoverageActive,
  );
  diversifyRepetitiveDryStripPercents(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    stripIndices: stripIndices,
    h: h,
    rainHoursBeforeStrip: _openMeteoUiPrecipHoursBeforeStrip(
      h: h,
      firstStripDataIndex: stripIndices.isEmpty ? 0 : stripIndices.first,
    ),
    radarCtx: radarCtx,
    locTime: locTime,
  );
  diversifyRepetitiveWetStripPercents(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMm,
    stripIndices: stripIndices,
    h: h,
  );
  // Mokré mm — až po % (mm z % musia sedieť s rozmanitými percentami).
  diversifyRepetitiveWetStripMm(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMm,
    stripIndices: stripIndices,
    h: h,
  );
  // Po diversify — znova strop podľa hodín dopredu (vlna nesmie vrátiť 90 %).
  applyRadarHorizonPrecipProbCaps(
    storedProbs: storedProbs,
    showRainPrecip: showRainPrecip,
    displayIcons: displayIcons,
    stripIndices: stripIndices,
    h: h,
    locTime: locTime,
    utcOffsetSeconds: utcOffsetSeconds,
  );
  alignDryStripPercentsForMatchingIcons(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    stripIndices: stripIndices,
    h: h,
    rainHoursBeforeStrip: _openMeteoUiPrecipHoursBeforeStrip(
      h: h,
      firstStripDataIndex: stripIndices.isEmpty ? 0 : stripIndices.first,
    ),
  );
}

/// Po zrážkovej **ikone** (nie radar / holé mm): 40 → 30 → 20.
/// Pred ďalšou zrážkovou ikonou: 20 → 30 → 40.
void applyHourlyStripPrecipPercentRamp({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required List<int> stripIndices,
  required HourlyForecast h,
  required DateTime locTime,
  int? utcOffsetSeconds,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
  int? rainHoursBeforeStripOverride,
}) {
  // Len skutočná zrážková ikona v UI — nie mm bez ikony, nie radarový dozvuk.
  final wetIcon = List<bool>.generate(
    displayIcons.length,
    (i) => showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i]),
  );

  var rainBefore = rainHoursBeforeStripOverride ?? 0;
  if (rainHoursBeforeStripOverride == null && stripIndices.isNotEmpty) {
    rainBefore = _openMeteoUiPrecipHoursBeforeStrip(
      h: h,
      firstStripDataIndex: stripIndices.first,
    );
    // Hero/mapa: práve prší, pás začína od ďalšej hodiny → 1. suchý riadok = 40 %.
    final rainingNow = radarCtx.pinForecast.wetAtPinNow ||
        radarCtx.precipNow ||
        radarCtx.rainAtPinNow;
    if (rainingNow && rainBefore < 1) {
      rainBefore = 1;
    }
  }

  for (var i = 0; i < displayIcons.length; i++) {
    if (wetIcon[i]) {
      // ECMWF — % podľa API aj mm (50 / 60 / 70+), nie natvrdo 50.
      final apiIdx = stripIndices[i];
      final rawApi = h.precipitationProbability != null &&
              apiIdx < h.precipitationProbability!.length
          ? (h.precipitationProbability![apiIdx] ?? 0)
          : storedProbs[i];
      final cloud = h.cloudCover != null && apiIdx < h.cloudCover!.length
          ? h.cloudCover![apiIdx]
          : null;
      var wetPct = ecmwfWetHourDisplayProbPercent(
        rawApiProb: rawApi,
        precipMm: precipMm[i],
        weatherCode: h.weatherCode?[apiIdx],
        cloudCoverPercent: cloud,
      );
      // Radar matematika (šanca doraziť) môže % ešte zdvihnúť.
      final snap = radarCtx.pinForecast;
      final parsed = DateTime.tryParse(h.time[apiIdx]);
      if (parsed != null && radarCtx.eligible) {
        final localT = utcOffsetSeconds != null
            ? parsed.add(Duration(seconds: utcOffsetSeconds))
            : parsed;
        final slotHour = DateTime(
          localT.year,
          localT.month,
          localT.day,
          localT.hour,
        );
        if (snap.authorizesLocalHour(slotHour) ||
            snap.wetAtPinNow ||
            snap.approaching) {
          final hoursAhead = slotHour
              .difference(DateTime(
                locTime.year,
                locTime.month,
                locTime.day,
                locTime.hour,
              ))
              .inHours;
          final minsToSlot = slotHour.difference(locTime).inMinutes;
          final live = radarLivePinUi(radarCtx);
          final rainingNow = live.wetAtPin || snap.wetAtPinNow;
          final certainty = radarStripCertaintyPercent(
            rainingNow: rainingNow,
            approaching: snap.approaching,
            hoursAhead: hoursAhead,
            minsToSlotStart: minsToSlot,
            etaMinutes: snap.etaMinutes,
            endMinutes: snap.endMinutes,
            distanceKm: snap.distanceKmEstimate,
            approachChancePercent: snap.approachChancePercent,
            pinUiDbz: snap.uiDbz,
            motionSpeedKmH: snap.motionSpeedKmH,
          );
          wetPct = math.max(wetPct, certainty);
          // mm podľa snímky hodiny / modelu / % — nekópiruj flat 0.1.
          final radarMm = radarStripMmForHour(
            radarCtx: radarCtx,
            snap: snap,
            slotHour: slotHour,
            locTime: locTime,
            hoursAhead: hoursAhead,
          );
          final mm = resolveRadarAuthorizedStripMm(
            modelMm: precipMm[i],
            radarMm: radarMm,
            certaintyPercent: math.max(wetPct, certainty),
            hoursAhead: hoursAhead,
          );
          // Radar nesmie prepísať modelové mm rovnakou hodnotou na celý pás.
          if (precipMm[i] < kMeaningfulPrecipMmPerHour && mm > precipMm[i]) {
            precipMm[i] = mm;
            displayIcons[i] = capRadarPrecipIconNoHeavy(
              hourlyStripPrecipIntensityIcon(
                baseCode: displayIcons[i],
                precipMm: mm,
                tempC: h.temperature?[apiIdx],
                allowHeavy: false,
              ),
            );
          }
        }
      }
      storedProbs[i] = _roundPrecipProbabilityForDisplay(
        math.max(storedProbs[i], wetPct),
      );
      continue;
    }

    final since = _hoursSinceLastRainInStrip(
      i,
      wetIcon,
      rainHoursBeforeStrip: rainBefore,
    );
    final until = _hoursUntilNextRainInStrip(i, wetIcon);
    final decay = _postRainDecayPercent(since);
    final approach = _preRainApproachFloor(until);

    final idx = stripIndices[i];
    final cloud = h.cloudCover != null && idx < h.cloudCover!.length
        ? h.cloudCover![idx]
        : null;
    final apiProb = h.precipitationProbability != null &&
            idx < h.precipitationProbability!.length
        ? (h.precipitationProbability![idx] ?? 0)
        : 0;

    var radarApproach = 0;
    final snap = radarCtx.pinForecast;
    final parsed = DateTime.tryParse(h.time[idx]);
    if (parsed != null && radarCtx.eligible) {
      final localT = utcOffsetSeconds != null
          ? parsed.add(Duration(seconds: utcOffsetSeconds))
          : parsed;
      final slotHour = DateTime(
        localT.year,
        localT.month,
        localT.day,
        localT.hour,
      );
      final nowHour = DateTime(
        locTime.year,
        locTime.month,
        locTime.day,
        locTime.hour,
      );
      if (snap.authorizesLocalHour(slotHour)) {
        // Hodina v radarovom mokrom okne — suché % max 40.
        radarApproach = math.min(
          math.max(snap.approachChancePercent, 30),
          40,
        );
      } else if (snap.approaching && snap.etaMinutes != null) {
        // Rozmanitosť podľa vzdialenosti od ETA príchodu.
        final hoursFromNow = slotHour.difference(nowHour).inHours;
        final etaH = math.max(0, (snap.etaMinutes! / 60.0).round());
        if (hoursFromNow >= 0 && hoursFromNow <= 8) {
          final dist = (hoursFromNow - etaH).abs();
          if (dist <= 0) {
            radarApproach = 40;
          } else if (dist == 1) {
            radarApproach = 30;
          } else if (dist == 2) {
            radarApproach = 20;
          }
        }
      }
    }

    final skyFloor = hourlyStripSkyIconPercent(
      displayIcons[i],
      cloudCoverPercent: cloud,
    );

    // Suché hodiny: % z API (variácia), nie flat 30 z ikony zamračené.
    var pct = hourlyStripDryHourPercentFromApi(
      apiProbPercent: apiProb,
      radarApproachPercent: radarApproach,
      iconCode: displayIcons[i],
      cloudCoverPercent: cloud,
    );

    // Po daždi / pred dažďom — NIE na čistom jasne (0).
    // Hneď po zrážkovej ikone → vždy 40.
    if (!_isClearStripSkyCode(displayIcons[i])) {
      final justAfterRainIcon =
          (i > 0 && wetIcon[i - 1]) || (since != null && since == 1);
      if (justAfterRainIcon) {
        pct = 40;
      } else {
        if (decay > 0) pct = math.max(pct, decay);
        if (approach > 0) pct = math.max(pct, approach);
        final farFromRain = (until == null || until > 2) &&
            (since == null || since > 2);
        if (farFromRain) pct = math.min(pct, 30);
      }
    }

    if (!_hourShowsPrecipIcon(displayIcons[i]) && !showRainPrecip[i]) {
      storedProbs[i] = _dryStripPercentWithNearbyRainCap(
        pct: pct,
        hoursUntilRain: until,
        hoursSinceRain: since,
        radarApproachPercent: radarApproach,
        iconCode: displayIcons[i],
      );
    } else {
      storedProbs[i] = _roundPrecipProbabilityForDisplay(
        pct.clamp(skyFloor, 100),
      );
    }
  }
}

/// Koľko hodín pred pásom bola posledná Open-Meteo UI zrážka (ikona), 1–6.
int _openMeteoUiPrecipHoursBeforeStrip({
  required HourlyForecast h,
  required int firstStripDataIndex,
}) {
  if (firstStripDataIndex <= 0) return 0;
  for (var gap = 1; gap <= 6; gap++) {
    final prevIdx = firstStripDataIndex - gap;
    if (prevIdx < 0) return 0;
    final slot = openMeteoHourSlotUiFromApi(h: h, idx: prevIdx);
    if (slot.showRainPrecip || _hourShowsPrecipIcon(slot.displayIconCode)) {
      return gap;
    }
  }
  return 0;
}

/// Búrka (95/96/99): sila z mm rozmedzia → potom blesky / model.
/// V nowcast okne modelová búrka **neprebíja** radar — len skutočné blesky.
void alignHourlyStripThunderWithProbability({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required List<int> stripIndices,
  required HourlyForecast h,
  bool lightningNearby = false,
  int? lightningHourIndex,
  int? utcOffsetSeconds,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
  DateTime? locTime,
}) {
  final loc = locTime;
  final trimStop = loc != null && useRadarOnlyNearTermPrecip(radarCtx)
      ? radarCtx.nowcastStripGateEndExclusive(loc)
      : null;
  final nowHour = loc == null
      ? null
      : DateTime(loc.year, loc.month, loc.day, loc.hour);

  for (var i = 0; i < displayIcons.length; i++) {
    final idx = stripIndices[i];
    final apiCode = h.weatherCode != null && idx < h.weatherCode!.length
        ? h.weatherCode![idx]
        : null;
    final cloud = h.cloudCover != null && idx < h.cloudCover!.length
        ? h.cloudCover![idx]
        : null;
    final apiThunder = ecmwfJsonThunderHour(apiCode);
    final lightningHere = lightningNearby &&
        lightningHourIndex != null &&
        idx == lightningHourIndex;
    final mm = precipMm[i];
    final intensityOkForModel = precipIntensityAllowsThunder(mm);
    final intensityOkForLightning = precipIntensityAllowsThunder(
      mm,
      liveLightning: true,
    );
    final iconThunder = kThunderWeatherCodes.contains(
      normalizeDisplayWeatherCode(displayIcons[i]),
    );

    var inNowcastWindow = false;
    if (trimStop != null &&
        nowHour != null &&
        idx < h.time.length) {
      final parsed = DateTime.tryParse(h.time[idx]);
      if (parsed != null) {
        final localT = utcOffsetSeconds != null
            ? parsed.add(Duration(seconds: utcOffsetSeconds))
            : parsed;
        final slotHour = DateTime(
          localT.year,
          localT.month,
          localT.day,
          localT.hour,
        );
        inNowcastWindow =
            !slotHour.isBefore(nowHour) && slotHour.isBefore(trimStop);
      }
    }

    // 1) Živé blesky — len ak mm sila aspoň slabý dážď (inak to nie je búrka pri pine).
    if (lightningHere && intensityOkForLightning) {
      displayIcons[i] = thunderWmoForPrecipIntensity(
        mm,
        liveLightning: true,
        preferredApiThunderCode: apiThunder ? apiCode : null,
      );
      showRainPrecip[i] = true;
      storedProbs[i] = math.max(storedProbs[i], kMinPrecipProbPercent);
      continue;
    }

    // 2) Modelová búrka — až keď rozmedzie mm hovorí mierny+ dážď.
    if (apiThunder && intensityOkForModel) {
      if (inNowcastWindow && !lightningHere) {
        continue;
      }
      displayIcons[i] = thunderWmoForPrecipIntensity(
        mm,
        preferredApiThunderCode: apiCode,
      );
      showRainPrecip[i] = true;
      final apiProb = apiCode != null &&
              h.precipitationProbability != null &&
              idx < h.precipitationProbability!.length
          ? roundPrecipProbPercent(h.precipitationProbability![idx] ?? 0)
          : storedProbs[i];
      storedProbs[i] = math.max(
        math.max(storedProbs[i], apiProb),
        kMinPrecipProbPercent,
      );
      continue;
    }

    if (!iconThunder) continue;

    // Falošná búrková ikona (slabé mm) — ikona podľa sily zrážok.
    if (showRainPrecip[i] ||
        mm >= kMeaningfulPrecipMmPerHour ||
        storedProbs[i] >= kMinPrecipProbPercent) {
      final rainIcon = hourlyStripPrecipIntensityIcon(
        baseCode: 61,
        precipMm: mm,
        allowHeavy: !inNowcastWindow,
      );
      displayIcons[i] = inNowcastWindow
          ? capRadarPrecipIconNoHeavy(rainIcon)
          : rainIcon;
      showRainPrecip[i] = true;
      storedProbs[i] = math.max(storedProbs[i], kMinPrecipProbPercent);
    } else {
      displayIcons[i] = skyWmoFromCloudCover(cloud);
      showRainPrecip[i] = false;
      final apiProb = h.precipitationProbability != null &&
              idx < h.precipitationProbability!.length
          ? (h.precipitationProbability![idx] ?? 0)
          : 0;
      storedProbs[i] = hourlyStripDryHourPercentFromApi(
        apiProbPercent: apiProb,
        iconCode: displayIcons[i],
        cloudCoverPercent: cloud,
      );
      precipMm[i] = 0;
    }
  }
}

/// Kapsovanie hodín v pásme podľa denného maxima šance v danom kalendárnom dni.
///
/// Len pre **vzdialené** mokré hodiny. Near-term (0–6 h) radarová istota
/// (80–95 %) sa **nesmie** zabiť denným API maxom 50 %.
void applyHourlyStripHorizonProbCaps({
  required List<int> storedProbs,
  required List<int> stripIndices,
  required HourlyForecast h,
  required DateTime locTime,
  int? utcOffsetSeconds,
}) {
  if (h.time.isEmpty) return;
  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );
  final len = math.min(storedProbs.length, stripIndices.length);
  for (var i = 0; i < len; i++) {
    // Suché % podľa oblohy/radaru (20–40) — nesahej.
    if (storedProbs[i] < kMinPrecipProbPercent) continue;

    final idx = stripIndices[i];
    if (idx < 0 || idx >= h.time.length) continue;
    final t = DateTime.tryParse(h.time[idx]);
    if (t == null) continue;
    final localT = utcOffsetSeconds != null
        ? t.add(Duration(seconds: utcOffsetSeconds))
        : t;
    final slotHour = DateTime(
      localT.year,
      localT.month,
      localT.day,
      localT.hour,
    );
    final hoursAhead = slotHour.difference(nowHour).inHours;
    // Blízke hodiny: radar / nowcast istota má prioritu pred API dayMax.
    if (hoursAhead <= 6) continue;

    final dateStr = localT.toIso8601String().substring(0, 10);
    final dayMax = hourlyDayMaxPrecipProb(h, dateStr);
    if (dayMax <= 0) continue;
    if (storedProbs[i] > dayMax) {
      storedProbs[i] = _roundPrecipProbabilityForDisplay(dayMax);
    }
  }
  for (var i = 0; i < storedProbs.length; i++) {
    storedProbs[i] = _roundPrecipProbabilityForDisplay(storedProbs[i]);
  }
}

/// Po všetkých clampoch — suché % drž z API (variácia 10/20/30/40),
/// len doplň dozvuk / blízkosť dažďa. **Neflatni** na jedno číslo.
void reapplyDryCloudyStripPercents({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<int> stripIndices,
  required HourlyForecast h,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
  DateTime? locTime,
  int? utcOffsetSeconds,
}) {
  final now = locTime;
  final wetIcon = List<bool>.generate(
    displayIcons.length,
    (i) => showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i]),
  );

  var rainBefore = stripIndices.isEmpty
      ? 0
      : _openMeteoUiPrecipHoursBeforeStrip(
          h: h,
          firstStripDataIndex: stripIndices.first,
        );
  if (now != null &&
      radarCtx.eligible &&
      (radarCtx.precipNow ||
          radarCtx.rainAtPinNow ||
          radarCtx.pinForecast.wetAtPinNow) &&
      rainBefore < 1) {
    rainBefore = 1;
  }

  for (var i = 0; i < displayIcons.length; i++) {
    if (wetIcon[i]) continue;
    if (storedProbs[i] >= kMinPrecipProbPercent) continue;

    final idx = stripIndices[i];
    final apiProb = h.precipitationProbability != null &&
            idx < h.precipitationProbability!.length
        ? (h.precipitationProbability![idx] ?? 0)
        : 0;

    var radarApproach = 0;
    if (now != null && radarCtx.eligible && idx < h.time.length) {
      final parsed = DateTime.tryParse(h.time[idx]);
      if (parsed != null) {
        final localT = utcOffsetSeconds != null
            ? parsed.add(Duration(seconds: utcOffsetSeconds))
            : parsed;
        final slotHour = DateTime(
          localT.year,
          localT.month,
          localT.day,
          localT.hour,
        );
        final snap = radarCtx.pinForecast;
        if (snap.authorizesLocalHour(slotHour)) {
          radarApproach = math.min(math.max(snap.approachChancePercent, 30), 40);
        } else if (snap.approaching && snap.etaMinutes != null) {
          final nowHour = DateTime(now.year, now.month, now.day, now.hour);
          final hoursFromNow = slotHour.difference(nowHour).inHours;
          final etaH = math.max(0, (snap.etaMinutes! / 60.0).round());
          final dist = (hoursFromNow - etaH).abs();
          if (hoursFromNow >= 0 && hoursFromNow <= 8) {
            if (dist <= 0) {
              radarApproach = 40;
            } else if (dist == 1) {
              radarApproach = 30;
            } else if (dist == 2) {
              radarApproach = 20;
            }
          }
        }
      }
    }

    final sinceRain = _hoursSinceLastRainInStrip(
      i,
      wetIcon,
      rainHoursBeforeStrip: rainBefore,
    );
    final untilRain = _hoursUntilNextRainInStrip(i, wetIcon);
    final decay = _postRainDecayPercent(sinceRain);
    final cloud = h.cloudCover != null && idx < h.cloudCover!.length
        ? h.cloudCover![idx]
        : null;
    final justAfterRainIcon =
        (i > 0 && wetIcon[i - 1]) || (sinceRain != null && sinceRain == 1);
    var pct = hourlyStripDryHourPercentFromApi(
      apiProbPercent: math.max(apiProb, storedProbs[i]),
      radarApproachPercent: radarApproach,
      iconCode: displayIcons[i],
      cloudCoverPercent: cloud,
      allowFortyNearRain: justAfterRainIcon ||
          (untilRain != null && untilRain <= 1),
    );
    if (!_isClearStripSkyCode(displayIcons[i])) {
      if (justAfterRainIcon) {
        // Hneď po zrážkovej ikone → vždy 40.
        pct = 40;
      } else if (decay > 0) {
        pct = math.max(pct, decay);
      }
      if (untilRain != null && untilRain <= 1) {
        pct = 40;
      }
    }
    storedProbs[i] = _dryStripPercentWithNearbyRainCap(
      pct: pct,
      hoursUntilRain: untilRain,
      hoursSinceRain: sinceRain,
      radarApproachPercent: radarApproach,
      iconCode: displayIcons[i],
    );
  }
}

/// Clamp šancí pre búrku (95/96/99) — aby sa po percent rampách držali v rozumnej škále.
void clampThunderHourlyStripProbs({
  required List<int> displayIcons,
  required List<int> storedProbs,
  required List<double> precipMm,
}) {
  final len = math.min(displayIcons.length, math.min(storedProbs.length, precipMm.length));
  for (var i = 0; i < len; i++) {
    final c = normalizeDisplayWeatherCode(displayIcons[i]);
    if (!kThunderWeatherCodes.contains(c)) continue;
    storedProbs[i] = _roundPrecipProbabilityForDisplay(
      storedProbs[i].clamp(kMinPrecipProbPercent, 100),
    );
  }
}

/// Doplní mm podľa intenzity ikony (slabý/mierny/silný/búrka), aby rozmedzie sedelo s realitou.
void applyThunderStripDisplayMm({
  required List<int> displayIcons,
  required List<int> storedProbs,
  required List<double> precipMm,
}) {
  final len = math.min(displayIcons.length, math.min(storedProbs.length, precipMm.length));
  for (var i = 0; i < len; i++) {
    final icon = displayIcons[i];
    final c = normalizeDisplayWeatherCode(icon);
    if (!kPrecipitationCodes.contains(c) && !kThunderWeatherCodes.contains(c)) {
      continue;
    }
    if (precipMm[i] <= 0 && !kThunderWeatherCodes.contains(c)) {
      // Suchý model + mokrá ikona len pri búrke / už potvrdenom mm.
      continue;
    }
    precipMm[i] = alignPrecipMmForDisplay(precipMm[i], weatherCode: icon);
  }
}

/// Blízke hodiny po všetkých OM/align krokoch — zrážková ikona len podľa
/// **nowcastu do 5 h**. Bez signálu na tú hodinu = sky + 0 mm.
void clampNearTermStripPercentsWithoutRadar({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<int> stripIndices,
  required HourlyForecast h,
  required DateTime locTime,
  int? utcOffsetSeconds,
  required RadarNowcastContext radarCtx,
  List<double>? precipMm,
}) {
  if (!useRadarOnlyNearTermPrecip(radarCtx)) return;

  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );
  final trimStop = radarCtx.nowcastStripGateEndExclusive(locTime);

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
    if (slotHour.isBefore(nowHour) || !slotHour.isBefore(trimStop)) continue;

    if (radarCtx.nowcastAuthorizesStripPrecipHour(slotHour, locTime)) {
      continue;
    }

    if (!(showRainPrecip[i] ||
        _hourShowsPrecipIcon(displayIcons[i]) ||
        (precipMm != null && precipMm[i] >= kMeaningfulPrecipMmPerHour))) {
      continue;
    }

    final cloud = h.cloudCover != null && idx < h.cloudCover!.length
        ? h.cloudCover![idx]
        : null;
    final apiProb = h.precipitationProbability != null &&
            idx < h.precipitationProbability!.length
        ? (h.precipitationProbability![idx] ?? 0)
        : 0;
    displayIcons[i] = skyWmoFromCloudCover(cloud);
    showRainPrecip[i] = false;
    if (precipMm != null) precipMm[i] = 0;
    storedProbs[i] = hourlyStripDryHourPercentFromApi(
      apiProbPercent: apiProb,
      iconCode: displayIcons[i],
      cloudCoverPercent: cloud,
    );
  }
}

/// Bez zrážkovej ikony — % z API (po 10), tip floor 10, suché max 40.
/// **Nestrať variáciu** floorom 30 na celé zamračené ráno.
void clampDryHourlyStripPrecipPercents({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<int> stripIndices,
  required HourlyForecast h,
}) {
  for (var i = 0; i < displayIcons.length; i++) {
    final wetUi =
        showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i]);
    if (wetUi) continue;
    final idx = stripIndices[i];
    final apiProb = h.precipitationProbability != null &&
            idx < h.precipitationProbability!.length
        ? (h.precipitationProbability![idx] ?? 0)
        : storedProbs[i];
    final cloud = h.cloudCover != null && idx < h.cloudCover!.length
        ? h.cloudCover![idx]
        : null;
    storedProbs[i] = hourlyStripDryHourPercentFromApi(
      apiProbPercent: math.max(apiProb, storedProbs[i]),
      iconCode: displayIcons[i],
      cloudCoverPercent: cloud,
    );
  }
}

/// Live pin UI — detekcia pinu cez RainViewer; Helkor/Meteo len fallback bez RV.
/// Stará snímka nepočíta ako „prší teraz“.
({bool wetAtPin, bool approaching, double uiDbz, bool rainViewer})
    radarLivePinUi(RadarNowcastContext ctx) {
  if (!ctx.eligible) {
    return (
      wetAtPin: false,
      approaching: false,
      uiDbz: 0.0,
      rainViewer: false,
    );
  }
  final snap = ctx.pinForecast;
  final latest = ctx.latest;
  final fresh = latest != null && radarPastFrameFreshForLivePin(latest);
  // Bunka nad pinom (mapa) = mokré — nielen stredný pixel ≥ 15 dBZ.
  final wetAtPin = fresh && ctx.radarUiWetAtPin;
  final uiDbz = wetAtPin
      ? math.max(
          snap.uiDbz,
          math.max(ctx.precipIntensityDbz, kRainViewerLegendMinDbz),
        )
      : snap.uiDbz;
  return (
    wetAtPin: wetAtPin,
    approaching: wetAtPin ? false : snap.approaching,
    uiDbz: uiDbz,
    rainViewer: snap.rainViewer || ctx.fromRainViewer,
  );
}

int _radarLivePinIconCode({
  required double uiDbz,
  required bool rainViewer,
  double? tempC,
  int precipProb = 0,
  double precipMm = 0,
}) {
  final snow = rainViewer
      ? rainViewerSnowLikely(tempC: tempC, uiDbz: uiDbz)
      : radarSnowLikely(tempC: tempC);
  // Len dBZ → WMO. Žiadny clamp podľa modelových mm (ten by vrátil rain.svg / 65).
  var icon = rainViewer
      ? wmoFromRainViewerDbz(uiDbz, snow: snow)
      : wmoFromRadarDbz(uiDbz, snow: snow);
  icon = wmoPrecipIconForAirTemp(icon, tempC);
  return capRadarPrecipIconNoHeavy(icon);
}

/// Strop podľa hodín odteraz — len jemný limit pred ladderom v úseku dažďa.
int radarHorizonPrecipProbCap(int hoursAhead) {
  if (hoursAhead <= 0) return 70;
  if (hoursAhead == 1) return 70;
  if (hoursAhead == 2) return 60;
  return 70; // ďaleký úsek rieši 70→60→50 v rámci dažďa, nie flat 50
}

/// % v súvislom mokrom úseku: 1. hodina 70, 2. 60, ďalšie 50.
int wetSpellPrecipProbLadder(int indexInSpell) {
  if (indexInSpell <= 0) return 70;
  if (indexInSpell == 1) return 60;
  return 50;
}

/// Po blend/diversify — mokré % klesajú v úseku dažďa (70→60→50), nie flat 50.
void applyRadarHorizonPrecipProbCaps({
  required List<int> storedProbs,
  required List<bool> showRainPrecip,
  required List<int> displayIcons,
  required List<int> stripIndices,
  required HourlyForecast h,
  required DateTime locTime,
  int? utcOffsetSeconds,
}) {
  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );
  final len = math.min(
    storedProbs.length,
    math.min(
      showRainPrecip.length,
      math.min(displayIcons.length, stripIndices.length),
    ),
  );
  var spellIndex = 0;
  for (var i = 0; i < len; i++) {
    final isWet =
        showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i]);
    if (!isWet || storedProbs[i] < kMinPrecipProbPercent) {
      spellIndex = 0;
      continue;
    }
    final idx = stripIndices[i];
    var hoursAhead = 0;
    if (idx >= 0 && idx < h.time.length) {
      final parsed = DateTime.tryParse(h.time[idx]);
      if (parsed != null) {
        final localT = utcOffsetSeconds != null
            ? parsed.add(Duration(seconds: utcOffsetSeconds))
            : parsed;
        final slotHour = DateTime(
          localT.year,
          localT.month,
          localT.day,
          localT.hour,
        );
        hoursAhead = slotHour.difference(nowHour).inHours;
      }
    }
    // Ladder v úseku + jemný strop podľa vzdialenosti odteraz.
    final ladder = wetSpellPrecipProbLadder(spellIndex);
    final horizon = radarHorizonPrecipProbCap(hoursAhead);
    storedProbs[i] = _roundPrecipProbabilityForDisplay(
      math.min(ladder, horizon).clamp(50, 70),
    );
    spellIndex++;
  }
}

int radarStripCertaintyPercent({
  required bool rainingNow,
  required bool approaching,
  required int hoursAhead,
  required int minsToSlotStart,
  int? etaMinutes,
  int? endMinutes,
  double? distanceKm,
  int approachChancePercent = 0,
  double pinUiDbz = 0,
  double? motionSpeedKmH,
}) {
  final horizonCap = radarHorizonPrecipProbCap(hoursAhead);
  final dist = distanceKm;
  final onTop = rainingNow || (dist != null && dist < 12);
  final departing = (motionSpeedKmH != null && motionSpeedKmH < -2) ||
      (endMinutes != null && endMinutes < 22);
  // Šanca z trajektórie/nowcastu (už po 10) — primárny signál pri príchode.
  final radarChance = approachChancePercent > 0
      ? _roundPrecipProbabilityForDisplay(approachChancePercent.clamp(0, 100))
      : 0;

  if (onTop) {
    // Na pine: istota podľa sily echa + vzdialenosť v čase — nie flat 90 na celý pás.
    int cert;
    if (departing) {
      cert = pinUiDbz >= 35 ? 80 : 70;
    } else if (pinUiDbz >= 40) {
      cert = 90;
    } else if (pinUiDbz >= 28) {
      cert = 80;
    } else if (pinUiDbz >= kRainViewerLegendMinDbz) {
      cert = 70;
    } else {
      cert = 80;
    }
    // Ďalšie hodiny: výrazný pokles (90 → 70 → 60 → 50).
    if (hoursAhead >= 1) {
      cert = (cert - hoursAhead * 10).clamp(50, horizonCap);
    }
    final hold = endMinutes ?? 40;
    if (hold <= minsToSlotStart + 5) {
      cert = math.min(cert, 50);
    } else if (hold <= minsToSlotStart + 25) {
      cert = math.min(cert, 60);
    } else if (hold <= minsToSlotStart + 45) {
      cert = math.min(cert, 70);
    }
    return _roundPrecipProbabilityForDisplay(
      math.min(cert, horizonCap).clamp(50, horizonCap),
    );
  }

  if (approaching || radarChance >= 50) {
    // Príchod: % = radarová šanca, strop podľa hodín dopredu.
    var cert = radarChance >= 50 ? radarChance : 60;
    cert = math.min(cert, horizonCap);

    final eta = etaMinutes ?? 50;
    if (eta > 55) {
      cert = math.min(cert, 60);
    } else if (eta > 35) {
      cert = math.min(cert, 70);
    }
    if (dist != null) {
      if (dist > 55) {
        cert = math.min(cert, 60);
      } else if (dist > 35) {
        cert = math.min(cert, 70);
      }
    }
    if (hoursAhead >= 1) {
      cert = (cert - hoursAhead * 10).clamp(50, horizonCap);
    }
    return _roundPrecipProbabilityForDisplay(
      math.min(cert, horizonCap).clamp(50, horizonCap),
    );
  }

  // Autorizovaná mokrá hodina bez silného live signálu.
  return _roundPrecipProbabilityForDisplay(
    math.min(
      hoursAhead <= 0 ? 70 : (hoursAhead == 1 ? 60 : 50),
      horizonCap,
    ),
  );
}

/// mm/h pre konkrétnu hodinu — **len zo snímky v [slotHour, slotHour+1)**.
/// Žiadne ±35 min / flat dBZ cez pás (to kopírovalo rovnaké mm).
double radarStripMmForHour({
  required RadarNowcastContext radarCtx,
  required RadarPinForecastSnapshot snap,
  required DateTime slotHour,
  required DateTime locTime,
  required int hoursAhead,
}) {
  // Helkor nemá budúce hodinové snímky — live mm len v aktuálnej hodine.
  if (!radarCtx.fromRainViewer) {
    if (hoursAhead != 0) return 0;
    final dbz = radarCtx.precipIntensityDbz;
    if (dbz < kRainViewerLegendMinDbz) return 0;
    final mm = radarLegendMmFromDbz(dbz);
    return mm > 0 ? mm : 0.0;
  }

  // RainViewer: dBZ len z nowcast/histórie v tej hodine (stripDbzForLocalHour).
  final dbz = radarCtx.stripDbzForLocalHour(slotHour, locTime);
  if (dbz < kRainViewerLegendMinDbz) return 0;
  final mm = radarLegendMmFromDbz(dbz);
  return mm > 0 ? mm : 0.0;
}

/// mm pre radarom autorizovanú hodinu — model má prioritu na rozmanitosť;
/// radarová snímka len keď naozaj existuje pre danú hodinu.
double resolveRadarAuthorizedStripMm({
  required double modelMm,
  required double radarMm,
  required int certaintyPercent,
  required int hoursAhead,
}) {
  // Blízka snímka radaru.
  if (radarMm >= kMeaningfulPrecipMmPerHour && hoursAhead <= 1) {
    return radarMm;
  }
  // Modelové mm = rozmanitosť v páse (0.3 / 1.2 / 2.5…).
  if (modelMm >= kMeaningfulPrecipMmPerHour) return modelMm;
  if (radarMm >= kMeaningfulPrecipMmPerHour) return radarMm;
  if (modelMm > 0 && radarMm > 0) return math.max(modelMm, radarMm);
  if (modelMm > 0) return modelMm;
  if (radarMm > 0) return radarMm;
  if (certaintyPercent >= 50) {
    return displayMmFromPrecipProbability(certaintyPercent);
  }
  return 0.0;
}

double rainingFallbackDbz(RadarPinForecastSnapshot snap) {
  // Len pin — nie peak červenej bunky v diaľke.
  if (snap.uiDbz >= kRainViewerLegendMinDbz) return snap.uiDbz;
  if (snap.wetAtPinNow && snap.peakDbz >= kRainViewerLegendMinDbz) {
    return math.min(snap.peakDbz, kRainViewerLegendDrizzleDbz + 5);
  }
  return kRainViewerLegendDrizzleDbz;
}

/// Near-term pás: zrážková ikona **podľa nowcastu do 5 h**.
/// Hodina bez nowcastu/trajektórie na pine = modelový dážď preč.
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
  if (!radarCtx.eligible) return;
  final snap = radarCtx.pinForecast;
  final live = radarLivePinUi(radarCtx);
  final rainingNow = live.wetAtPin;
  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );
  final trimStop = radarCtx.nowcastStripGateEndExclusive(locTime);

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

    final hoursAhead = slotHour.difference(nowHour).inHours;
    final minsToSlotStart = slotHour.difference(locTime).inMinutes;
    final inNowcastWindow =
        !slotHour.isBefore(nowHour) && slotHour.isBefore(trimStop);

    final radarWet =
        radarCtx.nowcastAuthorizesStripPrecipHour(slotHour, locTime);

    if (radarWet) {
      final radarMm = radarStripMmForHour(
        radarCtx: radarCtx,
        snap: snap,
        slotHour: slotHour,
        locTime: locTime,
        hoursAhead: hoursAhead,
      );
      final certainty = radarStripCertaintyPercent(
        rainingNow: rainingNow,
        approaching: snap.approaching && !rainingNow,
        hoursAhead: hoursAhead,
        minsToSlotStart: minsToSlotStart,
        etaMinutes: snap.etaMinutes,
        endMinutes: snap.endMinutes,
        distanceKm: snap.distanceKmEstimate,
        approachChancePercent: snap.approachChancePercent,
        pinUiDbz: snap.uiDbz,
        motionSpeedKmH: snap.motionSpeedKmH,
      );
      final mm = resolveRadarAuthorizedStripMm(
        modelMm: precipMm[i],
        radarMm: radarMm,
        certaintyPercent: certainty,
        hoursAhead: hoursAhead,
      );
      final iconMm = mm > 0 ? mm : radarMm;
      final iconDbz = iconMm >= 0.05
          ? math.max(
              kRainViewerLegendMinDbz,
              iconMm >= 5
                  ? kRainViewerLegendModerateRainDbz
                  : (iconMm >= 1.2
                      ? kRainViewerLegendLightRainDbz
                      : (iconMm >= 0.35
                          ? 30.0
                          : kRainViewerLegendDrizzleDbz)),
            )
          : math.max(
              kRainViewerLegendMinDbz,
              (live.uiDbz > 0 ? live.uiDbz : snap.uiDbz) -
                  4.0 * math.max(0, hoursAhead),
            );
      final icon = _radarLivePinIconCode(
        uiDbz: iconDbz,
        rainViewer: live.rainViewer || snap.rainViewer,
        tempC: h.temperature?[idx],
        precipProb: certainty,
        precipMm: iconMm > 0 ? iconMm : kMeaningfulPrecipMmPerHour,
      );
      displayIcons[i] = capRadarPrecipIconNoHeavy(
        hourlyStripPrecipIntensityIcon(
          baseCode: icon,
          precipMm: iconMm > 0 ? iconMm : kMeaningfulPrecipMmPerHour,
          tempC: h.temperature?[idx],
          allowHeavy: false,
        ),
      );
      showRainPrecip[i] = true;
      // mm zo snímky / modelu / istoty — nie flat 0.1 z min. dBZ na celý pás.
      final fromDbz = radarLegendMmFromDbz(iconDbz);
      if (mm > 0) {
        precipMm[i] = mm;
      } else if (radarMm > 0) {
        precipMm[i] = radarMm;
      } else if (precipMm[i] >= kMeaningfulPrecipMmPerHour) {
        // nechaj modelové mm
      } else if (fromDbz >= 0.15 && hoursAhead <= 1) {
        precipMm[i] = fromDbz;
      } else {
        precipMm[i] = displayMmFromPrecipProbability(certainty);
      }
      // %: radar + API, ale čím ďalej v čase, tým nižší strop (žiadnych 90 % o 3 h).
      final apiProb = h.precipitationProbability != null &&
              idx < h.precipitationProbability!.length
          ? roundPrecipProbPercent(h.precipitationProbability![idx] ?? 0)
          : storedProbs[i];
      final horizonCap = radarHorizonPrecipProbCap(hoursAhead);
      int shownProb;
      if (hoursAhead <= 0) {
        shownProb = math.max(apiProb, certainty);
      } else {
        final decayed = math.min(
          horizonCap,
          (certainty - hoursAhead * 10).clamp(50, horizonCap),
        );
        if (apiProb >= kMinPrecipProbPercent) {
          // API môže doplniť, ale nesmie držať 90 % ďaleko dopredu.
          shownProb = math.min(horizonCap, math.max(decayed, apiProb));
        } else {
          shownProb = decayed;
        }
      }
      storedProbs[i] = _roundPrecipProbabilityForDisplay(
        shownProb.clamp(50, horizonCap),
      );
      continue;
    }

    // V nowcast okne bez mokrej snímky — žiadna zrážková ikona z modelu.
    if (inNowcastWindow &&
        (showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i]))) {
      final cloud = h.cloudCover != null && idx < h.cloudCover!.length
          ? h.cloudCover![idx]
          : null;
      final apiProb = h.precipitationProbability != null &&
              idx < h.precipitationProbability!.length
          ? (h.precipitationProbability![idx] ?? 0)
          : 0;
      displayIcons[i] = skyWmoFromCloudCover(cloud);
      showRainPrecip[i] = false;
      storedProbs[i] = hourlyStripDryHourPercentFromApi(
        apiProbPercent: apiProb,
        iconCode: displayIcons[i],
        cloudCoverPercent: cloud,
      );
      precipMm[i] = 0;
    }
  }
}

/// Hero — „prší teraz“ len keď je pin mokrý. Blížiaca sa bunka ≠ aktuálny dážď.
/// Keď je radar eligible, modelová zrážková ikona sa nikdy nepoužije namiesto nowcastu.
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
  final live = radarLivePinUi(radarCtx);
  if (live.wetAtPin) {
    return _radarLivePinIconCode(
      uiDbz: live.uiDbz > 0 ? live.uiDbz : kRainViewerLegendMinDbz,
      rainViewer: live.rainViewer,
      tempC: tempC,
      precipProb: math.max(precipProb, kMinPrecipProbPercent),
      precipMm: math.max(precipMm, kMeaningfulPrecipMmPerHour),
    );
  }
  // Radar pokrýva lokalitu a pin je suchý — žiadny „Dážď“ z modelu / approaching.
  if (radarCtx.eligible && radarCtx.latest != null) {
    final c = normalizeDisplayWeatherCode(code);
    if (kPrecipitationCodes.contains(c)) {
      return skyWmoFromCloudCover(cloudCoverPercent);
    }
  }
  // Pokrytie mesta radarom, ale fetch ešte nie — aspoň neukáž silný modelový lejak.
  if (radarCoverageActive && kPrecipitationCodes.contains(normalizeDisplayWeatherCode(code))) {
    return capRadarPrecipIconNoHeavy(code);
  }
  return code;
}

/// Ikona denného úseku — iba Open-Meteo (radar v denných kartách spôsoboval stack overflow).
int applyRadarPrecipToDayPartIcon(
  int code, {
  required RadarNowcastContext radarCtx,
  required bool partHasRadarPrecip,
  double? tempC,
}) =>
    code;

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

/// Pinned hlavička a domovské widgety — zrážky bez slabý/silný/mrholenie.
String weatherDescriptionPinnedSk(int? code) {
  final c = normalizeDisplayWeatherCode(code);
  return simplifiedPrecipLabelSk(c) ?? weatherDescriptionSk(code);
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

/// Minimálny súčet mm v úseku bez šance ≥50 % — jedna stopa o polnoci nestačí.
const double kDayPartMinSumMmForWetIcon = 0.3;

/// Či úsek dňa na karte má ukázať mokré ikony.
///
/// Musí sedieť s dennou kartou / pätičkou: ≥0,1 mm + ≥50 % (inak hlavná ikona
/// dažďová a Ráno/Poobede/… stále suché).
bool dayPartWetIconWarranted({
  required double partSumMm,
  required int maxProbPercent,
  required int wetHourCount,
  required double maxHourMm,
}) {
  if (wetHourCount >= 2) return true;
  if (partSumMm >= kDayPartMinSumMmForWetIcon) return true;
  if (maxHourMm >= kDayPartMinSumMmForWetIcon) return true;
  // Rovnaký prah ako denná karta / pätička (0,2 mm @ 50 % → mrholenie v úseku).
  if (maxProbPercent >= kMinPrecipProbPercent &&
      (partSumMm >= kMeaningfulPrecipMmPerHour ||
          maxHourMm >= kMeaningfulPrecipMmPerHour)) {
    return true;
  }
  if (wetHourCount >= 1 &&
      maxHourMm >= kMeaningfulPrecipMmPerHour &&
      maxProbPercent >= 70) {
    return true;
  }
  return false;
}

/// Keď denná ikona ukazuje zrážky, ale všetky úseky sú suché, doplní mokrú ikonu
/// do úseku s najväčším úhrnom / šancou (ľahší vizuál podľa dennej ikony).
void syncWetDayPartIconsWithDailyMain({
  required int dailyMainIconCode,
  required double dailyPrecipMm,
  required int dailyPrecipProb,
  required double snowfallCm,
  required List<(String, Map<String, dynamic>)> parts,
}) {
  if (!dailyCardShowsWetPrecip(
    trustedMm: dailyPrecipMm,
    trustedProb: dailyPrecipProb,
    snowfallCm: snowfallCm,
  )) {
    return;
  }
  final mainWet = kPrecipitationCodes.contains(
    normalizeDisplayWeatherCode(dailyMainIconCode),
  );
  if (!mainWet) return;
  if (!dayPartIconCodesAllDry(parts.map((e) => e.$2['iconCode'] as int?))) {
    return;
  }

  Map<String, dynamic>? bestPart;
  var bestKey = '';
  var bestSum = -1.0;
  var bestProb = -1;
  for (final entry in parts) {
    final part = entry.$2;
    final sum = (part['partSumMm'] as num?)?.toDouble() ?? 0.0;
    final maxMm = (part['partMaxMm'] as num?)?.toDouble() ?? 0.0;
    final prob = (part['prob'] as int?) ?? 0;
    final score = math.max(sum, maxMm);
    if (score > bestSum || (score == bestSum && prob > bestProb)) {
      bestSum = score;
      bestProb = prob;
      bestPart = part;
      bestKey = entry.$1;
    }
  }
  if (bestPart == null) return;

  final wetCode = lightDailyPrecipVisualCode(
    normalizeDisplayWeatherCode(dailyMainIconCode),
  );
  final forceDay = bestKey == 'morning' || bestKey == 'afternoon';
  final forceNight = bestKey == 'night';
  bestPart['iconCode'] = wetCode;
  bestPart['icon'] = getWeatherIcon(
    wetCode,
    size: 38,
    forceDay: forceDay,
    forceNight: forceNight,
  );
  bestPart['partSumMm'] = math.max(
    (bestPart['partSumMm'] as num?)?.toDouble() ?? 0.0,
    math.max(dailyPrecipMm, kMeaningfulPrecipMmPerHour),
  );
  bestPart['prob'] = math.max(
    (bestPart['prob'] as int?) ?? 0,
    dailyPrecipProb,
  );
}

/// Prístupová fáza v 24 h — max. 3 h pred skutočným ECMWF dažďom.
const int kStripApproachMaxHours = 3;
const int kStripApproachProbFar = 50;
const int kStripApproachProbNear = 60;
const int kStripPhantomDecayHours = 3;

/// Búrková ikona — min. šanca a mm/h na zobrazenie ikony (nie zobrazený úhrn).
const double kThunderMinMmPerHour = 2.0;

/// mm/h v 24 h pásme pri búrke — model + spodná hranica podľa intenzity ikony.
double hourlyThunderStripDisplayMm({
  required int iconCode,
  required int probPercent,
  required double ecmwfMm,
  int? hourIndex,
  bool deDuplicateNeighbors = false,
}) {
  return alignPrecipMmForDisplay(ecmwfMm, weatherCode: iconCode);
}

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

/// Intenzita zrážok z úhrnu (mm/h alebo denný úhrn v tom istom meradle pre UI).
enum PrecipIntensity {
  none,
  trace,
  light,
  moderate,
  heavy,
  extreme,
}

/// Sila zrážok z mm — najprv toto, potom ikona / blesky.
PrecipIntensity precipIntensityFromMm(double amount) {
  if (amount <= 0.0) return PrecipIntensity.none;
  if (amount < 0.5) return PrecipIntensity.trace;
  if (amount < 2.0) return PrecipIntensity.light;
  if (amount < 5.0) return PrecipIntensity.moderate;
  if (amount < 15.0) return PrecipIntensity.heavy;
  return PrecipIntensity.extreme;
}

/// Textové rozmedzie úhrnu — krátke stupne bez znaku `<`.
String precipAmountRangeLabel(double amount) {
  if (amount <= 0.0) return '0';
  if (amount < 1.0) return '0-1';
  if (amount < 2.0) return '1-2';
  if (amount < 3.0) return '2-3';
  if (amount < 5.0) return '3-5';
  if (amount < 8.0) return '5-8';
  if (amount < 12.0) return '8-12';
  if (amount < 20.0) return '12-20';
  if (amount < 30.0) return '20-30';
  if (amount < 50.0) return '30-50';
  return '50+';
}

/// Búrka/blesky len od miernej sily zrážok; živé blesky stačia od slabého dažďa.
bool precipIntensityAllowsThunder(
  double precipMm, {
  bool liveLightning = false,
}) {
  final intensity = precipIntensityFromMm(precipMm);
  if (liveLightning) {
    return intensity.index >= PrecipIntensity.light.index ||
        precipMm >= kMeaningfulPrecipMmPerHour;
  }
  return intensity.index >= PrecipIntensity.moderate.index;
}

/// WMO búrky podľa sily zrážok (+ živé blesky).
int thunderWmoForPrecipIntensity(
  double precipMm, {
  bool liveLightning = false,
  int? preferredApiThunderCode,
}) {
  final intensity = precipIntensityFromMm(precipMm);
  if (preferredApiThunderCode != null) {
    final c = normalizeDisplayWeatherCode(preferredApiThunderCode);
    if (kThunderWeatherCodes.contains(c)) {
      // Pri slabej sile nestav silnú búrku s krúpami.
      if (intensity.index < PrecipIntensity.heavy.index && (c == 96 || c == 99)) {
        return 95;
      }
      return c;
    }
  }
  if (intensity.index >= PrecipIntensity.extreme.index) return 99;
  if (intensity.index >= PrecipIntensity.heavy.index) {
    return liveLightning ? 96 : 95;
  }
  return 95;
}

/// Spodná hranica mm podľa intenzity ikony — jemné dorovnanie, nie skok na silný dážď.
///
/// [dailyContext]: denný úhrn — búrka/silný dážď aspoň mierny denný úhrn, nie stopu.
double precipMmFloorForIntensityIcon(
  int? weatherCode, {
  bool dailyContext = false,
}) {
  if (weatherCode == null) return 0.0;
  final c = normalizeDisplayWeatherCode(weatherCode);
  if (!kPrecipitationCodes.contains(c) && !kThunderWeatherCodes.contains(c)) {
    return 0.0;
  }
  // Búrka: stačí spodok „mierny“ — silu určuje reálne mm / rozmedzie.
  if (kThunderWeatherCodes.contains(c)) {
    return dailyContext ? _kModeratePrecipMmDayPart : kThunderMinMmPerHour;
  }
  if (c == 65 || c == 75 || c == 82 || c == 86) {
    return dailyContext ? _kHeavyPrecipMmBlockSum : _kHeavyPrecipMmBlockSum;
  }
  if (c == 63 || c == 67 || c == 73 || c == 81 || c == 85) {
    return dailyContext ? _kModeratePrecipMmDayPart : _kModeratePrecipMmBlockSum;
  }
  if (c == 61 || c == 66 || c == 71 || c == 80) {
    // Len stopa — nie floor 0.5 (to zjednotilo celý pás na „0.5-1“).
    return kMeaningfulPrecipMmPerHour;
  }
  return kMeaningfulPrecipMmPerHour;
}

/// Zosúladí modelové/radarové mm s ikonou — bez umelého nafúknutia nad reálnu silu.
double alignPrecipMmForDisplay(
  double amount, {
  int? weatherCode,
  bool dailyContext = false,
}) {
  if (amount <= 0.0) return 0.0;
  final floor = precipMmFloorForIntensityIcon(
    weatherCode,
    dailyContext: dailyContext,
  );
  // Ak model hlási stopu a ikona je búrka, dorovnaj len na prah búrky (2 mm), nie na 5–10.
  return math.max(amount, floor);
}

/// Zlúči WMO z Open-Meteo s mm — zrážkový kód len pri potvrdených mm + %.
int effectiveWmoWeatherCode({
  int? apiCode,
  required double precipMm,
  required int precipProbPercent,
  double? cloudCoverPercent,
  double snowfallCm = 0.0,
}) {
  final showPrecipIcon = hourlyPrecipIconWarranted(
        mm: precipMm,
        prob: precipProbPercent,
        weatherCode: apiCode,
      ) ||
      snowfallCm >= 0.1;

  if (apiCode != null) {
    final code = normalizeDisplayWeatherCode(apiCode);
    if (ecmwfJsonThunderHour(code)) {
      if (_thunderIconWarranted(precipProbPercent, precipMm, snowfallCm: snowfallCm)) {
        return code;
      }
      if (showPrecipIcon) {
        return wmoFromPrecipitationMm(
          precipMm,
          snowfallCm: snowfallCm,
          cloudCoverPercent: cloudCoverPercent,
        );
      }
      return reconcileSkyCodeWithCloudCover(code, cloudCoverPercent);
    }
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

/// ECMWF JSON hlási búrku pre danú hodinu (WMO 95/96/99).
bool ecmwfJsonThunderHour(int? apiCode) {
  if (apiCode == null) return false;
  return kThunderWeatherCodes.contains(normalizeDisplayWeatherCode(apiCode));
}

/// WMO 95–99 z ECMWF — búrková ikona len pri živých bleskoch v okolí (nie vzdialená bunka modelu).
int applyEcmwfJsonThunderHourIcon(
  int code, {
  int? ecmwfApiCode,
  required int precipProb,
  required double precipMm,
  bool lightningNearby = false,
}) {
  if (!lightningNearby || !ecmwfJsonThunderHour(ecmwfApiCode)) return code;
  if (precipProb < kMinPrecipProbPercent &&
      precipMm < kMeaningfulPrecipMmPerHour &&
      !kPrecipitationCodes.contains(code)) {
    return code;
  }
  return normalizeDisplayWeatherCode(ecmwfApiCode!);
}

/// Má hodina v 24 h pásme hlásiť dážď (ikona + % + mm z ECMWF)?
bool hourlyStripShowRainPrecip({
  required int iconCode,
  required double precipMm,
  required int precipProb,
  int? ecmwfApiCode,
}) {
  final apiCode = ecmwfApiCode ?? iconCode;
  final norm = normalizeDisplayWeatherCode(apiCode);
  if (kThunderWeatherCodes.contains(norm) &&
      !_thunderIconWarranted(precipProb, precipMm)) {
    return false;
  }
  if (!hourlyPrecipIconWarranted(
    mm: precipMm,
    prob: precipProb,
    weatherCode: apiCode,
  )) {
    return false;
  }
  return true;
}

int _postRainDecayPercent(int? hoursSinceRain) {
  if (hoursSinceRain == null || hoursSinceRain < 1) return 0;
  if (hoursSinceRain == 1) return 40;
  if (hoursSinceRain == 2) return 30;
  if (hoursSinceRain == 3) return 20;
  return 0;
}

int _postRainSkyIcon(int hoursSinceRain, double? cloudCoverPercent) {
  final fromCloud = skyWmoFromCloudCover(cloudCoverPercent);
  if (hoursSinceRain <= 1) return math.max(fromCloud, 2);
  if (hoursSinceRain == 2) return math.max(fromCloud, 2);
  if (hoursSinceRain == 3) return math.max(fromCloud, 1);
  return fromCloud;
}

/// Po daždi — oblačno + klesajúce % (40 → 30 → 20), nie jasno / 10 %.
void applyPostRainDecayToHourlyStrip({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> precipPercents,
  required List<double> precipMm,
  required List<double?> cloudCoverPercents,
  required List<bool> pastRainHour,
  required int rainHoursBeforeStrip,
}) {
  for (var i = 0; i < displayIcons.length; i++) {
    if (pastRainHour[i] || precipMm[i] >= kMeaningfulPrecipMmPerHour) continue;
    if (_hourShowsPrecipIcon(displayIcons[i]) && showRainPrecip[i]) continue;

    // Jasno — nikdy dozvuk 40 %, vždy 10 %.
    if (_isClearStripSkyCode(displayIcons[i])) {
      precipPercents[i] = 10;
      showRainPrecip[i] = false;
      precipMm[i] = 0;
      continue;
    }

    final sinceRain = _hoursSinceLastRainInStrip(
      i,
      pastRainHour,
      rainHoursBeforeStrip: rainHoursBeforeStrip,
    );
    final decayPct = _postRainDecayPercent(sinceRain);
    if (decayPct <= 0) continue;

    precipPercents[i] = _roundPrecipProbabilityForDisplay(
      math.max(precipPercents[i], decayPct),
    );
    showRainPrecip[i] = false;
    precipMm[i] = 0;

    final sky = normalizeDisplayWeatherCode(displayIcons[i]);
    if (kPrecipitationCodes.contains(sky)) {
      displayIcons[i] = _postRainSkyIcon(
        sinceRain!,
        cloudCoverPercents.length > i ? cloudCoverPercents[i] : null,
      );
    }
  }
}

/// Radarom autorizované hodiny v 24 h pásme — ikona + % (sledovač ↔ pás).
void applyRadarAuthorizedHourlyStripDisplay({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> precipPercents,
  required List<double> precipMm,
  required List<DateTime> slotHours,
  required List<int?> apiWeatherCodes,
  required List<double?> cloudCoverPercents,
  required RadarNowcastContext radarCtx,
  required DateTime locTime,
  double? tempC,
}) {
  final nowHour = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  );
  for (var i = 0; i < slotHours.length; i++) {
    final slotHour = slotHours[i];
    if (!radarCtx.eligible) continue;
    if (!radarCtx.authorizesPrecipAtLocalHour(slotHour, locTime)) continue;

    final isCurrent = slotHour == nowHour;
    final rawDbz = radarCtx.fromRainViewer
        ? (isCurrent && radarCtx.precipNow
            ? math.max(
                radarCtx.precipIntensityDbz,
                radarCtx.stripDbzForLocalHour(slotHour, locTime),
              )
            : radarCtx.stripDbzForLocalHour(slotHour, locTime))
        : (isCurrent && radarCtx.precipNow
            ? radarCtx.precipIntensityDbz
            : radarCtx.stripMmDbz);
    final uiDbz = radarCtx.fromRainViewer
        ? rainViewerDbzForUi(rawDbz)
        : rawDbz;
    final iconDbz = math.max(
      uiDbz,
      radarCtx.fromRainViewer
          ? kRainViewerLegendMinDbz.toDouble()
          : kRadarMinDbzForUi,
    );
    final radarProb = math.max(
      effectiveRadarProbFromDbz(iconDbz, radarCtx),
      kMinPrecipProbPercent,
    );
    final radarMmOnly = effectiveRadarMmFromDbz(iconDbz, radarCtx);
    // Modelové mm majú prioritu — radar ich nesmie zjednotiť cez celý pás.
    final mm = precipMm[i] > 0
        ? precipMm[i]
        : radarMmOnly;
    var icon = radarCtx.fromRainViewer
        ? wmoFromRainViewerDbz(
            iconDbz,
            snow: rainViewerSnowLikely(tempC: tempC, uiDbz: iconDbz),
          )
        : wmoFromRadarDbz(iconDbz, snow: radarSnowLikely(tempC: tempC));
    icon = capRadarPrecipIconNoHeavy(
      _clampPrecipitationIconIntensity(
        icon,
        radarProb,
        mm,
        isDailyContext: false,
      ),
    );
    displayIcons[i] = icon;
    showRainPrecip[i] = true;
    if (precipMm[i] <= 0 && radarMmOnly > 0) {
      precipMm[i] = radarMmOnly;
    }
    precipPercents[i] = _roundPrecipProbabilityForDisplay(
      math.max(precipPercents[i], radarProb),
    );
  }
}

/// Ikona a % v 24 h — mimo radarového okna model WMO + % ≥ 50 → zrážková ikona.
/// V blízkom okne s radarom ikonu nedopĺňa — to robí radar gate.
void alignHourlyStripIconsWithPrecipPercents({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> precipPercents,
  required List<double> precipMm,
  required List<int?> apiWeatherCodes,
  required List<double?> cloudCoverPercents,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
  DateTime? locTime,
  List<DateTime>? slotHours,
}) {
  final loc = locTime;
  final trimStop = loc != null && useRadarOnlyNearTermPrecip(radarCtx)
      ? radarCtx.nowcastStripGateEndExclusive(loc)
      : null;
  final nowHour = loc == null
      ? null
      : DateTime(loc.year, loc.month, loc.day, loc.hour);

  for (var i = 0; i < displayIcons.length; i++) {
    final pct = precipPercents[i];
    var icon = displayIcons[i];
    final mm = precipMm[i];
    final api = apiWeatherCodes[i];
    final cloud = cloudCoverPercents[i];
    final roundedPct = roundPrecipProbPercent(pct);
    final apiPrecipCode = api != null &&
        kPrecipitationCodes.contains(normalizeDisplayWeatherCode(api));

    final stop = trimStop;
    final inRadarNearTerm = stop != null &&
        nowHour != null &&
        slotHours != null &&
        i < slotHours.length &&
        !slotHours[i].isBefore(nowHour) &&
        slotHours[i].isBefore(stop);

    // Model hlási dážď/búrku + % ≥ 50 — mimo radarového okna ukáž ikonu.
    // V near-terme s radarom to nerob — inak znova maľuje „Dážď“ bez echo.
    if (apiPrecipCode &&
        roundedPct >= kMinPrecipProbPercent &&
        !inRadarNearTerm) {
      showRainPrecip[i] = true;
      if (!_hourShowsPrecipIcon(icon)) {
        displayIcons[i] = _clampPrecipitationIconIntensity(
          normalizeDisplayWeatherCode(api),
          roundedPct,
          mm,
          isDailyContext: false,
        );
      }
      precipPercents[i] = math.max(
        roundedPct,
        ecmwfWetHourDisplayProbPercent(
          rawApiProb: pct,
          precipMm: precipMm[i],
          weatherCode: api,
          cloudCoverPercent: cloud,
        ),
      );
      // precipMm ostáva z API / blendu — bez doplnenia z %.
      continue;
    }

    final wetIcon = _hourShowsPrecipIcon(icon);
    final wetSlot = showRainPrecip[i] || wetIcon;

    if (!wetSlot) continue;

    if (pct >= kMinPrecipProbPercent) {
      if (!wetIcon && !inRadarNearTerm) {
        final modelCode = effectiveWmoWeatherCode(
          apiCode: api,
          precipMm: mm,
          precipProbPercent: pct,
          cloudCoverPercent: cloud,
          snowfallCm: 0.0,
        );
        final base = kPrecipitationCodes.contains(
          normalizeDisplayWeatherCode(modelCode),
        )
            ? modelCode
            : 61;
        displayIcons[i] = _clampPrecipitationIconIntensity(
          base,
          pct,
          mm,
          isDailyContext: false,
        );
      }
      continue;
    }

    final precipCode = api != null &&
        kPrecipitationCodes.contains(normalizeDisplayWeatherCode(api));
    if (mm >= kMeaningfulPrecipMmPerHour &&
        (precipCode || ecmwfHourPrecipShowsInUi(mm: mm, prob: pct))) {
      precipPercents[i] = _roundPrecipProbabilityForDisplay(
        math.max(pct, kMinPrecipProbPercent),
      );
      continue;
    }

    displayIcons[i] = skyWmoFromCloudCover(cloud);
    showRainPrecip[i] = false;
  }
}

/// Pri detegovaných bleskoch — búrka len ak mm sila sedí (slabý+).
int applyNearbyLightningIcon(
  int code, {
  required bool lightningNearby,
  double precipMm = 0,
  int precipProb = 0,
}) {
  if (!lightningNearby) return code;
  final mmForGate = precipMm > 0
      ? precipMm
      : (precipProb >= kMinPrecipProbPercent ? 0.5 : 0.0);
  if (!precipIntensityAllowsThunder(mmForGate, liveLightning: true)) {
    return code;
  }
  final norm = normalizeDisplayWeatherCode(code);
  if (kThunderWeatherCodes.contains(norm)) return code;
  return thunderWmoForPrecipIntensity(mmForGate, liveLightning: true);
}

/// Búrková ikona: najprv sila z mm, potom blesky; bez bleskov modelovú búrku zjemni.
int suppressThunderWithoutLightning(
  int code, {
  required bool lightningNearby,
  required int precipProb,
  required double precipMm,
  double? cloudCoverPercent,
  int? ecmwfApiCode,
}) {
  final norm = normalizeDisplayWeatherCode(code);
  if (lightningNearby) {
    if (precipIntensityAllowsThunder(precipMm, liveLightning: true) ||
        precipProb >= kMinPrecipProbPercent) {
      return thunderWmoForPrecipIntensity(
        math.max(precipMm, 0.5),
        liveLightning: true,
        preferredApiThunderCode: kThunderWeatherCodes.contains(norm) ? norm : null,
      );
    }
    return code;
  }
  if (!kThunderWeatherCodes.contains(norm)) return code;

  if (precipIntensityAllowsThunder(precipMm) &&
      precipProb >= kMinPrecipProbPercent) {
    return thunderWmoForPrecipIntensity(
      precipMm,
      preferredApiThunderCode: norm,
    );
  }

  if (ecmwfHourPrecipShowsInUi(mm: precipMm, prob: precipProb)) {
    return hourlyStripPrecipIntensityIcon(
      baseCode: 61,
      precipMm: precipMm,
    );
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
const int _kHeavyPrecipProbMin = 70;
/// 10 dní — silný dážď (rain.svg) až od denného súčtu.
const double _kHeavyPrecipMmDaily = 15.0;
/// 24 h — silný dážď (rain.svg) za jednu hodinu (nad 5 mm/h).
const double _kHeavyPrecipMmBlockSum = 5.0;
const int _kModeratePrecipProbMin = 60;
/// 10 dní — mierny dážď; pod týmto súčtom denná karta vždy ľahká ikona.
const double _kModeratePrecipMmDaily = 10.0;
/// 24 h — mierny dážď (drizzle.svg) za hodinu.
const double _kModeratePrecipMmBlockSum = 2.0;
const double _kHeavySnowCmDaily = 15.0;
/// Pod 2 cm/deň denná karta zjemní snehovú ikonu.
const double _kModerateSnowCmDaily = 2.0;
/// 24 h — silný sneh (snow.svg) za hodinu (≥ 5 cm/h), rovnako ako silný dážď ≥ 5 mm.
const double _kHeavySnowCmBlockSum = 5.0;
/// 24 h — mierny sneh za hodinu (≥ 2 cm/h), rovnako ako mierny dážď ≥ 2 mm.
const double _kModerateSnowCmBlockSum = 2.0;
/// 10 dní — silný dážď v úseku (súčet ~6 h), vyššie než 5 mm/h v 24 h páse.
const double _kHeavyPrecipMmDayPart = 10.0;
/// 10 dní — mierny dážď v úseku.
const double _kModeratePrecipMmDayPart = 4.0;
/// 10 dní — silný sneh v úseku (súčet cm), vyššie než 5 cm/h v 24 h.
const double _kHeavySnowCmDayPart = 8.0;
/// 10 dní — mierny sneh v úseku.
const double _kModerateSnowCmDayPart = 3.0;
/// 10 dní — silný sneh na celej dennej karte (cm/deň).
const double _kHeavySnowCmDailyIcon = 10.0;
/// 10 dní — mierny sneh na dennej karte.
const double _kModerateSnowCmDailyIcon = 5.0;

/// Úsek dňa (ráno/…): fáza podľa teploty + denného snehu, intenzita zo súčtu úseku.
///
/// Prahy sú zámerne vyššie než 1 h v 24 h (úsek ≈ 6 h), ale rovnaká logika 3 stupňov.
int dayPartPrecipDisplayIcon({
  required int code,
  double? avgTempC,
  required double partSumMm,
  required int probPercent,
  double partSnowCm = 0,
  double dailySnowCm = 0,
}) {
  final n = normalizeDisplayWeatherCode(code);
  if ({95, 96, 99}.contains(n)) return n;
  final baseSignal = kPrecipitationCodes.contains(n) ||
      partSumMm >= kMeaningfulPrecipMmPerHour ||
      partSnowCm >= 0.1 ||
      dailySnowCm >= 0.5;
  if (!baseSignal) return n;
  if (partSnowCm < 0.1 &&
      dailySnowCm < 0.5 &&
      !dayPartWetIconWarranted(
        partSumMm: partSumMm,
        maxProbPercent: probPercent,
        wetHourCount: kPrecipitationCodes.contains(n) ? 1 : 0,
        maxHourMm: partSumMm,
      )) {
    return isSkyOnlyWmoCode(n) ? n : 2;
  }

  final cold = avgTempC != null && avgTempC <= kSnowMaxAirTempC;
  final snowSignal = dailySnowCm >= 0.5 || partSnowCm >= 0.1;
  // −2 °C alebo deň so snehom → sneženie, nie dážď.
  final asSnow = cold || (snowSignal && (avgTempC == null || avgTempC <= 1.0));

  if (asSnow) {
    final cm = partSnowCm >= 0.1
        ? partSnowCm
        : (dailySnowCm >= 0.5
            ? math.max(partSumMm, dailySnowCm / 4.0)
            : partSumMm);
    if (cm >= _kHeavySnowCmDayPart &&
        probPercent >= kMinPrecipProbPercent) {
      return 75;
    }
    if (cm >= _kModerateSnowCmDayPart &&
        probPercent >= kMinPrecipProbPercent) {
      return 73;
    }
    return 71;
  }

  // Nad bodom mrazu — dážď (aj keby model hlásil sneh).
  if (partSumMm >= _kHeavyPrecipMmDayPart &&
      probPercent >= kMinPrecipProbPercent) {
    return 65;
  }
  if (partSumMm >= _kModeratePrecipMmDayPart &&
      probPercent >= kMinPrecipProbPercent) {
    return 63;
  }
  if (partSumMm >= 1.0) return 61;
  return 51;
}

/// Hlavná ikona 10-dňovej karty — denný súčet (nie hodinové prahy z 24 h).
int dailyCardPrecipDisplayIcon({
  required int code,
  required double dailyPrecipMm,
  required double dailySnowCm,
  required int probPercent,
  double? dayAvgTempC,
}) {
  final n = normalizeDisplayWeatherCode(code);
  if ({95, 96, 99}.contains(n)) return n;
  final wet = kPrecipitationCodes.contains(n) ||
      dailyPrecipMm >= kMeaningfulPrecipMmPerHour ||
      dailySnowCm >= 0.5;
  if (!wet) return n;

  final cold = dayAvgTempC != null && dayAvgTempC <= kSnowMaxAirTempC;
  final asSnow = dailySnowCm >= 0.5 || cold;

  if (asSnow) {
    final cm = dailySnowCm >= 0.5 ? dailySnowCm : dailyPrecipMm;
    if (cm >= _kHeavySnowCmDailyIcon &&
        probPercent >= kMinPrecipProbPercent) {
      return 75;
    }
    if (cm >= _kModerateSnowCmDailyIcon &&
        probPercent >= kMinPrecipProbPercent) {
      return 73;
    }
    return 71;
  }

  if (dailyPrecipMm >= _kHeavyPrecipMmDaily &&
      probPercent >= kMinPrecipProbPercent) {
    return 65;
  }
  if (dailyPrecipMm >= _kModeratePrecipMmDaily &&
      probPercent >= kMinPrecipProbPercent) {
    return 63;
  }
  if (dailyPrecipMm >= 2.0) return 61;
  return 51;
}

/// Výdatný denný lejak — silná ikona (rain.svg / WMO 65).
bool dayPartHeavyPrecipWarranted(double partPrecipMm, int probPercent) =>
    probPercent >= _kHeavyPrecipProbMin && partPrecipMm >= _kHeavyPrecipMmDayPart;

bool dayPartHeavySnowWarranted(double partSnowCm, int probPercent) =>
    probPercent >= _kHeavyPrecipProbMin && partSnowCm >= _kHeavySnowCmDayPart;

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
  double? dayAvgTempC,
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
      !kSnowWeatherCodes.contains(result) &&
      dailySnowCm < 0.5) {
    result = lightDailyPrecipVisualCode(result);
  }
  if (dailySnowCm > 0 &&
      dailySnowCm < _kModerateSnowCmDailyIcon &&
      kSnowWeatherCodes.contains(result)) {
    result = lightDailySnowVisualCode(result);
  }
  // 10 dní: fáza (sneh pri mraze / cm) + denné prahy (nie 5 mm/h z 24 h).
  result = dailyCardPrecipDisplayIcon(
    code: result,
    dailyPrecipMm: dailyPrecipMm,
    dailySnowCm: dailySnowCm,
    probPercent: dailyProb,
    dayAvgTempC: dayAvgTempC,
  );
  return result;
}

/// Po výbere ikony podľa prahu zrážok upraví intenzitu — napr. 12 mm/deň = mrholenie, nie rain.svg (až od 15 mm).
int _clampPrecipitationIconIntensity(
  int code,
  int probPercent,
  double precipMm,
  {
  required bool isDailyContext,
  bool isDayPartContext = false,
  double snowfallCm = 0.0,
  bool preserveEcmwfThunderFromJson = false,
}) {
  if (_belowMeaningfulPrecipAmountForIcon(precipMm, snowfallCm) &&
      kPrecipitationCodes.contains(code)) {
    return _lightPrecipDisplayCode(code);
  }

  if (!kPrecipitationCodes.contains(code)) return code;

  final mmHeavy = isDailyContext
      ? _kHeavyPrecipMmDaily
      : (isDayPartContext ? _kHeavyPrecipMmDayPart : _kHeavyPrecipMmBlockSum);
  final mmMod = isDailyContext
      ? _kModeratePrecipMmDaily
      : (isDayPartContext ? _kModeratePrecipMmDayPart : _kModeratePrecipMmBlockSum);
  // 24 h pás: intenzita podľa mm (5+ = silný), nie až od 70 % šance.
  final heavyOk = isDailyContext
      ? (probPercent >= _kHeavyPrecipProbMin && precipMm >= mmHeavy)
      : (precipMm >= mmHeavy && probPercent >= kMinPrecipProbPercent);
  if (heavyOk) {
    var next = code;
    if ({51, 53, 55, 61, 63}.contains(next)) next = 65;
    if (next == 80 || next == 81) next = 82;
    if (isDailyContext && precipMm < _kHeavyPrecipMmDaily) {
      return lightDailyPrecipVisualCode(next);
    }
    return next;
  }

  final moderateOk = isDailyContext
      ? (probPercent >= _kModeratePrecipProbMin && precipMm >= mmMod)
      : (precipMm >= mmMod && probPercent >= kMinPrecipProbPercent);

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
    final snowHeavy = isDailyContext
        ? _kHeavySnowCmDaily
        : (isDayPartContext ? _kHeavySnowCmDayPart : _kHeavySnowCmBlockSum);
    final snowMod = isDailyContext
        ? _kModerateSnowCmDaily
        : (isDayPartContext ? _kModerateSnowCmDayPart : _kModerateSnowCmBlockSum);
    // V 24 h často chýba hourly snowfall — intenzita zo zobrazených mm.
    final snowAmount =
        snowfallCm >= 0.1 ? snowfallCm : (isDailyContext ? snowfallCm : precipMm);
    final heavySnowOk = isDailyContext
        ? (probPercent >= _kHeavyPrecipProbMin && snowAmount >= snowHeavy)
        : (snowAmount >= snowHeavy && probPercent >= kMinPrecipProbPercent);
    final moderateSnowOk = isDailyContext
        ? (probPercent >= _kModeratePrecipProbMin && snowAmount >= snowMod)
        : (snowAmount >= snowMod && probPercent >= kMinPrecipProbPercent);

    if (!moderateSnowOk) {
      final light = code == 86
          ? 85
          : ({75, 73, 85, 77}.contains(code)
              ? 71
              : (code == 57 ? 56 : code));
      if (isDailyContext &&
          snowAmount > 0 &&
          snowAmount < _kModerateSnowCmDaily) {
        return lightDailySnowVisualCode(light);
      }
      return light;
    }
    if (heavySnowOk) {
      if (code == 56 || code == 57) return 57;
      if (code == 86) return 86;
      return 75;
    }
    if (code == 57) return 56;
    if (code == 75 && snowAmount < snowHeavy) return 73;
    if (code == 73 && snowAmount < snowMod) return 71;
    if (code == 86) return 85;
    if (moderateSnowOk && (code == 71 || code == 77 || code == 85)) return 73;
    return code;
  }

  // Búrky (95 / 96 / 99) — len pri živých bleskoch v okolí + silný lokálny signál.
  if ({95, 96, 99}.contains(code)) {
    if (preserveEcmwfThunderFromJson) return code;
    if (!_thunderIconWarranted(probPercent, precipMm, snowfallCm: snowfallCm)) {
      const rain = 61;
      return isDailyContext && precipMm > 0 && precipMm < _kModeratePrecipMmDaily
          ? lightDailyPrecipVisualCode(rain)
          : rain;
    }
    return code;
  }

  return code;
}

/// Pravdepodobnosť zrážok v UI — vždy po 10 %; **nikdy 0 % ani 5 %**.
/// Jasno min. 10 %; polooblačno/zamračené suché: 20–40 podľa radaru.
int _roundPrecipProbabilityForDisplay(int value) {
  if (value <= 0) return 10;
  if (value >= 100) return 100;
  final rounded = ((value / 10.0).round() * 10).clamp(10, 100);
  return rounded;
}

/// Minimálne % podľa oblohy — jasno 10; polooblačno 20; zamračené 30
/// (vyššie 40 podľa oblačnosti / API / radaru).
int hourlyStripSkyIconPercent(int iconCode, {double? cloudCoverPercent}) {
  final sky = normalizeDisplayWeatherCode(
    _stripSkyCodeForPercent(iconCode, cloudCoverPercent: cloudCoverPercent),
  );
  switch (sky) {
    case 0:
      return 10; // Jasno
    case 1:
      return 10; // Prevažne jasno
    case 2:
      return 20; // Polooblačno
    case 3:
    case 45:
    case 48:
      return 30; // Zamračené
    default:
      return 10;
  }
}

/// Tip % zo skutočnej oblačnosti — bez plánovaných zrážok max **30** (nie 40).
int _dryPercentHintFromCloudCover(double? cloudCoverPercent) {
  final c = cloudCoverPercent;
  if (c == null) return 10;
  if (c < 35) return 10;
  if (c < 55) return 20;
  return 30;
}

/// Suché % v 24 h — API + oblačnosť.
/// Bez zrážok v pláne: max **30**. Čisté jasno = 10. Nikdy flat 40.
int hourlyStripDryHourPercentFromApi({
  required int apiProbPercent,
  int radarApproachPercent = 0,
  int? iconCode,
  double? cloudCoverPercent,
  bool allowFortyNearRain = false,
}) {
  final sky = iconCode != null
      ? normalizeDisplayWeatherCode(iconCode)
      : null;

  if (sky == 0) return 10;

  final cloudHint = _dryPercentHintFromCloudCover(cloudCoverPercent);
  var pct = _roundPrecipProbabilityForDisplay(apiProbPercent);

  if (apiProbPercent <= 14) {
    pct = cloudHint;
  } else {
    if (pct < 10) pct = 10;
    // Suchá ikona — API ≥50 neznamená 40, keď nie sú zrážky na pine/v páse.
    if (pct >= kMinPrecipProbPercent) pct = 30;
    if ((cloudHint - pct).abs() >= 20) {
      pct = pct + (cloudHint > pct ? 10 : -10);
    }
  }

  // Prevažne jasno — max 20, okrem hodiny tesne pred zrážkou.
  if (sky == 1 && !allowFortyNearRain) {
    pct = math.min(pct, 20);
  }

  if (!allowFortyNearRain) {
    if (radarApproachPercent >= 25) {
      pct = math.max(pct, 30);
    } else if (radarApproachPercent >= 15) {
      pct = math.max(pct, 20);
    }
  }

  // Ďalšia hodina je zrážka → 40 %.
  if (allowFortyNearRain) {
    pct = math.max(pct, 40);
  }

  final cap = allowFortyNearRain ? 40 : 30;
  final floor = sky == 0
      ? 10
      : hourlyStripSkyIconPercent(
          iconCode ?? 0,
          cloudCoverPercent: cloudCoverPercent,
        );
  return _roundPrecipProbabilityForDisplay(pct.clamp(floor, cap));
}

/// Čisté jasno — len WMO 0 (slnko / mesiac bez oblaku).
bool _isClearStripSkyCode(int iconCode) {
  return normalizeDisplayWeatherCode(iconCode) == 0;
}

/// Bez blízkych zrážok: max 30. Hodina pred/po zrážke: **40**.
int _dryStripPercentWithNearbyRainCap({
  required int pct,
  required int? hoursUntilRain,
  required int? hoursSinceRain,
  required int radarApproachPercent,
  int? iconCode,
}) {
  if (iconCode != null && _isClearStripSkyCode(iconCode)) {
    return 10;
  }
  final nearIncoming = hoursUntilRain != null && hoursUntilRain <= 1;
  final justAfter = hoursSinceRain != null && hoursSinceRain == 1;
  final nearRain = nearIncoming || justAfter;
  var out = _roundPrecipProbabilityForDisplay(pct);
  if (nearRain) {
    out = 40;
  } else {
    out = out.clamp(10, 30);
    if (iconCode != null && normalizeDisplayWeatherCode(iconCode) == 1) {
      out = math.min(out, 20);
    }
  }
  return _roundPrecipProbabilityForDisplay(out);
}

/// Mokré mm v páse — keď sú zaseknuté v jednom bucketi, rozmeň podľa modelu / %.
void diversifyRepetitiveWetStripMm({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required List<int> stripIndices,
  required HourlyForecast h,
}) {
  final n = math.min(
    displayIcons.length,
    math.min(storedProbs.length, precipMm.length),
  );
  if (n == 0) return;

  final wetIdx = <int>[];
  for (var i = 0; i < n; i++) {
    if (showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i])) {
      wetIdx.add(i);
    }
  }
  if (wetIdx.length < 3) return;

  // Koľko rôznych textových bucketov? Ak ≤1, treba rozmanitosť.
  final buckets = wetIdx.map((i) => precipAmountRangeLabel(precipMm[i])).toSet();
  if (buckets.length >= 3) return;

  for (final i in wetIdx) {
    final idx = i < stripIndices.length ? stripIndices[i] : -1;
    final modelMm = idx >= 0 ? _ecmwfHourlyPrecipMm(h, idx) : 0.0;
    final fromProb = displayMmFromPrecipProbability(storedProbs[i]);
    var mm = precipMm[i];

    if (modelMm >= kMeaningfulPrecipMmPerHour) {
      mm = math.max(mm, modelMm);
    } else if (fromProb > mm) {
      mm = fromProb;
    }

    // Poradie v mokrom úseku → jemne posuň do 0-1 / 1-2 / 2-3.
    final rank = wetIdx.indexOf(i);
    final wave = (rank % 5);
    if (wave == 0) mm = math.max(mm, 0.4);
    if (wave == 1) mm = math.max(mm, 0.8);
    if (wave == 2) mm = math.max(mm, 1.3);
    if (wave == 3) mm = math.max(mm, 0.6);
    if (wave == 4) mm = math.max(mm, 2.1);

    // % 80+ → aspoň 1-2; 90+ → 2-3.
    if (storedProbs[i] >= 90) {
      mm = math.max(mm, 2.2);
    // ignore: curly_braces_in_flow_control_structures
    } else if (storedProbs[i] >= 80) mm = math.max(mm, 1.3);
    // ignore: curly_braces_in_flow_control_structures
    else if (storedProbs[i] >= 70) mm = math.max(mm, 0.9);

    precipMm[i] = mm.clamp(0.1, 8.0);
  }
}

/// Mokré % — keď je všade rovnakých 70, vráť API / klesajúcu škálu.
void diversifyRepetitiveWetStripPercents({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<double> precipMm,
  required List<int> stripIndices,
  required HourlyForecast h,
}) {
  final n = math.min(
    displayIcons.length,
    math.min(storedProbs.length, precipMm.length),
  );
  if (n == 0) return;

  final wetIdx = <int>[];
  for (var i = 0; i < n; i++) {
    if (showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i])) {
      wetIdx.add(i);
    }
  }
  if (wetIdx.length < 3) return;

  final probs = wetIdx.map((i) => storedProbs[i]).toSet();
  if (probs.length >= 3) return;

  for (var k = 0; k < wetIdx.length; k++) {
    final i = wetIdx[k];
    final idx = i < stripIndices.length ? stripIndices[i] : -1;
    final api = idx >= 0 &&
            h.precipitationProbability != null &&
            idx < h.precipitationProbability!.length
        ? roundPrecipProbPercent(h.precipitationProbability![idx] ?? 0)
        : 0;
    final fromMm = precipProbabilityFromMm(
      precipMm[i],
      precipWeatherCode: true,
      weatherCode: displayIcons[i],
    );

    var p = storedProbs[i];
    if (api >= kMinPrecipProbPercent) {
      p = api;
    } else if (fromMm >= kMinPrecipProbPercent) {
      p = fromMm;
    }

    // Keď je pás flat, použi vlnu 50–70 (nie 80–90 ďaleko dopredu).
    if (probs.length <= 1) {
      const wave = [60, 70, 60, 50, 70, 60, 50, 70, 60, 50];
      final target = wave[k % wave.length];
      if (api < kMinPrecipProbPercent) {
        p = target;
      } else {
        // API existuje — jemne odchýľ okolo neho podľa poradia, max 70.
        p = (api + (k % 3 - 1) * 10).clamp(50, 70);
      }
    }

    storedProbs[i] = _roundPrecipProbabilityForDisplay(p.clamp(50, 80));
  }
}

/// Suché % z API — bez umelého striedania každé 2–3 hodiny.
/// **Hneď po zrážkovej ikone = vždy 40 %** (nasledujúce okno).
void diversifyRepetitiveDryStripPercents({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<int> stripIndices,
  required HourlyForecast h,
  int rainHoursBeforeStrip = 0,
  RadarNowcastContext radarCtx = RadarNowcastContext.inactive,
  DateTime? locTime,
}) {
  final n = displayIcons.length;
  if (n == 0) return;

  final wetIcon = List<bool>.generate(
    n,
    (i) => showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i]),
  );

  var rainBefore = rainHoursBeforeStrip;
  if (locTime != null &&
      radarCtx.eligible &&
      (radarCtx.precipNow ||
          radarCtx.rainAtPinNow ||
          radarCtx.pinForecast.wetAtPinNow) &&
      rainBefore < 1) {
    rainBefore = 1;
  }

  // 1) Prepočítaj suché hodiny.
  for (var i = 0; i < n; i++) {
    if (wetIcon[i]) continue;
    if (storedProbs[i] >= kMinPrecipProbPercent) continue;

    final idx = stripIndices[i];
    final api = h.precipitationProbability != null &&
            idx < h.precipitationProbability!.length
        ? (h.precipitationProbability![idx] ?? 0)
        : storedProbs[i];
    final cloud = h.cloudCover != null && idx < h.cloudCover!.length
        ? h.cloudCover![idx]
        : null;
    final until = _hoursUntilNextRainInStrip(i, wetIcon);
    final since = _hoursSinceLastRainInStrip(
      i,
      wetIcon,
      rainHoursBeforeStrip: rainBefore,
    );
    // Hneď po zrážkovej ikone (alebo hero práve prší → 1. slot pásu).
    final justAfterRainIcon =
        (i > 0 && wetIcon[i - 1]) || (since != null && since == 1);
    final justBeforeRain = until != null && until <= 1;
    final nearRain = justAfterRainIcon || justBeforeRain;

    // Po zrážkovej ikone → vždy 40 (aj polooblačno / mesiac+oblak).
    // Čisté jasno (0) ostáva 10 podľa skoršieho pravidla.
    if (justAfterRainIcon && !_isClearStripSkyCode(displayIcons[i])) {
      storedProbs[i] = 40;
      continue;
    }

    var pct = hourlyStripDryHourPercentFromApi(
      apiProbPercent: api,
      iconCode: displayIcons[i],
      cloudCoverPercent: cloud,
      allowFortyNearRain: nearRain,
    );
    if (justBeforeRain && !_isClearStripSkyCode(displayIcons[i])) {
      pct = 40;
    } else {
      pct = _dryStripPercentWithNearbyRainCap(
        pct: pct,
        hoursUntilRain: until,
        hoursSinceRain: since,
        radarApproachPercent: 0,
        iconCode: displayIcons[i],
      );
      if (!nearRain) pct = math.min(pct, 30);
    }
    storedProbs[i] = pct;
  }
}

/// Rovnaká suchá ikona za sebou — plynulá postupka, žiadne skoky 20→10→20.
void alignDryStripPercentsForMatchingIcons({
  required List<int> displayIcons,
  required List<bool> showRainPrecip,
  required List<int> storedProbs,
  required List<int> stripIndices,
  required HourlyForecast h,
  int rainHoursBeforeStrip = 0,
}) {
  final n = displayIcons.length;
  if (n < 2) return;
  final wetIcon = List<bool>.generate(
    n,
    (i) => showRainPrecip[i] || _hourShowsPrecipIcon(displayIcons[i]),
  );

  for (var i = 1; i < n; i++) {
    if (wetIcon[i] || wetIcon[i - 1]) continue;
    if (storedProbs[i] >= kMinPrecipProbPercent) continue;
    if (storedProbs[i - 1] >= kMinPrecipProbPercent) continue;
    if (normalizeDisplayWeatherCode(displayIcons[i]) !=
        normalizeDisplayWeatherCode(displayIcons[i - 1])) {
      continue;
    }

    final since = _hoursSinceLastRainInStrip(
      i,
      wetIcon,
      rainHoursBeforeStrip: rainHoursBeforeStrip,
    );
    final until = _hoursUntilNextRainInStrip(i, wetIcon);
    // Rampy pred/po zrážke nechaj — tam má zmysel rásť/klesať.
    if (since != null && since <= 3) continue;
    if (until != null && until <= 3) continue;

    final idx = stripIndices[i];
    final cloud = h.cloudCover != null && idx < h.cloudCover!.length
        ? h.cloudCover![idx]
        : null;
    final floor = hourlyStripSkyIconPercent(
      displayIcons[i],
      cloudCoverPercent: cloud,
    );
    final prev = storedProbs[i - 1];
    var cur = storedProbs[i];
    // Blíži sa zrážka — povoliť rast po +10/h.
    if (until != null && until <= 3) {
      if (cur > prev) cur = math.min(cur, prev + 10);
      if (cur < prev) cur = math.max(cur, prev - 10);
    } else {
      // Po poklese neskákať späť hore (20→10→20).
      if (cur > prev && i >= 2 && prev < storedProbs[i - 2]) {
        cur = prev;
      } else {
        if (cur < prev) cur = math.max(cur, prev - 10);
        if (cur > prev) cur = math.min(cur, prev + 10);
      }
    }
    storedProbs[i] = _roundPrecipProbabilityForDisplay(
      math.max(cur, floor).clamp(10, 40),
    );
  }
}

/// Legacy — suché % podľa ikony; preferuj [hourlyStripDryHourPercentFromApi].
int hourlyStripDryCloudyPercentShown(int value) {
  return _roundPrecipProbabilityForDisplay(value.clamp(10, 30));
}

/// Legacy wrapper — API first.
int hourlyStripDryCloudyBasePercent({
  required int iconCode,
  double? cloudCoverPercent,
  int apiProbPercent = 0,
  int radarApproachPercent = 0,
}) =>
    hourlyStripDryHourPercentFromApi(
      apiProbPercent: apiProbPercent,
      radarApproachPercent: radarApproachPercent,
      iconCode: iconCode,
      cloudCoverPercent: cloudCoverPercent,
    );

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
      if (endAt != null && endAt.isBefore(firstSlotHour)) {
        lastRainHour = DateTime(
          endAt.year,
          endAt.month,
          endAt.day,
          endAt.hour,
        );
      }
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

  // Prší teraz, pás začína až od ďalšej hodiny — 1. slot je 1 h po daždi.
  if (gap == 0 &&
      radarCtx.eligible &&
      (radarCtx.precipNow || radarCtx.rainAtPinNow) &&
      firstSlotHour.isAfter(nowHour)) {
    final nextGap = firstSlotHour.difference(nowHour).inHours;
    if (nextGap >= 1 && nextGap <= 6) return nextGap;
  }
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
  int storedProb = 0,
}) {
  final clearSky = _isClearOrMostlyClearStripIcon(
    iconCode,
    cloudCoverPercent: cloudCoverPercent,
  );
  final pastRain = pastRainHour ?? isRainHour;
  final sinceRain = _hoursSinceLastRainInStrip(
    index,
    pastRain,
    rainHoursBeforeStrip: rainHoursBeforeStrip,
  );

  // Po daždi — dozvuk 40 → 30 → 20 (nie skok na jasno / 10 %).
  if (sinceRain != null && sinceRain >= 1 && sinceRain <= 3) {
    if (sinceRain == 1) return 40;
    if (sinceRain == 2) return 30;
    return 20;
  }

  final hoursUntil = _hoursUntilNextRainInStrip(index, isRainHour);

  if (!suppressApproachFloors) {
    if (hoursUntil != null && hoursUntil <= 3) {
      return _preRainApproachFloor(hoursUntil);
    }
  }

  final skyPct = hourlyStripCloudBaselinePercent(
    _stripSkyCodeForPercent(iconCode, cloudCoverPercent: cloudCoverPercent),
    cloudCoverPercent: cloudCoverPercent,
  );
  var capped = skyPct;
  if (storedProb <= 0 && hoursUntil != null && hoursUntil > 3) {
    capped = math.min(capped, _dryStripMaxPercentForRainDistance(hoursUntil));
  }
  if (clearSky) return capped;

  if (suppressApproachFloors) return math.min(capped, 20);

  if (storedProb > 0) {
    return math.max(
      capped,
      _roundPrecipProbabilityForDisplay(storedProb),
    );
  }
  return capped;
}

void _assignDryStripBlockPercents(
  List<int> result, {
  required List<bool> approachRainHour,
  required List<bool> rawRainHour,
  List<double>? precipMm,
  required List<int> storedProbs,
  required List<int> iconCodes,
  List<int?>? apiWeatherCodes,
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
    final stored = storedProbs[i];
    final suppress =
        suppressApproachFloors != null && suppressApproachFloors[i];
    final until = _hoursUntilNextRainInStrip(i, approachRainHour);
    final clearSky = _isClearOrMostlyClearStripIcon(
      iconCodes[i],
      cloudCoverPercent: cloud,
    );

    var pct = hourlyStripDryPercent(
      index: i,
      iconCode: iconCodes[i],
      isRainHour: approachRainHour,
      pastRainHour: decayPastRain,
      cloudCoverPercent: cloud,
      suppressApproachFloors: suppress,
      rainHoursBeforeStrip: rainHoursBeforeStrip,
      storedProb: stored,
    );
    final sinceRain = _hoursSinceLastRainInStrip(
      i,
      decayPastRain,
      rainHoursBeforeStrip: rainHoursBeforeStrip,
    );
    final inPostRainDecay =
        sinceRain != null && sinceRain >= 1 && sinceRain <= 3;

    if (stored > 0) {
      pct = math.max(
        pct,
        _roundPrecipProbabilityForDisplay(stored),
      );
    }

    if (!suppress && until != null && until <= 3) {
      if (clearSky) {
        if (until <= 1) pct = math.max(pct, 10);
      } else {
        pct = math.max(pct, _preRainApproachFloor(until));
      }
    } else if (!inPostRainDecay &&
        until != null &&
        until > 3 &&
        stored <= 0) {
      pct = math.min(pct, _dryStripMaxPercentForRainDistance(until));
    }

    result[i] = _roundPrecipProbabilityForDisplay(pct);
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
    return _roundPrecipProbabilityForDisplay(
      math.max(
        pct,
        skyPrecipChancePercentShown(
          weatherCode ?? 0,
          cloudCoverPercent: cloudCoverPercent,
        ),
      ),
    );
  }
  if (pct >= kMinPrecipProbPercent) {
    return _roundPrecipProbabilityForDisplay(pct);
  }
  return skyPrecipChancePercentShown(
    weatherCode ?? 0,
    cloudCoverPercent: cloudCoverPercent,
  );
}

/// Šanca zrážok pri oblačnosti bez dažďovej ikony — pre graf / denný riadok.
/// Nikdy 0 % — jasno 10; polooblačno/zamračené od 20 (radar môže 30/40 v páse).
int skyPrecipChancePercentShown(int iconCode, {double? cloudCoverPercent}) {
  final code = normalizeDisplayWeatherCode(iconCode);
  if (cloudCoverPercent != null) {
    if (cloudCoverPercent < 50) return 10;
    if (cloudCoverPercent < 80) return 20; // polooblačno
    return 30; // zamračené
  }
  switch (code) {
    case 0:
    case 1:
      return 10;
    case 2:
      return 20;
    case 3:
    case 45:
    case 48:
      return 30; // zamračené default; pás môže 20–40
    default:
      return 10;
  }
}


/// Oblačnostný WMO pre % — berie **zobrazenú** ikonu, nie surový 51–99 z API.
int _stripSkyCodeForPercent(int displayIconCode, {double? cloudCoverPercent}) {
  final code = normalizeDisplayWeatherCode(displayIconCode);
  if (kPrecipitationCodes.contains(code)) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }
  return code;
}

/// Jasno / prevažne jasno — nízka šanca zrážok, nie „prístupové“ 30–40 % pred dažďom.
bool _isClearOrMostlyClearStripIcon(
  int iconCode, {
  double? cloudCoverPercent,
}) {
  final sky = normalizeDisplayWeatherCode(
    _stripSkyCodeForPercent(iconCode, cloudCoverPercent: cloudCoverPercent),
  );
  if (sky == 0) return true;
  if (sky == 1) {
    return cloudCoverPercent == null || cloudCoverPercent < 35;
  }
  return false;
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
    case 3:
    case 45:
    case 48:
      return 20; // radar v páse môže zdvihnúť na 30/40
    default:
      return 0;
  }
}


/// Max. suché % podľa vzdialenosti dažďa — 4+ h vopred nie 40 %.
int _dryStripMaxPercentForRainDistance(int? hoursUntilRain) {
  if (hoursUntilRain == null) return 30;
  if (hoursUntilRain <= 3) return 100;
  if (hoursUntilRain <= 6) return 20;
  return 30;
}

/// Minimálne % podľa vzdialenosti dažďa — 3→2→1 h: 20→30→40 (stúpame k zrážke).
int _preRainApproachFloor(int? hoursUntilRain) {
  if (hoursUntilRain == null) return 0;
  if (hoursUntilRain <= 1) return 40;
  if (hoursUntilRain == 2) return 30;
  if (hoursUntilRain == 3) return 20;
  return 0;
}

/// Modelové hodiny s dažďom v 24 h pásme — nezávisle od radarovej autorizácie.
List<bool> hourlyStripEcmwfRainSignalHours({
  required List<int> storedProbs,
  required List<bool> showRainPrecip,
  required List<int> iconCodes,
  List<double>? precipMm,
}) {
  return List.generate(storedProbs.length, (i) {
    final mm = precipMm != null && i < precipMm.length ? precipMm[i] : 0.0;
    if (showRainPrecip[i]) return true;
    if (_hourShowsPrecipIcon(iconCodes[i])) return true;
    if (mm >= kMeaningfulPrecipMmPerHour) return true;
    return false;
  });
}

void _applyHourlyStripPrecipApproachSmoothing(
  List<int> percents, {
  required List<int> storedProbs,
  required List<bool> ecmwfRainSignal,
  List<bool>? pastRainHour,
  int rainHoursBeforeStrip = 0,
}) {
  final n = percents.length;
  for (var i = 0; i < n; i++) {
    final sinceRain = pastRainHour != null
        ? _hoursSinceLastRainInStrip(
            i,
            pastRainHour,
            rainHoursBeforeStrip: rainHoursBeforeStrip,
          )
        : null;
    final inPostRainDecay =
        sinceRain != null && sinceRain >= 1 && sinceRain <= 3;

    final until = _hoursUntilNextRainInStrip(i, ecmwfRainSignal);
    if (until != null && until <= 3) {
      percents[i] = math.max(percents[i], _preRainApproachFloor(until));
    } else if (!inPostRainDecay &&
        until != null &&
        until > 3 &&
        storedProbs[i] <= 0) {
      percents[i] = math.min(
        percents[i],
        _dryStripMaxPercentForRainDistance(until),
      );
    }
    if (storedProbs[i] > 0) {
      percents[i] = math.max(
        percents[i],
        _roundPrecipProbabilityForDisplay(storedProbs[i]),
      );
    }
    percents[i] = _roundPrecipProbabilityForDisplay(percents[i]);
  }
  for (var i = 0; i < n - 1; i++) {
    final until = _hoursUntilNextRainInStrip(i, ecmwfRainSignal);
    if (until != 1) continue;
    final nextPct = percents[i + 1];
    if (nextPct < kMinPrecipProbPercent) continue;
    final floor = _preRainApproachFloor(1);
    if (percents[i] < floor) {
      percents[i] = _roundPrecipProbabilityForDisplay(floor);
    }
  }
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
  if (hoursUntilNextRain != null && hoursUntilNextRain <= 3) {
    if (_isClearOrMostlyClearStripIcon(
      iconCode,
      cloudCoverPercent: cloudCoverPercent,
    )) {
      return hoursUntilNextRain <= 1 ? 10 : 10;
    }
    return _preRainApproachFloor(hoursUntilNextRain);
  }
  return hourlyStripSkyIconPercent(
    iconCode,
    cloudCoverPercent: cloudCoverPercent,
  );
}

/// % v paneli „24 h“ — priamo ECMWF / radar (po 10 %), bez odhadu z mm.
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
  final skyFloor = hourlyStripSkyIconPercent(
    iconCode,
    cloudCoverPercent: cloudCoverPercent,
  );
  if (radarOnlyPrecip && !showRainPrecip) {
    return math.max(storedProb > 0 ? storedProb : skyFloor, skyFloor);
  }

  if (showRainPrecip ||
      _hourShowsPrecipIcon(iconCode) ||
      precipMm >= kMeaningfulPrecipMmPerHour) {
    if (storedProb > 0) {
      return _roundPrecipProbabilityForDisplay(storedProb);
    }
    final derived = precipProbabilityFromMm(
      precipMm,
      precipWeatherCode: true,
      weatherCode: apiWeatherCode ?? iconCode,
      cloudCoverPercent: cloudCoverPercent,
    );
    if (derived >= kMinPrecipProbPercent) {
      return _roundPrecipProbabilityForDisplay(derived);
    }
    return kMinPrecipProbPercent;
  }

  return math.max(
    hourlyStripSkyBaselinePercent(
      iconCode: iconCode,
      storedProb: storedProb,
      cloudCoverPercent: cloudCoverPercent,
      hoursUntilNextRain: hoursUntilNextRain,
    ),
    skyFloor,
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
  final ecmwfRainSignal = hourlyStripEcmwfRainSignalHours(
    storedProbs: storedProbs,
    showRainPrecip: showRainPrecip,
    iconCodes: iconCodes,
    precipMm: precipMm,
  );
  final approachRainHour = List<bool>.from(ecmwfRainSignal);

  final suppressApproach = List<bool>.filled(n, false);
  final isRainHour = List<bool>.from(ecmwfRainSignal);
  if (radarCtx.eligible && locTime != null) {
    final globalSuppress =
        radarCtx.hourlyStripSuppressPhantomApproachPercents(locTime);
    final ecmwfWetAhead =
        storedProbs.any((p) => p >= kMinPrecipProbPercent);
    if (globalSuppress && !ecmwfWetAhead) {
      suppressApproach.fillRange(0, n, true);
    } else if (globalSuppress) {
      for (var i = 0; i < n; i++) {
        final until = _hoursUntilNextRainInStrip(i, approachRainHour);
        if (until == null || until > 4) {
          suppressApproach[i] = true;
        }
      }
    }
    if (slotHours != null) {
      for (var i = 0; i < n; i++) {
        if (i >= slotHours.length) continue;
        if (ecmwfRainSignal[i]) continue;
        isRainHour[i] = radarCtx.hourlyStripSlotCountsAsRainForApproach(
          slotHours[i],
          locTime,
          stripShowsRain: rawRainHour[i],
        );
        if (isRainHour[i]) approachRainHour[i] = true;
      }
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
        hoursUntilNextRain: _hoursUntilNextRainInStrip(i, approachRainHour),
        precipMm: mm,
        radarOnlyPrecip: radarOnlyPrecip,
      );
    }
  }

  if (!radarOnlyPrecip) {
    final pastRainForDecay = List<bool>.generate(
      n,
      (i) => rawRainHour[i] || isRainHour[i] || ecmwfRainSignal[i],
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
      approachRainHour: approachRainHour,
      rawRainHour: rawRainHour,
      precipMm: precipMm,
      storedProbs: storedProbs,
      iconCodes: iconCodes,
      apiWeatherCodes: apiWeatherCodes,
      cloudCoverPercents: cloudCoverPercents,
      showRainPrecip: showRainPrecip,
      suppressApproachFloors: suppressApproach,
      pastRainHour: pastRainForDecay,
      rainHoursBeforeStrip: beforeStrip,
    );
    _applyHourlyStripPrecipApproachSmoothing(
      result,
      storedProbs: storedProbs,
      ecmwfRainSignal: approachRainHour,
      pastRainHour: pastRainForDecay,
      rainHoursBeforeStrip: beforeStrip,
    );
  }

  for (var i = 0; i < n; i++) {
    result[i] = _roundPrecipProbabilityForDisplay(result[i]);
  }

  return result;
}

int? _hoursUntilNextRainInStrip(int i, List<bool> isRainHour) {
  if (i < 0 || i >= isRainHour.length) return null;
  for (var j = i + 1; j < isRainHour.length; j++) {
    if (isRainHour[j]) return j - i;
  }
  return null;
}

/// Percento v hodinovom stĺpci — dážď ≥ 50 % alebo oblačná šanca 10–40 % (nikdy 0).
int hourlyPrecipColumnPercentShown({
  required int rainProbPercent,
  required bool hourlyPrecipCode,
  required int iconCode,
  double? cloudCoverPercent,
  int? storedProbPercent,
  int? rawWeatherCode,
}) {
  final skyFloor = skyPrecipChancePercentShown(
    normalizeDisplayWeatherCode(rawWeatherCode ?? iconCode),
    cloudCoverPercent: cloudCoverPercent,
  );
  final stored = storedProbPercent ?? 0;
  if (stored > 0) {
    if (hourlyPrecipCode && stored >= kMinPrecipProbPercent) {
      return rainProbPercent >= kMinPrecipProbPercent
          ? rainProbPercent
          : stored;
    }
    if (stored < kMinPrecipProbPercent) {
      return hourlyPrecipCode
          ? kMinPrecipProbPercent
          : math.max(stored, skyFloor);
    }
  }

  if (hourlyPrecipCode && rainProbPercent >= kMinPrecipProbPercent) {
    return rainProbPercent;
  }
  if (hourlyPrecipCode) return kMinPrecipProbPercent;

  return skyFloor;
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

  speed ??= current?.windSpeed;
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

/// Pravdepodobnosť zrážok v UI — vždy po 10 % (0, 10, 20, …).
int roundPrecipProbPercent(int value) => _roundPrecipProbabilityForDisplay(value);

/// Zrážková ikona / stĺpec — podľa zaokrúhleného % (po 10).
bool precipProbShowsInUi(int rawProbPercent) =>
    roundPrecipProbPercent(rawProbPercent) >= kMinPrecipProbPercent;

/// Open-Meteo — zrážky pri % ≥ 50 a (mm ≥ 0,1 **alebo** WMO dážď/búrka z modela).
bool openMeteoHourlyWetShowsInUi({
  required int prob,
  required double mm,
  int? weatherCode,
}) {
  return hourlyPrecipIconWarranted(
    mm: mm,
    prob: prob,
    weatherCode: weatherCode,
  );
}

/// % pri ECMWF zrážke — max(API, odhad z mm), min. 50; môže 60 / 70 / 80+.
int ecmwfWetHourDisplayProbPercent({
  required int rawApiProb,
  required double precipMm,
  int? weatherCode,
  double? cloudCoverPercent,
}) {
  final fromApi = roundPrecipProbPercent(rawApiProb);
  final fromMm = precipProbabilityFromMm(
    precipMm,
    precipWeatherCode: true,
    weatherCode: weatherCode,
    cloudCoverPercent: cloudCoverPercent,
  );
  return math.max(math.max(fromApi, fromMm), kMinPrecipProbPercent);
}

/// Jediný zdroj pravdy pre hodinu z Open-Meteo API — ikona, %, mm, mokro/sucho.
({int displayIconCode, int displayProbPercent, double precipMm, bool showRainPrecip})
    openMeteoHourSlotUiFromApi({
  required HourlyForecast h,
  required int idx,
}) {
  if (idx < 0 || idx >= h.time.length) {
    return (
      displayIconCode: 0,
      displayProbPercent: 10,
      precipMm: 0.0,
      showRainPrecip: false,
    );
  }
  final rawProb = h.precipitationProbability?[idx] ?? 0;
  final rawMm = h.precipitation?[idx] ?? 0.0;
  final apiCode = h.weatherCode?[idx];
  final cloud = h.cloudCover?[idx];
  final displayProb = roundPrecipProbPercent(rawProb);
  final apiThunder = ecmwfJsonThunderHour(apiCode);
  // Model hlási búrku (95/96/99) → búrková ikona + % podľa API/mm (50+).
  if (apiThunder) {
    return (
      displayIconCode: normalizeDisplayWeatherCode(apiCode!),
      displayProbPercent: ecmwfWetHourDisplayProbPercent(
        rawApiProb: rawProb,
        precipMm: rawMm,
        weatherCode: apiCode,
        cloudCoverPercent: cloud,
      ),
      precipMm: rawMm,
      showRainPrecip: true,
    );
  }
  final wet = openMeteoHourlyWetShowsInUi(
    prob: rawProb,
    mm: rawMm,
    weatherCode: apiCode,
  );

  final tempC = h.temperature?[idx];
  final int displayIconCode;
  final int displayProbPercent;
  if (wet) {
    final normalized = normalizeDisplayWeatherCode(apiCode ?? 0);
    final rawIcon = kPrecipitationCodes.contains(normalized)
        ? normalized
        : wmoFromPrecipitationMm(rawMm, cloudCoverPercent: cloud);
    // 24 h: ≥5 mm → silný dážď; pri ≤0 °C sneh podľa cm (mm≈cm).
    displayIconCode = hourlyStripPrecipIntensityIcon(
      baseCode: rawIcon,
      precipMm: rawMm,
      tempC: tempC,
    );
    displayProbPercent = ecmwfWetHourDisplayProbPercent(
      rawApiProb: rawProb,
      precipMm: rawMm,
      weatherCode: apiCode,
      cloudCoverPercent: cloud,
    );
  } else {
    displayIconCode = openMeteoHourlyDisplayIconCode(
      storedWeatherCode: apiCode,
      precipMm: 0,
      storedPrecipProbPercent: displayProb,
      cloudCoverPercent: cloud,
    );
    final skyFloor = hourlyStripSkyIconPercent(
      displayIconCode,
      cloudCoverPercent: cloud,
    );
    // Suchá ikona: % z API (variácia), nie flat skyFloor 30 na zamračené.
    displayProbPercent = hourlyStripDryHourPercentFromApi(
      apiProbPercent: displayProb < 10 ? skyFloor : displayProb,
      iconCode: displayIconCode,
      cloudCoverPercent: cloud,
    );
  }

  // mm presne z API — žiadne umelé mm z %.
  final slotMm = wet ? rawMm : 0.0;

  return (
    displayIconCode: displayIconCode,
    displayProbPercent: displayProbPercent,
    precipMm: slotMm,
    showRainPrecip: wet,
  );
}

/// 24 h pás — rovnaké pravidlo ako Open-Meteo web/app.
bool hourlyStripWetFromOpenMeteo(
  HourlyForecast h,
  int idx, {
  List<bool>? tailTrimMask,
}) =>
    openMeteoHourlyWetShowsInUi(
      prob: h.precipitationProbability?[idx] ?? 0,
      mm: h.precipitation?[idx] ?? 0.0,
      weatherCode: h.weatherCode?[idx],
    );

/// 24 h pás — zrážková ikona aj pri budúcich hodinách (šanca ≥ 50 % + WMO alebo odhad z %).
bool hourlyPrecipIconWarranted({
  required double mm,
  required int prob,
  int? weatherCode,
}) {
  final roundedProb = roundPrecipProbPercent(prob);
  if (ecmwfHourPrecipShowsInUi(mm: mm, prob: prob)) return true;
  if (roundedProb < kMinPrecipProbPercent) return false;
  if (weatherCode != null &&
      kPrecipitationCodes.contains(normalizeDisplayWeatherCode(weatherCode))) {
    return true;
  }
  return displayMmFromPrecipProbability(roundedProb) >= kMeaningfulPrecipMmPerHour;
}

/// Alias pre existujúce volania (weather_code sa nepoužíva ako jediný signál).
bool hourlyHourShowsPrecipInUi({
  required double mm,
  required int prob,
  int? weatherCode,
}) =>
    hourlyPrecipIconWarranted(mm: mm, prob: prob, weatherCode: weatherCode);

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
  // Používa sa v UI na zladenie s prahmi, ale v tomto helperi ho nepotrebujeme.
  int? daysFromToday,
}) => math.max(dailyApiProb, math.max(hourlyStripMaxProb, hourlyDayMaxProb));

/// Prah šance zrážok v dennej predpovedi — bližšie dni prísnejšie, ďalej miernejšie.
int dailyForecastPrecipProbThreshold(int daysFromToday) {
  if (daysFromToday <= 1) return kMinPrecipProbPercent;
  if (daysFromToday <= 4) return 45;
  return 40;
}

/// Hodina v dennej predpovedi — mm aj šanca nad prahom; holý WMO bez mm nestačí.
bool dailyForecastHourShowsPrecipInUi({
  required double mm,
  required int prob,
  int? weatherCode,
  required int daysFromToday,
  double snowfallCm = 0,
}) {
  if (snowfallCm >= 0.1) return true;
  final threshold = math.max(
    dailyForecastPrecipProbThreshold(daysFromToday),
    kMinPrecipProbPercent,
  );
  return mm >= kMeaningfulPrecipMmPerHour && prob >= threshold;
}

/// Celý deň v 10-dňovej predpovedi — zobraziť zrážkové ikony aj bez mm ≥ 0,1 v každej hodine.
bool dailyForecastWetDayWarranted({
  required int dailyApiProb,
  required double apiDailyPrecip,
  required double apiDailySnow,
  int? dailyWeatherCode,
  HourlyForecast? hourly,
  required String dateStr,
  required int daysFromToday,
}) {
  if (apiDailySnow >= 0.1) return true;
  final threshold = dailyForecastPrecipProbThreshold(daysFromToday);
  final maxHourlyProb = hourlyDayMaxPrecipProb(hourly, dateStr);
  final effectiveProb = math.max(dailyApiProb, maxHourlyProb);
  if (effectiveProb < threshold) return false;
  if (apiDailyPrecip >= kMeaningfulPrecipMmPerHour) return true;
  final code = dailyWeatherCode != null
      ? normalizeDisplayWeatherCode(dailyWeatherCode)
      : 0;
  if (kPrecipitationCodes.contains(code) &&
      effectiveProb >= kMinPrecipProbPercent &&
      apiDailyPrecip >= kMeaningfulPrecipMmPerHour) {
    return true;
  }
  if (hourly != null) {
    for (var i = 0; i < hourly.time.length; i++) {
      if (!hourly.time[i].startsWith(dateStr)) continue;
      final mm = hourly.precipitation?[i] ?? 0.0;
      final prob = hourly.precipitationProbability?[i] ?? 0;
      final wc = hourly.weatherCode?[i];
      if (dailyForecastHourShowsPrecipInUi(
        mm: mm,
        prob: prob,
        weatherCode: wc,
        daysFromToday: daysFromToday,
      )) {
        return true;
      }
    }
  }
  return effectiveProb >= kMinPrecipProbPercent &&
      apiDailyPrecip >= kMeaningfulPrecipMmPerHour;
}

/// Ikony dennej karty len pri dôveryhodnom signáli — sedí s pätičkou (mm / %).
bool dailyCardShowsWetPrecip({
  required double trustedMm,
  required int trustedProb,
  double snowfallCm = 0,
}) {
  if (snowfallCm >= 0.1) return true;
  return trustedMm >= kMeaningfulPrecipMmPerHour &&
      trustedProb >= kMinPrecipProbPercent;
}

int dailyCardIconDryUnlessTrusted(
  int code,
  double trustedMm,
  int trustedProb, {
  double? cloudCover,
  double snowfallCm = 0,
}) {
  if (dailyCardShowsWetPrecip(
    trustedMm: trustedMm,
    trustedProb: trustedProb,
    snowfallCm: snowfallCm,
  )) {
    return code;
  }
  if (!kPrecipitationCodes.contains(normalizeDisplayWeatherCode(code))) {
    return code;
  }
  return skyWmoFromCloudCover(cloudCover);
}

/// Capping zrážkovej ikony podľa „dôveryhodného“ denného mm.
///
/// Používa sa v UI (hero + day-parts), aby silná ikona nevznikla iba z modelových
/// hodín, keď denný súčet reálne nedosiahne prahy.
int capPrecipIconByTrustedMm(
  int iconCode, {
  required double trustedMm,
  double? partMm,
}) {
  final c = normalizeDisplayWeatherCode(iconCode);
  final effectiveTrustedMm = partMm != null ? math.min(trustedMm, partMm) : trustedMm;

  // Búrka je konvekcia — držíme ikonu (damping rieši pipeline okolo).
  if ({95, 96, 99}.contains(c)) return iconCode;

  // Silný dážď/sneh: až pri ~15 mm/deň.
  if ({65, 75}.contains(c) && effectiveTrustedMm < _kHeavyPrecipMmDaily) {
    return c == 75 ? 73 : 63;
  }

  // Mierny dážď/sneh: až pri ~10 mm/deň.
  if ({63, 67, 73}.contains(c) && effectiveTrustedMm < _kModeratePrecipMmDaily) {
    return switch (c) {
      73 => 71,
      67 => 61,
      _ => 61,
    };
  }

  // Slabý/stopa: ak ani „zmysluplná“ zrážka nedošla, zníž na stopu.
  if ({61, 71}.contains(c) && effectiveTrustedMm < kMeaningfulPrecipMmPerHour) {
    return 51;
  }

  return iconCode;
}

/// mm pre intenzitu dennej ikony — pri vysokej šanci doplní odhad z %.
double dailyPrecipMmForIconDisplay({
  required double apiDailyPrecip,
  required double hourlySumMm,
  required int effectiveDailyProb,
  required int daysFromToday,
}) {
  final base = dailyPrecipMmForIconIntensity(
    apiDailyPrecip: apiDailyPrecip,
    hourlySumMm: hourlySumMm,
  );
  if (base >= kMeaningfulPrecipMmPerHour) return base;
  if (effectiveDailyProb >= kMinPrecipProbPercent) {
    return math.max(base, displayMmFromPrecipProbability(effectiveDailyProb));
  }
  return base;
}

/// WMO v dennej predpovedi — zrážkový kód pri šanci nad prahom aj bez mm ≥ 0,1.
int weatherCodeForDailyForecastThreshold(
  int code, {
  required int probPercent,
  double precipMm = 0,
  double? cloudCoverPercent,
  required int daysFromToday,
  double snowfallCm = 0,
}) {
  final normalized = normalizeDisplayWeatherCode(code);
  if (kPrecipitationCodes.contains(normalized) &&
      !dailyForecastHourShowsPrecipInUi(
        mm: precipMm,
        prob: probPercent,
        weatherCode: code,
        daysFromToday: daysFromToday,
        snowfallCm: snowfallCm,
      )) {
    return skyWmoFromCloudCover(cloudCoverPercent);
  }
  return normalized;
}

/// Súčet mm a max % pre dennú predpoveď — uvoľnené pravidlo oproti 24 h pásmu.
({double sumMm, int maxProb, bool any}) dayShowablePrecipForDailyForecast(
  HourlyForecast? h,
  String dateStr, {
  required int daysFromToday,
  HourlyStripDisplayState? stripState,
}) {
  if (h == null || h.time.isEmpty) {
    return (sumMm: 0.0, maxProb: 0, any: false);
  }

  // Keď máme už „UI“ verziu pásma (s radarom / orezom), použijeme mm a % z nej,
  // nie surové hodnoty z h.
  if (stripState != null) {
    var sum = 0.0;
    var maxProb = 0;
    var any = false;

    for (final entry in stripState.probs.entries) {
      final idx = entry.key;
      if (idx < 0 || idx >= h.time.length) continue;
      if (!h.time[idx].startsWith(dateStr)) continue;

      final mm = stripState.precipMm[idx] ?? h.precipitation?[idx] ?? 0.0;
      final prob = entry.value;

      // Rovnaké rozhodnutie ako v implementácii pre raw data.
      if (!dailyForecastHourShowsPrecipInUi(
        mm: mm,
        prob: prob,
        weatherCode: null,
        daysFromToday: daysFromToday,
      )) {
        continue;
      }

      any = true;
      sum += mm >= kMeaningfulPrecipMmPerHour
          ? mm
          : displayMmFromPrecipProbability(prob);
      if (prob > maxProb) maxProb = prob;
    }

    return (sumMm: sum, maxProb: maxProb, any: any);
  }

  var sum = 0.0;
  var maxProb = 0;
  var any = false;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(dateStr)) continue;
    final mm = h.precipitation?[i] ?? 0.0;
    final prob = h.precipitationProbability?[i] ?? 0;
    final wc = h.weatherCode?[i];
    if (!dailyForecastHourShowsPrecipInUi(
      mm: mm,
      prob: prob,
      weatherCode: wc,
      daysFromToday: daysFromToday,
    )) {
      continue;
    }
    any = true;
    sum += mm >= kMeaningfulPrecipMmPerHour
        ? mm
        : displayMmFromPrecipProbability(prob);
    if (prob > maxProb) maxProb = prob;
  }
  return (sumMm: sum, maxProb: maxProb, any: any);
}

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

/// Súčet mm len z hodín, ktoré by v UI ukázali zrážky (mm aj % nad prahom).
double ecmwfDayUiPrecipSumMm(HourlyForecast? h, String dateStr) {
  if (h == null || h.time.isEmpty) return 0.0;
  var sum = 0.0;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(dateStr)) continue;
    final mm = h.precipitation?[i] ?? 0.0;
    final prob = h.precipitationProbability?[i] ?? 0;
    if (!ecmwfHourPrecipShowsInUi(mm: mm, prob: prob)) continue;
    sum += mm;
  }
  return sum;
}

/// Max % len z hodín s reálnym dažďovým signálom v UI.
int hourlyDayUiMaxPrecipProb(HourlyForecast? h, String dateStr) {
  if (h == null || h.time.isEmpty) return 0;
  var maxP = 0;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(dateStr)) continue;
    final mm = h.precipitation?[i] ?? 0.0;
    final prob = h.precipitationProbability?[i] ?? 0;
    if (!ecmwfHourPrecipShowsInUi(mm: mm, prob: prob)) continue;
    if (prob > maxP) maxP = prob;
  }
  return maxP;
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

/// Viditeľné úseky dňa (ráno/poobede/…) nemajú mokré ikony.
bool dayPartIconCodesAllDry(Iterable<int?> codes) {
  for (final raw in codes) {
    if (raw == null || raw <= 0) continue;
    if (kPrecipitationCodes.contains(normalizeDisplayWeatherCode(raw))) {
      return false;
    }
  }
  return true;
}

/// Denný API úhrn/šanca platí len s hodinovou podporou (mm aj % nad prahom).
bool dailyApiWetClaimCorroboratedByHourly({
  required double apiDailyPrecip,
  required int dailyApiProb,
  HourlyForecast? hourly,
  required String dateStr,
  double expandedSumMm = 0,
  double partsSumMm = 0,
}) {
  if (expandedSumMm >= kMeaningfulPrecipMmPerHour ||
      partsSumMm >= kMeaningfulPrecipMmPerHour) {
    return true;
  }
  final uiSum = ecmwfDayUiPrecipSumMm(hourly, dateStr);
  final uiProb = hourlyDayUiMaxPrecipProb(hourly, dateStr);
  return uiSum >= kMeaningfulPrecipMmPerHour &&
      uiProb >= kMinPrecipProbPercent;
}

double trustedDailyApiPrecipMm({
  required double apiDailyPrecip,
  required int dailyApiProb,
  HourlyForecast? hourly,
  required String dateStr,
  double expandedSumMm = 0,
  double partsSumMm = 0,
}) {
  if (apiDailyPrecip < kMeaningfulPrecipMmPerHour) return 0.0;
  if (!dailyApiWetClaimCorroboratedByHourly(
    apiDailyPrecip: apiDailyPrecip,
    dailyApiProb: dailyApiProb,
    hourly: hourly,
    dateStr: dateStr,
    expandedSumMm: expandedSumMm,
    partsSumMm: partsSumMm,
  )) {
    return 0.0;
  }
  return apiDailyPrecip;
}

int trustedDailyApiPrecipProb({
  required int dailyApiProb,
  HourlyForecast? hourly,
  required String dateStr,
  int expandedMaxProb = 0,
  double partsSumMm = 0,
}) {
  final uiMaxProb = hourlyDayUiMaxPrecipProb(hourly, dateStr);
  if (expandedMaxProb >= kMinPrecipProbPercent ||
      partsSumMm >= kMeaningfulPrecipMmPerHour) {
    return math.max(expandedMaxProb, uiMaxProb);
  }
  return uiMaxProb;
}

/// Pätička dennej karty — sedí s ikonami; bez falošných mm z API/latch.
({double mm, int prob}) resolveDailyCardFooterPrecip({
  required bool partIconsAllDry,
  required int dailyMainIconCode,
  required double apiDailySnow,
  required double expandedSumMm,
  required int expandedMaxProb,
  required double partsSumMm,
  HourlyForecast? hourly,
  required String dateStr,
  required double apiDailyPrecip,
  required int dailyApiProb,
  double latchedDailyMm = 0,
  int latchedDailyProb = 0,
  int? daysFromToday,
}) {
  final mainDry =
      !kPrecipitationCodes.contains(normalizeDisplayWeatherCode(dailyMainIconCode));
  if (partIconsAllDry && mainDry) {
    return (
      mm: 0.0,
      prob: hourlyStripSkyIconPercent(dailyMainIconCode),
    );
  }

  final uiEcmwfMm = ecmwfDayUiPrecipSumMm(hourly, dateStr);
  final uiMaxProb = hourlyDayUiMaxPrecipProb(hourly, dateStr);
  final trustedApiMm = trustedDailyApiPrecipMm(
    apiDailyPrecip: apiDailyPrecip,
    dailyApiProb: dailyApiProb,
    hourly: hourly,
    dateStr: dateStr,
    expandedSumMm: expandedSumMm,
    partsSumMm: partsSumMm,
  );
  final trustedApiProb = trustedDailyApiPrecipProb(
    dailyApiProb: dailyApiProb,
    hourly: hourly,
    dateStr: dateStr,
    expandedMaxProb: expandedMaxProb,
    partsSumMm: partsSumMm,
  );
  final trustedLatchMm = dailyApiWetClaimCorroboratedByHourly(
            apiDailyPrecip: latchedDailyMm,
            dailyApiProb: latchedDailyProb,
            hourly: hourly,
            dateStr: dateStr,
            expandedSumMm: expandedSumMm,
            partsSumMm: partsSumMm,
        )
      ? latchedDailyMm
      : 0.0;
  final trustedLatchProb =
      trustedLatchMm >= kMeaningfulPrecipMmPerHour ? latchedDailyProb : 0;

  final mm = resolveDailyCardPrecipDisplayMm(
    apiDailyPrecip: trustedApiMm,
    expandedSumMm: expandedSumMm,
    partsSumMm: partsSumMm,
    ecmwfHourlyDaySumMm: uiEcmwfMm,
    latchedPrecipMm: trustedLatchMm,
  );
  final prob = math.max(
    trustedLatchProb,
    math.max(trustedApiProb, math.max(expandedMaxProb, uiMaxProb)),
  );
  if (apiDailySnow >= 0.1) {
    return (
      mm: math.max(mm, trustedApiMm),
      prob: math.max(prob, trustedApiProb),
    );
  }
  return (mm: mm, prob: prob);
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
  int? utcOffsetSeconds,
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
  if ({95, 96, 99}.contains(c)) {
    return hourlyThunderStripDisplayMm(
      iconCode: c,
      probPercent: prob,
      ecmwfMm: 0,
    );
  }
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
  int? daysFromToday,
}) {
  // Sneženie — nikdy nepotláčaj mokré ikony podľa surového API dažďa.
  if (apiDailySnow >= 0.1) return false;

  if (daysFromToday != null &&
      dailyForecastWetDayWarranted(
        dailyApiProb: dailyApiProb,
        apiDailyPrecip: apiDailyPrecip,
        apiDailySnow: apiDailySnow,
        dailyWeatherCode: dailyWeatherCode,
        hourly: h,
        dateStr: dateStr,
        daysFromToday: daysFromToday,
      )) {
    return false;
  }

  // Surový denný API súčet / latch / WMO bez hodinovej podpory nestačí na mokrý deň.
  if (h != null) {
    final hourlySum = ecmwfDayUiPrecipSumMm(h, dateStr);
    final hourlyMaxProb = hourlyDayUiMaxPrecipProb(h, dateStr);
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
  int? daysFromToday,
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

  if (daysFromToday != null) {
    final precipCode = kPrecipitationCodes.contains(
      normalizeDisplayWeatherCode(rawCode),
    );
    final prob = hourlyPrecipProbabilityPercentShown(
      rawProb,
      precipCode,
      precipMm: rawPrecip,
      weatherCode: rawCode,
    );
    final mmForIcon = rawPrecip >= kMeaningfulPrecipMmPerHour
        ? rawPrecip
        : (dailyForecastHourShowsPrecipInUi(
                mm: rawPrecip,
                prob: prob,
                weatherCode: rawCode,
                daysFromToday: daysFromToday,
              )
            ? displayMmFromPrecipProbability(prob)
            : rawPrecip);
    final code = weatherCodeForDailyForecastThreshold(
      rawCode,
      probPercent: prob,
      precipMm: mmForIcon,
      cloudCoverPercent: cloudCoverPercent,
      daysFromToday: daysFromToday,
    );
    return ProcessedWeather(code, prob, mmForIcon);
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

