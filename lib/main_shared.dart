part of 'main.dart';

// --- KONŠTANTY A NASTAVENIA ---
/// Predvoľba numerického modelu - oficiálny ECMWF IFS cez Copernicus CDS.
enum WeatherForecastModel {
  /// ECMWF IFS - jediný oficiálny model zo ECMWF.
  ecmwf._('ecmwf_ifs', 'ECMWF IFS', 'Globálny model Európskeho strediska pre predpovede počasia (IFS).');

  /// Kľúč cache (`CacheManager`).
  final String cacheKey;

  final String uiTitle;
  final String uiSubtitle;

  const WeatherForecastModel._(this.cacheKey, this.uiTitle, this.uiSubtitle);

  static WeatherForecastModel fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return WeatherForecastModel.ecmwf;
    for (final v in WeatherForecastModel.values) {
      if (v.cacheKey == raw) return v;
    }
    return WeatherForecastModel.ecmwf;
  }
}

/// Dĺžka dennej predpovede (ECMWF, graf, zoznam dní na domovskej obrazovke).
const int kForecastDays = 5; // ECMWF Open Data poskytuje ~5 dní predpovede

const int kEcmwfForecastDays = kForecastDays;
const int kChartForecastDays = kForecastDays;

/// Kľúč cache predpovede — musí obsahovať počet dní, inak ostane stará 10-dňová cache.
String forecastWeatherCacheKey(WeatherForecastModel model) =>
    '${model.cacheKey}_fd$kForecastDays';

