import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:pocasie/weather_home_widget.dart';

const String _kLastLocationKey = 'last_location_v7';
const String _kWindUnitKey = 'wind_unit_v1';
const String _kWidgetIntervalKey = 'home_widget_update_interval_minutes_v1';
const int _kWidgetIntervalDefault = 30;

/// Musí sedieť s `main.dart` — rovnaká logika ako pri ikone v aplikácii (nie holý WMO z API).
const double _kWIconTraceLiquidMm = 0.02;
const double _kWIconTraceSnowCm = 0.02;
const double _kWIconMeaningfulLiquidMm = 0.1;
const double _kWIconMeaningfulSnowCm = 0.1;
const Set<int> _kWPrecipitationCodes = {
  51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99,
};

bool _wHasTracePrecipForIcon(double liquidMm, double snowfallCm) =>
    liquidMm >= _kWIconTraceLiquidMm || snowfallCm >= _kWIconTraceSnowCm;

bool _wBelowMeaningfulPrecipAmountForIcon(double liquidMm, double snowfallCm) =>
    liquidMm < _kWIconMeaningfulLiquidMm && snowfallCm < _kWIconMeaningfulSnowCm;

bool _wPrecipIconShowsForHour(
  int precipProbabilityPercent,
  double liquidMm,
  double snowfallCm, {
  required bool wmoPrecipCode,
}) {
  if (liquidMm >= _kWIconMeaningfulLiquidMm || snowfallCm >= _kWIconMeaningfulSnowCm) {
    return precipProbabilityPercent >= 40;
  }
  if (_wHasTracePrecipForIcon(liquidMm, snowfallCm) && precipProbabilityPercent >= 35) {
    return true;
  }
  if (wmoPrecipCode && precipProbabilityPercent >= 42) return true;
  if (precipProbabilityPercent >= 55 && (liquidMm > 0 || snowfallCm > 0)) return true;
  return false;
}

int _wLightPrecipDisplayCode(int apiWeatherCode) {
  if ({51, 53, 55}.contains(apiWeatherCode)) {
    if (apiWeatherCode <= 51) return 51;
    if (apiWeatherCode <= 53) return 53;
    return 55;
  }
  if ({61, 63, 65, 66, 67, 80, 81, 82}.contains(apiWeatherCode)) return 61;
  if ({56, 57}.contains(apiWeatherCode)) return 56;
  if ({71, 73, 75, 77, 85, 86}.contains(apiWeatherCode)) return 71;
  return apiWeatherCode;
}

bool _wThunderIconWarranted(
  int precipProbabilityPercent,
  double hourlyPrecipitationMm, {
  double snowfallCm = 0.0,
}) =>
    precipProbabilityPercent >= 58 &&
    !_wBelowMeaningfulPrecipAmountForIcon(hourlyPrecipitationMm, snowfallCm);

int _wDrySkyIconTierFromModel({
  required int precipProbabilityPercent,
  required double hourlyPrecipitationMm,
  double? cloudCoverPercent,
}) {
  if (hourlyPrecipitationMm >= 0.45) return 3;

  final bool almostNoRain = hourlyPrecipitationMm < 0.018;
  final int probForTier =
      almostNoRain ? math.min(precipProbabilityPercent, 14) : precipProbabilityPercent;

  if (cloudCoverPercent != null) {
    const double kCoverBias = 36.0;
    final double eff = (cloudCoverPercent - kCoverBias).clamp(0.0, 100.0);
    if (eff < 9) return 0;
    if (eff < 26) return 1;
    if (eff < 54) return 2;
    return 3;
  }

  if (hourlyPrecipitationMm >= 0.09) return 2;
  if (hourlyPrecipitationMm >= 0.03) return 2;
  if (probForTier >= 42) return 2;
  if (probForTier >= 18) return 2;
  return 1;
}

int _wWeatherIconCodeWithPrecipThreshold(
  int apiWeatherCode,
  int precipProbabilityPercent, {
  double? cloudCoverPercent,
  double? hourlyPrecipitationMm,
  double snowfallCm = 0.0,
}) {
  final double mm = hourlyPrecipitationMm ?? 0.0;
  final bool thunderCode = apiWeatherCode == 95 || apiWeatherCode == 96 || apiWeatherCode == 99;
  final bool precipCode = _kWPrecipitationCodes.contains(apiWeatherCode);
  final bool precipShows = _wPrecipIconShowsForHour(
    precipProbabilityPercent,
    mm,
    snowfallCm,
    wmoPrecipCode: precipCode,
  );
  final bool onlyTrace = _wBelowMeaningfulPrecipAmountForIcon(mm, snowfallCm);

  if (!precipShows && (precipCode || thunderCode)) {
    if (thunderCode && _wThunderIconWarranted(precipProbabilityPercent, mm, snowfallCm: snowfallCm)) {
      return apiWeatherCode;
    }
    return _wDrySkyIconTierFromModel(
      precipProbabilityPercent: precipProbabilityPercent,
      hourlyPrecipitationMm: mm,
      cloudCoverPercent: cloudCoverPercent,
    );
  }

  if (thunderCode && _wThunderIconWarranted(precipProbabilityPercent, mm, snowfallCm: snowfallCm)) {
    return apiWeatherCode;
  }

  if (precipCode && precipShows) {
    return onlyTrace ? _wLightPrecipDisplayCode(apiWeatherCode) : apiWeatherCode;
  }

  if (!precipCode &&
      !thunderCode &&
      precipShows &&
      {0, 1, 2, 3, 45, 48}.contains(apiWeatherCode)) {
    return onlyTrace ? 51 : 61;
  }

  final int dryTier = _wDrySkyIconTierFromModel(
    precipProbabilityPercent: precipProbabilityPercent,
    hourlyPrecipitationMm: mm,
    cloudCoverPercent: cloudCoverPercent,
  );

  if (precipCode && !precipShows) {
    return dryTier;
  }

  int code = apiWeatherCode;
  if ({0, 1, 2, 3}.contains(code)) {
    code = math.min(code, dryTier);
  }
  return code;
}

