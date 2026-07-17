part of 'main.dart';

class CacheManager {
  static String _getKey(String prefix, double lat, double lon) {
    return '$prefix${lat.toStringAsFixed(3)}_${lon.toStringAsFixed(3)}';
  }

  static String _weatherCacheKey(String modelParam, double lat, double lon) {
    return '$kWeatherCachePrefix${modelParam}_${lat.toStringAsFixed(3)}_${lon.toStringAsFixed(3)}';
  }

  static Future<void> saveWeather(double lat, double lon, String modelParam, String jsonBody) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _weatherCacheKey(modelParam, lat, lon);
    final data = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'body': jsonBody,
    };
    await prefs.setString(key, json.encode(data));
  }

  /// Uloží [WeatherData] so schémou — staré cache bez verzie sa pri načítaní zahodia.
  static String encodeForecastWeatherBody(WeatherData data) {
    final body = Map<String, dynamic>.from(data.toJson());
    body['schema_version'] = kForecastCacheSchemaVersion;
    return json.encode(body);
  }

  static WeatherData? decodeForecastWeatherBody(String? jsonBody) {
    if (jsonBody == null) return null;
    try {
      final decoded = json.decode(jsonBody);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['schema_version'] != kForecastCacheSchemaVersion) {
        return null;
      }
      return WeatherData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Po zmene schémy cache — zmaže všetky uložené predpovede (staré vymyslené mm/%).
  /// Vráti `true`, ak sa cache práve vymazala (treba `forceRefresh`).
  static Future<bool> ensureForecastCacheGeneration() async {
    final prefs = await SharedPreferences.getInstance();
    const flag = 'forecast_cache_gen_v$kForecastCacheSchemaVersion';
    if (prefs.getBool(flag) == true) return false;

    final toRemove =
        prefs.getKeys().where((k) => k.startsWith(kWeatherCachePrefix)).toList();
    for (final k in toRemove) {
      await prefs.remove(k);
    }
    await prefs.setBool(flag, true);
    debugPrint(
      'Forecast cache: v$kForecastCacheSchemaVersion — zmazaných ${toRemove.length} záznamov',
    );
    return true;
  }

  static Future<String?> getWeather(double lat, double lon, String modelParam, {bool ignoreExpiry = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _weatherCacheKey(modelParam, lat, lon);
    if (!prefs.containsKey(key)) return null;

    try {
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;

      final data = json.decode(jsonStr);
      final timestamp = data['timestamp'] as int;
      final savedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

      if (!ignoreExpiry && DateTime.now().difference(savedTime).inMinutes > kWeatherCacheDurationMinutes) {
        return null;
      }
      return data['body'] as String;
    } catch (e) {
      return null;
    }
  }

  static Future<void> saveAirQuality(double lat, double lon, String jsonBody) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(kAirQualityCachePrefix, lat, lon);
    final data = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'body': jsonBody,
    };
    await prefs.setString(key, json.encode(data));
  }

  static Future<String?> getAirQuality(double lat, double lon, {bool ignoreExpiry = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(kAirQualityCachePrefix, lat, lon);
    if (!prefs.containsKey(key)) return null;
    try {
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;
      final data = json.decode(jsonStr);
      final timestamp = data['timestamp'] as int;
      final savedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (!ignoreExpiry && DateTime.now().difference(savedTime).inMinutes > kWeatherCacheDurationMinutes) {
        return null;
      }
      return data['body'] as String;
    } catch (e) {
      return null;
    }
  }

  /// Hrubšia mriežka (~1,1 km) ako pri počasí — menej „blúdenia“ názvu obce pri GPS šume.
  static String _geoCityCacheKey(double lat, double lon) {
    return '$kGeoCachePrefix${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
  }

  static Future<void> saveGeoCity(double lat, double lon, GeoCity city) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _geoCityCacheKey(lat, lon);
    final data = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'city': city.toGeoJson(),
    };
    await prefs.setString(key, json.encode(data));
  }

  static Future<GeoCity?> getGeoCity(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _geoCityCacheKey(lat, lon);
    if (!prefs.containsKey(key)) return null;
    try {
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return null;
      final data = json.decode(jsonStr);
      final timestamp = data['timestamp'] as int;
      final savedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      if (DateTime.now().difference(savedTime).inDays > kGeoCacheDurationDays) {
        return null;
      }
      return GeoCity.fromGeoJson(data['city']);
    } catch (e) {
      return null;
    }
  }
}



