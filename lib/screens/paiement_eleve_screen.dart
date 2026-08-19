import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import '../services/epson_printer_service.dart';

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
  // ⚡ NOUVEAU — MODE ADMINISTRATEUR CACHÉ
  //
  // Aucun bouton visible n'existe nulle part dans cet écran. Le point
  // d'entrée est un triple-tap sur le titre de l'AppBar ("Paiements des
  // Élèves"), un geste qui ne ressemble à rien de particulier pour un
  // caissier qui ne connaît pas son existence.
  //
  // - Si aucun code masqué n'est encore configuré (première fois) :
  //   on demande à l'admin de le définir.
  // - Sinon : on demande de saisir le code masqué pour déverrouiller
  //   le mode administrateur pour la durée de cette session d'écran
  //   uniquement (jamais persisté).
  // ==========================================================================
  int _secretTapCount = 0;
  DateTime? _lastSecretTap;
  bool _adminModeUnlocked = false;
  Timer? _adminAutoLockTimer;

  // Anti-brute-force simple : après 5 essais faux, blocage 60 secondes.
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
        // Recharger les données depuis le serveur
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
  // ⚡ NOUVEAU — DÉCLENCHEUR SECRET (triple-tap sur le titre de l'AppBar)
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
      // Déjà déverrouillé pour cette session : on ignore, pour ne pas
      // redemander le code inutilement.
      return;
    }
    if (widget.fraisScolaires.hiddenCodeIsConfigured) {
      _showEnterHiddenCodeDialog();
    } else {
      _showSetupHiddenCodeDialog();
    }
  }

  // ---- Première configuration du code masqué ----
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

  // ---- Saisie du code masqué existant ----
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

  /// Verrouillage automatique du mode admin après 10 minutes d'inactivité
  /// dans cet écran, pour éviter qu'il reste actif trop longtemps si
  /// l'appareil change de main.
  void _startAdminAutoLockTimer() {
    _adminAutoLockTimer?.cancel();
    _adminAutoLockTimer = Timer(const Duration(minutes: 10), () {
      if (mounted) setState(() => _adminModeUnlocked = false);
    });
  }

  /// Synchronise vers le serveur après une annulation/modification, pour
  /// que les autres appareils (app admin desktop, app parent) voient la
  /// correction dès que possible.
  Future<void> _syncAfterAdminChange() async {
    final schoolCode = widget.fraisScolaires.schoolCode;
    if (schoolCode == null || schoolCode.isEmpty) return;
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.backupPassword == null) return;
    try {
      await widget.fraisScolaires
          .backupToServer(schoolCode, appState.backupPassword!);
    } catch (_) {
      // Silencieux — la sauvegarde locale est déjà faite ; la synchro
      // se refera à la prochaine sauvegarde/restauration manuelle.
    }
  }

  // ---- Options admin sur une transaction (annuler / modifier) ----
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
  // ⚡ NOUVEAU — PAIEMENT SÉQUENTIEL DES MOIS
  // Règle : un mois ne peut être payé (même partiellement) que si tous les
  // mois qui le précèdent (dans l'ordre `fraisScolaires.months`, c'est-à-
  // dire Septembre → Juin) sont déjà intégralement soldés pour cet élève.
  // Ces deux petits utilitaires sont purement des helpers d'affichage/
  // validation dans l'écran : ils ne modifient rien, ils se contentent de
  // lire `eleve.paid` et les montants requis via `getRequiredForMonth`.
  // ==========================================================================

  /// Retourne le premier mois (dans l'ordre chronologique) qui n'est pas
  /// encore intégralement payé par l'élève, ou `null` si tous les mois
  /// sont soldés.
  String? _premierMoisNonPaye(Eleve eleve) {
    for (final m in widget.fraisScolaires.months) {
      final required = widget.fraisScolaires
          .getRequiredForMonth(m, eleve.section, eleve.classe);
      final paid = eleve.paid[m] ?? 0;
      if (paid < required) return m;
    }
    return null;
  }

  /// Vrai si l'élève est autorisé à effectuer un paiement pour `mois` :
  /// cela n'est possible que si `mois` est exactement le premier mois non
  /// encore soldé (donc tous les mois précédents sont déjà complets).
  bool _peutPayerCeMois(Eleve eleve, String mois) {
    final premierNonPaye = _premierMoisNonPaye(eleve);
    if (premierNonPaye == null) return false; // tout est déjà payé
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
        // ⚡ NOUVEAU — le titre sert de déclencheur secret (triple-tap).
        // Aucune indication visuelle particulière n'est ajoutée : pour
        // un caissier, ce titre est un simple texte comme n'importe où
        // ailleurs dans l'application.
        title: GestureDetector(
          onTap: _handleSecretTap,
          behavior: HitTestBehavior.opaque,
          child: const Text("Paiements des Élèves"),
        ),
        actions: [
          // ⚡ Badge Mobile Money
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
                // ⚡ NOUVEAU — un mois non payé mais qui n'est pas encore
                // "ouvert" (car un mois précédent n'est pas soldé) est
                // affiché avec un cadenas plutôt qu'un simple avertissement,
                // pour indiquer clairement qu'il faut d'abord régler les
                // mois précédents.
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
          // ⚡ NOUVEAU — n'autorise l'ajout d'un paiement que si ce mois
          // est bien le premier mois non encore soldé de l'élève.
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
                  // ⚡ NOUVEAU — message d'avertissement si ce mois n'est
                  // pas encore payable car un mois antérieur reste dû.
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
                            trailing: Text(
                              "${montant.toStringAsFixed(0)} FC",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            // ⚡ NOUVEAU — en mode administrateur
                            // déverrouillé, un tap sur un paiement déjà
                            // enregistré propose de l'annuler ou de le
                            // modifier. En mode normal (caissier), ce
                            // onTap est simplement absent (null) : rien
                            // ne change visuellement, aucune trace de
                            // cette fonctionnalité n'apparaît.
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
              // ⚡ NOUVEAU — le bouton "Ajouter un paiement" n'apparaît
              // que si le mois est réellement payable (premier mois non
              // soldé de l'élève). Sinon, seul le message d'avertissement
              // ci-dessus est visible.
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
    // ⚡ NOUVEAU — double sécurité : même si ce dialogue venait à être
    // appelé depuis un autre endroit du code, on revérifie ici que le
    // mois est bien payable avant d'accepter le moindre montant.
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
                // ⚡ NOUVEAU — dernière vérification juste avant
                // l'enregistrement effectif du paiement, au cas où l'état
                // de l'élève aurait changé entre l'ouverture du dialogue
                // et la confirmation (ex: paiement mobile reçu entre-
                // temps).
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
                  await _printReceiptAfterPayment(
                      eleve: eleve, mois: mois, montantPaye: amount);
                }
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
  }

  // ⚡ NOUVEAU — Recharge le logo depuis le disque, exactement comme le
  // fait SettingsScreen (même clé SharedPreferences 'has_logo', même
  // chemin de fichier 'school_logo.png' dans getApplicationDocumentsDirectory).
  // C'est ce qui manquait : cet écran n'avait jamais accès au logo,
  // donc il l'envoyait toujours comme "null" à l'impression.
  // On ne le garde pas dans un champ d'état permanent : on le relit à
  // chaque impression, pour être sûr d'avoir toujours la version la
  // plus récente même si l'admin vient de le changer dans les Paramètres.
  Future<Uint8List?> _loadLogoBytesFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasLogo = prefs.getBool('has_logo') ?? false;
      if (!hasLogo) return null;

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/school_logo.png');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ⚡ CORRIGÉ — utilise EscPosPrinterService (imprimante Epson TM-T20III
  // en USB, ciblée par son nom Windows) au lieu de l'ancien
  // BluetoothPrinterService (port COM Bluetooth), qui n'existe plus.
  // ⚡ CORRIGÉ (bug logo) — charge maintenant le logo depuis le disque
  // (comme SettingsScreen) et le transmet à printReceipt, alors qu'avant
  // logoBytes n'était jamais fourni et restait donc "null" à l'impression.
  Future<void> _printReceiptAfterPayment({
    required Eleve eleve,
    required String mois,
    required double montantPaye,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // ⚡ CORRIGÉ — la clé de préférence stocke maintenant le NOM de
    // l'imprimante Windows (ex: "EPSON TM-T20III Receipt"), et non plus
    // un port COM ('printer_com_port' est obsolète).
    final printerName = prefs.getString('printer_name') ?? '';
    if (printerName.isEmpty) return;

    // ⚡ NOUVEAU — chargement du logo AVANT l'impression du reçu.
    final logoBytes = await _loadLogoBytesFromDisk();

    final double montantRequis = widget.fraisScolaires
        .getRequiredForMonth(mois, eleve.section, eleve.classe);
    final double totalPaye =
    widget.fraisScolaires.getStudentTotalPaid(eleve);
    final double totalRequis =
        widget.fraisScolaires.getStudentPending(eleve) + totalPaye;
    final double resteAPayerMois =
        montantRequis - (eleve.paid[mois] ?? 0);

    final bool ok = await EscPosPrinterService.printReceipt(
      printerName: printerName,
      schoolName: widget.fraisScolaires.config.schoolName,
      currentYear: widget.fraisScolaires.currentYear,
      studentName: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      studentId: eleve.id,
      classe: eleve.classe,
      section: eleve.section,
      moisPaye: mois,
      montantPaye: montantPaye,
      montantRequis: montantRequis,
      resteAPayerMois: resteAPayerMois < 0 ? 0 : resteAPayerMois,
      totalDejaPayeAnnee: totalPaye,
      totalRequis: totalRequis,
      historiqueTransactions: eleve.transactions
          .map((t) => Map<String, dynamic>.from(t))
          .toList(),
      logoBytes: logoBytes, // ⚡ NOUVEAU — le logo est maintenant transmis
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? "🖨️ Reçu imprimé avec succès"
              : "⚠️ Reçu non imprimé — vérifiez l'imprimante"),
          backgroundColor: ok ? Colors.green : Colors.orange,
        ),
      );
    }
  }
}