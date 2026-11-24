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

  // ==========================================================================
  // ⚡ NOUVEAU — PROCHAIN ANNIVERSAIRE (compte à rebours)
  // --------------------------------------------------------------------------
  // Convention retenue pour une naissance un 29 février : les années non
  // bissextiles, l'anniversaire est célébré le 1er MARS. C'est le comportement
  // naturel de DateTime en Dart (DateTime(annee, 2, 29) se normalise tout
  // seul en 1er mars quand février n'a que 28 jours cette année-là), donc
  // aucun code spécial n'est nécessaire : le calcul ci-dessous l'applique
  // automatiquement.
  // ==========================================================================

  /// Ajoute [months] mois calendaires à [date], en bornant le jour au dernier
  /// jour du mois cible s'il déborde (ex: 31 janvier + 1 mois -> 28/29 février,
  /// jamais 2 ou 3 mars).
  static DateTime _addMonths(DateTime date, int months) {
    final int totalMonth = date.month - 1 + months;
    final int year = date.year + totalMonth ~/ 12;
    final int month = totalMonth % 12 + 1;
    final int dernierJourDuMois = DateTime(year, month + 1, 0).day;
    final int day = date.day > dernierJourDuMois ? dernierJourDuMois : date.day;
    return DateTime(year, month, day);
  }

  /// Calcule le prochain anniversaire d'un élève à partir de sa date de
  /// naissance, par rapport à [reference] (par défaut : maintenant, heure
  /// locale de l'appareil).
  ///
  /// Retourne `null` si la date de naissance est vide, invalide, ou dans le
  /// futur (aucune naissance n'a encore eu lieu) — dans ce cas, l'appelant
  /// ne doit rien afficher (ou un message "non renseignée").
  static ProchainAnniversaire? prochainAnniversaire(
      String dateNaissance, {
        DateTime? reference,
      }) {
    final d = parseDate(dateNaissance);
    if (d == null) return null;

    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final birthDate = DateTime(d.year, d.month, d.day);
    if (birthDate.isAfter(today)) return null; // naissance dans le futur

    final int ageActuel = calculerAge(dateNaissance, reference: now) ?? 0;

    // Prochaine occurrence calendaire du jour/mois de naissance (le 29/02
    // se normalise automatiquement en 1er mars les années non bissextiles).
    DateTime nextBirthday = DateTime(today.year, d.month, d.day);
    if (nextBirthday.isBefore(today)) {
      nextBirthday = DateTime(today.year + 1, d.month, d.day);
    }
    final int ageProchain = nextBirthday.year - d.year;

    if (nextBirthday.isAtSameMomentAs(today)) {
      return ProchainAnniversaire(
        ageActuel: ageActuel,
        ageProchain: ageProchain,
        estAujourdHui: true,
        dateProchainAnniversaire: nextBirthday,
        joursRestants: 0,
        mois: 0,
        jours: 0,
        heures: 0,
        minutes: 0,
        secondes: 0,
      );
    }

    // Décomposition calendaire exacte (mois entiers + jours restants), en
    // partant d'aujourd'hui (date seule, sans l'heure courante).
    int mois = (nextBirthday.year - today.year) * 12 +
        (nextBirthday.month - today.month);
    if (mois < 0) mois = 0;
    while (_addMonths(today, mois).isAfter(nextBirthday)) {
      mois--;
    }
    final DateTime curseur = _addMonths(today, mois);
    final int jours = nextBirthday.difference(curseur).inDays;
    final int joursRestants = nextBirthday.difference(today).inDays;

    // Temps restant aujourd'hui avant minuit (tourne chaque seconde).
    final DateTime minuitCeSoir = today.add(const Duration(days: 1));
    final Duration resteAujourdhui = minuitCeSoir.difference(now);
    final int heures = resteAujourdhui.inHours;
    final int minutes = resteAujourdhui.inMinutes % 60;
    final int secondes = resteAujourdhui.inSeconds % 60;

    return ProchainAnniversaire(
      ageActuel: ageActuel,
      ageProchain: ageProchain,
      estAujourdHui: false,
      dateProchainAnniversaire: nextBirthday,
      joursRestants: joursRestants,
      mois: mois,
      jours: jours,
      heures: heures,
      minutes: minutes,
      secondes: secondes,
    );
  }

  /// Phrase complète pour la fiche détaillée d'un élève, ex :
  /// "Aura 13 ans dans 3 mois, 20 jours, 12 h 0 min 0 s".
  /// Retourne [vide] si la date de naissance n'est pas exploitable.
  static String libelleProchainAnniversaire(
      String dateNaissance, {
        DateTime? reference,
        String vide = '',
      }) {
    final info = prochainAnniversaire(dateNaissance, reference: reference);
    if (info == null) return vide;
    if (info.estAujourdHui) return "Anniversaire aujourd'hui !";

    final parts = <String>[];
    if (info.mois > 0) parts.add("${info.mois} mois");
    parts.add("${info.jours} jour${info.jours > 1 ? 's' : ''}");
    parts.add("${info.heures} h ${info.minutes} min ${info.secondes} s");

    return "Aura ${formaterAge(info.ageProchain)} dans ${parts.join(', ')}";
  }

  /// Phrase courte pour une liste d'élèves, ex : "Anniversaire dans 12 jours".
  /// N'affiche rien (retourne [vide]) si l'anniversaire est à plus de
  /// [seuilJours] jours (par défaut 30), pour ne pas surcharger la liste.
  static String libelleAnniversaireProche(
      String dateNaissance, {
        DateTime? reference,
        int seuilJours = 30,
        String vide = '',
      }) {
    final info = prochainAnniversaire(dateNaissance, reference: reference);
    if (info == null) return vide;
    if (info.estAujourdHui) return "Anniversaire aujourd'hui";
    if (info.joursRestants > seuilJours) return vide;
    return "Anniversaire dans ${info.joursRestants} jour"
        "${info.joursRestants > 1 ? 's' : ''}";
  }
}

/// Résultat du calcul du prochain anniversaire d'un élève. Voir
/// [AgeUtils.prochainAnniversaire].
class ProchainAnniversaire {
  final int ageActuel;
  final int ageProchain;
  final bool estAujourdHui;
  final DateTime dateProchainAnniversaire;
  final int joursRestants;
  final int mois;
  final int jours;
  final int heures;
  final int minutes;
  final int secondes;

  const ProchainAnniversaire({
    required this.ageActuel,
    required this.ageProchain,
    required this.estAujourdHui,
    required this.dateProchainAnniversaire,
    required this.joursRestants,
    required this.mois,
    required this.jours,
    required this.heures,
    required this.minutes,
    required this.secondes,
  });
}