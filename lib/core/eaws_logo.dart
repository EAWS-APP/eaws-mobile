import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'theme.dart';

enum EawsLogoStyle {
  onRed,      // White shield & plus with semi-transparent container (for red backgrounds)
  onWhite,    // Red shield & plus with light red container (for white/light backgrounds)
  appIcon,    // Red solid rounded square with white shield & plus (exact replica of the icon image)
}

class EawsLogo extends StatelessWidget {
  final double size;
  final EawsLogoStyle style;
  final double borderRadius;

  const EawsLogo({
    super.key,
    this.size = 60,
    this.style = EawsLogoStyle.onRed,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    // Determine colors based on style
    Color containerColor;
    Border? border;
    Color iconColor;

    switch (style) {
      case EawsLogoStyle.onRed:
        containerColor = Colors.white.withOpacity(0.15);
        border = Border.all(color: Colors.white.withOpacity(0.3), width: 1.5);
        iconColor = Colors.white;
        break;
      case EawsLogoStyle.onWhite:
        containerColor = AppTheme.primaryColor.withOpacity(0.08);
        border = Border.all(color: AppTheme.primaryColor.withOpacity(0.15), width: 1.5);
        iconColor = AppTheme.primaryColor;
        break;
      case EawsLogoStyle.appIcon:
        containerColor = AppTheme.primaryColor;
        border = null;
        iconColor = Colors.white;
        break;
    }

    final double shieldSize = size * 0.65;
    final double plusSize = shieldSize * 0.45;
    final double plusThickness = plusSize * 0.22;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: containerColor,
        border: border,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: style == EawsLogoStyle.appIcon
            ? [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Center(
        child: SizedBox(
          width: shieldSize,
          height: shieldSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Shield outline
              Icon(
                LucideIcons.shield,
                color: iconColor,
                size: shieldSize,
              ),
              // Custom designed inner plus/cross with rounded caps for a premium vector feel
              Positioned(
                top: shieldSize * 0.22, // Adjusted vertically to center inside shield path perfectly
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Vertical line of the plus
                    Container(
                      width: plusThickness,
                      height: plusSize,
                      decoration: BoxDecoration(
                        color: iconColor,
                        borderRadius: BorderRadius.circular(plusThickness / 2),
                      ),
                    ),
                    // Horizontal line of the plus
                    Container(
                      width: plusSize,
                      height: plusThickness,
                      decoration: BoxDecoration(
                        color: iconColor,
                        borderRadius: BorderRadius.circular(plusThickness / 2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
