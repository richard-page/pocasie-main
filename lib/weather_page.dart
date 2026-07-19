part of 'main.dart';

/// Pri GPS šume na jednom mieste reverse-geocode vie vrátiť susedný názov — držíme stabilný údaj z poslednej uloženej polohy.
const double _kGeoStickySamePlaceRadiusM = 1200;

/// Prepínanie mesta pri obnovení len pri výraznejšom pohybe (100 m bolo príliš agresívne).
const double _kSwitchCityMinMoveM = 1200;

GeoCity _preferStickyCityIdentity(GeoCity? anchor, GeoCity fresh, double gpsLat, double gpsLon) {
  if (anchor == null || anchor.name.trim().isEmpty) return fresh;
  const gpsFallbackPrefix = 'Poloha (';
  if (anchor.name.startsWith(gpsFallbackPrefix)) return fresh;

  final dist = Geolocator.distanceBetween(anchor.lat, anchor.lon, gpsLat, gpsLon);
  if (dist > _kGeoStickySamePlaceRadiusM) return fresh;
  if (fresh.name.trim().isEmpty || anchor.name == fresh.name) return fresh;

  final tz = fresh.timezone.isNotEmpty && fresh.timezone != 'auto'
      ? fresh.timezone
      : anchor.timezone;

  return GeoCity(
    name: anchor.name,
    lat: gpsLat,
    lon: gpsLon,
    country: anchor.country.isNotEmpty ? anchor.country : fresh.country,
    countryCode: anchor.countryCode.isNotEmpty ? anchor.countryCode : fresh.countryCode,
    admin1: anchor.admin1.isNotEmpty ? anchor.admin1 : fresh.admin1,
    admin2: anchor.admin2.isNotEmpty ? anchor.admin2 : fresh.admin2,
    population: anchor.population ?? fresh.population,
    timezone: tz,
  );
}

/// Slovníkové WMO popisy do tvaru vhodného za „Dnes bude …“ / „Večer a v noci bude …“ (nominatív; pri „očakávať“ by bol vhodný 4. pád).
String _pushSummarySkyPhrase(String rawLower) {
  final s = rawLower.trim();
  if (s.isEmpty || s == 'stabilné') return 'premenlivé počasie';

  return switch (s) {
    'jasno' => 'jasná obloha',
    'prevažne jasno' => 'prevažne jasná obloha',
    'polooblačno' => 'polooblačná obloha',
    'zamračené' => 'zamračená obloha',
    'hmla' => 'zamračená obloha',
    'inovať / hmla' => 'zamračená obloha',
    'hmla alebo slabá inováť' => 'zamračená obloha',
    _ => s.replaceAll(' / ', ' alebo '),
  };
}

/// Kľúč do prefs pre „už sme naplánovali toto upozornenie“: čas budenia po 10 min + čísla ako v texte správy (iná hodnota = zmena situácie).
String _leadAlertPlannedSlotKey(DateTime eventLocal, List<Object?> valueParts) {
  final t = eventLocal.subtract(kLeadWeatherAlertBeforeEvent);
  final tenMinBucket = (t.hour * 60 + t.minute) ~/ 10;
  final date =
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  final tail = valueParts.map((o) => o.toString()).join('|');
  return '$date|b$tenMinBucket|$tail';
}

bool _isSameLocalCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Denný/večerný súhrn: „jasná / prevažne jasná / polooblačná“ — vhodné doplniť o možný vývoj oblačnosti.
bool _phraseIsFairSummarySky(String phrase) {
  return phrase == 'jasná obloha' ||
      phrase == 'prevažne jasná obloha' ||
      phrase == 'polooblačná obloha';
}

/// WMO: zamračené (vrátane 45/48 mapovaných na oblačno v UI).
bool _wmoIsHeavyCloudOrFog(int? code) => code != null && const {3, 45, 48}.contains(code);

bool _hourlyHasLaterOvercastSameDay(WeatherData data, DateTime nowLocal) {
  final hourly = data.hourly;
  if (hourly == null || hourly.time.isEmpty || hourly.weatherCode == null) return false;
  final len = math.min(hourly.time.length, hourly.weatherCode!.length);
  for (var i = 0; i < len; i++) {
    final t = DateTime.tryParse(hourly.time[i]);
    if (t == null) continue;
    if (!_isSameLocalCalendarDay(t, nowLocal)) continue;
    if (!t.isAfter(nowLocal)) continue;
    if (_wmoIsHeavyCloudOrFog(hourly.weatherCode![i])) return true;
  }
  return false;
}

/// Rovnaký poriadok stupňov ako slovný súhrn (bez zrážok): jasná / prevažne / polo / zamračená.
/// Pri zrážkovej efektívnej ikone vráti 0 — tá patrí do inej časti súhrnu.
int _drySkyBuildupRankForComparison(int effectiveDisplayCode) {
  if (kPrecipitationCodes.contains(effectiveDisplayCode)) return 0;
  if (effectiveDisplayCode == 0) return 1;
  if (effectiveDisplayCode == 1) return 2;
  if (effectiveDisplayCode == 2) return 3;
  if (effectiveDisplayCode == 3 || effectiveDisplayCode == 45 || effectiveDisplayCode == 48) return 4;
  return 0;
}

/// Pred **nadránom** (miestne zajtra hodiny **4–9**) berie **`_effectiveHourlySlotDisplayCode`**
/// ako hodiny na obrazovke; vetu doplní iba ak je ráno vizuálne **oblačnejšie** než základ večerného výroku `baselineDisplayCode`.
bool _eveningSummaryDawnCloudBuildsVersusBaseline(WeatherData data, DateTime nowLocal, int baselineDisplayCode) {
  final h = data.hourly;
  if (h == null || h.time.isEmpty) return false;
  final baselineRank = _drySkyBuildupRankForComparison(baselineDisplayCode);
  if (baselineRank <= 0) return false;
  final tomorrow = nowLocal.add(const Duration(days: 1));

  var dawnMaxRank = 0;
  var hasComparableDawn = false;
  for (var i = 0; i < h.time.length; i++) {
    final t = DateTime.tryParse(h.time[i]);
    if (t == null || !_isSameLocalCalendarDay(t, tomorrow)) continue;
    if (t.hour < 4 || t.hour > 9) continue;
    final eff = _effectiveHourlySlotDisplayCode(h, i);
    final r = _drySkyBuildupRankForComparison(eff);
    if (r <= 0) continue;
    hasComparableDawn = true;
    if (r > dawnMaxRank) dawnMaxRank = r;
  }
  if (!hasComparableDawn) return false;
  return dawnMaxRank > baselineRank;
}

/// Rovnaký WMO kód ako hlavná ikona dennej karty pre `dayIndex` — text súhrnov musí sedieť s UI, nie s holým `daily.weather_code`.
int _dailyMainIconSkyTextCode(WeatherData data, int dayIndex, {bool lightningNearby = false}) {
  final daily = data.daily;
  final h = data.hourly;
  final current = data.current;
  if (daily == null ||
      daily.time.isEmpty ||
      daily.weatherCode == null ||
      daily.weatherCode!.isEmpty) {
    if (current?.weatherCode != null && h != null) {
      final loc = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));
      final prob = _precipProbabilityForThreshold(_precipProbabilityPercentForLocalHour(h, loc));
      return _weatherIconCodeWithPrecipThreshold(
        current!.weatherCode!,
        prob,
        cloudCoverPercent: current.cloudCover,
        hourlyPrecipitationMm: current.precipitation,
        snowfallCm: 0.0,
      );
    }
    return current?.weatherCode ?? 0;
  }

  if (dayIndex < 0 || dayIndex >= daily.time.length) return daily.weatherCode![0] ?? 0;

  final dateStr = daily.time[dayIndex];

  int dailyApiCode = daily.weatherCode![dayIndex] ?? 0;
  int dailyApiProb = daily.precipProbMax?[dayIndex] ?? 0;
  double apiDailyPrecip =
      (daily.precipSum != null && daily.precipSum!.length > dayIndex) ? (daily.precipSum![dayIndex] ?? 0.0) : 0.0;
  final double apiDailySnow = (daily.snowfallSum != null && daily.snowfallSum!.length > dayIndex)
      ? (daily.snowfallSum![dayIndex] ?? 0.0)
      : 0.0;

  double? meanHourlyCloudForDay;
  final ccList = h?.cloudCover;
  if (ccList != null && h!.time.isNotEmpty) {
    double sumC = 0;
    int nC = 0;
    for (var i = 0; i < h.time.length; i++) {
      if (h.time[i].startsWith(dateStr)) {
        final v = ccList[i];
        if (v != null) {
          sumC += v;
          nC++;
        }
      }
    }
    if (nC > 0) meanHourlyCloudForDay = sumC / nC;
  }

  List<int> displayedDayIcons = const [];
  if (h != null && current != null) {
    final locTime = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));
    final fair = _hourlyFairDisplayIconsForCalendarDay(
      h,
      dateStr,
      current,
      daily,
      locTime,
    );
    if (fair != null) displayedDayIcons = fair.$2;
  }

  final int fallbackDailyCode = dailyApiCode;

  final bool suppressWetDayIcons = shouldSuppressWetDayIconsForDay(
    h,
    dateStr,
    apiDailyPrecip,
    apiDailySnow,
    dailyApiProb,
    dailyWeatherCode: fallbackDailyCode,
    daysFromToday: dayIndex,
  );

  final showableDayPrecip = dayShowablePrecipForDailyForecast(
    h,
    dateStr,
    daysFromToday: dayIndex,
  );
  final int effectiveDailyProb = dailyPrecipProbForIconIntensity(
    dailyApiProb: dailyApiProb,
    hourlyStripMaxProb: showableDayPrecip.maxProb,
    hourlyDayMaxProb: hourlyDayMaxPrecipProb(h, dateStr),
    daysFromToday: dayIndex,
  );
  final double effectiveDailyPrecipMm = dailyPrecipMmForIconDisplay(
    apiDailyPrecip: apiDailyPrecip,
    hourlySumMm: showableDayPrecip.any ? showableDayPrecip.sumMm : 0.0,
    effectiveDailyProb: effectiveDailyProb,
    daysFromToday: dayIndex,
  );

  final locTime = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));
  final utcOff = data.utcOffsetSeconds;
  final morningWeather = _getDayPartWeather(
      dateStr, h, 'morning', daily, fallbackDailyCode, effectiveDailyProb, current, locTime,
      suppressWetDayIcons: suppressWetDayIcons,
      dailyTotalPrecipMm: effectiveDailyPrecipMm,
      dailyTotalSnowCm: apiDailySnow,
      utcOffsetSeconds: utcOff,
      lightningNearby: lightningNearby,
      daysFromToday: dayIndex);
  final afternoonWeather = _getDayPartWeather(
      dateStr, h, 'afternoon', daily, fallbackDailyCode, effectiveDailyProb, current, locTime,
      suppressWetDayIcons: suppressWetDayIcons,
      dailyTotalPrecipMm: effectiveDailyPrecipMm,
      dailyTotalSnowCm: apiDailySnow,
      utcOffsetSeconds: utcOff,
      lightningNearby: lightningNearby,
      daysFromToday: dayIndex);
  final eveningWeather = _getDayPartWeather(
      dateStr, h, 'evening', daily, fallbackDailyCode, effectiveDailyProb, current, locTime,
      suppressWetDayIcons: suppressWetDayIcons,
      dailyTotalPrecipMm: effectiveDailyPrecipMm,
      dailyTotalSnowCm: apiDailySnow,
      utcOffsetSeconds: utcOff,
      lightningNearby: lightningNearby,
      daysFromToday: dayIndex);
  final nightWeather = _getDayPartWeather(
      dateStr, h, 'night', daily, fallbackDailyCode, effectiveDailyProb, current, locTime,
      suppressWetDayIcons: suppressWetDayIcons,
      dailyTotalPrecipMm: effectiveDailyPrecipMm,
      dailyTotalSnowCm: apiDailySnow,
      utcOffsetSeconds: utcOff,
      lightningNearby: lightningNearby,
      daysFromToday: dayIndex);

  return resolveDailyCardMainIconCode(
    displayedDayIcons: displayedDayIcons,
    fallbackCode: fallbackDailyCode,
    suppressWetDayIcons: suppressWetDayIcons,
    meanHourlyCloudForDay: meanHourlyCloudForDay,
    partIconCodes: [
      morningWeather['iconCode'] as int?,
      afternoonWeather['iconCode'] as int?,
      eveningWeather['iconCode'] as int?,
      nightWeather['iconCode'] as int?,
    ],
    dailyPrecipMm: effectiveDailyPrecipMm,
    dailyPrecipProb: effectiveDailyProb,
  );
}

