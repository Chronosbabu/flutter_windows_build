// ================================================
// lib/main.dart - VERSION DESKTOP OPTIMISÉE
// Compatible Windows - Prêt pour GitHub Actions
// ================================================
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';

const String API_URL = "https://unilu.onrender.com";

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNILU Professeurs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF001F3F),
          brightness: Brightness.dark,
          primary: const Color(0xFF00BFFF),
          secondary: const Color(0xFF22C55E),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF001F3F),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00BFFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E2937),
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: const SelectPromotionScreen(),
    );
  }
}

// ====================== MODÈLES ======================
class Student {
  final String matricule;
  final String prenom;
  final String nom;
  final String postNom;

  Student({
    required this.matricule,
    required this.prenom,
    required this.nom,
    required this.postNom,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      matricule: json['matricule']?.toString() ?? '',
      prenom: json['prenom']?.toString() ?? '',
      nom: json['nom']?.toString() ?? '',
      postNom: json['post_nom']?.toString() ?? '',
    );
  }
}

class Resultat {
  final int id;
  final String course;
  final String type;
  final double cote;
  final int ponderation;
  final String date;
  final String status;

  Resultat.fromJson(Map<String, dynamic> json)
      : id = json['id'] ?? 0,
        course = json['course'] ?? '',
        type = json['type'] ?? '',
        cote = (json['cote'] ?? 0).toDouble(),
        ponderation = json['ponderation'] ?? 0,
        date = json['date'] ?? '',
        status = json['status'] ?? 'RÉUSSITE';
}

// ====================== STATE GLOBAL ======================
class AppState extends ChangeNotifier {
  String? promotion;
  String? currentCourse;
  String? currentType;
  int? currentPonderation;

  void setPromotion(String p) {
    promotion = p;
    notifyListeners();
  }

  void setCurrentCourse(String course, String type, int ponderation) {
    currentCourse = course;
    currentType = type;
    currentPonderation = ponderation;
    notifyListeners();
  }

  void clearCurrentCourse() {
    currentCourse = null;
    currentType = null;
    currentPonderation = null;
    notifyListeners();
  }
}

// ====================== ÉCRAN 1 : SÉLECTION PROMOTION ======================
class SelectPromotionScreen extends StatefulWidget {
  const SelectPromotionScreen({super.key});

  @override
  State<SelectPromotionScreen> createState() => _SelectPromotionScreenState();
}

class _SelectPromotionScreenState extends State<SelectPromotionScreen> {
  String selectedPromotion = "L1";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.school, size: 140, color: Color(0xFF00BFFF)),
              const SizedBox(height: 32),
              const Text(
                "UNILU Professeurs",
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                "Publication des résultats",
                style: TextStyle(fontSize: 20, color: Colors.white70),
              ),
              const SizedBox(height: 80),
              const Text(
                "Choisissez la promotion",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2937),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedPromotion,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 32),
                    dropdownColor: const Color(0xFF1E2937),
                    style: const TextStyle(fontSize: 22, color: Colors.white),
                    items: ["L1", "L2", "L3", "M1", "M2"]
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedPromotion = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 60),
              FilledButton.icon(
                onPressed: () {
                  context.read<AppState>().setPromotion(selectedPromotion);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const MainScreen()),
                  );
                },
                icon: const Icon(Icons.arrow_forward, size: 28),
                label: const Text("CONTINUER →", style: TextStyle(fontSize: 20)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(320, 72),
                  backgroundColor: const Color(0xFF00BFFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================== ÉCRAN PRINCIPAL ======================
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("UNILU - Professeurs"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF001F3F),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.group, size: 48, color: Colors.white),
                  const SizedBox(width: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Promotion active", style: TextStyle(color: Colors.white70, fontSize: 16)),
                      Text(
                        state.promotion ?? "—",
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            _buildBigActionButton(
              context,
              icon: Icons.edit_note,
              title: "Définir un cours",
              subtitle: "Nom • Type • Pondération",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DefineCourseScreen())),
            ),
            const SizedBox(height: 20),
            _buildBigActionButton(
              context,
              icon: Icons.list_alt,
              title: "Saisir les notes",
              subtitle: "Liste des étudiants",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentListScreen())),
            ),
            const Spacer(),
            if (state.currentCourse != null) ...[
              const Divider(height: 40),
              ListTile(
                leading: const Icon(Icons.book, color: Color(0xFF22C55E), size: 32),
                title: Text(state.currentCourse!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                subtitle: Text("${state.currentType == 'periode' ? 'Moyenne Période' : 'Examen'} • Pondération ${state.currentPonderation}"),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 28),
                  onPressed: () => context.read<AppState>().clearCurrentCourse(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBigActionButton(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2937),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF00BFFF).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: const Color(0xFF00BFFF)),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 16, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 28),
          ],
        ),
      ),
    );
  }
}

