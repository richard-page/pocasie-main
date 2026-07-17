import 'package:flutter/material.dart';

/// Jedna svetlejšia navy paleta — hero aj scroll majú rovnaký canvas (žiadny farebný zlom).
///
/// canvas → surface → elevated → accent
const Color kAmbientBlendColor = Color(0xFF1A2C44);

/// Accent v tej istej rodine.
const Color kAppAccentBlue = Color(0xFF4A85C4);
const Color kAppAccentBlueBright = Color(0xFF5B96D4);

/// Karty — o stupeň nad canvas, stále rovnaký hue.
const Color kAppCardNavy = Color(0xFF243850);
const Color kAppCardNavyElevated = Color(0xFF2C4460);
const Color kAppCardNavyBorder = Color(0xFF3A5674);

/// Hero (teplota + ikona) — stred: ako karty, nie canvas ani bledý sky.
const Color kAppHeroGradientTop = Color(0xFF243850);
const Color kAppHeroGradientMid = Color(0xFF26405A);
const Color kAppHeroGradientBottom = Color(0xFF284460);

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
              color: const Color(0xFF0C1828).withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ]
        : null,
  );
}
