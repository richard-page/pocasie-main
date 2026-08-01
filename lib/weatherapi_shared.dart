import 'dart:convert';

import 'package:http/http.dart' as http;

/// Free plán: 3 dni. Developer: 7. Pro+: 14.
const int kWeatherApiForecastDaysMin = 3;
const int kWeatherApiForecastDaysMax = 14;

/// Spätná kompatibilita — max. dní podľa plánu.
const int kWeatherApiForecastDays = kWeatherApiForecastDaysMax;

const List<int> kWeatherApiForecastDayOptions = [14, 7, 3];

const String kWeatherApiBase = 'https://api.weatherapi.com/v1';
const String kWeatherApiAttributionUrl = 'https://www.weatherapi.com/';

const String kWeatherApiKey = String.fromEnvironment(
  'WEATHERAPI_KEY',
  defaultValue: 'f384507b2c994839bf7103225262707',
);

num? weatherApiNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

/// WeatherAPI search/reverse často vráti len názov krajiny, nie ISO kód.
String weatherApiCountryCodeFromName(String country) {
  final n = country
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('å', 'a')
      .replaceAll('č', 'c')
      .replaceAll('ď', 'd')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ľ', 'l')
      .replaceAll('ň', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ŕ', 'r')
      .replaceAll('š', 's')
      .replaceAll('ť', 't')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ž', 'z');
  if (n.isEmpty) return '';
  return switch (n) {
    'slovakia' || 'slovensko' => 'SK',
    'czech republic' || 'czechia' || 'cesko' || 'ceska republika' => 'CZ',
    'poland' || 'polsko' => 'PL',
    'germany' || 'nemecko' || 'deutschland' => 'DE',
    'romania' || 'rumunsko' => 'RO',
    'hungary' || 'madarsko' => 'HU',
    'austria' || 'rakusko' || 'oesterreich' || 'osterreich' => 'AT',
    'ukraine' || 'ukrajina' => 'UA',
    'serbia' || 'srbsko' => 'RS',
    'croatia' || 'chorvatsko' => 'HR',
    'slovenia' || 'slovinsko' => 'SI',
    'sweden' || 'svedsko' || 'sverige' => 'SE',
    'norway' || 'norsko' || 'norge' => 'NO',
    'denmark' || 'dansko' || 'danmark' => 'DK',
    'finland' || 'finsko' || 'suomi' => 'FI',
    'france' || 'francuzsko' || 'frankreich' => 'FR',
    'italy' || 'taliansko' || 'italia' => 'IT',
    'spain' || 'spanielsko' || 'espana' => 'ES',
    'portugal' || 'portugalsko' => 'PT',
    'netherlands' || 'holandsko' || 'nederland' => 'NL',
    'belgium' || 'belgicko' || 'belgie' => 'BE',
    'switzerland' || 'svajciarsko' || 'schweiz' || 'suisse' => 'CH',
    'united kingdom' ||
    'uk' ||
    'great britain' ||
    'britain' ||
    'england' ||
    'velka britania' ||
    'spojene kralovstvo' =>
      'GB',
    'ireland' || 'irsko' || 'eire' => 'IE',
    'iceland' || 'island' => 'IS',
    'greece' || 'grecko' || 'ellas' || 'ellada' => 'GR',
    'bulgaria' || 'bulharsko' => 'BG',
    'bosnia and herzegovina' ||
    'bosnia' ||
    'bosna a hercegovina' ||
    'bosna' =>
      'BA',
    'montenegro' || 'cierna hora' => 'ME',
    'north macedonia' || 'macedonia' || 'severne makedonsko' || 'makedonsko' =>
      'MK',
    'albania' || 'albansko' => 'AL',
    'lithuania' || 'litva' => 'LT',
    'latvia' || 'lotyssko' => 'LV',
    'estonia' || 'estonsko' => 'EE',
    'belarus' || 'bielorusko' => 'BY',
    'moldova' || 'moldavsko' => 'MD',
    'turkey' || 'turkiye' || 'turecko' => 'TR',
    'united states of america' ||
    'united states' ||
    'usa' ||
    'us' ||
    'spojene staty' ||
    'spojene staty americke' =>
      'US',
    'canada' || 'kanada' => 'CA',
    'mexico' || 'mexiko' => 'MX',
    'brazil' || 'brazilia' => 'BR',
    'argentina' => 'AR',
    'chile' || 'cile' => 'CL',
    'australia' => 'AU',
    'new zealand' || 'novy zeland' => 'NZ',
    'japan' || 'japonsko' => 'JP',
    'south korea' || 'korea' || 'juzna korea' => 'KR',
    'china' || 'cina' => 'CN',
    'india' => 'IN',
    'russia' || 'rusko' || 'russian federation' => 'RU',
    'israel' || 'izrael' => 'IL',
    'united arab emirates' || 'uae' || 'spojene arabske emiraty' => 'AE',
    'saudi arabia' || 'saudska arabia' => 'SA',
    'egypt' => 'EG',
    'south africa' || 'juhoafricka republika' || 'jar' => 'ZA',
    _ => '',
  };
}

/// WeatherAPI condition code → WMO kód pre existujúce ikony.
int wmoFromWeatherApiCode(int code) {
  return switch (code) {
    1000 => 0,
    1003 => 2,
    1006 || 1009 => 3,
    1030 || 1135 => 45,
    1147 => 48,
    1063 || 1180 || 1183 => 61,
    1186 || 1189 => 63,
    1192 || 1195 => 65,
    1150 || 1153 => 51,
    1072 || 1168 => 56,
    1171 => 57,
    1066 || 1210 || 1213 => 71,
    1216 || 1219 => 73,
    1222 || 1225 || 1114 || 1117 => 75,
    1069 || 1204 || 1207 => 67,
    1198 => 66,
    1201 => 67,
    1240 => 80,
    1243 => 81,
    1246 => 82,
    1255 => 85,
    1258 => 86,
    1087 => 95,
    1273 || 1279 => 96,
    1276 || 1282 => 99,
    1237 || 1261 || 1264 => 77,
    _ => 3,
  };
}

String weatherApiHourToIso(String time) {
  final t = time.trim();
  if (t.contains('T')) {
    return t.length == 16 ? '$t:00' : t;
  }
  final parts = t.split(' ');
  if (parts.length >= 2) return '${parts[0]}T${parts[1]}:00';
  return '${t}T00:00:00';
}

String weatherApiAstroToIso(String date, String time12h) {
  final match = RegExp(
    r'(\d{1,2}):(\d{2})\s*(AM|PM)',
    caseSensitive: false,
  ).firstMatch(time12h.trim());
  if (match == null) return '${date}T00:00';
  var h = int.parse(match.group(1)!);
  final m = match.group(2)!;
  final ampm = match.group(3)!.toUpperCase();
  if (ampm == 'PM' && h < 12) h += 12;
  if (ampm == 'AM' && h == 12) h = 0;
  return '$date'
      'T${h.toString().padLeft(2, '0')}:$m';
}

/// Mapuje WeatherAPI `forecast.json` na Open-Meteo tvar.
Map<String, dynamic> weatherApiToOpenMeteoShape(
  Map<String, dynamic> raw, {
  int? utcOffsetSeconds,
  required int forecastDaysAvailable,
}) {
  final location = raw['location'] as Map<String, dynamic>? ?? {};
  final current = raw['current'] as Map<String, dynamic>? ?? {};
  final forecast = raw['forecast'] as Map<String, dynamic>? ?? {};
  final days = (forecast['forecastday'] as List?) ?? [];

  final tzId = location['tz_id']?.toString();

  final hourlyTimes = <String>[];
  final hourlyTemp = <double?>[];
  final hourlyCodes = <int?>[];
  final hourlyPrecip = <double?>[];
  final hourlyPrecipProb = <int?>[];
  final hourlyWind = <double?>[];
  final hourlyWindGusts = <double?>[];
  final hourlyWindDir = <double?>[];
  final hourlyHumidity = <double?>[];
  final hourlyUv = <double?>[];
  final hourlyCloud = <double?>[];
  final hourlyApparent = <double?>[];
  final hourlyPressure = <double?>[];
  final hourlyDew = <double?>[];

  final dailyTimes = <String>[];
  final dailyCode = <int?>[];
  final dailyMax = <double?>[];
  final dailyMin = <double?>[];
  final dailyPrecipProb = <int?>[];
  final dailyPrecipSum = <double?>[];
  final dailySnow = <double?>[];
  final dailyUv = <double?>[];
  final dailyWindMax = <double?>[];
  final dailySunrise = <String>[];
  final dailySunset = <String>[];

  for (final dayEntry in days) {
    if (dayEntry is! Map) continue;
    final date = dayEntry['date']?.toString() ?? '';
    final day = dayEntry['day'] as Map<String, dynamic>? ?? {};
    final astro = dayEntry['astro'] as Map<String, dynamic>? ?? {};
    final hours = (dayEntry['hour'] as List?) ?? [];

    if (date.isNotEmpty) {
      dailyTimes.add(date);
      final dayCond = day['condition'] as Map<String, dynamic>? ?? {};
      dailyCode.add(
        wmoFromWeatherApiCode(weatherApiNum(dayCond['code'])?.toInt() ?? 1000),
      );
      dailyMax.add(weatherApiNum(day['maxtemp_c'])?.toDouble());
      dailyMin.add(weatherApiNum(day['mintemp_c'])?.toDouble());
      final rainP = weatherApiNum(day['daily_chance_of_rain'])?.toInt() ?? 0;
      final snowP = weatherApiNum(day['daily_chance_of_snow'])?.toInt() ?? 0;
      dailyPrecipProb.add(rainP > snowP ? rainP : snowP);
      dailyPrecipSum.add(weatherApiNum(day['totalprecip_mm'])?.toDouble());
      dailySnow.add(weatherApiNum(day['totalsnow_cm'])?.toDouble());
      dailyUv.add(weatherApiNum(day['uv'])?.toDouble());
      dailyWindMax.add(weatherApiNum(day['maxwind_kph'])?.toDouble());
      final sunrise = astro['sunrise']?.toString() ?? '';
      final sunset = astro['sunset']?.toString() ?? '';
      dailySunrise.add(
        sunrise.isNotEmpty
            ? weatherApiAstroToIso(date, sunrise)
            : '${date}T00:00',
      );
      dailySunset.add(
        sunset.isNotEmpty
            ? weatherApiAstroToIso(date, sunset)
            : '${date}T00:00',
      );
    }

    for (final hourEntry in hours) {
      if (hourEntry is! Map) continue;
      final timeRaw = hourEntry['time']?.toString() ?? '';
      if (timeRaw.isEmpty) continue;
      hourlyTimes.add(weatherApiHourToIso(timeRaw));

      final cond = hourEntry['condition'] as Map<String, dynamic>? ?? {};
      hourlyCodes.add(
        wmoFromWeatherApiCode(
          weatherApiNum(cond['code'])?.toInt() ?? 1000,
        ),
      );
      hourlyTemp.add(weatherApiNum(hourEntry['temp_c'])?.toDouble());
      hourlyPrecip.add(weatherApiNum(hourEntry['precip_mm'])?.toDouble());
      final rainP = weatherApiNum(hourEntry['chance_of_rain'])?.toInt() ?? 0;
      final snowP = weatherApiNum(hourEntry['chance_of_snow'])?.toInt() ?? 0;
      hourlyPrecipProb.add(rainP > snowP ? rainP : snowP);
      hourlyWind.add(weatherApiNum(hourEntry['wind_kph'])?.toDouble());
      hourlyWindGusts.add(weatherApiNum(hourEntry['gust_kph'])?.toDouble());
      hourlyWindDir.add(weatherApiNum(hourEntry['wind_degree'])?.toDouble());
      hourlyHumidity.add(weatherApiNum(hourEntry['humidity'])?.toDouble());
      hourlyUv.add(weatherApiNum(hourEntry['uv'])?.toDouble());
      hourlyCloud.add(weatherApiNum(hourEntry['cloud'])?.toDouble());
      hourlyApparent.add(weatherApiNum(hourEntry['feelslike_c'])?.toDouble());
      hourlyPressure.add(weatherApiNum(hourEntry['pressure_mb'])?.toDouble());
      hourlyDew.add(weatherApiNum(hourEntry['dewpoint_c'])?.toDouble());
    }
  }

  final curCond = current['condition'] as Map<String, dynamic>? ?? {};
  final curUpdated = current['last_updated']?.toString() ?? '';
  final curTime = curUpdated.isNotEmpty
      ? weatherApiHourToIso(curUpdated)
      : (hourlyTimes.isNotEmpty ? hourlyTimes.last : null);

  return {
    'source_provider': 'weatherapi',
    'forecast_days_available': forecastDaysAvailable,
    'timezone': tzId ?? 'auto',
    'timezone_abbreviation': null,
    'utc_offset_seconds': utcOffsetSeconds,
    'precipitation_probability_available': true,
    'model': 'weatherapi',
    'current': {
      'time': curTime,
      'temperature_2m': weatherApiNum(current['temp_c'])?.toDouble(),
      'is_day': weatherApiNum(current['is_day'])?.toInt(),
      'weather_code': wmoFromWeatherApiCode(
        weatherApiNum(curCond['code'])?.toInt() ?? 1000,
      ),
      'relative_humidity_2m': weatherApiNum(current['humidity'])?.toDouble(),
      'surface_pressure': weatherApiNum(current['pressure_mb'])?.toDouble(),
      'pressure_msl': weatherApiNum(current['pressure_mb'])?.toDouble(),
      'wind_speed_10m': weatherApiNum(current['wind_kph'])?.toDouble(),
      'wind_direction_10m': weatherApiNum(current['wind_degree'])?.toDouble(),
      'precipitation': weatherApiNum(current['precip_mm'])?.toDouble(),
      'uv_index': weatherApiNum(current['uv'])?.toDouble(),
      'cloud_cover': weatherApiNum(current['cloud'])?.toDouble(),
      'apparent_temperature':
          weatherApiNum(current['feelslike_c'])?.toDouble(),
    },
    'hourly': {
      'time': hourlyTimes,
      'temperature_2m': hourlyTemp,
      'weather_code': hourlyCodes,
      'precipitation': hourlyPrecip,
      'precipitation_probability': hourlyPrecipProb,
      'wind_speed_10m': hourlyWind,
      'wind_gusts_10m': hourlyWindGusts,
      'wind_direction_10m': hourlyWindDir,
      'relative_humidity_2m': hourlyHumidity,
      'uv_index': hourlyUv,
      'cloud_cover': hourlyCloud,
      'apparent_temperature': hourlyApparent,
      'pressure_msl': hourlyPressure,
      'dew_point_2m': hourlyDew,
      'timezone': tzId,
    },
    'daily': {
      'time': dailyTimes,
      'weather_code': dailyCode,
      'temperature_2m_max': dailyMax,
      'temperature_2m_min': dailyMin,
      'precipitation_probability_max': dailyPrecipProb,
      'precipitation_sum': dailyPrecipSum,
      'snowfall_sum': dailySnow,
      'uv_index_max': dailyUv,
      'wind_speed_10m_max': dailyWindMax,
      'sunrise': dailySunrise,
      'sunset': dailySunset,
      'timezone': tzId,
    },
  };
}

Uri weatherApiForecastUri(
  double lat,
  double lon, {
  required int days,
  bool pollen = false,
}) {
  return Uri.parse('$kWeatherApiBase/forecast.json').replace(
    queryParameters: <String, String>{
      'key': kWeatherApiKey,
      'q': '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}',
      'days': days.toString(),
      'aqi': 'no',
      'alerts': 'no',
      if (pollen) 'pollen': 'yes',
    },
  );
}

bool weatherApiRawHasForecast(Map<String, dynamic> raw) {
  if (raw.containsKey('error')) return false;
  final forecast = raw['forecast'];
  if (forecast is! Map) return false;
  final days = forecast['forecastday'];
  return days is List && days.isNotEmpty;
}

/// Skúsi 14 → 7 → 3 dni (podľa plánu API kľúča).
Future<Map<String, dynamic>?> downloadWeatherApiForecastMap(
  double lat,
  double lon, {
  String userAgent = 'pocasie-app/1.0 (flutter)',
}) async {
  if (kWeatherApiKey.isEmpty) return null;

  for (final days in kWeatherApiForecastDayOptions) {
    try {
      final uri = weatherApiForecastUri(lat, lon, days: days);
      final r = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': userAgent,
        },
      ).timeout(const Duration(seconds: 30));

      if (r.statusCode != 200) continue;

      final raw = json.decode(r.body) as Map<String, dynamic>;
      if (!weatherApiRawHasForecast(raw)) continue;

      final dayCount =
          ((raw['forecast'] as Map)['forecastday'] as List?)?.length ?? days;
      return weatherApiToOpenMeteoShape(
        raw,
        forecastDaysAvailable: dayCount,
      );
    } catch (_) {}
  }

  return null;
}

