part of frais_scolaires;

// ============================================================================
// ⚡ NOUVEAU — LISTE « EN ORDRE / PAS EN ORDRE » SUR PLUSIEURS MOIS
// ============================================================================
// Fonction OPTIONNELLE : la liste sur un seul mois (getStudentsByOrderStatus /
// generateOrderStatusPdf) reste inchangée. Ce fichier ajoute seulement la
// version « plusieurs mois ». Aucune donnée de l'école n'est modifiée.
//
// Règle :
//   - On calcule, pour chaque élève et chaque mois choisi, s'il est en ordre
//     (payé >= requis, avec SON montant requis personnel s'il en a un).
//   - Statut « Ont payé » (enOrdre = true) :
//         tousLesMois = true  -> en ordre pour CHACUN des mois choisis
//         tousLesMois = false -> en ordre pour AU MOINS UN des mois choisis
//   - Statut « Pas encore payé » (enOrdre = false) :
//         tousLesMois = true  -> pas en ordre pour CHACUN des mois choisis
//                                (aucun mois soldé)
//         tousLesMois = false -> pas en ordre pour AU MOINS UN des mois
//                                (il manque quelque chose)
//   Avec les réglages par défaut (Ont payé + tous / Pas payé + au moins un),
//   les deux listes se complètent : chaque élève est dans l'une ou l'autre.
// ============================================================================

/// Situation d'un élève pour UN mois.
class OrdreMoisDetail {
  final String mois;
  final double paye;
  final double requis;
  final bool enOrdre;

  /// Exception personnelle de l'élève pour ce mois (voir plus bas).
  final TypeExceptionMois exception;

  const OrdreMoisDetail({
    required this.mois,
    required this.paye,
    required this.requis,
    required this.enOrdre,
    this.exception = TypeExceptionMois.aucune,
  });

  double get reste => requis - paye > 0 ? requis - paye : 0.0;

  /// L'élève ne doit rien payer pour ce mois (exception à 0 FC).
  bool get exonere => exception == TypeExceptionMois.exonere;
}

/// Situation d'un élève sur l'ensemble des mois choisis.
class OrdreEleveMulti {
  final Eleve eleve;
  final List<OrdreMoisDetail> details;

  const OrdreEleveMulti({required this.eleve, required this.details});

  int get nbMoisEnOrdre => details.where((d) => d.enOrdre).length;
  int get nbMoisPasEnOrdre => details.length - nbMoisEnOrdre;
  double get totalPaye => details.fold(0.0, (s, d) => s + d.paye);
  double get totalRequis => details.fold(0.0, (s, d) => s + d.requis);
  double get totalReste => details.fold(0.0, (s, d) => s + d.reste);
}

extension FraisScolairesOrdreMulti on FraisScolaires {
  /// Retire les doublons et les mois inconnus, puis range les mois dans
  /// l'ordre de l'année scolaire (Septembre -> Juin).
  List<String> trierMoisScolaires(Iterable<String> mois) {
    final valides = mois.where((m) => months.contains(m)).toSet().toList();
    valides.sort((a, b) => months.indexOf(a).compareTo(months.indexOf(b)));
    return valides;
  }

  /// Nom court d'un mois (ex : "Sep", "Oct").
  String libelleMoisCourt(String mois) =>
      mois.length <= 3 ? mois : mois.substring(0, 3);

  /// Phrase qui explique quelle liste va être produite.
  String libelleConditionOrdreMulti({
    required bool enOrdre,
    required bool tousLesMois,
  }) {
    if (enOrdre) {
      return tousLesMois
          ? "En ordre pour TOUS les mois choisis"
          : "En ordre pour AU MOINS UN des mois choisis";
    }
    return tousLesMois
        ? "Pas en ordre pour TOUS les mois choisis (aucun mois soldé)"
        : "Pas en ordre pour AU MOINS UN des mois choisis";
  }

  List<OrdreEleveMulti> getStudentsByOrderStatusMulti({
    required List<String> mois,
    required bool enOrdre,
    required bool tousLesMois,
    String? sectionFilter,
    String? classFilter,
    // ⚡ Élèves en exception (par défaut : comportement d'origine).
    bool inclureExoneres = true,
    bool inclureMontantDifferent = true,
  }) {
    final moisTries = trierMoisScolaires(mois);
    if (moisTries.isEmpty) return [];

    Iterable<Eleve> students = currentData.eleves;
    if (sectionFilter != null) {
      students = students.where((e) => e.section == sectionFilter);
    }
    if (classFilter != null) {
      students = students.where((e) => e.classe == classFilter);
    }

    final result = <OrdreEleveMulti>[];
    for (final e in students) {
      if (!eleveRetenuSelonExceptions(e, moisTries,
          inclureExoneres: inclureExoneres,
          inclureMontantDifferent: inclureMontantDifferent)) {
        continue;
      }
      final details = <OrdreMoisDetail>[
        for (final m in moisTries)
          OrdreMoisDetail(
            mois: m,
            paye: e.paid[m] ?? 0.0,
            requis: getRequiredForMonthForEleve(e, m),
            enOrdre: isStudentEnOrdrePourMois(e, m),
            exception: typeExceptionPourMois(e, m),
          ),
      ];

      final int nbCorrespond = details.where((d) => d.enOrdre == enOrdre).length;
      final bool retenu =
      tousLesMois ? nbCorrespond == details.length : nbCorrespond >= 1;
      if (retenu) {
        result.add(OrdreEleveMulti(eleve: e, details: details));
      }
    }

    result.sort((a, b) {
      final c = a.eleve.classe.compareTo(b.eleve.classe);
      if (c != 0) return c;
      return a.eleve.nom.compareTo(b.eleve.nom);
    });
    return result;
  }

