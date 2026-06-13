# Spotlite

A lightweight **native macOS** Spotify client built with SwiftUI. Playback runs through Spotify’s Web Playback SDK inside a hidden `WKWebView`; everything else is native Swift.

## Requirements

- macOS 14+
- Xcode 16+
- **Spotify Premium** account
- A **Spotify Developer Client ID** ([dashboard](https://developer.spotify.com/dashboard))

## Spotify app setup

1. Create an app in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
2. Under **Settings → Redirect URIs**, add exactly:
   ```
   spotlite://callback
   ```
3. Enable **Web API** and **Web Playback SDK**.
4. Copy the **Client ID** (not the client secret — this app uses PKCE).

> Dev-mode Spotify apps are limited to 5 users. That’s fine for personal use.

## Run

1. Open `spotlite.xcodeproj` in Xcode.
2. Select the **spotlite** scheme and **My Mac** as destination.
3. Build & Run (`⌘R`).
4. Paste your Client ID on the login screen and click **Connect with Spotify**.

## Features

| Feature | Status |
|---|---|
| OAuth PKCE login + Keychain token storage | ✅ |
| Web Playback SDK (local playback device) | ✅ |
| Home — recently played | ✅ |
| Search — tracks, albums, artists, playlists | ✅ |
| Liked songs library | ✅ |
| Playlists grid + detail | ✅ |
| Album & artist detail pages | ✅ |
| Now playing bar — play/pause, skip, seek, volume | ✅ |
| Queue view + add to queue | ✅ |
| Like / unlike tracks | ✅ |
| Keyboard shortcuts | ✅ |
| Settings — Client ID, sign out | ✅ |

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Space` | Play / Pause |
| `⌘→` | Next track |
| `⌘←` | Previous track |
| `⌘L` | Like / Unlike current track |
| `⌘1–4` | Home / Search / Liked / Playlists |
| `⌘F` | Go to Search |

## Architecture

```
SwiftUI UI ──► AppModel ──► SpotifyAPIClient (REST)
                    │
                    └──► PlaybackCoordinator ──► WebPlaybackBridge (WKWebView + SDK)
```

- **Native shell**: sidebar navigation, lists, artwork, controls.
- **Hidden WebView**: only for Spotify Web Playback SDK (required by Spotify for third-party playback).
- **No Electron, no bundled Chromium.**

## Project layout

```
spotlite/
  spotlite/
    Services/     Auth, API, Web Playback bridge
    State/        AppModel
    Views/        SwiftUI screens
    Resources/    WebPlayback.html
  Info.plist      URL scheme: spotlite://
  spotlite.xcodeproj
```

## License

MIT