class SettingsManager {
  static const Map<String, bool> _defaultAlertTypeStates = <String, bool>{
    kAlertDailySummaryEnabledKey: false,
    kAlertEveningSummaryEnabledKey: false,
    kAlertHeavyRainEnabledKey: false,
    kAlertHeavySnowEnabledKey: false,
    kAlertStrongWindEnabledKey: false,
    kAlertHighUvEnabledKey: false,
    kAlertExtremeHeatEnabledKey: false,
    kAlertStrongFrostEnabledKey: false,
  };

  static Future<WindUnit> getWindUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(kWindUnitKey) ?? 'km/h';
    return WindUnit.values.firstWhere(
      (unit) => unit.symbol == value,
      orElse: () => WindUnit.kmh,
    );
  }

  static Future<void> setWindUnit(WindUnit unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kWindUnitKey, unit.symbol);
  }

  static Future<bool> getMyLocationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kMyLocationKey) ?? true;
  }

  static Future<void> setMyLocationEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kMyLocationKey, value);
  }

  static Future<int> getHomeWidgetUpdateIntervalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    var v = prefs.getInt(kHomeWidgetUpdateIntervalMinutesKey);
    if (v == null) {
      v = kHomeWidgetUpdateIntervalMinutesDefault;
      await prefs.setInt(kHomeWidgetUpdateIntervalMinutesKey, v);
    }
    return v.clamp(kHomeWidgetUpdateIntervalMinutesMin, kHomeWidgetUpdateIntervalMinutesMax);
  }

  static Future<void> setHomeWidgetUpdateIntervalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final m = minutes.clamp(
      kHomeWidgetUpdateIntervalMinutesMin,
      kHomeWidgetUpdateIntervalMinutesMax,
    );
    await prefs.setInt(kHomeWidgetUpdateIntervalMinutesKey, m);
  }

  /// Jedno načítanie prefs namiesto troch paralelných volaní — rýchlejší návrat z nastavení / štart WeatherPage.
  static Future<
          ({
            WindUnit windUnit,
            bool myLocationEnabled,
            int widgetIntervalMinutes,
            WeatherForecastModel forecastModel,
          })>
      getWeatherPageSettingsSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final windValue = prefs.getString(kWindUnitKey) ?? 'km/h';
    final windUnit = WindUnit.values.firstWhere(
      (unit) => unit.symbol == windValue,
      orElse: () => WindUnit.kmh,
    );
    final myLocationEnabled = prefs.getBool(kMyLocationKey) ?? true;
    var widgetV = prefs.getInt(kHomeWidgetUpdateIntervalMinutesKey);
    if (widgetV == null) {
      widgetV = kHomeWidgetUpdateIntervalMinutesDefault;
      await prefs.setInt(kHomeWidgetUpdateIntervalMinutesKey, widgetV);
    }
    final widgetIntervalMinutes = widgetV.clamp(
      kHomeWidgetUpdateIntervalMinutesMin,
      kHomeWidgetUpdateIntervalMinutesMax,
    );
    return (
      windUnit: windUnit,
      myLocationEnabled: myLocationEnabled,
      widgetIntervalMinutes: widgetIntervalMinutes,
      forecastModel: WeatherForecastModel.bestMatch,
    );
  }

  /// Jedno načítanie pre obrazovku Nastavenia (predtým tri oddelené async reťaze + getInstance).
  static Future<
          ({
            Map<String, bool> alertStates,
            TimeOfDay dailySummary,
            TimeOfDay eveningSummary,
            int widgetIntervalMinutes,
          })>
      getSettingsScreenBootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, bool> alertStates = <String, bool>{};
    for (final entry in _defaultAlertTypeStates.entries) {
      alertStates[entry.key] = prefs.getBool(entry.key) ?? entry.value;
    }
    final dailyHour = prefs.getInt(kAlertDailySummaryHourKey) ?? 8;
    final dailyMinute = prefs.getInt(kAlertDailySummaryMinuteKey) ?? 0;
    final eveningHourRaw = prefs.getInt(kAlertEveningSummaryHourKey) ?? kAlertEveningSummaryHourMin;
    final eveningMinuteRaw = prefs.getInt(kAlertEveningSummaryMinuteKey) ?? 0;
    final eveningHour =
        eveningHourRaw.clamp(kAlertEveningSummaryHourMin, kAlertEveningSummaryHourMax);
    const eveningMinute = 0;
    if (eveningHour != eveningHourRaw || eveningMinuteRaw != eveningMinute) {
      await prefs.setInt(kAlertEveningSummaryHourKey, eveningHour);
      await prefs.setInt(kAlertEveningSummaryMinuteKey, eveningMinute);
    }
    var widgetV = prefs.getInt(kHomeWidgetUpdateIntervalMinutesKey);
    if (widgetV == null) {
      widgetV = kHomeWidgetUpdateIntervalMinutesDefault;
      await prefs.setInt(kHomeWidgetUpdateIntervalMinutesKey, widgetV);
    }
    final widgetIntervalMinutes = widgetV.clamp(
      kHomeWidgetUpdateIntervalMinutesMin,
      kHomeWidgetUpdateIntervalMinutesMax,
    );
    return (
      alertStates: alertStates,
      dailySummary: TimeOfDay(hour: dailyHour.clamp(0, 23), minute: dailyMinute.clamp(0, 59)),
      eveningSummary: TimeOfDay(hour: eveningHour, minute: eveningMinute),
      widgetIntervalMinutes: widgetIntervalMinutes,
    );
  }

  static Future<WeatherForecastModel> getForecastModel() async {
    return WeatherForecastModel.bestMatch;
  }

  static Future<void> setForecastModel(WeatherForecastModel _) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kForecastModelKey,
      WeatherForecastModel.bestMatch.cacheKey,
    );
  }

  static Future<void> saveLastLocation(GeoCity city) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLastLocationKey, json.encode(city.toGeoJson()));
  }

  /// Jedno prefs namiesto troch pri dokončení onboardingu (rýchlejší prechod po povolení oznámení).
  static Future<void> finishOnboardingPersist({
    required GeoCity city,
    required bool myLocationEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingDoneKey, true);
    await prefs.setBool(kMyLocationKey, myLocationEnabled);
    await prefs.setString(kLastLocationKey, json.encode(city.toGeoJson()));
  }

  static Future<GeoCity?> getLastLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(kLastLocationKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      return GeoCity.fromGeoJson(json.decode(jsonStr));
    } catch (e) {
      return null;
    }
  }

  static Future<bool> getTestPushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kTestPushEnabledKey) ?? false;
  }

  static Future<void> setTestPushEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kTestPushEnabledKey, value);
  }

  static Future<TimeOfDay> getTestPushTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(kTestPushHourKey) ?? 16;
    final minute = prefs.getInt(kTestPushMinuteKey) ?? 40;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  static Future<void> setTestPushTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kTestPushHourKey, value.hour);
    await prefs.setInt(kTestPushMinuteKey, value.minute);
  }

  static Future<void> setTestPushNextAt(DateTime? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(kTestPushNextAtKey);
      return;
    }
    await prefs.setString(kTestPushNextAtKey, value.toIso8601String());
  }

  static Future<DateTime?> getTestPushNextAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kTestPushNextAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<bool> getAlertTypeEnabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? _defaultAlertTypeStates[key] ?? false;
  }

  static Future<void> setAlertTypeEnabled(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, enabled);
  }

  static Future<bool> getSystemNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kSystemNotificationsEnabledKey) ?? true;
  }

  static Future<void> setSystemNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSystemNotificationsEnabledKey, enabled);
  }

  static Future<Map<String, bool>> getAllAlertTypeStates() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, bool> states = <String, bool>{};
    for (final entry in _defaultAlertTypeStates.entries) {
      states[entry.key] = prefs.getBool(entry.key) ?? entry.value;
    }
    return states;
  }

  static Future<TimeOfDay> getAlertDailySummaryTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(kAlertDailySummaryHourKey) ?? 8;
    final minute = prefs.getInt(kAlertDailySummaryMinuteKey) ?? 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  static Future<void> setAlertDailySummaryTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kAlertDailySummaryHourKey, value.hour);
    await prefs.setInt(kAlertDailySummaryMinuteKey, value.minute);
    await prefs.remove(kAlertDailySummaryCatchUpLastAtMsKey);
  }

  static Future<TimeOfDay> getAlertEveningSummaryTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hourRaw = prefs.getInt(kAlertEveningSummaryHourKey) ?? kAlertEveningSummaryHourMin;
    final minuteRaw = prefs.getInt(kAlertEveningSummaryMinuteKey) ?? 0;
    final hour = hourRaw.clamp(kAlertEveningSummaryHourMin, kAlertEveningSummaryHourMax);
    const minute = 0;
    if (hour != hourRaw || minuteRaw != minute) {
      await prefs.setInt(kAlertEveningSummaryHourKey, hour);
      await prefs.setInt(kAlertEveningSummaryMinuteKey, minute);
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  static Future<void> setAlertEveningSummaryTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    final hour =
        value.hour.clamp(kAlertEveningSummaryHourMin, kAlertEveningSummaryHourMax);
    await prefs.setInt(kAlertEveningSummaryHourKey, hour);
    await prefs.setInt(kAlertEveningSummaryMinuteKey, 0);
    await prefs.remove(kAlertEveningSummaryCatchUpLastAtMsKey);
  }

  static Future<void> setAlertDailySummaryNextAt(DateTime? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(kAlertDailySummaryNextAtKey);
      return;
    }
    await prefs.setString(kAlertDailySummaryNextAtKey, value.toIso8601String());
  }

  static Future<DateTime?> getAlertDailySummaryNextAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAlertDailySummaryNextAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> setAlertEveningSummaryNextAt(DateTime? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(kAlertEveningSummaryNextAtKey);
      return;
    }
    await prefs.setString(kAlertEveningSummaryNextAtKey, value.toIso8601String());
  }

  static Future<DateTime?> getAlertEveningSummaryNextAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAlertEveningSummaryNextAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<String?> getAlertDailySummaryLastPushBody() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kAlertDailySummaryLastPushBodyKey);
  }

  static Future<void> setAlertDailySummaryLastPushBody(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(kAlertDailySummaryLastPushBodyKey);
      return;
    }
    await prefs.setString(kAlertDailySummaryLastPushBodyKey, value);
  }

  static Future<String?> getAlertEveningSummaryLastPushBody() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kAlertEveningSummaryLastPushBodyKey);
  }

  static Future<void> setAlertEveningSummaryLastPushBody(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(kAlertEveningSummaryLastPushBodyKey);
      return;
    }
    await prefs.setString(kAlertEveningSummaryLastPushBodyKey, value);
  }

  static Future<String?> getAlertHighUvLastPlannedSlot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAlertHighUvLastPlannedSlotKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> setAlertHighUvLastPlannedSlot(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(kAlertHighUvLastPlannedSlotKey);
      return;
    }
    await prefs.setString(kAlertHighUvLastPlannedSlotKey, value);
  }

  static Future<String?> getAlertStrongWindLastPlannedSlot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAlertStrongWindLastPlannedSlotKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> setAlertStrongWindLastPlannedSlot(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(kAlertStrongWindLastPlannedSlotKey);
      return;
    }
    await prefs.setString(kAlertStrongWindLastPlannedSlotKey, value);
  }

  static Future<String?> getAlertHeavyRainLastPlannedSlot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAlertHeavyRainLastPlannedSlotKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> setAlertHeavyRainLastPlannedSlot(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(kAlertHeavyRainLastPlannedSlotKey);
      return;
    }
    await prefs.setString(kAlertHeavyRainLastPlannedSlotKey, value);
  }

  static Future<String?> getAlertHeavySnowLastPlannedSlot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAlertHeavySnowLastPlannedSlotKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> setAlertHeavySnowLastPlannedSlot(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(kAlertHeavySnowLastPlannedSlotKey);
      return;
    }
    await prefs.setString(kAlertHeavySnowLastPlannedSlotKey, value);
  }

  static Future<bool> getLocationPermissionPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kLocationPermissionPromptShownKey) ?? false;
  }

  static Future<void> setLocationPermissionPromptShown(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kLocationPermissionPromptShownKey, value);
  }

  static Future<void> applyAlertDefaultsOffMigrationIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyMigrated = prefs.getBool(kAlertDefaultsOffMigrationKey) ?? false;
    if (alreadyMigrated) return;

    for (final key in _defaultAlertTypeStates.keys) {
      await prefs.setBool(key, false);
    }
    await prefs.remove(kAlertDailySummaryNextAtKey);
    await prefs.remove(kAlertEveningSummaryNextAtKey);
    await prefs.remove(kAlertHighUvLastPlannedSlotKey);
    await prefs.remove(kAlertStrongWindLastPlannedSlotKey);
    await prefs.remove(kAlertHeavyRainLastPlannedSlotKey);
    await prefs.remove(kAlertHeavySnowLastPlannedSlotKey);
    await prefs.setBool(kAlertDefaultsOffMigrationKey, true);
  }
}


