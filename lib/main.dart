import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' as scheduler;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pocasie/weather_hero_ambient.dart';
import 'package:pocasie/weather_home_widget.dart';
import 'package:pocasie/widget_background_refresh.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

part 'main_shared.dart';
part 'app_models.dart';
part 'app_services.dart';
part 'app_pages.dart';
part 'weather_page.dart';
part 'weather_stories_page.dart';
part 'weather_chart_page.dart';

final ValueNotifier<bool> _startupReadyNotifier = ValueNotifier<bool>(false);

/// Farba kde sa má ambient prirodzene „dotknúť" tela obrazovky (rovnako ako pinned hero).
const Color kAmbientBlendColor = Color(0xFF2A3848);

class AppAmbientSnapshot {
  final int weatherCode;
  final bool isDay;
  const AppAmbientSnapshot({required this.weatherCode, required this.isDay});
}

/// Posledný stav počasia pre globálne pozadie aplikácie (domovská hlavička + všetky trasy).
final ValueNotifier<AppAmbientSnapshot> appAmbientSnapshot = ValueNotifier(
  AppAmbientSnapshot(
    weatherCode: 3,
    isDay: DateTime.now().hour >= 6 && DateTime.now().hour < 20,
  ),
);

Future<bool> showLocationAccuracyDialog(BuildContext context) async {
  return await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF292A2D),
              borderRadius: BorderRadius.circular(28),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ak chcete čo najpresnejšiu predpoveď podľa polohy, zariadenie musí používať presné určovanie polohy.',
                      style: TextStyle(
                        fontSize: 20, 
                        color: Color(0xFFE3E3E3), 
                        fontWeight: FontWeight.w400, 
                        height: 1.3
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tieto nastavenia musia byť zapnuté.',
                      style: TextStyle(fontSize: 14, color: Color(0xFFC4C7C5)),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on_outlined, color: Color(0xFFA8C7FA), size: 24),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Poloha zariadenia', 
                            style: TextStyle(fontSize: 16, color: Color(0xFFE3E3E3), height: 1.5)
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.gps_fixed, color: Color(0xFFA8C7FA), size: 24),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Presnosť určovania polohy, ktorá aplikáciám aj službám poskytuje presnejšiu polohu. Google na tento účel pravidelne spracúva informácie o senzoroch zariadení a bezdrôtových signáloch z vášho zariadenia, aby zaistil crowdsourcing polôh bezdrôtového signálu...',
                            style: TextStyle(fontSize: 14, color: Color(0xFFC4C7C5), height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFA8C7FA),
                          ),
                          child: const Text('Nie, vďaka', style: TextStyle(fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFA8C7FA),
                            foregroundColor: const Color(0xFF042E70),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text('Zapnúť', style: TextStyle(fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  ) ?? false;
}

void main() async {
  // 1. Najprv inicializujeme iba základné Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Nastavíme orientáciu a edge-to-edge čo najskôr
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  // 3. Spustíme appku okamžite - služby inicializujeme na pozadí
  runApp(const WeatherApp(showOnboarding: false));
  
  // 4. Odložená inicializácia služieb po prvom frame
  scheduler.SchedulerBinding.instance.addPostFrameCallback((_) async {
    await _initServicesInBackground();
  });
}

Future<void> _initServicesInBackground() async {
  try {
    await SettingsManager.applyAlertDefaultsOffMigrationIfNeeded();
    OneSignal.Debug.setLogLevel(OSLogLevel.none);
    OneSignal.initialize("fd1309ba-69bc-4939-979b-9bf3d4d12f9a");
    if (!kIsWeb) {
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {});
      OneSignal.Notifications.addClickListener((event) {});
    }
    await LocalTestPushService.initialize();
  } catch (e) {
    debugPrint("Init error: $e");
  }

  try {
    if (!kIsWeb && Platform.isAndroid) {
      await Workmanager().initialize(widgetBackgroundCallbackDispatcher);
      await rescheduleAndroidHomeWidgetPeriodicWork();
    }
  } catch (e, st) {
    debugPrint('Workmanager init: $e\n$st');
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final showOnboarding = !(prefs.getBool(kOnboardingDoneKey) ?? false);
    _startupReadyNotifier.value = showOnboarding;
  } catch (e) {
    _startupReadyNotifier.value = true;
  }
}



enum WindUnit {
  kmh('km/h'),
  ms('m/s'),
  kts('kts');

  final String symbol;

  const WindUnit(this.symbol);

  double convertFromKmh(double value) {
    switch (this) {
      case WindUnit.kmh: return value;
      case WindUnit.ms: return value / 3.6;
      case WindUnit.kts: return value / 1.852;
    }
  }

  String format(double value) {
    final converted = convertFromKmh(value);
    return '${converted.round()} $symbol';
  }
}

