part of frais_scolaires;

// ⚡ NOUVEAU — Nom du type de "autres frais" qui possède les administrations /
// rubriques (liste "autresFraisAdministrations"). Seul ce type affichera une
// répartition par administration chez le promoteur ; les autres types
// n'affichent que leurs montants. Comparaison insensible aux majuscules et
// aux apostrophes. Si ce nom ne correspond à aucun type MAIS qu'il n'existe
// qu'un seul type de frais, c'est ce type unique qui est utilisé.
// Mettez ici le nom EXACT de votre type de frais (ex : "Frais de l'État").
const String kTypeFraisAvecAdministrations = "Frais de l'État";

extension FraisScolairesServices on FraisScolaires {
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

    double moneyTodayAutresFrais = 0;
    for (final p in (autresFraisPaiementsByYear[currentYear] ?? [])) {
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
    for (final p in (autresFraisPaiementsByYear[currentYear] ?? [])) {
      if (p.date.year == now.year && p.date.month == now.month) {
        moneyThisMonthAutresFrais += p.montant;
      }
    }

    final double totalPrincipalYear = getYearTotalCollected();
    final double totalAutresFraisYear =
    (autresFraisPaiementsByYear[currentYear] ?? [])
        .fold(0.0, (sum, p) => sum + p.montant);
    final Map<String, double> moneyThisYearBySection = getTotalBySection();

    final adminDistToday = calculateAdminDistribution(moneyTodayPrincipal);
    final adminDistThisMonth =
    calculateAdminDistribution(moneyThisMonthPrincipal);
    final adminDistThisYear = calculateAdminDistribution(totalPrincipalYear);

    final autresFraisAdminDistToday =
    calculateAutresFraisAdminDistribution(moneyTodayAutresFrais);
    final autresFraisAdminDistThisMonth =
    calculateAutresFraisAdminDistribution(moneyThisMonthAutresFrais);
    final autresFraisAdminDistThisYear =
    calculateAutresFraisAdminDistribution(totalAutresFraisYear);

    Map<String, Map<String, double>> distBySection(
        Map<String, double> amountsBySection) {
      final result = <String, Map<String, double>>{};
      amountsBySection.forEach((section, amount) {
        result[section] = calculateAdminDistribution(amount);
      });
      return result;
    }

    final adminDistributionTodayBySection = distBySection(moneyTodayBySection);
    final adminDistributionThisMonthBySection =
    distBySection(moneyThisMonthBySection);
    final adminDistributionThisYearBySection =
    distBySection(moneyThisYearBySection);

    final Map<String, int> studentsBySection = {};
    final Map<String, int> studentsByClass = {};
    for (final e in currentData.eleves) {
      studentsBySection[e.section] = (studentsBySection[e.section] ?? 0) + 1;
      final key = "${e.section} - ${e.classe}";
      studentsByClass[key] = (studentsByClass[key] ?? 0) + 1;
    }

    // ⚡ NOUVEAU — détail SÉPARÉ par type de frais additionnel.
    // Les frais portant le même nom sont regroupés (comme dans les rapports).
    // Seul le type qui possède les administrations reçoit une répartition ;
    // les autres types n'ont que leurs montants. Rien n'est modifié dans les
    // données : on ne fait que lire.
    final List<AutreFraisPaiement> tousPaiementsAutresFrais =
    List<AutreFraisPaiement>.from(
        autresFraisPaiementsByYear[currentYear] ?? const []);
    final Set<String> idsClasses = {};

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
      idsClasses.addAll(ids);
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

    // Paiements dont le frais a été supprimé depuis : groupe à part (sans
    // administration) pour que la somme des types égale toujours le total.
    final Set<String> idsOrphelins = tousPaiementsAutresFrais
        .map((p) => p.autreFraisId)
        .where((id) => !idsClasses.contains(id))
        .toSet();
    if (idsOrphelins.isNotEmpty) {
      final orphelin = construireTypeStat(
        cle: '_autres_non_classes',
        nom: 'Frais supprimés / non classés',
        ids: idsOrphelins,
        nbFusionnes: idsOrphelins.length,
        avecAdmins: false,
      );
      if ((orphelin['thisYear'] as double) != 0) {
        autresFraisParType.add(orphelin);
      }
    }

    // Les administrations des autres frais appartiennent à UN seul type :
    // la répartition globale ne porte donc que sur ce type. Si aucun type
    // propriétaire n'est identifié, on garde l'ancien calcul (sur le total).
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
      'soldeNet': getSoldeNetActuel(),
    };
  }

  Future<void> pushPromoterSummary() async {
    if (schoolCode == null || schoolCode!.isEmpty) return;
    try {
      final summary = computePromoterSummary();
      await http.post(
        Uri.parse('$serverUrl/school/push_promoter_summary'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'school_code': schoolCode, 'summary': summary}),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {}
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
      'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
      'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
            (key, value) =>
            MapEntry(key, value.map((p) => p.toJson()).toList()),
      ),
      'paiementsAutresFraisAnnules': paiementsAutresFraisAnnules.toList(),
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
          await payAutreFrais(
            frais: frais,
            eleve: eleve,
            enregistrePar: (p['enregistrePar'] ?? 'Agent').toString(),
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

  Future<void> loadData() async {
    final dir       = await getApplicationDocumentsDirectory();
    _dataFilePath   = '${dir.path}/school_fees_data.json';
    final file      = File(_dataFilePath!);

    if (await file.exists()) {
      try {
        final jsonStr = await file.readAsString();
        final data    = json.decode(jsonStr) as Map<String, dynamic>;

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

        await _assignMissingIds();
      } catch (_) {
        _initDefaultData();
      }
    } else {
      _initDefaultData();
    }
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
  }

  Future<void> saveData() async {
    if (_dataFilePath == null) {
      final dir     = await getApplicationDocumentsDirectory();
      _dataFilePath = '${dir.path}/school_fees_data.json';
    }
    history[currentYear] = currentData;
    final file = File(_dataFilePath!);
    final data = {
      'config':                  config.toJson(),
      'currentYear':             currentYear,
      'localIdCounter':          _localIdCounter,
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
      'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
      'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
            (key, value) =>
            MapEntry(key, value.map((p) => p.toJson()).toList()),
      ),
      'paiementsAutresFraisAnnules': paiementsAutresFraisAnnules.toList(),
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
    };
    await file.writeAsString(json.encode(data));
  }

  Future<void> clearLocalData() async {
    if (_dataFilePath == null) {
      final dir     = await getApplicationDocumentsDirectory();
      _dataFilePath = '${dir.path}/school_fees_data.json';
    }
    final file = File(_dataFilePath!);
    if (await file.exists()) {
      await file.delete();
    }
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
    autresFrais = [];
    autresFraisPaiementsByYear = {};
    paiementsAutresFraisAnnules = {};
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

  Future<Map<String, dynamic>> backupToServer(
      String schoolCodeParam, String password) async {
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
        'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
        'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
              (key, value) =>
              MapEntry(key, value.map((p) => p.toJson()).toList()),
        ),
        'paiementsAutresFraisAnnules': paiementsAutresFraisAnnules.toList(),
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

      final response = await http
          .post(
        Uri.parse('$serverUrl/backup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'school_code': normalizedCode, 'data': data}),
      )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final corrections  =
            responseData['corrections'] as Map<String, dynamic>? ?? {};
        if (corrections.isNotEmpty) {
          _applyIdCorrections(corrections);
          await saveData();
        }
        await pushPromoterSummary();
        return {'success': true};
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

  Future<Map<String, dynamic>> restoreFromServer(
      String schoolCodeParam, String password) async {
    final normalizedCode = schoolCodeParam.trim().toUpperCase();
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/restore?school_code=$normalizedCode'))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['backup_password'] != null &&
            data['backup_password'] != password) {
          return {'success': false, 'error': 'Mot de passe incorrect'};
        }
        schoolCode = normalizedCode;
        await mergeRestoredData(data);
        await saveData();
        return {'success': true};
      }
      if (response.statusCode == 404) {
        return {
          'success': false,
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
          .get(Uri.parse('$serverUrl/restore?school_code=$normalizedCode'))
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

  String _signatureTransaction(Map<String, dynamic> t) {
    final double montant = (t['amount'] as num?)?.toDouble() ?? 0.0;
    return '${t['date'] ?? ''}|${t['mois'] ?? ''}|${montant.toStringAsFixed(2)}';
  }

  List<Map<String, dynamic>> _fusionnerTransactionsSansDoublons(
      List<Map<String, dynamic>> locales,
      List<Map<String, dynamic>> serveur,
      ) {
    final Map<String, Map<String, dynamic>> parId = {};
    final Set<String> signaturesAvecIdLegacy = {};
    final List<Map<String, dynamic>> sansId = [];

    void classer(Map<String, dynamic> t) {
      final String tid = t['id']?.toString().trim() ?? '';
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

    for (final t in serveur) {
      classer(Map<String, dynamic>.from(t));
    }
    for (final t in locales) {
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

  Future<void> mergeRestoredData(Map<String, dynamic> serverData) async {
    config = SchoolConfig.fromJson(serverData['config'] ?? {});

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

    if (serverData['history'] != null) {
      final serverHistory =
      (serverData['history'] as Map<String, dynamic>).map(
            (key, value) =>
            MapEntry(key, SchoolYearData.fromJson(value)),
      );

      for (var entry in serverHistory.entries) {
        final year           = entry.key;
        final serverYearData = entry.value;

        if (history.containsKey(year)) {
          final localEleves  = history[year]!.eleves;
          final existingByKey = <String, Eleve>{};
          for (var e in localEleves) {
            final key =
                "${e.nom.trim().toLowerCase()}_${e.postNom.trim().toLowerCase()}_${e.prenom.trim().toLowerCase()}";
            existingByKey[key] = e;
          }

          for (var serverEleve in serverYearData.eleves) {
            final key =
                "${serverEleve.nom.trim().toLowerCase()}_${serverEleve.postNom.trim().toLowerCase()}_${serverEleve.prenom.trim().toLowerCase()}";

            if (existingByKey.containsKey(key)) {
              final localEleve = existingByKey[key]!;
              localEleve.id    = serverEleve.id.isNotEmpty
                  ? serverEleve.id
                  : localEleve.id;
              localEleve.classe   = serverEleve.classe;
              localEleve.section  = serverEleve.section;
              localEleve.montantMensuelPersonnalise =
                  serverEleve.montantMensuelPersonnalise ??
                      localEleve.montantMensuelPersonnalise;
              if (serverEleve.exceptionsMoisPersonnalisees.isNotEmpty) {
                serverEleve.exceptionsMoisPersonnalisees.forEach((m, v) {
                  localEleve.exceptionsMoisPersonnalisees.putIfAbsent(
                      m, () => v);
                });
              }
              localEleve.moisDebloque ??= serverEleve.moisDebloque;

              final List<Map<String, dynamic>> mergedTransactions =
              _fusionnerTransactionsSansDoublons(
                List<Map<String, dynamic>>.from(localEleve.transactions),
                List<Map<String, dynamic>>.from(serverEleve.transactions),
              );

              if (mergedTransactions.isEmpty) {
                final Map<String, double> paidConserve =
                Map<String, double>.from(localEleve.paid);
                serverEleve.paid.forEach((mois, montant) {
                  final double actuel = paidConserve[mois] ?? 0.0;
                  if (montant > actuel) paidConserve[mois] = montant;
                });
                localEleve.paid
                  ..clear()
                  ..addAll(paidConserve);
              } else {
                localEleve.transactions
                  ..clear()
                  ..addAll(mergedTransactions);

                final Map<String, double> paidReconstruit = {};
                for (var t in mergedTransactions) {
                  final mois = t['mois']?.toString() ?? '';
                  if (mois.isEmpty) continue;
                  final montant = (t['amount'] as num?)?.toDouble() ?? 0.0;
                  paidReconstruit[mois] =
                      (paidReconstruit[mois] ?? 0) + montant;
                }
                localEleve.paid
                  ..clear()
                  ..addAll(paidReconstruit);
              }
            } else {
              localEleves.add(serverEleve);
            }
          }
        } else {
          history[year] = serverYearData;
        }
      }
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
          final existingIds =
          depensesByYear[year]!.map((d) => d.id).toSet();
          for (var d in serverList) {
            if (!existingIds.contains(d.id)) {
              depensesByYear[year]!.add(d);
            }
          }
        } else {
          depensesByYear[year] = serverList;
        }
      }
    }
    if (serverData['autresFrais'] != null) {
      final serverAutresFrais = (serverData['autresFrais'] as List<dynamic>)
          .map((e) => AutreFrais.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingFraisIds = autresFrais.map((f) => f.id).toSet();
      for (var f in serverAutresFrais) {
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
            .where((p) => !paiementsAutresFraisAnnules.contains(p.id))
            .toList();

        if (autresFraisPaiementsByYear.containsKey(year)) {
          final existingIds =
          autresFraisPaiementsByYear[year]!.map((p) => p.id).toSet();
          for (var p in serverList) {
            if (!existingIds.contains(p.id)) {
              autresFraisPaiementsByYear[year]!.add(p);
            }
          }
        } else {
          autresFraisPaiementsByYear[year] = serverList;
        }
      }

      for (final liste in autresFraisPaiementsByYear.values) {
        liste.removeWhere((p) => paiementsAutresFraisAnnules.contains(p.id));
      }
    }
    if (serverData['autresFraisAdministrations'] != null) {
      final serverAutresFraisAdmins =
      (serverData['autresFraisAdministrations'] as List<dynamic>)
          .map((e) =>
          AutreFraisAdministration.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingAdminIds =
      autresFraisAdministrations.map((a) => a.id).toSet();
      for (var a in serverAutresFraisAdmins) {
        if (!existingAdminIds.contains(a.id)) {
          autresFraisAdministrations.add(a);
        }
      }
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
      final existingSignataireIds = signataires.map((s) => s.id).toSet();
      for (var s in serverSignataires) {
        if (!existingSignataireIds.contains(s.id)) {
          signataires.add(s);
        }
      }
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
    if (serverData['elevesSupprimesData'] != null) {
      final serverElevesSupprimes =
      SchoolYearData.fromJson(serverData['elevesSupprimesData']);
      final existingSupprimesIds =
      elevesSupprimesData.eleves.map((e) => e.id).toSet();
      for (var e in serverElevesSupprimes.eleves) {
        if (!existingSupprimesIds.contains(e.id)) {
          elevesSupprimesData.eleves.add(e);
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

    currentYear = serverData['currentYear'] ?? currentYear;
    if (history.containsKey(currentYear)) {
      currentData = history[currentYear]!;
    } else {
      currentData          = SchoolYearData(eleves: []);
      history[currentYear] = currentData;
    }

    await _assignMissingIds();
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
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return {'success': true};
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
}