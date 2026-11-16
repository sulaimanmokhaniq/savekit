import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../downloader/application/download_queue_controller.dart';
import '../../downloader/domain/download_task.dart';

/// Colours a folder can have: solid, and readable on every theme.
const folderColors = <Color>[
  Color(0xFFFF6A2B),
  Color(0xFF22C98A),
  Color(0xFF8E6CFF),
  Color(0xFF12B5E5),
  Color(0xFFFF4F7B),
  Color(0xFFF4B93A),
  Color(0xFF7C9CFF),
  Color(0xFF9AA1AD),
];

/// A folder in the Vault. It lists downloads by id: the same download can be
/// in several folders, and nothing is copied.
class VaultFolder {
  const VaultFolder({
    required this.id,
    required this.name,
    this.colorIndex = 0,
    this.taskIds = const [],
  });

  final String id;
  final String name;
  final int colorIndex;

  /// The downloads in the folder, most recently added first.
  final List<String> taskIds;

  Color get color => folderColors[colorIndex % folderColors.length];

  VaultFolder copyWith({
    String? name,
    int? colorIndex,
    List<String>? taskIds,
  }) => VaultFolder(
    id: id,
    name: name ?? this.name,
    colorIndex: colorIndex ?? this.colorIndex,
    taskIds: taskIds ?? this.taskIds,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'color': colorIndex,
    'tasks': taskIds,
  };

  factory VaultFolder.fromMap(Map<dynamic, dynamic> map) => VaultFolder(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    colorIndex: (map['color'] as num?)?.toInt() ?? 0,
    taskIds: [for (final id in (map['tasks'] as List?) ?? const []) '$id'],
  );
}

abstract interface class FolderRepository {
  List<VaultFolder> load();
  Future<void> save(List<VaultFolder> folders);
}

class HiveFolderRepository implements FolderRepository {
  HiveFolderRepository(this._box);

  static const boxName = 'folders';
  static const _key = 'all';
  final Box<List> _box;

  /// Call after `Hive.initFlutter()`.
  static Future<HiveFolderRepository> open() async =>
      HiveFolderRepository(await Hive.openBox<List>(boxName));

  @override
  List<VaultFolder> load() {
    try {
      return [
        for (final map in _box.get(_key) ?? const [])
          VaultFolder.fromMap(map as Map),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<VaultFolder> folders) =>
      _box.put(_key, [for (final folder in folders) folder.toMap()]);
}

class InMemoryFolderRepository implements FolderRepository {
  InMemoryFolderRepository([this._folders = const []]);

  List<VaultFolder> _folders;

  @override
  List<VaultFolder> load() => _folders;

  @override
  Future<void> save(List<VaultFolder> folders) async => _folders = folders;
}

/// Overridden in `main()` with the opened Hive repository.
final folderRepositoryProvider = Provider<FolderRepository>(
  (ref) => InMemoryFolderRepository(),
);

/// The Vault's folders, in the order the user arranged them.
class FoldersController extends Notifier<List<VaultFolder>> {
  final _random = Random();

  @override
  List<VaultFolder> build() => ref.read(folderRepositoryProvider).load();

  void _set(List<VaultFolder> folders) {
    state = folders;
    ref.read(folderRepositoryProvider).save(folders);
  }

  VaultFolder? byId(String id) {
    for (final folder in state) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  /// Adds a folder at the end and returns its id.
  String create(String name, {int colorIndex = 0}) {
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(1 << 20).toRadixString(36)}';
    _set([
      ...state,
      VaultFolder(id: id, name: name.trim(), colorIndex: colorIndex),
    ]);
    return id;
  }

  void _update(String id, VaultFolder Function(VaultFolder folder) change) =>
      _set([
        for (final folder in state)
          if (folder.id == id) change(folder) else folder,
      ]);

  void rename(String id, String name) =>
      _update(id, (folder) => folder.copyWith(name: name.trim()));

  void recolor(String id, int colorIndex) =>
      _update(id, (folder) => folder.copyWith(colorIndex: colorIndex));

  /// Removes the folder only; its downloads stay in the Vault.
  void delete(String id) => _set([
    for (final folder in state)
      if (folder.id != id) folder,
  ]);

  /// Moves the folder [by] places (negative: earlier).
  void move(String id, int by) {
    final folders = [...state];
    final from = folders.indexWhere((folder) => folder.id == id);
    if (from < 0) return;
    final to = (from + by).clamp(0, folders.length - 1);
    if (to == from) return;
    folders.insert(to, folders.removeAt(from));
    _set(folders);
  }

  /// Puts [taskIds] at the top of the folder; ones already in it stay once.
  void add(String id, Iterable<String> taskIds) {
    final adding = taskIds.toList();
    _update(
      id,
      (folder) => folder.copyWith(
        taskIds: [
          ...adding,
          for (final taskId in folder.taskIds)
            if (!adding.contains(taskId)) taskId,
        ],
      ),
    );
  }

  /// Takes [taskIds] out of the folder; they stay in the Vault.
  void remove(String id, Iterable<String> taskIds) {
    final removing = taskIds.toSet();
    _update(
      id,
      (folder) => folder.copyWith(
        taskIds: [
          for (final taskId in folder.taskIds)
            if (!removing.contains(taskId)) taskId,
        ],
      ),
    );
  }
}

final foldersProvider = NotifierProvider<FoldersController, List<VaultFolder>>(
  FoldersController.new,
);

/// The downloads in folder [id] that are still in the Vault.
final folderTasksProvider = Provider.family<List<DownloadTask>, String>((
  ref,
  id,
) {
  final folder = ref
      .watch(foldersProvider)
      .where((folder) => folder.id == id)
      .firstOrNull;
  if (folder == null) return const [];
  final byId = {
    for (final task in ref.watch(completedDownloadsProvider)) task.id: task,
  };
  return [for (final taskId in folder.taskIds) ?byId[taskId]];
});