class WeatherPage extends StatefulWidget {
  final GeoCity? initialCity;
  const WeatherPage({super.key, this.initialCity});
  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> with WidgetsBindingObserver {
  String activeTab = 'hourly';
  bool isLoading = false, hasError = false, _isRefreshing = false;
  GeoCity? currentCity;
  WeatherData? weatherData;
  AirQualityData? airQualityData; 
  HistoricalWeather? historicalWeather;
  Timer? _heartbeatTimer;
  Timer? _weatherPollTimer;
  Timer? _radarWatchTimer;
  int _widgetRefreshIntervalMinutes = kHomeWidgetUpdateIntervalMinutesDefault;
  WindUnit _currentWindUnit = WindUnit.kmh;
  bool _myLocationEnabled = true;
  WeatherForecastModel _forecastModel = WeatherForecastModel.bestMatch;
  /// Zvyšuje sa pri každom „plnom“ načítaní počasia; zastarané odpovede sa neaplikujú (preteky pri zmene modelu / pull refresh).
  int _weatherFetchSerial = 0;
  int _radarFetchSerial = 0;
  bool _isOffline = false;
  bool _lightningNearby = false;
  RadarNowcastContext _radarNowcastContext = RadarNowcastContext.inactive;
  DateTime? _lastRadarStripRefreshAt;
  DateTime? _lastRadarContextUiApplyAt;
  /// Stopky radaru — časté obnovenie + okamžitá reakcia UI na pohyb buniek.
  static const Duration _kRadarUiRefreshMinInterval = Duration(seconds: 20);
  static const Duration _kRadarWatchInterval = Duration(seconds: 20);
  static const Duration _kRadarForecastActiveApplyInterval = Duration(seconds: 20);
  static const Duration _kRadarForecastIdleApplyInterval = Duration(minutes: 2);
  List<bool> _expandedStates = [];
  (String, Widget, String, int)? _cachedFirstHourInfo;
  Object? _cachedFirstHourInfoKey;
  bool _forceWeatherRefreshOnce = false;

  void _invalidateDisplayCaches() {
    _cachedFirstHourInfo = null;
    _cachedFirstHourInfoKey = null;
  }

  Object _firstHourDisplayCacheKey() => (
        weatherData,
        _lightningNearby,
        _radarNowcastContext,
        currentCity?.lat,
        currentCity?.lon,
      );

  Future<void> _applyRadarNowcastSignal({
    required GeoCity city,
    required int mySerial,
    required int radarSerial,
    bool force = false,
  }) async {
    if (!radarNowcastActiveForCity(city)) {
      if (!mounted || mySerial != _weatherFetchSerial) return;
      if (radarSerial != _radarFetchSerial) return;
      if (_radarNowcastContext.eligible) {
        setState(() {
          _radarNowcastContext = RadarNowcastContext.inactive;
          _lastRadarContextUiApplyAt = DateTime.now();
        });
        _invalidateDisplayCaches();
      }
      return;
    }

    // Najprv posledná snímka (ikona zrážok hneď), potom plný nowcast.
    if (force) {
      try {
        final quick = await fetchRadarNowcastQuickPinContext(city);
        if (!mounted || mySerial != _weatherFetchSerial) return;
        if (radarSerial != _radarFetchSerial) return;
        if (quick.eligible &&
            (quick.pinForecast.wetAtPinNow ||
                quick.precipNow ||
                quick.pinForecast.approaching)) {
          setState(() {
            _radarNowcastContext = quick;
            _lastRadarContextUiApplyAt = DateTime.now();
          });
          _invalidateDisplayCaches();
        }
      } catch (e) {
        debugPrint('Radar quick pin failed: $e');
      }
    }

    RadarNowcastContext radarCtx = RadarNowcastContext.inactive;
    try {
      radarCtx = await _fetchRadarNowcastForCity(city);
    } catch (e) {
      debugPrint('Radar nowcast fetch failed: $e');
    }
    if (!mounted || mySerial != _weatherFetchSerial) return;
    if (radarSerial != _radarFetchSerial) return;
    if (!force && !_radarContextUiNeedsUpdate(radarCtx)) return;
    setState(() {
      _radarNowcastContext = radarCtx;
      _lastRadarContextUiApplyAt = DateTime.now();
    });
    _invalidateDisplayCaches();
  }

  Future<void> _applyLightningSignal({
    required GeoCity city,
    required int mySerial,
  }) async {
    bool lightningNear = false;
    try {
      lightningNear = await lightningDetectedNear(city.lat, city.lon);
    } catch (e) {
      debugPrint('Lightning fetch failed: $e');
    }
    if (!mounted || mySerial != _weatherFetchSerial) return;
    if (lightningNear == _lightningNearby) return;
    setState(() => _lightningNearby = lightningNear);
    _invalidateDisplayCaches();
  }

  /// Blesky + prípadný retry nowcastu (ak early kick ešte nedodal eligible).
  void _scheduleSecondaryWeatherSignals({
    required GeoCity city,
    required int mySerial,
    required int radarSerial,
  }) {
    unawaited(_applyLightningSignal(city: city, mySerial: mySerial));
    if (!_radarNowcastContext.eligible) {
      unawaited(_applyRadarNowcastSignal(
        city: city,
        mySerial: mySerial,
        radarSerial: radarSerial,
        force: true,
      ));
    }
  }

  /// Spusti nowcast už počas sťahovania OM — často hotový skôr / spolu s UI.
  void _kickRadarNowcastEarly({
    required GeoCity city,
    required int mySerial,
    required int radarSerial,
    bool force = false,
  }) {
    if (!radarNowcastActiveForCity(city)) return;
    unawaited(_applyRadarNowcastSignal(
      city: city,
      mySerial: mySerial,
      radarSerial: radarSerial,
      force: force,
    ));
  }

  void _deferRadarSetup(GeoCity city, {bool forceReload = false}) {
    // Pri zmene lokality precentruj (alebo reload) — bodka musí ísť na nové miesto.
    final cityChanged = _lastRadarCity == null ||
        (_lastRadarCity!.lat - city.lat).abs() > 0.0001 ||
        (_lastRadarCity!.lon - city.lon).abs() > 0.0001 ||
        _lastRadarCity!.name != city.name;
    _pendingRadarForceReload = forceReload || cityChanged;
    if (!_supportsRadarForCity(city)) return;
    // Hneď stiahni slovakia.geojson (~1 MB) — WebView to nestíha bez prefetchu.
    prefetchRadarMapAssets();
    _scheduleRadarWarmLoad(city);
  }

  /// Spustí WebView hneď; kým nie je karta, beží Offstage v plnej veľkosti (nie 1×1).
  void _scheduleRadarWarmLoad(GeoCity city) {
    if (!_supportsRadarForCity(city)) return;
    _radarWarmLoadTimer?.cancel();
    _radarWarmLoadTimer = null;
    if (_radarController != null) {
      final cityChanged = _lastRadarCity == null ||
          (_lastRadarCity!.lat - city.lat).abs() > 0.0001 ||
          (_lastRadarCity!.lon - city.lon).abs() > 0.0001 ||
          _lastRadarCity!.name != city.name;
      if (_pendingRadarForceReload || cityChanged) {
        final hardReload = _pendingRadarForceReload && !cityChanged;
        _pendingRadarForceReload = false;
        _setupRadarController(
          city,
          forceReload: hardReload,
          preferRecenter: cityChanged && !hardReload,
        );
      }
      return;
    }
    final force = _pendingRadarForceReload;
    _pendingRadarForceReload = false;
    _setupRadarController(city, forceReload: force);
  }

  void _scheduleRadarMapUiIfNeeded(GeoCity city) {
    prefetchRadarMapAssets();
    _scheduleRadarWarmLoad(city);

    if (_radarMapUiReady) {
      final cityChanged = _lastRadarCity == null ||
          (_lastRadarCity!.lat - city.lat).abs() > 0.0001 ||
          (_lastRadarCity!.lon - city.lon).abs() > 0.0001 ||
          _lastRadarCity!.name != city.name;
      if (_radarController == null || cityChanged || _pendingRadarForceReload) {
        final hardReload = _pendingRadarForceReload && !cityChanged;
        _setupRadarController(
          city,
          forceReload: hardReload || _radarController == null,
          preferRecenter: cityChanged && _radarController != null && !hardReload,
        );
        _pendingRadarForceReload = false;
      }
      return;
    }
    _revealRadarMapUi(city);
  }

  void _revealRadarMapUi(GeoCity city) {
    if (_radarMapUiReady) {
      final cityChanged = _lastRadarCity == null ||
          (_lastRadarCity!.lat - city.lat).abs() > 0.0001 ||
          (_lastRadarCity!.lon - city.lon).abs() > 0.0001 ||
          _lastRadarCity!.name != city.name;
      if (cityChanged || _pendingRadarForceReload) {
        final hardReload = _pendingRadarForceReload && !cityChanged;
        _setupRadarController(
          city,
          forceReload: hardReload,
          preferRecenter: cityChanged && !hardReload,
        );
        _pendingRadarForceReload = false;
      }
      return;
    }
    _radarMapUiReady = true;
    _radarMapUiTimer?.cancel();
    _radarMapUiTimer = null;
    final cityChanged = _lastRadarCity == null ||
        (_lastRadarCity!.lat - city.lat).abs() > 0.0001 ||
        (_lastRadarCity!.lon - city.lon).abs() > 0.0001 ||
        _lastRadarCity!.name != city.name;
    if (_radarController == null || cityChanged || _pendingRadarForceReload) {
      final hardReload = _pendingRadarForceReload && !cityChanged;
      _setupRadarController(
        city,
        forceReload: hardReload || _radarController == null,
        preferRecenter: cityChanged && _radarController != null && !hardReload,
      );
    }
    _pendingRadarForceReload = false;
    if (mounted) setState(() {});
    // Presun Offstage → karta: Mapbox potrebuje resize, inak ostane prázdny.
    final ctrl = _radarController;
    if (ctrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _radarController != ctrl) return;
        unawaited(ctrl.runJavaScript('''
          (function(){
            try {
              document.documentElement.classList.add('hide-ui');
              if (typeof map !== 'undefined' && map && map.resize) map.resize();
              window.dispatchEvent(new Event('resize'));
            } catch (e) {}
          })();
        '''));
      });
    }
  }

  void _ensureRadarMapUiNow(GeoCity city, {bool forceReload = false}) {
    _radarMapUiTimer?.cancel();
    _radarMapUiTimer = null;
    _radarWarmLoadTimer?.cancel();
    _radarWarmLoadTimer = null;
    _radarMapUiReady = true;
    _pendingRadarForceReload = forceReload;
    prefetchRadarMapAssets();
    _setupRadarController(city, forceReload: forceReload);
    _pendingRadarForceReload = false;
  }

  void _markRadarContentReady() {
    _radarContentReadyTimer?.cancel();
    _radarContentReadyTimer = null;
    if (!mounted) {
      _radarContentReady = true;
      _isRadarLoading = false;
      _radarMapUiReady = true;
      return;
    }
    if (_radarContentReady && !_isRadarLoading && _radarMapUiReady) return;
    setState(() {
      _radarContentReady = true;
      _isRadarLoading = false;
      _radarLoadFailed = false;
      _radarMapUiReady = true;
    });
  }

  /// Max strop len ak gate zlyhá — bežne ready skôr (hneď po dlaždiciach).
  void _armRadarContentReadyFallback() {
    _radarContentReadyTimer?.cancel();
    _radarContentReadyTimer = Timer(const Duration(milliseconds: 2800), () {
      _radarContentReadyTimer = null;
      if (!mounted || _radarContentReady) return;
      _markRadarContentReady();
    });
  }

  /// Hneď po mapa + hranice + zrážky + tiles — bez umelých 0,5–2 s pauz.
  static const String _kRadarReadyGateJs = r'''
(function() {
  try {
    document.documentElement.classList.add('hide-ui');
    document.documentElement.classList.remove('radar-layers-ready');
    var chrome = document.getElementById('app-radar-chrome');
    if (chrome) chrome.remove();
    if (!document.getElementById('app-radar-gate')) {
      var s = document.createElement('style');
      s.id = 'app-radar-gate';
      s.textContent =
        'html.hide-ui .legend-panel,html.hide-ui .controls-wrapper,' +
        'html.hide-ui .settings-btn,html.hide-ui .settings-menu,' +
        'html.hide-ui #radarLegendImg{display:none!important;opacity:0!important;visibility:hidden!important;}' +
        '#mapa{opacity:0!important;transition:none!important;}' +
        'html.radar-layers-ready #mapa{opacity:1!important;}';
      (document.head || document.documentElement).appendChild(s);
    }
    var loader = document.getElementById('loader-wrapper');
    if (loader) {
      loader.style.display = 'none';
      loader.style.opacity = '0';
      loader.style.visibility = 'hidden';
    }
    if (window.ukazLoader) window.ukazLoader = function(){};
    if (window.skryLoader) window.skryLoader = function(){};

    if (window.__radarReadyArmed) return;
    window.__radarReadyArmed = true;
    var done = false;
    function finish() {
      if (done) return;
      done = true;
      document.documentElement.classList.add('hide-ui');
      document.documentElement.classList.add('radar-layers-ready');
      try {
        if (typeof map !== 'undefined' && map && map.resize) map.resize();
      } catch (e) {}
      try {
        if (window.RadarReady && RadarReady.postMessage) RadarReady.postMessage('1');
      } catch (e) {}
    }
    function layersPresent() {
      try {
        if (typeof map === 'undefined' || !map || !map.getSource) return false;
        if (typeof mapLoaded !== 'undefined' && !mapLoaded) return false;
        if (!map.getSource('sk-borders')) return false;
        if (!map.getSource('radar-source-0') && !map.getSource('coverage-source')) return false;
        return true;
      } catch (e) { return false; }
    }
    function tilesReady() {
      try {
        if (!document.querySelector('.mapboxgl-canvas')) return false;
        // Mapbox: dlaždice hotové (ak API nie je, stačí loaded/canvas).
        if (typeof map.areTilesLoaded === 'function') return map.areTilesLoaded();
        if (typeof map.loaded === 'function') return map.loaded();
        return true;
      } catch (e) { return false; }
    }
    var n = 0;
    var t = setInterval(function() {
      n++;
      if (layersPresent() && tilesReady()) {
        clearInterval(t);
        finish(); // hneď — žiadne setTimeout pauzy
      } else if (n > 35) {
        // ~2,1 s strop (staršie zariadenia / pomalá sieť)
        clearInterval(t);
        finish();
      }
    }, 60);
  } catch (e) {
    try {
      document.documentElement.classList.add('radar-layers-ready');
      if (window.RadarReady && RadarReady.postMessage) RadarReady.postMessage('1');
    } catch (e2) {}
  }
})();
''';

  String _radarRecenterJs(GeoCity city) {
    return '''
(function() {
  try {
    document.documentElement.classList.add('hide-ui');
    document.documentElement.classList.add('radar-layers-ready');
    var lat = ${city.lat};
    var lon = ${city.lon};
    var z = (typeof requestedZoom !== 'undefined' && !isNaN(requestedZoom)) ? requestedZoom : 7;
    if (typeof map !== 'undefined' && map) {
      map.jumpTo({ center: [lon, lat], zoom: z });
      map.resize();
      if (typeof userMarker !== 'undefined' && userMarker) {
        userMarker.setLngLat([lon, lat]);
      } else if (typeof mapboxgl !== 'undefined') {
        var el = document.createElement('div');
        el.className = 'location-dot';
        userMarker = new mapboxgl.Marker(el).setLngLat([lon, lat]).addTo(map);
      }
    }
  } catch (e) {}
})();
''';
  }

  Future<void> _injectRadarReadyGate() async {
    final ctrl = _radarController;
    if (ctrl == null) return;
    try {
      await ctrl.runJavaScript(_kRadarReadyGateJs);
    } catch (_) {}
  }

  Future<void> _recenterRadarOnCity(GeoCity city) async {
    final ctrl = _radarController;
    if (ctrl == null) return;
    _lastRadarCity = city;
    try {
      await ctrl.runJavaScript(_radarRecenterJs(city));
    } catch (_) {
      if (!mounted) return;
      _setupRadarController(city, forceReload: true);
    }
  }

  /// Offstage host v plnej veľkosti karty — 1×1 lámalo Mapbox tiles / geojson timing.
  Widget _buildRadarWarmupHost() {
    if (_radarMapUiReady || _radarWebViewWidget == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: appRecentsCoverNotifier,
      builder: (context, cover, _) {
        if (cover) return const SizedBox.shrink();
        final w = MediaQuery.sizeOf(context).width;
        return Offstage(
          offstage: true,
          child: SizedBox(
            width: w > 0 ? w : 360,
            height: 220,
            child: _radarWebViewWidget!,
          ),
        );
      },
    );
  }

  void _deferVystrahyWarmup(GeoCity city) {
    if (!_supportsVystrahyForCity(city)) {
      VystrahyWebViewPreloader.instance.cancelScheduledWarmup();
      return;
    }
    // Hneď prefetch + WebView — okresy sa sťahujú async; 1–2 s delay bolo neskoro.
    VystrahyWebViewPreloader.instance.updateUserLocation(city.lat, city.lon);
    VystrahyWebViewPreloader.instance.scheduleWarmup(delay: Duration.zero);
  }

  bool _isLoadingWebcams = false;
  String? _webcamsError;
  String? _webcamsLoadedForCityKey;
  String? _webcamsRequestedForCityKey;
  List<_ShmuCameraItem> _nearbyWebcams = const [];
  final Map<String, bool> _cameraOnlineStatus = {};
  DateTime? _lastWebcamRefreshAt;
  int _webcamPreviewCacheBuster = DateTime.now().millisecondsSinceEpoch;
  DateTime? _lastOfflineRecoveryAttemptAt;
  DateTime? _lastLocationServicesOfferAt;

  WebViewController? _radarController;
  GeoCity? _lastRadarCity;
  bool _pendingRadarForceReload = false;
  bool _radarMapUiReady = false;
  /// Mapa + geojson + zrážky pripravené (Flutter overlay sa skryje až potom).
  bool _radarContentReady = false;
  Timer? _radarMapUiTimer;
  Timer? _radarWarmLoadTimer;
  Timer? _radarContentReadyTimer;
  bool _isRadarFullscreen = false; 
  bool _isRadarReturning = false;
  bool _isRadarLoading = false;
  bool _radarLoadFailed = false;
  bool _radarOffline = false;
  int _radarAutoRetryCount = 0;
  Timer? _radarLoadTimeoutTimer;
  Timer? _radarConnectivityTimer;
  bool _radarConnectivityCheckInFlight = false;

  final GlobalKey _radarWebViewKey = GlobalKey();
  Widget? _radarWebViewWidget;

  final Color primaryColor = kAmbientBlendColor;
  final Color secondaryColor = kAppCardNavy;
  final Color accentColor = kAppAccentBlue;
  final Color lightColor = const Color(0xFFE8EEF5);
  final Color glassColor = const Color(0x14FFFFFF);
  final Color glassBorderColor = kAppCardNavyBorder;

  final Color cardBackgroundColor = kAppCardNavy;
  final Color textColor = Colors.white;

  /// Rovnaká vertikálna medzera medzi kartami a sekciami na domovskej obrazovke (len `bottom` predchádzajúceho bloku).
  static const double _kHomeForecastSectionGap = 10;

  static const TextStyle _kHomeInsightTitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
  );

  static TextStyle get _kHomeInsightSubtitleStyle => TextStyle(
        color: Colors.white.withValues(alpha: 0.88),
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        height: 1.35,
      );

  static const double _kHomeInsightLeadingSize = 36;
  static const double _kHomeInsightLeadingGap = 12;
  static const double _kHomeQuickActionIconSize = 18;

  Widget _homeInsightLeadingSlot(Widget icon) {
    return SizedBox(
      width: _kHomeInsightLeadingSize,
      height: _kHomeInsightLeadingSize,
      child: Center(child: icon),
    );
  }
  /// Rovnaká max. šírka a bočný okraj ako riadky 24 h / 14 dní.
  static const double _kForecastStripMaxWidth = 800;

  BoxDecoration get _forecastStripCardDecoration =>
      appSurfaceDecoration(radius: 20);

  /// Rovnaký obal ako jeden riadok v 24 h / 14 dňoch.
  Widget _forecastStripCardShell({
    required Widget child,
    VoidCallback? onTap,
    EdgeInsetsGeometry padding = const EdgeInsets.only(bottom: 4, left: 12, right: 12),
  }) {
    Widget card = Container(
      decoration: _forecastStripCardDecoration,
      child: child,
    );
    if (onTap != null) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      );
    }
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kForecastStripMaxWidth),
          child: card,
        ),
      ),
    );
  }

  TextStyle get mono => const TextStyle(
      fontFeatures: [ui.FontFeature.tabularFigures(), ui.FontFeature.liningFigures()]);

  ui.Color? get secondary => null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_appStartup());
  }

  Future<void> _appStartup() async {
    // Hneď DNS/TCP + geojson — ešte pred settings / weather fetch.
    if (widget.initialCity != null) {
      currentCity = widget.initialCity;
      if (_supportsRadarForCity(widget.initialCity)) {
        prefetchRadarMapAssets();
      }
      // Výstrahy: WebView + okresy čo najskôr (nie až po weather fetch).
      if (_supportsVystrahyForCity(widget.initialCity)) {
        final city = widget.initialCity!;
        final preloader = VystrahyWebViewPreloader.instance;
        preloader.updateUserLocation(city.lat, city.lon);
        preloader.scheduleWarmup(delay: Duration.zero);
      }
      if (mounted) setState(() {});
    }
    await _loadSettings();
    final cachePurged = await CacheManager.ensureForecastCacheGeneration();
    _forceWeatherRefreshOnce = cachePurged;
    if (!mounted) return;
    if (widget.initialCity != null) {
      currentCity = widget.initialCity;
      if (_supportsRadarForCity(currentCity)) {
        _deferRadarSetup(currentCity!);
      }
      await fetchWeatherByCity(widget.initialCity!, forceRefresh: cachePurged);
      _updateOneSignalTags(widget.initialCity!);
    } else {
      await _initFromHomeOrLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _weatherPollTimer?.cancel();
    _radarWatchTimer?.cancel();
    _radarLoadTimeoutTimer?.cancel();
    _radarConnectivityTimer?.cancel();
    _radarMapUiTimer?.cancel();
    _radarWarmLoadTimer?.cancel();
    _radarContentReadyTimer?.cancel();
    VystrahyWebViewPreloader.instance.cancelScheduledWarmup();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final ctrl = _radarController;
      if (ctrl != null) {
        unawaited(ctrl.runJavaScript('''
          (function(){
            try {
              if (typeof map !== 'undefined' && map && map.resize) map.resize();
              window.dispatchEvent(new Event('resize'));
            } catch (e) {}
          })();
        '''));
      }
      unawaited(LocalTestPushService.applyFromSettingsIfAndroidExactAlarmsAllowed());
      unawaited(_loadSettings());
      if (currentCity != null && _supportsRadarForCity(currentCity)) {
        // Pri návrate do appky radar nereštartujeme vždy, inak zbytočne bliká.
        final shouldReloadRadar = _radarController == null || _radarLoadFailed;
        if (shouldReloadRadar && currentCity != null) {
          _scheduleRadarMapUiIfNeeded(currentCity!);
        }
      }
      if (_radarController != null && _supportsRadarForCity(currentCity)) {
        _ensureRadarConnectivityWatcher();
      }
      _ensureRadarWatchTimer();
      // Okamžite prepočítaj nowcast — oči na stopkách po návrate.
      final city = currentCity;
      if (city != null && radarNowcastActiveForCity(city)) {
        _lastRadarContextUiApplyAt = null;
        unawaited(_refreshRadarNowcastForCity(city));
      }
      if (_isOffline) {
        unawaited(_maybeRecoverFromOffline(force: true));
      } else if (currentCity != null && !isLoading && !_isRefreshing) {
        unawaited(_refreshData());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Periodické pingovanie siete pre radar žerie výkon na emulátori — pri pozadí vypnúť.
      _radarConnectivityTimer?.cancel();
      _radarConnectivityTimer = null;
      _radarWatchTimer?.cancel();
      _radarWatchTimer = null;
    }
  }

  Future<void> _openRadarFullscreen() async {
    if (!mounted) return;
    if (currentCity == null || !_supportsRadarForCity(currentCity)) {
      return;
    }
    _ensureRadarMapUiNow(currentCity!);
    if (_radarController == null) return;

    setState(() => _isRadarFullscreen = true);
    unawaited(_radarController!.runJavaScript('if(window.setFullscreen) window.setFullscreen(true);'));

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => FullscreenRadarPage(
          controller: _radarController!,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );

    if (mounted) {
      setState(() {
        _isRadarFullscreen = false;
        _isRadarReturning = true;
      });
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          setState(() => _isRadarReturning = false);
        }
      });
    }
  }

  void _setupRadarController(
    GeoCity city, {
    bool forceReload = false,
    bool preferRecenter = false,
    bool cacheBust = false,
  }) {
    if (!_supportsRadarForCity(city)) {
      return;
    }
    final hasCityChanged = _lastRadarCity == null ||
        (_lastRadarCity!.lat - city.lat).abs() > 0.0001 ||
        (_lastRadarCity!.lon - city.lon).abs() > 0.0001 ||
        _lastRadarCity!.name != city.name;

    // Zmena lokality: skôr jumpTo + marker — mapa/hranice/zrážky ostanú, bez blank reloadu.
    if (_radarController != null &&
        preferRecenter &&
        hasCityChanged &&
        !forceReload &&
        _radarContentReady &&
        !_radarLoadFailed) {
      unawaited(_recenterRadarOnCity(city));
      return;
    }

    if (_radarController == null || hasCityChanged || forceReload) {
      _lastRadarCity = city;
      final url = _buildRadarUrl(city, cacheBust: cacheBust);

      if (_radarController == null) {
        late final PlatformWebViewControllerCreationParams params;
        if (WebViewPlatform.instance is AndroidWebViewController) {
          params = AndroidWebViewControllerCreationParams();
        } else {
          params = const PlatformWebViewControllerCreationParams();
        }
        _radarController = WebViewController.fromPlatformCreationParams(params)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(kAmbientBlendColor)
          ..addJavaScriptChannel(
            'RadarReady',
            onMessageReceived: (JavaScriptMessage message) {
              _markRadarContentReady();
            },
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (String url) {
                _radarLoadTimeoutTimer?.cancel();
                _radarContentReady = false;
                if (mounted) {
                  setState(() {
                    _isRadarLoading = true;
                    _radarLoadFailed = false;
                    _radarContentReady = false;
                  });
                } else {
                  _isRadarLoading = true;
                  _radarLoadFailed = false;
                }
                _armRadarContentReadyFallback();
                _radarLoadTimeoutTimer = Timer(const Duration(seconds: 12), () {
                  if (!_isRadarLoading && _radarContentReady) return;
                  if (_radarContentReady) return;
                  _handleRadarLoadFailure(autoRetry: true);
                });
              },
              onPageFinished: (String url) {
                _radarLoadTimeoutTimer?.cancel();
                _radarAutoRetryCount = 0;
                _radarOffline = false;
                // Gate čaká na mapa+hranice+zrážky; neoznačovať ready hneď po HTML.
                unawaited(_injectRadarReadyGate());
                if (mounted && _isRadarFullscreen) {
                  _radarController!.runJavaScript(
                      'if(window.setFullscreen) window.setFullscreen(true); else window.dispatchEvent(new Event("resize"));');
                }
                if (mounted && !_radarMapUiReady && currentCity != null) {
                  _revealRadarMapUi(currentCity!);
                }
                unawaited(_radarController!.runJavaScript('''
                  (function(){
                    try {
                      document.documentElement.classList.add('hide-ui');
                      if (typeof map !== 'undefined' && map && map.resize) {
                        map.resize();
                      }
                      window.dispatchEvent(new Event('resize'));
                    } catch (e) {}
                  })();
                '''));
              },
              onWebResourceError: (WebResourceError error) {
                // Neobnovuj celý radar pri chybe čiastkového assetu (tile/img/js) —
                // to spôsobuje náhodné prebliknutia počas pozerania predpovede.
                final bool mainFrameFailed = error.isForMainFrame ?? true;
                if (!mainFrameFailed) return;
                _handleRadarLoadFailure(autoRetry: true);
              },
            ),
          );

        _radarWebViewWidget = RepaintBoundary(
          child: WebViewWidget(
            key: _radarWebViewKey,
            controller: _radarController!,
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            },
          ),
        );
        _ensureRadarConnectivityWatcher();
      }

      if (mounted) {
        setState(() {
          _isRadarLoading = true;
          _radarLoadFailed = false;
          _radarContentReady = false;
        });
      } else {
        _isRadarLoading = true;
        _radarLoadFailed = false;
        _radarContentReady = false;
      }
      _armRadarContentReadyFallback();
      // Load po frame — WebView musí byť v strome (plná karta), inak Mapbox/geojson nestihnú.
      final loadUrl = url;
      final ctrl = _radarController!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _radarController != ctrl) return;
        // Nový document = znova arm gate.
        unawaited(ctrl.runJavaScript('window.__radarReadyArmed = false;').catchError((_) {}));
        ctrl.loadRequest(Uri.parse(loadUrl));
      });
    }
  }

  String _buildRadarUrl(GeoCity city, {bool cacheBust = false}) =>
      buildMeteoRadarUrl(city, cacheBust: cacheBust);

  void _handleRadarLoadFailure({required bool autoRetry}) {
    _radarLoadTimeoutTimer?.cancel();
    _radarContentReadyTimer?.cancel();
    _radarContentReadyTimer = null;
    if (mounted) {
      setState(() {
        _isRadarLoading = false;
        _radarLoadFailed = true;
      });
    } else {
      _isRadarLoading = false;
      _radarLoadFailed = true;
    }
    // Pri zlyhaní si overíme, či ide o offline stav — vtedy ukážeme zrozumiteľnejšiu hlášku.
    unawaited(() async {
      final hasInternet = await hasInternetConnection();
      if (!hasInternet && mounted) {
        setState(() {
          _radarOffline = true;
        });
      }
    }());
    if (!autoRetry || _radarController == null || _lastRadarCity == null) return;
    if (_radarAutoRetryCount >= 2) return;
    _radarAutoRetryCount += 1;
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      if (!mounted || _radarController == null || _lastRadarCity == null) return;
      final hasInternet = await hasInternetConnection();
      if (!mounted) return;
      if (!hasInternet) {
        setState(() {
          _isRadarLoading = false;
          _radarLoadFailed = true;
          _radarOffline = true;
        });
        return;
      }
      final retryUrl = _buildRadarUrl(_lastRadarCity!, cacheBust: true);
      setState(() {
        _isRadarLoading = true;
        _radarLoadFailed = false;
        _radarOffline = false;
        _radarContentReady = false;
      });
      _armRadarContentReadyFallback();
      unawaited(_radarController!
          .runJavaScript('window.__radarReadyArmed = false;')
          .catchError((_) {}));
      _radarController!.loadRequest(Uri.parse(retryUrl));
    });
  }

  void _ensureRadarConnectivityWatcher() {
    if (_radarConnectivityTimer != null && _radarConnectivityTimer!.isActive) return;
    _radarConnectivityTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(_pollRadarConnectivity());
    });
  }

  Future<void> _pollRadarConnectivity() async {
    if (_radarConnectivityCheckInFlight) return;
    if (!mounted) return;
    _radarConnectivityCheckInFlight = true;
    try {
      final hasInternet = await hasInternetConnection();
      if (!mounted) return;
      if (!hasInternet) {
        if (!_radarOffline || !_radarLoadFailed) {
          _radarLoadTimeoutTimer?.cancel();
          setState(() {
            _isRadarLoading = false;
            _radarLoadFailed = true;
            _radarOffline = true;
          });
        }
      } else if (_radarOffline) {
        // Internet sa vrátil — automaticky obnov radar.
        _radarAutoRetryCount = 0;
        if (_radarController != null && _lastRadarCity != null) {
          final retryUrl = _buildRadarUrl(_lastRadarCity!, cacheBust: true);
          setState(() {
            _isRadarLoading = true;
            _radarLoadFailed = false;
            _radarOffline = false;
            _radarContentReady = false;
          });
          _armRadarContentReadyFallback();
          unawaited(_radarController!
              .runJavaScript('window.__radarReadyArmed = false;')
              .catchError((_) {}));
          _radarController!.loadRequest(Uri.parse(retryUrl));
        }
      }
    } finally {
      _radarConnectivityCheckInFlight = false;
    }
  }

  Future<void> _manualRadarRetry() async {
    if (_radarController == null || _lastRadarCity == null) return;
    _radarAutoRetryCount = 0;
    final hasInternet = await hasInternetConnection();
    if (!mounted) return;
    if (!hasInternet) {
      setState(() {
        _isRadarLoading = false;
        _radarLoadFailed = true;
        _radarOffline = true;
      });
      return;
    }
    final retryUrl = _buildRadarUrl(_lastRadarCity!, cacheBust: true);
    setState(() {
      _isRadarLoading = true;
      _radarLoadFailed = false;
      _radarOffline = false;
      _radarContentReady = false;
    });
    _armRadarContentReadyFallback();
    unawaited(_radarController!
        .runJavaScript('window.__radarReadyArmed = false;')
        .catchError((_) {}));
    _radarController!.loadRequest(Uri.parse(retryUrl));
  }

  Future<void> _loadSettings() async {
    final s = await SettingsManager.getWeatherPageSettingsSnapshot();
    if (!mounted) return;
    setState(() {
      _currentWindUnit = s.windUnit;
      _myLocationEnabled = s.myLocationEnabled;
      _widgetRefreshIntervalMinutes = s.widgetIntervalMinutes;
      _forecastModel = WeatherForecastModel.bestMatch;
    });
    _restartPeriodicTimers();
    unawaited(rescheduleAndroidHomeWidgetPeriodicWork());
  }

  void _restartPeriodicTimers() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 50), (_) {
      unawaited(_maybeRecoverFromOffline());
      _maybeRefreshNearbyWebcams();
      final city = currentCity;
      if (city != null) {
        unawaited(_refreshLightningForCity(city));
      }
    });

    _ensureRadarWatchTimer();

    _weatherPollTimer?.cancel();
    final mins = _widgetRefreshIntervalMinutes.clamp(
      kHomeWidgetUpdateIntervalMinutesMin,
      kHomeWidgetUpdateIntervalMinutesMax,
    );
    _weatherPollTimer = Timer.periodic(Duration(minutes: mins), (_) {
      if (currentCity != null && !isLoading && !_isRefreshing) {
        unawaited(_refreshData());
      }
    });
  }

  /// Kontinuálne sledovanie radaru — každých ~20 s nový fetch + matematika.
  void _ensureRadarWatchTimer() {
    if (_radarWatchTimer != null && _radarWatchTimer!.isActive) return;
    _radarWatchTimer?.cancel();
    _radarWatchTimer = Timer.periodic(_kRadarWatchInterval, (_) {
      final city = currentCity;
      if (city == null || !radarNowcastActiveForCity(city)) return;
      if (!mounted) return;
      unawaited(_refreshRadarNowcastForCity(city));
    });
  }

  Future<void> _maybeRecoverFromOffline({bool force = false}) async {
    if (!_isOffline || isLoading || _isRefreshing) return;
    final now = DateTime.now();
    if (!force &&
        _lastOfflineRecoveryAttemptAt != null &&
        now.difference(_lastOfflineRecoveryAttemptAt!) < const Duration(seconds: 20)) {
      return;
    }
    _lastOfflineRecoveryAttemptAt = now;
    final hasInternet = await hasInternetConnection();
    if (!hasInternet) return;
    await _retryConnection();
  }

  bool _hourlyIsoMatchesLocalWallHour(String iso, DateTime loc) {
    final ft = DateTime.tryParse(iso);
    if (ft == null) return false;
    return ft.year == loc.year &&
        ft.month == loc.month &&
        ft.day == loc.day &&
        ft.hour == loc.hour;
  }

  /// Jednotný UV pre „teraz“: hodnota z **hodinového slotu** pre lokálnu stenovú hodinu (súlad s rozbalením riadku).
  double? _uvForLocalWallClockHour(HourlyForecast h, DateTime loc, CurrentWeather? c) {
    if (h.uvIndex != null && h.uvIndex!.isNotEmpty) {
      final int len = math.min(h.time.length, h.uvIndex!.length);
      for (var i = 0; i < len; i++) {
        if (!_hourlyIsoMatchesLocalWallHour(h.time[i], loc)) continue;
        final uv = h.uvIndex![i] ?? c?.uvIndex;
        if (uv != null) return uv;
      }
    }
    if (c?.uvIndex != null) return c!.uvIndex;
    final idx = _hourlyIndexContainingLocalTime(h, loc) ?? _nearestHourlyIndex(h, loc);
    if (idx != null) {
      return _estimatedUvForHourlySlot(h, idx);
    }
    return null;
  }

  Map<String, String>? _getTodayUvWarning() {
    final h = weatherData?.hourly;
    if (h == null || h.time.isEmpty || h.uvIndex == null || h.uvIndex!.isEmpty) return null;
    final today = _getCurrentLocationTime();
    final dateStr =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final int len = math.min(h.time.length, h.uvIndex!.length);
    double? maxUv;
    for (int i = 0; i < len; i++) {
      if (!h.time[i].startsWith(dateStr)) continue;
      final uv = h.uvIndex![i];
      if (uv == null) continue;
      maxUv = maxUv == null ? uv : math.max(maxUv, uv);
    }
    if (maxUv == null) return null;

    double? currentUv = _uvForLocalWallClockHour(h, today, weatherData?.current);
    if (currentUv == null) {
      // Fallback na najblizsiu hodinovu hodnotu pre lokalny cas.
      int? nearestIdx;
      int nearestDiffMin = 1 << 30;
      for (int i = 0; i < len; i++) {
        if (!h.time[i].startsWith(dateStr)) continue;
        final uv = h.uvIndex![i];
        if (uv == null) continue;
        final dt = DateTime.tryParse(h.time[i]);
        if (dt == null) continue;
        final diff = dt.difference(today).inMinutes.abs();
        if (diff < nearestDiffMin) {
          nearestDiffMin = diff;
          nearestIdx = i;
        }
      }
      if (nearestIdx != null) {
        currentUv = h.uvIndex![nearestIdx];
      }
    }

    // Kartu ukazujeme iba vtedy, ked je aktualny UV v rizikovom rozsahu 3-12.
    if (currentUv == null || currentUv < 3.0 || currentUv > 12.0) return null;

    // "Nebezpecne" obdobie berieme od UV >= 3 (stredny a vyssie).
    const double rangeThreshold = 3.0;
    String? startIso;
    String? endIso;
    for (int i = 0; i < len; i++) {
      if (!h.time[i].startsWith(dateStr)) continue;
      final uv = h.uvIndex![i];
      if (uv == null || uv < rangeThreshold) continue;
      startIso ??= h.time[i];
      endIso = h.time[i];
    }
    if (startIso == null || endIso == null) return null;

    final now = _getCurrentLocationTime();
    final startTime = DateTime.tryParse(startIso);
    final endTime = DateTime.tryParse(endIso);
    if (startTime == null || endTime == null) return null;
    // Hide the warning once the relevant UV window has passed.
    if (now.isAfter(endTime.add(const Duration(hours: 1)))) return null;

    String hourLabel(String? iso) {
      if (iso == null || iso.length < 13) return '--:--';
      return '${iso.substring(11, 13)}:00';
    }

    final uvLevelValue = currentUv.round();
    final level = uvLevelValue >= 11
        ? 'Extrémny'
        : (uvLevelValue >= 8
            ? 'Veľmi vysoký'
            : (uvLevelValue >= 6
                ? 'Vysoký'
                : (uvLevelValue >= 3 ? 'Stredný' : 'Nízky')));
    return {
      'title': '$level UV Index ($uvLevelValue)',
      'subtitle': 'od ${hourLabel(startIso)} do ${hourLabel(endIso)} · max ${maxUv.round()}',
    };
  }

  Widget _buildUvWarningCard(Map<String, String> warning, {bool compact = false}) {
    if (compact) {
      return _heroGlassCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.wb_sunny_outlined,
                color: Color(0xFFFFD600),
                size: _kHomeQuickActionIconSize,
              ),
              const SizedBox(height: 8),
              Text(
                warning['title'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                warning['subtitle'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.94),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _heroGlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _homeInsightLeadingSlot(
              const Icon(
                Icons.wb_sunny_outlined,
                color: Color(0xFFFFD600),
                size: _kHomeQuickActionIconSize,
              ),
            ),
            const SizedBox(width: _kHomeInsightLeadingGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    warning['title'] ?? '',
                    style: _kHomeInsightTitleStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    warning['subtitle'] ?? '',
                    style: _kHomeInsightSubtitleStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radarGlassBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: kAppCardNavyElevated.withValues(alpha: 0.92),
        border: Border.all(color: kAppCardNavyBorder),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildHomeInsightTilesRow({Map<String, String>? uvWarning}) {
    if (uvWarning == null) return null;
    return _buildUvWarningCard(uvWarning, compact: false);
  }

  Widget _buildHomeQuickActions() {
    final showVystrahy = _supportsVystrahyForCity(currentCity);
    final chartLabel = weatherData?.daily != null && weatherData!.daily!.time.isNotEmpty
        ? 'Graf 16 dní'
        : 'Graf';

    Widget item({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: _kHomeQuickActionIconSize),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];

    if (showVystrahy) {
      children.add(
        item(
          icon: Icons.warning_amber_rounded,
          label: 'Výstrahy',
          onTap: () async {
            final city = currentCity;
            if (city == null) return;
            final preloader = VystrahyWebViewPreloader.instance;
            preloader.updateUserLocation(city.lat, city.lon);
            preloader.warmup();
            // Nečakať 12 s na home — stránka sa otvorí hneď (mapa už warm / spinner na stránke).
            preloader.markAttached();
            if (!context.mounted) return;
            await Navigator.push(
              context,
              PageRouteBuilder<void>(
                transitionDuration: const Duration(milliseconds: 200),
                reverseTransitionDuration: const Duration(milliseconds: 160),
                pageBuilder: (_, __, ___) => MeteoVystrahyPage(city: city),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                    child: child,
                  );
                },
              ),
            );
          },
        ),
      );
    }

    children.addAll([
      item(
        icon: Icons.grass_rounded,
        label: 'Peľ',
        onTap: () {
          final city = currentCity;
          if (city == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PollenForecastPage(
                city: city,
                aqiData: airQualityData ?? AirQualityData(),
              ),
            ),
          );
        },
      ),
      item(
        icon: Icons.bar_chart_rounded,
        label: chartLabel,
        onTap: _openWeatherChart,
      ),
    ]);

    return _heroGlassCard(
      withShadow: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refreshLightningForCity(GeoCity city) async {
    try {
      final near = await lightningDetectedNear(city.lat, city.lon);
      if (!mounted) return;
      if (near != _lightningNearby) {
        setState(() => _lightningNearby = near);
        _invalidateDisplayCaches();
      }
    } catch (e) {
      debugPrint('_refreshLightningForCity: $e');
    }
  }

  Future<RadarNowcastContext> _fetchRadarNowcastForCity(GeoCity city) async {
    // Priamo RainViewer/Helkor API — WebView mapu nečakáme (iba by oneskorilo ikony).
    return fetchRadarNowcastContextForCity(city);
  }

  bool _radarContextUiNeedsUpdate(RadarNowcastContext next) {
    final prev = _radarNowcastContext;
    if (prev.eligible != next.eligible) return true;
    if (prev.precipNow != next.precipNow) return true;
    if (prev.incomingPrecip != next.incomingPrecip) return true;
    if (prev.dryAtPin != next.dryAtPin) return true;
    // Profesionálny pin snapshot — oči na stopkách, hneď reagovať.
    final prevSnap = prev.pinForecast;
    final nextSnap = next.pinForecast;
    if (prevSnap.wetAtPinNow != nextSnap.wetAtPinNow) return true;
    if (prevSnap.approaching != nextSnap.approaching) return true;
    if (prevSnap.clearEcmwfNearTerm != nextSnap.clearEcmwfNearTerm) {
      return true;
    }
    if (prevSnap.etaMinutes != nextSnap.etaMinutes) return true;
    if (prevSnap.endMinutes != nextSnap.endMinutes) return true;
    if ((prevSnap.approachChancePercent - nextSnap.approachChancePercent)
            .abs() >=
        5) {
      return true;
    }
    if (!_sameIntList(prevSnap.wetHourStartsMs, nextSnap.wetHourStartsMs)) {
      return true;
    }
    if ((prevSnap.uiDbz - nextSnap.uiDbz).abs() >= 2) return true;
    if (prevSnap.towardPin != nextSnap.towardPin) return true;
    final prevDist = prevSnap.distanceKmEstimate;
    final nextDist = nextSnap.distanceKmEstimate;
    if (prevDist != null &&
        nextDist != null &&
        (prevDist - nextDist).abs() >= 3) {
      return true;
    }
    if (_lastRadarContextUiApplyAt == null) return true;
    final elapsed = DateTime.now().difference(_lastRadarContextUiApplyAt!);
    final active = next.eligible &&
        (nextSnap.wetAtPinNow ||
            nextSnap.approaching ||
            nextSnap.approachChancePercent >= 25 ||
            nextSnap.wetHourStartsMs.isNotEmpty);
    // Pri aktívnom počasí / pohybe buniek — obnov UI každých ~20 s.
    if (active) {
      return elapsed >= _kRadarForecastActiveApplyInterval;
    }
    return elapsed >= _kRadarForecastIdleApplyInterval;
  }

  bool _sameIntList(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _refreshRadarNowcastForCity(GeoCity city) async {
    if (!radarNowcastActiveForCity(city)) {
      if (!mounted) return;
      if (_radarNowcastContext.eligible) {
        setState(() {
          _radarNowcastContext = RadarNowcastContext.inactive;
        });
        _invalidateDisplayCaches();
      }
      return;
    }
    final int fetchSerial = ++_radarFetchSerial;
    try {
      final ctx = await _fetchRadarNowcastForCity(city);
      if (!mounted || fetchSerial != _radarFetchSerial) return;
      final liveCity = currentCity;
      if (liveCity == null ||
          (liveCity.lat - city.lat).abs() > 0.0002 ||
          (liveCity.lon - city.lon).abs() > 0.0002) {
        return;
      }
      if (!_radarContextUiNeedsUpdate(ctx)) return;
      setState(() {
        _radarNowcastContext = ctx;
        _lastRadarContextUiApplyAt = DateTime.now();
      });
      _invalidateDisplayCaches();
    } catch (e) {
      debugPrint('_refreshRadarNowcastForCity: $e');
    }
  }

  Future<void> _maybeRefreshNearbyWebcams() async {
    final city = currentCity;
    if (city == null || _isLoadingWebcams) return;
    final cc = city.countryCode.toUpperCase();
    if (cc != 'SK' && cc != 'CZ') return;
    final requiredGap = cc == 'CZ' ? const Duration(minutes: 5) : const Duration(minutes: 2);
    final now = DateTime.now();
    if (_lastWebcamRefreshAt != null && now.difference(_lastWebcamRefreshAt!) < requiredGap) return;
    _lastWebcamRefreshAt = now;
    _webcamsLoadedForCityKey = null;
    _webcamsRequestedForCityKey = null;
    _webcamPreviewCacheBuster = now.millisecondsSinceEpoch;
    await _loadNearbyWebcams(city);
  }

  Future<void> _refreshData() async {
    if (currentCity == null) return;
    final GeoCity citySnap = currentCity!;
    final int mySerial = ++_weatherFetchSerial;
    try {
      final weatherFuture = _fetchForecastWeatherData(
        citySnap.lat,
        citySnap.lon,
        apiTimezone: citySnap.timezone,
      );
      final aqiFuture = _fetchAirQualityData(citySnap.lat, citySnap.lon, forceRefresh: false);
      final int radarSerial = ++_radarFetchSerial;
      _kickRadarNowcastEarly(
        city: citySnap,
        mySerial: mySerial,
        radarSerial: radarSerial,
      );

      final data = await weatherFuture;

      AirQualityData? aqiData;
      try {
        aqiData = await aqiFuture;
      } catch (e) {
        debugPrint('AQI fetch failed: $e');
      }

      if (!mounted || mySerial != _weatherFetchSerial) return;
      if (currentCity == null ||
          (currentCity!.lat - citySnap.lat).abs() > 0.0002 ||
          (currentCity!.lon - citySnap.lon).abs() > 0.0002) {
        return;
      }
      unawaited(_observeDailyPrecipLatchForCity(citySnap, data));
      setState(() {
        weatherData = data;
        airQualityData = aqiData;
      });
      _invalidateDisplayCaches();
      _scheduleSecondaryWeatherSignals(
        city: citySnap,
        mySerial: mySerial,
        radarSerial: radarSerial,
      );
      unawaited(_syncWeatherFetchFollowUps(citySnap, data));
    // ignore: empty_catches
    } catch (e) {}
  }

  void _updateOneSignalTags(GeoCity city) {
    OneSignal.User.addTags({
      "city": city.name,
      "country": city.countryCode,
      "last_updated": DateTime.now().toIso8601String(),
    });
  }

  Future<void> _observeDailyPrecipLatchForCity(GeoCity city, WeatherData data) =>
      observeDailyPrecipDisplayLatchForWeatherData(
        lat: city.lat,
        lon: city.lon,
        data: data,
      );

  /// Zhoda s UI: berieme vyššiu z dennej max. rýchlosti a dennej max. nárazov — push predtým ukazoval len stály vietor (~11), zatiaľ čo nárazy môžu byť ~25.
  double _dailySummaryWindPeakKmh(WeatherData data) {
    final daily = data.daily;
    final cur = data.current?.windSpeed ?? 0.0;
    if (daily == null ||
        daily.time.isEmpty ||
        ((daily.windSpeedMax == null || daily.windSpeedMax!.isEmpty) &&
            (daily.windGustsMax == null || daily.windGustsMax!.isEmpty))) {
      return cur;
    }
    final sustained =
        daily.windSpeedMax != null && daily.windSpeedMax!.isNotEmpty ? (daily.windSpeedMax!.first ?? 0.0) : 0.0;
    final gusts =
        daily.windGustsMax != null && daily.windGustsMax!.isNotEmpty ? (daily.windGustsMax!.first ?? 0.0) : 0.0;
    final peak = math.max(math.max(sustained, gusts), cur);
    return peak > 0 ? peak : cur;
  }

  String _buildDailySummaryBody(GeoCity city, WeatherData data) {
    final daily = data.daily;
    final current = data.current;
    const snowCodes = {56, 57, 66, 67, 71, 73, 75, 77, 85, 86};
    final int summarySkyCode = _dailyMainIconSkyTextCode(data, 0, lightningNearby: _lightningNearby);
    final todayDesc =
        weatherDescriptionSk(summarySkyCode).toLowerCase();
    final maxTemp = (daily?.tempMax != null && daily!.tempMax!.isNotEmpty) ? daily.tempMax!.first : current?.temperature;
    final precip = (daily?.precipSum != null && daily!.precipSum!.isNotEmpty) ? (daily.precipSum!.first ?? 0.0) : 0.0;
    final snowfall = (daily?.snowfallSum != null && daily!.snowfallSum!.isNotEmpty) ? (daily.snowfallSum!.first ?? 0.0) : 0.0;
    final int todayCode =
        (daily?.weatherCode != null && daily!.weatherCode!.isNotEmpty) ? (daily.weatherCode!.first ?? summarySkyCode) : summarySkyCode;
    final windPeakKmh = _dailySummaryWindPeakKmh(data);
    final DateTime nowLocal = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));

    final maxTempText = maxTemp != null ? '${maxTemp.round()} °C' : '-- °C';
    final windText = _currentWindUnit.format(windPeakKmh);
    final rainSegment = snowCodes.contains(todayCode) && snowfall >= 0.2
        ? 'Očakáva sa sneženie, napadnúť môže približne ${snowfall.toStringAsFixed(1)} cm.'
        : precip > 0.2
            ? 'Očakávajú sa zrážky, ich úhrn môže dosiahnuť ${precip.toStringAsFixed(1)} mm.'
            : 'Zrážky sa neočakávajú.';

    final sky = _pushSummarySkyPhrase(todayDesc);
    final cloudSegment = _phraseIsFairSummarySky(sky) && _hourlyHasLaterOvercastSameDay(data, nowLocal)
        ? 'Popoludní môže pribudnúť oblačnosť.'
        : 'Oblačnosť sa počas dňa výrazne nezmení.';
    return '${city.name}: Dnes bude $sky. Denné maximum bude $maxTempText. $rainSegment Nárazy vetra môžu dosiahnuť $windText. $cloudSegment';
  }

  String _buildEveningSummaryBody(GeoCity city, WeatherData data) {
    final daily = data.daily;
    final hourly = data.hourly;
    const snowCodes = {56, 57, 66, 67, 71, 73, 75, 77, 85, 86};
    final DateTime nowLocal = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));
    final DateTime tonightStart = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 18);
    final DateTime tonightEnd = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 23, 59, 59);

    int? nextCode;
    int? eveningSlotIndex;
    int maxPrecipProb = 0;
    if (hourly != null && hourly.time.isNotEmpty) {
      for (int i = 0; i < hourly.time.length; i++) {
        final t = DateTime.tryParse(hourly.time[i]);
        if (t == null) continue;
        if (t.isBefore(tonightStart) || t.isAfter(tonightEnd)) continue;
        eveningSlotIndex ??= i;
        nextCode ??= hourly.weatherCode?[i];
        final p = (hourly.precipitationProbability != null && i < hourly.precipitationProbability!.length)
            ? (hourly.precipitationProbability![i] ?? 0)
            : 0;
        if (p > maxPrecipProb) maxPrecipProb = p;
      }
    }
    nextCode ??= daily?.weatherCode?.isNotEmpty == true ? daily!.weatherCode!.first : data.current?.weatherCode;
    int descCode = nextCode ?? 0;
    if (eveningSlotIndex != null &&
        hourly?.weatherCode != null &&
        eveningSlotIndex < hourly!.weatherCode!.length) {
      final i = eveningSlotIndex;
      final raw = hourly.weatherCode![i] ?? 0;
      final p = (hourly.precipitationProbability != null && i < hourly.precipitationProbability!.length)
          ? (hourly.precipitationProbability![i] ?? 0)
          : 0;
      final double? cc =
          hourly.cloudCover != null && i < hourly.cloudCover!.length ? hourly.cloudCover![i] : null;
      final double mm =
          hourly.precipitation != null && i < hourly.precipitation!.length ? (hourly.precipitation![i] ?? 0.0) : 0.0;
      descCode = _weatherIconCodeWithPrecipThreshold(
        raw,
        p,
        cloudCoverPercent: cc,
        hourlyPrecipitationMm: mm,
        snowfallCm: 0.0,
      );
    }
    final descRaw = weatherDescriptionSk(descCode).toLowerCase();
    final desc = _pushSummarySkyPhrase(descRaw);

    double? minTonight;
    double? maxTomorrow;
    if (daily != null && daily.time.isNotEmpty) {
      final todayKey = '${nowLocal.year.toString().padLeft(4, '0')}-${nowLocal.month.toString().padLeft(2, '0')}-${nowLocal.day.toString().padLeft(2, '0')}';
      final tomorrow = nowLocal.add(const Duration(days: 1));
      final tomorrowKey = '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      for (int i = 0; i < daily.time.length; i++) {
        if (daily.time[i] == todayKey) minTonight = daily.tempMin != null && i < daily.tempMin!.length ? daily.tempMin![i] : minTonight;
        if (daily.time[i] == tomorrowKey) maxTomorrow = daily.tempMax != null && i < daily.tempMax!.length ? daily.tempMax![i] : maxTomorrow;
      }
    }

    final minTxt = minTonight != null ? '${minTonight.round()} °C' : '-- °C';
    final maxTomorrowTxt = maxTomorrow != null ? '${maxTomorrow.round()} °C' : '-- °C';
    final bool snowTonightLikely = snowCodes.contains(descCode);
    final precipSegment = maxPrecipProb >= 50
        ? snowTonightLikely
            ? 'V noci sa očakáva sneženie s pravdepodobnosťou ${_roundPrecipProbabilityForDisplay(maxPrecipProb)} %.'
            : 'V noci sa očakávajú zrážky s pravdepodobnosťou ${_roundPrecipProbabilityForDisplay(maxPrecipProb)} %.'
        : 'V noci sa zrážky neočakávajú.';

    final cloudSegment = _phraseIsFairSummarySky(desc) &&
            _eveningSummaryDawnCloudBuildsVersusBaseline(data, nowLocal, descCode)
        ? ' Nadránom môže pribudnúť oblačnosť.'
        : '';
    return '${city.name}: Večer a v noci bude $desc. Nočné minimum bude $minTxt. $precipSegment Zajtrajšie maximum bude $maxTomorrowTxt.$cloudSegment';
  }

  Future<void> _syncDailySummaryWithLatestData(GeoCity city, WeatherData data) async {
    final enabled = await SettingsManager.getAlertTypeEnabled(kAlertDailySummaryEnabledKey);
    if (!enabled) return;
    final body = _buildDailySummaryBody(city, data);
    final dailyTime = await SettingsManager.getAlertDailySummaryTime();
    await LocalTestPushService.scheduleDailySummaryWithBody(
      enabled: true,
      time: dailyTime,
      body: body,
    );
    await SettingsManager.setAlertDailySummaryLastPushBody(body);
  }

  Future<void> _syncEveningSummaryWithLatestData(GeoCity city, WeatherData data) async {
    final enabled = await SettingsManager.getAlertTypeEnabled(kAlertEveningSummaryEnabledKey);
    if (!enabled) {
      await LocalTestPushService.cancelEveningSummary();
      await SettingsManager.setAlertEveningSummaryNextAt(null);
      await SettingsManager.setAlertEveningSummaryLastPushBody(null);
      return;
    }
    final body = _buildEveningSummaryBody(city, data);
    final eveningTime = await SettingsManager.getAlertEveningSummaryTime();
    await LocalTestPushService.scheduleEveningSummaryWithBody(
      enabled: true,
      time: eveningTime,
      body: body,
    );
    await SettingsManager.setAlertEveningSummaryLastPushBody(body);
  }

  Future<void> _syncHighUvLeadAlert(WeatherData data) async {
    final enabled = await SettingsManager.getAlertTypeEnabled(kAlertHighUvEnabledKey);
    if (!enabled) {
      await LocalTestPushService.cancelHighUvLeadAlert();
      await SettingsManager.setAlertHighUvLastPlannedSlot(null);
      return;
    }

    final hourly = data.hourly;
    if (hourly == null || hourly.time.isEmpty || hourly.uvIndex == null || hourly.uvIndex!.isEmpty) {
      await LocalTestPushService.cancelHighUvLeadAlert();
      await SettingsManager.setAlertHighUvLastPlannedSlot(null);
      return;
    }

    final nowLocal = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));
    final int len = math.min(hourly.time.length, hourly.uvIndex!.length);
    DateTime? firstEventAt;
    double? firstUv;
    for (int i = 0; i < len; i++) {
      final t = DateTime.tryParse(hourly.time[i]);
      final uv = hourly.uvIndex![i];
      if (t == null || uv == null) continue;
      if (!t.isAfter(nowLocal)) continue;
      if (uv > 4.0) {
        firstEventAt = t;
        firstUv = uv;
        break;
      }
    }

    if (firstEventAt == null || firstUv == null) {
      await LocalTestPushService.cancelHighUvLeadAlert();
      await SettingsManager.setAlertHighUvLastPlannedSlot(null);
      return;
    }

    final currentUv = data.current?.uvIndex;
    final notifyUv =
        currentUv != null ? math.max(firstUv, currentUv) : firstUv;

    final slotToken = _leadAlertPlannedSlotKey(firstEventAt, ['uv', notifyUv.round()]);
    final lastPlannedSlot = await SettingsManager.getAlertHighUvLastPlannedSlot();
    if (lastPlannedSlot == slotToken) {
      return;
    }

    await LocalTestPushService.scheduleHighUvLeadAlert(
      eventAt: firstEventAt,
      uvIndex: notifyUv,
    );
    await SettingsManager.setAlertHighUvLastPlannedSlot(slotToken);
  }

  Future<void> _syncStrongWindLeadAlert(WeatherData data) async {
    final enabled = await SettingsManager.getAlertTypeEnabled(kAlertStrongWindEnabledKey);
    if (!enabled) {
      await LocalTestPushService.cancelStrongWindLeadAlert();
      await SettingsManager.setAlertStrongWindLastPlannedSlot(null);
      return;
    }

    final hourly = data.hourly;
    if (hourly == null || hourly.time.isEmpty || hourly.windGusts == null || hourly.windGusts!.isEmpty) {
      await LocalTestPushService.cancelStrongWindLeadAlert();
      await SettingsManager.setAlertStrongWindLastPlannedSlot(null);
      return;
    }

    final nowLocal = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));
    final int len = math.min(hourly.time.length, hourly.windGusts!.length);
    DateTime? firstEventAt;
    double? firstGust;
    for (int i = 0; i < len; i++) {
      final t = DateTime.tryParse(hourly.time[i]);
      final gust = hourly.windGusts![i];
      if (t == null || gust == null) continue;
      if (!t.isAfter(nowLocal)) continue;
      if (gust >= 50.0) {
        firstEventAt = t;
        firstGust = gust;
        break;
      }
    }

    if (firstEventAt == null || firstGust == null) {
      await LocalTestPushService.cancelStrongWindLeadAlert();
      await SettingsManager.setAlertStrongWindLastPlannedSlot(null);
      return;
    }

    // Text upozornenia má sedieť na najbližšiu budúcu veternú udalosť,
    // nie na staršie nárazy z minulých hodín.
    var notifyGust = firstGust;
    final clusterEnd = firstEventAt.add(const Duration(hours: 2));
    for (int i = 0; i < len; i++) {
      final t = DateTime.tryParse(hourly.time[i]);
      final gust = hourly.windGusts![i];
      if (t == null || gust == null) continue;
      if (t.isBefore(firstEventAt) || t.isAfter(clusterEnd)) continue;
      notifyGust = math.max(notifyGust, gust);
    }

    final slotToken = _leadAlertPlannedSlotKey(firstEventAt, ['wind', notifyGust.round()]);
    final lastPlannedSlot = await SettingsManager.getAlertStrongWindLastPlannedSlot();
    if (lastPlannedSlot == slotToken) return;

    await LocalTestPushService.scheduleStrongWindLeadAlert(
      eventAt: firstEventAt,
      gustKmh: notifyGust,
    );
    await SettingsManager.setAlertStrongWindLastPlannedSlot(slotToken);
  }

  Future<void> _syncHeavyRainLeadAlert(WeatherData data) async {
    final enabled = await SettingsManager.getAlertTypeEnabled(kAlertHeavyRainEnabledKey);
    if (!enabled) {
      await LocalTestPushService.cancelHeavyRainLeadAlert();
      await SettingsManager.setAlertHeavyRainLastPlannedSlot(null);
      return;
    }

    final daily = data.daily;
    if (daily == null || daily.time.isEmpty || daily.precipSum == null || daily.precipSum!.isEmpty) {
      await LocalTestPushService.cancelHeavyRainLeadAlert();
      await SettingsManager.setAlertHeavyRainLastPlannedSlot(null);
      return;
    }

    final nowLocal = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));
    int targetDayIndex = -1;
    double targetMm = 0.0;
    for (int i = 0; i < daily.time.length && i < daily.precipSum!.length; i++) {
      final dayDate = DateTime.tryParse(daily.time[i]);
      final mm = daily.precipSum![i] ?? 0.0;
      if (dayDate == null) continue;
      if (DateTime(dayDate.year, dayDate.month, dayDate.day)
          .isBefore(DateTime(nowLocal.year, nowLocal.month, nowLocal.day))) {
        continue;
      }
      final code = (daily.weatherCode != null && i < daily.weatherCode!.length) ? (daily.weatherCode![i] ?? 0) : 0;
      if (mm >= kAlertHeavyRainDailyMmThreshold &&
          {61, 63, 65, 80, 81, 82, 95, 96, 99}.contains(code)) {
        targetDayIndex = i;
        targetMm = mm;
        break;
      }
    }

    if (targetDayIndex < 0) {
      await LocalTestPushService.cancelHeavyRainLeadAlert();
      await SettingsManager.setAlertHeavyRainLastPlannedSlot(null);
      return;
    }

    DateTime? firstRainAt;
    final hourly = data.hourly;
    if (hourly != null && hourly.time.isNotEmpty && hourly.precipitation != null) {
      final int len = math.min(hourly.time.length, hourly.precipitation!.length);
      final targetDate = daily.time[targetDayIndex];
      for (int i = 0; i < len; i++) {
        final t = DateTime.tryParse(hourly.time[i]);
        if (t == null || !hourly.time[i].startsWith(targetDate)) continue;
        final hourlyMm = hourly.precipitation![i] ?? 0.0;
        if (t.isAfter(nowLocal) && hourlyMm >= 0.8) {
          firstRainAt = t;
          break;
        }
      }
    }
    firstRainAt ??= DateTime.parse('${daily.time[targetDayIndex]}T09:00');
    final dayKey = daily.time[targetDayIndex];
    final morningLeadAt = DateTime.parse('${dayKey}T08:00');
    // Pri výdatnom daždi upozorniť v deň javu rozumne ráno,
    // nie až tesne pred prvou intenzívnou hodinou.
    DateTime plannedRainEventAt = firstRainAt;
    if (plannedRainEventAt.subtract(kLeadWeatherAlertBeforeEvent).isAfter(morningLeadAt)) {
      plannedRainEventAt = morningLeadAt.add(kLeadWeatherAlertBeforeEvent);
    }

    final slotToken = _leadAlertPlannedSlotKey(plannedRainEventAt, ['rain', targetMm.toStringAsFixed(1)]);
    final lastPlannedSlot = await SettingsManager.getAlertHeavyRainLastPlannedSlot();
    if (lastPlannedSlot == slotToken) return;

    await LocalTestPushService.scheduleHeavyRainLeadAlert(
      eventAt: plannedRainEventAt,
      precipitationMm: targetMm,
    );
    await SettingsManager.setAlertHeavyRainLastPlannedSlot(slotToken);
  }

  Future<void> _syncHeavySnowLeadAlert(WeatherData data) async {
    final enabled = await SettingsManager.getAlertTypeEnabled(kAlertHeavySnowEnabledKey);
    if (!enabled) {
      await LocalTestPushService.cancelHeavySnowLeadAlert();
      await SettingsManager.setAlertHeavySnowLastPlannedSlot(null);
      return;
    }

    final daily = data.daily;
    if (daily == null ||
        daily.time.isEmpty ||
        daily.snowfallSum == null ||
        daily.snowfallSum!.isEmpty ||
        daily.weatherCode == null) {
      await LocalTestPushService.cancelHeavySnowLeadAlert();
      await SettingsManager.setAlertHeavySnowLastPlannedSlot(null);
      return;
    }

    final snowCodes = {56, 57, 66, 67, 71, 73, 75, 77, 85, 86};
    final nowLocal = DateTime.now().toUtc().add(Duration(seconds: data.utcOffsetSeconds ?? 0));
    int targetDayIndex = -1;
    double targetCm = 0.0;
    for (int i = 0;
        i < daily.time.length && i < daily.snowfallSum!.length && i < daily.weatherCode!.length;
        i++) {
      final dayDate = DateTime.tryParse(daily.time[i]);
      final snowCm = daily.snowfallSum![i] ?? 0.0;
      final code = daily.weatherCode![i] ?? 0;
      if (dayDate == null) continue;
      if (DateTime(dayDate.year, dayDate.month, dayDate.day)
          .isBefore(DateTime(nowLocal.year, nowLocal.month, nowLocal.day))) {
        continue;
      }
      if (snowCm >= kAlertHeavySnowDailyCmThreshold && snowCodes.contains(code)) {
        targetDayIndex = i;
        targetCm = snowCm;
        break;
      }
    }

    if (targetDayIndex < 0) {
      await LocalTestPushService.cancelHeavySnowLeadAlert();
      await SettingsManager.setAlertHeavySnowLastPlannedSlot(null);
      return;
    }

    DateTime? firstSnowAt;
    final hourly = data.hourly;
    if (hourly != null && hourly.time.isNotEmpty && hourly.weatherCode != null) {
      final int len = hourly.weatherCode!.length;
      final targetDate = daily.time[targetDayIndex];
      for (int i = 0; i < len && i < hourly.time.length; i++) {
        final t = DateTime.tryParse(hourly.time[i]);
        final code = hourly.weatherCode![i] ?? 0;
        if (t == null || !hourly.time[i].startsWith(targetDate)) continue;
        if (t.isAfter(nowLocal) && snowCodes.contains(code)) {
          firstSnowAt = t;
          break;
        }
      }
    }
    firstSnowAt ??= DateTime.parse('${daily.time[targetDayIndex]}T09:00');
    final dayKey = daily.time[targetDayIndex];
    final morningLeadAt = DateTime.parse('${dayKey}T08:00');
    // Pri výdatnom snežení upozorniť v deň javu rozumne ráno,
    // nie až tesne pred prvou intenzívnou hodinou.
    DateTime plannedSnowEventAt = firstSnowAt;
    if (plannedSnowEventAt.subtract(kLeadWeatherAlertBeforeEvent).isAfter(morningLeadAt)) {
      plannedSnowEventAt = morningLeadAt.add(kLeadWeatherAlertBeforeEvent);
    }

    final slotToken = _leadAlertPlannedSlotKey(plannedSnowEventAt, ['snow', targetCm.round()]);
    final lastPlannedSlot = await SettingsManager.getAlertHeavySnowLastPlannedSlot();
    if (lastPlannedSlot == slotToken) return;

    await LocalTestPushService.scheduleHeavySnowLeadAlert(
      eventAt: plannedSnowEventAt,
      snowfallCm: targetCm,
    );
    await SettingsManager.setAlertHeavySnowLastPlannedSlot(slotToken);
  }

  Future<void> _syncAdditionalLeadAlerts(WeatherData data) async {
    await _syncStrongWindLeadAlert(data);
    await _syncHeavyRainLeadAlert(data);
    await _syncHeavySnowLeadAlert(data);
  }

  Future<void> _syncAllLeadAlerts(WeatherData data) async {
    await _syncHighUvLeadAlert(data);
    await _syncAdditionalLeadAlerts(data);
  }

  DateTime _getCurrentLocationTime() {
    if (weatherData?.utcOffsetSeconds != null) {
      final utcNow = DateTime.now().toUtc();
      final loc = utcNow.add(Duration(seconds: weatherData!.utcOffsetSeconds!));
      return DateTime(loc.year, loc.month, loc.day, loc.hour, loc.minute, loc.second);
    }
    return DateTime.now();
  }

  GeoCity _cityOrDefault(GeoCity? city) => city ?? kDefaultFallbackCity;

  Future<String?> _cachedWeatherJsonForCity(double lat, double lon) async {
    return CacheManager.getWeather(
      lat,
      lon,
      forecastWeatherCacheKey(_forecastModel, days: kForecastDays),
      ignoreExpiry: true,
    );
  }

  Future<bool> _canUseDeviceLocation() async {
    if (!_myLocationEnabled) return false;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<void> _primeWeatherFromCacheIfAny(GeoCity city) async {
    try {
      final cachedWeather = await _cachedWeatherJsonForCity(city.lat, city.lon);
      final cachedData = CacheManager.decodeForecastWeatherBody(cachedWeather);
      if (cachedData == null || !_forecastHasCoreFields(cachedData)) return;
      WeatherData data;
      try {
        data = await _augmentWeatherDataWithUvFallback(
          cachedData,
          city.lat,
          city.lon,
          _normalizeApiTimezone(city.timezone),
        );
      } catch (_) {
        data = cachedData;
      }
      if (!mounted) return;
      unawaited(_observeDailyPrecipLatchForCity(city, data));
      setState(() {
        weatherData = data;
        isLoading = false;
        hasError = false;
      });
      _invalidateDisplayCaches();
      unawaited(_refreshLightningForCity(city));
      unawaited(_refreshRadarNowcastForCity(city));
      unawaited(_primeWeatherFromCacheFollowUps(city, data));
    } catch (e) {
      debugPrint('_primeWeatherFromCacheIfAny: $e');
    }
  }

  Future<void> _syncWeatherFetchFollowUps(GeoCity city, WeatherData data) async {
    try {
      await _syncDailySummaryWithLatestData(city, data);
      await _syncEveningSummaryWithLatestData(city, data);
      await _syncAllLeadAlerts(data);
    } catch (e, st) {
      debugPrint('Post-weather sync failed: $e\n$st');
    }
    _scheduleWidgetUpdate();
    SettingsManager.saveLastLocation(city);
    _updateOneSignalTags(city);
    _fetchHistorical(city);
  }

  Future<void> _primeWeatherFromCacheFollowUps(GeoCity city, WeatherData data) async {
    if (data.current != null) {
      try {
        final satCloud = await fetchSatelliteCloudCover(city.lat, city.lon);
        if (satCloud != null && mounted) {
          final current = data.current!;
          final enriched = data.copyWith(
            current: CurrentWeather(
              temperature: current.temperature,
              isDay: current.isDay,
              weatherCode: current.weatherCode,
              relativeHumidity: current.relativeHumidity,
              surfacePressure: current.surfacePressure,
              windSpeed: current.windSpeed,
              windDirection: current.windDirection,
              precipitation: current.precipitation,
              time: current.time,
              uvIndex: current.uvIndex,
              cloudCover: current.cloudCover,
              apparentTemperature: current.apparentTemperature,
              satelliteCloudCover: satCloud,
            ),
          );
          setState(() => weatherData = enriched);
          _invalidateDisplayCaches();
        }
      } catch (_) {}
    }
    try {
      await _syncDailySummaryWithLatestData(city, data);
      await _syncEveningSummaryWithLatestData(city, data);
      await _syncAllLeadAlerts(data);
      _scheduleWidgetUpdate();
      final cachedAqi =
          await CacheManager.getAirQuality(city.lat, city.lon, ignoreExpiry: true);
      if (cachedAqi != null && mounted) {
        setState(() => airQualityData = AirQualityData.fromJson(json.decode(cachedAqi)));
      }
    } catch (e) {
      debugPrint('_primeWeatherFromCacheFollowUps: $e');
    }
  }

  Future<void> _initFromHomeOrLocation() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      hasError = false;
      _isOffline = false;
      _expandedStates = [];
    });

    try {
      final lastLocation = await SettingsManager.getLastLocation();
      final GeoCity seedCity = _cityOrDefault(lastLocation);

      currentCity = seedCity;
      _deferRadarSetup(seedCity);
      await _primeWeatherFromCacheIfAny(seedCity);

      if (await _canUseDeviceLocation()) {
        await _resolveCurrentLocation(lastLocation ?? seedCity);
      } else {
        await fetchWeatherByCity(
          seedCity,
          forceRefresh: false,
          showLoading: weatherData == null,
        );
      }
    } catch (e) {
      debugPrint('_initFromHomeOrLocation: $e');
      if (!mounted) return;
      final fallback = _cityOrDefault(await SettingsManager.getLastLocation());
      try {
        await fetchWeatherByCity(
          fallback,
          forceRefresh: false,
          showLoading: weatherData == null,
        );
      } catch (_) {
        if (mounted) {
          setState(() {
            isLoading = false;
            hasError = weatherData == null;
            _isOffline = false;
          });
        }
      }
    }
  }


  /// Obmedzuje opakované dialógy pri kolísajúcom GPS / starších Androidoch.
  Future<bool?> _offerTurnOnLocationServicesDialog() async {
    final now = DateTime.now();
    if (_lastLocationServicesOfferAt != null &&
        now.difference(_lastLocationServicesOfferAt!) < const Duration(seconds: 60)) {
      return false;
    }
    if (!mounted) return false;
    _lastLocationServicesOfferAt = now;
    return showLocationAccuracyDialog(context);
  }

  /// Rovnaká logika ako pri štarte: systém nepýta oprávnenie opakovane pri každom obnovení.
  Future<LocationPermission> _ensureForegroundLocationPermission() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      final alreadyPrompted = await SettingsManager.getLocationPermissionPromptShown();
      if (!alreadyPrompted) {
        await SettingsManager.setLocationPermissionPromptShown(true);
        perm = await Geolocator.requestPermission();
      }
    }
    return perm;
  }

  Future<void> _fetchWeatherForResolvedCity(GeoCity city) async {
    if (currentCity?.lat != city.lat || currentCity?.lon != city.lon) {
      resetRadarTrackerStabilizer();
      _lastRadarContextUiApplyAt = null;
    }
    currentCity = city;
    await SettingsManager.saveLastLocation(city);
    await fetchWeatherByCity(
      city,
      forceRefresh: false,
      showLoading: weatherData == null,
    );
  }

  Future<void> _resolveCurrentLocation(GeoCity? fallbackCity) async {
    final GeoCity backupCity = _cityOrDefault(fallbackCity);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final turnOn = await _offerTurnOnLocationServicesDialog();
        if (turnOn == true) {
          await Geolocator.openLocationSettings();
        }
        await _fetchWeatherForResolvedCity(backupCity);
        return;
      }

      final LocationPermission perm = await _ensureForegroundLocationPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) {
        await _fetchWeatherForResolvedCity(backupCity);
        return;
      }

      Position? pos = await Geolocator.getLastKnownPosition()
          .timeout(const Duration(milliseconds: 300), onTimeout: () => null);
      pos ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)));

      final cityRaw = await reverseGeocode(pos.latitude, pos.longitude);
      if (cityRaw != null) {
        final city = _preferStickyCityIdentity(fallbackCity, cityRaw, pos.latitude, pos.longitude);
        currentCity = city;
        await SettingsManager.saveLastLocation(city);
        _updateOneSignalTags(city);
        await fetchWeatherByCity(
          city,
          forceRefresh: false,
          showLoading: weatherData == null,
        );
      } else {
        await _fetchWeatherForResolvedCity(backupCity);
      }
    } catch (e) {
      debugPrint('_resolveCurrentLocation: $e');
      await _fetchWeatherForResolvedCity(backupCity);
    }
  }

  Future<void> _fetchHistorical(GeoCity city) async {
    try {
      final now = DateTime.now();
      final past = DateTime(now.year - 1, now.month, now.day);
      final dateStr = "${past.year}-${past.month.toString().padLeft(2, '0')}-${past.day.toString().padLeft(2, '0')}";

      String tz = city.timezone;
      if (tz == 'GMT' || tz == 'UTC' || tz.isEmpty) {
        tz = 'auto';
      }

      final url = Uri.parse(
          '$kHistoricalApi?latitude=${city.lat}&longitude=${city.lon}&start_date=$dateStr&end_date=$dateStr&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=${Uri.encodeQueryComponent(tz)}');
      final r = await http.get(url).timeout(const Duration(seconds: 10));

      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        final daily = data['daily'];
        if (daily != null && daily['time'] != null && daily['time'].isNotEmpty) {
          if (mounted) {
            setState(() {
              historicalWeather = HistoricalWeather(
                maxTemp: (daily['temperature_2m_max'][0] as num?)?.toDouble(),
                minTemp: (daily['temperature_2m_min'][0] as num?)?.toDouble(),
                weatherCode: (daily['weather_code'][0] as num?)?.toInt(),
                dateStr: dateStr,
              );
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Historical fetch error: $e');
    }
  }

  Future<WeatherData?> _weatherDataFromStoredJson(
    String? cachedJson,
    double lat,
    double lon,
    String timezone,
  ) async {
    final cachedData = CacheManager.decodeForecastWeatherBody(cachedJson);
    if (cachedData == null || !_forecastHasCoreFields(cachedData)) {
      return null;
    }
    try {
      return await _augmentWeatherDataWithUvFallback(cachedData, lat, lon, timezone);
    } catch (_) {
      return cachedData;
    }
  }

  Future<WeatherData?> _tryForecastFromModelMap(
    Map<String, dynamic>? map,
    double lat,
    double lon,
    String timezone, {
    WeatherForecastModel cacheModel = WeatherForecastModel.bestMatch,
  }) async {
    if (map == null) return null;
    try {
      final data = WeatherData.fromJson(map);
      if (!_forecastHasCoreFields(data)) {
        final days = data.daily?.time.length ?? 0;
        debugPrint(
          'forecast parse: missing fields or short horizon ($days/$kForecastDays dní)',
        );
        return null;
      }
      WeatherData result;
      try {
        result = await _augmentWeatherDataWithUvFallback(data, lat, lon, timezone);
      } catch (_) {
        result = enrichWeatherDataCurrentFromHourly(data);
      }
      await CacheManager.saveWeather(
        lat,
        lon,
        forecastWeatherCacheKey(cacheModel, days: kForecastDays),
        CacheManager.encodeForecastWeatherBody(result),
      );
      return result;
    } catch (e, st) {
      debugPrint('forecast parse failed: $e\n$st');
      return null;
    }
  }

  Future<WeatherData> _fetchForecastWeatherData(
    double lat,
    double lon, {
    bool forceRefresh = false,
    String? apiTimezone,
    WeatherForecastModel? model,
  }) async {
    final GeoCity lookupCity = currentCity != null &&
            (currentCity!.lat - lat).abs() < 0.05 &&
            (currentCity!.lon - lon).abs() < 0.05
        ? currentCity!
        : GeoCity(
            name: '',
            country: '',
            countryCode: '',
            admin1: '',
            admin2: '',
            lat: lat,
            lon: lon,
          );
    final forecastModel =
        model ?? forecastModelForCity(lookupCity, _forecastModel);
    final timezone = _normalizeApiTimezone(apiTimezone ?? currentCity?.timezone ?? 'auto');
    const String apiTz = 'auto';
    final cacheModel = forecastModel;

    Future<WeatherData?> fromCache({required bool allowStale}) async {
      final cachedJson = await CacheManager.getWeather(
        lat,
        lon,
        forecastWeatherCacheKey(cacheModel, days: kForecastDays),
        ignoreExpiry: allowStale,
      );
      WeatherData? data = await _weatherDataFromStoredJson(cachedJson, lat, lon, timezone);
      if (data?.current != null) {
        try {
          final satCloud = await fetchSatelliteCloudCover(lat, lon);
          if (satCloud != null) {
            final current = data!.current!;
            data = data.copyWith(
              current: CurrentWeather(
                temperature: current.temperature,
                isDay: current.isDay,
                weatherCode: current.weatherCode,
                relativeHumidity: current.relativeHumidity,
                surfacePressure: current.surfacePressure,
                windSpeed: current.windSpeed,
                windDirection: current.windDirection,
                precipitation: current.precipitation,
                time: current.time,
                uvIndex: current.uvIndex,
                cloudCover: current.cloudCover,
                apparentTemperature: current.apparentTemperature,
                satelliteCloudCover: satCloud,
              ),
            );
          }
        } catch (_) {}
      }
      return data;
    }

    if (!forceRefresh) {
      final fresh = await fromCache(allowStale: false);
      if (fresh != null) return fresh;
    }

    Object? lastError;
    try {
      final map = await _downloadOpenMeteoForecast(
        lat,
        lon,
        apiTz,
        model: forecastModel,
        forceRefresh: forceRefresh,
      );
      final parsed = await _tryForecastFromModelMap(
        map,
        lat,
        lon,
        timezone,
        cacheModel: cacheModel,
      );
      if (parsed != null) {
        try {
          final satCloud = await fetchSatelliteCloudCover(lat, lon);
          if (satCloud != null && parsed.current != null) {
            final current = parsed.current!;
            return parsed.copyWith(
              current: CurrentWeather(
                temperature: current.temperature,
                isDay: current.isDay,
                weatherCode: current.weatherCode,
                relativeHumidity: current.relativeHumidity,
                surfacePressure: current.surfacePressure,
                windSpeed: current.windSpeed,
                windDirection: current.windDirection,
                precipitation: current.precipitation,
                time: current.time,
                uvIndex: current.uvIndex,
                cloudCover: current.cloudCover,
                apparentTemperature: current.apparentTemperature,
                satelliteCloudCover: satCloud,
              ),
            );
          }
        } catch (_) {}
        return parsed;
      }
    } catch (e) {
      lastError = e;
      debugPrint('Forecast fetch failed (${forecastModel.uiTitle}): $e');
    }

    final stale = await fromCache(allowStale: true);
    if (stale != null) return stale;

    if (lastError is Exception) throw lastError;
    throw Exception('Predpoveď sa nepodarilo načítať');
  }

  Future<AirQualityData> _fetchAirQualityData(double lat, double lon, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cachedJson = await CacheManager.getAirQuality(lat, lon);
      if (cachedJson != null) {
        return AirQualityData.fromJson(json.decode(cachedJson));
      }
    }

    String timezone = currentCity?.timezone ?? 'auto';
    if (timezone == 'GMT' || timezone == 'UTC' || timezone.isEmpty) {
      timezone = 'auto';
    }

    final baseUrl = '$kAirQualityApi/air-quality?'
        'latitude=$lat'
        '&longitude=$lon'
        '&current=european_aqi'
        '&hourly=alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen'
        '&timezone=${Uri.encodeComponent(timezone)}'
        '&forecast_days=3'; 

    final url = Uri.parse(baseUrl);

    try {
      final r = await http.get(
        url,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'pocasie-app/1.0 (flutter)',
        },
      ).timeout(const Duration(seconds: 15));

      if (r.statusCode == 200) {
        await CacheManager.saveAirQuality(lat, lon, r.body);
        return AirQualityData.fromJson(json.decode(r.body));
      }
    } on SocketException {
      // Ignore network DNS/socket errors - use cached/empty fallback below.
    } on TimeoutException {
      // Ignore timeout - use cached/empty fallback below.
    } catch (_) {
      // Any AQI parsing/server error should not propagate to UI as a hard error.
    }

    final cachedJson = await CacheManager.getAirQuality(lat, lon, ignoreExpiry: true);
    if (cachedJson != null) {
      return AirQualityData.fromJson(json.decode(cachedJson));
    }
    return AirQualityData();
  }

  Future<({WeatherData data, AirQualityData? aqi})?> _loadStoredWeatherForCity(GeoCity city) async {
    try {
      final cachedWeather = await _cachedWeatherJsonForCity(city.lat, city.lon);
      final cachedData = CacheManager.decodeForecastWeatherBody(cachedWeather);
      if (cachedData == null || !_forecastHasCoreFields(cachedData)) return null;
      WeatherData data;
      try {
        data = await _augmentWeatherDataWithUvFallback(
          cachedData,
          city.lat,
          city.lon,
          _normalizeApiTimezone(city.timezone),
        );
      } catch (_) {
        data = cachedData;
      }
      // Aktualizácia satelitného cloud cover aj pre cache dáta
      if (data.current != null) {
        try {
          final satCloud = await fetchSatelliteCloudCover(city.lat, city.lon);
          if (satCloud != null) {
            final current = data.current!;
            data = data.copyWith(
              current: CurrentWeather(
                temperature: current.temperature,
                isDay: current.isDay,
                weatherCode: current.weatherCode,
                relativeHumidity: current.relativeHumidity,
                surfacePressure: current.surfacePressure,
                windSpeed: current.windSpeed,
                windDirection: current.windDirection,
                precipitation: current.precipitation,
                time: current.time,
                uvIndex: current.uvIndex,
                cloudCover: current.cloudCover,
                apparentTemperature: current.apparentTemperature,
                satelliteCloudCover: satCloud,
              ),
            );
          }
        } catch (_) {
        }
      }
      AirQualityData? aqiData;
      final cachedAqi =
          await CacheManager.getAirQuality(city.lat, city.lon, ignoreExpiry: true);
      if (cachedAqi != null) {
        aqiData = AirQualityData.fromJson(json.decode(cachedAqi));
      }
      return (data: data, aqi: aqiData);
    } catch (_) {
      return null;
    }
  }

  Future<void> fetchWeatherByCity(GeoCity city, {bool forceRefresh = false, bool showLoading = true}) async {
    if (!mounted) return;

    if (_forceWeatherRefreshOnce) {
      forceRefresh = true;
      _forceWeatherRefreshOnce = false;
    }

    final bool wasOffline = _isOffline;
    final int mySerial = ++_weatherFetchSerial;
    final GeoCity? previousCity = currentCity;
    final bool locationChanged = previousCity == null ||
        (previousCity.lat - city.lat).abs() > 0.0002 ||
        (previousCity.lon - city.lon).abs() > 0.0002;

    // Nowcast hneď — NIE až po hasInternetConnection (to vie zabrať 1–4 s).
    final int radarSerial = ++_radarFetchSerial;
    if (locationChanged) {
      setState(() {
        currentCity = city;
        hasError = false;
        _expandedStates = [];
        _lightningNearby = false;
        _radarNowcastContext = RadarNowcastContext.inactive;
        _lastRadarContextUiApplyAt = null;
        resetRadarTrackerStabilizer();
        _invalidateDisplayCaches();
        _radarMapUiTimer?.cancel();
        _radarMapUiTimer = null;
      });
      _kickRadarNowcastEarly(
        city: city,
        mySerial: mySerial,
        radarSerial: radarSerial,
        force: true,
      );
      _deferRadarSetup(city, forceReload: wasOffline || locationChanged);
      _syncVystrahyPreloaderForCity(city);
    }

    final bool hasInternet = await hasInternetConnection();
    // Pri falošnom „offline“ (DNS) stále skúsime sieť, ak nemáme platnú cache.
    if (!hasInternet && !forceRefresh) {
      final offlineStored = await _loadStoredWeatherForCity(city);
      if (offlineStored != null) {
        if (!mounted || mySerial != _weatherFetchSerial) return;
        await _observeDailyPrecipLatchForCity(city, offlineStored.data);
        setState(() {
          currentCity = city;
          weatherData = offlineStored.data;
          airQualityData = offlineStored.aqi;
          isLoading = false;
          _isRefreshing = false;
          _isOffline = true;
          hasError = false;
        });
        _invalidateDisplayCaches();
        await _syncDailySummaryWithLatestData(city, offlineStored.data);
        await _syncEveningSummaryWithLatestData(city, offlineStored.data);
        await _syncAllLeadAlerts(offlineStored.data);
        _scheduleWidgetUpdate();
        if (!locationChanged) {
          _deferRadarSetup(city, forceReload: wasOffline);
          _syncVystrahyPreloaderForCity(city);
        }
        return;
      }
    }

    final stored = await _loadStoredWeatherForCity(city);
    final bool horizonTooShort = !forecastDailyHorizonComplete(weatherData);
    final bool effectiveForceRefresh = forceRefresh || horizonTooShort;

    if (stored != null) {
      unawaited(_observeDailyPrecipLatchForCity(city, stored.data));
    }

    setState(() {
      currentCity = city;
      hasError = false;
      _isOffline = false;
      if (locationChanged) {
        // Radar/nowcast už kicknuté vyššie — tu len UI predpovede.
      }
      if (stored != null) {
        weatherData = stored.data;
        airQualityData = stored.aqi;
        isLoading = false;
        _isRefreshing = true;
      } else {
        if (locationChanged && showLoading) {
          weatherData = null;
          airQualityData = null;
          _invalidateDisplayCaches();
        }
        isLoading = showLoading;
        _isRefreshing = false;
      }
    });

    if (!locationChanged) {
      _deferRadarSetup(city, forceReload: wasOffline);
      _syncVystrahyPreloaderForCity(city);
      _kickRadarNowcastEarly(
        city: city,
        mySerial: mySerial,
        radarSerial: radarSerial,
        force: false,
      );
    }

    try {
      late WeatherData data;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          data = await _fetchForecastWeatherData(
            city.lat,
            city.lon,
            forceRefresh: effectiveForceRefresh,
            apiTimezone: 'auto',
          );
          break;
        } catch (e) {
          debugPrint('fetch attempt $attempt failed: $e');
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue;
          }
          rethrow;
        }
      }

      final aqiFuture = _fetchAirQualityData(
        city.lat,
        city.lon,
        forceRefresh: false,
      );

      AirQualityData? aqiData;
      try {
        aqiData = await aqiFuture;
      } catch (e) {
        debugPrint('AQI fetch failed: $e');
      }

      if (!mounted || mySerial != _weatherFetchSerial) return;
      unawaited(_observeDailyPrecipLatchForCity(city, data));
      setState(() {
        weatherData = data;
        airQualityData = aqiData;
        isLoading = false;
        _isRefreshing = false;
        _isOffline = false;
      });
      _invalidateDisplayCaches();
      _scheduleSecondaryWeatherSignals(
        city: city,
        mySerial: mySerial,
        radarSerial: radarSerial,
      );
      unawaited(_syncWeatherFetchFollowUps(city, data));
    } catch (e) {
      debugPrint('fetchWeatherByCity failed for ${city.name}: $e');
      final cachedWeather = await _cachedWeatherJsonForCity(city.lat, city.lon);
      final cachedAqi = await CacheManager.getAirQuality(city.lat, city.lon, ignoreExpiry: true);

      if (cachedWeather != null) {
        try {
          final cachedData = CacheManager.decodeForecastWeatherBody(cachedWeather);
          if (cachedData != null && _forecastHasCoreFields(cachedData)) {
            WeatherData data;
            try {
              data = await _augmentWeatherDataWithUvFallback(
                cachedData,
                city.lat,
                city.lon,
                _normalizeApiTimezone(city.timezone),
              );
            } catch (_) {
              data = cachedData;
            }
            AirQualityData? aqiData;
            if (cachedAqi != null) {
              aqiData = AirQualityData.fromJson(json.decode(cachedAqi));
            }

            if (!mounted || mySerial != _weatherFetchSerial) return;
            await _observeDailyPrecipLatchForCity(city, data);
            setState(() {
              weatherData = data;
              airQualityData = aqiData;
              isLoading = false;
              _isRefreshing = false;
              _isOffline = !hasInternet;
              hasError = false;
            });
            try {
              await _syncDailySummaryWithLatestData(city, data);
              await _syncEveningSummaryWithLatestData(city, data);
              await _syncAllLeadAlerts(data);
            } catch (e, st) {
              debugPrint('Post-weather sync (cache) failed: $e\n$st');
            }
            _scheduleWidgetUpdate();
            return;
          }
        } catch (_) {}
      }

      if (!mounted || mySerial != _weatherFetchSerial) return;
      final bool keepCalmAfterSilentReloadFail = forceRefresh &&
          !showLoading &&
          weatherData != null &&
          currentCity != null &&
          (currentCity!.lat - city.lat).abs() < 0.0002 &&
          (currentCity!.lon - city.lon).abs() < 0.0002;
      if (keepCalmAfterSilentReloadFail) {
        if (!mounted || mySerial != _weatherFetchSerial) return;
        setState(() {
          hasError = false;
          isLoading = false;
          _isRefreshing = false;
          _isOffline = false;
        });
        return;
      }

      if (!mounted || mySerial != _weatherFetchSerial) return;
      setState(() {
        hasError = true;
        isLoading = false;
        _isRefreshing = false;
        _isOffline = false;
        if (locationChanged) {
          weatherData = null;
          airQualityData = null;
        }
      });
    }
  }

  bool _supportsRadarForCity(GeoCity? city) =>
      city != null && radarCoverageForCity(city);

  bool _supportsVystrahyForCity(GeoCity? city) =>
      city != null && cityEligibleForVystrahy(city);

  void _syncVystrahyPreloaderForCity(GeoCity city) {
    _deferVystrahyWarmup(city);
  }

  Future<void> _loadNearbyWebcams(GeoCity city) async {
    final cityKey = '${city.lat.toStringAsFixed(3)}:${city.lon.toStringAsFixed(3)}';
    if (_isLoadingWebcams && _webcamsRequestedForCityKey == cityKey) return;

    setState(() {
      _isLoadingWebcams = true;
      _webcamsError = null;
      _webcamsRequestedForCityKey = cityKey;
    });

    try {
      final parsed = <_ShmuCameraItem>[];
      final cc = city.countryCode.toUpperCase();
      if (cc == 'SK') {
        final resp = await http
            .get(Uri.parse('https://www.shmu.sk/sk/?page=1&id=webkamery'))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) {
          throw Exception('Nepodarilo sa načítať SHMÚ kamery (${resp.statusCode}).');
        }

        final html = utf8.decode(resp.bodyBytes);
        final byId = {for (final m in _shmuCameraMetaList) m.id: m};
        final re = RegExp(
          r'<a href="\?page=1&amp;id=webkamery&amp;kamera=(hdcam\d+)".*?<img[^>]*src="([^"]+)"',
          dotAll: true,
        );

        for (final match in re.allMatches(html)) {
          final id = match.group(1);
          final src = match.group(2);
          if (id == null || src == null) continue;
          final meta = byId[id];
          if (meta == null) continue;

          final distanceKm = Geolocator.distanceBetween(
                city.lat,
                city.lon,
                meta.lat,
                meta.lon,
              ) /
              1000.0;
          final imageUrl = Uri.parse('https://www.shmu.sk').resolve(src).toString();
          parsed.add(
            _ShmuCameraItem(
              meta: meta,
              imageUrl: imageUrl,
              source: 'sk',
              provider: 'shmu.sk',
              detailUrl: 'https://www.shmu.sk/sk/?page=1&id=webkamery&kamera=$id',
              distanceKm: distanceKm,
            ),
          );
        }
      } else if (cc == 'CZ') {
        final resp = await http
            .get(Uri.parse('https://intranet.chmi.cz/files/portal/docs/meteo/kam/webcams.json'))
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode != 200) {
          throw Exception('Nepodarilo sa načítať české kamery (${resp.statusCode}).');
        }
        final raw = jsonDecode(utf8.decode(resp.bodyBytes));
        if (raw is! List) {
          throw Exception('Neplatný formát CZ kamier.');
        }
        for (final item in raw) {
          if (item is! Map<String, dynamic>) continue;
          final file = (item['file'] ?? '').toString().trim();
          final name = (item['name'] ?? '').toString().trim();
          final direction = (item['smer'] ?? '').toString().trim();
          final lat = double.tryParse((item['lat'] ?? '').toString());
          final lon = double.tryParse((item['lon'] ?? '').toString());
          if (file.isEmpty || name.isEmpty || lat == null || lon == null) continue;
          final displayName = direction.isEmpty ? name : '$name (${direction.toLowerCase()})';
          final meta = _ShmuCameraMeta(id: file, name: displayName, lat: lat, lon: lon);
          final distanceKm = Geolocator.distanceBetween(city.lat, city.lon, lat, lon) / 1000.0;
          parsed.add(
            _ShmuCameraItem(
              meta: meta,
              imageUrl: 'https://intranet.chmi.cz/files/portal/docs/meteo/kam/$file.jpg',
              source: 'cz',
              provider: 'chmi.cz',
              detailUrl: null,
              distanceKm: distanceKm,
            ),
          );
        }
      }

      parsed.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      if (cc == 'CZ') {
        const maxCameraDistanceKm = 180.0;
        parsed.removeWhere((cam) => cam.distanceKm > maxCameraDistanceKm);
      }
      if (!mounted) return;
      setState(() {
        _nearbyWebcams = parsed;
        _webcamsLoadedForCityKey = cityKey;
        _isLoadingWebcams = false;
        _webcamPreviewCacheBuster = DateTime.now().millisecondsSinceEpoch;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingWebcams = false;
        _webcamsError = 'Kamery sa nepodarilo načítať. Skús neskôr.';
      });
    }
  }

  void _ensureNearbyWebcamsLoaded() {
    final city = currentCity;
    if (city == null) return;
    final cc = city.countryCode.toUpperCase();
    if (cc != 'SK' && cc != 'CZ') return;
    final cityKey = '${city.lat.toStringAsFixed(3)}:${city.lon.toStringAsFixed(3)}';
    if (_webcamsLoadedForCityKey == cityKey || _webcamsRequestedForCityKey == cityKey) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadNearbyWebcams(city));
    });
  }

  void _openWebcamDetail(_ShmuCameraItem cam) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WebcamDetailPage(camera: cam),
      ),
    );
  }

  String _cameraStatusKey(_ShmuCameraItem cam) => '${cam.source}:${cam.meta.id}:${cam.imageUrl}';

  String _cameraPreviewUrl(_ShmuCameraItem cam) {
    final uri = Uri.parse(cam.imageUrl);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['cb'] = _webcamPreviewCacheBuster.toString();
    return uri.replace(queryParameters: qp).toString();
  }

  bool _isCameraOnline(_ShmuCameraItem cam) => _cameraOnlineStatus[_cameraStatusKey(cam)] ?? true;

  void _setCameraOnlineStatus(_ShmuCameraItem cam, bool isOnline) {
    final key = _cameraStatusKey(cam);
    if (_cameraOnlineStatus[key] == isOnline || !mounted) return;
    setState(() {
      _cameraOnlineStatus[key] = isOnline;
    });
  }

  Widget _buildWebcamsSection() {
    if (currentCity == null) {
      return const SizedBox.shrink();
    }
    final cc = currentCity!.countryCode.toUpperCase();
    if (cc != 'SK' && cc != 'CZ') {
      return const SizedBox.shrink();
    }
    _ensureNearbyWebcamsLoaded();

    const sectionTitle = Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Center(
        child: Text(
          'Najbližšia kamera podľa zvolenej lokality',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    Widget sectionBody;
    if (_isLoadingWebcams && _nearbyWebcams.isEmpty) {
      sectionBody = const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_webcamsError != null && _nearbyWebcams.isEmpty) {
      sectionBody = Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        child: Text(
          _webcamsError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    } else if (_nearbyWebcams.isEmpty) {
      sectionBody = const Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 16),
        child: Text(
          'Pre túto lokalitu nie je dostupná kamera.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    } else {
      final cam = _nearbyWebcams.first;
      sectionBody = GestureDetector(
        onTap: () => _openWebcamDetail(cam),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _cameraPreviewUrl(cam),
                  height: 90,
                  width: 130,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _setCameraOnlineStatus(cam, true);
                      });
                      return child;
                    }
                    return child;
                  },
                  errorBuilder: (_, __, ___) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _setCameraOnlineStatus(cam, false);
                    });
                    return Container(
                      height: 90,
                      width: 130,
                      color: kAppCardNavy,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image, color: Colors.white54),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Najbližšia kamera',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cam.meta.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stav kamery — ${_isCameraOnline(cam) ? 'Online' : 'Offline'}',
                      style: TextStyle(
                        color: _isCameraOnline(cam)
                            ? const Color(0xFF7CFFB2)
                            : const Color(0xFFFF9A9A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Otvorte kliknutím',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, _kHomeForecastSectionGap),
      padding: const EdgeInsets.only(top: 14, bottom: 12, left: 12, right: 12),
      decoration: appSurfaceDecoration(radius: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle,
          sectionBody,
        ],
      ),
    );
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing || isLoading) return;

    setState(() {
      _isRefreshing = true;
      hasError = false;
    });

    try {
      if (await _canUseDeviceLocation()) {
        await _refreshWithCurrentLocationOrKeepCurrent();
      } else {
        await _refreshCurrentDataOnly();
      }

      if (currentCity != null) {
        await _fetchHistorical(currentCity!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          hasError = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _refreshWithCurrentLocationOrKeepCurrent() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final turnOn = await _offerTurnOnLocationServicesDialog();
        if (turnOn == true) {
          await Geolocator.openLocationSettings();
        }
        await _refreshCurrentDataOnly();
        return;
      }

      final LocationPermission perm = await _ensureForegroundLocationPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        await _refreshCurrentDataOnly();
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 10),
            distanceFilter: 50,
          ),
        );
      } catch (e) {
        position = await Geolocator.getLastKnownPosition()
            .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
      }

      GeoCity? city;

      if (position != null) {
        try {
          city = await reverseGeocode(position.latitude, position.longitude)
              .timeout(const Duration(seconds: 10), onTimeout: () => null);
        } catch (e) {
          final formattedLat = position.latitude.toStringAsFixed(4);
          final formattedLon = position.longitude.toStringAsFixed(4);
          city = GeoCity(
            name: 'Poloha ($formattedLat, $formattedLon)',
            lat: position.latitude,
            lon: position.longitude,
            country: '',
            countryCode: '',
            admin1: '',
            admin2: '',
            timezone: 'auto',
          );
        }
      }

      double? distanceInMeters;
      if (position != null && currentCity != null) {
        distanceInMeters = Geolocator.distanceBetween(
          currentCity!.lat,
          currentCity!.lon,
          position.latitude,
          position.longitude,
        );
      }

      if (city != null && position != null &&
          (distanceInMeters == null || distanceInMeters > _kSwitchCityMinMoveM)) {

        try {
          final GeoCity pickedCity =
              _preferStickyCityIdentity(currentCity, city, position.latitude, position.longitude);

          final int mySerial = ++_weatherFetchSerial;
          final weatherFuture = _fetchForecastWeatherData(
            pickedCity.lat,
            pickedCity.lon,
            forceRefresh: true,
            apiTimezone: pickedCity.timezone,
          ).timeout(const Duration(seconds: 15));
          final aqiFuture =
              _fetchAirQualityData(pickedCity.lat, pickedCity.lon, forceRefresh: true).timeout(const Duration(seconds: 15));

          final weather = await weatherFuture;

          AirQualityData? aqiData;
          try {
            aqiData = await aqiFuture;
          } catch (e) {
            debugPrint('AQI fetch error');
          }

          if (!mounted || mySerial != _weatherFetchSerial) return;
          await _observeDailyPrecipLatchForCity(pickedCity, weather);
          setState(() {
            currentCity = pickedCity;
            weatherData = weather;
            airQualityData = aqiData;
            _isRefreshing = false;
            _isOffline = false;
            SettingsManager.saveLastLocation(pickedCity);
            _updateOneSignalTags(pickedCity);
          });
          await _syncDailySummaryWithLatestData(pickedCity, weather);
          await _syncEveningSummaryWithLatestData(pickedCity, weather);
          await _syncAllLeadAlerts(weather);
          _scheduleWidgetUpdate();
          _ensureRadarMapUiNow(pickedCity);
          _fetchHistorical(pickedCity);
        } catch (e) {
          await _refreshCurrentDataOnly();
        }
      } else {
        await _refreshCurrentDataOnly();
      }
    } catch (e) {
      await _refreshCurrentDataOnly();
    }
  }

  Future<void> _refreshCurrentDataOnly() async {
    if (currentCity == null) {
      setState(() {
        _isRefreshing = false;
      });
      return;
    }

    final int mySerial = ++_weatherFetchSerial;
    final GeoCity city = currentCity!;

    try {
      final weatherFuture = _fetchForecastWeatherData(
        city.lat,
        city.lon,
        forceRefresh: true,
        apiTimezone: city.timezone,
      ).timeout(const Duration(seconds: 15));
      final aqiFuture = _fetchAirQualityData(city.lat, city.lon, forceRefresh: true).timeout(const Duration(seconds: 15));

      final data = await weatherFuture;

      AirQualityData? aqiData;
      try {
        aqiData = await aqiFuture;
      } catch (e) {
        debugPrint('AQI fetch error');
      }

      if (!mounted || mySerial != _weatherFetchSerial) return;
      await _observeDailyPrecipLatchForCity(city, data);
      setState(() {
        weatherData = data;
        airQualityData = aqiData;
        _isRefreshing = false;
        _isOffline = false;
      });
      await _syncDailySummaryWithLatestData(city, data);
      await _syncEveningSummaryWithLatestData(city, data);
      await _syncAllLeadAlerts(data);
      _scheduleWidgetUpdate();
    } catch (e) {
      final cachedWeather = await _cachedWeatherJsonForCity(city.lat, city.lon);
      final cachedAqi = await CacheManager.getAirQuality(city.lat, city.lon, ignoreExpiry: true);

      if (cachedWeather != null) {
        final cachedData = CacheManager.decodeForecastWeatherBody(cachedWeather);
        if (cachedData == null) return;
        final data = await _augmentWeatherDataWithUvFallback(
          cachedData,
          city.lat,
          city.lon,
          _normalizeApiTimezone(city.timezone),
        );
        AirQualityData? aqiData;
        if (cachedAqi != null) {
          aqiData = AirQualityData.fromJson(json.decode(cachedAqi));
        }

        if (!mounted || mySerial != _weatherFetchSerial) return;
        await _observeDailyPrecipLatchForCity(city, data);
        setState(() {
          weatherData = data;
          airQualityData = aqiData;
          _isRefreshing = false;
          _isOffline = true;
        });
        await _syncDailySummaryWithLatestData(city, data);
        await _syncEveningSummaryWithLatestData(city, data);
        await _syncAllLeadAlerts(data);
        _scheduleWidgetUpdate();
        return;
      }

      if (!mounted || mySerial != _weatherFetchSerial) return;
      setState(() {
        hasError = false;
        _isRefreshing = false;
        _isOffline = true;
      });
    }
  }

  Future<void> _retryConnection() async {
    const minRetryIndicator = Duration(milliseconds: 900);
    final retryStartedAt = DateTime.now();

    setState(() {
      isLoading = true;
    });

    final GeoCity retryCity =
        currentCity ?? await SettingsManager.getLastLocation() ?? kDefaultFallbackCity;
    await fetchWeatherByCity(
      retryCity,
      forceRefresh: true,
      showLoading: weatherData == null,
    );
    if (weatherData != null || !mounted) return;

    final elapsed = DateTime.now().difference(retryStartedAt);
    if (elapsed < minRetryIndicator) {
      await Future.delayed(minRetryIndicator - elapsed);
    }
    if (!mounted) return;
    await _initFromHomeOrLocation();
  }

  Widget _buildFetchFailureScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: Color.fromRGBO(255, 255, 255, 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Počasie sa nepodarilo načítať',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Skúste znova o chvíľu.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : _retryConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAppAccentBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  splashFactory: NoSplash.splashFactory,
                ).copyWith(
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Skúsiť znova',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _heroTitle() =>
      currentCity?.name.trim().isEmpty != false ? 'Poloha' : currentCity!.name.trim();

  void _scheduleWidgetUpdate() {
    if (kIsWeb) return;
    Future<void>.microtask(() async {
      if (!mounted) return;
      try {
        final w = weatherData;
        if (w == null || currentCity == null) {
          await WeatherHomeWidget.clear();
          return;
        }
        final record = _getFirstHourWeatherInfo();
        final tempStr = record.$1;
        final displayCode = record.$4;
        final descRaw = weatherDescriptionPinnedSk(displayCode);
        final desc = descRaw.replaceFirstMapped(
          RegExp(r'^[a-záäčďéíĺľňóôŕšťúýž]'),
          (m) => m.group(0)!.toUpperCase(),
        );
        final loc = _getCurrentLocationTime();
        const wk = <String>[
          'Pondelok',
          'Utorok',
          'Streda',
          'Štvrtok',
          'Piatok',
          'Sobota',
          'Nedeľa',
        ];
        const mon = <String>[
          'januára',
          'februára',
          'marca',
          'apríla',
          'mája',
          'júna',
          'júla',
          'augusta',
          'septembra',
          'októbra',
          'novembra',
          'decembra',
        ];
        final timeJe =
            '${wk[loc.weekday - 1]} ${loc.day}. ${mon[loc.month - 1]}, ${loc.hour.toString().padLeft(2, '0')}:${loc.minute.toString().padLeft(2, '0')}';
        String? apparent;
        if (w.current?.apparentTemperature != null) {
          apparent = 'Pocitovo ${w.current!.apparentTemperature!.round()}°';
        }
        final sunTimes = _todaySunTimes();
        final sun = '${sunTimes['rise'] ?? '--:--'} / ${sunTimes['set'] ?? '--:--'}';
        final wind = w.current?.windSpeed != null ? _currentWindUnit.format(w.current!.windSpeed!) : '--';
        final humidity = w.current?.relativeHumidity != null ? '${w.current!.relativeHumidity!.round()}%' : '--%';
        final isDay = w.current?.isDay == 1;
        final weatherInfo = _weatherCodeMap[normalizeDisplayWeatherCode(displayCode)];
        String? iconAssetPath;
        if (isDay) {
          iconAssetPath = weatherInfo?['icon_day']?.toString();
        } else {
          iconAssetPath = weatherInfo?['icon_night']?.toString();
        }
        await WeatherHomeWidget.update(
          city: _heroTitle(),
          description: desc,
          temperature: tempStr,
          timeJe: timeJe,
          weatherCode: displayCode,
          iconAssetPath: iconAssetPath,
          isDay: isDay,
          apparent: apparent,
          wind: wind,
          sun: sun,
          humidity: humidity,
          isOffline: _isOffline,
        );
      } catch (e) {
        debugPrint('Widget sync: $e');
      }
    });
  }

  Map<String, String> _todaySunTimes() {
    if (_isOffline) {
      return {'rise': '--:--', 'set': '--:--'};
    }

    final d = weatherData?.daily;
    if (d == null || d.sunrise?.isEmpty == true || d.sunset?.isEmpty == true) {
      return {'rise': '--:--', 'set': '--:--'};
    }

    final sunriseTime = d.sunrise?.first ?? '';
    final sunsetTime = d.sunset?.first ?? '';

    try {
      String extractTime(String isoTime) {
        try {
          final timePart = isoTime.split('T')[1];
          final hourMinute = timePart.split(':').take(2).join(':');
          return hourMinute;
        } catch (e) {
          return '--:--';
        }
      }

      return {
        'rise': extractTime(sunriseTime),
        'set': extractTime(sunsetTime)
      };
    } catch (e) {
      return {'rise': '--:--', 'set': '--:--'};
    }
  }

  Future<void> _openSearch() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);

    final selected = await navigator.push<GeoCity>(
      MaterialPageRoute(builder: (_) => const CitySearchPage()),
    );

    if (!mounted || selected == null) return;

    // Po výbere lokality vždy skús načítanie z API (`forceRefresh: true` obíde vetvu
    // „žiadny internet + žiadna cache“, keď `hasInternetConnection()` falošne zlyhá).
    await fetchWeatherByCity(selected, forceRefresh: false, showLoading: false);
    _updateOneSignalTags(selected);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          currentWindUnit: _currentWindUnit,
          currentMyLocationEnabled: _myLocationEnabled,
        ),
      ),
    );
    if (mounted) {
      await _loadSettings();
      final city = currentCity;
      final data = weatherData;
      if (city != null && data != null) {
        await _syncDailySummaryWithLatestData(city, data);
        await _syncEveningSummaryWithLatestData(city, data);
        await _syncAllLeadAlerts(data);
      }
    }
  }

  (String, Widget, String, int) _getFirstHourWeatherInfo() {
    final cacheKey = _firstHourDisplayCacheKey();
    if (_cachedFirstHourInfo != null && _cachedFirstHourInfoKey == cacheKey) {
      return _cachedFirstHourInfo!;
    }
    final result = _computeFirstHourWeatherInfo();
    _cachedFirstHourInfo = result;
    _cachedFirstHourInfoKey = cacheKey;
    return result;
  }

  (String, Widget, String, int) _computeFirstHourWeatherInfo() {
    final h = weatherData?.hourly;
    final current = weatherData?.current;
    final daily = weatherData?.daily;

    if (h == null) return ('--°', getWeatherIcon(null, size: 100), '', 0);

    final DateTime locTime = _getCurrentLocationTime();
    final DateTime deviceNow = DateTime.now();

    final radarCoverageActive =
        currentCity != null && radarNowcastActiveForCity(currentCity!);

    // Ten istý WMO + ikona ako aktuálny riadok v 24 h (bez „najsilnejšieho“ dažďa z budúcich hodín).
    if (current != null) {
      final pinned = pinnedHeaderDisplayFromHourly(
        h: h,
        locTime: locTime,
        current: current,
        daily: daily,
        lightningNearby: _lightningNearby,
        radarNowcast: _radarNowcastContext,
        radarCoverageActive: radarCoverageActive,
      );
      final displayCode = pinned.code;
      final t = current.temperature;
      final tempStr = t != null ? '${t.round()}°' : '--°';
      final hourTime = pinned.hourIso;
      final icon = getWeatherIcon(
        displayCode,
        hourTime: hourTime,
        daily: daily,
        size: 100,
      );
      return (tempStr, icon, '', displayCode);
    }

    // Záloha: prvý hodinový riadok pre *biežacu* hodinu (predtým sa brala nasledujúca hodina → iný WMO kód)
    final DateTime slotTime = DateTime(
      deviceNow.year,
      deviceNow.month,
      deviceNow.day,
      deviceNow.hour,
    );

    int start = 0;
    for (var i = 0; i < h.time.length; i++) {
      final forecastTime = DateTime.tryParse(h.time[i]);
      if (forecastTime != null) {
        if (!forecastTime.isBefore(slotTime)) {
          start = i;
          break;
        }
      }
    }

    if (start >= h.time.length) return ('--°', getWeatherIcon(null, size: 100), '', 0);

    final end = math.min(start + 1, h.time.length);
    final smoothed = _smoothHourlyData(h, start, end, current, daily, locTime);

    final temp = smoothed.temperatures.isNotEmpty ? smoothed.temperatures[0] : null;
    final pinnedFb = pinnedHeaderDisplayFromHourly(
      h: h,
      locTime: locTime,
      current: current,
      daily: daily,
      lightningNearby: _lightningNearby,
      radarNowcast: _radarNowcastContext,
      radarCoverageActive: radarCoverageActive,
    );
    final displayCode = pinnedFb.code;

    final timeString = pinnedFb.hourIso ?? h.time[start];

    final icon = getWeatherIcon(
      displayCode,
      hourTime: timeString,
      daily: daily,
      size: 100,
    );

    final tempStr = temp != null ? '${temp.round()}°' : '--°';
    return (tempStr, icon, '', displayCode);
  }

  BoxDecoration _heroGlassDecoration(double borderRadius) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: kAppCardNavy,
      border: Border.all(color: kAppCardNavyBorder, width: 1),
    );
  }

  /// Sklenené pozadie pre karty na domovskej obrazovke; [borderRadius] bez zmeny rozloženia widgetu.
  Widget _heroGlassSurface({
    required Widget child,
    double borderRadius = 20,
    bool withShadow = false,
  }) {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      decoration: withShadow
          ? BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF060C14).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            )
          : null,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: _heroGlassDecoration(borderRadius),
          child: child,
        ),
      ),
    );
  }

  Widget _heroGlassCard({required Widget child, bool withShadow = true}) {
    return _heroGlassSurface(
      borderRadius: 20,
      withShadow: withShadow,
      child: child,
    );
  }

  /// Hero = teplota / ikona — rovnaká rodina ako karty, len mierne nadvihnutá.
  Widget _heroWeatherPanel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kAppHeroGradientTop,
            kAppHeroGradientMid,
            kAppHeroGradientBottom,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(color: kAppCardNavyBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C1828).withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _heroChromeButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kAppCardNavy,
          border: Border.all(color: kAppCardNavyBorder),
        ),
        child: Center(child: Icon(icon, size: 20, color: Colors.white)),
      ),
    );
  }

  Widget _buildHero(String firstHourTemp, Widget firstHourIcon, int displayCode) {
    final title = _heroTitle();
    final topPadding = math.max(6.0, MediaQuery.of(context).padding.top + 8);
    final sunTimes = _todaySunTimes();
    final enrichedCurrent = weatherData == null
        ? null
        : enrichWeatherDataCurrentFromHourly(weatherData!).current;
    final locationNow = _getCurrentLocationTime();
    final humidityText = _isOffline
        ? '--'
        : (enrichedCurrent?.relativeHumidity != null
            ? '${enrichedCurrent!.relativeHumidity!.round()}%'
            : '--');
    final windText = _isOffline
        ? '--'
        : (enrichedCurrent?.windSpeed != null
            ? _currentWindUnit.format(enrichedCurrent!.windSpeed!)
            : '--');
    final sunRiseText = _isOffline ? '--' : (sunTimes['rise'] ?? '--');
    final sunSetText = _isOffline ? '--' : (sunTimes['set'] ?? '--');
    final apparentText = _isOffline
        ? '--'
        : (enrichedCurrent?.apparentTemperature != null
            ? '${enrichedCurrent!.apparentTemperature!.round()}°'
            : '--');
    final description = _isOffline
        ? '--'
        : (weatherDescriptionPinnedSk(displayCode))
            .replaceFirstMapped(RegExp(r'^[a-záäčďéíĺľňóôŕšťúýž]'),
                (m) => m.group(0)!.toUpperCase());

    const List<String> skMonths = <String>[
      'januára',
      'februára',
      'marca',
      'apríla',
      'mája',
      'júna',
      'júla',
      'augusta',
      'septembra',
      'októbra',
      'novembra',
      'decembra',
    ];
    const List<String> skWeekdays = <String>[
      'Pondelok',
      'Utorok',
      'Streda',
      'Štvrtok',
      'Piatok',
      'Sobota',
      'Nedeľa',
    ];
    final dayText = skWeekdays[locationNow.weekday - 1];
    final monthText = skMonths[locationNow.month - 1];
    final timeText =
        '${locationNow.hour.toString().padLeft(2, '0')}:${locationNow.minute.toString().padLeft(2, '0')}';
    final dateLine = '$dayText ${locationNow.day}. $monthText, $timeText';

    return Padding(
      padding: EdgeInsets.fromLTRB(14, topPadding, 14, _kHomeForecastSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _heroChromeButton(icon: Icons.search_rounded, onTap: _openSearch),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _heroChromeButton(icon: Icons.settings_rounded, onTap: _openSettings),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                dateLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withAlpha(200),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_isOffline)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Offline údaje nie sú dostupné',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withAlpha(170),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _heroWeatherPanel(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isOffline ? '--°' : firstHourTemp,
                          style: mono.merge(
                            const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 0.95,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pocitovo $apparentText',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withAlpha(220),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isOffline
                          ? const SizedBox(
                              width: 100,
                              height: 100,
                              child: Center(
                                child: Text(
                                  '--',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 48,
                                    fontWeight: FontWeight.w500,
                                    height: 0.95,
                                  ),
                                ),
                              ),
                            )
                          : SizedBox(
                              width: 100,
                              height: 100,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: firstHourIcon,
                              ),
                            ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withAlpha(230),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Vietor',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              windText,
                              style: mono.merge(
                                const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Východ / západ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$sunRiseText / $sunSetText',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: mono.merge(
                                const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Vlhkosť',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              humidityText,
                              textAlign: TextAlign.right,
                              style: mono.merge(
                                const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }



  Widget _tabBtn(String label, String value) {
    final sel = activeTab == value;
    const tabRadius = 999.0;
    final labelChild = Center(
      child: SizedBox(
        height: 20,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => activeTab = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 38,
          decoration: BoxDecoration(
            color: sel ? kAppAccentBlue : kAppCardNavy,
            borderRadius: BorderRadius.circular(tabRadius),
            border: Border.all(
              color: sel ? kAppAccentBlueBright.withValues(alpha: 0.35) : kAppCardNavyBorder,
            ),
          ),
          child: labelChild,
        ),
      ),
    );
  }

  Future<void> _openWeatherChart() async {
    final city = currentCity;
    var data = weatherData;
    if (city == null || data == null) return;

    final dailyLen = data.daily?.time.length ?? 0;
    if (dailyLen < kChartForecastDays) {
      try {
        await fetchWeatherByCity(city, forceRefresh: true, showLoading: false);
        data = weatherData ?? data;
      } catch (_) {}
      if (!mounted) return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WeatherChartPage(
          city: city,
          data: data!,
          radarCtx: radarNowcastActiveForCity(city) && _radarNowcastContext.eligible
              ? _radarNowcastContext
              : RadarNowcastContext.inactive,
        ),
      ),
    );
  }

  /// Radar v domovskom scrolli — lokalita v rámci kompozitu (stredná Európa).
  bool _shouldShowRadarHomeCard() {
    if (currentCity == null) return false;
    return _supportsRadarForCity(currentCity);
  }

  Widget _buildRadarMapPanel() {
    return Container(
      height: 220,
      decoration: appSurfaceDecoration(radius: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isRadarReturning)
              const Text(
                'Prebieha načítavanie radaru...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (_radarLoadFailed && !_isRadarReturning)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _radarOffline ? Icons.wifi_off : Icons.error_outline,
                      color: Colors.white70,
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _radarOffline
                          ? 'Radar nie je možné načítať, nemáte prístup k internetu.'
                          : 'Radar sa nepodarilo načítať.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => unawaited(_manualRadarRetry()),
                      style: FilledButton.styleFrom(
                        backgroundColor: kAppAccentBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        splashFactory: NoSplash.splashFactory,
                      ).copyWith(
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                      child: const Text(
                        'Skúsiť znova',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_isRadarFullscreen &&
                _radarWebViewWidget != null &&
                _radarMapUiReady)
              ValueListenableBuilder<bool>(
                valueListenable: appRecentsCoverNotifier,
                builder: (context, cover, _) {
                  // Pri minimalizácii WebView vyhodiť zo stromu — PlatformView inak „pretečie“ cez celý náhľad.
                  if (cover) {
                    return const ColoredBox(color: kAmbientBlendColor);
                  }
                  return IgnorePointer(child: _radarWebViewWidget!);
                },
              )
            else if (!_isRadarReturning)
              Container(color: kAmbientBlendColor),
            // Statický text — žiadny progress bar (pri WebView sa animácie sekajú).
            if (!_isRadarReturning &&
                !_radarLoadFailed &&
                !appRecentsCoverNotifier.value &&
                (_isRadarLoading ||
                    !_radarContentReady ||
                    _radarWebViewWidget == null))
              const Positioned.fill(
                child: ColoredBox(
                  color: kAmbientBlendColor,
                  child: Center(
                    child: Text(
                      'Načítavam radar...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                onTap: () => unawaited(_openRadarFullscreen()),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: IgnorePointer(
                child: _radarGlassBadge(Icons.radar, 'Meteo Radar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarCard() {
    if (!_shouldShowRadarHomeCard()) {
      return const SizedBox.shrink();
    }

    final city = currentCity!;
    _scheduleRadarMapUiIfNeeded(city);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: _buildRadarMapPanel(),
    );
  }

  Widget _buildHistoricalCard() {
    if (historicalWeather == null) return const SizedBox.shrink();

    final hw = historicalWeather!;
    final maxT = hw.maxTemp != null ? '${hw.maxTemp!.round()}°' : '--°';
    final minT = hw.minTemp != null ? '${hw.minTemp!.round()}°' : '--°';
    final code = hw.weatherCode ?? 0;

    final weatherInfo = _weatherCodeMap[normalizeDisplayWeatherCode(code)] ?? _weatherCodeMap[0]!;
    final dayIcon = weatherInfo['icon_day'] as String;
    final nightIcon = weatherInfo['icon_night'] as String;

    final dateParts = hw.dateStr.split('-');
    final formattedDate = dateParts.length == 3 ? '${dateParts[2]}.${dateParts[1]}.${dateParts[0]}' : hw.dateStr;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, _kHomeForecastSectionGap),
      decoration: appSurfaceDecoration(radius: 20),
      padding: const EdgeInsets.only(top: 20, bottom: 16, left: 16, right: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history, color: Colors.white.withAlpha(204), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Počasie pred rokom',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formattedDate,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white.withAlpha(153),
            ),
          ),
          const SizedBox(height: 16), 
          Row(
            children: [
              Expanded(
                child: _buildHistPart(
                  'Deň', 
                  dayIcon, 
                  maxT, 
                  const Color(0xFFFFA726)
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white.withAlpha(38)), 
              Expanded(
                child: _buildHistPart(
                  'Noc', 
                  nightIcon, 
                  minT, 
                  const Color(0xFF81D4FA)
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistPart(String label, String iconPath, String temp, Color accentColor) {
    final tempColor = _temperatureScaleColor(_temperatureFromLabel(temp));
    return Column(
      children: [
        Text(
          label, 
          style: TextStyle(
            fontSize: 13, 
            fontWeight: FontWeight.w500, 
            color: Colors.white.withAlpha(179)
          )
        ),
        const SizedBox(height: 10), 
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(iconPath, width: 46, height: 46), 
            const SizedBox(width: 14), 
            Text(
              temp, 
              style: mono.merge(TextStyle(
                fontSize: 20, 
                fontWeight: FontWeight.w600, 
                color: tempColor
              ))
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSupportCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, _kHomeForecastSectionGap),
      decoration: appSurfaceDecoration(radius: 20),
      padding: const EdgeInsets.only(top: 20, bottom: 16, left: 16, right: 16),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite, color: Color(0xFFFF5E5B), size: 20),
              SizedBox(width: 8),
              Text(
                'Podporte vývoj',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Ak chcete podporiť vývoj aplikácie, môžete tak urobiť kliknutím na tlačidlo nižšie.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withAlpha(179),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.local_cafe, size: 20),
              label: const Text(
                'Podporiť na Ko-fi',
                style: TextStyle(
                  fontWeight: FontWeight.w700, 
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5E5B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                splashFactory: NoSplash.splashFactory, 
              ).copyWith(
                overlayColor: WidgetStateProperty.all(Colors.transparent),
              ),
              onPressed: () async {
                try {
                  await openUrl('https://ko-fi.com/meteopocasie');
                } catch (e) {
                  debugPrint('Mohol zlyhať url launcher: $e');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    bool hasData,
    String firstHourTemp,
    int displayCode, {
    required Widget hero,
  }) {
    if (_isOffline) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: hero),
          SliverFillRemaining(
            hasScrollBody: false,
            child: OfflineScreen(
              onRetry: _retryConnection,
              isRetrying: isLoading,
              isOnboarding: false,
            ),
          ),
        ],
      );
    }

    if (hasError && !hasData) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: hero),
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildFetchFailureScreen(),
          ),
        ],
      );
    }

    if (isLoading && !_isRefreshing && !hasData) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: hero),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox.shrink(),
          ),
        ],
      );
    }

    if (!hasData) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: hero),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox.shrink(),
          ),
        ],
      );
    }

    final uvWarning = _getTodayUvWarning();
    final homeInsightTiles = _buildHomeInsightTilesRow(uvWarning: uvWarning);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: hero),
        if (homeInsightTiles != null)
          SliverToBoxAdapter(
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, _kHomeForecastSectionGap),
              child: homeInsightTiles,
            ),
          ),
        if (_shouldShowRadarHomeCard())
          SliverToBoxAdapter(
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.only(bottom: _kHomeForecastSectionGap),
              child: _buildRadarCard(),
            ),
          ),
        SliverToBoxAdapter(
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, _kHomeForecastSectionGap),
            child: _buildHomeQuickActions(),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, _kHomeForecastSectionGap),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kForecastStripMaxWidth),
                child: Row(
                  children: [
                    _tabBtn('24 hodín', 'hourly'),
                    const SizedBox(width: 6),
                    _tabBtn('$kDailyListForecastDays dní', 'daily'),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Conditional slivers for hourly/daily - vracajú priamo Sliver
        if (activeTab == 'hourly') ...[
          _buildHourly(),
        ] else ...[
          _buildDaily(),
        ],

        SliverToBoxAdapter(
          child: Container(
            color: Colors.transparent,
            child: _buildWebcamsSection(),
          ),
        ),

        SliverToBoxAdapter(
          child: Container(
            color: Colors.transparent,
            child: _buildHistoricalCard(),
          ),
        ),

        SliverToBoxAdapter(
          child: Container(
            color: Colors.transparent,
            child: _buildSupportCard(),
          ),
        ),

        SliverToBoxAdapter(
          child: Container(
            color: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.only(
                top: _kHomeForecastSectionGap,
                bottom: MediaQuery.of(context).padding.bottom + _kHomeForecastSectionGap,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: () async {
                      try {
                        await openUrl(kOpenMeteoAttributionUrl);
                      // ignore: empty_catches
                      } catch (e) {}
                    },
                    child: const Text(
                      'Údaje čiastočne poskytuje Open-Meteo',
                      style: TextStyle(
                        color: Color(0xFFA0C8E0),
                        fontSize: 14,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHourly() {
    final h = weatherData?.hourly;
    final current = weatherData?.current;
    final daily = weatherData?.daily;

    if (h == null) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final DateTime locTime = _getCurrentLocationTime();
    final city = currentCity;
    if (city != null && radarNowcastActiveForCity(city)) {
      final now = DateTime.now();
      if (_lastRadarStripRefreshAt == null ||
          now.difference(_lastRadarStripRefreshAt!) >
              _kRadarUiRefreshMinInterval) {
        _lastRadarStripRefreshAt = now;
        unawaited(_refreshRadarNowcastForCity(city));
      }
    }

    final visFloor = DateTime(
      locTime.year,
      locTime.month,
      locTime.day,
      locTime.hour,
    ).add(const Duration(hours: 1));
    final start = _hourlyForecastFirstIndexNotBefore(
      h,
      visFloor,
      utcOffsetSeconds: weatherData?.utcOffsetSeconds,
    );
    if (start == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final end = math.min(start + 24, h.time.length);
    if (end <= start) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final stripIndices = List.generate(end - start, (j) => start + j);
    final count = stripIndices.length;

    if (_expandedStates.length != count) {
      _expandedStates = List.filled(count, false);
    }

    final smoothed = _smoothHourlyData(
      h,
      start,
      end,
      current,
      daily,
      locTime,
    );

    final displayIcons = <int>[];
    final stripStoredProbs = <int>[];
    final stripShowRainPrecip = <bool>[];
    final stripPrecipMm = <double>[];

    final radarCoverageActive =
        city != null && radarNowcastActiveForCity(city);
    final iconsBuf = List<int>.filled(count, 3);
    final probsBuf = List<int>.filled(count, 0);
    final wetBuf = List<bool>.filled(count, false);
    final mmBuf = List<double>.filled(count, 0.0);

    applyUnifiedHourlyStripPrecip(
      displayIcons: iconsBuf,
      showRainPrecip: wetBuf,
      storedProbs: probsBuf,
      precipMm: mmBuf,
      stripIndices: stripIndices,
      h: h,
      radarCtx: _radarNowcastContext,
      locTime: locTime,
      utcOffsetSeconds: weatherData?.utcOffsetSeconds,
      radarCoverageActive: radarCoverageActive,
    );

    displayIcons.addAll(iconsBuf);
    stripStoredProbs.addAll(probsBuf);
    stripShowRainPrecip.addAll(wetBuf);
    stripPrecipMm.addAll(mmBuf);

    final curIdx = _hourlyIndexContainingLocalTime(h, locTime);
    alignHourlyStripThunderWithProbability(
      displayIcons: displayIcons,
      showRainPrecip: stripShowRainPrecip,
      storedProbs: stripStoredProbs,
      precipMm: stripPrecipMm,
      stripIndices: stripIndices,
      h: h,
      lightningNearby: _lightningNearby,
      lightningHourIndex: curIdx,
      utcOffsetSeconds: weatherData?.utcOffsetSeconds,
      radarCtx: _radarNowcastContext,
      locTime: locTime,
    );
    applyHourlyStripPrecipPercentRamp(
      displayIcons: displayIcons,
      showRainPrecip: stripShowRainPrecip,
      storedProbs: stripStoredProbs,
      precipMm: stripPrecipMm,
      stripIndices: stripIndices,
      h: h,
      locTime: locTime,
      utcOffsetSeconds: weatherData?.utcOffsetSeconds,
      radarCtx: _radarNowcastContext,
    );
    applyHourlyStripHorizonProbCaps(
      storedProbs: stripStoredProbs,
      stripIndices: stripIndices,
      h: h,
      locTime: locTime,
      utcOffsetSeconds: weatherData?.utcOffsetSeconds,
    );
    clampThunderHourlyStripProbs(
      displayIcons: displayIcons,
      storedProbs: stripStoredProbs,
      precipMm: stripPrecipMm,
    );
    applyThunderStripDisplayMm(
      displayIcons: displayIcons,
      storedProbs: stripStoredProbs,
      precipMm: stripPrecipMm,
    );
    final utcOff = weatherData?.utcOffsetSeconds;
    final stripSlotHours = <DateTime>[];
    for (final idx in stripIndices) {
      final parsed = DateTime.tryParse(h.time[idx]);
      if (parsed == null) {
        stripSlotHours.add(DateTime(
          locTime.year,
          locTime.month,
          locTime.day,
          locTime.hour,
        ));
        continue;
      }
      final localT =
          utcOff != null ? parsed.add(Duration(seconds: utcOff)) : parsed;
      stripSlotHours.add(
        DateTime(localT.year, localT.month, localT.day, localT.hour),
      );
    }
    alignHourlyStripIconsWithPrecipPercents(
      displayIcons: displayIcons,
      showRainPrecip: stripShowRainPrecip,
      precipPercents: stripStoredProbs,
      precipMm: stripPrecipMm,
      apiWeatherCodes: [
        for (final idx in stripIndices)
          h.weatherCode != null && idx < h.weatherCode!.length
              ? h.weatherCode![idx]
              : null,
      ],
      cloudCoverPercents: [
        for (final idx in stripIndices)
          h.cloudCover != null && idx < h.cloudCover!.length
              ? h.cloudCover![idx]
              : null,
      ],
      radarCtx: _radarNowcastContext,
      locTime: locTime,
      slotHours: stripSlotHours,
    );
    // Nowcast má posledné slovo — model po align/thunder nesmie nechať falošnú ikonu.
    applyRadarPrecipEndToHourlyStrip(
      displayIcons: displayIcons,
      showRainPrecip: stripShowRainPrecip,
      storedProbs: stripStoredProbs,
      precipMm: stripPrecipMm,
      stripIndices: stripIndices,
      h: h,
      radarCtx: _radarNowcastContext,
      locTime: locTime,
      utcOffsetSeconds: utcOff,
      radarCoverageActive: radarCoverageActive,
    );
    clampNearTermStripPercentsWithoutRadar(
      displayIcons: displayIcons,
      showRainPrecip: stripShowRainPrecip,
      storedProbs: stripStoredProbs,
      stripIndices: stripIndices,
      h: h,
      locTime: locTime,
      utcOffsetSeconds: utcOff,
      radarCtx: _radarNowcastContext,
      precipMm: stripPrecipMm,
    );
    reapplyDryCloudyStripPercents(
      displayIcons: displayIcons,
      showRainPrecip: stripShowRainPrecip,
      storedProbs: stripStoredProbs,
      stripIndices: stripIndices,
      h: h,
      radarCtx: _radarNowcastContext,
      locTime: locTime,
      utcOffsetSeconds: weatherData?.utcOffsetSeconds,
    );
    diversifyRepetitiveDryStripPercents(
      displayIcons: displayIcons,
      showRainPrecip: stripShowRainPrecip,
      storedProbs: stripStoredProbs,
      stripIndices: stripIndices,
      h: h,
      rainHoursBeforeStrip: _openMeteoUiPrecipHoursBeforeStrip(
        h: h,
        firstStripDataIndex: stripIndices.isEmpty ? 0 : stripIndices.first,
      ),
      radarCtx: _radarNowcastContext,
      locTime: locTime,
    );

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, _kHomeForecastSectionGap),
      sliver: SliverList.builder(
        itemCount: count,
        itemBuilder: (context, i) {
          return RepaintBoundary(
            child: _hourlyTile(
              index: stripIndices[i],
              h: h,
              smoothed: smoothed,
              smoothedIndex: i,
              displayIconCode: displayIcons[i],
              precipColumnPercent: stripStoredProbs[i],
              showRainPrecipColumn: stripShowRainPrecip[i],
              precipDisplayMm: stripPrecipMm[i],
              daily: daily,
              isExpanded: _expandedStates[i],
              onExpandedChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    for (int j = 0; j < _expandedStates.length; j++) {
                      _expandedStates[j] = j == i;
                    }
                  } else {
                    _expandedStates[i] = false;
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }

  String _formatTemperature(double? temp) {
    if (temp == null) return '--°';
    return '${temp.round()}°';
  }

  Color _temperatureScaleColor(double? temp) {
    if (temp == null) return Colors.white;
    final stops = <({double t, Color c})>[
      (t: -50.0, c: const Color(0xFFECEFF1)),
      (t: -40.0, c: const Color(0xFFB0BEC5)),
      (t: -30.0, c: const Color(0xFFCE93D8)),
      (t: -20.0, c: const Color(0xFF7E57C2)),
      (t: -10.0, c: const Color(0xFF3949AB)),
      (t: 0.0, c: const Color(0xFF29B6F6)),
      (t: 10.0, c: const Color(0xFF64DD17)),
      (t: 20.0, c: const Color(0xFFFFD600)),
      (t: 30.0, c: const Color(0xFFFF6D00)),
      (t: 40.0, c: const Color(0xFFE53935)),
      (t: 50.0, c: const Color(0xFFE040FB)),
    ];
    if (temp <= stops.first.t) return stops.first.c;
    if (temp >= stops.last.t) return stops.last.c;
    for (int i = 0; i < stops.length - 1; i++) {
      final a = stops[i];
      final b = stops[i + 1];
      if (temp >= a.t && temp <= b.t) {
        final f = (temp - a.t) / (b.t - a.t);
        return Color.lerp(a.c, b.c, f) ?? a.c;
      }
    }
    return Colors.white;
  }

  double? _temperatureFromLabel(String label) {
    final normalized = label.replaceAll('°', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized);
  }

  String _formatPressure(double? pressure) {
    if (pressure == null) return '—';
    return '${pressure.round()} hPa';
  }

  String _formatWindWithDirection(double? speed, double? direction) {
    if (speed == null) return '—';
    final formattedWind = _currentWindUnit.format(speed);
    if (direction == null) return formattedWind;
    final directionShort = windDirectionShort2(direction);
    return '$formattedWind, $directionShort';
  }

  String _formatDewPoint(double? dewPoint) {
    if (dewPoint == null) return '—';
    return '${dewPoint.round()}°';
  }

  String _formatWindGusts(double? gusts) {
    if (gusts == null) return '—';
    return _currentWindUnit.format(gusts);
  }

  String _formatHumidity(double? humidity) {
    if (humidity == null) return '—';
    return '${humidity.round()}%';
  }

  String _formatUvIndex(double? uvIndex) {
    if (uvIndex == null) return '—';
    final intValue = uvIndex.round();
    return '$intValue';
  }

  String _formatApparentTemperature(double? apparentTemp) {
    if (apparentTemp == null) return '—';
    return '${apparentTemp.round()}°';
  }

  String _formatIsoTimeShort(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '--:--';
    try {
      final parsed = DateTime.parse(isoTime);
      return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }

  Widget _buildHourlyDetails(HourlyForecast h, int index, _SmoothedValues smoothed, int smoothedIndex) {
    if (index >= h.time.length) return const SizedBox.shrink();
    if (smoothedIndex >= smoothed.weatherCodes.length) {
      return const SizedBox.shrink();
    }

    return Transform.translate(
      offset: const Offset(0, -8),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.only(top: 4, bottom: 4, left: 6, right: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kAppCardNavyElevated,
                    kAppCardNavy,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: kAppCardNavyBorder.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailItem(
                          title: 'Vlhkosť',
                          value: _formatHumidity(h.relativeHumidity?[index]),
                          icon: Icons.water_drop,
                        ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildDetailItem(
                        title: 'Rosný bod',
                        value: _formatDewPoint(h.dewPoint?[index]),
                        icon: Icons.thermostat,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildDetailItem(
                        title: 'UV index',
                        value: _formatUvIndex(
                          _hourlyIsoMatchesLocalWallHour(h.time[index], _getCurrentLocationTime())
                              ? _uvForLocalWallClockHour(
                                  h,
                                  _getCurrentLocationTime(),
                                  weatherData?.current,
                                )
                              : (smoothedIndex < smoothed.uvIndex.length
                                  ? smoothed.uvIndex[smoothedIndex]
                                  : null),
                        ),
                        icon: Icons.wb_sunny,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildDetailItem(
                        title: 'Nárazy vetra',
                        value: _formatWindGusts(h.windGusts?[index]),
                        icon: Icons.air,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildDetailItem(
                        title: 'Tlak vzduchu',
                        value: _formatPressure(h.pressure?[index]),
                        icon: Icons.speed,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildDetailItem(
                        title: 'Pocitová teplota',
                        value: _formatApparentTemperature(smoothed.apparentTemperature[smoothedIndex]),
                        icon: Icons.device_thermostat,
                        iconSize: 15.5,
                      ),
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
  }

  Widget _buildDetailItem({
    required String title,
    required String value,
    required IconData icon,
    double iconSize = 17,
    bool fullWidth = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: kAppCardNavyElevated.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: kAppCardNavyBorder.withValues(alpha: 0.28),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      width: fullWidth ? double.infinity : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: Colors.white),
              const SizedBox(width: 5),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFADC4D4),
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFFF1F5F9),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hourlyTile({
    required int index,
    required HourlyForecast h,
    required _SmoothedValues smoothed,
    required int smoothedIndex,
    required int displayIconCode,
    required int precipColumnPercent,
    required bool showRainPrecipColumn,
    required double precipDisplayMm,
    required DailyForecast? daily,
    required bool isExpanded,
    required ValueChanged<bool> onExpandedChanged,
  }) {
    const kRowH = 60.0;

    if (index >= h.time.length) return const SizedBox.shrink();
    if (smoothedIndex >= smoothed.weatherCodes.length || 
        smoothedIndex >= smoothed.temperatures.length) {
      return const SizedBox.shrink();
    }

    final timeLabel = formatTime(h.time[index], utcOffsetSeconds: weatherData?.utcOffsetSeconds);
    final tempLabel = _formatTemperature(smoothed.temperatures[smoothedIndex]);
    final tempColor = _temperatureScaleColor(smoothed.temperatures[smoothedIndex]);

    final bool hasPrecipProbData = h.precipitationProbability != null &&
        index < h.precipitationProbability!.length;
    final int iconCode = displayIconCode;

    final skyFloor = hourlyStripSkyIconPercent(iconCode);
    final rounded = _roundPrecipProbabilityForDisplay(precipColumnPercent);
    // Suché % — bez zrážok max 30; hodina pred zrážkou 40; jasno 10.
    final int shownPct;
    if (!showRainPrecipColumn && _isClearStripSkyCode(iconCode)) {
      shownPct = 10;
    } else if (!showRainPrecipColumn && rounded < kMinPrecipProbPercent) {
      // Pipeline už nastavila 40 pred zrážkou — nerež na 30.
      shownPct = rounded.clamp(10, 40);
    } else {
      shownPct = math.max(rounded, skyFloor);
    }
    final String precipPercent = '$shownPct%';
    final bool showPrecipAmount =
        showRainPrecipColumn && precipDisplayMm > 0;

    final windWithDirection = _formatWindWithDirection(h.windSpeed?[index], h.windDirection?[index]);

    return _forecastStripCardShell(
      onTap: () => onExpandedChanged(!isExpanded),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: kRowH,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 46,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                timeLabel,
                                style: mono.merge(const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: Colors.white,
                                )),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 52,
                          child: Align(
                            alignment: Alignment.center,
                            child: getWeatherIcon(
                              iconCode,
                              hourTime: h.time[index],
                              daily: daily,
                              size: 46,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        SizedBox(
                          width: 44,
                          child: Align(
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                tempLabel,
                                style: mono.merge(TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: tempColor,
                                )),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: !hasPrecipProbData
                                ? Text(
                                    '—',
                                    style: mono.merge(TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withAlpha(120),
                                    )),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.water_drop_outlined,
                                        size: 14,
                                        color: Color(0xFF81D4FA),
                                      ),
                                      const SizedBox(width: 4),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            precipPercent,
                                            style: mono.merge(const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color.fromRGBO(255, 255, 255, 0.9),
                                              height: 1.1,
                                            )),
                                          ),
                                          if (showPrecipAmount)
                                            Text(
                                              _formatPrecipitation(precipDisplayMm, weatherCode: iconCode),
                                              style: mono.merge(const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFB3E5FC),
                                                height: 1.1,
                                              )),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        SizedBox(
                          width: 82,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                windWithDirection,
                                style: mono.merge(const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color.fromRGBO(255, 255, 255, 0.9),
                                )),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        ),

                        SizedBox(
                          width: 24,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Icon(
                              isExpanded ? Icons.expand_less : Icons.expand_more,
                              size: 20,
                              color: Colors.white.withAlpha(179),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: _buildHourlyDetails(h, index, smoothed, smoothedIndex),
            ),
        ],
      ),
    );
  }

  Widget _buildDaily() {
    final d = weatherData?.daily;
    final h = weatherData?.hourly;
    final current = weatherData?.current;

    if (d == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final n = math.min(kDailyListForecastDays, d.time.length);

    if (_expandedStates.length != n) {
      _expandedStates = List.filled(n, false);
    }

    double? minTemp, maxTemp;
    for (int i = 0; i < n; i++) {
      double? tempMin = d.tempMin?[i];
      double? tempMax = d.tempMax?[i];
      if ((tempMin == null || tempMax == null) && i < d.time.length) {
        final fb = _fallbackDailyTempsFromHourly(d.time[i], h);
        tempMin ??= fb['min'];
        tempMax ??= fb['max'];
      }
      if (tempMin != null) minTemp = minTemp == null ? tempMin : math.min(minTemp, tempMin);
      if (tempMax != null) maxTemp = maxTemp == null ? tempMax : math.max(maxTemp, tempMax);
    }

    final double finalMinTemp = minTemp ?? -10.0;
    final double finalMaxTemp = maxTemp ?? 35.0;
    final double span = math.max(10.0, (finalMaxTemp - finalMinTemp).abs());

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, _kHomeForecastSectionGap),
      sliver: SliverList.builder(
        itemCount: n,
        itemBuilder: (context, i) {
          return RepaintBoundary(
            child: _dailyTile(
              dayIndex: i,
              d: d,
              h: h,
              current: current,
              minTemp: finalMinTemp,
              span: span,
              isExpanded: _expandedStates[i],
              onExpandedChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    for (int j = 0; j < _expandedStates.length; j++) {
                      _expandedStates[j] = j == i;
                    }
                  } else {
                    _expandedStates[i] = false;
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }

  Map<String, double?> _fallbackDailyTempsFromHourly(String dateStr, HourlyForecast? h) {
    if (h == null || h.time.isEmpty || h.temperature == null) {
      return {'min': null, 'max': null};
    }

    double? minT;
    double? maxT;
    final int len = math.min(h.time.length, h.temperature!.length);
    for (int i = 0; i < len; i++) {
      if (!h.time[i].startsWith(dateStr)) continue;
      final t = h.temperature![i];
      if (t == null) continue;
      minT = minT == null ? t : math.min(minT, t);
      maxT = maxT == null ? t : math.max(maxT, t);
    }
    return {'min': minT, 'max': maxT};
  }

  double? _fallbackDailyUvFromHourly(String dateStr, HourlyForecast? h) {
    if (h == null || h.time.isEmpty) return null;
    double? maxUv;
    if (h.uvIndex != null) {
      final int len = math.min(h.time.length, h.uvIndex!.length);
      for (int i = 0; i < len; i++) {
        if (!h.time[i].startsWith(dateStr)) continue;
        final uv = h.uvIndex![i];
        if (uv == null) continue;
        maxUv = maxUv == null ? uv : math.max(maxUv, uv);
      }
    }
    if (maxUv != null) return maxUv;

    for (int i = 0; i < h.time.length; i++) {
      if (!h.time[i].startsWith(dateStr)) continue;
      final uv = _estimatedUvForHourlySlot(h, i);
      if (uv == null) continue;
      maxUv = maxUv == null ? uv : math.max(maxUv, uv);
    }
    return maxUv;
  }

  Widget _buildDailyDetailRow(
    IconData icon1,
    String text1,
    IconData? icon2,
    String? text2, {
    double bottomPadding = 12,
  }) {
    const Color detailIcon = kAppAccentBlueBright;
    const TextStyle detailText = TextStyle(
      color: Color(0xFFE2E8F0),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Icon(icon1, size: 18, color: detailIcon),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text1, style: detailText),
                ),
              ],
            ),
          ),
          Expanded(
            child: icon2 != null && text2 != null
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Icon(icon2, size: 18, color: detailIcon),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(text2, style: detailText),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _dailyTile({
    required int dayIndex,
    required DailyForecast d,
    required HourlyForecast? h,
    required CurrentWeather? current,
    required double minTemp,
    required double span,
    required bool isExpanded,
    required ValueChanged<bool> onExpandedChanged,
  }) {
    const kRowH = 60.0;

    final dt = DateTime.tryParse(d.time[dayIndex]);
    final dayLabel = dt != null ? _weekdaySkLongWithDate(dt) : '--';

    double? max = d.tempMax?[dayIndex];
    double? min = d.tempMin?[dayIndex];
    if ((max == null || min == null) && dayIndex < d.time.length) {
      final fb = _fallbackDailyTempsFromHourly(d.time[dayIndex], h);
      max ??= fb['max'];
      min ??= fb['min'];
    }
    final maxStr = max != null ? '${max.round()}°' : '--°';
    final minStr = min != null ? '${min.round()}°' : '--°';
    final tempText = '$maxStr / $minStr';
    final maxColor = _temperatureScaleColor(max);
    final minColor = _temperatureScaleColor(min);

    final textLength = tempText.length;
    double tempWidth = 68.0;
    if (textLength > 8) {
      tempWidth = 68.0 + (textLength - 8) * 4.0;
    }
    if (textLength > 10) {
      tempWidth = 76.0;
    }

    const dateWidth = 96.0;
    final dateStr = d.time[dayIndex];

    final locTime = _getCurrentLocationTime();
    final dayPrefix = calendarDayPrefix(dateStr);
    final utcOff = weatherData?.utcOffsetSeconds;
    /// Rovnaký 24 h pás ako záložka „24 hodín“ (vrátane RainViewer).
    final stripState = h != null && current != null
        ? _hourlyStripFinalDisplayState(
            h,
            locTime,
            current,
            d,
            utcOff,
            radarNowcast: _radarNowcastContext,
            radarCoverageActive:
                currentCity != null && radarNowcastActiveForCity(currentCity!),
            lightningNearby: _lightningNearby,
          )
        : null;

    final dayInStripWindow = stripState != null &&
        h != null &&
        h.time.asMap().entries.any(
              (e) =>
                  stripState.icons.containsKey(e.key) &&
                  _hourlyIndexOnDailyTile(h, e.key, dayPrefix, utcOff),
            );
    final HourlyStripDisplayState? stripForDay =
        dayInStripWindow ? stripState : null;

    final rainingAtPinNow = dayIndex == 0 &&
        (_radarNowcastContext.pinForecast.wetAtPinNow ||
            _radarNowcastContext.precipNow ||
            _radarNowcastContext.rainAtPinNow);

    final rawApiDailyPrecip = (d.precipSum != null && d.precipSum!.length > dayIndex)
        ? (d.precipSum![dayIndex] ?? 0.0)
        : 0.0;
    final apiDailyPrecip = rawApiDailyPrecip;
    final dailyApiProb = roundPrecipProbPercent(d.precipProbMax?[dayIndex] ?? 0);
    final double apiDailySnow = (d.snowfallSum != null && d.snowfallSum!.length > dayIndex)
        ? (d.snowfallSum![dayIndex] ?? 0.0)
        : 0.0;

    double? meanHourlyCloudForDay;
    final ccList = h?.cloudCover;
    if (ccList != null && h!.time.isNotEmpty) {
      double sumC = 0;
      int nC = 0;
      for (var i = 0; i < h.time.length; i++) {
        if (h.time[i].startsWith(dateStr)) {
          final v = ccList[i];
          if (v != null) {
            sumC += v;
            nC++;
          }
        }
      }
      if (nC > 0) meanHourlyCloudForDay = sumC / nC;
    }

    List<int> displayedDayIcons = const [];
    if (h != null && current != null) {
      final fair = _hourlyFairDisplayIconsForCalendarDay(
        h,
        dateStr,
        current,
        d,
        locTime,
      );
      if (fair != null) {
        displayedDayIcons = dayInStripWindow
            ? _mergeStripIconsIntoDayIconList(
                fair.$2,
                fair.$1,
                stripState,
              )
            : fair.$2;
      }
    }

    final int fallbackDailyCode = d.weatherCode?[dayIndex] ?? 0;

    final bool suppressWetDayIcons = !rainingAtPinNow &&
        shouldSuppressWetDayIconsForDay(
      h,
      dayPrefix,
      apiDailyPrecip,
      apiDailySnow,
      dailyApiProb,
      stripState: stripForDay,
      latchedDailyPrecipMm: 0,
      latchedDailyProb: 0,
      dailyWeatherCode: fallbackDailyCode,
      daysFromToday: dayIndex,
    );

    final showableDayPrecip = dayShowablePrecipForDailyForecast(
      h,
      dateStr,
      daysFromToday: dayIndex,
      stripState: stripForDay,
    );
    final ecmwfDayUiSumMm = ecmwfDayUiPrecipSumMm(h, dateStr);
    final int effectiveDailyProb = dailyPrecipProbForIconIntensity(
      dailyApiProb: dailyApiProb,
      hourlyStripMaxProb: showableDayPrecip.maxProb,
      hourlyDayMaxProb: hourlyDayMaxPrecipProb(h, dateStr),
      daysFromToday: dayIndex,
    );
    final double effectiveDailyPrecipMm = dailyPrecipMmForIconDisplay(
      apiDailyPrecip: apiDailyPrecip,
      hourlySumMm: math.max(
        showableDayPrecip.any ? showableDayPrecip.sumMm : 0.0,
        ecmwfDayUiSumMm,
      ),
      effectiveDailyProb: effectiveDailyProb,
      daysFromToday: dayIndex,
    );

    final morningWeather = _getDayPartWeather(
        dateStr, h, 'morning', d, fallbackDailyCode, effectiveDailyProb, current,
        locTime,
        suppressWetDayIcons: suppressWetDayIcons,
        dailyTotalPrecipMm: effectiveDailyPrecipMm,
        dailyTotalSnowCm: apiDailySnow,
        stripState: stripForDay,
        utcOffsetSeconds: weatherData?.utcOffsetSeconds,
        lightningNearby: _lightningNearby,
        daysFromToday: dayIndex);
    final afternoonWeather = _getDayPartWeather(
        dateStr, h, 'afternoon', d, fallbackDailyCode, effectiveDailyProb, current,
        locTime,
        suppressWetDayIcons: suppressWetDayIcons,
        dailyTotalPrecipMm: effectiveDailyPrecipMm,
        dailyTotalSnowCm: apiDailySnow,
        stripState: stripForDay,
        utcOffsetSeconds: weatherData?.utcOffsetSeconds,
        lightningNearby: _lightningNearby,
        daysFromToday: dayIndex);
    final eveningWeather = _getDayPartWeather(
        dateStr, h, 'evening', d, fallbackDailyCode, effectiveDailyProb, current,
        locTime,
        suppressWetDayIcons: suppressWetDayIcons,
        dailyTotalPrecipMm: effectiveDailyPrecipMm,
        dailyTotalSnowCm: apiDailySnow,
        stripState: stripForDay,
        utcOffsetSeconds: weatherData?.utcOffsetSeconds,
        lightningNearby: _lightningNearby,
        daysFromToday: dayIndex);
    final nightWeather = _getDayPartWeather(
        dateStr, h, 'night', d, fallbackDailyCode, effectiveDailyProb, current,
        locTime,
        suppressWetDayIcons: suppressWetDayIcons,
        dailyTotalPrecipMm: effectiveDailyPrecipMm,
        dailyTotalSnowCm: apiDailySnow,
        stripState: stripForDay,
        utcOffsetSeconds: weatherData?.utcOffsetSeconds,
        lightningNearby: _lightningNearby,
        daysFromToday: dayIndex);

    var dailyMainIconCode = finalizeDailyCardIconCode(
      resolveDailyCardMainIconCode(
        displayedDayIcons: displayedDayIcons,
        fallbackCode: fallbackDailyCode,
        suppressWetDayIcons: suppressWetDayIcons,
        meanHourlyCloudForDay: meanHourlyCloudForDay,
        partIconCodes: [
          morningWeather['iconCode'] as int?,
          afternoonWeather['iconCode'] as int?,
          eveningWeather['iconCode'] as int?,
          nightWeather['iconCode'] as int?,
        ],
        dailyPrecipMm: effectiveDailyPrecipMm,
        dailyPrecipProb: effectiveDailyProb,
      ),
      effectiveDailyProb,
      dailyPrecipMm: effectiveDailyPrecipMm,
      dailySnowCm: apiDailySnow,
      dayAvgTempC: (() {
        final tmax = d.tempMax != null && d.tempMax!.length > dayIndex
            ? d.tempMax![dayIndex]
            : null;
        final tmin = d.tempMin != null && d.tempMin!.length > dayIndex
            ? d.tempMin![dayIndex]
            : null;
        if (tmax != null && tmin != null) return (tmax + tmin) / 2;
        return tmax ?? tmin;
      })(),
    );

    double sumHum = 0, sumPress = 0, sumDew = 0;
    double maxWind = 0.0;
    double maxGusts = 0.0;
    int? windDirForMax;
    int count = 0;

    if (h != null && h.time.isNotEmpty) {
      for (int i = 0; i < h.time.length; i++) {
        if (h.time[i].startsWith(dateStr)) {
          sumHum += h.relativeHumidity?[i] ?? 0;
          sumPress += h.pressure?[i] ?? 0;
          sumDew += h.dewPoint?[i] ?? 0;

          final ws = h.windSpeed?[i] ?? 0;
          if (ws > maxWind) {
            maxWind = ws;
            windDirForMax = h.windDirection?[i]?.round();
          }

          final wg = h.windGusts?[i] ?? 0;
          if (wg > maxGusts) {
            maxGusts = wg;
          }
          count++;
        }
      }
    }

    final avgHum = count > 0 ? (sumHum / count).round() : null;
    final avgPress = count > 0 ? (sumPress / count).round() : null;
    final avgDew = count > 0 ? (sumDew / count).round() : null;

    double windSpd = 0.0;
    double gustSpd = 0.0;
    int? windDir;

    if (d.windSpeedMax != null && d.windSpeedMax!.length > dayIndex && d.windSpeedMax![dayIndex] != null) {
      windSpd = d.windSpeedMax![dayIndex]!;
    } else {
      windSpd = maxWind;
    }

    if (d.windGustsMax != null && d.windGustsMax!.length > dayIndex && d.windGustsMax![dayIndex] != null) {
      gustSpd = d.windGustsMax![dayIndex]!;
    } else {
      gustSpd = maxGusts;
    }

    if (d.windDirectionDominant != null && d.windDirectionDominant!.length > dayIndex && d.windDirectionDominant![dayIndex] != null) {
      windDir = d.windDirectionDominant![dayIndex]!;
    } else {
      windDir = windDirForMax;
    }

    final showablePrecip = dayExpandedPrecipSummary(
      h,
      dayPrefix,
      stripIcons: stripForDay?.icons,
      stripPrecipMm: stripForDay?.precipMm,
      stripProbs: stripForDay?.probs,
      utcOffsetSeconds: utcOff,
    );

    // Práve prší na pine — aktuálny úsek + hlavná ikona musia sedieť s hero / 24 h.
    // Intenzita ikony však podľa denného úhrnu — radar dBZ nesmie dať rain.svg pri 4 mm.
    if (rainingAtPinNow) {
      var liveIcon = applyRadarPrecipEndToHeroIcon(
        61,
        radarCtx: _radarNowcastContext,
        locTime: locTime,
        tempC: current?.temperature,
        precipMm: math.max(0.5, showablePrecip.sumMm),
        precipProb: math.max(60, showablePrecip.maxProb),
      );
      liveIcon = capRadarPrecipIconNoHeavy(
        capPrecipIconByTrustedMm(
          liveIcon,
          trustedMm: math.max(rawApiDailyPrecip, effectiveDailyPrecipMm),
        ),
      );
      final hour = locTime.hour;
      final livePart = (hour >= 6 && hour < 12)
          ? morningWeather
          : (hour >= 12 && hour < 18)
              ? afternoonWeather
              : (hour >= 18 && hour < 23)
                  ? eveningWeather
                  : nightWeather;
      livePart['iconCode'] = liveIcon;
      livePart['icon'] = getWeatherIcon(
        liveIcon,
        size: 38,
        forceDay: hour >= 6 && hour < 18,
        forceNight: hour < 6 || hour >= 23,
      );
      livePart['partSumMm'] = math.max(
        (livePart['partSumMm'] as double?) ?? 0.0,
        0.5,
      );
      dailyMainIconCode = liveIcon;
    }

    final partsPrecipMm = dayPrecipMmFromVisibleDayParts([
      morningWeather,
      afternoonWeather,
      eveningWeather,
      nightWeather,
    ]);
    final partIconCodes = [
      morningWeather['iconCode'] as int?,
      afternoonWeather['iconCode'] as int?,
      eveningWeather['iconCode'] as int?,
      nightWeather['iconCode'] as int?,
    ];
    final partIconsAllDry = dayPartIconCodesAllDry(partIconCodes);
    final footerPrecip = resolveDailyCardFooterPrecip(
      partIconsAllDry: partIconsAllDry && !rainingAtPinNow,
      dailyMainIconCode: dailyMainIconCode,
      apiDailySnow: apiDailySnow,
      expandedSumMm: math.max(
        showablePrecip.sumMm,
        rainingAtPinNow ? 0.5 : 0.0,
      ),
      expandedMaxProb: math.max(
        showablePrecip.maxProb,
        rainingAtPinNow ? 60 : 0,
      ),
      partsSumMm: math.max(partsPrecipMm, rainingAtPinNow ? 0.5 : 0.0),
      hourly: h,
      dateStr: dayPrefix,
      apiDailyPrecip: rawApiDailyPrecip,
      dailyApiProb: dailyApiProb,
      latchedDailyMm: 0,
      latchedDailyProb: 0,
      daysFromToday: dayIndex,
    );
    var displayMm = footerPrecip.mm;
    var footerProb = footerPrecip.prob;
    if (rainingAtPinNow) {
      displayMm = math.max(displayMm, 0.5);
      footerProb = math.max(footerProb, 60);
    }

    if (!rainingAtPinNow &&
        !dailyCardShowsWetPrecip(
      trustedMm: displayMm,
      trustedProb: footerProb,
      snowfallCm: apiDailySnow,
    )) {
      dailyMainIconCode = dailyCardIconDryUnlessTrusted(
        dailyMainIconCode,
        displayMm,
        footerProb,
        cloudCover: meanHourlyCloudForDay,
        snowfallCm: apiDailySnow,
      );
      for (final entry in <(String, Map<String, dynamic>)>[
        ('morning', morningWeather),
        ('afternoon', afternoonWeather),
        ('evening', eveningWeather),
        ('night', nightWeather),
      ]) {
        final part = entry.$2;
        final code = part['iconCode'] as int?;
        if (code == null) continue;
        final dried = dailyCardIconDryUnlessTrusted(
          code,
          displayMm,
          footerProb,
          cloudCover: meanHourlyCloudForDay,
          snowfallCm: apiDailySnow,
        );
        if (dried == code) continue;
        part['iconCode'] = dried;
        part['icon'] = getWeatherIcon(
          dried,
          size: 38,
          forceDay: entry.$1 == 'morning' || entry.$1 == 'afternoon',
          forceNight: entry.$1 == 'night',
        );
      }
    }

    // Ikony podľa čísla v pätičke — radar dBZ nesmie dať rain.svg pri 4,6 mm.
    // partMm nesmie byť vyšší než footer (nafúknuté strip mm).
    for (final entry in <(String, Map<String, dynamic>)>[
      ('morning', morningWeather),
      ('afternoon', afternoonWeather),
      ('evening', eveningWeather),
      ('night', nightWeather),
    ]) {
      final part = entry.$2;
      final code = part['iconCode'] as int?;
      if (code == null) continue;
      final rawPartMm = (part['partSumMm'] as num?)?.toDouble() ?? 0.0;
      final capped = capPrecipIconByTrustedMm(
        code,
        trustedMm: displayMm,
        partMm: math.min(rawPartMm, displayMm),
      );
      if (capped == code) continue;
      part['iconCode'] = capped;
      part['icon'] = getWeatherIcon(
        capped,
        size: 38,
        forceDay: entry.$1 == 'morning' || entry.$1 == 'afternoon',
        forceNight: entry.$1 == 'night',
      );
    }
    dailyMainIconCode = capPrecipIconByTrustedMm(
      dailyMainIconCode,
      trustedMm: displayMm,
    );

    final mainIcon = getWeatherIcon(
      dailyMainIconCode,
      forceDay: true,
      size: 48,
    );

    String precipStr;
    if (!rainingAtPinNow &&
        partIconsAllDry &&
        !kPrecipitationCodes.contains(
            normalizeDisplayWeatherCode(dailyMainIconCode))) {
      precipStr =
          '0 mm\nŠanca: ${_roundPrecipProbabilityForDisplay(footerProb)} %';
    } else if (displayMm >= kMeaningfulPrecipMmPerHour &&
        footerProb >= kMinPrecipProbPercent) {
      precipStr =
          '${_formatPrecipitation(displayMm, weatherCode: dailyMainIconCode)}\nŠanca: ${_roundPrecipProbabilityForDisplay(footerProb)} %';
    } else if (kPrecipitationCodes.contains(dailyMainIconCode) &&
        footerProb >= kMinPrecipProbPercent) {
      precipStr =
          '${displayMm >= kMeaningfulPrecipMmPerHour ? _formatPrecipitation(displayMm, weatherCode: dailyMainIconCode) : '0 mm'}\nŠanca: ${_roundPrecipProbabilityForDisplay(footerProb)} %';
    } else if (rainingAtPinNow) {
      precipStr =
          '${_formatPrecipitation(math.max(displayMm, 0.5), weatherCode: dailyMainIconCode)}\nŠanca: ${_roundPrecipProbabilityForDisplay(math.max(footerProb, 60))} %';
    } else {
      precipStr =
          '0 mm\nŠanca: ${_roundPrecipProbabilityForDisplay(math.max(footerProb, 10))} %';
    }

    String windStr = windSpd > 0 ? 'Vietor: ${windDirectionShort2(windDir)}, ${_currentWindUnit.format(windSpd)}' : 'Vietor: --';
    if (gustSpd > 0) {
      windStr += '\nNárazy do: ${_currentWindUnit.format(gustSpd)}';
    }

    String humStr = avgHum != null ? 'Vlhkosť: $avgHum %' : 'Vlhkosť: -- %';
    String pressStr = avgPress != null ? '$avgPress hPa' : '-- hPa';
    String dewStr = avgDew != null ? 'Rosný bod: $avgDew°C' : 'Rosný bod: --°C';
    final String sunriseStr = 'Východ slnka: ${_formatIsoTimeShort(d.sunrise?[dayIndex])}';
    final String sunsetStr = 'Západ slnka: ${_formatIsoTimeShort(d.sunset?[dayIndex])}';

    double? uvMax = (d.uvIndexMax != null && d.uvIndexMax!.length > dayIndex) ? d.uvIndexMax![dayIndex] : null;
    uvMax ??= _fallbackDailyUvFromHourly(dateStr, h);
    String uvStr = uvMax != null ? 'UV index: ${uvMax.round()}' : 'UV index: --';

    return _forecastStripCardShell(
      onTap: () => onExpandedChanged(!isExpanded),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: kRowH,
            padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
            child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: dateWidth,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                dayLabel,
                                style: mono.merge(const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.15,
                                )),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        SizedBox(
                          width: 56,
                          child: Align(
                            alignment: Alignment.center,
                            child: mainIcon, 
                          ),
                        ),
                        const SizedBox(width: 3),
                        SizedBox(
                          width: tempWidth,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: RichText(
                                text: TextSpan(
                                  style: mono.merge(const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    height: 1.15,
                                  )),
                                  children: [
                                    TextSpan(text: maxStr, style: TextStyle(color: maxColor)),
                                    TextSpan(text: ' / ', style: TextStyle(color: Colors.white.withAlpha(180))),
                                    TextSpan(text: minStr, style: TextStyle(color: minColor)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          flex: 8,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 140), 
                            child: _progressBar(
                              current: max,
                              minTemp: minTemp,
                              span: span,
                              showKnob: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Align(
                            alignment: Alignment.center,
                            child: Icon(
                              isExpanded ? Icons.expand_less : Icons.expand_more,
                              size: 24,
                              color: Colors.white.withAlpha(204),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (isExpanded)
                    Transform.translate(
                      offset: const Offset(0, -8),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Container(
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.only(top: 4, bottom: 4, left: 6, right: 6),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    kAppCardNavyElevated,
                                    kAppCardNavy,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: kAppCardNavyBorder.withValues(alpha: 0.5),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildDayPartColumn(
                                        label: 'Ráno',
                                        icon: morningWeather['icon'],
                                        temp: morningWeather['temp'],
                                      ),
                                      _buildDayPartColumn(
                                        label: 'Poobede',
                                        icon: afternoonWeather['icon'],
                                        temp: afternoonWeather['temp'],
                                      ),
                                      _buildDayPartColumn(
                                        label: 'Večer',
                                        icon: eveningWeather['icon'],
                                        temp: eveningWeather['temp'],
                                      ),
                                      _buildDayPartColumn(
                                        label: 'Noc',
                                        icon: nightWeather['icon'],
                                        temp: nightWeather['temp'],
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Container(
                                      height: 1,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(1),
                                        gradient: LinearGradient(
                                          colors: [
                                            kAppCardNavy.withValues(alpha: 0.0),
                                            kAppAccentBlueBright.withValues(alpha: 0.35),
                                            kAppCardNavy.withValues(alpha: 0.0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      _buildDailyDetailRow(
                                        Icons.wb_twilight_outlined,
                                        sunriseStr,
                                        Icons.nightlight_round,
                                        sunsetStr,
                                        bottomPadding: 6,
                                      ),
                                      _buildDailyDetailRow(
                                        Icons.water_drop_outlined,
                                        precipStr,
                                        Icons.air,
                                        windStr,
                                        bottomPadding: 6,
                                      ),
                                      _buildDailyDetailRow(
                                        Icons.water_drop,
                                        humStr,
                                        Icons.thermostat_outlined,
                                        dewStr,
                                        bottomPadding: 6,
                                      ),
                                      _buildDailyDetailRow(
                                        Icons.speed,
                                        pressStr,
                                        Icons.wb_sunny_outlined,
                                        uvStr,
                                        bottomPadding: 0,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildDayPartColumn({
    required String label,
    required Widget icon,
    required String temp,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFFADC4D4),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: icon,
          ),
          const SizedBox(height: 6),
          Text(
            temp,
            style: mono.merge(const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF1F5F9),
            )),
          ),
        ],
      ),
    );
  }

  Widget _progressBar({
    required double? current,
    required double minTemp,
    required double span,
    bool showKnob = true,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        const h = 10.0;
        final safeSpan = span <= 0 ? 1.0 : span;
        double nx(double v) => ((v - minTemp) / safeSpan).clamp(0.0, 1.0);
        final double? pos = (current == null) ? null : nx(current) * w;

        return SizedBox(
          height: h,
          child: Stack(
            children: [
              Container(
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              if (pos != null)
                Positioned(
                  left: 0,
                  width: math.max(8.0, pos),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFFD54F),
                          Color(0xFFFF9800),
                          Color(0xFFE53935),
                        ],
                      ),
                    ),
                  ),
                ),
              if (pos != null && showKnob)
                Positioned(
                  left: (pos - 6).clamp(0.0, math.max(0.0, w - 12.0)),
                  top: (h - 12) / 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0xFFFF9800),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasData = weatherData != null;

    final (firstHourTemp, firstHourIcon, _, displayCode) = _getFirstHourWeatherInfo();
    // NOTE: Pozadie sa nemení pri prepnutí lokality - konzistentná farba pre všetky lokality
    /*
    final nextAmbient = AppAmbientSnapshot(
      weatherCode: displayCode,
      isDay: _ambientIsDayForWeatherUI(),
    );
    final curAmbient = appAmbientSnapshot.value;
    if (curAmbient.weatherCode != nextAmbient.weatherCode ||
        curAmbient.isDay != nextAmbient.isDay) {
      final code = displayCode;
      final day = nextAmbient.isDay;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        appAmbientSnapshot.value = AppAmbientSnapshot(weatherCode: code, isDay: day);
      });
    }
    */

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) => false,
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              backgroundColor: kAppCardNavy,
              color: accentColor,
              notificationPredicate: (notification) {
                return !_isRefreshing && !isLoading;
              },
              child: _buildContent(
                hasData,
                firstHourTemp,
                displayCode,
                hero: _buildHero(firstHourTemp, firstHourIcon, displayCode),
              ),
            ),
          ),
          // Skrytý WebView v plnej veľkosti karty — radar (mapa+hranice) skôr, než je karta v strome.
          if (_supportsRadarForCity(currentCity)) _buildRadarWarmupHost(),
          // Skrytý WebView — prednačíta mapu výstrah + okresy hneď po štarte.
          if (_supportsVystrahyForCity(currentCity))
            ListenableBuilder(
              listenable: Listenable.merge([
                VystrahyWebViewPreloader.instance,
                appRecentsCoverNotifier,
              ]),
              builder: (context, _) =>
                  VystrahyWebViewPreloader.instance.buildWarmupHost(context),
            ),
        ],
      ),
    );
  }
}
