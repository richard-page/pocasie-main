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
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:pocasie/weather_hero_ambient.dart';
import 'package:pocasie/weather_home_widget.dart';
import 'package:pocasie/weather_labels_sk.dart';
import 'package:pocasie/widget_background_refresh.dart';
import 'package:pocasie/app_theme.dart';
import 'package:workmanager/workmanager.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'forecast_model.dart';

part 'main_shared.dart';
part 'app_models.dart';
part 'app_services.dart';
part 'app_pages.dart';
part 'weather_page.dart';
part 'weather_chart_page.dart';
part 'openmeteo_fetch.dart';
part 'lightning_fetch.dart';
part 'radar_nowcast_fetch.dart';
part 'rainviewer_fetch.dart';

final ValueNotifier<bool> _showOnboardingNotifier = ValueNotifier<bool>(false);

/// Pri minimalizácii skryť WebView (Android PlatformView inak snapshotne „štvorčeky“ cez celú appku).
final ValueNotifier<bool> appRecentsCoverNotifier = ValueNotifier<bool>(false);

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
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Onboarding pred runApp — bez splash a bez prebliknutia WeatherPage.
  // Android Auto Backup vie po reinstalli obnoviť SharedPreferences → onboarding by
  // sa inak nespustil (clear data áno, odinštalovanie nie). Kontrolujeme firstInstallTime.
  try {
    final prefs = await SharedPreferences.getInstance();
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final installMs = await const MethodChannel('sk.menopocasie.app/install')
            .invokeMethod<int>('firstInstallTimeMs');
        if (installMs != null) {
          final stored = prefs.getInt(kAppInstallEpochKey);
          if (stored != installMs) {
            await prefs.setInt(kAppInstallEpochKey, installMs);
            await prefs.remove(kOnboardingDoneKey);
          }
        }
      } catch (_) {}
    }
    _showOnboardingNotifier.value = !(prefs.getBool(kOnboardingDoneKey) ?? false);
  } catch (_) {}

  runApp(const WeatherApp());

  scheduler.SchedulerBinding.instance.addPostFrameCallback((_) async {
    await _initServicesInBackground();
  });
}

Future<void> _initServicesInBackground() async {
  unawaited(_initDeferredServices());
}

