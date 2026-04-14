# ForgeFlow

A fully on-device iOS work orchestration platform for field teams and office coordinators to manage service requests, task execution, and documentation without internet dependency.

## Prerequisites

- **macOS** 14.0+ (Sonoma or later)
- **Xcode** 16+ (tested with Xcode 26.3)
- An **iOS Simulator runtime** installed (iOS 17+ supported, iOS 26+ recommended)
- An **iOS Simulator device** created for that runtime

No server, no Docker, no backend, no API keys. Everything runs on-device in SQLite.

## Quick Start

### Option A: Xcode GUI

1. Open `ForgeFlow.xcodeproj` in Xcode
2. Select an iPhone or iPad simulator as the run destination
3. Build and Run (**Cmd+R**)
4. Log in with a demo account (see below)

### Option B: Command Line

```bash
cd repo/

# 1. Check available simulators
xcrun simctl list devices available

# 2. If no devices exist, create one (pick a runtime you have installed):
xcrun simctl create "iPhone 16 Pro" \
  "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro" \
  "com.apple.CoreSimulator.SimRuntime.iOS-26-3"

# 3. Boot the simulator and open Simulator.app
xcrun simctl boot <DEVICE_ID>
open -a Simulator

# 4. Build
xcodebuild build \
  -scheme ForgeFlow \
  -destination "platform=iOS Simulator,id=<DEVICE_ID>" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO

# 5. Install and launch
xcrun simctl install <DEVICE_ID> \
  ~/Library/Developer/Xcode/DerivedData/ForgeFlow-*/Build/Products/Debug-iphonesimulator/ForgeFlow.app
xcrun simctl launch <DEVICE_ID> com.forgeflow.app
```

Replace `<DEVICE_ID>` with the UUID from step 1 or 2.

## Demo Accounts

Seeded automatically on first launch (debug builds only):

| Username | Password      | Role          | Tabs                                              |
|----------|--------------|---------------|----------------------------------------------------|
| admin    | ForgeFlow1   | Administrator | Dashboard, Postings, Calendar, Messaging, Plugins, Sync |
| coord1   | Coordinator1 | Coordinator   | Dashboard, Postings, Calendar, Messaging, Sync     |
| tech1    | Technician1  | Technician    | Dashboard, Postings, Calendar, Messaging            |
| tech2    | Technician2  | Technician    | Dashboard, Postings, Calendar, Messaging            |

### Seed Data Included

- 5 service postings (1 draft, 2 open, 1 in-progress, 1 completed)
- 10 tasks with mixed statuses, 2 dependency chains, 1 blocked with comment
- 5 comments across postings
- 8 notifications (delivered, seen, pending)
- 2 plugins (1 active with 3 fields, 1 pending approval with step 1 done)
- 2 invited technicians on the invite-only posting

## Running Tests

### Quick (auto-detects simulator)

```bash
./run_tests.sh           # All tests
./run_tests.sh --unit    # Unit tests only
./run_tests.sh --integration  # Integration tests only
./run_tests.sh --views   # View tests only
```

### Manual (specify simulator)

```bash
xcodebuild test \
  -scheme ForgeFlow \
  -destination "platform=iOS Simulator,id=<DEVICE_ID>" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

### What to Expect

- **141 tests** across 22 suites
- Unit, integration, and view test layers
- Auth integration tests may show `saveFailed(status: -34018)` — this is a known iOS Simulator Keychain limitation when running outside Xcode's managed signing. The app itself works around this with a UserDefaults fallback in debug builds.

## Troubleshooting

### "No available iOS simulator found"
Install a simulator runtime: **Xcode > Settings > Platforms > iOS** and download a runtime. Then create a device:
```bash
xcrun simctl create "iPhone 16 Pro" \
  "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro" \
  "com.apple.CoreSimulator.SimRuntime.iOS-26-3"
```

### "Invalid username or password" on first launch
The app data may be stale from a previous build. Reset by uninstalling and reinstalling:
```bash
xcrun simctl uninstall <DEVICE_ID> com.forgeflow.app
xcrun simctl install <DEVICE_ID> <path-to-ForgeFlow.app>
xcrun simctl launch <DEVICE_ID> com.forgeflow.app
```

### Build fails with "Unable to find a destination"
Xcode requires a simulator runtime matching its SDK version. Check available runtimes with `xcrun simctl list runtimes` and ensure you have a device for one of them.

## Project Structure

```
ForgeFlow/
  App/              - Entry point (ForgeFlowApp), AppState, Seeder
  Models/           - GRDB data models, enums, error types
  Database/
    Migrations/     - 9 sequential schema migrations (001-009)
    Repositories/   - Data access layer (one per entity)
    DatabaseManager  - GRDB pool setup, migration runner
    Seeder          - Debug seed data
  Services/         - Business logic (Auth, Posting, Task, Assignment,
                      Comment, Attachment, Notification, Plugin, Sync)
  ViewModels/       - @Observable view models (MVVM pattern)
  Views/
    Auth/           - Login, lock screen, user management
    Postings/       - Posting list, detail, form
    Tasks/          - Task list, todo center
    Calendar/       - Calendar view
    Messaging/      - Notification inbox, DND settings
    Plugins/        - Plugin list, editor, test, approval
    Sync/           - Export, import, conflict resolution
    Components/     - Reusable UI components
  BackgroundTasks/  - BGProcessingTask handlers (cleanup, compression,
                      cache eviction, file chunking)
  Utilities/        - Keychain, formatters, validators, hash helpers
  Resources/        - Asset catalog, color sets

ForgeFlowTests/
  UnitTests/        - Pure logic tests (no DB)
  IntegrationTests/ - Full-stack tests with in-memory DB
  ViewTests/        - ViewModel + view logic tests
```

## Documentation

| Document | Contents |
|---|---|
| `../docs/design.md` | Architecture, state machines, pipelines, security model (threat matrix, role trust levels) |
| `../docs/api-spec.md` | HTTP/service API surface, request/response contracts, error codes |

Design decisions and data contracts are also documented inline via `MARK:` sections and comments throughout the source.
