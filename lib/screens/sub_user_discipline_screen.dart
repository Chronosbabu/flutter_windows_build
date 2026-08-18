import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

/// ⚡⚡ NOUVEAU — Écran Discipline pour un sous-utilisateur (clé DISC).
/// Contrairement aux clés PAY / INSC / AFR, RIEN ici ne passe par une file
/// d'attente de validation admin : absences, convocations et communiqués
/// partent DIRECTEMENT aux parents dès l'envoi — exactement comme le fait
/// déjà discipline_registre_screen.dart côté admin, via les routes
/// /school/record_absences, /school/send_convocation et
/// /school/send_announcement (le serveur ne distingue pas admin/sous-clé
/// pour ces 3 routes, donc rien à changer côté serveur).
///
/// ⚠️ Le communiqué est volontairement limité, côté client, au périmètre
/// autorisé par la clé (sa section, et sa classe si elle est verrouillée) :
/// jamais "toute l'école". Cette limite n'est PAS vérifiée côté serveur —
/// /school/send_announcement fait confiance à ce que le client envoie. Si
/// un contrôle strict est nécessaire, il faudra l'ajouter côté serveur.
class SubUserDisciplineScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String assignedSection;
  final String? assignedClasse;
  final String? initialYear;

  const SubUserDisciplineScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.assignedSection,
    this.assignedClasse,
    this.initialYear,
  });

  @override
  State<SubUserDisciplineScreen> createState() =>
      _SubUserDisciplineScreenState();
}

class _SubUserDisciplineScreenState extends State<SubUserDisciplineScreen> {
  late String currentYear;
  String? selectedClasse;
  DateTime selectedDate = DateTime.now();

  List<Map<String, dynamic>> eleves = [];
  List<String> classesDisponibles = [];
  final Set<String> absentIds = {};

  bool isLoading = true;
  bool isLoadingAttendance = false;
  bool isSending = false;

  final agentNameController = TextEditingController();
  static const _kAgentNameKey = 'sub_agent_name';

  String get _dateStr =>
      "${selectedDate.year.toString().padLeft(4, '0')}-"
          "${selectedDate.month.toString().padLeft(2, '0')}-"
          "${selectedDate.day.toString().padLeft(2, '0')}";

  @override
  void initState() {
    super.initState();
    currentYear = widget.initialYear ?? '2025-2026';
    selectedClasse = widget.assignedClasse;
    _bootstrap();
  }

  @override
  void dispose() {
    agentNameController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    agentNameController.text = prefs.getString(_kAgentNameKey) ?? '';
    await _fetchStudents();
    if (selectedClasse != null) await _loadExistingAttendance();
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchStudents() async {
    Map<String, dynamic>? data;
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/restore?school_code=${widget.schoolCode}'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        data = json.decode(response.body) as Map<String, dynamic>;
        await LocalStorageHelper.saveCachedServerData(data);
      }
    } catch (_) {}
    data ??= await LocalStorageHelper.getCachedServerData();
    if (data == null) return;

    final fetchedYear = data['currentYear']?.toString();
    if (fetchedYear != null && fetchedYear.isNotEmpty) currentYear = fetchedYear;

