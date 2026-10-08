// ============================================================================
// FICHIER 2/4 — MODÈLES DE DONNÉES (partie de frais_scolaires.dart)
// ============================================================================
// Contient uniquement les classes de données et les constantes :
// Depense, RubriqueStat, SectionStat, DepensePeriodeStats, GroupeOption,
// AutreFraisGroupe, AutreFraisTranche, AutreFrais, AutreFraisPaiement,
// AutreFraisAdministration, RepartitionDetail, AdminAuditLog, Signataire,
// ainsi que formatMontant() et les constantes de dépenses.
//
// Ce fichier fait partie de la MÊME bibliothèque que frais_scolaires.dart
// (directive "part of"). Il ne s'importe jamais tout seul.
// ============================================================================
part of frais_scolaires;

const String kDepenseGlobale = 'globale';
const String kDepenseIndependante = 'independante';
const String kDepenseMixte = 'mixte';
const String kRubriqueAutre = 'Autre';
const String kRubriqueNonAffectee = 'Non affectée';

String formatMontant(double v) {
  final neg = v < -0.5;
  final s = v.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${neg ? '-' : ''}$buf';
}

class Depense {
  String id;
  String motif;
  double montant;
  DateTime date;
  String enregistrePar;
  String portee;
  List<String> sections;
  List<String> classes;
  String rubrique;

  Depense({
    required this.id,
    required this.motif,
    required this.montant,
    required this.date,
    this.enregistrePar = 'Direction',
    this.portee = kDepenseGlobale,
    List<String>? sections,
    List<String>? classes,
    this.rubrique = '',
  })  : sections = sections ?? [],
        classes = classes ?? [];

