import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'services/epson_printer_service.dart';
import 'dart:math';

const String serverUrl = "https://jsinf.onrender.com";

class Depense {
  String id;
  String motif;
  double montant;
  DateTime date;
  String enregistrePar;

  Depense({
    required this.id,
    required this.motif,
    required this.montant,
    required this.date,
    this.enregistrePar = 'Direction',
  });

  factory Depense.fromJson(Map<String, dynamic> json) => Depense(
    id: json['id'] as String? ?? '',
    motif: json['motif'] as String? ?? '',
    montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.tryParse(json['date'] as String? ?? '') ??
        DateTime.now(),
    enregistrePar: json['enregistrePar'] as String? ?? 'Direction',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'motif': motif,
    'montant': montant,
    'date': date.toIso8601String(),
    'enregistrePar': enregistrePar,
  };

  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }
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
  })  : dateCreation = dateCreation ?? DateTime.now(),
        montantsParSection = montantsParSection ?? {},
        montantsParClasse = montantsParClasse ?? {};

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

  AutreFraisPaiement({
    required this.id,
    required this.autreFraisId,
    required this.autreFraisNom,
    required this.eleveId,
    required this.montant,
    required this.date,
    this.enregistrePar = 'Direction',
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
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'autreFraisId': autreFraisId,
    'autreFraisNom': autreFraisNom,
    'eleveId': eleveId,
    'montant': montant,
    'date': date.toIso8601String(),
    'enregistrePar': enregistrePar,
  };

  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
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

class FraisScolaires {
  SchoolConfig config;
  SchoolYearData currentData = SchoolYearData(eleves: []);
  String currentYear = '2025-2026';
  Map<String, SchoolYearData> history = {};
  String? _dataFilePath;
  String? lastSelectedClassFilter;
  String? lastSelectedSectionFilter;
  String? schoolCode;
  Map<String, List<Depense>> depensesByYear = {};
  List<AutreFrais> autresFrais = [];
  Map<String, List<AutreFraisPaiement>> autresFraisPaiementsByYear = {};
  List<AutreFraisAdministration> autresFraisAdministrations = [];
  List<AdminAuditLog> adminAuditLog = [];
  List<Signataire> signataires = [];
  String? lastReportCity;
  List<String> printedReceiptKeys = [];
  List<Map<String, dynamic>> receiptQueue = [];
  List<Map<String, dynamic>> localAccessKeys = [];
  List<Map<String, dynamic>> localPendingPayments = [];
  List<Map<String, dynamic>> localPendingRegistrations = [];
  List<Map<String, dynamic>> localPendingAutresFraisPayments = [];
  Map<String, List<String>> localAttendance = {};
  List<Map<String, dynamic>> localCommunicationsLog = [];

  int _localIdCounter = 0;

  // ⚡ NOUVEAU — verrou anti-concurrence pour flushReceiptQueue() : empêche
  // deux vidages simultanés de la file de reçus en attente, qui pouvaient
  // provoquer l'impression du même reçu plusieurs fois.
  bool _isFlushingReceiptQueue = false;

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre',
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
  ];

  static const List<String> _joursSemaine = [
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
  ];

  FraisScolaires() : config = SchoolConfig(schoolName: "EduPay School RDC");

  int _schoolMonthIndexForToday() {
    final calendarMonth = DateTime.now().month;
    if (calendarMonth >= 9 && calendarMonth <= 12) {
      return calendarMonth - 9;
    } else if (calendarMonth >= 1 && calendarMonth <= 6) {
      return calendarMonth + 3;
    }
    return -1;
  }

  String? get currentSchoolMonthName {
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return null;
    return months[idx];
  }

  String get _dateGenerationFormatee {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final jour = _joursSemaine[now.weekday - 1];
    return '$jour ${two(now.day)}/${two(now.month)}/${now.year} à '
        '${two(now.hour)}:${two(now.minute)}';
  }

  String getMoisPayesPourDate(Eleve eleve, [String? date]) {
    final targetDate = date ?? DateTime.now().toString().split(' ')[0];
    final moisDuJour = <String>[];
    for (final t in eleve.transactions) {
      if (t['date'] == targetDate) {
        final mois = t['mois']?.toString() ?? '';
        if (mois.isNotEmpty && !moisDuJour.contains(mois)) {
          moisDuJour.add(mois);
        }
      }
    }
    moisDuJour.sort(
            (a, b) => months.indexOf(a).compareTo(months.indexOf(b)));
    return moisDuJour.join(', ');
  }

  List<pw.Widget> _buildSignatureSection([String? city]) {
    if (signataires.isEmpty) return [];

    final villeAffichee =
    (city != null && city.trim().isNotEmpty) ? city.trim() : 'Lubumbashi';

    final rows = <List<Signataire>>[];
    for (var i = 0; i < signataires.length; i += 3) {
      final end = (i + 3 > signataires.length) ? signataires.length : i + 3;
      rows.add(signataires.sublist(i, end));
    }

    pw.Widget buildColonne(Signataire s) {
      return pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: 34),
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(width: 0.8, color: PdfColors.black),
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                s.nom.isNotEmpty ? s.nom : ' ',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                s.fonction.isNotEmpty ? s.fonction : ' ',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return [
      pw.SizedBox(height: 36),
      pw.Divider(thickness: 0.6, color: PdfColors.grey400),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Fait à $villeAffichee, le : $_dateGenerationFormatee',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      pw.SizedBox(height: 26),
      ...rows.map((rowSignataires) {
        final widgets = rowSignataires.map(buildColonne).toList();
        while (widgets.length < 3) {
          widgets.add(pw.Expanded(child: pw.SizedBox()));
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 24),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: widgets,
          ),
        );
      }),
    ];
  }

  Map<int, pw.TableColumnWidth> _buildColumnWidths(List<double> flexRatios) {
    return {
      for (var i = 0; i < flexRatios.length; i++)
        i: pw.FlexColumnWidth(flexRatios[i]),
    };
  }

  double _tableCellFontSize(int columnCount) {
    if (columnCount <= 6) return 9;
    if (columnCount <= 8) return 8.5;
    if (columnCount <= 10) return 8;
    if (columnCount <= 13) return 7.5;
    return 6.5;
  }

  double _tableHeaderFontSize(int columnCount) {
    if (columnCount <= 6) return 9;
    if (columnCount <= 8) return 8.5;
    if (columnCount <= 10) return 8;
    if (columnCount <= 13) return 7.5;
    return 7;
  }

  // ==========================================================================
  // DEMANDES PROMOTEUR (remplace l'ancien système de code masqué)
  // ==========================================================================
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
      // ⚡ NOUVEAU — purge une éventuelle entrée résiduelle de la file
      // d'attente pour ce même paiement, pour qu'une impression
      // automatique ultérieure (flushReceiptQueue) ne reproduise jamais
      // ce reçu. Il s'agit ici d'une réimpression explicitement demandée
      // (duplicata volontaire) donc l'impression elle-même n'est pas
      // bloquée, mais on garde le registre cohérent après coup.
      final key = _principalReceiptKey(eleve, transaction);
      if (!isReceiptPrinted(key)) {
        await _markReceiptPrinted(key);
      } else {
        await saveData();
      }
    }
    return ok;
  }

  // ==========================================================================
  // RÉSUMÉ PROMOTEUR — calculé et poussé au serveur après chaque sauvegarde
  // ⚡ ENRICHI : inclut désormais la répartition Aujourd'hui / Ce mois /
  // Cette année, globale ET par section, pour que le promoteur puisse voir
  // combien chaque administration (enseignants, gestionnaire, etc.) a déjà
  // accumulé — pas seulement pour la journée, mais aussi pour le mois en
  // cours, l'année, et pour chaque section de l'école.
  // ==========================================================================
  Map<String, dynamic> computePromoterSummary() {
    final today = DateTime.now().toString().split(' ')[0];

    // --- Aujourd'hui, par section (frais principaux) ---
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

    // --- Ce mois-ci, par section (frais principaux) ---
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

    // --- Cette année (déjà existant) ---
    final double totalPrincipalYear = getYearTotalCollected();
    final double totalAutresFraisYear =
    (autresFraisPaiementsByYear[currentYear] ?? [])
        .fold(0.0, (sum, p) => sum + p.montant);
    final Map<String, double> moneyThisYearBySection = getTotalBySection();

    // --- Répartition GLOBALE par administration (toute l'école) ---
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

    // --- Répartition PAR SECTION par administration ---
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

    return {
      'schoolName': config.schoolName,
      'currentYear': currentYear,
      'currentMonthName': currentSchoolMonthName ?? '',

      // Aujourd'hui
      'moneyToday': moneyTodayPrincipal + moneyTodayAutresFrais,
      'moneyTodayPrincipal': moneyTodayPrincipal,
      'moneyTodayAutresFrais': moneyTodayAutresFrais,
      'adminDistributionToday': adminDistToday,
      'autresFraisAdminDistributionToday': autresFraisAdminDistToday,
      'moneyTodayBySection': moneyTodayBySection,
      'adminDistributionTodayBySection': adminDistributionTodayBySection,

      // Ce mois-ci
      'moneyThisMonth': moneyThisMonthPrincipal + moneyThisMonthAutresFrais,
      'moneyThisMonthPrincipal': moneyThisMonthPrincipal,
      'moneyThisMonthAutresFrais': moneyThisMonthAutresFrais,
      'adminDistributionThisMonth': adminDistThisMonth,
      'autresFraisAdminDistributionThisMonth': autresFraisAdminDistThisMonth,
      'moneyThisMonthBySection': moneyThisMonthBySection,
      'adminDistributionThisMonthBySection':
      adminDistributionThisMonthBySection,

      // Cette année / global
      'adminDistributionThisYear': adminDistThisYear,
      'autresFraisAdminDistributionThisYear': autresFraisAdminDistThisYear,
      'moneyThisYearBySection': moneyThisYearBySection,
      'adminDistributionThisYearBySection':
      adminDistributionThisYearBySection,

      'totalStudents': currentData.eleves.length,
      'studentsBySection': studentsBySection,
      'studentsByClass': studentsByClass,
      'totalAmountGlobal': totalPrincipalYear + totalAutresFraisYear,
      'totalAmountBySection': getTotalBySection(),
      'totalAmountByClass': getTotalByClass(),
      'totalDepenses': getTotalDepenses(),
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

  Future<void> cancelTransaction({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
  }) async {
    final mois = transaction['mois']?.toString() ?? '';
    final montant = (transaction['amount'] as num?)?.toDouble() ?? 0.0;

    final currentPaid = eleve.paid[mois] ?? 0;
    double newPaid = currentPaid - montant;
    if (newPaid < 0) newPaid = 0;
    eleve.paid[mois] = newPaid;

    eleve.transactions.remove(transaction);

    recalculerRepartitionMoisPourEleve(eleve);

    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().millisecondsSinceEpoch}',
      action: 'annulation',
      eleveId: eleve.id,
      eleveNomComplet: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      mois: mois,
      montantAvant: montant,
      montantApres: 0,
    ));

    await saveData();
  }

  Future<void> modifyTransactionAmount({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
    required double newAmount,
  }) async {
    final mois = transaction['mois']?.toString() ?? '';
    final oldAmount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;

    final currentPaid = eleve.paid[mois] ?? 0;
    double newPaid = currentPaid - oldAmount + newAmount;
    if (newPaid < 0) newPaid = 0;
    eleve.paid[mois] = newPaid;

    transaction['amount'] = newAmount;
    transaction['modifiePar'] = 'Promoteur';
    transaction['modifieLe'] = DateTime.now().toString().split(' ')[0];

    recalculerRepartitionMoisPourEleve(eleve);

    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().millisecondsSinceEpoch}',
      action: 'modification',
      eleveId: eleve.id,
      eleveNomComplet: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      mois: mois,
      montantAvant: oldAmount,
      montantApres: newAmount,
    ));

    await saveData();
  }

  List<AdminAuditLog> getAdminAuditLog() {
    final list = List<AdminAuditLog>.from(adminAuditLog);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<Signataire> getSignataires() => List<Signataire>.from(signataires);

  Future<Signataire> addSignataire({
    required String nom,
    required String fonction,
  }) async {
    final signataire = Signataire(
      id: 'SIG${DateTime.now().millisecondsSinceEpoch}',
      nom: nom.trim(),
      fonction: fonction.trim(),
    );
    signataires.add(signataire);
    await saveData();
    return signataire;
  }

  Future<void> updateSignataire(
      String id, {
        required String nom,
        required String fonction,
      }) async {
    for (var s in signataires) {
      if (s.id == id) {
        s.nom = nom.trim();
        s.fonction = fonction.trim();
        break;
      }
    }
    await saveData();
  }

  Future<void> deleteSignataire(String id) async {
    signataires.removeWhere((s) => s.id == id);
    await saveData();
  }

  Future<void> setLastReportCity(String city) async {
    final trimmed = city.trim();
    lastReportCity = trimmed.isEmpty ? null : trimmed;
    await saveData();
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

  // ==========================================================================
  // ⚡ NOUVEAU — Clé unique et STABLE identifiant le reçu d'UNE transaction
  // du frais principal. TOUTES les voies d'impression (immédiate, file
  // d'attente `flushReceiptQueue`, et réimpression manuelle
  // `retryPrintPrincipalReceipt`) utilisent désormais cette même clé.
  // C'est ce qui garantit qu'un même paiement ne soit JAMAIS imprimé plus
  // d'une fois, quel que soit le chemin par lequel l'impression est
  // déclenchée (impression au moment du paiement, impression différée
  // après reconnexion de l'imprimante, ou clic manuel sur "imprimer").
  // ==========================================================================
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

    // ⚡ Clé unifiée (voir _principalReceiptKey) — identique à celle
    // utilisée par flushReceiptQueue() et retryPrintPrincipalReceipt().
    final key = _principalReceiptKey(eleve, transaction);
    if (isReceiptPrinted(key)) return false;

    final double montantRequis =
    getRequiredForMonth(mois, eleve.section, eleve.classe);
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

  // ==========================================================================
  // ⚡ NOUVEAU — Réimpression manuelle d'UN paiement principal déjà
  // enregistré (bouton imprimante sur une transaction non confirmée dans
  // l'écran "Paiements des Élèves"). Avant ce correctif, cette action ne
  // passait PAS par le registre `printedReceiptKeys`/`receiptQueue`, ce
  // qui pouvait provoquer une réimpression automatique en double lors du
  // prochain passage de `flushReceiptQueue()`. Désormais elle utilise la
  // MÊME clé et le MÊME registre que toutes les autres voies d'impression.
  // ==========================================================================
  Future<bool> retryPrintPrincipalReceipt({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
    required String printerName,
    Uint8List? logoBytes,
  }) async {
    final key = _principalReceiptKey(eleve, transaction);

    if (isReceiptPrinted(key)) {
      // Déjà imprimé avec certitude par une autre voie (impression
      // automatique au moment du paiement, ou file d'attente) entre-temps
      // : on synchronise simplement l'état local SANS réimprimer, pour
      // ne jamais produire un doublon.
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
  }) async {
    final key = 'autre_frais|${eleve.id}|${frais.id}';
    if (isReceiptPrinted(key)) return false;

    final double montant = getMontantAutreFraisPourEleve(frais, eleve);

    final data = <String, dynamic>{
      'titreFrais': frais.nom,
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
    // ⚡ NOUVEAU — verrou anti-concurrence : si un vidage de la file est
    // déjà en cours (ex: l'écran de paiement a été réinitialisé deux fois
    // rapidement), on ne relance pas un second vidage en parallèle. Sans
    // ce verrou, deux exécutions concurrentes pouvaient toutes les deux
    // constater qu'un reçu n'était "pas encore imprimé" et l'imprimer
    // chacune une fois, créant un doublon.
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

  String generateLocalStudentId(String nom) {
    final yearShort = currentYear.length >= 2
        ? currentYear.substring(currentYear.length - 2)
        : '26';
    final schoolLetter = config.schoolName.isNotEmpty
        ? config.schoolName[0].toUpperCase()
        : 'B';
    final nameRaw    = nom.trim().toUpperCase();
    final namePrefix = nameRaw.length >= 2
        ? nameRaw.substring(0, 2)
        : nameRaw.padRight(2, 'X');

    final allIds = history.values
        .expand((yd) => yd.eleves)
        .map((e) => e.id)
        .where((id) => id.isNotEmpty)
        .toSet();

    _localIdCounter++;
    String candidate = '$namePrefix$yearShort$schoolLetter$_localIdCounter';

    while (allIds.contains(candidate)) {
      _localIdCounter++;
      candidate = '$namePrefix$yearShort$schoolLetter$_localIdCounter';
    }
    return candidate;
  }

  Future<String> generateUniqueStudentId(
      String nom, String schoolCodeForServer) async {
    if (nom.trim().isEmpty) {
      throw Exception("Le nom est requis pour générer un identifiant.");
    }
    return generateLocalStudentId(nom);
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

  Eleve? findStudentByFullName(
      String nom, String postNom, String prenom, [String? year]) {
    final targetKey =
        '${nom.trim().toLowerCase()}_${postNom.trim().toLowerCase()}_${prenom.trim().toLowerCase()}';
    final list = year != null
        ? (history[year]?.eleves ?? currentData.eleves)
        : currentData.eleves;
    for (final e in list) {
      final key =
          '${e.nom.trim().toLowerCase()}_${e.postNom.trim().toLowerCase()}_${e.prenom.trim().toLowerCase()}';
      if (key == targetKey) return e;
    }
    return null;
  }

  Eleve? findDuplicateFullName({
    required String nom,
    required String postNom,
    required String prenom,
    String? excludeId,
  }) {
    final nomN = nom.trim().toLowerCase();
    final postNomN = postNom.trim().toLowerCase();
    final prenomN = prenom.trim().toLowerCase();
    for (final e in currentData.eleves) {
      if (excludeId != null && e.id == excludeId) continue;
      if (e.nom.trim().toLowerCase() == nomN &&
          e.postNom.trim().toLowerCase() == postNomN &&
          e.prenom.trim().toLowerCase() == prenomN) {
        return e;
      }
    }
    return null;
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
      'autresFraisAdministrations':
      autresFraisAdministrations.map((a) => a.toJson()).toList(),
      'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
      'signataires': signataires.map((s) => s.toJson()).toList(),
      'printedReceiptKeys': printedReceiptKeys,
      'receiptQueue': receiptQueue,
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
        await payAutreFrais(
          frais: frais,
          eleve: eleve,
          enregistrePar: (p['enregistrePar'] ?? 'Agent').toString(),
        );
        count++;
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

  String _classeKey(String section, String classeNumero) =>
      "$section|$classeNumero";

  List<String> getClassesForSection(String section) {
    if (config.classesBySection.containsKey(section) &&
        config.classesBySection[section]!.isNotEmpty) {
      return config.classesBySection[section]!;
    }
    final autoClasses = SchoolConfig.defaultClassesForSectionName(section);
    if (autoClasses.isNotEmpty) {
      config.classesBySection[section] = List<String>.from(autoClasses);
    }
    return config.classesBySection[section] ?? [];
  }

  Future<void> addClasseNumero(String section, String classeNumero) async {
    final trimmed = classeNumero.trim();
    if (trimmed.isEmpty) return;
    final list = config.classesBySection.putIfAbsent(section, () => []);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await saveData();
    }
  }

  Future<void> renameClasseNumero(
      String section, String oldNumero, String newNumero) async {
    final trimmedNew = newNumero.trim();
    if (trimmedNew.isEmpty || trimmedNew == oldNumero) return;

    final list = config.classesBySection[section];
    if (list != null) {
      final idx = list.indexOf(oldNumero);
      if (idx != -1) {
        if (list.contains(trimmedNew)) {
          list.removeAt(idx);
        } else {
          list[idx] = trimmedNew;
        }
      }
    }

    final oldKey = _classeKey(section, oldNumero);
    final newKey = _classeKey(section, trimmedNew);
    if (config.subClassesByClasse.containsKey(oldKey)) {
      final subs = config.subClassesByClasse.remove(oldKey)!;
      if (config.subClassesByClasse.containsKey(newKey)) {
        for (var s in subs) {
          if (!config.subClassesByClasse[newKey]!.contains(s)) {
            config.subClassesByClasse[newKey]!.add(s);
          }
        }
      } else {
        config.subClassesByClasse[newKey] = subs;
      }
    }
    if (config.feesByClasse.containsKey(oldKey)) {
      final fee = config.feesByClasse.remove(oldKey)!;
      config.feesByClasse[newKey] = fee;
    }
    if (config.monthlyExceptionsByClasse.containsKey(oldKey)) {
      final exc = config.monthlyExceptionsByClasse.remove(oldKey)!;
      config.monthlyExceptionsByClasse[newKey] = exc;
    }
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.section != section) continue;
        final numero = classeNumeroFromFullClasse(eleve.classe);
        if (numero == oldNumero) {
          final sub = subClasseFromFullClasse(eleve.classe);
          eleve.classe = buildFullClasseName(trimmedNew, sub);
        }
      }
    }

    for (var frais in autresFrais) {
      if (frais.scope == 'classe' &&
          frais.section == section &&
          frais.classe == oldNumero) {
        frais.classe = trimmedNew;
      }
      if (frais.montantsParClasse.containsKey(oldKey)) {
        final montant = frais.montantsParClasse.remove(oldKey)!;
        frais.montantsParClasse[newKey] = montant;
      }
    }

    if (lastSelectedClassFilter == oldNumero) {
      lastSelectedClassFilter = trimmedNew;
    }

    await saveData();
  }

  Future<Map<String, dynamic>> deleteClasseNumero(
      String section,
      String numero, {
        bool force = false,
      }) async {
    int studentCount = 0;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.section == section &&
            classeNumeroFromFullClasse(eleve.classe) == numero) {
          studentCount++;
        }
      }
    }

    final key = _classeKey(section, numero);

    int autresFraisCount = 0;
    for (var frais in autresFrais) {
      if (frais.scope == 'classe' &&
          frais.section == section &&
          frais.classe == numero) {
        autresFraisCount++;
      } else if (frais.montantsParClasse.containsKey(key)) {
        autresFraisCount++;
      }
    }

    if ((studentCount > 0 || autresFraisCount > 0) && !force) {
      return {
        'success': false,
        'studentCount': studentCount,
        'autresFraisCount': autresFraisCount,
      };
    }

    config.classesBySection[section]?.remove(numero);
    config.subClassesByClasse.remove(key);
    config.feesByClasse.remove(key);
    config.monthlyExceptionsByClasse.remove(key);

    for (var frais in autresFrais) {
      if (frais.scope == 'classe' &&
          frais.section == section &&
          frais.classe == numero) {
        frais.scope = 'section';
        frais.classe = null;
      }
      frais.montantsParClasse.remove(key);
    }

    if (lastSelectedClassFilter == numero) {
      lastSelectedClassFilter = null;
    }
    await saveData();
    return {
      'success': true,
      'studentCount': studentCount,
      'autresFraisCount': autresFraisCount,
    };
  }

  List<String> getSubClassesFor(String section, String classeNumero) {
    return config.subClassesByClasse[_classeKey(section, classeNumero)] ?? [];
  }

  Future<void> addSubClasse(
      String section, String classeNumero, String subClasse) async {
    final trimmed = subClasse.trim();
    if (trimmed.isEmpty) return;
    final key  = _classeKey(section, classeNumero);
    final list = config.subClassesByClasse.putIfAbsent(key, () => []);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await saveData();
    }
  }

  Future<Map<String, dynamic>> removeSubClasse(
      String section,
      String classeNumero,
      String subClasse, {
        bool force = false,
      }) async {
    int studentCount = 0;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.section == section &&
            classeNumeroFromFullClasse(eleve.classe) == classeNumero &&
            subClasseFromFullClasse(eleve.classe) == subClasse) {
          studentCount++;
        }
      }
    }

    if (studentCount > 0 && !force) {
      return {
        'success': false,
        'studentCount': studentCount,
      };
    }

    final key = _classeKey(section, classeNumero);
    config.subClassesByClasse[key]?.remove(subClasse);
    await saveData();
    return {
      'success': true,
      'studentCount': studentCount,
    };
  }

  String buildFullClasseName(String classeNumero, String? subClasse) {
    if (subClasse == null || subClasse.trim().isEmpty) return classeNumero;
    return "$classeNumero ${subClasse.trim()}";
  }

  String classeNumeroFromFullClasse(String classeComplete) {
    final trimmed = classeComplete.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.split(' ').first;
  }

  String? subClasseFromFullClasse(String classeComplete) {
    final parts = classeComplete.trim().split(' ');
    if (parts.length > 1) {
      final rest = parts.sublist(1).join(' ').trim();
      return rest.isEmpty ? null : rest;
    }
    return null;
  }

  List<String> getAllDisplayClassesForSection(String section) {
    final result = <String>[];
    for (var numero in getClassesForSection(section)) {
      final subs = getSubClassesFor(section, numero);
      if (subs.isEmpty) {
        result.add(numero);
      } else {
        for (var sub in subs) {
          result.add(buildFullClasseName(numero, sub));
        }
      }
    }
    return result;
  }

  List<String> getAllDisplayClasses() {
    final result = <String>{};
    for (var section in config.sections) {
      result.addAll(getAllDisplayClassesForSection(section));
    }
    return result.toList();
  }

  List<Map<String, String>> getAllDisplayClassesWithSection() {
    final List<MapEntry<String, String>> paires = [];
    for (var section in config.sections) {
      for (var classe in getAllDisplayClassesForSection(section)) {
        paires.add(MapEntry(classe, section));
      }
    }

    final Map<String, int> occurrences = {};
    for (var p in paires) {
      occurrences[p.key] = (occurrences[p.key] ?? 0) + 1;
    }

    final Set<String> dejaVus = {};
    final result = <Map<String, String>>[];
    for (var p in paires) {
      final cleUnique = '${p.value}|${p.key}';
      if (dejaVus.contains(cleUnique)) continue;
      dejaVus.add(cleUnique);
      final bool ambigu = (occurrences[p.key] ?? 0) > 1;
      result.add({
        'classe': p.key,
        'section': p.value,
        'label': ambigu ? '${p.key} (${p.value})' : p.key,
      });
    }
    return result;
  }

  String? getNextClasseNumero(String section, String classeNumero) {
    final list = getClassesForSection(section);
    final idx  = list.indexOf(classeNumero);
    if (idx == -1 || idx == list.length - 1) return null;
    return list[idx + 1];
  }

  String computePromotedClasse(Eleve eleve) {
    final numero     = classeNumeroFromFullClasse(eleve.classe);
    final subClasse  = subClasseFromFullClasse(eleve.classe);
    final nextNumero = getNextClasseNumero(eleve.section, numero);
    if (nextNumero == null) return eleve.classe;
    return buildFullClasseName(nextNumero, subClasse);
  }

  Future<Map<String, int>> promoteStudents({
    required List<Eleve> studentsToProcess,
    required Map<String, bool> passToNextYear,
    required Map<String, bool> monterClasse,
    required String targetYear,
  }) async {
    int promoted    = 0;
    int abandoned   = 0;
    int redoublants = 0;

    if (!history.containsKey(targetYear)) {
      history[targetYear] = SchoolYearData(eleves: []);
    }
    final targetData  = history[targetYear]!;
    final existingIds = targetData.eleves.map((e) => e.id).toSet();

    for (var eleve in studentsToProcess) {
      final shouldPass = passToNextYear[eleve.id] ?? true;
      if (!shouldPass) {
        abandoned++;
        continue;
      }
      final shouldMonter = monterClasse[eleve.id] ?? true;
      String newClasse;
      if (shouldMonter) {
        final promotedClasse = computePromotedClasse(eleve);
        if (promotedClasse == eleve.classe) redoublants++;
        newClasse = promotedClasse;
      } else {
        newClasse = eleve.classe;
        redoublants++;
      }

      if (existingIds.contains(eleve.id)) {
        final existing =
        targetData.eleves.firstWhere((e) => e.id == eleve.id);
        existing.classe  = newClasse;
        existing.section = eleve.section;
      } else {
        targetData.eleves.add(Eleve(
          id:      eleve.id,
          nom:     eleve.nom,
          postNom: eleve.postNom,
          prenom:  eleve.prenom,
          classe:  newClasse,
          section: eleve.section,
        ));
        existingIds.add(eleve.id);
      }
      promoted++;
    }

    await saveData();
    return {
      'promoted':    promoted,
      'abandoned':   abandoned,
      'redoublants': redoublants,
    };
  }

  List<Eleve> getStudentsBySection(String section) =>
      currentData.eleves.where((e) => e.section == section).toList();

  List<Eleve> getStudentsByClass(String classe) =>
      currentData.eleves.where((e) => e.classe == classe).toList();

  List<Eleve> getStudentsBySectionAndClass(
      String? section, String? classe) {
    return currentData.eleves.where((e) {
      final matchSection = section == null || e.section == section;
      final matchClass   = classe  == null || e.classe  == classe;
      return matchSection && matchClass;
    }).toList();
  }

  static const double _montantSecoursSiNonConfigure = 35000;

  bool sectionAFraisConfigure(String section) =>
      config.feesBySection.containsKey(section);

  List<String> getSectionsSansFraisConfigure() {
    return config.sections
        .where((s) => !sectionAFraisConfigure(s))
        .toList();
  }

  double getRequiredForMonth(String mois, String section,
      [String? classe]) {
    if (classe != null && classe.trim().isNotEmpty) {
      final classeNumero = classeNumeroFromFullClasse(classe);
      final key          = _classeKey(section, classeNumero);
      final classExc     = config.monthlyExceptionsByClasse[key];
      if (classExc != null && classExc.containsKey(mois)) {
        return classExc[mois]!;
      }
      if (config.feesByClasse.containsKey(key)) {
        return config.feesByClasse[key]!;
      }
    }
    final exc = config.monthlyExceptionsBySection[section];
    if (exc != null && exc.containsKey(mois)) return exc[mois]!;
    return config.feesBySection[section] ?? _montantSecoursSiNonConfigure;
  }

  Map<String, double> getTotalBySection() {
    final totals = <String, double>{};
    for (var e in currentData.eleves) {
      totals[e.section] = (totals[e.section] ?? 0) + getStudentTotalPaid(e);
    }
    return totals;
  }

  Map<String, double> getTotalByClass() {
    final totals = <String, double>{};
    for (var e in currentData.eleves) {
      final key = "${e.section} - ${e.classe}";
      totals[key] = (totals[key] ?? 0) + getStudentTotalPaid(e);
    }
    return totals;
  }

  double getYearTotalCollected() =>
      months.fold(
          0.0,
              (sum, m) =>
          sum +
              currentData.eleves.fold(
                  0.0, (s, e) => s + (e.paid[m] ?? 0)));

  double getCurrentMonthTotalCollected() {
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return 0.0;
    final moisCourant = months[idx];
    return currentData.eleves
        .fold(0.0, (sum, e) => sum + (e.paid[moisCourant] ?? 0));
  }

  // ==========================================================================
  // ⚡ NOUVEAU — Montants collectés (frais principaux) groupés PAR SECTION,
  // pour "Aujourd'hui" et pour "Ce mois-ci". Le total par section pour
  // "Cette année" existe déjà via getTotalBySection().
  // ==========================================================================
  Map<String, double> getMoneyCollectedTodayBySection() {
    final today = DateTime.now().toString().split(' ')[0];
    final Map<String, double> result = {};
    for (final e in currentData.eleves) {
      double sumToday = 0;
      for (final t in e.transactions) {
        if (t['date'] == today) {
          sumToday += (t['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
      if (sumToday != 0) {
        result[e.section] = (result[e.section] ?? 0) + sumToday;
      }
    }
    return result;
  }

  Map<String, double> getMoneyCollectedThisMonthBySection() {
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return {};
    final moisCourant = months[idx];
    final Map<String, double> result = {};
    for (final e in currentData.eleves) {
      final montant = e.paid[moisCourant] ?? 0;
      if (montant != 0) {
        result[e.section] = (result[e.section] ?? 0) + montant;
      }
    }
    return result;
  }

  /// Montant total collecté (frais principaux, toutes sections) pour la
  /// période demandée : 'today', 'month' ou 'year'.
  double getMoneyCollectedForPeriod(String period) {
    switch (period) {
      case 'today':
        return getMoneyCollectedTodayBySection()
            .values
            .fold(0.0, (a, b) => a + b);
      case 'month':
        return getCurrentMonthTotalCollected();
      case 'year':
      default:
        return getYearTotalCollected();
    }
  }

  List<Eleve> getPaidStudentsToday() {
    final today = DateTime.now().toString().split(' ')[0];
    return currentData.eleves
        .where((e) => e.transactions.any((t) => t['date'] == today))
        .toList();
  }

  List<Eleve> getPaidStudentsThisMonth() {
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return [];
    final moisCourant = months[idx];
    return currentData.eleves
        .where((e) =>
    e.paid.containsKey(moisCourant) &&
        e.paid[moisCourant]! > 0)
        .toList();
  }

  Map<String, double> calculateAdminDistribution(double totalAmount) {
    final distribution = <String, double>{};
    for (var admin in config.administrations) {
      distribution[admin.nom] = totalAmount * (admin.pourcentage / 100);
    }
    return distribution;
  }

  double getTotalPourcentageAdministrations() =>
      config.administrations.fold(0.0, (sum, a) => sum + a.pourcentage);

  List<Depense> getDepensesForYear([String? year]) {
    final y = year ?? currentYear;
    final list = List<Depense>.from(depensesByYear[y] ?? []);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  double getTotalDepenses([String? year]) {
    final y = year ?? currentYear;
    return (depensesByYear[y] ?? [])
        .fold(0.0, (sum, d) => sum + d.montant);
  }

  // ==========================================================================
  // ⚡ NOUVEAU — Dépenses "Aujourd'hui" et "Ce mois-ci" (basées sur le mois
  // calendaire de la dépense, faute de notion de "mois scolaire" pour les
  // dépenses).
  // ==========================================================================
  double getTotalDepensesToday([String? year]) {
    final y = year ?? currentYear;
    final today = DateTime.now().toString().split(' ')[0];
    return (depensesByYear[y] ?? [])
        .where((d) => d.date.toString().split(' ')[0] == today)
        .fold(0.0, (sum, d) => sum + d.montant);
  }

  double getTotalDepensesThisMonth([String? year]) {
    final y = year ?? currentYear;
    final now = DateTime.now();
    return (depensesByYear[y] ?? [])
        .where((d) => d.date.year == now.year && d.date.month == now.month)
        .fold(0.0, (sum, d) => sum + d.montant);
  }

  double getSoldeNetActuel([String? year]) {
    final y = year ?? currentYear;
    final totalCollecte = (y == currentYear)
        ? getYearTotalCollected()
        : months.fold<double>(
      0.0,
          (sum, m) =>
      sum +
          (history[y]?.eleves.fold<double>(
              0.0, (s, e) => s + (e.paid[m] ?? 0)) ??
              0.0),
    );
    return totalCollecte - getTotalDepenses(y);
  }

  /// ⚡ NOUVEAU — Solde net (collecté - dépenses) pour une période donnée :
  /// 'today', 'month' ou 'year'.
  double getSoldeNetForPeriod(String period, [String? year]) {
    switch (period) {
      case 'today':
        return getMoneyCollectedForPeriod('today') -
            getTotalDepensesToday(year);
      case 'month':
        return getMoneyCollectedForPeriod('month') -
            getTotalDepensesThisMonth(year);
      case 'year':
      default:
        return getSoldeNetActuel(year);
    }
  }

  Future<Depense> addDepense({
    required String motif,
    required double montant,
    String enregistrePar = 'Direction',
  }) async {
    final depense = Depense(
      id: 'DEP${DateTime.now().millisecondsSinceEpoch}',
      motif: motif.trim(),
      montant: montant,
      date: DateTime.now(),
      enregistrePar: enregistrePar,
    );
    depensesByYear.putIfAbsent(currentYear, () => []).add(depense);
    await saveData();
    return depense;
  }

  Future<void> deleteDepense(String id, [String? year]) async {
    final y = year ?? currentYear;
    depensesByYear[y]?.removeWhere((d) => d.id == id);
    await saveData();
  }

  Future<void> clearDepensesForYear([String? year]) async {
    final y = year ?? currentYear;
    depensesByYear[y] = [];
    await saveData();
  }

  List<AutreFrais> getAutresFrais() {
    final list = List<AutreFrais>.from(autresFrais);
    list.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return list;
  }

  Future<AutreFrais> addAutreFrais({
    required String nom,
    required double montant,
    String scope = 'all',
    String? section,
    String? classe,
  }) async {
    final frais = AutreFrais(
      id: 'AF${DateTime.now().millisecondsSinceEpoch}',
      nom: nom.trim(),
      montant: montant,
      scope: scope,
      section: scope == 'all' ? null : section,
      classe: scope == 'classe' ? classe : null,
    );
    autresFrais.add(frais);
    await saveData();
    return frais;
  }

  Future<void> deleteAutreFrais(String id) async {
    autresFrais.removeWhere((f) => f.id == id);
    await saveData();
  }

  Future<void> updateAutreFrais(
      String id, {
        required String nom,
        required double montant,
        required String scope,
        String? section,
        String? classe,
      }) async {
    for (var f in autresFrais) {
      if (f.id == id) {
        f.nom = nom.trim();
        f.montant = montant;
        f.scope = scope;
        f.section = scope == 'all' ? null : section;
        f.classe = scope == 'classe' ? classe : null;
        break;
      }
    }
    await saveData();
  }

  Future<void> setMontantSectionPourAutreFrais(
      String autreFraisId, String section, double montant) async {
    for (var f in autresFrais) {
      if (f.id == autreFraisId) {
        f.montantsParSection[section] = montant;
        break;
      }
    }
    await saveData();
  }

  Future<void> removeMontantSectionPourAutreFrais(
      String autreFraisId, String section) async {
    for (var f in autresFrais) {
      if (f.id == autreFraisId) {
        f.montantsParSection.remove(section);
        break;
      }
    }
    await saveData();
  }

  Future<void> setMontantClassePourAutreFrais(
      String autreFraisId,
      String section,
      String classeNumero,
      double montant,
      ) async {
    final key = _classeKey(section, classeNumero);
    for (var f in autresFrais) {
      if (f.id == autreFraisId) {
        f.montantsParClasse[key] = montant;
        break;
      }
    }
    await saveData();
  }

  Future<void> removeMontantClassePourAutreFrais(
      String autreFraisId, String section, String classeNumero) async {
    final key = _classeKey(section, classeNumero);
    for (var f in autresFrais) {
      if (f.id == autreFraisId) {
        f.montantsParClasse.remove(key);
        break;
      }
    }
    await saveData();
  }

  bool autreFraisAppliesToStudent(AutreFrais frais, Eleve eleve) {
    switch (frais.scope) {
      case 'section':
        return frais.section != null && eleve.section == frais.section;
      case 'classe':
        return frais.section != null &&
            frais.classe != null &&
            eleve.section == frais.section &&
            classeNumeroFromFullClasse(eleve.classe) == frais.classe;
      case 'all':
      default:
        return true;
    }
  }

  List<Eleve> getEligibleStudentsForAutreFrais(AutreFrais frais) {
    final students = currentData.eleves
        .where((e) => autreFraisAppliesToStudent(frais, e))
        .toList();
    students.sort((a, b) {
      final c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      return a.nom.compareTo(b.nom);
    });
    return students;
  }

  double getMontantAutreFraisPourEleve(AutreFrais frais, Eleve eleve) {
    final classeNumero = classeNumeroFromFullClasse(eleve.classe);
    final classeKey = _classeKey(eleve.section, classeNumero);
    if (frais.montantsParClasse.containsKey(classeKey)) {
      return frais.montantsParClasse[classeKey]!;
    }
    if (frais.montantsParSection.containsKey(eleve.section)) {
      return frais.montantsParSection[eleve.section]!;
    }
    return frais.montant;
  }

  bool hasPaidAutreFrais(Eleve eleve, AutreFrais frais, [String? year]) {
    final y = year ?? currentYear;
    return (autresFraisPaiementsByYear[y] ?? []).any(
            (p) => p.autreFraisId == frais.id && p.eleveId == eleve.id);
  }

  Future<AutreFraisPaiement> payAutreFrais({
    required AutreFrais frais,
    required Eleve eleve,
    String enregistrePar = 'Direction',
  }) async {
    final double montant = getMontantAutreFraisPourEleve(frais, eleve);
    final paiement = AutreFraisPaiement(
      id: 'AFP${DateTime.now().millisecondsSinceEpoch}',
      autreFraisId: frais.id,
      autreFraisNom: frais.nom,
      eleveId: eleve.id,
      montant: montant,
      date: DateTime.now(),
      enregistrePar: enregistrePar,
    );
    autresFraisPaiementsByYear
        .putIfAbsent(currentYear, () => [])
        .add(paiement);
    await saveData();
    return paiement;
  }

  Future<void> deleteAutreFraisPaiement(String id, [String? year]) async {
    final y = year ?? currentYear;
    autresFraisPaiementsByYear[y]?.removeWhere((p) => p.id == id);
    await saveData();
  }

  List<AutreFraisPaiement> getAutresFraisPaiementsForYear([String? year]) {
    final y = year ?? currentYear;
    final list = List<AutreFraisPaiement>.from(
        autresFraisPaiementsByYear[y] ?? []);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  double getTotalPaidForAutreFrais(
      AutreFrais frais, {
        String? year,
        String? sectionFilter,
        String? classFilter,
      }) {
    final y = year ?? currentYear;
    Iterable<AutreFraisPaiement> paiements =
    (autresFraisPaiementsByYear[y] ?? [])
        .where((p) => p.autreFraisId == frais.id);

    if (sectionFilter != null || classFilter != null) {
      paiements = paiements.where((p) {
        Eleve? eleve;
        for (final e in currentData.eleves) {
          if (e.id == p.eleveId) {
            eleve = e;
            break;
          }
        }
        if (eleve == null) return false;
        if (sectionFilter != null && eleve.section != sectionFilter) {
          return false;
        }
        if (classFilter != null && eleve.classe != classFilter) {
          return false;
        }
        return true;
      });
    }

    return paiements.fold(0.0, (sum, p) => sum + p.montant);
  }

  Map<String, double> calculateAutresFraisAdminDistribution(
      double totalAmount) {
    final distribution = <String, double>{};
    for (var admin in autresFraisAdministrations) {
      distribution[admin.nom] = totalAmount * (admin.pourcentage / 100);
    }
    return distribution;
  }

  double getTotalPourcentageAutresFraisAdministrations() =>
      autresFraisAdministrations.fold(0.0, (sum, a) => sum + a.pourcentage);

  Map<String, double> getAdminDistributionForAutreFrais(
      AutreFrais frais, {
        String? year,
        String? sectionFilter,
        String? classFilter,
      }) {
    final double total = getTotalPaidForAutreFrais(
      frais,
      year: year,
      sectionFilter: sectionFilter,
      classFilter: classFilter,
    );
    return calculateAutresFraisAdminDistribution(total);
  }

  List<AutreFraisAdministration> getAutresFraisAdministrations() =>
      List<AutreFraisAdministration>.from(autresFraisAdministrations);

  Future<AutreFraisAdministration> addAutreFraisAdministration({
    required String nom,
    required double pourcentage,
  }) async {
    final admin = AutreFraisAdministration(
      id: 'AFA${DateTime.now().millisecondsSinceEpoch}',
      nom: nom.trim(),
      pourcentage: pourcentage,
    );
    autresFraisAdministrations.add(admin);
    await saveData();
    return admin;
  }

  Future<void> updateAutreFraisAdministration(
      String id, {
        required String nom,
        required double pourcentage,
      }) async {
    for (var a in autresFraisAdministrations) {
      if (a.id == id) {
        a.nom = nom.trim();
        a.pourcentage = pourcentage;
        break;
      }
    }
    await saveData();
  }

  Future<void> deleteAutreFraisAdministration(String id) async {
    autresFraisAdministrations.removeWhere((a) => a.id == id);
    await saveData();
  }

  List<String> getOptions() => List<String>.from(config.sections);

  RepartitionDetail getRepartitionForOption(String option) =>
      getRepartitionForOptionPeriod(option, 'year');

  /// ⚡ NOUVEAU — Répartition (total + par administration) pour une
  /// section (option) donnée, sur la période demandée : 'today', 'month'
  /// ou 'year'.
  RepartitionDetail getRepartitionForOptionPeriod(
      String option, String period) {
    double total;
    switch (period) {
      case 'today':
        total = getMoneyCollectedTodayBySection()[option] ?? 0.0;
        break;
      case 'month':
        total = getMoneyCollectedThisMonthBySection()[option] ?? 0.0;
        break;
      case 'year':
      default:
        total = getStudentsBySection(option)
            .fold(0.0, (sum, e) => sum + getStudentTotalPaid(e));
    }
    return RepartitionDetail(
      label: option,
      total: total,
      parAdministration: calculateAdminDistribution(total),
    );
  }

  String _sousSectionLabelFor(Eleve eleve) {
    final sousClasse = subClasseFromFullClasse(eleve.classe);
    if (sousClasse != null && sousClasse.trim().isNotEmpty) {
      return sousClasse.trim();
    }
    final numero = classeNumeroFromFullClasse(eleve.classe);
    return "Éducation de Base ($numero)";
  }

  /// ⚡ NOUVEAU — Montant payé par un élève pour une période donnée :
  /// 'today' (transactions du jour), 'month' (mois scolaire en cours) ou
  /// 'year' (total annuel déjà payé).
  double _getStudentAmountForPeriod(Eleve eleve, String period) {
    switch (period) {
      case 'today':
        final today = DateTime.now().toString().split(' ')[0];
        double sum = 0;
        for (final t in eleve.transactions) {
          if (t['date'] == today) {
            sum += (t['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
        return sum;
      case 'month':
        final idx = _schoolMonthIndexForToday();
        if (idx < 0 || idx >= months.length) return 0.0;
        return eleve.paid[months[idx]] ?? 0.0;
      case 'year':
      default:
        return getStudentTotalPaid(eleve);
    }
  }

  List<RepartitionDetail> getSousSectionsForOption(String option) =>
      getSousSectionsForOptionPeriod(option, 'year');

  /// ⚡ NOUVEAU — Répartition par sous-section (classe pédagogique) pour la
  /// période demandée.
  List<RepartitionDetail> getSousSectionsForOptionPeriod(
      String option, String period) {
    final students = getStudentsBySection(option);
    final Map<String, double> totalsByLabel = {};
    for (var e in students) {
      final label = _sousSectionLabelFor(e);
      final montant = _getStudentAmountForPeriod(e, period);
      totalsByLabel[label] = (totalsByLabel[label] ?? 0) + montant;
    }
    final details = totalsByLabel.entries
        .map((entry) => RepartitionDetail(
      label: entry.key,
      total: entry.value,
      parAdministration: calculateAdminDistribution(entry.value),
    ))
        .toList();
    details.sort((a, b) {
      final aBase = a.label.startsWith("Éducation de Base");
      final bBase = b.label.startsWith("Éducation de Base");
      if (aBase && !bBase) return -1;
      if (!aBase && bBase) return 1;
      return a.label.compareTo(b.label);
    });
    return details;
  }

  bool optionHasSousSections(String option) {
    return getStudentsBySection(option).any((e) {
      final sc = subClasseFromFullClasse(e.classe);
      return sc != null && sc.trim().isNotEmpty;
    });
  }

  List<double> getMonthlyEvolution({
    String? option,
    String? sousSectionLabel,
    String? classe,
  }) {
    List<Eleve> students = currentData.eleves;
    if (option != null) {
      students = students.where((e) => e.section == option).toList();
    }
    if (sousSectionLabel != null) {
      students = students
          .where((e) => _sousSectionLabelFor(e) == sousSectionLabel)
          .toList();
    }
    if (classe != null) {
      students = students.where((e) => e.classe == classe).toList();
    }
    return months
        .map((m) =>
        students.fold<double>(0.0, (sum, e) => sum + (e.paid[m] ?? 0)))
        .toList();
  }

  List<String> getClassesForOptionAndSousSection(
      String option, [
        String? sousSectionLabel,
      ]) {
    final classes = getAllDisplayClassesForSection(option);
    if (sousSectionLabel == null) return classes;
    return classes.where((c) {
      final sousClasse = subClasseFromFullClasse(c);
      final label = (sousClasse != null && sousClasse.trim().isNotEmpty)
          ? sousClasse.trim()
          : "Éducation de Base (${classeNumeroFromFullClasse(c)})";
      return label == sousSectionLabel;
    }).toList();
  }

  bool isStudentEnOrdrePourMois(Eleve eleve, String mois) {
    final required     = getRequiredForMonth(mois, eleve.section, eleve.classe);
    final paidForMonth = eleve.paid[mois] ?? 0;
    return paidForMonth >= required;
  }

  List<Eleve> getStudentsByOrderStatus({
    required String mois,
    required bool enOrdre,
    String? sectionFilter,
    String? classFilter,
  }) {
    List<Eleve> students = currentData.eleves;
    if (sectionFilter != null) {
      students = students.where((e) => e.section == sectionFilter).toList();
    }
    if (classFilter != null) {
      students = students.where((e) => e.classe == classFilter).toList();
    }
    students = students
        .where((e) => isStudentEnOrdrePourMois(e, mois) == enOrdre)
        .toList();

    students.sort((a, b) {
      final c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      return a.nom.compareTo(b.nom);
    });
    return students;
  }

  void recalculerRepartitionMoisPourEleve(Eleve eleve) {
    if (eleve.transactions.isEmpty) {
      final double totalPayeSansTransactions = getStudentTotalPaid(eleve);
      if (totalPayeSansTransactions > 0) {
        double restant = totalPayeSansTransactions;
        final Map<String, double> paidSansTransactions = {};
        for (final mois in months) {
          if (restant <= 0) break;
          final double requis =
          getRequiredForMonth(mois, eleve.section, eleve.classe);
          if (requis <= 0) continue;
          final double aAffecter = restant >= requis ? requis : restant;
          paidSansTransactions[mois] = aAffecter;
          restant -= aAffecter;
        }
        if (restant > 0 && months.isNotEmpty) {
          final dernierMois = months.last;
          paidSansTransactions[dernierMois] =
              (paidSansTransactions[dernierMois] ?? 0) + restant;
        }
        eleve.paid
          ..clear()
          ..addAll(paidSansTransactions);
        _rafraichirRecusEnAttentePourEleve(eleve);
        return;
      }
      eleve.paid.clear();
      _rafraichirRecusEnAttentePourEleve(eleve);
      return;
    }

    final indexees = <MapEntry<int, Map<String, dynamic>>>[
      for (var i = 0; i < eleve.transactions.length; i++)
        MapEntry(i, eleve.transactions[i]),
    ];
    indexees.sort((a, b) {
      final parDate = (a.value['date'] ?? '')
          .toString()
          .compareTo((b.value['date'] ?? '').toString());
      if (parDate != 0) return parDate;
      return a.key.compareTo(b.key);
    });

    final Map<String, double> nouveauPaid = {};
    int monthIndex = 0;

    for (final transaction in indexees.map((e) => e.value)) {
      final double montant =
          (transaction['amount'] as num?)?.toDouble() ?? 0.0;
      if (montant <= 0) continue;

      while (monthIndex < months.length) {
        final mois = months[monthIndex];
        final requis =
        getRequiredForMonth(mois, eleve.section, eleve.classe);
        final dejaAffecte = nouveauPaid[mois] ?? 0;
        if (requis > 0 && dejaAffecte < requis) break;
        monthIndex++;
      }

      if (monthIndex < months.length) {
        final mois = months[monthIndex];
        transaction['mois'] = mois;
        nouveauPaid[mois] = (nouveauPaid[mois] ?? 0) + montant;
      } else if (months.isNotEmpty) {
        final dernierMois = months.last;
        transaction['mois'] = dernierMois;
        transaction['excedent'] = true;
        nouveauPaid[dernierMois] = (nouveauPaid[dernierMois] ?? 0) + montant;
      }
    }

    eleve.paid
      ..clear()
      ..addAll(nouveauPaid);

    _rafraichirRecusEnAttentePourEleve(eleve);
  }

  void _rafraichirRecusEnAttentePourEleve(Eleve eleve) {
    for (var i = 0; i < receiptQueue.length; i++) {
      final r = receiptQueue[i];
      if (r['type'] != 'principal' || r['eleveId'] != eleve.id) continue;

      final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
      final mois = data['moisPaye']?.toString() ?? '';
      if (mois.isEmpty) continue;

      final double montantRequis =
      getRequiredForMonth(mois, eleve.section, eleve.classe);
      final double totalPaye = getStudentTotalPaid(eleve);
      final double totalRequis = getStudentPending(eleve) + totalPaye;
      final double resteBrut = montantRequis - (eleve.paid[mois] ?? 0);
      final double reste = resteBrut < 0 ? 0.0 : resteBrut;

      data['montantRequis']      = montantRequis;
      data['resteAPayerMois']    = reste;
      data['totalDejaPayeAnnee'] = totalPaye;
      data['totalRequis']        = totalRequis;
      data['historiqueTransactions'] = eleve.transactions
          .map((t) => Map<String, dynamic>.from(t))
          .toList();

      receiptQueue[i] = {...r, 'data': data};
    }
  }

  Future<int> recalculerPaiementsPour({
    String? section,
    String? classeNumero,
  }) async {
    int count = 0;
    for (final eleve in currentData.eleves) {
      if (section != null && eleve.section != section) continue;
      if (classeNumero != null &&
          classeNumeroFromFullClasse(eleve.classe) != classeNumero) {
        continue;
      }
      recalculerRepartitionMoisPourEleve(eleve);
      count++;
    }
    await saveData();
    return count;
  }

  Future<int> recalculerPaiementsPourModeConstant({
    String? section,
    String? classeNumero,
    required Map<String, double> anciensRequisParMois,
  }) async {
    int count = 0;
    for (final eleve in currentData.eleves) {
      if (section != null && eleve.section != section) continue;
      if (classeNumero != null &&
          classeNumeroFromFullClasse(eleve.classe) != classeNumero) {
        continue;
      }

      bool modifie = false;
      for (final mois in anciensRequisParMois.keys) {
        final double? ancienRequis = anciensRequisParMois[mois];
        if (ancienRequis == null) continue;

        final double nouveauRequis =
        getRequiredForMonth(mois, eleve.section, eleve.classe);

        if (nouveauRequis >= ancienRequis) continue;

        final double paidActuel = eleve.paid[mois] ?? 0;
        if (paidActuel > nouveauRequis) {
          eleve.paid[mois] = nouveauRequis;
          modifie = true;
        }
      }

      if (modifie) {
        count++;
        _rafraichirRecusEnAttentePourEleve(eleve);
      }
    }
    await saveData();
    return count;
  }

  Map<String, double> snapshotRequisTousMoisPour(
      String section, String? classeNumero) {
    return {
      for (final m in months) m: getRequiredForMonth(m, section, classeNumero),
    };
  }

  Map<String, dynamic> _computeStudentCounts(List<Eleve> students) {
    final Map<String, int> parSection = {};
    final Map<String, int> parClasse = {};

    for (final e in students) {
      parSection[e.section] = (parSection[e.section] ?? 0) + 1;
      final classeKey = "${e.section} - ${e.classe}";
      parClasse[classeKey] = (parClasse[classeKey] ?? 0) + 1;
    }

    final sectionsTriees = parSection.keys.toList()..sort();
    final classesTriees = parClasse.keys.toList()..sort();

    return {
      'total': students.length,
      'parSection': {
        for (final s in sectionsTriees) s: parSection[s]!,
      },
      'parClasse': {
        for (final c in classesTriees) c: parClasse[c]!,
      },
    };
  }

  List<pw.Widget> _buildStudentCountSection(
      List<Eleve> students, {
        String label = "Élèves concernés par ce rapport",
      }) {
    final counts = _computeStudentCounts(students);
    final int total = counts['total'] as int;
    final Map<String, int> parSection =
    Map<String, int>.from(counts['parSection'] as Map);
    final Map<String, int> parClasse =
    Map<String, int>.from(counts['parClasse'] as Map);

    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo50,
          border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "NOMBRE D'ÉLÈVES — $label",
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              "Total général : $total élève(s)",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (parSection.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                "Par section :",
                style: pw.TextStyle(
                    fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              ...parSection.entries.map(
                    (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, bottom: 1),
                  child: pw.Text(
                    "• ${entry.key} : ${entry.value} élève(s)",
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ],
            if (parClasse.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                "Par classe :",
                style: pw.TextStyle(
                    fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              ...parClasse.entries.map(
                    (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, bottom: 1),
                  child: pw.Text(
                    "• ${entry.key} : ${entry.value} élève(s)",
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  // ==========================================================================
  // ⚡ NOUVEAU — RÉPARTITION PAR SECTION ET PAR ADMINISTRATION
  //
  // Inspiré du modèle papier fourni ("RAPPORT FINANCIER MOIS DE ...") :
  // un grand tableau où chaque LIGNE est une section de l'école, chaque
  // COLONNE est une administration configurée (avec son pourcentage), et
  // chaque cellule est le montant qui revient à cette administration pour
  // cette section. Une dernière colonne donne le Total (FC) de la
  // section. Juste en dessous, un second petit tableau (mis en
  // évidence) donne le TOTAL GÉNÉRAL toutes sections et classes
  // confondues — exactement la répartition globale déjà calculée
  // ailleurs dans le rapport, mais présentée ici sous forme de tableau
  // pour rester cohérente avec le tableau détaillé par section.
  //
  // N'est affiché que lorsque le rapport couvre TOUTES les sections ET
  // TOUTES les classes (aucun filtre Section/Classe appliqué), puisque
  // c'est le seul cas où une ventilation par section a du sens.
  //
  // `students` doit déjà être la liste des élèves correspondant au type
  // de rapport demandé (journalier / mensuel / annuel) — la même liste
  // que celle utilisée pour construire le tableau principal du rapport.
  // ==========================================================================
  List<pw.Widget> _buildRepartitionParSectionEtAdministration(
      List<Eleve> students) {
    if (config.administrations.isEmpty || students.isEmpty) return [];

    // Total (frais principal) par section, pour les élèves du rapport.
    final Map<String, double> totalBySection = {};
    for (final e in students) {
      totalBySection[e.section] =
          (totalBySection[e.section] ?? 0) + getStudentTotalPaid(e);
    }
    totalBySection.removeWhere((_, v) => v <= 0);
    if (totalBySection.isEmpty) return [];

    // On respecte l'ordre des sections tel que défini dans la
    // configuration de l'école, puis on ajoute en fin de liste les
    // sections "orphelines" (non présentes dans la config), triées par
    // ordre alphabétique, pour ne perdre aucune donnée.
    final List<String> sectionsOrdonnees = [
      ...config.sections.where((s) => totalBySection.containsKey(s)),
      ...(totalBySection.keys
          .where((s) => !config.sections.contains(s))
          .toList()
        ..sort()),
    ];

    final headers = [
      'Section',
      'Effectif',
      'Montant Total (FC)',
      ...config.administrations
          .map((a) => '${a.nom}\n(${a.pourcentage.toStringAsFixed(0)}%)'),
    ];

    final Map<String, int> effectifParSection = {};
    for (final e in students) {
      if ((totalBySection[e.section] ?? 0) <= 0) continue;
      effectifParSection[e.section] =
          (effectifParSection[e.section] ?? 0) + 1;
    }

    final rows = <List<String>>[];
    for (final section in sectionsOrdonnees) {
      final double total = totalBySection[section] ?? 0;
      final dist = calculateAdminDistribution(total);
      rows.add([
        section,
        '${effectifParSection[section] ?? 0}',
        total.toStringAsFixed(0),
        ...config.administrations
            .map((a) => (dist[a.nom] ?? 0).toStringAsFixed(0)),
      ]);
    }

    final double totalGeneral =
    totalBySection.values.fold(0.0, (sum, v) => sum + v);
    final int effectifGeneral =
    effectifParSection.values.fold(0, (sum, v) => sum + v);
    final distGenerale = calculateAdminDistribution(totalGeneral);

    final columnWidths = _buildColumnWidths([
      1.7,
      0.9,
      1.5,
      ...List<double>.filled(config.administrations.length, 1.3),
    ]);
    final double cellFontSize = _tableCellFontSize(headers.length);
    final double headerFontSize = _tableHeaderFontSize(headers.length);

    return [
      pw.Text(
        "RÉPARTITION PAR SECTION ET PAR ADMINISTRATION",
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        "Détail du montant collecté et de sa répartition entre "
            "administrations, section par section. Le total général "
            "toutes sections et classes confondues figure dans le "
            "tableau récapitulatif juste en dessous.",
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        columnWidths: columnWidths,
        headerStyle: pw.TextStyle(
          fontSize: headerFontSize,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
        headerAlignment: pw.Alignment.center,
        cellStyle: pw.TextStyle(fontSize: cellFontSize),
        cellAlignment: pw.Alignment.centerRight,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
        },
        cellPadding:
        const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
      ),
      pw.SizedBox(height: 16),
      // ---- Petit tableau récapitulatif : TOTAL GÉNÉRAL toutes sections
      // et classes confondues, clairement mis en évidence. ----
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo50,
          border: pw.Border.all(color: PdfColors.indigo400, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "TOTAL GÉNÉRAL — TOUTES SECTIONS ET CLASSES CONFONDUES "
                  "($effectifGeneral élève(s))",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: [
                'Montant Total (FC)',
                ...config.administrations.map((a) =>
                '${a.nom}\n(${a.pourcentage.toStringAsFixed(0)}%)'),
              ],
              data: [
                [
                  totalGeneral.toStringAsFixed(0),
                  ...config.administrations.map(
                          (a) => (distGenerale[a.nom] ?? 0).toStringAsFixed(0)),
                ],
              ],
              columnWidths: _buildColumnWidths([
                1.5,
                ...List<double>.filled(config.administrations.length, 1.3),
              ]),
              headerStyle: pw.TextStyle(
                fontSize: headerFontSize,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo900),
              headerAlignment: pw.Alignment.center,
              cellStyle: pw.TextStyle(
                fontSize: cellFontSize + 0.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo900,
              ),
              cellAlignment: pw.Alignment.center,
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 24),
    ];
  }

  List<pw.Widget> _buildCenteredReportHeader({
    required String title,
    String? subtitle,
  }) {
    return [
      pw.Center(
        child: pw.Text(
          config.schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ),
      if (subtitle != null && subtitle.trim().isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            subtitle,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          'Généré le : $_dateGenerationFormatee',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ),
      pw.SizedBox(height: 16),
      pw.Divider(thickness: 1),
      pw.SizedBox(height: 10),
    ];
  }

  Future<Map<String, dynamic>> generatePdf({
    required String filename,
    required String reportType,
    String? sectionFilter,
    String? classFilter,
    String? city,
  }) async {
    if (reportType == "student_list") {
      return await _generateStudentListPdf(
        filename:      filename,
        sectionFilter: sectionFilter,
        classFilter:   classFilter,
        city:          city,
      );
    }

    final pdf     = pw.Document();
    List<Eleve> students;
    String title;
    String countLabel;

    if (reportType == "daily") {
      students = getPaidStudentsToday();
      title    = "RAPPORT JOURNALIER";
      countLabel = "ont payé aujourd'hui";
    } else if (reportType == "monthly") {
      students = getPaidStudentsThisMonth();
      title    = "RAPPORT MENSUEL";
      countLabel = "ont payé ce mois-ci";
    } else {
      students = currentData.eleves;
      title    = "RAPPORT ANNUEL";
      countLabel = "figurent dans ce rapport";
    }

    // ⚡ NOUVEAU — La ventilation par section n'a de sens que si le rapport
    // couvre TOUTES les sections ET TOUTES les classes (aucun filtre
    // appliqué). On capture donc la liste des élèves AVANT application
    // des filtres Section/Classe, pour construire ce tableau plus loin.
    final List<Eleve> studentsAvantFiltres = List<Eleve>.from(students);
    final bool afficherRepartitionParSection =
        sectionFilter == null && classFilter == null;

    if (sectionFilter != null) {
      students = students
          .where((e) => e.section == sectionFilter)
          .toList();
      title += " - $sectionFilter";
    }
    if (classFilter != null) {
      students = students
          .where((e) => e.classe == classFilter)
          .toList();
      title += " - $classFilter";
    }

    final double total              = students.fold(
        0.0, (sum, e) => sum + getStudentTotalPaid(e));
    final adminDistribution         = calculateAdminDistribution(total);
    final double totalMoisEcole     = getCurrentMonthTotalCollected();
    final double totalAnneeEcole    = getYearTotalCollected();
    final String currentMonthName =
        currentSchoolMonthName ?? "Hors année scolaire (vacances)";
    final bool showMoisConcerne = reportType == "daily";

    final headers = [
      'ID', 'Nom Complet', 'Section', 'Classe', 'Montant Payé (FC)',
      if (showMoisConcerne) 'Mois Concerné(s)',
      ...config.administrations.map(
              (a) => '${a.nom} (${a.pourcentage.toStringAsFixed(0)}%)'),
    ];

    final rows = students.map((e) {
      final montant = getStudentTotalPaid(e);
      final row = [
        e.id.isNotEmpty ? e.id : "N/A",
        "${e.nom} ${e.postNom} ${e.prenom}",
        e.section,
        e.classe,
        montant.toStringAsFixed(0),
      ];
      if (showMoisConcerne) {
        final moisConcernes = getMoisPayesPourDate(e);
        row.add(moisConcernes.isNotEmpty
            ? moisConcernes
            : (currentSchoolMonthName ?? '-'));
      }
      for (var admin in config.administrations) {
        row.add(
            (montant * (admin.pourcentage / 100)).toStringAsFixed(0));
      }
      return row;
    }).toList();
    final List<double> recapMensuel =
    reportType == "annual" ? getMonthlyEvolution() : const [];

    final List<double> mainTableFlex = [
      0.7,
      2.5,
      1.1,
      1.3,
      1.3,
      if (showMoisConcerne) 1.7,
      ...List<double>.filled(config.administrations.length, 1.3),
    ];
    final mainTableColumnWidths = _buildColumnWidths(mainTableFlex);
    final double mainCellFontSize = _tableCellFontSize(headers.length);
    final double mainHeaderFontSize = _tableHeaderFontSize(headers.length);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          ..._buildCenteredReportHeader(
            title: title,
            subtitle: 'Année scolaire $currentYear',
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.indigo50,
              border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.indigo900,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  "Total ce Mois ($currentMonthName) : "
                      "${totalMoisEcole.toStringAsFixed(0)} FC",
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  "Total cette Année ($currentYear) : "
                      "${totalAnneeEcole.toStringAsFixed(0)} FC",
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          ..._buildStudentCountSection(students, label: countLabel),
          pw.SizedBox(height: 16),
          pw.Text("LISTE DES ÉLÈVES",
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers:   headers,
            data:      rows,
            columnWidths: mainTableColumnWidths,
            headerStyle: pw.TextStyle(
                fontSize: mainHeaderFontSize,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo),
            cellStyle: pw.TextStyle(fontSize: mainCellFontSize),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            oddRowDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo50),
          ),
          if (reportType == "annual") ...[
            pw.SizedBox(height: 26),
            pw.Text("RÉCAPITULATIF MENSUEL",
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: const ['Mois', 'Total Collecté (FC)'],
              data: List<List<String>>.generate(
                months.length,
                    (i) => [
                  months[i],
                  (i < recapMensuel.length ? recapMensuel[i] : 0.0)
                      .toStringAsFixed(0),
                ],
              ),
              columnWidths: _buildColumnWidths([1.4, 1]),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
              },
              oddRowDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo50),
            ),
          ],
          pw.SizedBox(height: 30),
          // ⚡ NOUVEAU — Tableau détaillé de répartition PAR SECTION et par
          // administration, affiché uniquement lorsque le rapport couvre
          // toutes les sections et toutes les classes (aucun filtre).
          if (afficherRepartitionParSection)
            ..._buildRepartitionParSectionEtAdministration(
                studentsAvantFiltres),
          pw.Text(
            "RÉPARTITION GLOBALE PAR ADMINISTRATION",
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          ...adminDistribution.entries.map(
                (entry) => pw.Text(
              "${entry.key} : ${entry.value.toStringAsFixed(0)} FC "
                  "(${config.administrations.firstWhere((a) => a.nom == entry.key).pourcentage.toStringAsFixed(0)}%)",
            ),
          ),

          ..._buildSignatureSection(city),
        ],
      ),
    );

    return await _savePdf(pdf, filename, reportType);
  }

  Future<Map<String, dynamic>> _generateStudentListPdf({
    required String filename,
    String? sectionFilter,
    String? classFilter,
    String? city,
  }) async {
    List<Eleve> students = currentData.eleves;
    if (sectionFilter != null) {
      students =
          students.where((e) => e.section == sectionFilter).toList();
    }
    if (classFilter != null) {
      students =
          students.where((e) => e.classe == classFilter).toList();
    }
    students.sort((a, b) {
      final c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      return a.nom.compareTo(b.nom);
    });

    final sectionLabel = sectionFilter ?? "Toutes les sections";
    final classeLabel  = classFilter   ?? "Toutes les classes";
    final dateStr      = _dateGenerationFormatee;

    final rows = <List<String>>[];
    for (int i = 0; i < students.length; i++) {
      final e = students[i];
      rows.add(['${i + 1}', e.nom, e.postNom, e.prenom, e.classe]);
    }

    final columnWidths = _buildColumnWidths([0.5, 1.6, 1.6, 1.6, 1.5]);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "REGISTRE DES ÉLÈVES — Année $currentYear",
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel | Classe : $classeLabel",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Imprimé le : $dateStr | Total : ${students.length} élève(s)",
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['N°', 'Nom', 'Post-nom', 'Prénom', 'Classe'],
            data:    rows,
            columnWidths: columnWidths,
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo),
            cellStyle:   const pw.TextStyle(fontSize: 10),
            cellHeight:  22,
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerLeft,
            },
            oddRowDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo50),
          ),
          ..._buildSignatureSection(city),
        ],
      ),
    );

    return await _savePdf(pdf, filename, "student_list");
  }

  Future<Map<String, dynamic>> generateOrderStatusPdf({
    required String filename,
    required String mois,
    required bool enOrdre,
    String? sectionFilter,
    String? classFilter,
  }) async {
    final students = getStudentsByOrderStatus(
      mois:          mois,
      enOrdre:       enOrdre,
      sectionFilter: sectionFilter,
      classFilter:   classFilter,
    );

    final sectionLabel = sectionFilter ?? "Toutes les sections";
    final classeLabel  = classFilter   ?? "Toutes les classes";
    final dateStr      = _dateGenerationFormatee;
    final statutLabel  =
    enOrdre ? "QUI ONT DÉJÀ PAYÉ" : "QUI N'ONT PAS ENCORE PAYÉ";

    final title = "LISTE DES ÉLÈVES DE $classeLabel - $sectionLabel "
        "DU $dateStr $statutLabel $mois";

    final rows = <List<String>>[];
    for (int i = 0; i < students.length; i++) {
      final e              = students[i];
      final montantPaye    = e.paid[mois] ?? 0;
      final montantRequis  =
      getRequiredForMonth(mois, e.section, e.classe);
      rows.add([
        '${i + 1}',
        e.nom,
        e.postNom,
        e.prenom,
        e.section,
        e.classe,
        '${montantPaye.toStringAsFixed(0)} / ${montantRequis.toStringAsFixed(0)} FC',
      ]);
    }

    final columnWidths =
    _buildColumnWidths([0.5, 1.4, 1.4, 1.4, 1.1, 1.3, 1.8]);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel | Classe : $classeLabel | Mois : $mois",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Année $currentYear | Imprimé le : $dateStr | "
                  "Total : ${students.length} élève(s)",
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'N°', 'Nom', 'Post-nom', 'Prénom', 'Section', 'Classe',
              'Payé / Requis ($mois)',
            ],
            data: rows,
            columnWidths: columnWidths,
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(
              color: enOrdre ? PdfColors.green700 : PdfColors.red700,
            ),
            cellStyle:  const pw.TextStyle(fontSize: 9),
            cellHeight: 22,
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.centerLeft,
              6: pw.Alignment.center,
            },
            oddRowDecoration: pw.BoxDecoration(
              color: enOrdre ? PdfColors.green50 : PdfColors.red50,
            ),
          ),
        ],
      ),
    );

    return await _savePdf(
      pdf,
      filename,
      enOrdre ? 'en_ordre_$mois' : 'pas_en_ordre_$mois',
    );
  }

  Future<Map<String, dynamic>> generateAutresFraisPdf({
    required String filename,
    String? autreFraisId,
    String? sectionFilter,
    String? classFilter,
    String? city,
  }) async {
    AutreFrais? fraisSelectionne;
    if (autreFraisId != null) {
      for (final f in autresFrais) {
        if (f.id == autreFraisId) {
          fraisSelectionne = f;
          break;
        }
      }
    }

    var paiements = getAutresFraisPaiementsForYear();
    if (autreFraisId != null) {
      paiements =
          paiements.where((p) => p.autreFraisId == autreFraisId).toList();
    }

    final rows = <List<String>>[];
    double total = 0;
    final Map<String, Eleve> elevesDistincts = {};

    for (final p in paiements) {
      Eleve? eleve;
      for (final e in currentData.eleves) {
        if (e.id == p.eleveId) {
          eleve = e;
          break;
        }
      }
      final section = eleve?.section ?? '';
      final classe  = eleve?.classe  ?? '';
      if (sectionFilter != null && section != sectionFilter) continue;
      if (classFilter != null && classe != classFilter) continue;

      rows.add([
        (eleve != null && eleve.id.isNotEmpty) ? eleve.id : 'N/A',
        eleve != null
            ? "${eleve.nom} ${eleve.postNom} ${eleve.prenom}"
            : "Élève introuvable",
        section.isEmpty ? '-' : section,
        classe.isEmpty ? '-' : classe,
        p.autreFraisNom,
        p.montant.toStringAsFixed(0),
        p.dateFormatee,
      ]);
      total += p.montant;

      if (eleve != null) {
        elevesDistincts[eleve.id] = eleve;
      }
    }

    final adminDistribution = calculateAutresFraisAdminDistribution(total);

    String title = "RAPPORT — AUTRES FRAIS DE PAIEMENT";
    if (fraisSelectionne != null) {
      title += " : ${fraisSelectionne.nom}";
    } else if (autreFraisId != null) {
      title += paiements.isNotEmpty
          ? " : ${paiements.first.autreFraisNom}"
          : "";
    } else {
      title += " (TOUS TYPES CONFONDUS)";
    }
    if (sectionFilter != null) title += " - $sectionFilter";
    if (classFilter != null) title += " - $classFilter";

    final headers = [
      'ID', 'Nom Complet', 'Section', 'Classe', 'Type de Frais',
      'Montant (FC)', 'Date de Paiement',
    ];

    final columnWidths =
    _buildColumnWidths([0.6, 2.1, 1.0, 1.1, 1.5, 1.0, 1.3]);
    final double cellFontSize = _tableCellFontSize(headers.length);
    final double headerFontSize = _tableHeaderFontSize(headers.length);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          ..._buildCenteredReportHeader(
            title: title,
            subtitle: 'Année scolaire $currentYear',
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.indigo50,
              border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.indigo900,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  "Nombre de paiements : ${rows.length}",
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          ..._buildStudentCountSection(
            elevesDistincts.values.toList(),
            label: "ont payé au moins un frais de ce rapport",
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            "DÉTAIL DES PAIEMENTS",
            style:
            pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (rows.isEmpty)
            pw.Text(
              "Aucun paiement enregistré pour ce filtre.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              columnWidths: columnWidths,
              headerStyle: pw.TextStyle(
                  fontSize: headerFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo),
              cellStyle: pw.TextStyle(fontSize: cellFontSize),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              oddRowDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo50),
            ),
          pw.SizedBox(height: 30),
          pw.Text(
            "RÉPARTITION GLOBALE PAR ADMINISTRATION (AUTRES FRAIS)",
            style:
            pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (autresFraisAdministrations.isEmpty)
            pw.Text(
              "Aucune administration configurée pour les Autres Frais.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else if (total == 0)
            pw.Text(
              "Aucun montant à répartir pour ce filtre.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            ...adminDistribution.entries.map(
                  (entry) => pw.Text(
                "${entry.key} : ${entry.value.toStringAsFixed(0)} FC "
                    "(${autresFraisAdministrations.firstWhere((a) => a.nom == entry.key).pourcentage.toStringAsFixed(0)}%)",
              ),
            ),
          ..._buildSignatureSection(city),
        ],
      ),
    );

    return await _savePdf(pdf, filename, "autres_frais");
  }

  Future<Map<String, dynamic>> _savePdf(
      pw.Document pdf, String filename, String reportType) async {
    try {
      final bytes     = await pdf.save();
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        final fileName =
            '${filename}_${reportType}_${DateTime.now().toString().split(' ')[0]}.pdf';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
        return {'success': true, 'path': file.path};
      } else {
        final saveLocation = await getSaveLocation(
          suggestedName: '${filename}_$reportType.pdf',
          acceptedTypeGroups: [
            XTypeGroup(label: 'PDF', extensions: ['pdf'])
          ],
        );
        if (saveLocation != null) {
          final file = File(saveLocation.path);
          await file.writeAsBytes(bytes);
          await OpenFile.open(file.path);
          return {'success': true, 'path': file.path};
        }
        return {'success': false, 'error': 'Enregistrement annulé.'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
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
      'autresFraisAdministrations':
      autresFraisAdministrations.map((a) => a.toJson()).toList(),
      'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
      'signataires': signataires.map((s) => s.toJson()).toList(),
      'localAccessKeys': localAccessKeys,
      'localPendingPayments': localPendingPayments,
      'localPendingRegistrations': localPendingRegistrations,
      'localPendingAutresFraisPayments': localPendingAutresFraisPayments,
      'localAttendance': localAttendance,
      'localCommunicationsLog': localCommunicationsLog,
      'printedReceiptKeys': printedReceiptKeys,
      'receiptQueue': receiptQueue,
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
    autresFraisAdministrations = [];
    adminAuditLog = [];
    signataires = [];
    localAccessKeys = [];
    localPendingPayments = [];
    localPendingRegistrations = [];
    localPendingAutresFraisPayments = [];
    localAttendance = {};
    localCommunicationsLog = [];
    printedReceiptKeys = [];
    receiptQueue = [];
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

  List<Map<String, dynamic>> handlePayment(
      Eleve eleve, String mois, double payment) {
    int    index     = months.indexOf(mois);
    if (index == -1) return [];

    final String today     = DateTime.now().toString().split(' ')[0];
    double       remaining = payment;
    String       currentMonth = mois;
    final List<Map<String, dynamic>> nouvellesTransactions = [];

    String genererIdTransaction() =>
        'TX${DateTime.now().microsecondsSinceEpoch}_${nouvellesTransactions.length}';

    while (remaining > 0 && index < months.length) {
      double required    =
      getRequiredForMonth(currentMonth, eleve.section, eleve.classe);
      double alreadyPaid = eleve.paid[currentMonth] ?? 0;
      double needed      = required - alreadyPaid;

      if (needed > 0) {
        double toAdd = remaining > needed ? needed : remaining;
        eleve.paid[currentMonth] = alreadyPaid + toAdd;
        final transaction = <String, dynamic>{
          'id': genererIdTransaction(),
          'date':   today,
          'mois':   currentMonth,
          'amount': toAdd,
        };
        eleve.transactions.add(transaction);
        nouvellesTransactions.add(transaction);
        remaining -= toAdd;
      }

      index++;
      if (index < months.length) currentMonth = months[index];
    }

    if (remaining > 0 && months.isNotEmpty) {
      final dernierMois = months.last;
      final double dejaPayeDernierMois = eleve.paid[dernierMois] ?? 0;
      eleve.paid[dernierMois] = dejaPayeDernierMois + remaining;
      final transaction = <String, dynamic>{
        'id': genererIdTransaction(),
        'date': today,
        'mois': dernierMois,
        'amount': remaining,
        'excedent': true,
      };
      eleve.transactions.add(transaction);
      nouvellesTransactions.add(transaction);
      remaining = 0;
    }

    return nouvellesTransactions;
  }

  double getStudentTotalPaid(Eleve eleve) =>
      eleve.paid.values.fold(0.0, (sum, p) => sum + p);

  double getStudentPending(Eleve eleve) {
    return months.fold(
        0.0,
            (sum, m) =>
        sum +
            (getRequiredForMonth(m, eleve.section, eleve.classe) -
                (eleve.paid[m] ?? 0)));
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
        'autresFraisAdministrations':
        autresFraisAdministrations.map((a) => a.toJson()).toList(),
        'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
        'signataires': signataires.map((s) => s.toJson()).toList(),
        'printedReceiptKeys': printedReceiptKeys,
        'receiptQueue': receiptQueue,
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

  Future<void> mergeRestoredData(Map<String, dynamic> serverData) async {
    config = SchoolConfig.fromJson(serverData['config'] ?? {});

    if (serverData['localIdCounter'] != null) {
      final serverCounter = serverData['localIdCounter'] as int;
      if (serverCounter > _localIdCounter) {
        _localIdCounter = serverCounter;
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

              final Map<String, Map<String, dynamic>> transactionsFusionnees =
              {};
              int compteurSansId = 0;

              void ajouterTransaction(Map<String, dynamic> t) {
                final tid = t['id']?.toString() ?? '';
                final String cle = tid.isNotEmpty
                    ? 'id:$tid'
                    : 'legacy:${t['date']}|${t['mois']}|${t['amount']}|'
                    '${compteurSansId++}';
                transactionsFusionnees.putIfAbsent(cle, () => t);
              }

              for (var t in localEleve.transactions) {
                ajouterTransaction(Map<String, dynamic>.from(t));
              }
              for (var t in serverEleve.transactions) {
                ajouterTransaction(Map<String, dynamic>.from(t));
              }

              final mergedTransactions = transactionsFusionnees.values
                  .toList()
                ..sort((a, b) => (a['date'] ?? '')
                    .toString()
                    .compareTo((b['date'] ?? '').toString()));

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
        final serverList = entry.value;

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