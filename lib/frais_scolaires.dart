import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'services/epson_printer_service.dart';

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

  /// Ex: "14/08/2026 à 10:32"
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

  AutreFrais({
    required this.id,
    required this.nom,
    required this.montant,
    this.scope = 'all',
    this.section,
    this.classe,
    DateTime? dateCreation,
  }) : dateCreation = dateCreation ?? DateTime.now();
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
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'montant': montant,
    'scope': scope,
    'section': section,
    'classe': classe,
    'dateCreation': dateCreation.toIso8601String(),
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
// ==========================================================================
// ⚡ NOUVEAU — ADMINISTRATION DÉDIÉE AUX "AUTRES FRAIS DE PAIEMENT"
// ==========================================================================
// ⚠️ IMPORTANT — Cette classe est VOLONTAIREMENT SÉPARÉE de la classe
// `Administration` utilisée par `config.administrations` (celle des frais
// mensuels PRINCIPAUX, définie dans models.dart et gérée dans Paramètres >
// "Administrations & Répartition (%)"). Les deux ne partagent AUCUNE
// donnée, AUCUNE liste, AUCUN calcul commun :
//   - `config.administrations`         -> UNIQUEMENT les frais principaux.
//   - `autresFraisAdministrations`     -> UNIQUEMENT les "Autres Frais".
// Cette séparation stricte est intentionnelle et ne doit JAMAIS être
// fusionnée : l'application est utilisée par plusieurs écoles, et un
// mélange entre les deux systèmes de répartition casserait la confiance
// des utilisateurs dans des calculs financiers déjà validés et utilisés en
// production pour les frais principaux. Ne jamais faire pointer l'une vers
// l'autre, ni partager un pourcentage ou un nom entre les deux listes.
// ==========================================================================
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
  String action; // 'annulation' | 'modification'
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
  // ⚡ NOUVEAU — Liste d'administrations DÉDIÉE aux "Autres Frais de
  // Paiement", totalement indépendante de `config.administrations` (qui
  // reste réservée aux frais mensuels principaux). Voir les commentaires
  // détaillés sur la classe `AutreFraisAdministration` plus haut.
  List<AutreFraisAdministration> autresFraisAdministrations = [];
  String? hiddenCodeHash;
  String? hiddenCodeSalt;
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

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre',
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
  ];

  static const List<String> _joursSemaine = [
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
  ];

  FraisScolaires() : config = SchoolConfig(schoolName: "EduPay School RDC");
  int _schoolMonthIndexForToday() {
    final calendarMonth = DateTime.now().month; // 1 (Janvier)..12 (Décembre)
    if (calendarMonth >= 9 && calendarMonth <= 12) {
      return calendarMonth - 9; // Sept->0, Oct->1, Nov->2, Dec->3
    } else if (calendarMonth >= 1 && calendarMonth <= 6) {
      return calendarMonth + 3; // Jan->4, Fev->5, Mar->6, Avr->7, Mai->8, Jun->9
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
              // Espace réservé à la signature manuscrite.
              pw.SizedBox(height: 34),
              // Ligne de signature.
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

  // ==========================================================================
  // ⚡ NOUVEAU — MISE EN PAGE ROBUSTE DES TABLEAUX PDF
  // ==========================================================================
  // Problème résolu : sans largeurs de colonnes explicites, la librairie
  // PDF calcule des largeurs "intrinsèques" par colonne (une largeur qui
  // dépend du contenu, sans tenir compte de la largeur totale disponible).
  // Dès qu'un rapport contient beaucoup de colonnes (typiquement une
  // colonne par administration configurée) ou des textes un peu longs
  // (noms de classes composés, noms d'administrations...), la somme de
  // ces largeurs "idéales" dépasse la largeur de la page : la librairie
  // réduit alors TOUTES les colonnes proportionnellement pour que ça
  // tienne, au point qu'une colonne peut devenir plus étroite qu'un seul
  // caractère — ce qui produit le rendu illisible parfois observé (texte
  // étalé lettre par lettre à la verticale).
  //
  // La solution appliquée à TOUS les tableaux de rapports ci-dessous :
  //   1. Des largeurs de colonnes EXPLICITES et proportionnées
  //      (`FlexColumnWidth`), toujours assez généreuses pour les colonnes
  //      à texte long (Nom, Classe, Type de frais...), jamais écrasées
  //      même avec beaucoup de colonnes numériques à côté.
  //   2. Une taille de police qui s'adapte AUTOMATIQUEMENT au nombre de
  //      colonnes (plus il y en a — ex: beaucoup d'administrations —
  //      plus elle est réduite), mais jamais en dessous d'un seuil
  //      lisible à l'impression.
  //   3. Une orientation PAYSAGE pour tous les rapports à plusieurs
  //      colonnes, qui donne nettement plus de largeur disponible et
  //      garde un rendu net et présentable devant la direction, quel que
  //      soit le nombre de colonnes ou la longueur des noms.
  //   4. Des en-têtes harmonisés (fond indigo, texte blanc, gras) sur
  //      tous les tableaux, pour un rendu homogène d'un rapport à l'autre.
  // ==========================================================================

  /// Construit une carte {index de colonne -> largeur relative} à partir
  /// d'une liste de proportions (ex: [0.7, 2.4, 1.1, 1.2] pour ID / Nom
  /// Complet / Section / Classe). Les proportions n'ont pas besoin de
  /// totaliser 1 : seul leur ratio les unes par rapport aux autres compte.
  Map<int, pw.TableColumnWidth> _buildColumnWidths(List<double> flexRatios) {
    return {
      for (var i = 0; i < flexRatios.length; i++)
        i: pw.FlexColumnWidth(flexRatios[i]),
    };
  }

  /// Taille de police des CELLULES d'un tableau, réduite automatiquement
  /// quand il y a beaucoup de colonnes (typiquement à cause du nombre
  /// d'administrations configurées), mais jamais en dessous de 6.5pt pour
  /// rester lisible à l'impression.
  double _tableCellFontSize(int columnCount) {
    if (columnCount <= 6) return 9;
    if (columnCount <= 8) return 8.5;
    if (columnCount <= 10) return 8;
    if (columnCount <= 13) return 7.5;
    return 6.5;
  }

  /// Taille de police des EN-TÊTES — suit la même logique de réduction
  /// progressive que `_tableCellFontSize`, avec un plancher légèrement
  /// plus haut car les en-têtes portent souvent des libellés importants
  /// (ex: nom d'une administration + son pourcentage).
  double _tableHeaderFontSize(int columnCount) {
    if (columnCount <= 6) return 9;
    if (columnCount <= 8) return 8.5;
    if (columnCount <= 10) return 8;
    if (columnCount <= 13) return 7.5;
    return 7;
  }

  bool get hiddenCodeIsConfigured =>
      hiddenCodeHash != null && hiddenCodeHash!.isNotEmpty;

  String _hashWithSalt(String code, String salt) {
    final bytes = utf8.encode('$salt::$code');
    return sha256.convert(bytes).toString();
  }
  Future<void> setHiddenCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    final rand = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final salt = base64Url.encode(saltBytes);
    hiddenCodeSalt = salt;
    hiddenCodeHash = _hashWithSalt(trimmed, salt);
    await saveData();
  }
  bool verifyHiddenCode(String code) {
    if (!hiddenCodeIsConfigured) return false;
    return _hashWithSalt(code.trim(), hiddenCodeSalt!) == hiddenCodeHash;
  }

  // ==========================================================================
  // ⚡ CORRIGÉ — ANNULATION / MODIFICATION D'UN PAIEMENT PAR L'ADMIN
  // ==========================================================================
  // Avant : ces deux fonctions ne touchaient QUE le mois concerné par la
  // transaction annulée/modifiée. Si un mois suivant avait déjà reçu un
  // trop-perçu (reporté automatiquement lors d'un paiement), ce trop-perçu
  // restait bloqué sur le mois suivant après l'annulation/modification, et
  // le mois concerné pouvait se retrouver mal soldé alors que l'argent
  // existait bel et bien ailleurs dans l'année.
  //
  // Maintenant : après avoir touché la transaction, on appelle le même
  // moteur de recalcul intelligent que celui utilisé lors d'un changement
  // de frais dans les Paramètres (`recalculerRepartitionMoisPourEleve`).
  // Il reprend le total RÉELLEMENT payé par l'élève (jamais modifié, jamais
  // perdu) et le redistribue mois par mois selon les montants requis
  // ACTUELS. Les reçus "principal" encore en attente d'impression pour cet
  // élève sont automatiquement rafraîchis au passage (jamais les reçus déjà
  // imprimés). Le comportement est donc désormais cohérent, que le
  // désalignement vienne d'un changement de frais OU d'une annulation /
  // modification manuelle d'un paiement.
  // ==========================================================================
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

    // ⚡ NOUVEAU — recalcul intelligent de toute l'année après l'annulation,
    // pour que les mois suivants (et leurs éventuels trop-perçus déjà
    // reportés) restent parfaitement cohérents avec le nouveau total payé.
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
    transaction['modifiePar'] = 'Admin';
    transaction['modifieLe'] = DateTime.now().toString().split(' ')[0];

    // ⚡ NOUVEAU — même recalcul intelligent que pour l'annulation, pour que
    // toute l'année de l'élève reste cohérente avec le nouveau montant.
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
    required String mois,
    required double montantPaye,
  }) async {
    final key = 'principal|${eleve.id}|$mois';
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
  Future<bool> printOrQueueAutreFraisReceipt({
    required Eleve eleve,
    required AutreFrais frais,
  }) async {
    final key = 'autre_frais|${eleve.id}|${frais.id}';
    if (isReceiptPrinted(key)) return false;

    final data = <String, dynamic>{
      'titreFrais': frais.nom,
      'studentName': '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      'classe': eleve.classe,
      'section': eleve.section,
      'montant': frais.montant,
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
    if (receiptQueue.isEmpty) return 0;
    final printerName = await _currentPrinterName();
    if (printerName.isEmpty) return 0;

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
      // ⚡ NOUVEAU — administrations dédiées aux Autres Frais (séparées de
      // config.administrations, incluses dans config.toJson() ci-dessus).
      'autresFraisAdministrations':
      autresFraisAdministrations.map((a) => a.toJson()).toList(),
      'hiddenCodeHash': hiddenCodeHash,
      'hiddenCodeSalt': hiddenCodeSalt,
      'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
      // ⚡ NOUVEAU
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

    // 1. Liste des numéros de classe de la section.
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

    if (studentCount > 0 && !force) {
      return {'success': false, 'studentCount': studentCount};
    }

    config.classesBySection[section]?.remove(numero);
    final key = _classeKey(section, numero);
    config.subClassesByClasse.remove(key);
    config.feesByClasse.remove(key);
    config.monthlyExceptionsByClasse.remove(key);

    if (lastSelectedClassFilter == numero) {
      lastSelectedClassFilter = null;
    }
    await saveData();
    return {'success': true, 'studentCount': studentCount};
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
  Future<void> removeSubClasse(
      String section, String classeNumero, String subClasse) async {
    final key = _classeKey(section, classeNumero);
    config.subClassesByClasse[key]?.remove(subClasse);
    await saveData();
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
    return config.feesBySection[section] ?? 35000;
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
  bool autreFraisAppliesToStudent(AutreFrais frais, Eleve eleve) {
    switch (frais.scope) {
      case 'section':
        return frais.section != null && eleve.section == frais.section;
      case 'classe':
        return frais.classe != null && eleve.classe == frais.classe;
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
    final paiement = AutreFraisPaiement(
      id: 'AFP${DateTime.now().millisecondsSinceEpoch}',
      autreFraisId: frais.id,
      autreFraisNom: frais.nom,
      eleveId: eleve.id,
      montant: frais.montant,
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

  // ==========================================================================
  // ⚡ NOUVEAU — RÉPARTITION PAR ADMINISTRATION POUR UN "AUTRE FRAIS" PRÉCIS
  // ==========================================================================
  // Demande de la direction : pouvoir gérer des administrations et consulter
  // leur répartition en %, DIRECTEMENT depuis l'écran "Autres Frais de
  // Paiement" (et non plus depuis les Paramètres), pour l'argent collecté
  // sur le frais additionnel actuellement sélectionné (ex: "Frais de
  // l'État", "Frais d'Aide"...).
  //
  // ⚠️⚠️⚠️ SÉPARATION TOTALE ET DÉFINITIVE AVEC LES FRAIS PRINCIPAUX ⚠️⚠️⚠️
  // Ce bloc utilise EXCLUSIVEMENT :
  //   - la liste `autresFraisAdministrations` (nouvelle, dédiée),
  //   - la fonction `calculateAutresFraisAdminDistribution` (nouvelle,
  //     dédiée),
  //   - les paiements de `autresFraisPaiementsByYear`.
  // Il n'utilise JAMAIS, et ne doit JAMAIS utiliser :
  //   - `config.administrations` (réservée aux frais principaux),
  //   - `calculateAdminDistribution` (réservée aux frais principaux),
  //   - `eleve.paid` / `getStudentTotalPaid` (alimentés uniquement par les
  //     frais principaux via `handlePayment`).
  // La page "Répartition" des frais PRINCIPAUX (`getRepartitionForOption` /
  // `getSousSectionsForOption`) reste donc strictement intacte et ne peut
  // structurellement recevoir aucune donnée issue des "Autres Frais" — les
  // deux systèmes ne se croisent à aucun moment, dans aucune direction.
  // Cette règle est absolue : l'application sert plusieurs écoles et une
  // fuite entre les deux calculs financiers casserait la confiance des
  // utilisateurs. Si une évolution future doit toucher à ce bloc, elle doit
  // continuer à n'utiliser que les éléments listés ci-dessus.
  //
  // Si aucune administration n'a été ajoutée pour les "Autres Frais"
  // (`autresFraisAdministrations` vide), tout le reste de l'application
  // continue de fonctionner normalement : le paiement des autres frais, les
  // reçus, les totaux par classe/option restent inchangés. Seule la
  // répartition par administration affiche alors "aucune administration
  // configurée" au lieu d'une liste vide silencieuse.
  //
  // Filtres [sectionFilter] / [classFilter] optionnels : permettent de
  // limiter le calcul à une section ou une classe précise (utilisés par le
  // rapport PDF). Laissés à `null` (par défaut), le calcul porte sur TOUS
  // les élèves ayant payé ce frais pour l'année en cours (ou l'année
  // [year] si fournie) — c'est ce que l'écran "Autres Frais de Paiement"
  // utilise pour son bouton de répartition rapide.
  // ==========================================================================
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

  /// ⚡ NOUVEAU — Calcule la répartition (nom -> montant en FC) UNIQUEMENT à
  /// partir de `autresFraisAdministrations` (jamais `config.administrations`).
  /// Fonction miroir de `calculateAdminDistribution`, mais totalement isolée
  /// et dédiée aux "Autres Frais de Paiement". Si `autresFraisAdministrations`
  /// est vide, retourne une carte vide sans erreur.
  Map<String, double> calculateAutresFraisAdminDistribution(
      double totalAmount) {
    final distribution = <String, double>{};
    for (var admin in autresFraisAdministrations) {
      distribution[admin.nom] = totalAmount * (admin.pourcentage / 100);
    }
    return distribution;
  }

  /// Répartition par administration (nom -> montant en FC) pour le total
  /// réellement collecté sur [frais]. Calcul isolé, basé uniquement sur
  /// `autresFraisPaiementsByYear` et sur les administrations dédiées
  /// `autresFraisAdministrations` — jamais sur celles des frais principaux.
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

  // ==========================================================================
  // ⚡ NOUVEAU — GESTION (CRUD) DES ADMINISTRATIONS DÉDIÉES AUX "AUTRES
  // FRAIS DE PAIEMENT"
  // ==========================================================================
  // Ajout, modification et suppression d'administrations pour les "Autres
  // Frais" — accessible DIRECTEMENT depuis l'écran "Autres Frais de
  // Paiement" (voir AutresFraisScreen), sans jamais passer par les
  // Paramètres et sans jamais toucher à `config.administrations`.
  // ==========================================================================
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
  RepartitionDetail getRepartitionForOption(String option) {
    final total = getStudentsBySection(option)
        .fold(0.0, (sum, e) => sum + getStudentTotalPaid(e));
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
  List<RepartitionDetail> getSousSectionsForOption(String option) {
    final students = getStudentsBySection(option);
    final Map<String, double> totalsByLabel = {};
    for (var e in students) {
      final label = _sousSectionLabelFor(e);
      totalsByLabel[label] =
          (totalsByLabel[label] ?? 0) + getStudentTotalPaid(e);
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

  // ==========================================================================
  // ⚡ RECALCUL INTELLIGENT DES PAIEMENTS APRÈS CORRECTION D'UN FRAIS
  // (utilisé aussi désormais par cancelTransaction / modifyTransactionAmount
  // ci-dessus, pour garder toute l'année cohérente après une action admin)
  // ==========================================================================
  // Problème résolu : un frais mensuel mal configuré (ex: laissé au montant
  // par défaut de 35000 FC alors qu'il devait être 45000 FC) peut être
  // corrigé APRÈS que des élèves aient déjà commencé à payer sur base de
  // l'ancien montant. Sans recalcul, un mois resterait marqué "entièrement
  // payé" alors qu'il ne l'est plus au tarif réel, et l'excédent versé sur
  // les mois suivants ne "redescendrait" jamais compenser le manque.
  //
  // La fonction ci-dessous répare cela : elle prend le total RÉELLEMENT payé
  // par un élève (jamais modifié, jamais perdu, jamais inventé) et le
  // redistribue mois par mois, dans l'ordre chronologique de l'année
  // scolaire, en appliquant les montants requis ACTUELS (donc les
  // exceptions et frais par classe/section en vigueur au moment du
  // recalcul). Un mois n'est donc à nouveau considéré comme "payé" que
  // s'il l'est vraiment ; l'éventuel trop-perçu sur un mois suivant vient
  // automatiquement compléter un mois précédent resté en défaut, et
  // inversement un excédent redescend sur les mois suivants si un frais a
  // été réduit.
  //
  // L'historique des transactions (montants, dates, qui a encaissé) n'est
  // JAMAIS modifié par cette fonction : il reste une trace fidèle de ce qui
  // a réellement été perçu, jour par jour. Seule la répartition "combien
  // pour quel mois" (eleve.paid) est recalculée.
  //
  // ⚡ NOUVEAU — Ce recalcul "intelligent" reste le comportement PAR DÉFAUT
  // et n'a pas changé. Il existe désormais, juste après, une ALTERNATIVE
  // appelée mode "constant" (voir `recalculerPaiementsPourModeConstant`
  // plus bas), proposée UNIQUEMENT depuis les Paramètres et UNIQUEMENT
  // quand le nouveau montant d'un frais/exception est plus bas que
  // l'ancien, pour les écoles qui ne veulent PAS que l'argent déjà payé se
  // reporte automatiquement sur les mois suivants dans ce cas précis.
  // ==========================================================================

  /// Recalcule la répartition mois par mois du total déjà payé par [eleve],
  /// selon les montants requis ACTUELS de sa section/classe, et met à jour
  /// les éventuels reçus "principal" encore en attente d'impression pour
  /// cet élève. N'enregistre pas sur disque : à appeler avant un
  /// `saveData()` (voir `recalculerPaiementsPour` pour la version qui
  /// traite plusieurs élèves d'un coup et sauvegarde automatiquement).
  void recalculerRepartitionMoisPourEleve(Eleve eleve) {
    final double totalPaye = getStudentTotalPaid(eleve);
    double restant = totalPaye;
    final Map<String, double> nouveauPaid = {};

    for (final mois in months) {
      if (restant <= 0) break;
      final double requis =
      getRequiredForMonth(mois, eleve.section, eleve.classe);
      if (requis <= 0) continue;
      final double aAffecter = restant >= requis ? requis : restant;
      nouveauPaid[mois] = aAffecter;
      restant -= aAffecter;
    }

    // Élève ayant payé plus que le total requis sur toute l'année (ou
    // reliquat après un frais réduit) : on ne fait JAMAIS disparaître cet
    // argent, on le garde sur le dernier mois de l'année scolaire.
    if (restant > 0 && months.isNotEmpty) {
      final dernierMois = months.last;
      nouveauPaid[dernierMois] = (nouveauPaid[dernierMois] ?? 0) + restant;
    }

    eleve.paid
      ..clear()
      ..addAll(nouveauPaid);

    _rafraichirRecusEnAttentePourEleve(eleve);
  }

  /// Met à jour les données (montant requis, reste à payer, total payé...)
  /// des reçus de type "principal" encore en file d'attente (donc pas
  /// encore imprimés) pour [eleve], afin qu'ils reflètent l'état à jour
  /// après un recalcul. Les reçus DÉJÀ imprimés ne sont jamais modifiés :
  /// ils restent une trace fidèle de ce qui a réellement été remis au
  /// parent à l'époque de l'impression.
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

  /// Recalcule, pour tous les élèves de l'ANNÉE SCOLAIRE EN COURS
  /// correspondant aux filtres donnés (ou tous les élèves si aucun filtre
  /// n'est fourni), la répartition mois par mois de leurs paiements selon
  /// les montants requis ACTUELS. À appeler après toute correction d'un
  /// frais mensuel (section ou classe) ou d'une exception mensuelle.
  ///
  /// [section] : ne recalcule que les élèves de cette section.
  /// [classeNumero] : ne recalcule que les élèves de ce numéro de classe
  /// (ex: "6eme", sans la sous-classe A/B/C) au sein de la section.
  ///
  /// Retourne le nombre d'élèves effectivement recalculés. Enregistre les
  /// données automatiquement (un seul `saveData()` à la fin, même pour un
  /// grand nombre d'élèves).
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

  // ==========================================================================
  // ⚡ NOUVEAU — MODE "CONSTANT" DE RECALCUL (ALTERNATIVE AU RECALCUL
  // INTELLIGENT, UNIQUEMENT UTILISABLE QUAND LE NOUVEAU MONTANT EST PLUS BAS)
  // ==========================================================================
  // Le recalcul "intelligent" ci-dessus est parfait dans la grande majorité
  // des cas : il reprend le total réellement payé par l'élève et le
  // redistribue mois par mois selon les montants requis actuels, sans
  // jamais perdre un centime. MAIS certaines écoles ne veulent PAS de cet
  // effet de "report automatique" dans un cas précis : quand elles baissent
  // le montant d'UN mois précis (ou d'une classe/section entière) pour que
  // les élèves paient moins ce mois-là, elles ne veulent pas que
  // l'excédent déjà payé aille se reporter tout seul sur les mois suivants
  // (ce qui marquerait les mois suivants comme "partiellement payés" alors
  // que l'élève n'a strictement rien versé pour eux).
  //
  // Le mode "constant" répond exactement à ce besoin, et UNIQUEMENT à
  // celui-là : il ne doit être proposé/utilisé que lorsque le nouveau
  // montant requis est STRICTEMENT INFÉRIEUR à l'ancien (voir les écrans de
  // Paramètres, qui ne proposent ce choix que dans ce cas précis — pour une
  // hausse de tarif, le mode intelligent habituel s'applique directement
  // sans rien demander).
  //
  // Pour chaque mois présent dans [anciensRequisParMois] :
  //   - Si le nouveau montant requis pour ce mois est plus bas que
  //     l'ancien montant fourni, ET que l'élève avait déjà payé plus que ce
  //     nouveau montant pour ce mois (que ce soit tout ou une partie), son
  //     paiement enregistré pour ce mois est simplement RAMENÉ au nouveau
  //     montant. Le mois reste donc directement coché comme "payé"
  //     (puisque paid == nouveau requis), SANS qu'aucun report automatique
  //     ne soit fait vers un autre mois.
  //   - Si l'élève avait payé MOINS que le nouveau montant (le mois
  //     n'était de toute façon pas encore soldé), rien ne change : il
  //     devra simplement compléter jusqu'au nouveau montant, plus bas,
  //     comme avant.
  //   - Si le montant n'a PAS baissé pour un mois donné (égal ou en
  //     hausse), ce mois est ignoré : le mode "constant" n'agit jamais à
  //     la hausse.
  //   - Tous les autres mois de l'élève (ceux absents de
  //     [anciensRequisParMois]) ne sont JAMAIS touchés par ce mode : pas de
  //     cascade, pas de report, pas de compensation croisée entre mois.
  //
  // [anciensRequisParMois] doit contenir, pour chaque mois à examiner, le
  // montant qui était requis AVANT le changement de configuration (donc
  // calculé juste avant de modifier le frais ou l'exception — voir
  // `snapshotRequisTousMoisPour` ci-dessous). Seuls les mois présents dans
  // cette carte sont examinés.
  //
  // ⚡ Fonctionnalité volontairement discrète et peu mise en avant : elle
  // n'est proposée à l'utilisateur que lorsque le nouveau montant est
  // effectivement plus bas que l'ancien, et reste invisible le reste du
  // temps pour ne pas alourdir l'usage courant de l'application.
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

        // On n'agit que si le montant a réellement baissé pour ce mois ;
        // sinon on laisse ce mois totalement intact.
        if (nouveauRequis >= ancienRequis) continue;

        final double paidActuel = eleve.paid[mois] ?? 0;
        if (paidActuel > nouveauRequis) {
          // On ramène le paiement enregistré pour ce mois au nouveau
          // montant requis (le mois reste "payé"), sans reporter le reste
          // vers un autre mois.
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

  /// Calcule, pour [section] et [classeNumero] (optionnel), le montant
  /// requis ACTUEL pour chaque mois de l'année scolaire. À utiliser pour
  /// prendre un "instantané" des montants requis AVANT d'appliquer un
  /// changement de frais ou d'exception, afin de pouvoir ensuite proposer
  /// et exécuter le mode "constant" si le nouveau montant s'avère plus bas
  /// (voir `recalculerPaiementsPourModeConstant` ci-dessus).
  Map<String, double> snapshotRequisTousMoisPour(
      String section, String? classeNumero) {
    return {
      for (final m in months) m: getRequiredForMonth(m, section, classeNumero),
    };
  }

  // ==========================================================================
  // ⚡ NOUVEAU — NOMBRE D'ÉLÈVES CONCERNÉS PAR UN RAPPORT (comptage
  // automatique)
  // ==========================================================================
  // Problème résolu : jusqu'ici, savoir combien d'élèves avaient payé un
  // jour donné (ou sur un mois, ou sur l'année) obligeait à parcourir
  // manuellement toute la liste des élèves du rapport PDF, un par un.
  // Cette fonction calcule automatiquement, à partir de la liste des
  // élèves déjà filtrée par `generatePdf` (rapport journalier, mensuel ou
  // annuel, avec les filtres Section/Classe déjà appliqués) :
  //   - le nombre total d'élèves concernés,
  //   - le détail par section (nombre d'élèves par section),
  //   - le détail par classe (nombre d'élèves par "Section - Classe").
  // Le résultat est affiché tout en haut du rapport PDF, juste après les
  // totaux financiers, pour que l'utilisateur n'ait plus jamais besoin de
  // compter manuellement.
  // ==========================================================================
  Map<String, dynamic> _computeStudentCounts(List<Eleve> students) {
    final Map<String, int> parSection = {};
    final Map<String, int> parClasse = {};

    for (final e in students) {
      parSection[e.section] = (parSection[e.section] ?? 0) + 1;
      final classeKey = "${e.section} - ${e.classe}";
      parClasse[classeKey] = (parClasse[classeKey] ?? 0) + 1;
    }

    // Tri alphabétique pour un affichage stable et lisible.
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

  /// Construit le bloc PDF "NOMBRE D'ÉLÈVES" affiché en haut du rapport :
  /// total général, puis détail par section, puis détail par classe. Un
  /// titre personnalisable (`label`) permet de préciser le contexte (ex:
  /// "élèves ayant payé aujourd'hui", "élèves du rapport").
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
    // ⚡ NOUVEAU — libellé du bloc de comptage, adapté selon le type de
    // rapport, pour que le total affiché ait toujours un sens clair.
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

    // ⚡ NOUVEAU — largeurs de colonnes explicites et police adaptative
    // (voir commentaire détaillé plus haut sur `_buildColumnWidths` et
    // consorts) : évite tout écrasement du tableau, même avec beaucoup
    // d'administrations configurées. Les colonnes à texte long (Nom
    // Complet, Classe, Mois Concerné(s)) reçoivent une part généreuse ;
    // chaque colonne d'administration reste compacte mais toujours
    // lisible.
    final List<double> mainTableFlex = [
      0.7, // ID
      2.5, // Nom Complet
      1.1, // Section
      1.3, // Classe
      1.3, // Montant Payé (FC)
      if (showMoisConcerne) 1.7, // Mois Concerné(s)
      ...List<double>.filled(config.administrations.length, 1.3),
    ];
    final mainTableColumnWidths = _buildColumnWidths(mainTableFlex);
    final double mainCellFontSize = _tableCellFontSize(headers.length);
    final double mainHeaderFontSize = _tableHeaderFontSize(headers.length);

    pdf.addPage(
      pw.MultiPage(
        // ⚡ NOUVEAU — orientation paysage : donne nettement plus de
        // largeur disponible pour les tableaux à plusieurs colonnes
        // (frais principaux + une colonne par administration), ce qui
        // évite tout écrasement du texte quel que soit le nombre
        // d'administrations configurées ou la longueur des noms.
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text('${config.schoolName} - $currentYear'),
          pw.Text('Généré le : $_dateGenerationFormatee'),
          pw.SizedBox(height: 20),
          pw.Text(
            "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            "Total ce Mois ($currentMonthName) : "
                "${totalMoisEcole.toStringAsFixed(0)} FC",
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.Text(
            "Total cette Année ($currentYear) : "
                "${totalAnneeEcole.toStringAsFixed(0)} FC",
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 16),
          // ⚡ NOUVEAU — bloc "NOMBRE D'ÉLÈVES" (total général + détail
          // par section + détail par classe), affiché juste après les
          // totaux financiers et avant la liste détaillée des élèves,
          // pour une lecture immédiate sans avoir à compter manuellement.
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
    // ⚡ CORRIGÉ — date + jour, voir `_dateGenerationFormatee`.
    final dateStr      = _dateGenerationFormatee;

    final rows = <List<String>>[];
    for (int i = 0; i < students.length; i++) {
      final e = students[i];
      rows.add(['${i + 1}', e.nom, e.postNom, e.prenom, e.classe]);
    }

    // ⚡ NOUVEAU — largeurs de colonnes explicites : la colonne "Classe"
    // (souvent un nom composé, ex: "6eme Informatique Management A") ne
    // sera plus jamais écrasée par les colonnes voisines.
    final columnWidths = _buildColumnWidths([0.5, 1.6, 1.6, 1.6, 1.5]);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        // ⚡ NOUVEAU — paysage : plus de place pour les noms longs.
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
        e.classe,
        '${montantPaye.toStringAsFixed(0)} / ${montantRequis.toStringAsFixed(0)} FC',
      ]);
    }

    // ⚡ NOUVEAU — largeurs de colonnes explicites : "Classe" et la
    // colonne "Payé / Requis" (qui contient deux montants) reçoivent
    // suffisamment de place pour ne jamais être écrasées.
    final columnWidths =
    _buildColumnWidths([0.5, 1.5, 1.5, 1.5, 1.4, 1.9]);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        // ⚡ NOUVEAU — paysage : plus de largeur pour les six colonnes.
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
              'N°', 'Nom', 'Post-nom', 'Prénom', 'Classe',
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
              5: pw.Alignment.center,
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

  // ==========================================================================
  // RAPPORT "AUTRES FRAIS DE PAIEMENT"
  // ==========================================================================
  // ⚡ RAPPEL — ce rapport contenait DÉJÀ le bloc "RÉPARTITION GLOBALE PAR
  // ADMINISTRATION" (basé sur `calculateAdminDistribution(total)`, le total
  // étant calculé uniquement à partir des paiements d'"Autres Frais"
  // filtrés ci-dessous — jamais mélangé avec les frais principaux). Ce
  // comportement est conservé tel quel, il fonctionnait déjà correctement.
  // Le nouveau bouton ajouté dans l'écran "Autres Frais de Paiement"
  // (`getAdminDistributionForAutreFrais`) permet simplement de consulter le
  // même type d'information EN AMONT, avant même de générer le PDF, pour un
  // frais précis actuellement sélectionné.
  // ==========================================================================
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
    // ⚡ NOUVEAU — on garde trace des élèves DISTINCTS concernés par ce
    // rapport (un même élève peut avoir payé plusieurs frais différents,
    // il ne doit être compté qu'une seule fois dans le total général).
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

    // ⚡ NOUVEAU — utilise EXCLUSIVEMENT les administrations dédiées aux
    // "Autres Frais" (`autresFraisAdministrations`), jamais
    // `config.administrations` (réservée aux frais principaux).
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

    // ⚡ NOUVEAU — largeurs explicites : "Nom Complet" et "Type de Frais"
    // reçoivent la part la plus généreuse, les colonnes numériques/date
    // restent compactes sans jamais être écrasées.
    final columnWidths =
    _buildColumnWidths([0.6, 2.1, 1.0, 1.1, 1.5, 1.0, 1.3]);
    final double cellFontSize = _tableCellFontSize(headers.length);
    final double headerFontSize = _tableHeaderFontSize(headers.length);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        // ⚡ NOUVEAU — paysage : plus de largeur pour les sept colonnes.
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('${config.schoolName} - $currentYear'),
          pw.Text('Généré le : $_dateGenerationFormatee'),
          pw.SizedBox(height: 20),
          pw.Text(
            "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
            style:
            pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            "Nombre de paiements : ${rows.length}",
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 16),
          // ⚡ NOUVEAU — bloc "NOMBRE D'ÉLÈVES" pour le rapport "Autres
          // Frais", basé sur les élèves DISTINCTS ayant au moins un
          // paiement dans ce rapport (et non le nombre de paiements, qui
          // peut être supérieur si un élève a payé plusieurs frais).
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
          // ⚡ NOUVEAU — répartition par administration DÉDIÉE aux "Autres
          // Frais" (basée sur `autresFraisAdministrations`, totalement
          // indépendante de `config.administrations`). Basée sur `total`,
          // calculé ci-dessus exclusivement à partir des paiements de ce
          // rapport. Elle n'apparaît QUE dans ce rapport-ci et n'est
          // jamais ajoutée au rapport de répartition des frais principaux.
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
        hiddenCodeHash = data['hiddenCodeHash'] as String?;
        hiddenCodeSalt = data['hiddenCodeSalt'] as String?;
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
        // ⚡ NOUVEAU — chargement des administrations dédiées aux Autres
        // Frais. Absentes d'une ancienne sauvegarde (avant cette version),
        // la liste reste simplement vide : aucune erreur, aucun impact sur
        // le reste des données.
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
      // ⚡ NOUVEAU
      'depensesByYear': depensesByYear.map(
            (key, value) =>
            MapEntry(key, value.map((d) => d.toJson()).toList()),
      ),
      // ⚡ NOUVEAU
      'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
      'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
            (key, value) =>
            MapEntry(key, value.map((p) => p.toJson()).toList()),
      ),
      // ⚡ NOUVEAU — administrations dédiées aux Autres Frais, sauvegardées
      // séparément de config.administrations (déjà incluses dans
      // config.toJson()).
      'autresFraisAdministrations':
      autresFraisAdministrations.map((a) => a.toJson()).toList(),
      'hiddenCodeHash': hiddenCodeHash,
      'hiddenCodeSalt': hiddenCodeSalt,
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
    lastReportCity = null; // ⚡ NOUVEAU
    schoolCode  = null;
    depensesByYear = {}; // ⚡ NOUVEAU
    autresFrais = []; // ⚡ NOUVEAU
    autresFraisPaiementsByYear = {}; // ⚡ NOUVEAU
    autresFraisAdministrations = []; // ⚡ NOUVEAU
    hiddenCodeHash = null; // ⚡ NOUVEAU
    hiddenCodeSalt = null; // ⚡ NOUVEAU
    adminAuditLog = []; // ⚡ NOUVEAU
    signataires = []; // ⚡ NOUVEAU
    localAccessKeys = []; // ⚡ NOUVEAU
    localPendingPayments = []; // ⚡ NOUVEAU
    localPendingRegistrations = []; // ⚡ NOUVEAU
    localPendingAutresFraisPayments = []; // ⚡ NOUVEAU
    localAttendance = {}; // ⚡ NOUVEAU
    localCommunicationsLog = []; // ⚡ NOUVEAU
    printedReceiptKeys = []; // ⚡ NOUVEAU
    receiptQueue = []; // ⚡ NOUVEAU
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

  void handlePayment(Eleve eleve, String mois, double payment) {
    int    index     = months.indexOf(mois);
    if (index == -1) return;

    final String today     = DateTime.now().toString().split(' ')[0];
    double       remaining = payment;
    String       currentMonth = mois;

    while (remaining > 0 && index < months.length) {
      double required    =
      getRequiredForMonth(currentMonth, eleve.section, eleve.classe);
      double alreadyPaid = eleve.paid[currentMonth] ?? 0;
      double needed      = required - alreadyPaid;

      if (needed > 0) {
        double toAdd = remaining > needed ? needed : remaining;
        eleve.paid[currentMonth] = alreadyPaid + toAdd;
        eleve.transactions.add({
          'date':   today,
          'mois':   currentMonth,
          'amount': toAdd,
        });
        remaining -= toAdd;
      }

      index++;
      if (index < months.length) currentMonth = months[index];
    }
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
        // ⚡ NOUVEAU — administrations dédiées aux Autres Frais, envoyées
        // au serveur séparément de config.administrations.
        'autresFraisAdministrations':
        autresFraisAdministrations.map((a) => a.toJson()).toList(),
        'hiddenCodeHash': hiddenCodeHash,
        'hiddenCodeSalt': hiddenCodeSalt,
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
              localEleve.paid
                ..clear()
                ..addAll(serverEleve.paid);
              localEleve.transactions
                ..clear()
                ..addAll(serverEleve.transactions);
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
    // ⚡ NOUVEAU — fusion des administrations dédiées aux Autres Frais,
    // anti-doublon par id, exactement comme pour `autresFrais` ci-dessus.
    // Totalement indépendant de la fusion de `config.administrations`
    // (qui se fait via `config = SchoolConfig.fromJson(...)` plus haut et
    // reste réservée aux frais principaux).
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
    if (!hiddenCodeIsConfigured) {
      hiddenCodeHash =
          serverData['hiddenCodeHash'] as String? ?? hiddenCodeHash;
      hiddenCodeSalt =
          serverData['hiddenCodeSalt'] as String? ?? hiddenCodeSalt;
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
    required String target, // 'all' | 'section' | 'classe' | 'students'
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