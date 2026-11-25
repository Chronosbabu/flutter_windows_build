library frais_scolaires;

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
import 'package:crypto/crypto.dart';

part 'frais_scolaires_modeles.dart';
part 'frais_scolaires_rapports.dart';
part 'frais_scolaires_services.dart';
part 'frais_scolaires_ordre.dart';
part 'frais_scolaires_messagerie.dart';
part 'frais_scolaires_retenues.dart';
const String serverUrl = "https://jsinf.onrender.com";

// ⚡ NOUVEAU — état d'une tranche pour un élève, calculé à partir du cumul
// payé réparti dans l'ordre des tranches.
enum AutreFraisEtatTranche { payee, partielle, nonPayee }

class AutreFraisTrancheEtat {
  final AutreFraisTranche tranche;
  final int numero; // 1, 2, 3...
  final double montantDu;
  final double verse;
  final AutreFraisEtatTranche etat;

  const AutreFraisTrancheEtat({
    required this.tranche,
    required this.numero,
    required this.montantDu,
    required this.verse,
    required this.etat,
  });

  double get reste =>
      etat == AutreFraisEtatTranche.payee || montantDu - verse <= 0
          ? 0.0
          : montantDu - verse;
}

// ⚡ NOUVEAU — une ligne des listes de recouvrement (par tranche ou pour le
// frais entier).
class AutreFraisRecouvrementLigne {
  final Eleve eleve;
  final double montantDu;
  final double montantPaye;
  final bool paye;

  const AutreFraisRecouvrementLigne({
    required this.eleve,
    required this.montantDu,
    required this.montantPaye,
    required this.paye,
  });

  double get reste =>
      paye || montantDu - montantPaye <= 0 ? 0.0 : montantDu - montantPaye;
  bool get partiel => !paye && montantPaye > 0;
}

class AutreFraisStatut {
  final List<AutreFraisTranche> tranches;
  // ⚡ NOUVEAU — état de chaque tranche (vide si le frais n'a pas de tranches).
  final List<AutreFraisTrancheEtat> etatsTranches;
  final int nbPayees;
  final double totalPaye;
  final double totalDu;
  final double reste;
  final AutreFraisTranche? prochaine;
  final double montantProchain;
  final bool solde;
  final bool partiel;

  const AutreFraisStatut({
    required this.tranches,
    required this.nbPayees,
    required this.totalPaye,
    required this.totalDu,
    required this.reste,
    required this.prochaine,
    required this.montantProchain,
    required this.solde,
    required this.partiel,
    this.etatsTranches = const [],
  });
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
  // ⚡ NOUVEAU — entrées d'argent (apports de caisse), stockées par année
  // scolaire comme les dépenses.
  Map<String, List<Entree>> entreesByYear = {};
  List<AutreFrais> autresFrais = [];
  Map<String, List<AutreFraisPaiement>> autresFraisPaiementsByYear = {};
  Set<String> paiementsAutresFraisAnnules = {};
  Set<String> autresFraisSupprimesIds = {};
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

  SchoolYearData elevesSupprimesData = SchoolYearData(eleves: []);
  Map<String, String> dateSuppressionEleves = {};
  Map<String, String> motifSuppressionEleves = {};

  Map<String, List<String>> optionsSections = {};

  int _localIdCounter = 0;
  // ⚡ Code propre à CET ordinateur (2 lettres tirées au hasard une seule
  // fois, gardées dans le fichier local, jamais envoyées au serveur). Il
  // entre dans les identifiants d'élèves : deux ordinateurs qui inscrivent
  // en même temps ne fabriquent plus le même identifiant.
  String? _codeAppareil;

  String get codeAppareil {
    final actuel = _codeAppareil;
    if (actuel != null && RegExp(r'^[A-Z]{2}$').hasMatch(actuel)) {
      return actuel;
    }
    const lettres = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // sans I ni O
    final r = Random.secure();
    final code = String.fromCharCodes(
        List.generate(2, (_) => lettres.codeUnitAt(r.nextInt(lettres.length))));
    _codeAppareil = code;
    return code;
  }

  bool _isFlushingReceiptQueue = false;

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre',
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
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

  // ⚡ NOUVEAU — même logique que _schoolMonthIndexForToday mais pour une
  // date arbitraire (utilisé pour proposer le mois d'imputation par défaut
  // d'une dépense, selon sa date).
  int _schoolMonthIndexForDate(DateTime date) {
    final calendarMonth = date.month;
    if (calendarMonth >= 9 && calendarMonth <= 12) {
      return calendarMonth - 9;
    } else if (calendarMonth >= 1 && calendarMonth <= 6) {
      return calendarMonth + 3;
    }
    return -1;
  }

