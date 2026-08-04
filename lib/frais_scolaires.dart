import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:file_selector/file_selector.dart';
import 'models.dart';

const String serverUrl = "https://jsinf.onrender.com";

class FraisScolaires {
  SchoolConfig config;
  SchoolYearData currentData = SchoolYearData(eleves: []);
  String currentYear = '2025-2026';
  Map<String, SchoolYearData> history = {};
  String? _dataFilePath;
  String? lastSelectedClassFilter;
  String? lastSelectedSectionFilter;
  String? schoolCode;

  // ⚡ Compteur local pour la génération d'IDs hors-ligne.
  // Sauvegardé dans le fichier JSON et incrémenté à chaque nouvel élève.
  int _localIdCounter = 0;

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre',
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
  ];

  FraisScolaires() : config = SchoolConfig(schoolName: "MAPENDO TCC");

  // ====================================================================
  // GÉNÉRATION D'ID LOCALE (sans connexion internet)
  // ====================================================================
  // L'ID est généré directement sur l'appareil, en incrémentant un
  // compteur local. Format : {PREFIX_NOM}{ANNEE_COURTE}{LETTRE_ECOLE}{N}
  // Ex: BA26M1, BA26M2, JO26M3...
  //
  // Lors du backup serveur, le serveur vérifie les conflits entre écoles
  // et retourne un dictionnaire de corrections. Le client applique ensuite
  // ces corrections localement.
  String generateLocalStudentId(String nom) {
    final yearShort = currentYear.length >= 2
        ? currentYear.substring(currentYear.length - 2)
        : '26';
    final schoolLetter = config.schoolName.isNotEmpty
        ? config.schoolName[0].toUpperCase()
        : 'B';
    final nameRaw = nom.trim().toUpperCase();
    final namePrefix = nameRaw.length >= 2
        ? nameRaw.substring(0, 2)
        : nameRaw.padRight(2, 'X');

    // Collecter tous les IDs déjà utilisés (toutes années confondues)
    final allIds = history.values
        .expand((yd) => yd.eleves)
        .map((e) => e.id)
        .where((id) => id.isNotEmpty)
        .toSet();

    _localIdCounter++;
    String candidate = '$namePrefix$yearShort$schoolLetter$_localIdCounter';

    // S'assurer de l'unicité locale
    while (allIds.contains(candidate)) {
      _localIdCounter++;
      candidate = '$namePrefix$yearShort$schoolLetter$_localIdCounter';
    }

    return candidate;
  }

  // Compatibilité avec le code existant (enregistrer_eleve_screen etc.)
  // L'ID est maintenant généré localement ; plus besoin d'internet.
  Future<String> generateUniqueStudentId(
      String nom, String schoolCodeForServer) async {
    if (nom.trim().isEmpty) {
      throw Exception(
          "Le nom de l'élève est requis pour générer un identifiant.");
    }
    return generateLocalStudentId(nom);
  }

  // ====================================================================
  // APPLIQUER LES CORRECTIONS D'IDs REÇUES DU SERVEUR
  // ====================================================================
  // Après un backup, le serveur peut signaler des conflits d'IDs entre
  // écoles et fournir un mapping {ancien_id: nouvel_id}. On met à jour
  // tous les enregistrements locaux en conséquence.
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

  // ==================== GESTION DES CLASSES & SOUS-CLASSES ====================
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

  List<String> getSubClassesFor(String section, String classeNumero) {
    return config.subClassesByClasse[_classeKey(section, classeNumero)] ?? [];
  }

  Future<void> addSubClasse(
      String section, String classeNumero, String subClasse) async {
    final trimmed = subClasse.trim();
    if (trimmed.isEmpty) return;
    final key = _classeKey(section, classeNumero);
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

  // ==================== PASSATION VERS LA CLASSE / ANNÉE SUPÉRIEURE ====================
  String? getNextClasseNumero(String section, String classeNumero) {
    final list = getClassesForSection(section);
    final idx = list.indexOf(classeNumero);
    if (idx == -1 || idx == list.length - 1) return null;
    return list[idx + 1];
  }

  String computePromotedClasse(Eleve eleve) {
    final numero = classeNumeroFromFullClasse(eleve.classe);
    final subClasse = subClasseFromFullClasse(eleve.classe);
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
    int promoted = 0;
    int abandoned = 0;
    int redoublants = 0;

    if (!history.containsKey(targetYear)) {
      history[targetYear] = SchoolYearData(eleves: []);
    }
    final targetData = history[targetYear]!;
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
        existing.classe = newClasse;
        existing.section = eleve.section;
      } else {
        targetData.eleves.add(Eleve(
          id: eleve.id,
          nom: eleve.nom,
          postNom: eleve.postNom,
          prenom: eleve.prenom,
          classe: newClasse,
          section: eleve.section,
        ));
        existingIds.add(eleve.id);
      }
      promoted++;
    }

    await saveData();
    return {
      'promoted': promoted,
      'abandoned': abandoned,
      'redoublants': redoublants,
    };
  }

  // ==================== FILTRES ====================
  List<Eleve> getStudentsBySection(String section) =>
      currentData.eleves.where((e) => e.section == section).toList();

  List<Eleve> getStudentsByClass(String classe) =>
      currentData.eleves.where((e) => e.classe == classe).toList();

  List<Eleve> getStudentsBySectionAndClass(String? section, String? classe) {
    return currentData.eleves.where((e) {
      final matchSection = section == null || e.section == section;
      final matchClass = classe == null || e.classe == classe;
      return matchSection && matchClass;
    }).toList();
  }

  // ==================== CALCULS ====================
  double getRequiredForMonth(String mois, String section, [String? classe]) {
    if (classe != null && classe.trim().isNotEmpty) {
      final classeNumero = classeNumeroFromFullClasse(classe);
      final key = _classeKey(section, classeNumero);
      final classExceptions = config.monthlyExceptionsByClasse[key];
      if (classExceptions != null && classExceptions.containsKey(mois)) {
        return classExceptions[mois]!;
      }
      if (config.feesByClasse.containsKey(key)) {
        return config.feesByClasse[key]!;
      }
    }
    final exceptions = config.monthlyExceptionsBySection[section];
    if (exceptions != null && exceptions.containsKey(mois)) {
      return exceptions[mois]!;
    }
    return config.feesBySection[section] ?? 35000;
  }

  Map<String, double> getTotalBySection() {
    Map<String, double> totals = {};
    for (var eleve in currentData.eleves) {
      double totalEleve = getStudentTotalPaid(eleve);
      totals[eleve.section] = (totals[eleve.section] ?? 0) + totalEleve;
    }
    return totals;
  }

  Map<String, double> getTotalByClass() {
    Map<String, double> totals = {};
    for (var eleve in currentData.eleves) {
      double totalEleve = getStudentTotalPaid(eleve);
      String key = "${eleve.section} - ${eleve.classe}";
      totals[key] = (totals[key] ?? 0) + totalEleve;
    }
    return totals;
  }

  double getYearTotalCollected() {
    return months.fold(
        0.0,
            (sum, m) =>
        sum +
            currentData.eleves
                .fold(0.0, (s, e) => s + (e.paid[m] ?? 0)));
  }

  double getCurrentMonthTotalCollected() {
    final now = DateTime.now();
    if (now.month - 1 < 0 || now.month - 1 >= months.length) return 0.0;
    final currentMonthName = months[now.month - 1];
    return currentData.eleves
        .fold(0.0, (sum, e) => sum + (e.paid[currentMonthName] ?? 0));
  }

  List<Eleve> getPaidStudentsToday() {
    String today = DateTime.now().toString().split(' ')[0];
    return currentData.eleves
        .where((eleve) => eleve.transactions.any((t) => t['date'] == today))
        .toList();
  }

  List<Eleve> getPaidStudentsThisMonth() {
    String currentMonthName = months[DateTime.now().month - 1];
    return currentData.eleves
        .where((eleve) =>
    eleve.paid.containsKey(currentMonthName) &&
        eleve.paid[currentMonthName]! > 0)
        .toList();
  }

  Map<String, double> calculateAdminDistribution(double totalAmount) {
    Map<String, double> distribution = {};
    for (var admin in config.administrations) {
      distribution[admin.nom] = totalAmount * (admin.pourcentage / 100);
    }
    return distribution;
  }

  // ==================== GÉNÉRATION PDF ====================
  Future<void> generatePdf({
    required String filename,
    required String reportType,
    String? sectionFilter,
    String? classFilter,
  }) async {
    if (reportType == "student_list") {
      await _generateStudentListPdf(
        filename: filename,
        sectionFilter: sectionFilter,
        classFilter: classFilter,
      );
      return;
    }

    final pdf = pw.Document();
    List<Eleve> students = [];
    String title = "";

    if (reportType == "daily") {
      students = getPaidStudentsToday();
      title = "RAPPORT JOURNALIER";
    } else if (reportType == "monthly") {
      students = getPaidStudentsThisMonth();
      title = "RAPPORT MENSUEL";
    } else {
      students = currentData.eleves;
      title = "RAPPORT ANNUEL";
    }

    if (sectionFilter != null) {
      students = students.where((e) => e.section == sectionFilter).toList();
      title += " - $sectionFilter";
    }
    if (classFilter != null) {
      students = students.where((e) => e.classe == classFilter).toList();
      title += " - $classFilter";
    }

    double total =
    students.fold(0.0, (sum, e) => sum + getStudentTotalPaid(e));
    final adminDistribution = calculateAdminDistribution(total);
    final double totalMoisEcole = getCurrentMonthTotalCollected();
    final double totalAnneeEcole = getYearTotalCollected();
    final String currentMonthName =
    (DateTime.now().month - 1 >= 0 &&
        DateTime.now().month - 1 < months.length)
        ? months[DateTime.now().month - 1]
        : "Mois en cours";

    final List<String> headers = [
      'ID',
      'Nom Complet',
      'Section',
      'Classe',
      'Montant Payé (FC)',
      ...config.administrations
          .map((a) => '${a.nom} (${a.pourcentage.toStringAsFixed(0)}%)'),
    ];

    final List<List<String>> rows = students.map((e) {
      final double montantEleve = getStudentTotalPaid(e);
      final List<String> row = [
        e.id.isNotEmpty ? e.id : "N/A",
        "${e.nom} ${e.postNom} ${e.prenom}",
        e.section,
        e.classe,
        montantEleve.toStringAsFixed(0),
      ];
      for (var admin in config.administrations) {
        final double partAdmin = montantEleve * (admin.pourcentage / 100);
        row.add(partAdmin.toStringAsFixed(0));
      }
      return row;
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text('${config.schoolName} - $currentYear'),
          pw.Text('Date: ${DateTime.now().toString().split(" ")[0]}'),
          pw.SizedBox(height: 20),
          pw.Text(
            "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            "Total Collecté ce Mois ($currentMonthName, toute l'école) : "
                "${totalMoisEcole.toStringAsFixed(0)} FC",
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.Text(
            "Total Collecté cette Année ($currentYear, toute l'école) : "
                "${totalAnneeEcole.toStringAsFixed(0)} FC",
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 20),
          pw.Text("LISTE DES ÉLÈVES",
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            "Pour chaque élève, le montant déjà payé est réparti par "
                "administration selon son pourcentage.",
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 30),
          pw.Text(
            "RÉPARTITION GLOBALE PAR ADMINISTRATION (CE RAPPORT)",
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          ...adminDistribution.entries.map(
                (entry) => pw.Text(
              "${entry.key} : ${entry.value.toStringAsFixed(0)} FC "
                  "(${config.administrations.firstWhere((a) => a.nom == entry.key).pourcentage.toStringAsFixed(0)}% "
                  "du total de ${total.toStringAsFixed(0)} FC)",
            ),
          ),
        ],
      ),
    );

    await _savePdf(pdf, filename, reportType);
  }

  Future<void> _generateStudentListPdf({
    required String filename,
    String? sectionFilter,
    String? classFilter,
  }) async {
    List<Eleve> students = currentData.eleves;
    if (sectionFilter != null) {
      students = students.where((e) => e.section == sectionFilter).toList();
    }
    if (classFilter != null) {
      students = students.where((e) => e.classe == classFilter).toList();
    }
    students.sort((a, b) {
      final classeComp = a.classe.compareTo(b.classe);
      if (classeComp != 0) return classeComp;
      return a.nom.compareTo(b.nom);
    });

    final String sectionLabel = sectionFilter ?? "Toutes les sections";
    final String classeLabel = classFilter ?? "Toutes les classes";
    final String dateStr = DateTime.now().toString().split(' ')[0];

    final List<List<String>> rows = [];
    for (int i = 0; i < students.length; i++) {
      final e = students[i];
      rows.add(['${i + 1}', e.nom, e.postNom, e.prenom, e.classe]);
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
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
              "REGISTRE DES ÉLÈVES  —  Année $currentYear",
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel     |     Classe : $classeLabel",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Imprimé le : $dateStr     |     Total : ${students.length} élève(s)",
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['N°', 'Nom', 'Post-nom', 'Prénom', 'Classe'],
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellHeight: 22,
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.center,
            },
            rowDecoration:
            const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo50),
          ),
        ],
      ),
    );

    await _savePdf(pdf, filename, "student_list");
  }

  Future<void> _savePdf(
      pw.Document pdf, String filename, String reportType) async {
    try {
      final bytes = await pdf.save();
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        final fileName =
            '${filename}_${reportType}_${DateTime.now().toString().split(' ')[0]}.pdf';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
      } else {
        final saveLocation = await getSaveLocation(
          suggestedName: '${filename}_${reportType}.pdf',
          acceptedTypeGroups: [
            XTypeGroup(label: 'PDF', extensions: ['pdf'])
          ],
        );
        if (saveLocation != null) {
          final file = File(saveLocation.path);
          await file.writeAsBytes(bytes);
          await OpenFile.open(file.path);
        }
      }
    } catch (e) {
      // Erreur PDF silencieuse
    }
  }

  // ==================== GESTION DES DONNÉES LOCALES ====================
  Future<void> loadData() async {
    final dir = await getApplicationDocumentsDirectory();
    _dataFilePath = '${dir.path}/school_fees_data.json';
    final file = File(_dataFilePath!);

    if (await file.exists()) {
      try {
        final jsonStr = await file.readAsString();
        final data = json.decode(jsonStr) as Map<String, dynamic>;

        config = SchoolConfig.fromJson(data['config'] ?? {});
        currentYear = data['currentYear'] ?? '2025-2026';
        lastSelectedClassFilter = data['lastSelectedClassFilter'];
        lastSelectedSectionFilter = data['lastSelectedSectionFilter'];

        if (data['history'] != null) {
          history = (data['history'] as Map<String, dynamic>).map(
                (key, value) =>
                MapEntry(key, SchoolYearData.fromJson(value)),
          );
        }

        if (history.containsKey(currentYear)) {
          currentData = history[currentYear]!;
        } else {
          currentData = SchoolYearData(eleves: []);
          history[currentYear] = currentData;
        }

        // ⚡ Charger le compteur d'IDs local
        if (data['localIdCounter'] != null) {
          _localIdCounter = data['localIdCounter'] as int;
        } else {
          // Initialiser depuis les IDs existants pour éviter les doublons
          _localIdCounter = _inferCounterFromExistingIds();
        }

        await _assignMissingIds();
      } catch (e) {
        _initDefaultData();
      }
    } else {
      _initDefaultData();
    }
  }

  /// Déduit la valeur de départ du compteur en trouvant le plus grand
  /// numéro de fin dans les IDs existants. Utilisé à la migration
  /// (première fois qu'on charge des données avec des IDs déjà créés).
  int _inferCounterFromExistingIds() {
    int maxCounter = 0;
    final regex = RegExp(r'(\d+)$');
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
    // Les IDs manquants sont maintenant générés localement, sans serveur.
    bool changed = false;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.id.isEmpty || eleve.id == "N/A") {
          eleve.id = generateLocalStudentId(eleve.nom);
          changed = true;
        }
      }
    }
    if (changed) await saveData();
  }

  void _initDefaultData() {
    currentData = SchoolYearData(eleves: []);
    history[currentYear] = currentData;
    _localIdCounter = 0;
  }

  Future<void> saveData() async {
    if (_dataFilePath == null) {
      final dir = await getApplicationDocumentsDirectory();
      _dataFilePath = '${dir.path}/school_fees_data.json';
    }
    history[currentYear] = currentData;
    final file = File(_dataFilePath!);
    final data = {
      'config': config.toJson(),
      'currentYear': currentYear,
      'localIdCounter': _localIdCounter,
      'lastSelectedClassFilter': lastSelectedClassFilter,
      'lastSelectedSectionFilter': lastSelectedSectionFilter,
      'history': history.map((key, value) => MapEntry(key, value.toJson())),
    };
    await file.writeAsString(json.encode(data));
  }

  Future<void> changeYear(String newYear) async {
    if (currentYear == newYear) return;
    history[currentYear] = currentData;
    currentYear = newYear;
    if (history.containsKey(newYear)) {
      currentData = history[newYear]!;
    } else {
      currentData = SchoolYearData(eleves: []);
      history[newYear] = currentData;
    }
    await saveData();
  }

  void handlePayment(Eleve eleve, String mois, double payment) {
    int index = months.indexOf(mois);
    if (index == -1) return;

    String today = DateTime.now().toString().split(' ')[0];
    double remaining = payment;
    String currentMonth = mois;

    while (remaining > 0 && index < months.length) {
      double required =
      getRequiredForMonth(currentMonth, eleve.section, eleve.classe);
      double alreadyPaid = eleve.paid[currentMonth] ?? 0;
      double needed = required - alreadyPaid;

      if (needed > 0) {
        double toAdd = remaining > needed ? needed : remaining;
        eleve.paid[currentMonth] = alreadyPaid + toAdd;
        eleve.transactions.add({
          'date': today,
          'mois': currentMonth,
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

  // ==================== BACKUP & RESTORE ====================
  Future<bool> backupToServer(String schoolCode, String password) async {
    try {
      this.schoolCode = schoolCode;
      final data = {
        'config': config.toJson(),
        'currentYear': currentYear,
        'localIdCounter': _localIdCounter,
        'lastSelectedClassFilter': lastSelectedClassFilter,
        'lastSelectedSectionFilter': lastSelectedSectionFilter,
        'history': history.map((key, value) => MapEntry(key, value.toJson())),
        'backup_password': password,
      };

      final response = await http.post(
        Uri.parse('$serverUrl/backup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'school_code': schoolCode, 'data': data}),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // ⚡ Appliquer les corrections d'IDs si le serveur en a trouvé
        final corrections =
            responseData['corrections'] as Map<String, dynamic>? ?? {};
        if (corrections.isNotEmpty) {
          _applyIdCorrections(corrections);
          await saveData();
        }

        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> restoreFromServer(String schoolCode, String password) async {
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/restore?school_code=$schoolCode'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['backup_password'] != null &&
            data['backup_password'] != password) {
          return false;
        }
        this.schoolCode = schoolCode;
        await _mergeRestoredData(data);
        await saveData();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _mergeRestoredData(Map<String, dynamic> serverData) async {
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
            (key, value) => MapEntry(key, SchoolYearData.fromJson(value)),
      );

      for (var entry in serverHistory.entries) {
        final year = entry.key;
        final serverYearData = entry.value;

        if (history.containsKey(year)) {
          final localEleves = history[year]!.eleves;
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
              localEleve.id = serverEleve.id.isNotEmpty
                  ? serverEleve.id
                  : localEleve.id;
              localEleve.classe = serverEleve.classe;
              localEleve.section = serverEleve.section;
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

    currentYear = serverData['currentYear'] ?? currentYear;
    if (history.containsKey(currentYear)) {
      currentData = history[currentYear]!;
    }

    await _assignMissingIds();
  }
}