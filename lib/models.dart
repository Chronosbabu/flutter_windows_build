class Eleve {
  String id;                    // Nouvel ID unique
  String nom;
  String postNom;
  String prenom;
  String classe;
  String section;
  Map<String, double> paid = {};
  List<Map<String, dynamic>> transactions = [];

  Eleve({
    required this.id,
    required this.nom,
    required this.postNom,
    required this.prenom,
    required this.classe,
    required this.section,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'postNom': postNom,
    'prenom': prenom,
    'classe': classe,
    'section': section,
    'paid': paid,
    'transactions': transactions,
  };

  factory Eleve.fromJson(Map<String, dynamic> json) {
    return Eleve(
      id: json['id'] ?? '',
      nom: json['nom'] ?? '',
      postNom: json['postNom'] ?? '',
      prenom: json['prenom'] ?? '',
      classe: json['classe'] ?? '',
      section: json['section'] ?? 'Primaire',
    )
      ..paid = Map<String, double>.from(json['paid'] ?? {})
      ..transactions = (json['transactions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  }
}

class Administration {
  String nom;
  double pourcentage;

  Administration({required this.nom, required this.pourcentage});

  Map<String, dynamic> toJson() => {
    'nom': nom,
    'pourcentage': pourcentage,
  };

  factory Administration.fromJson(Map<String, dynamic> json) {
    return Administration(
      nom: json['nom'] ?? '',
      pourcentage: (json['pourcentage'] ?? 0.0).toDouble(),
    );
  }
}

class SchoolConfig {
  String schoolName;
  double defaultMonthlyFee;
  List<String> sections = ['Primaire', 'Secondaire'];
  Map<String, double> feesBySection = {};
  Map<String, Map<String, double>> monthlyExceptionsBySection = {};
  List<Administration> administrations = [];

  // ==================== CLASSES & SOUS-CLASSES ====================
  //
  // Numéros de classe par section (ex: "Primaire" -> ['1ère', ..., '6ème']).
  // Générés automatiquement la première fois via defaultClassesForSectionName,
  // mais stockés ici pour rester stables et pouvoir être complétés manuellement
  // par l'utilisateur (ex: pour une section personnalisée).
  Map<String, List<String>> classesBySection = {};

  // Sous-classes par "section|numéroDeClasse" (ex: "Primaire|7ème" -> ['A','B']).
  // Toujours ajoutées manuellement par l'utilisateur.
  Map<String, List<String>> subClassesByClasse = {};

  // ==================== NOUVEAU : FRAIS & EXCEPTIONS PAR CLASSE ====================
  //
  // Certaines écoles font payer des montants différents selon le numéro de
  // classe (ex: 1ère primaire ne paie pas le même montant que 6ème primaire),
  // même au sein d'une même section. Ces deux champs permettent de définir
  // un frais (ou une exception mensuelle) propre à un numéro de classe précis.
  //
  // Clé utilisée : "section|numéroDeClasse" (ex: "Primaire|6ème").
  // Si aucune entrée n'existe pour une classe précise, on retombe sur le
  // frais/l'exception de la SECTION entière (comportement actuel, inchangé).
  Map<String, double> feesByClasse = {};
  Map<String, Map<String, double>> monthlyExceptionsByClasse = {};

  SchoolConfig({
    required this.schoolName,
    this.defaultMonthlyFee = 35000,
    List<String>? sections,
    Map<String, double>? feesBySection,
    Map<String, Map<String, double>>? monthlyExceptionsBySection,
    List<Administration>? administrations,
    Map<String, List<String>>? classesBySection,
    Map<String, List<String>>? subClassesByClasse,
    Map<String, double>? feesByClasse,
    Map<String, Map<String, double>>? monthlyExceptionsByClasse,
  }) {
    this.sections = sections ?? ['Primaire', 'Secondaire'];
    this.feesBySection = feesBySection ?? {};
    this.monthlyExceptionsBySection = monthlyExceptionsBySection ?? {};
    this.administrations = administrations ?? [];
    this.classesBySection = classesBySection ?? {};
    this.subClassesByClasse = subClassesByClasse ?? {};
    this.feesByClasse = feesByClasse ?? {};
    this.monthlyExceptionsByClasse = monthlyExceptionsByClasse ?? {};
  }

  // Numéros de classe générés AUTOMATIQUEMENT selon le nom de la section.
  // Basé sur le système scolaire de la RDC :
  //   - Maternelle  : 1ère à 3ème
  //   - Primaire    : 1ère à 6ème
  //   - Secondaire  : 7ème, 8ème, puis 1ère à 4ème
  // Si la section ne correspond à aucun de ces noms (section personnalisée),
  // on retourne une liste vide : l'utilisateur devra ajouter les numéros de
  // classe lui-même.
  static List<String> defaultClassesForSectionName(String section) {
    final normalized = section.trim().toLowerCase();
    if (normalized.contains('maternelle')) {
      return ['1ère', '2ème', '3ème'];
    } else if (normalized.contains('primaire')) {
      return ['1ère', '2ème', '3ème', '4ème', '5ème', '6ème'];
    } else if (normalized.contains('secondaire')) {
      return ['7ème', '8ème', '1ère', '2ème', '3ème', '4ème'];
    }
    return [];
  }

  Map<String, dynamic> toJson() => {
    'schoolName': schoolName,
    'defaultMonthlyFee': defaultMonthlyFee,
    'sections': sections,
    'feesBySection': feesBySection,
    'monthlyExceptionsBySection': monthlyExceptionsBySection,
    'administrations': administrations.map((a) => a.toJson()).toList(),
    'classesBySection': classesBySection,
    'subClassesByClasse': subClassesByClasse,
    'feesByClasse': feesByClasse,
    'monthlyExceptionsByClasse': monthlyExceptionsByClasse,
  };

  factory SchoolConfig.fromJson(Map<String, dynamic> json) {
    return SchoolConfig(
      schoolName: json['schoolName'] ?? "MAPENDO TCC",
      sections: List<String>.from(json['sections'] ?? ['Primaire', 'Secondaire']),
      feesBySection: Map<String, double>.from(json['feesBySection'] ?? {}),
      monthlyExceptionsBySection: (json['monthlyExceptionsBySection'] as Map? ?? {}).map(
            (key, value) => MapEntry(key, Map<String, double>.from(value)),
      ),
      administrations: (json['administrations'] as List? ?? [])
          .map((a) => Administration.fromJson(a))
          .toList(),
      classesBySection: (json['classesBySection'] as Map? ?? {}).map(
            (key, value) => MapEntry(
          key as String,
          List<String>.from(value as List? ?? []),
        ),
      ),
      subClassesByClasse: (json['subClassesByClasse'] as Map? ?? {}).map(
            (key, value) => MapEntry(
          key as String,
          List<String>.from(value as List? ?? []),
        ),
      ),
      feesByClasse: Map<String, double>.from(json['feesByClasse'] ?? {}),
      monthlyExceptionsByClasse: (json['monthlyExceptionsByClasse'] as Map? ?? {}).map(
            (key, value) => MapEntry(key as String, Map<String, double>.from(value)),
      ),
    );
  }
}

class SchoolYearData {
  List<Eleve> eleves;

  SchoolYearData({required this.eleves});

  Map<String, dynamic> toJson() => {
    'eleves': eleves.map((e) => e.toJson()).toList(),
  };

  factory SchoolYearData.fromJson(Map<String, dynamic> json) {
    return SchoolYearData(
      eleves: (json['eleves'] as List? ?? [])
          .map((e) => Eleve.fromJson(e))
          .toList(),
    );
  }
}