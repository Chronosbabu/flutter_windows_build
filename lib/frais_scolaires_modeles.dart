// ============================================================================
// FICHIER 2/4 — MODÈLES DE DONNÉES (partie de frais_scolaires.dart)
// ============================================================================
// Contient uniquement les classes de données et les constantes :
// Depense, RubriqueStat, SectionStat, DepensePeriodeStats, GroupeOption,
// AutreFraisGroupe, AutreFraisTranche, AutreFrais, AutreFraisPaiement,
// AutreFraisAdministration, RepartitionDetail, AdminAuditLog, Signataire,
// RapportPersonnalise (réglage optionnel des montants de rapport),
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

// ⚡ NOUVEAU — ENTRÉES D'ARGENT (apports de caisse)
// La "portée" d'une entrée réutilise volontairement les mêmes constantes que
// les dépenses (kDepenseGlobale/Independante/Mixte) : c'est exactement le
// même concept (toute l'école / une section / plusieurs sections).
const String kEntreeRetourReliquat = 'retour_reliquat';
const String kEntreeDon = 'don';
const String kEntreeSubvention = 'subvention';
const String kEntreeAutre = 'autre_apport';

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
  // ⚡ NOUVEAU — mois scolaire choisi manuellement pour l'imputation dans les
  // rapports mensuels (ex. "Octobre"). null = on utilise la date de la
  // dépense comme avant (compatibilité avec les dépenses existantes).
  String? moisImputation;

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
    this.moisImputation,
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
      moisImputation: json['moisImputation'] as String?,
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
    'moisImputation': moisImputation,
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

// ⚡ NOUVEAU — ENTRÉE D'ARGENT (apport de caisse)
// Même esprit que Depense : une ligne séparée et justifiée dans le livre de
// caisse. On ne modifie jamais une dépense pour "simuler" un retour d'argent
// — on enregistre une Entree distincte, éventuellement liée à une dépense
// (depenseLieeId) pour un retour de reliquat.
class Entree {
  String id;
  DateTime date;
  double montant;
  String type; // kEntreeRetourReliquat / kEntreeDon / kEntreeSubvention / kEntreeAutre
  String rubrique;
  String justification; // OBLIGATOIRE, non vide
  String motif; // nom court, facultatif
  String enregistrePar;
  String portee; // kDepenseGlobale / kDepenseIndependante / kDepenseMixte
  List<String> sections;
  List<String> classes;
  String? moisImputation;
  String? depenseLieeId; // id de la Depense d'origine (retour de reliquat)
  bool annulee;
  DateTime? dateAnnulation;
  String? motifAnnulation;

  Entree({
    required this.id,
    required this.date,
    required this.montant,
    required this.type,
    this.rubrique = '',
    required this.justification,
    this.motif = '',
    this.enregistrePar = 'Direction',
    this.portee = kDepenseGlobale,
    List<String>? sections,
    List<String>? classes,
    this.moisImputation,
    this.depenseLieeId,
    this.annulee = false,
    this.dateAnnulation,
    this.motifAnnulation,
  })  : sections = sections ?? [],
        classes = classes ?? [];

