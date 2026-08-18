import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../frais_scolaires.dart';
import '../app_state.dart';

const String _serverUrl = 'https://jsinf.onrender.com';

// ⚡⚡ NOUVEAU — Les 4 types d'accès qu'une clé peut porter. Chaque type
// correspond à un écran différent côté application sous-utilisateur.
enum KeyAccessType { paiement, discipline, inscription, autresFrais }

extension KeyAccessTypeX on KeyAccessType {
  // Code envoyé au serveur (doit correspondre à KEY_TYPES côté Python).
  String get code {
    switch (this) {
      case KeyAccessType.paiement:
        return 'PAY';
      case KeyAccessType.discipline:
        return 'DISC';
      case KeyAccessType.inscription:
        return 'INSC';
      case KeyAccessType.autresFrais:
        return 'AFR';
    }
  }

  String get label {
    switch (this) {
      case KeyAccessType.paiement:
        return 'Paiement des frais scolaires';
      case KeyAccessType.discipline:
        return 'Discipline (absences, convocations, communiqués)';
      case KeyAccessType.inscription:
        return 'Inscription des élèves';
      case KeyAccessType.autresFrais:
        return 'Paiement des autres frais';
    }
  }

  IconData get icon {
    switch (this) {
      case KeyAccessType.paiement:
        return Icons.payments;
      case KeyAccessType.discipline:
        return Icons.gavel;
      case KeyAccessType.inscription:
        return Icons.person_add;
      case KeyAccessType.autresFrais:
        return Icons.receipt_long;
    }
  }
}

// Valeur spéciale utilisée dans le dropdown "Classe" pour signifier
// "toutes les classes de la section" (envoyée comme classe vide au
// serveur, ce que verify_key traduit en `classe: null`).
const String _kToutesLesClasses = '__TOUTES__';

class AdminDashboardScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const AdminDashboardScreen({super.key, required this.fraisScolaires});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // ---------------- GÉNÉRATION DE CLÉ ----------------
  KeyAccessType selectedKeyType = KeyAccessType.paiement;
  String? selectedSectionForKey;
  String? selectedClasseForKey; // null / _kToutesLesClasses = toutes les classes
  bool isGeneratingKey = false;
  List<Map<String, dynamic>> generatedKeys = [];

  List<String> connectedUsers = [
    "Utilisateur Primaire 1",
    "Utilisateur Secondaire 1"
  ];

  // ---------------- PAIEMENTS EN ATTENTE (frais mensuels) ----------------
  List<Map<String, dynamic>> pendingPayments = [];
  bool hasPendingPayments = false;
  bool isValidating = false;
  bool isRefreshing = false;

  // ⚡⚡ NOUVEAU — INSCRIPTIONS EN ATTENTE
  List<Map<String, dynamic>> pendingRegistrations = [];
  bool isValidatingRegistrations = false;

  // ⚡⚡ NOUVEAU — AUTRES FRAIS EN ATTENTE
  List<Map<String, dynamic>> pendingAutresFrais = [];
  bool isValidatingAutresFrais = false;

  // Classes disponibles pour la section actuellement choisie dans le
  // formulaire de génération de clé (utilise Config.classesBySection).
  List<String> get _classesForSelectedSection {
    if (selectedSectionForKey == null) return [];
    return widget.fraisScolaires.config.classesBySection[selectedSectionForKey!] ??
        [];
  }

  Future<bool> _verifyAdminPassword() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Aucun mot de passe administrateur défini. "
                "Rendez-vous dans les Paramètres pour en créer un.",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    final passController = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vérification Administrateur"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Cette action est protégée. Entrez le mot de passe "
                  "administrateur pour continuer.",
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () {
              if (passController.text.trim() == appState.backupPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Mot de passe incorrect."),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _refreshData() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Définissez d'abord le Code École"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Définissez un mot de passe de sauvegarde")),
      );
      return;
    }

    setState(() => isRefreshing = true);

    try {
      final Map<String, dynamic> restoreResult =
      await widget.fraisScolaires.restoreFromServer(
        appState.schoolCode!,
        appState.backupPassword!,
      );
      final bool success = restoreResult['success'] == true;

      // Paiements de frais mensuels en attente.
      List<Map<String, dynamic>> fetchedPending = [];
      try {
        final pendingResponse = await http
            .get(Uri.parse(
            '$_serverUrl/get_pending_payments?school_code=${appState.schoolCode}'))
            .timeout(const Duration(seconds: 15));
        if (pendingResponse.statusCode == 200) {
          final data = jsonDecode(pendingResponse.body);
          final list = data['pending_payments'] as List<dynamic>? ?? [];
          fetchedPending =
              list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}

      // ⚡⚡ NOUVEAU — Inscriptions en attente.
      List<Map<String, dynamic>> fetchedRegistrations = [];
      try {
        final regResponse = await http
            .get(Uri.parse(
            '$_serverUrl/school/get_pending_registrations?school_code=${appState.schoolCode}'))
            .timeout(const Duration(seconds: 15));
        if (regResponse.statusCode == 200) {
          final data = jsonDecode(regResponse.body);
          final list =
              data['pending_registrations'] as List<dynamic>? ?? [];
          fetchedRegistrations =
              list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}

      // ⚡⚡ NOUVEAU — Paiements d'autres frais en attente.
      List<Map<String, dynamic>> fetchedAutresFrais = [];
      try {
        final afrResponse = await http
            .get(Uri.parse(
            '$_serverUrl/school/get_pending_autres_frais?school_code=${appState.schoolCode}'))
            .timeout(const Duration(seconds: 15));
        if (afrResponse.statusCode == 200) {
          final data = jsonDecode(afrResponse.body);
          final list =
              data['pending_autres_frais'] as List<dynamic>? ?? [];
          fetchedAutresFrais =
              list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          pendingPayments = fetchedPending;
          hasPendingPayments = pendingPayments.isNotEmpty;
          pendingRegistrations = fetchedRegistrations;
          pendingAutresFrais = fetchedAutresFrais;
        });

        if (success) {
          final int totalPending = pendingPayments.length +
              pendingRegistrations.length +
              pendingAutresFrais.length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                totalPending > 0
                    ? "✅ $totalPending élément(s) en attente de validation"
                    : "✅ Données récupérées du serveur",
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          final String errorMsg =
              restoreResult['error']?.toString() ?? "Erreur inconnue";
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "⚠️ Impossible de recharger les données générales : $errorMsg",
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Erreur de connexion"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isRefreshing = false);
    }
  }

  // ==================== PAIEMENTS DES FRAIS MENSUELS ====================

  void _showPendingPaymentsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Paiements en Attente de Validation"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: pendingPayments.isEmpty
              ? const Center(child: Text("Aucun paiement en attente"))
              : ListView.builder(
            itemCount: pendingPayments.length,
            itemBuilder: (context, index) {
              final p = pendingPayments[index];
              return ListTile(
                title: Text(
                  "${p['nom']} ${p['postNom'] ?? ''} ${p['prenom']}",
                ),
                subtitle: Text(
                  "${p['mois']} - ${p['amount']} FC\n"
                      "Section: ${p['section'] ?? ''} | Classe: ${p['classe'] ?? ''}",
                ),
                trailing:
                const Icon(Icons.check_circle, color: Colors.green),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: pendingPayments.isEmpty
                ? null
                : () async {
              Navigator.pop(ctx);
              await _validateAllPayments();
            },
            child: const Text("Valider Tout"),
          ),
        ],
      ),
    );
  }

  Future<void> _validateAllPayments() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Code école manquant"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (appState.backupPassword == null || appState.backupPassword!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Mot de passe de sauvegarde manquant"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isValidating = true);

    try {
      final ids = pendingPayments.map((p) => p['id']).toList();

      final response = await http
          .post(
        Uri.parse('$_serverUrl/validate_payments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': appState.schoolCode,
          'payment_ids': ids,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> restoreResult =
        await widget.fraisScolaires.restoreFromServer(
          appState.schoolCode!,
          appState.backupPassword!,
        );
        final bool success = restoreResult['success'] == true;

        if (success && mounted) {
          await widget.fraisScolaires.saveData();

          setState(() {
            hasPendingPayments = false;
            pendingPayments.clear();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
              Text("✅ Tous les paiements ont été validés et enregistrés !"),
              backgroundColor: Colors.green,
            ),
          );

          await widget.fraisScolaires.loadData();
          if (mounted) setState(() {});
        } else if (mounted) {
          final String errorMsg =
              restoreResult['error']?.toString() ?? "Erreur inconnue";
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "⚠️ Paiements validés côté serveur mais impossible de "
                    "recharger les données locales : $errorMsg",
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Erreur lors de la validation côté serveur"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur lors de la validation"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isValidating = false);
    }
  }

  // ==================== ⚡⚡ NOUVEAU — INSCRIPTIONS EN ATTENTE ====================

  void _showPendingRegistrationsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Inscriptions en Attente de Validation"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: pendingRegistrations.isEmpty
              ? const Center(child: Text("Aucune inscription en attente"))
              : ListView.builder(
            itemCount: pendingRegistrations.length,
            itemBuilder: (context, index) {
              final r = pendingRegistrations[index];
              return ListTile(
                leading: const Icon(Icons.person_add, color: Colors.indigo),
                title: Text("${r['nom']} ${r['postNom'] ?? ''} ${r['prenom'] ?? ''}"),
                subtitle: Text(
                  "Section: ${r['section']} | Classe: ${r['classe']}\n"
                      "Soumis par: ${r['submitted_by'] ?? ''}",
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer"),
          ),
          ElevatedButton(
            onPressed: pendingRegistrations.isEmpty
                ? null
                : () async {
              Navigator.pop(ctx);
              await _validateAllRegistrations();
            },
            child: const Text("Valider Tout"),
          ),
        ],
      ),
    );
  }

  Future<void> _validateAllRegistrations() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) return;

    setState(() => isValidatingRegistrations = true);
    try {
      final ids = pendingRegistrations.map((r) => r['id']).toList();
      final response = await http
          .post(
        Uri.parse('$_serverUrl/school/validate_registrations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': appState.schoolCode,
          'registration_ids': ids,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && appState.backupPassword != null) {
        await widget.fraisScolaires
            .restoreFromServer(appState.schoolCode!, appState.backupPassword!);
        await widget.fraisScolaires.saveData();
        await widget.fraisScolaires.loadData();
        if (mounted) {
          setState(() => pendingRegistrations.clear());
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Inscriptions validées et élèves créés !"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Erreur lors de la validation des inscriptions"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur lors de la validation"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isValidatingRegistrations = false);
    }
  }

  // ==================== ⚡⚡ NOUVEAU — AUTRES FRAIS EN ATTENTE ====================

  void _showPendingAutresFraisDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Paiements d'Autres Frais en Attente"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: pendingAutresFrais.isEmpty
              ? const Center(child: Text("Aucun paiement en attente"))
              : ListView.builder(
            itemCount: pendingAutresFrais.length,
            itemBuilder: (context, index) {
              final p = pendingAutresFrais[index];
              return ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.teal),
                title: Text("${p['nom']} ${p['postNom'] ?? ''} ${p['prenom'] ?? ''}"),
                subtitle: Text(
                  "${p['autreFraisNom']} - ${p['montant']} FC\n"
                      "Enregistré par: ${p['enregistrePar'] ?? ''}",
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer"),
          ),
          ElevatedButton(
            onPressed: pendingAutresFrais.isEmpty
                ? null
                : () async {
              Navigator.pop(ctx);
              await _validateAllAutresFrais();
            },
            child: const Text("Valider Tout"),
          ),
        ],
      ),
    );
  }

  Future<void> _validateAllAutresFrais() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) return;

    setState(() => isValidatingAutresFrais = true);
    try {
      final ids = pendingAutresFrais.map((p) => p['id']).toList();
      final response = await http
          .post(
        Uri.parse('$_serverUrl/school/validate_autres_frais_payments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': appState.schoolCode,
          'payment_ids': ids,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && appState.backupPassword != null) {
        await widget.fraisScolaires
            .restoreFromServer(appState.schoolCode!, appState.backupPassword!);
        await widget.fraisScolaires.saveData();
        await widget.fraisScolaires.loadData();
        if (mounted) {
          setState(() => pendingAutresFrais.clear());
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Paiements d'autres frais validés !"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Erreur lors de la validation"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur lors de la validation"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isValidatingAutresFrais = false);
    }
  }

  // ==================== ⚡⚡ NOUVEAU — GÉNÉRATION DE CLÉ MULTI-USAGES ====================

  Future<void> _generateKey() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (selectedSectionForKey == null) return;

    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Définissez d'abord le Code École"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final bool authorized = await _verifyAdminPassword();
    if (!authorized) return;

    // "Toutes les classes" (ou aucune classe disponible pour la section) →
    // on envoie une classe vide, ce que le serveur traduit en "pas de
    // restriction de classe" pour cette clé.
    final String? classeToSend =
    (selectedClasseForKey == null || selectedClasseForKey == _kToutesLesClasses)
        ? null
        : selectedClasseForKey;

    setState(() => isGeneratingKey = true);
    try {
      final response = await http
          .post(
        Uri.parse('$_serverUrl/generate_key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': appState.schoolCode,
          'section': selectedSectionForKey,
          'type': selectedKeyType.code,
          'classe': classeToSend,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          generatedKeys.add({
            'key': data['key'],
            'section': data['section'],
            'type': data['type'] ?? selectedKeyType.code,
            'classe': data['classe'], // null = toutes les classes
          });
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "✅ Clé générée (${selectedKeyType.label}) pour "
                    "${data['section']}"
                    "${classeToSend != null ? ' - $classeToSend' : ' - toutes les classes'}",
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Le serveur n'a pas pu générer la clé"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Pas de connexion internet"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isGeneratingKey = false);
    }
  }

  void _removeUser(String user) {
    setState(() => connectedUsers.remove(user));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$user a été déconnecté")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int totalPendingCount =
        pendingPayments.length + pendingRegistrations.length + pendingAutresFrais.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard - Contrôle Central"),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: isRefreshing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.refresh),
            tooltip: "Rafraîchir les données",
            onPressed: isRefreshing ? null : _refreshData,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================== GÉNÉRATION DE CLÉ ====================
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Générer une Clé d'Accès",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Le mot de passe administrateur sera demandé avant la "
                            "génération afin de protéger l'accès aux données de "
                            "l'école.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      // ⚡⚡ NOUVEAU — 1) Type d'accès de la clé.
                      const Text("1. Pour quoi faire ?",
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: KeyAccessType.values.map((type) {
                          final bool isSelected = selectedKeyType == type;
                          return ChoiceChip(
                            avatar: Icon(type.icon,
                                size: 18,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.deepPurple),
                            label: Text(type.label),
                            selected: isSelected,
                            selectedColor: Colors.deepPurple,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontSize: 12,
                            ),
                            onSelected: (_) =>
                                setState(() => selectedKeyType = type),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // 2) Section (comme avant).
                      const Text("2. Quelle section ?",
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text("Choisir la Section"),
                        value: selectedSectionForKey,
                        items: widget.fraisScolaires.config.sections
                            .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (val) => setState(() {
                          selectedSectionForKey = val;
                          // On réinitialise la classe : elle dépend de la
                          // section choisie.
                          selectedClasseForKey = null;
                        }),
                      ),
                      const SizedBox(height: 16),

                      // ⚡⚡ NOUVEAU — 3) Classe, ou "toutes les classes".
                      const Text("3. Quelle(s) classe(s) ?",
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text("Choisir la classe"),
                        value: selectedClasseForKey,
                        items: [
                          const DropdownMenuItem(
                            value: _kToutesLesClasses,
                            child: Text(
                              "Toutes les classes de la section",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          ..._classesForSelectedSection.map(
                                (c) => DropdownMenuItem(value: c, child: Text(c)),
                          ),
                        ],
                        onChanged: selectedSectionForKey == null
                            ? null
                            : (val) => setState(() => selectedClasseForKey = val),
                      ),
                      const SizedBox(height: 16),

                      ElevatedButton.icon(
                        icon: isGeneratingKey
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                            : const Icon(Icons.key),
                        label: Text(
                          isGeneratingKey
                              ? "Génération en cours..."
                              : "Générer la Clé",
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: (selectedSectionForKey == null ||
                            selectedClasseForKey == null ||
                            isGeneratingKey)
                            ? null
                            : _generateKey,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                "Clés Générées",
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (generatedKeys.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    "Aucune clé générée pour cette session.",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ...generatedKeys.map((keyData) {
                  final KeyAccessType type = KeyAccessType.values.firstWhere(
                        (t) => t.code == keyData['type'],
                    orElse: () => KeyAccessType.paiement,
                  );
                  final String classeLabel =
                  keyData['classe'] == null ? "Toutes les classes" : keyData['classe'];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(type.icon, color: Colors.amber),
                      title: Text(
                        keyData['key'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "${type.label}\nSection : ${keyData['section']} | Classe : $classeLabel",
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: "Copier la clé",
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: keyData['key']));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("✅ Clé copiée")),
                          );
                        },
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 30),

              // ==================== VALIDATIONS EN ATTENTE ====================
              if (totalPendingCount > 0)
                ElevatedButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: Text(
                    "Voir & Valider Tout ce qui est en Attente "
                        "($totalPendingCount)",
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () {
                    if (pendingPayments.isNotEmpty) {
                      _showPendingPaymentsDialog();
                    } else if (pendingRegistrations.isNotEmpty) {
                      _showPendingRegistrationsDialog();
                    } else if (pendingAutresFrais.isNotEmpty) {
                      _showPendingAutresFraisDialog();
                    }
                  },
                )
              else
                ElevatedButton.icon(
                  icon: isRefreshing
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.refresh),
                  label: Text(isRefreshing
                      ? "Rafraîchissement..."
                      : "Rafraîchir les Données"),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: Colors.teal,
                  ),
                  onPressed: isRefreshing ? null : _refreshData,
                ),
              const SizedBox(height: 12),

              // ⚡⚡ NOUVEAU — Détail des 3 files d'attente, chacune avec
              // son propre bouton (paiements / inscriptions / autres frais).
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.payments,
                          color: pendingPayments.isEmpty
                              ? Colors.grey
                              : Colors.green),
                      label: Text("Paiements (${pendingPayments.length})"),
                      onPressed: pendingPayments.isEmpty
                          ? null
                          : _showPendingPaymentsDialog,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.person_add,
                          color: pendingRegistrations.isEmpty
                              ? Colors.grey
                              : Colors.indigo),
                      label: Text("Inscriptions (${pendingRegistrations.length})"),
                      onPressed: pendingRegistrations.isEmpty
                          ? null
                          : _showPendingRegistrationsDialog,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.receipt_long,
                          color: pendingAutresFrais.isEmpty
                              ? Colors.grey
                              : Colors.teal),
                      label: Text("Autres frais (${pendingAutresFrais.length})"),
                      onPressed: pendingAutresFrais.isEmpty
                          ? null
                          : _showPendingAutresFraisDialog,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              const Text(
                "Utilisateurs Connectés",
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...connectedUsers.map(
                    (user) => Card(
                  child: ListTile(
                    leading:
                    const Icon(Icons.person, color: Colors.green),
                    title: Text(user),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _removeUser(user),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    totalPendingCount > 0
                        ? "$totalPendingCount élément(s) envoyé(s) par les "
                        "sous-utilisateurs sont en attente (paiements, "
                        "inscriptions, autres frais).\n\n"
                        "Utilisez les boutons ci-dessus pour les voir et "
                        "les valider."
                        : "Tout ce qui est envoyé par les sous-utilisateurs "
                        "(paiements, inscriptions, autres frais) apparaît "
                        "ici en attente de validation manuelle.",
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}