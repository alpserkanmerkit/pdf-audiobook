.PHONY: deps analyze format test probe e2e e2e-linux check doctor demo demo-shot demo-test demo-smoke

FLUTTER ?= flutter
DART ?= dart

# Dependencies (first setup / after a pubspec change).
deps:
	$(FLUTTER) pub get

# Static analysis (same as CI).
analyze:
	$(FLUTTER) analyze

# Format check (fails if changes are needed).
format:
	$(DART) format --output=none --set-exit-if-changed lib test

# Unit and widget tests (same as CI).
test:
	$(FLUTTER) test

# Scenario probe: runs end-to-end scenarios that unit tests do not catch.
probe:
	$(DART) run tool/senaryo_probe.dart

# Steps run by CI.
check: analyze test

# End-to-end smoke tests (integration_test/). Default: deviceless flutter_tester VM.
# --linux mode needs a native Linux build + xvfb (packages: scripts/e2e-apt.txt).
e2e:
	bash scripts/e2e.sh

e2e-linux:
	bash scripts/e2e.sh --linux

# DEMO mode (no API key REQUIRED; fake answers, silent audio; entry point lib/main_demo.dart).
# The device is picked from the OS; override with DEMO_DEVICE=linux|windows|macos.
demo:
	bash scripts/demo.sh

# Headless (xvfb) startup proof: builds the Linux binary and takes a PNG -> docs/demo/acilis.png.
demo-shot:
	bash scripts/demo-shot.sh

# Demo tests: unit/widget (test/demo) + end-to-end demo flow (deviceless VM).
demo-test:
	$(FLUTTER) test test/demo
	bash scripts/e2e.sh --plain-name 'flow 7'

# Demo smoke test run by CI (headless; test + startup PNG + demo flow).
demo-smoke:
	bash scripts/demo-smoke.sh

# Environment check: tool versions.
doctor:
	@$(FLUTTER) --version
	@$(DART) --version
