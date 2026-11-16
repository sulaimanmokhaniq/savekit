import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../tools/application/space_saver_controller.dart'
    show spaceServiceProvider;
import '../application/folders_controller.dart';
import '../application/phone_import.dart';

/// The folders at the top of the Vault: a "New folder" card, then one card
/// per folder. A tap opens a folder; a long press offers its options.
class FolderRow extends ConsumerWidget {
  const FolderRow({super.key, required this.onOpen});

  final void Function(VaultFolder folder) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider);
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        children: [
          _FolderCard(
            icon: Icons.create_new_folder_outlined,
            color: AppColors.textMuted,
            name: tr('New folder'),
            detail: null,
            onTap: () async {
              final created = await createFolder(context, ref);
              final folder = created == null
                  ? null
                  : ref.read(foldersProvider.notifier).byId(created);
              if (folder != null) onOpen(folder);
            },
          ),
          for (final folder in folders) ...[
            const SizedBox(width: 10),
            Consumer(
              builder: (context, ref, _) {
                final count = ref.watch(folderTasksProvider(folder.id)).length;
                return _FolderCard(
                  key: ValueKey(folder.id),
                  icon: Icons.folder_rounded,
                  color: folder.color,
                  name: folder.name,
                  detail: count == 1 ? tr('1 item') : tr('$count items'),
                  onTap: () => onOpen(folder),
                  onLongPress: () => showFolderOptions(context, ref, folder),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    super.key,
    required this.icon,
    required this.color,
    required this.name,
    required this.detail,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final Color color;
  final String name;
  final String? detail;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: 124,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 26),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a name and colour. Returns null when cancelled.
Future<(String, int)?> showFolderEditor(
  BuildContext context, {
  String title = 'New folder',
  String action = 'Create',
  String name = '',
  int colorIndex = 0,
}) {
  return showDialog<(String, int)>(
    context: context,
    builder: (context) => _FolderEditor(
      title: title,
      action: action,
      name: name,
      colorIndex: colorIndex,
    ),
  );
}

class _FolderEditor extends StatefulWidget {
  const _FolderEditor({
    required this.title,
    required this.action,
    required this.name,
    required this.colorIndex,
  });

  final String title;
  final String action;
  final String name;
  final int colorIndex;

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final _name = TextEditingController(text: widget.name);
  late int _color = widget.colorIndex;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name, _color));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(widget.title)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _done(),
            decoration: InputDecoration(hintText: tr('Folder name')),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < folderColors.length; index++)
                Semantics(
                  button: true,
                  selected: index == _color,
                  label: tr('Colour ${index + 1}'),
                  child: InkWell(
                    onTap: () => setState(() => _color = index),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: folderColors[index],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: index == _color
                              ? AppColors.text
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: index == _color
                          ? const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Colors.black,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          onPressed: _name.text.trim().isEmpty ? null : _done,
          child: Text(tr(widget.action)),
        ),
      ],
    );
  }
}

/// Asks for a name and colour and makes the folder. Returns its id, or null
/// when cancelled.
Future<String?> createFolder(BuildContext context, WidgetRef ref) async {
  final folders = ref.read(foldersProvider);
  final answer = await showFolderEditor(
    context,
    // A different colour from the last folder, to tell them apart.
    colorIndex: folders.isEmpty
        ? 0
        : (folders.last.colorIndex + 1) % folderColors.length,
  );
  if (answer == null) return null;
  return ref
      .read(foldersProvider.notifier)
      .create(answer.$1, colorIndex: answer.$2);
}

/// Rename, recolour, move or delete a folder.
Future<void> showFolderOptions(
  BuildContext context,
  WidgetRef ref,
  VaultFolder folder,
) async {
  final folders = ref.read(foldersProvider.notifier);
  final position = ref
      .read(foldersProvider)
      .indexWhere((other) => other.id == folder.id);
  final last = ref.read(foldersProvider).length - 1;
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              folder.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(tr('Rename or change colour')),
            onTap: () => Navigator.of(context).pop('edit'),
          ),
          if (position > 0)
            ListTile(
              leading: const Icon(Icons.arrow_back_rounded),
              title: Text(tr('Move earlier')),
              onTap: () => Navigator.of(context).pop('earlier'),
            ),
          if (position < last)
            ListTile(
              leading: const Icon(Icons.arrow_forward_rounded),
              title: Text(tr('Move later')),
              onTap: () => Navigator.of(context).pop('later'),
            ),
          ListTile(
            leading: Icon(
              Icons.folder_delete_outlined,
              color: AppColors.danger,
            ),
            title: Text(
              tr('Delete folder'),
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'edit':
      final answer = await showFolderEditor(
        context,
        title: 'Edit folder',
        action: 'Save',
        name: folder.name,
        colorIndex: folder.colorIndex,
      );
      if (answer == null) return;
      folders
        ..rename(folder.id, answer.$1)
        ..recolor(folder.id, answer.$2);
    case 'earlier':
      folders.move(folder.id, -1);
    case 'later':
      folders.move(folder.id, 1);
    case 'delete':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Delete “${folder.name}”?')),
          content: Text(
            tr('Only the folder goes. Everything in it stays in the Vault.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text(tr('Delete folder')),
            ),
          ],
        ),
      );
      if (confirmed == true) folders.delete(folder.id);
  }
}

