import 'dart:convert';

import 'package:http/http.dart' as http;

/// Rovnaké názvy okresov ako v Helkor `mapovanieKrajov` (vystrahy.php).
const List<String> kVystrahyOkresNames = [
  'Bratislava',
  'Malacky',
  'Pezinok',
  'Senec',
  'Dunajská Streda',
  'Galanta',
  'Hlohovec',
  'Piešťany',
  'Senica',
  'Skalica',
  'Trnava',
  'Bánovce nad Bebravou',
  'Ilava',
  'Myjava',
  'Nové Mesto nad Váhom',
  'Partizánske',
  'Považská Bystrica',
  'Prievidza',
  'Púchov',
  'Trenčín',
  'Komárno',
  'Levice',
  'Nitra',
  'Nové Zámky',
  'Šaľa',
  'Topoľčany',
  'Zlaté Moravce',
  'Bytča',
  'Čadca',
  'Dolný Kubín',
  'Kysucké Nové Mesto',
  'Liptovský Mikuláš',
  'Martin',
  'Námestovo',
  'Ružomberok',
  'Turčianske Teplice',
  'Tvrdošín',
  'Žilina',
  'Banská Bystrica',
  'Banská Štiavnica',
  'Brezno',
  'Detva',
  'Krupina',
  'Lučenec',
  'Poltár',
  'Revúca',
  'Rimavská Sobota',
  'Veľký Krtíš',
  'Zvolen',
  'Žarnovica',
  'Žiar nad Hronom',
  'Bardejov',
  'Humenné',
  'Kežmarok',
  'Levoča',
  'Medzilaborce',
  'Poprad',
  'Prešov',
  'Sabinov',
  'Snina',
  'Stará Ľubovňa',
  'Stropkov',
  'Svidník',
  'Vranov nad Topľou',
  'Gelnica',
  'Košice',
  'Michalovce',
  'Rožňava',
  'Sobrance',
  'Spišská Nová Ves',
  'Trebišov',
];

const String kVystrahyJsonUrl = 'http://cz1.helkor.eu:41083/vystrahy.json';
const String kVystrahyPhpUrl = 'http://cz1.helkor.eu:41083/vystrahy.php';

DateTime? parseVystrahyWidgetSkDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final cleaned =
      raw.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final m = RegExp(
    r'^(\d{1,2})\s*\.\s*(\d{1,2})\s*\.\s*(\d{4})\s*(\d{1,2})\s*:\s*(\d{1,2})',
  ).firstMatch(cleaned);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
  );
}

