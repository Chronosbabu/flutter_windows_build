import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../frais_scolaires.dart';
import '../app_state.dart';

class AdminDashboardScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const AdminDashboardScreen({super.key, required this.fraisScolaires});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String? selectedSectionForKey;
  bool isGeneratingKey = false;
  List<Map<String, dynamic>> generatedKeys = [];
  List<String> connectedUsers = ["Utilisateur Primaire 1", "Utilisateur Secondaire 1"];

  // ==================== PAIEMENTS EN ATTENTE (CORRIGÉ) ====================
  List<Map<String, dynamic>> pendingPayments = [];
  bool hasPendingPayments = false;
  bool isValidating = false;
  bool isRefreshing = false;

  // ==================== RAFRAÎCHIR ET RÉCUPÉRER LES VRAIS PAIEMENTS EN ATTENTE ====================
  Future<void> _refreshData() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Définissez d'abord le Code École"), backgroundColor: Colors.red),
      );
      return;
    }
    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Définissez un mot de passe de sauvegarde")),
      );
      return;
    }

    setState(() => isRefreshing = true);

    try {
      // 1) On recharge les données générales (élèves, config, etc.) depuis le serveur
      bool success = await widget.fraisScolaires.restoreFromServer(
        appState.schoolCode!,
        appState.backupPassword!,
      );

      // 2) On va chercher la VRAIE liste des paiements en attente côté serveur
      List<Map<String, dynamic>> fetchedPending = [];
      try {
        final pendingResponse = await http.get(
          Uri.parse(
            'https://jsinf.onrender.com/get_pending_payments?school_code=${appState.schoolCode}',
          ),
        ).timeout(const Duration(seconds: 15));

        if (pendingResponse.statusCode == 200) {
          final data = jsonDecode(pendingResponse.body);
          final list = data['pending_payments'] as List<dynamic>? ?? [];
          fetchedPending = list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        // Si la récupération des paiements en attente échoue, on continue
        // quand même avec une liste vide plutôt que de bloquer tout le refresh.
      }

      if (mounted) {
        setState(() {
          pendingPayments = fetchedPending;
          hasPendingPayments = pendingPayments.isNotEmpty;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                hasPendingPayments
                    ? "✅ ${pendingPayments.length} paiement(s) en attente de validation"
                    : "✅ Données récupérées du serveur",
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("⚠️ Impossible de recharger les données générales (mot de passe ou code école ?)"),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Erreur de connexion"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isRefreshing = false);
    }
  }

  // ==================== OUVRIR LA VALIDATION MANUELLE ====================
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
                title: Text("${p['nom']} ${p['postNom'] ?? ''} ${p['prenom']}"),
                subtitle: Text(
                  "${p['mois']} - ${p['amount']} FC\n"
                      "Section: ${p['section'] ?? ''} | Classe: ${p['classe'] ?? ''}",
                ),
                trailing: const Icon(Icons.check_circle, color: Colors.green),
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

  // ==================== VALIDATION RÉELLE CÔTÉ SERVEUR ====================
  Future<void> _validateAllPayments() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Code école manquant"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => isValidating = true);

    try {
      final ids = pendingPayments.map((p) => p['id']).toList();

      final response = await http.post(
        Uri.parse('https://jsinf.onrender.com/validate_payments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': appState.schoolCode,
          'payment_ids': ids,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // On recharge les données fraîches (avec les paiements maintenant validés)
        bool success = await widget.fraisScolaires.restoreFromServer(
          appState.schoolCode!,
          appState.backupPassword!,
        );

        if (success && mounted) {
          await widget.fraisScolaires.saveData();

          setState(() {
            hasPendingPayments = false;
            pendingPayments.clear();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Tous les paiements ont été validés et enregistrés !"),
              backgroundColor: Colors.green,
            ),
          );

          // Rafraîchissement global de l'état local de l'app
          await widget.fraisScolaires.loadData();
          if (mounted) setState(() {});
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de la validation"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => isValidating = false);
    }
  }

  Future<void> _generateKey() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (selectedSectionForKey == null) return;

    if (appState.schoolCode == null || appState.schoolCode!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Définissez d'abord le Code École"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => isGeneratingKey = true);
    try {
      final response = await http.post(
        Uri.parse('https://jsinf.onrender.com/generate_key'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': appState.schoolCode,
          'section': selectedSectionForKey,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          generatedKeys.add({'key': data['key'], 'section': data['section']});
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("✅ Clé générée pour ${data['section']}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Pas de connexion internet"), backgroundColor: Colors.red),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
              // Génération de Clé
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Générer une Clé d'Accès", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text("Choisir la Section"),
                        value: selectedSectionForKey,
                        items: widget.fraisScolaires.config.sections
                            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (val) => setState(() => selectedSectionForKey = val),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: isGeneratingKey
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.key),
                        label: Text(isGeneratingKey ? "Génération en cours..." : "Générer Clé pour cette Section"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: (selectedSectionForKey == null || isGeneratingKey) ? null : _generateKey,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text("Clés Générées", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...generatedKeys.map((keyData) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.key, color: Colors.amber),
                  title: Text(keyData['key']),
                  subtitle: Text("Section : ${keyData['section']}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: keyData['key']));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Clé copiée")));
                    },
                  ),
                ),
              )),
              const SizedBox(height: 30),

              // Bouton de validation manuelle
              if (hasPendingPayments)
                ElevatedButton.icon(
                  icon: isValidating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.visibility),
                  label: Text(isValidating
                      ? "Validation en cours..."
                      : "Voir & Valider Paiements en Attente (${pendingPayments.length})"),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: isValidating ? null : _showPendingPaymentsDialog,
                )
              else
                ElevatedButton.icon(
                  icon: isRefreshing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh),
                  label: Text(isRefreshing ? "Rafraîchissement..." : "Rafraîchir les Données"),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: Colors.teal,
                  ),
                  onPressed: isRefreshing ? null : _refreshData,
                ),
              const SizedBox(height: 30),

              const Text("Utilisateurs Connectés", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...connectedUsers.map((user) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: Text(user),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeUser(user),
                  ),
                ),
              )),
              const SizedBox(height: 30),

              const Text("Paiements en Attente de Validation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    hasPendingPayments
                        ? "${pendingPayments.length} paiement(s) envoyé(s) par les caissiers sont en attente.\n\n"
                        "Utilisez le bouton ci-dessus pour les voir et les valider."
                        : "Les paiements des caissiers sont envoyés au serveur.\n\n"
                        "Utilisez le bouton ci-dessus pour les voir et les valider manuellement.",
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