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

String? passwordValidation(String value) {
  if (value.length < 8 ||
      !RegExp(r'[A-Za-z]').hasMatch(value) ||
      !RegExp(r'[0-9]').hasMatch(value)) {
    return 'Use at least 8 characters, including a letter and a number.';
  }
  return null;
}

bool validEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