  Future<Map<String, dynamic>> generateOrderStatusMultiPdf({
    required String filename,
    required List<String> mois,
    required bool enOrdre,
    required bool tousLesMois,
    String? sectionFilter,
    String? classFilter,
    bool inclureExoneres = true,
    bool inclureMontantDifferent = true,
  }) async {
    // Chargement du réglage « montants personnalisés du rapport ».
    await rapportPersonnalise.charger();

    final List<String> moisTries = trierMoisScolaires(mois);
    if (moisTries.isEmpty) {
      return {'success': false, 'error': 'Aucun mois sélectionné.'};
    }

    final lignes = getStudentsByOrderStatusMulti(
      mois: moisTries,
      enOrdre: enOrdre,
      tousLesMois: tousLesMois,
      sectionFilter: sectionFilter,
      classFilter: classFilter,
      inclureExoneres: inclureExoneres,
      inclureMontantDifferent: inclureMontantDifferent,
    );

    final ResumeOrdre resume = resumeOrdre(
      mois: moisTries,
      sectionFilter: sectionFilter,
      classFilter: classFilter,
    );

    // Conversion éventuelle vers les montants du rapport (même règle que les
    // autres rapports PDF). Sans réglage actif, la valeur réelle est gardée.
    double conv(Eleve e, double v) =>
        FraisScolairesRapports(this)._versMontantRapportEleve(e, v);

    String two(int n) => n.toString().padLeft(2, '0');
    const jours = [
      'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
    ];
    final now = DateTime.now();
    final String dateStr = '${jours[now.weekday - 1]} ${two(now.day)}/'
        '${two(now.month)}/${now.year} à ${two(now.hour)}:${two(now.minute)}';

    final String sectionLabel = sectionFilter ?? "Toutes les sections";
    final String classeLabel = classFilter ?? "Toutes les classes";
    final String statutLabel =
    enOrdre ? "QUI ONT DÉJÀ PAYÉ" : "QUI N'ONT PAS ENCORE PAYÉ";
    final String condition = libelleConditionOrdreMulti(
        enOrdre: enOrdre, tousLesMois: tousLesMois);

    final bool moisComplets = moisTries.length <= 5;
    String enteteMois(String m) => moisComplets ? m : libelleMoisCourt(m);

    final headers = <String>[
      'N°',
      'Nom complet',
      'Section / Classe',
      ...moisTries.map(enteteMois),
      'Total payé (FC)',
      'Reste (FC)',
    ];

    final rows = <List<String>>[];
    final List<int> okParMois = List<int>.filled(moisTries.length, 0);
    final List<int> exoParMois = List<int>.filled(moisTries.length, 0);
    double sommePaye = 0;
    double sommeReste = 0;
    bool auMoinsUneException = false;

    for (int i = 0; i < lignes.length; i++) {
      final l = lignes[i];
      final e = l.eleve;
      final cellsMois = <String>[];
      double totPaye = 0;
      double totReste = 0;

      for (int k = 0; k < l.details.length; k++) {
        final d = l.details[k];
        final double p = conv(e, d.paye);
        final double r = conv(e, d.requis);
        final double reste = r - p > 0 ? r - p : 0.0;
        totPaye += p;
        totReste += reste;
        if (d.exonere) {
          // Ne doit rien pour ce mois : ni « OK », ni reste.
          exoParMois[k]++;
          cellsMois.add('EXO');
        } else if (d.enOrdre) {
          okParMois[k]++;
          cellsMois.add('OK');
        } else {
          cellsMois.add('-${formatMontant(reste)}');
        }
      }

      sommePaye += totPaye;
      sommeReste += totReste;

      final String marque = repereExceptionEleve(e, moisTries);
      if (marque.isNotEmpty) auMoinsUneException = true;

      rows.add([
        '${i + 1}',
        '${e.nom} ${e.postNom} ${e.prenom}$marque',
        '${e.section} — ${e.classe}',
        ...cellsMois,
        formatMontant(totPaye),
        formatMontant(totReste),
      ]);
    }

    if (rows.isNotEmpty) {
      rows.add([
        '',
        'TOTAL (${lignes.length} élève(s))',
        '',
        for (int k = 0; k < moisTries.length; k++)
          exoParMois[k] > 0
              ? '${okParMois[k]} OK + ${exoParMois[k]} EXO'
              : '${okParMois[k]} OK',
        formatMontant(sommePaye),
        formatMontant(sommeReste),
      ]);
    }

    final int nbCols = headers.length;
    double tailleCellule() {
      if (nbCols <= 6) return 9;
      if (nbCols <= 8) return 8.5;
      if (nbCols <= 10) return 8;
      if (nbCols <= 13) return 7.5;
      return 6.5;
    }

    final double fontCell = tailleCellule();
    final double fontHeader = nbCols <= 13 ? fontCell : 7;

    final List<double> flex = [
      0.5,
      2.4,
      2.0,
      ...List<double>.filled(moisTries.length, moisComplets ? 1.2 : 1.0),
      1.5,
      1.3,
    ];

    final String moisTexte = moisTries.join(', ');

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              style:
              pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "LISTE DES ÉLÈVES $statutLabel — ${moisTries.length} MOIS",
              textAlign: pw.TextAlign.center,
              style:
              pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Mois : $moisTexte",
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Condition : $condition",
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel | Classe : $classeLabel",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Année $currentYear | Imprimé le : $dateStr | "
                  "Total : ${lignes.length} élève(s)",
              style:
              const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 10),
          ...blocResumeOrdrePdf(
            resume,
            inclureExoneres: inclureExoneres,
            inclureMontantDifferent: inclureMontantDifferent,
          ),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text(
              "Aucun élève ne correspond à ces critères.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              columnWidths: {
                for (var i = 0; i < flex.length; i++)
                  i: pw.FlexColumnWidth(flex[i]),
              },
              headerStyle: pw.TextStyle(
                fontSize: fontHeader,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(
                color: enOrdre ? PdfColors.green700 : PdfColors.red700,
              ),
              headerAlignment: pw.Alignment.center,
              cellStyle: pw.TextStyle(fontSize: fontCell),
              cellAlignment: pw.Alignment.center,
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                nbCols - 2: pw.Alignment.centerRight,
                nbCols - 1: pw.Alignment.centerRight,
              },
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              oddRowDecoration: pw.BoxDecoration(
                color: enOrdre ? PdfColors.green50 : PdfColors.red50,
              ),
            ),
          pw.SizedBox(height: 8),
          pw.Text(
            "Légende : « OK » = mois soldé ; « -montant » = reste à payer "
                "pour ce mois ; « EXO » = l'élève ne doit rien pour ce mois "
                "(exception à 0 FC). « Reste » = total restant sur les mois "
                "choisis uniquement."
                "${auMoinsUneException ? ' $kLegendeReperesException' : ''}",
            style: pw.TextStyle(
              fontSize: 9,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );

    return await FraisScolairesRapports(this)._savePdf(
      pdf,
      filename,
      enOrdre ? 'en_ordre_multi' : 'pas_en_ordre_multi',
    );
  }
}
// ============================================================================
// ⚡ NOUVEAU — ÉLÈVES EN EXCEPTION (exonérés / montant différent)
// ============================================================================
// Un élève est « en exception » pour un mois quand l'école lui a fixé un
// montant PERSONNEL (écran des exceptions de paiement) pour ce mois :
//   - Exonéré           : son montant à payer pour ce mois est 0 FC ;
//   - Montant différent : il paie, mais un montant différent du montant
//                         normal de sa section / classe.
// Un montant personnel identique au montant normal n'est pas une exception.
//
// Avant : un élève exonéré (0 FC à payer) était considéré « en ordre »
// (0 payé >= 0 requis) et apparaissait donc dans « Ont déjà payé ».
// Maintenant : la liste peut l'exclure (choix par défaut à l'écran) et le
// rapport indique toujours combien d'élèves sont en exception, par section.
//
// Lecture seule : aucune donnée de l'école n'est modifiée.
// ============================================================================