String forecastWeatherCacheKeyForModelId(String modelId) {
  if (modelId.isEmpty) {
    return forecastWeatherCacheKey(WeatherForecastModel.ecmwf);
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

bool forecastDailyHorizonComplete(WeatherData? data) {
  final times = data?.daily?.time;
  if (times == null || times.isEmpty) return false;
  return times.length >= kForecastDays;
}
const String kForecastModelKey = 'forecast_model_v1';

const String kOnboardingDoneKey = 'onboarding_playstore_fix';

// ECMWF CDS (Copernicus Data Store) API - oficiálny zdroj
const String kEcmwfCdsApi = 'https://cds.climate.copernicus.eu/api/v2';
const String kEcmwfApiKey = 'ECMWF_API_KEY'; // Uložené v secure storage

// Geocoding zostáva na Open-Meteo (je to samostatná služba)
const String kGeoApi = 'https://geocoding-api.open-meteo.com/v1';

// Air quality cez Copernicus CAMS
const String kAirQualityApi = 'https://ads.atmosphere.copernicus.eu/api/v2';

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
  73: {'icon_day': 'assets/snow.svg', 'icon_night': 'assets/snow.svg', 'description': 'mierne sneženie'},
  75: {'icon_day': 'assets/snow.svg', 'icon_night': 'assets/snow.svg', 'description': 'silné sneženie'},
  77: {'icon_day': 'assets/snow-drizzle.svg', 'icon_night': 'assets/snow-drizzle.svg', 'description': 'snehové zrná'},
  80: {'icon_day': 'assets/drizzle.svg', 'icon_night': 'assets/drizzle.svg', 'description': 'slabé prehánky'},
  81: {'icon_day': 'assets/rain.svg', 'icon_night': 'assets/rain.svg', 'description': 'mierne prehánky'},
  82: {'icon_day': 'assets/rain.svg', 'icon_night': 'assets/rain.svg', 'description': 'prudký dážď'},
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

final Set<int> kPrecipitationCodes = {
  51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99,
};

/// „Silný“ vizuál (dažď, sneh) pri vyššej šanci a mm — zoslabenie WMO stupňa; búrky (95–99) výnimka (konvekcia).
const int _kHeavyPrecipProbMin = 65;
const double _kHeavyPrecipMmDaily = 12.0;
const double _kHeavyPrecipMmBlockSum = 4.0;
const int _kModeratePrecipProbMin = 55;
const double _kModeratePrecipMmDaily = 5.0;
const double _kModeratePrecipMmBlockSum = 2.0;

/// Po výbere ikony podľa prahu zrážok upraví intenzitu tak, aby napr. 8 mm / 50 % nevyzeralo ako silný lejak vo všetkých blokoch.
int _clampPrecipitationIconIntensity(
  int code,
  int probPercent,
  double precipMm,
  {required bool isDailyContext, double snowfallCm = 0.0}
) {
  if (_belowMeaningfulPrecipAmountForIcon(precipMm, snowfallCm) &&
      kPrecipitationCodes.contains(code)) {
    if (_precipIconShowsForHour(
      probPercent,
      precipMm,
      snowfallCm,
      wmoPrecipCode: true,
    )) {
      return _lightPrecipDisplayCode(code);
    }
    return _drySkyIconTierFromModel(
      precipProbabilityPercent: probPercent,
      hourlyPrecipitationMm: precipMm,
      cloudCoverPercent: null,
    );
  }

  if (!kPrecipitationCodes.contains(code)) return code;

  final mmHeavy = isDailyContext ? _kHeavyPrecipMmDaily : _kHeavyPrecipMmBlockSum;
  final mmMod = isDailyContext ? _kModeratePrecipMmDaily : _kModeratePrecipMmBlockSum;
  final heavyOk = probPercent >= _kHeavyPrecipProbMin && precipMm >= mmHeavy;
  if (heavyOk) return code;

  final moderateOk = probPercent >= _kModeratePrecipProbMin && precipMm >= mmMod;

  if (code == 67 && !heavyOk) return 66;

  if ({61, 63, 65, 80, 81, 82}.contains(code)) {
    if (!moderateOk) {
      if (code == 82 || code == 81 || code == 80) return 80;
      if (code == 65 || code == 63 || code == 61) return 61;
      return code;
    }
    if (code == 82) return 81;
    if (code == 65) return 63;
    return code;
  }

  // Sneženie, snehové mrholenie (56–57), zrná (77), prehánky (85–86) — tie isté prahy % / mm ako pri daždi.
  if ({56, 57, 71, 73, 75, 77, 85, 86}.contains(code)) {
    if (!moderateOk) {
      if (code == 86) return 85;
      if ({75, 73, 85, 77}.contains(code)) return 71;
      if (code == 57) return 56;
      return code;
    }
    if (code == 57) return 56;
    if (code == 75) return 73;
    if (code == 86) return 85;
    if (code == 73) return 71;
    return code;
  }

  // Búrky (95 / 96 / 99) — len pri vyššej šanci a merateľnej zrážke (mm alebo cm snehu).
  if ({95, 96, 99}.contains(code)) {
    if (!_thunderIconWarranted(probPercent, precipMm, snowfallCm: snowfallCm)) {
      return _drySkyIconTierFromModel(
        precipProbabilityPercent: probPercent,
        hourlyPrecipitationMm: precipMm,
        cloudCoverPercent: null,
      );
    }
    return code;
  }

  return code;
}

/// Pravdepodobnosť zrážok v UI po 10 % (50, 60, 70 …), nie hodnoty ako 52 alebo 58.
int _roundPrecipProbabilityForDisplay(int value) {
  if (value <= 0) return 0;
  if (value >= 100) return 100;
  return ((value / 10.0).round() * 10).clamp(0, 100);
}

/// Hodinovka: zhoda ikony bez zrážkového WMO z váženého zmiešania — také sloty nesmú ukazovať „50 %+“ (po desiatkach najviac 40 %).
/// So zrážkovým kódom: klasické zaokrúhlenie na 10 %; pod prahom dažďovej ikony (raw < 50) neklamať „50 %“ pri 46–49.
int _hourlyPrecipProbabilityPercentShown(int rawProbPercent, bool hourlyPrecipCode) {
  if (!hourlyPrecipCode) {
    final capped = rawProbPercent.clamp(0, 49);
    return (capped ~/ 10) * 10;
  }
  final precipIconShows = rawProbPercent >= 40;
  final rounded = _roundPrecipProbabilityForDisplay(rawProbPercent);
  if (!precipIconShows && rounded >= 40) {
    return (rawProbPercent ~/ 10) * 10;
  }
  return rounded;
}

class ProcessedWeather {
  final int code;
  final int prob;
  final double precip;
  ProcessedWeather(this.code, this.prob, this.precip);
}

/// Bez úprav WMO kódu z modela — stará logika umelo menila jasno/oblačno podľa %
/// a dokázala rozbiť zmysel váženého zmiešania oproti surovým výstupom API.
ProcessedWeather _processWeather(int rawCode, int rawProb, double rawPrecip, {bool isHourly = false, String? timeStr}) {
  return ProcessedWeather(rawCode, _roundPrecipProbabilityForDisplay(rawProb), rawPrecip);
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
