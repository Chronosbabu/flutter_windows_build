import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
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

  int _mobilePendingCount = 0;
  List<Map<String, dynamic>> _mobilePendingPayments = [];
  bool _loadingMobile = false;
  bool _reprinting = false;

  Timer? _pendingRequestsPoller;

  List<String> _dedupe(Iterable<String> items) =>
      LinkedHashSet<String>.from(items).toList();

  String _classFilterKey(String section, String classe) => '$section|$classe';

  @override
  void initState() {
    super.initState();
    selectedSectionFilter = widget.fraisScolaires.lastSelectedSectionFilter;
    selectedClassFilter = widget.fraisScolaires.lastSelectedClassFilter;
    _filterEleves();
    searchController.addListener(_filterEleves);
    _fetchMobilePendingPayments();
    _flushPendingReceipts();
    _pendingRequestsPoller =
        Timer.periodic(const Duration(seconds: 5), (_) => _pollPendingRequests());
  }

  Future<void> _flushPendingReceipts() async {
    final count = await widget.fraisScolaires.flushReceiptQueue();
    if (mounted && count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
          Text("🖨️ $count reçu(s) en attente ont été imprimés automatiquement."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _fetchMobilePendingPayments() async {
    final schoolCode = widget.fraisScolaires.schoolCode;
    if (schoolCode == null || schoolCode.isEmpty) return;
    setState(() => _loadingMobile = true);
    try {
      final response = await http
          .get(Uri.parse(
          'https://jsinf.onrender.com/get_mobile_payments?school_code=$schoolCode'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['mobile_payments'] as List? ?? []);
        if (mounted) {
          setState(() {
            _mobilePendingCount = list.length;
            _mobilePendingPayments =
                list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      }
    } catch (_) {
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
        title: Text("Paiements Mobile Money (${_mobilePendingPayments.length})"),
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
                    child: Icon(_networkIcon(p['network']?.toString() ?? ''),
                        color: Colors.white, size: 18),
                  ),
                  title:
                  Text("${p['nom']} ${p['postNom'] ?? ''} ${p['prenom']}"),
                  subtitle: Text(
                    "${p['mois']} — ${(p['amount'] as num?)?.toStringAsFixed(0) ?? '0'} FC\n"
                        "Réseau: ${p['network'] ?? '—'} • ${p['date'] ?? ''}",
                  ),
                  trailing: const Icon(Icons.phone_android, color: Colors.green),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle),
            label: Text("Confirmer tout (${_mobilePendingPayments.length})"),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
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
      final ids = _mobilePendingPayments.map((p) => p['id']).toList();
      final response = await http
          .post(
        Uri.parse('https://jsinf.onrender.com/confirm_mobile_payments'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'school_code': schoolCode, 'payment_ids': ids}),
      )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final appState = Provider.of<AppState>(context, listen: false);
        if (appState.backupPassword != null) {
          await widget.fraisScolaires
              .restoreFromServer(schoolCode, appState.backupPassword!);
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
                backgroundColor: Colors.green),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("❌ Erreur lors de la confirmation"),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur de connexion"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMobile = false);
    }
  }

  Future<void> _pollPendingRequests() async {
    bool changed = false;
    for (final eleve in widget.fraisScolaires.currentData.eleves) {
      for (final t in eleve.transactions) {
        final reqId = t['pendingRequestId'];
        if (reqId == null) continue;
        final status =
        await widget.fraisScolaires.checkPromoterRequestStatus(reqId as String);
        final st = status['status'];
        if (st == 'approved') {
          await widget.fraisScolaires
              .applyApprovedRequest(t['pendingRequestType'] as String, eleve, t, status);
          t.remove('pendingRequestId');
          t.remove('pendingRequestType');
          changed = true;
        } else if (st == 'rejected') {
          t.remove('pendingRequestId');
          t.remove('pendingRequestType');
          changed = true;
        }
      }
    }
    if (changed) {
      await widget.fraisScolaires.saveData();
      if (mounted) {
        setState(() {});
        _filterEleves();
      }
    }
  }

  Future<void> _sendPromoterRequest({
    required String type,
    required Eleve eleve,
    required Map<String, dynamic> transaction,
    required String mois,
    double? nouveauMontant,
  }) async {
    final result = await widget.fraisScolaires.createPromoterRequest(
      type: type,
      eleve: eleve,
      transaction: transaction,
      mois: mois,
      nouveauMontant: nouveauMontant,
    );
    if (result['success'] == true) {
      transaction['pendingRequestId'] = result['request_id'];
      transaction['pendingRequestType'] = type;
      await widget.fraisScolaires.saveData();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Demande envoyée au promoteur — en attente de confirmation.")),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Échec de l'envoi : ${result['error']}"),
            backgroundColor: Colors.red),
      );
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'reprint':
        return "réimpression";
      case 'modify':
        return "modification";
      case 'cancel':
        return "annulation";
      default:
        return type;
    }
  }

  void _showTransactionActionsSheet(
      Eleve eleve, Map<String, dynamic> transaction, String mois) {
    final pendingType = transaction['pendingRequestType'];
    if (pendingType != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Demande en cours"),
          content: Text(
            "Une demande de ${_typeLabel(pendingType as String)} pour ce paiement "
                "est déjà en attente de confirmation du promoteur.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
          ],
        ),
      );
      return;
    }

    final confirmed = _isReceiptConfirmed(transaction);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (confirmed)
              ListTile(
                leading: const Icon(Icons.print, color: Colors.indigo),
                title: const Text("Demander une réimpression (duplicata)"),
                onTap: () {
                  Navigator.pop(ctx);
                  _sendPromoterRequest(
                      type: 'reprint', eleve: eleve, transaction: transaction, mois: mois);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Demander une modification"),
              onTap: () {
                Navigator.pop(ctx);
                _promptModifyAmount(eleve, transaction, mois);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Demander une annulation"),
              onTap: () {
                Navigator.pop(ctx);
                _confirmRequestCancel(eleve, transaction, mois);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRequestCancel(
      Eleve eleve, Map<String, dynamic> transaction, String mois) {
    final montant = (transaction['amount'] as num?)?.toDouble() ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Demander l'annulation"),
        content: Text(
          "Envoyer au promoteur une demande d'annulation du paiement de "
              "${montant.toStringAsFixed(0)} FC pour \"$mois\" ?\n\n"
              "Le paiement ne sera annulé qu'après confirmation du promoteur.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Non")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _sendPromoterRequest(
                  type: 'cancel', eleve: eleve, transaction: transaction, mois: mois);
            },
            child: const Text("Envoyer la demande"),
          ),
        ],
      ),
    );
  }

  void _promptModifyAmount(
      Eleve eleve, Map<String, dynamic> transaction, String mois) {
    final currentAmount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final controller =
    TextEditingController(text: currentAmount.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Demander une modification — $mois"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Nouveau montant (FC)"),
            ),
            const SizedBox(height: 10),
            const Text(
              "Cette modification ne sera appliquée qu'après confirmation du promoteur.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final newAmount = double.tryParse(controller.text);
              if (newAmount == null || newAmount < 0) return;
              Navigator.pop(ctx);
              _sendPromoterRequest(
                type: 'modify',
                eleve: eleve,
                transaction: transaction,
                mois: mois,
                nouveauMontant: newAmount,
              );
            },
            child: const Text("Envoyer la demande"),
          ),
        ],
      ),
    );
  }

  bool _isReceiptConfirmed(Map<String, dynamic> t) => t['receiptConfirmed'] == true;

  // ⚡ CORRIGÉ — délègue désormais entièrement à
  // widget.fraisScolaires.retryPrintPrincipalReceipt(), qui utilise le
  // MÊME registre de déduplication (`printedReceiptKeys`/`receiptQueue`)
  // que l'impression automatique et que la file d'attente. Avant ce
  // correctif, un clic sur cette icône n'était PAS enregistré dans ce
  // registre, ce qui pouvait provoquer une réimpression automatique en
  // double lors du prochain vidage de la file (ex: après reconnexion de
  // l'imprimante ou réouverture de l'écran).
  Future<void> _retryPrintUnconfirmed(
      Eleve eleve, Map<String, dynamic> transaction) async {
    if (_reprinting) return;
    setState(() => _reprinting = true);
    try {
      final printerName = await _currentPrinterName();
      if (printerName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Aucune imprimante configurée dans les Paramètres."),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      final logoBytes = await _loadLogoBytesLocal();
      final ok = await widget.fraisScolaires.retryPrintPrincipalReceipt(
        eleve: eleve,
        transaction: transaction,
        printerName: printerName,
        logoBytes: logoBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? "🖨️ Reçu imprimé avec succès" : "❌ Échec de l'impression"),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reprinting = false);
    }
  }

  Future<String> _currentPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_name') ?? '';
  }

  Future<Uint8List?> _loadLogoBytesLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('has_logo') ?? false)) return null;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/school_logo.png');
      if (await file.exists()) return await file.readAsBytes();
      return null;
    } catch (_) {
      return null;
    }
  }

  void _filterEleves() {
    final query = searchController.text.toLowerCase().trim();
    setState(() {
      filtered = widget.fraisScolaires.currentData.eleves.where((e) {
        final idMatch = e.id.toLowerCase().contains(query);
        final nameMatch =
        '${e.nom} ${e.postNom} ${e.prenom}'.toLowerCase().contains(query);
        final classMatch =
            selectedClassFilter == null || e.classe == selectedClassFilter;
        final sectionMatch =
            selectedSectionFilter == null || e.section == selectedSectionFilter;
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
    _pendingRequestsPoller?.cancel();
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

  String? _premierMoisNonPaye(Eleve eleve) {
    for (final m in widget.fraisScolaires.months) {
      final required =
      widget.fraisScolaires.getRequiredForMonth(m, eleve.section, eleve.classe);
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
          final sectionsOptions = _dedupe(widget.fraisScolaires.config.sections);
          if (selectedSectionEdit != null &&
              !sectionsOptions.contains(selectedSectionEdit)) {
            sectionsOptions.add(selectedSectionEdit!);
          }
          final classesNumeros = selectedSectionEdit != null
              ? _dedupe(
              widget.fraisScolaires.getClassesForSection(selectedSectionEdit!))
              : <String>[];
          if (selectedClasseNumeroEdit != null &&
              !classesNumeros.contains(selectedClasseNumeroEdit)) {
            classesNumeros.add(selectedClasseNumeroEdit!);
          }
          final sousClasses = (selectedSectionEdit != null &&
              selectedClasseNumeroEdit != null)
              ? _dedupe(widget.fraisScolaires
              .getSubClassesFor(selectedSectionEdit!, selectedClasseNumeroEdit!))
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
                      decoration: const InputDecoration(labelText: "Post-nom")),
                  TextField(
                      controller: prenomController,
                      decoration: const InputDecoration(labelText: "Prénom")),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: selectedSectionEdit,
                    decoration: const InputDecoration(labelText: "Section"),
                    items: sectionsOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
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
                    decoration: const InputDecoration(labelText: "Numéro de classe"),
                    items: classesNumeros
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
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
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) =>
                        setStateDialog(() => selectedSousClasseEdit = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
              ElevatedButton(
                onPressed: () async {
                  if (nomController.text.trim().isNotEmpty &&
                      postNomController.text.trim().isNotEmpty &&
                      selectedClasseNumeroEdit != null &&
                      selectedSectionEdit != null) {
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
                    eleve.classe = widget.fraisScolaires.buildFullClasseName(
                      selectedClasseNumeroEdit!,
                      selectedSousClasseEdit,
                    );
                    eleve.section = selectedSectionEdit!;
                    await widget.fraisScolaires.saveData();
                    _filterEleves();
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Élève modifié avec succès")),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                          Text("Veuillez remplir tous les champs obligatoires")),
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
    final List<Map<String, String>> classFilterEntries = selectedSectionFilter != null
        ? _dedupe(widget.fraisScolaires
        .getAllDisplayClassesForSection(selectedSectionFilter!))
        .map((c) => {'classe': c, 'section': selectedSectionFilter!, 'label': c})
        .toList()
        : widget.fraisScolaires.getAllDisplayClassesWithSection();

    String? selectedClassFilterKey =
    (selectedClassFilter != null && selectedSectionFilter != null)
        ? _classFilterKey(selectedSectionFilter!, selectedClassFilter!)
        : null;

    if (selectedClassFilterKey != null &&
        !classFilterEntries.any((e) =>
        _classFilterKey(e['section']!, e['classe']!) == selectedClassFilterKey)) {
      classFilterEntries.add({
        'classe': selectedClassFilter!,
        'section': selectedSectionFilter!,
        'label': selectedClassFilter!,
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Paiements des Élèves"),
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
                            strokeWidth: 2, color: Colors.white))
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
                        decoration:
                        const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '$_mobilePendingCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
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
                              value: null, child: Text("Toutes les sections")),
                          ..._dedupe(widget.fraisScolaires.config.sections)
                              .map((s) => DropdownMenuItem(value: s, child: Text(s))),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedSectionFilter = value;
                            final validClasses = value != null
                                ? widget.fraisScolaires
                                .getAllDisplayClassesForSection(value)
                                : widget.fraisScolaires.getAllDisplayClasses();
                            if (selectedClassFilter != null &&
                                !validClasses.contains(selectedClassFilter)) {
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
                        value: selectedClassFilterKey,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text("Toutes les classes")),
                          ...classFilterEntries.map((e) => DropdownMenuItem<String>(
                            value: _classFilterKey(e['section']!, e['classe']!),
                            child: Text(e['label']!),
                          )),
                        ],
                        onChanged: (value) {
                          setState(() {
                            if (value == null) {
                              selectedClassFilter = null;
                            } else {
                              final entry = classFilterEntries.firstWhere((e) =>
                              _classFilterKey(e['section']!, e['classe']!) ==
                                  value);
                              selectedClassFilter = entry['classe'];
                              selectedSectionFilter = entry['section'];
                            }
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
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(eleve.id.isNotEmpty ? eleve.id.substring(0, 2) : "?"),
                    ),
                    title: Text('${eleve.nom} ${eleve.postNom} ${eleve.prenom}'),
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
          title:
          Text('${eleve.nom} ${eleve.prenom} - ${eleve.classe} (${eleve.section})'),
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
                final estOuvert = isFullyPaid || _peutPayerCeMois(eleve, mois);
                final nbPaiements =
                    eleve.transactions.where((t) => t['mois'] == mois).length;
                return ListTile(
                  title: Text(mois),
                  subtitle: Text(
                    'Requis: $required FC | Payé: $paid FC'
                        '${nbPaiements > 0 ? ' • $nbPaiements paiement(s)' : ''}'
                        '${!isFullyPaid && !estOuvert ? '\nSoldez d\'abord les mois précédents' : ''}',
                    style: (!isFullyPaid && !estOuvert)
                        ? const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
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
          final historique = eleve.transactions.where((t) => t['mois'] == mois).toList()
            ..sort((a, b) =>
                (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));

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
                                    "Vous devez d'abord solder entièrement \"$premierNonPaye\".",
                                style: const TextStyle(
                                    color: Colors.deepOrange, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Historique des paiements :",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      if (historique.isNotEmpty)
                        const Text(
                          "✅ imprimé • 🖨️ à imprimer • ⏳ demande en cours",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (historique.isEmpty)
                    const Text("Aucun paiement enregistré pour ce mois.",
                        style: TextStyle(color: Colors.grey))
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: historique.length,
                        itemBuilder: (context, i) {
                          final t = historique[i];
                          final montant = (t['amount'] as num?)?.toDouble() ?? 0;
                          final date = t['date']?.toString() ?? "Date inconnue";
                          final isFromParent = t['from_parent'] == true;
                          final confirmed = _isReceiptConfirmed(t);
                          final pendingType = t['pendingRequestType'];

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              isFromParent ? Icons.phone_android : Icons.receipt_long,
                              size: 20,
                              color: isFromParent ? Colors.green : Colors.indigo,
                            ),
                            title: Text(date),
                            subtitle: isFromParent
                                ? Text("Via ${t['network'] ?? 'Mobile Money'}",
                                style:
                                const TextStyle(fontSize: 11, color: Colors.green))
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("${montant.toStringAsFixed(0)} FC",
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 4),
                                if (pendingType != null)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.hourglass_top,
                                        color: Colors.orange, size: 20),
                                  )
                                else
                                  IconButton(
                                    icon: _reprinting
                                        ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child:
                                        CircularProgressIndicator(strokeWidth: 2))
                                        : Icon(
                                      confirmed ? Icons.check_circle : Icons.print,
                                      color:
                                      confirmed ? Colors.green : Colors.indigo,
                                      size: 20,
                                    ),
                                    tooltip:
                                    confirmed ? "Reçu déjà imprimé" : "Imprimer",
                                    onPressed: _reprinting
                                        ? null
                                        : () {
                                      if (confirmed) {
                                        Navigator.pop(ctx);
                                        _showTransactionActionsSheet(
                                            eleve, t, mois);
                                      } else {
                                        _retryPrintUnconfirmed(eleve, t);
                                      }
                                    },
                                  ),
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _showTransactionActionsSheet(eleve, t, mois);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
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

  double _soldeMaxRestantAPartirDe(Eleve eleve, String mois) {
    final idx = widget.fraisScolaires.months.indexOf(mois);
    if (idx == -1) return 0;
    double total = 0;
    for (var i = idx; i < widget.fraisScolaires.months.length; i++) {
      final m = widget.fraisScolaires.months[i];
      final requis =
      widget.fraisScolaires.getRequiredForMonth(m, eleve.section, eleve.classe);
      final dejaPaye = eleve.paid[m] ?? 0;
      final restant = requis - dejaPaye;
      if (restant > 0) total += restant;
    }
    return total;
  }

  // ⚡ CORRIGÉ — Le bouton "Confirmer" utilise désormais un flag
  // `isSubmitting` local au dialogue (via StatefulBuilder) qui :
  //   1) se met à `true` de manière SYNCHRONE au tout début du clic
  //      (avant tout `await`), ce qui empêche toute exécution concurrente
  //      même en cas de double-clic très rapide ;
  //   2) désactive et grise le bouton "Confirmer" + le champ de saisie
  //      pendant tout le traitement (enregistrement + impression), avec
  //      un indicateur de chargement visuel pour rassurer l'utilisateur
  //      et lui éviter de re-cliquer par impatience.
  // C'est ce correctif qui garantit qu'UN clic = UN paiement = UN reçu.
  void _showPaymentDialog(BuildContext context, Eleve eleve, String mois) {
    if (!_peutPayerCeMois(eleve, mois)) {
      final premierNonPaye = _premierMoisNonPaye(eleve);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            premierNonPaye != null
                ? "Veuillez d'abord solder entièrement \"$premierNonPaye\" avant de payer \"$mois\"."
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
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          bool isSubmitting = false;

          Future<void> onConfirmPressed() async {
            // ⚡ Verrou synchrone : rien d'autre ne s'exécute avant cette
            // ligne, donc un deuxième clic pendant que isSubmitting est
            // déjà vrai est immédiatement ignoré.
            if (isSubmitting) return;
            setStateDialog(() => isSubmitting = true);

            final amount = double.tryParse(controller.text);
            if (amount == null || amount <= 0) {
              setStateDialog(() => isSubmitting = false);
              return;
            }

            if (!_peutPayerCeMois(eleve, mois)) {
              Navigator.pop(ctx);
              final premierNonPaye = _premierMoisNonPaye(eleve);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    premierNonPaye != null
                        ? "Impossible : \"$premierNonPaye\" doit être soldé en premier."
                        : "Tous les mois sont déjà soldés pour cet élève.",
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }

            final double soldeMax = _soldeMaxRestantAPartirDe(eleve, mois);
            if (soldeMax > 0 && amount > soldeMax) {
              final bool? continuer = await showDialog<bool>(
                context: context,
                builder: (ctx2) => AlertDialog(
                  title: const Text("Montant supérieur au solde dû"),
                  content: Text(
                    "Le montant saisi (${amount.toStringAsFixed(0)} FC) "
                        "dépasse le solde total restant à payer par cet élève "
                        "sur toute l'année scolaire (${soldeMax.toStringAsFixed(0)} FC).\n\n"
                        "L'excédent éventuel sera tout de même conservé et "
                        "ajouté au dernier mois de l'année.",
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx2, false),
                        child: const Text("Corriger le montant")),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx2, true),
                      child: const Text("Confirmer quand même"),
                    ),
                  ],
                ),
              );
              if (continuer != true) {
                setStateDialog(() => isSubmitting = false);
                return;
              }
            }

            // ⚡ handlePayment() est synchrone : à ce stade, la transaction
            // (ou les transactions, si le paiement est réparti sur
            // plusieurs mois) est créée en une seule fois, de façon
            // atomique, avant tout autre await.
            final List<Map<String, dynamic>> nouvellesTransactions =
            widget.fraisScolaires.handlePayment(eleve, mois, amount);
            await widget.fraisScolaires.saveData();
            if (ctx.mounted) Navigator.pop(ctx);

            if (mounted) {
              _filterEleves();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("✅ Paiement enregistré avec succès")),
              );

              int nbRecusImprimes = 0;
              for (final transaction in nouvellesTransactions) {
                final printed = await widget.fraisScolaires
                    .printOrQueuePrincipalReceipt(
                    eleve: eleve, transaction: transaction);
                transaction['receiptConfirmed'] = printed;
                if (printed) nbRecusImprimes++;
              }
              if (nouvellesTransactions.isNotEmpty) {
                await widget.fraisScolaires.saveData();
              }

              if (mounted) {
                final int totalRecus = nouvellesTransactions.length;
                String message;
                Color color;
                if (totalRecus == 0) {
                  message = "Aucune transaction créée.";
                  color = Colors.orange;
                } else if (nbRecusImprimes == totalRecus) {
                  message = totalRecus == 1
                      ? "🖨️ Reçu imprimé avec succès"
                      : "🖨️ $nbRecusImprimes reçu(s) imprimé(s) avec succès "
                      "(paiement réparti sur $totalRecus mois)";
                  color = Colors.green;
                } else if (nbRecusImprimes == 0) {
                  message = totalRecus == 1
                      ? "📥 Aucune imprimante disponible — le reçu sortira "
                      "automatiquement dès qu'une imprimante sera prête."
                      : "📥 $totalRecus reçu(s) en attente d'impression.";
                  color = Colors.orange;
                } else {
                  message = "🖨️ $nbRecusImprimes/$totalRecus reçu(s) imprimé(s).";
                  color = Colors.orange;
                }
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
              }
            }
          }

          return AlertDialog(
            title: Text("Paiement - $mois (${eleve.section})"),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              enabled: !isSubmitting,
              decoration: const InputDecoration(labelText: "Montant (FC)"),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text("Annuler"),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : onConfirmPressed,
                child: isSubmitting
                    ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Confirmer"),
              ),
            ],
          );
        },
      ),
    );
  }
}