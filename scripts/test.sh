#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/oh-my-grid-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$TEST_DIR" <<'PY'
import pathlib, subprocess, sys
# Compile the tested app logic without starting lifecycle or updater integrations.
# The complete app, including Sparkle, is validated by the Release build.
integrations = {'Sources/App/main.swift', 'Sources/App/AppDelegate.swift',
                'Sources/App/MenuBarController.swift', 'Sources/App/UpdaterController.swift',
                'Sources/Settings/PreferencesWindowController.swift'}
sources = sorted(str(p) for p in pathlib.Path('Sources').rglob('*.swift') if str(p) not in integrations)
binary = str(pathlib.Path(sys.argv[1]) / 'OhMyGridRegression')
subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', '-module-name', 'OhMyGridRegression', *sources, 'Tests/RegressionTests.swift', '-o', binary], check=True)
subprocess.run([binary], check=True)
PY
