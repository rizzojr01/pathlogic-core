import 'dart:math' as math;
import 'package:flutter/material.dart';

/// User position marker with navigation arrow that rotates based on orientation
class UserPositionMarker extends StatelessWidget {
  final double size;
  final double orientationDegrees;
  final Color? primaryColor;
  final Color? iconColor;
  final bool showPulse;
  final bool isCheckpoint;

  const UserPositionMarker({
    super.key,
    this.size = 24.0,
    this.orientationDegrees = 0.0,
    this.primaryColor,
    this.iconColor,
    this.showPulse = true,
    this.isCheckpoint = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = primaryColor ?? Colors.green;
    final fgColor = iconColor ?? Colors.white;

    // Convert degrees to radians for rotation
    final rotationRadians =
        orientationDegrees.isNaN || orientationDegrees.isInfinite
        ? 0.0
        : orientationDegrees * (math.pi / 180);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer pulse ring
          if (showPulse)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bgColor.withOpacity(0.2),
              ),
            ),

          // Main marker body
          Container(
            width: isCheckpoint ? size * 0.5 : size * 0.75,
            height: isCheckpoint ? size * 0.5 : size * 0.75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCheckpoint ? Colors.white : bgColor,
              border: Border.all(
                color: isCheckpoint ? bgColor : Colors.white,
                width: isCheckpoint ? 1.5 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isCheckpoint ? bgColor : Colors.black).withValues(
                    alpha: 0.25,
                  ),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: isCheckpoint
                ? Center(
                    child: Container(
                      width: size * 0.2,
                      height: size * 0.2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bgColor,
                        boxShadow: [
                          BoxShadow(
                            color: bgColor.withValues(alpha: 0.4),
                            blurRadius: 2,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  )
                : Transform.rotate(
                    angle: rotationRadians,
                    child: Icon(
                      Icons.navigation,
                      size: size * 0.4,
                      color: fgColor,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Destination marker with flag icon - refined pin style
class DestinationFlagMarker extends StatelessWidget {
  final double size;
  final Color? flagColor;
  final Color? iconColor;
  final String? label;
  final VoidCallback? onTap;

  const DestinationFlagMarker({
    super.key,
    this.size = 24.0,
    this.flagColor,
    this.iconColor,
    this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = flagColor ?? const Color(0xFFEA4335);
    final fgColor = iconColor ?? Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer subtle glow
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor.withValues(alpha: 0.15),
            ),
          ),
          // Main Pin
          Container(
            width: size * 0.8,
            height: size * 0.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bgColor, bgColor.withValues(alpha: 0.8)],
              ),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(Icons.flag_rounded, size: size * 0.45, color: fgColor),
          ),
        ],
      ),
    );
  }
}

/// Circular POI marker. Pass [isSelected] to highlight the chosen destination.
class DestinationMarker extends StatelessWidget {
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color; // overrides default POI color

  const DestinationMarker({
    super.key,
    this.size = 28.0,
    this.backgroundColor,
    this.iconColor,
    this.icon = Icons.place,
    this.onTap,
    this.color,
  });

  static const Color _defaultPoiColor = Color(0xFF1E88E5);

  @override
  Widget build(BuildContext context) {
    final isGeneralIcon = icon == Icons.place;
    final effectivePoiColor = color ?? backgroundColor ?? _defaultPoiColor;

    if (isGeneralIcon) {
      return GestureDetector(
        onTap: onTap,
        child: Icon(icon, color: effectivePoiColor, size: size),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectivePoiColor,
          boxShadow: [
            BoxShadow(
              color: effectivePoiColor.withValues(alpha: 0.3),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.6),
      ),
    );
  }

  /// Get appropriate icon based on destination name
  static IconData getIconForDestination(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('elevator')) return Icons.elevator;
    if (lowerName.contains('restroom') || lowerName.contains('bathroom')) {
      return Icons.wc;
    }
    if (lowerName.contains('pantry') || lowerName.contains('kitchen')) {
      return Icons.kitchen;
    }
    if (lowerName.contains('office')) return Icons.business;
    if (lowerName.contains('reception')) return Icons.desk;
    if (lowerName.contains('board') || lowerName.contains('meeting')) {
      return Icons.groups;
    }
    return Icons.place;
  }
}

/// Small, low-emphasis marker for door locations on the floor map.
class DoorLocationMarker extends StatelessWidget {
  final double size;
  final Color? color;

  const DoorLocationMarker({super.key, this.size = 16.0, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Use theme's secondary color as the default accent for doors to fit perfectly
    // with the app's selected scheme and contrast with green/red markers.
    final markerColor = color ?? theme.colorScheme.secondary;

    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.35),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: markerColor.withOpacity(0.7),
            width: (size / 12.0).clamp(0.6, 1.4),
          ),
        ),
        child: CustomPaint(
          painter: PerspectiveDoorPainter(color: markerColor),
        ),
      ),
    );
  }
}

/// Draws an open door in perspective (trapeze shape leaf) for high visual fidelity.
class PerspectiveDoorPainter extends CustomPainter {
  final Color color;

  const PerspectiveDoorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = (size.width * 0.10).clamp(1.0, 2.5);
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Draw the door frame (top, right side)
    // Left side is open/covered by the swung door leaf hinge.
    final framePath = Path()
      ..moveTo(w * 0.20, h * 0.85)
      ..lineTo(w * 0.20, h * 0.20)
      ..lineTo(w * 0.80, h * 0.20)
      ..lineTo(w * 0.80, h * 0.85);
    canvas.drawPath(framePath, paint);

    // Draw the open door leaf (trapezoidal perspective shape swinging towards viewer)
    // Hinged on the left (x = w * 0.20). Since it swings open towards the viewer:
    // Left edge (hinge): y_top = h * 0.20, y_bottom = h * 0.85
    // Right edge (open edge): y_top = h * 0.08, y_bottom = h * 0.95 (taller due to perspective)
    final doorLeafPath = Path()
      ..moveTo(w * 0.20, h * 0.20) // Hinge top
      ..lineTo(w * 0.58, h * 0.08) // Open top (projected closer/taller)
      ..lineTo(w * 0.58, h * 0.95) // Open bottom (projected closer/taller)
      ..lineTo(w * 0.20, h * 0.85) // Hinge bottom
      ..close();

    // Fill the door leaf slightly
    canvas.drawPath(doorLeafPath, fillPaint);
    
    // Draw the door leaf outline
    canvas.drawPath(doorLeafPath, paint);

    // Draw a small door knob on the open edge of the leaf
    final knobPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.52),
      (w * 0.07).clamp(0.8, 1.8),
      knobPaint,
    );
  }

  @override
  bool shouldRepaint(covariant PerspectiveDoorPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
