import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:pocasie/openmeteo_widget_fetch.dart';
import 'package:pocasie/weather_home_widget.dart';
import 'package:pocasie/weather_labels_sk.dart';
import 'package:pocasie/vystrahy_home_widget.dart';
import 'package:pocasie/vystrahy_widget_fetch.dart';

const String _kLastLocationKey = 'last_location_v7';
const String _kWindUnitKey = 'wind_unit_v1';
const String _kWidgetIntervalKey = 'home_widget_update_interval_minutes_v1';
const int _kWidgetIntervalDefault = 30;

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

  final forecast = await widgetFetchOpenMeteoForecast(lat, lon);
  if (forecast == null) return;

  final cur = forecast['current'] as Map<String, dynamic>?;
  if (cur == null) return;

  final temp = (cur['temperature_2m'] as num?)?.toDouble();
  final isDay = (cur['is_day'] as num?)?.toInt() == 1;

  if (temp == null) return;

  final int displayCode = widgetEffectiveWeatherCodeFromForecast(forecast);

  final desc = _capitalizeSk(
    simplifiedPrecipLabelSk(displayCode) ?? _wmoDescriptionSk(displayCode),
  );

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
  final daily = forecast['daily'] as Map<String, dynamic>?;
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

  await _refreshVystrahyWidgetInBackground(
    cityName: name,
    admin1: city['admin1'] as String?,
    admin2: city['admin2'] as String?,
    countryCode: city['countryCode'] as String? ?? city['country_code'] as String?,
    lat: lat,
    lon: lon,
  );
}

Future<void> _refreshVystrahyWidgetInBackground({
  required String cityName,
  String? admin1,
  String? admin2,
  String? countryCode,
  required double lat,
  required double lon,
}) async {
  final cc = (countryCode ?? '').toUpperCase().trim();
  final inSkExtent = lat >= 47.73 && lat <= 49.61 && lon >= 16.83 && lon <= 22.58;
  if ((cc.isNotEmpty && cc != 'SK') || !inSkExtent) {
    await VystrahyHomeWidget.clear(showMapHint: false);
    return;
  }

  final snap = await fetchVystrahySnapshotForCity(
    cityName: cityName,
    admin1: admin1,
    admin2: admin2,
  );
  if (snap == null) {
    await VystrahyHomeWidget.clear(showMapHint: true);
    return;
  }
  if (!snap.hasWarning) {
    await VystrahyHomeWidget.clear(okres: snap.okres, showMapHint: true);
    return;
  }
  final primary = snap.primary;
  await VystrahyHomeWidget.update(
    hasWarning: true,
    title: snap.countTitleSk(),
    levelLine: snap.levelLine(),
    typesLine: snap.typesLine(),
    timing: snap.timingLine(DateTime.now()),
    okres: snap.okres,
    rank: snap.maxRank,
    javId: primary.jav,
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
