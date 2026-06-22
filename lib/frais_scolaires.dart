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

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre', 'Janvier',
    'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
  ];

  FraisScolaires() : config = SchoolConfig(schoolName: "MAPENDO TCC");

  // ==================== GÉNÉRATION D'ID UNIQUE ULTRA SÉCURISÉE ====================
  String generateUniqueStudentId(String nom, String schoolName) {
    String yearShort = currentYear.length >= 2
        ? currentYear.substring(currentYear.length - 2)
        : "26";

    String schoolLetter = (schoolName.isNotEmpty && schoolName.length >= 1)
        ? schoolName[0].toUpperCase()
        : 'B';

    String namePrefix = "XX";
    String trimmedNom = nom.trim();
    if (trimmedNom.isNotEmpty) {
      namePrefix = trimmedNom.length >= 2
          ? trimmedNom.substring(0, 2).toUpperCase()
          : trimmedNom.toUpperCase();
    }

    String baseId = "$namePrefix$yearShort$schoolLetter";

    int counter = 1;
    String candidateId = "$baseId$counter";

    while (_idExists(candidateId)) {
      counter++;
      candidateId = "$baseId$counter";
    }

    return candidateId;
  }

  bool _idExists(String id) {
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.id == id) return true;
      }
    }
    return false;
  }

  double getRequiredForMonth(String mois, String section) {
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

  List<Eleve> getPaidStudentsToday() {
    String today = DateTime.now().toString().split(' ')[0];
    return currentData.eleves.where((eleve) =>
        eleve.transactions.any((t) => t['date'] == today)).toList();
  }

  List<Eleve> getPaidStudentsThisMonth() {
    String currentMonthName = months[DateTime.now().month - 1];
    return currentData.eleves.where((eleve) =>
    eleve.paid.containsKey(currentMonthName) && eleve.paid[currentMonthName]! > 0).toList();
  }

  // ==================== GÉNÉRATION PDF ====================
  Future<void> generatePdf(String filename, String reportType) async {
    final pdf = pw.Document();
    List<Eleve> students = [];
    String title = "";
    double total = 0.0;

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

    total = students.fold(0.0, (sum, e) => sum + getStudentTotalPaid(e));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text('${config.schoolName} - $currentYear'),
          pw.Text('Date: ${DateTime.now().toString().split(" ")[0]}'),
          pw.SizedBox(height: 20),
          pw.Text("Total Collecté : ${total.toStringAsFixed(0)} FC",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 20),
          pw.Text("LISTE DES ÉLÈVES AYANT PAYÉ", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: ['ID', 'Nom Complet', 'Section', 'Classe', 'Montant Payé (FC)'],
            data: students.map((e) => [
              e.id.isNotEmpty ? e.id : "N/A",
              "${e.nom} ${e.postNom} ${e.prenom}",
              e.section,
              e.classe,
              getStudentTotalPaid(e).toStringAsFixed(0)
            ]).toList(),
          ),
        ],
      ),
    );

    try {
      final bytes = await pdf.save();
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        final fileName = '${filename}_${reportType}_$currentYear.pdf';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
      } else {
        final saveLocation = await getSaveLocation(
          suggestedName: '${filename}_${reportType}_$currentYear.pdf',
          acceptedTypeGroups: [XTypeGroup(label: 'PDF', extensions: ['pdf'])],
        );
        if (saveLocation != null) {
          final file = File(saveLocation.path);
          await file.writeAsBytes(bytes);
          await OpenFile.open(file.path);
        }
      }
    } catch (e) {
      print("❌ Erreur lors de la génération PDF: $e");
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
      } catch (e) {
        print("Erreur de chargement des données : $e");
        _initDefaultData();
      }
    } else {
      _initDefaultData();
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
      double required = getRequiredForMonth(currentMonth, eleve.section);
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
    return months.fold(0.0, (sum, m) => sum + (getRequiredForMonth(m, eleve.section) - (eleve.paid[m] ?? 0)));
  }

  // ==================== BACKUP & RESTORE ====================
  Future<bool> backupToServer(String schoolCode, String password) async {
    try {
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
          final existing = <String, Eleve>{};
          for (var e in localEleves) {
            final key = "${e.nom.trim().toLowerCase()}_${e.postNom.trim().toLowerCase()}_${e.prenom.trim().toLowerCase()}";
            existing[key] = e;
          }
          for (var serverEleve in serverYearData.eleves) {
            final key = "${serverEleve.nom.trim().toLowerCase()}_${serverEleve.postNom.trim().toLowerCase()}_${serverEleve.prenom.trim().toLowerCase()}";
            if (!existing.containsKey(key)) {
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
  }
}
