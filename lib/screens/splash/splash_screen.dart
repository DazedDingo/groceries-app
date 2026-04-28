import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart' show pendingInviteToken;

/// Animated cold-start splash. Tells the brand story in ~2.6s:
///   1. A finger taps a phone — "the user opens the app".
///   2. The "Groceries" wordmark materialises out of the phone.
///   3. The wordmark drops into a shopping cart.
/// Then redirects to /login (or to /setup with the token if the cold-start
/// deep link queued one).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2600);

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duration)
      ..forward().whenComplete(_advance);
  }

  void _advance() {
    if (!mounted) return;
    final token = pendingInviteToken;
    if (token != null && _tokenPattern.hasMatch(token)) {
      pendingInviteToken = null;
      context.go('/setup?token=$token');
    } else {
      context.go('/login');
    }
  }

  static final _tokenPattern = RegExp(r'^[a-zA-Z0-9]{20,64}$');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => GestureDetector(
            onTap: _advance, // tap-to-skip
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                _Phone(t: _ctrl.value, scheme: scheme),
                _Finger(t: _ctrl.value, scheme: scheme),
                _Title(t: _ctrl.value, scheme: scheme),
                _Cart(t: _ctrl.value, scheme: scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 0.0 → 1.0 segment helper. Returns a normalised local progress for the
/// sub-window [start, end] of an outer animation, eased with easeOutCubic.
double _segment(double t, double start, double end, {Curve curve = Curves.easeOutCubic}) {
  if (t <= start) return 0;
  if (t >= end) return 1;
  return curve.transform((t - start) / (end - start));
}

/// Phone screen sitting centre. Subtle press-down on the tap (0.20–0.35).
class _Phone extends StatelessWidget {
  final double t;
  final ColorScheme scheme;
  const _Phone({required this.t, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final tapped = _segment(t, 0.20, 0.35, curve: Curves.easeInOut);
    final released = _segment(t, 0.35, 0.45, curve: Curves.easeOutBack);
    final scale = 1.0 - 0.08 * tapped + 0.08 * released;
    final fadeOut = _segment(t, 0.55, 0.75);
    return Center(
      child: Transform.translate(
        offset: const Offset(0, -40),
        child: Opacity(
          opacity: 1 - fadeOut,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 120,
              height: 200,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.shopping_basket,
                      size: 32, color: scheme.onPrimaryContainer),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Finger that slides in from the bottom-right and taps the phone. Visible
/// over [0.0–0.55], tap impact at 0.25, then retreats.
class _Finger extends StatelessWidget {
  final double t;
  final ColorScheme scheme;
  const _Finger({required this.t, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final approach = _segment(t, 0.0, 0.25);
    final retreat = _segment(t, 0.35, 0.55);
    // Approach: travel from offscreen-bottom-right to centre.
    // Retreat: travel back outward.
    final dx = 200 * (1 - approach) + 200 * retreat;
    final dy = 240 * (1 - approach) + 240 * retreat;
    final fadeOut = _segment(t, 0.50, 0.65);
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(dx, dy - 40),
        child: Opacity(
          opacity: 1 - fadeOut,
          child: Icon(
            Icons.touch_app,
            size: 64,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

/// "Groceries" wordmark that materialises from the phone (0.50–0.70) and
/// then descends into the cart (0.75–1.0).
class _Title extends StatelessWidget {
  final double t;
  final ColorScheme scheme;
  const _Title({required this.t, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final appear = _segment(t, 0.50, 0.70, curve: Curves.easeOutBack);
    final drop = _segment(t, 0.75, 1.0, curve: Curves.easeInCubic);
    if (appear == 0) return const SizedBox.shrink();

    final size = MediaQuery.of(context).size;
    // Start at phone centre (-40 from screen centre), drop towards the cart
    // near the bottom. Cart sits at +180 below centre.
    final dy = -40.0 + (220 * drop);
    // Shrink as it drops into the cart.
    final scale = 1.0 - 0.7 * drop;
    // Fade out the last 10% so the text doesn't visibly clip the cart icon.
    final opacity = (1 - _segment(t, 0.92, 1.0)).clamp(0.0, 1.0);

    return Center(
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Opacity(
          opacity: appear * opacity,
          child: Transform.scale(
            scale: 0.6 + 0.4 * appear * scale,
            child: Text(
              'Groceries',
              style: TextStyle(
                fontSize: size.width < 360 ? 30 : 36,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shopping cart icon that emerges at the bottom-centre once the title is
/// dropping in. Briefly bounces when the title lands.
class _Cart extends StatelessWidget {
  final double t;
  final ColorScheme scheme;
  const _Cart({required this.t, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final emerge = _segment(t, 0.65, 0.80, curve: Curves.easeOutBack);
    final bounce = _segment(t, 0.92, 1.0, curve: Curves.elasticOut);
    if (emerge == 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: const Offset(0, 180),
        child: Transform.scale(
          scale: 0.8 + 0.2 * emerge + 0.06 * bounce,
          child: Opacity(
            opacity: emerge,
            child: Icon(
              Icons.shopping_cart,
              size: 96,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
