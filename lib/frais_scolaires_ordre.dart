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

  const OrdreMoisDetail({
    required this.mois,
    required this.paye,
    required this.requis,
    required this.enOrdre,
  });

  double get reste => requis - paye > 0 ? requis - paye : 0.0;
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
      final details = <OrdreMoisDetail>[
        for (final m in moisTries)
          OrdreMoisDetail(
            mois: m,
            paye: e.paid[m] ?? 0.0,
            requis: getRequiredForMonthForEleve(e, m),
            enOrdre: isStudentEnOrdrePourMois(e, m),
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
    double sommePaye = 0;
    double sommeReste = 0;

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
        if (d.enOrdre) {
          okParMois[k]++;
          cellsMois.add('OK');
        } else {
          cellsMois.add('-${formatMontant(reste)}');
        }
      }

      sommePaye += totPaye;
      sommeReste += totReste;

      rows.add([
        '${i + 1}',
        '${e.nom} ${e.postNom} ${e.prenom}',
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
        ...okParMois.map((n) => '$n OK'),
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
          pw.SizedBox(height: 14),
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
                "pour ce mois. « Reste » = total restant sur les mois choisis "
                "uniquement.",
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