Future<void> _initDeferredServices() async {
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

class WeatherApp extends StatefulWidget {
  const WeatherApp({super.key});

  @override
  State<WeatherApp> createState() => _WeatherAppState();
}

class _WeatherAppState extends State<WeatherApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // WebView v recent apps NEskrývame — skrytie spôsobovalo prázdny radar
    // v náhľade a krátke prebliknutie. PlatformView bleed riešime inde.
    if (state == AppLifecycleState.resumed &&
        appRecentsCoverNotifier.value) {
      appRecentsCoverNotifier.value = false;
      if (mounted) setState(() {});
    }
  }

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
        primary: kAppAccentBlue,
        secondary: kAppAccentBlueBright,
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
            home: ValueListenableBuilder<bool>(
              valueListenable: _showOnboardingNotifier,
              builder: (context, showOnboarding, _) {
                return DefaultSelectionStyle(
                  selectionColor: theme.textSelectionTheme.selectionColor ??
                      theme.colorScheme.primary.withValues(alpha: 0.40),
                  cursorColor: theme.textSelectionTheme.cursorColor ??
                      theme.colorScheme.primary,
                  child: ScaffoldMessenger(
                    child: showOnboarding
                        ? const OnboardingPage()
                        : const WeatherPage(),
                  ),
                );
              },
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
const String kEcmwfBackendUrl = ''; // Prázdne = preskočiť localhost, použiť GitHub priamo
const String kGitHubRawUrl = 'https://raw.githubusercontent.com/richard-page/pocasie/main/backend'; // GitHub URL pre jednotlivé JSONy

// Open-Meteo fallback FUNKCIA ODSTRÁNENÁ
// Appka používa výhradne ECMWF Open Data z tvojho zdroja
// Nepoužívame žiadne tretie strany na predpoveď




/// Vygeneruje ECMWF dáta pre ľubovoľnú lokalitu
Map<String, dynamic> generateEcmwfDataForLocation(double lat, double lon, String? locationName) {
  final now = DateTime.now().toUtc();
  final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  const cycle = '00';
  
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
  // ECMWF Open Data neposkytuje UV index v štandardnom výstupe — odhad z hodiny a oblačnosti.
  return enrichWeatherDataWithEstimatedUv(data);
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

/// Búrkovú ikonu pri WMO 95/96/99 — šanca ≥ 50 % a merateľné mm (Best Match ju rozhodol).
bool _thunderIconWarranted(
  int precipProbabilityPercent,
  double hourlyPrecipitationMm, {
  double snowfallCm = 0.0,
}) =>
    precipProbabilityPercent >= kMinPrecipProbPercent &&
    hourlyPrecipitationMm >= kThunderMinMmPerHour &&
    snowfallCm < _kIconMeaningfulSnowCm;


/// „Výrazná“ hodnota — silnejší vizuál, búrka, denné potlačenie suchých ikon.
const double _kIconMeaningfulLiquidMm = 0.1;
const double _kIconMeaningfulSnowCm = 0.1;

bool _belowMeaningfulPrecipAmountForIcon(double liquidMm, double snowfallCm) =>
    liquidMm < _kIconMeaningfulLiquidMm && snowfallCm < _kIconMeaningfulSnowCm;

/// Zrážková ikona v 24 h — mm + %, alebo šanca ≥ 50 % s WMO zrážkou / odhadom z %.
bool _precipIconShowsForHour(
  int precipProbabilityPercent,
  double liquidMm,
  double snowfallCm, {
  required bool wmoPrecipCode,
  int? apiWeatherCode,
}) {
  if (snowfallCm >= _kIconMeaningfulSnowCm &&
      precipProbabilityPercent >= kMinPrecipProbPercent) {
    return true;
  }
  return hourlyPrecipIconWarranted(
    mm: liquidMm,
    prob: precipProbabilityPercent,
    weatherCode: apiWeatherCode,
  );
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

/// Zrážková ikona — WMO z Open-Meteo len pri mm ≥ 0,1 a šanca ≥ 50 %; búrka prísnejšia.
/// Preferuje satelitný cloud cover pred modelovým ak je k dispozícii.
int _weatherIconCodeWithPrecipThreshold(
  int apiWeatherCode,
  int precipProbabilityPercent, {
  double? cloudCoverPercent,
  double? satelliteCloudCoverPercent,
  double? hourlyPrecipitationMm,
  double snowfallCm = 0.0,
  int? apiWeatherCodeForPrecip,
}) {
  final double mm = hourlyPrecipitationMm ?? 0.0;
  final double? effectiveCloudCover = satelliteCloudCoverPercent ?? cloudCoverPercent;
  final int code = normalizeDisplayWeatherCode(apiWeatherCode);
  final int precipSourceCode =
      normalizeDisplayWeatherCode(apiWeatherCodeForPrecip ?? apiWeatherCode);
  final bool thunderCode = code == 95 || code == 96 || code == 99;
  final bool precipCode = kPrecipitationCodes.contains(precipSourceCode);
  final bool precipConfirmed = _precipIconShowsForHour(
    precipProbabilityPercent,
    mm,
    snowfallCm,
    wmoPrecipCode: precipCode,
    apiWeatherCode: precipSourceCode,
  );
  final bool onlyTrace = _belowMeaningfulPrecipAmountForIcon(mm, snowfallCm);

  if (thunderCode) {
    // Best Match / API búrka — ukáž ju; nezoslabuj na dážď pri nízkom mm.
    if (precipProbabilityPercent >= kMinPrecipProbPercent ||
        mm >= kMeaningfulPrecipMmPerHour ||
        precipConfirmed) {
      return code;
    }
    return _drySkyIconTierFromModel(
      precipProbabilityPercent: precipProbabilityPercent,
      hourlyPrecipitationMm: mm,
      cloudCoverPercent: effectiveCloudCover,
    );
  }

  if (!precipConfirmed && precipCode) {
    return _drySkyIconTierFromModel(
      precipProbabilityPercent: precipProbabilityPercent,
      hourlyPrecipitationMm: mm,
      cloudCoverPercent: effectiveCloudCover,
    );
  }

  if (precipCode && precipConfirmed) {
    return onlyTrace ? _lightPrecipDisplayCode(code) : code;
  }

  if (!precipCode &&
      !thunderCode &&
      precipConfirmed &&
      {0, 1, 2, 3, 45, 48}.contains(code)) {
    return onlyTrace ? 51 : 61;
  }

  final int dryTier = _drySkyIconTierFromModel(
    precipProbabilityPercent: precipProbabilityPercent,
    hourlyPrecipitationMm: mm,
    cloudCoverPercent: effectiveCloudCover,
  );

  if (precipCode && !precipConfirmed) {
    return dryTier;
  }

  if ({0, 1, 2, 3, 45, 48}.contains(code)) {
    return dryTier;
  }
  return code;
}

/// Ikona a popis hornej pinned hlavičky — rovnaký slot ako aktuálny riadok v 24 h
/// (Open-Meteo API: mm ≥ 0,1 a zaokrúhlené % ≥ 50).
({int code, String? hourIso}) pinnedHeaderDisplayFromHourly({
  required HourlyForecast h,
  required DateTime locTime,
  CurrentWeather? current,
  DailyForecast? daily,
  bool lightningNearby = false,
  RadarNowcastContext radarNowcast = RadarNowcastContext.inactive,
  bool radarCoverageActive = false,
}) {
  final idx = _hourlyIndexContainingLocalTime(h, locTime);
  if (idx != null && idx < h.time.length) {
    final slot = openMeteoHourSlotUiFromApi(h: h, idx: idx);
    var code = slot.displayIconCode;
    final rawProb = h.precipitationProbability?[idx] ?? 0;
    final mm = h.precipitation?[idx] ?? 0.0;
    final cloud = h.cloudCover?[idx];
    final apiCode = h.weatherCode?[idx];

    if (lightningNearby) {
      code = applyNearbyLightningIcon(
        code,
        lightningNearby: true,
        precipMm: mm,
        precipProb: rawProb,
      );
      code = suppressThunderWithoutLightning(
        code,
        lightningNearby: true,
        precipProb: rawProb,
        precipMm: mm,
        cloudCoverPercent: cloud,
        ecmwfApiCode: apiCode,
      );
    } else {
      code = applyEcmwfJsonThunderHourIcon(
        code,
        ecmwfApiCode: apiCode,
        precipProb: slot.displayProbPercent,
        precipMm: mm,
        lightningNearby: false,
      );
      code = suppressThunderWithoutLightning(
        code,
        lightningNearby: false,
        precipProb: slot.displayProbPercent,
        precipMm: mm,
        cloudCoverPercent: cloud,
        ecmwfApiCode: apiCode,
      );
    }
    code = applyRadarPrecipEndToHeroIcon(
      code,
      radarCtx: radarNowcast,
      locTime: locTime,
      tempC: h.temperature?[idx],
      cloudCoverPercent: cloud,
      precipMm: mm,
      precipProb: slot.displayProbPercent,
      radarCoverageActive: radarCoverageActive,
    );
    // Intenzita len ak po radare ostala zrážková ikona (nie keď bunka odišla).
    if (kPrecipitationCodes.contains(normalizeDisplayWeatherCode(code))) {
      final radarActive =
          radarCoverageActive || radarNowcast.eligible;
      final fromRadar = radarLivePinUi(radarNowcast).wetAtPin;
      code = hourlyStripPrecipIntensityIcon(
        baseCode: code,
        precipMm: math.max(mm, slot.precipMm),
        tempC: h.temperature?[idx] ?? current?.temperature,
        allowHeavy: !radarActive && !fromRadar,
      );
      // Pri radare nikdy rain.svg / snow.svg — aj keď model hlási 65.
      if (radarActive || fromRadar) {
        code = capRadarPrecipIconNoHeavy(code);
      }
    }
    return (code: code, hourIso: h.time[idx]);
  }

  if (current?.weatherCode != null) {
    final rawProb = _precipProbabilityPercentForLocalHour(h, locTime) ?? 0;
    final mm = current!.precipitation ?? 0.0;
    final displayProb = roundPrecipProbPercent(rawProb);
    var code = openMeteoHourlyDisplayIconCode(
      storedWeatherCode: current.weatherCode,
      precipMm: mm,
      storedPrecipProbPercent: displayProb,
      cloudCoverPercent: current.cloudCover,
    );
    if (openMeteoHourlyWetShowsInUi(
      prob: rawProb,
      mm: mm,
      weatherCode: current.weatherCode,
    )) {
      final normalized = normalizeDisplayWeatherCode(current.weatherCode!);
      code = kPrecipitationCodes.contains(normalized)
          ? normalized
          : wmoFromPrecipitationMm(mm, cloudCoverPercent: current.cloudCover);
    }
    if (lightningNearby) {
      code = applyNearbyLightningIcon(
        code,
        lightningNearby: true,
        precipMm: mm,
        precipProb: rawProb,
      );
    }
    code = suppressThunderWithoutLightning(
      code,
      lightningNearby: lightningNearby,
      precipProb: rawProb,
      precipMm: mm,
      cloudCoverPercent: current.cloudCover,
      ecmwfApiCode: current.weatherCode,
    );
    code = applyRadarPrecipEndToHeroIcon(
      code,
      radarCtx: radarNowcast,
      locTime: locTime,
      tempC: current.temperature,
      cloudCoverPercent: current.cloudCover,
      precipMm: mm,
      precipProb: roundPrecipProbPercent(rawProb),
      radarCoverageActive: radarCoverageActive,
    );
    if (kPrecipitationCodes.contains(normalizeDisplayWeatherCode(code))) {
      final radarActive =
          radarCoverageActive || radarNowcast.eligible;
      final fromRadar = radarLivePinUi(radarNowcast).wetAtPin;
      code = hourlyStripPrecipIntensityIcon(
        baseCode: code,
        precipMm: mm,
        tempC: current.temperature,
        allowHeavy: !radarActive && !fromRadar,
      );
      if (radarActive || fromRadar) {
        code = capRadarPrecipIconNoHeavy(code);
      }
    }
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

String _calendarDateStamp(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Denná pečiatka z API (`2026-07-16` alebo `2026-07-16T00:00`).
String calendarDayPrefix(String dateStr) =>
    dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;

bool _hourlyIndexOnCalendarDay(
  HourlyForecast h,
  int index,
  String dayPrefix,
  int? utcOffsetSeconds,
) {
  if (index < 0 || index >= h.time.length) return false;
  final parsed = _tryParseHourlyTimestamp(h.time[index]);
  if (parsed == null) return h.time[index].startsWith(dayPrefix);
  return _calendarDateStamp(_hourlyParsedLocal(parsed, utcOffsetSeconds)) ==
      dayPrefix;
}

/// Hodina patrí na dennú kartu (vrátane noci 0–5 nasledujúceho dňa).
bool _hourlyIndexOnDailyTile(
  HourlyForecast h,
  int index,
  String dayPrefix,
  int? utcOffsetSeconds,
) {
  if (_hourlyIndexOnCalendarDay(h, index, dayPrefix, utcOffsetSeconds)) {
    return true;
  }
  if (index < 0 || index >= h.time.length) return false;
  final parsed = _tryParseHourlyTimestamp(h.time[index]);
  if (parsed == null) return false;
  return _dailyTileNightContainsParsed(
    _hourlyParsedLocal(parsed, utcOffsetSeconds),
    dayPrefix,
  );
}

/// UTC pečiatka z `hourly.time` → lokálna (offset z API).
DateTime _hourlyParsedLocal(DateTime parsedUtc, int? utcOffsetSeconds) {
  if (utcOffsetSeconds != null && utcOffsetSeconds != 0) {
    return parsedUtc.add(Duration(seconds: utcOffsetSeconds));
  }
  return parsedUtc;
}

/// Prvé `hourly.time` index s časovou pečatkou **`!parsed.isBefore(threshold)`** (rovnaká logika ako panel „24 h“).
/// Konvertuje UTC časy z JSON na lokálny čas pomocou utcOffsetSeconds.
int? _hourlyForecastFirstIndexNotBefore(HourlyForecast h, DateTime threshold, {int? utcOffsetSeconds}) {
  for (var i = 0; i < h.time.length; i++) {
    final t = DateTime.tryParse(h.time[i]);
    if (t == null) continue;
    // Konvertuj UTC na lokálny čas
    final localT = utcOffsetSeconds != null ? t.add(Duration(seconds: utcOffsetSeconds)) : t;
    if (!localT.isBefore(threshold)) return i;
  }
  return null;
}

/// Finálny stav pásu 24 h — rovnaký ako v UI zozname (vrátane radaru / orezania ECMWF).
class HourlyStripDisplayState {
  const HourlyStripDisplayState({
    required this.icons,
    required this.precipMm,
    required this.probs,
    required this.showRainPrecip,
  });

  final Map<int, int> icons;
  final Map<int, double> precipMm;
  final Map<int, int> probs;
  final Map<int, bool> showRainPrecip;
}

HourlyStripDisplayState? _hourlyStripFinalDisplayState(
  HourlyForecast h,
  DateTime locTime,
  CurrentWeather? current,
  DailyForecast? daily,
  int? utcOffsetSeconds, {
  RadarNowcastContext radarNowcast = RadarNowcastContext.inactive,
  bool radarCoverageActive = false,
  bool lightningNearby = false,
}) {
  final visFloor = DateTime(
    locTime.year,
    locTime.month,
    locTime.day,
    locTime.hour,
  ).add(const Duration(hours: 1));
  final start = _hourlyForecastFirstIndexNotBefore(
    h,
    visFloor,
    utcOffsetSeconds: utcOffsetSeconds,
  );
  if (start == null) return null;
  final end = math.min(start + 24, h.time.length);
  if (end <= start) return null;

  final stripIndices = List.generate(end - start, (j) => start + j);

  final displayIcons = List<int>.filled(stripIndices.length, 3);
  final showRainPrecip = List<bool>.filled(stripIndices.length, false);
  final storedProbs = List<int>.filled(stripIndices.length, 0);
  final precipMmList = List<double>.filled(stripIndices.length, 0.0);

  applyUnifiedHourlyStripPrecip(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMmList,
    stripIndices: stripIndices,
    h: h,
    radarCtx: radarNowcast,
    locTime: locTime,
    utcOffsetSeconds: utcOffsetSeconds,
    radarCoverageActive: radarCoverageActive,
  );

  final curIdx = _hourlyIndexContainingLocalTime(h, locTime);
  alignHourlyStripThunderWithProbability(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMmList,
    stripIndices: stripIndices,
    h: h,
    lightningNearby: lightningNearby,
    lightningHourIndex: curIdx,
    utcOffsetSeconds: utcOffsetSeconds,
    radarCtx: radarNowcast,
    locTime: locTime,
  );
  applyHourlyStripPrecipPercentRamp(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMmList,
    stripIndices: stripIndices,
    h: h,
    locTime: locTime,
    utcOffsetSeconds: utcOffsetSeconds,
    radarCtx: radarNowcast,
  );
  applyRadarPrecipEndToHourlyStrip(
    displayIcons: displayIcons,
    showRainPrecip: showRainPrecip,
    storedProbs: storedProbs,
    precipMm: precipMmList,
    stripIndices: stripIndices,
    h: h,
    radarCtx: radarNowcast,
    locTime: locTime,
    utcOffsetSeconds: utcOffsetSeconds,
    radarCoverageActive: radarCoverageActive,
  );

  final icons = <int, int>{};
  final precipMm = <int, double>{};
  final probs = <int, int>{};
  final showRainPrecipByIdx = <int, bool>{};
  for (var i = 0; i < stripIndices.length; i++) {
    final idx = stripIndices[i];
    icons[idx] = displayIcons[i];
    precipMm[idx] = precipMmList[i];
    probs[idx] = storedProbs[i];
    showRainPrecipByIdx[idx] = showRainPrecip[i];
  }
  return HourlyStripDisplayState(
    icons: icons,
    precipMm: precipMm,
    probs: probs,
    showRainPrecip: showRainPrecipByIdx,
  );
}

/// Noc = 23–5 dňa kartičky + skoré ráno **pred** 6:00 (0–5) toho istého kalendárneho dňa
/// a skoré ráno nasledujúceho dňa (0–5), aby dážď o 4–5 nepadol do „rána“ (6–12).
bool _dailyTileNightContainsParsed(DateTime slot, String tileCalendarIso) {
  final stamp = _calendarDateStamp(slot);
  final tileAnchor = DateTime.parse('${tileCalendarIso}T12:00:00');
  final followingStamp =
      _calendarDateStamp(tileAnchor.add(const Duration(days: 1)));
  final hour = slot.hour;
  return (stamp == tileCalendarIso && (hour >= 23 || hour < 6)) ||
      (stamp == followingStamp && hour < 6);
}

/// Denné úseky na kartičke — lokálny čas (wall clock).
/// Ráno 6–11, Poobede 12–17, Večer 18–22, Noc 23–5 (+ skoré ráno nasledujúceho dňa do 5:59).
bool _dailyTileSegmentMatchesParsed(
    DateTime parsed, String calendarTileIso, String segment) {
  final hour = parsed.hour;
  final tileDay = calendarDayPrefix(calendarTileIso);

  switch (segment) {
    case 'morning':
      return _calendarDateStamp(parsed) == tileDay && hour >= 6 && hour < 12;
    case 'afternoon':
      return _calendarDateStamp(parsed) == tileDay && hour >= 12 && hour < 18;
    case 'evening':
      return _calendarDateStamp(parsed) == tileDay && hour >= 18 && hour < 23;
    case 'night':
      return _dailyTileNightContainsParsed(parsed, tileDay);
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

List<int> _mergeStripIconsIntoDayIconList(
  List<int> dayIcons,
  int dayStartIdx,
  HourlyStripDisplayState? stripState,
) {
  if (stripState == null || stripState.icons.isEmpty) return dayIcons;
  final merged = List<int>.from(dayIcons);
  for (final entry in stripState.icons.entries) {
    final off = entry.key - dayStartIdx;
    if (off >= 0 && off < merged.length) merged[off] = entry.value;
  }
  return merged;
}

int _applyDayPartPrecipIconIntensity(
  int code, {
  required int iconProb,
  required double intensityMm,
  required bool useDailyIntensityScale,
  required bool dailyIntensityScale,
  required bool dailySnowIntensityScale,
  required double intensitySnowCm,
  bool isDayPartContext = true,
}) {
  var result = _clampPrecipitationIconIntensity(
    code,
    iconProb,
    intensityMm,
    isDailyContext: useDailyIntensityScale,
    isDayPartContext: isDayPartContext && !useDailyIntensityScale,
    snowfallCm: intensitySnowCm,
  );
  if (dailyIntensityScale &&
      intensityMm > 0 &&
      intensityMm < _kModeratePrecipMmDaily &&
      kPrecipitationCodes.contains(result) &&
      !kSnowWeatherCodes.contains(result)) {
    result = lightDailyPrecipVisualCode(result);
  }
  if (dailySnowIntensityScale &&
      intensitySnowCm > 0 &&
      intensitySnowCm < _kModerateSnowCmDaily &&
      kSnowWeatherCodes.contains(result)) {
    result = lightDailySnowVisualCode(result);
  }
  if (useDailyIntensityScale &&
      dailyHeavyPrecipWarranted(intensityMm, iconProb)) {
    result = applyHeavyDailyPrecipIconFloor(
      result,
      precipMm: intensityMm,
      probPercent: iconProb,
      isDailyContext: true,
    );
  }
  return result;
}

/// Dominantná zrážková ikona z finálneho 24 h pásu pre daný úsek dňa (ráno / večer / …).
int? _dominantPrecipIconForDayPartFromStrip(
  HourlyForecast hourly,
  String datePrefix,
  String part,
  HourlyStripDisplayState stripState, {
  int? utcOffsetSeconds,
}) {
  final stats = _dayPartStripPrecipStats(
    hourly,
    datePrefix,
    part,
    stripState,
    utcOffsetSeconds: utcOffsetSeconds,
  );
  if (!dayPartWetIconWarranted(
    partSumMm: stats.sumMm,
    maxProbPercent: stats.maxProb,
    wetHourCount: stats.wetHours,
    maxHourMm: stats.maxMm,
  )) {
    return null;
  }
  final precipIcons = <int>[];
  for (final entry in stripState.icons.entries) {
    final i = entry.key;
    if (i < 0 || i >= hourly.time.length) continue;
    final parsed = _tryParseHourlyTimestamp(hourly.time[i]);
    if (parsed == null) continue;
    final localParsed = _hourlyParsedLocal(parsed, utcOffsetSeconds);
    if (!_dailyTileSegmentMatchesParsed(localParsed, datePrefix, part)) continue;

    final icon = entry.value;
    final mm = stripState.precipMm[i] ?? hourly.precipitation?[i] ?? 0.0;
    final prob = stripState.probs[i] ?? hourly.precipitationProbability?[i] ?? 0;
    if (kPrecipitationCodes.contains(icon)) {
      precipIcons.add(icon);
    } else if (ecmwfHourPrecipShowsInUi(mm: mm, prob: prob)) {
      precipIcons.add(61);
    }
  }
  if (precipIcons.isEmpty) return null;
  return _dominantFromHourlyDisplayedCodes(precipIcons);
}

typedef _DayPartStripPrecipStats = ({
  int wetHours,
  double sumMm,
  double maxMm,
  int maxProb,
});

_DayPartStripPrecipStats _dayPartStripPrecipStats(
  HourlyForecast hourly,
  String datePrefix,
  String part,
  HourlyStripDisplayState stripState, {
  int? utcOffsetSeconds,
}) {
  var wetHours = 0;
  var sumMm = 0.0;
  var maxMm = 0.0;
  var maxProb = 0;
  for (final entry in stripState.icons.entries) {
    final i = entry.key;
    if (i < 0 || i >= hourly.time.length) continue;
    final parsed = _tryParseHourlyTimestamp(hourly.time[i]);
    if (parsed == null) continue;
    final localParsed = _hourlyParsedLocal(parsed, utcOffsetSeconds);
    if (!_dailyTileSegmentMatchesParsed(localParsed, datePrefix, part)) continue;

    final icon = entry.value;
    final mm = stripState.precipMm[i] ?? hourly.precipitation?[i] ?? 0.0;
    final prob = stripState.probs[i] ?? hourly.precipitationProbability?[i] ?? 0;
    final wc = hourly.weatherCode?[i];
    final showWet = kPrecipitationCodes.contains(icon) ||
        hourlyPrecipIconWarranted(mm: mm, prob: prob, weatherCode: wc ?? icon);
    if (!showWet) continue;
    wetHours++;
    final hourMm =
        mm >= kMeaningfulPrecipMmPerHour ? mm : displayMmFromPrecipProbability(prob);
    sumMm += hourMm;
    if (mm > maxMm) maxMm = mm;
    if (prob > maxProb) maxProb = prob;
  }
  return (wetHours: wetHours, sumMm: sumMm, maxMm: maxMm, maxProb: maxProb);
}

/// Noc kartičky: jediná stopa o 00:00 nasledujúceho dňa (23:00 ešte suchá) ≠ dnešná noc s dažďom.
bool _nightPartFollowingDayTraceOnly(
  String tileDay,
  String part,
  _DayPartStripPrecipStats stats,
  HourlyForecast hourly,
  HourlyStripDisplayState stripState, {
  int? utcOffsetSeconds,
}) {
  if (part != 'night' || stats.wetHours == 0) return false;
  final tileAnchor = DateTime.parse('${tileDay}T12:00:00');
  final followingStamp =
      _calendarDateStamp(tileAnchor.add(const Duration(days: 1)));

  var wetOnTile23 = false;
  var wetOnFollowingEarly = 0;
  var followingSum = 0.0;

  for (final entry in stripState.icons.entries) {
    final i = entry.key;
    if (i < 0 || i >= hourly.time.length) continue;
    final parsed = _tryParseHourlyTimestamp(hourly.time[i]);
    if (parsed == null) continue;
    final localParsed = _hourlyParsedLocal(parsed, utcOffsetSeconds);
    if (!_dailyTileSegmentMatchesParsed(localParsed, tileDay, 'night')) continue;

    final icon = entry.value;
    final mm = stripState.precipMm[i] ?? hourly.precipitation?[i] ?? 0.0;
    final prob = stripState.probs[i] ?? hourly.precipitationProbability?[i] ?? 0;
    final wc = hourly.weatherCode?[i];
    final showWet = kPrecipitationCodes.contains(icon) ||
        hourlyPrecipIconWarranted(mm: mm, prob: prob, weatherCode: wc ?? icon);
    if (!showWet) continue;

    final stamp = _calendarDateStamp(localParsed);
    final hour = localParsed.hour;
    if (stamp == tileDay && hour == 23) wetOnTile23 = true;
    if (stamp == followingStamp && hour < 6) {
      wetOnFollowingEarly++;
      followingSum += mm;
    }
  }

  return !wetOnTile23 &&
      wetOnFollowingEarly >= 1 &&
      wetOnFollowingEarly <= 1 &&
      followingSum < kDayPartMinSumMmForWetIcon &&
      stats.wetHours <= 1;
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

/// Ikony pre celý kalendárny deň — priamo z Open-Meteo API (bez smooth / fair-weather).
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

  final span = dayEndExclusive - dayStartIdx;
  final icons = List<int>.generate(
    span,
    (j) => openMeteoHourSlotUiFromApi(h: h, idx: dayStartIdx + j).displayIconCode,
  );
  return (dayStartIdx, icons);
}

/// Najsilnejší WMO búrkový kód v zozname hodín bloku (poradie 95, 96, 99 podľa čísla).
int? _strongestThunderFromCodes(
  Iterable<int?> codes, {
  bool lightningNearby = false,
}) {
  if (!lightningNearby) return null;
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
  bool lightningNearby = false,
}) {
  if (!lightningNearby || displayedHourlyCodes.isEmpty) {
    return dominantOrCandidate;
  }
  final thunder = _strongestThunderFromCodes(
    displayedHourlyCodes,
    lightningNearby: true,
  );
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

    final processed = _processWeather(
      rawCode,
      rawProb,
      rawPrecip,
      isHourly: true,
      timeStr: h.time[i],
      cloudCoverPercent: h.cloudCover?[i],
    );

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
  HourlyStripDisplayState? stripState,
  int? utcOffsetSeconds,
  bool lightningNearby = false,
  int? daysFromToday,
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
  int apiMaxProbInPart = 0;
  double apiMaxPrecipInPart = 0.0;
  double sumCloudRawInPart = 0.0;
  int countCloudRawInPart = 0;
  final String datePrefix = date;

  /// Ten istý pás ikon ako panel „24 h“ — len ak je úsek v strip okne (bez padania do radaru).
  final Map<int, int>? stripIconsByIdx = stripState?.icons;

  final List<int> partGridDisplayedCodes = [];
  final List<int> partGridStripOnlyCodes = [];

  var stripAlignedPart = false;
  if (stripState != null) {
    for (var j = 0; j < hourly.time.length; j++) {
      if (!stripState.icons.containsKey(j)) continue;
      final parsedJ = _tryParseHourlyTimestamp(hourly.time[j]);
      if (parsedJ == null) continue;
      final localJ = _hourlyParsedLocal(parsedJ, utcOffsetSeconds);
      if (_dailyTileSegmentMatchesParsed(localJ, datePrefix, part)) {
        stripAlignedPart = true;
        break;
      }
    }
  }

  for (int i = 0; i < hourly.time.length; i++) {
    final timeStr = hourly.time[i];
    final parsedSlot = _tryParseHourlyTimestamp(timeStr);
    if (parsedSlot == null) continue;

    final localSlot = _hourlyParsedLocal(parsedSlot, utcOffsetSeconds);
    final matchesPart =
        _dailyTileSegmentMatchesParsed(localSlot, datePrefix, part);

    if (matchesPart) {
      temps.add(hourly.temperature?[i]);

      final ccList = hourly.cloudCover;
      if (ccList != null && i < ccList.length) {
        final double? rawCloud = ccList[i];
        if (rawCloud != null) {
          sumCloudRawInPart += rawCloud;
          countCloudRawInPart++;
        }
      }

      final apiProb = hourly.precipitationProbability?[i] ?? 0;
      final apiPrecip = hourly.precipitation?[i] ?? 0.0;
      if (apiProb > apiMaxProbInPart) apiMaxProbInPart = apiProb;
      if (apiPrecip > apiMaxPrecipInPart) apiMaxPrecipInPart = apiPrecip;

      // Úsek prekrýva 24 h pás → ber len hodiny z pásu (rovnaké ako zoznam).
      // Úsek mimo pásu (ráno už preč) → Open-Meteo, NIE prázdna suchá obloha.
      if (stripState != null && stripAlignedPart) {
        if (!stripState.icons.containsKey(i)) continue;
      }

      final rawProb = hourly.precipitationProbability?[i] ?? 0;
      final rawPrecip = hourly.precipitation?[i] ?? 0.0;
      if (rawProb > maxProbRawInPart) maxProbRawInPart = rawProb;
      if (rawPrecip > maxPrecipRawInPart) maxPrecipRawInPart = rawPrecip;
      sumPrecipRawInPart += rawPrecip;

      final stripIcon = stripIconsByIdx?[i];
      final slotUi = openMeteoHourSlotUiFromApi(h: hourly, idx: i);
      // Strip (radar+OM) má prioritu — inak 10 dní mlčí pri živom daždi.
      final iconForPart = stripIcon ?? slotUi.displayIconCode;
      final partMm = stripState?.precipMm[i] ?? slotUi.precipMm;
      final partProb = stripState?.probs[i] ?? slotUi.displayProbPercent;
      codes.add(iconForPart);
      precip.add(partMm);
      probs.add(partProb);

      times.add(timeStr);

      if (stripIcon != null) {
        partGridStripOnlyCodes.add(iconForPart);
      }
      partGridDisplayedCodes.add(iconForPart);
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

  final double? avgCloudInPart =
      countCloudRawInPart > 0 ? sumCloudRawInPart / countCloudRawInPart : null;

  /// Ak je úsek v páse „24 h“, ikona len z tých hodín (overiteľné oproti zoznamu).
  final List<int> codesForPartIcon = partGridStripOnlyCodes.isNotEmpty
      ? partGridStripOnlyCodes
      : partGridDisplayedCodes;

  _DayPartStripPrecipStats? stripPartStats;
  if (stripState != null && stripAlignedPart && codesForPartIcon.isNotEmpty) {
    stripPartStats = _dayPartStripPrecipStats(
      hourly,
      datePrefix,
      part,
      stripState,
      utcOffsetSeconds: utcOffsetSeconds,
    );
  }
  final bool stripPartMeaningfulWet = stripPartStats != null &&
      dayPartWetIconWarranted(
        partSumMm: stripPartStats.sumMm,
        maxProbPercent: stripPartStats.maxProb,
        wetHourCount: stripPartStats.wetHours,
        maxHourMm: stripPartStats.maxMm,
      ) &&
      !(stripState != null &&
          _nightPartFollowingDayTraceOnly(
            datePrefix,
            part,
            stripPartStats,
            hourly,
            stripState,
            utcOffsetSeconds: utcOffsetSeconds,
          ));
  final bool stripPartAllDry = stripAlignedPart &&
      codesForPartIcon.isNotEmpty &&
      !stripPartMeaningfulWet;

  final List<int> codesForDominantIcon = stripPartAllDry
      ? codesForPartIcon
          .where((c) => !kPrecipitationCodes.contains(c))
          .toList()
      : codesForPartIcon;
  final List<int> iconCodesForBlock = codesForDominantIcon.isNotEmpty
      ? codesForDominantIcon
      : codesForPartIcon;

  if (codesForPartIcon.isEmpty && stripState != null && stripAlignedPart) {
    // Pás pokrýva úsek, ale žiadna hodina v ňom — nechaj oblohu (nie falošný dážď).
    final skyCode = skyWmoFromCloudCover(avgCloudInPart);
    return {
      'temp': tempStr,
      'code': skyCode,
      'iconCode': skyCode,
      'icon': getWeatherIcon(
        skyCode,
        hourTime: sampleTime,
        daily: daily,
        size: 38,
        forceDay: forceDayForBlock,
        forceNight: forceNightForBlock,
      ),
      'prob': maxProb,
    };
  }

  final bool alignPartIconWithHourlyPipeline = codesForPartIcon.isNotEmpty;
  final int seededFromHourlyFairGrid = alignPartIconWithHourlyPipeline
      ? _dominantFromHourlyDisplayedCodes(iconCodesForBlock)
      : (dominantCode ?? 0);

  int blockIconCandidate = alignPartIconWithHourlyPipeline
      ? _applyThunderFromDisplayedHourlyIcons(
          seededFromHourlyFairGrid,
          displayedHourlyCodes: iconCodesForBlock,
          lightningNearby: lightningNearby,
        )
      : seededFromHourlyFairGrid;
  final bool dailyPrecipSummary = kPrecipitationCodes.contains(dailyWeatherCode) &&
      dailyPrecipProbMax >= kMinPrecipProbPercent;
  final int wetSignalProbThreshold = daysFromToday != null
      ? dailyForecastPrecipProbThreshold(daysFromToday)
      : kMinPrecipProbPercent;
  /// Mokré signály — v pásme 24 h len z finálnych ikon (radar / orez), nie zo surového ECMWF.
  final bool blockShowsWetSignals = iconCodesForBlock.any(kPrecipitationCodes.contains) ||
      (iconCodesForBlock.isEmpty &&
          ((maxProbRawInPart >= wetSignalProbThreshold &&
                  maxPrecipRawInPart >= kMeaningfulPrecipMmPerHour) ||
              (maxProbRawInPart >= wetSignalProbThreshold &&
                  sumPrecipRawInPart >= kMeaningfulPrecipMmPerHour) ||
              (daysFromToday != null &&
                  maxProbRawInPart >= wetSignalProbThreshold &&
                  dailyPrecipSummary)));

  final bool partIconsShowPrecip =
      iconCodesForBlock.any(kPrecipitationCodes.contains);

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

  int iconProb = suppressWetDayIcons ? 0 : maxProbRawInPart;
  double iconMaxMm = suppressWetDayIcons ? 0.0 : maxPrecipRawInPart;
  double iconSumMm = suppressWetDayIcons ? 0.0 : sumPrecipRawInPart;

  /// Po doplnení z dennej WMO zdvihneme šancu pre prah — **nikdy** nevymýšľame mm; pri 0 mm zostane suchá ikona.
  if (mergedDailyPrecipIntoBlock && !suppressWetDayIcons) {
    iconProb = math.max(iconProb, dailyPrecipProbMax);
  }

  final bool snowBlock = dailyTotalSnowCm >= 0.5 ||
      (avgTemp != null && avgTemp <= kSnowMaxAirTempC) ||
      kSnowWeatherCodes.contains(blockIconCandidate) ||
      codesForPartIcon.any(kSnowWeatherCodes.contains);

  /// Intenzitu ikony úseku z hodinového súčtu v tom úseku — nie z celého dňa.
  final double intensityMm = suppressWetDayIcons ? 0.0 : iconSumMm;
  const bool useDailyIntensityScale = false;
  const bool dailyIntensityScale = false;
  final double partSnowCm = suppressWetDayIcons || !snowBlock || dailyTotalSnowCm <= 0
      ? 0.0
      : (dailyTotalPrecipMm > 0
          ? dailyTotalSnowCm * (iconSumMm / dailyTotalPrecipMm).clamp(0.0, 1.0)
          : dailyTotalSnowCm * (temps.length / 24.0).clamp(0.0, 1.0));
  final bool dailySnowIntensityScale = partSnowCm > 0 && snowBlock;
  final double intensitySnowCm = dailySnowIntensityScale ? partSnowCm : 0.0;
  /// Pri mokrom úseku používaj max. šancu z hodín v tom úseku.
  final int intensityProb = iconProb;

  /// Keď použijeme už finálne hodiny ako v „24 h“, druhý agregovaný prah nesmú znovu rozožrať výsledok.
  final bool skipBlockAggregateThreshold =
      alignPartIconWithHourlyPipeline && !mergedDailyPrecipIntoBlock;

  /// Ikona bloku z úseku; pri suchom dni na karte ignorujeme mokré signály z jednotlivých hodín.
  final double mmForPrecipThreshold = suppressWetDayIcons
      ? 0.0
      : (iconMaxMm >= kMeaningfulPrecipMmPerHour
          ? iconMaxMm
          : (iconProb >= wetSignalProbThreshold
              ? displayMmFromPrecipProbability(iconProb)
              : iconMaxMm));
  final int afterPrecipThreshold = skipBlockAggregateThreshold
      ? blockIconCandidate
      : _weatherIconCodeWithPrecipThreshold(
          blockIconCandidate,
          iconProb,
          cloudCoverPercent: avgCloudInPart,
          hourlyPrecipitationMm: mmForPrecipThreshold,
          snowfallCm: suppressWetDayIcons ? 0.0 : dailyTotalSnowCm,
        );
  var blockIconCode = _applyDayPartPrecipIconIntensity(
    afterPrecipThreshold,
    iconProb: intensityProb,
    intensityMm: intensityMm,
    useDailyIntensityScale: useDailyIntensityScale,
    dailyIntensityScale: dailyIntensityScale,
    dailySnowIntensityScale: dailySnowIntensityScale,
    intensitySnowCm: intensitySnowCm,
  );

  if (suppressWetDayIcons) {
    blockIconCode = _precipIconForcedDryWhenSuppressed(blockIconCode, cloudCoverPercent: avgCloudInPart);
  }

  // Ak 24 h pás pre tento úsek hlási zrážky, doplni signál — intenzitu určí súčet mm úseku.
  // Ak pás úsek pokrýva a je suchý — nikdy nedopĺňaj dážď z denného WMO / mm.
  if (stripState != null) {
    final stripPartIcon = _dominantPrecipIconForDayPartFromStrip(
      hourly,
      date,
      part,
      stripState,
      utcOffsetSeconds: utcOffsetSeconds,
    );
    if (stripPartIcon != null && kPrecipitationCodes.contains(stripPartIcon)) {
      if (!kPrecipitationCodes.contains(blockIconCode)) {
        // Len „je dážď“ — nie silná/búrková ikona z 24 h pri malom úhrne úseku.
        blockIconCode = 51;
      }
      // Búrku z pásu nechaj len pri reálnom úhrne v úseku (inak slabý dážď).
      if ({95, 96, 99}.contains(normalizeDisplayWeatherCode(stripPartIcon)) &&
          iconSumMm >= _kModeratePrecipMmDayPart) {
        blockIconCode = stripPartIcon;
      }
    } else if (stripPartAllDry &&
        kPrecipitationCodes.contains(blockIconCode)) {
      blockIconCode = iconCodesForBlock.isNotEmpty
          ? _dominantFromHourlyDisplayedCodes(iconCodesForBlock)
          : skyWmoFromCloudCover(avgCloudInPart);
    }
  }

  blockIconCode = _applyDayPartPrecipIconIntensity(
    blockIconCode,
    iconProb: intensityProb,
    intensityMm: intensityMm,
    useDailyIntensityScale: useDailyIntensityScale,
    dailyIntensityScale: dailyIntensityScale,
    dailySnowIntensityScale: dailySnowIntensityScale,
    intensitySnowCm: intensitySnowCm,
  );

  // −2 °C / denný sneh → sneženie; intenzita podľa súčtu úseku (nie prahy 1 h z 24 h).
  // V okne 24 h pásu: ak pás ukazuje sucho, mm z API nesmú vymyslieť dažďovú ikonu.
  if (!suppressWetDayIcons &&
      !stripPartAllDry &&
      (kPrecipitationCodes.contains(blockIconCode) ||
          iconSumMm >= kMeaningfulPrecipMmPerHour ||
          dailyTotalSnowCm >= 0.5)) {
    final partCm = partSnowCm > 0
        ? partSnowCm
        : (dailyTotalSnowCm > 0 && dailyTotalPrecipMm > 0
            ? dailyTotalSnowCm * (iconSumMm / dailyTotalPrecipMm).clamp(0.0, 1.0)
            : (dailyTotalSnowCm > 0
                ? dailyTotalSnowCm * (temps.length / 24.0).clamp(0.05, 1.0)
                : 0.0));
    blockIconCode = dayPartPrecipDisplayIcon(
      code: blockIconCode,
      avgTempC: avgTemp,
      partSumMm: iconSumMm,
      probPercent: intensityProb,
      partSnowCm: partCm,
      dailySnowCm: dailyTotalSnowCm,
    );
    // Pri nízkom úhrne úseku nikdy silný dážď / búrka (24 h mohlo nafúknuť ikonu).
    if (iconSumMm < _kHeavyPrecipMmDayPart &&
        kPrecipitationCodes.contains(blockIconCode) &&
        !kSnowWeatherCodes.contains(blockIconCode)) {
      final n = normalizeDisplayWeatherCode(blockIconCode);
      if (n == 65 || n == 82 || {95, 96, 99}.contains(n)) {
        blockIconCode =
            iconSumMm >= _kModeratePrecipMmDayPart ? 63 : 51;
      } else if (iconSumMm < _kModeratePrecipMmDayPart &&
          {61, 63, 81}.contains(n)) {
        blockIconCode = 51;
      }
    }
  }

  // Poistka: úsek v 24 h páse so suchými hodinami = suchá ikona (ako v zozname 18–21).
  if (stripPartAllDry) {
    blockIconCode = iconCodesForBlock.isNotEmpty
        ? _dominantFromHourlyDisplayedCodes(iconCodesForBlock)
        : skyWmoFromCloudCover(avgCloudInPart);
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
    'partSumMm': iconSumMm,
    'partMaxMm': iconMaxMm,
  };
}

/// Hlavná ikona dennej karty — dominantný kód z častí dňa / hodín, nie surový `daily.weather_code`.
int resolveDailyCardMainIconCode({
  required List<int> displayedDayIcons,
  required int fallbackCode,
  required bool suppressWetDayIcons,
  double? meanHourlyCloudForDay,
  required List<int?> partIconCodes,
  double dailyPrecipMm = 0,
  int dailyPrecipProb = 0,
}) {
  final parts = partIconCodes.whereType<int>().where((c) => c > 0).toList();
  var code = parts.isNotEmpty
      ? _dominantFromHourlyDisplayedCodes(parts)
      : displayedDayIcons.isNotEmpty
          ? _dominantFromHourlyDisplayedCodes(displayedDayIcons)
          : fallbackCode;

  if (!suppressWetDayIcons &&
      dailyHeavyPrecipWarranted(dailyPrecipMm, dailyPrecipProb)) {
    final precipParts =
        parts.where((c) => kPrecipitationCodes.contains(c)).toList();
    if (precipParts.isNotEmpty) {
      code = precipParts.reduce(math.max);
    } else if (!kPrecipitationCodes.contains(code)) {
      code = 65;
    }
  }

  code = _applyThunderFromDisplayedHourlyIcons(
    code,
    displayedHourlyCodes: parts.isNotEmpty ? parts : displayedDayIcons,
  );
  if (suppressWetDayIcons && kPrecipitationCodes.contains(code)) {
    code = skyWmoFromCloudCover(meanHourlyCloudForDay);
  }
  return _capDailyMainThunderByPartIcons(code, partIconCodes);
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
      'User-Agent': kNominatimUserAgent
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

/// Detekuje timezone podľa geografických súradníc bez externého API
Future<String?> _getTimezoneForCoordinates(double lat, double lon) async {
  // Slovensko a Česko
  if (lat >= 47.5 && lat <= 52.0 && lon >= 12.0 && lon <= 23.0) {
    return 'Europe/Bratislava';
  }
  // Maďarsko
  if (lat >= 45.5 && lat <= 49.0 && lon >= 16.0 && lon <= 23.0) {
    return 'Europe/Budapest';
  }
  // Rakúsko
  if (lat >= 46.0 && lat <= 50.0 && lon >= 9.0 && lon <= 18.0) {
    return 'Europe/Vienna';
  }
  // Poľsko
  if (lat >= 49.0 && lat <= 55.0 && lon >= 14.0 && lon <= 25.0) {
    return 'Europe/Warsaw';
  }
  // Nemecko
  if (lat >= 47.0 && lat <= 55.0 && lon >= 6.0 && lon <= 15.0) {
    return 'Europe/Berlin';
  }
  // EU fallback
  if (lat >= 36.0 && lat <= 71.0 && lon >= -11.0 && lon <= 40.0) {
    return 'Europe/London';
  }
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
