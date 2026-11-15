# SaveKit

An Android app that downloads media entirely on the device. There is no backend and no
third-party API: extraction, multi-connection downloading and stream merging all run locally.

## Features

- **Download** video, audio and photos from YouTube, TikTok, Instagram, Snapchat, X, LinkedIn
  and the 1,000+ sites yt-dlp supports; several links at once; whole YouTube playlists.
- **One-tap download**: share a link to SaveKit and it downloads at your saved quality.
- **Queue**: pause, resume, retry, Wi-Fi only, and a choice of how many run at once.
- **Vault**: search, sort, filter, multi-select, built-in playback, optional fingerprint lock.
- **Tools**: convert any video on the phone to MP3/M4A, save WhatsApp statuses you have
  viewed, and a storage manager with sizes, sorting and delete.
- **Themes**: five solid-colour themes (Ember, Vault, Pulse, Tide, Classic), switchable in
  Settings.

## How it works

| Layer | What it does |
| --- | --- |
| Embedded engine | `youtubedl-android` bundles Python + yt-dlp, FFmpeg and aria2c as native libraries. Kotlin (`android/app/src/main/kotlin/com/savekit/app`) exposes them to Flutter. |
| Photo engine | gallery-dl runs on the same embedded Python for photo posts and carousels (Instagram, X, TikTok, Snapchat and more). Its bundle lives in `android/app/src/main/assets/gallerydl`; rebuild it with `tool/build_gallery_dl_bundle.sh`. |
| Page reader | For sites neither extractor handles (LinkedIn photos, and as a general fallback), the post is opened in a hidden WebView sharing the login sessions and its photos are read from the page, then downloaded over HTTP. |
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
| `updateDownloadService` | `activeCount`, `title`, `text`, `progress` | starts, refreshes or stops the background service |
| `notifyDownloadFinished` | `taskId`, `title`, `success` | posts the finished/failed notification |
| `exportToMediaStore` | `path`, `audio` | copies audio to Music/SaveKit, other files to Download/SaveKit |
| `getPlaylistInfo` | `url`, `cookiesFilePath?` | playlist title and entries, without resolving each |
| `pickVideo` | none | `{path, name, size}` of a video chosen in the system picker, or null |
| `grantStatusFolder`, `statusFolderGranted`, `forgetStatusFolder` | `business?` | access to WhatsApp's status folder |
| `listStatuses`, `statusThumbnail`, `importStatuses` | see `DeviceFiles.kt` | list, preview and copy viewed statuses |

`startDownload` with `engine: convert` converts the local video at `url` to `audioFormat`.

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
  ConverterEngine.kt     FFmpeg video-to-audio conversion of local files
  DeviceFiles.kt         system pickers: a video to convert, WhatsApp's status folder
  DownloadService.kt     foreground service + notifications while downloads run
  MediaStoreExporter.kt  audio and documents into shared storage
lib/
  core/
    providers.dart                            service wiring (Riverpod)
    engine/engine_controller.dart             engine start-up and over-the-air updates
    storage/app_paths.dart                    the app's download folder
    native/youtube_dl_native_service.dart     Dart side of the Kotlin bridge
    platform/media_platform.dart              known platforms, link detection
  features/extractor/
    domain/                                   MediaInfo, MediaFormat
    application/extraction_controller.dart    link lookup state for the format picker
    application/incoming_link_controller.dart share-sheet links and clipboard detection
    data/media_extractor.dart                 native engine first, WebView fallback
    data/web_page_extractor.dart              reads photos from a page in a hidden WebView
    data/web_extraction_rules.dart            per-site rules (assets/web_rules.json), updatable
  features/downloader/
    domain/                                   DownloadTask, DownloadProgress
    application/download_queue_controller.dart  queue, history, retries, concurrency
    data/download_repository.dart             Hive persistence
    data/gallery_export_service.dart          finished files -> Gallery / Music / Download
    data/direct_download_service.dart         HTTP download of WebView-found photos
  features/cookies/
    domain/platform_account.dart              Instagram, X, TikTok, LinkedIn logins
    data/cookie_export_service.dart           WebView cookies -> Netscape cookies.txt
  features/vault/                             vault grid/list, media viewer, lock
  features/tools/                             converter, WhatsApp status saver, storage manager
  core/settings/app_settings.dart             saved preferences (theme, one-tap, Wi-Fi only…)
  core/theme/app_palette.dart                 the selectable solid-colour themes
  app/                                        MaterialApp and the four-tab shell
  core/theme/, core/widgets/                  dark theme and shared widgets
```

Each feature also has a `presentation/` folder with its screens: Home and the format picker
(extractor), Queue (downloader), Settings and the login WebView (cookies).

## Testing

```bash
flutter test
```

To also render a PNG of every screen into `test/screenshots/` for design review:

```bash
SAVEKIT_SCREENSHOTS=1 flutter test test/app_test.dart --update-goldens
```

## Building

Every push to `main` builds release APKs and publishes them under **Releases**; install
`SaveKit-arm64.apk` on the phone. To build locally:

```bash
flutter pub get
```

```bash
flutter build apk --release --split-per-abi
```

Requires Flutter 3.50 and the Android SDK. Android only, minimum Android 7.0 (API 24).

### Signing

Builds are signed with `android/app/sideload.jks`, a key committed to this repository so
that each new build installs over the previous one. Like Android's debug key it is public
and proves nothing about who built an APK. Before distributing through a store, sign with a
private keystore by setting `SAVEKIT_KEYSTORE`, `SAVEKIT_KEYSTORE_PASSWORD`,
`SAVEKIT_KEY_ALIAS` and `SAVEKIT_KEY_PASSWORD`.

Only download media you have the right to save.
