import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MyApp(),
    ),
  );
}

class AppState extends ChangeNotifier {
  bool isDarkMode = false;
  AppState() {
    _loadTheme();
  }
  Future _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode = prefs.getBool('isDarkMode') ?? false;
    notifyListeners();
  }
  Future toggleTheme() async {
    isDarkMode = !isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return MaterialApp(
      title: 'Gestion des Frais Scolaires',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo[700],
          secondary: Colors.teal,
          surface: Colors.grey[50],
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            elevation: 4,
          ),
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo[700],
          secondary: Colors.teal,
          surface: Colors.grey[900],
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo[700],
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            elevation: 4,
          ),
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          color: Colors.grey[800],
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[800],
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        scaffoldBackgroundColor: Colors.grey[900],
      ),
      themeMode: appState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}

class Eleve {
  String nom;
  String postNom;
  String prenom;
  String classe;
  Map<String, double> paid = {};
  Eleve({
    required this.nom,
    required this.postNom,
    required this.prenom,
    required this.classe,
  });
  Map<String, dynamic> toJson() => {
    'nom': nom,
    'postNom': postNom,
    'prenom': prenom,
    'classe': classe,
    'paid': paid,
  };
  factory Eleve.fromJson(Map<String, dynamic> json) {
    return Eleve(
      nom: json['nom'],
      postNom: json['postNom'],
      prenom: json['prenom'],
      classe: json['classe'],
    )..paid = Map<String, double>.from(json['paid'] ?? {});
  }
}

class SchoolYearData {
  Map<String, double> manualFrais;
  List<Eleve> eleves;
  double defaultMonthly;
  Map<String, double> monthExceptions;
  SchoolYearData({
    required this.manualFrais,
    required this.eleves,
    required this.defaultMonthly,
    required this.monthExceptions,
  });
  Map<String, dynamic> toJson() => {
    'manualFrais': manualFrais,
    'eleves': eleves.map((e) => e.toJson()).toList(),
    'defaultMonthly': defaultMonthly,
    'monthExceptions': monthExceptions,
  };
  factory SchoolYearData.fromJson(Map<String, dynamic> json) {
    return SchoolYearData(
      manualFrais: Map<String, double>.from(json['manualFrais'] ?? {}),
      eleves: (json['eleves'] as List? ?? []).map((e) => Eleve.fromJson(e)).toList(),
      defaultMonthly: json['defaultMonthly'] ?? 0.0,
      monthExceptions: Map<String, double>.from(json['monthExceptions'] ?? {}),
    );
  }
}