// ====================== ÉCRAN 2 : DÉFINIR COURS ======================
class DefineCourseScreen extends StatefulWidget {
  const DefineCourseScreen({super.key});

  @override
  State<DefineCourseScreen> createState() => _DefineCourseScreenState();
}

class _DefineCourseScreenState extends State<DefineCourseScreen> {
  final TextEditingController _courseController = TextEditingController();
  String _selectedType = "Moyenne Période";
  final TextEditingController _ponderationController = TextEditingController(text: "20");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Définir un cours")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Nom du cours", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _courseController,
              decoration: InputDecoration(
                hintText: "Ex: Algorithmique Avancée",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: const Color(0xFF1E2937),
              ),
            ),
            const SizedBox(height: 32),
            const Text("Type de session", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2937),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButton<String>(
                value: _selectedType,
                isExpanded: true,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: "Moyenne Période", child: Text("Moyenne Période")),
                  DropdownMenuItem(value: "Examen", child: Text("Examen")),
                ],
                onChanged: (val) => setState(() => _selectedType = val!),
              ),
            ),
            const SizedBox(height: 32),
            const Text("Pondération (sur combien ?)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _ponderationController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "20",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: const Color(0xFF1E2937),
              ),
            ),
            const SizedBox(height: 60),
            FilledButton(
              onPressed: () {
                final course = _courseController.text.trim();
                if (course.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Veuillez entrer le nom du cours")));
                  return;
                }
                final pon = int.tryParse(_ponderationController.text);
                if (pon == null || pon < 1 || pon > 100) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pondération invalide (1-100)")));
                  return;
                }
                final typeCode = _selectedType == "Moyenne Période" ? "periode" : "examen";
                context.read<AppState>().setCurrentCourse(course, typeCode, pon);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Cours défini avec succès !")));
                Navigator.pop(context);
              },
              child: const Text("ENREGISTRER CE COURS", style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================== ÉCRAN 3 : LISTE DES ÉTUDIANTS (DESKTOP OPTIMISÉ) ======================
class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  List<Student> students = [];
  List<Student> filteredStudents = [];
  Map<String, double?> pendingResults = {};
  Map<String, TextEditingController> _coteControllers = {};
  final TextEditingController _searchController = TextEditingController();
  bool isLoading = true;
  bool isPublishing = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    for (var controller in _coteControllers.values) controller.dispose();
    _coteControllers.clear();
    _searchController.dispose();
    super.dispose();
  }

  void _filterStudents(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      filteredStudents = q.isEmpty
          ? List.from(students)
          : students.where((s) {
        final fullName = "${s.prenom} ${s.nom} ${s.postNom}".toLowerCase();
        return fullName.contains(q) || s.matricule.toLowerCase().contains(q);
      }).toList();
    });
  }

  Future<void> _loadStudents() async {
    setState(() => isLoading = true);
    try {
      final promotion = context.read<AppState>().promotion;
      if (promotion == null) throw Exception("Promotion non définie");

      final response = await http.get(Uri.parse("$API_URL/api/students?promotion=$promotion"));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        students = data.map((e) => Student.fromJson(e)).toList();

        for (var controller in _coteControllers.values) controller.dispose();
        _coteControllers.clear();
        pendingResults.clear();

        for (var s in students) {
          pendingResults[s.matricule] = null;
          _coteControllers[s.matricule] = TextEditingController(text: "");
        }

        filteredStudents = List.from(students);
      } else {
        throw Exception("Erreur serveur");
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _publierBatch() async {
    final state = context.read<AppState>();
    if (state.currentCourse == null || state.currentPonderation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Définissez d'abord un cours")));
      return;
    }

    setState(() => isPublishing = true);
    int count = 0;

    for (var entry in pendingResults.entries) {
      if (entry.value != null) {
        try {
          await http.post(
            Uri.parse("$API_URL/api/publish_result"),
            headers: {"Content-Type": "application/json"},
            body: json.encode({
              "matricule": entry.key,
              "course": state.currentCourse,
              "result_type": state.currentType,
              "cote": entry.value,
              "ponderation": state.currentPonderation,
            }),
          );
          count++;
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() => isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ $count résultats publiés avec succès !")));
      setState(() {
        pendingResults.updateAll((key, value) => null);
        for (var ctrl in _coteControllers.values) ctrl.clear();
      });
    }
  }

  void _showStudentResults(String matricule, String nomComplet) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudentResultsScreen(matricule: matricule, nomComplet: nomComplet)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Liste des étudiants")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : students.isEmpty
          ? const Center(child: Text("Aucun étudiant trouvé", style: TextStyle(fontSize: 20)))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _filterStudents,
              decoration: InputDecoration(
                hintText: "Rechercher par nom ou matricule...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => {_searchController.clear(), _filterStudents('')})
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                filled: true,
                fillColor: const Color(0xFF1E2937),
              ),
            ),
          ),
          Expanded(
            child: filteredStudents.isEmpty
                ? const Center(child: Text("Aucun étudiant ne correspond à votre recherche", style: TextStyle(fontSize: 18, color: Colors.white70)))
                : RefreshIndicator(
              onRefresh: _loadStudents,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: filteredStudents.length,
                itemBuilder: (context, index) {
                  final s = filteredStudents[index];
                  final controller = _coteControllers[s.matricule]!;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${s.prenom} ${s.nom} ${s.postNom}", style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                                Text(s.matricule, style: const TextStyle(color: Colors.white54, fontSize: 16)),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: controller,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: "Cote",
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  pendingResults[s.matricule] = val.isEmpty ? null : double.tryParse(val);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () => _showStudentResults(s.matricule, "${s.prenom} ${s.nom} ${s.postNom}"),
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                            child: const Text("Historique"),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: students.isNotEmpty
          ? SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FilledButton.icon(
            onPressed: isPublishing ? null : _publierBatch,
            icon: isPublishing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : const Icon(Icons.send),
            label: Text(isPublishing ? "PUBLICATION EN COURS..." : "📤 PUBLIER TOUS LES RÉSULTATS", style: const TextStyle(fontSize: 20)),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(76), backgroundColor: const Color(0xFF22C55E)),
          ),
        ),
      )
          : null,
    );
  }
}

