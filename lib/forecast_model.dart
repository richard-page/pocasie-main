/// Globálne predpovedné modely Open-Meteo (oficiálne API).
enum WeatherForecastModel {
  bestMatch(
    cacheKey: 'best_match',
    uiTitle: 'Najlepší výber',
    uiSubtitle:
        'Predvolené Open-Meteo API (`/v1/forecast`) — server sám zvolí '
        'a skombinuje najpresnejší model pre dané miesto.',
    apiBase: 'https://api.open-meteo.com/v1/forecast',
  ),
  ecmwf(
    cacheKey: 'ecmwf_ifs',
    uiTitle: 'ECMWF IFS',
    uiSubtitle: 'Globálna predpoveď ECMWF (0,25°) cez Open-Meteo `/v1/ecmwf`.',
    apiBase: 'https://api.open-meteo.com/v1/ecmwf',
  ),
  iconSeamless(
    cacheKey: 'icon_seamless',
    uiTitle: 'ICON (DWD)',
    uiSubtitle: 'Globálny a európsky model Deutscher Wetterdienst.',
    apiBase: 'https://api.open-meteo.com/v1/forecast',
    apiModels: 'icon_seamless',
  ),
  gfsSeamless(
    cacheKey: 'gfs_seamless',
    uiTitle: 'GFS / HRRR',
    uiSubtitle: 'Globálny model NOAA; v Severnej Amerike aj hodinový HRRR.',
    apiBase: 'https://api.open-meteo.com/v1/forecast',
    apiModels: 'gfs_seamless',
  ),
  gemSeamless(
    cacheKey: 'gem_seamless',
    uiTitle: 'GEM (Kanada)',
    uiSubtitle: 'Globálny model Environment and Climate Change Canada.',
    apiBase: 'https://api.open-meteo.com/v1/forecast',
    apiModels: 'gem_seamless',
  ),
  metnoSeamless(
    cacheKey: 'metno_seamless',
    uiTitle: 'MetNo (Seversko)',
    uiSubtitle: 'Seamless model Nórskeho meteorologického inštitútu.',
    apiBase: 'https://api.open-meteo.com/v1/forecast',
    apiModels: 'metno_seamless',
  ),
  jmaSeamless(
    cacheKey: 'jma_seamless',
    uiTitle: 'JMA (Japonsko)',
    uiSubtitle: 'Model Japonskej meteorologickej agentúry.',
    apiBase: 'https://api.open-meteo.com/v1/forecast',
    apiModels: 'jma_seamless',
  );

  const WeatherForecastModel({
    required this.cacheKey,
    required this.uiTitle,
    required this.uiSubtitle,
    required this.apiBase,
    this.apiModels,
  });

  final String cacheKey;
  final String uiTitle;
  final String uiSubtitle;
  final String apiBase;
  final String? apiModels;

  static WeatherForecastModel fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return WeatherForecastModel.bestMatch;
    if (raw == 'bestmatch') return WeatherForecastModel.bestMatch;
    if (raw == 'open_meteo' ||
        raw == 'ecmwf_ifs025' ||
        raw == 'open_meteo_ecmwf') {
      return WeatherForecastModel.ecmwf;
    }
    for (final v in WeatherForecastModel.values) {
      if (v.cacheKey == raw) return v;
    }
    return WeatherForecastModel.bestMatch;
  }
}

const String kForecastModelKey = 'forecast_model_v1';

/// Po zmene logiky predpovede / formátu cache zvýšiť — staré záznamy sa ignorujú.
const int kForecastCacheSchemaVersion = 9;

/// Kľúč cache predpovede — verzia v názve zruší starú cache po zmene logiky.
String forecastWeatherCacheKey(WeatherForecastModel model, {int days = 16}) =>
    '${model.cacheKey}_v${kForecastCacheSchemaVersion}_fd$days';

String forecastWeatherCacheKeyForModelId(String modelId, {int days = 16}) =>
    forecastWeatherCacheKey(WeatherForecastModel.fromStorage(modelId), days: days);