enum TypeExceptionMois { aucune, exonere, montantDifferent }

enum FiltreExceptions { toutes, exoneres, montantDifferent }

const String kLegendeReperesException =
    "« (EXO) » après un nom = élève exonéré pour tous les mois choisis ; "
    "« * » = élève qui paie un montant différent du montant normal de sa "
    "classe.";

String libelleFiltreExceptions(FiltreExceptions f) {
  switch (f) {
    case FiltreExceptions.exoneres:
      return "Élèves exonérés (ne paient rien)";
    case FiltreExceptions.montantDifferent:
      return "Élèves qui paient un montant différent";
    case FiltreExceptions.toutes:
      return "Tous les élèves en exception";
  }
}

/// Situation d'un élève pour UN mois, vue sous l'angle des exceptions.
class ExceptionMoisDetail {
  final String mois;
  final double requisEleve; // ce que CET élève doit payer
  final double requisNormal; // montant normal de sa section / classe
  final double paye;
  final TypeExceptionMois type;

  const ExceptionMoisDetail({
    required this.mois,
    required this.requisEleve,
    required this.requisNormal,
    required this.paye,
    required this.type,
  });

  double get reste =>
      requisEleve - paye > 0 ? requisEleve - paye : 0.0;
}

/// Situation d'un élève sur l'ensemble des mois choisis.
class ExceptionEleve {
  final Eleve eleve;
  final List<ExceptionMoisDetail> details;

  const ExceptionEleve({required this.eleve, required this.details});

  bool get aMoisExonere =>
      details.any((d) => d.type == TypeExceptionMois.exonere);
  bool get aMontantDifferent =>
      details.any((d) => d.type == TypeExceptionMois.montantDifferent);
  bool get estException => aMoisExonere || aMontantDifferent;

  /// Exonéré pour CHACUN des mois choisis (ne doit rien du tout).
  bool get totalementExonere =>
      details.isNotEmpty &&
          details.every((d) => d.type == TypeExceptionMois.exonere);

  /// En ordre pour chacun des mois choisis (un mois exonéré compte comme
  /// réglé : l'élève ne doit rien).
  bool get enOrdre => details.every((d) => d.paye >= d.requisEleve);

  double get totalPaye => details.fold(0.0, (s, d) => s + d.paye);
  double get totalRequis => details.fold(0.0, (s, d) => s + d.requisEleve);
  double get totalReste => details.fold(0.0, (s, d) => s + d.reste);

  bool correspond(FiltreExceptions f) {
    switch (f) {
      case FiltreExceptions.exoneres:
        return aMoisExonere;
      case FiltreExceptions.montantDifferent:
        return aMontantDifferent;
      case FiltreExceptions.toutes:
        return estException;
    }
  }

  String get libelleType {
    if (totalementExonere) return 'Exonéré (0 FC)';
    if (aMoisExonere && aMontantDifferent) {
      return 'Exonéré certains mois + montant différent';
    }
    if (aMoisExonere) return 'Exonéré certains mois';
    if (aMontantDifferent) return 'Montant différent';
    return '-';
  }
}

/// Comptes d'une section (ou du total).
class ResumeSectionOrdre {
  final String section;
  int effectif = 0;
  int enOrdre = 0; // ont payé (hors exonérés)
  int pasEnOrdre = 0; // n'ont pas encore payé (hors exonérés)
  int exoneres = 0; // ne doivent rien (exception à 0 FC)
  int montantDifferent = 0; // déjà comptés dans enOrdre / pasEnOrdre

  ResumeSectionOrdre(this.section);
}

class ResumeOrdre {
  final List<String> mois;
  final List<ResumeSectionOrdre> parSection;
  final ResumeSectionOrdre total;

  const ResumeOrdre({
    required this.mois,
    required this.parSection,
    required this.total,
  });

  bool get plusieursMois => mois.length >= 2;

  String get libelleColonnePaye =>
      plusieursMois ? 'Ont tout payé' : 'Ont payé';
  String get libelleColonneNonPaye =>
      plusieursMois ? 'Pas encore tout payé' : 'Pas encore payé';
}

extension FraisScolairesExceptions on FraisScolaires {
  /// L'élève a un montant personnel pour ce mois.
  bool eleveAMontantPersonnelPourMois(Eleve e, String mois) =>
      e.exceptionsMoisPersonnalisees.containsKey(mois) ||
          e.montantMensuelPersonnalise != null;

  TypeExceptionMois typeExceptionPourMois(Eleve e, String mois) {
    if (!eleveAMontantPersonnelPourMois(e, mois)) {
      return TypeExceptionMois.aucune;
    }
    final double requis = getRequiredForMonthForEleve(e, mois);
    if (requis <= 0) return TypeExceptionMois.exonere;
    final double normal = getRequiredForMonth(mois, e.section, e.classe);
    if ((requis - normal).abs() > 0.5) {
      return TypeExceptionMois.montantDifferent;
    }
    return TypeExceptionMois.aucune;
  }

  ExceptionEleve analyserExceptionsEleve(Eleve e, List<String> mois) {
    return ExceptionEleve(
      eleve: e,
      details: <ExceptionMoisDetail>[
        for (final m in mois)
          ExceptionMoisDetail(
            mois: m,
            requisEleve: getRequiredForMonthForEleve(e, m),
            requisNormal: getRequiredForMonth(m, e.section, e.classe),
            paye: e.paid[m] ?? 0.0,
            type: typeExceptionPourMois(e, m),
          ),
      ],
    );
  }

  /// Faut-il garder cet élève dans la liste « en ordre / pas en ordre » ?
  /// - exonéré pour TOUS les mois choisis : gardé seulement si
  ///   [inclureExoneres] (un élève exonéré seulement certains mois reste
  ///   dans la liste : ces mois sont marqués EXO) ;
  /// - montant différent : gardé seulement si [inclureMontantDifferent].
  bool eleveRetenuSelonExceptions(
      Eleve e,
      List<String> mois, {
        required bool inclureExoneres,
        required bool inclureMontantDifferent,
      }) {
    if (inclureExoneres && inclureMontantDifferent) return true;
    final a = analyserExceptionsEleve(e, mois);
    if (!inclureExoneres && a.totalementExonere) return false;
    if (!inclureMontantDifferent && a.aMontantDifferent) return false;
    return true;
  }