/// Minimálny WeatherAPI fetch pre Android widget.
Future<Map<String, dynamic>?> widgetFetchWeatherApiForecast(
  double lat,
  double lon,
) =>
    downloadWeatherApiForecastMap(
      lat,
      lon,
      userAgent: 'pocasie-app/1.0 (flutter-widget)',
    );

int widgetEffectiveWeatherCodeFromForecast(Map<String, dynamic> forecast) {
  final cur = forecast['current'] as Map<String, dynamic>?;
  if (cur == null) return 0;
  final rawCode = (cur['weather_code'] as num?)?.toInt();
  return switch (rawCode) {
    45 || 48 => 3,
    _ => rawCode ?? 0,
  };
}

String _weatherApiHourTimeIso(String raw) {
  final t = raw.trim();
  if (t.contains('T')) return t;
  // "2026-08-01 12:00" → "2026-08-01T12:00"
  return t.replaceFirst(' ', 'T');
}

double? _weatherApiPollenGrain(Map<String, dynamic>? pollen, String key) {
  if (pollen == null) return null;
  final v = weatherApiNum(pollen[key]);
  return v?.toDouble();
}

/// WeatherAPI `pollen=yes` → tvar kompatibilný s [AirQualityData.fromJson].
///
/// WeatherAPI: Hazel, Alder, Birch, Oak, Grass, Mugwort, Ragweed (bez Olive).
Map<String, dynamic>? weatherApiRawToAirQualityPollenJson(
  Map<String, dynamic> raw,
) {
  final forecast = raw['forecast'];
  if (forecast is! Map) return null;
  final days = forecast['forecastday'];
  if (days is! List || days.isEmpty) return null;

  final times = <String>[];
  final alder = <double?>[];
  final birch = <double?>[];
  final grass = <double?>[];
  final mugwort = <double?>[];
  final olive = <double?>[];
  final ragweed = <double?>[];
  final hazel = <double?>[];
  final oak = <double?>[];
  var sawAnyPollen = false;

  void addPollen(Map<String, dynamic>? pollen, String timeIso) {
    if (pollen != null) sawAnyPollen = true;
    times.add(timeIso);
    alder.add(_weatherApiPollenGrain(pollen, 'Alder'));
    birch.add(_weatherApiPollenGrain(pollen, 'Birch'));
    grass.add(_weatherApiPollenGrain(pollen, 'Grass'));
    mugwort.add(_weatherApiPollenGrain(pollen, 'Mugwort'));
    olive.add(null); // WeatherAPI Olive nemá
    ragweed.add(_weatherApiPollenGrain(pollen, 'Ragweed'));
    hazel.add(_weatherApiPollenGrain(pollen, 'Hazel'));
    oak.add(_weatherApiPollenGrain(pollen, 'Oak'));
  }

  for (final dayDyn in days) {
    if (dayDyn is! Map) continue;
    final day = Map<String, dynamic>.from(dayDyn);
    final hours = day['hour'];
    if (hours is List && hours.isNotEmpty) {
      for (final hourDyn in hours) {
        if (hourDyn is! Map) continue;
        final hour = Map<String, dynamic>.from(hourDyn);
        final pollenRaw = hour['pollen'];
        final pollen = pollenRaw is Map
            ? Map<String, dynamic>.from(pollenRaw)
            : null;
        addPollen(pollen, _weatherApiHourTimeIso('${hour['time'] ?? ''}'));
      }
      continue;
    }

    // Fallback: denný peľ (1 slot na deň).
    final dayBlock = day['day'];
    final pollenRaw = dayBlock is Map ? dayBlock['pollen'] : day['pollen'];
    final pollen =
        pollenRaw is Map ? Map<String, dynamic>.from(pollenRaw) : null;
    if (pollen == null) continue;
    final date = '${day['date'] ?? ''}';
    if (date.isEmpty) continue;
    addPollen(pollen, '${date}T12:00');
  }

  if (!sawAnyPollen || times.isEmpty) return null;

  return <String, dynamic>{
    'source_provider': 'weatherapi',
    'current': <String, dynamic>{},
    'hourly': <String, dynamic>{
      'time': times,
      'alder_pollen': alder,
      'birch_pollen': birch,
      'grass_pollen': grass,
      'mugwort_pollen': mugwort,
      'olive_pollen': olive,
      'ragweed_pollen': ragweed,
      'hazel_pollen': hazel,
      'oak_pollen': oak,
    },
  };
}

/// Peľ z WeatherAPI (`pollen=yes`) — 3 dni stačia pre UI kartu.
Future<Map<String, dynamic>?> downloadWeatherApiPollenAirQualityMap(
  double lat,
  double lon, {
  String userAgent = 'pocasie-app/1.0 (flutter)',
}) async {
  if (kWeatherApiKey.isEmpty) return null;
  try {
    final uri = weatherApiForecastUri(lat, lon, days: 3, pollen: true);
    final r = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'User-Agent': userAgent,
      },
    ).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return null;
    final raw = json.decode(r.body) as Map<String, dynamic>;
    if (raw.containsKey('error')) return null;
    return weatherApiRawToAirQualityPollenJson(raw);
  } catch (_) {
    return null;
  }
}
