/// Basic input sanitizers applied before sending data to the API.
class InputSanitizer {
  InputSanitizer._();

  /// Trim, collapse internal whitespace, drop control characters.
  static String clean(String input) {
    return input
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String email(String input) => clean(input).toLowerCase();

  /// Keep letters, spaces, hyphens, apostrophes for names/barangays.
  static String name(String input) {
    final cleaned = clean(input);
    return cleaned.replaceAll(RegExp(r"[^A-Za-zÀ-ÿ'’\-\. ]"), '');
  }

  /// Allow a safe subset for titles/descriptions (strip HTML/script).
  static String text(String input, {int max = 2000}) {
    var cleaned = clean(input);
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]*>'), '');
    if (cleaned.length > max) cleaned = cleaned.substring(0, max);
    return cleaned;
  }
}
