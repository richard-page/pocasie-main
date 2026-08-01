part of 'main.dart';

/// Predpoved cez WeatherAPI (nazov funkcie historicky Open-Meteo).
Future<Map<String, dynamic>?> _downloadOpenMeteoForecast(
  double lat,
  double lon,
  String timezone, {
  required WeatherForecastModel model,
  required bool forceRefresh,
}) async {
  assert(model.cacheKey.isNotEmpty);
  return _downloadWeatherApiForecast(
    lat,
    lon,
    timezone,
    forceRefresh: forceRefresh,
  );
}