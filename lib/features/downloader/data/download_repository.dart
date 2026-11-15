import 'package:hive_ce_flutter/hive_flutter.dart';

import '../domain/download_task.dart';

/// Persistence for the download queue and history.
abstract interface class DownloadRepository {
  /// Every stored task, in no particular order.
  List<DownloadTask> loadAll();
  Future<void> save(DownloadTask task);
  Future<void> delete(String id);
  Future<void> deleteAll(Iterable<String> ids);
}

/// Stores each task as a plain map in a Hive box, keyed by task id.
class HiveDownloadRepository implements DownloadRepository {
  HiveDownloadRepository(this._box);

  static const boxName = 'downloads';

  final Box<Map> _box;

  /// Opens the box. Call once, before the app starts, so reads are synchronous.
  static Future<HiveDownloadRepository> open() async {
    await Hive.initFlutter();
    return HiveDownloadRepository(await Hive.openBox<Map>(boxName));
  }

  @override
  List<DownloadTask> loadAll() {
    final tasks = <DownloadTask>[];
    for (final key in _box.keys) {
      final value = _box.get(key);
      if (value == null) continue;
      try {
        tasks.add(DownloadTask.fromMap(value));
      } catch (_) {
        // An entry written by an incompatible version is skipped, not fatal.
      }
    }
    return tasks;
  }

  @override
  Future<void> save(DownloadTask task) => _box.put(task.id, task.toMap());

  @override
  Future<void> delete(String id) => _box.delete(id);

  @override
  Future<void> deleteAll(Iterable<String> ids) => _box.deleteAll(ids);
}

/// Keeps tasks in memory only; used in tests and as a fallback if storage
/// cannot be opened.
class InMemoryDownloadRepository implements DownloadRepository {
  InMemoryDownloadRepository([Iterable<DownloadTask> initial = const []]) {
    for (final task in initial) {
      _tasks[task.id] = task;
    }
  }

  final _tasks = <String, DownloadTask>{};

  @override
  List<DownloadTask> loadAll() => _tasks.values.toList();

  @override
  Future<void> save(DownloadTask task) async => _tasks[task.id] = task;

  @override
  Future<void> delete(String id) async => _tasks.remove(id);

  @override
  Future<void> deleteAll(Iterable<String> ids) async =>
      ids.forEach(_tasks.remove);
}