const String _periodicUniqueName = 'sk.menopocasie.widget_periodic_v1';
const String _refreshTaskName = 'sk.menopocasie.widgetRefresh';

/// Android WorkManager povolí periodickú prácu najčastejšie najviac raz za 15 minút.
const int _androidMinPeriodicMinutes = 15;

/// Volaj po štarte alebo zmene intervalu widgetov (iba Android).
Future<void> rescheduleAndroidHomeWidgetPeriodicWork() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    var mins = prefs.getInt(_kWidgetIntervalKey) ?? _kWidgetIntervalDefault;
    mins = mins.clamp(1, 720);
    final periodic =
        mins < _androidMinPeriodicMinutes ? _androidMinPeriodicMinutes : mins;

    await Workmanager().registerPeriodicTask(
      _periodicUniqueName,
      _refreshTaskName,
      frequency: Duration(minutes: periodic),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } catch (e, st) {
    debugPrint('rescheduleAndroidHomeWidgetPeriodicWork: $e\n$st');
  }
}

@pragma('vm:entry-point')
void widgetBackgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (taskName == _refreshTaskName) {
        await _refreshHomeWidgetInBackground();
      }
    } catch (e, st) {
      debugPrint('Widget BG task error: $e\n$st');
    }
    return true;
  });
}

