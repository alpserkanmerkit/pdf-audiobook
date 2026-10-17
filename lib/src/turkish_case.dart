/// K17: Turkish upper-case conversion. Dart's locale-insensitive [String.toUpperCase]
/// turns a dotted 'i' into 'I' ('S. Demir' -> 'S. DEMIR'); in Turkish the correct
/// letter is 'İ'. It first explicitly applies the i -> İ and ı -> I mappings, then
/// upper-cases the remaining characters with the standard function (ş/ğ/ü/ö/ç are already correct).
String turkishUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