  /// Repère ajouté après le nom dans les listes : « (EXO) », « * » ou rien.
  String repereExceptionEleve(Eleve e, List<String> mois) {
    final a = analyserExceptionsEleve(e, mois);
    if (a.totalementExonere) return ' (EXO)';
    if (a.aMontantDifferent) return ' *';
    return '';
  }

  List<Eleve> _elevesSelonFiltresExceptions(
      String? sectionFilter, String? classFilter) {
    Iterable<Eleve> l = currentData.eleves;
    if (sectionFilter != null) {
      l = l.where((e) => e.section == sectionFilter);
    }
    if (classFilter != null) {
      l = l.where((e) => e.classe == classFilter);
    }
    return l.toList();
  }

  int _rangSection(String s) {
    final int i = config.sections.indexOf(s);
    return i < 0 ? 1 << 20 : i;
  }

  /// Liste « un seul mois » avec le choix sur les élèves en exception.
  List<Eleve> getStudentsByOrderStatusAvecExceptions({
    required String mois,
    required bool enOrdre,
    String? sectionFilter,
    String? classFilter,
    bool inclureExoneres = true,
    bool inclureMontantDifferent = true,
  }) {
    return getStudentsByOrderStatus(
      mois: mois,
      enOrdre: enOrdre,
      sectionFilter: sectionFilter,
      classFilter: classFilter,
    )
        .where((e) => eleveRetenuSelonExceptions(e, [mois],
        inclureExoneres: inclureExoneres,
        inclureMontantDifferent: inclureMontantDifferent))
        .toList();
  }

  /// Comptes par section : effectif, ont payé, pas encore payé, exonérés,
  /// montant différent. Indépendant des options d'affichage de la liste.
  ResumeOrdre resumeOrdre({
    required List<String> mois,
    String? sectionFilter,
    String? classFilter,
  }) {
    final List<String> moisTries = trierMoisScolaires(mois);
    final ResumeSectionOrdre total = ResumeSectionOrdre('TOTAL');
    final Map<String, ResumeSectionOrdre> parSection = {};
    if (moisTries.isEmpty) {
      return ResumeOrdre(mois: moisTries, parSection: const [], total: total);
    }

    for (final e in _elevesSelonFiltresExceptions(sectionFilter, classFilter)) {
      final a = analyserExceptionsEleve(e, moisTries);
      final r =
      parSection.putIfAbsent(e.section, () => ResumeSectionOrdre(e.section));
      for (final x in [r, total]) {
        x.effectif++;
        if (a.totalementExonere) {
          x.exoneres++;
        } else if (a.enOrdre) {
          x.enOrdre++;
        } else {
          x.pasEnOrdre++;
        }
        if (a.aMontantDifferent) x.montantDifferent++;
      }
    }

    final sections = parSection.values.toList()
      ..sort((a, b) {
        final c = _rangSection(a.section).compareTo(_rangSection(b.section));
        return c != 0 ? c : a.section.compareTo(b.section);
      });
    return ResumeOrdre(mois: moisTries, parSection: sections, total: total);
  }

  /// Élèves en exception pour les mois choisis, selon le type demandé.
  List<ExceptionEleve> getElevesEnException({
    required List<String> mois,
    FiltreExceptions filtre = FiltreExceptions.toutes,
    String? sectionFilter,
    String? classFilter,
  }) {
    final List<String> moisTries = trierMoisScolaires(mois);
    if (moisTries.isEmpty) return [];
    final result = <ExceptionEleve>[];
    for (final e in _elevesSelonFiltresExceptions(sectionFilter, classFilter)) {
      final a = analyserExceptionsEleve(e, moisTries);
      if (a.correspond(filtre)) result.add(a);
    }
    result.sort((x, y) {
      final a = x.eleve;
      final b = y.eleve;
      int c = _rangSection(a.section).compareTo(_rangSection(b.section));
      if (c != 0) return c;
      c = a.section.compareTo(b.section);
      if (c != 0) return c;
      c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      return a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
    });
    return result;
  }

  String _texteMoisResume(List<String> mois) {
    if (mois.isEmpty) return '';
    if (mois.length == 1) return 'le mois de ${mois.first}';
    return 'les mois choisis';
  }