class FraisScolaires {
  SchoolYearData currentData = SchoolYearData(
    manualFrais: {},
    eleves: [],
    defaultMonthly: 0.0,
    monthExceptions: {},
  );
  String currentYear = '2023-2024'; // Default year
  Map<String, SchoolYearData> history = {};
  final List<String> months = [
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin'
  ];
  Future loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedData = prefs.getString('encrypted_data');
    if (encryptedData != null) {
      final decrypted = _decrypt(encryptedData);
      final data = json.decode(decrypted);
      currentData = SchoolYearData.fromJson(data['currentData'] ?? {});
      currentYear = data['currentYear'] ?? '2023-2024';
      history = Map.fromEntries(
        (data['history'] as Map? ?? {}).entries.map(
              (entry) => MapEntry(entry.key, SchoolYearData.fromJson(entry.value)),
        ),
      );
    }
  }
  Future saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'currentData': currentData.toJson(),
      'currentYear': currentYear,
      'history': history.map((key, value) => MapEntry(key, value.toJson())),
    };
    final jsonData = json.encode(data);
    final encrypted = _encrypt(jsonData);
    await prefs.setString('encrypted_data', encrypted);
  }
  void enregistrerFrais(String mois, double montant) {
    currentData.manualFrais[mois] = (currentData.manualFrais[mois] ?? 0) + montant;
  }
  double getRequiredForMonth(String mois) {
    return currentData.monthExceptions[mois] ?? currentData.defaultMonthly;
  }
  double getTotalForMonth(String mois) {
    double studentTotal = currentData.eleves.fold(0, (sum, e) => sum + (e.paid[mois] ?? 0));
    return (currentData.manualFrais[mois] ?? 0) + studentTotal;
  }
  Map<String, double> calculerRepartitions(String mois) {
    final total = getTotalForMonth(mois);
    return {
      '30%': total * 0.3,
      '70%': total * 0.7,
      '7%': total * 0.07,
    };
  }
  void handlePayment(Eleve eleve, String mois, double payment) {
    int monthIndex = months.indexOf(mois);
    if (monthIndex == -1) return;
    String currentMonth = mois;
    double remaining = payment;
    while (remaining > 0 && monthIndex < months.length) {
      double required = getRequiredForMonth(currentMonth);
      double alreadyPaid = eleve.paid[currentMonth] ?? 0;
      double needed = required - alreadyPaid;
      if (needed > 0) {
        double toAdd = remaining > needed ? needed : remaining;
        eleve.paid[currentMonth] = alreadyPaid + toAdd;
        remaining -= toAdd;
      }
      monthIndex++;
      if (monthIndex < months.length) {
        currentMonth = months[monthIndex];
      }
    }
  }
  Future resetForNewYear(String newYear) async {
    history[currentYear] = SchoolYearData(
      manualFrais: Map.from(currentData.manualFrais),
      eleves: List.from(currentData.eleves),
      defaultMonthly: currentData.defaultMonthly,
      monthExceptions: Map.from(currentData.monthExceptions),
    );
    currentData = SchoolYearData(
      manualFrais: {},
      eleves: [],
      defaultMonthly: 0.0,
      monthExceptions: {},
    );
    currentYear = newYear;
    await saveData();
  }
  String _encrypt(String text) {
    final key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1');
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(text, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }
  String _decrypt(String encryptedText) {
    final parts = encryptedText.split(':');
    final iv = encrypt.IV.fromBase64(parts[0]);
    final encryptedPart = parts[1];
    final key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1');
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decrypt64(encryptedPart, iv: iv);
  }
  double getTotalRequired() {
    return months.fold(0.0, (sum, mois) => sum + getRequiredForMonth(mois));
  }
  double getStudentTotalPaid(Eleve eleve) {
    return eleve.paid.values.fold(0.0, (sum, paid) => sum + paid);
  }
  double getStudentPending(Eleve eleve) {
    return getTotalRequired() - getStudentTotalPaid(eleve);
  }
  double getYearTotalCollected() {
    return months.fold(0.0, (sum, mois) => sum + getTotalForMonth(mois));
  }
  double getYearTotalPending() {
    return currentData.eleves.fold(0.0, (sum, e) => sum + getStudentPending(e));
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FraisScolaires fraisScolaires = FraisScolaires();
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  Future _loadData() async {
    await fraisScolaires.loadData();
    setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gestion des Frais Scolaires - ${fraisScolaires.currentYear}'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(fraisScolaires: fraisScolaires),
                ),
              ).then((_) => setState(() {}));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tableau de Bord', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text('Total Élèves: ${fraisScolaires.currentData.eleves.length}'),
                      Text('Total Collecté: ${fraisScolaires.getYearTotalCollected().toStringAsFixed(2)}'),
                      Text('Total En Attente: ${fraisScolaires.getYearTotalPending().toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                children: [
                  _buildActionCard(
                    icon: Icons.person_add,
                    label: 'Enregistrer un élève',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EnregistrerEleveScreen(fraisScolaires: fraisScolaires),
                        ),
                      ).then((_) => setState(() {}));
                    },
                  ),
                  _buildActionCard(
                    icon: Icons.payment,
                    label: 'Paiement élève',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PaiementEleveScreen(fraisScolaires: fraisScolaires),
                        ),
                      ).then((_) => setState(() {}));
                    },
                  ),
                  _buildActionCard(
                    icon: Icons.add_circle_outline,
                    label: 'Frais manuel',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EnregistrerScreen(fraisScolaires: fraisScolaires),
                        ),
                      ).then((_) => setState(() {}));
                    },
                  ),
                  _buildActionCard(
                    icon: Icons.bar_chart,
                    label: 'Répartitions',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AfficherScreen(fraisScolaires: fraisScolaires),
                        ),
                      );
                    },
                  ),
                  _buildActionCard(
                    icon: Icons.history,
                    label: 'Historique',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => HistoryScreen(fraisScolaires: fraisScolaires),
                        ),
                      );
                    },
                  ),
                  _buildActionCard(
                    icon: Icons.exit_to_app,
                    label: 'Quitter',
                    onTap: () => SystemNavigator.pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildActionCard({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 50, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class EnregistrerEleveScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  final Eleve? eleveToEdit;
  final int? editIndex;
  const EnregistrerEleveScreen({
    super.key,
    required this.fraisScolaires,
    this.eleveToEdit,
    this.editIndex,
  });
  @override
  State<EnregistrerEleveScreen> createState() => _EnregistrerEleveScreenState();
}

class _EnregistrerEleveScreenState extends State<EnregistrerEleveScreen> {
  late TextEditingController nomController;
  late TextEditingController postNomController;
  late TextEditingController prenomController;
  late TextEditingController classeController;
  @override
  void initState() {
    super.initState();
    nomController = TextEditingController(text: widget.eleveToEdit?.nom ?? '');
    postNomController = TextEditingController(text: widget.eleveToEdit?.postNom ?? '');
    prenomController = TextEditingController(text: widget.eleveToEdit?.prenom ?? '');
    classeController = TextEditingController(text: widget.eleveToEdit?.classe ?? '');
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eleveToEdit == null ? 'Enregistrer un Élève' : 'Modifier Élève'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: nomController,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: postNomController,
              decoration: const InputDecoration(labelText: 'Post-nom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: prenomController,
              decoration: const InputDecoration(labelText: 'Prénom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: classeController,
              decoration: const InputDecoration(labelText: 'Classe'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final nom = nomController.text.trim();
                final postNom = postNomController.text.trim();
                final prenom = prenomController.text.trim();
                final classe = classeController.text.trim();
                if (nom.isNotEmpty && postNom.isNotEmpty && prenom.isNotEmpty && classe.isNotEmpty) {
                  if (widget.eleveToEdit == null) {
                    widget.fraisScolaires.currentData.eleves.add(Eleve(
                      nom: nom,
                      postNom: postNom,
                      prenom: prenom,
                      classe: classe,
                    ));
                  } else if (widget.editIndex != null) {
                    widget.fraisScolaires.currentData.eleves[widget.editIndex!] = Eleve(
                      nom: nom,
                      postNom: postNom,
                      prenom: prenom,
                      classe: classe,
                    )..paid = widget.eleveToEdit!.paid;
                  }
                  await widget.fraisScolaires.saveData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(widget.eleveToEdit == null ? 'Élève enregistré!' : 'Élève modifié!')),
                  );
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Remplir tous les champs')),
                  );
                }
              },
              child: Text(widget.eleveToEdit == null ? 'Enregistrer' : 'Modifier'),
            ),
          ],
        ),
      ),
    );
  }
}

class PaiementEleveScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const PaiementEleveScreen({super.key, required this.fraisScolaires});
  @override
  State<PaiementEleveScreen> createState() => _PaiementEleveScreenState();
}

class _PaiementEleveScreenState extends State<PaiementEleveScreen> {
  final TextEditingController searchController = TextEditingController();
  List<Eleve> filteredEleves = [];
  String? selectedClass;
  List<String> classes = [];
  @override
  void initState() {
    super.initState();
    filteredEleves = widget.fraisScolaires.currentData.eleves;
    classes = widget.fraisScolaires.currentData.eleves.map((e) => e.classe).toSet().toList();
    searchController.addListener(_filterEleves);
  }
  void _filterEleves() {
    final query = searchController.text.toLowerCase();
    setState(() {
      filteredEleves = widget.fraisScolaires.currentData.eleves.where((eleve) {
        final fullName = '${eleve.nom} ${eleve.postNom} ${eleve.prenom}'.toLowerCase();
        final classMatch = selectedClass == null || eleve.classe == selectedClass;
        return fullName.contains(query) && classMatch;
      }).toList()
        ..sort((a, b) => '${a.nom} ${a.postNom} ${a.prenom}'.compareTo('${b.nom} ${b.postNom} ${b.prenom}'));
    });
  }
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Paiements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSetMonthlyDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.warning),
            tooltip: 'Exceptions',
            onPressed: () => _showSetExceptionsDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher par nom',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButton<String>(
                  hint: const Text('Filtrer par classe'),
                  value: selectedClass,
                  onChanged: (value) {
                    setState(() {
                      selectedClass = value;
                      _filterEleves();
                    });
                  },
                  items: classes.map((classe) {
                    return DropdownMenuItem(value: classe, child: Text(classe));
                  }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredEleves.length,
              itemBuilder: (context, index) {
                final eleve = filteredEleves[index];
                double totalPaid = widget.fraisScolaires.getStudentTotalPaid(eleve);
                double pending = widget.fraisScolaires.getStudentPending(eleve);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${eleve.nom} ${eleve.postNom} ${eleve.prenom} - ${eleve.classe}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EnregistrerEleveScreen(
                                      fraisScolaires: widget.fraisScolaires,
                                      eleveToEdit: eleve,
                                      editIndex: widget.fraisScolaires.currentData.eleves.indexOf(eleve),
                                    ),
                                  ),
                                ).then((_) => setState(() {}));
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _showDeleteConfirm(context, eleve),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text('Payé: $totalPaid | En attente: $pending'),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.fraisScolaires.months.length,
                            itemBuilder: (context, monthIndex) {
                              final mois = widget.fraisScolaires.months[monthIndex];
                              double required = widget.fraisScolaires.getRequiredForMonth(mois);
                              double paid = eleve.paid[mois] ?? 0;
                              bool isFullyPaid = paid >= required;
                              Color backgroundColor = isFullyPaid
                                  ? (isDark ? Colors.green[700]! : Colors.green[100]!)
                                  : (isDark ? Colors.red[700]! : Colors.red[100]!);
                              Color borderColor = isDark ? Colors.grey[600]! : Colors.grey[300]!;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: GestureDetector(
                                  onTap: isFullyPaid ? null : () => _showPaymentDialog(context, eleve, mois),
                                  child: Container(
                                    width: 120,
                                    decoration: BoxDecoration(
                                      color: backgroundColor,
                                      border: Border.all(color: borderColor),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(mois, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        Text('Requis: ${required.toStringAsFixed(0)}'),
                                        if (paid > 0) Text('Payé: ${paid.toStringAsFixed(0)}'),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  void _showDeleteConfirm(BuildContext context, Eleve eleve) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer Suppression'),
        content: const Text('Voulez-vous supprimer cet élève?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              widget.fraisScolaires.currentData.eleves.remove(eleve);
              await widget.fraisScolaires.saveData();
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
  void _showSetMonthlyDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.fraisScolaires.currentData.defaultMonthly.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Montant Mensuel Défaut'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Montant'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              final montant = double.tryParse(controller.text);
              if (montant != null) {
                widget.fraisScolaires.currentData.defaultMonthly = montant;
                await widget.fraisScolaires.saveData();
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
  void _showSetExceptionsDialog(BuildContext context) {
    String? selectedMonth;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exception pour Mois'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              hint: const Text('Mois'),
              value: selectedMonth,
              onChanged: (value) => selectedMonth = value,
              items: widget.fraisScolaires.months.map((mois) => DropdownMenuItem(value: mois, child: Text(mois))).toList(),
            ),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Montant'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              if (selectedMonth != null) {
                final montant = double.tryParse(controller.text);
                if (montant != null) {
                  widget.fraisScolaires.currentData.monthExceptions[selectedMonth!] = montant;
                  await widget.fraisScolaires.saveData();
                  setState(() {});
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
  void _showPaymentDialog(BuildContext context, Eleve eleve, String mois) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Payer pour $mois'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Montant'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              final montant = double.tryParse(controller.text);
              if (montant != null && montant > 0) {
                widget.fraisScolaires.handlePayment(eleve, mois, montant);
                await widget.fraisScolaires.saveData();
                setState(() {});
                Navigator.pop(context);
                _showReceiptDialog(context, eleve, mois, montant);
              }
            },
            child: const Text('Payer'),
          ),
        ],
      ),
    );
  }
  void _showReceiptDialog(BuildContext context, Eleve eleve, String mois, double montant) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reçu de Paiement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Élève: ${eleve.nom} ${eleve.prenom}'),
            Text('Mois: $mois'),
            Text('Montant: $montant'),
            Text('Date: ${DateTime.now().toString()}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}

class EnregistrerScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const EnregistrerScreen({super.key, required this.fraisScolaires});
  @override
  State<EnregistrerScreen> createState() => _EnregistrerScreenState();
}

class _EnregistrerScreenState extends State<EnregistrerScreen> {
  String? selectedMois;
  final TextEditingController montantController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Frais Manuel')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<String>(
              hint: const Text('Sélectionner Mois'),
              value: selectedMois,
              onChanged: (value) {
                setState(() {
                  selectedMois = value;
                });
              },
              items: widget.fraisScolaires.months.map((mois) {
                return DropdownMenuItem(value: mois, child: Text(mois));
              }).toList(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: montantController,
              decoration: const InputDecoration(labelText: 'Montant'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final mois = selectedMois;
                final montantStr = montantController.text.trim();
                if (mois != null && montantStr.isNotEmpty) {
                  final montant = double.tryParse(montantStr);
                  if (montant != null) {
                    widget.fraisScolaires.enregistrerFrais(mois, montant);
                    await widget.fraisScolaires.saveData();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Frais enregistré!')));
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Montant invalide')));
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remplir tous les champs')));
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class AfficherScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const AfficherScreen({super.key, required this.fraisScolaires});
  @override
  State<AfficherScreen> createState() => _AfficherScreenState();
}

class _AfficherScreenState extends State<AfficherScreen> {
  Map<String, Map<String, double>> allRepartitions = {};
  @override
  void initState() {
    super.initState();
    _computeAllRepartitions();
  }
  void _computeAllRepartitions() {
    setState(() {
      for (var mois in widget.fraisScolaires.months) {
        allRepartitions[mois] = widget.fraisScolaires.calculerRepartitions(mois);
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    double totalCollected = widget.fraisScolaires.getYearTotalCollected();
    return Scaffold(
      appBar: AppBar(title: const Text('Répartitions')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Total Collecté Année: $totalCollected', style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.fraisScolaires.months.length,
              itemBuilder: (context, index) {
                final mois = widget.fraisScolaires.months[index];
                final repartitions = allRepartitions[mois] ?? {'30%': 0.0, '70%': 0.0, '7%': 0.0};
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$mois:', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        ...repartitions.entries.map((entry) => Text('${entry.key}: ${entry.value.toStringAsFixed(2)}')),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const SettingsScreen({super.key, required this.fraisScolaires});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController yearController = TextEditingController();
  final TextEditingController monthlyController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: monthlyController,
              decoration: const InputDecoration(labelText: 'Montant Mensuel Défaut'),
              keyboardType: TextInputType.number,
            ),
            ElevatedButton(
              onPressed: () async {
                final montant = double.tryParse(monthlyController.text);
                if (montant != null) {
                  widget.fraisScolaires.currentData.defaultMonthly = montant;
                  await widget.fraisScolaires.saveData();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mis à jour')));
                }
              },
              child: const Text('Enregistrer Montant'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: yearController,
              decoration: const InputDecoration(labelText: 'Nouvelle Année (ex: 2024-2025)'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newYear = yearController.text.trim();
                if (newYear.isNotEmpty) {
                  await widget.fraisScolaires.resetForNewYear(newYear);
                  Navigator.pop(context);
                }
              },
              child: const Text('Nouvelle Année'),
            ),
            const SizedBox(height: 20),
            ListTile(
              title: const Text('Mode Sombre'),
              trailing: Switch(
                value: appState.isDarkMode,
                onChanged: (value) {
                  appState.toggleTheme();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const HistoryScreen({super.key, required this.fraisScolaires});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? selectedYear;
  String? selectedView;
  Map<String, Map<String, double>> allRepartitions = {};
  List<Eleve> filteredHistoryEleves = [];
  final TextEditingController searchHistoryController = TextEditingController();
  @override
  void initState() {
    super.initState();
    searchHistoryController.addListener(_filterHistoryEleves);
  }
  void _computeRepartitions(String year) {
    final data = widget.fraisScolaires.history[year];
    if (data != null) {
      setState(() {
        allRepartitions = {};
        for (var mois in widget.fraisScolaires.months) {
          double studentTotal = data.eleves.fold(0, (sum, e) => sum + (e.paid[mois] ?? 0));
          double total = (data.manualFrais[mois] ?? 0) + studentTotal;
          allRepartitions[mois] = {
            '30%': total * 0.3,
            '70%': total * 0.7,
            '7%': total * 0.07,
          };
        }
      });
    }
  }
  void _filterHistoryEleves() {
    if (selectedYear == null) return;
    final data = widget.fraisScolaires.history[selectedYear!];
    if (data == null) return;
    final query = searchHistoryController.text.toLowerCase();
    setState(() {
      filteredHistoryEleves = data.eleves.where((eleve) {
        final fullName = '${eleve.nom} ${eleve.postNom} ${eleve.prenom}'.toLowerCase();
        return fullName.contains(query);
      }).toList()
        ..sort((a, b) => '${a.nom} ${a.postNom} ${a.prenom}'.compareTo('${b.nom} ${b.postNom} ${b.prenom}'));
    });
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: Column(
        children: [
          DropdownButton<String>(
            hint: const Text('Année'),
            value: selectedYear,
            onChanged: (value) {
              setState(() {
                selectedYear = value;
                selectedView = null;
                searchHistoryController.clear();
                filteredHistoryEleves = [];
                if (value != null) {
                  _computeRepartitions(value);
                  _filterHistoryEleves();
                }
              });
            },
            items: widget.fraisScolaires.history.keys.map((year) => DropdownMenuItem(value: year, child: Text(year))).toList(),
          ),
          if (selectedYear != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 20,
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => selectedView = 'repartitions'),
                    child: const Text('Répartitions'),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => selectedView = 'paiements'),
                    child: const Text('Paiements Élèves'),
                  ),
                ],
              ),
            ),
          if (selectedYear != null && selectedView == 'paiements')
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: searchHistoryController,
                decoration: const InputDecoration(
                  labelText: 'Rechercher Élève',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          if (selectedYear != null && selectedView != null)
            Expanded(
              child: selectedView == 'repartitions'
                  ? ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: widget.fraisScolaires.months.length,
                itemBuilder: (context, index) {
                  final mois = widget.fraisScolaires.months[index];
                  final repartitions = allRepartitions[mois] ?? {'30%': 0.0, '70%': 0.0, '7%': 0.0};
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$mois ($selectedYear):', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          ...repartitions.entries.map((entry) => Text('${entry.key}: ${entry.value.toStringAsFixed(2)}')),
                        ],
                      ),
                    ),
                  );
                },
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: filteredHistoryEleves.length,
                itemBuilder: (context, index) {
                  final data = widget.fraisScolaires.history[selectedYear!]!;
                  final eleve = filteredHistoryEleves[index];
                  double totalPaid = eleve.paid.values.fold(0.0, (sum, p) => sum + p);
                  double pending = widget.fraisScolaires.months.fold(0.0, (sum, m) => sum + ((data.monthExceptions[m] ?? data.defaultMonthly) - (eleve.paid[m] ?? 0)));
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${eleve.nom} ${eleve.postNom} ${eleve.prenom} - ${eleve.classe}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Payé: $totalPaid | En attente: $pending'),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 80,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: widget.fraisScolaires.months.length,
                              itemBuilder: (context, monthIndex) {
                                final mois = widget.fraisScolaires.months[monthIndex];
                                double required = data.monthExceptions[mois] ?? data.defaultMonthly;
                                double paid = eleve.paid[mois] ?? 0;
                                bool isFullyPaid = paid >= required;
                                Color backgroundColor = isFullyPaid
                                    ? (isDark ? Colors.green[700]! : Colors.green[100]!)
                                    : (isDark ? Colors.red[700]! : Colors.red[100]!);
                                Color borderColor = isDark ? Colors.grey[600]! : Colors.grey[300]!;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                  child: Container(
                                    width: 120,
                                    decoration: BoxDecoration(
                                      color: backgroundColor,
                                      border: Border.all(color: borderColor),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(mois, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        Text('Requis: ${required.toStringAsFixed(0)}'),
                                        if (paid > 0) Text('Payé: ${paid.toStringAsFixed(0)}'),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
