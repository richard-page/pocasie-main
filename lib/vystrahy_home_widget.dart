import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Deep link z Android widgetu výstrah (`MeteoVystrahyWidgetProvider`).
const String kVystrahyWidgetLaunchUri = 'menopocasie://open/vystrahy';

bool isVystrahyWidgetLaunchUri(Uri? uri) {
  if (uri == null) return false;
  final s = uri.toString();
  if (s == kVystrahyWidgetLaunchUri) return true;
  return uri.scheme == 'menopocasie' &&
      (uri.host == 'open' || uri.host == 'vystrahy') &&
      (uri.path.contains('vystrahy') || uri.host == 'vystrahy');
}

/// Android domovský widget info okna výstrah (`MeteoVystrahyWidgetProvider`).
class VystrahyHomeWidget {
  static const String androidQualifiedName =
      'sk.menopocasie.app.MeteoVystrahyWidgetProvider';

  static const String kReady = 'vystrahy_widget_ready';
  static const String kHasWarning = 'vystrahy_widget_has_warning';
  static const String kTitle = 'vystrahy_widget_title';
  static const String kLevelLine = 'vystrahy_widget_level';
  static const String kTypesLine = 'vystrahy_widget_types';
  static const String kTiming = 'vystrahy_widget_timing';
  static const String kOkres = 'vystrahy_widget_okres';
  static const String kRank = 'vystrahy_widget_rank';
  static const String kJavId = 'vystrahy_widget_jav_id';

  static Future<void> update({
    required bool hasWarning,
    required String title,
    required String levelLine,
    required String typesLine,
    required String timing,
    required String okres,
    required int rank,
    String javId = '',
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;

    await HomeWidget.saveWidgetData<String>(kReady, '1');
    await HomeWidget.saveWidgetData<String>(
      kHasWarning,
      hasWarning ? '1' : '0',
    );
    await HomeWidget.saveWidgetData<String>(kTitle, title);
    await HomeWidget.saveWidgetData<String>(kLevelLine, levelLine);
    await HomeWidget.saveWidgetData<String>(kTypesLine, typesLine);
    await HomeWidget.saveWidgetData<String>(kTiming, timing);
    await HomeWidget.saveWidgetData<String>(kOkres, okres);
    await HomeWidget.saveWidgetData<String>(kRank, '$rank');
    await HomeWidget.saveWidgetData<String>(kJavId, javId);
    await HomeWidget.updateWidget(qualifiedAndroidName: androidQualifiedName);
  }

  static Future<void> clear({
    String okres = '',
    /// Hint na mapu výstrah len pre SK (mimo SR výstrahy nie sú).
    bool showMapHint = true,
  }) async {
    await update(
      hasWarning: false,
      title: 'Bez výstrahy',
      levelLine: okres.isEmpty
          ? 'Žiadna aktívna výstraha'
          : 'okres $okres',
      typesLine: '',
      timing: showMapHint ? 'Otvorte aplikáciu pre mapu výstrah' : '',
      okres: okres,
      rank: 0,
      javId: '',
    );
  }
}
