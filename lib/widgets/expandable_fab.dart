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

/// Single primary FAB that fans children upward when tapped. The fanned
/// children + scrim live in an [OverlayEntry] covering the whole screen,
/// because the Scaffold's FAB slot is sized to the primary FAB only and
/// would clip away taps that fall on visually-overflowing children.
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
  OverlayEntry? _entry;

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
    _entry?.remove();
    _entry = null;
    _ctrl.dispose();
    super.dispose();
  }

  bool get _open => _entry != null;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _show();
    }
  }

  void _show() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final fabPos = renderBox.localToGlobal(Offset.zero);
    final fabSize = renderBox.size;
    final screen = MediaQuery.of(context).size;
    final rightEdge = screen.width - (fabPos.dx + fabSize.width);
    final bottomEdge = screen.height - (fabPos.dy + fabSize.height);

    _entry = OverlayEntry(
      builder: (_) => _FabFanOverlay(
        rightEdge: rightEdge,
        bottomEdge: bottomEdge,
        fabHeight: fabSize.height,
        animation: _expand,
        actions: widget.actions,
        onClose: _close,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _ctrl.forward();
    setState(() {}); // refresh primary FAB icon
  }

  Future<void> _close() async {
    if (!_open) return;
    await _ctrl.reverse();
    if (!mounted) return;
    _entry?.remove();
    _entry = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: _toggle,
      tooltip: _open ? 'Close' : widget.tooltip,
      child: AnimatedRotation(
        turns: _open ? 0.125 : 0,
        duration: const Duration(milliseconds: 220),
        child: Icon(_open ? widget.closeIcon : widget.openIcon),
      ),
    );
  }
}

class _FabFanOverlay extends StatelessWidget {
  final double rightEdge;
  final double bottomEdge;
  final double fabHeight;
  final Animation<double> animation;
  final List<FabAction> actions;
  final VoidCallback onClose;

  const _FabFanOverlay({
    required this.rightEdge,
    required this.bottomEdge,
    required this.fabHeight,
    required this.animation,
    required this.actions,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: animation,
              builder: (_, __) => ColoredBox(
                color: Colors.black.withValues(alpha: 0.35 * animation.value),
              ),
            ),
          ),
        ),
        for (var i = 0; i < actions.length; i++)
          AnimatedBuilder(
            animation: animation,
            builder: (_, __) {
              const stepPx = 64.0;
              const baseOffset = 12.0;
              final stagger = i * 0.05;
              final progress = ((animation.value - stagger) / (1.0 - stagger))
                  .clamp(0.0, 1.0);
              // Slot baseline: directly above the primary FAB, then stacked.
              final slotBottom = bottomEdge + fabHeight + baseOffset + stepPx * i;
              // Slide-up entry: start ~24px lower, settle as progress→1.
              final entrySlide = (1 - progress) * 24.0;
              return Positioned(
                right: rightEdge,
                bottom: slotBottom - entrySlide,
                child: Opacity(
                  opacity: progress,
                  child: _ChildAction(
                    action: actions[i],
                    onTap: () {
                      actions[i].onPressed();
                      onClose();
                    },
                    scheme: scheme,
                  ),
                ),
              );
            },
          ),
      ],
    );
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
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                action.label,
                style: TextStyle(color: scheme.onSurface, fontSize: 13),
              ),
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
