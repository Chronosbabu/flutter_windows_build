part of frais_scolaires;

// ============================================================================
// ⚡ NOUVEAU — RETENUES SUR PAIEMENTS (partie de frais_scolaires.dart)
// ----------------------------------------------------------------------------
// Une retenue sort de chaque paiement d'élève AVANT le calcul des pourcentages
// des administrations. Les 100 % encaissés ne changent pas : seul le montant
// sur lequel on applique les pourcentages devient  (encaissé − retenues).
//
// Rien n'est stocké dans les paiements : les retenues sont recalculées à la
// demande à partir des transactions de chaque élève. Ainsi, annuler ou
// modifier un paiement, recalculer la répartition par mois, ou supprimer un
// élève reste toujours cohérent.
//
// Règle de calcul pour un paiement de montant M, pour le mois X :
//   retenue = M × (total des retenues de la règle ÷ frais mensuel standard)
//   (plafonnée à M). Un paiement complet retient donc le total des retenues,
//   un paiement partiel en retient la part proportionnelle.
//
// Priorité des règles : classe  >  section  >  toute l'école.
// Tant qu'aucune règle active n'existe, TOUT reste identique à avant.
// ============================================================================

class RetenueStatRegle {
  final RetenueRegle regle;
  double total = 0.0;
  int nbPaiements = 0;

  /// id de la ligne de retenue -> montant cumulé
  final Map<String, double> parItem = {};

  RetenueStatRegle(this.regle);
}

class RetenueResume {
  final double total;
  final List<RetenueStatRegle> regles;

  const RetenueResume({required this.total, required this.regles});
}

extension FraisScolairesRetenues on FraisScolaires {
  // ==========================================================================
  // ÉTAT GÉNÉRAL
  // ==========================================================================

  bool get aDesRetenuesActives => config.retenues
      .any((r) => r.actif && r.items.isNotEmpty && r.total > 0);

  List<RetenueRegle> getRegles() => List<RetenueRegle>.from(config.retenues);

  RetenueRegle? trouverRegleRetenue(String id) {
    for (final r in config.retenues) {
      if (r.id == id) return r;
    }
    return null;
  }

  String libelleCibleRetenue(RetenueRegle r) {
    if (r.section.isEmpty) return "Toute l'école";
    if (r.classe.isEmpty) return 'Section ${r.section}';
    return '${r.section} - ${r.classe}';
  }

  String libelleMoisRetenue(RetenueRegle r) {
    if (r.mois.isEmpty || r.mois.length >= months.length) {
      return 'Tous les mois';
    }
    final tries = months.where((m) => r.mois.contains(m)).toList();
    return tries.isEmpty ? 'Tous les mois' : tries.join(', ');
  }

  // ==========================================================================
  // CHOIX DE LA RÈGLE APPLICABLE
  // ==========================================================================

  RetenueRegle? regleRetenuePour(
      String section, String classeComplete, String mois) {
    if (!aDesRetenuesActives) return null;
    final String numero = classeNumeroFromFullClasse(classeComplete);
    RetenueRegle? parClasse;
    RetenueRegle? parSection;
    RetenueRegle? parEcole;
    for (final r in config.retenues) {
      if (!r.actif || r.total <= 0) continue;
      if (r.mois.isNotEmpty && !r.mois.contains(mois)) continue;
      if (r.section.isEmpty) {
        parEcole ??= r;
      } else if (r.section == section) {
        if (r.classe.isEmpty) {
          parSection ??= r;
        } else if (r.classe == numero) {
          parClasse ??= r;
        }
      }
    }
    return parClasse ?? parSection ?? parEcole;
  }

  // ==========================================================================
  // CALCUL D'UNE RETENUE
  // ==========================================================================

  double _retenueSurMontant(Eleve eleve, String mois, double montant) {
    if (montant <= 0) return 0.0;
    final RetenueRegle? regle =
    regleRetenuePour(eleve.section, eleve.classe, mois);
    if (regle == null) return 0.0;
    final double ref = getRequiredForMonth(mois, eleve.section, eleve.classe);
    if (ref <= 0) return 0.0;
    double r = montant * regle.total / ref;
    if (r > montant) r = montant;
    if (r < 0) r = 0;
    return (r * 100).round() / 100;
  }

  List<Map<String, dynamic>> _entreesPaiementEleve(Eleve eleve) {
    if (eleve.transactions.isNotEmpty) return eleve.transactions;
    // Anciennes données sans transactions : on se base sur "paid".
    return eleve.paid.entries
        .where((e) => e.value > 0)
        .map((e) => <String, dynamic>{
      'mois': e.key,
      'amount': e.value,
      'date': '',
    })
        .toList();
  }

  bool _entreeDansPeriode(
      Map<String, dynamic> t, String period, String? mois) {
    switch (period) {
      case 'today':
        return t['date']?.toString() ==
            DateTime.now().toString().split(' ')[0];
      case 'month':
        final String? m = mois ?? currentSchoolMonthName;
        return m != null && t['mois']?.toString() == m;
      case 'year':
      default:
        return true;
    }
  }

