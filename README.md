# Codex Quota Bar

A native macOS menu bar app for viewing the remaining usage limits of your signed-in ChatGPT/Codex account. It reads quota data from the Codex service through `codex app-server`; it does not estimate usage from local logs or token counts.

## Requirements

- macOS 13 or later and Xcode Command Line Tools
- An installed Codex executable and a ChatGPT sign-in (`codex login`)

API-key-only sign-in does not provide ChatGPT subscription limits. The app searches common Codex installation paths and `PATH`; you can also select the executable in Settings.

## Build and run

From the repository root:

```sh
./scripts/build-debug.sh
open build/Debug/CodexQuotaBar.app
```

The script creates a locally signed **Debug** app at `build/Debug/CodexQuotaBar.app`. No release build or distribution package is produced. The app runs in the menu bar without a Dock icon. Click the menu bar value and choose the option to open the main window and settings.

## Features

- Shows the used percentage, remaining percentage, and reset time for each quota window returned by the service.
- Supports automatic refresh, a custom interval in seconds, and manual refresh. A failed refresh is marked as stale rather than presented as current data.
- Offers standard, compact, Chinese, and two-line menu bar layouts. Show both windows, only 5-hour, or only weekly quota; optionally hide missing windows and display percentages without labels.
- Includes an optional movable desktop panel. This is an in-app panel, not a macOS WidgetKit extension, and it closes when the app exits.

The service may omit a window. In that case the app shows `—` where needed; it never infers an unavailable quota or assumes a reset has occurred.

## Data and privacy

Each refresh starts a short-lived `codex app-server` process, checks the active account with `account/read`, and requests server-provided limits with `account/rateLimits/read`. The app supports both `rateLimitsByLimitId` and the older `rateLimits` response. Displayed remaining percentages are calculated as `100 − usedPercent` from that response.

The app uses the selected Codex installation's existing sign-in. It does not ask for, copy, or store credentials, and it does not persist quota snapshots. Display preferences and the selected executable path are saved locally. See the [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server) for the protocol.

## Development

```sh
swift test -c debug
.build/debug/CodexQuotaBar --probe
```

`--probe` uses the same service-reading code as the app and prints the returned windows without printing the account email or credentials.
