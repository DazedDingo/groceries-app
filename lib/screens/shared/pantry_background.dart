import 'dart:math';
import 'package:flutter/material.dart';

/// A decorative stocked-pantry backdrop.
///
/// Lays a warm gradient plus a scattered grid of food/kitchen icons at low
/// opacity. Purely cosmetic — it sits behind the real screen content and never
/// intercepts input.
class PantryBackground extends StatelessWidget {
  final Widget child;
  const PantryBackground({super.key, required this.child});

  static const _icons = <IconData>[
    Icons.kitchen,
    Icons.local_grocery_store,
    Icons.bakery_dining,
    Icons.restaurant,
    Icons.local_pizza,
    Icons.egg_outlined,
    Icons.rice_bowl,
    Icons.ramen_dining,
    Icons.lunch_dining,
    Icons.cookie,
    Icons.icecream,
    Icons.local_cafe,
    Icons.emoji_food_beverage,
    Icons.wine_bar,
    Icons.apple,
    Icons.cake,
    Icons.set_meal,
    Icons.breakfast_dining,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.55),
                scheme.tertiaryContainer.withValues(alpha: 0.45),
                scheme.secondaryContainer.withValues(alpha: 0.55),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _PantryIconPainter(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.08),
            ),
            size: Size.infinite,
          ),
        ),
        child,
      ],
    );
  }
}

class _PantryIconPainter extends CustomPainter {
  final Color color;
  _PantryIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Stable pseudo-random so the layout doesn't jitter between rebuilds.
    final rng = Random(42);
    const spacing = 72.0;
    const iconSize = 34.0;

    for (double y = -spacing; y < size.height + spacing; y += spacing) {
      for (double x = -spacing; x < size.width + spacing; x += spacing) {
        final icon = PantryBackground._icons[
            rng.nextInt(PantryBackground._icons.length)];
        final dx = x + rng.nextDouble() * 24 - 12;
        final dy = y + rng.nextDouble() * 24 - 12;
        final tp = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: iconSize,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: color,
            ),
          ),
        )..layout();
        canvas.save();
        canvas.translate(dx + iconSize / 2, dy + iconSize / 2);
        canvas.rotate((rng.nextDouble() - 0.5) * 0.5);
        canvas.translate(-iconSize / 2, -iconSize / 2);
        tp.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PantryIconPainter old) => old.color != color;
}