  /// Total des retenues d'un élève sur la période ('today', 'month', 'year').
  /// Pour 'month', [mois] permet de choisir un autre mois que le mois en cours.
  double retenueEleve(Eleve eleve, String period, {String? mois}) {
    if (!aDesRetenuesActives) return 0.0;
    double total = 0.0;
    for (final t in _entreesPaiementEleve(eleve)) {
      if (!_entreeDansPeriode(t, period, mois)) continue;
      final String m = t['mois']?.toString() ?? '';
      final double montant = (t['amount'] as num?)?.toDouble() ?? 0.0;
      total += _retenueSurMontant(eleve, m, montant);
    }
    return total;
  }

  /// Retenues par section (élèves actifs + archivés, comme les totaux de
  /// collecte de l'application).
  Map<String, double> retenuesParSection(String period, {String? mois}) {
    final Map<String, double> res = {};
    if (!aDesRetenuesActives) return res;
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
      final double r = retenueEleve(e, period, mois: mois);
      if (r != 0) res[e.section] = (res[e.section] ?? 0) + r;
    }
    return res;
  }

  double getTotalRetenues(String period, {String? mois}) =>
      retenuesParSection(period, mois: mois)
          .values
          .fold(0.0, (sum, v) => sum + v);

  /// Retenues d'une section, calculées sur les MÊMES élèves que le montant
  /// affiché dans la répartition (année : élèves actifs ; jour/mois : actifs
  /// + archivés).
  double retenuePourSectionPeriode(String section, String period) {
    if (!aDesRetenuesActives) return 0.0;
    final List<Eleve> source = period == 'year'
        ? currentData.eleves
        : [...currentData.eleves, ...elevesSupprimesData.eleves];
    double total = 0.0;
    for (final e in source) {
      if (e.section == section) total += retenueEleve(e, period);
    }
    return total;
  }

  // --- versions "montants du rapport" (fonction montants personnalisés) ----

  double _retenueRapportEleve(Eleve eleve, String period, String? mois) =>
      _versMontantRapportEleve(eleve, retenueEleve(eleve, period, mois: mois));

  Map<String, double> _retenuesRapportParSection(String period,
      {String? mois}) {
    final Map<String, double> res = {};
    if (!aDesRetenuesActives) return res;
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
      final double r = _retenueRapportEleve(e, period, mois);
      if (r != 0) res[e.section] = (res[e.section] ?? 0) + r;
    }
    return res;
  }

  // ==========================================================================
  // STATISTIQUES (écran + rapports)
  // ==========================================================================

  /// Détail des retenues par règle et par ligne de retenue.
  /// [eleves] : restreint le calcul à ces élèves (sinon tous, archivés inclus).
  /// [convertir] : conversion éventuelle vers les montants du rapport.
  RetenueResume calculerResumeRetenues(
      String period, {
        String? mois,
        List<Eleve>? eleves,
        double Function(Eleve, double)? convertir,
      }) {
    final Map<String, RetenueStatRegle> parRegle = {};
    double total = 0.0;
    if (aDesRetenuesActives) {
      final List<Eleve> source = eleves ??
          [...currentData.eleves, ...elevesSupprimesData.eleves];
      for (final e in source) {
        for (final t in _entreesPaiementEleve(e)) {
          if (!_entreeDansPeriode(t, period, mois)) continue;
          final String m = t['mois']?.toString() ?? '';
          final double montant = (t['amount'] as num?)?.toDouble() ?? 0.0;
          final RetenueRegle? regle =
          regleRetenuePour(e.section, e.classe, m);
          if (regle == null) continue;
          double r = _retenueSurMontant(e, m, montant);
          if (r <= 0) continue;
          if (convertir != null) r = convertir(e, r);
          final st =
          parRegle.putIfAbsent(regle.id, () => RetenueStatRegle(regle));
          st.total += r;
          st.nbPaiements++;
          total += r;
          final double rt = regle.total;
          if (rt > 0) {
            for (final it in regle.items) {
              st.parItem[it.id] =
                  (st.parItem[it.id] ?? 0) + r * it.montant / rt;
            }
          }
        }
      }
    }
    final liste = parRegle.values.toList();
    liste.sort((a, b) => libelleCibleRetenue(a.regle)
        .toLowerCase()
        .compareTo(libelleCibleRetenue(b.regle).toLowerCase()));
    return RetenueResume(total: total, regles: liste);
  }

  // ==========================================================================
  // VALIDATION ET ENREGISTREMENT DES RÈGLES
  // ==========================================================================

  /// Frais mensuel le plus bas parmi les classes concernées par la cible.
  double? plusPetitFraisPourCible(String section, String classe) {
    final vals = <double>[];
    void voirSection(String s) {
      vals.add(montantReferencePourRapport(s));
      for (final c in (config.classesBySection[s] ?? const <String>[])) {
        vals.add(montantReferencePourRapport(s, c));
      }
    }

    if (section.isEmpty) {
      for (final s in config.sections) {
        voirSection(s);
      }
    } else if (classe.isEmpty) {
      voirSection(section);
    } else {
      vals.add(montantReferencePourRapport(section, classe));
    }
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a < b ? a : b);
  }

  String? validerRegleRetenue(RetenueRegle r) {
    if (r.section.isEmpty && r.classe.isNotEmpty) {
      return "Choisissez d'abord une section.";
    }
    if (r.items.isEmpty) {
      return 'Ajoutez au moins une retenue (nom + montant).';
    }
    final noms = <String>{};
    for (final it in r.items) {
      if (it.nom.trim().isEmpty) return 'Chaque retenue doit avoir un nom.';
      if (it.montant <= 0) {
        return 'Le montant de « ${it.nom} » doit être supérieur à zéro.';
      }
      if (!noms.add(normaliserNomFrais(it.nom))) {
        return 'Le nom « ${it.nom} » est utilisé deux fois dans cette règle.';
      }
    }
    for (final autre in config.retenues) {
      if (autre.id == r.id) continue;
      if (autre.section == r.section && autre.classe == r.classe) {
        return 'Une règle existe déjà pour cette cible '
            '(${libelleCibleRetenue(r)}). Modifiez-la au lieu d\'en créer '
            'une seconde.';
      }
    }
    final double? min = plusPetitFraisPourCible(r.section, r.classe);
    if (min != null && r.total > min + 0.5) {
      return 'Le total des retenues (${formatMontant(r.total)} FC) dépasse le '
          'frais mensuel le plus bas concerné (${formatMontant(min)} FC).';
    }
    return null;
  }

  /// Ajoute ou remplace une règle. Retourne null si tout va bien, sinon un
  /// message d'erreur à afficher.
  Future<String?> enregistrerRegleRetenue(RetenueRegle regle) async {
    final String? erreur = validerRegleRetenue(regle);
    if (erreur != null) return erreur;
    final int idx = config.retenues.indexWhere((r) => r.id == regle.id);
    if (idx >= 0) {
      config.retenues[idx] = regle;
    } else {
      config.retenues.add(regle);
    }
    await saveData();
    return null;
  }

  Future<void> supprimerRegleRetenue(String id) async {
    config.retenues.removeWhere((r) => r.id == id);
    await saveData();
  }

  Future<void> basculerRegleRetenue(String id, bool actif) async {
    for (final r in config.retenues) {
      if (r.id == id) {
        r.actif = actif;
        break;
      }
    }
    await saveData();
  }

  // ==========================================================================
  // SECTION PDF « RETENUES »
  // ==========================================================================

  List<pw.Widget> _buildRetenuesSection(
      List<Eleve> students, String period, String? mois) {
    final RetenueResume resume = calculerResumeRetenues(
      period,
      mois: mois,
      eleves: students,
      convertir: (e, v) => _versMontantRapportEleve(e, v),
    );
    if (resume.regles.isEmpty || resume.total <= 0) return [];

    final rows = <List<String>>[];
    final Map<String, double> parLibelle = {};
    final Map<String, String> nomAffiche = {};

    for (final st in resume.regles) {
      for (final it in st.regle.items) {
        final double v = st.parItem[it.id] ?? 0.0;
        rows.add([
          libelleCibleRetenue(st.regle),
          libelleMoisRetenue(st.regle),
          it.nom,
          formatMontant(v),
        ]);
        final String cle = normaliserNomFrais(it.nom);
        parLibelle[cle] = (parLibelle[cle] ?? 0) + v;
        nomAffiche.putIfAbsent(cle, () => it.nom.trim());
      }
    }
    rows.add(['TOTAL', '', '', formatMontant(resume.total)]);

    final rowsLibelle = <List<String>>[
      for (final e in parLibelle.entries)
        [nomAffiche[e.key] ?? e.key, formatMontant(e.value)],
      ['TOTAL', formatMontant(resume.total)],
    ];

    return [
      pw.SizedBox(height: 24),
      pw.Text(
        "RETENUES PRÉLEVÉES AVANT LA RÉPARTITION",
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        "Ces montants sont retirés des paiements avant le calcul des "
            "pourcentages des administrations. Seul le reste "
            "(${formatMontant(students.fold<double>(0.0, (s, e) => s + _montantEleve(e, period, mois)) - resume.total)} FC) "
            "est réparti.",
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: const ['Cible', 'Mois concernés', 'Retenue', 'Montant (FC)'],
        data: rows,
        columnWidths: _buildColumnWidths([2.0, 2.2, 2.4, 1.4]),
        headerStyle: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.orange800),
        headerAlignment: pw.Alignment.center,
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {3: pw.Alignment.centerRight},
        cellPadding:
        const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.orange50),
      ),
      pw.SizedBox(height: 12),
      pw.Text(
        "Total par type de retenue (toutes cibles confondues)",
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: const ['Retenue', 'Montant (FC)'],
        data: rowsLibelle,
        columnWidths: _buildColumnWidths([3.0, 1.4]),
        headerStyle: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.orange800),
        headerAlignment: pw.Alignment.center,
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {1: pw.Alignment.centerRight},
        cellPadding:
        const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.orange50),
      ),
      pw.SizedBox(height: 16),
    ];
  }
}