import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../l10n/l10n.dart';

/// What to download when the picker is skipped (one-tap sharing, batches and
/// playlists).
enum QualityPreference {
  ask('ask', 'Ask every time', null),
  best('best', 'Best available', null),
  p1080('1080', '1080p', 1080),
  p720('720', '720p', 720),
  p480('480', '480p', 480),
  mp3('mp3', 'MP3 audio', null),
  m4a('m4a', 'M4A audio', null);

  const QualityPreference(this.id, this.label, this.height);

  final String id;
  final String label;

  /// Largest video height to accept; null for "best" and the audio choices.
  final int? height;

  bool get isAudio => this == mp3 || this == m4a;

  static QualityPreference fromId(String? id) =>
      values.firstWhere((value) => value.id == id, orElse: () => ask);

  /// The choices that can run without asking.
  static List<QualityPreference> get automatic => [
    for (final value in values)
      if (value != ask) value,
  ];
}

/// Where finished downloads are kept. Either way there is one copy.
enum SaveLocation {
  /// In the phone's gallery (Pictures, Movies, Music under "SaveKit"), where
  /// other apps can see them too.
  gallery('gallery', 'Gallery'),

  /// Inside SaveKit only: hidden from the gallery and other apps.
  private('private', 'Private (SaveKit only)');

  const SaveLocation(this.id, this.label);

  final String id;
  final String label;

  static SaveLocation fromId(String? id) =>
      values.firstWhere((value) => value.id == id, orElse: () => gallery);
}

enum VaultSort {
  newest('newest', 'Newest first'),
  oldest('oldest', 'Oldest first'),
  largest('largest', 'Largest first'),
  smallest('smallest', 'Smallest first'),
  name('name', 'Name (A–Z)');

  const VaultSort(this.id, this.label);

  final String id;
  final String label;

  static VaultSort fromId(String? id) =>
      values.firstWhere((value) => value.id == id, orElse: () => newest);
}

/// The user's preferences. Immutable; persisted as a plain map.
class AppSettings {
  const AppSettings({
    this.themeId = 'ember',
    this.iconId = AppSettings.iconMatchesTheme,
    this.oneTap = QualityPreference.ask,
    this.wifiOnly = false,
    this.maxConcurrent = 3,
    this.lockVault = false,
    this.vaultSort = VaultSort.newest,
    this.vaultGrid = true,
    this.autoUpdate = true,
    this.lastEngineUpdate,
    this.saveLocation = SaveLocation.gallery,
    this.language = AppLanguage.system,
    this.onboarded = false,
    this.shareToTonight = false,
    this.tonightQuality = QualityPreference.best,
    this.nightStart = defaultNightStart,
  });

  /// Id of the selected [AppPalette].
  final String themeId;

  /// Colour of the home-screen icon: the id of an [AppPalette], or
  /// [iconMatchesTheme] to follow the app's theme.
  final String iconId;

  static const iconMatchesTheme = 'match';

  /// The palette id whose icon the home screen should show.
  String get launcherIconId => iconId == iconMatchesTheme ? themeId : iconId;

  /// Quality used when a link is shared to the app; [QualityPreference.ask]
  /// opens the picker instead.
  final QualityPreference oneTap;

  /// Hold downloads until the phone is on Wi-Fi.
  final bool wifiOnly;

  /// Downloads running at once (1–5).
  final int maxConcurrent;

  /// Ask for fingerprint, face or screen lock before showing the vault.
  final bool lockVault;
  final VaultSort vaultSort;
  final bool vaultGrid;

  /// Refresh the extractors in the background when they are over a week old.
  final bool autoUpdate;

  /// When the extractors were last checked for updates; null if never.
  final DateTime? lastEngineUpdate;

  /// Where new downloads are kept.
  final SaveLocation saveLocation;

  /// Language of the app's own text.
  final AppLanguage language;

  /// The welcome screens have been seen.
  final bool onboarded;

  /// Links shared to the app go straight to tonight's list instead of the
  /// picker.
  final bool shareToTonight;

  /// Quality of the downloads on tonight's list. Never "ask".
  final QualityPreference tonightQuality;

  /// When the night begins for night downloads, in minutes after midnight.
  /// They may start from then until [nightLength] later, on Wi-Fi.
  final int nightStart;

