import 'package:flutter/material.dart';

class PlayerUiConstants {
  // Common Opacities - for reference or direct use
  static const double primaryOpacity = 0.8;
  static const double secondaryOpacity = 0.6;
  static const double tertiaryOpacity = 0.3;

  // Padding and Spacing
  static const double p10 = 10.0; // General padding for positioned elements
  static const double p8 =
      8.0; // Common spacing (e.g., SizedBox, bottom bar padding)
  static const double p4 =
      4.0; // Fine-grained padding (e.g., bottom bar internal row)

  // Sizes
  static const double errorIconSize = 48.0;

  // --- Side Sliders (Brightness/Volume) ---
  static const double sideSliderTrackHeight = 2.0;
  static const double sideSliderThumbRadiusNormal = 8.0;
  static const double sideSliderThumbRadiusFull = 10.0;
  static const double sideSliderOverlayRadiusNormal = 16.0;
  static const double sideSliderOverlayRadiusFull = 20.0;
  static final BorderRadius sideSliderContainerRadius = BorderRadius.circular(
    20.0,
  );
  static final Color sideSliderBackgroundColor = Colors.black.withOpacity(
    tertiaryOpacity,
  ); // 0.3
  // Raw values for width/offsets which depend on orientation
  static const double sideSliderWidthLandscape = 50.0;
  static const double sideSliderWidthPortrait = 40.0;
  static const double sideSliderTopOffsetLandscape = 60.0;
  static const double sideSliderTopOffsetPortrait = 30.0;
  static const double sideSliderBottomOffsetLandscape = 90.0;
  static const double sideSliderBottomOffsetPortrait = 60.0;

  // --- Central Controls (Play/Pause, Seek buttons) ---
  static final Color controlButtonIconColor = Colors.white.withOpacity(
    primaryOpacity,
  ); // 0.8
  // Raw values for spacing which depend on fullscreen
  static const double centralControlSpacingFull = 30.0;
  static const double centralControlSpacingNormal = 20.0;

  // --- Bottom Bar ---
  static final Color bottomBarBackgroundColor = Colors.black.withOpacity(
    secondaryOpacity,
  ); // 0.6
  static final BorderRadius bottomBarContainerRadius = BorderRadius.circular(
    12.0,
  );
  static const double bottomBarSeekSliderTrackHeightNormal = 2.5;
  static const double bottomBarSeekSliderTrackHeightFull = 3.0;
  static const Color timeDisplayTextColor = Colors.white;
  static const double timeDisplayFontSizeNormal = 12.0;
  static const double timeDisplayFontSizeFull = 14.0;

  // --- General Player Elements ---
  static final Color generalProgressIndicatorColor = Colors.white.withOpacity(
    primaryOpacity,
  ); // 0.8
  static const Color errorTextColor = Colors.white70;
  static const Color errorIconColor = Colors.red;

  // --- Common Colors for Sliders (used by side and bottom bar sliders) ---
  static const Color commonSliderActiveColor = Colors.amber;
  static const Color commonSliderInactiveColor = Colors.white38; // for track
  static const Color commonSliderThumbColor = Colors.amber;
}
