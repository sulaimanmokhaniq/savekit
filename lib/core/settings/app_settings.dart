import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

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
    this.oneTap = QualityPreference.ask,
    this.wifiOnly = false,
    this.maxConcurrent = 3,
    this.lockVault = false,
    this.vaultSort = VaultSort.newest,
    this.vaultGrid = true,
  });

  /// Id of the selected [AppPalette].
  final String themeId;

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

  static const minConcurrent = 1;
  static const maxConcurrentLimit = 5;

  AppSettings copyWith({
    String? themeId,
    QualityPreference? oneTap,
    bool? wifiOnly,
    int? maxConcurrent,
    bool? lockVault,
    VaultSort? vaultSort,
    bool? vaultGrid,
  }) => AppSettings(
    themeId: themeId ?? this.themeId,
    oneTap: oneTap ?? this.oneTap,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    maxConcurrent: (maxConcurrent ?? this.maxConcurrent).clamp(
      minConcurrent,
      maxConcurrentLimit,
    ),
    lockVault: lockVault ?? this.lockVault,
    vaultSort: vaultSort ?? this.vaultSort,
    vaultGrid: vaultGrid ?? this.vaultGrid,
  );

  Map<String, dynamic> toMap() => {
    'themeId': themeId,
    'oneTap': oneTap.id,
    'wifiOnly': wifiOnly,
    'maxConcurrent': maxConcurrent,
    'lockVault': lockVault,
    'vaultSort': vaultSort.id,
    'vaultGrid': vaultGrid,
  };

  factory AppSettings.fromMap(Map<Object?, Object?> map) => AppSettings(
    themeId: map['themeId'] as String? ?? 'ember',
    oneTap: QualityPreference.fromId(map['oneTap'] as String?),
    wifiOnly: map['wifiOnly'] as bool? ?? false,
    maxConcurrent: ((map['maxConcurrent'] as num?)?.toInt() ?? 3).clamp(
      minConcurrent,
      maxConcurrentLimit,
    ),
    lockVault: map['lockVault'] as bool? ?? false,
    vaultSort: VaultSort.fromId(map['vaultSort'] as String?),
    vaultGrid: map['vaultGrid'] as bool? ?? true,
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

  void setTheme(String themeId) => _set(state.copyWith(themeId: themeId));
  void setOneTap(QualityPreference value) =>
      _set(state.copyWith(oneTap: value));
  void setWifiOnly(bool value) => _set(state.copyWith(wifiOnly: value));
  void setMaxConcurrent(int value) =>
      _set(state.copyWith(maxConcurrent: value));
  void setLockVault(bool value) => _set(state.copyWith(lockVault: value));
  void setVaultSort(VaultSort value) => _set(state.copyWith(vaultSort: value));
  void setVaultGrid(bool value) => _set(state.copyWith(vaultGrid: value));
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