  factory Depense.fromJson(Map<String, dynamic> json) {
    final String porteeRaw = json['portee'] as String? ?? kDepenseGlobale;
    final String portee = (porteeRaw == kDepenseIndependante ||
        porteeRaw == kDepenseMixte)
        ? porteeRaw
        : kDepenseGlobale;
    return Depense(
      id: json['id'] as String? ?? '',
      motif: json['motif'] as String? ?? '',
      montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.tryParse(json['date'] as String? ?? '') ??
          DateTime.now(),
      enregistrePar: json['enregistrePar'] as String? ?? 'Direction',
      portee: portee,
      sections: (json['sections'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
          [],
      classes: (json['classes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
          [],
      rubrique: json['rubrique'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'motif': motif,
    'montant': montant,
    'date': date.toIso8601String(),
    'enregistrePar': enregistrePar,
    'portee': portee,
    'sections': sections,
    'classes': classes,
    'rubrique': rubrique,
  };

  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String get porteeLabel {
    switch (portee) {
      case kDepenseIndependante:
        return 'Indépendante';
      case kDepenseMixte:
        return 'Mixte';
      case kDepenseGlobale:
      default:
        return 'Globale';
    }
  }

  String get rubriqueAffichee =>
      rubrique.trim().isEmpty ? kRubriqueNonAffectee : rubrique.trim();

  String get sectionsLabel {
    if (portee == kDepenseGlobale || sections.isEmpty) {
      return "Toute l'école";
    }
    return sections.join(', ');
  }

  String get classesLabel {
    if (portee == kDepenseGlobale) return 'Toutes';
    if (classes.isEmpty) return 'Toutes les classes';
    return classes.join(', ');
  }
}

class RubriqueStat {
  final String rubrique;
  final double pourcentage;
  double collecte;
  double globales = 0;
  double independantes = 0;
  double mixtes = 0;

  RubriqueStat({
    required this.rubrique,
    required this.pourcentage,
    required this.collecte,
  });

  double get total => globales + independantes + mixtes;
  double get reste => collecte - total;
}

class SectionStat {
  final String section;
  double collecte;
  double independantes = 0;
  double mixtes = 0;

  SectionStat({required this.section, required this.collecte});

  double get total => independantes + mixtes;
  double get reste => collecte - total;
  bool get aDeLActivite => collecte != 0 || total != 0;
}

class DepensePeriodeStats {
  final String period;
  final List<Depense> depenses;
  final List<RubriqueStat> rubriques;
  final List<SectionStat> sections;
  final double totalCollecte;
  final double globales;
  final double independantes;
  final double mixtes;
  final bool globalesExclues;

  DepensePeriodeStats({
    required this.period,
    required this.depenses,
    required this.rubriques,
    required this.sections,
    required this.totalCollecte,
    required this.globales,
    required this.independantes,
    required this.mixtes,
    required this.globalesExclues,
  });

  double get totalDepenses => globales + independantes + mixtes;
  double get reste => totalCollecte - totalDepenses;

  RubriqueStat? rubriqueParNom(String nom) {
    for (final r in rubriques) {
      if (r.rubrique == nom) return r;
    }
    return null;
  }
}

class GroupeOption {
  final String nom;
  final List<String> sections;
  final bool estOption;

  GroupeOption({
    required this.nom,
    required this.sections,
    required this.estOption,
  });
}

// ============================================================================
// ⚡ NOUVEAU — GROUPE DE "AUTRES FRAIS" PORTANT LE MÊME NOM
// ============================================================================
// Quand plusieurs frais additionnels ont le même nom (ex : "Frais de l'État"
// ajouté une fois par classe/section avec des montants différents), ils sont
// considérés comme UN SEUL type de frais UNIQUEMENT pour la génération des
// rapports. Rien n'est modifié dans les données : chaque frais garde son id,
// son montant et ses paiements. Ce groupe sert seulement à les rassembler
// dans le rapport PDF.
// ============================================================================
class AutreFraisGroupe {
  final String cle;
  final String nom;
  final List<String> ids;
  final double montantMin;
  final double montantMax;

  AutreFraisGroupe({
    required this.cle,
    required this.nom,
    required this.ids,
    required this.montantMin,
    required this.montantMax,
  });

  int get nombreDeFraisFusionnes => ids.length;
}

// ============================================================================
// ⚡ NOUVEAU — TRANCHE D'UN "AUTRE FRAIS" (ex : Première tranche du Frais de
// l'État). Une tranche a un nom et un montant. Les tranches d'un frais sont
// stockées dans AutreFrais.tranchesParCle, par cible (toute l'école, une
// section ou une classe).
// ============================================================================
class AutreFraisTranche {
  String id;
  String nom;
  double montant;

  AutreFraisTranche({
    required this.id,
    required this.nom,
    required this.montant,
  });

  factory AutreFraisTranche.fromJson(Map<String, dynamic> json) =>
      AutreFraisTranche(
        id: json['id'] as String? ?? '',
        nom: json['nom'] as String? ?? '',
        montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'montant': montant,
  };
}

class AutreFrais {
  String id;
  String nom;
  double montant;
  String scope;
  String? section;
  String? classe;
  DateTime dateCreation;
  Map<String, double> montantsParSection;
  Map<String, double> montantsParClasse;
  // ⚡ NOUVEAU — tranches par cible :
  //   'ALL'                  -> toute l'école
  //   'S:<section>'          -> une section
  //   'C:<section>|<classe>' -> une classe (numéro de classe, sans sous-classe)
  // Si aucune tranche n'est définie pour un élève, le frais se paie en une
  // seule fois comme avant.
  Map<String, List<AutreFraisTranche>> tranchesParCle;

  AutreFrais({
    required this.id,
    required this.nom,
    required this.montant,
    this.scope = 'all',
    this.section,
    this.classe,
    DateTime? dateCreation,
    Map<String, double>? montantsParSection,
    Map<String, double>? montantsParClasse,
    Map<String, List<AutreFraisTranche>>? tranchesParCle,
  })  : dateCreation = dateCreation ?? DateTime.now(),
        montantsParSection = montantsParSection ?? {},
        montantsParClasse = montantsParClasse ?? {},
        tranchesParCle = tranchesParCle ?? {};

  factory AutreFrais.fromJson(Map<String, dynamic> json) => AutreFrais(
    id: json['id'] as String? ?? '',
    nom: json['nom'] as String? ?? '',
    montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
    scope: json['scope'] as String? ?? 'all',
    section: json['section'] as String?,
    classe: json['classe'] as String?,
    dateCreation:
    DateTime.tryParse(json['dateCreation'] as String? ?? '') ??
        DateTime.now(),
    montantsParSection:
    (json['montantsParSection'] as Map<String, dynamic>?)?.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
    ) ??
        {},
    montantsParClasse:
    (json['montantsParClasse'] as Map<String, dynamic>?)?.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
    ) ??
        {},
    tranchesParCle:
    (json['tranchesParCle'] as Map<String, dynamic>?)?.map(
          (key, value) => MapEntry(
        key,
        (value as List<dynamic>)
            .map((e) =>
            AutreFraisTranche.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
    ) ??
        {},
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'montant': montant,
    'scope': scope,
    'section': section,
    'classe': classe,
    'dateCreation': dateCreation.toIso8601String(),
    'montantsParSection': montantsParSection,
    'montantsParClasse': montantsParClasse,
    'tranchesParCle': tranchesParCle.map(
          (key, value) => MapEntry(key, value.map((t) => t.toJson()).toList()),
    ),
  };
}

class AutreFraisPaiement {
  String id;
  String autreFraisId;
  String autreFraisNom;
  String eleveId;
  double montant;
  DateTime date;
  String enregistrePar;
  // ⚡ NOUVEAU — informations de tranche (vides si le frais a été payé en une
  // seule fois, sans tranche).
  String trancheId;
  String trancheNom;
  int trancheNumero;
  int trancheTotal;

  AutreFraisPaiement({
    required this.id,
    required this.autreFraisId,
    required this.autreFraisNom,
    required this.eleveId,
    required this.montant,
    required this.date,
    this.enregistrePar = 'Direction',
    this.trancheId = '',
    this.trancheNom = '',
    this.trancheNumero = 0,
    this.trancheTotal = 0,
  });

  factory AutreFraisPaiement.fromJson(Map<String, dynamic> json) =>
      AutreFraisPaiement(
        id: json['id'] as String? ?? '',
        autreFraisId: json['autreFraisId'] as String? ?? '',
        autreFraisNom: json['autreFraisNom'] as String? ?? '',
        eleveId: json['eleveId'] as String? ?? '',
        montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        enregistrePar: json['enregistrePar'] as String? ?? 'Direction',
        trancheId: json['trancheId'] as String? ?? '',
        trancheNom: json['trancheNom'] as String? ?? '',
        trancheNumero: (json['trancheNumero'] as num?)?.toInt() ?? 0,
        trancheTotal: (json['trancheTotal'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'autreFraisId': autreFraisId,
    'autreFraisNom': autreFraisNom,
    'eleveId': eleveId,
    'montant': montant,
    'date': date.toIso8601String(),
    'enregistrePar': enregistrePar,
    'trancheId': trancheId,
    'trancheNom': trancheNom,
    'trancheNumero': trancheNumero,
    'trancheTotal': trancheTotal,
  };

  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }

  // ⚡ NOUVEAU — libellé court de la tranche, ex : "Deuxième tranche (2/3)".
  // Vide si le paiement n'est pas lié à une tranche.
  String get trancheLibelle {
    if (trancheNom.trim().isEmpty) return '';
    if (trancheNumero > 0 && trancheTotal > 0) {
      return '${trancheNom.trim()} ($trancheNumero/$trancheTotal)';
    }
    return trancheNom.trim();
  }
}

class AutreFraisAdministration {
  String id;
  String nom;
  double pourcentage;

  AutreFraisAdministration({
    required this.id,
    required this.nom,
    required this.pourcentage,
  });

  factory AutreFraisAdministration.fromJson(Map<String, dynamic> json) =>
      AutreFraisAdministration(
        id: json['id'] as String? ?? '',
        nom: json['nom'] as String? ?? '',
        pourcentage: (json['pourcentage'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'pourcentage': pourcentage,
  };
}

class RepartitionDetail {
  final String label;
  final double total;
  final Map<String, double> parAdministration;

  RepartitionDetail({
    required this.label,
    required this.total,
    required this.parAdministration,
  });
}

class AdminAuditLog {
  String id;
  String action;
  String eleveId;
  String eleveNomComplet;
  String classe;
  String mois;
  double montantAvant;
  double montantApres;
  DateTime date;

  AdminAuditLog({
    required this.id,
    required this.action,
    required this.eleveId,
    required this.eleveNomComplet,
    required this.classe,
    required this.mois,
    required this.montantAvant,
    required this.montantApres,
    DateTime? date,
  }) : date = date ?? DateTime.now();

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) => AdminAuditLog(
    id: json['id'] as String? ?? '',
    action: json['action'] as String? ?? '',
    eleveId: json['eleveId'] as String? ?? '',
    eleveNomComplet: json['eleveNomComplet'] as String? ?? '',
    classe: json['classe'] as String? ?? '',
    mois: json['mois'] as String? ?? '',
    montantAvant: (json['montantAvant'] as num?)?.toDouble() ?? 0.0,
    montantApres: (json['montantApres'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action,
    'eleveId': eleveId,
    'eleveNomComplet': eleveNomComplet,
    'classe': classe,
    'mois': mois,
    'montantAvant': montantAvant,
    'montantApres': montantApres,
    'date': date.toIso8601String(),
  };

  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

class Signataire {
  String id;
  String nom;
  String fonction;

  Signataire({
    required this.id,
    required this.nom,
    required this.fonction,
  });

  factory Signataire.fromJson(Map<String, dynamic> json) => Signataire(
    id: json['id'] as String? ?? '',
    nom: json['nom'] as String? ?? '',
    fonction: json['fonction'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'fonction': fonction,
  };
}