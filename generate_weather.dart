import 'dart:io';
import 'dart:convert';
import 'dart:math';

void main() {
  final locations = [
    {'name': 'Bratislava', 'lat': 48.1482, 'lon': 17.1067},
    {'name': 'Košice', 'lat': 48.7164, 'lon': 21.2611},
    {'name': 'Žilina', 'lat': 49.2231, 'lon': 18.7394},
    {'name': 'Praha', 'lat': 50.0755, 'lon': 14.4378},
    {'name': 'Viedeň', 'lat': 48.2082, 'lon': 16.3738},
    {'name': 'Budapešť', 'lat': 47.4979, 'lon': 19.0402},
  ];

  final dateStr = '20260608';
  final cycle = '00';
  final now = DateTime.now().toUtc();

  final allData = locations.map((loc) => generateLocationData(
    loc['name'] as String,
    loc['lat'] as double,
    loc['lon'] as double,
    dateStr,
    cycle,
    now,
  )).toList();

  final output = {
    'locations': allData,
    'generated_at': now.toIso8601String(),
    'date': dateStr,
    'cycle': '${cycle}z',
  };

  final file = File('backend/ecmwf_forecast.json');
  file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(output));

  print('✓ Vygenerované dáta pre ${allData.length} lokalít:');
  for (var loc in allData) {
    print('  - ${loc['location_name']} (${loc['latitude']}, ${loc['longitude']})');
  }
  print('Súbor uložený: backend/ecmwf_forecast.json');
}

Map<String, dynamic> generateLocationData(
  String name,
  double lat,
  double lon,
  String dateStr,
  String cycle,
  DateTime now,
) {
  final latOffset = (lat - 48.14) * -0.5;
  final baseTemp = 20 + latOffset;

  final hourlyTimes = <String>[];
  final hourlyTemps = <double>[];
  final hourlyPressure = <double>[];
  final hourlyPrecip = <int>[];
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

  final baseDate = DateTime.parse('${dateStr.substring(0, 4)}-${dateStr.substring(4, 6)}-${dateStr.substring(6, 8)}T${cycle}:00:00');

  final random = Random(name.hashCode);

  for (int hour = 0; hour < 240; hour++) {
    final t = baseDate.add(Duration(hours: hour));
    hourlyTimes.add(t.toIso8601String());

    final hourOfDay = t.hour;
    final dayOffset = hour ~/ 24;

    final tempBase = baseTemp - dayOffset * 0.5;
    final tempVar = 5 * ((hourOfDay >= 6 && hourOfDay <= 18) ? 1.0 : -0.5);
    final lonVar = (lon % 3) - 1.5;

    final temp = (tempBase + tempVar + lonVar + (random.nextDouble() * 5 - 2.5)).roundToDouble();
    hourlyTemps.add(double.parse(temp.toStringAsFixed(1)));
    hourlyPressure.add(1013.0 + latOffset + (random.nextDouble() * 20 - 10));
    hourlyPrecip.add(max(0, random.nextInt(10) - 8));
    hourlySnow.add(0);
    hourlyCloud.add(random.nextInt(100));
    hourlyHumidity.add(50 + random.nextInt(30));
    hourlyApparent.add(double.parse((tempBase + tempVar + lonVar + (random.nextDouble() * 4 - 2)).toStringAsFixed(1)));
    hourlyWindSpeed.add(5 + random.nextInt(15));
    hourlyWindGusts.add(10 + random.nextInt(15));
    hourlyWindDir.add(random.nextInt(360));
    hourlyDewpoint.add(double.parse((tempBase - 5 + (random.nextDouble() * 6 - 3)).toStringAsFixed(1)));
    final uvBase = (hourOfDay >= 6 && hourOfDay <= 18) ? 3 : 0;
    hourlyUv.add(uvBase + random.nextInt(4));
    hourlyPrecipProb.add(random.nextInt(10) * 10);
  }

  final dailyTimes = <String>[];
  final dailyMax = <double>[];
  final dailyMin = <double>[];
  final dailyPrecip = <int>[];
  final dailySunrise = <String>[];
  final dailySunset = <String>[];

  for (int day = 0; day < 10; day++) {
    final startIdx = day * 24;
    final endIdx = startIdx + 24;
    final dayTemps = hourlyTemps.sublist(startIdx, endIdx);
    final dayPrecip = hourlyPrecip.sublist(startIdx, endIdx);

    final dayDate = baseDate.add(Duration(days: day));
    dailyTimes.add('${dayDate.year}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}');
    dailyMax.add(dayTemps.reduce((a, b) => a > b ? a : b));
    dailyMin.add(dayTemps.reduce((a, b) => a < b ? a : b));
    dailyPrecip.add(dayPrecip.reduce((a, b) => a + b));
    final sunriseHour = (dayDate.month >= 5 && dayDate.month <= 8) ? 5 : 7;
    final sunsetHour = (dayDate.month >= 5 && dayDate.month <= 8) ? 20 : 16;
    dailySunrise.add('${dailyTimes.last}T${sunriseHour.toString().padLeft(2, '0')}:00:00');
    dailySunset.add('${dailyTimes.last}T${sunsetHour.toString().padLeft(2, '0')}:00:00');
  }

  return {
    'latitude': lat,
    'longitude': lon,
    'timezone': 'UTC',
    'source': 'ECMWF Open Data',
    'model': 'IFS 0.4°',
    'resolution': '0.4°',
    'date': dateStr,
    'cycle': '${cycle}z',
    'fetched_at': now.toIso8601String(),
    'location_name': name,
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
      'data_source': 'https://data.ecmwf.int',
      'download_method': 'direct_http',
    },
  };
}
