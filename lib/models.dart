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

  SchoolConfig({
    required this.schoolName,
    this.defaultMonthlyFee = 35000,
    List<String>? sections,
    Map<String, double>? feesBySection,
    Map<String, Map<String, double>>? monthlyExceptionsBySection,
    List<Administration>? administrations,
  }) {
    this.sections = sections ?? ['Primaire', 'Secondaire'];
    this.feesBySection = feesBySection ?? {};
    this.monthlyExceptionsBySection = monthlyExceptionsBySection ?? {};
    this.administrations = administrations ?? [];
  }

  Map<String, dynamic> toJson() => {
    'schoolName': schoolName,
    'defaultMonthlyFee': defaultMonthlyFee,
    'sections': sections,
    'feesBySection': feesBySection,
    'monthlyExceptionsBySection': monthlyExceptionsBySection,
    'administrations': administrations.map((a) => a.toJson()).toList(),
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