int _alertRainMmDisplay(double mm) {
  final v = ((mm / 5.0).round() * 5).clamp(5, 500);
  return v;
}

int _alertSnowCmDisplay(double cm) {
  final v = ((cm / 5.0).round() * 5).clamp(5, 500);
  return v;
}

class LocalTestPushService {
  static const int _dailySummaryNotificationId = 4040;
  static const int _eveningSummaryNotificationId = 4041;
  static const int _dailySummaryCatchUpNotificationId = 4140;
  static const int _eveningSummaryCatchUpNotificationId = 4141;
  static const int _previewBaseNotificationId = 4500;
  static const int _highUvNotificationId = 4601;
  static const int _strongWindNotificationId = 4602;
  static const int _heavyRainNotificationId = 4603;
  static const int _heavySnowNotificationId = 4604;
  static const int _dailySummarySlipGuardId = 4242;
  static const int _eveningSummarySlipGuardId = 4243;
  static const int _highUvSlipNotificationId = 4701;
  static const int _strongWindSlipNotificationId = 4702;
  static const int _heavyRainSlipNotificationId = 4703;
  static const int _heavySnowSlipNotificationId = 4704;
  /// Výstrahy UV/vietor/dážď/sneh: jedno upozornenie presne toľko minút pred očakávanou udalosťou (nie pevná hodina dňa ako súhrny).
  static const Duration _kLeadAlertBeforeEvent = kLeadWeatherAlertBeforeEvent;
  static const TimeOfDay fixedDailySummaryTime = TimeOfDay(hour: 8, minute: 0);
  static const TimeOfDay fixedEveningSummaryTime = TimeOfDay(hour: 18, minute: 0);
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Jednotný vzhľad: malá ikona oblak (`ic_stat_meteo`) + veľká farebná (`ic_notification_large`).
  static NotificationDetails _meteoNotificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'meteo_počasie_alerts',
        'Meteo Počasie',
        channelDescription: 'Denný súhrn počasia a miestne upozornenia',
        icon: 'ic_stat_meteo',
        largeIcon: DrawableResourceAndroidBitmap('@drawable/ic_notification_large'),
        // Zhoda s OneSignal / manifest accent: modré pozadie okolo malej ikony (nie celá karta).
        color: Color(0xFF2196F3),
        colorized: false,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

