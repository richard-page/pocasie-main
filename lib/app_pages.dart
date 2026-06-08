part of 'main.dart';

class _AlertTypeSetting {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final String oneSignalTag;

  const _AlertTypeSetting({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.oneSignalTag,
  });
}

class SettingsPage extends StatefulWidget {
  final WindUnit currentWindUnit;
  final bool currentMyLocationEnabled;

  const SettingsPage({
    super.key,
    required this.currentWindUnit,
    required this.currentMyLocationEnabled,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  static final List<_AlertTypeSetting> _alertSettings = <_AlertTypeSetting>[
    const _AlertTypeSetting(
      key: kAlertDailySummaryEnabledKey,
      title: 'Denný súhrn',
      subtitle: 'Ranné zhrnutie počasia',
      icon: Icons.notifications_active_outlined,
      oneSignalTag: 'alert_daily_summary',
    ),
    const _AlertTypeSetting(
      key: kAlertEveningSummaryEnabledKey,
      title: 'Večerný súhrn',
      subtitle: 'Súhrn počasia na večer, noc a nasledujúci deň',
      icon: Icons.nightlight_round,
      oneSignalTag: 'alert_evening_summary',
    ),
    const _AlertTypeSetting(
      key: kAlertHighUvEnabledKey,
      title: 'Vysoký UV index',
      subtitle: 'Upozornenie pred silnejším UV žiarením (hodnota nad 4)',
      icon: Icons.wb_sunny_outlined,
      oneSignalTag: 'alert_high_uv',
    ),
    const _AlertTypeSetting(
      key: kAlertStrongWindEnabledKey,
      title: 'Silný vietor',
      subtitle: 'Upozornenie pred silnými nárazmi vetra (nad približne 50 km/h)',
      icon: Icons.air,
      oneSignalTag: 'alert_strong_wind',
    ),
    _AlertTypeSetting(
      key: kAlertHeavyRainEnabledKey,
      title: 'Výdatný dážď',
      subtitle:
          'Upozornenie pri výdatnom daždi (nad ${kAlertHeavyRainDailyMmThreshold.toStringAsFixed(0)} mm za deň)',
      icon: Icons.water_drop_rounded,
      oneSignalTag: 'alert_heavy_rain',
    ),
    _AlertTypeSetting(
      key: kAlertHeavySnowEnabledKey,
      title: 'Výdatné sneženie',
      subtitle:
          'Upozornenie pri výdatnom snežení (nad ${kAlertHeavySnowDailyCmThreshold.toStringAsFixed(0)} cm za deň)',
      icon: Icons.ac_unit,
      oneSignalTag: 'alert_heavy_snow',
    ),
  ];

  late WindUnit _selectedWindUnit;
  late bool _myLocationEnabled;
  TimeOfDay _dailySummaryTime = LocalTestPushService.fixedDailySummaryTime;
  TimeOfDay _eveningSummaryTime = LocalTestPushService.fixedEveningSummaryTime;
  Map<String, bool> _alertTypeStates = <String, bool>{};
  bool _alertSettingsLoaded = false;
  bool _systemNotificationsEnabled = true;

  static const List<int> _widgetUpdatePresetMinutes = <int>[15, 30, 60, 120];

  int _widgetUpdateMinutes = kHomeWidgetUpdateIntervalMinutesDefault;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedWindUnit = widget.currentWindUnit;
    _myLocationEnabled = widget.currentMyLocationEnabled;
    unawaited(_loadSettingsBootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Po manuálnom zapnutí/vypnutí v systémových nastaveniach načítame stav nanovo.
      unawaited(_loadSettingsBootstrap());
    }
  }

  Future<void> _loadSettingsBootstrap() async {
    try {
      final b = await SettingsManager.getSettingsScreenBootstrap();
      final liveSystemPermission = await LocalTestPushService.areSystemNotificationsEnabled();
      final systemPermission = liveSystemPermission;
      await SettingsManager.setSystemNotificationsEnabled(systemPermission);
      if (!mounted) return;
      setState(() {
        _alertTypeStates = b.alertStates;
        _alertSettingsLoaded = true;
        _systemNotificationsEnabled = systemPermission;
        _dailySummaryTime = b.dailySummary;
        _eveningSummaryTime = b.eveningSummary;
        _widgetUpdateMinutes = b.widgetIntervalMinutes;
      });
    } catch (_) {
      final storedSystemPermission = await SettingsManager.getSystemNotificationsEnabled();
      if (!mounted) return;
      setState(() {
        _alertSettingsLoaded = true;
        _systemNotificationsEnabled = storedSystemPermission;
      });
    }
  }

  /// Po zapnutí / zmene času súhrnu: systém môže otvoriť nastavenia presných alarmov (ak treba), potom znova naplánujeme presný čas.
  Future<void> _androidExactAlarmsAfterSummaryReschedule(Future<void> Function() reschedule) async {
    if (kIsWeb || !Platform.isAndroid) {
      await reschedule();
      return;
    }
    await LocalTestPushService.requestExactAlarmsPermissionAndroid();
    await reschedule();
  }

  Future<void> _setWidgetPreset(int minutes) async {
    await SettingsManager.setHomeWidgetUpdateIntervalMinutes(minutes);
    await rescheduleAndroidHomeWidgetPeriodicWork();
    if (!mounted) return;
    setState(() => _widgetUpdateMinutes = minutes);
  }

  String _fmtTime(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  bool _isAllowedSummaryTime(TimeOfDay t, {required bool evening}) {
    if (t.minute != 0) return false;
    final int startHour =
        evening ? kAlertEveningSummaryHourMin : 6;
    final int endHour =
        evening ? kAlertEveningSummaryHourMax : 10;
    return t.hour >= startHour && t.hour <= endHour;
  }

  Future<void> _pickSummaryTime({required bool evening}) async {
    final current = evening ? _eveningSummaryTime : _dailySummaryTime;
    final options = <TimeOfDay>[
      for (int h = evening ? kAlertEveningSummaryHourMin : 6;
          h <= (evening ? kAlertEveningSummaryHourMax : 10);
          h++)
        TimeOfDay(hour: h, minute: 0),
    ];
    final picked = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: const Color(0xFF2A3848),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: options.map((t) {
              final selected = t.hour == current.hour && t.minute == current.minute;
              return ListTile(
                title: Text(
                  _fmtTime(t),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                trailing: selected ? const Icon(Icons.check, color: Color(0xFF3498DB)) : null,
                onTap: () => Navigator.of(context).pop(t),
              );
            }).toList(),
          ),
        );
      },
    );
    if (picked == null) return;
    if (!_isAllowedSummaryTime(picked, evening: evening)) {
      return;
    }

