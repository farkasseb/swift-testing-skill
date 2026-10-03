#!/usr/bin/env bash
# Verifies the skill's code samples and behavioral claims against an installed Xcode.
#
# Xcode selection, first match wins:
#   XCODE=/Applications/Xcode.app tests/run.sh
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tests/run.sh
#   otherwise: xcode-select -p
# Requires Swift 6.3 or later on macOS. Swift 6.4-only checks are skipped on 6.3.
# Set TEST_LOG_DIR to preserve full logs; otherwise temporary logs are removed.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

if [[ -n "${XCODE:-}" ]]; then
    export DEVELOPER_DIR="$XCODE/Contents/Developer"
elif [[ -z "${DEVELOPER_DIR:-}" ]]; then
    DEVELOPER_DIR="$(xcode-select -p)"
    export DEVELOPER_DIR
fi

version_line="$(xcrun swift --version 2>&1 | grep -m1 'Swift version')"
swift_version="$(sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1.\2/p' <<<"$version_line")"
major="${swift_version%%.*}"
minor="${swift_version##*.}"
if [[ -z "$swift_version" ]] || (( major < 6 || (major == 6 && minor < 3) )); then
    echo "Needs Swift 6.3 or later; found: ${version_line:-none} ($DEVELOPER_DIR)" >&2
    exit 2
fi

echo "Developer dir: $DEVELOPER_DIR"
echo "Toolchain:     $version_line"
echo

scratch="$(mktemp -d)"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then
    mkdir -p "$TEST_LOG_DIR"
    logs="$(cd "$TEST_LOG_DIR" && pwd)"
else
    logs="$scratch"
fi
trap 'rm -Rf "$scratch"' EXIT

passed=0
failed=0
pass() { echo "PASS  $1"; passed=$((passed + 1)); }
fail() { echo "FAIL  $1"; failed=$((failed + 1)); }

# 1. Code samples and behavioral checks.
log="$logs/snippets.log"
if xcrun swift test --package-path "$here/Snippets" --scratch-path "$scratch/snippets" >"$log" 2>&1; then
    pass "samples compile and all checks pass (tests/Snippets)"
else
    fail "tests/Snippets; see output below"
    grep -E 'error:|recorded an issue|failed' "$log" | head -40
fi
if grep -q 'availabilityGated() skipped: "Requires macOS 99"' "$log"; then
    pass "@available on a test skips it on older systems"
else
    fail "@available skip was not reported"
fi

# 2. XCTAssert inside @Test under each interop mode (packages).
run_interop() { # name, package dir, expected result, expected warnings, optional mode
    local name="$1" dir="$2" expected="$3" warnings="$4" mode="${5:-}"
    local output="$logs/$name.log" status
    if [[ -n "$mode" ]]; then
        env SWIFT_TESTING_XCTEST_INTEROP_MODE="$mode" xcrun swift test --package-path "$dir" --scratch-path "$scratch/$name" >"$output" 2>&1
    else
        env -u SWIFT_TESTING_XCTEST_INTEROP_MODE xcrun swift test --package-path "$dir" --scratch-path "$scratch/$name" >"$output" 2>&1
    fi
    status=$?
    if [[ "$expected" == failed ]] && (( status == 0 )); then
        fail "$name: expected a failing process; see $output"
    elif [[ "$expected" == passed ]] && (( status != 0 )); then
        fail "$name: unexpected process failure; see $output"
    elif ! grep -q "Test xctAssertInsideTest() $expected" "$output"; then
        fail "$name: expected named test to $expected; see $output"
    elif [[ "$warnings" == yes ]] && ! grep -q 'recorded a warning' "$output"; then
        fail "$name: expected runtime interop warning; see $output"
    else
        pass "$name: $expected (runtime warning required: $warnings)"
    fi
}

if (( major > 6 || minor >= 4 )); then
    run_interop tools60 "$here/Interop/Tools60" passed yes
    run_interop tools64 "$here/Interop/Tools64" failed yes
    run_interop tools60-complete "$here/Interop/Tools60" failed yes complete
else
    run_interop tools60 "$here/Interop/Tools60" passed no
    run_interop tools60-complete-ignored "$here/Interop/Tools60" passed no complete
    echo "SKIP  Swift 6.4 interop modes, Transferable attachment and CustomTestReflectable samples"
fi

# 3. Availability read from the SDK's Testing interfaces.
frameworks="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/Library/Frameworks"
testing_ios="$frameworks/Testing.framework/Modules/Testing.swiftmodule/arm64-apple-ios.swiftinterface"
transferable_ios="$frameworks/_Testing_CoreTransferable.framework/Modules/_Testing_CoreTransferable.swiftmodule/arm64-apple-ios.swiftinterface"

if grep -B1 'macro expect(processExitsWith' "$testing_ios" | grep -q 'unavailable'; then
    pass "exit tests are unavailable on iOS"
else
    fail "exit tests on iOS: unavailable attribute not found"
fi
if grep -q 'unavailable, message: "Time limit must be specified in minutes"' "$testing_ios"; then
    pass ".timeLimit sub-minute durations are unavailable"
else
    fail ".timeLimit: unavailable sub-minute durations not found"
fi
if (( major == 6 && minor < 4 )); then
    echo "SKIP  Swift 6.4 Transferable attachment overlay"
elif grep -q '@available(macOS 15.2, iOS 18.2' "$transferable_ios"; then
    pass "Transferable attachments require iOS 18.2 / macOS 15.2"
else
    fail "Transferable attachment availability not found"
fi

minos() { otool -l "$1" 2>/dev/null | awk '/LC_BUILD_VERSION/ {f=1} f && /minos/ {print $2; exit}'; }
echo "INFO  Testing.framework minimum iOS:   $(minos "$frameworks/Testing.framework/Testing")"
echo "INFO  Testing.framework minimum macOS: $(minos "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework/Testing")"

echo
echo "$passed passed, $failed failed"
[[ -n "${TEST_LOG_DIR:-}" ]] && echo "Logs: $logs"
(( failed == 0 ))