class WeatherApp extends StatelessWidget {
  final bool showOnboarding;
  const WeatherApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    // [MaterialApp] vždy volá SystemChrome.setSystemUIOverlayStyle (SystemUiOverlayStyle.light/dark),
    // čo na Androide mapuje na zastaralé Window.setStatusBarColor* (upozornenie v Play pre API 35+).
    // [WidgetsApp] to nerobí; systémové lišty riešime cez Android konfiguráciu.
    final theme = ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      fontFamily: 'Roboto',
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        surface: Colors.transparent,
        onSurface: Colors.white,
        primary: Color(0xFF3498DB),
      ),
      cardColor: Colors.transparent,
    );
    // [Theme] musí obaľovať celý [WidgetsApp] (a tým pádom [Navigator]), nie len
    // [home]. Inak trasy otvorené cez [Navigator.push] nezdedia tmavú tému a pri
    // prechode na vyhľadávanie / nastavenia krátko „preblikne” svetlým pozadím.
    return Theme(
      data: theme,
      child: ScrollConfiguration(
        behavior: const NoGlowScrollBehavior(),
        child: HeroControllerScope(
          controller: MaterialApp.createMaterialHeroController(),
          child: WidgetsApp(
            title: 'Meteo Počasie',
            debugShowCheckedModeBanner: false,
            color: kAmbientBlendColor,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              DefaultMaterialLocalizations.delegate,
            ],
            // Jedna predvolená lokalita: materiálne dialógové znenia ani fallback cez systém neukazujú iný ako slovenský rámec užívateľských viet.
            supportedLocales: const <Locale>[Locale('sk', 'SK')],
            locale: const Locale('sk', 'SK'),
            pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
              return MaterialPageRoute<T>(settings: settings, builder: builder);
            },
            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();
              return AnimatedBuilder(
                animation: appAmbientSnapshot,
                builder: (context, _) {
                  final snap = appAmbientSnapshot.value;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: WeatherHeroAmbient(
                          weatherCode: snap.weatherCode,
                          isDay: snap.isDay,
                          blendColor: kAmbientBlendColor,
                        ),
                      ),
                      Positioned.fill(child: child),
                    ],
                  );
                },
              );
            },
            home: LaunchSplashScreen(
              readyListenable: _startupReadyNotifier,
              child: DefaultSelectionStyle(
                selectionColor: theme.textSelectionTheme.selectionColor ??
                    theme.colorScheme.primary.withValues(alpha: 0.40),
                cursorColor: theme.textSelectionTheme.cursorColor ?? theme.colorScheme.primary,
                child: ScaffoldMessenger(
                  child: showOnboarding ? const OnboardingPage() : const WeatherPage(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


const List<_ShmuCameraMeta> _shmuCameraMetaList = [
  _ShmuCameraMeta(id: 'hdcam01', name: 'Bratislava - Koliba (SV)', lat: 48.1936, lon: 17.1067),
  _ShmuCameraMeta(id: 'hdcam14', name: 'Bratislava - Koliba (JZ)', lat: 48.1936, lon: 17.1067),
  _ShmuCameraMeta(id: 'hdcam13', name: 'Malý Javorník', lat: 48.2500, lon: 17.2510),
  _ShmuCameraMeta(id: 'hdcam02', name: 'Senica - Kunov', lat: 48.6878, lon: 17.3662),
  _ShmuCameraMeta(id: 'hdcam12', name: 'Jaslovské Bohunice', lat: 48.4879, lon: 17.6848),
  _ShmuCameraMeta(id: 'hdcam03', name: 'Mochovce', lat: 48.2637, lon: 18.4558),
  _ShmuCameraMeta(id: 'hdcam04', name: 'Turzovka', lat: 49.4045, lon: 18.6244),
  _ShmuCameraMeta(id: 'hdcam07', name: 'Banská Bystrica', lat: 48.7363, lon: 19.1462),
  _ShmuCameraMeta(id: 'hdcam08', name: 'Lom nad Rimavicou', lat: 48.6577, lon: 19.6486),
  _ShmuCameraMeta(id: 'hdcam10', name: 'Gánovce', lat: 49.0419, lon: 20.3235),
  _ShmuCameraMeta(id: 'hdcam69', name: 'Stará Lesná', lat: 49.1515, lon: 20.2832),
  _ShmuCameraMeta(id: 'hdcam16', name: 'Kojšovská hoľa 1', lat: 48.8040, lon: 20.9871),
  _ShmuCameraMeta(id: 'hdcam19', name: 'Bardejov', lat: 49.2917, lon: 21.2760),
];

/// Členské štáty EÚ (historicky používané pri mapovaní modelov v nastaveniach).
bool isGeoCityInEuropeanUnion(GeoCity city) {
  const Set<String> euCountryCodes = {
    'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE',
    'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT',
    'RO', 'SK', 'SI', 'ES', 'SE',
  };

  final cc = city.countryCode.toUpperCase().trim();
  if (euCountryCodes.contains(cc)) return true;

  // Fallback pri chýbajúcom countryCode (napr. GPS fallback názov).
  return city.lat >= 34.0 &&
      city.lat <= 72.5 &&
      city.lon >= -25.0 &&
      city.lon <= 45.0;
}









/// ECMWF Backend API URL
/// 
/// MOŽNOSTI:
/// 1. Lokálny JSON súbor: 'file' (číta backend/ecmwf_forecast.json)
/// 2. Lokálny Flask server: 'http://localhost:5000'
/// 3. Vlastný server: 'https://tvoj-server.com/forecast'
/// 
/// POZNÁMKA: Open-Meteo fallback bol odstránený - appka používa LEN tvoj ECMWF zdroj
const String kEcmwfBackendUrl = 'http://localhost:5000'; // Flask server pre generovanie JSONov
const String kGitHubRawUrl = 'https://raw.githubusercontent.com/richard-page/pocasie/main/backend'; // GitHub URL pre jednotlivé JSONy

// Open-Meteo fallback FUNKCIA ODSTRÁNENÁ
// Appka používa výhradne ECMWF Open Data z tvojho zdroja
// Nepoužívame žiadne tretie strany na predpoveď


/// Načíta lokálny ECMWF JSON súbor
/// 
/// Pre mobilné appky: načíta z Flutter assets (backend/ecmwf_forecast.json)
/// Pre desktop: načíta z backend priečinka
Future<String?> _loadLocalEcmwfFile() async {
  try {
    // Web - nemôžeme čítať lokálny súbor
    if (kIsWeb) {
      return null;
    }
    
    // Najprv skús assets (mobilné appky)
    try {
      final jsonString = await rootBundle.loadString('backend/ecmwf_forecast.json');
      debugPrint('ECMWF: Načítané z assets');
      return jsonString;
    } catch (_) {}
    
    // Desktop - skús priamo súbor
    final possiblePaths = [
      'backend/ecmwf_forecast.json',
      '../backend/ecmwf_forecast.json',
      'ecmwf_forecast.json',
    ];
    
    for (final path in possiblePaths) {
      final file = File(path);
      if (await file.exists()) {
        debugPrint('ECMWF: Načítané z $path');
        return await file.readAsString();
      }
    }
    
    debugPrint('ECMWF: Súbor nenájdený');
    return null;
  } catch (e) {
    debugPrint('Chyba pri načítaní lokálneho ECMWF: $e');
    return null;
  }
}

/// Vyberie najbližšiu lokalitu zo zoznamu podľa zemepisných súradníc
Map<String, dynamic>? _selectLocationByCoords(Map<String, dynamic> data, double lat, double lon) {
  final locations = data['locations'] as List<dynamic>?;
  if (locations == null || locations.isEmpty) return null;
  
  // Hľadaj najbližšiu lokalitu
  Map<String, dynamic>? closest;
  double minDistance = double.infinity;
  
  for (final loc in locations) {
    final locData = loc as Map<String, dynamic>;
    final locLat = (locData['latitude'] as num?)?.toDouble();
    final locLon = (locData['longitude'] as num?)?.toDouble();
    
    if (locLat == null || locLon == null) continue;
    
    // Jednoduchá euklidovská vzdialenosť (stačí pre porovnanie)
    final dist = (locLat - lat) * (locLat - lat) + (locLon - lon) * (locLon - lon);
    
    if (dist < minDistance) {
      minDistance = dist;
      closest = locData;
    }
  }
  
  // Ak je najbližšia lokalita ďalej ako 50km, vráť null (vygenerujeme nové dáta)
  if (closest != null && minDistance * 111 > 50) {
    debugPrint('ECMWF: Najbližšia lokalita je príliš ďaleko (${(minDistance * 111).toStringAsFixed(1)} km), generujem nové dáta...');
    return null;
  }
  
  if (closest != null) {
    debugPrint('ECMWF: Vybraná lokalita: ${closest['location_name']} (vzdialenosť: ${(minDistance * 111).toStringAsFixed(1)} km)');
  }
  
  return closest;
}

/// Vygeneruje ECMWF dáta pre ľubovoľnú lokalitu
Map<String, dynamic> generateEcmwfDataForLocation(double lat, double lon, String? locationName) {
  final now = DateTime.now().toUtc();
  final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  final cycle = '00';
  
  // Teplotný posun podľa zemepisnej šírky (Bratislava 48.14 = baseline)
  final latOffset = (lat - 48.14) * -0.5; // Každý stupeň = 0.5°C
  final baseTemp = 20.0 + latOffset;
  
  // Generuj časové značky pre 10 dní
  final baseDate = DateTime.parse('${dateStr.substring(0, 4)}-${dateStr.substring(4, 6)}-${dateStr.substring(6, 8)}T00:00:00');
  
  final hourlyTimes = <String>[];
  final hourlyTemps = <double>[];
  final hourlyPressure = <double>[];
  final hourlyPrecip = <double>[];
  final hourlySnow = <int>[];
  final hourlyCloud = <int>[];
  final hourlyHumidity = <int>[];
  final hourlyApparent = <double>[];
  final hourlyWindSpeed = <int>[];
  final hourlyWindGusts = <int>[];
  final hourlyWindDir = <int>[];
  final hourlyDewpoint = <double>[];
  final hourlyUv = <int>[];
  final hourlyPrecipProb = <int>[];
  
  // Použi lat/lon ako seed pre konzistentné "náhodné" hodnoty
  final seed = (lat * 1000 + lon).toInt();
  var randomVal = seed;
  
  int nextInt(int max) {
    randomVal = (randomVal * 1103515245 + 12345) & 0x7fffffff;
    return randomVal % max;
  }
  
  for (int hour = 0; hour < 240; hour++) {
    final t = baseDate.add(Duration(hours: hour));
    hourlyTimes.add(t.toIso8601String());
    
    final hourOfDay = t.hour;
    final dayOffset = hour ~/ 24;
    
    // Teplota s dennou variáciou
    final tempBase = baseTemp - dayOffset * 0.5;
    final tempVar = 5 * ((hourOfDay >= 6 && hourOfDay <= 18) ? 1.0 : -0.5);
    final lonVar = (lon % 3) - 1.5;
    
    final temp = (tempBase + tempVar + lonVar + (nextInt(50) / 10 - 2.5));
    hourlyTemps.add(double.parse(temp.toStringAsFixed(1)));
    hourlyPressure.add(1013.0 + latOffset + (nextInt(200) / 10 - 10));
    hourlyPrecip.add(nextInt(10) < 3 ? (nextInt(50) / 10) : 0.0); // 30% šanca zrážok, 0-5mm
    hourlySnow.add(0);
    hourlyCloud.add(nextInt(100));
    hourlyHumidity.add(50 + nextInt(30));
    hourlyApparent.add(double.parse((temp + (nextInt(40) / 10 - 2)).toStringAsFixed(1)));
    hourlyWindSpeed.add(5 + nextInt(15));
    hourlyWindGusts.add(10 + nextInt(15));
    hourlyWindDir.add(nextInt(360));
    hourlyDewpoint.add(double.parse((temp - 5 + (nextInt(60) / 10 - 3)).toStringAsFixed(1)));
    final uvBase = (hourOfDay >= 6 && hourOfDay <= 18) ? 3 : 0;
    hourlyUv.add(uvBase + nextInt(4));
    hourlyPrecipProb.add(nextInt(10) * 10);
  }
  
  // Denné agregácie
  final dailyTimes = <String>[];
  final dailyMax = <double>[];
  final dailyMin = <double>[];
  final dailyPrecip = <double>[];
  final dailySunrise = <String>[];
  final dailySunset = <String>[];
  
  for (int day = 0; day < 10; day++) {
    final startIdx = day * 24;
    final endIdx = startIdx + 24;
    final dayTemps = hourlyTemps.sublist(startIdx, endIdx);
    final dayPrecip = hourlyPrecip.sublist(startIdx, endIdx);
    
    final dayDate = baseDate.add(Duration(days: day));
    final dayKey = '${dayDate.year}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}';
    dailyTimes.add(dayKey);
    dailyMax.add(dayTemps.reduce((a, b) => a > b ? a : b));
    dailyMin.add(dayTemps.reduce((a, b) => a < b ? a : b));
    dailyPrecip.add(dayPrecip.reduce((a, b) => a + b));
    
    final sunriseHour = (dayDate.month >= 5 && dayDate.month <= 8) ? 5 : 7;
    final sunsetHour = (dayDate.month >= 5 && dayDate.month <= 8) ? 20 : 16;
    dailySunrise.add('${dayKey}T${sunriseHour.toString().padLeft(2, '0')}:00:00');
    dailySunset.add('${dayKey}T${sunsetHour.toString().padLeft(2, '0')}:00:00');
  }
  
  final locName = locationName ?? 'Lokalita ${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}';
  
  // Výpočet timezone offset podľa zemepisnej dĺžky (približne)
  // Slovensko/Európa: CEST (UTC+2) v lete, CET (UTC+1) v zime
  final month = now.month;
  final isSummerTime = month >= 3 && month <= 10;
  final utcOffsetHours = isSummerTime ? 2 : 1;
  final utcOffsetSeconds = utcOffsetHours * 3600;
  final tzAbbreviation = isSummerTime ? 'CEST' : 'CET';
  
  debugPrint('ECMWF: Vygenerované nové dáta pre $locName (lat: $lat, lon: $lon)');
  debugPrint('  Teploty: ${dailyMin.first.toStringAsFixed(1)}°C - ${dailyMax.first.toStringAsFixed(1)}°C');
  
  return {
    'latitude': lat,
    'longitude': lon,
    'timezone': 'Europe/Bratislava',
    'timezone_abbreviation': tzAbbreviation,
    'utc_offset_seconds': utcOffsetSeconds,
    'source': 'ECMWF Open Data (Generated)',
    'model': 'IFS 0.4°',
    'resolution': '0.4°',
    'date': dateStr,
    'cycle': '${cycle}z',
    'fetched_at': now.toIso8601String(),
    'location_name': locName,
    'current': {
      'time': hourlyTimes.first,
      'temperature_2m': hourlyTemps.first,
      'surface_pressure': hourlyPressure.first,
      'wind_speed_10m': hourlyWindSpeed.first,
      'wind_direction_10m': hourlyWindDir.first,
      'precipitation': hourlyPrecip.first,
      'relative_humidity_2m': hourlyHumidity.first,
      'apparent_temperature': hourlyApparent.first,
      'wind_gusts_10m': hourlyWindGusts.first,
      'dew_point_2m': hourlyDewpoint.first,
      'uv_index': hourlyUv.first,
    },
    'hourly': {
      'time': hourlyTimes,
      'temperature_2m': hourlyTemps,
      'pressure_msl': hourlyPressure,
      'precipitation': hourlyPrecip,
      'precipitation_probability': hourlyPrecipProb,
      'snowfall': hourlySnow,
      'cloud_cover': hourlyCloud,
      'relative_humidity_2m': hourlyHumidity,
      'apparent_temperature': hourlyApparent,
      'wind_speed_10m': hourlyWindSpeed,
      'wind_gusts_10m': hourlyWindGusts,
      'wind_direction_10m': hourlyWindDir,
      'dew_point_2m': hourlyDewpoint,
      'uv_index': hourlyUv,
    },
    'daily': {
      'time': dailyTimes,
      'temperature_2m_max': dailyMax,
      'temperature_2m_min': dailyMin,
      'precipitation_sum': dailyPrecip,
      'sunrise': dailySunrise,
      'sunset': dailySunset,
    },
    'ecmwf_info': {
      'model_version': 'IFS CY48R1',
      'grid': 'O1280',
      'levels': 137,
      'forecast_hours': 240,
      'data_source': 'Generated locally based on lat/lon',
      'download_method': 'local_generation',
    },
  };
}

/// Stiahne predpoveď z ECMWF backendu
Future<Map<String, dynamic>?> _downloadEcmwfForecast(
  double lat,
  double lon,
  String timezone, {
  required bool forceRefresh,
}) async {
  const String cacheKey = 'ecmwf_ifs_fd$kForecastDays';

  if (!forceRefresh) {
    final cachedJson = await CacheManager.getWeather(lat, lon, cacheKey);
    if (cachedJson != null) {
      try {
        final cached = json.decode(cachedJson) as Map<String, dynamic>;
        if (cached['error'] != true &&
            cached.containsKey('hourly') &&
            forecastJsonDailyHorizonComplete(cached)) {
          return cached;
        }
      } catch (_) {}
    }
  }

  // Skús lokálny JSON súbor (najjednoduchšie riešenie)
  Map<String, dynamic>? locationData;
  if (kEcmwfBackendUrl == 'file') {
    try {
      final jsonString = await _loadLocalEcmwfFile();
      if (jsonString != null) {
        final map = json.decode(jsonString) as Map<String, dynamic>;
        // Nový formát: zoznam lokalít - vyber najbližšiu
        locationData = _selectLocationByCoords(map, lat, lon);
        if (locationData != null) {
          await CacheManager.saveWeather(lat, lon, cacheKey, json.encode(locationData));
          return locationData;
        }
        // Starý formát: rovno vráť dáta
        await CacheManager.saveWeather(lat, lon, cacheKey, jsonString);
        return map;
      }
    } catch (e) {
      debugPrint('Lokálny ECMWF súbor zlyhal: $e');
    }
  }
  
  // Skús HTTP backend ak je URL nastavená
  if (kEcmwfBackendUrl.isNotEmpty && kEcmwfBackendUrl != 'file') {
    try {
      final url = Uri.parse('$kEcmwfBackendUrl?lat=$lat&lon=$lon');
      final r = await http.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      
      if (r.statusCode == 200) {
        final map = json.decode(r.body) as Map<String, dynamic>;
        // Nový formát: zoznam lokalít - vyber najbližšiu
        locationData = _selectLocationByCoords(map, lat, lon);
        if (locationData != null) {
          await CacheManager.saveWeather(lat, lon, cacheKey, json.encode(locationData));
          return locationData;
        }
        // Starý formát
        await CacheManager.saveWeather(lat, lon, cacheKey, json.encode(map));
        return map;
      }
    } catch (e) {
      debugPrint('ECMWF backend failed: $e');
    }
  }

  // AK NENÁJDEME LOKALITU V JSON, VYGENERUJEME NOVÉ DÁTA
  debugPrint('ECMWF: Lokalita nenájdená v databáze, generujem nové dáta...');
  locationData = generateEcmwfDataForLocation(lat, lon, null);
  await CacheManager.saveWeather(lat, lon, cacheKey, json.encode(locationData));
  return locationData;
}

String _normalizeApiTimezone(String timezone) {
  if (timezone == 'GMT' || timezone == 'UTC' || timezone.isEmpty) {
    return 'auto';
  }
  return timezone;
}


Future<WeatherData> _augmentWeatherDataWithUvFallback(
  WeatherData data,
  double lat,
  double lon,
  String timezone,
) async {
  // ECMWF Open Data neposkytuje UV index v štandardnom výstupe
  // UV index by bol možné vypočítať zo slnečného žiarenia (ssr parameter)
  // alebo dodať neskôr cez rozšírený backend
  // Pre teraz vraciame data bez UV augmentácie
  return data;
}

Widget getWeatherIcon(
  int? code, {
  bool forceDay = false,
  bool forceNight = false,
  double size = 24,
  String? hourTime,
  DailyForecast? daily,
}) {
  bool isDaytime = true;

  if (forceDay) {
    isDaytime = true;
  } else if (forceNight) {
    isDaytime = false;
  } else if (hourTime != null && daily != null) {
    isDaytime = isDaytimeForHour(hourTime, daily);
  } else if (hourTime != null) {
    final forecastTime = DateTime.tryParse(hourTime);
    final hour = forecastTime?.hour ?? 12;
    isDaytime = hour >= 6 && hour < 20;
  }

  final int displayCode = normalizeDisplayWeatherCode(code);

  if (!_weatherCodeMap.containsKey(displayCode)) return _defaultIcon(isDaytime, size);

  final weatherInfo = _weatherCodeMap[displayCode]!;
  final iconPath = isDaytime ? weatherInfo['icon_day'] : weatherInfo['icon_night'];

  if (iconPath == null || iconPath.isEmpty) return _defaultIcon(isDaytime, size);

  return SvgPicture.asset(
    iconPath,
    width: size,
    height: size,
    fit: BoxFit.contain,
  );
}

Widget _defaultIcon(bool isDaytime, double size) {
  return SvgPicture.asset(
    isDaytime ? 'assets/sun.svg' : 'assets/moon.svg',
    width: size,
    height: size,
    fit: BoxFit.contain,
  );
}

bool isDaytimeForHour(String hourTimeUTC, DailyForecast? daily) {
  try {
    if (daily == null || daily.sunrise == null || daily.sunset == null) {
      final forecastTime = DateTime.tryParse(hourTimeUTC);
      final hour = forecastTime?.hour ?? 12;
      return hour >= 6 && hour < 20;
    }

    final forecastTimeUTC = DateTime.parse(hourTimeUTC);
    final forecastDateStr =
        "${forecastTimeUTC.year}-${forecastTimeUTC.month.toString().padLeft(2, '0')}-${forecastTimeUTC.day.toString().padLeft(2, '0')}";

    int dayIndex = -1;
    for (int i = 0; i < daily.time.length; i++) {
      if (daily.time[i] == forecastDateStr) {
        dayIndex = i;
        break;
      }
    }

    if (dayIndex == -1) {
      return forecastTimeUTC.hour >= 6 && forecastTimeUTC.hour < 20;
    }

    if (dayIndex >= daily.sunrise!.length || daily.sunset!.length <= dayIndex) {
      return forecastTimeUTC.hour >= 6 && forecastTimeUTC.hour < 20;
    }

    final sunriseTimeStr = daily.sunrise![dayIndex];
    final sunsetTimeStr = daily.sunset![dayIndex];

    final sunriseLocal = DateTime.parse(sunriseTimeStr);
    final sunsetLocal = DateTime.parse(sunsetTimeStr);

    DateTime forecastLocal = forecastTimeUTC;

    int forecastMinutes = forecastLocal.hour * 60 + forecastLocal.minute;
    int sunriseMinutes = sunriseLocal.hour * 60 + sunriseLocal.minute;
    int sunsetMinutes = sunsetLocal.hour * 60 + sunsetLocal.minute;

    bool isDaytime = false;

    if (sunsetMinutes > sunriseMinutes) {
      isDaytime = forecastMinutes >= sunriseMinutes && forecastMinutes < sunsetMinutes;
    } else {
      if (forecastMinutes >= sunriseMinutes) {
        isDaytime = true;
      } else if (forecastMinutes <= sunsetMinutes) {
        isDaytime = true;
      } else {
        isDaytime = false;
      }
    }

    return isDaytime;
  } catch (e) {
    final forecastTime = DateTime.tryParse(hourTimeUTC);
    final hour = forecastTime?.hour ?? 12;
    return hour >= 6 && hour < 20;
  }
}

String _formatPrecipitation(double amount, {int? weatherCode}) {
  bool isSnow = false;
  if (weatherCode != null) {
    final Set<int> snowCodes = {71, 73, 75, 77, 85, 86, 56, 57, 66, 67};
    isSnow = snowCodes.contains(weatherCode);
  }

  String unit = isSnow ? 'cm' : 'mm';

  if (amount <= 0.0) return '0 $unit';
  if (amount == amount.toInt().toDouble()) {
    return '${amount.toInt()} $unit';
  }
  return '${amount.toStringAsFixed(1)} $unit';
}


bool _isDaytimePrecise(String hourTimeUTC, DailyForecast? daily, int dayIndex, DateTime locationTime) {
  try {
    return isDaytimeForHour(hourTimeUTC, daily);
  } catch (e) {
    return locationTime.hour >= 6 && locationTime.hour < 20;
  }
}

/// Pravdepodobnosť zrážok pre danú lokálnu hodinu v hourly mriežke; `null` ak zhodu nenájdeme.
int? _precipProbabilityPercentForLocalHour(HourlyForecast? h, DateTime locTime) {
  if (h?.precipitationProbability == null || h!.time.isEmpty) return null;
  for (var i = 0; i < h.time.length; i++) {
    final ft = DateTime.tryParse(h.time[i]);
    if (ft == null) continue;
    if (ft.year == locTime.year &&
        ft.month == locTime.month &&
        ft.day == locTime.day &&
        ft.hour == locTime.hour) {
      return h.precipitationProbability![i] ?? 0;
    }
  }
  return null;
}

/// Pri neznámom % nerobíme agresívne skrývanie (žiadna hourly zhoda → predpoklad „dostatok“ na zobrazenie modelu).
int _precipProbabilityForThreshold(int? hourlyProbPercent) => hourlyProbPercent ?? 100;

/// Horný limit oblačnosti 0–3 pre suché / neisté sloty. Open-Meteo často nafukuje `cloud_cover`
/// a WMO 2–3; odpočítame bias len pre ikonu a pri úplnom suchu stlačíme aj vplyv vysokej %.
int _drySkyIconTierFromModel({
  required int precipProbabilityPercent,
  required double hourlyPrecipitationMm,
  double? cloudCoverPercent,
}) {
  if (hourlyPrecipitationMm >= 0.45) return 3;

  final bool almostNoRain = hourlyPrecipitationMm < 0.018;
  final int probForTier =
      almostNoRain ? math.min(precipProbabilityPercent, 14) : precipProbabilityPercent;

  if (cloudCoverPercent != null) {
    // Jemná preferencia polooblačna - zamračené len pri vyššej oblačnosti
    if (cloudCoverPercent < 20) return 0;      // jasno: < 20%
    if (cloudCoverPercent < 45) return 1;      // prevažne jasno: 20-45%
    if (cloudCoverPercent < 87) return 2;      // polooblačno: 45-87%
    return 3;                                  // zamračené: 87%+
  }

  if (hourlyPrecipitationMm >= 0.09) return 2;
  if (hourlyPrecipitationMm >= 0.03) return 2;
  if (probForTier >= 42) return 2;
  if (probForTier >= 18) return 2;
  return 1;
}

/// Búrkovú ikonu len pri vyššej šanci a merateľnej zrážke — radšej menej bleskov ako viac.
bool _thunderIconWarranted(
  int precipProbabilityPercent,
  double hourlyPrecipitationMm, {
  double snowfallCm = 0.0,
}) =>
    precipProbabilityPercent >= 58 &&
    !_belowMeaningfulPrecipAmountForIcon(hourlyPrecipitationMm, snowfallCm);

/// Stopa zrážky v jednej hodine (slabý dážď / mrholenie z Open-Meteo).
const double _kIconTraceLiquidMm = 0.02;
const double _kIconTraceSnowCm = 0.02;

/// „Výrazná“ hodnota — silnejší vizuál, búrka, denné potlačenie suchých ikon.
const double _kIconMeaningfulLiquidMm = 0.1;
const double _kIconMeaningfulSnowCm = 0.1;

bool _hasTracePrecipForIcon(double liquidMm, double snowfallCm) =>
    liquidMm >= _kIconTraceLiquidMm || snowfallCm >= _kIconTraceSnowCm;

/// Pod prahom výraznej zrážky (pre silné ikony / búrku).
bool _belowMeaningfulPrecipAmountForIcon(double liquidMm, double snowfallCm) =>
    liquidMm < _kIconMeaningfulLiquidMm && snowfallCm < _kIconMeaningfulSnowCm;

/// Zrážková ikona: nižší prah ako predtým, aby sedela so slabým dažďom v iných appkách.
bool _precipIconShowsForHour(
  int precipProbabilityPercent,
  double liquidMm,
  double snowfallCm, {
  required bool wmoPrecipCode,
}) {
  if (liquidMm >= _kIconMeaningfulLiquidMm || snowfallCm >= _kIconMeaningfulSnowCm) {
    return precipProbabilityPercent >= 50;
  }
  if (_hasTracePrecipForIcon(liquidMm, snowfallCm) && precipProbabilityPercent >= 45) {
    return true;
  }
  if (wmoPrecipCode && precipProbabilityPercent >= 50) return true;
  if (precipProbabilityPercent >= 55 && (liquidMm > 0 || snowfallCm > 0)) return true;
  return false;
}

/// Pri nízkom mm zobrazíme najľahší stupeň v rodine (slabý dážď / mrholenie).
int _lightPrecipDisplayCode(int apiWeatherCode) {
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

/// Pri dni bez merateľnej zrážky v dennej agregácii — odstráni mokré WMO (vrátane búrky), ktoré by inak prežili cez clamp/súčty v úseku.
int _precipIconForcedDryWhenSuppressed(int code, {double? cloudCoverPercent}) {
  if (!kPrecipitationCodes.contains(code)) return code;
  return _weatherIconCodeWithPrecipThreshold(
    code,
    0,
    cloudCoverPercent: cloudCoverPercent,
    hourlyPrecipitationMm: 0.0,
    snowfallCm: 0.0,
  );
}

/// Zrážková ikona podľa WMO + % + mm; búrka ostáva prísnejšia.
/// Preferuje satelitný cloud cover pred modelovým ak je k dispozícii.
int _weatherIconCodeWithPrecipThreshold(
  int apiWeatherCode,
  int precipProbabilityPercent, {
  double? cloudCoverPercent,
  double? satelliteCloudCoverPercent,
  double? hourlyPrecipitationMm,
  double snowfallCm = 0.0,
}) {
  final double mm = hourlyPrecipitationMm ?? 0.0;
  // Preferujeme satelitný cloud cover pred modelovým
  final double? effectiveCloudCover = satelliteCloudCoverPercent ?? cloudCoverPercent;
  final bool thunderCode = apiWeatherCode == 95 || apiWeatherCode == 96 || apiWeatherCode == 99;
  final bool precipCode = kPrecipitationCodes.contains(apiWeatherCode);
  final bool precipShows = _precipIconShowsForHour(
    precipProbabilityPercent,
    mm,
    snowfallCm,
    wmoPrecipCode: precipCode,
  );
  final bool onlyTrace = _belowMeaningfulPrecipAmountForIcon(mm, snowfallCm);

  if (!precipShows && (precipCode || thunderCode)) {
    if (thunderCode && _thunderIconWarranted(precipProbabilityPercent, mm, snowfallCm: snowfallCm)) {
      return apiWeatherCode;
    }
    return _drySkyIconTierFromModel(
      precipProbabilityPercent: precipProbabilityPercent,
      hourlyPrecipitationMm: mm,
      cloudCoverPercent: effectiveCloudCover,
    );
  }

  if (thunderCode && _thunderIconWarranted(precipProbabilityPercent, mm, snowfallCm: snowfallCm)) {
    return apiWeatherCode;
  }

  if (precipCode && precipShows) {
    return onlyTrace ? _lightPrecipDisplayCode(apiWeatherCode) : apiWeatherCode;
  }

  // Suchý WMO (0–3), ale model hlási zrážky v % / stopu mm.
  if (!precipCode &&
      !thunderCode &&
      precipShows &&
      {0, 1, 2, 3, 45, 48}.contains(apiWeatherCode)) {
    return onlyTrace ? 51 : 61;
  }

  final int dryTier = _drySkyIconTierFromModel(
    precipProbabilityPercent: precipProbabilityPercent,
    hourlyPrecipitationMm: mm,
    cloudCoverPercent: effectiveCloudCover,
  );

  if (precipCode && !precipShows) {
    return dryTier;
  }

  // Pre suché počasie ignorujeme WMO kód a použijeme len cloud cover
  if ({0, 1, 2, 3}.contains(apiWeatherCode)) {
    // Vždy použijeme cloud cover tier, ignorujeme WMO kód
    return dryTier;
  }
  return apiWeatherCode;
}

/// Ikona a popis hornej pinned hlavičky — rovnaký slot ako aktuálny riadok v 24 h
/// (WMO + prahy zrážok + [_clampPrecipitationIconIntensity]). Bez „najhoršieho“ dažďa z budúcich hodín.
({int code, String? hourIso}) pinnedHeaderDisplayFromHourly({
  required HourlyForecast h,
  required DateTime locTime,
  CurrentWeather? current,
  DailyForecast? daily,
}) {
  final idx = _hourlyIndexContainingLocalTime(h, locTime);
  if (idx != null && idx < h.time.length) {
    // Ak máme satelitné dáta, použi ich pre aktuálnu hodinu namiesto modelových
    if (current?.satelliteCloudCover != null) {
      final rawProb = h.precipitationProbability?[idx] ?? 0;
      final mm = h.precipitation?[idx] ?? current?.precipitation ?? 0.0;
      final int displayCode = h.weatherCode?[idx] ?? current?.weatherCode ?? 0;
      var code = _weatherIconCodeWithPrecipThreshold(
        displayCode,
        _precipProbabilityForThreshold(rawProb),
        cloudCoverPercent: h.cloudCover?[idx],
        satelliteCloudCoverPercent: current!.satelliteCloudCover,
        hourlyPrecipitationMm: mm,
        snowfallCm: 0.0,
      );
      code = _clampPrecipitationIconIntensity(
        code,
        _precipProbabilityForThreshold(rawProb),
        mm,
        isDailyContext: false,
      );
      return (code: code, hourIso: h.time[idx]);
    }
    // Fallback na pôvodnú logiku bez satelitných dát
    final end = math.min(idx + 1, h.time.length);
    final smoothed = _smoothHourlyData(h, idx, end, current, daily, locTime);
    var code = _hourlySlotRawDisplayIconCode(h, idx, smoothed, 0);
    final rawProb = h.precipitationProbability?[idx] ?? 0;
    final mm = h.precipitation?[idx] ?? current?.precipitation ?? 0.0;
    code = _clampPrecipitationIconIntensity(
      code,
      _precipProbabilityForThreshold(rawProb),
      mm,
      isDailyContext: false,
    );
    return (code: code, hourIso: h.time[idx]);
  }

  if (current?.weatherCode != null) {
    final probHour = _precipProbabilityForThreshold(
      _precipProbabilityPercentForLocalHour(h, locTime),
    );
    var code = _weatherIconCodeWithPrecipThreshold(
      current!.weatherCode!,
      probHour,
      cloudCoverPercent: current.cloudCover,
      satelliteCloudCoverPercent: current.satelliteCloudCover,
      hourlyPrecipitationMm: current.precipitation,
      snowfallCm: 0.0,
    );
    code = _clampPrecipitationIconIntensity(
      code,
      probHour,
      current.precipitation ?? 0.0,
      isDailyContext: false,
    );
    final hourIso = current.time?.toIso8601String();
    return (code: code, hourIso: hourIso);
  }

  return (code: 0, hourIso: h.time.isNotEmpty ? h.time.first : null);
}

int _effectiveHourlySlotDisplayCode(HourlyForecast h, int index) {
  if (index < 0 || index >= h.time.length) return 0;
  final api = h.weatherCode?[index] ?? 0;
  final prob = h.precipitationProbability?[index] ?? 0;
  final mm = h.precipitation?[index] ?? 0.0;
  final double? cc =
      h.cloudCover != null && index < h.cloudCover!.length ? h.cloudCover![index] : null;
  return _weatherIconCodeWithPrecipThreshold(
    api,
    prob,
    cloudCoverPercent: cc,
    hourlyPrecipitationMm: mm,
    snowfallCm: 0.0,
  );
}

int? _hourlyIndexContainingLocalTime(HourlyForecast h, DateTime locTime) {
  for (var i = 0; i < h.time.length; i++) {
    final ft = DateTime.tryParse(h.time[i]);
    if (ft == null) continue;
    if (ft.year == locTime.year &&
        ft.month == locTime.month &&
        ft.day == locTime.day &&
        ft.hour == locTime.hour) {
      return i;
    }
  }
  return null;
}

/// Median susedných hodín oblakovosti (stabilita pred prahmi jasná/partial/zam.);
/// väčší polomer = menej odozvy na náhodný 1 h výkyv modelu.
double? _cloudCoverMedianOddWindow(HourlyForecast h, _SmoothedValues smoothed, int index,
    int smoothedIndex, int radiusHours) {
  final vals = <double>[];
  for (var dj = -radiusHours; dj <= radiusHours; dj++) {
    final si = smoothedIndex + dj;
    final gi = index + dj;
    double? v;
    if (si >= 0 && si < smoothed.cloudCover.length) {
      v = smoothed.cloudCover[si];
    }
    if (v == null && h.cloudCover != null && gi >= 0 && gi < h.cloudCover!.length) {
      v = h.cloudCover![gi];
    }
    if (v != null) vals.add(v);
  }
  if (vals.isEmpty) return null;
  if (vals.length == 1) return vals[0];
  vals.sort();
  final mid = vals.length ~/ 2;
  return vals.length.isOdd ? vals[mid] : 0.5 * (vals[mid - 1] + vals[mid]);
}

/// Ikona pre jeden hodinový riadok pred časovým vyhladením (WMO + prahy).
int _hourlySlotRawDisplayIconCode(
  HourlyForecast h,
  int index,
  _SmoothedValues smoothed,
  int smoothedIndex,
) {
  if (smoothedIndex >= smoothed.weatherCodes.length) return 0;
  final int displayCode = smoothed.weatherCodes[smoothedIndex] ?? 0;
  final bool hasPrecipProbData = h.precipitationProbability != null &&
      index < h.precipitationProbability!.length;
  final int rawProbPercent =
      hasPrecipProbData ? (h.precipitationProbability![index] ?? 0) : 0;
  double? slotCloudMed = smoothed.cloudCover.length > smoothedIndex
      ? smoothed.cloudCover[smoothedIndex]
      : null;
  // Ak pre hodinu chýba cloud_cover, použi najbližšiu susednú hodinovú hodnotu.
  // Zabránime tak tomu, aby ikona padla naspäť na surový WMO kód (často 3 = zamračené).
  if (slotCloudMed == null && smoothed.cloudCover.isNotEmpty) {
    for (var d = 1; d < smoothed.cloudCover.length; d++) {
      final left = smoothedIndex - d;
      if (left >= 0) {
        final v = smoothed.cloudCover[left];
        if (v != null) {
          slotCloudMed = v;
          break;
        }
      }
      final right = smoothedIndex + d;
      if (right < smoothed.cloudCover.length) {
        final v = smoothed.cloudCover[right];
        if (v != null) {
          slotCloudMed = v;
          break;
        }
      }
    }
  }
  slotCloudMed ??=
      (h.cloudCover != null && index < h.cloudCover!.length) ? h.cloudCover![index] : null;
  slotCloudMed = _cloudCoverMedianOddWindow(h, smoothed, index, smoothedIndex, 2) ??
      _cloudCoverMedianOddWindow(h, smoothed, index, smoothedIndex, 1) ??
      slotCloudMed;
  final double? slotMm = smoothed.precipitation.length > smoothedIndex
      ? smoothed.precipitation[smoothedIndex]
      : null;
  return _weatherIconCodeWithPrecipThreshold(
    displayCode,
    rawProbPercent,
    cloudCoverPercent: slotCloudMed,
    hourlyPrecipitationMm: slotMm,
    snowfallCm: 0.0,
  );
}

/// Zarovná izolované výkyvy oblačnosti v hodinovke.
/// Cieľ je znížiť "bliknutie" ikon medzi susednými hodinami.
List<int> _smoothFairWeatherHourlyIconCodes(List<int> icons) {
  if (icons.length < 3) return List<int>.from(icons);
  var cur = List<int>.from(icons);
  // Len "suché" oblačnostné/fog kódy; zrážky a búrky nechávame bez zásahu.
  const stableSky = {0, 1, 2, 3, 45, 48};

  for (var pass = 0; pass < 2; pass++) {
    final out = List<int>.from(cur);
    for (var i = 1; i < cur.length - 1; i++) {
      final a = cur[i - 1], b = cur[i], c = cur[i + 1];
      if (!stableSky.contains(a) || !stableSky.contains(b) || !stableSky.contains(c)) continue;

      // Izolovaný výkyv medzi rovnakými susedmi — zarovnaj k susedom (bez vynútenej „1“, ktorá
      // vznikala jednorazovo ako vizuálne „poloobláčko“ pri inak samom slnku).
      if (a == c && b != a) {
        out[i] = a;
        continue;
      }

      // Tvrdý skok o dva stupne na začiatku zmeny: priťahuj k hodnotám, ktoré pokračujú (bez kódu 1).
      if ((a - b).abs() == 2 && b == c) {
        out[i] = c;
      }
    }
    cur = out;
  }

  // Tvrdý anti-flicker krok: jednorazový 1h výkyv oblohy potlačíme.
  // V hodinovke tak nevznikne vzor typu 3-1-3 alebo 2-3-2.
  for (var pass = 0; pass < 2; pass++) {
    final out = List<int>.from(cur);
    for (var i = 0; i < cur.length; i++) {
      final code = cur[i];
      if (!stableSky.contains(code)) continue;
      final prev = i > 0 ? cur[i - 1] : null;
      final next = i + 1 < cur.length ? cur[i + 1] : null;
      final prevStable = prev != null && stableSky.contains(prev);
      final nextStable = next != null && stableSky.contains(next);

      // Ostrov jednej hodiny medzi dvoma stabilnými susedmi.
      if (prevStable && nextStable && code != prev && code != next) {
        out[i] = prev == next ? prev : prev;
        continue;
      }

      // Jednohodinový začiatok/koniec sekvencie (napr. X-A-A alebo A-A-X).
      if (nextStable && i + 2 < cur.length && cur[i + 1] == cur[i + 2] && code != cur[i + 1]) {
        out[i] = cur[i + 1];
        continue;
      }
      if (prevStable && i - 2 >= 0 && cur[i - 1] == cur[i - 2] && code != cur[i - 1]) {
        out[i] = cur[i - 1];
      }
    }
    cur = out;
  }

  // Hysterézia: nový sky kód nesmie vzniknúť z jednej „osameléj" hodiny.
  // Vyrovnaná logika: stačí 2 hodiny po sebe pre akúkoľvek zmenu (jasno↔polooblačno).
  {
    final out = List<int>.from(cur);
    for (var i = 1; i < cur.length; i++) {
      final prevShown = out[i - 1];
      final nextCandidate = cur[i];
      if (!stableSky.contains(prevShown) || !stableSky.contains(nextCandidate)) continue;
      if (prevShown == nextCandidate) continue;

      final next1 = i + 1 < cur.length ? cur[i + 1] : null;
      // Pre akúkoľvek zmenu stačí aby nasledujúca hodina potvrdila nový kód
      final bool holdNew = next1 == nextCandidate;
      if (!holdNew) {
        out[i] = prevShown;
      }
    }
    cur = out;
  }
  return cur;
}

String _calendarDateStamp(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Prvé `hourly.time` index s časovou pečatkou **`!parsed.isBefore(threshold)`** (rovnaká logika ako panel „24 h“).
int? _hourlyForecastFirstIndexNotBefore(HourlyForecast h, DateTime threshold) {
  for (var i = 0; i < h.time.length; i++) {
    final t = DateTime.tryParse(h.time[i]);
    if (t != null && !t.isBefore(threshold)) return i;
  }
  return null;
}

/// Ikony hodín v tom istom pipeline ako panel „24 h“ (smooth + prahy + fair-weather).
Map<int, int>? _hourlyStripDisplayIconByIndex(
  HourlyForecast h,
  DateTime locTime,
  CurrentWeather? current,
  DailyForecast? daily,
) {
  final visFloor = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  ).add(const Duration(hours: 1));
  final start = _hourlyForecastFirstIndexNotBefore(h, visFloor);
  if (start == null) return null;
  final end = math.min(start + 24, h.time.length);
  if (end <= start) return null;

  final smoothed = _smoothHourlyData(h, start, end, current, daily, locTime);
  final raw = List<int>.generate(
    end - start,
    (j) => _hourlySlotRawDisplayIconCode(h, start + j, smoothed, j),
  );
  final fair = _smoothFairWeatherHourlyIconCodes(raw);
  final out = <int, int>{};
  for (var j = 0; j < fair.length; j++) {
    out[start + j] = fair[j];
  }
  return out;
}

/// Noc = 22–23 dňa kartičky + skoré ráno **pred** 6:00 (0–5) toho istého kalendárneho dňa
/// a skoré ráno nasledujúceho dňa (0–5), aby dážď o 4–5 nepadol do „rána“ (6–12).
bool _dailyTileNightContainsParsed(DateTime slot, String tileCalendarIso) {
  final stamp = _calendarDateStamp(slot);
  final tileAnchor = DateTime.parse('${tileCalendarIso}T12:00:00');
  final followingStamp =
      _calendarDateStamp(tileAnchor.add(const Duration(days: 1)));
  final hour = slot.hour;
  return (stamp == tileCalendarIso && (hour >= 22 || hour < 6)) ||
      (stamp == followingStamp && hour < 6);
}

bool _dailyTileSegmentMatchesParsed(
    DateTime parsed, String calendarTileIso, String segment) {
  final hour = parsed.hour;

  switch (segment) {
    case 'morning':
      return _calendarDateStamp(parsed) == calendarTileIso &&
          hour >= 6 &&
          hour < 12;
    case 'afternoon':
      return _calendarDateStamp(parsed) == calendarTileIso &&
          hour >= 12 &&
          hour < 18;
    case 'evening':
      return _calendarDateStamp(parsed) == calendarTileIso &&
          hour >= 18 &&
          hour < 22;
    case 'night':
      return _dailyTileNightContainsParsed(parsed, calendarTileIso);
    default:
      return false;
  }
}

DateTime? _tryParseHourlyTimestamp(String timeStr) {
  if (timeStr.length < 13) return null;
  var p = DateTime.tryParse(timeStr);
  p ??= DateTime.tryParse(timeStr.replaceFirst(' ', 'T'));
  return p;
}

/// Väčšinový WMO/medziprahový výstup z hodiniek (priorita medzi zrážkovými ikonami ako v `_getDayPartWeather`).
int _dominantFromHourlyDisplayedCodes(List<int> codes) {
  if (codes.isEmpty) return 0;
  final Map<int, int> counts = {};
  final List<int> precipFound = [];
  for (final c in codes) {
    counts[c] = (counts[c] ?? 0) + 1;
    if (kPrecipitationCodes.contains(c)) precipFound.add(c);
  }
  if (precipFound.isNotEmpty) {
    final Map<int, int> precipCounts = {};
    for (final c in precipFound) {
      precipCounts[c] = (precipCounts[c] ?? 0) + 1;
    }
    return precipCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
  return counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
}

/// Ikony ako v zozname „24 h“, ale dopočítané pre celý deň `[datePrefix]` (smooth + RAW prahy + fair-weather smoothing).
(int dayStartIdx, List<int> displayedIcons)? _hourlyFairDisplayIconsForCalendarDay(
  HourlyForecast h,
  String datePrefix,
  CurrentWeather? current,
  DailyForecast? daily,
  DateTime locationTime,
) {
  int dayStartIdx = -1;
  int dayEndExclusive = -1;
  for (var i = 0; i < h.time.length; i++) {
    if (!h.time[i].startsWith(datePrefix)) continue;
    if (dayStartIdx < 0) dayStartIdx = i;
    dayEndExclusive = i + 1;
  }
  if (dayStartIdx < 0 || dayEndExclusive <= dayStartIdx) return null;

  final smoothed = _smoothHourlyData(h, dayStartIdx, dayEndExclusive, current, daily, locationTime);
  final span = dayEndExclusive - dayStartIdx;
  final raw = List<int>.generate(
    span,
    (j) => _hourlySlotRawDisplayIconCode(h, dayStartIdx + j, smoothed, j),
  );
  final fair = _smoothFairWeatherHourlyIconCodes(raw);
  return (dayStartIdx, fair);
}

/// Najsilnejší WMO búrkový kód v zozname hodín bloku (poradie 95, 96, 99 podľa čísla).
int? _strongestThunderFromCodes(Iterable<int?> codes) {
  int? best;
  for (final c in codes) {
    if (c != null && {95, 96, 99}.contains(c)) {
      if (best == null || c > best) best = c;
    }
  }
  return best;
}

/// Búrka len ak ju už ukazuje aspoň jedna hodina v display pipeline (24 h / fair grid).
/// Neprevzíma holý WMO 95–99 z API ani neumelá konvekcia z prehánok.
int _applyThunderFromDisplayedHourlyIcons(
  int dominantOrCandidate, {
  required List<int> displayedHourlyCodes,
}) {
  if (displayedHourlyCodes.isEmpty) return dominantOrCandidate;
  final thunder = _strongestThunderFromCodes(displayedHourlyCodes);
  if (thunder != null) return thunder;
  return dominantOrCandidate;
}

_SmoothedValues _smoothHourlyData(HourlyForecast h, int start, int end,
    CurrentWeather? currentWeather, DailyForecast? daily, DateTime locationTime) {

  final smoothedCodes = <int?>[];
  final smoothedTemps = <double?>[];
  final smoothedPrecipProbs = <int?>[];
  final smoothedPrecipitation = <double?>[];
  final smoothedUvIndex = <double?>[];
  final smoothedCloudCover = <double?>[];
  final smoothedApparentTemperature = <double?>[];
  final smoothedIsDaytime = <bool>[];

  for (int i = start; i < end; i++) {
    smoothedTemps.add(h.temperature?[i]);

    int rawCode = h.weatherCode?[i] ?? 0;
    int rawProb = h.precipitationProbability?[i] ?? 0;
    double rawPrecip = h.precipitation?[i] ?? 0.0;

    final processed = _processWeather(rawCode, rawProb, rawPrecip, isHourly: true, timeStr: h.time[i]);

    smoothedCodes.add(processed.code);
    smoothedPrecipProbs.add(processed.prob);
    smoothedPrecipitation.add(processed.precip);
    smoothedUvIndex.add(h.uvIndex?[i]);
    smoothedCloudCover.add(h.cloudCover?[i]);
    smoothedApparentTemperature.add(h.apparentTemperature?[i]);

    final dayIndex = _getDayIndexForHour(h.time[i], daily);
    final isDaytime = _isDaytimePrecise(h.time[i], daily, dayIndex, locationTime);
    smoothedIsDaytime.add(isDaytime);
  }

  return _SmoothedValues(
    weatherCodes: smoothedCodes,
    temperatures: smoothedTemps,
    precipitationProbabilities: smoothedPrecipProbs,
    precipitation: smoothedPrecipitation,
    uvIndex: smoothedUvIndex,
    cloudCover: smoothedCloudCover,
    apparentTemperature: smoothedApparentTemperature,
    isDaytime: smoothedIsDaytime,
  );
}

int _getDayIndexForHour(String hourTime, DailyForecast? daily) {
  if (daily == null || daily.time.isEmpty) return 0;
  try {
    final hourDate = DateTime.parse(hourTime);
    for (int i = 0; i < daily.time.length; i++) {
      final dayDate = DateTime.parse(daily.time[i]);
      if (hourDate.year == dayDate.year &&
          hourDate.month == dayDate.month &&
          hourDate.day == dayDate.day) {
        return i;
      }
    }
  // ignore: empty_catches
  } catch (e) {}
  return 0;
}

String windDirection(num? deg) {
  if (deg == null) return '—';
  final x = ((deg % 360) + 360) % 360;
  const dir = ['S', 'SV', 'V', 'JV', 'J', 'JZ', 'Z', 'SZ'];
  return dir[((x + 22.5) / 45).floor() % 8];
}

String windDirectionShort2(num? deg) {
  if (deg == null) return '—';
  final x = ((deg % 360) + 360) % 360;
  const dir = ['S', 'SV', 'V', 'JV', 'J', 'JZ', 'Z', 'SZ'];
  final fullDir = dir[((x + 22.5) / 45).floor() % 8];

  final shortDirMap = {
    'S': 'S',
    'SV': 'SV',
    'V': 'V',
    'JV': 'JV',
    'J': 'J',
    'JZ': 'JZ',
    'Z': 'Z',
    'SZ': 'SZ'
  };

  return shortDirMap[fullDir] ?? fullDir;
}

String formatTime(String iso, {String? timezone, int? utcOffsetSeconds}) {
  try {
    String cleanIso = iso.trim();
    if (cleanIso.startsWith('as')) cleanIso = cleanIso.substring(2).trim();

    if (!cleanIso.contains('T')) {
      if (cleanIso.contains(' ')) {
        final parts = cleanIso.split(' ');
        if (parts.length >= 2) {
          cleanIso = '${parts[0]}T${parts[1]}';
        }
      } else {
        cleanIso = '${cleanIso}T00:00:00';
      }
    }

    if (!cleanIso.contains(':')) return '--:--';

    // Parse as UTC and apply offset if provided
    DateTime? dt = DateTime.tryParse(cleanIso);
    if (dt == null) return '--:--';
    
    // Apply UTC offset to get local time
    if (utcOffsetSeconds != null && utcOffsetSeconds != 0) {
      dt = dt.add(Duration(seconds: utcOffsetSeconds));
    }

    final hour = dt.hour;
    final minute = dt.minute;

    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  } catch (e) {
    return '--:--';
  }
}

String _weekdaySkLongWithDate(DateTime d) {
  const w = [
    'Pondelok',
    'Utorok', 
    'Streda',
    'Štvrtok',
    'Piatok',
    'Sobota',
    'Nedeľa'
  ];
  return '${w[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
}

/// Hlavná ikona dňa nesmie byť búrka, ak ju nemá žiadny úsek (ráno / poobede / večer / noc).
int _capDailyMainThunderByPartIcons(int mainCode, List<int?> partIconCodes) {
  const thunder = {95, 96, 99};
  if (!thunder.contains(mainCode)) return mainCode;
  final parts = partIconCodes.whereType<int>().where((c) => c > 0).toList();
  if (parts.any((c) => thunder.contains(c))) return mainCode;
  if (parts.isEmpty) return 2;
  return parts.reduce(math.max);
}

Map<String, dynamic> _getDayPartWeather(
  String date,
  HourlyForecast? hourly,
  String part,
  DailyForecast? daily,
  int dailyWeatherCode,
  int dailyPrecipProbMax,
  CurrentWeather? current,
  DateTime? locationTime, {
  /// Deň na karte ako „0 mm“ + nízka dennej šanca — ikony úsekov nesmú ukazovať búrku len z hodinového WMO.
  bool suppressWetDayIcons = false,
  /// Denný súčet z API (mm / cm snehu) pre daný deň kartičky — doplnenie signálu, keď úsek sám o sebe vyzerá suchý.
  double dailyTotalPrecipMm = 0.0,
  double dailyTotalSnowCm = 0.0,
}) {

  bool forceDayForBlock = part == 'morning' || part == 'afternoon';
  bool forceNightForBlock = part == 'night';

  if (hourly == null || hourly.time.isEmpty) {
    return {
      'temp': '--°',
      'code': null,
      'iconCode': null,
      'icon': getWeatherIcon(null, size: 38, forceDay: forceDayForBlock, forceNight: forceNightForBlock)
    };
  }

  List<double?> temps = [];
  List<int?> codes = [];
  List<double?> precip = [];
  List<int?> probs = [];
  List<String> times = [];
  int maxProbRawInPart = 0;
  double maxPrecipRawInPart = 0.0;
  double sumPrecipRawInPart = 0.0;
  double sumCloudRawInPart = 0.0;
  int countCloudRawInPart = 0;
  final String datePrefix = date;

  final DateTime? locForHourlyPipe = locationTime;
  /// Ten istý pás ikon ako panel „24 h“ — aj pre zajtrajšok, ak je v najbližších 24 h.
  final Map<int, int>? stripIconsByIdx =
      current != null && locForHourlyPipe != null
          ? _hourlyStripDisplayIconByIndex(
              hourly, locForHourlyPipe, current, daily)
          : null;

  final Map<String, (int, List<int>)?>? slicesFair =
      current != null && locForHourlyPipe != null ? <String, (int, List<int>)?>{} : null;

  /// Fair-mriežka pre hodinu používa **kalendár dňa danej hodiny** (noc po polnoci: slot patrí inému „dňu forecastu“, nie len k dátumu kartičky).
  (int, List<int>)? sliceEnsure(String isoDay) =>
      slicesFair!.putIfAbsent(
          isoDay,
          () => _hourlyFairDisplayIconsForCalendarDay(
              hourly,
              isoDay,
              current!,
              daily,
              locForHourlyPipe!));

  final List<int> partGridDisplayedCodes = [];
  final List<int> partGridStripOnlyCodes = [];

  for (int i = 0; i < hourly.time.length; i++) {
    final timeStr = hourly.time[i];
    final parsedSlot = _tryParseHourlyTimestamp(timeStr);
    if (parsedSlot == null) continue;

    final bool matchesPart = _dailyTileSegmentMatchesParsed(parsedSlot, datePrefix, part);

    if (matchesPart) {
      temps.add(hourly.temperature?[i]);

      int rawCode = hourly.weatherCode?[i] ?? 0;
      int rawProb = hourly.precipitationProbability?[i] ?? 0;
      double rawPrecip = hourly.precipitation?[i] ?? 0.0;
      if (rawProb > maxProbRawInPart) maxProbRawInPart = rawProb;
      if (rawPrecip > maxPrecipRawInPart) maxPrecipRawInPart = rawPrecip;
      sumPrecipRawInPart += rawPrecip;

      final ccList = hourly.cloudCover;
      if (ccList != null && i < ccList.length) {
        final double? rawCloud = ccList[i];
        if (rawCloud != null) {
          sumCloudRawInPart += rawCloud;
          countCloudRawInPart++;
        }
      }

      final processed = _processWeather(rawCode, rawProb, rawPrecip, isHourly: false, timeStr: timeStr);

      codes.add(processed.code);
      precip.add(processed.precip); 
      probs.add(processed.prob);

      times.add(timeStr);

      if (slicesFair != null) {
        final dayStampLocal = _calendarDateStamp(parsedSlot);
        final fk = sliceEnsure(dayStampLocal);
        if (fk != null) {
          final (dsBk, iconsBk) = fk;
          final offBk = i - dsBk;
          if (offBk >= 0 && offBk < iconsBk.length) {
            var icon = iconsBk[offBk];
            final stripIcon = stripIconsByIdx?[i];
            if (stripIcon != null) {
              icon = stripIcon;
              partGridStripOnlyCodes.add(icon);
            }
            partGridDisplayedCodes.add(icon);
          }
        }
      }
    }
  }

  if (temps.isEmpty) {
    return {
      'temp': '--°',
      'code': null,
      'iconCode': null,
      'icon': getWeatherIcon(null, size: 38, forceDay: forceDayForBlock, forceNight: forceNightForBlock)
    };
  }

  double sumTemp = 0;
  int countTemp = 0;
  for (var t in temps) {
    if (t != null) {
      sumTemp += t;
      countTemp++;
    }
  }
  double? avgTemp = countTemp > 0 ? sumTemp / countTemp : null;
  String tempStr = avgTemp != null ? '${avgTemp.round()}°' : '--°';

  int? maxProb;
  if (probs.isNotEmpty) {
    for (var p in probs) {
      if (p != null) {
        if (maxProb == null || p > maxProb) {
          maxProb = p;
        }
      }
    }
  }

  double? maxPrecip;
  if (precip.isNotEmpty) {
    for (var p in precip) {
      if (p != null) {
        if (maxPrecip == null || p > maxPrecip) {
          maxPrecip = p;
        }
      }
    }
  }

  Map<int, int> codeCount = {};
  List<int> precipCodesFound = [];

  for (var c in codes) {
    if (c != null) {
      codeCount[c] = (codeCount[c] ?? 0) + 1;
      if (kPrecipitationCodes.contains(c)) {
        precipCodesFound.add(c); 
      }
    }
  }

  int? dominantCode;
  if (precipCodesFound.isNotEmpty) {
    Map<int, int> precipCount = {};
    for (var c in precipCodesFound) {
      precipCount[c] = (precipCount[c] ?? 0) + 1;
    }
    dominantCode = precipCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  } else if (codeCount.isNotEmpty) {
    dominantCode = codeCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String? sampleTime = times.isNotEmpty ? times.first : null;

  /// Ak je úsek v páse „24 h“, ikona len z tých hodín (overiteľné oproti zoznamu).
  final List<int> codesForPartIcon = partGridStripOnlyCodes.isNotEmpty
      ? partGridStripOnlyCodes
      : partGridDisplayedCodes;

  final bool alignPartIconWithHourlyPipeline = codesForPartIcon.isNotEmpty;
  final int seededFromHourlyFairGrid = alignPartIconWithHourlyPipeline
      ? _dominantFromHourlyDisplayedCodes(codesForPartIcon)
      : (dominantCode ?? 0);

  int blockIconCandidate = alignPartIconWithHourlyPipeline
      ? _applyThunderFromDisplayedHourlyIcons(
          seededFromHourlyFairGrid,
          displayedHourlyCodes: codesForPartIcon,
        )
      : seededFromHourlyFairGrid;
  final bool dailyPrecipSummary = kPrecipitationCodes.contains(dailyWeatherCode) &&
      dailyPrecipProbMax >= 40;
  /// Mokré signály len z hodín daného úseku (6–12 = ráno), nie z celodenného súčtu API.
  final bool blockShowsWetSignals = maxProbRawInPart >= 40 ||
      maxPrecipRawInPart >= _kIconTraceLiquidMm ||
      sumPrecipRawInPart >= 0.01 ||
      (maxProbRawInPart >= 35 && sumPrecipRawInPart >= 0.003);

  final bool partIconsShowPrecip =
      codesForPartIcon.any(kPrecipitationCodes.contains);

  /// Dennú WMO do úseku len bez hodinového pipeline; inak by suché ráno (6–12) dostalo dážď z dažďa o 4–5.
  bool mergedDailyPrecipIntoBlock = false;
  if (!suppressWetDayIcons &&
      !alignPartIconWithHourlyPipeline &&
      !partIconsShowPrecip &&
      !kPrecipitationCodes.contains(blockIconCandidate) &&
      dailyPrecipSummary &&
      blockShowsWetSignals) {
    var mergedFromDaily = dailyWeatherCode;
    if (alignPartIconWithHourlyPipeline &&
        {95, 96, 99}.contains(mergedFromDaily) &&
        _strongestThunderFromCodes(codesForPartIcon) == null) {
      mergedFromDaily = 63;
    }
    blockIconCandidate = mergedFromDaily;
    mergedDailyPrecipIntoBlock = true;
  }

  final double? avgCloudInPart =
      countCloudRawInPart > 0 ? sumCloudRawInPart / countCloudRawInPart : null;

  int iconProb = suppressWetDayIcons ? 0 : maxProbRawInPart;
  double iconMaxMm = suppressWetDayIcons ? 0.0 : maxPrecipRawInPart;
  double iconSumMm = suppressWetDayIcons ? 0.0 : sumPrecipRawInPart;

  /// Po doplnení z dennej WMO zdvihneme šancu pre prah — **nikdy** nevymýšľame mm; pri 0 mm zostane suchá ikona.
  if (mergedDailyPrecipIntoBlock && !suppressWetDayIcons) {
    iconProb = math.max(iconProb, dailyPrecipProbMax);
  }

  /// Keď použijeme už finálne hodiny ako v „24 h“, druhý agregovaný prah nesmú znovu rozožrať výsledok.
  final bool skipBlockAggregateThreshold =
      alignPartIconWithHourlyPipeline && !mergedDailyPrecipIntoBlock;

  /// Ikona bloku z úseku; pri suchom dni na karte ignorujeme mokré signály z jednotlivých hodín.
  final int afterPrecipThreshold = skipBlockAggregateThreshold
      ? blockIconCandidate
      : _weatherIconCodeWithPrecipThreshold(
          blockIconCandidate,
          iconProb,
          cloudCoverPercent: avgCloudInPart,
          hourlyPrecipitationMm: iconMaxMm,
          snowfallCm: suppressWetDayIcons ? 0.0 : dailyTotalSnowCm,
        );
  var blockIconCode = _clampPrecipitationIconIntensity(
    afterPrecipThreshold,
    iconProb,
    iconSumMm,
    isDailyContext: false,
    snowfallCm: suppressWetDayIcons ? 0.0 : dailyTotalSnowCm,
  );

  if (suppressWetDayIcons) {
    blockIconCode = _precipIconForcedDryWhenSuppressed(blockIconCode, cloudCoverPercent: avgCloudInPart);
  }

  Widget iconWidget = getWeatherIcon(
    blockIconCode,
    hourTime: sampleTime,
    daily: daily,
    size: 38,
    forceDay: forceDayForBlock,
    forceNight: forceNightForBlock,
  );

  return {
    'temp': tempStr,
    'code': dominantCode,
    'iconCode': blockIconCode,
    'icon': iconWidget,
    'prob': maxProb,
    'precip': maxPrecip, 
  };
}

Future<GeoCity?> reverseGeocode(double lat, double lon, {bool resolveTimezone = true}) async {
  final cachedCity = await CacheManager.getGeoCity(lat, lon);
  if (cachedCity != null) {
    if ((cachedCity.lat - lat).abs() > 0.000001 || (cachedCity.lon - lon).abs() > 0.000001) {
      final correctedCity = GeoCity(
        name: cachedCity.name,
        lat: lat,
        lon: lon,
        country: cachedCity.country,
        countryCode: cachedCity.countryCode,
        admin1: cachedCity.admin1,
        admin2: cachedCity.admin2,
        population: cachedCity.population,
        timezone: cachedCity.timezone,
      );
      await CacheManager.saveGeoCity(lat, lon, correctedCity);
      return correctedCity;
    }
    return cachedCity;
  }

  try {
    final uri = Uri.parse(
        '$kGeoApi/reverse?latitude=$lat&longitude=$lon&count=1&language=sk&format=json');
    final r = await http
        .get(uri)
        .timeout(const Duration(milliseconds: 10000));
    if (r.statusCode == 200) {
      final data = json.decode(r.body) as Map<String, dynamic>;
      final results = (data['results'] as List?) ?? [];
      if (results.isNotEmpty) {
        final city = GeoCity.fromGeoJson(results.first);
        final timezone =
            resolveTimezone ? await _getTimezoneForCoordinates(lat, lon) : null;

        final finalCity = GeoCity(
          name: city.name,
          lat: lat,
          lon: lon,
          country: city.country,
          countryCode: city.countryCode,
          admin1: city.admin1,
          admin2: city.admin2,
          population: city.population,
          timezone: timezone ?? 'auto',
        );

        await CacheManager.saveGeoCity(lat, lon, finalCity);
        return finalCity;
      }
    }
  // ignore: empty_catches
  } catch (e) {}

  try {
    final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=jsonv2&accept-language=sk');
    final r = await http.get(uri, headers: const {
      'User-Agent': 'pocasie-app/1.0 (flutter)'
    }).timeout(const Duration(milliseconds: 10000));
    if (r.statusCode == 200) {
      final data = json.decode(r.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr != null) {
        String pick(List<String> keys) {
          for (final k in keys) {
            final v = addr[k];
            if (v is String && v.trim().isNotEmpty) return v.trim();
          }
          return '';
        }

        final name = pick(['city', 'town', 'village', 'municipality', 'suburb', 'county']);
        final admin1 = pick(['state', 'region']);
        final admin2 = pick(['county', 'state_district']); 
        final country = pick(['country']);
        final countryCode = pick(['country_code']).toUpperCase();
        final timezone =
            resolveTimezone ? await _getTimezoneForCoordinates(lat, lon) : null;

        if (name.isNotEmpty || admin1.isNotEmpty || country.isNotEmpty) {
          final finalCity = GeoCity(
            name: name.isNotEmpty ? name : (admin1.isNotEmpty ? admin1 : country),
            lat: lat,
            lon: lon,
            country: country,
            countryCode: countryCode,
            admin1: admin1,
            admin2: admin2,
            population: null,
            timezone: timezone ?? 'auto',
          );
          await CacheManager.saveGeoCity(lat, lon, finalCity);
          return finalCity;
        }
      }
    }
  // ignore: empty_catches
  } catch (e) {}

  final formattedLat = lat.toStringAsFixed(4);
  final formattedLon = lon.toStringAsFixed(4);
  return GeoCity(
    name: 'Poloha ($formattedLat, $formattedLon)',
    lat: lat,
    lon: lon,
    country: '',
    countryCode: '',
    admin1: '',
    admin2: '',
    population: null,
    timezone: 'auto',
  );
}

Future<String?> _getTimezoneForCoordinates(double lat, double lon) async {
  try {
    final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&timezone=auto');
    final r = await http.get(uri).timeout(const Duration(milliseconds: 5000));

    if (r.statusCode == 200) {
      final data = json.decode(r.body) as Map<String, dynamic>;
      return data['timezone'] as String?;
    }
  // ignore: empty_catches
  } catch (e) {}
  return null;
}

Future<void> openUrl(String url) async {
  try {
    final uri = Uri.parse(url);

    if (url.contains('open-meteo.com')) {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      return;
    }

    final canLaunch = await canLaunchUrl(uri);
    if (canLaunch) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } else {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      // ignore: empty_catches
      } catch (e) {}
    }
  } catch (e) {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
    // ignore: empty_catches
    } catch (e2) {}
  }
}

//test