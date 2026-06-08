import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:home_widget/home_widget.dart';

/// Android domovský widget (`MeteoPocasieWidgetProvider`).
class WeatherHomeWidget {
  static const String _androidQualifiedName = 'sk.menopocasie.app.MeteoPocasieWidgetProvider';
  static const String _androidQualifiedNamePlus = 'sk.menopocasie.app.MeteoPocasieWidgetPlusProvider';
  static const String _androidQualifiedNameMini = 'sk.menopocasie.app.MeteoPocasieWidgetMiniProvider';

  static const String _kCity = 'widget_city';
  static const String _kDescription = 'widget_description';
  static const String _kTemp = 'widget_temp';
  static const String _kTimeJe = 'widget_time_je';
  static const String _kCode = 'widget_code';
  static const String _kIsDay = 'widget_is_day';
  static const String _kApparent = 'widget_apparent';
  static const String _kOffline = 'widget_offline';
  static const String _kIconFile = 'widget_icon_file';
  static const String _kWind = 'widget_wind';
  static const String _kSun = 'widget_sun';
  static const String _kHumidity = 'widget_humidity';
  static const String _kReady = 'widget_ready';

  static Future<void> update({
    required String city,
    required String description,
    required String temperature,
    required String timeJe,
    required int weatherCode,
    String? iconAssetPath,
    bool isDay = true,
    String? apparent,
    String? wind,
    String? sun,
    String? humidity,
    bool isOffline = false,
  }) async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    await HomeWidget.saveWidgetData<String>(_kCity, city);
    await HomeWidget.saveWidgetData<String>(_kDescription, description);
    await HomeWidget.saveWidgetData<String>(_kTemp, temperature);
    await HomeWidget.saveWidgetData<String>(_kTimeJe, timeJe);
    await HomeWidget.saveWidgetData<String>(_kCode, '$weatherCode');
    await HomeWidget.saveWidgetData<String>(_kIsDay, isDay ? '1' : '0');
    await HomeWidget.saveWidgetData<String>(_kApparent, apparent ?? '');
    await HomeWidget.saveWidgetData<String>(_kWind, wind ?? '--');
    await HomeWidget.saveWidgetData<String>(_kSun, sun ?? '--:-- / --:--');
    await HomeWidget.saveWidgetData<String>(_kHumidity, humidity ?? '--%');
    await HomeWidget.saveWidgetData<String>(_kOffline, isOffline ? '1' : '0');
    await HomeWidget.saveWidgetData<String>(_kReady, '1');
    if (iconAssetPath != null && iconAssetPath.isNotEmpty) {
      try {
        await HomeWidget.renderFlutterWidget(
          SvgPicture.asset(iconAssetPath, width: 256, height: 256),
          key: _kIconFile,
          logicalSize: const Size(256, 256),
          pixelRatio: 2.5,
        );
      } catch (_) {
        await HomeWidget.saveWidgetData<String>(_kIconFile, '');
      }
    } else {
      await HomeWidget.saveWidgetData<String>(_kIconFile, '');
    }

    await HomeWidget.updateWidget(qualifiedAndroidName: _androidQualifiedName);
    await HomeWidget.updateWidget(qualifiedAndroidName: _androidQualifiedNamePlus);
    await HomeWidget.updateWidget(qualifiedAndroidName: _androidQualifiedNameMini);
  }

  static Future<void> clear() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    await HomeWidget.saveWidgetData<String>(_kCity, '—');
    await HomeWidget.saveWidgetData<String>(_kDescription, 'Otvorte aplikáciu');
    await HomeWidget.saveWidgetData<String>(_kTemp, '—');
    await HomeWidget.saveWidgetData<String>(_kTimeJe, '');
    await HomeWidget.saveWidgetData<String>(_kCode, '0');
    await HomeWidget.saveWidgetData<String>(_kIsDay, '1');
    await HomeWidget.saveWidgetData<String>(_kApparent, '');
    await HomeWidget.saveWidgetData<String>(_kWind, '--');
    await HomeWidget.saveWidgetData<String>(_kSun, '--:-- / --:--');
    await HomeWidget.saveWidgetData<String>(_kHumidity, '--%');
    await HomeWidget.saveWidgetData<String>(_kOffline, '0');
    await HomeWidget.saveWidgetData<String>(_kReady, '0');
    await HomeWidget.saveWidgetData<String>(_kIconFile, '');
    await HomeWidget.updateWidget(qualifiedAndroidName: _androidQualifiedName);
    await HomeWidget.updateWidget(qualifiedAndroidName: _androidQualifiedNamePlus);
    await HomeWidget.updateWidget(qualifiedAndroidName: _androidQualifiedNameMini);
  }
}
