import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../downloader/application/download_queue_controller.dart';
import '../downloader/domain/download_task.dart';

/// A marked point in a saved video or audio file, with an optional note.
class Moment {
  const Moment({
    required this.id,
    required this.taskId,
    required this.path,
    required this.position,
    required this.createdAt,
    this.note = '',
  });

  final String id;

  /// The download the file belongs to.
  final String taskId;
  final String path;
  final Duration position;
  final String note;
  final DateTime createdAt;

  Moment copyWith({String? note}) => Moment(
    id: id,
    taskId: taskId,
    path: path,
    position: position,
    createdAt: createdAt,
    note: note ?? this.note,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'taskId': taskId,
    'path': path,
    'positionMs': position.inMilliseconds,
    'note': note,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Moment.fromMap(Map<dynamic, dynamic> map) => Moment(
    id: map['id'] as String,
    taskId: map['taskId'] as String? ?? '',
    path: map['path'] as String? ?? '',
    position: Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
    note: map['note'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] as num?)?.toInt() ?? 0,
    ),
  );
}

abstract interface class MomentRepository {
  List<Moment> load();
  Future<void> save(List<Moment> moments);
}

class HiveMomentRepository implements MomentRepository {
  HiveMomentRepository(this._box);

  static const boxName = 'moments';
  static const _key = 'all';
  final Box<List> _box;

  /// Call after `Hive.initFlutter()`.
  static Future<HiveMomentRepository> open() async =>
      HiveMomentRepository(await Hive.openBox<List>(boxName));

  @override
  List<Moment> load() {
    try {
      return [
        for (final map in _box.get(_key) ?? const [])
          Moment.fromMap(map as Map),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<Moment> moments) =>
      _box.put(_key, [for (final moment in moments) moment.toMap()]);
}

class InMemoryMomentRepository implements MomentRepository {
  InMemoryMomentRepository([this._moments = const []]);

  List<Moment> _moments;

  @override
  List<Moment> load() => _moments;

  @override
  Future<void> save(List<Moment> moments) async => _moments = moments;
}

/// Overridden in `main()` with the opened Hive repository.
final momentRepositoryProvider = Provider<MomentRepository>(
  (ref) => InMemoryMomentRepository(),
);

/// Every moment, newest first.
class MomentsController extends Notifier<List<Moment>> {
  final _random = Random();

  @override
  List<Moment> build() => ref.read(momentRepositoryProvider).load();

  void _set(List<Moment> moments) {
    state = moments;
    ref.read(momentRepositoryProvider).save(moments);
  }

  /// Marks [position] in [path] and returns the new moment.
  Moment add({
    required String taskId,
    required String path,
    required Duration position,
    String note = '',
  }) {
    final moment = Moment(
      id:
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '${_random.nextInt(1 << 20).toRadixString(36)}',
      taskId: taskId,
      path: path,
      position: position,
      note: note.trim(),
      createdAt: DateTime.now(),
    );
    _set([moment, ...state]);
    return moment;
  }

  void editNote(String id, String note) => _set([
    for (final moment in state)
      moment.id == id ? moment.copyWith(note: note.trim()) : moment,
  ]);

  void remove(String id) => _set([
    for (final moment in state)
      if (moment.id != id) moment,
  ]);
}

final momentsProvider = NotifierProvider<MomentsController, List<Moment>>(
  MomentsController.new,
);

/// Moments whose file is still in the Vault, each with its download, in the
/// order of the file and then of the time in it.
final vaultMomentsProvider = Provider<List<(Moment, DownloadTask)>>((ref) {
  final tasks = {
    for (final task in ref.watch(completedDownloadsProvider)) task.id: task,
  };
  return [
    for (final moment in ref.watch(momentsProvider))
      if (tasks[moment.taskId] case final task?
          when task.filePaths.contains(moment.path))
        (moment, task),
  ];
});
