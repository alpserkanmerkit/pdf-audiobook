// pumpAndSettle replacement with a fixed, short frame sequence (speed-3).
//
// pumpAndSettle pumps 16 ms frames until no frame is scheduled (for transition/dialog
// animations, ~20 frames). Here the animations are NOT continuous (no infinite
// animation), so the first frame (builds the tree) plus two large-step frames (finishes
// the animation; the ticker advances on the second frame) reach the same final state in
// 3 frames. DO NOT USE on screens with an infinite animation (test writing principles §6:
// pump(Duration) -- already a fixed frame).
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpFast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// The COARSE-STEP form of pumpAndSettle (speed-4): same logic ("pump frames until no
/// frame is scheduled"; an infinite animation still times out), the only difference is
/// 400 ms steps instead of 100 ms. On a quiet tree it takes 1 frame (same as
/// pumpAndSettle); during transition/dialog/avatar animation ~3 frames (pumpAndSettle
/// ~8). Every frame is a full-screen rebuild cost; the final state is the same
/// (animations finish within 400 ms steps), only the fake clock advances in bigger jumps.
Future<int> pumpSettle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 400));
