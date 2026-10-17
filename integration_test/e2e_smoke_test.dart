// End-to-end SMOKE tests: one file = one build (flutter test compiles and launches
// separately for each integration_test file; putting all flows in one file is
// ~N times faster). To run a single flow: --plain-name 'flow 3'.
// Run with: scripts/e2e.sh (sets env vars + a fake xdg-user-dir).
import 'flows/add_book_flow.dart';
import 'flows/boot_flow.dart';
import 'flows/demo_flow.dart';
import 'flows/provider_flow.dart';
import 'flows/reading_flow.dart';
import 'flows/resume_flow.dart';
import 'flows/tutor_flow.dart';
import 'support/e2e_world.dart';

void main() {
  initE2eBinding();
  bootFlow();
  addBookFlow();
  readingFlow();
  tutorFlow();
  resumeFlow();
  providerFlow();
  demoFlow();
}
