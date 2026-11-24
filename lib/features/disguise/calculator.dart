/// A plain four-function calculator, as on any phone. It also remembers
/// every digit typed since the last clear, so the disguise can tell when the
/// secret code was entered.
class Calculator {
  String _display = '0';
  double? _stored;
  String? _operator;
  bool _fresh = true;

  /// Digits typed since the last clear or result, for the secret code.
  String typed = '';

  String get display => _display;

  /// The operator waiting for its second number, for highlighting.
  String? get pendingOperator => _fresh ? _operator : null;

  void digit(String d) {
    typed += d;
    if (_fresh || _display == '0') {
      _display = d;
      _fresh = false;
    } else if (_display.length < 15) {
      _display += d;
    }
  }

  void point() {
    if (_fresh) {
      _display = '0.';
      _fresh = false;
    } else if (!_display.contains('.')) {
      _display += '.';
    }
  }

  void clear() {
    _display = '0';
    _stored = null;
    _operator = null;
    _fresh = true;
    typed = '';
  }

  void backspace() {
    if (_fresh) return;
    _display = _display.length <= 1
        ? '0'
        : _display.substring(0, _display.length - 1);
    if (_display == '-') _display = '0';
    if (typed.isNotEmpty) typed = typed.substring(0, typed.length - 1);
  }

  void toggleSign() {
    if (_display == '0' || _display == 'Error') return;
    _display = _display.startsWith('-') ? _display.substring(1) : '-$_display';
  }

  void percent() {
    final value = double.tryParse(_display);
    if (value == null) return;
    _display = _format(value / 100);
  }

  /// One of + − × ÷.
  void operator(String op) {
    if (_operator != null && !_fresh) _evaluate();
    _stored = double.tryParse(_display);
    _operator = op;
    _fresh = true;
  }

  /// Works out the result. Returns the digits typed for it, before they are
  /// forgotten, so the caller can compare them with the secret code.
  String equals() {
    final entered = typed;
    if (_operator != null) _evaluate();
    _operator = null;
    _stored = null;
    _fresh = true;
    typed = '';
    return entered;
  }

  void _evaluate() {
    final a = _stored;
    final b = double.tryParse(_display);
    if (a == null || b == null) return;
    final double result;
    switch (_operator) {
      case '+':
        result = a + b;
      case '−':
        result = a - b;
      case '×':
        result = a * b;
      case '÷':
        if (b == 0) {
          _display = 'Error';
          return;
        }
        result = a / b;
      default:
        return;
    }
    _display = _format(result);
    _stored = result;
  }

  static String _format(double value) {
    if (value.isNaN || value.isInfinite) return 'Error';
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    var text = value.toStringAsPrecision(12);
    if (text.contains('e')) return text;
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }
}
