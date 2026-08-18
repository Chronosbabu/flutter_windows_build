import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

/// ⚡⚡ NOUVEAU — Écran "Autres Frais" pour un sous-utilisateur (clé AFR).
/// Contrairement à AutresFraisScreen (admin, écrit directement via
/// FraisScolaires.payAutreFrais), chaque paiement est envoyé au serveur
/// via /school/submit_autre_frais_payment et reste EN ATTENTE tant que
/// l'admin ne l'a pas validé (POST /school/validate_autres_frais_payments)
/// — exactement la même règle que pour les frais mensuels (clé PAY).
///
/// ⚠️ Hypothèse sur le format JSON d'un "AutreFrais" renvoyé par
/// /school/get_autres_frais : clés 'id', 'nom', 'montant', 'scope',
/// 'section', 'classe' (déduit du modèle AutreFrais utilisé par
/// AutresFraisScreen côté admin). À vérifier avec models.dart réel.
class SubUserAutresFraisScreen extends StatefulWidget {
  final String schoolCode;
  final String schoolName;
  final String assignedSection;
  final String? assignedClasse;
  final String? initialYear;

  const SubUserAutresFraisScreen({
    super.key,
    required this.schoolCode,
    required this.schoolName,
    required this.assignedSection,
    this.assignedClasse,
    this.initialYear,
  });

  @override
  State<SubUserAutresFraisScreen> createState() =>
      _SubUserAutresFraisScreenState();
}

class _SubUserAutresFraisScreenState extends State<SubUserAutresFraisScreen> {
  final searchController = TextEditingController();
  final agentNameController = TextEditingController();

  late String currentYear;
  bool isLoading = true;
  bool isProcessing = false;

  List<Map<String, dynamic>> autresFraisList = [];
  Map<String, dynamic>? selectedFrais;
  List<Map<String, dynamic>> eleves = [];

  // eleve_id -> Set des autre_frais_id déjà validés (payé, confirmé serveur)
  final Map<String, Set<String>> paidMap = {};
  // "eleve_id|autre_frais_id" envoyés mais pas encore validés par l'admin
  final Set<String> pendingKeys = {};

  List<Map<String, dynamic>> offlineQueue = [];
  static const _kOfflineQueueKey = 'sub_offline_autres_frais';
  static const _kAgentNameKey = 'sub_agent_name';

  @override
  void initState() {
    super.initState();
    currentYear = widget.initialYear ?? '2025-2026';
    searchController.addListener(() => setState(() {}));
    _bootstrap();
  }

