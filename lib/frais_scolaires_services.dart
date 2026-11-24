part of frais_scolaires;

const String kTypeFraisAvecAdministrations = "Frais de l'État";

int? _syncServerRevision;
Map<String, Set<String>> _syncBase = <String, Set<String>>{};
String? _syncBaseConfigJson;
bool _syncBusy = false;
bool _localLoadFailed = false;
Future<void> _saveChain = Future<void>.value();

List<String> dernierAvertissementsFusion = <String>[];

// ⚡ ÉTAPE 5 — protections de la synchronisation
const int kNbCopiesSecurite = 30;
const int kMaxLignesJournalSync = 1000;
const String kFichierJournalSync = 'sync_journal.jsonl';
String? _derniereCopieAvantRecuperation;
// Résumé chiffré (élèves, argent...) au moment de la dernière
// synchronisation réussie : sert à vérifier qu'une fusion n'invente ni ne
// perd rien.
Map<String, num>? _syncBaseResume;

extension FraisScolairesServices on FraisScolaires {
  bool get synchronisationEnCours => _syncBusy;

  Future<Map<String, dynamic>> createPromoterRequest({
    required String type,
    required Eleve eleve,
    Map<String, dynamic>? transaction,
    String? mois,
    double? nouveauMontant,
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {
        'success': false,
        'error': "Code école manquant. Sauvegardez d'abord sur le serveur."
      };
    }
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/school/create_promoter_request'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCode,
          'type': type,
          'eleve_id': eleve.id,
          'eleve_nom': '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
          'classe': eleve.classe,
          'section': eleve.section,
          'mois': mois ?? transaction?['mois'] ?? '',
          'transaction_id': transaction?['id'] ?? '',
          'montant_actuel': (transaction?['amount'] as num?)?.toDouble(),
          'nouveau_montant': nouveauMontant,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'request_id': data['request_id']};
      }
      return {
        'success': false,
        'error': 'Statut ${response.statusCode} : ${response.body}',
      };
    } on SocketException catch (e) {
      return {'success': false, 'error': 'Aucune connexion réseau : $e'};
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  Future<Map<String, dynamic>> checkPromoterRequestStatus(
      String requestId) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {'status': 'pending'};
    }
    try {
      final response = await http
          .get(Uri.parse(
          '$serverUrl/school/get_request_status?school_code=$schoolCode&request_id=$requestId'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(response.body));
      }
      return {'status': 'pending'};
    } catch (_) {
      return {'status': 'pending'};
    }
  }

  Future<void> applyApprovedRequest(
      String type,
      Eleve eleve,
      Map<String, dynamic> transaction,
      Map<String, dynamic> requestData,
      ) async {
    if (type == 'cancel') {
      await cancelTransaction(eleve: eleve, transaction: transaction);
    } else if (type == 'modify') {
      final nouveau = (requestData['nouveau_montant'] as num?)?.toDouble();
      if (nouveau != null) {
        await modifyTransactionAmount(
            eleve: eleve, transaction: transaction, newAmount: nouveau);
      }
    } else if (type == 'reprint') {
      await forceReprintTransactionReceipt(
          eleve: eleve, transaction: transaction);
    }
  }

  Future<bool> forceReprintTransactionReceipt({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
  }) async {
    final printerName = await _currentPrinterName();
    if (printerName.isEmpty) return false;
    final logoBytes = await _loadLogoBytesForPrinting();
    final bool ok = await EscPosPrinterService.printTransactionsReceipt(
      printerName: printerName,
      schoolName: config.schoolName,
      currentYear: currentYear,
      studentName: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      studentId: eleve.id,
      classe: eleve.classe,
      section: eleve.section,
      transactions: [transaction],
      logoBytes: logoBytes,
      duplicata: true,
    );
    if (ok) {
      transaction['receiptConfirmed'] = true;
      final key = _principalReceiptKey(eleve, transaction);
      if (!isReceiptPrinted(key)) {
        await _markReceiptPrinted(key);
      } else {
        await saveData();
      }
    }
    return ok;
  }

  Map<String, dynamic> computePromoterSummary() {
    final today = DateTime.now().toString().split(' ')[0];

    final Map<String, double> moneyTodayBySection =
    getMoneyCollectedTodayBySection();
    final double moneyTodayPrincipal =
    moneyTodayBySection.values.fold(0.0, (sum, v) => sum + v);

    final Set<String> idsFraisExistants = autresFrais.map((f) => f.id).toSet();
    final List<AutreFraisPaiement> paiementsValides =
    (autresFraisPaiementsByYear[currentYear] ?? <AutreFraisPaiement>[])
        .where((p) => idsFraisExistants.contains(p.autreFraisId))
        .toList();

    double moneyTodayAutresFrais = 0;
    for (final p in paiementsValides) {
      if (p.date.toString().split(' ')[0] == today) {
        moneyTodayAutresFrais += p.montant;
      }
    }

    final Map<String, double> moneyThisMonthBySection =
    getMoneyCollectedThisMonthBySection();
    final double moneyThisMonthPrincipal =
    moneyThisMonthBySection.values.fold(0.0, (sum, v) => sum + v);

    double moneyThisMonthAutresFrais = 0;
    final DateTime now = DateTime.now();
    for (final p in paiementsValides) {
      if (p.date.year == now.year && p.date.month == now.month) {
        moneyThisMonthAutresFrais += p.montant;
      }
    }

    final double totalPrincipalYear = getYearTotalCollected();
    final double totalAutresFraisYear =
    paiementsValides.fold(0.0, (sum, p) => sum + p.montant);
    final Map<String, double> moneyThisYearBySection = getTotalBySection();

    // ⚡ Retenues : elles sortent AVANT les pourcentages des administrations.
    final Map<String, double> retenuesTodayBySection =
    retenuesParSection('today');
    final Map<String, double> retenuesMonthBySection =
    retenuesParSection('month');
    final Map<String, double> retenuesYearBySection =
    retenuesParSection('year');
    final double retenuesToday =
    retenuesTodayBySection.values.fold(0.0, (s, v) => s + v);
    final double retenuesThisMonth =
    retenuesMonthBySection.values.fold(0.0, (s, v) => s + v);
    final double retenuesThisYear =
    retenuesYearBySection.values.fold(0.0, (s, v) => s + v);

    final adminDistToday =
    calculateAdminDistribution(moneyTodayPrincipal - retenuesToday);
    final adminDistThisMonth =
    calculateAdminDistribution(moneyThisMonthPrincipal - retenuesThisMonth);
    final adminDistThisYear =
    calculateAdminDistribution(totalPrincipalYear - retenuesThisYear);

    final autresFraisAdminDistToday =
    calculateAutresFraisAdminDistribution(moneyTodayAutresFrais);
    final autresFraisAdminDistThisMonth =
    calculateAutresFraisAdminDistribution(moneyThisMonthAutresFrais);
    final autresFraisAdminDistThisYear =
    calculateAutresFraisAdminDistribution(totalAutresFraisYear);

    Map<String, Map<String, double>> distBySection(
        Map<String, double> amountsBySection,
        Map<String, double> retenuesBySection) {
      final result = <String, Map<String, double>>{};
      amountsBySection.forEach((section, amount) {
        result[section] = calculateAdminDistribution(
            amount - (retenuesBySection[section] ?? 0.0));
      });
      return result;
    }

    final adminDistributionTodayBySection =
    distBySection(moneyTodayBySection, retenuesTodayBySection);
    final adminDistributionThisMonthBySection =
    distBySection(moneyThisMonthBySection, retenuesMonthBySection);
    final adminDistributionThisYearBySection =
    distBySection(moneyThisYearBySection, retenuesYearBySection);

    final Map<String, int> studentsBySection = {};
    final Map<String, int> studentsByClass = {};
    for (final e in currentData.eleves) {
      studentsBySection[e.section] = (studentsBySection[e.section] ?? 0) + 1;
      final key = "${e.section} - ${e.classe}";
      studentsByClass[key] = (studentsByClass[key] ?? 0) + 1;
    }

    final List<AutreFraisPaiement> tousPaiementsAutresFrais =
    List<AutreFraisPaiement>.from(paiementsValides);

    String cleNom(String s) =>
        normaliserNomFrais(s.replaceAll('’', "'").replaceAll('`', "'"));

    final List<AutreFraisGroupe> groupesFrais = getAutresFraisGroupes();
    String? cleProprietaireAdmins;
    if (autresFraisAdministrations.isNotEmpty) {
      final String cible = cleNom(kTypeFraisAvecAdministrations);
      for (final g in groupesFrais) {
        if (cleNom(g.nom) == cible) {
          cleProprietaireAdmins = g.cle;
          break;
        }
      }
      if (cleProprietaireAdmins == null && groupesFrais.length == 1) {
        cleProprietaireAdmins = groupesFrais.first.cle;
      }
    }

    Map<String, dynamic> construireTypeStat({
      required String cle,
      required String nom,
      required Set<String> ids,
      required int nbFusionnes,
      required bool avecAdmins,
    }) {
      double jour = 0, mois = 0, annee = 0;
      for (final p in tousPaiementsAutresFrais) {
        if (!ids.contains(p.autreFraisId)) continue;
        annee += p.montant;
        if (p.date.toString().split(' ')[0] == today) jour += p.montant;
        if (p.date.year == now.year && p.date.month == now.month) {
          mois += p.montant;
        }
      }
      return {
        'cle': cle,
        'nom': nom,
        'nombreFraisFusionnes': nbFusionnes,
        'today': jour,
        'thisMonth': mois,
        'thisYear': annee,
        'adminToday': avecAdmins
            ? calculateAutresFraisAdminDistribution(jour)
            : <String, double>{},
        'adminThisMonth': avecAdmins
            ? calculateAutresFraisAdminDistribution(mois)
            : <String, double>{},
        'adminThisYear': avecAdmins
            ? calculateAutresFraisAdminDistribution(annee)
            : <String, double>{},
      };
    }

    final List<Map<String, dynamic>> autresFraisParType = [];
    Map<String, dynamic>? statProprietaire;
    for (final groupe in groupesFrais) {
      final ids = groupe.ids.toSet();
      final bool proprietaire = groupe.cle == cleProprietaireAdmins;
      final stat = construireTypeStat(
        cle: groupe.cle,
        nom: groupe.nom,
        ids: ids,
        nbFusionnes: groupe.nombreDeFraisFusionnes,
        avecAdmins: proprietaire,
      );
      if (proprietaire) statProprietaire = stat;
      autresFraisParType.add(stat);
    }

    final Map<String, double> afAdminJour = statProprietaire != null
        ? Map<String, double>.from(statProprietaire['adminToday'] as Map)
        : autresFraisAdminDistToday;
    final Map<String, double> afAdminMois = statProprietaire != null
        ? Map<String, double>.from(statProprietaire['adminThisMonth'] as Map)
        : autresFraisAdminDistThisMonth;
    final Map<String, double> afAdminAnnee = statProprietaire != null
        ? Map<String, double>.from(statProprietaire['adminThisYear'] as Map)
        : autresFraisAdminDistThisYear;

    return {
      'schoolName': config.schoolName,
      'currentYear': currentYear,
      'currentMonthName': currentSchoolMonthName ?? '',
      'retenuesToday': retenuesToday,
      'retenuesThisMonth': retenuesThisMonth,
      'retenuesThisYear': retenuesThisYear,
      'generatedAt': DateTime.now().toIso8601String(),

      'moneyToday': moneyTodayPrincipal + moneyTodayAutresFrais,
      'moneyTodayPrincipal': moneyTodayPrincipal,
      'moneyTodayAutresFrais': moneyTodayAutresFrais,
      'adminDistributionToday': adminDistToday,
      'autresFraisAdminDistributionToday': afAdminJour,
      'moneyTodayBySection': moneyTodayBySection,
      'adminDistributionTodayBySection': adminDistributionTodayBySection,

      'moneyThisMonth': moneyThisMonthPrincipal + moneyThisMonthAutresFrais,
      'moneyThisMonthPrincipal': moneyThisMonthPrincipal,
      'moneyThisMonthAutresFrais': moneyThisMonthAutresFrais,
      'adminDistributionThisMonth': adminDistThisMonth,
      'autresFraisAdminDistributionThisMonth': afAdminMois,
      'moneyThisMonthBySection': moneyThisMonthBySection,
      'adminDistributionThisMonthBySection':
      adminDistributionThisMonthBySection,

      'adminDistributionThisYear': adminDistThisYear,
      'autresFraisAdminDistributionThisYear': afAdminAnnee,
      'moneyThisYearBySection': moneyThisYearBySection,
      'adminDistributionThisYearBySection':
      adminDistributionThisYearBySection,

      'autresFraisParType': autresFraisParType,

      'totalStudents': currentData.eleves.length,
      'studentsBySection': studentsBySection,
      'studentsByClass': studentsByClass,
      'totalAmountGlobal': totalPrincipalYear + totalAutresFraisYear,
      'totalAmountBySection': getTotalBySection(),
      'totalAmountByClass': getTotalByClass(),
      'totalDepenses': getTotalDepenses(),
      'totalDepensesToday': getTotalDepensesToday(),
      'totalDepensesThisMonth': getTotalDepensesThisMonth(),
      'depensesParPortee': {
        kDepenseGlobale: getTotalDepensesParPortee(kDepenseGlobale),
        kDepenseIndependante: getTotalDepensesParPortee(kDepenseIndependante),
        kDepenseMixte: getTotalDepensesParPortee(kDepenseMixte),
      },
      // ⚡ NOUVEAU — entrées d'argent (apports de caisse), déjà incluses dans
      // 'soldeNet' ci-dessous.
      'totalEntrees': getTotalEntrees(),
      'soldeNet': getSoldeNetActuel(),
    };
  }

  Future<bool> pushPromoterSummary() async {
    if (schoolCode == null || schoolCode!.isEmpty) return false;
    for (int essai = 1; essai <= 2; essai++) {
      try {
        final summary = computePromoterSummary();
        final response = await http
            .post(
          Uri.parse('$serverUrl/school/push_promoter_summary'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'school_code': schoolCode, 'summary': summary}),
        )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode == 200) return true;
      } catch (_) {}
    }
    return false;
  }

  bool isReceiptPrinted(String key) => printedReceiptKeys.contains(key);

  Future<Uint8List?> _loadLogoBytesForPrinting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasLogo = prefs.getBool('has_logo') ?? false;
      if (!hasLogo) return null;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/school_logo.png');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _currentPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_name') ?? '';
  }

  String _principalReceiptKey(Eleve eleve, Map<String, dynamic> transaction) {
    final String transactionId = transaction['id']?.toString() ?? '';
    if (transactionId.isNotEmpty) {
      return 'principal|${eleve.id}|$transactionId';
    }
    final String mois = transaction['mois']?.toString() ?? '';
    return 'principal|${eleve.id}|$mois|${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> _markReceiptPrinted(String key) async {
    if (!printedReceiptKeys.contains(key)) {
      printedReceiptKeys.add(key);
    }
    receiptQueue.removeWhere((r) => r['key'] == key);
    await saveData();
  }

  Future<void> _enqueueReceipt({
    required String key,
    required String type,
    required String eleveId,
    required Map<String, dynamic> data,
  }) async {
    final existingIndex = receiptQueue.indexWhere((r) => r['key'] == key);
    final entry = <String, dynamic>{
      'key': key,
      'type': type,
      'eleveId': eleveId,
      'data': data,
      'dateAjout': DateTime.now().toIso8601String(),
    };
    if (existingIndex != -1) {
      receiptQueue[existingIndex] = entry;
    } else {
      receiptQueue.add(entry);
    }
    await saveData();
  }

  Future<bool> printOrQueuePrincipalReceipt({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
  }) async {
    final String transactionId = transaction['id']?.toString() ?? '';
    final String mois = transaction['mois']?.toString() ?? '';
    final double montantPaye =
        (transaction['amount'] as num?)?.toDouble() ?? 0.0;

    final key = _principalReceiptKey(eleve, transaction);
    if (isReceiptPrinted(key)) return false;

    final double montantRequis = getRequiredForMonthForEleve(eleve, mois);
    final double totalPaye = getStudentTotalPaid(eleve);
    final double totalRequis = getStudentPending(eleve) + totalPaye;
    final double resteAPayerMoisBrut = montantRequis - (eleve.paid[mois] ?? 0);
    final double resteAPayerMois =
    resteAPayerMoisBrut < 0 ? 0.0 : resteAPayerMoisBrut;

    final data = <String, dynamic>{
      'studentName': '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      'studentId': eleve.id,
      'classe': eleve.classe,
      'section': eleve.section,
      'moisPaye': mois,
      'montantPaye': montantPaye,
      'montantRequis': montantRequis,
      'resteAPayerMois': resteAPayerMois,
      'totalDejaPayeAnnee': totalPaye,
      'totalRequis': totalRequis,
      'transactionId': transactionId,
      'historiqueTransactions':
      eleve.transactions.map((t) => Map<String, dynamic>.from(t)).toList(),
    };

    final printerName = await _currentPrinterName();
    if (printerName.isNotEmpty) {
      final logoBytes = await _loadLogoBytesForPrinting();
      final bool ok = await EscPosPrinterService.printReceipt(
        printerName: printerName,
        schoolName: config.schoolName,
        currentYear: currentYear,
        studentName: data['studentName'] as String,
        studentId: data['studentId'] as String,
        classe: data['classe'] as String,
        section: data['section'] as String,
        moisPaye: mois,
        montantPaye: montantPaye,
        montantRequis: montantRequis,
        resteAPayerMois: resteAPayerMois,
        totalDejaPayeAnnee: totalPaye,
        totalRequis: totalRequis,
        historiqueTransactions: List<Map<String, dynamic>>.from(
            data['historiqueTransactions'] as List),
        logoBytes: logoBytes,
      );
      if (ok) {
        await _markReceiptPrinted(key);
        return true;
      }
    }

    await _enqueueReceipt(
      key: key,
      type: 'principal',
      eleveId: eleve.id,
      data: data,
    );
    return false;
  }

  Future<bool> retryPrintPrincipalReceipt({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
    required String printerName,
    Uint8List? logoBytes,
  }) async {
    final key = _principalReceiptKey(eleve, transaction);

    if (isReceiptPrinted(key)) {
      transaction['receiptConfirmed'] = true;
      await saveData();
      return true;
    }

    final bool ok = await EscPosPrinterService.printTransactionsReceipt(
      printerName: printerName,
      schoolName: config.schoolName,
      currentYear: currentYear,
      studentName: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      studentId: eleve.id,
      classe: eleve.classe,
      section: eleve.section,
      transactions: [transaction],
      logoBytes: logoBytes,
      duplicata: false,
    );

    if (ok) {
      transaction['receiptConfirmed'] = true;
      await _markReceiptPrinted(key);
    }

    return ok;
  }

  Future<bool> printOrQueueAutreFraisReceipt({
    required Eleve eleve,
    required AutreFrais frais,
    AutreFraisPaiement? paiement,
  }) async {
    final bool avecTranche =
        paiement != null && paiement.trancheId.trim().isNotEmpty;
    final key = paiement != null
        ? 'autre_frais|${eleve.id}|${frais.id}|${paiement.id}'
        : 'autre_frais|${eleve.id}|${frais.id}';
    if (isReceiptPrinted(key)) return false;

    final double montant =
        paiement?.montant ?? getMontantAutreFraisPourEleve(frais, eleve);

    final String titre = avecTranche
        ? '${frais.nom} - ${paiement.trancheLibelle}'
        : frais.nom;

    final data = <String, dynamic>{
      'titreFrais': titre,
      'studentName': '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      'classe': eleve.classe,
      'section': eleve.section,
      'montant': montant,
    };
    // ⚡ NOUVEAU — situation figée au moment du paiement (montant versé,
    // cumul, reste), conservée dans la file d'attente avec le reçu.
    if (paiement != null) {
      try {
        data.addAll(situationApresPaiementAutreFrais(frais, eleve, paiement));
      } catch (_) {}
    }

    final printerName = await _currentPrinterName();
    if (printerName.isNotEmpty) {
      final bool ok = await EscPosPrinterService.printAutreFraisReceipt(
        printerName: printerName,
        schoolName: config.schoolName,
        titreFrais: data['titreFrais'] as String,
        studentName: data['studentName'] as String,
        classe: data['classe'] as String,
        section: data['section'] as String,
        montant: data['montant'] as double,
        cumulPaye: (data['cumulPaye'] as num?)?.toDouble(),
        totalDu: (data['totalDu'] as num?)?.toDouble(),
        resteAPayer: (data['resteAPayer'] as num?)?.toDouble(),
        tranchesCouvertes: data['tranchesCouvertes'] as String?,
      );
      if (ok) {
        await _markReceiptPrinted(key);
        return true;
      }
    }

    await _enqueueReceipt(
      key: key,
      type: 'autre_frais',
      eleveId: eleve.id,
      data: data,
    );
    return false;
  }

  Future<int> flushReceiptQueue() async {
    if (_isFlushingReceiptQueue) return 0;
    if (receiptQueue.isEmpty) return 0;
    final printerName = await _currentPrinterName();
    if (printerName.isEmpty) return 0;

    _isFlushingReceiptQueue = true;
    try {
      final logoBytes = await _loadLogoBytesForPrinting();
      int printedCount = 0;
      final items = List<Map<String, dynamic>>.from(receiptQueue);

      for (final item in items) {
        final key = item['key']?.toString() ?? '';
        if (key.isEmpty) continue;
        if (isReceiptPrinted(key)) {
          receiptQueue.removeWhere((r) => r['key'] == key);
          continue;
        }
        final type = item['type']?.toString() ?? '';
        final data = Map<String, dynamic>.from(item['data'] as Map? ?? {});
        bool ok = false;

        if (type == 'principal') {
          ok = await EscPosPrinterService.printReceipt(
            printerName: printerName,
            schoolName: config.schoolName,
            currentYear: currentYear,
            studentName: data['studentName'] as String? ?? '',
            studentId: data['studentId'] as String? ?? '',
            classe: data['classe'] as String? ?? '',
            section: data['section'] as String? ?? '',
            moisPaye: data['moisPaye'] as String? ?? '',
            montantPaye: (data['montantPaye'] as num?)?.toDouble() ?? 0.0,
            montantRequis: (data['montantRequis'] as num?)?.toDouble() ?? 0.0,
            resteAPayerMois:
            (data['resteAPayerMois'] as num?)?.toDouble() ?? 0.0,
            totalDejaPayeAnnee:
            (data['totalDejaPayeAnnee'] as num?)?.toDouble() ?? 0.0,
            totalRequis: (data['totalRequis'] as num?)?.toDouble() ?? 0.0,
            historiqueTransactions:
            ((data['historiqueTransactions'] as List?) ?? [])
                .map((t) => Map<String, dynamic>.from(t as Map))
                .toList(),
            logoBytes: logoBytes,
          );
        } else if (type == 'autre_frais') {
          ok = await EscPosPrinterService.printAutreFraisReceipt(
            printerName: printerName,
            schoolName: config.schoolName,
            titreFrais: data['titreFrais'] as String? ?? '',
            studentName: data['studentName'] as String? ?? '',
            classe: data['classe'] as String? ?? '',
            section: data['section'] as String? ?? '',
            montant: (data['montant'] as num?)?.toDouble() ?? 0.0,
            cumulPaye: (data['cumulPaye'] as num?)?.toDouble(),
            totalDu: (data['totalDu'] as num?)?.toDouble(),
            resteAPayer: (data['resteAPayer'] as num?)?.toDouble(),
            tranchesCouvertes: data['tranchesCouvertes'] as String?,
          );
        }

        if (ok) {
          await _markReceiptPrinted(key);
          printedCount++;
        }
      }

      return printedCount;
    } finally {
      _isFlushingReceiptQueue = false;
    }
  }

  void _applyIdCorrections(Map<String, dynamic> corrections) {
    if (corrections.isEmpty) return;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (corrections.containsKey(eleve.id)) {
          eleve.id = corrections[eleve.id] as String;
        }
      }
    }
    for (final eleve in elevesSupprimesData.eleves) {
      if (corrections.containsKey(eleve.id)) {
        eleve.id = corrections[eleve.id] as String;
      }
    }
    final Map<String, String> remap =
    corrections.map((k, v) => MapEntry(k, v.toString()));
    for (final liste in autresFraisPaiementsByYear.values) {
      for (final p in liste) {
        _syncRemapperEleveIdPaiement(p, remap);
      }
    }
  }

  Map<String, dynamic> exportSnapshotForClients() {
    return {
      'config': config.toJson(),
      'currentYear': currentYear,
      'localIdCounter': _localIdCounter,
      'lastSelectedClassFilter': lastSelectedClassFilter,
      'lastSelectedSectionFilter': lastSelectedSectionFilter,
      'history': history.map((key, value) => MapEntry(key, value.toJson())),
      'depensesByYear': depensesByYear.map(
            (key, value) =>
            MapEntry(key, value.map((d) => d.toJson()).toList()),
      ),
      'entreesByYear': entreesByYear.map(
            (key, value) =>
            MapEntry(key, value.map((e) => e.toJson()).toList()),
      ),
      'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
      'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
            (key, value) =>
            MapEntry(key, value.map((p) => p.toJson()).toList()),
      ),
      'paiementsAutresFraisAnnules': paiementsAutresFraisAnnules.toList(),
      'autresFraisSupprimesIds': autresFraisSupprimesIds.toList(),
      'autresFraisAdministrations':
      autresFraisAdministrations.map((a) => a.toJson()).toList(),
      'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
      'signataires': signataires.map((s) => s.toJson()).toList(),
      'optionsSections': optionsSections,
      'printedReceiptKeys': printedReceiptKeys,
      'receiptQueue': receiptQueue,
      'elevesSupprimesData': elevesSupprimesData.toJson(),
      'dateSuppressionEleves': dateSuppressionEleves,
      'motifSuppressionEleves': motifSuppressionEleves,
      'backup_password': null,
    };
  }

  Future<Map<String, dynamic>> generateLocalKey({
    required List<String> sections,
    required String type,
    String? classe,
    int durationValue = 30,
    String durationUnit = 'days',
  }) async {
    final rand = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final suffix =
    List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    final prefix =
    (schoolCode != null && schoolCode!.isNotEmpty) ? schoolCode! : 'ECOLE';
    final key = 'LOC-$prefix-$type-$suffix';
    final int safeDurationValue = durationValue < 1 ? 1 : durationValue;
    final String safeDurationUnit =
    durationUnit == 'minutes' ? 'minutes' : 'days';

    final entry = <String, dynamic>{
      'key': key,
      'type': type,
      'sections': sections,
      'classe': classe,
      'createdAt': DateTime.now().toIso8601String(),
      'durationValue': safeDurationValue,
      'durationUnit': safeDurationUnit,
    };
    localAccessKeys.add(entry);
    await saveData();
    return entry;
  }

  Future<Map<String, dynamic>?> verifyLocalKey(String key) async {
    for (final entry in localAccessKeys) {
      if (entry['key'] == key) {
        return entry;
      }
    }
    return null;
  }

  Future<void> revokeLocalKey(String key) async {
    localAccessKeys.removeWhere((e) => e['key'] == key);
    await saveData();
  }

  Future<Map<String, dynamic>> addLocalPendingPayment({
    required String eleveId,
    required String mois,
    required double amount,
  }) async {
    Eleve? eleve;
    for (final e in currentData.eleves) {
      if (e.id == eleveId) {
        eleve = e;
        break;
      }
    }
    final entry = <String, dynamic>{
      'id': 'LPP${DateTime.now().millisecondsSinceEpoch}',
      'eleve_id': eleveId,
      'nom': eleve?.nom ?? '',
      'postNom': eleve?.postNom ?? '',
      'prenom': eleve?.prenom ?? '',
      'section': eleve?.section ?? '',
      'classe': eleve?.classe ?? '',
      'mois': mois,
      'amount': amount,
      'date': DateTime.now().toString().split(' ')[0],
    };
    localPendingPayments.add(entry);
    await saveData();
    return entry;
  }

  Future<int> validateLocalPendingPayments(List<String> ids) async {
    int count = 0;
    final toValidate =
    localPendingPayments.where((p) => ids.contains(p['id'])).toList();
    for (final p in toValidate) {
      Eleve? eleve;
      for (final e in currentData.eleves) {
        if (e.id == p['eleve_id']) {
          eleve = e;
          break;
        }
      }
      eleve ??= findStudentByFullName(
        (p['nom'] ?? '').toString(),
        (p['postNom'] ?? '').toString(),
        (p['prenom'] ?? '').toString(),
      );
      if (eleve != null) {
        handlePayment(
            eleve, p['mois'].toString(), (p['amount'] as num).toDouble());
        count++;
      }
    }
    localPendingPayments.removeWhere((p) => ids.contains(p['id']));
    await saveData();
    return count;
  }

  Future<Map<String, dynamic>> addLocalPendingRegistration(
      Map<String, dynamic> data) async {
    final entry = <String, dynamic>{
      'id': 'LPR${DateTime.now().millisecondsSinceEpoch}',
      ...data,
    };
    localPendingRegistrations.add(entry);
    await saveData();
    return entry;
  }

  Future<int> validateLocalPendingRegistrations(List<String> ids) async {
    int count = 0;
    final toValidate = localPendingRegistrations
        .where((r) => ids.contains(r['id']))
        .toList();
    final processedIds = <String>[];
    for (final r in toValidate) {
      final nom = (r['nom'] ?? '').toString().trim();
      final section = (r['section'] ?? '').toString().trim();
      final classe = (r['classe'] ?? '').toString().trim();
      final postNom = (r['postNom'] ?? '').toString().trim();
      final prenom = (r['prenom'] ?? '').toString().trim();
      if (nom.isEmpty || section.isEmpty || classe.isEmpty) {
        processedIds.add(r['id'] as String);
        continue;
      }
      if (findDuplicateFullName(nom: nom, postNom: postNom, prenom: prenom) !=
          null) {
        continue;
      }

      final id = generateLocalStudentId(nom);
      currentData.eleves.add(Eleve(
        id: id,
        nom: nom,
        postNom: postNom,
        prenom: prenom,
        classe: classe,
        section: section,
      ));
      count++;
      processedIds.add(r['id'] as String);
    }
    localPendingRegistrations
        .removeWhere((r) => processedIds.contains(r['id']));
    await saveData();
    return count;
  }

  Future<Map<String, dynamic>> addLocalPendingAutreFraisPayment({
    required String eleveId,
    required String autreFraisId,
    required double montant,
    String enregistrePar = 'Agent',
  }) async {
    Eleve? eleve;
    for (final e in currentData.eleves) {
      if (e.id == eleveId) {
        eleve = e;
        break;
      }
    }
    AutreFrais? frais;
    for (final f in autresFrais) {
      if (f.id == autreFraisId) {
        frais = f;
        break;
      }
    }
    final entry = <String, dynamic>{
      'id': 'LPAF${DateTime.now().millisecondsSinceEpoch}',
      'eleveId': eleveId,
      'nom': eleve?.nom ?? '',
      'postNom': eleve?.postNom ?? '',
      'prenom': eleve?.prenom ?? '',
      'autreFraisId': autreFraisId,
      'autreFraisNom': frais?.nom ?? '',
      'montant': montant,
      'enregistrePar': enregistrePar,
    };
    localPendingAutresFraisPayments.add(entry);
    await saveData();
    return entry;
  }

  Future<int> validateLocalPendingAutresFraisPayments(
      List<String> ids) async {
    int count = 0;
    final toValidate = localPendingAutresFraisPayments
        .where((p) => ids.contains(p['id']))
        .toList();
    for (final p in toValidate) {
      Eleve? eleve;
      for (final e in currentData.eleves) {
        if (e.id == p['eleveId']) {
          eleve = e;
          break;
        }
      }
      eleve ??= findStudentByFullName(
        (p['nom'] ?? '').toString(),
        (p['postNom'] ?? '').toString(),
        (p['prenom'] ?? '').toString(),
      );
      AutreFrais? frais;
      for (final f in autresFrais) {
        if (f.id == p['autreFraisId']) {
          frais = f;
          break;
        }
      }
      if (eleve != null && frais != null) {
        try {
          // ⚡ Paiement partiel : on enregistre le montant envoyé par l'agent
          // (refusé s'il dépasse le reste dû). Sans montant valide, on garde
          // l'ancien comportement (tranche entière).
          final double montantAgent =
              (p['montant'] as num?)?.toDouble() ?? 0.0;
          await payAutreFrais(
            frais: frais,
            eleve: eleve,
            enregistrePar: (p['enregistrePar'] ?? 'Agent').toString(),
            montantSaisi: montantAgent > 0 ? montantAgent : null,
          );
          count++;
        } catch (_) {}
      }
    }
    localPendingAutresFraisPayments.removeWhere((p) => ids.contains(p['id']));
    await saveData();
    return count;
  }

  Future<void> recordLocalAbsences({
    required String classe,
    required String section,
    required String date,
    required List<String> absentIds,
    String recordedBy = 'Direction',
  }) async {
    localAttendance['$classe|$date'] = absentIds;
    localCommunicationsLog.add({
      'type': 'absences',
      'classe': classe,
      'section': section,
      'date': date,
      'absent_ids': absentIds,
      'recordedBy': recordedBy,
      'loggedAt': DateTime.now().toIso8601String(),
      'delivered': false,
    });
    await saveData();
  }

  List<String> getLocalAttendance(String classe, String date) {
    return localAttendance['$classe|$date'] ?? [];
  }

  Future<void> logLocalCommunication(Map<String, dynamic> entry) async {
    localCommunicationsLog.add({
      ...entry,
      'loggedAt': DateTime.now().toIso8601String(),
      'delivered': false,
    });
    await saveData();
  }

  String _syncHorodatage() => DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');

  /// Copie de sécurité du fichier local. Attend la fin des enregistrements
  /// en cours (la copie reflète exactement l'état en mémoire). Garde les
  /// [kNbCopiesSecurite] plus récentes. Retourne le chemin de la copie.
  Future<String?> _creerCopieSecuriteLocale(String raison) async {
    try {
      await _saveChain.catchError((_) {});
      final dir = await getApplicationDocumentsDirectory();
      final src = File('${dir.path}/school_fees_data.json');
      if (!await src.exists()) return null;
      final chemin =
          '${dir.path}/school_fees_data.safety_${_syncHorodatage()}_$raison.json';
      await src.copy(chemin);
      final copies = await _listerCopiesSecurite(dir);
      for (int i = 0; i < copies.length - kNbCopiesSecurite; i++) {
        if (copies[i].path == chemin) continue;
        try {
          await copies[i].delete();
        } catch (_) {}
      }
      return chemin;
    } catch (_) {
      return null;
    }
  }

  /// ⚡ Annule la dernière récupération : remet cet ordinateur exactement
  /// dans l'état de la copie de sécurité faite juste avant (données,
  /// révision et base de synchronisation comprises). Rien n'est envoyé au
  /// serveur.
  Future<Map<String, dynamic>> annulerDerniereRecuperation() async {
    final chemin = _derniereCopieAvantRecuperation;
    if (chemin == null || !await File(chemin).exists()) {
      return {
        'success': false,
        'error': "Aucune récupération à annuler sur cet ordinateur (pas de "
            "copie de sécurité récente).",
      };
    }
    try {
      final data =
      json.decode(await File(chemin).readAsString()) as Map<String, dynamic>;
      await _saveChain.catchError((_) {});
      _resetEtatEnMemoire();
      await _appliquerDonneesLocales(data);
      _localLoadFailed = false;
      await saveData();
      _derniereCopieAvantRecuperation = null;
      await _journaliserSync({
        'action': 'annulation_recuperation',
        'copie_securite': chemin,
        'resume': resumeSynchronisation(),
      });
      return {'success': true, 'copie': chemin};
    } catch (e) {
      return {'success': false, 'error': 'Copie de sécurité illisible : $e'};
    }
  }

  /// Nombre de copies de sécurité présentes sur cet ordinateur.
  Future<int> nombreCopiesSecurite() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return (await _listerCopiesSecurite(dir)).length;
    } catch (_) {
      return 0;
    }
  }

  // ==========================================================================
  // ⚡ ÉTAPE 5 — JOURNAL DE SYNCHRONISATION
  // Une ligne JSON par opération (récupération, sauvegarde, déconnexion,
  // annulation d'une récupération), dans sync_journal.jsonl à côté du fichier
  // de données. Les [kMaxLignesJournalSync] dernières lignes sont gardées.
  // ==========================================================================
  Future<void> _journaliserSync(Map<String, dynamic> entree) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$kFichierJournalSync');
      final ligne = json.encode({
        'date': DateTime.now().toIso8601String(),
        'ecole': schoolCode,
        ...entree,
      });
      await f.writeAsString('$ligne\n', mode: FileMode.append, flush: true);
      if (await f.length() > 2000000) {
        final lignes = (await f.readAsLines())
            .where((l) => l.trim().isNotEmpty)
            .toList();
        final garder = lignes.length > kMaxLignesJournalSync
            ? lignes.sublist(lignes.length - kMaxLignesJournalSync)
            : lignes;
        await f.writeAsString('${garder.join('\n')}\n', flush: true);
      }
    } catch (_) {}
  }

  /// ⚡ Résumé chiffré des données de cet ordinateur (toutes années) :
  /// nombre d'élèves, de transactions, argent des frais scolaires et des
  /// autres frais. Sert au résumé avant / après chaque récupération.
  Map<String, num> resumeSynchronisation() {
    int eleves = 0, tx = 0, af = 0;
    double argent = 0, argentAf = 0;
    for (final y in history.values) {
      for (final e in y.eleves) {
        eleves++;
        for (final t in e.transactions) {
          tx++;
          argent += (t['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    for (final l in autresFraisPaiementsByYear.values) {
      for (final p in l) {
        af++;
        argentAf += p.montant;
      }
    }
    return {
      'eleves': eleves,
      'transactions': tx,
      'argent': argent,
      'paiements_autres_frais': af,
      'argent_autres_frais': argentAf,
    };
  }

  /// Même résumé, calculé sur les données reçues du serveur.
  static Map<String, num> resumeDepuisJson(Map<String, dynamic> d) {
    int eleves = 0, tx = 0, af = 0;
    double argent = 0, argentAf = 0;
    final h = d['history'];
    if (h is Map) {
      for (final y in h.values) {
        final l = y is Map ? y['eleves'] : null;
        if (l is! List) continue;
        for (final e in l) {
          if (e is! Map) continue;
          eleves++;
          final txs = e['transactions'];
          if (txs is List) {
            for (final t in txs) {
              if (t is Map) {
                tx++;
                argent += (t['amount'] as num?)?.toDouble() ?? 0.0;
              }
            }
          }
        }
      }
    }
    final ap = d['autresFraisPaiementsByYear'];
    if (ap is Map) {
      for (final l in ap.values) {
        if (l is! List) continue;
        for (final p in l) {
          if (p is Map) {
            af++;
            argentAf += (p['montant'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    }
    return {
      'eleves': eleves,
      'transactions': tx,
      'argent': argent,
      'paiements_autres_frais': af,
      'argent_autres_frais': argentAf,
    };
  }

  /// Résultat renvoyé quand une récupération a donné des chiffres anormaux :
  /// rien n'est envoyé au serveur ; l'utilisateur choisit de garder ou
  /// d'annuler (annulerDerniereRecuperation).
  Map<String, dynamic> _arretAnomalie(Map<String, dynamic> r) => {
    ...r,
    'success': false,
    'code': 'ANOMALIE_FUSION',
    'error': "Chiffres anormaux après la récupération : RIEN n'a été envoyé "
        "au serveur. Vérifiez le résumé, puis gardez ou annulez la "
        "récupération.",
  };

  Map<String, List<Eleve>> _historiqueDepuisJson(dynamic d) {
    final out = <String, List<Eleve>>{};
    final h = d is Map ? d['history'] : null;
    if (h is! Map) return out;
    h.forEach((annee, y) {
      try {
        out[annee.toString()] =
            SchoolYearData.fromJson(Map<String, dynamic>.from(y as Map)).eleves;
      } catch (_) {}
    });
    return out;
  }

  /// Clés « année|nom complet » des élèves présents en plusieurs fiches
  /// (identifiants différents) la même année.
  Set<String> _clesDoublonsEleves(Map<String, dynamic> parAnnee) {
    final out = <String>{};
    parAnnee.forEach((annee, v) {
      final List<Eleve> eleves =
      v is SchoolYearData ? v.eleves : (v as List<Eleve>);
      final parNom = <String, Set<String>>{};
      for (final e in eleves) {
        final cle = _cleNomEleve(e);
        if (cle.replaceAll('_', '').trim().isEmpty) continue;
        parNom.putIfAbsent(cle, () => <String>{}).add(e.id);
      }
      parNom.forEach((cle, ids) {
        if (ids.length > 1) out.add('$annee|$cle');
      });
    });
    return out;
  }

  /// ⚡ Contrôle d'une fusion. Une fusion correcte ne peut pas dépasser
  /// « cet ordinateur + serveur − dernière synchronisation commune » (tout
  /// ce qui est commun n'est compté qu'une fois) ; elle ne doit pas non
  /// plus tomber nettement en dessous de ce que cet ordinateur avait.
  static List<Map<String, dynamic>> controlerFusion({
    required Map<String, num> avant,
    required Map<String, num> serveur,
    required Map<String, num>? base,
    required Map<String, num> apres,
    Set<String> doublonsAvant = const {},
    Set<String> doublonsServeur = const {},
    Set<String> doublonsApres = const {},
  }) {
    final anomalies = <Map<String, dynamic>>[];
    String fmt(num v) => v.toStringAsFixed(0);
    const libelles = {
      'eleves': "nombre d'élèves",
      'argent': 'argent des frais scolaires (FC)',
      'argent_autres_frais': 'argent des autres frais (FC)',
    };
    libelles.forEach((cle, libelle) {
      final num a = avant[cle] ?? 0;
      final num s = serveur[cle] ?? 0;
      final num p = apres[cle] ?? 0;
      final num? b = base?[cle];
      final bool eleves = cle == 'eleves';
      num tol(num ref) => eleves
          ? 0
          : (ref.abs() * 0.005 < 500 ? 500 : ref.abs() * 0.005);
      // Partie commune connue = dernière synchronisation, bornée par ce
      // que chacun possède encore.
      num commun = b ?? 0;
      if (commun > a) commun = a;
      if (commun > s) commun = s;
      if (commun < 0) commun = 0;
      final num maxi = a + s - commun;
      if (p > maxi + tol(maxi)) {
        anomalies.add({
          'niveau': 'bloquant',
          'cle': cle,
          'message': "Hausse inexpliquée du $libelle : ${fmt(p)} après la "
              "fusion, alors que cet ordinateur en avait ${fmt(a)} et le "
              "serveur ${fmt(s)} (maximum possible ${fmt(maxi)}). Risque de "
              "doublons.",
        });
      }
      // Baisse par rapport à CET ordinateur : des données qu'il avait ont
      // disparu (annulées ailleurs... ou effacées du serveur par un autre
      // ordinateur).
      if (p < a * 0.9 - tol(a)) {
        anomalies.add({
          'niveau': 'bloquant',
          'cle': cle,
          'message': "Baisse importante du $libelle : ${fmt(p)} après la "
              "fusion, alors que cet ordinateur en avait ${fmt(a)} (serveur : "
              "${fmt(s)}). Des données ont peut-être été effacées sur le "
              "serveur.",
        });
      } else if (p < a - tol(a)) {
        anomalies.add({
          'niveau': 'attention',
          'cle': cle,
          'message': "Baisse du $libelle : ${fmt(a)} → ${fmt(p)} "
              "(paiements annulés sur un autre ordinateur ?).",
        });
      }
    });
    final nouveaux = doublonsApres.difference(doublonsAvant);
    final crees = nouveaux.difference(doublonsServeur);
    final venus = nouveaux.intersection(doublonsServeur);
    if (crees.isNotEmpty) {
      anomalies.add({
        'niveau': 'bloquant',
        'cle': 'doublons',
        'message': "La fusion a créé ${crees.length} élève(s) en double "
            "(même nom, identifiants différents) : "
            "${crees.map((c) => c.split('|').last.replaceAll('_', ' ').trim()).take(5).join(', ')}.",
      });
    }
    if (venus.isNotEmpty) {
      anomalies.add({
        'niveau': 'attention',
        'cle': 'doublons',
        'message': "Le serveur contient déjà ${venus.length} élève(s) en "
            "double : ${venus.map((c) => c.split('|').last.replaceAll('_', ' ').trim()).take(5).join(', ')}. "
            "Utilisez « Vérifier les doublons ».",
      });
    }
    return anomalies;
  }

  // ==========================================================================
  // ⚡ ÉTAPE 5 — DÉTECTEUR DE DOUBLONS (année en cours)
  // ==========================================================================
  bool _ficheVide(Eleve e) =>
      e.transactions.isEmpty &&
          !e.hasCarteInfo &&
          !autresFraisPaiementsByYear.values
              .any((l) => l.any((p) => p.eleveId == e.id));

  /// Groupes de doublons de l'année en cours :
  ///  • type 'eleve' : même nom complet, plusieurs fiches. « aArchiver » =
  ///    fiches VIDES qu'on peut archiver sans rien perdre (vide si aucune
  ///    réparation sûre n'est possible) ;
  ///  • type 'transactions' : paiements identiques (même date, mois et
  ///    montant) dans un même élève — à vérifier à la main (ils peuvent être
  ///    réels), jamais supprimés automatiquement.
  List<Map<String, dynamic>> detecterDoublons() {
    final out = <Map<String, dynamic>>[];
    final parNom = <String, List<Eleve>>{};
    for (final e in currentData.eleves) {
      final cle = _cleNomEleve(e);
      if (cle.replaceAll('_', '').trim().isEmpty) continue;
      parNom.putIfAbsent(cle, () => []).add(e);
    }
    parNom.forEach((cle, liste) {
      if (liste.map((e) => e.id).toSet().length < 2) return;
      final vides = liste.where(_ficheVide).toList();
      final pleines = liste.where((e) => !_ficheVide(e)).toList();
      final List<Eleve> aArchiver = pleines.isNotEmpty
          ? vides
          : (vides.length > 1 ? vides.sublist(1) : <Eleve>[]);
      out.add({
        'type': 'eleve',
        'nom': '${liste.first.nom} ${liste.first.postNom} ${liste.first.prenom}'
            .trim(),
        'fiches': [
          for (final e in liste)
            {
              'id': e.id,
              'classe': e.classe,
              'section': e.section,
              'transactions': e.transactions.length,
              'argent': e.transactions.fold<double>(
                  0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0)),
              'vide': _ficheVide(e),
            }
        ],
        'aArchiver': aArchiver.map((e) => e.id).toList(),
      });
    });
    for (final e in currentData.eleves) {
      final parSig = <String, List<String>>{};
      for (final t in e.transactions) {
        final id = t['id']?.toString() ?? '';
        parSig.putIfAbsent(_signatureTransaction(t), () => []).add(id);
      }
      parSig.forEach((sig, ids) {
        if (ids.length < 2) return;
        final parts = sig.split('|');
        out.add({
          'type': 'transactions',
          'eleveId': e.id,
          'nom': '${e.nom} ${e.postNom} ${e.prenom}'.trim(),
          'date': parts.isNotEmpty ? parts[0] : '',
          'mois': parts.length > 1 ? parts[1] : '',
          'montant': parts.length > 2 ? double.tryParse(parts[2]) ?? 0 : 0,
          'ids': ids,
        });
      });
    }
    return out;
  }

  /// Réparation SÛRE : archive uniquement les fiches en double VIDES (aucun
  /// paiement, aucun « autre frais », aucune information) quand une autre
  /// fiche du même élève existe. Rien d'autre n'est touché. L'archivage se
  /// propage aux autres ordinateurs à la synchronisation. Retourne le nombre
  /// de fiches archivées.
  Future<int> reparerDoublonsSurs() async {
    final ids = <String>{
      for (final g in detecterDoublons())
        if (g['type'] == 'eleve') ...(g['aArchiver'] as List).cast<String>(),
    };
    if (ids.isEmpty) return 0;
    await _creerCopieSecuriteLocale('avant_reparation_doublons');
    final aArchiver =
    currentData.eleves.where((e) => ids.contains(e.id)).toList();
    for (final e in aArchiver) {
      await archiverEtSupprimerEleve(e,
          motif: 'Doublon vide (réparation automatique)');
    }
    await _journaliserSync({
      'action': 'reparation_doublons',
      'fiches_archivees': aArchiver.map((e) => e.id).toList(),
      'resume': resumeSynchronisation(),
    });
    return aArchiver.length;
  }

  /// Dernières entrées du journal, de la plus récente à la plus ancienne.
  Future<List<Map<String, dynamic>>> lireJournalSync({int max = 200}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$kFichierJournalSync');
      if (!await f.exists()) return [];
      final lignes = await f.readAsLines();
      final out = <Map<String, dynamic>>[];
      for (final l in lignes.reversed) {
        if (out.length >= max) break;
        if (l.trim().isEmpty) continue;
        try {
          out.add(Map<String, dynamic>.from(json.decode(l) as Map));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<File>> _listerCopiesSecurite(Directory dir) async {
    final copies = <File>[];
    await for (final f in dir.list()) {
      if (f is File) {
        final nom = f.uri.pathSegments.last;
        if (nom.startsWith('school_fees_data.safety_')) copies.add(f);
      }
    }
    copies.sort((a, b) => a.path.compareTo(b.path));
    return copies;
  }

  void _resetEtatEnMemoire() {
    config      = SchoolConfig(schoolName: "EduPay School RDC");
    currentData = SchoolYearData(eleves: []);
    currentYear = '2025-2026';
    history     = {};
    _localIdCounter = 0;
    lastSelectedClassFilter   = null;
    lastSelectedSectionFilter = null;
    lastReportCity = null;
    schoolCode  = null;
    depensesByYear = {};
    entreesByYear = {};
    autresFrais = [];
    autresFraisPaiementsByYear = {};
    paiementsAutresFraisAnnules = {};
    autresFraisSupprimesIds = {};
    autresFraisAdministrations = [];
    adminAuditLog = [];
    signataires = [];
    optionsSections = {};
    localAccessKeys = [];
    localPendingPayments = [];
    localPendingRegistrations = [];
    localPendingAutresFraisPayments = [];
    localAttendance = {};
    localCommunicationsLog = [];
    printedReceiptKeys = [];
    receiptQueue = [];
    elevesSupprimesData = SchoolYearData(eleves: []);
    dateSuppressionEleves = {};
    motifSuppressionEleves = {};
    _syncServerRevision = null;
    _syncBase = <String, Set<String>>{};
    _syncBaseConfigJson = null;
    _syncBaseResume = null;
  }

  Future<void> _appliquerDonneesLocales(Map<String, dynamic> data) async {
    config       = SchoolConfig.fromJson(data['config'] ?? {});
    currentYear  = data['currentYear'] ?? '2025-2026';
    lastSelectedClassFilter   = data['lastSelectedClassFilter'];
    lastSelectedSectionFilter = data['lastSelectedSectionFilter'];
    lastReportCity = data['lastReportCity'] as String?;
    schoolCode = data['schoolCode'] as String?;
    if (data['adminAuditLog'] != null) {
      adminAuditLog = (data['adminAuditLog'] as List<dynamic>)
          .map((e) => AdminAuditLog.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data['signataires'] != null) {
      signataires = (data['signataires'] as List<dynamic>)
          .map((e) => Signataire.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data['optionsSections'] != null) {
      optionsSections = _parseOptionsSections(data['optionsSections']);
      _nettoyerOptions();
    }

    if (data['history'] != null) {
      history = (data['history'] as Map<String, dynamic>).map(
            (key, value) =>
            MapEntry(key, SchoolYearData.fromJson(value)),
      );
    }
    if (data['depensesByYear'] != null) {
      depensesByYear =
          (data['depensesByYear'] as Map<String, dynamic>).map(
                (key, value) => MapEntry(
              key,
              (value as List<dynamic>)
                  .map((e) => Depense.fromJson(e as Map<String, dynamic>))
                  .toList(),
            ),
          );
    }
    // ⚡ NOUVEAU — absent des anciennes sauvegardes : entreesByYear reste {}
    // (valeur par défaut du champ), aucune erreur.
    if (data['entreesByYear'] != null) {
      entreesByYear =
          (data['entreesByYear'] as Map<String, dynamic>).map(
                (key, value) => MapEntry(
              key,
              (value as List<dynamic>)
                  .map((e) => Entree.fromJson(e as Map<String, dynamic>))
                  .toList(),
            ),
          );
    }
    if (data['autresFrais'] != null) {
      autresFrais = (data['autresFrais'] as List<dynamic>)
          .map((e) => AutreFrais.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (data['autresFraisPaiementsByYear'] != null) {
      autresFraisPaiementsByYear = (data['autresFraisPaiementsByYear']
      as Map<String, dynamic>)
          .map(
            (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map((e) => AutreFraisPaiement.fromJson(
              e as Map<String, dynamic>))
              .toList(),
        ),
      );
    }
    if (data['paiementsAutresFraisAnnules'] != null) {
      paiementsAutresFraisAnnules =
          (data['paiementsAutresFraisAnnules'] as List<dynamic>)
              .map((e) => e.toString())
              .toSet();
    }
    if (data['autresFraisSupprimesIds'] != null) {
      autresFraisSupprimesIds =
          (data['autresFraisSupprimesIds'] as List<dynamic>)
              .map((e) => e.toString())
              .toSet();
    }
    if (data['autresFraisAdministrations'] != null) {
      autresFraisAdministrations =
          (data['autresFraisAdministrations'] as List<dynamic>)
              .map((e) => AutreFraisAdministration.fromJson(
              e as Map<String, dynamic>))
              .toList();
    }

    if (history.containsKey(currentYear)) {
      currentData = history[currentYear]!;
    } else {
      currentData          = SchoolYearData(eleves: []);
      history[currentYear] = currentData;
    }

    if (data['localIdCounter'] != null) {
      _localIdCounter = data['localIdCounter'] as int;
    } else {
      _localIdCounter = _inferCounterFromExistingIds();
    }
    _codeAppareil = data['codeAppareil'] as String?;
    if (data['localAccessKeys'] != null) {
      localAccessKeys = (data['localAccessKeys'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (data['localPendingPayments'] != null) {
      localPendingPayments =
          (data['localPendingPayments'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
    }
    if (data['localPendingRegistrations'] != null) {
      localPendingRegistrations =
          (data['localPendingRegistrations'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
    }
    if (data['localPendingAutresFraisPayments'] != null) {
      localPendingAutresFraisPayments =
          (data['localPendingAutresFraisPayments'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
    }
    if (data['localAttendance'] != null) {
      localAttendance =
          (data['localAttendance'] as Map<String, dynamic>).map(
                (key, value) => MapEntry(
              key,
              (value as List<dynamic>).map((e) => e.toString()).toList(),
            ),
          );
    }
    if (data['localCommunicationsLog'] != null) {
      localCommunicationsLog =
          (data['localCommunicationsLog'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
    }
    if (data['printedReceiptKeys'] != null) {
      printedReceiptKeys = (data['printedReceiptKeys'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
    }
    if (data['receiptQueue'] != null) {
      receiptQueue = (data['receiptQueue'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (data['elevesSupprimesData'] != null) {
      elevesSupprimesData =
          SchoolYearData.fromJson(data['elevesSupprimesData']);
    }
    if (data['dateSuppressionEleves'] != null) {
      dateSuppressionEleves =
          (data['dateSuppressionEleves'] as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, value.toString()));
    }
    if (data['motifSuppressionEleves'] != null) {
      motifSuppressionEleves =
          (data['motifSuppressionEleves'] as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, value.toString()));
    }

    final dynamic rev = data['serverRevision'];
    _syncServerRevision = rev is num ? rev.toInt() : null;
    _syncBase = <String, Set<String>>{};
    final dynamic base = data['syncBase'];
    if (base is Map) {
      base.forEach((k, v) {
        if (v is List) {
          _syncBase[k.toString()] = v.map((e) => e.toString()).toSet();
        }
      });
    }
    _syncBaseConfigJson = data['syncBaseConfig'] as String?;
    final dynamic br = data['syncBaseResume'];
    _syncBaseResume = br is Map
        ? {
      for (final e in br.entries)
        if (e.value is num) e.key.toString(): e.value as num,
    }
        : null;

    await _assignMissingIds();
  }

  Future<void> loadData() async {
    final dir       = await getApplicationDocumentsDirectory();
    _dataFilePath   = '${dir.path}/school_fees_data.json';
    final file      = File(_dataFilePath!);

    if (!await file.exists()) {
      _initDefaultData();
      return;
    }

    try {
      final jsonStr = await file.readAsString();
      final data    = json.decode(jsonStr) as Map<String, dynamic>;
      await _appliquerDonneesLocales(data);
      _localLoadFailed = false;
      return;
    } catch (_) {}

    try {
      await file.rename(
          '${dir.path}/school_fees_data.corrupt_${_syncHorodatage()}.json');
    } catch (_) {}

    final candidats = <File>[File('${dir.path}/school_fees_data.json.tmp')];
    try {
      final copies = await _listerCopiesSecurite(dir);
      candidats.addAll(copies.reversed);
    } catch (_) {}

    for (final c in candidats) {
      try {
        if (!await c.exists()) continue;
        final data = json.decode(await c.readAsString()) as Map<String, dynamic>;
        _resetEtatEnMemoire();
        await _appliquerDonneesLocales(data);
        _localLoadFailed = true;
        await saveData();
        return;
      } catch (_) {
        continue;
      }
    }

    _initDefaultData();
    _localLoadFailed = true;
  }

  int _inferCounterFromExistingIds() {
    int maxCounter = 0;
    final regex    = RegExp(r'(\d+)$');
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        final match = regex.firstMatch(eleve.id);
        if (match != null) {
          final n = int.tryParse(match.group(1) ?? '') ?? 0;
          if (n > maxCounter) maxCounter = n;
        }
      }
    }
    return maxCounter;
  }

  Future<void> _assignMissingIds() async {
    bool changed = false;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.id.isEmpty || eleve.id == "N/A") {
          eleve.id = generateLocalStudentId(eleve.nom);
          changed  = true;
        }
      }
    }
    if (changed) await saveData();
  }

  void _initDefaultData() {
    currentData          = SchoolYearData(eleves: []);
    history[currentYear] = currentData;
    _localIdCounter      = 0;
    _syncServerRevision  = null;
    _syncBase            = <String, Set<String>>{};
    _syncBaseConfigJson  = null;
    _syncBaseResume      = null;
  }

  Map<String, dynamic> _construireJsonLocal() {
    return {
      'config':                  config.toJson(),
      'currentYear':             currentYear,
      'localIdCounter':          _localIdCounter,
      'codeAppareil':            _codeAppareil,
      'lastSelectedClassFilter': lastSelectedClassFilter,
      'lastSelectedSectionFilter': lastSelectedSectionFilter,
      'lastReportCity': lastReportCity,
      'schoolCode':              schoolCode,
      'history':                 history.map(
              (key, value) => MapEntry(key, value.toJson())),
      'depensesByYear': depensesByYear.map(
            (key, value) =>
            MapEntry(key, value.map((d) => d.toJson()).toList()),
      ),
      'entreesByYear': entreesByYear.map(
            (key, value) =>
            MapEntry(key, value.map((e) => e.toJson()).toList()),
      ),
      'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
      'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
            (key, value) =>
            MapEntry(key, value.map((p) => p.toJson()).toList()),
      ),
      'paiementsAutresFraisAnnules': paiementsAutresFraisAnnules.toList(),
      'autresFraisSupprimesIds': autresFraisSupprimesIds.toList(),
      'autresFraisAdministrations':
      autresFraisAdministrations.map((a) => a.toJson()).toList(),
      'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
      'signataires': signataires.map((s) => s.toJson()).toList(),
      'optionsSections': optionsSections,
      'localAccessKeys': localAccessKeys,
      'localPendingPayments': localPendingPayments,
      'localPendingRegistrations': localPendingRegistrations,
      'localPendingAutresFraisPayments': localPendingAutresFraisPayments,
      'localAttendance': localAttendance,
      'localCommunicationsLog': localCommunicationsLog,
      'printedReceiptKeys': printedReceiptKeys,
      'receiptQueue': receiptQueue,
      'elevesSupprimesData': elevesSupprimesData.toJson(),
      'dateSuppressionEleves': dateSuppressionEleves,
      'motifSuppressionEleves': motifSuppressionEleves,
      'serverRevision': _syncServerRevision,
      'syncBase': _syncBase.map((k, v) => MapEntry(k, v.toList())),
      'syncBaseConfig': _syncBaseConfigJson,
      'syncBaseResume': _syncBaseResume,
    };
  }

  Future<void> saveData() {
    if (_dataFilePath != null) {
      history[currentYear] = currentData;
    }
    _saveChain = _saveChain.catchError((_) {}).then((_) => _ecrireFichierLocal());
    return _saveChain;
  }

  Future<void> _ecrireFichierLocal() async {
    if (_dataFilePath == null) {
      final dir     = await getApplicationDocumentsDirectory();
      _dataFilePath = '${dir.path}/school_fees_data.json';
    }
    history[currentYear] = currentData;
    final String encoded = json.encode(_construireJsonLocal());
    final String chemin = _dataFilePath!;
    final tmp = File('$chemin.tmp');
    await tmp.writeAsString(encoded, flush: true);
    try {
      await tmp.rename(chemin);
    } on FileSystemException {
      final cible = File(chemin);
      if (await cible.exists()) await cible.delete();
      await tmp.rename(chemin);
    }
  }

  Future<void> clearLocalData() async {
    if (_dataFilePath == null) {
      final dir     = await getApplicationDocumentsDirectory();
      _dataFilePath = '${dir.path}/school_fees_data.json';
    }
    await _saveChain.catchError((_) {});
    final copie = await _creerCopieSecuriteLocale('avant_deconnexion');
    await _journaliserSync({
      'action': 'deconnexion',
      'copie_securite': copie,
      'resume': resumeSynchronisation(),
    });
    final file = File(_dataFilePath!);
    if (await file.exists()) {
      await file.delete();
    }
    _resetEtatEnMemoire();
    _localLoadFailed = false;
  }

  Future<void> changeYear(String newYear) async {
    if (currentYear == newYear) return;
    history[currentYear] = currentData;
    currentYear = newYear;
    if (history.containsKey(newYear)) {
      currentData = history[newYear]!;
    } else {
      currentData          = SchoolYearData(eleves: []);
      history[newYear]     = currentData;
    }
    await saveData();
  }

  Map<String, dynamic> _syncOccupe() => {
    'success': false,
    'busy': true,
    'error': 'Une synchronisation est déjà en cours. Patientez quelques '
        'secondes (ne cliquez pas plusieurs fois).',
  };

  Future<void> _journaliserResultat(
      String action, Map<String, dynamic> r) async {
    String? err = r['error']?.toString();
    if (err != null && err.length > 300) err = '${err.substring(0, 300)}…';
    await _journaliserSync({
      'action': action,
      'succes': r['success'] == true,
      if (r['code'] != null) 'code': r['code'],
      'erreur': ?err,
      'revision': _syncServerRevision,
      if (r['autreOrdinateur'] == true) 'autre_ordinateur': true,
      if ((r['warnings'] as List?)?.isNotEmpty == true)
        'avertissements': r['warnings'],
      if (r['resume'] != null) 'resume': r['resume'],
      if ((r['anomalies'] as List?)?.isNotEmpty == true)
        'anomalies': r['anomalies'],
    });
  }

  Future<Map<String, dynamic>> backupToServer(
      String schoolCodeParam, String password,
      {bool force = false}) async {
    if (_syncBusy) return _syncOccupe();
    _syncBusy = true;
    try {
      final r = await _backupToServerInterne(schoolCodeParam, password,
          force: force);
      await _journaliserResultat('sauvegarde', r);
      return r;
    } finally {
      _syncBusy = false;
    }
  }

  Future<Map<String, dynamic>> _backupToServerInterne(
      String schoolCodeParam, String password,
      {bool force = false}) async {
      if (_localLoadFailed && !force) {
        return {
          'success': false,
          'error': "Les données de cet ordinateur n'ont pas pu être lues "
              "correctement. Cliquez d'abord sur « Récupérer depuis le "
              "Serveur », puis sauvegardez.",
          'code': 'LOCAL_UNREADABLE',
        };
      }

      if (_syncServerRevision == null && !force) {
        final r = await _restoreInternal(schoolCodeParam, password);
        if (r['success'] != true && r['notFound'] != true) return r;
        if (r['bloquant'] == true) return _arretAnomalie(r);
      }

      var res = await _backupInternal(schoolCodeParam, password, force: force);

      if (res['success'] != true && res['code'] == 'STALE_REVISION') {
        // ⚡ Un autre ordinateur a sauvegardé entre-temps : on récupère et
        // on fusionne ses données avant d'envoyer, et on le dit clairement.
        final r = await _restoreInternal(schoolCodeParam, password);
        if (r['success'] != true) return {...r, 'autreOrdinateur': true};
        if (r['bloquant'] == true) {
          return {..._arretAnomalie(r), 'autreOrdinateur': true};
        }
        res = await _backupInternal(schoolCodeParam, password);
        res = {
          ...res,
          'autreOrdinateur': true,
          'warnings': r['warnings'] ?? const <String>[],
          if (r['resume'] != null) 'resume': r['resume'],
        };
      }
      return res;
  }

  // ==========================================================================
  // ⚡ CHANGEMENT DU MOT DE PASSE — enregistré sur le SERVEUR
  // Avant : le nouveau mot de passe n'était gardé que sur cet ordinateur ; le
  // serveur gardait l'ancien et refusait ensuite les sauvegardes.
  // Maintenant, en une seule opération :
  //   1. récupération avec l'ANCIEN mot de passe (cet ordinateur est à jour,
  //      rien de ce qu'ont saisi les autres ne se perd) ;
  //   2. sauvegarde avec le NOUVEAU mot de passe et current_password =
  //      ancien : le serveur enregistre le nouveau.
  // L'application ne doit changer son mot de passe local QUE si le résultat
  // est un succès (voir settings_screen).
  // ==========================================================================
  Future<Map<String, dynamic>> changerMotDePasse(
      String schoolCodeParam, String ancien, String nouveau) async {
    if (_syncBusy) return _syncOccupe();
    nouveau = nouveau.trim();
    if (nouveau.length < 6) {
      return {
        'success': false,
        'error': 'Le mot de passe doit contenir au moins 6 caractères.',
      };
    }
    if (nouveau == ancien) {
      return {
        'success': false,
        'error': "Le nouveau mot de passe est identique à l'ancien.",
      };
    }
    _syncBusy = true;
    try {
      Map<String, dynamic> r =
      await _restoreInternal(schoolCodeParam, ancien);
      if (r['success'] != true && r['notFound'] != true) {
        if (r['code'] == 'MOT_DE_PASSE_REFUSE') {
          r = {
            ...r,
            'error': "Le serveur refuse le mot de passe actuel : il a "
                "peut-être déjà été changé sur un autre ordinateur.",
          };
        }
        await _journaliserResultat('changement_mot_de_passe', r);
        return r;
      }
      if (r['bloquant'] == true) {
        final arret = _arretAnomalie(r);
        await _journaliserResultat('changement_mot_de_passe', arret);
        return arret;
      }
      var b = await _backupInternal(schoolCodeParam, nouveau,
          motDePasseActuel: ancien);
      if (b['success'] != true && b['code'] == 'STALE_REVISION') {
        r = await _restoreInternal(schoolCodeParam, ancien);
        if (r['success'] == true && r['bloquant'] != true) {
          b = await _backupInternal(schoolCodeParam, nouveau,
              motDePasseActuel: ancien);
        } else {
          b = r['bloquant'] == true ? _arretAnomalie(r) : r;
        }
      }
      final res = {
        ...b,
        'motDePasseChange': b['success'] == true,
        if (r['resume'] != null) 'resume': r['resume'],
      };
      await _journaliserResultat('changement_mot_de_passe', res);
      return res;
    } finally {
      _syncBusy = false;
    }
  }

  /// Vérifie un mot de passe auprès du serveur (/verify_password), sans
  /// rien télécharger ni modifier. Sert quand le mot de passe a été changé
  /// sur un autre ordinateur. 'valid' : vrai / faux ; 'reseau' : faux si le
  /// serveur n'a pas pu être joint.
  Future<Map<String, dynamic>> verifierMotDePasseServeur(
      String schoolCodeParam, String motDePasse) async {
    try {
      final response = await http
          .post(
        Uri.parse('$serverUrl/verify_password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCodeParam.trim().toUpperCase(),
          'password': motDePasse.trim(),
        }),
      )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final d = json.decode(response.body);
        return {'valid': d is Map && d['valid'] == true, 'reseau': true};
      }
      return {'valid': false, 'reseau': true};
    } catch (e) {
      return {'valid': false, 'reseau': false, 'error': '$e'};
    }
  }

  Future<Map<String, dynamic>> restoreFromServer(
      String schoolCodeParam, String password) async {
    if (_syncBusy) return _syncOccupe();
    _syncBusy = true;
    try {
      final r = await _restoreInternal(schoolCodeParam, password);
      await _journaliserResultat('recuperation', r);
      return r;
    } finally {
      _syncBusy = false;
    }
  }

  Future<Map<String, dynamic>> syncWithServer(
      String schoolCodeParam, String password) async {
    if (_syncBusy) return _syncOccupe();
    _syncBusy = true;
    try {
      final r = await _restoreInternal(schoolCodeParam, password);
      if (r['success'] != true && r['notFound'] != true) {
        await _journaliserResultat('synchronisation', r);
        return r;
      }
      if (r['bloquant'] == true) {
        final arret = _arretAnomalie(r);
        await _journaliserResultat('synchronisation', arret);
        return arret;
      }
      final b = await _backupInternal(schoolCodeParam, password);
      final res = {
        ...b,
        'restored': r['success'] == true,
        'warnings': r['warnings'] ?? const <String>[],
        if (r['resume'] != null) 'resume': r['resume'],
      };
      await _journaliserResultat('synchronisation', res);
      return res;
    } finally {
      _syncBusy = false;
    }
  }

  Future<Map<String, dynamic>> _backupInternal(
      String schoolCodeParam, String password,
      {bool force = false, String? motDePasseActuel}) async {
    final normalizedCode = schoolCodeParam.trim().toUpperCase();
    try {
      schoolCode = normalizedCode;
      await saveData();

      final data = {
        'config':          config.toJson(),
        'currentYear':     currentYear,
        'localIdCounter':  _localIdCounter,
        'lastSelectedClassFilter':   lastSelectedClassFilter,
        'lastSelectedSectionFilter': lastSelectedSectionFilter,
        'history':         history.map(
                (key, value) => MapEntry(key, value.toJson())),
        'depensesByYear': depensesByYear.map(
              (key, value) =>
              MapEntry(key, value.map((d) => d.toJson()).toList()),
        ),
        'entreesByYear': entreesByYear.map(
              (key, value) =>
              MapEntry(key, value.map((e) => e.toJson()).toList()),
        ),
        'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
        'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
              (key, value) =>
              MapEntry(key, value.map((p) => p.toJson()).toList()),
        ),
        'paiementsAutresFraisAnnules': paiementsAutresFraisAnnules.toList(),
        'autresFraisSupprimesIds': autresFraisSupprimesIds.toList(),
        'autresFraisAdministrations':
        autresFraisAdministrations.map((a) => a.toJson()).toList(),
        'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
        'signataires': signataires.map((s) => s.toJson()).toList(),
        'optionsSections': optionsSections,
        'printedReceiptKeys': printedReceiptKeys,
        'receiptQueue': receiptQueue,
        'elevesSupprimesData': elevesSupprimesData.toJson(),
        'dateSuppressionEleves': dateSuppressionEleves,
        'motifSuppressionEleves': motifSuppressionEleves,
        'backup_password': password,
      };

      final Map<String, dynamic> corps = {
        'school_code': normalizedCode,
        'data': data,
        'promoter_summary': computePromoterSummary(),
      };
      if (_syncServerRevision != null) {
        corps['base_revision'] = _syncServerRevision;
      }
      if (force) corps['force'] = true;
      // ⚡ Changement de mot de passe : le serveur accepte la sauvegarde si
      // l'ANCIEN mot de passe est donné ici, et enregistre le nouveau
      // (data.backup_password) — app.py, /backup.
      if (motDePasseActuel != null && motDePasseActuel.isNotEmpty) {
        corps['current_password'] = motDePasseActuel;
      }

      final response = await http
          .post(
        Uri.parse('$serverUrl/backup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(corps),
      )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final corrections  =
            responseData['corrections'] as Map<String, dynamic>? ?? {};
        if (corrections.isNotEmpty) {
          _applyIdCorrections(corrections);
        }

        final dynamic rev = responseData['revision'];
        if (rev is num) _syncServerRevision = rev.toInt();
        _syncBase = _syncIdsDepuisEtatLocal();
        _syncBaseResume = resumeSynchronisation();
        _syncBaseConfigJson = _syncCanon(config.toJson());
        _localLoadFailed = false;
        await saveData();

        bool summaryOk = responseData['summary_saved'] == true;
        if (!summaryOk) summaryOk = await pushPromoterSummary();
        return {
          'success': true,
          'summarySent': summaryOk,
          'revision': _syncServerRevision,
        };
      }

      if (response.statusCode == 409) {
        String msg = 'Le serveur a refusé la sauvegarde pour protéger vos '
            'données (statut 409).';
        String? code;
        try {
          final b = json.decode(response.body);
          msg = b['error']?.toString() ?? msg;
          code = b['code']?.toString();
        } catch (_) {}
        return {
          'success': false,
          'error': msg,
          'code': code,
          'conflict': true,
        };
      }
      if (response.statusCode == 401) {
        return {
          'success': false,
          'error': 'Mot de passe incorrect',
          'code': 'MOT_DE_PASSE_REFUSE',
        };
      }
      return {
        'success': false,
        'error':
        'Le serveur a répondu avec le statut ${response.statusCode} : '
            '${response.body}',
      };
    } on SocketException catch (e) {
      return {
        'success': false,
        'error': 'Aucune connexion réseau (vérifiez internet / pare-feu) : $e',
      };
    } on HandshakeException catch (e) {
      return {
        'success': false,
        'error': 'Erreur de certificat TLS/SSL sur cet appareil : $e',
      };
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  Future<Map<String, dynamic>> _restoreInternal(
      String schoolCodeParam, String password) async {
    final normalizedCode = schoolCodeParam.trim().toUpperCase();
    try {
      final response = await http
          .get(
        Uri.parse('$serverUrl/restore?school_code=$normalizedCode'),
        headers: {'X-Backup-Password': password},
      )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['backup_password'] != null &&
            data['backup_password'] != password) {
          return {
          'success': false,
          'error': 'Mot de passe incorrect',
          'code': 'MOT_DE_PASSE_REFUSE',
        };
        }
        _derniereCopieAvantRecuperation =
            await _creerCopieSecuriteLocale('avant_recuperation');
        schoolCode = normalizedCode;

        // ⚡ ÉTAPE 5 — résumé avant / serveur / après + contrôle
        final avant = resumeSynchronisation();
        final base = _syncBaseResume == null
            ? null
            : Map<String, num>.from(_syncBaseResume!);
        final serveurResume = FraisScolairesServices.resumeDepuisJson(
            data as Map<String, dynamic>);
        final doublonsAvant = _clesDoublonsEleves(history);
        final doublonsServeur = _clesDoublonsEleves(_historiqueDepuisJson(data));

        await mergeRestoredData(data);
        await saveData();

        final apres = resumeSynchronisation();
        final anomalies = controlerFusion(
          avant: avant,
          serveur: serveurResume,
          base: base,
          apres: apres,
          doublonsAvant: doublonsAvant,
          doublonsServeur: doublonsServeur,
          doublonsApres: _clesDoublonsEleves(history),
        );
        final bool bloquant =
        anomalies.any((a) => a['niveau'] == 'bloquant');
        return {
          'success': true,
          'warnings': List<String>.from(dernierAvertissementsFusion),
          'resume': {'avant': avant, 'serveur': serveurResume, 'apres': apres},
          'anomalies': anomalies,
          'bloquant': bloquant,
        };
      }
      if (response.statusCode == 401) {
        return {
          'success': false,
          'error': 'Mot de passe incorrect',
          'code': 'MOT_DE_PASSE_REFUSE',
        };
      }
      if (response.statusCode == 404) {
        return {
          'success': false,
          'notFound': true,
          'error':
          'Aucune sauvegarde trouvée pour le code "$normalizedCode". '
              'Vérifiez que ce code est exactement celui utilisé lors '
              'du dernier "Sauvegarder sur le Serveur".',
        };
      }
      return {
        'success': false,
        'error':
        'Le serveur a répondu avec le statut ${response.statusCode} : '
            '${response.body}',
      };
    } on SocketException catch (e) {
      return {
        'success': false,
        'error': 'Aucune connexion réseau (vérifiez internet / pare-feu) : $e',
      };
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  Future<Map<String, dynamic>> checkSchoolCodeExists(
      String schoolCodeParam) async {
    final normalizedCode = schoolCodeParam.trim().toUpperCase();
    try {
      final response = await http
          .get(Uri.parse(
          '$serverUrl/restore?school_code=$normalizedCode&exists_only=1'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final name = (data['config']?['schoolName'] ?? '') as String;
        return {'exists': true, 'schoolName': name};
      }
      if (response.statusCode == 404) {
        return {'exists': false, 'error': 'Aucune école trouvée avec ce code.'};
      }
      return {
        'exists': false,
        'error': 'Statut HTTP ${response.statusCode} : ${response.body}',
      };
    } catch (e) {
      return {'exists': false, 'error': 'Erreur réseau : $e'};
    }
  }

  String _syncCanon(dynamic v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return '{${keys.map((k) => '${json.encode(k)}:${_syncCanon(v[k])}').join(',')}}';
    }
    if (v is List) {
      return '[${v.map(_syncCanon).join(',')}]';
    }
    return json.encode(v);
  }

  Map<String, Set<String>> _syncIdsDepuisEtatLocal() {
    final eleves = <String>{};
    final tx = <String>{};
    final dep = <String>{};
    final ent = <String>{};
    final sig = <String>{};
    final adm = <String>{};
    for (final y in history.values) {
      for (final e in y.eleves) {
        if (e.id.isNotEmpty) eleves.add(e.id);
        for (final t in e.transactions) {
          final tid = t['id']?.toString().trim() ?? '';
          if (tid.isNotEmpty) tx.add(tid);
        }
      }
    }
    for (final liste in depensesByYear.values) {
      for (final d in liste) {
        final id = d.id.toString();
        if (id.isNotEmpty) dep.add(id);
      }
    }
    for (final liste in entreesByYear.values) {
      for (final e in liste) {
        final id = e.id.toString();
        if (id.isNotEmpty) ent.add(id);
      }
    }
    for (final s in signataires) {
      final id = s.id.toString();
      if (id.isNotEmpty) sig.add(id);
    }
    for (final a in autresFraisAdministrations) {
      final id = a.id.toString();
      if (id.isNotEmpty) adm.add(id);
    }
    return {
      'eleves': eleves,
      'tx': tx,
      'depenses': dep,
      'entrees': ent,
      'signataires': sig,
      'admins': adm,
      'infos': {
        for (final y in history.values)
          for (final e in y.eleves)
            if (e.id.isNotEmpty) '${e.id}|${_syncEmpreinteInfos(e)}',
      },
      'afp': {
        for (final l in autresFraisPaiementsByYear.values)
          for (final p in l)
            if (p.id.isNotEmpty) '${p.id}|${_syncEmpreinteAfp(p)}',
      },
    };
  }

  // ⚡ ÉTAPE 4 — EMPREINTES DES MODIFICATIONS
  // À chaque synchronisation, on garde l'empreinte des infos de chaque élève
  // et de chaque paiement « autres frais ». À la fusion suivante, on sait
  // ainsi QUI a modifié : cet ordinateur, le serveur (un autre ordinateur),
  // ou les deux.
  String _syncEmpreinte(String s) =>
      sha1.convert(utf8.encode(s)).toString().substring(0, 16);

  String _syncEmpreinteInfos(Eleve e) {
    final champs = e.customFields.keys.toList()..sort();
    return _syncEmpreinte(json.encode([
      e.nom, e.postNom, e.prenom, e.pereNom, e.mereNom, e.adresse,
      e.dateNaissance, e.photoBase64 ?? '',
      [for (final k in champs) [k, e.customFields[k]]],
    ]));
  }

  String _syncEmpreinteAfp(AutreFraisPaiement p) =>
      _syncEmpreinte(json.encode(p.toJson()));

  Map<String, String> _syncLireEmpreintes(Set<String>? entrees) {
    final m = <String, String>{};
    for (final x in entrees ?? const <String>{}) {
      final i = x.lastIndexOf('|');
      if (i > 0) m[x.substring(0, i)] = x.substring(i + 1);
    }
    return m;
  }

  Map<String, Set<String>> _syncIdsDepuisServeur(Map<String, dynamic> d) {
    final eleves = <String>{};
    final tx = <String>{};
    final dep = <String>{};
    final ent = <String>{};
    final sig = <String>{};
    final adm = <String>{};

    final h = d['history'];
    if (h is Map) {
      for (final y in h.values) {
        if (y is Map && y['eleves'] is List) {
          for (final e in (y['eleves'] as List)) {
            if (e is! Map) continue;
            final id = e['id']?.toString() ?? '';
            if (id.isNotEmpty) eleves.add(id);
            final t = e['transactions'];
            if (t is List) {
              for (final x in t) {
                if (x is Map) {
                  final tid = x['id']?.toString().trim() ?? '';
                  if (tid.isNotEmpty) tx.add(tid);
                }
              }
            }
          }
        }
      }
    }
    final dp = d['depensesByYear'];
    if (dp is Map) {
      for (final l in dp.values) {
        if (l is List) {
          for (final x in l) {
            if (x is Map) {
              final id = x['id']?.toString() ?? '';
              if (id.isNotEmpty) dep.add(id);
            }
          }
        }
      }
    }
    final ey = d['entreesByYear'];
    if (ey is Map) {
      for (final l in ey.values) {
        if (l is List) {
          for (final x in l) {
            if (x is Map) {
              final id = x['id']?.toString() ?? '';
              if (id.isNotEmpty) ent.add(id);
            }
          }
        }
      }
    }
    final sg = d['signataires'];
    if (sg is List) {
      for (final x in sg) {
        if (x is Map) {
          final id = x['id']?.toString() ?? '';
          if (id.isNotEmpty) sig.add(id);
        }
      }
    }
    final ad = d['autresFraisAdministrations'];
    if (ad is List) {
      for (final x in ad) {
        if (x is Map) {
          final id = x['id']?.toString() ?? '';
          if (id.isNotEmpty) adm.add(id);
        }
      }
    }
    final infos = <String>{};
    if (h is Map) {
      for (final y in h.values) {
        if (y is Map && y['eleves'] is List) {
          for (final e in (y['eleves'] as List)) {
            if (e is! Map) continue;
            try {
              final el = Eleve.fromJson(Map<String, dynamic>.from(e));
              if (el.id.isNotEmpty) {
                infos.add('${el.id}|${_syncEmpreinteInfos(el)}');
              }
            } catch (_) {}
          }
        }
      }
    }
    final afp = <String>{};
    final ap = d['autresFraisPaiementsByYear'];
    if (ap is Map) {
      for (final l in ap.values) {
        if (l is List) {
          for (final x in l) {
            if (x is! Map) continue;
            try {
              final p =
              AutreFraisPaiement.fromJson(Map<String, dynamic>.from(x));
              if (p.id.isNotEmpty) afp.add('${p.id}|${_syncEmpreinteAfp(p)}');
            } catch (_) {}
          }
        }
      }
    }
    return {
      'eleves': eleves,
      'tx': tx,
      'depenses': dep,
      'entrees': ent,
      'signataires': sig,
      'admins': adm,
      'infos': infos,
      'afp': afp,
    };
  }

  String _syncNorm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _cleNomEleve(Eleve e) =>
      "${_syncNorm(e.nom)}_${_syncNorm(e.postNom)}_${_syncNorm(e.prenom)}";

  Set<String> _syncJetonsNom(Eleve e) {
    return '${e.nom} ${e.postNom} ${e.prenom}'
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  bool _syncMemeIdentite(Eleve a, Eleve b) {
    final ja = _syncJetonsNom(a);
    final jb = _syncJetonsNom(b);
    if (ja.isEmpty || jb.isEmpty) return true;
    return ja.containsAll(jb) || jb.containsAll(ja);
  }

  bool _syncVide(dynamic v) => v == null || v.toString().trim().isEmpty;

  // ⚡ Vrai si les deux fiches ont au moins une transaction en commun (même
  // identifiant) : c'est alors le même enfant, même si le nom a été corrigé.
  bool _syncPartagentUnPaiement(Eleve a, Eleve b) {
    final ids = a.transactions
        .map((t) => t['id']?.toString().trim() ?? '')
        .where((i) => i.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return false;
    return b.transactions
        .any((t) => ids.contains(t['id']?.toString().trim() ?? ''));
  }

  // ⚡ Donne un nouvel ID à un élève de CET ordinateur (pendant une fusion,
  // avant que les données du serveur ne soient ajoutées) : ses fiches des
  // autres années, son éventuelle archive, ses paiements « autres frais » et
  // ses reçus en attente le suivent.
  void _syncRenommerEleveLocal(Eleve l, String nouveau) {
    final String ancien = l.id;
    for (final y in history.values) {
      for (final e in y.eleves) {
        if (e.id == ancien && (identical(e, l) || _syncMemeIdentite(e, l))) {
          e.id = nouveau;
        }
      }
    }
    for (final e in elevesSupprimesData.eleves) {
      if (e.id == ancien && _syncMemeIdentite(e, l)) e.id = nouveau;
    }
    l.id = nouveau;
    final remap = <String, String>{ancien: nouveau};
    for (final liste in autresFraisPaiementsByYear.values) {
      for (final p in liste) {
        _syncRemapperEleveIdPaiement(p, remap);
      }
    }
    for (var i = 0; i < receiptQueue.length; i++) {
      final r = receiptQueue[i];
      if (r['eleveId'] == ancien) receiptQueue[i] = {...r, 'eleveId': nouveau};
    }
  }

  void _syncCopierInfosEleve(Eleve l, Eleve s) {
    final dynamic dl = l;
    final dynamic ds = s;
    try {
      if (_syncVide(dl.pereNom) && !_syncVide(ds.pereNom)) {
        dl.pereNom = ds.pereNom;
      }
    } catch (_) {}
    try {
      if (_syncVide(dl.mereNom) && !_syncVide(ds.mereNom)) {
        dl.mereNom = ds.mereNom;
      }
    } catch (_) {}
    try {
      if (_syncVide(dl.adresse) && !_syncVide(ds.adresse)) {
        dl.adresse = ds.adresse;
      }
    } catch (_) {}
    try {
      if (_syncVide(dl.dateNaissance) && !_syncVide(ds.dateNaissance)) {
        dl.dateNaissance = ds.dateNaissance;
      }
    } catch (_) {}
    try {
      if (_syncVide(dl.photoBase64) && !_syncVide(ds.photoBase64)) {
        dl.photoBase64 = ds.photoBase64;
      }
    } catch (_) {}
    try {
      final dynamic cs = ds.customFields;
      final dynamic cl = dl.customFields;
      if (cs is Map && cl is Map) {
        cs.forEach((k, v) {
          if (!cl.containsKey(k) || _syncVide(cl[k])) cl[k] = v;
        });
      }
    } catch (_) {}
  }

  void _syncRemapperEleveIdPaiement(
      AutreFraisPaiement p, Map<String, String> remap) {
    if (remap.isEmpty) return;
    try {
      final dynamic d = p;
      final String ancien = d.eleveId.toString();
      if (remap.containsKey(ancien)) d.eleveId = remap[ancien];
    } catch (_) {}
  }

  List<T> _syncFusionnerListeParId<T>({
    required List<T> locale,
    required List<T> serveur,
    required String Function(T) idDe,
    required Set<String> base,
  }) {
    final idsLocaux =
    locale.map(idDe).where((i) => i.isNotEmpty).toSet();
    final idsServeur =
    serveur.map(idDe).where((i) => i.isNotEmpty).toSet();
    final bool localVide = locale.isEmpty;
    final resultat = <T>[];
    for (final l in locale) {
      final id = idDe(l);
      if (id.isNotEmpty && base.contains(id) && !idsServeur.contains(id)) {
        continue;
      }
      resultat.add(l);
    }
    for (final s in serveur) {
      final id = idDe(s);
      if (id.isEmpty || idsLocaux.contains(id)) continue;
      if (!localVide && base.contains(id)) continue;
      resultat.add(s);
    }
    return resultat;
  }

  String _signatureTransaction(Map<String, dynamic> t) {
    final double montant = (t['amount'] as num?)?.toDouble() ?? 0.0;
    return '${t['date'] ?? ''}|${t['mois'] ?? ''}|${montant.toStringAsFixed(2)}';
  }

  void _syncAppliquerDateSiPlusRecente(
      Map<String, dynamic> cible, Map<String, dynamic> source) {
    final DateTime? dateSource =
    DateTime.tryParse(source['dateModifieeLe']?.toString() ?? '');
    if (dateSource == null) return;
    final DateTime? dateCible =
    DateTime.tryParse(cible['dateModifieeLe']?.toString() ?? '');
    if (dateCible != null && !dateSource.isAfter(dateCible)) return;
    if (source['date'] != null) cible['date'] = source['date'];
    cible['dateModifieeLe'] = source['dateModifieeLe'];
    if (source['dateOriginale'] != null) {
      cible['dateOriginale'] = source['dateOriginale'];
    }
  }

  List<Map<String, dynamic>> _fusionnerTransactionsSansDoublons(
      List<Map<String, dynamic>> locales,
      List<Map<String, dynamic>> serveur, {
        Set<String>? base,
      }) {
    final Set<String> b = base ?? <String>{};
    String idDe(Map<String, dynamic> t) => t['id']?.toString().trim() ?? '';
    final idsLocaux = locales.map(idDe).where((i) => i.isNotEmpty).toSet();
    final idsServeur = serveur.map(idDe).where((i) => i.isNotEmpty).toSet();

    final Map<String, Map<String, dynamic>> parId = {};
    final Set<String> signaturesAvecIdLegacy = {};
    final List<Map<String, dynamic>> sansId = [];

    void classer(Map<String, dynamic> t) {
      final String tid = idDe(t);
      if (tid.isNotEmpty) {
        if (!parId.containsKey(tid)) {
          parId[tid] = t;
          if (tid.startsWith('LEG_')) {
            signaturesAvecIdLegacy.add(_signatureTransaction(t));
          }
        }
      } else {
        sansId.add(t);
      }
    }

    for (final t in locales) {
      final id = idDe(t);
      if (id.isNotEmpty && b.contains(id) && !idsServeur.contains(id)) {
        continue;
      }
      classer(Map<String, dynamic>.from(t));
    }
    for (final t in serveur) {
      final id = idDe(t);
      if (id.isNotEmpty && b.contains(id) && !idsLocaux.contains(id)) {
        continue;
      }
      if (id.isNotEmpty && parId.containsKey(id)) {
        _syncAppliquerDateSiPlusRecente(parId[id]!, t);
        continue;
      }
      classer(Map<String, dynamic>.from(t));
    }

    final List<Map<String, dynamic>> resultat = parId.values.toList();
    final Set<String> signaturesSansIdVues = {};
    for (final t in sansId) {
      final String sig = _signatureTransaction(t);
      if (signaturesAvecIdLegacy.contains(sig)) continue;
      if (signaturesSansIdVues.contains(sig)) continue;
      signaturesSansIdVues.add(sig);
      resultat.add(t);
    }

    resultat.sort((a, b) => (a['date'] ?? '')
        .toString()
        .compareTo((b['date'] ?? '').toString()));
    return resultat;
  }

  // ⚡ ÉTAPE 4 — infos d'un élève (noms, parents, adresse, naissance, photo,
  // champs libres) : la version modifiée gagne.
  void _syncFusionnerInfos(Eleve l, Eleve s, String? empreinteBase) {
    final String hl = _syncEmpreinteInfos(l);
    final String hs = _syncEmpreinteInfos(s);
    if (hl == hs) return;
    if (empreinteBase != null && hl == empreinteBase) {
      // Seul le serveur (un autre ordinateur) a modifié : on prend tout.
      l
        ..nom = s.nom
        ..postNom = s.postNom
        ..prenom = s.prenom
        ..pereNom = s.pereNom
        ..mereNom = s.mereNom
        ..adresse = s.adresse
        ..dateNaissance = s.dateNaissance
        ..photoBase64 = s.photoBase64
        ..customFields = Map<String, String>.from(s.customFields);
      return;
    }
    if (empreinteBase != null && hs == empreinteBase) {
      return; // seul cet ordinateur a modifié : il l'enverra
    }
    // Modifié des deux côtés (ou première synchronisation) : on garde cet
    // ordinateur et on complète seulement les champs vides.
    _syncCopierInfosEleve(l, s);
    if (empreinteBase != null && _syncEmpreinteInfos(l) != hs) {
      dernierAvertissementsFusion.add(
          "Les informations de ${l.nom} ${l.postNom} ${l.prenom} (${l.id}) "
              "ont été modifiées sur cet ordinateur ET sur un autre : la "
              "version de cet ordinateur a été gardée. Vérifiez sa fiche.");
    }
  }

  bool _syncFusionnerEleve(
      Eleve localEleve, Eleve serverEleve, Set<String> baseTx,
      [Map<String, String> baseInfos = const {}]) {
    if (localEleve.id.isEmpty && serverEleve.id.isNotEmpty) {
      localEleve.id = serverEleve.id;
    }
    if (serverEleve.classe.isNotEmpty) localEleve.classe = serverEleve.classe;
    if (serverEleve.section.isNotEmpty) {
      localEleve.section = serverEleve.section;
    }
    localEleve.montantMensuelPersonnalise =
        serverEleve.montantMensuelPersonnalise ??
            localEleve.montantMensuelPersonnalise;
    if (serverEleve.exceptionsMoisPersonnalisees.isNotEmpty) {
      serverEleve.exceptionsMoisPersonnalisees.forEach((m, v) {
        localEleve.exceptionsMoisPersonnalisees.putIfAbsent(m, () => v);
      });
    }
    localEleve.moisDebloque ??= serverEleve.moisDebloque;

    _syncFusionnerInfos(
        localEleve, serverEleve, baseInfos[serverEleve.id]);

    final List<Map<String, dynamic>> txLocales =
    List<Map<String, dynamic>>.from(localEleve.transactions);
    final List<Map<String, dynamic>> txServeur =
    List<Map<String, dynamic>>.from(serverEleve.transactions);

    final Set<String> moisAvecTx = {};
    for (final t in [...txLocales, ...txServeur]) {
      final m = t['mois']?.toString() ?? '';
      if (m.isNotEmpty) moisAvecTx.add(m);
    }

    final Map<String, double> paidAvantFusion =
    Map<String, double>.from(localEleve.paid);
    serverEleve.paid.forEach((m, v) {
      if (v > (paidAvantFusion[m] ?? 0)) paidAvantFusion[m] = v;
    });

    final List<Map<String, dynamic>> mergedTransactions =
    _fusionnerTransactionsSansDoublons(txLocales, txServeur, base: baseTx);

    String idDe(Map<String, dynamic> t) => t['id']?.toString().trim() ?? '';
    final idsL = txLocales.map(idDe).where((i) => i.isNotEmpty).toSet();
    final idsS = txServeur.map(idDe).where((i) => i.isNotEmpty).toSet();
    final bool lesDeuxOntAjoute = idsS.any((i) => !idsL.contains(i)) &&
        idsL.any((i) => !idsS.contains(i));

    localEleve.transactions
      ..clear()
      ..addAll(mergedTransactions);

    final Map<String, double> paidReconstruit = {};
    for (final t in mergedTransactions) {
      final mois = t['mois']?.toString() ?? '';
      if (mois.isEmpty) continue;
      final montant = (t['amount'] as num?)?.toDouble() ?? 0.0;
      paidReconstruit[mois] = (paidReconstruit[mois] ?? 0) + montant;
    }
    for (final mois in paidAvantFusion.keys) {
      if (!moisAvecTx.contains(mois) && (paidAvantFusion[mois] ?? 0) > 0) {
        paidReconstruit[mois] = paidAvantFusion[mois]!;
      }
    }
    localEleve.paid
      ..clear()
      ..addAll(paidReconstruit);

    if (lesDeuxOntAjoute) {
      for (final entry in paidReconstruit.entries) {
        try {
          final double requis =
          getRequiredForMonthForEleve(localEleve, entry.key);
          if (entry.value > requis + 0.5) return true;
        } catch (_) {}
      }
    }
    return false;
  }

  Future<void> mergeRestoredData(Map<String, dynamic> serverData) async {
    dernierAvertissementsFusion = <String>[];
    final Set<String> baseTx = _syncBase['tx'] ?? <String>{};
    final Map<String, String> baseInfos =
    _syncLireEmpreintes(_syncBase['infos']);
    final Map<String, String> baseAfp = _syncLireEmpreintes(_syncBase['afp']);
    final Set<String> baseDepenses = _syncBase['depenses'] ?? <String>{};
    final Set<String> baseEntrees = _syncBase['entrees'] ?? <String>{};
    final Set<String> baseSignataires = _syncBase['signataires'] ?? <String>{};
    final Set<String> baseAdmins = _syncBase['admins'] ?? <String>{};

    final bool localEtaitVide =
    history.values.every((y) => y.eleves.isEmpty);

    final SchoolConfig serverConfig =
    SchoolConfig.fromJson(serverData['config'] ?? {});
    final String cfgServeur = _syncCanon(serverConfig.toJson());
    final String cfgLocale = _syncCanon(config.toJson());
    if (_syncBaseConfigJson == null || cfgServeur != _syncBaseConfigJson) {
      if (_syncBaseConfigJson != null &&
          cfgLocale != _syncBaseConfigJson &&
          cfgLocale != cfgServeur) {
        dernierAvertissementsFusion.add(
            "La configuration (frais, sections, classes) a été modifiée sur "
                "cet ordinateur ET sur un autre : la version du serveur a été "
                "conservée. Vérifiez les frais dans Paramètres.");
      }
      config = serverConfig;
    }

    if (serverData['localIdCounter'] != null) {
      final serverCounter = serverData['localIdCounter'] as int;
      if (serverCounter > _localIdCounter) {
        _localIdCounter = serverCounter;
      }
    }

    if (serverData['paiementsAutresFraisAnnules'] != null) {
      for (final e in (serverData['paiementsAutresFraisAnnules']
      as List<dynamic>)) {
        paiementsAutresFraisAnnules.add(e.toString());
      }
    }
    if (serverData['autresFraisSupprimesIds'] != null) {
      for (final e in (serverData['autresFraisSupprimesIds']
      as List<dynamic>)) {
        autresFraisSupprimesIds.add(e.toString());
      }
    }

    final Set<String> idsArchiveLocal = elevesSupprimesData.eleves
        .map((e) => e.id)
        .where((i) => i.isNotEmpty)
        .toSet();
    SchoolYearData? serverArchive;
    if (serverData['elevesSupprimesData'] != null) {
      serverArchive = SchoolYearData.fromJson(serverData['elevesSupprimesData']);
    }
    final Set<String> idsArchiveServer = serverArchive == null
        ? <String>{}
        : serverArchive.eleves
        .map((e) => e.id)
        .where((i) => i.isNotEmpty)
        .toSet();

    final Map<String, String> idRemap = {};
    bool besoinRecalcul = false;

    if (serverData['history'] != null) {
      final serverHistory =
      (serverData['history'] as Map<String, dynamic>).map(
            (key, value) =>
            MapEntry(key, SchoolYearData.fromJson(value)),
      );

      final Set<String> idsServeurToutesAnnees = {
        for (final y in serverHistory.values)
          for (final e in y.eleves)
            if (e.id.isNotEmpty) e.id,
      };

      for (var entry in serverHistory.entries) {
        final year           = entry.key;
        final serverYearData = entry.value;

        if (!history.containsKey(year)) {
          serverYearData.eleves.removeWhere(
                  (e) => e.id.isNotEmpty && idsArchiveLocal.contains(e.id));
          history[year] = serverYearData;
          continue;
        }

        final localEleves = history[year]!.eleves;
        final Set<String> idsServeurAnnee = serverYearData.eleves
            .map((e) => e.id)
            .where((i) => i.isNotEmpty)
            .toSet();

        if (idsArchiveServer.isNotEmpty) {
          final aArchiver = localEleves
              .where((l) =>
          l.id.isNotEmpty &&
              idsArchiveServer.contains(l.id) &&
              !idsServeurAnnee.contains(l.id))
              .toList();
          for (final l in aArchiver) {
            localEleves.remove(l);
            if (!idsArchiveLocal.contains(l.id)) {
              elevesSupprimesData.eleves.add(l);
              idsArchiveLocal.add(l.id);
            }
          }
        }

        final List<Eleve> instantane = List<Eleve>.from(localEleves);
        final List<bool> pris = List<bool>.filled(instantane.length, false);

        for (final s in serverYearData.eleves) {
          if (s.id.isNotEmpty && idsArchiveLocal.contains(s.id)) continue;

          int idx = -1;
          if (s.id.isNotEmpty) {
            idx = instantane.indexWhere((l) => l.id == s.id);
          }
          if (idx != -1) {
            final l = instantane[idx];
            // ⚡ Même ID, noms différents et aucun paiement en commun : ce
            // sont deux enfants différents (ID fabriqué en double par deux
            // ordinateurs). On ne les fusionne JAMAIS (avant : les paiements
            // de l'un passaient à l'autre). L'élève du serveur garde son ID ;
            // l'élève de CET ordinateur reçoit un nouvel ID, pour que tous
            // les ordinateurs finissent avec les mêmes identifiants.
            if (!_syncMemeIdentite(l, s) && !_syncPartagentUnPaiement(l, s)) {
              final String ancien = l.id;
              final String nouveau = generateLocalStudentId(l.nom,
                  idsReserves: idsServeurToutesAnnees);
              _syncRenommerEleveLocal(l, nouveau);
              localEleves.add(s);
              dernierAvertissementsFusion.add(
                  "Deux élèves différents avaient le même ID ($ancien) : "
                      "${l.nom} ${l.postNom} ${l.prenom} (saisi sur cet "
                      "ordinateur) a reçu le nouvel ID $nouveau ; "
                      "${s.nom} ${s.postNom} ${s.prenom} garde l'ID $ancien.");
              continue;
            }
            pris[idx] = true;
            if (_syncFusionnerEleve(l, s, baseTx, baseInfos)) {
              besoinRecalcul = true;
            }
            continue;
          }

          final String cle = _cleNomEleve(s);
          idx = -1;
          for (int i = 0; i < instantane.length; i++) {
            if (pris[i]) continue;
            if (idsServeurAnnee.contains(instantane[i].id)) continue;
            if (_cleNomEleve(instantane[i]) == cle) {
              idx = i;
              break;
            }
          }
          if (idx != -1) {
            pris[idx] = true;
            final l = instantane[idx];
            if (s.id.isNotEmpty && s.id != l.id) idRemap[s.id] = l.id;
            if (_syncFusionnerEleve(l, s, baseTx, baseInfos)) {
              besoinRecalcul = true;
            }
            continue;
          }

          localEleves.add(s);
        }
      }
    }

    if (serverArchive != null) {
      for (final e in serverArchive.eleves) {
        if (e.id.isEmpty || !idsArchiveLocal.contains(e.id)) {
          elevesSupprimesData.eleves.add(e);
          if (e.id.isNotEmpty) idsArchiveLocal.add(e.id);
        }
      }
    }
    if (serverData['dateSuppressionEleves'] != null) {
      (serverData['dateSuppressionEleves'] as Map<String, dynamic>)
          .forEach((key, value) {
        dateSuppressionEleves.putIfAbsent(key, () => value.toString());
      });
    }
    if (serverData['motifSuppressionEleves'] != null) {
      (serverData['motifSuppressionEleves'] as Map<String, dynamic>)
          .forEach((key, value) {
        motifSuppressionEleves.putIfAbsent(key, () => value.toString());
      });
    }

    if (serverData['depensesByYear'] != null) {
      final serverDepenses =
      (serverData['depensesByYear'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map((e) => Depense.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );

      for (var entry in serverDepenses.entries) {
        final year       = entry.key;
        final serverList = entry.value;

        if (depensesByYear.containsKey(year)) {
          depensesByYear[year] = _syncFusionnerListeParId<Depense>(
            locale: depensesByYear[year]!,
            serveur: serverList,
            idDe: (d) => d.id.toString(),
            base: baseDepenses,
          );
        } else {
          depensesByYear[year] = serverList;
        }
      }
    }

    // ⚡ NOUVEAU — entrées d'argent : fusion par id comme les dépenses, avec
    // une garde supplémentaire : une entrée annulée sur CET ordinateur OU sur
    // le serveur reste annulée après la fusion (la fusion par id garde par
    // défaut l'objet LOCAL quand l'id existe des deux côtés, ce qui pourrait
    // sinon "oublier" une annulation faite ailleurs).
    if (serverData['entreesByYear'] != null) {
      final serverEntrees =
      (serverData['entreesByYear'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map((e) => Entree.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );

      for (var entry in serverEntrees.entries) {
        final year       = entry.key;
        final serverList = entry.value;

        final Map<String, Entree> annuleesConnues = {};
        for (final e in (entreesByYear[year] ?? [])) {
          if (e.annulee && e.id.isNotEmpty) annuleesConnues[e.id] = e;
        }
        for (final e in serverList) {
          if (e.annulee &&
              e.id.isNotEmpty &&
              !annuleesConnues.containsKey(e.id)) {
            annuleesConnues[e.id] = e;
          }
        }

        if (entreesByYear.containsKey(year)) {
          entreesByYear[year] = _syncFusionnerListeParId<Entree>(
            locale: entreesByYear[year]!,
            serveur: serverList,
            idDe: (e) => e.id.toString(),
            base: baseEntrees,
          );
        } else {
          entreesByYear[year] = serverList;
        }

        if (annuleesConnues.isNotEmpty) {
          for (final e in entreesByYear[year]!) {
            final ref = annuleesConnues[e.id];
            if (ref != null && !e.annulee) {
              e.annulee = true;
              e.dateAnnulation = ref.dateAnnulation;
              e.motifAnnulation = ref.motifAnnulation;
            }
          }
        }
      }
    }

    if (serverData['autresFrais'] != null) {
      final serverAutresFrais = (serverData['autresFrais'] as List<dynamic>)
          .map((e) => AutreFrais.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingFraisIds = autresFrais.map((f) => f.id).toSet();
      for (var f in serverAutresFrais) {
        if (autresFraisSupprimesIds.contains(f.id)) continue;
        if (!existingFraisIds.contains(f.id)) {
          autresFrais.add(f);
        } else {
          for (final local in autresFrais) {
            if (local.id != f.id) continue;
            f.tranchesParCle.forEach((cle, liste) {
              if (!local.tranchesParCle.containsKey(cle)) {
                local.tranchesParCle[cle] = liste;
              }
            });
            break;
          }
        }
      }
    }
    autresFrais.removeWhere((f) => autresFraisSupprimesIds.contains(f.id));

    if (serverData['autresFraisPaiementsByYear'] != null) {
      final serverPaiements = (serverData['autresFraisPaiementsByYear']
      as Map<String, dynamic>)
          .map(
            (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map((e) =>
              AutreFraisPaiement.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );

      for (var entry in serverPaiements.entries) {
        final year       = entry.key;
        final serverList = entry.value
            .where((p) =>
        !paiementsAutresFraisAnnules.contains(p.id) &&
            !autresFraisSupprimesIds.contains(p.autreFraisId))
            .toList();

        for (final p in serverList) {
          _syncRemapperEleveIdPaiement(p, idRemap);
        }

        if (autresFraisPaiementsByYear.containsKey(year)) {
          final locaux = autresFraisPaiementsByYear[year]!;
          final existingIds = locaux.map((p) => p.id).toSet();
          for (var p in serverList) {
            if (!existingIds.contains(p.id)) {
              locaux.add(p);
              continue;
            }
            // ⚡ ÉTAPE 4 — paiement modifié (montant...) sur un autre
            // ordinateur et pas sur celui-ci : on prend la version du serveur.
            final String? hBase = baseAfp[p.id];
            if (hBase == null) continue;
            final i = locaux.indexWhere((x) => x.id == p.id);
            if (i < 0) continue;
            final String hLocal = _syncEmpreinteAfp(locaux[i]);
            final String hServeur = _syncEmpreinteAfp(p);
            if (hLocal == hBase && hServeur != hBase) {
              locaux[i] = p;
            } else if (hLocal != hBase &&
                hServeur != hBase &&
                hLocal != hServeur) {
              dernierAvertissementsFusion.add(
                  "Un paiement « ${p.autreFraisNom} » a été modifié sur cet "
                      "ordinateur ET sur un autre : la version de cet "
                      "ordinateur a été gardée (${locaux[i].montant.toStringAsFixed(0)} FC).");
            }
          }
        } else {
          autresFraisPaiementsByYear[year] = serverList;
        }
      }

      for (final liste in autresFraisPaiementsByYear.values) {
        liste.removeWhere((p) =>
        paiementsAutresFraisAnnules.contains(p.id) ||
            autresFraisSupprimesIds.contains(p.autreFraisId));
      }
    }

    if (serverData['autresFraisAdministrations'] != null) {
      final serverAutresFraisAdmins =
      (serverData['autresFraisAdministrations'] as List<dynamic>)
          .map((e) =>
          AutreFraisAdministration.fromJson(e as Map<String, dynamic>))
          .toList();
      autresFraisAdministrations =
          _syncFusionnerListeParId<AutreFraisAdministration>(
            locale: autresFraisAdministrations,
            serveur: serverAutresFraisAdmins,
            idDe: (a) => a.id.toString(),
            base: baseAdmins,
          );
    }

    if (serverData['adminAuditLog'] != null) {
      final serverAudit = (serverData['adminAuditLog'] as List<dynamic>)
          .map((e) => AdminAuditLog.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingAuditIds = adminAuditLog.map((a) => a.id).toSet();
      for (var a in serverAudit) {
        if (!existingAuditIds.contains(a.id)) {
          adminAuditLog.add(a);
        }
      }
    }

    if (serverData['signataires'] != null) {
      final serverSignataires = (serverData['signataires'] as List<dynamic>)
          .map((e) => Signataire.fromJson(e as Map<String, dynamic>))
          .toList();
      signataires = _syncFusionnerListeParId<Signataire>(
        locale: signataires,
        serveur: serverSignataires,
        idDe: (s) => s.id.toString(),
        base: baseSignataires,
      );
    }

    if (serverData['optionsSections'] != null) {
      final serverOptions = _parseOptionsSections(serverData['optionsSections']);
      serverOptions.forEach((nom, secs) {
        if (optionsSections.containsKey(nom)) return;
        final dejaUtilisees = optionsSections.values.expand((l) => l).toSet();
        optionsSections[nom] =
            secs.where((s) => !dejaUtilisees.contains(s)).toList();
      });
    }
    _nettoyerOptions();

    if (serverData['printedReceiptKeys'] != null) {
      final serverKeys = (serverData['printedReceiptKeys'] as List<dynamic>)
          .map((e) => e.toString());
      for (var k in serverKeys) {
        if (!printedReceiptKeys.contains(k)) {
          printedReceiptKeys.add(k);
        }
      }
    }
    if (serverData['receiptQueue'] != null) {
      final serverQueue = (serverData['receiptQueue'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map));
      for (var item in serverQueue) {
        final key = item['key']?.toString() ?? '';
        if (key.isEmpty || printedReceiptKeys.contains(key)) continue;
        final alreadyQueued = receiptQueue.any((r) => r['key'] == key);
        if (!alreadyQueued) {
          receiptQueue.add(item);
        }
      }
    }

    final String anneeServeur =
        serverData['currentYear']?.toString() ?? currentYear;
    if (localEtaitVide) currentYear = anneeServeur;
    if (history.containsKey(currentYear)) {
      currentData = history[currentYear]!;
    } else {
      currentData          = SchoolYearData(eleves: []);
      history[currentYear] = currentData;
    }

    await _assignMissingIds();

    if (besoinRecalcul) {
      try {
        await recalculerPaiementsPour();
        dernierAvertissementsFusion.add(
            "Des paiements du même mois avaient été saisis sur deux "
                "ordinateurs : la répartition par mois a été recalculée "
                "(aucun montant n'a été perdu ni ajouté).");
      } catch (_) {}
    }

    final dynamic rev = serverData['revision'] ?? serverData['_revision'];
    if (rev is num) _syncServerRevision = rev.toInt();
    _syncBase = _syncIdsDepuisServeur(serverData);
    _syncBaseResume = FraisScolairesServices.resumeDepuisJson(serverData);
    _syncBaseConfigJson = cfgServeur;
    _localLoadFailed = false;
  }

  Future<Map<String, dynamic>> recordAbsences({
    required List<String> absentIds,
    required String classe,
    required String section,
    String? date,
    String? message,
    String recordedBy = 'Direction',
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {
        'success': false,
        'error': "Code école manquant. Sauvegardez d'abord sur le serveur "
            "(Paramètres) avant d'utiliser le module Discipline.",
      };
    }
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/school/record_absences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCode,
          'annee':       currentYear,
          'classe':      classe,
          'section':     section,
          'date':        date ?? DateTime.now().toString().split(' ')[0],
          'absent_ids':  absentIds,
          'message':     message ?? '',
          'recorded_by': recordedBy,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'notified_count': data['notified_count'] ?? 0,
        };
      }
      return {
        'success': false,
        'error': 'Statut ${response.statusCode} : ${response.body}',
      };
    } on SocketException catch (e) {
      return {'success': false, 'error': 'Aucune connexion réseau : $e'};
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  Future<Map<String, dynamic>> getAttendance({
    required String classe,
    String? date,
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {'success': false, 'absents': <String>[]};
    }
    try {
      final dateStr = date ?? DateTime.now().toString().split(' ')[0];
      final response = await http.get(
        Uri.parse('$serverUrl/school/get_attendance'
            '?school_code=$schoolCode&date=$dateStr'
            '&classe=${Uri.encodeComponent(classe)}'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'absents': List<String>.from(data['absents'] ?? []),
        };
      }
      return {'success': false, 'absents': <String>[]};
    } catch (_) {
      return {'success': false, 'absents': <String>[]};
    }
  }

  Future<Map<String, dynamic>> sendConvocation({
    required String studentId,
    required String title,
    required String message,
    bool urgent = false,
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {'success': false, 'error': 'Code école manquant.'};
    }
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/school/send_convocation'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCode,
          'student_id':  studentId,
          'title':       title,
          'message':     message,
          'urgent':      urgent,
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'batch_id': data['batch_id'],
          'urgent': data['urgent'] == true,
        };
      }
      return {
        'success': false,
        'error': 'Statut ${response.statusCode} : ${response.body}',
      };
    } on SocketException catch (e) {
      return {'success': false, 'error': 'Aucune connexion réseau : $e'};
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  Future<Map<String, dynamic>> sendAnnouncement({
    required String title,
    required String message,
    required String target,
    String? classe,
    String? section,
    List<String>? studentIds,
    bool urgent = false,
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {'success': false, 'error': 'Code école manquant.'};
    }
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/school/send_announcement'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCode,
          'annee':       currentYear,
          'title':       title,
          'message':     message,
          'target':      target,
          'classe':      classe ?? '',
          'section':     section ?? '',
          'student_ids': studentIds ?? [],
          'urgent':      urgent,
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'notified_count': data['notified_count'] ?? 0,
          'batch_id': data['batch_id'],
          'urgent': data['urgent'] == true,
        };
      }
      return {
        'success': false,
        'error': 'Statut ${response.statusCode} : ${response.body}',
      };
    } on SocketException catch (e) {
      return {'success': false, 'error': 'Aucune connexion réseau : $e'};
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }
}