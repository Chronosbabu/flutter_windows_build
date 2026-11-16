class AgeUtils {
  /// Lit une date au format jj/mm/aaaa (ou aaaa-mm-jj en secours).
  static DateTime? parseDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;

    final parts = t.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day == null || month == null || year == null) return null;
      if (parts[2].length != 4) return null;
      final d = DateTime(year, month, day);
      if (d.day != day || d.month != month || d.year != year) return null;
      return d;
    }

    return DateTime.tryParse(t);
  }

  /// Retourne l'âge en années complètes, ou null si la date est absente/invalide.
  static int? calculerAge(String dateNaissance, {DateTime? reference}) {
    final d = parseDate(dateNaissance);
    if (d == null) return null;
    final now = reference ?? DateTime.now();
    int age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      age--;
    }
    if (age < 0) return null;
    return age;
  }

  /// "12 ans", "1 an", "0 an"
  static String formaterAge(int age) => age <= 1 ? "$age an" : "$age ans";

  /// Retourne "12 ans" ou [vide] si la date de naissance n'est pas exploitable.
  static String libelle(String dateNaissance, {String vide = ''}) {
    final a = calculerAge(dateNaissance);
    if (a == null) return vide;
    return formaterAge(a);
  }
}