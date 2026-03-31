import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Système Examens',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ProfHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ProfHomePage extends StatefulWidget {
  const ProfHomePage({super.key});

  @override
  State<ProfHomePage> createState() => _ProfHomePageState();
}

class _ProfHomePageState extends State<ProfHomePage> {
  Socket? _socket;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToServer();
  }

  @override
  void dispose() {
    _socket?.close();
    super.dispose();
  }

  Future<void> _connectToServer() async {
    for (int attempt = 1; attempt <= 5; attempt++) {
      try {
        _socket = await Socket.connect('192.168.4.1', 9999);
        final msg = {'type': 'PROF'};
        _socket!.add(utf8.encode(jsonEncode(msg)));

        setState(() => _isConnected = true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Connecté au serveur")),
        );
        return;
      } catch (e) {
        if (attempt == 5) {
          _showErrorDialog("Aucune connexion au réseau");
        } else {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Erreur"),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Application Professeur"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Bienvenue", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 60),
            ElevatedButton(
              onPressed: _isConnected
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => GenerateExamPage(socket: _socket!)))
                  : null,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              child: const Text("Générer un examen"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isConnected
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubmissionsPage(socket: _socket!)))
                  : null,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              child: const Text("Voir examens reçus"),
            ),
            if (!_isConnected)
              const Padding(padding: EdgeInsets.only(top: 30), child: Text("Connexion en cours...", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
          ],
        ),
      ),
    );
  }
}

// ====================== PAGE GÉNÉRER UN EXAMEN ======================
class GenerateExamPage extends StatefulWidget {
  final Socket socket;
  const GenerateExamPage({super.key, required this.socket});
  @override
  State<GenerateExamPage> createState() => _GenerateExamPageState();
}

class _GenerateExamPageState extends State<GenerateExamPage> {
  final List<TextEditingController> _questionControllers = [];
  final TextEditingController _durationController = TextEditingController(text: "60");

  @override
  void initState() {
    super.initState();
    _addQuestionField();
  }

  void _addQuestionField() {
    setState(() => _questionControllers.add(TextEditingController()));
  }

  Future<void> _publishExam() async {
    final questions = _questionControllers.map((c) => c.text.trim()).where((q) => q.isNotEmpty).toList();
    if (questions.isEmpty) {
      _showError("Ajoutez au moins une question");
      return;
    }
    final examText = questions.join(" --- ");
    try {
      final duration = int.parse(_durationController.text);
      final msg = {'action': 'PUBLISH_EXAM', 'exam': examText, 'duration': duration};
      widget.socket.add(utf8.encode(jsonEncode(msg)));

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Examen publié")));
      Navigator.pop(context);
    } catch (e) {
      _showError("Erreur lors de la publication");
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Erreur"),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("GENERER UN EXAMEN")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _questionControllers.length,
                itemBuilder: (context, index) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Question ${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _questionControllers[index],
                          maxLines: 5,
                          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Entrez la question ici..."),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ElevatedButton(onPressed: _addQuestionField, child: const Text("+ Ajouter une question")),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text("Durée de l'examen (minutes) :"),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _durationController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _publishExam,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text("PUBLIER L'EXAMEN", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================== PAGE EXAMENS REÇUS ======================
class SubmissionsPage extends StatefulWidget {
  final Socket socket;
  const SubmissionsPage({super.key, required this.socket});
  @override
  State<SubmissionsPage> createState() => _SubmissionsPageState();
}

class _SubmissionsPageState extends State<SubmissionsPage> {
  List<String> _students = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSubmissions());
  }

  Future<void> _loadSubmissions() async {
    setState(() => _loading = true);

    try {
      widget.socket.add(utf8.encode(jsonEncode({'action': 'GET_SUBMISSIONS'})));
      // Correction : Socket n'a pas de méthode .read() → on utilise .first
      final data = await widget.socket.first.timeout(const Duration(seconds: 8));
      final resp = jsonDecode(utf8.decode(data));

      setState(() {
        _students = List<String>.from(resp['names'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible de charger la liste")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Examens reçus des étudiants"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSubmissions)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
          ? const Center(child: Text("Aucun étudiant n'a encore rendu sa copie"))
          : ListView.builder(
        itemCount: _students.length,
        itemBuilder: (context, index) {
          final name = _students[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text(name, style: const TextStyle(fontSize: 18)),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CorrectionPage(socket: widget.socket, studentName: name))),
            ),
          );
        },
      ),
    );
  }
}

// ====================== PAGE CORRECTION ======================
class CorrectionPage extends StatefulWidget {
  final Socket socket;
  final String studentName;
  const CorrectionPage({super.key, required this.socket, required this.studentName});
  @override
  State<CorrectionPage> createState() => _CorrectionPageState();
}

class _CorrectionPageState extends State<CorrectionPage> {
  List<String> _questions = [];
  List<String> _answers = [];
  bool _loading = true;
  final TextEditingController _scoreController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSubmission());
  }

  Future<void> _loadSubmission() async {
    setState(() => _loading = true);

    try {
      final msg = {'action': 'GET_SUBMISSION', 'name': widget.studentName};
      widget.socket.add(utf8.encode(jsonEncode(msg)));
      // Correction : Socket n'a pas de méthode .read() → on utilise .first
      final data = await widget.socket.first.timeout(const Duration(seconds: 8));
      final resp = jsonDecode(utf8.decode(data));

      setState(() {
        _questions = resp['exam'].toString().split('---').map((q) => q.trim()).where((q) => q.isNotEmpty).toList();
        _answers = (resp['answers'] ?? "").toString().split('---').map((a) => a.trim()).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible de charger la copie")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Correction - ${widget.studentName}")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
          ? const Center(child: Text("Aucune donnée reçue pour cet étudiant"))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _questions.length,
        itemBuilder: (context, i) {
          final answer = i < _answers.length ? _answers[i] : "Aucune réponse fournie";
          return Card(
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Question ${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_questions[i], style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 16),
                  const Text("Réponse de l'étudiant :", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(answer, style: const TextStyle(fontSize: 15)),
                  const Divider(height: 30),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Text("Note finale /20 :", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 15),
            Expanded(child: TextField(controller: _scoreController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder()))),
            const SizedBox(width: 15),
            ElevatedButton(
              onPressed: () {
                final note = _scoreController.text.trim();
                if (note.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Note de ${widget.studentName} : $note/20")));
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Veuillez entrer une note")));
                }
              },
              child: const Text("Enregistrer la note"),
            ),
          ],
        ),
      ),
    );
  }
}