    if (evening) {
      await SettingsManager.setAlertEveningSummaryTime(picked);
      final enabled = _alertTypeStates[kAlertEveningSummaryEnabledKey] ?? false;
      final lastBody = await SettingsManager.getAlertEveningSummaryLastPushBody();
      if (enabled && lastBody != null && lastBody.isNotEmpty) {
        await LocalTestPushService.scheduleEveningSummaryWithBody(
          enabled: true,
          time: picked,
          body: lastBody,
        );
        await _androidExactAlarmsAfterSummaryReschedule(
          () => LocalTestPushService.scheduleEveningSummaryWithBody(
            enabled: true,
            time: picked,
            body: lastBody,
          ),
        );
      } else {
        await LocalTestPushService.scheduleEveningSummary(enabled: enabled, time: picked);
        if (enabled) {
          await _androidExactAlarmsAfterSummaryReschedule(
            () => LocalTestPushService.scheduleEveningSummary(enabled: true, time: picked),
          );
        }
      }
      if (!mounted) return;
      final persisted = await SettingsManager.getAlertEveningSummaryTime();
      if (!mounted) return;
      setState(() => _eveningSummaryTime = persisted);
    } else {
      await SettingsManager.setAlertDailySummaryTime(picked);
      final enabled = _alertTypeStates[kAlertDailySummaryEnabledKey] ?? false;
      final lastBody = await SettingsManager.getAlertDailySummaryLastPushBody();
      if (enabled && lastBody != null && lastBody.isNotEmpty) {
        await LocalTestPushService.scheduleDailySummaryWithBody(
          enabled: true,
          time: picked,
          body: lastBody,
        );
        await _androidExactAlarmsAfterSummaryReschedule(
          () => LocalTestPushService.scheduleDailySummaryWithBody(
            enabled: true,
            time: picked,
            body: lastBody,
          ),
        );
      } else {
        await LocalTestPushService.scheduleDailySummary(enabled: enabled, time: picked);
        if (enabled) {
          await _androidExactAlarmsAfterSummaryReschedule(
            () => LocalTestPushService.scheduleDailySummary(enabled: true, time: picked),
          );
        }
      }
      if (!mounted) return;
      final persisted = await SettingsManager.getAlertDailySummaryTime();
      if (!mounted) return;
      setState(() => _dailySummaryTime = persisted);
    }

  }

  Future<void> _saveWindUnit(WindUnit unit) async {
    await SettingsManager.setWindUnit(unit);
    if (mounted) {
      setState(() {
        _selectedWindUnit = unit;
      });
    }
  }

  Future<void> _saveMyLocationEnabled(bool value) async {
    await SettingsManager.setMyLocationEnabled(value);
    if (mounted) {
      setState(() {
        _myLocationEnabled = value;
      });
    }
  }

  Future<void> _syncOneSignalAlertPreferences(_AlertTypeSetting setting, bool enabled) async {
    final tags = <String, dynamic>{
      setting.oneSignalTag: enabled ? 'true' : 'false',
    };
    if (setting.key == kAlertHeavyRainEnabledKey) {
      tags['alert_heavy_rain_threshold_mm'] = kAlertHeavyRainDailyMmThreshold.toString();
    } else if (setting.key == kAlertHeavySnowEnabledKey) {
      tags['alert_heavy_snow_threshold_cm'] = kAlertHeavySnowDailyCmThreshold.toString();
    }
    await OneSignal.User.addTags(tags);
  }

  Future<void> _saveAlertTypeEnabled(_AlertTypeSetting setting, bool value) async {
    if (value && !_systemNotificationsEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Najprv povoľte oznámenia pre aplikáciu v systéme.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await SettingsManager.setAlertTypeEnabled(setting.key, value);
    await _syncOneSignalAlertPreferences(setting, value);
    if (setting.key == kAlertDailySummaryEnabledKey) {
      final dailyTime = await SettingsManager.getAlertDailySummaryTime();
      final dailyBody = await SettingsManager.getAlertDailySummaryLastPushBody();
      if (!value) {
        await LocalTestPushService.scheduleDailySummary(enabled: false, time: dailyTime);
      } else if (dailyBody != null && dailyBody.isNotEmpty) {
        await LocalTestPushService.scheduleDailySummaryWithBody(
          enabled: true,
          time: dailyTime,
          body: dailyBody,
        );
        await _androidExactAlarmsAfterSummaryReschedule(
          () => LocalTestPushService.scheduleDailySummaryWithBody(
            enabled: true,
            time: dailyTime,
            body: dailyBody,
          ),
        );
      } else {
        await LocalTestPushService.scheduleDailySummary(enabled: true, time: dailyTime);
        await _androidExactAlarmsAfterSummaryReschedule(
          () => LocalTestPushService.scheduleDailySummary(enabled: true, time: dailyTime),
        );
      }
    }
    if (setting.key == kAlertEveningSummaryEnabledKey) {
      final eveningTime = await SettingsManager.getAlertEveningSummaryTime();
      final eveningBody = await SettingsManager.getAlertEveningSummaryLastPushBody();
      if (!value) {
        await LocalTestPushService.scheduleEveningSummary(enabled: false, time: eveningTime);
      } else if (eveningBody != null && eveningBody.isNotEmpty) {
        await LocalTestPushService.scheduleEveningSummaryWithBody(
          enabled: true,
          time: eveningTime,
          body: eveningBody,
        );
        await _androidExactAlarmsAfterSummaryReschedule(
          () => LocalTestPushService.scheduleEveningSummaryWithBody(
            enabled: true,
            time: eveningTime,
            body: eveningBody,
          ),
        );
      } else {
        await LocalTestPushService.scheduleEveningSummary(enabled: true, time: eveningTime);
        await _androidExactAlarmsAfterSummaryReschedule(
          () => LocalTestPushService.scheduleEveningSummary(enabled: true, time: eveningTime),
        );
      }
    }
    if (setting.key == kAlertHighUvEnabledKey && !value) {
      await LocalTestPushService.cancelHighUvLeadAlert();
      await SettingsManager.setAlertHighUvLastPlannedSlot(null);
    }
    if (setting.key == kAlertStrongWindEnabledKey && !value) {
      await LocalTestPushService.cancelStrongWindLeadAlert();
      await SettingsManager.setAlertStrongWindLastPlannedSlot(null);
    }
    if (setting.key == kAlertHeavyRainEnabledKey && !value) {
      await LocalTestPushService.cancelHeavyRainLeadAlert();
      await SettingsManager.setAlertHeavyRainLastPlannedSlot(null);
    }
    if (setting.key == kAlertHeavySnowEnabledKey && !value) {
      await LocalTestPushService.cancelHeavySnowLeadAlert();
      await SettingsManager.setAlertHeavySnowLastPlannedSlot(null);
    }
    if (setting.key == kAlertEveningSummaryEnabledKey && !value) {
      await LocalTestPushService.cancelEveningSummary();
      await SettingsManager.setAlertEveningSummaryNextAt(null);
    }
    if (!mounted) return;
    setState(() {
      _alertTypeStates[setting.key] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ForecastSubpageScaffold(
      title: 'Nastavenia',
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4551),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.2)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.my_location, color: Color(0xFF3498DB)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Moja lokalita',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Keď je táto funkcia zapnutá, aplikácia pri spustení a po potiahnutí nadol automaticky získa vašu aktuálnu GPS polohu. Ak je vypnutá, používa sa iba posledná vybraná poloha.',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(179),
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Switch(
                              value: _myLocationEnabled,
                              onChanged: (value) async {
                                await _saveMyLocationEnabled(value);
                              },
                              activeThumbColor: const Color(0xFF3498DB),
                              activeTrackColor: const Color(0xFF3498DB).withAlpha(128),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4551),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.widgets_outlined, color: Color(0xFF3498DB), size: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Aktualizácia widgetov',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'Častejšie intervaly znamenajú presnejšie údaje na domovskej obrazovke, ale vyššiu spotrebu batérie.',
                        style: TextStyle(
                          color: Colors.white.withAlpha(165),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Teraz: $_widgetUpdateMinutes min',
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      child: Row(
                        children: [
                          for (var i = 0; i < _widgetUpdatePresetMinutes.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _WidgetPresetMinuteButton(
                                minutes: _widgetUpdatePresetMinutes[i],
                                selected: _widgetUpdateMinutes == _widgetUpdatePresetMinutes[i],
                                onTap: () => _setWidgetPreset(_widgetUpdatePresetMinutes[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4551),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.air_rounded, color: Color(0xFF3498DB)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Jednotky vetra',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A4551),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedWindUnit.symbol,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...WindUnit.values.asMap().entries.map((e) {
                      final unit = e.value;
                      final isFirst = e.key == 0;
                      final isSelected = _selectedWindUnit == unit;
                      return ListTile(
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.fromLTRB(12, isFirst ? 0 : 2, 12, 2),
                        horizontalTitleGap: 8,
                        minVerticalPadding: 0,
                        leading: Radio<WindUnit>(
                          value: unit,
                          // ignore: deprecated_member_use
                          groupValue: _selectedWindUnit,
                          // ignore: deprecated_member_use
                          onChanged: (value) async {
                            if (value != null) {
                              await _saveWindUnit(value);
                            }
                          },
                          fillColor: WidgetStateProperty.resolveWith<Color>(
                            (Set<WidgetState> states) {
                              return Colors.white;
                            },
                          ),
                        ),
                        title: Text(
                          unit.symbol,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF3498DB), size: 20)
                            : null,
                        onTap: () async {
                          await _saveWindUnit(unit);
                        },
                      );
                    }),
                  ],
                ),
              ),

              if (!kIsWeb && Platform.isAndroid)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A4551),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Row(
                          children: [
                            Icon(Icons.battery_saver_outlined, color: Color(0xFF3498DB), size: 22),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Upozornenia a úspora batérie',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'Ak systém aplikáciu príliš šetrí v pozadí, naplánované upozornenia nemusia prísť včas. Tu môžete povoliť výnimku (bez obmedzení batérie) pre Meteo Počasie.',
                          style: TextStyle(
                            color: Colors.white.withAlpha(165),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3498DB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              splashFactory: NoSplash.splashFactory,
                            ).copyWith(
                              overlayColor: WidgetStateProperty.all(Colors.transparent),
                            ),
                            onPressed: () {
                              unawaited(LocalTestPushService.openAndroidReliableNotificationsSettings());
                            },
                            child: const Text(
                              'Otvoriť nastavenia batérie aplikácie',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4551),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.2)),
                ),
                child: !_alertSettingsLoaded
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF3498DB),
                            ),
                          ),
                        ),
                      )
                    : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.warning_amber_rounded, color: Color(0xFF3498DB), size: 20),
                          SizedBox(width: 12),
                          Text(
                            'Typy výstrah',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_systemNotificationsEnabled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A4551),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF5B6777).withAlpha(100),
                                ),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.settings_outlined, size: 15, color: Color(0xFFB8C6D8)),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Upozornenia sú vypnuté',
                                          style: TextStyle(
                                            color: Color(0xFFDCE5F0),
                                            fontSize: 12.4,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 7),
                                  Text(
                                    '1) Prejdite do nastavení',
                                    style: TextStyle(
                                      color: Color(0xFFCFD8E4),
                                      fontSize: 12.2,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '2) Vyberte položku aplikácie a zvoľte Meteo Počasie',
                                    style: TextStyle(
                                      color: Color(0xFFCFD8E4),
                                      fontSize: 12.2,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '3) Kliknite na povolenia aplikácie a povoľte upozornenia',
                                    style: TextStyle(
                                      color: Color(0xFFCFD8E4),
                                      fontSize: 12.2,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...List<Widget>.generate(_alertSettings.length, (index) {
                      final setting = _alertSettings[index];
                      final enabled = _alertTypeStates[setting.key] ?? false;
                      final isDailySummary = setting.key == kAlertDailySummaryEnabledKey;
                      final isEveningSummary = setting.key == kAlertEveningSummaryEnabledKey;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                            child: Row(
                              children: [
                                Icon(setting.icon, color: const Color(0xFF3498DB), size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        setting.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        setting.subtitle,
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(165),
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (isDailySummary || isEveningSummary) ...[
                                        const SizedBox(height: 6),
                                        GestureDetector(
                                          onTap: () => _pickSummaryTime(evening: isEveningSummary),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF3A4551),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Každý deň o ${_fmtTime(isDailySummary ? _dailySummaryTime : _eveningSummaryTime)}',
                                              style: TextStyle(
                                                color: Colors.white.withAlpha(enabled ? 230 : 130),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: enabled,
                                  onChanged: (value) async {
                                    await _saveAlertTypeEnabled(setting, value);
                                  },
                                  activeThumbColor: const Color(0xFF3498DB),
                                  activeTrackColor: const Color(0xFF3498DB).withAlpha(128),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
    );
  }
}

class _WidgetPresetMinuteButton extends StatelessWidget {
  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  const _WidgetPresetMinuteButton({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3498DB) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFF3498DB) : Colors.white.withAlpha(77),
              width: 1.2,
            ),
          ),
          child: Text(
            '$minutes min',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white.withAlpha(217),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShmuCameraMeta {
  final String id;
  final String name;
  final double lat;
  final double lon;

  const _ShmuCameraMeta({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
  });
}

class _ShmuCameraItem {
  final _ShmuCameraMeta meta;
  final String imageUrl;
  final String source;
  final String? provider;
  final String? detailUrl;
  final double distanceKm;

  const _ShmuCameraItem({
    required this.meta,
    required this.imageUrl,
    required this.source,
    this.provider,
    this.detailUrl,
    required this.distanceKm,
  });
}

class _WebcamDetailPage extends StatefulWidget {
  final _ShmuCameraItem camera;

  const _WebcamDetailPage({
    required this.camera,
  });

  @override
  State<_WebcamDetailPage> createState() => _WebcamDetailPageState();
}

class _WebcamDetailPageState extends State<_WebcamDetailPage> {
  Timer? _refreshTimer;
  int _cacheBuster = DateTime.now().millisecondsSinceEpoch;
  late String _currentImageUrl;
  bool _isCameraOnline = true;

  @override
  void initState() {
    super.initState();
    _currentImageUrl = widget.camera.imageUrl;
    unawaited(_refreshCameraImageUrl());
    final refreshInterval = widget.camera.source == 'cz' ? const Duration(minutes: 5) : const Duration(minutes: 2);
    _refreshTimer = Timer.periodic(refreshInterval, (_) {
      unawaited(_refreshCameraImageUrl());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshCameraImageUrl() async {
    if (widget.camera.source == 'cz' && widget.camera.imageUrl.contains('exports.holidayinfo.cz')) {
      if (!mounted) return;
      setState(() {
        _cacheBuster = DateTime.now().millisecondsSinceEpoch;
      });
      return;
    }
    if (widget.camera.detailUrl == null) {
      if (!mounted) return;
      setState(() {
        _cacheBuster = DateTime.now().millisecondsSinceEpoch;
      });
      return;
    }
    try {
      final resp = await http.get(Uri.parse(widget.camera.detailUrl!)).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;

      final html = utf8.decode(resp.bodyBytes);
      final re = widget.camera.source == 'cz'
          ? RegExp(r'https://webcams\.ventusky\.com/data/\d+/\d+/(?:hour|day|month)/[^"\s]+\.jpg(?:\?[^"\s]*)?')
          : RegExp('/data/datawebcam/${widget.camera.meta.id}/[^"\\s]+\\.jpg');
      final match = re.firstMatch(html);
      if (match == null) return;

      final latest = widget.camera.source == 'cz'
          ? match.group(0)!
          : Uri.parse('https://www.shmu.sk').resolve(match.group(0)!).toString();
      if (!mounted) return;
      setState(() {
        _currentImageUrl = latest;
        _cacheBuster = DateTime.now().millisecondsSinceEpoch;
        _isCameraOnline = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cacheBuster = DateTime.now().millisecondsSinceEpoch;
        _isCameraOnline = false;
      });
    }
  }

  String get _imageUrlWithCacheBuster {
    final uri = Uri.parse(_currentImageUrl);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['cb'] = _cacheBuster.toString();
    return uri.replace(queryParameters: qp).toString();
  }

  String get _refreshText {
    return widget.camera.source == 'cz'
        ? 'Zábery sa obnovujú automaticky každých 5-10 minút.'
        : 'Zábery sa obnovujú automaticky každé 2 minúty.';
  }

  void _showCameraInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF2A3848),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_rounded, size: 48, color: Color(0xFF3498DB)),
                    const SizedBox(height: 16),
                    const Text(
                      'Informácie o kamere',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Zobrazuje sa najbližšia ${widget.camera.source == 'cz' ? 'česká' : 'SHMÚ'} kamera podľa zvolenej lokality: ${widget.camera.meta.name}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                    if ((widget.camera.provider ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Zdroj kamery: ${widget.camera.provider}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      _refreshText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF34495E),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          splashFactory: NoSplash.splashFactory,
                        ).copyWith(
                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                        ),
                        child: const Text('Zavrieť', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Icon(Icons.arrow_back, size: 22, color: Colors.white)),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Aktuálne zábery',
              style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.2),
            ),
            const SizedBox(height: 1),
            Text(
              widget.camera.meta.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: _showCameraInfoDialog,
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12, left: 4),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: Icon(Icons.info_outline, size: 20, color: Colors.white)),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.network(
                      _imageUrlWithCacheBuster,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) {
                          if (!_isCameraOnline && mounted) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() => _isCameraOnline = true);
                            });
                          }
                          return child;
                        }
                        return child;
                      },
                      errorBuilder: (_, __, ___) {
                        if (_isCameraOnline && mounted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() => _isCameraOnline = false);
                          });
                        }
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nepodarilo sa načítať obrázok z kamery.',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stav kamery — ${_isCameraOnline ? 'Online' : 'Offline'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isCameraOnline ? const Color(0xFF7CFFB2) : const Color(0xFFFF9A9A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _refreshText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.25,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}



class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _busy = false;
  bool _checkingInternet = false;
  bool _checkingManual = false;
  bool _isOffline = false;

  Future<void> _checkInternetAndContinue() async {
    setState(() {
      _checkingInternet = true;
    });

    final hasInternet = await hasInternetConnection();

    if (!hasInternet) {
      setState(() {
        _isOffline = true;
        _checkingInternet = false;
      });
      return;
    }

    setState(() {
      _checkingInternet = false;
      _isOffline = false;
    });

    await _continueWithLocation();
  }

  Future<void> _continueWithLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _busy = false);
        // ignore: use_build_context_synchronously
        final turnOn = await showLocationAccuracyDialog(context);
        if (turnOn == true) {
          await Geolocator.openLocationSettings();
        }
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        await SettingsManager.setLocationPermissionPromptShown(true);
      }
      if (perm == LocationPermission.deniedForever ||
          (perm != LocationPermission.always && perm != LocationPermission.whileInUse)) {
        if (mounted) setState(() => _busy = false);
        await _chooseLocationManually();
        return;
      }

      Position? pos = await Geolocator.getLastKnownPosition()
          .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
      pos ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.lowest, timeLimit: Duration(seconds: 10)));

      final city = await reverseGeocode(
        pos.latitude,
        pos.longitude,
        resolveTimezone: false,
      );
      if (!mounted || city == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => NotificationPermissionPage(
              city: city,
              myLocationEnabled: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseLocationManually() async {
    if (_busy || _checkingInternet || _checkingManual) return;

    setState(() => _checkingManual = true);
    try {
      // Nevoláme `hasInternetConnection()` pred vyhľadávaním — DNS/proxy často vráti falošné „offline“
      // a používateľ potom vôbec neuvidí výber mesta; samotné API pri výpadku aj tak zlyhá.
      // ignore: use_build_context_synchronously
      final city = await Navigator.of(context)
          .push<GeoCity>(MaterialPageRoute(builder: (_) => const CitySearchPage()));
      if (!mounted || city == null) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => NotificationPermissionPage(
            city: city,
            myLocationEnabled: false,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _checkingManual = false);
    }
  }

  void _retryInternetCheck() async {
    setState(() {
      _isOffline = false;
      _checkingInternet = true;
    });

    await Future.delayed(const Duration(milliseconds: 400));

    final hasInternet = await hasInternetConnection();

    if (mounted) {
      if (hasInternet) {
        setState(() {
          _isOffline = false;
          _checkingInternet = false;
        });
      } else {
        setState(() {
          _isOffline = true;
          _checkingInternet = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isOffline) {
      return OfflineScreen(
        onRetry: _retryInternetCheck,
        isOnboarding: true,
      );
    }

    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    'Meteo Počasie',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),

                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(38),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withAlpha(76),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.location_on,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: const Text(
                      'Povoľte polohu pre presnú predpoveď',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: const Text(
                      'Pre presnú predpoveď potrebujeme vedieť, kde sa nachádzate. Povoľte používanie polohy alebo si lokalitu vyberte manuálne v aplikácii.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: Color(0xFFEFF6FF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy || _checkingInternet || _checkingManual
                          ? null
                          : _checkInternetAndContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3498DB),
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        splashFactory: NoSplash.splashFactory,
                      ).copyWith(
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                      child: _busy || _checkingInternet
                          ? const Text(
                              'Spracovávam...',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Pokračovať',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy || _checkingInternet || _checkingManual
                        ? null
                        : _chooseLocationManually,
                    style: TextButton.styleFrom(
                      splashFactory: NoSplash.splashFactory,
                    ).copyWith(
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                    ),
                    child: Text(
                      _checkingManual ? 'Otváram výber lokality...' : 'Zadať lokalitu manuálne',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  SizedBox(height: bottomPad + 24),
                ],
              ),
            ),
          ),
    );
  }
}

class NotificationPermissionPage extends StatefulWidget {
  final GeoCity city;

  /// Po manuálnom výbere mesta musí byť false, aby sa po vstupe do appky nevolalo GPS znova.
  final bool myLocationEnabled;

  const NotificationPermissionPage({
    super.key,
    required this.city,
    this.myLocationEnabled = true,
  });

  @override
  State<NotificationPermissionPage> createState() => _NotificationPermissionPageState();
}

class _NotificationPermissionPageState extends State<NotificationPermissionPage> {
  bool _isAllowing = false;
  bool _isSkipping = false;
  bool get _isProcessing => _isAllowing || _isSkipping;

  Future<void> _completeOnboardingAndNavigate({
    required GeoCity city,
    required bool myLocationEnabled,
  }) async {
    await SettingsManager.finishOnboardingPersist(
      city: city,
      myLocationEnabled: myLocationEnabled,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WeatherPage(initialCity: city),
      ),
    );
  }

  Future<void> _enableNotifications() async {
    if (_isProcessing) return;
    setState(() {
      _isAllowing = true;
    });

    try {
      final permissionResult = await OneSignal.Notifications.requestPermission(true);
      await SettingsManager.setSystemNotificationsEnabled(permissionResult);

      await _completeOnboardingAndNavigate(city: widget.city, myLocationEnabled: widget.myLocationEnabled);

      // Neblokuj vstup do appky pomalšími systémovými/SDK operáciami.
      unawaited(Future<void>(() async {
        OneSignal.User.addTags({
          "city": widget.city.name,
          "notifications_enabled": permissionResult ? "true" : "false"
        });
      }));
    } catch (e) {
      await SettingsManager.setSystemNotificationsEnabled(false);
      await _completeOnboardingAndNavigate(city: widget.city, myLocationEnabled: widget.myLocationEnabled);
    } finally {
      if (mounted) {
        setState(() {
          _isAllowing = false;
        });
      }
    }
  }

  Future<void> _skipNotifications() async {
    if (_isProcessing) return;
    setState(() {
      _isSkipping = true;
    });

    try {
      await SettingsManager.setSystemNotificationsEnabled(false);
      OneSignal.User.addTags({"notifications_enabled": "false"});
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isSkipping = false);
    _showNotificationSettingsHintDialog();
  }

  /// Po „Teraz nie“ — krátky návod ako zapnúť oznámenia v systéme (bez druhého systémového dialógu).
  void _showNotificationSettingsHintDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withAlpha(153),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF2C3E50),
          surfaceTintColor: Colors.transparent,
          elevation: 16,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Color(0xFF243341),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(38),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withAlpha(102),
                            width: 2,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.notifications_none,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nenechajte si ujsť dôležité upozornenia',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _buildNotificationHintStep(
                        number: 1,
                        text: 'Prejdite do nastavení',
                      ),
                      const SizedBox(height: 12),
                      _buildNotificationHintStep(
                        number: 2,
                        text: 'Vyberte položku aplikácie a zvoľte Meteo Počasie',
                      ),
                      const SizedBox(height: 12),
                      _buildNotificationHintStep(
                        number: 3,
                        text: 'Kliknite na povolenia aplikácie a povoľte upozornenia',
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            unawaited(_completeOnboardingAndNavigate(
                              city: widget.city,
                              myLocationEnabled: widget.myLocationEnabled,
                            ));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3498DB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            surfaceTintColor: Colors.transparent,
                            splashFactory: NoSplash.splashFactory,
                          ).copyWith(
                            overlayColor: WidgetStateProperty.all(Colors.transparent),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Pokračovať do aplikácie',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationHintStep({
    required int number,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF243341).withAlpha(102),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withAlpha(38),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF3498DB),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(51),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    'Meteo Počasie',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(38),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withAlpha(76),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.notifications_active,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: const Text(
                      'Nenechajte si ujsť dôležité zmeny počasia',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: const Text(
                      'Povoľte oznámenia — budeme vás informovať o výstrahách, silnom vetre, daždi alebo snežení vo vašej lokalite.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _enableNotifications,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3498DB),
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        shadowColor: Colors.transparent,
                        surfaceTintColor: Colors.transparent,
                        splashFactory: NoSplash.splashFactory,
                      ).copyWith(
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                      child: _isAllowing
                          ? const Text(
                              'Spracovávam...',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Povoliť notifikácie',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isProcessing ? null : _skipNotifications,
                    style: TextButton.styleFrom(
                      splashFactory: NoSplash.splashFactory,
                    ).copyWith(
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                    ),
                    child: Text(
                      _isSkipping ? 'Spracovávam...' : 'Teraz nie',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  SizedBox(height: bottomPad + 24),
                ],
              ),
            ),
          ),
    );
  }
}



