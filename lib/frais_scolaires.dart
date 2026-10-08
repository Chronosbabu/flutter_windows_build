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

part 'frais_scolaires_modeles.dart';
part 'frais_scolaires_rapports.dart';
part 'frais_scolaires_services.dart';

const String serverUrl = "https://jsinf.onrender.com";

class AutreFraisStatut {
  final List<AutreFraisTranche> tranches;
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
  List<AutreFrais> autresFrais = [];
  Map<String, List<AutreFraisPaiement>> autresFraisPaiementsByYear = {};
  Set<String> paiementsAutresFraisAnnules = {};
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
        .where((d) => d.date.year == now.year && d.date.month == now.month)
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
    return totalCollecte - getTotalDepenses(y);
  }

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
          okPeriode = d.date.year == now.year && d.date.month == now.month;
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

    final depenses = getDepensesForPeriod(
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
        collecte: totalCollecte * (admin.pourcentage / 100),
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
    double collecte = 0;
    if (portee == kDepenseGlobale) {
      collecte = collecteSec.values.fold(0.0, (a, b) => a + b) * pct / 100;
    } else {
      for (final s in sections) {
        collecte += (collecteSec[s] ?? 0) * pct / 100;
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
    return collecte - depense;
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
  }) async {
    final frais = _trouverAutreFrais(autreFraisId);
    if (frais == null) return false;
    final liste = frais.tranchesParCle[cle];
    if (liste == null) return false;
    for (final t in liste) {
      if (t.id == trancheId) {
        t.nom = nom.trim();
        t.montant = montant;
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
      final bool solde = liste.isNotEmpty;
      return AutreFraisStatut(
        tranches: tranches,
        nbPayees: 0,
        totalPaye: totalPaye,
        totalDu: montant,
        reste: solde ? 0.0 : montant,
        prochaine: null,
        montantProchain: solde ? 0.0 : montant,
        solde: solde,
        partiel: false,
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
    );
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
      return getMontantAutreFraisPourEleve(frais, eleve);
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
  }) async {
    final statut = getStatutAutreFrais(frais, eleve);
    final tranches = statut.tranches;

    AutreFraisTranche? aPayer;
    double montant;
    int numeroTranche = 0;

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
      montant = getMontantAutreFraisPourEleve(frais, eleve);
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

    double cumulPaye = 0;
    int prevK = 0;
    for (final i in indices) {
      final p = liste[i];
      cumulPaye += p.montant;

      int k = 0;
      double c = 0;
      for (final t in tranches) {
        c += t.montant;
        if (cumulPaye + _toleranceMontant >= c) {
          k++;
        } else {
          break;
        }
      }

      if (p.trancheId.isNotEmpty) {
        int cible;
        if (k > prevK) {
          cible = k - 1;
        } else {
          cible = prevK < tranches.length ? prevK : tranches.length - 1;
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
        );
      }

      if (k > prevK) prevK = k;
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

    if (frais != null) {
      final tranches = getTranchesPourEleve(frais, eleve);
      if (tranches.isNotEmpty) {
        final double totalDu =
        tranches.fold(0.0, (sum, t) => sum + t.montant);
        final double autres = liste
            .where((x) =>
        x.id != p.id &&
            x.autreFraisId == frais.id &&
            x.eleveId == eleve.id)
            .fold(0.0, (sum, x) => sum + x.montant);
        if (autres + newMontant > totalDu + _toleranceMontant) {
          final double maxPossible = totalDu - autres;
          throw Exception('Le montant dépasse le total dû. Maximum possible '
              'pour ce paiement : ${maxPossible.toStringAsFixed(0)} FC.');
        }
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