  /// Bloc « RÉSUMÉ » placé en haut des PDF de la liste en ordre.
  List<pw.Widget> blocResumeOrdrePdf(
      ResumeOrdre r, {
        required bool inclureExoneres,
        required bool inclureMontantDifferent,
      }) {
    if (r.mois.isEmpty) return const [];
    final List<ResumeSectionOrdre> lignes = [
      ...r.parSection,
      if (r.parSection.length != 1) r.total,
    ];
    List<String> ligne(ResumeSectionOrdre s) => [
      s.section,
      '${s.effectif}',
      '${s.enOrdre}',
      '${s.pasEnOrdre}',
      '${s.exoneres}',
      '${s.montantDifferent}',
    ];

    final String moisTxt = _texteMoisResume(r.mois);
    final noteStyle = pw.TextStyle(
      fontSize: 8.5,
      fontStyle: pw.FontStyle.italic,
      color: PdfColors.grey800,
    );

    return [
      pw.Text(
        "RÉSUMÉ (${r.mois.length == 1 ? r.mois.first : '${r.mois.length} mois'})",
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: [
          'Section',
          'Effectif',
          r.libelleColonnePaye,
          r.libelleColonneNonPaye,
          'Exonérés (0 FC)',
          'Montant différent',
        ],
        data: lignes.map(ligne).toList(),
        headerStyle: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        cellAlignment: pw.Alignment.center,
        cellAlignments: {0: pw.Alignment.centerLeft},
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.2),
          for (int i = 1; i < 6; i++) i: const pw.FlexColumnWidth(1.2),
        },
      ),
      pw.SizedBox(height: 4),
      if (r.plusieursMois)
        pw.Text(
          "« ${r.libelleColonnePaye} » = en ordre pour CHACUN des mois "
              "choisis ; « ${r.libelleColonneNonPaye} » = il reste quelque "
              "chose à payer sur au moins un mois.",
          style: noteStyle,
        ),
      if (r.total.exoneres > 0)
        pw.Text(
          "Exonérés : ${r.total.exoneres} élève(s) dont le montant à payer "
              "pour $moisTxt est 0 FC (exception de paiement). Ils ne sont "
              "comptés ni parmi ceux qui ont payé, ni parmi ceux qui n'ont pas "
              "payé"
              "${inclureExoneres ? " ; ils figurent quand même dans la liste, avec une mention." : " et ne figurent pas dans la liste ci-dessous."}",
          style: noteStyle,
        ),
      if (r.total.montantDifferent > 0)
        pw.Text(
          "Montant différent : ${r.total.montantDifferent} élève(s) qui "
              "paient un montant différent du montant normal de leur classe. "
              "Ils sont déjà comptés dans les colonnes « ${r.libelleColonnePaye} »"
              " ou « ${r.libelleColonneNonPaye} »"
              "${inclureMontantDifferent ? " et figurent dans la liste, avec une mention." : " ; selon l'option choisie, ils ne figurent pas dans la liste ci-dessous."}",
          style: noteStyle,
        ),
      if (r.total.exoneres == 0 && r.total.montantDifferent == 0)
        pw.Text("Aucun élève en exception pour $moisTxt.", style: noteStyle),
    ];
  }

  /// PDF : liste des élèves en exception (selon le type choisi).
  Future<Map<String, dynamic>> generateExceptionsPdf({
    required String filename,
    required List<String> mois,
    FiltreExceptions filtre = FiltreExceptions.toutes,
    String? sectionFilter,
    String? classFilter,
  }) async {
    await rapportPersonnalise.charger();

    final List<String> moisTries = trierMoisScolaires(mois);
    if (moisTries.isEmpty) {
      return {'success': false, 'error': 'Aucun mois sélectionné.'};
    }

    double conv(Eleve e, double v) =>
        FraisScolairesRapports(this)._versMontantRapportEleve(e, v);

    final List<ExceptionEleve> toutes = getElevesEnException(
      mois: moisTries,
      filtre: FiltreExceptions.toutes,
      sectionFilter: sectionFilter,
      classFilter: classFilter,
    );
    final List<ExceptionEleve> liste =
    toutes.where((a) => a.correspond(filtre)).toList();

    // ---- Comptes par section (tous types, pour information) ----
    final Map<String, List<int>> parSection = {}; // [exo, diff, total]
    for (final a in toutes) {
      final c = parSection.putIfAbsent(a.eleve.section, () => [0, 0, 0]);
      if (a.aMoisExonere) c[0]++;
      if (a.aMontantDifferent) c[1]++;
      c[2]++;
    }
    final sections = parSection.keys.toList()
      ..sort((a, b) {
        final c = _rangSection(a).compareTo(_rangSection(b));
        return c != 0 ? c : a.compareTo(b);
      });
    final resumeRows = <List<String>>[
      for (final s in sections)
        [s, '${parSection[s]![0]}', '${parSection[s]![1]}',
          '${parSection[s]![2]}'],
      if (sections.length > 1)
        [
          'TOTAL',
          '${toutes.where((a) => a.aMoisExonere).length}',
          '${toutes.where((a) => a.aMontantDifferent).length}',
          '${toutes.length}',
        ],
    ];

    // ---- Détail des montants ----
    String montantMois(Eleve e, ExceptionMoisDetail d) =>
        d.type == TypeExceptionMois.exonere
            ? '0 FC (exonéré)'
            : '${formatMontant(conv(e, d.requisEleve))} FC '
            '(normal ${formatMontant(conv(e, d.requisNormal))})';

    String detail(ExceptionEleve a) {
      final ex = a.details
          .where((d) => d.type != TypeExceptionMois.aucune)
          .toList();
      if (ex.isEmpty) return '-';
      final String premier = montantMois(a.eleve, ex.first);
      if (a.details.length > 1 &&
          ex.length == a.details.length &&
          ex.every((d) => montantMois(a.eleve, d) == premier)) {
        return 'Tous les mois choisis : $premier';
      }
      return ex
          .map((d) => '${libelleMoisCourt(d.mois)} : ${montantMois(a.eleve, d)}')
          .join('\n');
    }

    String situation(ExceptionEleve a) {
      if (a.totalementExonere) return 'Ne doit rien';
      if (a.enOrdre) return 'En ordre';
      return 'Reste ${formatMontant(conv(a.eleve, a.totalReste))} FC';
    }

    final rows = <List<String>>[];
    for (int i = 0; i < liste.length; i++) {
      final a = liste[i];
      final e = a.eleve;
      rows.add([
        '${i + 1}',
        '${e.nom} ${e.postNom} ${e.prenom}',
        '${e.section} - ${e.classe}',
        a.libelleType,
        detail(a),
        '${formatMontant(conv(e, a.totalPaye))} / '
            '${formatMontant(conv(e, a.totalRequis))}',
        situation(a),
      ]);
    }

    final String sectionLabel = sectionFilter ?? "Toutes les sections";
    final String classeLabel = classFilter ?? "Toutes les classes";
    final String dateStr = FraisScolairesRapports(this)._dateGenerationFormatee;
    final String titreType = libelleFiltreExceptions(filtre).toUpperCase();
    final noteStyle = pw.TextStyle(
      fontSize: 9,
      fontStyle: pw.FontStyle.italic,
      color: PdfColors.grey800,
    );

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              style:
              pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "LISTE DES ÉLÈVES EN EXCEPTION - $titreType",
              textAlign: pw.TextAlign.center,
              style:
              pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Mois : ${moisTries.join(', ')}",
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel | Classe : $classeLabel",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Année $currentYear | Imprimé le : $dateStr | "
                  "Total : ${liste.length} élève(s)",
              style:
              const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            "Élève en exception = élève à qui l'école a fixé un montant "
                "personnel. « Exonéré » : il ne doit rien payer (0 FC) pour le "
                "mois ; « Montant différent » : il paie, mais un autre montant "
                "que le montant normal de sa classe.",
            style: noteStyle,
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            "RÉSUMÉ PAR SECTION (tous types d'exception)",
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          if (resumeRows.isEmpty)
            pw.Text("Aucun élève en exception pour ces mois.",
                style: noteStyle)
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Section',
                'Exonérés (0 FC)',
                'Montant différent',
                'Total en exception',
              ],
              data: resumeRows,
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.blueGrey700),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.center,
              cellAlignments: {0: pw.Alignment.centerLeft},
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.5),
                1: pw.FlexColumnWidth(1.4),
                2: pw.FlexColumnWidth(1.4),
                3: pw.FlexColumnWidth(1.4),
              },
            ),
          if (toutes.any((a) => a.aMoisExonere && a.aMontantDifferent))
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(
                "Un élève exonéré certains mois et à montant différent "
                    "d'autres mois est compté dans les deux colonnes, mais une "
                    "seule fois dans le total.",
                style: noteStyle,
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text(
              "Aucun élève ne correspond à ce type d'exception.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'N°',
                'Nom complet',
                'Section / Classe',
                "Type d'exception",
                'Montant de l\'élève par mois',
                'Payé / À payer (FC)',
                'Situation',
              ],
              data: rows,
              columnWidths: const {
                0: pw.FlexColumnWidth(0.5),
                1: pw.FlexColumnWidth(2.4),
                2: pw.FlexColumnWidth(1.9),
                3: pw.FlexColumnWidth(1.6),
                4: pw.FlexColumnWidth(2.8),
                5: pw.FlexColumnWidth(1.5),
                6: pw.FlexColumnWidth(1.3),
              },
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo700),
              headerAlignment: pw.Alignment.center,
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerLeft,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.center,
              },
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              oddRowDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo50),
            ),
        ],
      ),
    );

    return await FraisScolairesRapports(this)
        ._savePdf(pdf, filename, 'eleves_en_exception');
  }
}