class DailyPollen {
  final String dateStr;
  final double? birch;
  final double? alder;
  final double? grass;
  final double? mugwort;
  final double? ragweed;
  final double? olive;

  DailyPollen({
    required this.dateStr,
    this.birch,
    this.alder,
    this.grass,
    this.mugwort,
    this.ragweed,
    this.olive,
  });
}

class PollenForecastPage extends StatelessWidget {
  final GeoCity city;
  final AirQualityData aqiData;

  const PollenForecastPage({super.key, required this.city, required this.aqiData});

  Color _getPollenColor(int level) {
    switch (level) {
      case 1: return const Color(0xFFA6D05E); 
      case 2: return const Color(0xFFE9B54A); 
      case 3: return const Color(0xFFE6743A); 
      case 4: return const Color(0xFFB5235A); 
      case 0:
      default: return Colors.white30; 
    }
  }

  String _getPollenLabel(int level) {
    switch (level) {
      case 1: return 'Nízka';
      case 2: return 'Stredná';
      case 3: return 'Vysoká';
      case 4: return 'Veľmi vysoká';
      case 0:
      default: return 'Žiadna';
    }
  }

  int _getPollenLevel(double? grains) {
    if (grains == null || grains < 1) return 0;
    if (grains < 15) return 1;
    if (grains < 50) return 2;
    if (grains < 150) return 3;
    return 4;
  }

