import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../frais_scolaires.dart';
import '../app_state.dart';

const String _serverUrl = 'https://jsinf.onrender.com';

// ⚡⚡ Les 4 types d'accès qu'une clé peut porter. Chaque type
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

  // ⚡⚡⚡ NOUVEAU — Sélection MULTIPLE de sections/options pour une même
  // clé. Le sous-utilisateur connecté avec cette clé pourra ensuite
  // basculer librement entre toutes les sections cochées ici, sans
  // avoir besoin d'une clé différente par section.
  final Set<String> selectedSectionsForKey = {};

  // La classe précise n'a de sens que lorsqu'UNE SEULE section est
  // cochée (une classe appartient à une seule section). Dès que 2
  // sections ou plus sont sélectionnées, ce champ est automatiquement
  // ignoré et la clé donne accès à "toutes les classes" de chacune.
  String? selectedClasseForKey; // null / _kToutesLesClasses = toutes les classes
  bool isGeneratingKey = false;
  // ⚡⚡⚡ NOUVEAU — indique qu'une sauvegarde automatique (déclenchée
  // après une génération de clé) est en cours, pour désactiver le
  // bouton "Générer" et éviter les doubles clics pendant l'upload.
  bool isAutoBackingUp = false;
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

  // ⚡⚡ INSCRIPTIONS EN ATTENTE
  List<Map<String, dynamic>> pendingRegistrations = [];
  bool isValidatingRegistrations = false;

  // ⚡⚡ AUTRES FRAIS EN ATTENTE
  List<Map<String, dynamic>> pendingAutresFrais = [];
  bool isValidatingAutresFrais = false;

  // ⚡⚡⚡ NOUVEAU — La classe ne peut être restreinte que si exactement
  // une section est cochée. Les classes proposées dans le dropdown
  // proviennent alors de cette unique section sélectionnée.
  List<String> get _classesForSelectedSection {
    if (selectedSectionsForKey.length != 1) return [];
    final section = selectedSectionsForKey.first;
    return widget.fraisScolaires.config.classesBySection[section] ?? [];
  }

  bool get _classeSelectionAllowed => selectedSectionsForKey.length == 1;

  void _toggleSection(String section, bool selected) {
    setState(() {
      if (selected) {
        selectedSectionsForKey.add(section);
      } else {
        selectedSectionsForKey.remove(section);
      }
      // Dès qu'on n'a plus exactement une seule section cochée, la
      // restriction de classe n'a plus de sens : on la réinitialise.
      if (!_classeSelectionAllowed) {
        selectedClasseForKey = null;
      }
    });
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

      // ⚡⚡ Inscriptions en attente.
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

      // ⚡⚡ Paiements d'autres frais en attente.
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

  // ==================== ⚡⚡ INSCRIPTIONS EN ATTENTE ====================

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

  // ==================== ⚡⚡ AUTRES FRAIS EN ATTENTE ====================

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

  // ==================== ⚡⚡⚡ GÉNÉRATION DE CLÉ MULTI-SECTIONS ====================
  // ⚡⚡⚡ NOUVEAU — Après une génération de clé réussie, les données sont
  // désormais AUTOMATIQUEMENT sauvegardées sur le serveur central (même
  // appel que le bouton "Sauvegarder sur le Serveur" de l'écran
  // Paramètres), sans que l'admin ait besoin d'y aller manuellement.
  // Cela garantit que la clé nouvellement générée (et tout ce qui a pu
  // changer localement depuis la dernière sauvegarde) est immédiatement
  // disponible pour le sous-utilisateur dès qu'il se connecte avec elle.

  /// Sauvegarde silencieuse (pas de SnackBar dédiée en cas de succès —
  /// le résultat est intégré au message de la génération de clé) sur le
  /// serveur central. Renvoie un message d'erreur, ou null en cas de
  /// succès / si la sauvegarde n'a pas pu être tentée faute
  /// d'identifiants.
  Future<String?> _autoBackupAfterKeyGeneration() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) {
      return "code école manquant";
    }
    if (appState.backupPassword == null || appState.backupPassword!.isEmpty) {
      return "mot de passe de sauvegarde non défini (Paramètres)";
    }

    setState(() => isAutoBackingUp = true);
    try {
      final result = await widget.fraisScolaires.backupToServer(
        appState.schoolCode!,
        appState.backupPassword!,
      );
      if (result['success'] == true) {
        return null;
      }
      return result['error']?.toString() ?? "erreur inconnue";
    } catch (e) {
      return "$e";
    } finally {
      if (mounted) setState(() => isAutoBackingUp = false);
    }
  }

  Future<void> _generateKey() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (selectedSectionsForKey.isEmpty) return;

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

    // La classe n'est envoyée que si UNE SEULE section est cochée ET
    // qu'une classe précise (autre que "toutes") a été choisie.
    final String? classeToSend = (_classeSelectionAllowed &&
        selectedClasseForKey != null &&
        selectedClasseForKey != _kToutesLesClasses)
        ? selectedClasseForKey
        : null;

    // ⚡⚡⚡ NOUVEAU — on envoie la LISTE complète des sections cochées.
    final List<String> sectionsToSend = selectedSectionsForKey.toList();

    setState(() => isGeneratingKey = true);
    try {
      final response = await http
          .post(
        Uri.parse('$_serverUrl/generate_key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': appState.schoolCode,
          'sections': sectionsToSend,
          'type': selectedKeyType.code,
          'classe': classeToSend,
        }),
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<String> confirmedSections = (data['sections'] as List?)
            ?.map((s) => s.toString())
            .toList() ??
            sectionsToSend;
        setState(() {
          generatedKeys.add({
            'key': data['key'],
            'sections': confirmedSections,
            'type': data['type'] ?? selectedKeyType.code,
            'classe': data['classe'], // null = toutes les classes
          });
        });

        final String sectionsLabel = confirmedSections.length > 1
            ? "${confirmedSections.length} sections (${confirmedSections.join(', ')})"
            : confirmedSections.first;

        // ⚡⚡⚡ NOUVEAU — sauvegarde automatique sur le serveur central,
        // juste après la génération de la clé, sans passer par les
        // Paramètres.
        final String? backupError = await _autoBackupAfterKeyGeneration();

        if (mounted) {
          final String keyMsg =
              "✅ Clé générée (${selectedKeyType.label}) pour "
              "$sectionsLabel"
              "${classeToSend != null ? ' - $classeToSend' : ' - toutes les classes'}";

          if (backupError == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    "$keyMsg\n💾 Données également sauvegardées sur le serveur"),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    "$keyMsg\n⚠️ Sauvegarde automatique impossible : $backupError"),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
          }
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
    // ⚡⚡⚡ NOUVEAU — le bouton "Générer" reste désactivé tant que la
    // sauvegarde automatique déclenchée par une génération précédente
    // n'est pas terminée.
    final bool generateButtonBusy = isGeneratingKey || isAutoBackingUp;

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
                            "l'école. Les données seront aussi automatiquement "
                            "sauvegardées sur le serveur central juste après.",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      // 1) Type d'accès de la clé.
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

                      // ⚡⚡⚡ NOUVEAU — 2) Sélection MULTIPLE de sections.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("2. Quelle(s) section(s) ?",
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          if (widget.fraisScolaires.config.sections.isNotEmpty)
                            TextButton.icon(
                              icon: Icon(
                                selectedSectionsForKey.length ==
                                    widget.fraisScolaires.config.sections.length
                                    ? Icons.deselect
                                    : Icons.select_all,
                                size: 16,
                              ),
                              label: Text(
                                selectedSectionsForKey.length ==
                                    widget.fraisScolaires.config.sections.length
                                    ? "Tout désélectionner"
                                    : "Tout sélectionner",
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () {
                                setState(() {
                                  if (selectedSectionsForKey.length ==
                                      widget.fraisScolaires.config.sections
                                          .length) {
                                    selectedSectionsForKey.clear();
                                  } else {
                                    selectedSectionsForKey
                                      ..clear()
                                      ..addAll(
                                          widget.fraisScolaires.config.sections);
                                  }
                                  if (!_classeSelectionAllowed) {
                                    selectedClasseForKey = null;
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Cochez une ou plusieurs sections/options : le "
                            "sous-utilisateur pourra ensuite basculer "
                            "librement entre elles, une fois connecté avec "
                            "cette clé, sans avoir besoin d'une autre clé.",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.fraisScolaires.config.sections
                            .map((s) {
                          final bool isSelected =
                          selectedSectionsForKey.contains(s);
                          return FilterChip(
                            avatar: isSelected
                                ? const Icon(Icons.check, size: 16,
                                color: Colors.white)
                                : null,
                            label: Text(s),
                            selected: isSelected,
                            selectedColor: Colors.deepPurple,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontSize: 12,
                            ),
                            onSelected: (val) => _toggleSection(s, val),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // 3) Classe, ou "toutes les classes" — uniquement
                      // proposée quand une seule section est cochée.
                      const Text("3. Quelle(s) classe(s) ?",
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      if (!_classeSelectionAllowed)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            selectedSectionsForKey.isEmpty
                                ? "Sélectionnez d'abord une section."
                                : "Plusieurs sections sont sélectionnées : "
                                "toutes les classes de chacune seront "
                                "accessibles (restriction par classe "
                                "indisponible ici).",
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        )
                      else
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
                                  (c) => DropdownMenuItem(
                                  value: c, child: Text(c)),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => selectedClasseForKey = val),
                        ),
                      const SizedBox(height: 16),

                      ElevatedButton.icon(
                        icon: generateButtonBusy
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
                              : (isAutoBackingUp
                              ? "Sauvegarde automatique en cours..."
                              : "Générer la Clé"),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: (selectedSectionsForKey.isEmpty ||
                            generateButtonBusy)
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
                  final List<String> sections =
                  List<String>.from(keyData['sections'] ?? const []);
                  final String sectionsLabel = sections.isEmpty
                      ? "—"
                      : sections.join(' + ');
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
                        "${type.label}\nSection(s) : $sectionsLabel | Classe : $classeLabel",
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

              // ⚡⚡ Détail des 3 files d'attente, chacune avec
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