part of 'main.dart';

class WarningData {
  final String title;
  final String description;
  final String severity;
  final String phenomenon;
  final String author;
  final String region;
  final String validFrom;
  final String validTo;
  final String link;
  final List<String> areas;

  WarningData({
    required this.title,
    required this.description,
    required this.severity,
    required this.phenomenon,
    required this.author,
    required this.region,
    required this.validFrom,
    required this.validTo,
    required this.link,
    required this.areas,
  });

  static String _str(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static List<String> _areasList(dynamic v) {
    if (v == null) return [];
    if (v is String) {
      return v
          .split(RegExp(r'[,;|]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (v is List) {
      return v.map((e) => _str(e)).where((e) => e.isNotEmpty).toList();
    }
    return [_str(v)];
  }

  /// dd.MM.yyyy HH:mm alebo ISO 8601.
  static DateTime? _parseObservedDateTime(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    final iso = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (iso != null) return iso;

    final m = RegExp(
      r'^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(s);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final y = int.parse(m.group(3)!);
      final hh = int.tryParse(m.group(4) ?? '') ?? 0;
      final mm = int.tryParse(m.group(5) ?? '') ?? 0;
      final ss = int.tryParse(m.group(6) ?? '') ?? 0;
      return DateTime(y, mo, d, hh, mm, ss);
    }
    return null;
  }

  factory WarningData.fromJson(dynamic raw) {
    if (raw is! Map) {
      return WarningData(
        title: '',
        description: '',
        severity: 'yellow',
        phenomenon: 'other',
        author: '',
        region: '',
        validFrom: '',
        validTo: '',
        link: '#',
        areas: [],
      );
    }
    final json = Map<String, dynamic>.from(raw);
    return WarningData(
      title: _str(json['title'] ?? json['name'] ?? json['headline']),
      description: _str(json['description'] ??
          json['text'] ??
          json['body'] ??
          json['detail'] ??
          json['message'] ??
          json['instruction'] ??
          json['parameters'] ??
          json['info'] ??
          json['content']),
      severity: _str(json['severity'] ?? json['level'], 'yellow'),
      phenomenon: _str(json['phenomenon'] ?? json['type'], 'other'),
      author: _str(json['author'] ?? json['source'] ?? json['issuer']),
      region: _str(json['region'] ?? json['district'] ?? json['kraj']),
      validFrom: _str(json['valid_from'] ?? json['validFrom'] ?? json['from'] ?? json['start']),
      validTo: _str(json['valid_to'] ?? json['validTo'] ?? json['until'] ?? json['end']),
      link: _str(json['link'] ?? json['url'] ?? json['href'], '#'),
      areas: _areasList(json['areas'] ?? json['districts'] ?? json['regions']),
    );
  }

  /// Nezobrazovať len po vypršaní [valid_to]. "Od zajtra" sa stále zobrazí dnes (okno webu ostáva zdrojom pravdy).
  bool get isActive {
    final toDt = _parseObservedDateTime(validTo);
    if (toDt != null && DateTime.now().isAfter(toDt.add(const Duration(minutes: 1)))) {
      return false;
    }

    final fromDt = _parseObservedDateTime(validFrom);
    if (fromDt != null && DateTime.now().add(const Duration(hours: 48)).isBefore(fromDt)) {
      return false;
    }

    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'severity': severity,
      'phenomenon': phenomenon,
      'author': author,
      'region': region,
      'valid_from': validFrom,
      'valid_to': validTo,
      'link': link,
      'areas': areas,
    };
  }
}

class HistoricalWeather {
  final double? maxTemp;
  final double? minTemp;
  final int? weatherCode;
  final String dateStr;

  HistoricalWeather({
    this.maxTemp,
    this.minTemp,
    this.weatherCode,
    required this.dateStr,
  });
}

class GeoCity {
  final String name;
  final double lat;
  final double lon;
  final String country;
  final String countryCode;
  final String admin1;
  final String admin2;
  final int? population;
  final String timezone;

  const GeoCity({
    required this.name,
    required this.lat,
    required this.lon,
    required this.country,
    required this.countryCode,
    required this.admin1,
    required this.admin2,
    this.population,
    this.timezone = 'auto',
  });

  factory GeoCity.fromGeoJson(Map<String, dynamic> json) => GeoCity(
        name: json['name'] ?? '',
        lat: (json['latitude'] as num).toDouble(),
        lon: (json['longitude'] as num).toDouble(),
        country: json['country'] ?? '',
        countryCode: json['countryCode'] ?? json['country_code'] ?? '',
        admin1: json['admin1'] ?? '',
        admin2: json['admin2'] ?? json['county'] ?? '', 
        population: (json['population'] as num?)?.toInt(),
        timezone: json['timezone'] ?? 'auto',
      );

  Map<String, dynamic> toGeoJson() => {
        'name': name,
        'latitude': lat,
        'longitude': lon,
        'country': country,
        'countryCode': countryCode,
        'admin1': admin1,
        'admin2': admin2,
        'population': population,
        'timezone': timezone,
      };
}

/// Záložné mesto, ak nie je uložená poloha a GPS nie je k dispozícii.
const GeoCity kDefaultFallbackCity = GeoCity(
  name: 'Bratislava',
  lat: 48.1486,
  lon: 17.1077,
  country: 'Slovensko',
  countryCode: 'SK',
  admin1: 'Bratislavský',
  admin2: '',
  timezone: 'Europe/Bratislava',
);

class AirQualityData {
  final int? aqi;
  final List<String>? time;
  final List<double?>? alder;
  final List<double?>? birch;
  final List<double?>? grass;
  final List<double?>? mugwort;
  final List<double?>? olive;
  final List<double?>? ragweed;

  AirQualityData({
    this.aqi,
    this.time,
    this.alder,
    this.birch,
    this.grass,
    this.mugwort,
    this.olive,
    this.ragweed,
  });

  factory AirQualityData.fromJson(Map<String, dynamic> json) {
    final current = json['current'] ?? {};
    final hourly = json['hourly'] ?? {};

    List<double?>? asDoubleList(List<dynamic>? l) => l
        ?.map((e) => e == null ? null : (e is num ? e.toDouble() : double.tryParse(e.toString())))
        .toList();
    List<String>? asStringList(List<dynamic>? l) => l?.map((e) => e.toString()).toList();

    return AirQualityData(
      aqi: (current['european_aqi'] as num?)?.toInt(),
      time: asStringList(hourly['time'] as List?),
      alder: asDoubleList(hourly['alder_pollen'] as List?),
      birch: asDoubleList(hourly['birch_pollen'] as List?),
      grass: asDoubleList(hourly['grass_pollen'] as List?),
      mugwort: asDoubleList(hourly['mugwort_pollen'] as List?),
      olive: asDoubleList(hourly['olive_pollen'] as List?),
      ragweed: asDoubleList(hourly['ragweed_pollen'] as List?),
    );
  }
}

class WeatherData {
  final CurrentWeather? current;
  final HourlyForecast? hourly;
  final DailyForecast? daily;
  final String? timezone;
  final String? timezoneAbbreviation;
  final double? elevation;
  final int? utcOffsetSeconds;
  /// Jedno-modelová predpoveď bola nedostupná — použil sa automatický vážený priemer troch výstupov API.
  final bool usedFallbackToBestMatch;
  /// Hodinová pravdepodobnosť zrážok z modela (ECMWF Open Data GRIB ju nemá).
  final bool precipitationProbabilityAvailable;
  /// `bestmatch` | `ecmwf_ifs025` — zdroj predpovede v UI.
  final String? forecastModelId;

  const WeatherData({
    this.current,
    this.hourly,
    this.daily,
    this.timezone,
    this.timezoneAbbreviation,
    this.elevation,
    this.utcOffsetSeconds,
    this.usedFallbackToBestMatch = false,
    this.precipitationProbabilityAvailable = false,
    this.forecastModelId,
  });

  bool get isBestMatchForecast =>
      forecastModelId == 'bestmatch' || usedFallbackToBestMatch;

  factory WeatherData.fromJson(Map<String, dynamic> json) => WeatherData(
        current: json['current'] != null
            ? CurrentWeather.fromJson(json['current'] as Map<String, dynamic>)
            : null,
        hourly: json['hourly'] != null
            ? HourlyForecast.fromJson(json['hourly'] as Map<String, dynamic>)
            : null,
        daily: json['daily'] != null
            ? DailyForecast.fromJson(json['daily'] as Map<String, dynamic>)
            : null,
        timezone: json['timezone'] as String?,
        timezoneAbbreviation: json['timezone_abbreviation'] as String?,
        elevation: (json['elevation'] as num?)?.toDouble(),
        utcOffsetSeconds: json['utc_offset_seconds'] as int?,
        usedFallbackToBestMatch: json['used_fallback_to_best_match'] == true,
        precipitationProbabilityAvailable:
            json['precipitation_probability_available'] == true,
        forecastModelId: json['model'] as String?,
      );

  WeatherData copyWith({
    CurrentWeather? current,
    HourlyForecast? hourly,
    DailyForecast? daily,
    String? timezone,
    String? timezoneAbbreviation,
    double? elevation,
    int? utcOffsetSeconds,
    bool? usedFallbackToBestMatch,
    bool? precipitationProbabilityAvailable,
    String? forecastModelId,
  }) {
    return WeatherData(
      current: current ?? this.current,
      hourly: hourly ?? this.hourly,
      daily: daily ?? this.daily,
      timezone: timezone ?? this.timezone,
      timezoneAbbreviation: timezoneAbbreviation ?? this.timezoneAbbreviation,
      elevation: elevation ?? this.elevation,
      utcOffsetSeconds: utcOffsetSeconds ?? this.utcOffsetSeconds,
      usedFallbackToBestMatch: usedFallbackToBestMatch ?? this.usedFallbackToBestMatch,
      precipitationProbabilityAvailable:
          precipitationProbabilityAvailable ?? this.precipitationProbabilityAvailable,
      forecastModelId: forecastModelId ?? this.forecastModelId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (current != null) 'current': current!.toJson(),
        if (hourly != null) 'hourly': hourly!.toJson(),
        if (daily != null) 'daily': daily!.toJson(),
        if (timezone != null) 'timezone': timezone,
        if (timezoneAbbreviation != null) 'timezone_abbreviation': timezoneAbbreviation,
        if (elevation != null) 'elevation': elevation,
        if (utcOffsetSeconds != null) 'utc_offset_seconds': utcOffsetSeconds,
        if (usedFallbackToBestMatch) 'used_fallback_to_best_match': true,
        if (precipitationProbabilityAvailable)
          'precipitation_probability_available': true,
        if (forecastModelId != null) 'model': forecastModelId,
      };
}

class CurrentWeather {
  final double? temperature;
  final int? isDay;
  final int? weatherCode;
  final double? relativeHumidity;
  final double? surfacePressure;
  final double? windSpeed;
  final double? windDirection;
  final double? precipitation;
  final DateTime? time;
  final double? uvIndex;
  final double? cloudCover;
  final double? apparentTemperature;
  /// Satelitný cloud cover zo živých meraní (preferovaný pred modelovým)
  final double? satelliteCloudCover;

  const CurrentWeather({
    this.temperature,
    this.isDay,
    this.weatherCode,
    this.relativeHumidity,
    this.surfacePressure,
    this.windSpeed,
    this.windDirection,
    this.precipitation,
    this.time,
    this.uvIndex,
    this.cloudCover,
    this.apparentTemperature,
    this.satelliteCloudCover,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) => CurrentWeather(
        temperature: _safeParseDouble(json['temperature_2m']),
        isDay: _safeParseInt(json['is_day']),
        weatherCode: _safeParseInt(json['weather_code']),
        relativeHumidity: _safeParseDouble(json['relative_humidity_2m']),
        surfacePressure: _safeParseDouble(json['pressure_msl'] ?? json['surface_pressure']),
        windSpeed: _safeParseDouble(json['wind_speed_10m']),
        windDirection: _safeParseDouble(json['wind_direction_10m']),
        precipitation: _safeParseDouble(json['precipitation']),
        uvIndex: _safeParseDouble(json['uv_index']),
        cloudCover: _safeParseDouble(json['cloud_cover']),
        apparentTemperature: _safeParseDouble(json['apparent_temperature']),
        satelliteCloudCover: _safeParseDouble(json['satellite_cloud_cover']),
        time: json['time'] != null ? DateTime.tryParse(json['time'].toString()) : null,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (temperature != null) 'temperature_2m': temperature,
        if (isDay != null) 'is_day': isDay,
        if (weatherCode != null) 'weather_code': weatherCode,
        if (relativeHumidity != null) 'relative_humidity_2m': relativeHumidity,
        if (surfacePressure != null) 'pressure_msl': surfacePressure,
        if (windSpeed != null) 'wind_speed_10m': windSpeed,
        if (windDirection != null) 'wind_direction_10m': windDirection,
        if (precipitation != null) 'precipitation': precipitation,
        if (time != null) 'time': time!.toIso8601String(),
        if (uvIndex != null) 'uv_index': uvIndex,
        if (cloudCover != null) 'cloud_cover': cloudCover,
        if (apparentTemperature != null) 'apparent_temperature': apparentTemperature,
        if (satelliteCloudCover != null) 'satellite_cloud_cover': satelliteCloudCover,
      };

  static double? _safeParseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _safeParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toDouble().toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class HourlyForecast {
  final List<String> time;
  final List<double?>? temperature,
      dewPoint,
      pressure, 
      windSpeed,
      windGusts,
      windDirection,
      relativeHumidity,
      precipitation,
      uvIndex,
      cloudCover,
      apparentTemperature;
  final List<int?>? weatherCode, precipitationProbability;
  final String? timezone;

  const HourlyForecast({
    required this.time,
    this.temperature,
    this.dewPoint,
    this.pressure,
    this.weatherCode,
    this.precipitationProbability,
    this.precipitation,
    this.windSpeed,
    this.windGusts,
    this.windDirection,
    this.relativeHumidity,
    this.uvIndex,
    this.cloudCover,
    this.apparentTemperature,
    this.timezone,
    });

  factory HourlyForecast.fromJson(Map<String, dynamic> json) {
    List<int?>? asIntList(List<dynamic>? l) => l
        ?.map((e) =>
            e == null ? null : (e is num ? e.toInt() : int.tryParse(e.toString())))
        .toList();
    List<double?>? asDoubleList(List<dynamic>? l) => l
        ?.map((e) => e == null
            ? null
            : (e is num ? e.toDouble() : double.tryParse(e.toString())))
        .toList();

    return HourlyForecast(
      time: (json['time'] as List).map((e) => e.toString()).toList(),
      temperature: asDoubleList(json['temperature_2m'] as List?),
      dewPoint: asDoubleList(json['dew_point_2m'] as List?),
      pressure: asDoubleList((json['pressure_msl'] ?? json['surface_pressure']) as List?),
      weatherCode: asIntList(json['weather_code'] as List?),
      precipitationProbability:
          asIntList(json['precipitation_probability'] as List?),
      precipitation: asDoubleList(json['precipitation'] as List?),
      windSpeed: asDoubleList(json['wind_speed_10m'] as List?),
      windGusts: asDoubleList(json['wind_gusts_10m'] as List?),
      windDirection: asDoubleList(json['wind_direction_10m'] as List?),
      relativeHumidity: asDoubleList(json['relative_humidity_2m'] as List?),
      uvIndex: asDoubleList(json['uv_index'] as List?),
      cloudCover: asDoubleList(json['cloud_cover'] as List?),
      apparentTemperature: asDoubleList(json['apparent_temperature'] as List?),
      timezone: json['timezone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'time': time,
        if (temperature != null) 'temperature_2m': temperature,
        if (dewPoint != null) 'dew_point_2m': dewPoint,
        if (pressure != null) 'pressure_msl': pressure,
        if (weatherCode != null) 'weather_code': weatherCode,
        if (precipitationProbability != null) 'precipitation_probability': precipitationProbability,
        if (precipitation != null) 'precipitation': precipitation,
        if (windSpeed != null) 'wind_speed_10m': windSpeed,
        if (windGusts != null) 'wind_gusts_10m': windGusts,
        if (windDirection != null) 'wind_direction_10m': windDirection,
        if (relativeHumidity != null) 'relative_humidity_2m': relativeHumidity,
        if (uvIndex != null) 'uv_index': uvIndex,
        if (cloudCover != null) 'cloud_cover': cloudCover,
        if (apparentTemperature != null) 'apparent_temperature': apparentTemperature,
        if (timezone != null) 'timezone': timezone,
      };
}

class DailyForecast {
  final List<String> time;
  final List<int?>? weatherCode, precipProbMax, windDirectionDominant;
  final List<double?>? tempMax, tempMin, precipSum, snowfallSum, uvIndexMax, windSpeedMax, windGustsMax, sunshineDuration;
  final List<String>? sunrise, sunset;
  final String? timezone;

  const DailyForecast({
    required this.time,
    this.weatherCode,
    this.tempMax,
    this.tempMin,
    this.precipProbMax,
    this.precipSum,
    this.snowfallSum,
    this.sunrise,
    this.sunset,
    this.uvIndexMax,
    this.windSpeedMax,
    this.windGustsMax,
    this.windDirectionDominant,
    this.sunshineDuration,
    this.timezone,
  });

  factory DailyForecast.fromJson(Map<String, dynamic> json) {
    List<int?>? asIntList(List<dynamic>? l) => l
        ?.map((e) =>
            e == null ? null : (e is num ? e.toInt() : int.tryParse(e.toString())))
        .toList();
    List<double?>? asDoubleList(List<dynamic>? l) => l
        ?.map((e) => e == null
            ? null
            : (e is num ? e.toDouble() : double.tryParse(e.toString())))
        .toList();

    return DailyForecast(
      time: (json['time'] as List).map((e) => e.toString()).toList(),
      weatherCode: asIntList(json['weather_code'] as List?),
      tempMax: asDoubleList(json['temperature_2m_max'] as List?),
      tempMin: asDoubleList(json['temperature_2m_min'] as List?),
      precipProbMax:
          asIntList(json['precipitation_probability_max'] as List?),
      precipSum: asDoubleList(json['precipitation_sum'] as List?),
      snowfallSum: asDoubleList(json['snowfall_sum'] as List?),
      uvIndexMax: asDoubleList(json['uv_index_max'] as List?),
      windSpeedMax: asDoubleList((json['wind_speed_10m_max'] ?? json['windspeed_10m_max']) as List?),
      windGustsMax: asDoubleList((json['wind_gusts_10m_max'] ?? json['windgusts_10m_max']) as List?),
      windDirectionDominant: asIntList((json['wind_direction_10m_dominant'] ?? json['winddirection_10m_dominant']) as List?),
      sunshineDuration: asDoubleList(json['sunshine_duration'] as List?),
      sunrise: (json['sunrise'] as List?)?.map((e) => e.toString()).toList(),
      sunset: (json['sunset'] as List?)?.map((e) => e.toString()).toList(),
      timezone: json['timezone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'time': time,
        if (weatherCode != null) 'weather_code': weatherCode,
        if (tempMax != null) 'temperature_2m_max': tempMax,
        if (tempMin != null) 'temperature_2m_min': tempMin,
        if (precipProbMax != null) 'precipitation_probability_max': precipProbMax,
        if (precipSum != null) 'precipitation_sum': precipSum,
        if (snowfallSum != null) 'snowfall_sum': snowfallSum,
        if (uvIndexMax != null) 'uv_index_max': uvIndexMax,
        if (windSpeedMax != null) 'wind_speed_10m_max': windSpeedMax,
        if (windGustsMax != null) 'wind_gusts_10m_max': windGustsMax,
        if (windDirectionDominant != null) 'wind_direction_10m_dominant': windDirectionDominant,
        if (sunshineDuration != null) 'sunshine_duration': sunshineDuration,
        if (sunrise != null) 'sunrise': sunrise,
        if (sunset != null) 'sunset': sunset,
        if (timezone != null) 'timezone': timezone,
      };
}

bool _forecastHasCoreFields(WeatherData? d) {
  if (d == null) return false;
  final h = d.hourly;
  if (h == null || h.time.isEmpty) return false;
  if (!forecastDailyHorizonComplete(d)) return false;
  return true;
}


class _SmoothedValues {
  final List<int?> weatherCodes;
  final List<double?> temperatures;
  final List<int?> precipitationProbabilities;
  final List<double?> precipitation;
  final List<double?> uvIndex;
  final List<double?> cloudCover;
  final List<double?> apparentTemperature;
  final List<bool> isDaytime;

  const _SmoothedValues({
    required this.weatherCodes,
    required this.temperatures,
    required this.precipitationProbabilities,
    required this.precipitation,
    required this.uvIndex,
    required this.cloudCover,
    required this.apparentTemperature,
    required this.isDaytime,
  });
}

