# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## App Purpose

**Payday** is a native iOS app that integrates with the Monzo personal developer API to automate payday fund sorting. On payday, the user launches the app, confirms their salary deposit, and the app distributes funds into configured Monzo pots using fixed or percentage-based allocation rules.

## Build & Test Commands

This is a pure `.xcodeproj` project (no Swift Package Manager manifest at the project level).

```bash
# Build
xcodebuild -project Payday.xcodeproj -scheme Payday -configuration Debug build

# Run all tests (unit + UI) on simulator
xcodebuild -project Payday.xcodeproj -scheme Payday -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run unit tests only
xcodebuild test -project Payday.xcodeproj -scheme PaydayTests -destination 'platform=iOS Simulator,name=iPhone 16'
```

Use `Cmd+B` / `Cmd+U` in Xcode for interactive development.

## Architecture

SwiftUI + MVVM, no external dependencies. All Monzo API calls happen directly from the app (no backend).

**Planned folder layout** (defined in `MONZO_PROJECT.md`, not yet implemented):

```
Payday/
├── App/          # @main entry point
├── Auth/         # AuthManager (OAuth flow), KeychainHelper (token storage)
├── Services/     # MonzoService — all URLSession API calls
├── Models/       # Account, Balance, Pot, Transaction (Codable structs)
├── ViewModels/   # DashboardViewModel, SortViewModel (ObservableObject)
├── Views/        # DashboardView, TransactionSearchView, SortView
└── Components/   # PotCard, TransactionRow (reusable SwiftUI views)
```

The current repo only has the Xcode default CoreData scaffold (`ContentView.swift`, `Persistence.swift`). This boilerplate should be replaced when implementing the actual features.

## Key Constraints

- **Money is always in pence** (integer). The Monzo API requires `PUT /pots/{pot_id}/deposit` amounts in pence, not pounds.
- **Percentage allocations** are resolved against the selected salary transaction amount, not the total account balance.
- **Pre-sort validation** must check that `sum(allocations) <= current account balance` before dispatching any deposits.
- **Pot deposits are dispatched sequentially** — abort and surface error to user on any failure.
- Monzo personal API tokens expire and require manual re-auth via an email link (no programmatic refresh flow).
- Filter deleted pots from `GET /pots` responses before displaying.

## Monzo API Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/accounts` | GET | Get account ID |
| `/balance` | GET | Current balance |
| `/pots` | GET | List pots (filter `deleted: true`) |
| `/transactions` | GET | Search salary deposits (last 30 days) |
| `/pots/{pot_id}/deposit` | PUT | Move money into a pot |

## Swift Configuration

- Swift 5.0, iOS 26.0 deployment target, iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 6 strict concurrency enabled)
- Use `async/await` and `@MainActor` for all async work
- Authentication uses `ASWebAuthenticationSession` (import `AuthenticationServices`)
- Tokens stored in Keychain (no UserDefaults for sensitive data)

## Testing

- **Unit tests** (`PaydayTests/`): Swift Testing framework (`import Testing`, `@Test` macro)
- **UI tests** (`PaydayUITests/`): XCTest