// ============================================================================
// ⚡ NOUVEAU — SYNTHÈSE EN TÊTE DES RAPPORTS (journalier / mensuel / annuel)
// ============================================================================
// But : qu'une personne qui lit le rapport comprenne en 30 secondes :
//   - combien d'argent était ATTENDU (selon le montant de CHAQUE élève :
//     tarif de sa classe ou de sa section, et SON exception s'il en a une) ;
//   - combien est DÉJÀ PAYÉ, combien il RESTE, le TAUX en % ;
//   - combien d'élèves ont tout payé / une partie / rien / n'ont rien à payer ;
//   - combien d'élèves sont en exception, et de quel type, par section.
//
// Le montant attendu n'est JAMAIS « nombre d'élèves × un seul tarif » :
// il est la somme, élève par élève et mois par mois, de ce que chacun doit
// réellement (getRequiredForMonthForEleve). Le « tarif normal sans
// exceptions » est aussi affiché pour montrer l'effet des exceptions.
//
// Contrôle affiché sur le rapport :
//   Attendu = Payé − Payé en plus + Reste à payer
// (vrai mois par mois et élève par élève, donc vrai aussi pour les totaux).
//
// Élèves comptés : élèves actuellement inscrits (comme la liste « Total
// collecté (ce rapport) »). Lecture seule.
// ============================================================================

class LigneSynthese {
  final String libelle;
  int eleves = 0;
  int toutPaye = 0;
  int partiel = 0;
  int rienPaye = 0;
  int rienADevoir = 0;
  int exoneres = 0;
  int montantDifferent = 0;
  double attendu = 0;
  double attenduNormal = 0; // si tout le monde payait le tarif normal
  double paye = 0;
  double reste = 0;
  double excedent = 0; // payé au-delà du montant dû (avance)
  double effetExoneres = 0; // tarif normal − montant dû, mois exonérés
  double effetDifferents = 0; // idem, mois à montant différent

  LigneSynthese(this.libelle);

  /// Part du montant attendu déjà réglée (0 à 100 %).
  double get taux =>
      attendu > 0 ? ((paye - excedent) / attendu * 100).clamp(0, 100) : 0;

  void ajouter(LigneSynthese o) {
    eleves += o.eleves;
    toutPaye += o.toutPaye;
    partiel += o.partiel;
    rienPaye += o.rienPaye;
    rienADevoir += o.rienADevoir;
    exoneres += o.exoneres;
    montantDifferent += o.montantDifferent;
    attendu += o.attendu;
    attenduNormal += o.attenduNormal;
    paye += o.paye;
    reste += o.reste;
    excedent += o.excedent;
    effetExoneres += o.effetExoneres;
    effetDifferents += o.effetDifferents;
  }
}

class SyntheseRapport {
  final List<String> mois;
  final List<LigneSynthese> lignes; // par section (ou par classe)
  final LigneSynthese total;
  final bool parClasse;
  final List<ExceptionEleve> exceptions;

  const SyntheseRapport({
    required this.mois,
    required this.lignes,
    required this.total,
    required this.parClasse,
    required this.exceptions,
  });

  /// Vérifie l'égalité Attendu = Payé − Payé en plus + Reste.
  bool get calculsCoherents =>
      (total.attendu - (total.paye - total.excedent + total.reste)).abs() < 1;
}

extension FraisScolairesSyntheseRapport on FraisScolaires {
  SyntheseRapport calculerSyntheseRapport({
    required List<String> mois,
    String? sectionFilter,
    String? classFilter,
    double Function(Eleve e, double reel)? conversion,
  }) {
    final List<String> moisTries = trierMoisScolaires(mois);
    double conv(Eleve e, double v) =>
        conversion == null ? v : conversion(e, v);

    final bool parClasse = sectionFilter != null || classFilter != null;
    final Map<String, LigneSynthese> groupes = {};
    final LigneSynthese total = LigneSynthese('TOTAL');
    final List<ExceptionEleve> exceptions = [];

    final eleves = currentData.eleves.where((e) =>
    (sectionFilter == null || e.section == sectionFilter) &&
        (classFilter == null || e.classe == classFilter));

    for (final e in eleves) {
      final String cle = parClasse ? e.classe : e.section;
      final g = groupes.putIfAbsent(cle, () => LigneSynthese(cle));
      final LigneSynthese l = LigneSynthese(cle)..eleves = 1;

      double requisTotal = 0;
      double payeTotal = 0;
      bool toutRegle = true;
      for (final m in moisTries) {
        final double req = getRequiredForMonthForEleve(e, m);
        final double normal = getRequiredForMonth(m, e.section, e.classe);
        final double p = e.paid[m] ?? 0.0;
        requisTotal += req;
        payeTotal += p;
        if (p + 0.5 < req) toutRegle = false;

        l.attendu += conv(e, req);
        l.attenduNormal += conv(e, normal);
        l.paye += conv(e, p);
        if (req > p) l.reste += conv(e, req - p);
        if (p > req) l.excedent += conv(e, p - req);
        switch (typeExceptionPourMois(e, m)) {
          case TypeExceptionMois.exonere:
            l.effetExoneres += conv(e, normal - req);
            break;
          case TypeExceptionMois.montantDifferent:
            l.effetDifferents += conv(e, normal - req);
            break;
          case TypeExceptionMois.aucune:
            break;
        }
      }

      if (requisTotal <= 0) {
        l.rienADevoir = 1;
      } else if (toutRegle) {
        l.toutPaye = 1;
      } else if (payeTotal > 0) {
        l.partiel = 1;
      } else {
        l.rienPaye = 1;
      }

      final a = analyserExceptionsEleve(e, moisTries);
      if (a.aMoisExonere) l.exoneres = 1;
      if (a.aMontantDifferent) l.montantDifferent = 1;
      if (a.estException) exceptions.add(a);

      g.ajouter(l);
      total.ajouter(l);
    }

    int rang(String cle) {
      if (parClasse) return 0;
      final int i = config.sections.indexOf(cle);
      return i < 0 ? 1 << 20 : i;
    }

    final lignes = groupes.values.toList()
      ..sort((a, b) {
        final c = rang(a.libelle).compareTo(rang(b.libelle));
        return c != 0 ? c : a.libelle.compareTo(b.libelle);
      });
    exceptions.sort((x, y) {
      int c = rang(x.eleve.section).compareTo(rang(y.eleve.section));
      if (c != 0) return c;
      c = x.eleve.classe.compareTo(y.eleve.classe);
      if (c != 0) return c;
      return x.eleve.nom.toLowerCase().compareTo(y.eleve.nom.toLowerCase());
    });

    return SyntheseRapport(
      mois: moisTries,
      lignes: lignes,
      total: total,
      parClasse: parClasse,
      exceptions: exceptions,
    );
  }