  factory Entree.fromJson(Map<String, dynamic> json) {
    final String porteeRaw = json['portee'] as String? ?? kDepenseGlobale;
    final String portee = (porteeRaw == kDepenseIndependante ||
        porteeRaw == kDepenseMixte)
        ? porteeRaw
        : kDepenseGlobale;
    return Entree(
      id: json['id'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ??
          DateTime.now(),
      montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
      type: json['type'] as String? ?? kEntreeAutre,
      rubrique: json['rubrique'] as String? ?? '',
      justification: json['justification'] as String? ?? '',
      motif: json['motif'] as String? ?? '',
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
      moisImputation: json['moisImputation'] as String?,
      depenseLieeId: json['depenseLieeId'] as String?,
      annulee: json['annulee'] as bool? ?? false,
      dateAnnulation: json['dateAnnulation'] != null
          ? DateTime.tryParse(json['dateAnnulation'] as String)
          : null,
      motifAnnulation: json['motifAnnulation'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'montant': montant,
    'type': type,
    'rubrique': rubrique,
    'justification': justification,
    'motif': motif,
    'enregistrePar': enregistrePar,
    'portee': portee,
    'sections': sections,
    'classes': classes,
    'moisImputation': moisImputation,
    'depenseLieeId': depenseLieeId,
    'annulee': annulee,
    'dateAnnulation': dateAnnulation?.toIso8601String(),
    'motifAnnulation': motifAnnulation,
  };

  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }

  String get typeLabel {
    switch (type) {
      case kEntreeRetourReliquat:
        return 'Retour de reliquat';
      case kEntreeDon:
        return 'Don';
      case kEntreeSubvention:
        return 'Subvention';
      case kEntreeAutre:
      default:
        return 'Autre apport';
    }
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
}

class RubriqueStat {
  final String rubrique;
  final double pourcentage;
  double collecte;
  double globales = 0;
  double independantes = 0;
  double mixtes = 0;
  // ⚡ NOUVEAU — entrées d'argent actives (non annulées) attribuées à cette
  // rubrique, mêmes découpages que les dépenses.
  double entreesGlobales = 0;
  double entreesIndependantes = 0;
  double entreesMixtes = 0;

  RubriqueStat({
    required this.rubrique,
    required this.pourcentage,
    required this.collecte,
  });

  double get total => globales + independantes + mixtes;
  double get totalEntrees =>
      entreesGlobales + entreesIndependantes + entreesMixtes;
  // Reste de la rubrique = collecte (après retenues) + entrées − dépenses.
  double get reste => collecte - total + totalEntrees;
}

class SectionStat {
  final String section;
  double collecte;
  double independantes = 0;
  double mixtes = 0;
  // ⚡ NOUVEAU — entrées d'argent actives rattachées à cette section
  // (indépendantes/mixtes seulement : une entrée globale n'est pas attribuée
  // à une section, comme pour les dépenses).
  double entreesIndependantes = 0;
  double entreesMixtes = 0;

  SectionStat({required this.section, required this.collecte});

  double get total => independantes + mixtes;
  double get totalEntrees => entreesIndependantes + entreesMixtes;
  double get reste => collecte - total + totalEntrees;
  bool get aDeLActivite => collecte != 0 || total != 0 || totalEntrees != 0;
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
  // ⚡ NOUVEAU — retenues prélevées avant la répartition (0 si aucune)
  final double retenues;
  // ⚡ NOUVEAU — entrées d'argent (apports de caisse) de la période.
  // [entrees] contient TOUTES les entrées (actives + annulées, pour
  // l'affichage détaillé) ; les totaux ci-dessous ne comptent que les
  // entrées actives (non annulées).
  final List<Entree> entrees;
  final double entreesGlobales;
  final double entreesIndependantes;
  final double entreesMixtes;

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
    this.retenues = 0.0,
    this.entrees = const [],
    this.entreesGlobales = 0.0,
    this.entreesIndependantes = 0.0,
    this.entreesMixtes = 0.0,
  });

  double get totalDepenses => globales + independantes + mixtes;
  double get totalEntrees =>
      entreesGlobales + entreesIndependantes + entreesMixtes;
  // Reste en caisse = collecté − dépenses + entrées actives.
  double get reste => totalCollecte - totalDepenses + totalEntrees;

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
  // ⚡ NOUVEAU — paiement PAR MOIS : nom du mois (ex : "Novembre") quand cette
  // échéance est un mois. Vide pour une tranche classique. L'ordre de la
  // liste donne l'ordre de paiement (1er mois à payer, 2e, ...). N'est écrit
  // dans le JSON que s'il est rempli (anciennes sauvegardes inchangées).
  String mois;

  AutreFraisTranche({
    required this.id,
    required this.nom,
    required this.montant,
    this.mois = '',
  });

  bool get estMois => mois.trim().isNotEmpty;

  factory AutreFraisTranche.fromJson(Map<String, dynamic> json) =>
      AutreFraisTranche(
        id: json['id'] as String? ?? '',
        nom: json['nom'] as String? ?? '',
        montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
        mois: json['mois'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'montant': montant,
    if (mois.trim().isNotEmpty) 'mois': mois,
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
  // ⚡ NOUVEAU — vrai si le montant a été saisi librement (paiement partiel).
  // Utilisé uniquement pour les frais SANS tranches : un paiement "classique"
  // (saisieLibre = false, cas de tous les anciens paiements) solde le frais
  // comme avant ; les paiements libres s'additionnent jusqu'au montant dû.
  // N'est écrit dans le JSON que s'il vaut vrai (anciennes sauvegardes
  // inchangées).
  bool saisieLibre;

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
    this.saisieLibre = false,
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
        saisieLibre: json['saisieLibre'] == true,
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
    if (saisieLibre) 'saisieLibre': true,
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
  // ⚡ NOUVEAU — retenues déduites avant le calcul des pourcentages
  final double retenues;
  final Map<String, double> parAdministration;

  RepartitionDetail({
    required this.label,
    required this.total,
    required this.parAdministration,
    this.retenues = 0.0,
  });

  /// Montant réellement réparti (total − retenues).
  double get net => total - retenues;
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

// ============================================================================
// ⚡ NOUVEAU — MONTANTS PERSONNALISÉS DU RAPPORT (fonction optionnelle)
// ============================================================================
// Permet à certaines écoles d'afficher, SUR LES RAPPORTS PDF UNIQUEMENT, un
// montant par élève différent du montant réel (ex : 65 000 FC réel -> 60 000
// FC sur le rapport).
//
// - Désactivé par défaut : tant qu'il n'est pas activé, l'application se
//   comporte exactement comme avant.
// - Aucune donnée de l'école n'est modifiée (paiements, reçus, historique,
//   paramètres restent sur les montants réels).
// - Le réglage est enregistré à part (SharedPreferences) : le fichier de
//   données de l'école et la sauvegarde serveur ne changent pas.
// - L'accès est protégé par un mot de passe MODIFIABLE par chaque école
//   (enregistré sur l'appareil). Valeur par défaut ci-dessous.
// ============================================================================

/// Mot de passe PAR DÉFAUT (utilisé tant que l'utilisateur n'en a pas choisi
/// un autre depuis la fenêtre cachée).
const String kMotDePasseRapportPersonnalise = 'Rapport@2026';

class RapportPersonnalise {
  /// Interrupteur général.
  bool actif = false;

  /// Montant du rapport par section : { 'Maternelle': 60000 }
  Map<String, double> parSection = {};

  /// Montant du rapport par classe : { 'Maternelle|1ère': 60000 }
  /// (clé = section|numéro de classe). La classe est prioritaire sur la section.
  Map<String, double> parClasse = {};

  bool _charge = false;
  int _echecs = 0;
  DateTime? _verrouJusqua;

  // ⚡ NOUVEAU — mot de passe courant (modifiable).
  String _motDePasse = kMotDePasseRapportPersonnalise;

  static const String _cleStockage = 'rapport_personnalise_v1';
  static const String _cleMotDePasse = 'rapport_personnalise_mdp_v1';
  static const int _maxEssais = 3;
  static const int _dureeVerrouSecondes = 60;
  static const int longueurMinMotDePasse = 6;

  static String cleClasse(String section, String classeNumero) =>
      '$section|$classeNumero';

  /// Vrai si le mot de passe n'a jamais été changé (valeur par défaut).
  bool get motDePasseParDefaut => _motDePasse == kMotDePasseRapportPersonnalise;

  /// Vrai seulement si la fonction est activée ET qu'au moins un montant est
  /// défini. Sinon, les rapports restent identiques à l'ancien comportement.
  bool get enVigueur =>
      actif && (parSection.isNotEmpty || parClasse.isNotEmpty);

  /// Montant du rapport pour une classe (la classe prime sur la section).
  /// Null si la fonction n'est pas en vigueur ou si rien n'est défini.
  double? montantPour(String section, String classeNumero) {
    if (!enVigueur) return null;
    return parClasse[cleClasse(section, classeNumero)] ?? parSection[section];
  }

  Map<String, double> _lireMontants(dynamic brut) {
    final Map<String, double> result = {};
    if (brut is Map) {
      brut.forEach((k, v) {
        if (v is num && v > 0) {
          result[k.toString()] = v.toDouble();
        }
      });
    }
    return result;
  }

  Future<void> charger() async {
    if (_charge) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? brut = prefs.getString(_cleStockage);
      if (brut == null || brut.isEmpty) {
        actif = false;
        parSection = {};
        parClasse = {};
      } else {
        final data = json.decode(brut);
        if (data is Map) {
          actif = data['actif'] == true;
          parSection = _lireMontants(data['parSection']);
          parClasse = _lireMontants(data['parClasse']);
        }
      }
    } catch (_) {
      // En cas de problème de lecture : fonction désactivée (comportement normal).
      actif = false;
      parSection = {};
      parClasse = {};
    }

    // ⚡ NOUVEAU — chargement du mot de passe choisi par l'utilisateur.
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? mdp = prefs.getString(_cleMotDePasse);
      if (mdp != null && mdp.isNotEmpty) {
        _motDePasse = mdp;
      } else {
        _motDePasse = kMotDePasseRapportPersonnalise;
      }
    } catch (_) {
      _motDePasse = kMotDePasseRapportPersonnalise;
    }

    _charge = true;
  }

  Future<bool> sauvegarder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool ok = await prefs.setString(
        _cleStockage,
        json.encode({
          'actif': actif,
          'parSection': parSection,
          'parClasse': parClasse,
        }),
      );
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Retourne null si le mot de passe est correct, sinon un message d'erreur.
  /// Après 3 erreurs, l'accès est verrouillé 60 secondes.
  String? verifierMotDePasse(String saisi) {
    final now = DateTime.now();
    if (_verrouJusqua != null && now.isBefore(_verrouJusqua!)) {
      final int secondes = _verrouJusqua!.difference(now).inSeconds + 1;
      return "Trop de tentatives. Réessayez dans $secondes seconde(s).";
    }
    if (saisi == _motDePasse) {
      _echecs = 0;
      _verrouJusqua = null;
      return null;
    }

    _echecs++;
    if (_echecs >= _maxEssais) {
      _echecs = 0;
      _verrouJusqua = now.add(const Duration(seconds: _dureeVerrouSecondes));
      return "Mot de passe incorrect. Accès verrouillé pendant "
          "$_dureeVerrouSecondes secondes.";
    }
    return "Mot de passe incorrect (${_maxEssais - _echecs} essai(s) "
        "restant(s)).";
  }

  /// ⚡ NOUVEAU — change le mot de passe. Retourne null si tout s'est bien
  /// passé, sinon un message d'erreur à afficher.
  Future<String?> changerMotDePasse({
    required String ancien,
    required String nouveau,
    required String confirmation,
  }) async {
    final String? erreurAncien = verifierMotDePasse(ancien);
    if (erreurAncien != null) return erreurAncien;

    final String n = nouveau.trim();
    if (n.length < longueurMinMotDePasse) {
      return "Le nouveau mot de passe doit contenir au moins "
          "$longueurMinMotDePasse caractères.";
    }
    if (n != confirmation.trim()) {
      return "La confirmation ne correspond pas au nouveau mot de passe.";
    }
    if (n == _motDePasse) {
      return "Le nouveau mot de passe doit être différent de l'ancien.";
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final bool ok = await prefs.setString(_cleMotDePasse, n);
      if (!ok) return "Échec de l'enregistrement. Réessayez.";
    } catch (_) {
      return "Échec de l'enregistrement. Réessayez.";
    }
    _motDePasse = n;
    return null;
  }
}

/// Instance unique utilisée par toute l'application.
final RapportPersonnalise rapportPersonnalise = RapportPersonnalise();