/// Lets the user choose a folder for [taskIds] (or make a new one) and adds
/// them to it. Returns the folder's name, or null when cancelled.
Future<String?> addToFolder(
  BuildContext context,
  WidgetRef ref,
  List<String> taskIds,
) async {
  final folders = ref.read(foldersProvider);
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                tr('Add to folder'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(tr('New folder')),
              onTap: () => Navigator.of(context).pop(''),
            ),
            for (final folder in folders)
              ListTile(
                leading: Icon(Icons.folder_rounded, color: folder.color),
                title: Text(folder.name),
                onTap: () => Navigator.of(context).pop(folder.id),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  final id = choice.isEmpty ? await createFolder(context, ref) : choice;
  if (id == null) return null;
  ref.read(foldersProvider.notifier).add(id, taskIds);
  return ref.read(foldersProvider.notifier).byId(id)?.name;
}

/// Picks photos and videos from the phone, asks whether to copy or move
/// them (showing where each one is and where it goes), and adds them to the
/// Vault and to folder [folderId].
Future<void> addFromPhone(
  BuildContext context,
  WidgetRef ref, {
  String? folderId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  List<PickedMedia> picked;
  try {
    picked = await ref.read(phoneMediaServiceProvider).pick();
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(content: Text(tr('The files could not be opened.'))),
    );
    return;
  }
  if (picked.isEmpty || !context.mounted) return;
  final destination = readableLocation(
    await ref.read(appPathsProvider).downloadDirectory(),
  );
  if (!context.mounted) return;

  final move = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImportSheet(items: picked, destination: destination),
  );
  if (move == null || !context.mounted) return;

  // The copying can take a while for long videos.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                move ? tr('Moving into SaveKit…') : tr('Copying into SaveKit…'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  ImportOutcome? outcome;
  try {
    outcome = await ref
        .read(phoneImporterProvider)
        .add(picked, folderId: folderId, move: move);
  } catch (_) {
    outcome = null;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

  final String message;
  if (outcome == null || outcome.added == 0) {
    message = tr('Nothing could be added.');
  } else if (move && !outcome.originalsRemoved) {
    message = tr(
      'Added ${outcome.added}. The originals are still on the phone, because '
      'Android was not allowed to delete them.',
    );
  } else if (outcome.failed > 0) {
    message = tr(
      'Added ${outcome.added}; ${outcome.failed} could not be read.',
    );
  } else if (move) {
    message = outcome.added == 1
        ? tr('Moved into SaveKit.')
        : tr('${outcome.added} files moved into SaveKit.');
  } else {
    message = outcome.added == 1
        ? tr('Copied into SaveKit.')
        : tr('${outcome.added} files copied into SaveKit.');
  }
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// Copy or move, with where each file is now and where it would go.
class _ImportSheet extends StatefulWidget {
  const _ImportSheet({required this.items, required this.destination});

  final List<PickedMedia> items;

  /// SaveKit's folder, as a person would write it.
  final String destination;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  bool _move = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final movable = items.every((item) => item.canMove);
    final total = items.fold(0, (sum, item) => sum + item.size);
    final count = items.length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              children: [
                Text(
                  count == 1 ? tr('Add 1 file') : tr('Add $count files'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatBytes(total),
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(tr('Copy')),
                    ),
                    ButtonSegment(
                      value: true,
                      enabled: movable,
                      icon: const Icon(
                        Icons.drive_file_move_outlined,
                        size: 18,
                      ),
                      label: Text(tr('Move')),
                    ),
                  ],
                  selected: {_move},
                  showSelectedIcon: false,
                  onSelectionChanged: (choice) =>
                      setState(() => _move = choice.first),
                ),
                const SizedBox(height: 12),
                _Explanation(
                  move: _move,
                  movable: movable,
                  destination: widget.destination,
                ),
                const SizedBox(height: 16),
                Text(
                  _move ? tr('MOVING FROM') : tr('COPYING FROM'),
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PickedRow(item: item),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_move),
                  child: Text(
                    _move
                        ? (count == 1
                              ? tr('Move 1 file')
                              : tr('Move $count files'))
                        : (count == 1
                              ? tr('Copy 1 file')
                              : tr('Copy $count files')),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.move,
    required this.movable,
    required this.destination,
  });

  final bool move;
  final bool movable;
  final String destination;

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? AppColors.textMuted,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: move ? AppColors.warning : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (move) ...[
            line(
              Icons.drive_file_move_outlined,
              tr(
                'The files leave your gallery and live only in SaveKit. Other '
                'apps will no longer see them.',
              ),
              color: AppColors.text,
            ),
            line(
              Icons.verified_user_outlined,
              tr(
                'Android asks you to confirm before the originals are '
                'deleted. If you say no, they stay in both places.',
              ),
            ),
          ] else ...[
            line(
              Icons.copy_rounded,
              tr(
                'SaveKit keeps its own copy. The originals stay where they '
                'are, so they use space twice.',
              ),
              color: AppColors.text,
            ),
            if (!movable)
              line(
                Icons.info_outline_rounded,
                tr(
                  'Moving works only for photos and videos from this phone’s '
                  'gallery, not from cloud drives or other apps.',
                ),
              ),
          ],
          Text(
            move ? tr('MOVING TO') : tr('COPYING TO'),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              destination,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// A small preview of a picked file.
final _pickedPreviewProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, uri) => ref.watch(spaceServiceProvider).preview(uri, size: 160),
    );

class _PickedRow extends ConsumerWidget {
  const _PickedRow({required this.item});

  final PickedMedia item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(_pickedPreviewProvider(item.uri)).value;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            width: 44,
            height: 44,
            child: preview == null
                ? ColoredBox(
                    color: AppColors.surfaceHigh,
                    child: Icon(
                      item.isVideo
                          ? Icons.movie_outlined
                          : Icons.image_outlined,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  )
                : Image.memory(preview, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  item.location,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                [
                  formatBytes(item.size),
                  if (!item.canMove) tr('copy only'),
                ].where((part) => part.isNotEmpty).join(' · '),
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
