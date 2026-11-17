/// A failure explained in plain words, with the original message kept for
/// anyone who wants the detail.
class FriendlyError {
  const FriendlyError({
    required this.message,
    required this.raw,
    this.loginRequired = false,
  });

  /// What to tell the user. English; translated where it is shown.
  final String message;

  /// The extractor's own wording.
  final String raw;

  /// Signing in under Platform Accounts is the likely fix.
  final bool loginRequired;

  /// Whether [message] says something the raw text does not.
  bool get isRewritten => message != raw;
}

class _Rule {
  const _Rule(this.pattern, this.message, {this.login = false});

  final String pattern;
  final String message;
  final bool login;
}

/// Checked in order; the first match wins, so the specific come first.
const _rules = [
  _Rule(
    r'confirm your age|age[- ]restricted|inappropriate for some users',
    'This video is age-restricted. Log in to the platform to save it.',
    login: true,
  ),
  _Rule(
    r'private (video|account|post)|is private|only visible to|followers only|'
        r'protected (tweet|post)s?',
    'This is private. Log in with an account that can see it.',
    login: true,
  ),
  _Rule(
    r'log ?in required|login_required|sign in|logged[- ]in|requires? (a )?login|'
        r'authenticat|use --cookies|no csrf|401',
    'This needs an account. Log in to the platform to save it.',
    login: true,
  ),
  _Rule(
    r'rate[- ]?limit|too many requests|429|try again later',
    'The platform is limiting requests right now. Wait a few minutes and '
        'try again.',
  ),
  _Rule(
    r'available in your country|geo[- ]?(restricted|blocked)|'
        r'blocked it in your country',
    'This is not available in your country.',
  ),
  _Rule(
    r'video unavailable|has been removed|no longer available|does not exist|'
        r'404|deleted|account (has been )?(terminated|suspended)',
    'This is no longer available. It may have been deleted.',
  ),
  _Rule(
    r'live event will begin|premieres in|is not yet available|offline\.',
    'This has not started yet. Try again once it is live or published.',
  ),
  _Rule(
    r'requested format (is )?not available|no video formats? found|'
        r'no formats? found',
    'That quality is not offered for this link. Try another quality, or '
        'update the engine.',
  ),
  _Rule(
    r'unsupported url|no suitable extractor|is not a valid url',
    'SaveKit cannot read this kind of link.',
  ),
  _Rule(
    r'no space left|enospc|disk full',
    'The phone is out of storage. Free some space and try again.',
  ),
  _Rule(
    r'name resolution|failed to resolve|network is unreachable|'
        r'no address associated|connection (refused|reset|timed out)|'
        r'timed out|timeout|unable to download webpage|ssl|socketexception',
    'There is a connection problem. Check the internet and try again.',
  ),
  _Rule(
    r'403|forbidden|unable to extract|sign(ature)? extraction|nsig|'
        r'please report this issue',
    'The platform changed something. Update the engine and try again.',
  ),
  _Rule(
    r'ffmpeg|postprocessing|conversion failed',
    'The file downloaded but could not be finished. Try another quality.',
  ),
];

final _compiled = [
  for (final rule in _rules) (RegExp(rule.pattern, caseSensitive: false), rule),
];

/// Turns an extractor's message into something a person can act on. Text
/// that matches nothing known is passed through unchanged.
FriendlyError describeError(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) {
    return const FriendlyError(message: 'Something went wrong.', raw: '');
  }
  for (final (pattern, rule) in _compiled) {
    if (pattern.hasMatch(text)) {
      return FriendlyError(
        message: rule.message,
        raw: text,
        loginRequired: rule.login,
      );
    }
  }
  return FriendlyError(message: text, raw: text);
}

final _connectionTrouble = RegExp(
  r'name resolution|failed to resolve|network is unreachable|'
  r'no address associated|connection (refused|reset|timed out|aborted|closed)|'
  r'timed out|timeout|unable to download webpage|socketexception|'
  r'broken pipe|errno (101|104|110|113)|incompleteread|'
  r'connection was lost|software caused connection abort|'
  r'clientexception|httpexception|failed host lookup',
  caseSensitive: false,
);

/// Whether [raw] says the connection dropped or could not be made, rather
/// than that the platform refused. Such downloads are worth trying again.
bool isConnectionError(String? raw) =>
    raw != null && _connectionTrouble.hasMatch(raw);
