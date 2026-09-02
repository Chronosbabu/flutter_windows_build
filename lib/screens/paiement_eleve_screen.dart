import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../frais_scolaires.dart';
import '../models.dart';

class PaiementEleveScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const PaiementEleveScreen({super.key, required this.fraisScolaires});

  @override
  State<PaiementEleveScreen> createState() => _PaiementEleveScreenState();
}

class _PaiementEleveScreenState extends State<PaiementEleveScreen> {
  final searchController = TextEditingController();
  String? selectedClassFilter;
  String? selectedSectionFilter;
  List<Eleve> filtered = [];

  // ⚡ Badge Mobile Money
  int _mobilePendingCount = 0;
  List<Map<String, dynamic>> _mobilePendingPayments = [];
  bool _loadingMobile = false;

  // ==========================================================================
  // MODE ADMINISTRATEUR CACHÉ
  // ==========================================================================
  int _secretTapCount = 0;
  DateTime? _lastSecretTap;
  bool _adminModeUnlocked = false;
  Timer? _adminAutoLockTimer;

  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  @override
  void initState() {
    super.initState();
    selectedSectionFilter = widget.fraisScolaires.lastSelectedSectionFilter;
    selectedClassFilter = widget.fraisScolaires.lastSelectedClassFilter;
    _filterEleves();
    searchController.addListener(_filterEleves);
    // Vérifier les paiements mobile en attente
    _fetchMobilePendingPayments();
    // ⚡ NOUVEAU — vide la file d'attente des reçus non encore imprimés à
    // l'ouverture de cet écran de paiement (voir
    // FraisScolaires.flushReceiptQueue). Fonctionne même après un
    // redémarrage complet de l'application ou de l'ordinateur, puisque
    // cette file est persistée dans le fichier JSON local.
    _flushPendingReceipts();
  }