  String _formatPollenDate(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return '--';
    const w = ['Pondelok', 'Utorok', 'Streda', 'Štvrtok', 'Piatok', 'Sobota', 'Nedeľa'];
    return '${w[dt.weekday - 1]}, ${dt.day}. ${dt.month}.';
  }

  List<DailyPollen> _getDailyPollen(AirQualityData data) {
    if (data.time == null || data.time!.isEmpty) return [];

    Map<String, DailyPollen> dailyMap = {};

    double? maxVal(double? a, double? b) {
      if (a == null) return b;
      if (b == null) return a;
      return math.max(a, b);
    }

    for (int i = 0; i < data.time!.length; i++) {
      String dateStr = data.time![i].split('T')[0];

      double? currentBirch = data.birch != null && data.birch!.length > i ? data.birch![i] : null;
      double? currentAlder = data.alder != null && data.alder!.length > i ? data.alder![i] : null;
      double? currentGrass = data.grass != null && data.grass!.length > i ? data.grass![i] : null;
      double? currentMugwort = data.mugwort != null && data.mugwort!.length > i ? data.mugwort![i] : null;
      double? currentRagweed = data.ragweed != null && data.ragweed!.length > i ? data.ragweed![i] : null;
      double? currentOlive = data.olive != null && data.olive!.length > i ? data.olive![i] : null;

      if (!dailyMap.containsKey(dateStr)) {
        dailyMap[dateStr] = DailyPollen(
          dateStr: dateStr,
          birch: currentBirch,
          alder: currentAlder,
          grass: currentGrass,
          mugwort: currentMugwort,
          ragweed: currentRagweed,
          olive: currentOlive,
        );
      } else {
        DailyPollen existing = dailyMap[dateStr]!;
        dailyMap[dateStr] = DailyPollen(
          dateStr: dateStr,
          birch: maxVal(existing.birch, currentBirch),
          alder: maxVal(existing.alder, currentAlder),
          grass: maxVal(existing.grass, currentGrass),
          mugwort: maxVal(existing.mugwort, currentMugwort),
          ragweed: maxVal(existing.ragweed, currentRagweed),
          olive: maxVal(existing.olive, currentOlive),
        );
      }
    }

    return dailyMap.values.toList();
  }

