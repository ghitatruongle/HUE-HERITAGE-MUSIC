import 'package:flutter/material.dart';
import 'hue_icons.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final double iconSize;
  final Color? iconColor;

  const AppLogo({
    super.key,
    required this.size,
    this.borderRadius = 12,
    this.iconSize = 24,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        'assets/images/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => HueIcon(
          HueIcons.musicNote,
          size: iconSize,
          color: iconColor,
        ),
      ),
    );
  }
}
