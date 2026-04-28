import 'package:flutter/material.dart';

/// Action shown in an [ExpandableFab] fan. Each child becomes a small FAB
/// labelled with [label]; tapping it auto-collapses the fan and runs
/// [onPressed].
class FabAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final String heroTag;
  const FabAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.heroTag,
  });
}

/// Single primary FAB that fans children upward when tapped. Backdrop scrim
/// dismisses on tap, ESC-style. Children stagger so the closest one lands
/// first — feels like an unfolding hand of cards rather than a teleport.
class ExpandableFab extends StatefulWidget {
  final List<FabAction> actions;
  final IconData openIcon;
  final IconData closeIcon;
  final String tooltip;

  const ExpandableFab({
    super.key,
    required this.actions,
    this.openIcon = Icons.add,
    this.closeIcon = Icons.close,
    this.tooltip = 'Add',
  });

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _expand;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 240),
      vsync: this,
    );
    _expand = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomRight,
      children: [
        // Backdrop scrim — only hit-tests when open so it doesn't swallow
        // gestures behind the page when collapsed.
        if (_open)
          Positioned.fill(
            // Anchor scrim to a much larger area than the FAB itself so
            // taps anywhere on the screen close the fan. The negative offsets
            // expand the hit area into the rest of the Scaffold body.
            left: -2000,
            top: -2000,
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: AnimatedBuilder(
                animation: _expand,
                builder: (_, __) => Container(
                  color: Colors.black.withValues(alpha: 0.35 * _expand.value),
                ),
              ),
            ),
          ),
        ..._buildChildren(scheme),
        FloatingActionButton(
          onPressed: _toggle,
          tooltip: _open ? 'Close' : widget.tooltip,
          child: AnimatedRotation(
            turns: _open ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            child: Icon(_open ? widget.closeIcon : widget.openIcon),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildChildren(ColorScheme scheme) {
    const stepPx = 64.0; // spacing between each child FAB
    const baseOffset = 72.0; // distance above the primary FAB
    return [
      for (var i = 0; i < widget.actions.length; i++)
        AnimatedBuilder(
          animation: _expand,
          builder: (_, __) {
            // Staggered curve: child i animates over [i * 0.05, 1.0] so the
            // bottom one fully lands before the top one finishes.
            final stagger = i * 0.05;
            final progress = ((_expand.value - stagger) / (1.0 - stagger))
                .clamp(0.0, 1.0);
            final dy = -(baseOffset + stepPx * i) * progress;
            return Positioned(
              right: 4,
              bottom: 4,
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Opacity(
                  opacity: progress,
                  child: IgnorePointer(
                    ignoring: !_open,
                    child: _ChildAction(
                      action: widget.actions[i],
                      onTap: () {
                        _close();
                        widget.actions[i].onPressed();
                      },
                      scheme: scheme,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ];
  }
}

class _ChildAction extends StatelessWidget {
  final FabAction action;
  final VoidCallback onTap;
  final ColorScheme scheme;
  const _ChildAction({
    required this.action,
    required this.onTap,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Material(
          color: scheme.surface,
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              action.label,
              style: TextStyle(color: scheme.onSurface, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: action.heroTag,
          onPressed: onTap,
          tooltip: action.label,
          child: Icon(action.icon),
        ),
      ],
    );
  }
}