  void _showLegend(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF2A3848),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.spa_outlined, size: 48, color: Color(0xFF3498DB)),
                    const SizedBox(height: 16),
                    const Text(
                      'Legenda úrovne peľu',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildLegendRow('Žiadna', Colors.white30),
                    _buildLegendRow('Nízka', const Color(0xFFA6D05E)),
                    _buildLegendRow('Stredná', const Color(0xFFE9B54A)),
                    _buildLegendRow('Vysoká', const Color(0xFFE6743A)),
                    _buildLegendRow('Veľmi vysoká', const Color(0xFFB5235A)),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF34495E),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          splashFactory: NoSplash.splashFactory,
                        ).copyWith(
                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                        ),
                        child: const Text('Zavrieť', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegendRow(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0, left: 16),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildAllergenRow(String name, double? grains) {
    final level = _getPollenLevel(grains);
    final color = _getPollenColor(level);
    final label = _getPollenLabel(level);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: level > 0 ? color.withAlpha(38) : Colors.white.withAlpha(12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.eco_rounded, 
                size: 18, 
                color: level > 0 ? color : Colors.white38
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name, 
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: level > 0 ? color : Colors.white54,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 14),
          Row(
            children: List.generate(4, (index) {
              return Container(
                width: 12,
                height: 5,
                margin: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(
                  color: index < level ? color : Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          )
        ],
      ),
    );
  }

  Widget _buildDayCard(DailyPollen dayData) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0x15FFFFFF), 
        border: Border.all(color: const Color(0x28FFFFFF)), 
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(38),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withAlpha(38), width: 1))
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF81D4FA)),
                  const SizedBox(width: 10),
                  Text(
                    _formatPollenDate(dayData.dateStr),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildAllergenRow('Breza', dayData.birch),
            _buildAllergenRow('Olša', dayData.alder),
            _buildAllergenRow('Tráva', dayData.grass),
            _buildAllergenRow('Palina', dayData.mugwort),
            _buildAllergenRow('Ambrózia', dayData.ragweed),
            _buildAllergenRow('Oliva', dayData.olive),
            _buildAllergenRow('Lieska', null),
            _buildAllergenRow('Dub', null),
            _buildAllergenRow('Jaseň', null),
            _buildAllergenRow('Skorocel', null),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dailyPollen = _getDailyPollen(aqiData).take(3).toList(); 
    final bool hasData = dailyPollen.isNotEmpty;

    return ForecastSubpageScaffold(
      title: 'Predpoveď peľu',
      actions: [
        GestureDetector(
          onTap: () => _showLegend(context),
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12, left: 4),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Icon(Icons.info_outline, size: 20, color: Colors.white)),
          ),
        ),
      ],
      body: hasData
          ? ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              itemCount: dailyPollen.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24, left: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        city.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  );
                }
                return _buildDayCard(dailyPollen[index - 1]);
              },
            )
          : Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.spa_outlined, size: 64, color: Colors.white.withAlpha(128)),
                    const SizedBox(height: 24),
                    Text(
                      city.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Pre túto lokalitu nie sú bohužiaľ dostupné údaje o peľoch.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Pinned header s presne rovnakou farbou ako forecastSectionBackground
// ignore: unused_element
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 48.0;
  @override
  double get maxExtent => 48.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: 48,
      color: const Color(0xFF2A3848), // kAmbientBlendColor = forecastSectionBackground
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) => false;
}

