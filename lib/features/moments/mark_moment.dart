import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/formatters.dart';
import '../downloader/application/download_queue_controller.dart';
import 'moments_controller.dart';

/// Marks [position] in the saved file at [path] as a moment, after asking
/// for an optional note. Shows a confirmation; does nothing for a file that
/// is not in the Vault.
Future<void> markMoment(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  required Duration position,
}) async {
  final task = ref
      .read(completedDownloadsProvider)
      .where((task) => task.filePaths.contains(path))
      .firstOrNull;
  if (task == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final note = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Moment at ${formatClock(position.inSeconds)}')),
      content: TextField(
        controller: note,
        autofocus: true,
        maxLength: 120,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: tr('A note, if you like (optional)'),
        ),
        onSubmitted: (_) => Navigator.of(context).pop(true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Save')),
        ),
      ],
    ),
  );
  final text = note.text;
  note.dispose();
  if (saved != true) return;
  ref
      .read(momentsProvider.notifier)
      .add(taskId: task.id, path: path, position: position, note: text);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(tr('Moment saved. Find it in Tools → Moments.'))),
    );
}
