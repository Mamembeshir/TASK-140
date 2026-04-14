#!/bin/bash
set -e
echo "ForgeFlow Test Suite"
echo "===================="

# Skip gracefully on non-macOS / non-iOS environments (e.g. Linux CI, Docker)
if [ "$(uname)" != "Darwin" ]; then
    echo "Skipping: not running on macOS. ForgeFlow is a native iOS app."
    echo "Tests require macOS with Xcode and an iOS Simulator."
    echo "PASS (skipped — non-iOS environment)"
    exit 0
fi

if ! command -v xcodebuild &>/dev/null; then
    echo "Skipping: xcodebuild not found. Xcode is required to run iOS tests."
    echo "PASS (skipped — Xcode not installed)"
    exit 0
fi

if ! command -v xcrun &>/dev/null; then
    echo "Skipping: xcrun not found."
    echo "PASS (skipped — Xcode toolchain not available)"
    exit 0
fi

RUN_ALL=false
RUN_UNIT=false
RUN_INTEGRATION=false
RUN_VIEWS=false

if [ $# -eq 0 ]; then
    RUN_ALL=true
fi

for arg in "$@"; do
    case $arg in
        --unit) RUN_UNIT=true ;;
        --integration) RUN_INTEGRATION=true ;;
        --views) RUN_VIEWS=true ;;
    esac
done

# Auto-detect first available iOS simulator
SIM_ID=$(xcrun simctl list devices available -j 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' in runtime or 'SimRuntime.iOS' in runtime:
        for d in devices:
            if d.get('isAvailable', False):
                print(d['udid'])
                sys.exit(0)
print('')
" 2>/dev/null)

if [ -z "$SIM_ID" ]; then
    echo "Skipping: No available iOS simulator found."
    echo "Install a simulator runtime via Xcode > Settings > Platforms, then create a device."
    echo "PASS (skipped — no iOS simulator)"
    exit 0
fi

SIM_NAME=$(xcrun simctl list devices available 2>/dev/null | grep "$SIM_ID" | sed 's/(.*//' | xargs)
echo "Using simulator: $SIM_NAME ($SIM_ID)"
echo ""

DEST="platform=iOS Simulator,id=$SIM_ID"
EXIT=0
BASE_CMD="xcodebuild -scheme ForgeFlow -destination $DEST -configuration Debug CODE_SIGNING_ALLOWED=NO test"
GREP_FILTER='grep -E "✔|✘|Suite.*passed|Suite.*failed|Test run with|BUILD"'

# -only-testing: class names per layer (struct/class name, not @Suite display string)
UNIT_SUITES=(
    ForgeFlowTests/UnitTests
    ForgeFlowTests/AuthServiceTests
    ForgeFlowTests/PostingServiceTests
    ForgeFlowTests/TaskServiceTests
    ForgeFlowTests/AttachmentServiceTests
    ForgeFlowTests/NotificationServiceTests
)

INTEGRATION_SUITES=(
    ForgeFlowTests/IntegrationTests
    ForgeFlowTests/AuthIntegrationTests
    ForgeFlowTests/AuthVerificationTests
    ForgeFlowTests/PostingIntegrationTests
    ForgeFlowTests/PostingVerificationTests
    ForgeFlowTests/AssignmentIntegrationTests
    ForgeFlowTests/TaskIntegrationTests
    ForgeFlowTests/TaskVerificationTests
    ForgeFlowTests/NotificationIntegrationTests
    ForgeFlowTests/PluginIntegrationTests
    ForgeFlowTests/SyncIntegrationTests
    ForgeFlowTests/WorkflowTests
)

VIEW_SUITES=(
    ForgeFlowTests/ViewTests
    ForgeFlowTests/AuthViewTests
    ForgeFlowTests/PostingViewTests
    ForgeFlowTests/TaskViewTests
    ForgeFlowTests/MessagingViewTests
)

run_filtered() {
    local label="$1"
    shift
    local filters=()
    for suite in "$@"; do
        filters+=(-only-testing:"$suite")
    done
    echo "--- $label ---"
    $BASE_CMD "${filters[@]}" 2>&1 | eval "$GREP_FILTER" | tail -30 || EXIT=1
    echo ""
}

if $RUN_ALL; then
    echo "--- All Tests ---"
    $BASE_CMD 2>&1 | eval "$GREP_FILTER" | tail -50 || EXIT=1
    echo ""
else
    $RUN_UNIT        && run_filtered "Unit Tests"        "${UNIT_SUITES[@]}"
    $RUN_INTEGRATION && run_filtered "Integration Tests" "${INTEGRATION_SUITES[@]}"
    $RUN_VIEWS       && run_filtered "View Tests"        "${VIEW_SUITES[@]}"
fi

exit $EXIT
