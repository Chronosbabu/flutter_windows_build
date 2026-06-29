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

  // Code de l'école utilisé pour parler au serveur central (identique à celui
  // utilisé pour backup/restore). Doit être renseigné par l'écran appelant
  // (ex: SchoolHomeScreen) à partir de AppState.schoolCode, AVANT toute
  // génération d'ID élève.
  String? schoolCode;

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre',
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
  ];

  FraisScolaires() : config = SchoolConfig(schoolName: "MAPENDO TCC");

  // ==================== GÉNÉRATION D'ID UNIQUE (côté serveur uniquement) ====================
  Future<String> generateUniqueStudentId(String nom, String schoolCodeForServer) async {
    if (schoolCodeForServer.isEmpty) {
      throw Exception("Code de l'école manquant. Définissez-le dans les Paramètres avant d'ajouter un élève.");
    }
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/generate_student_id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCodeForServer,
          'school_name': config.schoolName,
          'nom': nom,
          'year': currentYear,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['id'] as String;
      } else {
        throw Exception("Le serveur n'a pas pu générer l'ID élève.");
      }
    } on Exception catch (e) {
      if (e.toString().contains("Le serveur")) rethrow;
      throw Exception("Connexion internet requise pour créer un nouvel élève.");
    }
  }

  // ==================== GESTION DES CLASSES & SOUS-CLASSES ====================
  //
  // Numéros de classe (1ère, 2ème, ... 7ème, 8ème) : AUTOMATIQUES, déduits du
  // nom de la section (Maternelle / Primaire / Secondaire). On les calcule à
  // la volée et on les mémorise dans config.classesBySection pour qu'ils
  // restent stables (et modifiables plus tard si besoin).
  //
  // Sous-classes (A, B, C, ...) : MANUELLES, ajoutées par l'utilisateur pour
  // un numéro de classe précis d'une section précise.

  String _classeKey(String section, String classeNumero) => "$section|$classeNumero";

  /// Retourne les numéros de classe disponibles pour une section donnée.
  /// Les génère automatiquement (et les mémorise) la première fois.
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

  /// Permet d'ajouter manuellement un numéro de classe pour une section qui
  /// n'a pas été reconnue automatiquement (section personnalisée).
  Future<void> addClasseNumero(String section, String classeNumero) async {
    final trimmed = classeNumero.trim();
    if (trimmed.isEmpty) return;
    final list = config.classesBySection.putIfAbsent(section, () => []);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await saveData();
    }
  }

  /// Sous-classes existantes pour un numéro de classe précis d'une section.
  List<String> getSubClassesFor(String section, String classeNumero) {
    return config.subClassesByClasse[_classeKey(section, classeNumero)] ?? [];
  }

  /// Ajoute une sous-classe manuelle (ex: "A", "B") pour un numéro de classe
  /// donné. Sauvegardée immédiatement pour apparaître partout, partout où
  /// les classes sont utilisées (inscription, filtres, etc.).
  Future<void> addSubClasse(String section, String classeNumero, String subClasse) async {
    final trimmed = subClasse.trim();
    if (trimmed.isEmpty) return;
    final key = _classeKey(section, classeNumero);
    final list = config.subClassesByClasse.putIfAbsent(key, () => []);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await saveData();
    }
  }

  Future<void> removeSubClasse(String section, String classeNumero, String subClasse) async {
    final key = _classeKey(section, classeNumero);
    config.subClassesByClasse[key]?.remove(subClasse);
    await saveData();
  }

  /// Construit le nom final de classe à partir d'un numéro et d'une
  /// sous-classe optionnelle. Ex: ("7ème", "A") -> "7ème A". Si aucune
  /// sous-classe n'est choisie, on garde juste le numéro : "7ème".
  String buildFullClasseName(String classeNumero, String? subClasse) {
    if (subClasse == null || subClasse.trim().isEmpty) return classeNumero;
    return "$classeNumero ${subClasse.trim()}";
  }

  /// Extrait le numéro de classe ("7ème") à partir d'un nom de classe complet
  /// qui peut contenir une sous-classe ("7ème A" -> "7ème"). Utile partout où
  /// on doit retrouver le numéro à partir de la valeur stockée chez l'élève.
  String classeNumeroFromFullClasse(String classeComplete) {
    final trimmed = classeComplete.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.split(' ').first;
  }

  /// Extrait la sous-classe ("A") à partir d'un nom de classe complet
  /// ("7ème A" -> "A"). Retourne null s'il n'y a pas de sous-classe.
  String? subClasseFromFullClasse(String classeComplete) {
    final parts = classeComplete.trim().split(' ');
    if (parts.length > 1) {
      final rest = parts.sublist(1).join(' ').trim();
      return rest.isEmpty ? null : rest;
    }
    return null;
  }

  /// Liste complète des classes "affichables" pour une section, utile pour
  /// les filtres et dropdowns : pour chaque numéro, soit le numéro seul
  /// (s'il n'a pas de sous-classe), soit chaque combinaison numéro+sous-classe.
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

  /// Union de toutes les classes affichables, toutes sections confondues
  /// (utile pour un filtre "Toutes les sections").
  List<String> getAllDisplayClasses() {
    final result = <String>{};
    for (var section in config.sections) {
      result.addAll(getAllDisplayClassesForSection(section));
    }
    return result.toList();
  }

  // ==================== PASSATION VERS LA CLASSE / ANNÉE SUPÉRIEURE ====================
  //
  // Permet de déterminer le numéro de classe qui suit immédiatement un
  // numéro donné, au sein d'une même section, en se basant sur l'ordre de
  // la liste config.classesBySection (ex: "1ère" -> "2ème", ... "6ème" ->
  // null si c'est la dernière classe de la section).
  //
  // Retourne null si le numéro n'est pas trouvé OU s'il s'agit déjà de la
  // dernière classe de la section (dans ce cas, l'élève reste dans la même
  // classe lors de la passation : c'est l'appelant qui décide quoi faire).
  String? getNextClasseNumero(String section, String classeNumero) {
    final list = getClassesForSection(section);
    final idx = list.indexOf(classeNumero);
    if (idx == -1 || idx == list.length - 1) return null;
    return list[idx + 1];
  }

  /// Calcule, pour un élève donné, le nom de classe qu'il aurait dans
  /// l'année suivante s'il "monte" de classe. Si aucune classe supérieure
  /// n'existe (déjà la dernière classe de la section), retourne sa classe
  /// actuelle inchangée. La sous-classe (ex: "A") est conservée telle
  /// quelle.
  String computePromotedClasse(Eleve eleve) {
    final numero = classeNumeroFromFullClasse(eleve.classe);
    final subClasse = subClasseFromFullClasse(eleve.classe);
    final nextNumero = getNextClasseNumero(eleve.section, numero);
    if (nextNumero == null) return eleve.classe;
    return buildFullClasseName(nextNumero, subClasse);
  }

  /// ====================================================================
  /// PASSATION EN MASSE VERS UNE NOUVELLE ANNÉE SCOLAIRE
  /// ====================================================================
  ///
  /// Permet de copier en une seule fois une sélection d'élèves de l'année
  /// actuelle vers `targetYear` (créée si elle n'existe pas encore), sans
  /// rien supprimer ni modifier dans l'année actuelle.
  ///
  /// - `studentsToProcess` : la liste des élèves à examiner (en général
  ///   currentData.eleves au complet, pour ne dépendre d'aucun filtre
  ///   d'affichage).
  /// - `passToNextYear` : pour chaque élève (clé = eleve.id), true si
  ///   l'élève doit être copié dans la nouvelle année, false sinon
  ///   (= abandon, l'élève ne sera pas copié).
  /// - `monterClasse` : pour chaque élève (clé = eleve.id), true s'il doit
  ///   monter à la classe supérieure dans la nouvelle année, false s'il
  ///   doit redoubler (rester dans la même classe).
  /// - `targetYear` : le nom de l'année scolaire cible (doit déjà exister
  ///   dans les Paramètres, ou sera créée automatiquement si besoin).
  ///
  /// Chaque élève copié démarre dans la nouvelle année avec un historique
  /// de paiements totalement vide (`paid` et `transactions` réinitialisés),
  /// ce qui est normal : c'est une nouvelle année scolaire.
  ///
  /// Retourne un résumé {'promoted', 'abandoned', 'redoublants'} pour que
  /// l'écran appelant puisse afficher un message récapitulatif clair.
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
        if (promotedClasse == eleve.classe) {
          // Déjà à la dernière classe de la section : impossible de monter
          // davantage, l'élève reste dans la même classe.
          redoublants++;
        }
        newClasse = promotedClasse;
      } else {
        // L'utilisateur a explicitement décoché "Monter de classe" :
        // l'élève redouble, il garde la même classe.
        newClasse = eleve.classe;
        redoublants++;
      }

      if (existingIds.contains(eleve.id)) {
        // L'élève est déjà présent dans l'année cible (ex: appel répété de
        // la passation) : on met simplement à jour sa classe/section au
        // lieu de créer un doublon.
        final existing = targetData.eleves.firstWhere((e) => e.id == eleve.id);
        existing.classe = newClasse;
        existing.section = eleve.section;
      } else {
        final newEleve = Eleve(
          id: eleve.id,
          nom: eleve.nom,
          postNom: eleve.postNom,
          prenom: eleve.prenom,
          classe: newClasse,
          section: eleve.section,
        );
        targetData.eleves.add(newEleve);
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

  // ==================== FILTRES POUR LISTE ET PDF ====================
  List<Eleve> getStudentsBySection(String section) {
    return currentData.eleves.where((e) => e.section == section).toList();
  }

  List<Eleve> getStudentsByClass(String classe) {
    return currentData.eleves.where((e) => e.classe == classe).toList();
  }

  List<Eleve> getStudentsBySectionAndClass(String? section, String? classe) {
    return currentData.eleves.where((e) {
      final matchSection = section == null || e.section == section;
      final matchClass = classe == null || e.classe == classe;
      return matchSection && matchClass;
    }).toList();
  }

  // ==================== CALCULS ====================
  //
  // Montant requis pour un mois donné, pour une section et — désormais — pour
  // une classe précise. Priorité de résolution (du plus spécifique au plus
  // général) :
  //   1. Exception mensuelle définie pour CETTE classe précise
  //   2. Frais fixe défini pour CETTE classe précise
  //   3. Exception mensuelle définie pour toute la SECTION
  //   4. Frais fixe défini pour toute la SECTION
  //   5. Frais par défaut (35000)
  //
  // Le paramètre `classe` est optionnel pour ne rien casser dans le code
  // existant qui n'appelait cette méthode qu'avec (mois, section).
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
    return months.fold(0.0, (sum, m) => sum + currentData.eleves.fold(0.0, (s, e) => s + (e.paid[m] ?? 0)));
  }

  /// Total collecté pour le mois calendaire en cours, toutes sections et
  /// toutes classes confondues (sans tenir compte d'un éventuel filtre de
  /// rapport). Utilisé pour afficher un récapitulatif global dans les PDF.
  double getCurrentMonthTotalCollected() {
    final now = DateTime.now();
    if (now.month - 1 < 0 || now.month - 1 >= months.length) return 0.0;
    final currentMonthName = months[now.month - 1];
    return currentData.eleves.fold(0.0, (sum, e) => sum + (e.paid[currentMonthName] ?? 0));
  }

  List<Eleve> getPaidStudentsToday() {
    String today = DateTime.now().toString().split(' ')[0];
    return currentData.eleves.where((eleve) =>
        eleve.transactions.any((t) => t['date'] == today)
    ).toList();
  }

  List<Eleve> getPaidStudentsThisMonth() {
    String currentMonthName = months[DateTime.now().month - 1];
    return currentData.eleves.where((eleve) =>
    eleve.paid.containsKey(currentMonthName) && eleve.paid[currentMonthName]! > 0
    ).toList();
  }

  // Calcul répartition par administration, pour un montant donné (ex: le
  // total d'un rapport filtré, ou le total payé par UN seul élève).
  Map<String, double> calculateAdminDistribution(double totalAmount) {
    Map<String, double> distribution = {};
    for (var admin in config.administrations) {
      distribution[admin.nom] = totalAmount * (admin.pourcentage / 100);
    }
    return distribution;
  }

  // ==================== GÉNÉRATION PDF AMÉLIORÉE ====================
  //
  // Chaque PDF généré contient désormais :
  //   - La date de génération (déjà présente avant).
  //   - Pour CHAQUE élève listé, une colonne par administration montrant
  //     la part de CET élève qui revient à cette administration (montant
  //     payé par l'élève x pourcentage de l'administration). Ex: si un
  //     élève a payé 35000 FC et que "Enseignants" a 70%, sa colonne
  //     "Enseignants (70%)" affichera 24500 FC.
  //   - Le récapitulatif global de répartition par administration pour
  //     l'ensemble du rapport (déjà présent avant, conservé).
  //   - NOUVEAU : le total collecté ce mois-ci pour TOUTE l'école (toutes
  //     sections/classes confondues, sans filtre), et le total collecté
  //     depuis le début de l'année scolaire pour TOUTE l'école. Ces deux
  //     totaux globaux permettent de toujours savoir où en est l'école,
  //     même si le rapport lui-même est filtré par section/classe.
  Future<void> generatePdf({
    required String filename,
    required String reportType,
    String? sectionFilter,
    String? classFilter,
  }) async {
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

    // Appliquer les filtres
    if (sectionFilter != null) {
      students = students.where((e) => e.section == sectionFilter).toList();
      title += " - $sectionFilter";
    }
    if (classFilter != null) {
      students = students.where((e) => e.classe == classFilter).toList();
      title += " - $classFilter";
    }

    double total = students.fold(0.0, (sum, e) => sum + getStudentTotalPaid(e));
    final adminDistribution = calculateAdminDistribution(total);

    // Totaux globaux (toute l'école, sans filtre) : permettent de toujours
    // situer ce rapport par rapport à la situation financière complète.
    final double totalMoisEcole = getCurrentMonthTotalCollected();
    final double totalAnneeEcole = getYearTotalCollected();
    final String currentMonthName = (DateTime.now().month - 1 >= 0 && DateTime.now().month - 1 < months.length)
        ? months[DateTime.now().month - 1]
        : "Mois en cours";

    // En-têtes du tableau : colonnes fixes + une colonne par administration
    // (montant que CETTE administration touche sur le paiement de CET
    // élève précisément).
    final List<String> headers = [
      'ID',
      'Nom Complet',
      'Section',
      'Classe',
      'Montant Payé (FC)',
      ...config.administrations.map((a) => '${a.nom} (${a.pourcentage.toStringAsFixed(0)}%)'),
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
          pw.Text(title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text('${config.schoolName} - $currentYear'),
          pw.Text('Date: ${DateTime.now().toString().split(" ")[0]}'),
          pw.SizedBox(height: 20),

          pw.Text("Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
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

          pw.Text("LISTE DES ÉLÈVES", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            "Pour chaque élève, le montant déjà payé est réparti par "
                "administration selon son pourcentage.",
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
          ),

          pw.SizedBox(height: 30),
          pw.Text("RÉPARTITION GLOBALE PAR ADMINISTRATION (CE RAPPORT)",
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          ...adminDistribution.entries.map((entry) =>
              pw.Text(
                "${entry.key} : ${entry.value.toStringAsFixed(0)} FC "
                    "(${config.administrations.firstWhere((a) => a.nom == entry.key).pourcentage.toStringAsFixed(0)}% "
                    "du total de ${total.toStringAsFixed(0)} FC)",
              )
          ),
        ],
      ),
    );

    try {
      final bytes = await pdf.save();
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        final fileName = '${filename}_${reportType}_${DateTime.now().toString().split(' ')[0]}.pdf';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
      } else {
        final saveLocation = await getSaveLocation(
          suggestedName: '${filename}_${reportType}.pdf',
          acceptedTypeGroups: [XTypeGroup(label: 'PDF', extensions: ['pdf'])],
        );
        if (saveLocation != null) {
          final file = File(saveLocation.path);
          await file.writeAsBytes(bytes);
          await OpenFile.open(file.path);
        }
      }
    } catch (e) {
      print("❌ Erreur PDF: $e");
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
                (key, value) => MapEntry(key, SchoolYearData.fromJson(value)),
          );
        }

        if (history.containsKey(currentYear)) {
          currentData = history[currentYear]!;
        } else {
          currentData = SchoolYearData(eleves: []);
          history[currentYear] = currentData;
        }

        await _assignMissingIds();
      } catch (e) {
        print("Erreur de chargement : $e");
        _initDefaultData();
      }
    } else {
      _initDefaultData();
    }
  }

  // Best-effort : ne corrige les IDs manquants/legacy que si une connexion au
  // serveur est disponible. Si la première tentative échoue (hors-ligne), on
  // arrête immédiatement au lieu de générer des IDs locaux.
  Future<void> _assignMissingIds() async {
    if (schoolCode == null || schoolCode!.isEmpty) return;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.id.isEmpty || eleve.id == "N/A") {
          try {
            eleve.id = await generateUniqueStudentId(eleve.nom, schoolCode!);
          } catch (e) {
            return;
          }
        }
      }
    }
  }

  void _initDefaultData() {
    currentData = SchoolYearData(eleves: []);
    history[currentYear] = currentData;
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
      double required = getRequiredForMonth(currentMonth, eleve.section, eleve.classe);
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

  double getStudentTotalPaid(Eleve eleve) => eleve.paid.values.fold(0.0, (sum, p) => sum + p);

  double getStudentPending(Eleve eleve) {
    return months.fold(0.0, (sum, m) => sum + (getRequiredForMonth(m, eleve.section, eleve.classe) - (eleve.paid[m] ?? 0)));
  }

  // ==================== BACKUP & RESTORE ====================
  Future<bool> backupToServer(String schoolCode, String password) async {
    try {
      this.schoolCode = schoolCode;
      final data = {
        'config': config.toJson(),
        'currentYear': currentYear,
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

      return response.statusCode == 200;
    } catch (e) {
      print("❌ ERREUR BACKUP: $e");
      return false;
    }
  }

  Future<bool> restoreFromServer(String schoolCode, String password) async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/restore?school_code=$schoolCode'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['backup_password'] != null && data['backup_password'] != password) {
          return false;
        }
        this.schoolCode = schoolCode;
        await _mergeRestoredData(data);
        await saveData();
        return true;
      }
      return false;
    } catch (e) {
      print("❌ ERREUR RESTORE: $e");
      return false;
    }
  }

  // ==================== FUSION DES DONNÉES SERVEUR ====================
  //
  // Le serveur est considéré comme la source de vérité après une
  // validation. Si l'élève existe déjà localement, on met à jour SES CHAMPS
  // (paid, transactions, classe, section, id, etc.) avec les valeurs reçues
  // du serveur, au lieu de l'ignorer. S'il est nouveau, on l'ajoute.
  Future<void> _mergeRestoredData(Map<String, dynamic> serverData) async {
    config = SchoolConfig.fromJson(serverData['config'] ?? {});

    if (serverData['history'] != null) {
      final serverHistory = (serverData['history'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(key, SchoolYearData.fromJson(value)),
      );

      for (var entry in serverHistory.entries) {
        final year = entry.key;
        final serverYearData = entry.value;

        if (history.containsKey(year)) {
          final localEleves = history[year]!.eleves;

          // Index des élèves locaux par clé "nom_postnom_prenom"
          final existingByKey = <String, Eleve>{};
          for (var e in localEleves) {
            final key = "${e.nom.trim().toLowerCase()}_${e.postNom.trim().toLowerCase()}_${e.prenom.trim().toLowerCase()}";
            existingByKey[key] = e;
          }

          for (var serverEleve in serverYearData.eleves) {
            final key = "${serverEleve.nom.trim().toLowerCase()}_${serverEleve.postNom.trim().toLowerCase()}_${serverEleve.prenom.trim().toLowerCase()}";

            if (existingByKey.containsKey(key)) {
              // L'élève existe déjà localement : on met à jour ses données
              // avec celles, à jour, du serveur (source de vérité).
              final localEleve = existingByKey[key]!;

              localEleve.id = serverEleve.id.isNotEmpty ? serverEleve.id : localEleve.id;
              localEleve.classe = serverEleve.classe;
              localEleve.section = serverEleve.section;

              localEleve.paid
                ..clear()
                ..addAll(serverEleve.paid);

              localEleve.transactions
                ..clear()
                ..addAll(serverEleve.transactions);
            } else {
              // Élève totalement nouveau (créé côté serveur, pas encore vu en local)
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