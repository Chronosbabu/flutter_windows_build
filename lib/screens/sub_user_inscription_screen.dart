import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

/// ⚡⚡ NOUVEAU — Écran d'inscription pour un sous-utilisateur (clé INSC).
/// Contrairement à EnregistrerEleveScreen (admin, écrit directement dans
/// les données locales via FraisScolaires), chaque fiche est envoyée au
/// serveur via /school/submit_registration et reste EN ATTENTE tant que
/// l'admin ne l'a pas validée (POST /school/validate_registrations) —
/// exactement la même règle que pour les paiements (clé PAY).
///
/// ⚠️ LIMITATION SERVEUR ACTUELLE : /school/submit_registration et
/// /school/validate_registrations ne conservent PAS la photo ni les
/// questions personnalisées (customFields). Ces deux champs ne sont donc
/// volontairement PAS proposés ici, pour éviter de faire croire à l'agent
/// que ces informations seront gardées alors qu'elles seraient
/// silencieusement perdues à la validation.
class SubUserInscriptionScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String assignedSection;
  final String? assignedClasse; // null = toutes les classes de la section
  final String? initialYear;

  const SubUserInscriptionScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.assignedSection,
    this.assignedClasse,
    this.initialYear,
  });

  @override
  State<SubUserInscriptionScreen> createState() =>
      _SubUserInscriptionScreenState();
}

class _SubUserInscriptionScreenState extends State<SubUserInscriptionScreen> {
  final nomController = TextEditingController();
  final postNomController = TextEditingController();
  final prenomController = TextEditingController();
  final pereNomController = TextEditingController();
  final mereNomController = TextEditingController();
  final adresseController = TextEditingController();
  final agentNameController = TextEditingController();

  final FocusNode nomFocus = FocusNode();
  final FocusNode postNomFocus = FocusNode();
  final FocusNode prenomFocus = FocusNode();

  DateTime? selectedDateNaissance;

  String? selectedClasseNumero; // utilisé seulement si assignedClasse == null
  List<String> classesDisponibles = [];

  late String currentYear;
  bool isLoading = true;
  bool isSaving = false;

  List<Map<String, dynamic>> offlineQueue = [];
  static const _kOfflineQueueKey = 'sub_offline_registrations';
  static const _kAgentNameKey = 'sub_agent_name';

  @override
  void initState() {
    super.initState();
    currentYear = widget.initialYear ?? '2025-2026';
    selectedClasseNumero = widget.assignedClasse;
    _bootstrap();
  }

  @override
  void dispose() {
    nomController.dispose();
    postNomController.dispose();
    prenomController.dispose();
    pereNomController.dispose();
    mereNomController.dispose();
    adresseController.dispose();
    agentNameController.dispose();
    nomFocus.dispose();
    postNomFocus.dispose();
    prenomFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    agentNameController.text = prefs.getString(_kAgentNameKey) ?? '';

    final queueStr = prefs.getString(_kOfflineQueueKey);
    if (queueStr != null) {
      try {
        offlineQueue = List<Map<String, dynamic>>.from(
          (jsonDecode(queueStr) as List)
              .map((e) => Map<String, dynamic>.from(e)),
        );
      } catch (_) {
        offlineQueue = [];
      }
    }

    // Classes disponibles : si la clé est verrouillée sur une classe
    // précise, on ne propose que celle-là. Sinon on va chercher la liste
    // des classes existantes de la section depuis le serveur.
    if (widget.assignedClasse != null) {
      classesDisponibles = [widget.assignedClasse!];
      selectedClasseNumero = widget.assignedClasse;
    } else {
      await _fetchClassesForSection();
    }

    if (mounted) setState(() => isLoading = false);
    await _flushOfflineQueue(silent: true);
  }

