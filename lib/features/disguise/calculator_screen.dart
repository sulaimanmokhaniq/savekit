import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/settings/app_settings.dart';
import '../vault/application/vault_lock.dart';
import 'calculator.dart';

/// Whether the disguised app has been opened with its code this time.
class DisguiseUnlocked extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
  void lock() => state = false;
}

final disguiseUnlockedProvider = NotifierProvider<DisguiseUnlocked, bool>(
  DisguiseUnlocked.new,
);

/// What shows while SaveKit is disguised: a real, working calculator. Typing
/// the secret code and then "=" opens the app. Holding "=" asks for the
/// phone's fingerprint or screen lock instead, in case the code is
/// forgotten.
///
/// Its colours are fixed, a calculator's, whatever the app's theme.
class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});

  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  final _calculator = Calculator();

  static const _background = Color(0xFF000000);
  static const _key = Color(0xFF333333);
  static const _function = Color(0xFFA5A5A5);
  static const _operator = Color(0xFFFF9F0A);

  void _press(void Function(Calculator calculator) action) {
    HapticFeedback.selectionClick();
    setState(() => action(_calculator));
  }

  void _equals() {
    HapticFeedback.selectionClick();
    final entered = _calculator.equals();
    final code = ref.read(settingsControllerProvider).disguiseCode;
    if (code != null && entered == code) {
      ref.read(disguiseUnlockedProvider.notifier).unlock();
      return;
    }
    setState(() {});
  }

  Future<void> _unlockWithPhoneLock() async {
    final lock = ref.read(vaultLockServiceProvider);
    if (!await lock.isAvailable()) return;
    if (await lock.authenticate('Calculator')) {
      ref.read(disguiseUnlockedProvider.notifier).unlock();
    }
  }

  Widget _button(
    String label, {
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Color color = _key,
    Color text = Colors.white,
    int flex = 1,
    bool active = false,
    IconData? icon,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AspectRatio(
          aspectRatio: flex.toDouble(),
          child: Material(
            color: active ? Colors.white : color,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Align(
                alignment: flex > 1
                    ? const AlignmentDirectional(-0.6, 0)
                    : Alignment.center,
                child: icon != null
                    ? Icon(icon, size: 30, color: text, semanticLabel: label)
                    : Text(
                        label,
                        style: TextStyle(
                          fontSize: 30,
                          color: active ? color : text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _calculator.pendingOperator;
    Widget digit(String d, {int flex = 1}) =>
        _button(d, flex: flex, onTap: () => _press((c) => c.digit(d)));
    Widget op(String o) => _button(
      o,
      color: _operator,
      active: pending == o,
      onTap: () => _press((c) => c.operator(o)),
    );

    // A calculator reads left to right in every language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _calculator.display,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 84,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _button(
                      'AC',
                      color: _function,
                      text: Colors.black,
                      onTap: () => _press((c) => c.clear()),
                    ),
                    _button(
                      'Delete',
                      icon: Icons.backspace_outlined,
                      color: _function,
                      text: Colors.black,
                      onTap: () => _press((c) => c.backspace()),
                    ),
                    _button(
                      '%',
                      color: _function,
                      text: Colors.black,
                      onTap: () => _press((c) => c.percent()),
                    ),
                    op('÷'),
                  ],
                ),
                Row(children: [digit('7'), digit('8'), digit('9'), op('×')]),
                Row(children: [digit('4'), digit('5'), digit('6'), op('−')]),
                Row(children: [digit('1'), digit('2'), digit('3'), op('+')]),
                Row(
                  children: [
                    digit('0', flex: 2),
                    _button('.', onTap: () => _press((c) => c.point())),
                    _button(
                      '=',
                      color: _operator,
                      onTap: _equals,
                      onLongPress: _unlockWithPhoneLock,
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
