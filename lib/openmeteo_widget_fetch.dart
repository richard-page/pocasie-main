export 'package:pocasie/weatherapi_shared.dart'
    show widgetEffectiveWeatherCodeFromForecast;

import 'package:pocasie/weatherapi_shared.dart';

/// Widget fetch — WeatherAPI (názov súboru kvôli kompatibilite importov).
Future<Map<String, dynamic>?> widgetFetchOpenMeteoForecast(
  double lat,
  double lon,
) =>
    widgetFetchWeatherApiForecast(lat, lon);
