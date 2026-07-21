import 'package:flutter/material.dart';

/// Jedna hlbšia navy paleta — hero aj scroll majú rovnaký canvas (žiadny farebný zlom).
///
/// canvas → surface → elevated → accent
const Color kAmbientBlendColor = Color(0xFF0E1826);

/// Accent v tej istej rodine.
const Color kAppAccentBlue = Color(0xFF3D78B8);
const Color kAppAccentBlueBright = Color(0xFF4A88C4);

/// Karty — o stupeň nad canvas, stále rovnaký hue.
const Color kAppCardNavy = Color(0xFF162434);
const Color kAppCardNavyElevated = Color(0xFF1C2E42);
const Color kAppCardNavyBorder = Color(0xFF2A3E56);

/// Hero (teplota + ikona) — stred: ako karty, nie canvas ani bledý sky.
const Color kAppHeroGradientTop = Color(0xFF162434);
const Color kAppHeroGradientMid = Color(0xFF182838);
const Color kAppHeroGradientBottom = Color(0xFF1A2C3C);

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
              color: const Color(0xFF050A12).withValues(alpha: 0.40),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ]
        : null,
  );
}
