import 'package:flutter/material.dart';

/// Navy paleta — svetlejšia než predchádzajúca, stále tmavšia než pôvodná bledá.
///
/// canvas → surface → elevated → accent
const Color kAmbientBlendColor = Color(0xFF172438);

/// Accent v tej istej rodine.
const Color kAppAccentBlue = Color(0xFF4684C0);
const Color kAppAccentBlueBright = Color(0xFF5494D0);

/// Karty — o stupeň nad canvas, stále rovnaký hue.
const Color kAppCardNavy = Color(0xFF203648);
const Color kAppCardNavyElevated = Color(0xFF284058);
const Color kAppCardNavyBorder = Color(0xFF365270);

/// Hero (teplota + ikona) — stred: ako karty, nie canvas ani bledý sky.
const Color kAppHeroGradientTop = Color(0xFF203648);
const Color kAppHeroGradientMid = Color(0xFF223A4C);
const Color kAppHeroGradientBottom = Color(0xFF243E50);

/// Spoločný obal karty — rovnaký vzhľad na celej appke.
BoxDecoration appSurfaceDecoration({
  double radius = 20,
  bool elevated = false,
  bool withShadow = true,
}) {
  return BoxDecoration(
    color: elevated ? kAppCardNavyElevated : kAppCardNavy,
    borderRadius: BorderRadius.circular(radius),
    border: const Border.fromBorderSide(
      BorderSide(color: kAppCardNavyBorder, width: 1),
    ),
    boxShadow: withShadow
        ? [
            BoxShadow(
              color: const Color(0xFF091018).withValues(alpha: 0.34),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ]
        : null,
  );
}

/// Info dialógy (peľ, radar, kamera…) — jedna farba pozadia / accent / tlačidiel.
BoxDecoration appInfoDialogDecoration({double radius = 20}) {
  return BoxDecoration(
    color: kAmbientBlendColor,
    borderRadius: BorderRadius.circular(radius),
    border: const Border.fromBorderSide(
      BorderSide(color: kAppCardNavyBorder, width: 1),
    ),
  );
}

ButtonStyle appInfoDialogCloseButtonStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: kAppCardNavy,
    foregroundColor: Colors.white70,
    padding: const EdgeInsets.symmetric(vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: kAppCardNavyBorder),
    ),
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
  ).copyWith(
    overlayColor: WidgetStateProperty.all(Colors.transparent),
  );
}

/// Ikona v kruhu — rovnaký vzhľad vo všetkých info dialógoch.
Widget appInfoDialogIcon(IconData icon) {
  return Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: kAppAccentBlue, width: 2.5),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 26, color: kAppAccentBlue),
  );
}