  static const List<AndroidScheduleMode> _androidPreferredAlarmModes = <AndroidScheduleMode>[
    AndroidScheduleMode.alarmClock,
    AndroidScheduleMode.exactAllowWhileIdle,
    AndroidScheduleMode.exact,
    AndroidScheduleMode.inexact,
    AndroidScheduleMode.inexactAllowWhileIdle,
  ];

  static Future<void> _androidZonedSchedulePickMode(
    Future<void> Function(AndroidScheduleMode mode) trySchedule,
  ) async {
    Object? lastError;
    for (final mode in _androidPreferredAlarmModes) {
      try {
        await trySchedule(mode);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('Android zonedSchedule failed'),
      StackTrace.current,
    );
  }

  static Future<void> _zonedScheduleOneShot({
    required int notificationId,
    required tz.TZDateTime scheduled,
    required String title,
    required String body,
  }) async {
    final details = _meteoNotificationDetails();
    await _androidZonedSchedulePickMode(
      (mode) => _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      ),
    );
  }

  static Future<void> _zonedScheduleRepeatingSummary({
    required int notificationId,
    required tz.TZDateTime scheduled,
    required String title,
    required String body,
    required Future<void> Function(DateTime?) persistNextAt,
  }) async {
    final details = _meteoNotificationDetails();
    await _androidZonedSchedulePickMode(
      (mode) => _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: mode,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      ),
    );
    await persistNextAt(scheduled.toLocal());
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_meteo');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final id = response.id;
        if (id != null) {
          unawaited(handleNotificationOpened(id));
        }
      },
    );

    _initialized = true;
    await applyFromSettings();
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final openedId = launch!.notificationResponse?.id;
        if (openedId != null) {
          await handleNotificationOpened(openedId);
        }
      }
    } catch (_) {}
  }

  /// Zruší prípadné staré doplnkové upozornenie (staršie verzie aplikácie ho plánovali zvlášť).
  static Future<void> handleNotificationOpened(int notificationId) async {
    if (!_initialized) return;
    if (notificationId == _dailySummaryNotificationId) {
      await _plugin.cancel(_dailySummarySlipGuardId);
    } else if (notificationId == _eveningSummaryNotificationId) {
      await _plugin.cancel(_eveningSummarySlipGuardId);
    }
  }

  static const String _androidPackageUri = 'package:sk.menopocasie.app';

  /// Android 12+: ak presné alarmy ešte nie sú povolené, otvorí systémovú obrazovku. Ak už sú, okamžite vráti `true` bez UI.
  static Future<bool?> requestExactAlarmsPermissionAndroid() async {
    if (!_initialized) return null;
    if (kIsWeb || !Platform.isAndroid) return null;
    return _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  /// Úspora batérie na Androide môže oneskoriť alebo presunúť lokálne upozornenia. Otvorí systémovú obrazovku na výnimku.
  static Future<void> openAndroidReliableNotificationsSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await const AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: _androidPackageUri,
      ).launch();
    } catch (_) {
      try {
        await const AndroidIntent(
          action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
          data: _androidPackageUri,
        ).launch();
      } catch (_) {}
    }
  }

  /// Samostatný systémový dialóg oznámení (napr. zapnutie súhrnov v nastaveniach bez OneSignal onboardingu).
  static Future<void> requestPermissionsFromUserAction() async {
    if (!_initialized) return;
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    final iosImpl = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<bool> areSystemNotificationsEnabled() async {
    if (!_initialized) return true;
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      try {
        final dynamic androidImpl =
            _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final dynamic enabled = await androidImpl?.areNotificationsEnabled();
        if (enabled is bool) return enabled;
      } catch (_) {}
    }
    return true;
  }

  static Future<void> applyFromSettings() async {
    final enabled = await SettingsManager.getAlertTypeEnabled(kAlertDailySummaryEnabledKey);
    final dailyTime = await SettingsManager.getAlertDailySummaryTime();
    if (!enabled) {
      await scheduleDailySummary(enabled: false, time: dailyTime);
    } else {
      await scheduleDailySummary(enabled: true, time: dailyTime);
    }

    final eveningEnabled = await SettingsManager.getAlertTypeEnabled(kAlertEveningSummaryEnabledKey);
    final eveningTime = await SettingsManager.getAlertEveningSummaryTime();
    if (!eveningEnabled) {
      await scheduleEveningSummary(enabled: false, time: eveningTime);
    } else {
      await scheduleEveningSummary(enabled: true, time: eveningTime);
    }
    final uvEnabled = await SettingsManager.getAlertTypeEnabled(kAlertHighUvEnabledKey);
    if (!uvEnabled) {
      await cancelHighUvLeadAlert();
    }
    final windEnabled = await SettingsManager.getAlertTypeEnabled(kAlertStrongWindEnabledKey);
    if (!windEnabled) {
      await cancelStrongWindLeadAlert();
    }
    final rainEnabled = await SettingsManager.getAlertTypeEnabled(kAlertHeavyRainEnabledKey);
    if (!rainEnabled) {
      await cancelHeavyRainLeadAlert();
    }
    final snowEnabled = await SettingsManager.getAlertTypeEnabled(kAlertHeavySnowEnabledKey);
    if (!snowEnabled) {
      await cancelHeavySnowLeadAlert();
    }
  }

  static Future<void> applyFromSettingsIfAndroidExactAlarmsAllowed() async {
    if (!_initialized || kIsWeb || !Platform.isAndroid) return;
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final can = await android?.canScheduleExactNotifications();
    if (can == true) {
      await applyFromSettings();
    }
  }

  static Future<void> scheduleDailySummary({required bool enabled, required TimeOfDay time}) async {
    if (!_initialized) return;
    if (!enabled) {
      await _plugin.cancel(_dailySummaryNotificationId);
      await _plugin.cancel(_dailySummaryCatchUpNotificationId);
      await _plugin.cancel(_dailySummarySlipGuardId);
      await SettingsManager.setAlertDailySummaryNextAt(null);
      await SettingsManager.setAlertDailySummaryLastPushBody(null);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kAlertDailySummaryCatchUpLastAtMsKey);
      return;
    }

    final body = await SettingsManager.getAlertDailySummaryLastPushBody();
    final effectiveBody =
        (body != null && body.isNotEmpty) ? body : kDailySummaryPlaceholderBody;
    await scheduleDailySummaryWithBody(enabled: true, time: time, body: effectiveBody);
  }

  static Future<void> scheduleDailySummaryWithBody({
    required bool enabled,
    required TimeOfDay time,
    required String body,
  }) async {
    if (!_initialized) return;
    if (!enabled) {
      await _plugin.cancel(_dailySummaryNotificationId);
      await _plugin.cancel(_dailySummaryCatchUpNotificationId);
      await _plugin.cancel(_dailySummarySlipGuardId);
      await SettingsManager.setAlertDailySummaryNextAt(null);
      final prefsOff = await SharedPreferences.getInstance();
      await prefsOff.remove(kAlertDailySummaryCatchUpLastAtMsKey);
      await SettingsManager.setAlertDailySummaryLastPushBody(null);
      return;
    }

    final scheduled = _nextInstanceOfTime(time);
    await _plugin.cancel(_dailySummaryCatchUpNotificationId);
    await _plugin.cancel(_dailySummaryNotificationId);
    await _plugin.cancel(_dailySummarySlipGuardId);
    await _zonedScheduleRepeatingSummary(
      notificationId: _dailySummaryNotificationId,
      scheduled: scheduled,
      title: 'Ranné zhrnutie',
      body: body,
      persistNextAt: SettingsManager.setAlertDailySummaryNextAt,
    );
  }

  static Future<void> scheduleEveningSummary({required bool enabled, required TimeOfDay time}) async {
    if (!_initialized) return;
    if (!enabled) {
      await _plugin.cancel(_eveningSummaryNotificationId);
      await _plugin.cancel(_eveningSummaryCatchUpNotificationId);
      await _plugin.cancel(_eveningSummarySlipGuardId);
      await SettingsManager.setAlertEveningSummaryNextAt(null);
      await SettingsManager.setAlertEveningSummaryLastPushBody(null);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kAlertEveningSummaryCatchUpLastAtMsKey);
      return;
    }

    final body = await SettingsManager.getAlertEveningSummaryLastPushBody();
    final effectiveBody =
        (body != null && body.isNotEmpty) ? body : kEveningSummaryPlaceholderBody;
    await scheduleEveningSummaryWithBody(enabled: true, time: time, body: effectiveBody);
  }

  static Future<void> scheduleEveningSummaryWithBody({
    required bool enabled,
    required TimeOfDay time,
    required String body,
  }) async {
    if (!_initialized) return;
    if (!enabled) {
      await _plugin.cancel(_eveningSummaryNotificationId);
      await _plugin.cancel(_eveningSummaryCatchUpNotificationId);
      await _plugin.cancel(_eveningSummarySlipGuardId);
      await SettingsManager.setAlertEveningSummaryNextAt(null);
      final prefsOff = await SharedPreferences.getInstance();
      await prefsOff.remove(kAlertEveningSummaryCatchUpLastAtMsKey);
      await SettingsManager.setAlertEveningSummaryLastPushBody(null);
      return;
    }

    final scheduled = _nextInstanceOfTime(time);
    await _plugin.cancel(_eveningSummaryCatchUpNotificationId);
    await _plugin.cancel(_eveningSummaryNotificationId);
    await _plugin.cancel(_eveningSummarySlipGuardId);
    await _zonedScheduleRepeatingSummary(
      notificationId: _eveningSummaryNotificationId,
      scheduled: scheduled,
      title: 'Večerné zhrnutie',
      body: body,
      persistNextAt: SettingsManager.setAlertEveningSummaryNextAt,
    );
  }

  static Future<void> sendAlertPreview({
    required int alertIndex,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      _previewBaseNotificationId + alertIndex,
      title,
      body,
      _meteoNotificationDetails(),
    );
  }

  static Future<void> scheduleHighUvLeadAlert({
    required DateTime eventAt,
    required double uvIndex,
  }) async {
    if (!_initialized) return;
    final triggerAt = eventAt.subtract(_kLeadAlertBeforeEvent);
    final scheduled = _ensureFutureScheduled(tz.TZDateTime.from(triggerAt, tz.local));

    await _plugin.cancel(_highUvNotificationId);
    await _plugin.cancel(_highUvSlipNotificationId);
    const title = 'Upozornenie · UV index';
    final body =
        'Očakáva sa vysoký UV index ${uvIndex.round()}. Obmedzte pobyt na priamom slnku.';
    await _zonedScheduleOneShot(
      notificationId: _highUvNotificationId,
      scheduled: scheduled,
      title: title,
      body: body,
    );
  }

  static Future<void> cancelHighUvLeadAlert() async {
    if (!_initialized) return;
    await _plugin.cancel(_highUvNotificationId);
    await _plugin.cancel(_highUvSlipNotificationId);
  }

  static Future<void> cancelEveningSummary() async {
    if (!_initialized) return;
    await _plugin.cancel(_eveningSummaryNotificationId);
    await _plugin.cancel(_eveningSummaryCatchUpNotificationId);
    await _plugin.cancel(_eveningSummarySlipGuardId);
    await SettingsManager.setAlertEveningSummaryLastPushBody(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAlertEveningSummaryCatchUpLastAtMsKey);
  }

  static Future<void> scheduleStrongWindLeadAlert({
    required DateTime eventAt,
    required double gustKmh,
  }) async {
    if (!_initialized) return;
    final scheduled = _ensureFutureScheduled(
      tz.TZDateTime.from(eventAt.subtract(_kLeadAlertBeforeEvent), tz.local),
    );
    await _plugin.cancel(_strongWindNotificationId);
    await _plugin.cancel(_strongWindSlipNotificationId);
    const title = 'Upozornenie · Silný vietor';
    const body =
        'Očakávajú sa silné nárazy vetra. Zabezpečte voľné predmety a vonku zvýšte pozornosť.';
    await _zonedScheduleOneShot(
      notificationId: _strongWindNotificationId,
      scheduled: scheduled,
      title: title,
      body: body,
    );
  }

  static Future<void> cancelStrongWindLeadAlert() async {
    if (!_initialized) return;
    await _plugin.cancel(_strongWindNotificationId);
    await _plugin.cancel(_strongWindSlipNotificationId);
  }

  static Future<void> scheduleHeavyRainLeadAlert({
    required DateTime eventAt,
    required double precipitationMm,
  }) async {
    if (!_initialized) return;
    final scheduled = _ensureFutureScheduled(
      tz.TZDateTime.from(eventAt.subtract(_kLeadAlertBeforeEvent), tz.local),
    );
    await _plugin.cancel(_heavyRainNotificationId);
    await _plugin.cancel(_heavyRainSlipNotificationId);
    const title = 'Upozornenie · Výdatný dážď';
    final mmShown = _alertRainMmDisplay(precipitationMm);
    final body =
        'Očakáva sa výdatný dážď. Denný úhrn zrážok môže dosiahnuť približne $mmShown mm. Na cestách zvýšte pozornosť.';
    await _zonedScheduleOneShot(
      notificationId: _heavyRainNotificationId,
      scheduled: scheduled,
      title: title,
      body: body,
    );
  }

  static Future<void> cancelHeavyRainLeadAlert() async {
    if (!_initialized) return;
    await _plugin.cancel(_heavyRainNotificationId);
    await _plugin.cancel(_heavyRainSlipNotificationId);
  }

  static Future<void> scheduleHeavySnowLeadAlert({
    required DateTime eventAt,
    required double snowfallCm,
  }) async {
    if (!_initialized) return;
    final scheduled = _ensureFutureScheduled(
      tz.TZDateTime.from(eventAt.subtract(_kLeadAlertBeforeEvent), tz.local),
    );
    await _plugin.cancel(_heavySnowNotificationId);
    await _plugin.cancel(_heavySnowSlipNotificationId);
    const title = 'Upozornenie · Výdatné sneženie';
    final cmShown = _alertSnowCmDisplay(snowfallCm);
    final body =
        'Očakáva sa výdatné sneženie. Napadnúť môže približne $cmShown cm snehu. Na cestách zvýšte pozornosť.';
    await _zonedScheduleOneShot(
      notificationId: _heavySnowNotificationId,
      scheduled: scheduled,
      title: title,
      body: body,
    );
  }

  static Future<void> cancelHeavySnowLeadAlert() async {
    if (!_initialized) return;
    await _plugin.cancel(_heavySnowNotificationId);
    await _plugin.cancel(_heavySnowSlipNotificationId);
  }

  static tz.TZDateTime _nextInstanceOfTime(TimeOfDay t) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  /// `zonedSchedule` vyžaduje striktne budúci čas.
  /// Pri lead alertoch môže byť `eventAt - X min` už v minulosti (napr. po neskorom fetchi).
  static tz.TZDateTime _ensureFutureScheduled(
    tz.TZDateTime scheduled, {
    Duration minAhead = const Duration(seconds: 5),
  }) {
    final now = tz.TZDateTime.now(tz.local);
    final minAllowed = now.add(minAhead);
    if (!scheduled.isAfter(minAllowed)) {
      return minAllowed;
    }
    return scheduled;
  }
}

Future<bool> hasInternetConnection() async {
  Future<bool> probe(String host) async {
    try {
      final result = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
  Future<bool> probeHttp(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      // Stačí, že server odpovie - aj 4xx znamená, že internet funguje.
      return response.statusCode > 0;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  if (await probe('api.open-meteo.com')) return true;
  if (await probe('google.com')) return true;
  if (await probeHttp('https://api.open-meteo.com/')) return true;
  if (await probeHttp('https://www.google.com/generate_204')) return true;
  return false;
}

/// Získanie aktuálneho cloud cover
/// 
/// POZNÁMKA: Satelitné cloud cover dáta boli dostupné cez Open-Meteo.
/// ECMWF Open Data poskytuje len modelovú oblačnosť (tcc parameter).
/// Pre satelitné dáta by bolo potrebné iné zdroj (napr. EUMETSAT).
Future<double?> fetchSatelliteCloudCover(double lat, double lon) async {
  // Dočasne vypnuté - satelitné dáta nie sú dostupné cez ECMWF Open Data
  // Používame len modelovú oblačnosť z ECMWF IFS
  return null;
}
