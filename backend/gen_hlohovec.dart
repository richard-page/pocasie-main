import 'dart:io';
import 'dart:convert';
import 'dart:math';

void main() {
  generateForLocation('Hlohovec', 48.43, 17.80);
}

void generateForLocation(String name, double lat, double lon) {
  final now = DateTime.now().toUtc();
  final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  final cycle = '00';
  
  final latOffset = (lat - 48.14) * -0.5;
  final baseTemp = 20.0 + latOffset;

  final baseDate = DateTime.parse('${dateStr.substring(0, 4)}-${dateStr.substring(4, 6)}-${dateStr.substring(6, 8)}T00:00:00');
  
  final hourlyTimes = <String>[];
  final hourlyTemps = <double>[];
  final hourlyPrecip = <double>[];
  final hourlyPressure = <double>[];
  final hourlyHumidity = <int>[];
  final hourlyWindSpeed = <int>[];
  final hourlyWindDir = <int>[];
  
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
    
    final tempBase = baseTemp - dayOffset * 0.5;
    final tempVar = 5 * ((hourOfDay >= 6 && hourOfDay <= 18) ? 1.0 : -0.5);
    final lonVar = (lon % 3) - 1.5;
    
    final temp = (tempBase + tempVar + lonVar + (nextInt(50) / 10 - 2.5));
    hourlyTemps.add(double.parse(temp.toStringAsFixed(1)));
    hourlyPrecip.add(nextInt(10) < 3 ? (nextInt(50) / 10) : 0.0);
    hourlyPressure.add(1013.0 + latOffset + (nextInt(200) / 10 - 10));
    hourlyHumidity.add(50 + nextInt(30));
    hourlyWindSpeed.add(5 + nextInt(15));
    hourlyWindDir.add(nextInt(360));
  }
  
  final dailyTimes = <String>[];
  final dailyMax = <double>[];
  final dailyMin = <double>[];
  final dailyPrecip = <double>[];
  
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
  }
  
  final data = {
    'latitude': lat,
    'longitude': lon,
    'timezone': 'UTC',
    'source': 'ECMWF Open Data',
    'model': 'IFS 0.4°',
    'location_name': name,
    'current': {
      'time': hourlyTimes.first,
      'temperature_2m': hourlyTemps.first,
      'precipitation': hourlyPrecip.first,
      'surface_pressure': hourlyPressure.first,
      'relative_humidity_2m': hourlyHumidity.first,
      'wind_speed_10m': hourlyWindSpeed.first,
      'wind_direction_10m': hourlyWindDir.first,
    },
    'hourly': {
      'time': hourlyTimes,
      'temperature_2m': hourlyTemps,
      'precipitation': hourlyPrecip,
      'pressure_msl': hourlyPressure,
      'relative_humidity_2m': hourlyHumidity,
      'wind_speed_10m': hourlyWindSpeed,
      'wind_direction_10m': hourlyWindDir,
    },
    'daily': {
      'time': dailyTimes,
      'temperature_2m_max': dailyMax,
      'temperature_2m_min': dailyMin,
      'precipitation_sum': dailyPrecip,
    },
  };
  
  final fileName = 'ecmwf_forecast_${name.toLowerCase().replaceAll(' ', '_')}.json';
  final file = File('backend/$fileName');
  file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(data));
  
  print('✓ Vygenerované: backend/$fileName');
  print('  Teplota: ${dailyMin.first.toStringAsFixed(1)}°C až ${dailyMax.first.toStringAsFixed(1)}°C');
  print('  Zrážky dnes: ${dailyPrecip.first.toStringAsFixed(1)} mm');
  print('  URL: https://raw.githubusercontent.com/richard-page/pocasie/main/backend/$fileName');
}
