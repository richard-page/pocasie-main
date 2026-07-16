import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pocasie/forecast_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kWidgetHourlyVars =
    'temperature_2m,cloud_cover,precipitation,precipitation_probability,weather_code,wind_speed_10m';

const String _kWidgetDailyVars =
    'temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset';

const String _kWidgetCurrentVars =
    'temperature_2m,is_day,weather_code,cloud_cover,precipitation,wind_speed_10m,wind_direction_10m,relative_humidity_2m,apparent_temperature,pressure_msl';

Future<WeatherForecastModel> _widgetForecastModel() async {
  final prefs = await SharedPreferences.getInstance();
  return WeatherForecastModel.fromStorage(prefs.getString(kForecastModelKey));
}

/// Minimálny Open-Meteo fetch pre Android widget (rovnaký model ako v appke).
Future<Map<String, dynamic>?> widgetFetchOpenMeteoForecast(
  double lat,
  double lon,
) async {
  try {
    final model = await _widgetForecastModel();
    final params = <String, String>{
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': _kWidgetHourlyVars,
      'daily': _kWidgetDailyVars,
      'current': _kWidgetCurrentVars,
      'forecast_days': '16',
      'timezone': 'auto',
    };
    if (model.apiModels != null && model.apiModels!.isNotEmpty) {
      params['models'] = model.apiModels!;
    }
    final uri = Uri.parse(model.apiBase).replace(queryParameters: params);
    final r = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'pocasie-app/1.0 (flutter-widget)',
      },
    ).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) return null;
    final map = json.decode(r.body) as Map<String, dynamic>;
    if (!map.containsKey('hourly')) return null;
    return {
      ...map,
      'precipitation_probability_available': true,
      'model': model.cacheKey,
    };
  } catch (e) {
    debugPrint('Widget Open-Meteo fetch: $e');
    return null;
  }
}

int widgetEffectiveWeatherCodeFromForecast(Map<String, dynamic> forecast) {
  final cur = forecast['current'] as Map<String, dynamic>?;
  if (cur == null) return 0;
  final rawCode = (cur['weather_code'] as num?)?.toInt();
  return switch (rawCode) {
    45 || 48 => 3,
    _ => rawCode ?? 0,
  };
}