  @override
  void dispose() {
    searchController.dispose();
    agentNameController.dispose();
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
        for (final p in offlineQueue) {
          pendingKeys.add("${p['eleve_id']}|${p['autre_frais_id']}");
        }
      } catch (_) {
        offlineQueue = [];
      }
    }

    await _fetchData();
    await _flushOfflineQueue(silent: true);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchData() async {
    // 1) Élèves + paiements déjà validés (via /restore : données complètes
    //    de l'école, incluant autresFraisPaiementsByYear).
    Map<String, dynamic>? data;
    try {
      final restoreResp = await http
          .get(Uri.parse('$serverUrl/restore?school_code=${widget.schoolCode}'))
          .timeout(const Duration(seconds: 15));
      if (restoreResp.statusCode == 200) {
        data = json.decode(restoreResp.body) as Map<String, dynamic>;
        await LocalStorageHelper.saveCachedServerData(data);
      }
    } catch (_) {}
    data ??= await LocalStorageHelper.getCachedServerData();
    if (data != null) _applyRestoreData(data);

    // 2) Liste des "autres frais" définis par l'admin
    try {
      final response = await http
          .get(Uri.parse(
          '$serverUrl/school/get_autres_frais?school_code=${widget.schoolCode}'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        final list = (result['autres_frais'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (mounted) {
          setState(() {
            autresFraisList = list;
            selectedFrais ??= list.isNotEmpty ? list.first : null;
          });
        }
      }
    } catch (_) {}
  }

  void _applyRestoreData(Map<String, dynamic> data) {
    final fetchedYear = data['currentYear']?.toString();
    if (fetchedYear != null && fetchedYear.isNotEmpty) currentYear = fetchedYear;

    final rawList = (data['history']?[currentYear]?['eleves'] ?? []) as List;
    final filtered = rawList
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['section'] == widget.assignedSection)
        .where((e) =>
    widget.assignedClasse == null || e['classe'] == widget.assignedClasse)
        .toList();

    paidMap.clear();
    final paiements =
    (data['autresFraisPaiementsByYear']?[currentYear] ?? []) as List;
    for (final p in paiements) {
      final eid = p['eleveId']?.toString();
      final fid = p['autreFraisId']?.toString();
      if (eid == null || fid == null) continue;
      paidMap.putIfAbsent(eid, () => {}).add(fid);
      pendingKeys.remove("$eid|$fid");
    }

    if (mounted) setState(() => eleves = filtered);
  }

  Future<void> _saveAgentName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgentNameKey, agentNameController.text.trim());
  }

  Future<void> _saveOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOfflineQueueKey, jsonEncode(offlineQueue));
  }

  String _scopeLabel(Map<String, dynamic> f) {
    switch (f['scope']) {
      case 'section':
        return f['section']?.toString() ?? 'Section';
      case 'classe':
        return f['classe']?.toString() ?? 'Classe';
      default:
        return 'Toutes les classes';
    }
  }

  bool _isEligible(Map<String, dynamic> eleve, Map<String, dynamic> frais) {
    final scope = frais['scope'];
    if (scope == 'section') return eleve['section'] == frais['section'];
    if (scope == 'classe') return eleve['classe'] == frais['classe'];
    return true;
  }

  List<Map<String, dynamic>> get _eligibleFiltered {
    if (selectedFrais == null) return [];
    final query = searchController.text.toLowerCase().trim();
    final eligible = eleves.where((e) => _isEligible(e, selectedFrais!)).toList();
    if (query.isEmpty) return eligible;
    return eligible.where((e) {
      final id = (e['id'] ?? '').toString().toLowerCase();
      final name = "${e['nom']} ${e['postNom']} ${e['prenom']}".toLowerCase();
      return id.contains(query) || name.contains(query);
    }).toList();
  }

  bool _hasPaid(Map<String, dynamic> eleve, Map<String, dynamic> frais) {
    final eid = eleve['id']?.toString() ?? '';
    final fid = frais['id']?.toString() ?? '';
    return paidMap[eid]?.contains(fid) ?? false;
  }

  bool _isPending(Map<String, dynamic> eleve, Map<String, dynamic> frais) {
    final eid = eleve['id']?.toString() ?? '';
    final fid = frais['id']?.toString() ?? '';
    return pendingKeys.contains("$eid|$fid");
  }

  Future<bool> _trySubmit(Map<String, dynamic> payload) async {
    try {
      final response = await http
          .post(
        Uri.parse('$serverUrl/school/submit_autre_frais_payment'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _payerUnSeul(Map<String, dynamic> eleve) async {
    if (selectedFrais == null) return;
    if (_hasPaid(eleve, selectedFrais!) || _isPending(eleve, selectedFrais!)) {
      return;
    }

    await _saveAgentName();
    setState(() => isProcessing = true);

    final frais = selectedFrais!;
    final payload = {
      'school_code': widget.schoolCode,
      'annee': currentYear,
      'eleve_id': eleve['id'],
      'autre_frais_id': frais['id'],
      'montant': frais['montant'],
      'enregistre_par': agentNameController.text.trim().isEmpty
          ? 'Agent'
          : agentNameController.text.trim(),
    };

    final eid = eleve['id']?.toString() ?? '';
    final fid = frais['id']?.toString() ?? '';
    final key = "$eid|$fid";

    final ok = await _trySubmit(payload);
    setState(() {
      pendingKeys.add(key);
      isProcessing = false;
    });

    if (!ok) {
      offlineQueue.add(payload);
      await _saveOfflineQueue();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Hors ligne : paiement enregistré localement, sera envoyé plus tard"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "✅ ${frais['nom']} envoyé pour ${eleve['nom']} ${eleve['prenom']}, en attente de validation"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _confirmPaiementUnique(Map<String, dynamic> eleve) {
    if (selectedFrais == null) return;
    final frais = selectedFrais!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(frais['nom']?.toString() ?? 'Frais'),
        content: Text(
          "Confirmer le paiement de "
              "${(frais['montant'] as num?)?.toStringAsFixed(0) ?? '?'} FC "
              "pour ${eleve['nom']} ${eleve['prenom']} (${eleve['classe']}) ?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _payerUnSeul(eleve);
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
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
              content: Text("✅ $sentCount paiement(s) en attente envoyé(s)")),
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
        title: Text("Autres Frais - $titleSuffix"),
        backgroundColor: Colors.indigo,
        actions: [
          if (offlineQueue.isNotEmpty)
            IconButton(
              icon: _queueIcon(),
              tooltip: "Renvoyer les paiements en attente",
              onPressed: () => _flushOfflineQueue(),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => isLoading = true);
              await _fetchData();
              if (mounted) setState(() => isLoading = false);
            },
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
          : autresFraisList.isEmpty
          ? _buildEmptyState()
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: selectedFrais,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Type de frais",
                    border: OutlineInputBorder(),
                  ),
                  items: autresFraisList
                      .map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(
                      "${f['nom']} — "
                          "${(f['montant'] as num?)?.toStringAsFixed(0) ?? '?'} FC "
                          "(${_scopeLabel(f)})",
                    ),
                  ))
                      .toList(),
                  onChanged: (v) => setState(() => selectedFrais = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: "Rechercher par ID ou Nom",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          if (selectedFrais != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "${_eligibleFiltered.length} élève(s) concerné(s) dans votre périmètre",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
          Expanded(
            child: selectedFrais == null
                ? const Center(child: Text("Sélectionnez un type de frais"))
                : ListView.builder(
              itemCount: _eligibleFiltered.length,
              itemBuilder: (context, index) {
                final eleve = _eligibleFiltered[index];
                final frais = selectedFrais!;
                final paid = _hasPaid(eleve, frais);
                final pending = !paid && _isPending(eleve, frais);
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  color: paid
                      ? Colors.green.withAlpha(20)
                      : pending
                      ? Colors.orange.withAlpha(20)
                      : null,
                  child: ListTile(
                    leading: paid
                        ? const Icon(Icons.check_circle,
                        color: Colors.green)
                        : pending
                        ? const Icon(Icons.hourglass_top,
                        color: Colors.orange)
                        : const Icon(Icons.radio_button_unchecked),
                    title: Text(
                        '${eleve['nom']} ${eleve['postNom']} ${eleve['prenom']}'),
                    subtitle: Text(
                      'ID: ${eleve['id']} | Classe: ${eleve['classe']} (${eleve['section']})',
                    ),
                    trailing: paid
                        ? const Text("Payé",
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold))
                        : pending
                        ? const Text("En attente",
                        style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold))
                        : IconButton(
                      icon: const Icon(Icons.payment,
                          color: Colors.indigo),
                      onPressed: isProcessing
                          ? null
                          : () => _confirmPaiementUnique(eleve),
                    ),
                    onTap: (paid || pending || isProcessing)
                        ? null
                        : () => _confirmPaiementUnique(eleve),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.receipt_long, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "Aucun frais additionnel défini pour le moment.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              "Contactez l'admin : les \"Autres Frais\" se configurent depuis "
                  "l'Admin Dashboard.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}