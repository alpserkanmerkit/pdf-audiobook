import 'package:flutter/widgets.dart';

/// Android/WCAG minimum tap target (dp).
const double kMinTapTarget = 48;

/// Adds an invisible tap area of at least 48x48 dp around [child] without changing
/// its visual size. Use it
/// INSIDE a `GestureDetector(behavior: HitTestBehavior.opaque)` so the empty edges also
/// receive taps; the semantics node covers this box.
class MinTapArea extends StatelessWidget {
  const MinTapArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: kMinTapTarget,
        minHeight: kMinTapTarget,
      ),
      child: Center(child: child),
    );
  }
}