  static const defaultNightStart = 23 * 60;
  static const nightLength = Duration(hours: 8);

  /// Whether [time] falls in the night that starts at [nightStart].
  bool isNight(DateTime time) {
    final minutes = time.hour * 60 + time.minute;
    final sinceStart = (minutes - nightStart) % (24 * 60);
    return sinceStart < nightLength.inMinutes;
  }

  /// The next moment the night begins, after [time].
  DateTime nextNightStart(DateTime time) {
    var start = DateTime(
      time.year,
      time.month,
      time.day,
      nightStart ~/ 60,
      nightStart % 60,
    );
    if (!start.isAfter(time)) start = start.add(const Duration(days: 1));
    return start;
  }

  static const defaultThemeId = 'ember';
  static const minConcurrent = 1;
  static const maxConcurrentLimit = 5;

  AppSettings copyWith({
    String? themeId,
    String? iconId,
    QualityPreference? oneTap,
    bool? wifiOnly,
    int? maxConcurrent,
    bool? lockVault,
    VaultSort? vaultSort,
    bool? vaultGrid,
    bool? autoUpdate,
    DateTime? lastEngineUpdate,
    SaveLocation? saveLocation,
    AppLanguage? language,
    bool? onboarded,
    bool? shareToTonight,
    QualityPreference? tonightQuality,
    int? nightStart,
  }) => AppSettings(
    themeId: themeId ?? this.themeId,
    iconId: iconId ?? this.iconId,
    oneTap: oneTap ?? this.oneTap,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    maxConcurrent: (maxConcurrent ?? this.maxConcurrent).clamp(
      minConcurrent,
      maxConcurrentLimit,
    ),
    lockVault: lockVault ?? this.lockVault,
    vaultSort: vaultSort ?? this.vaultSort,
    vaultGrid: vaultGrid ?? this.vaultGrid,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    lastEngineUpdate: lastEngineUpdate ?? this.lastEngineUpdate,
    saveLocation: saveLocation ?? this.saveLocation,
    language: language ?? this.language,
    onboarded: onboarded ?? this.onboarded,
    shareToTonight: shareToTonight ?? this.shareToTonight,
    tonightQuality: tonightQuality ?? this.tonightQuality,
    nightStart: (nightStart ?? this.nightStart) % (24 * 60),
  );

  Map<String, dynamic> toMap() => {
    'themeId': themeId,
    'iconId': iconId,
    'oneTap': oneTap.id,
    'wifiOnly': wifiOnly,
    'maxConcurrent': maxConcurrent,
    'lockVault': lockVault,
    'vaultSort': vaultSort.id,
    'vaultGrid': vaultGrid,
    'autoUpdate': autoUpdate,
    'lastEngineUpdate': lastEngineUpdate?.millisecondsSinceEpoch,
    'saveLocation': saveLocation.id,
    'language': language.id,
    'onboarded': onboarded,
    'shareToTonight': shareToTonight,
    'tonightQuality': tonightQuality.id,
    'nightStart': nightStart,
  };

  factory AppSettings.fromMap(Map<Object?, Object?> map) => AppSettings(
    themeId: map['themeId'] as String? ?? 'ember',
    // Older versions stored a "match the theme" switch instead.
    iconId:
        map['iconId'] as String? ??
        (map['matchIcon'] == false ? defaultThemeId : iconMatchesTheme),
    oneTap: QualityPreference.fromId(map['oneTap'] as String?),
    wifiOnly: map['wifiOnly'] as bool? ?? false,
    maxConcurrent: ((map['maxConcurrent'] as num?)?.toInt() ?? 3).clamp(
      minConcurrent,
      maxConcurrentLimit,
    ),
    lockVault: map['lockVault'] as bool? ?? false,
    vaultSort: VaultSort.fromId(map['vaultSort'] as String?),
    vaultGrid: map['vaultGrid'] as bool? ?? true,
    autoUpdate: map['autoUpdate'] as bool? ?? true,
    lastEngineUpdate: map['lastEngineUpdate'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (map['lastEngineUpdate'] as num).toInt(),
          )
        : null,
    saveLocation: SaveLocation.fromId(map['saveLocation'] as String?),
    language: AppLanguage.fromId(map['language'] as String?),
    // Anyone with saved settings from before the welcome screens existed
    // has used the app already.
    onboarded: map['onboarded'] as bool? ?? true,
    shareToTonight: map['shareToTonight'] as bool? ?? false,
    tonightQuality: switch (QualityPreference.fromId(
      map['tonightQuality'] as String?,
    )) {
      QualityPreference.ask => QualityPreference.best,
      final quality => quality,
    },
    nightStart:
        ((map['nightStart'] as num?)?.toInt() ?? defaultNightStart) % (24 * 60),
  );
}

