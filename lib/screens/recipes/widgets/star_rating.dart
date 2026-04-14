import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 5-star widget. When [onChanged] is null, it's display-only.
/// [value] of 0 means "not rated" — all stars shown empty.
class StarRating extends StatelessWidget {
  final double value;
  final void Function(int rating)? onChanged;
  final double size;
  final Color? color;

  const StarRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.amber;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        IconData icon;
        if (value >= starIndex) {
          icon = Icons.star;
        } else if (value >= starIndex - 0.5) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_border;
        }
        final star = Icon(icon, size: size, color: c);
        if (onChanged == null) return Padding(padding: const EdgeInsets.all(1), child: star);
        return InkResponse(
          radius: size,
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged!(starIndex);
          },
          child: Padding(padding: const EdgeInsets.all(1), child: star),
        );
      }),
    );
  }
}
