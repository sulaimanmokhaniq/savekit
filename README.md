# SaveKit

An Android app that downloads media entirely on the device. There is no backend and no
third-party API: extraction, multi-connection downloading and stream merging all run locally.

## How it works

| Layer | What it does |
| --- | --- |
| Embedded engine | `youtubedl-android` bundles Python + yt-dlp, FFmpeg and aria2c as native libraries. Kotlin (`android/app/src/main/kotlin/com/savekit/app`) exposes them to Flutter. |
| Photo engine | gallery-dl runs on the same embedded Python for photo posts and carousels (Instagram, X, TikTok, Snapchat and more). Its bundle lives in `android/app/src/main/assets/gallerydl`; rebuild it with `tool/build_gallery_dl_bundle.sh`. |
| Cookie manager | An in-app WebView login exports session cookies to a Netscape `cookies.txt`, passed to yt-dlp for content that needs an account. |

### Native bridge

`MethodChannel` `com.app.downloader/engine`

| Method | Arguments | Returns |
| --- | --- | --- |
| `initEngine` | none | `{initialized, version, galleryVersion}` |
| `getEngineVersion` | none | yt-dlp version string |
| `updateEngine` | none | `{status, updated, version, galleryUpdated, galleryVersion, galleryError}` (nightly yt-dlp, latest gallery-dl) |
| `getMediaInfo` | `url`, `cookiesFilePath?` | metadata + `videoOptions`, `noWatermarkOption`, `audioOptions`, `galleryOption`, `galleryItems`, `formats` |
| `startDownload` | `taskId`, `url`, `formatSelection`, `outputDir`, `cookiesFilePath?`, `extractAudio`, `formatSort?`, `audioFormat?`, `engine?` (`ytdlp` \| `gallerydl`), `itemCount?` | `true` once queued |
| `cancelDownload` | `taskId` | whether a process was killed |

`EventChannel` `com.app.downloader/progress` emits
`{taskId, status, progressPercent, speed, eta}` plus `filePath`/`filePaths`/`fileSize` on
`completed` and `error` on `failed`. Status is one of `starting`, `downloading`, `processing`,
`completed`, `failed`, `canceled`.

## Project layout

```
android/app/src/main/kotlin/com/savekit/app/
  MainActivity.kt        channel wiring
  DownloadEngine.kt      yt-dlp / aria2c / FFmpeg execution and progress
  MediaInfoParser.kt     yt-dlp JSON -> format options
  GalleryEngine.kt       gallery-dl: photo posts, carousels, self-update
lib/
  core/                  theme, native service, shared utilities
  features/extractor/    URL -> media info and format picker
  features/downloader/   queue and active downloads
  features/vault/        completed media
  features/cookies/      platform logins and cookies.txt export
```

## Building

```bash
flutter pub get
```

```bash
flutter build apk --release
```

Requires Flutter 3.50 and the Android SDK. Android only, minimum Android 7.0 (API 24).

Only download media you have the right to save.
