import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
        title: const Text("Paiements des Élèves"),
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
                final nbPaiements = eleve.transactions
                    .where((t) => t['mois'] == mois)
                    .length;
                return ListTile(
                  title: Text(mois),
                  subtitle: Text(
                    'Requis: $required FC | Payé: $paid FC'
                        '${nbPaiements > 0 ? ' • $nbPaiements paiement(s)' : ''}',
                  ),
                  trailing: isFullyPaid
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.warning, color: Colors.orange),
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
              if (!isFullyPaid)
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

  // ⚡ CORRIGÉ — utilise EscPosPrinterService (imprimante Epson TM-T20III
  // en USB, ciblée par son nom Windows) au lieu de l'ancien
  // BluetoothPrinterService (port COM Bluetooth), qui n'existe plus.
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