class CitySearchPage extends StatefulWidget {
  const CitySearchPage({super.key});
  @override
  State<CitySearchPage> createState() => _CitySearchPageState();
}

class _CitySearchPageState extends State<CitySearchPage> {
  final TextEditingController _c = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<GeoCity> _results = <GeoCity>[];
  List<GeoCity> _searchHistory = <GeoCity>[];
  bool _loading = false;
  bool _editMode = false;
  Timer? _debounce;

  /// Middle dot — v zdroji bývalo pokazené UTF-8 (zobrazilo sa ako „â€““).
  static const String _citySubtitleSep = ' \u00B7 ';

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    _c.addListener(_onChanged);
    _loadSearchHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.removeListener(_onChanged);
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? historyJson = prefs.getStringList(kSearchHistoryKey);
    if (historyJson != null) {
      setState(() {
        _searchHistory = historyJson
            .map((e) {
              try {
                return GeoCity.fromGeoJson(json.decode(e));
              } catch (_) {
                return null;
              }
            })
            .whereType<GeoCity>()
            .toList();
      });
    }
  }

  Future<void> _saveSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyJson = _searchHistory.map((e) => json.encode(e.toGeoJson())).toList();
    await prefs.setStringList(kSearchHistoryKey, historyJson);
  }

  void _addToSearchHistory(GeoCity city) {
    _searchHistory.removeWhere((existingCity) =>
        existingCity.name == city.name &&
        existingCity.countryCode == city.countryCode &&
        (existingCity.lat - city.lat).abs() < 0.001 &&
        (existingCity.lon - city.lon).abs() < 0.001);

    setState(() {
      _searchHistory.insert(0, city);
      if (_searchHistory.length > 20) {
        _searchHistory.removeLast();
      }
    });
    _saveSearchHistory();
  }

  void _removeFromHistory(GeoCity city) {
    setState(() {
      _searchHistory.remove(city);
    });
    _saveSearchHistory();
  }

  void _toggleEditMode() {
    setState(() {
      _editMode = !_editMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showHistory = _c.text.isEmpty && _searchHistory.isNotEmpty;
    final bool showEmptyState = _c.text.isEmpty && _searchHistory.isEmpty;
    final bool showResults = _c.text.isNotEmpty;

    return ForecastSubpageScaffold(
      title: 'Vyhľadávanie miest',
      wrapBodyInGlass: false,
      leading: GestureDetector(
          onTap: () {
            if (_editMode) {
              _toggleEditMode();
            } else {
              Navigator.of(context).maybePop();
            }
          },
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(_editMode ? Icons.close : Icons.arrow_back, size: 22, color: Colors.white),
            ),
          ),
        ),
      actions: [
        if (showHistory)
          GestureDetector(
            onTap: _toggleEditMode,
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _editMode ? const Color(0xFF3498DB) : const Color.fromRGBO(255, 255, 255, 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.delete_outline, size: 22, color: Colors.white),
              ),
            ),
          ),
      ],
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.1)),
              boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.2), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: TextField(
              controller: _c,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                if (_results.isNotEmpty) _choose(_results.first);
              },
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Zadajte názov mesta...',
                hintStyle: const TextStyle(color: Color.fromRGBO(255, 255, 255, 0.6)),
                prefixIcon: const Icon(Icons.search, size: 24, color: Color.fromRGBO(255, 255, 255, 0.6)),
                suffixIcon: _c.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _c.clear();
                          setState(() {
                            _results = <GeoCity>[];
                          });
                        },
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: Center(
                          child: Icon(Icons.close, size: 18, color: Colors.white.withAlpha(153)),
                        ),
                        ),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3498DB)),
            ),
          Expanded(
            child: _forecastGlassBody(
              child: Builder(
                builder: (context) {
                  if (showEmptyState) {
                    return _buildEmptyState();
                  } else if (showHistory) {
                    return _buildHistoryList();
                  } else if (showResults) {
                    return _buildSearchResults();
                  } else {
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_searchHistory.isEmpty) return _buildEmptyState(message: 'Žiadna história vyhľadávania.');

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: Colors.white70),
              SizedBox(width: 8),
              Text('Naposledy hľadané', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: _searchHistory.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = _searchHistory[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4551),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (!_editMode) {
                        _choose(c);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A4551),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Icon(Icons.history, size: 16, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 20,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      c.name,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white, height: 1.2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                SizedBox(
                                  height: 16,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      [c.admin1, c.country].where((e) => e.isNotEmpty).join(_citySubtitleSep),
                                      style: const TextStyle(fontSize: 12, color: Color.fromRGBO(255, 255, 255, 0.7), height: 1.1),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_editMode)
                            GestureDetector(
                              onTap: () => _removeFromHistory(c),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color.fromRGBO(255, 255, 255, 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(Icons.delete_outline, size: 18, color: Colors.white70),
                                ),
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_results.isEmpty) {
      return _buildEmptyState(message: 'Nenašli sa žiadne výsledky.');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final c = _results[i];

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF3A4551),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _choose(c),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A3848),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(_flag(c.countryCode), style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 20,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              c.name,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white, height: 1.2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          height: 16,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              [c.admin1, c.country].where((e) => e.isNotEmpty).join(_citySubtitleSep),
                              style: const TextStyle(fontSize: 12, color: Color.fromRGBO(255, 255, 255, 0.7), height: 1.1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

  Widget _buildEmptyState({String message = 'Zadajte názov mesta a vyberte z ponuky.'}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: Icon(Icons.search, size: 48, color: Color.fromRGBO(255, 255, 255, 0.6)),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Color.fromRGBO(255, 255, 255, 0.6), fontSize: 15, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _choose(GeoCity c) {
    _addToSearchHistory(c);
    Navigator.of(context).pop<GeoCity>(c);
  }

  Future<void> _search(String q) async {
    try {
      setState(() => _loading = true);
      final uri = Uri.parse('$kGeoApi/search?name=${Uri.encodeComponent(q)}&count=24&language=sk&format=json');
      final r = await http.get(uri).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final data = json.decode(r.body);
        final raw = (data['results'] as List?) ?? [];
        final filteredRaw = _filterGhostGeocodeRows(raw);
        final List<GeoCity> cities =
            filteredRaw.map((e) => GeoCity.fromGeoJson(e)).toList();
        final Map<String, GeoCity> uniqueByDisplayKey = {};
        for (final c in cities) {
          final key = _cityDisplayKey(c);
          final prev = uniqueByDisplayKey[key];
          if (prev == null || (c.population ?? 0) > (prev.population ?? 0)) {
            uniqueByDisplayKey[key] = c;
          }
        }
        final mergedCities = _mergeNearDuplicateCities(uniqueByDisplayKey.values.toList());
        final normalizedQuery = _normalizeSearchPart(q);
        final relevantCities = mergedCities
            .where((c) => _isRelevantCityForQuery(c, normalizedQuery))
            .toList();
        setState(() => _results = relevantCities);
      } else {
        setState(() => _results = <GeoCity>[]);
      }
    } catch (_) {
      setState(() => _results = <GeoCity>[]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final q = _c.text.trim();
      if (q.isEmpty) {
        setState(() => _results = <GeoCity>[]);
        return;
      }
      await _search(q);
    });
  }

  String _flag(String code) => code.length == 2
      ? String.fromCharCodes([
          0x1F1E6 - 'A'.codeUnitAt(0) + code.toUpperCase().codeUnitAt(0),
          0x1F1E6 - 'A'.codeUnitAt(0) + code.toUpperCase().codeUnitAt(1),
        ])
      : '';

  String _cityDisplayKey(GeoCity c) {
    return [
      _normalizeSearchPart(c.name),
      _normalizeSearchPart(c.admin2),
      _normalizeSearchPart(c.admin1),
      _normalizeSearchPart(c.country),
      _normalizeSearchPart(c.countryCode),
      // rozlíši napr. dve Hlohovce v SR bez zlučovania do jedného riadku
      (c.lat * 1e5).round(),
      (c.lon * 1e5).round(),
    ].join('|');
  }

  /// Druhý stupeň deduplikácie pre API varianty typu `Plzeň` vs `Plzen`:
  /// rovnaký názov (bez diakritiky), rovnaký kraj/štát a takmer rovnaké súradnice.
  List<GeoCity> _mergeNearDuplicateCities(List<GeoCity> input) {
    const double maxLatDiff = 0.25; // ~27 km
    const double maxLonDiff = 0.25; // ~17-20 km v našich zem. šírkach

    final Map<String, List<GeoCity>> groups = <String, List<GeoCity>>{};
    for (final c in input) {
      final key = [
        _normalizeSearchPart(c.name),
        _normalizeSearchPart(c.admin1),
        _normalizeSearchPart(c.countryCode),
      ].join('|');
      groups.putIfAbsent(key, () => <GeoCity>[]).add(c);
    }

    final List<GeoCity> out = <GeoCity>[];
    for (final group in groups.values) {
      GeoCity? selected;
      for (final c in group) {
        if (selected == null) {
          selected = c;
          continue;
        }
        final isNear = (selected.lat - c.lat).abs() <= maxLatDiff &&
            (selected.lon - c.lon).abs() <= maxLonDiff;
        if (!isNear) {
          out.add(c);
          continue;
        }

        final selectedPop = selected.population ?? 0;
        final candidatePop = c.population ?? 0;
        if (candidatePop > selectedPop) {
          selected = c;
          continue;
        }
        if (candidatePop == selectedPop &&
            !_hasDiacritics(selected.name) &&
            _hasDiacritics(c.name)) {
          // Ak je všetko rovnaké, preferujeme názov s diakritikou (`Plzeň` pred `Plzen`).
          selected = c;
          continue;
        }
      }
      if (selected != null) out.add(selected);
    }
    return out;
  }

  bool _hasDiacritics(String value) => _foldDiacritics(value) != value;

  /// Open‑Meteo/GeoNames občas vráti druhý riadok so zhodným [name] + [country_code], ale bez obyvateľov,
  /// typ PPL a iným [admin3] ako názov — typicky ide o chybu v DB (nie samostatné sídlo).
  List<Map<String, dynamic>> _filterGhostGeocodeRows(List<dynamic> rawList) {
    final raw = <Map<String, dynamic>>[];
    for (final item in rawList) {
      if (item is Map<String, dynamic>) {
        raw.add(item);
      } else if (item is Map) {
        raw.add(Map<String, dynamic>.from(item));
      }
    }

    int populationOf(Map<String, dynamic> e) => (e['population'] as num?)?.toInt() ?? 0;

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final e in raw) {
      final name = (e['name'] ?? '').toString().trim().toLowerCase();
      final cc = (e['country_code'] ?? '').toString();
      if (name.isEmpty || cc.length != 2) continue;
      groups.putIfAbsent('$cc|$name', () => []).add(e);
    }

    final skipIds = <int>{};
    for (final group in groups.values) {
      if (group.length < 2) continue;

      final sorted = [...group]..sort((a, b) => populationOf(b).compareTo(populationOf(a)));
      final strongest = sorted.first;
      final strongPop = populationOf(strongest);
      if (strongPop < 400) continue;

      for (final weak in sorted.skip(1)) {
        if (!_isGhostTwinGeocodeRow(weak, strongPop)) continue;
        final oid = weak['id'];
        final wid = oid is int ? oid : (oid is num ? oid.toInt() : null);
        if (wid != null) skipIds.add(wid);
      }
    }

    return raw.where((e) {
      final oid = e['id'];
      final id = oid is int ? oid : (oid is num ? oid.toInt() : null);
      return id == null || !skipIds.contains(id);
    }).toList();
  }

  bool _isGhostTwinGeocodeRow(Map<String, dynamic> weak, int strongPopulation) {
    final weakPop = (weak['population'] as num?)?.toInt();
    if (weakPop != null && weakPop > 0) return false;

    final feature = (weak['feature_code'] ?? '').toString();
    if (feature != 'PPL') return false;

    final name = (weak['name'] ?? '').toString().trim().toLowerCase();
    final admin3 = (weak['admin3'] ?? '').toString().trim().toLowerCase();
    if (admin3.isEmpty || admin3 == name) return false;

    return strongPopulation >= 400;
  }

  bool _isRelevantCityForQuery(GeoCity city, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;

    final compactQuery = normalizedQuery.replaceAll(' ', '');
    final fields = <String>[
      _normalizeSearchPart(city.name),
      _normalizeSearchPart(city.admin2),
      _normalizeSearchPart(city.admin1),
      _normalizeSearchPart(city.country),
    ].where((f) => f.isNotEmpty).toList();

    bool tokenStartsWithQuery(String field) {
      if (field.startsWith(normalizedQuery)) return true;
      final tokens = field.split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty);
      for (final token in tokens) {
        if (token.startsWith(compactQuery)) return true;
      }
      return false;
    }

    for (final field in fields) {
      if (tokenStartsWithQuery(field)) return true;
    }

    // Pri veľmi krátkom dopyte povoľ jemnejšie matchovanie (aby nepadla použiteľnosť).
    if (compactQuery.length <= 3) {
      for (final field in fields) {
        if (field.contains(compactQuery)) return true;
      }
    }

    return false;
  }

  String _normalizeSearchPart(String v) {
    final x = _foldDiacritics(v).toLowerCase().trim();
    return x.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _foldDiacritics(String input) {
    const map = <String, String>{
      'á': 'a', 'ä': 'a', 'č': 'c', 'ď': 'd', 'é': 'e', 'ě': 'e', 'í': 'i',
      'ĺ': 'l', 'ľ': 'l', 'ň': 'n', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'ř': 'r',
      'ŕ': 'r', 'š': 's', 'ť': 't', 'ú': 'u', 'ů': 'u', 'ü': 'u', 'ý': 'y', 'ž': 'z',
      'Á': 'A', 'Ä': 'A', 'Č': 'C', 'Ď': 'D', 'É': 'E', 'Ě': 'E', 'Í': 'I',
      'Ĺ': 'L', 'Ľ': 'L', 'Ň': 'N', 'Ó': 'O', 'Ô': 'O', 'Ö': 'O', 'Ř': 'R',
      'Ŕ': 'R', 'Š': 'S', 'Ť': 'T', 'Ú': 'U', 'Ů': 'U', 'Ü': 'U', 'Ý': 'Y', 'Ž': 'Z',
    };
    final sb = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }
}


class OfflineScreen extends StatelessWidget {
  final VoidCallback onRetry;
  final bool isOnboarding;
  final bool isRetrying;

  const OfflineScreen({
    super.key,
    required this.onRetry,
    this.isOnboarding = false,
    this.isRetrying = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
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
                    Icons.wifi_off,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Žiadne internetové pripojenie',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isOnboarding
                    ? 'Pre zobrazenie počasia potrebujete internetové pripojenie.'
                    : 'Aplikácia potrebuje internet na načítanie najnovších údajov o počasí.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isRetrying ? null : onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    splashFactory: NoSplash.splashFactory,
                  ).copyWith(
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    elevation: WidgetStateProperty.all(0),
                    shadowColor: WidgetStateProperty.all(Colors.transparent),
                    surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
                  ),
                  child: isRetrying
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: body,
    );
  }
}

class FullscreenRadarPage extends StatelessWidget {
  final WebViewController controller;

  const FullscreenRadarPage({
    super.key,
    required this.controller,
  });

  void _closeRadar(BuildContext context) {
    controller.runJavaScript('if(window.setFullscreen) window.setFullscreen(false);');

    Future.delayed(const Duration(milliseconds: 60), () {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeRadar(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Meteo Radar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
          centerTitle: true,
          leading: GestureDetector(
            onTap: () => _closeRadar(context),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: Icon(Icons.arrow_back, size: 22, color: Colors.white)),
            ),
          ),
          actions: [
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return Center(
                      child: Material(
                        type: MaterialType.transparency,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A3848),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.info_outline, size: 48, color: Color(0xFF3498DB)),
                                const SizedBox(height: 16),
                                const Text(
                                  'Zdroj dát',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Radarové snímky sú spracovávané z voľno dostupných dát siete Slovenského hydrometeorologického ústavu (SHMÚ).',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Blesky: EUMETSAT',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () => launchUrl(Uri.parse('https://www.eumetsat.int')),
                                  child: const Text(
                                    'https://www.eumetsat.int',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF3498DB),
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF34495E),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          elevation: 0,
                                          shadowColor: Colors.transparent,
                                          surfaceTintColor: Colors.transparent,
                                          splashFactory: NoSplash.splashFactory,
                                        ).copyWith(
                                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                                        ),
                                        child: const Text('Zavrieť', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          openUrl('https://www.shmu.sk');
                                          Navigator.of(context).pop();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF3498DB),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          elevation: 0,
                                          shadowColor: Colors.transparent,
                                          surfaceTintColor: Colors.transparent,
                                          splashFactory: NoSplash.splashFactory,
                                        ).copyWith(
                                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                                        ),
                                        child: const Text('Web SHMÚ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12, left: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4551),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: Icon(Icons.info_outline, size: 20, color: Colors.white)),
              ),
            ),
          ],
        ),
        body: WebViewWidget(controller: controller),
      ),
    );
  }
}


