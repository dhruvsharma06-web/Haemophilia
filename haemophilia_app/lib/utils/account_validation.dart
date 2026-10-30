/// Indian mobile numbers or an international number with an explicit + prefix.
String? mobileValidation(String? value) {
  final phone = (value ?? '').replaceAll(RegExp(r'[\s()-]'), '');
  if (phone.startsWith('+91')) {
    return RegExp(r'^\+91[6-9][0-9]{9}$').hasMatch(phone)
        ? null
        : 'Enter a valid 10-digit mobile number or include the country code with +.';
  }
  if (RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone) ||
      RegExp(r'^\+91[6-9][0-9]{9}$').hasMatch(phone) ||
      RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
    return null;
  }
  return 'Enter a valid 10-digit mobile number or include the country code with +.';
}

/// Minimum password length. Every screen, hint and server check uses this value.
const int passwordMinLength = 8;
const int passwordMaxLength = 128;

/// Shown under every password field so the stated rule matches the check.
const String passwordRequirementsHint =
    'At least 8 characters with a letter and a number. Avoid sequences like "abc" or "123".';

const String passwordTooShortMessage =
    'Use at least 8 characters, including a letter and a number.';
const String passwordTooLongMessage = 'Use no more than 128 characters.';
const String passwordRepeatMessage =
    'Do not repeat the same character three or more times in a row.';
const String passwordSequenceMessage =
    'Avoid consecutive sequences such as "abc", "123", "cba" or "qwer".';
const String passwordCommonMessage =
    'Avoid common words such as "password" or the app name.';
const String passwordPersonalMessage =
    'Do not include your name or email address in the password.';

const _keyboardRows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm', '1234567890'];

const _commonWords = [
  'password',
  'passw0rd',
  'welcome',
  'letmein',
  'iloveyou',
  'admin',
  'qwerty',
  'monkey',
  'dragon',
  'sunshine',
  'princess',
  'football',
  'baseball',
  'haemophilia',
  'hemophilia',
  'haemophysio',
  'hemophysio',
  'somaiya',
  'physio',
  'doctor',
  'patient',
];

/// True when [value] holds three or more consecutive characters that step by
/// +1 or -1 in the alphabet or digits ("abc", "CBA", "123", "321").
bool hasSequentialRun(String value, {int run = 3}) {
  final lower = value.toLowerCase();
  var ascending = 1;
  var descending = 1;
  for (var i = 1; i < lower.length; i++) {
    final previous = lower.codeUnitAt(i - 1);
    final current = lower.codeUnitAt(i);
    final sameClass =
        (_isDigit(previous) && _isDigit(current)) ||
        (_isLetter(previous) && _isLetter(current));
    ascending = sameClass && current - previous == 1 ? ascending + 1 : 1;
    descending = sameClass && previous - current == 1 ? descending + 1 : 1;
    if (ascending >= run || descending >= run) return true;
  }
  return false;
}

/// True when the same character appears [run] or more times in a row.
bool hasRepeatedRun(String value, {int run = 3}) {
  var count = 1;
  for (var i = 1; i < value.length; i++) {
    count = value[i].toLowerCase() == value[i - 1].toLowerCase()
        ? count + 1
        : 1;
    if (count >= run) return true;
  }
  return false;
}

/// True when four or more adjacent keyboard keys appear in order ("qwer", "lkjh").
bool hasKeyboardRun(String value, {int run = 4}) {
  final lower = value.toLowerCase();
  for (final row in _keyboardRows) {
    final reversed = row.split('').reversed.join();
    for (var i = 0; i + run <= row.length; i++) {
      if (lower.contains(row.substring(i, i + run)) ||
          lower.contains(reversed.substring(i, i + run))) {
        return true;
      }
    }
  }
  return false;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isLetter(int c) => c >= 0x61 && c <= 0x7a;

/// Returns null for an acceptable password, otherwise the first problem found.
///
/// [email] and [name] are optional; when given, passwords containing the
/// email's local part or any name part of four or more letters are refused.
String? passwordValidation(String value, {String? email, String? name}) {
  if (value.length < passwordMinLength ||
      !RegExp(r'[A-Za-z]').hasMatch(value) ||
      !RegExp(r'[0-9]').hasMatch(value)) {
    return passwordTooShortMessage;
  }
  if (value.length > passwordMaxLength) return passwordTooLongMessage;
  if (hasRepeatedRun(value)) return passwordRepeatMessage;
  if (hasSequentialRun(value) || hasKeyboardRun(value)) {
    return passwordSequenceMessage;
  }
  final lower = value.toLowerCase();
  final lettersOnly = lower
      .replaceAll('0', 'o')
      .replaceAll('1', 'i')
      .replaceAll('3', 'e')
      .replaceAll('4', 'a')
      .replaceAll('5', 's')
      .replaceAll('@', 'a')
      .replaceAll('\$', 's');
  if (_commonWords.any(
    (word) => lower.contains(word) || lettersOnly.contains(word),
  )) {
    return passwordCommonMessage;
  }
  List<String> words(String text) =>
      text.split(RegExp(r'[^a-z]+')).where((p) => p.isNotEmpty).toList();
  final local = email?.trim().toLowerCase().split('@').first ?? '';
  final personal = <String>[
    local,
    ...words(local),
    if (name != null) ...words(name.toLowerCase()),
  ].where((part) => part.length >= 4);
  if (personal.any(lower.contains)) return passwordPersonalMessage;
  return null;
}

bool validEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