String? matchVystrahyOkresName({
  required String cityName,
  String? admin1,
  String? admin2,
}) {
  final candidates = <String>[
    cityName,
    if (admin2 != null && admin2.trim().isNotEmpty) admin2,
    if (admin1 != null && admin1.trim().isNotEmpty) admin1,
  ];

  String? best;
  var bestLen = 0;
  for (final raw in candidates) {
    final cleaned = raw
        .replaceFirst(RegExp(r'^Okres\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^District\s+of\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+District$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+Region$', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty) continue;
    final lower = cleaned.toLowerCase();
    for (final okres in kVystrahyOkresNames) {
      final o = okres.toLowerCase();
      if (lower == o || lower.startsWith(o) || o.startsWith(lower)) {
        if (okres.length >= bestLen) {
          best = okres;
          bestLen = okres.length;
        }
      }
    }
  }
  return best;
}

class VystrahyWidgetItem {
  const VystrahyWidgetItem({
    required this.jav,
    required this.rank,
    required this.od,
    required this.doUntil,
    required this.isActiveNow,
  });

  final String jav;
  final int rank;
  final DateTime? od;
  final DateTime? doUntil;
  final bool isActiveNow;
}

class VystrahyWidgetSnapshot {
  const VystrahyWidgetSnapshot({
    required this.okres,
    required this.items,
  });

  final String okres;
  final List<VystrahyWidgetItem> items;

  bool get hasWarning => items.isNotEmpty;

  int get maxRank =>
      items.fold(0, (m, i) => i.rank > m ? i.rank : m);

  VystrahyWidgetItem get primary {
    final sorted = [...items]..sort((a, b) {
        if (a.isActiveNow != b.isActiveNow) {
          return a.isActiveNow ? -1 : 1;
        }
        if (b.rank != a.rank) return b.rank.compareTo(a.rank);
        final aOd = a.od;
        final bOd = b.od;
        if (aOd == null) return 1;
        if (bOd == null) return -1;
        return aOd.compareTo(bOd);
      });
    return sorted.first;
  }

  String countTitleSk() {
    final n = items.length;
    return switch (n) {
      1 => items.first.jav,
      2 || 3 || 4 => '$n výstrahy',
      _ => '$n výstrah',
    };
  }

  String levelLine() {
    if (maxRank <= 1) return '1. stupeň • okres $okres';
    if (items.length == 1) return '$maxRank. stupeň • okres $okres';
    return 'najvyšší $maxRank. stupeň • okres $okres';
  }

  String typesLine() {
    if (items.length <= 1) return '';
    return scheduleLines(DateTime.now());
  }

  String timingLine(DateTime now) {
    if (items.isEmpty) return '';
    if (items.length == 1) {
      return _formatItemTiming(now, items.first);
    }
    // Viac výstrah: rozpis je v typesLine (každý jav + od–do).
    return '';
  }

  String scheduleLines([DateTime? now]) {
    final at = now ?? DateTime.now();
    final list = [...items]..sort((a, b) {
        if (a.isActiveNow != b.isActiveNow) {
          return a.isActiveNow ? -1 : 1;
        }
        if (b.rank != a.rank) return b.rank.compareTo(a.rank);
        final aOd = a.od;
        final bOd = b.od;
        if (aOd == null && bOd == null) return 0;
        if (aOd == null) return 1;
        if (bOd == null) return -1;
        return aOd.compareTo(bOd);
      });
    return list.map((item) => _formatItemSchedule(at, item)).join('\n');
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  static String _dayWord(DateTime now, DateTime at) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final dayDiff = day.difference(today).inDays;
    return switch (dayDiff) {
      0 => 'dnes',
      1 => 'zajtra',
      2 => 'pozajtra',
      _ => '${at.day}.${at.month}.',
    };
  }

  static String _dayTime(DateTime now, DateTime at) =>
      '${_dayWord(now, at)} ${_clock(at)}';

  static String _formatItemSchedule(DateTime now, VystrahyWidgetItem item) {
    final when = _formatItemTiming(now, item);
    if (when.isEmpty) return '${item.jav} · ${item.rank}. st.';
    return '${item.jav} · $when';
  }

  static String _formatItemTiming(DateTime now, VystrahyWidgetItem item) {
    final startAt = item.od;
    final endAt = item.doUntil;

    String? rangeLabel() {
      if (startAt == null && endAt == null) return null;
      if (startAt != null && endAt != null) {
        final startLabel = _dayTime(now, startAt);
        final sameDay = startAt.year == endAt.year &&
            startAt.month == endAt.month &&
            startAt.day == endAt.day;
        if (sameDay) {
          return 'Od $startLabel do ${_clock(endAt)}';
        }
        return 'Od $startLabel do ${_dayTime(now, endAt)}';
      }
      if (startAt != null) return 'Od ${_dayTime(now, startAt)}';
      return 'Do ${_dayTime(now, endAt!)}';
    }

    if (item.isActiveNow) {
      final range = rangeLabel();
      if (range != null) return range;
      return 'Práve platí';
    }

    if (startAt == null) {
      if (endAt != null) return 'Do ${_dayTime(now, endAt)}';
      return '';
    }

    final startLabel = _dayTime(now, startAt);
    var diff = startAt.difference(now);
    if (diff.isNegative) diff = Duration.zero;
    final totalMinutes = diff.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    final rel = hours > 0 && minutes > 0
        ? 'o $hours h $minutes min'
        : hours > 0
            ? 'o $hours h'
            : minutes > 0
                ? 'o $minutes min'
                : 'o chvíľu';
    final range = rangeLabel();
    if (range != null) return '$range ($rel)';
    return 'Začína $startLabel ($rel)';
  }
}

Future<Map<String, dynamic>?> _fetchVystrahyDbaseFromJson() async {
  try {
    final res = await http
        .get(
          Uri.parse(
            '$kVystrahyJsonUrl?_cb=${DateTime.now().millisecondsSinceEpoch}',
          ),
          headers: const {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = json.decode(utf8.decode(res.bodyBytes));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return null;
}

Future<Map<String, dynamic>?> _fetchVystrahyDbaseFromPhp() async {
  try {
    final res = await http
        .get(
          Uri.parse(
            '$kVystrahyPhpUrl?_cb=${DateTime.now().millisecondsSinceEpoch}',
          ),
          headers: const {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final literal = _extractDbaseLiteral(res.body);
    if (literal == null) return null;
    final decoded = json.decode(literal == '[]' ? '{}' : literal);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    if (decoded is List) return <String, dynamic>{};
  } catch (_) {}
  return null;
}

/// [preferPhp] — domovský banner / pull: vždy čerstvé PHP (JSON býva cache/oneskorený).
Future<Map<String, dynamic>?> fetchVystrahyDbaseMap({
  bool preferPhp = false,
}) async {
  if (preferPhp) {
    return await _fetchVystrahyDbaseFromPhp() ??
        await _fetchVystrahyDbaseFromJson();
  }
  return await _fetchVystrahyDbaseFromJson() ??
      await _fetchVystrahyDbaseFromPhp();
}

String? _extractDbaseLiteral(String html) {
  final marker = RegExp(r'let\s+dbase\s*=\s*');
  final m = marker.firstMatch(html);
  if (m == null) return null;
  var i = m.end;
  if (i >= html.length) return null;
  final open = html[i];
  if (open != '{' && open != '[') return null;
  final close = open == '{' ? '}' : ']';
  var depth = 0;
  final start = i;
  for (; i < html.length; i++) {
    final ch = html[i];
    if (ch == '"' || ch == "'") {
      final quote = ch;
      i++;
      while (i < html.length) {
        if (html[i] == r'\') {
          i += 2;
          continue;
        }
        if (html[i] == quote) break;
        i++;
      }
      continue;
    }
    if (ch == open) {
      depth++;
    } else if (ch == close) {
      depth--;
      if (depth == 0) return html.substring(start, i + 1);
    }
  }
  return null;
}

VystrahyWidgetSnapshot? buildVystrahySnapshotForOkres(
  Map<String, dynamic> dbase,
  String okres, {
  DateTime? now,
}) {
  final nowLocal = now ?? DateTime.now();
  final raw = dbase[okres];
  if (raw is! List) {
    // Skús kľúč s prefixom „Okres “.
    final alt = dbase['Okres $okres'];
    if (alt is! List) return VystrahyWidgetSnapshot(okres: okres, items: const []);
    return _snapshotFromList(okres, alt, nowLocal);
  }
  return _snapshotFromList(okres, raw, nowLocal);
}

VystrahyWidgetSnapshot _snapshotFromList(
  String okres,
  List<dynamic> raw,
  DateTime now,
) {
  final items = <VystrahyWidgetItem>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    final jav = (map['jav'] as String?)?.trim() ?? '';
    final rank = int.tryParse('${map['uroven'] ?? ''}') ?? 0;
    if (jav.isEmpty || rank < 1) continue;
    final od = parseVystrahyWidgetSkDate(map['od'] as String?);
    final doUntil = parseVystrahyWidgetSkDate(map['do'] as String?);
    if (doUntil == null || !doUntil.isAfter(now)) continue;
    final active = od != null && !od.isAfter(now);
    items.add(
      VystrahyWidgetItem(
        jav: jav,
        rank: rank,
        od: od,
        doUntil: doUntil,
        isActiveNow: active,
      ),
    );
  }
  items.sort((a, b) {
    if (a.isActiveNow != b.isActiveNow) return a.isActiveNow ? -1 : 1;
    if (b.rank != a.rank) return b.rank.compareTo(a.rank);
    final aOd = a.od;
    final bOd = b.od;
    if (aOd == null) return 1;
    if (bOd == null) return -1;
    return aOd.compareTo(bOd);
  });
  return VystrahyWidgetSnapshot(okres: okres, items: items);
}

Future<VystrahyWidgetSnapshot?> fetchVystrahySnapshotForCity({
  required String cityName,
  String? admin1,
  String? admin2,
  bool preferPhp = false,
}) async {
  final okres = matchVystrahyOkresName(
    cityName: cityName,
    admin1: admin1,
    admin2: admin2,
  );
  if (okres == null) return null;
  final dbase = await fetchVystrahyDbaseMap(preferPhp: preferPhp);
  if (dbase == null) return null;
  return buildVystrahySnapshotForOkres(dbase, okres);
}