    final rawList = (data['history']?[currentYear]?['eleves'] ?? []) as List;
    final sectionStudents = rawList
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['section'] == widget.assignedSection)
        .toList();

    final classes = sectionStudents
        .map((e) => e['classe']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (mounted) {
      setState(() {
        eleves = sectionStudents;
        classesDisponibles =
        widget.assignedClasse != null ? [widget.assignedClasse!] : classes;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (selectedClasse == null) return [];
    final list = eleves.where((e) => e['classe'] == selectedClasse).toList();
    list.sort((a, b) =>
        (a['nom'] ?? '').toString().compareTo((b['nom'] ?? '').toString()));
    return list;
  }

  Future<void> _loadExistingAttendance() async {
    if (selectedClasse == null) return;
    setState(() => isLoadingAttendance = true);
    try {
      final response = await http
          .get(Uri.parse(
          '$serverUrl/school/get_attendance?school_code=${widget.schoolCode}'
              '&date=$_dateStr&classe=${Uri.encodeComponent(selectedClasse!)}'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            absentIds
              ..clear()
              ..addAll(List<String>.from(result['absents'] ?? []));
          });
        }
      }
    } catch (_) {
      // Hors ligne : on garde les cases cochées localement telles quelles.
    } finally {
      if (mounted) setState(() => isLoadingAttendance = false);
    }
  }

  void _onClasseChanged(String? value) {
    setState(() {
      selectedClasse = value;
      absentIds.clear();
    });
    _loadExistingAttendance();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      await _loadExistingAttendance();
    }
  }

  void _toggleAbsent(String id) {
    setState(() {
      if (absentIds.contains(id)) {
        absentIds.remove(id);
      } else {
        absentIds.add(id);
      }
    });
  }

  Future<void> _saveAgentName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgentNameKey, agentNameController.text.trim());
  }

  Future<void> _sendAbsences() async {
    if (selectedClasse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sélectionnez d'abord une classe")),
      );
      return;
    }
    if (absentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucun élève coché comme absent")),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer l'envoi"),
        content: Text(
          "Envoyer une notification d'absence non justifiée aux parents de "
              "${absentIds.length} élève(s) pour le $_dateStr ?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Envoyer"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _saveAgentName();
    setState(() => isSending = true);
    try {
      final response = await http
          .post(
        Uri.parse('$serverUrl/school/record_absences'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': widget.schoolCode,
          'annee': currentYear,
          'classe': selectedClasse,
          'section': widget.assignedSection,
          'date': _dateStr,
          'absent_ids': absentIds.toList(),
          'recorded_by': agentNameController.text.trim().isEmpty
              ? 'Direction'
              : agentNameController.text.trim(),
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${result['notified_count']} parent(s) notifié(s)"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("⚠️ Erreur lors de l'envoi"),
              backgroundColor: Colors.orange),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Pas de connexion : réessayez plus tard"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  void _showConvocationDialog(Map<String, dynamic> eleve) {
    final titleController = TextEditingController(text: "Convocation des parents");
    final messageController = TextEditingController(
      text: "Nous souhaitons vous rencontrer au sujet du comportement de "
          "votre enfant ${eleve['nom']} ${eleve['prenom']} à l'école. Merci "
          "de vous présenter à l'administration dans les meilleurs délais.",
    );
    bool sending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text("Convoquer — ${eleve['nom']} ${eleve['prenom']}"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                      labelText: "Titre", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: "Message au parent",
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: sending
                  ? null
                  : () async {
                if (messageController.text.trim().isEmpty) return;
                setDialogState(() => sending = true);
                bool success = false;
                String error = "Échec de l'envoi";
                try {
                  final response = await http
                      .post(
                    Uri.parse('$serverUrl/school/send_convocation'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'school_code': widget.schoolCode,
                      'student_id': eleve['id'],
                      'title': titleController.text.trim(),
                      'message': messageController.text.trim(),
                    }),
                  )
                      .timeout(const Duration(seconds: 15));
                  success = response.statusCode == 200;
                } catch (_) {
                  error = 'Pas de connexion';
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? "✅ Convocation envoyée au parent"
                          : "⚠️ $error"),
                      backgroundColor:
                      success ? Colors.green : Colors.orange,
                    ),
                  );
                }
              },
              child: sending
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Text("Envoyer"),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // COMMUNIQUÉ — ciblage limité au périmètre de la clé : élèves sélectionnés
  // dans la classe affichée, la classe elle-même, ou (seulement si la clé
  // n'est pas verrouillée sur une seule classe) toute la section assignée.
  // Jamais "toute l'école".
  // ==========================================================================
  void _showCommuniqueDialog() {
    final titleController = TextEditingController(text: "Communiqué de l'école");
    final messageController = TextEditingController();
    // Valeur par défaut sûre : on ne pointe jamais sur un target désactivé.
    String target = selectedClasse != null
        ? 'classe'
        : (widget.assignedClasse == null ? 'section' : 'students');
    final Set<String> selectedStudentIds = {};
    bool sending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("Nouveau Communiqué"),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                        labelText: "Titre", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: "Message", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text("Destinataires",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  RadioListTile<String>(
                    dense: true,
                    value: 'classe',
                    groupValue: target,
                    title: Text(selectedClasse != null
                        ? "Uniquement la classe $selectedClasse"
                        : "Sélectionnez d'abord une classe"),
                    onChanged: selectedClasse == null
                        ? null
                        : (v) => setDialogState(() => target = v!),
                  ),
                  if (widget.assignedClasse == null)
                    RadioListTile<String>(
                      dense: true,
                      value: 'section',
                      groupValue: target,
                      title: Text("Toute la section ${widget.assignedSection}"),
                      onChanged: (v) => setDialogState(() => target = v!),
                    ),
                  RadioListTile<String>(
                    dense: true,
                    value: 'students',
                    groupValue: target,
                    title: Text(
                        "Élèves sélectionnés (${selectedStudentIds.length})"),
                    onChanged: (v) => setDialogState(() => target = v!),
                  ),
                  if (target == 'students')
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView(
                        shrinkWrap: true,
                        children: _filteredStudents.map((e) {
                          final id = e['id']?.toString() ?? '';
                          final checked = selectedStudentIds.contains(id);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            title: Text("${e['nom']} ${e['prenom']}"),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selectedStudentIds.add(id);
                              } else {
                                selectedStudentIds.remove(id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler")),
            ElevatedButton(
              onPressed: sending
                  ? null
                  : () async {
                if (messageController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Le message est vide")),
                  );
                  return;
                }
                if (target == 'classe' && selectedClasse == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Choisissez d'abord une classe")),
                  );
                  return;
                }
                if (target == 'students' && selectedStudentIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Sélectionnez au moins un élève")),
                  );
                  return;
                }

                setDialogState(() => sending = true);

                final payload = <String, dynamic>{
                  'school_code': widget.schoolCode,
                  'annee': currentYear,
                  'title': titleController.text.trim(),
                  'message': messageController.text.trim(),
                  'target': target,
                };
                if (target == 'classe') payload['classe'] = selectedClasse;
                if (target == 'section') {
                  payload['section'] = widget.assignedSection;
                }
                if (target == 'students') {
                  payload['student_ids'] = selectedStudentIds.toList();
                }

                bool success = false;
                int notified = 0;
                try {
                  final response = await http
                      .post(
                    Uri.parse('$serverUrl/school/send_announcement'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(payload),
                  )
                      .timeout(const Duration(seconds: 15));
                  if (response.statusCode == 200) {
                    final result =
                    json.decode(response.body) as Map<String, dynamic>;
                    notified =
                        (result['notified_count'] as num?)?.toInt() ?? 0;
                    success = true;
                  }
                } catch (_) {}

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? "✅ Communiqué envoyé à $notified parent(s)"
                          : "❌ Échec de l'envoi (pas de connexion ?)"),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              child: sending
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Text("Envoyer"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final students = _filteredStudents;
    final String titleSuffix = widget.assignedClasse != null
        ? "${widget.assignedSection} - ${widget.assignedClasse}"
        : widget.assignedSection;

    return Scaffold(
      appBar: AppBar(
        title: Text("Discipline - $titleSuffix"),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: "Lancer un communiqué",
            onPressed: _showCommuniqueDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: agentNameController,
                  decoration: const InputDecoration(
                    labelText: "Votre nom (agent, optionnel)",
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  onEditingComplete: _saveAgentName,
                ),
                const SizedBox(height: 10),
                if (widget.assignedClasse != null)
                  Card(
                    color: Colors.indigo.shade50,
                    child: ListTile(
                      leading:
                      const Icon(Icons.class_, color: Colors.indigo),
                      title: Text("Classe : ${widget.assignedClasse}"),
                      subtitle:
                      const Text("Verrouillée par votre clé d'accès"),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: selectedClasse,
                    decoration: const InputDecoration(
                      labelText: "Classe",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: classesDisponibles
                        .map((c) =>
                        DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: _onClasseChanged,
                  ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: "Date",
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(_dateStr),
                  ),
                ),
              ],
            ),
          ),
          if (selectedClasse != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${students.length} élève(s) • "
                        "${absentIds.length} absent(s) coché(s)",
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  if (isLoadingAttendance)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: selectedClasse == null
                ? const Center(
                child: Text(
                    "Sélectionnez une classe pour commencer le registre du jour."))
                : students.isEmpty
                ? const Center(child: Text("Aucun élève trouvé"))
                : ListView.builder(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: students.length,
              itemBuilder: (context, index) {
                final e = students[index];
                final id = e['id']?.toString() ?? '';
                final isAbsent = absentIds.contains(id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: isAbsent ? Colors.red.shade50 : null,
                  child: ListTile(
                    leading: Checkbox(
                      value: isAbsent,
                      activeColor: Colors.red,
                      onChanged: (_) => _toggleAbsent(id),
                    ),
                    title: Text("${e['nom']} ${e['postNom']} ${e['prenom']}"),
                    subtitle: Text(
                      isAbsent ? "Marqué ABSENT aujourd'hui" : "Présent",
                      style: TextStyle(
                        color: isAbsent ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.campaign_outlined,
                          color: Colors.orange),
                      tooltip: "Convoquer le parent",
                      onPressed: () => _showConvocationDialog(e),
                    ),
                    onTap: () => _toggleAbsent(id),
                  ),
                );
              },
            ),
          ),
          if (selectedClasse != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: isSending
                      ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                  label: Text(isSending
                      ? "Envoi en cours..."
                      : "Envoyer les absences (${absentIds.length})"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: isSending ? null : _sendAbsences,
                ),
              ),
            ),
        ],
      ),
    );
  }
}