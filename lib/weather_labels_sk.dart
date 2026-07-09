/// Zjednodušené slovenské popisy zrážok pre pinned hlavičku a domovské widgety.
///
/// Ikony a intenzita ostávajú podľa WMO kódu; text je len Búrka / Dážď / Sneženie.
String? simplifiedPrecipLabelSk(int? code) {
  if (code == null) return null;
  return switch (code) {
    95 || 96 || 99 => 'búrka',
    51 ||
    53 ||
    55 ||
    61 ||
    63 ||
    65 ||
    66 ||
    67 ||
    80 ||
    81 ||
    82 =>
      'dážď',
    56 || 57 || 71 || 73 || 75 || 77 || 85 || 86 => 'sneženie',
    _ => null,
  };
}