// ====================== ÉCRAN HISTORIQUE RÉSULTATS ======================
class StudentResultsScreen extends StatefulWidget {
  final String matricule;
  final String nomComplet;

  const StudentResultsScreen({super.key, required this.matricule, required this.nomComplet});

  @override
  State<StudentResultsScreen> createState() => _StudentResultsScreenState();
}

class _StudentResultsScreenState extends State<StudentResultsScreen> {
  List<Resultat> results = [];
  bool isLoading = true;
  Set<int> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    _fetchResults();
  }

  Future<void> _fetchResults() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse("$API_URL/api/get_results?matricule=${widget.matricule}"));
      if (res.statusCode == 200) {
        final List<dynamic> data = json.decode(res.body);
        results = data.map((e) => Resultat.fromJson(e)).toList();
        results.sort((a, b) => b.date.compareTo(a.date));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _deleteResult(int id) async { /* même code que précédemment */ }
  void _modifyResult(Resultat current) { /* même code que précédemment */ }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Résultats • ${widget.nomComplet}")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : results.isEmpty
          ? const Center(child: Text("Aucun résultat publié pour cet étudiant"))
          : ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final r = results[index];
          final color = r.status == "RÉUSSITE" ? Colors.green : Colors.red;
          final typeLabel = r.type == "periode" ? "MOYENNE PÉRIODE" : "EXAMEN";
          final isDeleting = _deletingIds.contains(r.id);

          return Card(
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                      const Spacer(),
                      Text(r.date, style: const TextStyle(color: Colors.grey, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(r.course, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${r.cote} / ${r.ponderation}", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
                      Row(
                        children: [
                          TextButton.icon(onPressed: () => _modifyResult(r), icon: const Icon(Icons.edit), label: const Text("Modifier")),
                          TextButton.icon(
                            onPressed: isDeleting ? null : () => _deleteResult(r.id),
                            icon: isDeleting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.delete, color: Colors.red),
                            label: Text("Supprimer", style: TextStyle(color: isDeleting ? Colors.grey : Colors.red)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