  /// Bloc « SYNTHÈSE » placé en tête du rapport PDF.
  /// [titrePeriode] : ex. « OCTOBRE 2026 » ou « DE SEPTEMBRE À NOVEMBRE ».
  List<pw.Widget> blocSyntheseRapportPdf(
      SyntheseRapport s, {
        required String titrePeriode,
        double payeArchives = 0,
        int maxExceptionsListees = 40,
        double Function(Eleve e, double reel)? conversion,
      }) {
    if (s.mois.isEmpty) return const [];
    double cv(Eleve e, double v) => conversion == null ? v : conversion(e, v);
    final t = s.total;
    String fc(double v) => '${formatMontant(v)} FC';
    String pct(double v) => '${v.toStringAsFixed(v >= 99.95 || v == 0 ? 0 : 1)} %';
    final bool unMois = s.mois.length == 1;
    final String surPeriode = unMois
        ? 'pour le mois de ${s.mois.first}'
        : 'pour les mois de ${s.mois.first} à ${s.mois.last} '
        '(${s.mois.length} mois)';

    final noteStyle = pw.TextStyle(
        fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey800);
    PdfColor couleurTaux(double v) => v >= 80
        ? PdfColors.green700
        : (v >= 50 ? PdfColors.orange700 : PdfColors.red700);

    pw.Widget chiffre(String titre, String valeur, PdfColor c,
        {String? sous}) =>
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: c, width: 1),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(titre,
                    style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800)),
                pw.SizedBox(height: 2),
                pw.Text(valeur,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold, color: c)),
                if (sous != null)
                  pw.Text(sous,
                      style: const pw.TextStyle(
                          fontSize: 7.5, color: PdfColors.grey700)),
              ],
            ),
          ),
        );

    // Barre de progression du taux de recouvrement.
    pw.Widget barre(double v) {
      const double largeur = 300;
      final double rempli = largeur * (v.clamp(0, 100) / 100);
      return pw.Row(children: [
        pw.Container(
          width: largeur,
          height: 9,
          decoration: pw.BoxDecoration(
            color: PdfColors.grey300,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          alignment: pw.Alignment.centerLeft,
          child: pw.Container(
            width: rempli,
            height: 9,
            decoration: pw.BoxDecoration(
              color: couleurTaux(v),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text('${pct(v)} du montant attendu est déjà payé',
            style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: couleurTaux(v))),
      ]);
    }

    final double effetExceptions = t.effetExoneres + t.effetDifferents;
    final List<LigneSynthese> lignesTableau = [
      ...s.lignes,
      if (s.lignes.length != 1) t,
    ];
    final String colLibelle = s.parClasse ? 'Classe' : 'Section';

    // Phrase-résumé (lisible sans le tableau).
    final String phrase = 'Sur ${t.eleves} élève(s), '
        '${fc(t.attendu)} étaient attendus $surPeriode. '
        '${fc(t.paye - t.excedent)} sont déjà payés (${pct(t.taux)}) et il '
        'reste ${fc(t.reste)} à recevoir. '
        '${t.toutPaye} élève(s) ont tout payé, ${t.partiel} ont payé une '
        'partie, ${t.rienPaye} n\'ont encore rien payé'
        '${t.rienADevoir > 0 ? ' et ${t.rienADevoir} n\'ont rien à payer' : ''}.';

    final List<ExceptionEleve> exListees =
    s.exceptions.take(maxExceptionsListees).toList();

    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.blueGrey50,
          border: pw.Border.all(color: PdfColors.blueGrey400, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('SYNTHÈSE - $titrePeriode',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900)),
            pw.SizedBox(height: 4),
            pw.Text(phrase, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 7),
            pw.Row(children: [
              chiffre('MONTANT ATTENDU', fc(t.attendu), PdfColors.blueGrey800,
                  sous: 'selon le montant de chaque élève'),
              chiffre('DÉJÀ PAYÉ', fc(t.paye - t.excedent), PdfColors.green800,
                  sous: t.excedent > 0.5
                      ? '+ ${fc(t.excedent)} payés en avance'
                      : null),
              chiffre('RESTE À PAYER', fc(t.reste), PdfColors.red700),
              chiffre('ÉLÈVES', '${t.eleves}', PdfColors.indigo800,
                  sous: '${t.toutPaye} tout payé | ${t.partiel} partiel | '
                      '${t.rienPaye} rien'),
            ]),
            pw.SizedBox(height: 7),
            barre(t.taux),
            pw.SizedBox(height: 8),

            // ---- D'où vient le montant attendu ----
            pw.Text('Comment le montant attendu est calculé',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(5),
                1: pw.FlexColumnWidth(1.6),
              },
              children: [
                pw.TableRow(children: [
                  pw.Text('Si chaque élève payait le tarif normal de sa classe '
                      '(sans exception) :',
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(fc(t.attenduNormal),
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 9)),
                ]),
                if (t.effetExoneres.abs() > 0.5)
                  pw.TableRow(children: [
                    pw.Text('Moins : ${t.exoneres} élève(s) exonéré(s) '
                        '(ne paient rien certains mois ou tous les mois)',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('- ${fc(t.effetExoneres)}',
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 9)),
                  ]),
                if (t.effetDifferents.abs() > 0.5)
                  pw.TableRow(children: [
                    pw.Text('${t.effetDifferents >= 0 ? 'Moins' : 'Plus'} : '
                        '${t.montantDifferent} élève(s) qui paient un montant '
                        'différent du tarif de leur classe',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(
                        '${t.effetDifferents >= 0 ? '-' : '+'} '
                            '${fc(t.effetDifferents.abs())}',
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: 9)),
                  ]),
                pw.TableRow(children: [
                  pw.Text('= MONTANT RÉELLEMENT ATTENDU',
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(fc(t.attendu),
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ]),
              ],
            ),
            if (effetExceptions.abs() <= 0.5)
              pw.Text('Aucun élève en exception : le montant attendu est le '
                  'tarif normal.', style: noteStyle),
            pw.SizedBox(height: 4),
            pw.Text(
              'Contrôle des calculs : attendu ${fc(t.attendu)} = payé '
                  '${fc(t.paye)}'
                  '${t.excedent > 0.5 ? ' - payé en avance ${fc(t.excedent)}' : ''}'
                  ' + reste ${fc(t.reste)}  '
                  '${s.calculsCoherents ? '[OK]' : '[A VÉRIFIER]'}',
              style: noteStyle,
            ),
            if (payeArchives > 0.5)
              pw.Text(
                'Les élèves supprimés (archivés) ne sont pas comptés dans '
                    'cette synthèse ; ils ont payé ${fc(payeArchives)} '
                    '$surPeriode (compris dans les totaux de l\'école plus bas).',
                style: noteStyle,
              ),
          ],
        ),
      ),
      pw.SizedBox(height: 10),

      // ---- Tableau par section / classe ----
      pw.Text('SITUATION PAR ${colLibelle.toUpperCase()}',
          style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: [
          colLibelle,
          'Élèves',
          'Attendu (FC)',
          'Déjà payé (FC)',
          'Reste (FC)',
          'Taux',
          'Tout payé',
          'Partiel',
          'Rien payé',
          'Rien à payer',
          'Exonérés',
          'Montant diff.',
        ],
        data: lignesTableau
            .map((l) => [
          l.libelle,
          '${l.eleves}',
          formatMontant(l.attendu),
          formatMontant(l.paye - l.excedent),
          formatMontant(l.reste),
          pct(l.taux),
          '${l.toutPaye}',
          '${l.partiel}',
          '${l.rienPaye}',
          '${l.rienADevoir}',
          '${l.exoneres}',
          '${l.montantDifferent}',
        ])
            .toList(),
        headerStyle: pw.TextStyle(
            fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        cellAlignment: pw.Alignment.centerRight,
        cellAlignments: {0: pw.Alignment.centerLeft},
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        cellDecoration: (int index, dynamic data, int rowNum) {
          if (index != 5) return const pw.BoxDecoration();
          final double v =
              double.tryParse(data.toString().replaceAll(' %', '')) ?? 0;
          final PdfColor c = couleurTaux(v);
          return pw.BoxDecoration(
            color: c == PdfColors.green700
                ? PdfColors.green100
                : (c == PdfColors.orange700
                ? PdfColors.orange100
                : PdfColors.red100),
          );
        },
        columnWidths: {
          0: const pw.FlexColumnWidth(2.2),
          for (int i = 1; i < 12; i++)
            i: pw.FlexColumnWidth(i >= 2 && i <= 4 ? 1.5 : 0.9),
        },
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        'Lecture : « Tout payé » + « Partiel » + « Rien payé » + « Rien à '
            'payer » = nombre d\'élèves. « Exonérés » et « Montant diff. » '
            'sont des élèves en exception, déjà comptés dans les colonnes '
            'précédentes. Taux : vert = 80 % ou plus, orange = 50 à 80 %, '
            'rouge = moins de 50 %.',
        style: noteStyle,
      ),
      pw.SizedBox(height: 10),

      // ---- Élèves en exception ----
      pw.Text('ÉLÈVES EN EXCEPTION (${s.exceptions.length})',
          style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 3),
      if (s.exceptions.isEmpty)
        pw.Text('Aucun élève en exception $surPeriode.', style: noteStyle)
      else ...[
        pw.Text(
          'Élèves à qui l\'école a fixé un montant personnel : '
              '${t.exoneres} exonéré(s) (0 FC) et ${t.montantDifferent} avec un '
              'montant différent du tarif de leur classe.',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 3),
        pw.TableHelper.fromTextArray(
          headers: const [
            'N°', 'Nom complet', 'Section - Classe', 'Type', 'Doit (FC)',
            'Tarif normal (FC)', 'Payé (FC)', 'Situation',
          ],
          data: [
            for (int i = 0; i < exListees.length; i++)
                () {
              final a = exListees[i];
              final e = a.eleve;
              final double normal =
              a.details.fold(0.0, (x, d) => x + d.requisNormal);
              return [
                '${i + 1}',
                '${e.nom} ${e.postNom} ${e.prenom}',
                '${e.section} - ${e.classe}',
                a.libelleType,
                formatMontant(cv(e, a.totalRequis)),
                formatMontant(cv(e, normal)),
                formatMontant(cv(e, a.totalPaye)),
                a.totalementExonere
                    ? 'Ne doit rien'
                    : (a.enOrdre
                    ? 'En ordre'
                    : 'Reste ${formatMontant(cv(e, a.totalReste))}'),
              ];
            }(),
          ],
          headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: {
            0: pw.Alignment.center,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),
            1: pw.FlexColumnWidth(2.6),
            2: pw.FlexColumnWidth(1.9),
            3: pw.FlexColumnWidth(1.9),
            4: pw.FlexColumnWidth(1.1),
            5: pw.FlexColumnWidth(1.2),
            6: pw.FlexColumnWidth(1.1),
            7: pw.FlexColumnWidth(1.3),
          },
        ),
        if (s.exceptions.length > exListees.length)
          pw.Text(
            '... et ${s.exceptions.length - exListees.length} autre(s). Liste '
                'complète : Liste En Ordre > « Liste des élèves en exception '
                '(PDF) ».',
            style: noteStyle,
          ),
        pw.Text(
          '« Doit » = ce que l\'élève doit payer $surPeriode ; « Tarif '
              'normal » = ce que paie un élève de la même classe sans '
              'exception.',
          style: noteStyle,
        ),
      ],
      pw.SizedBox(height: 14),
    ];
  }
}
