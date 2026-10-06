// Lightweight validation helpers used across the auth screens.
// Mirrors client-side checks from the MVEC web frontend.

bool isEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

bool isPhone(String value) => phoneProblem(value) == null;

/// Explains exactly what to correct about a telephone number.
///
/// The old wording ("Enter a valid telephone number.") gave no clue whether
/// digits were missing, extra, or simply not a Rwandan number, so a
/// half-typed number looked like a rejected login. Returns `null` when the
/// number is acceptable. Mirrors the backend's `describePhoneIssue`.
String? phoneProblem(String value) {
  final v = value.trim();
  final digits = v.replaceAll(RegExp(r'[^\d]'), '');

  if (digits.isEmpty) {
    return 'Enter a Rwandan telephone number, e.g. 0788123456 or +250788123456.';
  }

  final hasCountryCode = digits.startsWith('250');
  final expected = hasCountryCode ? 12 : 10;

  if (digits.length < expected) {
    return 'Your telephone number is incomplete: ${digits.length} of $expected digits entered. '
        'Enter all $expected digits, e.g. 0788123456.';
  }
  if (digits.length > expected) {
    return 'Your telephone number is too long: ${digits.length} digits entered, but a Rwandan '
        'number has $expected. Example: 0788123456.';
  }

  final local = hasCountryCode ? '0${digits.substring(3)}' : digits;
  if (!RegExp(r'^07[2389]\d{7}$').hasMatch(local)) {
    return 'That is not a valid Rwandan number. It must start with 07 (e.g. 0788123456) '
        'or +2507 (e.g. +250788123456).';
  }
  return null;
}

String? validateEmailOrPhone(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter your email or telephone number.';
  if (v.contains('@')) {
    if (!isEmail(v)) return 'Enter a valid email address, e.g. you@example.com.';
    return null;
  }
  return phoneProblem(v);
}

String? validatePhone(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter your telephone number, e.g. 0788123456.';
  return phoneProblem(v);
}

String? validateEmail(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return null;
  if (!isEmail(v)) return 'Enter a valid email address.';
  return null;
}

String? validateFullName(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter your full name.';
  if (v.split(RegExp(r'\s+')).length < 2) {
    return 'Enter your first and last name.';
  }
  return null;
}

String? validatePassword(String? value) {
  final v = value ?? '';
  if (v.isEmpty) return 'Enter your password.';
  if (v.length < 6) return 'Password must be at least 6 characters.';
  return null;
}

String? validateConfirmPassword(String? value, String? password) {
  if (value == null || value.isEmpty) return 'Confirm your password.';
  if (value != password) return 'Passwords do not match.';
  return null;
}

String? validateOtp(String? value) {
  final v = (value ?? '').trim();
  if (v.length != 6) return 'Enter the complete 6-digit code.';
  if (RegExp(r'^\d{6}$').hasMatch(v) == false) {
    return 'The code contains digits only.';
  }
  return null;
}