  Future<void> _fetchClassesForSection() async {
    Map<String, dynamic>? data;
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/restore?school_code=${widget.schoolCode}'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        data = json.decode(response.body) as Map<String, dynamic>;
        await LocalStorageHelper.saveCachedServerData(data);
      }
    } catch (_) {
      // Pas de connexion : on retombe sur le cache local si disponible.
    }
    data ??= await LocalStorageHelper.getCachedServerData();
    if (data == null) return;

    final fetchedYear = data['currentYear']?.toString();
    if (fetchedYear != null && fetchedYear.isNotEmpty) currentYear = fetchedYear;

    final config = data['config'] as Map<String, dynamic>? ?? {};
    final classesBySection =
        config['classesBySection'] as Map<String, dynamic>? ?? {};
    final list = (classesBySection[widget.assignedSection] as List?) ?? [];
    if (mounted) {
      setState(() {
        classesDisponibles = list.map((e) => e.toString()).toList();
      });
    }
  }

  Future<void> _saveAgentName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgentNameKey, agentNameController.text.trim());
  }

  Future<void> _saveOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOfflineQueueKey, jsonEncode(offlineQueue));
  }

  void _clearFields() {
    nomController.clear();
    postNomController.clear();
    prenomController.clear();
    pereNomController.clear();
    mereNomController.clear();
    adresseController.clear();
    setState(() {
      selectedDateNaissance = null;
      if (widget.assignedClasse == null) selectedClasseNumero = null;
    });
    nomFocus.requestFocus();
  }

  Future<void> _pickDateNaissance() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDateNaissance ?? DateTime(now.year - 10),
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked != null) setState(() => selectedDateNaissance = picked);
  }

  Map<String, dynamic> _buildPayload() {
    String dateNaissanceStr = '';
    if (selectedDateNaissance != null) {
      final d = selectedDateNaissance!;
      String two(int n) => n.toString().padLeft(2, '0');
      dateNaissanceStr = "${two(d.day)}/${two(d.month)}/${d.year}";
    }
    return {
      'school_code': widget.schoolCode,
      'annee': currentYear,
      'section': widget.assignedSection,
      'classe': selectedClasseNumero ?? '',
      'nom': nomController.text.trim(),
      'postNom': postNomController.text.trim(),
      'prenom': prenomController.text.trim(),
      'pereNom': pereNomController.text.trim(),
      'mereNom': mereNomController.text.trim(),
      'adresse': adresseController.text.trim(),
      'dateNaissance': dateNaissanceStr,
      'submitted_by': agentNameController.text.trim().isEmpty
          ? 'Agent inscriptions'
          : agentNameController.text.trim(),
    };
  }

  Future<void> _ajouterEleve() async {
    if (nomController.text.trim().isEmpty ||
        postNomController.text.trim().isEmpty ||
        prenomController.text.trim().isEmpty ||
        selectedClasseNumero == null ||
        selectedClasseNumero!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Veuillez remplir tous les champs obligatoires")),
      );
      return;
    }

    await _saveAgentName();
    setState(() => isSaving = true);
    final payload = _buildPayload();

    final sent = await _trySubmit(payload);

    if (!sent) {
      offlineQueue.add(payload);
      await _saveOfflineQueue();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Pas de connexion : inscription enregistrée localement, "
                    "sera envoyée automatiquement plus tard"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ ${nomController.text.trim()} ${prenomController.text.trim()} "
                "envoyé(e), en attente de validation par l'admin",
          ),
          backgroundColor: Colors.green,
        ),
      );
    }

    if (mounted) {
      setState(() => isSaving = false);
      _clearFields();
    }
  }

  Future<bool> _trySubmit(Map<String, dynamic> payload) async {
    try {
      final response = await http
          .post(
        Uri.parse('$serverUrl/school/submit_registration'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _flushOfflineQueue({bool silent = false}) async {
    if (offlineQueue.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    int sentCount = 0;
    for (final payload in offlineQueue) {
      final ok = await _trySubmit(payload);
      if (ok) {
        sentCount++;
      } else {
        remaining.add(payload);
      }
    }
    offlineQueue = remaining;
    await _saveOfflineQueue();
    if (mounted) {
      setState(() {});
      if (sentCount > 0 && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
              Text("✅ $sentCount inscription(s) en attente envoyée(s)")),
        );
      }
    }
  }

  Widget _queueIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.cloud_upload),
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${offlineQueue.length}',
              style: const TextStyle(color: Colors.white, fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String titleSuffix = widget.assignedClasse != null
        ? "${widget.assignedSection} - ${widget.assignedClasse}"
        : widget.assignedSection;

    return Scaffold(
      appBar: AppBar(
        title: Text("Inscriptions - $titleSuffix"),
        backgroundColor: Colors.indigo,
        actions: [
          if (offlineQueue.isNotEmpty)
            IconButton(
              icon: _queueIcon(),
              tooltip: "Renvoyer les inscriptions en attente",
              onPressed: () => _flushOfflineQueue(),
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
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Inscription Rapide d'Élève",
                style:
                TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              "Chaque fiche est envoyée à l'admin pour validation avant "
                  "de devenir un élève officiel (Section : "
                  "${widget.assignedSection}"
                  "${widget.assignedClasse != null ? ', Classe : ${widget.assignedClasse}' : ''}).",
              style: const TextStyle(color: Colors.grey, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 20),
            TextField(
              controller: nomController,
              focusNode: nomFocus,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: "Nom", border: OutlineInputBorder()),
              onEditingComplete: () => postNomFocus.requestFocus(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: postNomController,
              focusNode: postNomFocus,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: "Post-nom", border: OutlineInputBorder()),
              onEditingComplete: () => prenomFocus.requestFocus(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: prenomController,
              focusNode: prenomFocus,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: "Prénom", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            if (widget.assignedClasse != null)
              Card(
                color: Colors.indigo.shade50,
                child: ListTile(
                  leading: const Icon(Icons.class_, color: Colors.indigo),
                  title: Text("Classe : ${widget.assignedClasse}"),
                  subtitle: const Text("Verrouillée par votre clé d'accès"),
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: selectedClasseNumero,
                decoration: const InputDecoration(
                  labelText: "Classe",
                  border: OutlineInputBorder(),
                ),
                items: classesDisponibles
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => selectedClasseNumero = v),
              ),
            const SizedBox(height: 20),
            TextField(
              controller: pereNomController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: "Nom du père (optionnel)",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mereNomController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: "Nom de la mère (optionnel)",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: adresseController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: "Adresse (optionnel)",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDateNaissance,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: "Date de naissance (optionnel)",
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(selectedDateNaissance == null
                    ? "Non renseignée"
                    : "${selectedDateNaissance!.day.toString().padLeft(2, '0')}/"
                    "${selectedDateNaissance!.month.toString().padLeft(2, '0')}/"
                    "${selectedDateNaissance!.year}"),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                icon: isSaving
                    ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.person_add),
                label:
                Text(isSaving ? "Envoi en cours..." : "Envoyer l'Inscription"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white),
                onPressed: isSaving ? null : _ajouterEleve,
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                "L'élève apparaîtra dans la liste officielle uniquement "
                    "après validation par l'admin.",
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}