  // ⚡ NOUVEAU
  Future<void> _flushPendingReceipts() async {
    final count = await widget.fraisScolaires.flushReceiptQueue();
    if (mounted && count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "🖨️ $count reçu(s) en attente ont été imprimés automatiquement."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ==================== BADGE MOBILE MONEY ====================
  Future<void> _fetchMobilePendingPayments() async {
    final schoolCode = widget.fraisScolaires.schoolCode;
    if (schoolCode == null || schoolCode.isEmpty) return;

    setState(() => _loadingMobile = true);
    try {
      final response = await http.get(
        Uri.parse(
            'https://jsinf.onrender.com/get_mobile_payments?school_code=$schoolCode'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['mobile_payments'] as List? ?? []);
        if (mounted) {
          setState(() {
            _mobilePendingCount = list.length;
            _mobilePendingPayments = list
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          });
        }
      }
    } catch (_) {
      // Silencieux — le badge reste à 0 si pas de connexion
    } finally {
      if (mounted) setState(() => _loadingMobile = false);
    }
  }

  void _showMobilePaymentsDialog() {
    if (_mobilePendingPayments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucun paiement mobile en attente")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            "Paiements Mobile Money (${_mobilePendingPayments.length})"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _mobilePendingPayments.length,
            itemBuilder: (context, index) {
              final p = _mobilePendingPayments[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(
                      _networkIcon(p['network']?.toString() ?? ''),
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(
                      "${p['nom']} ${p['postNom'] ?? ''} ${p['prenom']}"),
                  subtitle: Text(
                    "${p['mois']} — ${(p['amount'] as num?)?.toStringAsFixed(0) ?? '0'} FC\n"
                        "Réseau: ${p['network'] ?? '—'} • ${p['date'] ?? ''}",
                  ),
                  trailing: const Icon(Icons.phone_android,
                      color: Colors.green),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle),
            label: Text(
                "Confirmer tout (${_mobilePendingPayments.length})"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _confirmAllMobilePayments();
            },
          ),
        ],
      ),
    );
  }

  IconData _networkIcon(String network) {
    switch (network.toLowerCase()) {
      case 'airtel':
        return Icons.signal_cellular_alt;
      case 'orange':
        return Icons.signal_cellular_4_bar;
      case 'vodacom':
      case 'mpesa':
        return Icons.mobile_screen_share;
      default:
        return Icons.phone_android;
    }
  }

  Future<void> _confirmAllMobilePayments() async {
    final schoolCode = widget.fraisScolaires.schoolCode;
    if (schoolCode == null || schoolCode.isEmpty) return;

    setState(() => _loadingMobile = true);
    try {
      final ids =
      _mobilePendingPayments.map((p) => p['id']).toList();
      final response = await http.post(
        Uri.parse('https://jsinf.onrender.com/confirm_mobile_payments'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCode,
          'payment_ids': ids,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final appState = Provider.of<AppState>(context, listen: false);
        if (appState.backupPassword != null) {
          await widget.fraisScolaires.restoreFromServer(
              schoolCode, appState.backupPassword!);
          await widget.fraisScolaires.saveData();
        }

        if (mounted) {
          setState(() {
            _mobilePendingCount = 0;
            _mobilePendingPayments = [];
          });
          _filterEleves();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Paiements mobile confirmés et enregistrés !"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Erreur lors de la confirmation"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur de connexion"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMobile = false);
    }
  }

  // ==========================================================================
  // DÉCLENCHEUR SECRET (triple-tap sur le titre de l'AppBar)
  // ==========================================================================
  void _handleSecretTap() {
    final now = DateTime.now();
    if (_lastSecretTap == null ||
        now.difference(_lastSecretTap!) > const Duration(milliseconds: 700)) {
      _secretTapCount = 0;
    }
    _lastSecretTap = now;
    _secretTapCount++;

    if (_secretTapCount >= 3) {
      _secretTapCount = 0;
      _onSecretTriggered();
    }
  }

  void _onSecretTriggered() {
    if (_adminModeUnlocked) {
      return;
    }
    if (widget.fraisScolaires.hiddenCodeIsConfigured) {
      _showEnterHiddenCodeDialog();
    } else {
      _showSetupHiddenCodeDialog();
    }
  }

  void _showSetupHiddenCodeDialog() {
    final codeController = TextEditingController();
    final confirmController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Configuration — Code masqué"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Définissez un code secret, différent du mot de passe "
                    "de sauvegarde. Ce code sera nécessaire pour annuler "
                    "ou modifier un paiement déjà enregistré. "
                    "Ne le partagez avec personne.",
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: codeController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Nouveau code masqué",
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Confirmer le code",
                ),
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler"),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = codeController.text.trim();
                final confirm = confirmController.text.trim();
                if (code.length < 4) {
                  setStateDialog(() =>
                  errorText = "Le code doit contenir au moins 4 caractères.");
                  return;
                }
                if (code != confirm) {
                  setStateDialog(
                          () => errorText = "Les deux codes ne correspondent pas.");
                  return;
                }
                await widget.fraisScolaires.setHiddenCode(code);
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() => _adminModeUnlocked = true);
                  _startAdminAutoLockTimer();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          "Code masqué défini. Gardez-le secret — mode "
                              "administrateur actif pour cette session."),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text("Définir"),
            ),
          ],
        ),
      ),
    );
  }

  void _showEnterHiddenCodeDialog() {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      final remaining = _lockedUntil!.difference(DateTime.now()).inSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Trop de tentatives. Réessayez dans ${remaining}s."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final codeController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Code masqué"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(labelText: "Code"),
                onSubmitted: (_) {},
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler"),
            ),
            ElevatedButton(
              onPressed: () {
                final ok = widget.fraisScolaires
                    .verifyHiddenCode(codeController.text);
                if (ok) {
                  _failedAttempts = 0;
                  _lockedUntil = null;
                  Navigator.pop(ctx);
                  setState(() => _adminModeUnlocked = true);
                  _startAdminAutoLockTimer();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Mode administrateur activé pour cette session."),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  _failedAttempts++;
                  if (_failedAttempts >= 5) {
                    _lockedUntil =
                        DateTime.now().add(const Duration(seconds: 60));
                    _failedAttempts = 0;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            "Trop de tentatives incorrectes. Blocage de 60 secondes."),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    setStateDialog(() => errorText = "Code incorrect.");
                  }
                }
              },
              child: const Text("Valider"),
            ),
          ],
        ),
      ),
    );
  }

  void _startAdminAutoLockTimer() {
    _adminAutoLockTimer?.cancel();
    _adminAutoLockTimer = Timer(const Duration(minutes: 10), () {
      if (mounted) setState(() => _adminModeUnlocked = false);
    });
  }

  Future<void> _syncAfterAdminChange() async {
    final schoolCode = widget.fraisScolaires.schoolCode;
    if (schoolCode == null || schoolCode.isEmpty) return;
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.backupPassword == null) return;
    try {
      await widget.fraisScolaires
          .backupToServer(schoolCode, appState.backupPassword!);
    } catch (_) {
      // Silencieux
    }
  }

  void _showAdminTransactionOptions(
      Eleve eleve, Map<String, dynamic> transaction, String mois) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Modifier ce paiement"),
              onTap: () {
                Navigator.pop(ctx);
                _showModifyTransactionDialog(eleve, transaction, mois);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Annuler ce paiement"),
              onTap: () {
                Navigator.pop(ctx);
                _confirmCancelTransaction(eleve, transaction, mois);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmCancelTransaction(
      Eleve eleve, Map<String, dynamic> transaction, String mois) {
    final montant = (transaction['amount'] as num?)?.toDouble() ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer l'annulation"),
        content: Text(
          "Annuler ce paiement de ${montant.toStringAsFixed(0)} FC "
              "pour \"$mois\" ?\n\nCette action modifiera directement les "
              "données de l'élève et sera synchronisée avec le serveur.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Non"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.fraisScolaires
                  .cancelTransaction(eleve: eleve, transaction: transaction);
              await _syncAfterAdminChange();
              if (mounted) {
                _filterEleves();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Paiement annulé."),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text("Oui, annuler"),
          ),
        ],
      ),
    );
  }

  void _showModifyTransactionDialog(
      Eleve eleve, Map<String, dynamic> transaction, String mois) {
    final currentAmount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final controller =
    TextEditingController(text: currentAmount.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Modifier le paiement — $mois"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Nouveau montant (FC)"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newAmount = double.tryParse(controller.text);
              if (newAmount == null || newAmount < 0) return;
              Navigator.pop(ctx);
              await widget.fraisScolaires.modifyTransactionAmount(
                eleve: eleve,
                transaction: transaction,
                newAmount: newAmount,
              );
              await _syncAfterAdminChange();
              if (mounted) {
                _filterEleves();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Paiement modifié."),
                    backgroundColor: Colors.blue,
                  ),
                );
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  // ==================== FILTRE ====================
  void _filterEleves() {
    final query = searchController.text.toLowerCase().trim();
    setState(() {
      filtered = widget.fraisScolaires.currentData.eleves.where((e) {
        final idMatch = e.id.toLowerCase().contains(query);
        final nameMatch =
        '${e.nom} ${e.postNom} ${e.prenom}'.toLowerCase().contains(query);
        final classMatch =
            selectedClassFilter == null || e.classe == selectedClassFilter;
        final sectionMatch = selectedSectionFilter == null ||
            e.section == selectedSectionFilter;
        return (idMatch || nameMatch) && classMatch && sectionMatch;
      }).toList();
    });
  }

  @override
  void dispose() {
    widget.fraisScolaires.lastSelectedClassFilter = selectedClassFilter;
    widget.fraisScolaires.lastSelectedSectionFilter = selectedSectionFilter;
    widget.fraisScolaires.saveData();
    searchController.dispose();
    _adminAutoLockTimer?.cancel();
    super.dispose();
  }

  String? _extractClasseNumero(String classeComplete) {
    final parts = classeComplete.trim().split(' ');
    return parts.isNotEmpty && parts.first.isNotEmpty ? parts.first : null;
  }

  String? _extractSousClasse(String classeComplete) {
    final parts = classeComplete.trim().split(' ');
    if (parts.length > 1) {
      final rest = parts.sublist(1).join(' ').trim();
      return rest.isEmpty ? null : rest;
    }
    return null;
  }

  // ==========================================================================
  // PAIEMENT SÉQUENTIEL DES MOIS
  // ==========================================================================
  String? _premierMoisNonPaye(Eleve eleve) {
    for (final m in widget.fraisScolaires.months) {
      final required = widget.fraisScolaires
          .getRequiredForMonth(m, eleve.section, eleve.classe);
      final paid = eleve.paid[m] ?? 0;
      if (paid < required) return m;
    }
    return null;
  }

  bool _peutPayerCeMois(Eleve eleve, String mois) {
    final premierNonPaye = _premierMoisNonPaye(eleve);
    if (premierNonPaye == null) return false;
    return mois == premierNonPaye;
  }

  void _showEditStudentDialog(Eleve eleve) {
    final nomController = TextEditingController(text: eleve.nom);
    final postNomController = TextEditingController(text: eleve.postNom);
    final prenomController = TextEditingController(text: eleve.prenom);
    String? selectedSectionEdit = eleve.section;
    String? selectedClasseNumeroEdit = _extractClasseNumero(eleve.classe);
    String? selectedSousClasseEdit = _extractSousClasse(eleve.classe);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final sectionsOptions =
          List<String>.from(widget.fraisScolaires.config.sections);
          if (selectedSectionEdit != null &&
              !sectionsOptions.contains(selectedSectionEdit)) {
            sectionsOptions.add(selectedSectionEdit!);
          }
          final classesNumeros = selectedSectionEdit != null
              ? List<String>.from(widget.fraisScolaires
              .getClassesForSection(selectedSectionEdit!))
              : <String>[];
          if (selectedClasseNumeroEdit != null &&
              !classesNumeros.contains(selectedClasseNumeroEdit)) {
            classesNumeros.add(selectedClasseNumeroEdit!);
          }
          final sousClasses = (selectedSectionEdit != null &&
              selectedClasseNumeroEdit != null)
              ? List<String>.from(widget.fraisScolaires.getSubClassesFor(
              selectedSectionEdit!, selectedClasseNumeroEdit!))
              : <String>[];
          if (selectedSousClasseEdit != null &&
              !sousClasses.contains(selectedSousClasseEdit)) {
            sousClasses.add(selectedSousClasseEdit!);
          }

          return AlertDialog(
            title: const Text("Modifier l'élève"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("ID: ${eleve.id}",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: nomController,
                      decoration: const InputDecoration(labelText: "Nom")),
                  TextField(
                      controller: postNomController,
                      decoration:
                      const InputDecoration(labelText: "Post-nom")),
                  TextField(
                      controller: prenomController,
                      decoration:
                      const InputDecoration(labelText: "Prénom")),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: selectedSectionEdit,
                    decoration:
                    const InputDecoration(labelText: "Section"),
                    items: sectionsOptions
                        .map((s) =>
                        DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedSectionEdit = value;
                        selectedClasseNumeroEdit = null;
                        selectedSousClasseEdit = null;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedClasseNumeroEdit,
                    decoration: const InputDecoration(
                        labelText: "Numéro de classe"),
                    items: classesNumeros
                        .map((c) =>
                        DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) {
                      setStateDialog(() {
                        selectedClasseNumeroEdit = value;
                        selectedSousClasseEdit = null;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedSousClasseEdit,
                    decoration: const InputDecoration(
                        labelText: "Sous-classe (optionnel)",
                        helperText: "Ex: A, B, C..."),
                    items: sousClasses
                        .map((s) =>
                        DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) {
                      setStateDialog(
                              () => selectedSousClasseEdit = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Annuler")),
              ElevatedButton(
                onPressed: () async {
                  if (nomController.text.trim().isNotEmpty &&
                      postNomController.text.trim().isNotEmpty &&
                      selectedClasseNumeroEdit != null &&
                      selectedSectionEdit != null) {
                    // ==========================================================
                    // ⚡ NOUVEAU — UNICITÉ STRICTE NOM + POST-NOM + PRÉNOM,
                    // vérifiée aussi lors d'une MODIFICATION (et pas
                    // seulement à la création). `excludeId` permet de ne
                    // jamais comparer l'élève à lui-même.
                    // ==========================================================
                    final duplicateEleve =
                    widget.fraisScolaires.findDuplicateFullName(
                      nom: nomController.text.trim(),
                      postNom: postNomController.text.trim(),
                      prenom: prenomController.text.trim(),
                      excludeId: eleve.id,
                    );
                    if (duplicateEleve != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "⚠️ Un autre élève (${duplicateEleve.classe} - "
                                "ID: ${duplicateEleve.id}) a déjà exactement "
                                "ce Nom, Post-nom et Prénom. Modifiez au "
                                "moins un des trois champs pour continuer.",
                          ),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                      return;
                    }

                    eleve.nom = nomController.text.trim();
                    eleve.postNom = postNomController.text.trim();
                    eleve.prenom = prenomController.text.trim();
                    eleve.classe =
                        widget.fraisScolaires.buildFullClasseName(
                          selectedClasseNumeroEdit!,
                          selectedSousClasseEdit,
                        );
                    eleve.section = selectedSectionEdit!;
                    await widget.fraisScolaires.saveData();
                    _filterEleves();
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text("Élève modifié avec succès")),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "Veuillez remplir tous les champs obligatoires")),
                    );
                  }
                },
                child: const Text("Enregistrer"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classFilterOptions = selectedSectionFilter != null
        ? List<String>.from(widget.fraisScolaires
        .getAllDisplayClassesForSection(selectedSectionFilter!))
        : List<String>.from(widget.fraisScolaires.getAllDisplayClasses());
    if (selectedClassFilter != null &&
        !classFilterOptions.contains(selectedClassFilter)) {
      classFilterOptions.add(selectedClassFilter!);
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleSecretTap,
          behavior: HitTestBehavior.opaque,
          child: const Text("Paiements des Élèves"),
        ),
        actions: [
          GestureDetector(
            onTap: _showMobilePaymentsDialog,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: _loadingMobile
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                        : const Icon(Icons.phone_android),
                    tooltip: "Paiements Mobile Money en attente",
                    onPressed: _showMobilePaymentsDialog,
                  ),
                  if (_mobilePendingCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 18, minHeight: 18),
                        child: Text(
                          '$_mobilePendingCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Rafraîchir les paiements mobile",
            onPressed: _fetchMobilePendingPayments,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: "Rechercher par ID ou Nom",
                    prefixIcon: Icon(Icons.search),
                    hintText: "Ex: BB26B10 ou BARAKA",
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        hint: const Text("Toutes les sections"),
                        value: selectedSectionFilter,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                              value: null,
                              child: Text("Toutes les sections")),
                          ...widget.fraisScolaires.config.sections.map(
                                  (s) => DropdownMenuItem(
                                  value: s, child: Text(s))),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedSectionFilter = value;
                            final validClasses = value != null
                                ? widget.fraisScolaires
                                .getAllDisplayClassesForSection(value)
                                : widget.fraisScolaires
                                .getAllDisplayClasses();
                            if (selectedClassFilter != null &&
                                !validClasses
                                    .contains(selectedClassFilter)) {
                              selectedClassFilter = null;
                            }
                            _filterEleves();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButton<String>(
                        hint: const Text("Toutes les classes"),
                        value: selectedClassFilter,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                              value: null,
                              child: Text("Toutes les classes")),
                          ...classFilterOptions.map((c) =>
                              DropdownMenuItem(value: c, child: Text(c))),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedClassFilter = value;
                            _filterEleves();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final eleve = filtered[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        eleve.id.isNotEmpty
                            ? eleve.id.substring(0, 2)
                            : "?",
                      ),
                    ),
                    title: Text(
                        '${eleve.nom} ${eleve.postNom} ${eleve.prenom}'),
                    subtitle: Text(
                      'ID: ${eleve.id}\n'
                          'Classe: ${eleve.classe} | Section: ${eleve.section}\n'
                          'Total payé: ${widget.fraisScolaires.getStudentTotalPaid(eleve)} FC',
                    ),
                    // ⚡ CORRIGÉ — le bouton de réimpression manuelle a été
                    // retiré (sur demande de la direction). Seule
                    // l'impression automatique, juste après un paiement,
                    // reste possible.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditStudentDialog(eleve),
                        ),
                        const Icon(Icons.arrow_forward_ios),
                      ],
                    ),
                    onTap: () => _showMonthsDialog(context, eleve),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showMonthsDialog(BuildContext context, Eleve eleve) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(
              '${eleve.nom} ${eleve.prenom} - ${eleve.classe} (${eleve.section})'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: ListView.builder(
              itemCount: widget.fraisScolaires.months.length,
              itemBuilder: (context, i) {
                final mois = widget.fraisScolaires.months[i];
                final required = widget.fraisScolaires
                    .getRequiredForMonth(mois, eleve.section, eleve.classe);
                final paid = eleve.paid[mois] ?? 0;
                final isFullyPaid = paid >= required;
                final estOuvert =
                    isFullyPaid || _peutPayerCeMois(eleve, mois);
                final nbPaiements = eleve.transactions
                    .where((t) => t['mois'] == mois)
                    .length;
                return ListTile(
                  title: Text(mois),
                  subtitle: Text(
                    'Requis: $required FC | Payé: $paid FC'
                        '${nbPaiements > 0 ? ' • $nbPaiements paiement(s)' : ''}'
                        '${!isFullyPaid && !estOuvert ? '\nSoldez d\'abord les mois précédents' : ''}',
                    style: (!isFullyPaid && !estOuvert)
                        ? const TextStyle(
                        color: Colors.grey, fontStyle: FontStyle.italic)
                        : null,
                  ),
                  trailing: isFullyPaid
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : (estOuvert
                      ? const Icon(Icons.warning, color: Colors.orange)
                      : const Icon(Icons.lock_outline, color: Colors.grey)),
                  onTap: () async {
                    await _showMonthDetailDialog(context, eleve, mois);
                    setStateDialog(() {});
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fermer")),
          ],
        ),
      ),
    );
  }

  Future<void> _showMonthDetailDialog(
      BuildContext context, Eleve eleve, String mois) async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final required = widget.fraisScolaires
              .getRequiredForMonth(mois, eleve.section, eleve.classe);
          final paid = eleve.paid[mois] ?? 0;
          final isFullyPaid = paid >= required;
          final peutPayer = !isFullyPaid && _peutPayerCeMois(eleve, mois);
          final premierNonPaye = _premierMoisNonPaye(eleve);
          final historique = eleve.transactions
              .where((t) => t['mois'] == mois)
              .toList()
            ..sort((a, b) => (a['date'] ?? '')
                .toString()
                .compareTo((b['date'] ?? '').toString()));

          return AlertDialog(
            title: Text("$mois - ${eleve.nom} ${eleve.prenom}"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Requis : ${required.toStringAsFixed(0)} FC\n"
                        "Déjà payé : ${paid.toStringAsFixed(0)} FC",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (!isFullyPaid && !peutPayer && premierNonPaye != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lock_outline,
                                color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Ce mois ne peut pas encore être payé. "
                                    "Vous devez d'abord solder entièrement "
                                    "\"$premierNonPaye\".",
                                style: const TextStyle(
                                    color: Colors.deepOrange,
                                    fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text("Historique des paiements :",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (historique.isEmpty)
                    const Text("Aucun paiement enregistré pour ce mois.",
                        style: TextStyle(color: Colors.grey))
                  else
                    ConstrainedBox(
                      constraints:
                      const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: historique.length,
                        itemBuilder: (context, i) {
                          final t = historique[i];
                          final montant =
                              (t['amount'] as num?)?.toDouble() ?? 0;
                          final date = t['date']?.toString() ??
                              "Date inconnue";
                          final isFromParent =
                              t['from_parent'] == true;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              isFromParent
                                  ? Icons.phone_android
                                  : Icons.receipt_long,
                              size: 20,
                              color: isFromParent
                                  ? Colors.green
                                  : Colors.indigo,
                            ),
                            title: Text(date),
                            subtitle: isFromParent
                                ? Text(
                              "Via ${t['network'] ?? 'Mobile Money'}",
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.green),
                            )
                                : null,
                            // ⚡ CORRIGÉ — le bouton de réimpression
                            // manuelle par paiement a été retiré (sur
                            // demande de la direction) : seul le montant
                            // reste affiché.
                            trailing: Text(
                              "${montant.toStringAsFixed(0)} FC",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            onTap: _adminModeUnlocked
                                ? () {
                              Navigator.pop(ctx);
                              _showAdminTransactionOptions(
                                  eleve, t, mois);
                            }
                                : null,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fermer")),
              if (peutPayer)
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text("Ajouter un paiement"),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showPaymentDialog(context, eleve, mois);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  void _showPaymentDialog(
      BuildContext context, Eleve eleve, String mois) {
    if (!_peutPayerCeMois(eleve, mois)) {
      final premierNonPaye = _premierMoisNonPaye(eleve);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            premierNonPaye != null
                ? "Veuillez d'abord solder entièrement \"$premierNonPaye\" "
                "avant de payer \"$mois\"."
                : "Tous les mois sont déjà soldés pour cet élève.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Paiement - $mois (${eleve.section})"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Montant (FC)"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                if (!_peutPayerCeMois(eleve, mois)) {
                  Navigator.pop(ctx);
                  final premierNonPaye = _premierMoisNonPaye(eleve);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        premierNonPaye != null
                            ? "Impossible : \"$premierNonPaye\" doit être "
                            "soldé en premier."
                            : "Tous les mois sont déjà soldés pour cet "
                            "élève.",
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                widget.fraisScolaires.handlePayment(eleve, mois, amount);
                await widget.fraisScolaires.saveData();
                Navigator.pop(ctx);
                if (mounted) {
                  _filterEleves();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                        Text("✅ Paiement enregistré avec succès")),
                  );
                  // ==========================================================
                  // ⚡ CORRIGÉ — L'IMPRESSION PASSE DÉSORMAIS PAR LE SYSTÈME
                  // CENTRALISÉ ANTI-DOUBLON + FILE D'ATTENTE DE
                  // FraisScolaires (`printOrQueuePrincipalReceipt`), au lieu
                  // d'imprimer directement depuis cet écran. Un reçu déjà
                  // imprimé pour cet élève et ce mois ne sera plus jamais
                  // réimprimé automatiquement, et si aucune imprimante
                  // n'est branchée, le reçu reste en attente et sortira
                  // automatiquement dès qu'une imprimante redevient
                  // disponible (même après extinction complète de
                  // l'ordinateur ou de l'application) — voir
                  // `flushReceiptQueue`, appelée à l'ouverture de cet écran.
                  // ==========================================================
                  final printed = await widget.fraisScolaires
                      .printOrQueuePrincipalReceipt(
                    eleve: eleve,
                    mois: mois,
                    montantPaye: amount,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          printed
                              ? "🖨️ Reçu imprimé avec succès"
                              : "📥 Aucune imprimante disponible — le reçu "
                              "sortira automatiquement dès qu'une "
                              "imprimante sera branchée",
                        ),
                        backgroundColor:
                        printed ? Colors.green : Colors.orange,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
  }
}