  /// Nom du mois scolaire (Septembre à Juin) correspondant à [date], ou null
  /// si la date tombe en dehors de l'année scolaire (juillet/août).
  String? schoolMonthNameForDate(DateTime date) {
    final idx = _schoolMonthIndexForDate(date);
    if (idx < 0 || idx >= months.length) return null;
    return months[idx];
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

  String _affichageDateIso(String iso) {
    final p = iso.split('-');
    if (p.length == 3 && p[0].length == 4) return '${p[2]}/${p[1]}/${p[0]}';
    return iso;
  }

  bool _estDateIso(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);

  Future<String?> modifierDateTransaction({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
    required DateTime nouvelleDate,
  }) async {
    if (!eleve.transactions.any((t) => identical(t, transaction))) {
      return "Ce paiement est introuvable. Fermez la fenêtre, rafraîchissez "
          "la liste puis réessayez.";
    }

    final DateTime maintenant = DateTime.now();
    final DateTime aujourdhui =
    DateTime(maintenant.year, maintenant.month, maintenant.day);
    final DateTime jour =
    DateTime(nouvelleDate.year, nouvelleDate.month, nouvelleDate.day);
    if (jour.isAfter(aujourdhui)) {
      return "La date d'un paiement ne peut pas être dans le futur.";
    }
    if (jour.year < 2000) {
      return "Date invalide.";
    }

    final String nouvelleStr = jour.toString().split(' ')[0];
    final String ancienneStr = transaction['date']?.toString() ?? '';
    if (nouvelleStr == ancienneStr) return null;

    final String mois = transaction['mois']?.toString() ?? '';
    final int idxMois = months.indexOf(mois);
    final bool moisFixe = transaction['moisDebloque'] == true;

    if (!moisFixe && idxMois >= 0) {
      for (final t in eleve.transactions) {
        if (identical(t, transaction)) continue;
        if (t['moisDebloque'] == true) continue;
        final String autreMois = t['mois']?.toString() ?? '';
        final int i = months.indexOf(autreMois);
        if (i < 0 || i == idxMois) continue;
        final String d = t['date']?.toString() ?? '';
        if (!_estDateIso(d)) continue;
        if (i < idxMois && d.compareTo(nouvelleStr) > 0) {
          return "Impossible : le mois \"$autreMois\" (mois précédent) a été "
              "payé le ${_affichageDateIso(d)}. Le paiement de \"$mois\" ne "
              "peut pas être daté avant cette date. Choisissez le "
              "${_affichageDateIso(d)} ou une date plus tard.";
        }
        if (i > idxMois && d.compareTo(nouvelleStr) < 0) {
          return "Impossible : le mois \"$autreMois\" (mois suivant) a été "
              "payé le ${_affichageDateIso(d)}. Le paiement de \"$mois\" ne "
              "peut pas être daté après cette date. Choisissez le "
              "${_affichageDateIso(d)} ou une date plus tôt.";
        }
      }
    }

    final double montant = (transaction['amount'] as num?)?.toDouble() ?? 0.0;

    transaction['date'] = nouvelleStr;
    transaction['dateModifieeLe'] = DateTime.now().toIso8601String();
    if (ancienneStr.isNotEmpty) {
      transaction.putIfAbsent('dateOriginale', () => ancienneStr);
    }

    _rafraichirRecusEnAttentePourEleve(eleve);

    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().microsecondsSinceEpoch}',
      action: 'modification',
      eleveId: eleve.id,
      eleveNomComplet: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      mois: '$mois (date : ${_affichageDateIso(ancienneStr)} → '
          '${_affichageDateIso(nouvelleStr)})',
      montantAvant: montant,
      montantApres: montant,
    ));

    await saveData();
    return null;
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

  String normalizeSectionKey(String raw) => raw.trim().toUpperCase();

  String? resolveSectionAlias(String rawSectionCandidate) {
    final key = normalizeSectionKey(rawSectionCandidate);
    if (config.sectionAliases.containsKey(key)) {
      return config.sectionAliases[key];
    }
    for (final s in config.sections) {
      if (normalizeSectionKey(s) == key) return s;
    }
    return null;
  }

  Future<void> registerSectionAlias(
      String rawSectionCandidate, String targetSection) async {
    final key = normalizeSectionKey(rawSectionCandidate);
    config.sectionAliases[key] = targetSection;
    if (!config.sections.contains(targetSection)) {
      config.sections.add(targetSection);
    }
    await saveData();
  }

  Future<void> registerCustomFieldQuestion(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;
    final exists = config.customFieldQuestions
        .any((q) => q.trim().toLowerCase() == trimmed.toLowerCase());
    if (!exists) {
      config.customFieldQuestions.add(trimmed);
      await saveData();
    }
  }

  /// [idsReserves] : identifiants à éviter en plus de ceux de cet
  /// ordinateur (par exemple ceux du serveur pendant une fusion).
  String generateLocalStudentId(String nom, {Set<String>? idsReserves}) {
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

    final appareil = codeAppareil;
    _localIdCounter++;
    String candidate =
        '$namePrefix$yearShort$schoolLetter$appareil$_localIdCounter';

    while (allIds.contains(candidate) ||
        (idsReserves != null && idsReserves.contains(candidate))) {
      _localIdCounter++;
      candidate = '$namePrefix$yearShort$schoolLetter$appareil$_localIdCounter';
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

  Eleve? trouverEleveParId(String id, [String? year]) {
    final y = year ?? currentYear;
    final candidats = <List<Eleve>>[
      if (y == currentYear) currentData.eleves,
      history[y]?.eleves ?? const <Eleve>[],
      currentData.eleves,
      elevesSupprimesData.eleves,
    ];
    for (final liste in candidats) {
      for (final e in liste) {
        if (e.id == id) return e;
      }
    }
    return null;
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
      final String oldTrancheKey = 'C:$oldKey';
      final String newTrancheKey = 'C:$newKey';
      if (frais.tranchesParCle.containsKey(oldTrancheKey)) {
        final tranches = frais.tranchesParCle.remove(oldTrancheKey)!;
        if (!frais.tranchesParCle.containsKey(newTrancheKey)) {
          frais.tranchesParCle[newTrancheKey] = tranches;
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
      frais.tranchesParCle.remove('C:$key');
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
        existing.montantMensuelPersonnalise = eleve.montantMensuelPersonnalise;
      } else {
        targetData.eleves.add(Eleve(
          id:      eleve.id,
          nom:     eleve.nom,
          postNom: eleve.postNom,
          prenom:  eleve.prenom,
          classe:  newClasse,
          section: eleve.section,
          montantMensuelPersonnalise: eleve.montantMensuelPersonnalise,
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

  double getRequiredForMonthForEleve(Eleve eleve, String mois) {
    if (eleve.exceptionsMoisPersonnalisees.containsKey(mois)) {
      final v = eleve.exceptionsMoisPersonnalisees[mois]!;
      return v < 0 ? 0 : v;
    }
    if (eleve.montantMensuelPersonnalise != null) {
      return eleve.montantMensuelPersonnalise!;
    }
    return getRequiredForMonth(mois, eleve.section, eleve.classe);
  }

  Future<void> setMontantMensuelPersonnalise(
      Eleve eleve, double? montant) async {
    eleve.montantMensuelPersonnalise =
    (montant != null && montant > 0) ? montant : null;
    recalculerRepartitionMoisPourEleve(eleve);
    await saveData();
  }

  Future<void> setExceptionsMoisPourEleve(
      Eleve eleve, Map<String, double> exceptionsParMois) async {
    exceptionsParMois.forEach((mois, montant) {
      eleve.exceptionsMoisPersonnalisees[mois] = montant < 0 ? 0 : montant;
    });
    recalculerRepartitionMoisPourEleve(eleve);
    await saveData();
  }

  Future<int> setExceptionsMoisPourPlusieursEleves(
      List<Map<String, dynamic>> lot) async {
    int count = 0;
    for (final entry in lot) {
      final Eleve eleve = entry['eleve'] as Eleve;
      final Map<String, double> exceptions =
      Map<String, double>.from(entry['exceptions'] as Map);
      exceptions.forEach((mois, montant) {
        eleve.exceptionsMoisPersonnalisees[mois] = montant < 0 ? 0 : montant;
      });
      recalculerRepartitionMoisPourEleve(eleve);
      count++;
    }
    await saveData();
    return count;
  }

  Future<void> removeExceptionMoisPourEleve(Eleve eleve, String mois) async {
    eleve.exceptionsMoisPersonnalisees.remove(mois);
    recalculerRepartitionMoisPourEleve(eleve);
    await saveData();
  }

  Future<void> removeToutesExceptionsMoisPourEleve(Eleve eleve) async {
    eleve.exceptionsMoisPersonnalisees.clear();
    recalculerRepartitionMoisPourEleve(eleve);
    await saveData();
  }

  List<Eleve> getElevesAvecExceptionPersonnalisee() {
    final list = currentData.eleves
        .where((e) =>
    e.montantMensuelPersonnalise != null ||
        e.exceptionsMoisPersonnalisees.isNotEmpty)
        .toList();
    list.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return list;
  }

  bool moisEstDebloquePourEleve(Eleve eleve, String mois) =>
      eleve.moisDebloque == mois;

  Future<void> setMoisDebloquePourEleve(Eleve eleve, String? mois) async {
    eleve.moisDebloque = mois;
    await saveData();
  }

  Map<String, double> getTotalBySection() {
    final totals = <String, double>{};
    for (var e in currentData.eleves) {
      totals[e.section] = (totals[e.section] ?? 0) + getStudentTotalPaid(e);
    }
    for (var e in elevesSupprimesData.eleves) {
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
    for (var e in elevesSupprimesData.eleves) {
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
                  0.0, (s, e) => s + (e.paid[m] ?? 0)) +
              elevesSupprimesData.eleves.fold(
                  0.0, (s, e) => s + (e.paid[m] ?? 0)));

  double getCurrentMonthTotalCollected() {
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return 0.0;
    final moisCourant = months[idx];
    return currentData.eleves
        .fold(0.0, (sum, e) => sum + (e.paid[moisCourant] ?? 0)) +
        elevesSupprimesData.eleves
            .fold(0.0, (sum, e) => sum + (e.paid[moisCourant] ?? 0));
  }

  Map<String, double> getMoneyCollectedTodayBySection() {
    final today = DateTime.now().toString().split(' ')[0];
    final Map<String, double> result = {};
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
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
    for (final e in [...currentData.eleves, ...elevesSupprimesData.eleves]) {
      final montant = e.paid[moisCourant] ?? 0;
      if (montant != 0) {
        result[e.section] = (result[e.section] ?? 0) + montant;
      }
    }
    return result;
  }

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

  List<Map<String, dynamic>> getPaiementsPourDate({
    required String date,
    String? mois,
    String? sectionFilter,
    String? classFilter,
  }) {
    final List<Map<String, dynamic>> result = [];
    for (final e in currentData.eleves) {
      if (sectionFilter != null && e.section != sectionFilter) continue;
      if (classFilter != null && e.classe != classFilter) continue;
      for (final t in e.transactions) {
        if (t['date']?.toString() != date) continue;
        final String moisTransaction = t['mois']?.toString() ?? '';
        if (mois != null && moisTransaction != mois) continue;
        result.add({
          'eleve': e,
          'transaction': t,
        });
      }
    }
    result.sort((a, b) {
      final Eleve ea = a['eleve'] as Eleve;
      final Eleve eb = b['eleve'] as Eleve;
      final c = ea.nom.toLowerCase().compareTo(eb.nom.toLowerCase());
      if (c != 0) return c;
      return ea.prenom.toLowerCase().compareTo(eb.prenom.toLowerCase());
    });
    return result;
  }

  double getTotalPaiementsPourDate({
    required String date,
    String? mois,
    String? sectionFilter,
    String? classFilter,
  }) {
    return getPaiementsPourDate(
      date: date,
      mois: mois,
      sectionFilter: sectionFilter,
      classFilter: classFilter,
    ).fold(0.0, (sum, item) {
      final t = item['transaction'] as Map<String, dynamic>;
      return sum + ((t['amount'] as num?)?.toDouble() ?? 0.0);
    });
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

  bool get aDesOptionsActives =>
      optionsSections.values.any((liste) => liste.isNotEmpty);

  List<String> getOptionsNoms() => List<String>.from(optionsSections.keys);

  List<String> getOptionsUtilisables() => optionsSections.entries
      .where((e) => e.value.isNotEmpty)
      .map((e) => e.key)
      .toList();

  List<String> getSectionsPourOption(String option) =>
      List<String>.from(optionsSections[option] ?? const <String>[]);

  String? getOptionDeSection(String section) {
    for (final e in optionsSections.entries) {
      if (e.value.contains(section)) return e.key;
    }
    return null;
  }

  bool _nomDejaPrisParSectionOuOption(String nom, {String? sauf}) {
    final bas = nom.trim().toLowerCase();
    for (final k in optionsSections.keys) {
      if (sauf != null && k == sauf) continue;
      if (k.trim().toLowerCase() == bas) return true;
    }
    for (final s in config.sections) {
      if (s.trim().toLowerCase() == bas) return true;
    }
    return false;
  }

  Future<String?> addOption(String nom) async {
    final n = nom.trim();
    if (n.isEmpty) return "Le nom de l'option ne peut pas être vide";
    if (_nomDejaPrisParSectionOuOption(n)) {
      return "Ce nom est déjà utilisé par une option ou une section";
    }
    optionsSections[n] = <String>[];
    await saveData();
    return null;
  }

  Future<String?> renameOption(String ancien, String nouveau) async {
    final n = nouveau.trim();
    if (n.isEmpty) return "Le nom de l'option ne peut pas être vide";
    if (!optionsSections.containsKey(ancien)) return "Option introuvable";
    if (n == ancien) return null;
    if (_nomDejaPrisParSectionOuOption(n, sauf: ancien)) {
      return "Ce nom est déjà utilisé par une option ou une section";
    }
    final reconstruit = <String, List<String>>{};
    optionsSections.forEach((k, v) {
      reconstruit[k == ancien ? n : k] = v;
    });
    optionsSections = reconstruit;
    await saveData();
    return null;
  }

  Future<void> deleteOption(String option) async {
    if (optionsSections.remove(option) != null) {
      await saveData();
    }
  }

  Future<void> setSectionsPourOption(
      String option, List<String> sections) async {
    if (!optionsSections.containsKey(option)) return;
    final valides = <String>[];
    for (final s in sections) {
      if (config.sections.contains(s) && !valides.contains(s)) {
        valides.add(s);
      }
    }
    valides.sort((a, b) =>
        config.sections.indexOf(a).compareTo(config.sections.indexOf(b)));

    for (final e in optionsSections.entries) {
      if (e.key == option) continue;
      e.value.removeWhere((s) => valides.contains(s));
    }
    optionsSections[option] = valides;
    await saveData();
  }

  void retirerSectionDesOptions(String section) {
    for (final liste in optionsSections.values) {
      liste.removeWhere((s) => s == section);
    }
  }

  Map<String, List<String>> _parseOptionsSections(dynamic raw) {
    final result = <String, List<String>>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final nom = k.toString().trim();
        if (nom.isEmpty) return;
        final liste = <String>[];
        if (v is List) {
          for (final s in v) {
            final t = s.toString();
            if (t.isNotEmpty && !liste.contains(t)) liste.add(t);
          }
        }
        result[nom] = liste;
      });
    }
    return result;
  }

  void _nettoyerOptions() {
    final propres = <String, List<String>>{};
    final dejaAffectees = <String>{};
    optionsSections.forEach((nom, secs) {
      final n = nom.trim();
      if (n.isEmpty || propres.containsKey(n)) return;
      final liste = <String>[];
      for (final s in secs) {
        if (config.sections.isNotEmpty && !config.sections.contains(s)) {
          continue;
        }
        if (dejaAffectees.contains(s) || liste.contains(s)) continue;
        liste.add(s);
        dejaAffectees.add(s);
      }
      propres[n] = liste;
    });
    optionsSections = propres;
  }

  List<GroupeOption> _groupesOptions(Iterable<String> sectionsPresentes) {
    final presentes = <String>{...sectionsPresentes};
    final groupes = <GroupeOption>[];
    final dejaPris = <String>{};

    optionsSections.forEach((nom, secs) {
      final incluses = secs
          .where((s) => presentes.contains(s) && !dejaPris.contains(s))
          .toList();
      if (incluses.isEmpty) return;
      dejaPris.addAll(incluses);
      groupes.add(
          GroupeOption(nom: nom, sections: incluses, estOption: true));
    });

    final restantes = <String>[
      ...config.sections
          .where((s) => presentes.contains(s) && !dejaPris.contains(s)),
      ...(presentes
          .where((s) => !config.sections.contains(s) && !dejaPris.contains(s))
          .toList()
        ..sort()),
    ];
    for (final s in restantes) {
      groupes.add(GroupeOption(nom: s, sections: [s], estOption: false));
    }

    int cle(GroupeOption g) {
      var m = 1 << 30;
      for (final s in g.sections) {
        var i = config.sections.indexOf(s);
        if (i < 0) i = 1 << 20;
        if (i < m) m = i;
      }
      return m;
    }

    groupes.sort((a, b) {
      final c = cle(a).compareTo(cle(b));
      if (c != 0) return c;
      return a.nom.compareTo(b.nom);
    });
    return groupes;
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
        .where((d) {
      final eff = _depenseDateEffective(d);
      return eff.year == now.year && eff.month == now.month;
    })
        .fold(0.0, (sum, d) => sum + d.montant);
  }

  double getTotalDepensesParPortee(String portee, [String? year]) {
    final y = year ?? currentYear;
    return (depensesByYear[y] ?? [])
        .where((d) => d.portee == portee)
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
    return totalCollecte - getTotalDepenses(y) + getTotalEntrees(y);
  }

  double getSoldeNetForPeriod(String period, [String? year]) {
    switch (period) {
      case 'today':
        return getMoneyCollectedForPeriod('today') -
            getTotalDepensesToday(year) +
            getTotalEntreesToday(year);
      case 'month':
        return getMoneyCollectedForPeriod('month') -
            getTotalDepensesThisMonth(year) +
            getTotalEntreesThisMonth(year);
      case 'year':
      default:
        return getSoldeNetActuel(year);
    }
  }

  List<String> getRubriquesDisponibles() {
    final result = <String>[];
    for (final a in config.administrations) {
      final nom = a.nom.trim();
      if (nom.isNotEmpty && !result.contains(nom)) result.add(nom);
    }
    result.add(kRubriqueAutre);
    return result;
  }

  Map<String, double> repartitionDepenseParSection(Depense d) {
    if (d.portee == kDepenseGlobale || d.sections.isEmpty) return {};
    final part = d.montant / d.sections.length;
    return {for (final s in d.sections) s: part};
  }

  bool _depenseConcerneFiltre(
      Depense d, String? sectionFilter, String? classFilter) {
    if (d.portee == kDepenseGlobale) return true;
    if (sectionFilter != null && !d.sections.contains(sectionFilter)) {
      return false;
    }
    if (classFilter != null &&
        d.classes.isNotEmpty &&
        !d.classes.contains(classFilter)) {
      return false;
    }
    return true;
  }

  // ⚡ NOUVEAU — date à utiliser pour tous les calculs mensuels : le mois
  // d'imputation choisi manuellement s'il existe, sinon la date réelle de la
  // dépense (comportement d'origine, conservé pour les dépenses existantes).
  DateTime _depenseDateEffective(Depense d) {
    final m = d.moisImputation;
    if (m != null && m.trim().isNotEmpty) {
      return _dateRepereMois(m);
    }
    return d.date;
  }

  List<Depense> getDepensesForPeriod(
      String period, {
        String? year,
        String? sectionFilter,
        String? classFilter,
      }) {
    final y = year ?? currentYear;
    final now = DateTime.now();
    final todayStr = now.toString().split(' ')[0];
    final list = (depensesByYear[y] ?? []).where((d) {
      bool okPeriode;
      switch (period) {
        case 'today':
          okPeriode = d.date.toString().split(' ')[0] == todayStr;
          break;
        case 'month':
          final eff = _depenseDateEffective(d);
          okPeriode = eff.year == now.year && eff.month == now.month;
          break;
        case 'year':
        default:
          okPeriode = true;
      }
      return okPeriode && _depenseConcerneFiltre(d, sectionFilter, classFilter);
    }).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  Map<String, double> _collecteParSectionPourPeriode(String period) {
    switch (period) {
      case 'today':
        return getMoneyCollectedTodayBySection();
      case 'month':
        return getMoneyCollectedThisMonthBySection();
      case 'year':
      default:
        return getTotalBySection();
    }
  }

  DepensePeriodeStats computeDepensesStats(
      String period, {
        String? year,
        String? sectionFilter,
        String? classFilter,
      }) {
    final collecteAll = _collecteParSectionPourPeriode(period);
    final collecteBySection = <String, double>{};
    collecteAll.forEach((s, v) {
      if (sectionFilter == null || s == sectionFilter) {
        collecteBySection[s] = v;
      }
    });
    final double totalCollecte =
    collecteBySection.values.fold(0.0, (a, b) => a + b);

    // ⚡ Retenues : elles sortent avant les pourcentages des rubriques.
    double totalRetenues = 0.0;
    retenuesParSection(period).forEach((s, v) {
      if (sectionFilter == null || s == sectionFilter) totalRetenues += v;
    });
    final double baseRepartition = totalCollecte - totalRetenues;

    final depenses = getDepensesForPeriod(
      period,
      year: year,
      sectionFilter: sectionFilter,
      classFilter: classFilter,
    );
    // ⚡ NOUVEAU — entrées d'argent de la période (actives + annulées, pour
    // l'affichage ; seules les actives sont comptées dans les totaux).
    final entrees = getEntreesForPeriod(
      period,
      year: year,
      sectionFilter: sectionFilter,
      classFilter: classFilter,
    );

    final Map<String, RubriqueStat> rub = {};
    for (final admin in config.administrations) {
      final nom = admin.nom.trim();
      if (nom.isEmpty) continue;
      rub[nom] = RubriqueStat(
        rubrique: nom,
        pourcentage: admin.pourcentage,
        collecte: baseRepartition * (admin.pourcentage / 100),
      );
    }

    final Map<String, SectionStat> secStats = {};
    final sectionsBase = sectionFilter != null
        ? <String>[sectionFilter]
        : List<String>.from(config.sections);
    for (final s in sectionsBase) {
      secStats[s] = SectionStat(section: s, collecte: collecteBySection[s] ?? 0);
    }
    collecteBySection.forEach((s, v) {
      secStats.putIfAbsent(s, () => SectionStat(section: s, collecte: v));
    });

    double globales = 0;
    double independantes = 0;
    double mixtes = 0;

    for (final d in depenses) {
      final cle = d.rubriqueAffichee;
      final r = rub.putIfAbsent(
        cle,
            () => RubriqueStat(rubrique: cle, pourcentage: 0, collecte: 0),
      );
      if (d.portee == kDepenseGlobale) {
        if (sectionFilter == null) {
          r.globales += d.montant;
          globales += d.montant;
        }
      } else {
        final parts = repartitionDepenseParSection(d);
        parts.forEach((s, amt) {
          if (sectionFilter != null && s != sectionFilter) return;
          final st = secStats.putIfAbsent(
              s, () => SectionStat(section: s, collecte: 0));
          if (d.portee == kDepenseIndependante) {
            r.independantes += amt;
            st.independantes += amt;
            independantes += amt;
          } else {
            r.mixtes += amt;
            st.mixtes += amt;
            mixtes += amt;
          }
        });
      }
    }

    double entreesGlobales = 0;
    double entreesIndependantes = 0;
    double entreesMixtes = 0;

    for (final e in entrees) {
      if (e.annulee) continue; // non comptées, seulement affichées
      final cle = e.rubriqueAffichee;
      final r = rub.putIfAbsent(
        cle,
            () => RubriqueStat(rubrique: cle, pourcentage: 0, collecte: 0),
      );
      if (e.portee == kDepenseGlobale) {
        if (sectionFilter == null) {
          r.entreesGlobales += e.montant;
          entreesGlobales += e.montant;
        }
      } else {
        final parts = repartitionEntreeParSection(e);
        parts.forEach((s, amt) {
          if (sectionFilter != null && s != sectionFilter) return;
          final st = secStats.putIfAbsent(
              s, () => SectionStat(section: s, collecte: 0));
          if (e.portee == kDepenseIndependante) {
            r.entreesIndependantes += amt;
            st.entreesIndependantes += amt;
            entreesIndependantes += amt;
          } else {
            r.entreesMixtes += amt;
            st.entreesMixtes += amt;
            entreesMixtes += amt;
          }
        });
      }
    }

    return DepensePeriodeStats(
      period: period,
      depenses: depenses,
      rubriques: rub.values.toList(),
      sections: secStats.values.toList(),
      totalCollecte: totalCollecte,
      globales: globales,
      independantes: independantes,
      mixtes: mixtes,
      globalesExclues: sectionFilter != null,
      retenues: totalRetenues,
      entrees: entrees,
      entreesGlobales: entreesGlobales,
      entreesIndependantes: entreesIndependantes,
      entreesMixtes: entreesMixtes,
    );
  }

  double? getSoldeDisponibleRubrique({
    required String rubrique,
    required String portee,
    List<String> sections = const [],
  }) {
    if (rubrique == kRubriqueAutre || rubrique.trim().isEmpty) return null;
    double pct = 0;
    for (final a in config.administrations) {
      if (a.nom.trim() == rubrique.trim()) {
        pct = a.pourcentage;
        break;
      }
    }
    final collecteSec = getTotalBySection();
    // ⚡ Les retenues sortent avant les pourcentages.
    final retenuesSec = retenuesParSection('year');
    double collecte = 0;
    if (portee == kDepenseGlobale) {
      final double brut = collecteSec.values.fold(0.0, (a, b) => a + b);
      final double ret = retenuesSec.values.fold(0.0, (a, b) => a + b);
      collecte = (brut - ret) * pct / 100;
    } else {
      for (final s in sections) {
        collecte +=
            ((collecteSec[s] ?? 0) - (retenuesSec[s] ?? 0)) * pct / 100;
      }
    }

    double depense = 0;
    for (final d in (depensesByYear[currentYear] ?? [])) {
      if (d.rubrique.trim() != rubrique.trim()) continue;
      if (portee == kDepenseGlobale) {
        depense += d.montant;
      } else {
        final parts = repartitionDepenseParSection(d);
        for (final s in sections) {
          depense += parts[s] ?? 0;
        }
      }
    }

    // ⚡ NOUVEAU — les entrées actives de cette rubrique augmentent le solde
    // disponible.
    double entree = 0;
    for (final e in (entreesByYear[currentYear] ?? [])) {
      if (e.annulee || e.rubrique.trim() != rubrique.trim()) continue;
      if (portee == kDepenseGlobale) {
        entree += e.montant;
      } else {
        final parts = repartitionEntreeParSection(e);
        for (final s in sections) {
          entree += parts[s] ?? 0;
        }
      }
    }

    return collecte - depense + entree;
  }

  Future<Depense> addDepense({
    required String motif,
    required double montant,
    String enregistrePar = 'Direction',
    String portee = kDepenseGlobale,
    List<String>? sections,
    List<String>? classes,
    String rubrique = '',
    DateTime? date,
    String? moisImputation,
  }) async {
    final depense = Depense(
      id: 'DEP${DateTime.now().millisecondsSinceEpoch}',
      motif: motif.trim(),
      montant: montant,
      date: date ?? DateTime.now(),
      enregistrePar: enregistrePar,
      portee: portee,
      sections: portee == kDepenseGlobale ? [] : (sections ?? []),
      classes: portee == kDepenseGlobale ? [] : (classes ?? []),
      rubrique: rubrique.trim(),
      moisImputation: moisImputation,
    );
    depensesByYear.putIfAbsent(currentYear, () => []).add(depense);
    await saveData();
    return depense;
  }

  Future<Depense> addDepenseParOption({
    required String motif,
    required double montant,
    required String option,
    String enregistrePar = 'Direction',
    List<String>? classes,
    String rubrique = '',
    DateTime? date,
    String? moisImputation,
  }) async {
    final sections = getSectionsPourOption(option);
    if (sections.isEmpty) {
      throw Exception("L'option \"$option\" ne contient aucune section.");
    }
    return addDepense(
      motif: motif,
      montant: montant,
      enregistrePar: enregistrePar,
      portee: sections.length == 1 ? kDepenseIndependante : kDepenseMixte,
      sections: sections,
      classes: classes,
      rubrique: rubrique,
      date: date,
      moisImputation: moisImputation,
    );
  }

  Future<void> deleteDepense(String id, [String? year]) async {
    final y = year ?? currentYear;
    depensesByYear[y]?.removeWhere((d) => d.id == id);
    await saveData();
  }

  Future<void> updateDepenseDate(
      String id,
      DateTime newDate, [
        String? year,
      ]) async {
    final y = year ?? currentYear;
    final list = depensesByYear[y];
    if (list == null) return;
    for (final d in list) {
      if (d.id == id) {
        d.date = newDate;
        break;
      }
    }
    await saveData();
  }

  /// ⚡ NOUVEAU — modifie le mois d'imputation d'une dépense existante.
  /// [moisImputation] null = revenir au comportement par défaut (utiliser
  /// la date de la dépense).
  Future<void> updateDepenseMoisImputation(
      String id,
      String? moisImputation, [
        String? year,
      ]) async {
    final y = year ?? currentYear;
    final list = depensesByYear[y];
    if (list == null) return;
    for (final d in list) {
      if (d.id == id) {
        d.moisImputation = moisImputation;
        break;
      }
    }
    await saveData();
  }

  Future<void> clearDepensesForYear([String? year]) async {
    final y = year ?? currentYear;
    depensesByYear[y] = [];
    await saveData();
  }

  // ==========================================================================
  // ⚡ NOUVEAU — ENTRÉES D'ARGENT (apports de caisse)
  // --------------------------------------------------------------------------
  // Même esprit que les dépenses, mais en sens inverse : une entrée AUGMENTE
  // le reste d'une rubrique et le solde de caisse. Elle n'est JAMAIS soumise
  // aux pourcentages des administrations, ne touche pas la base de
  // répartition des frais scolaires, ni les retenues, ni les soldes élèves.
  // Une entrée n'est jamais supprimée : seulement annulée (elle reste
  // visible, marquée, et n'est plus comptée dans les totaux).
  // ==========================================================================

  Map<String, double> repartitionEntreeParSection(Entree e) {
    if (e.portee == kDepenseGlobale || e.sections.isEmpty) return {};
    final part = e.montant / e.sections.length;
    return {for (final s in e.sections) s: part};
  }

  bool _entreeConcerneFiltre(
      Entree e, String? sectionFilter, String? classFilter) {
    if (e.portee == kDepenseGlobale) return true;
    if (sectionFilter != null && !e.sections.contains(sectionFilter)) {
      return false;
    }
    if (classFilter != null &&
        e.classes.isNotEmpty &&
        !e.classes.contains(classFilter)) {
      return false;
    }
    return true;
  }

  // Date à utiliser pour les calculs mensuels : le mois d'imputation choisi
  // s'il existe, sinon la date réelle de l'entrée (même logique que pour les
  // dépenses, voir _depenseDateEffective).
  DateTime _entreeDateEffective(Entree e) {
    final m = e.moisImputation;
    if (m != null && m.trim().isNotEmpty) {
      return _dateRepereMois(m);
    }
    return e.date;
  }

  List<Entree> getEntreesForYear([String? year]) {
    final y = year ?? currentYear;
    final list = List<Entree>.from(entreesByYear[y] ?? []);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Total des entrées ACTIVES (non annulées) de l'année.
  double getTotalEntrees([String? year]) {
    final y = year ?? currentYear;
    return (entreesByYear[y] ?? [])
        .where((e) => !e.annulee)
        .fold(0.0, (sum, e) => sum + e.montant);
  }

  double getTotalEntreesParType(String type, [String? year]) {
    final y = year ?? currentYear;
    return (entreesByYear[y] ?? [])
        .where((e) => !e.annulee && e.type == type)
        .fold(0.0, (sum, e) => sum + e.montant);
  }

  double getTotalEntreesToday([String? year]) {
    final y = year ?? currentYear;
    final today = DateTime.now().toString().split(' ')[0];
    return (entreesByYear[y] ?? [])
        .where((e) => !e.annulee && e.date.toString().split(' ')[0] == today)
        .fold(0.0, (sum, e) => sum + e.montant);
  }

  double getTotalEntreesThisMonth([String? year]) {
    final y = year ?? currentYear;
    final now = DateTime.now();
    return (entreesByYear[y] ?? [])
        .where((e) {
      if (e.annulee) return false;
      final eff = _entreeDateEffective(e);
      return eff.year == now.year && eff.month == now.month;
    })
        .fold(0.0, (sum, e) => sum + e.montant);
  }

  /// Total déjà retourné (entrées actives de type "retour de reliquat") pour
  /// une dépense donnée. Sert à plafonner un nouveau retour.
  double totalEntreesRetourPourDepense(String depenseId, [String? year]) {
    final y = year ?? currentYear;
    return (entreesByYear[y] ?? [])
        .where((e) =>
    !e.annulee &&
        e.type == kEntreeRetourReliquat &&
        e.depenseLieeId == depenseId)
        .fold(0.0, (sum, e) => sum + e.montant);
  }

  /// Entrées (actives ET annulées, pour l'affichage détaillé) correspondant à
  /// une période ('today', 'month', 'year') et à des filtres optionnels.
  List<Entree> getEntreesForPeriod(
      String period, {
        String? year,
        String? sectionFilter,
        String? classFilter,
      }) {
    final y = year ?? currentYear;
    final now = DateTime.now();
    final todayStr = now.toString().split(' ')[0];
    final list = (entreesByYear[y] ?? []).where((e) {
      bool okPeriode;
      switch (period) {
        case 'today':
          okPeriode = e.date.toString().split(' ')[0] == todayStr;
          break;
        case 'month':
          final eff = _entreeDateEffective(e);
          okPeriode = eff.year == now.year && eff.month == now.month;
          break;
        case 'year':
        default:
          okPeriode = true;
      }
      return okPeriode && _entreeConcerneFiltre(e, sectionFilter, classFilter);
    }).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Ajoute une entrée d'argent. Retourne `null` si tout va bien, sinon un
  /// message d'erreur à afficher (rien n'est enregistré dans ce cas).
  Future<String?> addEntree({
    required double montant,
    required String type,
    required String justification,
    String motif = '',
    String enregistrePar = 'Direction',
    String rubrique = '',
    String portee = kDepenseGlobale,
    List<String>? sections,
    List<String>? classes,
    DateTime? date,
    String? moisImputation,
    String? depenseLieeId,
  }) async {
    if (montant <= 0) {
      return 'Le montant doit être supérieur à zéro.';
    }
    if (justification.trim().isEmpty) {
      return 'La justification est obligatoire.';
    }
    if (rubrique.trim().isEmpty) {
      return 'Veuillez choisir la rubrique.';
    }
    final sectionsFinales = portee == kDepenseGlobale ? <String>[] : (sections ?? []);
    if (portee == kDepenseIndependante && sectionsFinales.isEmpty) {
      return 'Veuillez choisir la section concernée.';
    }
    if (portee == kDepenseMixte && sectionsFinales.length < 2) {
      return 'Une entrée mixte doit concerner au moins deux sections.';
    }

    String? depenseLieeFinale;
    if (type == kEntreeRetourReliquat) {
      if (depenseLieeId == null || depenseLieeId.trim().isEmpty) {
        return "Veuillez choisir la dépense d'origine pour un retour de "
            "reliquat.";
      }
      Depense? origine;
      for (final d in (depensesByYear[currentYear] ?? [])) {
        if (d.id == depenseLieeId) {
          origine = d;
          break;
        }
      }
      if (origine == null) {
        return "Dépense d'origine introuvable.";
      }
      final double dejaRetourne = totalEntreesRetourPourDepense(depenseLieeId);
      final double disponible = origine.montant - dejaRetourne;
      // Blocage strict : un retour de reliquat ne peut jamais dépasser ce
      // qu'il reste à rendre sur la dépense d'origine.
      if (montant > disponible + 0.009) {
        return "Ce retour (${formatMontant(montant)} FC) dépasse le "
            "reliquat encore disponible sur cette dépense "
            "(${formatMontant(disponible)} FC déjà retourné : "
            "${formatMontant(dejaRetourne)} FC).";
      }
      depenseLieeFinale = depenseLieeId;
    }

    final entree = Entree(
      id: 'ENT${DateTime.now().millisecondsSinceEpoch}',
      date: date ?? DateTime.now(),
      montant: montant,
      type: type,
      rubrique: rubrique.trim(),
      justification: justification.trim(),
      motif: motif.trim(),
      enregistrePar: enregistrePar,
      portee: portee,
      sections: sectionsFinales,
      classes: portee == kDepenseGlobale ? [] : (classes ?? []),
      moisImputation: moisImputation,
      depenseLieeId: depenseLieeFinale,
    );
    entreesByYear.putIfAbsent(currentYear, () => []).add(entree);

    // ⚡ Journalisation, comme pour les paiements (adminAuditLog). Les champs
    // pensés pour les élèves sont réemployés : eleveId -> id de l'entrée,
    // eleveNomComplet -> description, classe -> portée, mois -> imputation.
    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().millisecondsSinceEpoch}',
      action: 'entree_ajoutee',
      eleveId: entree.id,
      eleveNomComplet:
      'Entrée : ${entree.typeLabel} — ${entree.rubriqueAffichee} '
          '(${formatMontant(entree.montant)} FC)',
      classe: entree.portee,
      mois: entree.moisImputation ?? '',
      montantAvant: 0,
      montantApres: entree.montant,
    ));

    await saveData();
    return null;
  }

  /// Annule une entrée (motif obligatoire). L'entrée reste visible dans
  /// l'historique, marquée "annulée", et n'est plus comptée nulle part.
  /// Retourne `null` si tout va bien, sinon un message d'erreur.
  Future<String?> annulerEntree(
      String id,
      String motif, [
        String? year,
      ]) async {
    if (motif.trim().isEmpty) {
      return "Le motif d'annulation est obligatoire.";
    }
    final y = year ?? currentYear;
    final list = entreesByYear[y];
    if (list == null) return 'Entrée introuvable.';
    Entree? entree;
    for (final e in list) {
      if (e.id == id) {
        entree = e;
        break;
      }
    }
    if (entree == null) return 'Entrée introuvable.';
    if (entree.annulee) return 'Cette entrée est déjà annulée.';

    entree.annulee = true;
    entree.dateAnnulation = DateTime.now();
    entree.motifAnnulation = motif.trim();

    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().millisecondsSinceEpoch}',
      action: 'entree_annulee',
      eleveId: entree.id,
      eleveNomComplet:
      'Entrée : ${entree.typeLabel} — ${entree.rubriqueAffichee} '
          '(motif : ${motif.trim()})',
      classe: entree.portee,
      mois: entree.moisImputation ?? '',
      montantAvant: entree.montant,
      montantApres: 0,
    ));

    await saveData();
    return null;
  }

  List<AutreFrais> getAutresFrais() {
    final list = List<AutreFrais>.from(autresFrais);
    list.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return list;
  }

  String normaliserNomFrais(String nom) =>
      nom.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  List<AutreFraisGroupe> getAutresFraisGroupes() {
    final Map<String, List<AutreFrais>> parCle = {};
    for (final f in autresFrais) {
      final cle = normaliserNomFrais(f.nom);
      if (cle.isEmpty) continue;
      parCle.putIfAbsent(cle, () => []).add(f);
    }

    final result = <AutreFraisGroupe>[];
    parCle.forEach((cle, liste) {
      double min = double.infinity;
      double max = double.negativeInfinity;
      void considerer(double v) {
        if (v < min) min = v;
        if (v > max) max = v;
      }

      for (final f in liste) {
        considerer(f.montant);
        for (final v in f.montantsParSection.values) {
          considerer(v);
        }
        for (final v in f.montantsParClasse.values) {
          considerer(v);
        }
      }
      if (min == double.infinity) {
        min = 0;
        max = 0;
      }

      result.add(AutreFraisGroupe(
        cle: cle,
        nom: liste.first.nom.trim(),
        ids: liste.map((f) => f.id).toList(),
        montantMin: min,
        montantMax: max,
      ));
    });

    result.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return result;
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
    autresFraisSupprimesIds.add(id);
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

  static const String kTrancheCleTous = 'ALL';
  static const double _toleranceMontant = 0.5;

  String cleTrancheSection(String section) => 'S:$section';

  String cleTrancheClasse(String section, String classeNumero) =>
      'C:${_classeKey(section, classeNumero)}';

  String cleTranchePourCible({String? section, String? classeNumero}) {
    if (section != null && classeNumero != null) {
      return cleTrancheClasse(section, classeNumero);
    }
    if (section != null) return cleTrancheSection(section);
    return kTrancheCleTous;
  }

  String nomTrancheSuggere(int numero) {
    switch (numero) {
      case 1:
        return 'Première tranche';
      case 2:
        return 'Deuxième tranche';
      case 3:
        return 'Troisième tranche';
      default:
        return '${numero}ème tranche';
    }
  }

  AutreFrais? _trouverAutreFrais(String autreFraisId) {
    for (final f in autresFrais) {
      if (f.id == autreFraisId) return f;
    }
    return null;
  }

  List<AutreFraisTranche> getTranchesPourCle(AutreFrais frais, String cle) =>
      List<AutreFraisTranche>.from(
          frais.tranchesParCle[cle] ?? const <AutreFraisTranche>[]);

  List<AutreFraisTranche> getTranchesPourEleve(AutreFrais frais, Eleve eleve) {
    final numero = classeNumeroFromFullClasse(eleve.classe);
    final cles = <String>[
      cleTrancheClasse(eleve.section, numero),
      cleTrancheSection(eleve.section),
      kTrancheCleTous,
    ];
    for (final cle in cles) {
      final liste = frais.tranchesParCle[cle];
      if (liste != null && liste.isNotEmpty) {
        return List<AutreFraisTranche>.from(liste);
      }
    }
    return <AutreFraisTranche>[];
  }

  bool autreFraisAUneTranchePourEleve(AutreFrais frais, Eleve eleve) =>
      getTranchesPourEleve(frais, eleve).isNotEmpty;

  double getMontantAutreFraisPourCible(
      AutreFrais frais, {
        String? section,
        String? classeNumero,
      }) {
    if (section != null && classeNumero != null) {
      final key = _classeKey(section, classeNumero);
      if (frais.montantsParClasse.containsKey(key)) {
        return frais.montantsParClasse[key]!;
      }
    }
    if (section != null && frais.montantsParSection.containsKey(section)) {
      return frais.montantsParSection[section]!;
    }
    return frais.montant;
  }

  Future<AutreFraisTranche?> addTranchePourAutreFrais({
    required String autreFraisId,
    required String cle,
    required String nom,
    required double montant,
  }) async {
    final frais = _trouverAutreFrais(autreFraisId);
    if (frais == null) return null;
    final tranche = AutreFraisTranche(
      id: 'TR${DateTime.now().microsecondsSinceEpoch}',
      nom: nom.trim(),
      montant: montant,
    );
    frais.tranchesParCle.putIfAbsent(cle, () => []).add(tranche);
    await saveData();
    return tranche;
  }

  Future<bool> updateTranchePourAutreFrais({
    required String autreFraisId,
    required String cle,
    required String trancheId,
    required String nom,
    required double montant,
    // ⚡ NOUVEAU — pour une échéance mensuelle : nouveau mois (null = ne
    // change pas).
    String? mois,
  }) async {
    final frais = _trouverAutreFrais(autreFraisId);
    if (frais == null) return false;
    final liste = frais.tranchesParCle[cle];
    if (liste == null) return false;
    for (final t in liste) {
      if (t.id == trancheId) {
        t.nom = nom.trim();
        t.montant = montant;
        if (mois != null) t.mois = mois.trim();
        await saveData();
        return true;
      }
    }
    return false;
  }

  int compterPaiementsPourTranche(String trancheId) {
    int count = 0;
    for (final liste in autresFraisPaiementsByYear.values) {
      for (final p in liste) {
        if (p.trancheId == trancheId) count++;
      }
    }
    return count;
  }

  Future<bool> deleteTranchePourAutreFrais({
    required String autreFraisId,
    required String cle,
    required String trancheId,
  }) async {
    if (compterPaiementsPourTranche(trancheId) > 0) return false;
    final frais = _trouverAutreFrais(autreFraisId);
    if (frais == null) return false;
    final liste = frais.tranchesParCle[cle];
    if (liste == null) return false;
    liste.removeWhere((t) => t.id == trancheId);
    if (liste.isEmpty) frais.tranchesParCle.remove(cle);
    await saveData();
    return true;
  }

  // ==========================================================================
  // ⚡ NOUVEAU — PAIEMENT PAR MOIS (Autres Frais)
  // Un frais peut, pour une cible (toute l'école, une section ou une classe),
  // se payer mois par mois au lieu de tranches. Chaque mois est une échéance
  // (AutreFraisTranche avec « mois » rempli) : l'ordre de la liste est l'ordre
  // de paiement (1er mois, 2e mois, ...). Les paiements, reçus, annulations,
  // modifications et rapports par tranche fonctionnent donc tels quels.
  // ==========================================================================
  static const List<String> moisAutresFraisDisponibles = [
    'Septembre', 'Octobre', 'Novembre', 'Décembre', 'Janvier', 'Février',
    'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août',
  ];

  static String _normaliserMois(String m) => m
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('û', 'u');

  static bool memeMois(String a, String b) =>
      _normaliserMois(a) == _normaliserMois(b);

  // Position du mois dans l'année scolaire (pour trier les listes).
  static int rangMoisScolaire(String mois) {
    for (var i = 0; i < moisAutresFraisDisponibles.length; i++) {
      if (memeMois(moisAutresFraisDisponibles[i], mois)) return i;
    }
    return 1 << 20;
  }

  String nomMoisOrdinal(int numero) {
    switch (numero) {
      case 1:
        return '1er mois';
      default:
        return '${numero}e mois';
    }
  }

  // Vrai si les échéances de cette cible sont des mois.
  bool cleEstParMois(AutreFrais frais, String cle) {
    final liste = frais.tranchesParCle[cle];
    return liste != null && liste.isNotEmpty && liste.every((t) => t.estMois);
  }

  // Vrai si ce frais se paie par mois pour au moins une cible.
  bool autreFraisAMois(AutreFrais frais) =>
      frais.tranchesParCle.values.any((l) => l.any((t) => t.estMois));

  // Tous les mois utilisés par ce frais (toutes cibles), dans l'ordre de
  // l'année scolaire.
  List<String> moisDefinisAutreFrais(AutreFrais frais) {
    final result = <String>[];
    for (final liste in frais.tranchesParCle.values) {
      for (final t in liste) {
        if (!t.estMois) continue;
        if (!result.any((m) => memeMois(m, t.mois))) result.add(t.mois.trim());
      }
    }
    result.sort(
            (a, b) => rangMoisScolaire(a).compareTo(rangMoisScolaire(b)));
    return result;
  }

  // Ajoute des mois (dans l'ordre donné) à la fin de la liste de la cible.
  // Les mois déjà présents sont ignorés. Refusé si la cible a déjà des
  // tranches classiques. Renvoie le nombre de mois ajoutés.
  Future<int> addMoisPourAutreFrais({
    required String autreFraisId,
    required String cle,
    required List<String> mois,
    required double montantParMois,
  }) async {
    final frais = _trouverAutreFrais(autreFraisId);
    if (frais == null) return 0;
    if ((frais.tranchesParCle[cle] ?? const <AutreFraisTranche>[])
        .any((t) => !t.estMois)) {
      throw Exception('Cette cible a déjà des tranches classiques. '
          'Supprimez-les avant de passer au paiement par mois.');
    }
    final liste = frais.tranchesParCle.putIfAbsent(cle, () => []);
    int ajoutes = 0;
    final base = DateTime.now().microsecondsSinceEpoch;
    for (final m in mois) {
      final String nomMois = m.trim();
      if (nomMois.isEmpty) continue;
      if (liste.any((t) => memeMois(t.mois, nomMois))) continue;
      liste.add(AutreFraisTranche(
        id: 'TRM${base + ajoutes}',
        nom: nomMois,
        montant: montantParMois,
        mois: nomMois,
      ));
      ajoutes++;
    }
    if (liste.isEmpty) frais.tranchesParCle.remove(cle);
    if (ajoutes > 0) await saveData();
    return ajoutes;
  }

  // Nombre de paiements rattachés à une échéance de cette cible.
  int compterPaiementsPourCle(AutreFrais frais, String cle) {
    final liste = frais.tranchesParCle[cle];
    if (liste == null) return 0;
    int n = 0;
    for (final t in liste) {
      n += compterPaiementsPourTranche(t.id);
    }
    return n;
  }

  // Déplace une échéance (mois ou tranche) d'un cran vers le haut (-1) ou le
  // bas (+1) : cela change l'ordre de paiement. Refusé dès qu'un paiement est
  // rattaché à une échéance de cette cible (l'ordre déjà payé doit rester).
  Future<bool> deplacerTranchePourAutreFrais({
    required String autreFraisId,
    required String cle,
    required String trancheId,
    required int delta,
  }) async {
    final frais = _trouverAutreFrais(autreFraisId);
    if (frais == null) return false;
    final liste = frais.tranchesParCle[cle];
    if (liste == null) return false;
    if (compterPaiementsPourCle(frais, cle) > 0) return false;
    final int i = liste.indexWhere((t) => t.id == trancheId);
    final int j = i + delta;
    if (i < 0 || j < 0 || j >= liste.length) return false;
    final t = liste.removeAt(i);
    liste.insert(j, t);
    await saveData();
    return true;
  }

  // Copie la liste d'échéances (mois ou tranches) d'une cible vers d'autres
  // cibles (ex : « ces classes de telle section paient ces mois »). Une cible
  // qui a déjà des paiements rattachés est laissée telle quelle.
  Future<({int copiees, List<String> ignorees})> copierTranchesVersCibles({
    required String autreFraisId,
    required String cleSource,
    required List<String> clesCibles,
  }) async {
    final frais = _trouverAutreFrais(autreFraisId);
    if (frais == null) return (copiees: 0, ignorees: <String>[]);
    final source = frais.tranchesParCle[cleSource] ?? const <AutreFraisTranche>[];
    int copiees = 0;
    final ignorees = <String>[];
    int compteur = 0;
    final base = DateTime.now().microsecondsSinceEpoch;
    for (final cle in clesCibles) {
      if (cle == cleSource) continue;
      if (compterPaiementsPourCle(frais, cle) > 0) {
        ignorees.add(cle);
        continue;
      }
      if (source.isEmpty) {
        frais.tranchesParCle.remove(cle);
      } else {
        frais.tranchesParCle[cle] = source
            .map((t) => AutreFraisTranche(
          id: 'TRC${base + compteur++}',
          nom: t.nom,
          montant: t.montant,
          mois: t.mois,
        ))
            .toList();
      }
      copiees++;
    }
    if (copiees > 0) await saveData();
    return (copiees: copiees, ignorees: ignorees);
  }

  // Libellé lisible d'une clé de cible ('ALL', 'S:...', 'C:...').
  String libelleCleTranche(String cle) {
    if (cle == kTrancheCleTous) return "Toute l'école";
    if (cle.startsWith('S:')) return 'Section ${cle.substring(2)}';
    if (cle.startsWith('C:')) {
      final reste = cle.substring(2);
      final int k = reste.indexOf('|');
      if (k > 0) {
        return 'Classe ${reste.substring(k + 1)} (${reste.substring(0, k)})';
      }
      return 'Classe $reste';
    }
    return cle;
  }

  // Élèves qui ont payé / pas encore payé un MOIS donné de ce frais. Seuls
  // les élèves dont la classe (ou section, ou toute l'école) doit payer ce
  // mois sont concernés. Un mois est payé quand le cumul versé couvre tous
  // les mois précédents dans l'ordre de paiement, plus ce mois.
  ({
    List<AutreFraisRecouvrementLigne> payes,
    List<AutreFraisRecouvrementLigne> nonPayes,
  }) recouvrementAutreFraisParMois(
      AutreFrais frais,
      String mois, {
        String? section,
        String? classe,
        String? year,
      }) {
    final payes = <AutreFraisRecouvrementLigne>[];
    final nonPayes = <AutreFraisRecouvrementLigne>[];
    for (final e in getEligibleStudentsForAutreFrais(frais)) {
      if (section != null && e.section != section) continue;
      if (classe != null && e.classe != classe) continue;
      final statut = getStatutAutreFrais(frais, e, year: year);
      AutreFraisTrancheEtat? et;
      for (final x in statut.etatsTranches) {
        if (x.tranche.estMois && memeMois(x.tranche.mois, mois)) {
          et = x;
          break;
        }
      }
      if (et == null) continue;
      final bool paye = et.etat == AutreFraisEtatTranche.payee;
      final ligne = AutreFraisRecouvrementLigne(
        eleve: e,
        montantDu: et.montantDu,
        montantPaye: paye ? et.montantDu : et.verse,
        paye: paye,
      );
      (paye ? payes : nonPayes).add(ligne);
    }
    return (payes: payes, nonPayes: nonPayes);
  }

  List<AutreFraisPaiement> getPaiementsEleveAutreFrais(
      Eleve eleve, AutreFrais frais, [String? year]) {
    final y = year ?? currentYear;
    return (autresFraisPaiementsByYear[y] ?? [])
        .where((p) => p.autreFraisId == frais.id && p.eleveId == eleve.id)
        .toList();
  }

  AutreFraisStatut getStatutAutreFrais(
      AutreFrais frais,
      Eleve eleve, {
        String? year,
        List<AutreFraisPaiement>? paiements,
      }) {
    final liste = paiements ?? getPaiementsEleveAutreFrais(eleve, frais, year);
    final double totalPaye = liste.fold(0.0, (sum, p) => sum + p.montant);
    final tranches = getTranchesPourEleve(frais, eleve);

    if (tranches.isEmpty) {
      final double montant = getMontantAutreFraisPourEleve(frais, eleve);
      // Un paiement "classique" (tous les anciens paiements) solde le frais
      // comme avant. Les paiements saisis librement s'additionnent.
      final bool aPaiementClassique = liste.any((p) => !p.saisieLibre);
      final bool solde = liste.isNotEmpty &&
          (aPaiementClassique || totalPaye + _toleranceMontant >= montant);
      final double reste =
      solde ? 0.0 : (montant - totalPaye > 0 ? montant - totalPaye : 0.0);
      return AutreFraisStatut(
        tranches: tranches,
        nbPayees: 0,
        totalPaye: totalPaye,
        totalDu: montant,
        reste: reste,
        prochaine: null,
        montantProchain: reste,
        solde: solde,
        partiel: liste.isNotEmpty && !solde,
      );
    }

    double cumul = 0;
    int nbPayees = 0;
    AutreFraisTranche? prochaine;
    double montantProchain = 0;
    for (final t in tranches) {
      cumul += t.montant;
      if (totalPaye + _toleranceMontant >= cumul) {
        if (prochaine == null) nbPayees++;
      } else if (prochaine == null) {
        prochaine = t;
        montantProchain = cumul - totalPaye;
      }
    }

    final bool solde = liste.isNotEmpty && prochaine == null;
    final double reste = cumul - totalPaye > 0 ? cumul - totalPaye : 0.0;
    return AutreFraisStatut(
      tranches: tranches,
      nbPayees: nbPayees,
      totalPaye: totalPaye,
      totalDu: cumul,
      reste: solde ? 0.0 : reste,
      prochaine: prochaine,
      montantProchain: montantProchain,
      solde: solde,
      partiel: liste.isNotEmpty && !solde,
      etatsTranches: repartirSurTranchesAutreFrais(tranches, totalPaye),
    );
  }

  // ⚡ NOUVEAU — répartit un cumul payé dans l'ordre des tranches.
  // Une tranche est payée quand le cumul couvre toutes les tranches jusqu'à
  // elle (même règle et même tolérance que nbPayees).
  static List<AutreFraisTrancheEtat> repartirSurTranchesAutreFrais(
      List<AutreFraisTranche> tranches, double totalPaye) {
    final result = <AutreFraisTrancheEtat>[];
    double cumulAvant = 0;
    for (var i = 0; i < tranches.length; i++) {
      final t = tranches[i];
      final double cumulFin = cumulAvant + t.montant;
      double verse = totalPaye - cumulAvant;
      if (verse < 0) verse = 0;
      if (verse > t.montant) verse = t.montant;
      final AutreFraisEtatTranche etat;
      if (totalPaye + _toleranceMontant >= cumulFin) {
        etat = AutreFraisEtatTranche.payee;
      } else if (verse > _toleranceMontant) {
        etat = AutreFraisEtatTranche.partielle;
      } else {
        etat = AutreFraisEtatTranche.nonPayee;
        verse = 0;
      }
      result.add(AutreFraisTrancheEtat(
        tranche: t,
        numero: i + 1,
        montantDu: t.montant,
        verse: verse,
        etat: etat,
      ));
      cumulAvant = cumulFin;
    }
    return result;
  }

  // ⚡ NOUVEAU — paiements d'un élève pour un frais, dans l'ordre de
  // répartition (date, puis ordre d'enregistrement).
  List<AutreFraisPaiement> paiementsOrdonnesAutreFrais(
      Eleve eleve, AutreFrais frais, [String? year]) {
    final y = year ?? currentYear;
    final liste = autresFraisPaiementsByYear[y] ?? const <AutreFraisPaiement>[];
    final indices = <int>[];
    for (var i = 0; i < liste.length; i++) {
      if (liste[i].autreFraisId == frais.id && liste[i].eleveId == eleve.id) {
        indices.add(i);
      }
    }
    indices.sort((a, b) {
      final c = liste[a].date.compareTo(liste[b].date);
      if (c != 0) return c;
      return a.compareTo(b);
    });
    return indices.map((i) => liste[i]).toList();
  }

  // ⚡ NOUVEAU — part de chaque paiement dans chaque tranche (index de
  // tranche -> montant), paiements pris dans l'ordre. Tout excédent au-delà
  // du total des tranches est compté sur la dernière tranche.
  static List<Map<int, double>> ventilerPaiementsAutreFrais(
      List<AutreFraisTranche> tranches, List<AutreFraisPaiement> ordonnes) {
    final result = <Map<int, double>>[];
    double cumulAvant = 0;
    for (final p in ordonnes) {
      final parts = <int, double>{};
      double debut = cumulAvant;
      final double fin = cumulAvant + p.montant;
      double c = 0;
      for (var j = 0; j < tranches.length && debut < fin; j++) {
        final double cFin = c + tranches[j].montant;
        final bool derniere = j == tranches.length - 1;
        if (debut < cFin || derniere) {
          final double haut = derniere ? fin : (fin < cFin ? fin : cFin);
          final double part = haut - debut;
          if (part > 0) parts[j] = (parts[j] ?? 0) + part;
          debut = haut;
        }
        c = cFin;
      }
      result.add(parts);
      cumulAvant = fin;
    }
    return result;
  }

  // ⚡ NOUVEAU — situation juste après un paiement (pour le reçu) : cumul
  // payé, reste et libellé des tranches couvertes par ce paiement.
  Map<String, dynamic> situationApresPaiementAutreFrais(
      AutreFrais frais, Eleve eleve, AutreFraisPaiement paiement,
      [String? year]) {
    final ordonnes = paiementsOrdonnesAutreFrais(eleve, frais, year);
    int idx = ordonnes.indexWhere((p) => p.id == paiement.id);
    if (idx < 0) {
      ordonnes.add(paiement);
      idx = ordonnes.length - 1;
    }
    final jusquIci = ordonnes.sublist(0, idx + 1);
    final statut = getStatutAutreFrais(frais, eleve, paiements: jusquIci);
    String tranchesCouvertes = '';
    if (statut.tranches.isNotEmpty) {
      final ventilation =
      ventilerPaiementsAutreFrais(statut.tranches, jusquIci);
      final parts = ventilation[idx];
      final etats = statut.etatsTranches;
      final morceaux = <String>[];
      final cles = parts.keys.toList()..sort();
      for (final j in cles) {
        final e = etats[j];
        final String etat = e.etat == AutreFraisEtatTranche.payee
            ? 'soldée'
            : 'partielle, reste ${e.reste.toStringAsFixed(0)} FC';
        morceaux.add('${e.tranche.nom} : ${parts[j]!.toStringAsFixed(0)} FC '
            '($etat)');
      }
      tranchesCouvertes = morceaux.join('\n');
    }
    return {
      'cumulPaye': statut.totalPaye,
      'totalDu': statut.totalDu,
      'resteAPayer': statut.reste,
      'tranchesCouvertes': tranchesCouvertes,
    };
  }

  // ⚡ NOUVEAU — recouvrement d'un frais : élèves qui ont payé / pas encore
  // payé une tranche (numeroTranche >= 1, par position : 1re, 2e...) ou le
  // frais entier (numeroTranche == 0). Pour une tranche, seuls les élèves
  // qui ont au moins ce nombre de tranches sont concernés.
  ({
    List<AutreFraisRecouvrementLigne> payes,
    List<AutreFraisRecouvrementLigne> nonPayes,
  }) recouvrementAutreFrais(
      AutreFrais frais,
      int numeroTranche, {
        String? section,
        String? classe,
        String? year,
      }) {
    final payes = <AutreFraisRecouvrementLigne>[];
    final nonPayes = <AutreFraisRecouvrementLigne>[];
    for (final e in getEligibleStudentsForAutreFrais(frais)) {
      if (section != null && e.section != section) continue;
      if (classe != null && e.classe != classe) continue;
      final statut = getStatutAutreFrais(frais, e, year: year);
      final AutreFraisRecouvrementLigne ligne;
      if (numeroTranche <= 0) {
        ligne = AutreFraisRecouvrementLigne(
          eleve: e,
          montantDu: statut.totalDu,
          montantPaye: statut.solde
              ? statut.totalDu
              : (statut.totalPaye < statut.totalDu
              ? statut.totalPaye
              : statut.totalDu),
          paye: statut.solde,
        );
      } else {
        if (statut.etatsTranches.length < numeroTranche) continue;
        // ⚡ Les élèves qui paient ce frais par mois ont leur propre liste
        // (par mois) : on ne les mélange pas aux tranches numérotées.
        if (statut.tranches.any((t) => t.estMois)) continue;
        final et = statut.etatsTranches[numeroTranche - 1];
        final bool paye = et.etat == AutreFraisEtatTranche.payee;
        ligne = AutreFraisRecouvrementLigne(
          eleve: e,
          montantDu: et.montantDu,
          montantPaye: paye ? et.montantDu : et.verse,
          paye: paye,
        );
      }
      (ligne.paye ? payes : nonPayes).add(ligne);
    }
    return (payes: payes, nonPayes: nonPayes);
  }

  // ⚡ NOUVEAU — nombre maximal de tranches de ce frais parmi les élèves
  // concernés (pour proposer "Tranche 1", "Tranche 2"... dans le filtre).
  int nombreMaxTranchesAutreFrais(AutreFrais frais) {
    int n = 0;
    for (final liste in frais.tranchesParCle.values) {
      if (liste.any((t) => t.estMois)) continue;
      if (liste.length > n) n = liste.length;
    }
    return n;
  }

  bool hasPaidTrancheAutreFrais(
      Eleve eleve, AutreFrais frais, AutreFraisTranche tranche,
      [String? year]) {
    final statut = getStatutAutreFrais(frais, eleve, year: year);
    final idx = statut.tranches.indexWhere((t) => t.id == tranche.id);
    return idx >= 0 && idx < statut.nbPayees;
  }

  AutreFraisTranche? getProchaineTrancheAutreFrais(
      AutreFrais frais, Eleve eleve,
      [String? year]) {
    return getStatutAutreFrais(frais, eleve, year: year).prochaine;
  }

  int getNombreTranchesPayeesAutreFrais(Eleve eleve, AutreFrais frais,
      [String? year]) {
    return getStatutAutreFrais(frais, eleve, year: year).nbPayees;
  }

  double getMontantProchainPaiementAutreFrais(AutreFrais frais, Eleve eleve) {
    final statut = getStatutAutreFrais(frais, eleve);
    if (statut.tranches.isEmpty) {
      // Sans tranches : le reste dû (montant plein s'il n'y a aucun paiement).
      return statut.solde
          ? getMontantAutreFraisPourEleve(frais, eleve)
          : statut.reste;
    }
    return statut.prochaine != null ? statut.montantProchain : 0.0;
  }

  double getResteAPayerAutreFrais(AutreFrais frais, Eleve eleve) {
    return getStatutAutreFrais(frais, eleve).reste;
  }

  bool hasPaidAutreFrais(Eleve eleve, AutreFrais frais, [String? year]) {
    return getStatutAutreFrais(frais, eleve, year: year).solde;
  }

  bool hasPaidPartiellementAutreFrais(Eleve eleve, AutreFrais frais,
      [String? year]) {
    return getStatutAutreFrais(frais, eleve, year: year).partiel;
  }

  Future<AutreFraisPaiement> payAutreFrais({
    required AutreFrais frais,
    required Eleve eleve,
    String enregistrePar = 'Direction',
    AutreFraisTranche? tranche,
    // ⚡ NOUVEAU — montant saisi librement (paiement partiel). Null = payer
    // la tranche entière (ou le reste du frais s'il n'a pas de tranches).
    double? montantSaisi,
  }) async {
    final statut = getStatutAutreFrais(frais, eleve);
    final tranches = statut.tranches;

    AutreFraisTranche? aPayer;
    double montant;
    int numeroTranche = 0;
    bool saisieLibre = montantSaisi != null;

    if (tranches.isNotEmpty) {
      if (statut.solde || statut.prochaine == null) {
        throw Exception('Toutes les tranches de "${frais.nom}" sont déjà '
            'payées pour cet élève.');
      }
      if (tranche != null && hasPaidTrancheAutreFrais(eleve, frais, tranche)) {
        throw Exception('La tranche "${tranche.nom}" est déjà payée pour cet '
            'élève.');
      }
      aPayer = statut.prochaine;
      montant = statut.montantProchain;
      final idx = tranches.indexWhere((t) => t.id == aPayer!.id);
      numeroTranche = idx >= 0 ? idx + 1 : 0;
    } else {
      if (statut.solde) {
        throw Exception('"${frais.nom}" est déjà payé pour cet élève.');
      }
      montant = statut.reste;
      // Paiement du reste après un paiement partiel : il compte au cumul
      // (sinon l'annulation du paiement partiel laisserait le frais soldé).
      if (statut.totalPaye > 0) saisieLibre = true;
    }

    if (montantSaisi != null) {
      if (montantSaisi.isNaN || montantSaisi <= 0) {
        throw Exception('Le montant doit être supérieur à zéro.');
      }
      if (montantSaisi > statut.reste + _toleranceMontant) {
        throw Exception('Le montant dépasse le reste à payer pour '
            '"${frais.nom}". Maximum possible : '
            '${statut.reste.toStringAsFixed(0)} FC.');
      }
      montant = montantSaisi;
    }
    if (montant <= 0) {
      throw Exception('"${frais.nom}" est déjà payé pour cet élève.');
    }

    final paiement = AutreFraisPaiement(
      id: 'AFP${DateTime.now().microsecondsSinceEpoch}',
      autreFraisId: frais.id,
      autreFraisNom: frais.nom,
      eleveId: eleve.id,
      montant: montant,
      date: DateTime.now(),
      enregistrePar: enregistrePar,
      trancheId: aPayer?.id ?? '',
      trancheNom: aPayer?.nom ?? '',
      trancheNumero: numeroTranche,
      trancheTotal: aPayer != null ? tranches.length : 0,
      saisieLibre: saisieLibre,
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

  String libelleTranchePaiementAutreFrais(AutreFraisPaiement p) {
    if (p.trancheId.isEmpty) return 'Paiement unique / avant tranches';
    final String l = p.trancheLibelle;
    return l.isNotEmpty ? l : 'Tranche ${p.trancheNumero}';
  }

  String _libelleAuditPaiementAutreFrais(AutreFraisPaiement p) =>
      'Autres frais : ${p.autreFraisNom} (${libelleTranchePaiementAutreFrais(p)})';

  void _reaffecterTranchesPaiementsAutreFrais(
      AutreFrais frais, Eleve eleve, String year) {
    final liste = autresFraisPaiementsByYear[year];
    if (liste == null) return;
    final tranches = getTranchesPourEleve(frais, eleve);
    if (tranches.isEmpty) return;

    final indices = <int>[];
    for (var i = 0; i < liste.length; i++) {
      final p = liste[i];
      if (p.autreFraisId == frais.id && p.eleveId == eleve.id) {
        indices.add(i);
      }
    }
    indices.sort((a, b) {
      final c = liste[a].date.compareTo(liste[b].date);
      if (c != 0) return c;
      return a.compareTo(b);
    });

    // Chaque paiement lié à une tranche est rattaché à la tranche où tombe
    // son premier franc (pour un paiement d'une tranche entière, c'est la
    // tranche payée, comme avant).
    double cumulAvant = 0;
    for (final i in indices) {
      final p = liste[i];
      if (p.trancheId.isNotEmpty) {
        int cible = tranches.length - 1;
        double c = 0;
        for (var j = 0; j < tranches.length; j++) {
          c += tranches[j].montant;
          if (cumulAvant + _toleranceMontant < c) {
            cible = j;
            break;
          }
        }
        final t = tranches[cible];
        liste[i] = AutreFraisPaiement(
          id: p.id,
          autreFraisId: p.autreFraisId,
          autreFraisNom: p.autreFraisNom,
          eleveId: p.eleveId,
          montant: p.montant,
          date: p.date,
          enregistrePar: p.enregistrePar,
          trancheId: t.id,
          trancheNom: t.nom,
          trancheNumero: cible + 1,
          trancheTotal: tranches.length,
          saisieLibre: p.saisieLibre,
        );
      }
      cumulAvant += p.montant;
    }
  }

  Future<void> annulerPaiementAutreFrais({
    required AutreFraisPaiement paiement,
    required Eleve eleve,
    String? year,
  }) async {
    final y = year ?? currentYear;
    final liste = autresFraisPaiementsByYear[y];
    if (liste == null) {
      throw Exception('Paiement introuvable.');
    }
    final idx = liste.indexWhere((p) => p.id == paiement.id);
    if (idx < 0) {
      throw Exception('Paiement introuvable.');
    }
    final AutreFraisPaiement p = liste[idx];
    final String libelle = _libelleAuditPaiementAutreFrais(p);
    final double montantAvant = p.montant;

    liste.removeAt(idx);
    paiementsAutresFraisAnnules.add(p.id);

    final AutreFrais? frais = _trouverAutreFrais(p.autreFraisId);
    if (frais != null) {
      _reaffecterTranchesPaiementsAutreFrais(frais, eleve, y);
    }

    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().microsecondsSinceEpoch}',
      action: 'annulation',
      eleveId: eleve.id,
      eleveNomComplet: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      mois: libelle,
      montantAvant: montantAvant,
      montantApres: 0,
    ));

    await saveData();
  }

  Future<void> modifierMontantPaiementAutreFrais({
    required AutreFraisPaiement paiement,
    required Eleve eleve,
    required double newMontant,
    String? year,
  }) async {
    if (newMontant <= 0) {
      throw Exception('Le montant doit être supérieur à zéro.');
    }
    final y = year ?? currentYear;
    final liste = autresFraisPaiementsByYear[y];
    if (liste == null) {
      throw Exception('Paiement introuvable.');
    }
    final idx = liste.indexWhere((p) => p.id == paiement.id);
    if (idx < 0) {
      throw Exception('Paiement introuvable.');
    }
    final AutreFraisPaiement p = liste[idx];
    final AutreFrais? frais = _trouverAutreFrais(p.autreFraisId);

    bool saisieLibre = p.saisieLibre;
    if (frais != null) {
      final tranches = getTranchesPourEleve(frais, eleve);
      // Frais sans tranches : le paiement modifié compte au cumul, plafonné
      // au montant du frais.
      if (tranches.isEmpty) saisieLibre = true;
      final double totalDu = tranches.isNotEmpty
          ? tranches.fold(0.0, (sum, t) => sum + t.montant)
          : getMontantAutreFraisPourEleve(frais, eleve);
      final double autres = liste
          .where((x) =>
      x.id != p.id &&
          x.autreFraisId == frais.id &&
          x.eleveId == eleve.id)
          .fold(0.0, (sum, x) => sum + x.montant);
      if (autres + newMontant > totalDu + _toleranceMontant) {
        final double maxPossible =
        totalDu - autres > 0 ? totalDu - autres : 0.0;
        throw Exception('Le montant dépasse le total dû. Maximum possible '
            'pour ce paiement : ${maxPossible.toStringAsFixed(0)} FC.');
      }
    }

    final double montantAvant = p.montant;
    final String libelle = _libelleAuditPaiementAutreFrais(p);

    liste[idx] = AutreFraisPaiement(
      id: p.id,
      autreFraisId: p.autreFraisId,
      autreFraisNom: p.autreFraisNom,
      eleveId: p.eleveId,
      montant: newMontant,
      date: p.date,
      enregistrePar: p.enregistrePar,
      trancheId: p.trancheId,
      trancheNom: p.trancheNom,
      trancheNumero: p.trancheNumero,
      trancheTotal: p.trancheTotal,
      saisieLibre: saisieLibre,
    );

    if (frais != null) {
      _reaffecterTranchesPaiementsAutreFrais(frais, eleve, y);
    }

    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().microsecondsSinceEpoch}',
      action: 'modification',
      eleveId: eleve.id,
      eleveNomComplet: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      mois: libelle,
      montantAvant: montantAvant,
      montantApres: newMontant,
    ));

    await saveData();
  }

  List<AutreFraisPaiement> getAutresFraisPaiementsForYear([String? year]) {
    final y = year ?? currentYear;
    final list = List<AutreFraisPaiement>.from(
        autresFraisPaiementsByYear[y] ?? []);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  bool paiementAutreFraisDansPeriode(AutreFraisPaiement p, String period) {
    final now = DateTime.now();
    switch (period) {
      case 'today':
        return p.date.year == now.year &&
            p.date.month == now.month &&
            p.date.day == now.day;
      case 'month':
        return p.date.year == now.year && p.date.month == now.month;
      case 'year':
      default:
        return true;
    }
  }

  List<AutreFraisPaiement> getAutresFraisPaiementsPourPeriode(String period,
      [String? year]) {
    return getAutresFraisPaiementsForYear(year)
        .where((p) => paiementAutreFraisDansPeriode(p, period))
        .toList();
  }

  double getTotalPaidForAutreFrais(
      AutreFrais frais, {
        String? year,
        String? sectionFilter,
        String? classFilter,
        String period = 'year',
      }) {
    final y = year ?? currentYear;
    Iterable<AutreFraisPaiement> paiements =
    (autresFraisPaiementsByYear[y] ?? [])
        .where((p) =>
    p.autreFraisId == frais.id &&
        paiementAutreFraisDansPeriode(p, period));

    if (sectionFilter != null || classFilter != null) {
      paiements = paiements.where((p) {
        final Eleve? eleve = trouverEleveParId(p.eleveId, y);
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
    // ⚡ Les retenues sortent AVANT les pourcentages.
    final double retenues = retenuePourSectionPeriode(option, period);
    return RepartitionDetail(
      label: option,
      total: total,
      retenues: retenues,
      parAdministration: calculateAdminDistribution(total - retenues),
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

  List<RepartitionDetail> getSousSectionsForOptionPeriod(
      String option, String period) {
    final students = getStudentsBySection(option);
    final Map<String, double> totalsByLabel = {};
    final Map<String, double> retenuesByLabel = {};
    for (var e in students) {
      final label = _sousSectionLabelFor(e);
      final montant = _getStudentAmountForPeriod(e, period);
      totalsByLabel[label] = (totalsByLabel[label] ?? 0) + montant;
      retenuesByLabel[label] =
          (retenuesByLabel[label] ?? 0) + retenueEleve(e, period);
    }
    final details = totalsByLabel.entries.map((entry) {
      final double ret = retenuesByLabel[entry.key] ?? 0.0;
      return RepartitionDetail(
        label: entry.key,
        total: entry.value,
        retenues: ret,
        parAdministration: calculateAdminDistribution(entry.value - ret),
      );
    }).toList();
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
    final required     = getRequiredForMonthForEleve(eleve, mois);
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
          final double requis = getRequiredForMonthForEleve(eleve, mois);
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
      final int ma = months.indexOf(a.value['mois']?.toString() ?? '');
      final int mb = months.indexOf(b.value['mois']?.toString() ?? '');
      final int ia = ma < 0 ? months.length : ma;
      final int ib = mb < 0 ? months.length : mb;
      if (ia != ib) return ia.compareTo(ib);
      return a.key.compareTo(b.key);
    });

    final Map<String, double> nouveauPaid = {};
    int monthIndex = 0;

    for (final transaction in indexees.map((e) => e.value)) {
      final double montant =
          (transaction['amount'] as num?)?.toDouble() ?? 0.0;
      if (montant <= 0) continue;

      final String? moisFixe = transaction['moisDebloque'] == true
          ? transaction['mois']?.toString()
          : null;

      if (moisFixe != null && moisFixe.isNotEmpty) {
        nouveauPaid[moisFixe] = (nouveauPaid[moisFixe] ?? 0) + montant;
        continue;
      }

      while (monthIndex < months.length) {
        final mois = months[monthIndex];
        final requis = getRequiredForMonthForEleve(eleve, mois);
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

      final double montantRequis = getRequiredForMonthForEleve(eleve, mois);
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
      if (eleve.montantMensuelPersonnalise != null) continue;

      bool modifie = false;
      for (final mois in anciensRequisParMois.keys) {
        final double? ancienRequis = anciensRequisParMois[mois];
        if (ancienRequis == null) continue;

        final double nouveauRequis = getRequiredForMonthForEleve(eleve, mois);

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
      double required    = getRequiredForMonthForEleve(eleve, currentMonth);
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

  List<Map<String, dynamic>> _distribuerSurMoisSuivants(
      Eleve eleve, double montant, {String? moisExclu}) {
    final String today = DateTime.now().toString().split(' ')[0];
    final List<Map<String, dynamic>> nouvellesTransactions = [];

    String genererId() =>
        'TX${DateTime.now().microsecondsSinceEpoch}_${nouvellesTransactions.length}_c';

    double remaining = montant;
    int index = 0;
    while (remaining > 0 && index < months.length) {
      final mois = months[index];
      if (mois == moisExclu) {
        index++;
        continue;
      }
      final double required = getRequiredForMonthForEleve(eleve, mois);
      final double dejaPaye = eleve.paid[mois] ?? 0;
      final double needed = required - dejaPaye;
      if (needed > 0) {
        final double toAdd = remaining >= needed ? needed : remaining;
        eleve.paid[mois] = dejaPaye + toAdd;
        final transaction = <String, dynamic>{
          'id': genererId(),
          'date': today,
          'mois': mois,
          'amount': toAdd,
        };
        eleve.transactions.add(transaction);
        nouvellesTransactions.add(transaction);
        remaining -= toAdd;
      }
      index++;
    }

    if (remaining > 0 && months.isNotEmpty) {
      final dernierMois = months.last;
      if (dernierMois != moisExclu) {
        final double dejaPayeDernierMois = eleve.paid[dernierMois] ?? 0;
        eleve.paid[dernierMois] = dejaPayeDernierMois + remaining;
        final transaction = <String, dynamic>{
          'id': genererId(),
          'date': today,
          'mois': dernierMois,
          'amount': remaining,
          'excedent': true,
        };
        eleve.transactions.add(transaction);
        nouvellesTransactions.add(transaction);
      }
    }

    return nouvellesTransactions;
  }

  List<Map<String, dynamic>> handlePaymentMoisDebloque(
      Eleve eleve, String moisDebloque, double montant) {
    final String today = DateTime.now().toString().split(' ')[0];
    final List<Map<String, dynamic>> nouvellesTransactions = [];

    String genererId() =>
        'TX${DateTime.now().microsecondsSinceEpoch}_${nouvellesTransactions.length}_d';

    final double required = getRequiredForMonthForEleve(eleve, moisDebloque);
    final double dejaPaye = eleve.paid[moisDebloque] ?? 0;
    final double needed = required - dejaPaye;
    double remaining = montant;

    if (needed > 0) {
      final double toAdd = remaining >= needed ? needed : remaining;
      eleve.paid[moisDebloque] = dejaPaye + toAdd;
      final transaction = <String, dynamic>{
        'id': genererId(),
        'date': today,
        'mois': moisDebloque,
        'amount': toAdd,
        'moisDebloque': true,
      };
      eleve.transactions.add(transaction);
      nouvellesTransactions.add(transaction);
      remaining -= toAdd;
    }

    if (remaining > 0) {
      nouvellesTransactions.addAll(
        _distribuerSurMoisSuivants(eleve, remaining, moisExclu: moisDebloque),
      );
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
            (getRequiredForMonthForEleve(eleve, m) -
                (eleve.paid[m] ?? 0)));
  }

  List<Eleve> getElevesSupprimes() {
    final list = List<Eleve>.from(elevesSupprimesData.eleves);
    list.sort((a, b) {
      final dateA = dateSuppressionEleves[a.id] ?? '';
      final dateB = dateSuppressionEleves[b.id] ?? '';
      return dateB.compareTo(dateA);
    });
    return list;
  }

  String? getDateSuppressionEleve(String eleveId) =>
      dateSuppressionEleves[eleveId];

  String? getMotifSuppressionEleve(String eleveId) =>
      motifSuppressionEleves[eleveId];

  Future<void> archiverEtSupprimerEleve(
      Eleve eleve, {
        String motif = 'Suppression manuelle',
      }) async {
    currentData.eleves.removeWhere((e) => e.id == eleve.id);
    elevesSupprimesData.eleves.removeWhere((e) => e.id == eleve.id);
    elevesSupprimesData.eleves.add(eleve);
    dateSuppressionEleves[eleve.id] = DateTime.now().toIso8601String();
    motifSuppressionEleves[eleve.id] = motif;
    await saveData();
  }

  Future<void> supprimerDefinitivementEleveArchive(String eleveId) async {
    elevesSupprimesData.eleves.removeWhere((e) => e.id == eleveId);
    dateSuppressionEleves.remove(eleveId);
    motifSuppressionEleves.remove(eleveId);
    await saveData();
  }

  Future<void> viderHistoriqueElevesSupprimes() async {
    elevesSupprimesData = SchoolYearData(eleves: []);
    dateSuppressionEleves = {};
    motifSuppressionEleves = {};
    await saveData();
  }
}