/// Where settings are kept between launches.
abstract interface class SettingsRepository {
  AppSettings load();
  Future<void> save(AppSettings settings);
}

class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository(this._box);

  static const boxName = 'settings';
  static const _key = 'app';

  final Box<Map> _box;

  /// Call after `Hive.initFlutter()`.
  static Future<HiveSettingsRepository> open() async =>
      HiveSettingsRepository(await Hive.openBox<Map>(boxName));

  @override
  AppSettings load() {
    final stored = _box.get(_key);
    if (stored == null) return const AppSettings();
    try {
      return AppSettings.fromMap(stored);
    } catch (_) {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) => _box.put(_key, settings.toMap());
}

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this._settings = const AppSettings()]);

  AppSettings _settings;

  @override
  AppSettings load() => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

/// Changes the home-screen icon to the one of a theme. On Android this
/// switches which launcher entry is enabled; the launcher shows the new icon
/// within a few seconds.
typedef LauncherIconSetter = Future<void> Function(String themeId);

final launcherIconProvider = Provider<LauncherIconSetter>(
  (ref) => (themeId) async {
    try {
      await const MethodChannel('com.app.downloader/engine')
          .invokeMethod<void>('setLauncherIcon', {'theme': themeId});
    } catch (_) {
      // The icon is cosmetic; the theme itself has already changed.
    }
  },
);

/// Gives the next launch's splash screen the colours of a theme (Android 13
/// and later; older versions keep the default splash).
final splashThemeProvider = Provider<Future<void> Function(String themeId)>(
  (ref) => (themeId) async {
    try {
      await const MethodChannel('com.app.downloader/engine')
          .invokeMethod<void>('setSplashTheme', {'theme': themeId});
    } catch (_) {
      // Cosmetic.
    }
  },
);

/// Overridden in `main()` with the opened Hive repository.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => InMemorySettingsRepository(),
);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  void _set(AppSettings settings) {
    state = settings;
    ref.read(settingsRepositoryProvider).save(settings);
  }

  void setTheme(String themeId) {
    _set(state.copyWith(themeId: themeId));
    _syncIcon();
    ref.read(splashThemeProvider)(themeId);
  }

  /// [iconId] is a palette id, or [AppSettings.iconMatchesTheme].
  void setIcon(String iconId) {
    _set(state.copyWith(iconId: iconId));
    _syncIcon();
  }

  /// Shows the chosen icon colour on the home screen.
  void _syncIcon() => ref.read(launcherIconProvider)(state.launcherIconId);

  void setOneTap(QualityPreference value) =>
      _set(state.copyWith(oneTap: value));
  void setWifiOnly(bool value) => _set(state.copyWith(wifiOnly: value));
  void setMaxConcurrent(int value) =>
      _set(state.copyWith(maxConcurrent: value));
  void setLockVault(bool value) => _set(state.copyWith(lockVault: value));
  void setVaultSort(VaultSort value) => _set(state.copyWith(vaultSort: value));
  void setVaultGrid(bool value) => _set(state.copyWith(vaultGrid: value));
  void setLanguage(AppLanguage value) => _set(state.copyWith(language: value));
  void finishOnboarding() => _set(state.copyWith(onboarded: true));
  void setShareToTonight(bool value) =>
      _set(state.copyWith(shareToTonight: value));
  void setNightStart(int minutes) => _set(state.copyWith(nightStart: minutes));
  void setTonightQuality(QualityPreference value) => _set(
    state.copyWith(
      tonightQuality: value == QualityPreference.ask
          ? QualityPreference.best
          : value,
    ),
  );
  void setSaveLocation(SaveLocation value) =>
      _set(state.copyWith(saveLocation: value));
  void setAutoUpdate(bool value) => _set(state.copyWith(autoUpdate: value));
  void markEngineUpdated(DateTime when) =>
      _set(state.copyWith(lastEngineUpdate: when));
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