Future<void> _refreshHomeWidgetInBackground() async {
  if (kIsWeb || !Platform.isAndroid) return;

  final prefs = await SharedPreferences.getInstance();
  final rawLoc = prefs.getString(_kLastLocationKey);
  if (rawLoc == null || rawLoc.isEmpty) return;

  Map<String, dynamic> city;
  try {
    city = json.decode(rawLoc) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final lat = (city['latitude'] as num?)?.toDouble();
  final lon = (city['longitude'] as num?)?.toDouble();
  if (lat == null || lon == null) return;

  final name = (city['name'] as String?)?.trim().isNotEmpty == true
      ? city['name'] as String
      : 'Poloha';

  final windSym = prefs.getString(_kWindUnitKey) ?? 'km/h';

  final uri = Uri.parse(
    'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
    '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m,precipitation,cloud_cover,time'
    '&hourly=time,precipitation_probability,precipitation,cloud_cover'
    '&forecast_hours=24&daily=sunrise,sunset&timezone=auto&forecast_days=1',
  );

  http.Response resp;
  try {
    resp = await http.get(uri).timeout(const Duration(seconds: 25));
  } catch (_) {
    return;
  }

  if (resp.statusCode != 200) return;

  Map<String, dynamic> data;
  try {
    data = json.decode(resp.body) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final cur = data['current'] as Map<String, dynamic>?;
  if (cur == null) return;

  final temp = (cur['temperature_2m'] as num?)?.toDouble();
  final rawCode = (cur['weather_code'] as num?)?.toInt() ?? 0;
  final isDay = (cur['is_day'] as num?)?.toInt() == 1;

  if (temp == null) return;

  final String? currentTimeStr = cur['time'] as String?;
  final hourly = data['hourly'] as Map<String, dynamic>?;
  int slotProb = 0;
  double slotMm = 0.0;
  double? slotCloud;
  if (hourly != null && currentTimeStr != null) {
    final times = hourly['time'] as List?;
    if (times != null) {
      final idx = times.indexWhere((e) => e.toString() == currentTimeStr);
      if (idx >= 0) {
        final probs = hourly['precipitation_probability'] as List?;
        final mms = hourly['precipitation'] as List?;
        final clouds = hourly['cloud_cover'] as List?;
        if (probs != null && idx < probs.length) {
          slotProb = (probs[idx] as num?)?.toInt() ?? 0;
        }
        if (mms != null && idx < mms.length) {
          slotMm = (mms[idx] as num?)?.toDouble() ?? 0.0;
        }
        if (clouds != null && idx < clouds.length) {
          slotCloud = (clouds[idx] as num?)?.toDouble();
        }
      }
    }
  }

  final double curPrecip = (cur['precipitation'] as num?)?.toDouble() ?? 0.0;
  final double? curCloud = (cur['cloud_cover'] as num?)?.toDouble();
  final int displayCode = _wWeatherIconCodeWithPrecipThreshold(
    rawCode,
    slotProb,
    cloudCoverPercent: slotCloud ?? curCloud,
    hourlyPrecipitationMm: slotMm > 0 ? slotMm : curPrecip,
    snowfallCm: 0.0,
  );

  final desc = _capitalizeSk(_wmoDescriptionSk(displayCode));

  DateTime locNow;
  try {
    final ts = cur['time'] as String?;
    locNow = ts != null ? DateTime.parse(ts) : DateTime.now();
  } catch (_) {
    locNow = DateTime.now();
  }

  const wk = <String>[
    'Pondelok',
    'Utorok',
    'Streda',
    'Štvrtok',
    'Piatok',
    'Sobota',
    'Nedeľa',
  ];
  const mon = <String>[
    'januára',
    'februára',
    'marca',
    'apríla',
    'mája',
    'júna',
    'júla',
    'augusta',
    'septembra',
    'októbra',
    'novembra',
    'decembra',
  ];
  final timeJe =
      '${wk[locNow.weekday - 1]} ${locNow.day}. ${mon[locNow.month - 1]}, ${locNow.hour.toString().padLeft(2, '0')}:${locNow.minute.toString().padLeft(2, '0')}';

  String? apparent;
  final ap = (cur['apparent_temperature'] as num?)?.toDouble();
  if (ap != null) {
    apparent = 'Pocitovo ${ap.round()}°';
  }

  String wind = '--';
  final ws = (cur['wind_speed_10m'] as num?)?.toDouble();
  if (ws != null) {
    wind = _formatWind(ws, windSym);
  }

  String humidity = '--%';
  final rh = (cur['relative_humidity_2m'] as num?)?.toDouble();
  if (rh != null) {
    humidity = '${rh.round()}%';
  }

  String sun = '--:-- / --:--';
  final daily = data['daily'] as Map<String, dynamic>?;
  final sr = daily?['sunrise'];
  final ss = daily?['sunset'];
  if (sr is List && sr.isNotEmpty && ss is List && ss.isNotEmpty) {
    sun = '${_hm(sr.first.toString())} / ${_hm(ss.first.toString())}';
  }

  await WeatherHomeWidget.update(
    city: name,
    description: desc,
    temperature: '${temp.round()}°',
    timeJe: timeJe,
    weatherCode: displayCode,
    iconAssetPath: null,
    isDay: isDay,
    apparent: apparent,
    wind: wind,
    sun: sun,
    humidity: humidity,
    isOffline: false,
  );
}

String _hm(String iso) {
  try {
    final d = DateTime.parse(iso);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return '--:--';
  }
}

String _formatWind(double kmh, String sym) {
  switch (sym) {
    case 'm/s':
      return '${(kmh / 3.6).round()} m/s';
    case 'kts':
      return '${(kmh / 1.852).round()} kts';
    default:
      return '${kmh.round()} km/h';
  }
}

String _capitalizeSk(String s) {
  if (s.isEmpty) return 'Počasie';
  return s.replaceFirstMapped(
    RegExp(r'^[a-záäčďéíĺľňóôŕšťúýž]'),
    (m) => m.group(0)!.toUpperCase(),
  );
}

/// Zodné popisy ako v `_weatherCodeMap` (main_shared).
String _wmoDescriptionSk(int code) {
  switch (code) {
    case 0:
      return 'jasno';
    case 1:
      return 'prevažne jasno';
    case 2:
      return 'polooblačno';
    case 3:
      return 'zamračené';
    case 45:
    case 48:
      return 'zamračené';
    case 51:
      return 'slabé mrholenie';
    case 53:
      return 'mierne mrholenie';
    case 55:
      return 'výdatné mrholenie';
    case 56:
      return 'slabé sneženie';
    case 57:
      return 'silné sneženie';
    case 61:
      return 'slabý dážď';
    case 63:
      return 'mierny dážď';
    case 65:
      return 'silný dážď';
    case 66:
      return 'slabý mrznúci dážď';
    case 67:
      return 'silný mrznúci dážď';
    case 71:
      return 'slabé sneženie';
    case 73:
      return 'mierne sneženie';
    case 75:
      return 'silné sneženie';
    case 77:
      return 'snehové zrná';
    case 80:
      return 'slabé prehánky';
    case 81:
      return 'mierne prehánky';
    case 82:
      return 'prudký dážď';
    case 85:
      return 'slabé snehové prehánky';
    case 86:
      return 'silné snehové prehánky';
    case 95:
      return 'búrka';
    case 96:
      return 'búrka s krúpami';
    case 99:
      return 'silná búrka s krúpami';
    default:
      return 'počasie';
  }
}
