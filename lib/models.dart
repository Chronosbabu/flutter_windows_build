class Eleve {
  String nom;
  String postNom;
  String prenom;
  String classe;
  String section;                    // NOUVEAU : Section ajoutée
  Map<String, double> paid = {};
  List<Map<String, dynamic>> transactions = [];

  Eleve({
    required this.nom,
    required this.postNom,
    required this.prenom,
    required this.classe,
    required this.section,           // Obligatoire maintenant
  });

  Map<String, dynamic> toJson() => {
    'nom': nom,
    'postNom': postNom,
    'prenom': prenom,
    'classe': classe,
    'section': section,          // Sauvegardé
    'paid': paid,
    'transactions': transactions,
  };

  factory Eleve.fromJson(Map<String, dynamic> json) {
    return Eleve(
      nom: json['nom'] ?? '',
      postNom: json['postNom'] ?? '',
      prenom: json['prenom'] ?? '',
      classe: json['classe'] ?? '',
      section: json['section'] ?? 'Secondaire', // Valeur par défaut si ancien fichier
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
  Map<String, double> feesBySection;                    // Frais mensuel par section
  Map<String, Map<String, double>> monthlyExceptionsBySection; // Exceptions par section
  List<String> sections;                                // Liste des sections
  List<Administration> administrations = [];

  SchoolConfig({
    required this.schoolName,
    Map<String, double>? feesBySection,
    Map<String, Map<String, double>>? monthlyExceptionsBySection,
    List<String>? sections,
    List<Administration>? administrations,
  })  : feesBySection = feesBySection ?? {
    'Maternelle': 25000,
    'Primaire': 30000,
    'Secondaire': 35000,
  },
        monthlyExceptionsBySection = monthlyExceptionsBySection ?? {},
        sections = sections ?? ['Maternelle', 'Primaire', 'Secondaire'],
        administrations = administrations ?? [
          Administration(nom: "Enseignants", pourcentage: 60.0),
          Administration(nom: "Autres", pourcentage: 40.0),
        ];

  Map<String, dynamic> toJson() => {
    'schoolName': schoolName,
    'feesBySection': feesBySection,
    'monthlyExceptionsBySection': monthlyExceptionsBySection,
    'sections': sections,
    'administrations': administrations.map((a) => a.toJson()).toList(),
  };

  factory SchoolConfig.fromJson(Map<String, dynamic> json) {
    return SchoolConfig(
      schoolName: json['schoolName'] ?? 'Etablissement Scolaire',
      feesBySection: Map<String, double>.from(json['feesBySection'] ?? {}),
      monthlyExceptionsBySection: (json['monthlyExceptionsBySection'] as Map? ?? {}).map(
            (key, value) => MapEntry(key, Map<String, double>.from(value)),
      ),
      sections: List<String>.from(json['sections'] ?? ['Maternelle', 'Primaire', 'Secondaire']),
      administrations: (json['administrations'] as List? ?? [])
          .map((a) => Administration.fromJson(a))
          .toList(),
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
