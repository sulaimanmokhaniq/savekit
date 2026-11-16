import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

import '../../core/l10n/l10n.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_thumbnail.dart';
import '../vault/application/vault_lock.dart';
import 'transfer_controller.dart';

/// Wireless transfer: open the phone's address in a computer's browser on
/// the same Wi-Fi to download from the Vault or send files to it. Sharing
/// lasts only while this screen is open.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  /// The Vault's lock also guards sharing it.
  bool get _locked =>
      ref.read(settingsControllerProvider).lockVault &&
      !ref.read(vaultUnlockedProvider);

  @override
  void initState() {
    super.initState();
    if (!_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(transferProvider.notifier).start();
      });
    }
  }

  Future<void> _unlock() async {
    final ok = await ref
        .read(vaultLockServiceProvider)
        .authenticate(tr('Unlock your Vault'));
    if (!ok || !mounted) return;
    ref.read(vaultUnlockedProvider.notifier).unlock();
    setState(() {});
    await ref.read(transferProvider.notifier).start();
  }

  @override
  Widget build(BuildContext context) {
    // Watching keeps the sharing alive for as long as the screen is.
    final state = ref.watch(transferProvider);
    final locked =
        ref.watch(settingsControllerProvider).lockVault &&
        !ref.watch(vaultUnlockedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Wireless transfer'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: locked
          ? _Message(
              icon: Icons.lock_outline_rounded,
              title: tr('The Vault is locked'),
              message: tr('Unlock it to share its files.'),
              action: tr('Unlock'),
              onAction: _unlock,
            )
          : switch (state.phase) {
              TransferPhase.starting => const Center(
                child: CircularProgressIndicator(),
              ),
              TransferPhase.noNetwork => _Message(
                icon: Icons.wifi_off_rounded,
                title: tr('No Wi-Fi'),
                message: tr(
                  'Connect this phone to Wi-Fi, or turn on its hotspot and '
                  'connect the other device to it.',
                ),
                action: tr('Try again'),
                onAction: ref.read(transferProvider.notifier).start,
              ),
              TransferPhase.failed => _Message(
                icon: Icons.error_outline_rounded,
                title: tr('Sharing could not start'),
                message: tr('Close the screen and open it again.'),
                action: tr('Try again'),
                onAction: ref.read(transferProvider.notifier).start,
              ),
              TransferPhase.running => _Running(state: state),
            },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        EmptyState(icon: icon, title: title, message: message),
        FilledButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    Widget step(int number, String text, {Widget? below}) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(text, style: const TextStyle(height: 1.4)),
                ),
                if (below != null) ...[const SizedBox(height: 8), below],
              ],
            ),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          tr(
            'Get your saved files onto a computer, or send files to this '
            'phone, without a cable.',
          ),
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        step(1, tr('Connect the computer to the same Wi-Fi as this phone.')),
        step(
          2,
          tr('Open this address in its browser:'),
          below: _Copyable(
            // Addresses read left to right in every language.
            text: state.address,
            copied: tr('Address copied'),
          ),
        ),
        step(
          3,
          tr('Enter this code:'),
          below: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              state.code,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
                color: AppColors.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Semantics(
                label: tr('QR code for the address'),
                child: _QrCode(data: state.link, size: 132),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  tr(
                    'Or scan this with another phone’s camera. It opens '
                    'straight away, with no code to type.',
                  ),
                  style: TextStyle(color: AppColors.textMuted, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(
                  'Keep this screen open. Sharing stops as soon as you leave '
                  'it, and only devices on your Wi-Fi with the code get in.',
                ),
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        if (state.received.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            tr('RECEIVED (${state.received.length})'),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          for (final name in state.received)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            tr('They are in the Vault.'),
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

/// Text in a box with a copy button.
class _Copyable extends StatelessWidget {
  const _Copyable({required this.text, required this.copied});

  final String text;

  /// Said after copying.
  final String copied;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: tr('Copy'),
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(copied)));
            },
          ),
        ],
      ),
    );
  }
}

/// A QR code, dark on white whatever the theme, so cameras can read it.
class _QrCode extends StatelessWidget {
  const _QrCode({required this.data, required this.size});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: CustomPaint(
        painter: _QrPainter(
          QrImage(QrCode(payload: QrPayload.fromString(data))),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final cell = size.shortestSide / count;
    final paint = Paint()..color = Colors.black;
    for (var row = 0; row < count; row++) {
      for (var column = 0; column < count; column++) {
        if (!image.isDark(row, column)) continue;
        // A hair of overlap, so no gaps show between neighbouring squares.
        canvas.drawRect(
          Rect.fromLTWH(column * cell, row * cell, cell + 0.3, cell + 0.3),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