class LaunchSplashScreen extends StatefulWidget {
  final Widget child;
  final ValueListenable<bool> readyListenable;

  const LaunchSplashScreen({
    super.key,
    required this.child,
    required this.readyListenable,
  });

  @override
  State<LaunchSplashScreen> createState() => _LaunchSplashScreenState();
}

class _LaunchSplashScreenState extends State<LaunchSplashScreen> {
  bool _showSplash = true;
  bool _minTimeElapsed = false;
  bool _maxTimeElapsed = false;
  bool _hideScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.readyListenable.addListener(_tryHideSplash);
    _startMinDelay();
    _startMaxDelay();
  }

  @override
  void dispose() {
    widget.readyListenable.removeListener(_tryHideSplash);
    super.dispose();
  }

  Future<void> _startMinDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    _minTimeElapsed = true;
    _tryHideSplash();
  }

  Future<void> _startMaxDelay() async {
    await Future<void>.delayed(const Duration(seconds: 8));
    _maxTimeElapsed = true;
    _tryHideSplash();
  }

  void _tryHideSplash() {
    if (!_showSplash) return;
    if (!_minTimeElapsed) return;
    if (!widget.readyListenable.value && !_maxTimeElapsed) return;
    if (!mounted) return;
    if (_hideScheduled) return;
    _hideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hideScheduled = false;
      if (!mounted || !_showSplash) return;
      setState(() {
        _showSplash = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSplash) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        const Positioned.fill(
          child: _SplashScreenContent(),
        ),
      ],
    );
  }
}

class _SplashScreenContent extends StatelessWidget {
  const _SplashScreenContent();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: kAmbientBlendColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Image(
                    image: AssetImage('assets/icon.png'),
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(height: 56),
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4B9CFF)),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  'Načítavajú sa dáta...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
