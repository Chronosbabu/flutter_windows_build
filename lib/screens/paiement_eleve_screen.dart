import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import '../app_state.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import '../services/epson_printer_service.dart';
import '../services/student_import_service.dart';

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
  bool _importing = false;

  Timer? _pendingRequestsPoller;

  static const String _receiptsLockedPrefKey = 'receipts_locked';
  bool _receiptsLocked = false;

  static const String _autoImportSchoolName = 'COMPLEXE SCOLAIRE CHRIST SAUVEUR';
  static const String _autoImportFileName = 'liste.txt';

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
    _loadReceiptsLockState();
    _fetchMobilePendingPayments();
    _flushPendingReceipts();
    _pendingRequestsPoller =
        Timer.periodic(const Duration(seconds: 5), (_) => _pollPendingRequests());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeAutoImportFromDesktop());
  }

  Future<void> _loadReceiptsLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = prefs.getBool(_receiptsLockedPrefKey) ?? false;
    if (mounted) {
      setState(() => _receiptsLocked = locked);
    }
  }

  Future<void> _setReceiptsLocked(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_receiptsLockedPrefKey, value);
    if (mounted) {
      setState(() => _receiptsLocked = value);
    }
  }

  Future<void> _toggleReceiptsLock() async {
    final bool nouveauEtat = !_receiptsLocked;
    final String titre = nouveauEtat
        ? "Bloquer l'impression des reçus ?"
        : "Débloquer l'impression des reçus ?";
    final String message = nouveauEtat
        ? "Tant que c'est bloqué, les nouveaux paiements seront enregistrés "
        "normalement, mais AUCUN reçu ne sera imprimé ni mis en attente "
        "d'impression pour ces paiements.\n\n"
        "Voulez-vous vraiment bloquer l'impression maintenant ?"
        : "Les nouveaux paiements seront à nouveau imprimés (ou mis en "
        "attente si aucune imprimante n'est disponible), comme "
        "d'habitude.\n\n"
        "Voulez-vous vraiment débloquer l'impression maintenant ?";

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: nouveauEtat ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(nouveauEtat ? "Bloquer" : "Débloquer"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _setReceiptsLocked(nouveauEtat);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nouveauEtat
                  ? "🔒 Impression des reçus bloquée."
                  : "🔓 Impression des reçus débloquée.",
            ),
            backgroundColor: nouveauEtat ? Colors.red : Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _flushPendingReceipts() async {
    if (_receiptsLocked) return;
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

  Future<void> _maybeAutoImportFromDesktop() async {
    final targetName = _autoImportSchoolName.trim().toUpperCase();
    if (widget.fraisScolaires.config.schoolName.trim().toUpperCase() !=
        targetName) {
      return;
    }

    final path =
    await StudentImportService.findDesktopFile(_autoImportFileName);
    if (path == null) return;

    String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      return;
    }
    if (content.trim().isEmpty) return;

    if (await AutoImportGuard.alreadyHandled(content)) return;
    if (!mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Fichier d'élèves détecté"),
        content: const Text(
          "Un fichier \"liste.txt\" a été trouvé sur le Bureau. "
              "Voulez-vous importer ces élèves maintenant ?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Plus tard")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Importer")),
        ],
      ),
    );

    if (proceed == true) {
      await _runStudentImportFlow(content);
    }
    await AutoImportGuard.markHandled(content);
  }

  Future<void> _pickAndImportFile() async {
    if (_importing) return;
    const typeGroup =
    XTypeGroup(label: 'Liste d\'élèves', extensions: ['json', 'txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final content = await file.readAsString();
    await _runStudentImportFlow(content);
  }

  Future<void> _runStudentImportFlow(String content) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final parseResult = StudentImportParser.parse(content);
      if (parseResult.errors.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(parseResult.errors.first),
                backgroundColor: Colors.red),
          );
        }
        return;
      }
      if (parseResult.records.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Aucun élève trouvé dans ce fichier.")),
          );
        }
        return;
      }

      final analysis =
      StudentImportService.analyze(widget.fraisScolaires, parseResult.records);

      if (analysis.sectionConflicts.isNotEmpty) {
        final proceed = await _resolveSectionConflicts(analysis.sectionConflicts);
        if (!proceed) return;
        await StudentImportService.applySectionResolutions(
            widget.fraisScolaires, analysis.sectionConflicts);
      }

      final duplicates =
      StudentImportService.findDuplicates(widget.fraisScolaires, parseResult.records);
      final duplicateIncoming = duplicates.map((d) => d.incoming).toSet();
      final newRecords = parseResult.records
          .where((r) => !duplicateIncoming.contains(r))
          .toList();

      if (duplicates.isNotEmpty) {
        final proceed = await _resolveDuplicates(duplicates);
        if (!proceed) return;
      }

      final addedCount =
      await StudentImportService.importNewRecords(widget.fraisScolaires, newRecords);
      final completedCount =
      await StudentImportService.completeDuplicates(widget.fraisScolaires, duplicates);
      final ignoredCount = duplicates.length - completedCount;

      if (mounted) {
        _filterEleves();
        setState(() {});
        final parts = <String>["$addedCount élève(s) ajouté(s)"];
        if (completedCount > 0) parts.add("$completedCount fiche(s) complétée(s)");
        if (ignoredCount > 0) parts.add("$ignoredCount doublon(s) ignoré(s)");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Import terminé : ${parts.join(', ')}."),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<bool> _resolveSectionConflicts(List<SectionConflict> conflicts) async {
    final existingSections = _dedupe(widget.fraisScolaires.config.sections);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Sections inconnues détectées"),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Ces valeurs du fichier importé ne correspondent à aucune "
                        "section déjà connue. Pour chacune, choisissez une "
                        "section existante à fusionner, ou créez-la telle "
                        "quelle. La valeur d'origine reste toujours visible "
                        "sur la fiche des élèves concernés.",
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  ...conflicts.map((c) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('"${c.rawCandidate}"',
                              style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          RadioListTile<bool>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Créer comme nouvelle section",
                                style: TextStyle(fontSize: 13)),
                            value: true,
                            groupValue: c.createNew,
                            onChanged: (v) =>
                                setStateDialog(() => c.createNew = true),
                          ),
                          if (c.createNew)
                            Padding(
                              padding: const EdgeInsets.only(left: 32, bottom: 6),
                              child: TextFormField(
                                initialValue: c.newSectionName,
                                decoration: const InputDecoration(
                                    labelText: "Nom de la nouvelle section"),
                                onChanged: (v) => c.newSectionName = v,
                              ),
                            ),
                          RadioListTile<bool>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                                "Fusionner vers une section existante",
                                style: TextStyle(fontSize: 13)),
                            value: false,
                            groupValue: c.createNew,
                            onChanged: (v) =>
                                setStateDialog(() => c.createNew = false),
                          ),
                          if (!c.createNew)
                            Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: DropdownButtonFormField<String>(
                                value: existingSections.contains(c.mergeTarget)
                                    ? c.mergeTarget
                                    : null,
                                hint: const Text("Choisir une section"),
                                items: existingSections
                                    .map((s) =>
                                    DropdownMenuItem(value: s, child: Text(s)))
                                    .toList(),
                                onChanged: (v) =>
                                    setStateDialog(() => c.mergeTarget = v),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler l'import")),
            ElevatedButton(
              onPressed: () {
                for (final c in conflicts) {
                  if (!c.createNew &&
                      (c.mergeTarget == null || c.mergeTarget!.isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "Veuillez choisir une section pour chaque élément.")),
                    );
                    return;
                  }
                }
                Navigator.pop(ctx, true);
              },
              child: const Text("Continuer"),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  Future<bool> _resolveDuplicates(List<DuplicateMatch> matches) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text("Élèves déjà existants (${matches.length})"),
          content: SizedBox(
            width: 480,
            height: 420,
            child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (context, i) {
                final m = matches[i];
                return CheckboxListTile(
                  value: m.completeMissingInfo,
                  onChanged: (v) =>
                      setStateDialog(() => m.completeMissingInfo = v ?? false),
                  title: Text(
                      "${m.existing.nom} ${m.existing.postNom} ${m.existing.prenom}"),
                  subtitle: Text(
                    "Déjà dans ${m.existing.classe} (ID: ${m.existing.id}).\n"
                        "Le fichier apporte peut-être des informations que "
                        "la fiche actuelle n'a pas (téléphone, tuteur, lieu "
                        "de naissance...). Compléter automatiquement la "
                        "fiche existante avec ce qui manque ?",
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                for (final m in matches) {
                  m.completeMissingInfo = false;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text("Ignorer tous les doublons"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Continuer"),
            ),
          ],
        ),
      ),
    );
    return result == true;
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

  Future<void> _retryPrintUnconfirmed(
      Eleve eleve, Map<String, dynamic> transaction) async {
    if (_reprinting) return;
    if (_receiptsLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "🔒 L'impression des reçus est actuellement bloquée. "
                  "Débloquez-la depuis le bouton en haut de l'écran pour imprimer."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
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

  // ⚡ NOUVEAU — Texte affiché directement sur la carte de l'élève :
  // liste des dates de paiement (sans doublon, de la plus ancienne à la plus
  // récente, format jj/mm/aaaa). Lecture seule : ne modifie aucune donnée.
  // Retourne une chaîne vide si l'élève n'a encore aucun paiement.
  String _datesPaiementsLabel(Eleve eleve) {
    final Set<String> dates = {};
    for (final t in eleve.transactions) {
      final d = t['date']?.toString().trim() ?? '';
      if (d.isNotEmpty) dates.add(d);
    }
    if (dates.isEmpty) return '';
    final List<String> triees = dates.toList()..sort();
    final List<String> affichees = triees.map((d) {
      final p = d.split('-');
      if (p.length == 3 && p[0].length == 4) {
        return '${p[2]}/${p[1]}/${p[0]}';
      }
      return d;
    }).toList();
    return '\n📅 Dates de paiement : ${affichees.join(', ')}';
  }

  String? _premierMoisNonPaye(Eleve eleve) {
    for (final m in widget.fraisScolaires.months) {
      final required =
      widget.fraisScolaires.getRequiredForMonthForEleve(eleve, m);
      final paid = eleve.paid[m] ?? 0;
      if (paid < required) return m;
    }
    return null;
  }

  String? _moisDebloqueActif(Eleve eleve) {
    final m = eleve.moisDebloque;
    if (m == null || m.isEmpty) return null;
    if (!widget.fraisScolaires.months.contains(m)) return null;
    final required = widget.fraisScolaires.getRequiredForMonthForEleve(eleve, m);
    final paid = eleve.paid[m] ?? 0;
    if (paid >= required) return null;
    return m;
  }

  bool _peutPayerCeMois(Eleve eleve, String mois) {
    final required =
    widget.fraisScolaires.getRequiredForMonthForEleve(eleve, mois);
    final paid = eleve.paid[mois] ?? 0;
    if (paid >= required) return false;
    if (_moisDebloqueActif(eleve) == mois) return true;
    final premierNonPaye = _premierMoisNonPaye(eleve);
    if (premierNonPaye == null) return false;
    return mois == premierNonPaye;
  }

  bool _paiementViaDeblocage(Eleve eleve, String mois) {
    if (_moisDebloqueActif(eleve) != mois) return false;
    return _premierMoisNonPaye(eleve) != mois;
  }

  Future<void> _deverrouillerMois(Eleve eleve, String mois) async {
    final actif = _moisDebloqueActif(eleve);
    if (actif != null && actif != mois) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Un seul mois peut être déverrouillé à la fois : \"$actif\" est "
                  "déjà déverrouillé. Soldez-le ou re-verrouillez-le d'abord."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final premierNonPaye = _premierMoisNonPaye(eleve);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Déverrouiller \"$mois\" ?"),
        content: Text(
          "Vous pourrez payer \"$mois\" sans avoir soldé les mois précédents.\n\n"
              "Si le montant payé dépasse ce qui est dû pour \"$mois\", le "
              "surplus sera automatiquement réparti sur les mois en priorité"
              "${premierNonPaye != null ? ", en commençant par \"$premierNonPaye\"" : ""}.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Déverrouiller"),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.fraisScolaires.setMoisDebloquePourEleve(eleve, mois);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🔓 Mois \"$mois\" déverrouillé pour cet élève."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _reverrouillerMois(Eleve eleve) async {
    await widget.fraisScolaires.setMoisDebloquePourEleve(eleve, null);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🔒 Mois re-verrouillé.")),
      );
    }
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

  // ⚡ NOUVEAU — ouvre la fenêtre de saisie groupée des anciens paiements.
  // Rien ne change sur cet écran tant qu'on n'appuie pas sur le bouton.
  Future<void> _ouvrirSaisieGroupee() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaisieGroupeeScreen(
          fraisScolaires: widget.fraisScolaires,
          receiptsLocked: _receiptsLocked,
        ),
      ),
    );
    if (!mounted) return;
    _filterEleves();
  }

  // ⚡ NOUVEAU — ouvre la grille type cahier (élèves × mois).
  Future<void> _ouvrirGrilleCahier() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GrilleCahierScreen(
          fraisScolaires: widget.fraisScolaires,
          receiptsLocked: _receiptsLocked,
        ),
      ),
    );
    if (!mounted) return;
    _filterEleves();
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
          IconButton(
            icon: Icon(
              _receiptsLocked ? Icons.lock : Icons.lock_open,
              color: _receiptsLocked ? Colors.red : Colors.white,
            ),
            tooltip: _receiptsLocked
                ? "Impression des reçus bloquée — appuyer pour débloquer"
                : "Impression des reçus active — appuyer pour bloquer",
            onPressed: _toggleReceiptsLock,
          ),
          // ⚡ NOUVEAU — grille type cahier (cocher les mois payés)
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: "Grille type cahier (cocher les mois payés)",
            onPressed: _ouvrirGrilleCahier,
          ),
          // ⚡ NOUVEAU — bouton de saisie groupée des anciens paiements
          IconButton(
            icon: const Icon(Icons.playlist_add_check_circle),
            tooltip: "Saisie groupée des anciens paiements (cahier)",
            onPressed: _ouvrirSaisieGroupee,
          ),
          IconButton(
            icon: _importing
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file),
            tooltip: "Importer une liste d'élèves (JSON/TXT)",
            onPressed: _importing ? null : _pickAndImportFile,
          ),
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
          if (_receiptsLocked)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: const [
                  Icon(Icons.lock, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Impression des reçus bloquée : les paiements sont "
                          "enregistrés, mais aucun reçu n'est imprimé ni "
                          "mis en attente.",
                      style: TextStyle(color: Colors.red, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
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
                final moisDebloqueActif = _moisDebloqueActif(eleve);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(eleve.id.length >= 2
                          ? eleve.id.substring(0, 2)
                          : (eleve.id.isNotEmpty ? eleve.id : "?")),
                    ),
                    title: Text('${eleve.nom} ${eleve.postNom} ${eleve.prenom}'),
                    subtitle: Text(
                      'ID: ${eleve.id}\n'
                          'Classe: ${eleve.classe} | Section: ${eleve.section}\n'
                          'Total payé: ${widget.fraisScolaires.getStudentTotalPaid(eleve)} FC'
                          '${_datesPaiementsLabel(eleve)}'
                          '${eleve.montantMensuelPersonnalise != null ? '\n⭐ Montant personnalisé : ${eleve.montantMensuelPersonnalise!.toStringAsFixed(0)} FC/mois' : ''}'
                          '${eleve.exceptionsMoisPersonnalisees.isNotEmpty ? '\n⭐ ${eleve.exceptionsMoisPersonnalisees.length} mois en exception' : ''}'
                          '${moisDebloqueActif != null ? '\n🔓 Mois déverrouillé : $moisDebloqueActif' : ''}',
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
                    .getRequiredForMonthForEleve(eleve, mois);
                final paid = eleve.paid[mois] ?? 0;
                final isFullyPaid = paid >= required;
                final estGratuit = required <= 0;
                final estDebloque = !isFullyPaid && _moisDebloqueActif(eleve) == mois;
                final estOuvert = isFullyPaid || _peutPayerCeMois(eleve, mois);
                final nbPaiements =
                    eleve.transactions.where((t) => t['mois'] == mois).length;
                return ListTile(
                  title: Text(mois),
                  subtitle: Text(
                    estGratuit
                        ? 'Mois gratuit (0 FC)'
                        : 'Requis: $required FC | Payé: $paid FC'
                        '${nbPaiements > 0 ? ' • $nbPaiements paiement(s)' : ''}'
                        '${estDebloque ? '\n🔓 Déverrouillé' : ''}'
                        '${!isFullyPaid && !estOuvert ? '\nSoldez d\'abord les mois précédents ou déverrouillez ce mois' : ''}',
                    style: (!isFullyPaid && !estOuvert)
                        ? const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)
                        : null,
                  ),
                  trailing: estGratuit
                      ? const Icon(Icons.card_giftcard, color: Colors.green)
                      : isFullyPaid
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : (estDebloque
                      ? const Icon(Icons.lock_open, color: Colors.indigo)
                      : (estOuvert
                      ? const Icon(Icons.warning, color: Colors.orange)
                      : const Icon(Icons.lock_outline, color: Colors.grey))),
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
              .getRequiredForMonthForEleve(eleve, mois);
          final paid = eleve.paid[mois] ?? 0;
          final isFullyPaid = paid >= required;
          final peutPayer = !isFullyPaid && _peutPayerCeMois(eleve, mois);
          final premierNonPaye = _premierMoisNonPaye(eleve);
          final estDebloque = !isFullyPaid && _moisDebloqueActif(eleve) == mois;
          final viaDeblocage = estDebloque && premierNonPaye != mois;
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
                    required <= 0
                        ? "Ce mois est gratuit pour cet élève (0 FC)."
                        : "Requis : ${required.toStringAsFixed(0)} FC\n"
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
                                    "Vous devez d'abord solder entièrement \"$premierNonPaye\", "
                                    "ou déverrouiller ce mois avec le bouton ci-dessous.",
                                style: const TextStyle(
                                    color: Colors.deepOrange, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (viaDeblocage)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lock_open,
                                color: Colors.indigo, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Ce mois est déverrouillé. Un paiement complétera "
                                    "d'abord \"$mois\", puis le surplus ira sur "
                                    "\"${premierNonPaye ?? ''}\" et les mois suivants.",
                                style: const TextStyle(
                                    color: Colors.indigo, fontSize: 12.5),
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
              if (!isFullyPaid && !peutPayer)
                OutlinedButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: const Text("Déverrouiller ce mois"),
                  onPressed: () async {
                    await _deverrouillerMois(eleve, mois);
                    setStateDialog(() {});
                  },
                ),
              if (viaDeblocage)
                TextButton.icon(
                  icon: const Icon(Icons.lock_outline, color: Colors.red),
                  label: const Text("Re-verrouiller",
                      style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    await _reverrouillerMois(eleve);
                    setStateDialog(() {});
                  },
                ),
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
      widget.fraisScolaires.getRequiredForMonthForEleve(eleve, m);
      final dejaPaye = eleve.paid[m] ?? 0;
      final restant = requis - dejaPaye;
      if (restant > 0) total += restant;
    }
    return total;
  }

  double _soldeTotalRestantAnnee(Eleve eleve) {
    double total = 0;
    for (final m in widget.fraisScolaires.months) {
      final requis =
      widget.fraisScolaires.getRequiredForMonthForEleve(eleve, m);
      final dejaPaye = eleve.paid[m] ?? 0;
      final restant = requis - dejaPaye;
      if (restant > 0) total += restant;
    }
    return total;
  }

  void _showPaymentDialog(BuildContext context, Eleve eleve, String mois) {
    if (!_peutPayerCeMois(eleve, mois)) {
      final premierNonPaye = _premierMoisNonPaye(eleve);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            premierNonPaye != null
                ? "Veuillez d'abord solder entièrement \"$premierNonPaye\" avant de payer \"$mois\", ou déverrouillez ce mois."
                : "Tous les mois sont déjà soldés pour cet élève.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final controller = TextEditingController();
    bool isSubmitting = false;
    final bool viaDeblocageAffichage = _paiementViaDeblocage(eleve, mois);
    final String? premierPrioritaire = _premierMoisNonPaye(eleve);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          Future<void> onConfirmPressed() async {
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

            final bool viaDeblocage = _paiementViaDeblocage(eleve, mois);

            if (viaDeblocage) {
              final double soldeTotal = _soldeTotalRestantAnnee(eleve);
              if (amount > soldeTotal) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Le montant saisi (${amount.toStringAsFixed(0)} FC) dépasse "
                          "le solde total restant de l'année "
                          "(${soldeTotal.toStringAsFixed(0)} FC). "
                          "Veuillez corriger le montant.",
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                setStateDialog(() => isSubmitting = false);
                return;
              }
            } else {
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
            }

            final List<Map<String, dynamic>> nouvellesTransactions = viaDeblocage
                ? widget.fraisScolaires.handlePaymentMoisDebloque(eleve, mois, amount)
                : widget.fraisScolaires.handlePayment(eleve, mois, amount);

            if (eleve.moisDebloque != null) {
              final moisDeb = eleve.moisDebloque!;
              final requisDeb = widget.fraisScolaires
                  .getRequiredForMonthForEleve(eleve, moisDeb);
              if ((eleve.paid[moisDeb] ?? 0) >= requisDeb) {
                eleve.moisDebloque = null;
              }
            }

            await widget.fraisScolaires.saveData();
            if (ctx.mounted) Navigator.pop(ctx);

            if (mounted) {
              _filterEleves();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("✅ Paiement enregistré avec succès")),
              );

              if (_receiptsLocked) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          "🔒 Impression bloquée : ce paiement a été "
                              "enregistré, mais aucun reçu n'a été imprimé "
                              "ni mis en attente."),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } else {
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
          }

          return AlertDialog(
            title: Text("Paiement - $mois (${eleve.section})"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (viaDeblocageAffichage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.indigo),
                      ),
                      child: Text(
                        "🔓 Mois déverrouillé : le montant complétera d'abord "
                            "\"$mois\", puis le surplus sera réparti sur "
                            "\"${premierPrioritaire ?? ''}\" et les mois suivants.",
                        style: const TextStyle(color: Colors.indigo, fontSize: 11.5),
                      ),
                    ),
                  ),
                if (eleve.montantMensuelPersonnalise != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.indigo),
                      ),
                      child: Text(
                        "⭐ Cet élève a un montant mensuel personnalisé : "
                            "${eleve.montantMensuelPersonnalise!.toStringAsFixed(0)} FC/mois "
                            "(exception de paiement).",
                        style: const TextStyle(color: Colors.indigo, fontSize: 11.5),
                      ),
                    ),
                  ),
                if (_receiptsLocked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red),
                      ),
                      child: const Text(
                        "🔒 Impression bloquée : ce paiement sera enregistré, "
                            "mais aucun reçu ne sera imprimé ni mis en attente.",
                        style: TextStyle(color: Colors.red, fontSize: 11.5),
                      ),
                    ),
                  ),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  enabled: !isSubmitting,
                  decoration: const InputDecoration(labelText: "Montant (FC)"),
                ),
              ],
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

// ============================================================================
// ⚡ NOUVEAU — OUTILS PARTAGÉS PAR LA SAISIE GROUPÉE ET LA GRILLE CAHIER
// ============================================================================
// Formats de dates + gestion des « lots saisis » (liste et annulation).
// Chaque saisie groupée / grille crée un lot (marqueur lotSaisie sur chaque
// paiement) : on peut ainsi retrouver et annuler un lot saisi par erreur.
// ============================================================================

String _deuxChiffres(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) =>
    '${_deuxChiffres(d.day)}/${_deuxChiffres(d.month)}/${d.year}';

String _formatDateHeure(DateTime d) =>
    '${_formatDate(d)} ${_deuxChiffres(d.hour)}:${_deuxChiffres(d.minute)}';

String _formatDateIso(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final p = iso.split('-');
  if (p.length == 3 && p[0].length == 4) return '${p[2]}/${p[1]}/${p[0]}';
  return iso;
}

class _LigneLot {
  final String mois;
  final double montant;
  // 'ok' | 'solde' | 'gratuit' | 'bloque' | 'sans_montant'
  final String statut;
  final bool plafonne;
  final bool deblocage;

  const _LigneLot({
    required this.mois,
    required this.montant,
    required this.statut,
    this.plafonne = false,
    this.deblocage = false,
  });
}

class _PlanEleve {
  final Eleve eleve;
  final List<_LigneLot> lignes;

  const _PlanEleve({required this.eleve, required this.lignes});

  Iterable<_LigneLot> get lignesOk =>
      lignes.where((l) => l.statut == 'ok' && l.montant > 0);

  bool get aEnregistrer => lignesOk.isNotEmpty;

  double get total => lignesOk.fold(0.0, (s, l) => s + l.montant);

  bool get toutSolde =>
      lignes.isNotEmpty &&
          lignes.every((l) => l.statut == 'solde' || l.statut == 'gratuit');
}

class _InfoLot {
  final String id;
  final Set<String> eleves = {};
  final Set<String> mois = {};
  int nbPaiements = 0;
  double total = 0;
  String? datePaiement;
  DateTime? creeLe;

  _InfoLot(this.id);

  bool annulable(int heures) {
    if (creeLe == null) return false;
    return DateTime.now().difference(creeLe!) <= Duration(hours: heures);
  }
}

class _LotsSaisie {
  // Délai pendant lequel un lot peut être annulé directement (au-delà, il faut
  // passer par les demandes au promoteur, paiement par paiement).
  static const int delaiAnnulationHeures = 72;

  static List<_InfoLot> collecter(FraisScolaires fs) {
    final Map<String, _InfoLot> map = {};
    for (final e in fs.currentData.eleves) {
      for (final t in e.transactions) {
        final String lot = t['lotSaisie']?.toString() ?? '';
        if (lot.isEmpty) continue;
        final info = map.putIfAbsent(lot, () => _InfoLot(lot));
        info.eleves.add(e.id);
        info.nbPaiements++;
        info.total += (t['amount'] as num?)?.toDouble() ?? 0.0;
        info.mois.add(t['mois']?.toString() ?? '');
        info.datePaiement = t['date']?.toString();
        final c = DateTime.tryParse(t['lotCreeLe']?.toString() ?? '');
        if (c != null) info.creeLe = c;
      }
    }
    final lots = map.values.toList();
    lots.sort((a, b) {
      final da = a.creeLe;
      final db = b.creeLe;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return lots;
  }

  static Future<int> annuler(FraisScolaires fs, String lotId) async {
    int retires = 0;
    for (final e in fs.currentData.eleves) {
      final aRetirer = e.transactions
          .where((t) =>
      t['lotSaisie'] == lotId && t['pendingRequestId'] == null)
          .toList();
      if (aRetirer.isEmpty) continue;

      for (final t in aRetirer) {
        final String mois = t['mois']?.toString() ?? '';
        final double montant = (t['amount'] as num?)?.toDouble() ?? 0.0;
        double nouveau = (e.paid[mois] ?? 0.0) - montant;
        if (nouveau < 0) nouveau = 0;
        e.paid[mois] = nouveau;
        e.transactions.remove(t);
        final String cle = 'principal|${e.id}|${t['id']}';
        fs.receiptQueue.removeWhere((r) => r['key'] == cle);
        retires++;
      }
      // Même logique que l'annulation normale d'un paiement.
      fs.recalculerRepartitionMoisPourEleve(e);
    }
    await fs.saveData();
    return retires;
  }

  static void afficher(
      BuildContext context, FraisScolaires fs, VoidCallback onChange) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final lots = collecter(fs);
          return AlertDialog(
            title: const Text("Lots saisis"),
            content: SizedBox(
              width: 560,
              height: 420,
              child: lots.isEmpty
                  ? const Center(
                  child: Text("Aucune saisie groupée enregistrée."))
                  : ListView.builder(
                itemCount: lots.length,
                itemBuilder: (c, i) {
                  final l = lots[i];
                  final moisTries = fs.months
                      .where((m) => l.mois.contains(m))
                      .toList();
                  final bool annulable = l.annulable(delaiAnnulationHeures);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(l.creeLe != null
                          ? "Lot du ${_formatDateHeure(l.creeLe!)}"
                          : "Lot ${l.id}"),
                      subtitle: Text(
                        "${l.eleves.length} élève(s) • ${l.nbPaiements} paiement(s)\n"
                            "Total : ${formatMontant(l.total)} FC\n"
                            "Mois : ${moisTries.join(', ')}\n"
                            "Date des paiements : ${_formatDateIso(l.datePaiement)}",
                      ),
                      isThreeLine: true,
                      trailing: annulable
                          ? TextButton(
                        onPressed: () async {
                          final bool? conf = await showDialog<bool>(
                            context: ctx,
                            builder: (ctx2) => AlertDialog(
                              title: const Text("Annuler ce lot ?"),
                              content: Text(
                                "Les ${l.nbPaiements} paiements de ce lot "
                                    "(${formatMontant(l.total)} FC) seront retirés. "
                                    "Cette action est définitive.",
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx2, false),
                                    child: const Text("Non")),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white),
                                  onPressed: () =>
                                      Navigator.pop(ctx2, true),
                                  child: const Text("Annuler le lot"),
                                ),
                              ],
                            ),
                          );
                          if (conf != true) return;
                          final n = await annuler(fs, l.id);
                          if (!ctx.mounted) return;
                          setD(() {});
                          onChange();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    "🗑️ Lot annulé : $n paiement(s) retiré(s)."),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                        child: const Text("Annuler",
                            style: TextStyle(color: Colors.red)),
                      )
                          : const Tooltip(
                        message:
                        "Délai dépassé : passez par les demandes d'annulation au promoteur.",
                        child: Icon(Icons.lock_clock, color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fermer")),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// ⚡ NOUVEAU — SAISIE GROUPÉE DES ANCIENS PAIEMENTS
// ============================================================================
// Permet d'enregistrer d'un coup les paiements déjà faits avant l'utilisation
// de l'application (cahier) : on coche le(s) mois, on choisit le montant, on
// sélectionne les élèves, puis on enregistre.
//
// Règles (identiques au fonctionnement normal) :
//   - un mois ne peut être payé que si les mois précédents sont soldés
//     (sauf si l'option « Autoriser… » est activée) ;
//   - le montant appliqué ne dépasse jamais ce qui reste à payer pour le mois ;
//   - les exceptions de montant par élève/mois sont respectées ;
//   - chaque paiement crée une vraie transaction (mêmes champs que d'habitude).
//
// Chaque paiement porte en plus les marqueurs « saisieGroupee » et « lotSaisie »
// qui permettent de retrouver (et d'annuler) un lot saisi par erreur.
// ============================================================================

class SaisieGroupeeScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  final bool receiptsLocked;

  const SaisieGroupeeScreen({
    super.key,
    required this.fraisScolaires,
    required this.receiptsLocked,
  });

  @override
  State<SaisieGroupeeScreen> createState() => _SaisieGroupeeScreenState();
}

class _SaisieGroupeeScreenState extends State<SaisieGroupeeScreen> {
  static const int _delaiAnnulationLotHeures =
      _LotsSaisie.delaiAnnulationHeures;

  final Set<String> _moisCoches = {};
  String _modeMontant = 'complet'; // 'complet' | 'fixe'
  final TextEditingController _montantCtrl = TextEditingController();
  final TextEditingController _rechercheCtrl = TextEditingController();
  DateTime _datePaiement = DateTime.now();
  bool _autoriserSansPrecedents = false;
  bool _imprimerRecus = false;
  bool _masquerSoldes = true;
  String? _filtreSection;
  String? _filtreClasse;
  final Set<String> _selection = {};
  List<_PlanEleve> _plans = [];
  bool _enCours = false;
  String _progression = '';
  int _seq = 0;

  FraisScolaires get fs => widget.fraisScolaires;

  @override
  void initState() {
    super.initState();
    _plans = _calculerPlans();
  }

  @override
  void dispose() {
    _montantCtrl.dispose();
    _rechercheCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Utilitaires
  // --------------------------------------------------------------------------
  String _fmtDate(DateTime d) => _formatDate(d);

  double? get _montantFixe {
    final t = _montantCtrl.text
        .trim()
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  List<String> _moisCochesOrdonnes() =>
      fs.months.where((m) => _moisCoches.contains(m)).toList();

  // --------------------------------------------------------------------------
  // Calcul du plan (aperçu = exactement ce qui sera enregistré)
  // --------------------------------------------------------------------------
  _PlanEleve _planifier(Eleve e) {
    final Map<String, double> paidSim = Map<String, double>.from(e.paid);
    final List<_LigneLot> lignes = [];
    final double? fixe = _montantFixe;
    bool precedentsSoldes = true;

    for (final m in fs.months) {
      final double requis = fs.getRequiredForMonthForEleve(e, m);
      final double dejaPaye = paidSim[m] ?? 0.0;

      if (_moisCoches.contains(m)) {
        if (requis <= 0) {
          lignes.add(_LigneLot(mois: m, montant: 0, statut: 'gratuit'));
        } else if (dejaPaye >= requis) {
          lignes.add(_LigneLot(mois: m, montant: 0, statut: 'solde'));
        } else if (!precedentsSoldes && !_autoriserSansPrecedents) {
          lignes.add(_LigneLot(mois: m, montant: 0, statut: 'bloque'));
        } else {
          final double reste = requis - dejaPaye;
          double montant = 0;
          bool plafonne = false;
          bool valide = true;
          if (_modeMontant == 'fixe') {
            if (fixe == null || fixe <= 0) {
              valide = false;
            } else if (fixe > reste) {
              montant = reste;
              plafonne = true;
            } else {
              montant = fixe;
            }
          } else {
            montant = reste;
          }
          if (!valide) {
            lignes.add(_LigneLot(mois: m, montant: 0, statut: 'sans_montant'));
          } else {
            paidSim[m] = dejaPaye + montant;
            lignes.add(_LigneLot(
              mois: m,
              montant: montant,
              statut: 'ok',
              plafonne: plafonne,
              deblocage: !precedentsSoldes,
            ));
          }
        }
      }

      if (requis > 0 && (paidSim[m] ?? 0.0) < requis) {
        precedentsSoldes = false;
      }
    }

    return _PlanEleve(eleve: e, lignes: lignes);
  }

  List<_PlanEleve> _calculerPlans() {
    final String q = _rechercheCtrl.text.toLowerCase().trim();
    final List<_PlanEleve> plans = [];
    for (final e in fs.currentData.eleves) {
      if (_filtreSection != null && e.section != _filtreSection) continue;
      if (_filtreClasse != null && e.classe != _filtreClasse) continue;
      if (q.isNotEmpty) {
        final nom = '${e.nom} ${e.postNom} ${e.prenom}'.toLowerCase();
        if (!nom.contains(q) && !e.id.toLowerCase().contains(q)) continue;
      }
      final plan = _planifier(e);
      if (_masquerSoldes && _moisCoches.isNotEmpty && plan.toutSolde) continue;
      plans.add(plan);
    }
    plans.sort((a, b) {
      final c = a.eleve.classe.compareTo(b.eleve.classe);
      if (c != 0) return c;
      final n = a.eleve.nom.toLowerCase().compareTo(b.eleve.nom.toLowerCase());
      if (n != 0) return n;
      return a.eleve.postNom
          .toLowerCase()
          .compareTo(b.eleve.postNom.toLowerCase());
    });
    return plans;
  }

  void _recalc() {
    final plans = _calculerPlans();
    final ids =
    plans.where((p) => p.aEnregistrer).map((p) => p.eleve.id).toSet();
    setState(() {
      _plans = plans;
      // On n'applique jamais qu'à ce qui est visible et enregistrable.
      _selection.retainAll(ids);
    });
  }

  String _resume(_PlanEleve p) {
    if (_moisCoches.isEmpty) {
      return 'Total déjà payé : ${formatMontant(fs.getStudentTotalPaid(p.eleve))} FC';
    }
    final parts = <String>[];
    for (final l in p.lignes) {
      switch (l.statut) {
        case 'ok':
          parts.add('✔ ${l.mois} : ${formatMontant(l.montant)} FC'
              '${l.plafonne ? ' (plafonné au reste dû)' : ''}'
              '${l.deblocage ? ' 🔓' : ''}');
          break;
        case 'solde':
          parts.add('${l.mois} : déjà soldé');
          break;
        case 'gratuit':
          parts.add('${l.mois} : mois gratuit');
          break;
        case 'bloque':
          parts.add('⚠ ${l.mois} : bloqué (mois précédent non soldé)');
          break;
        case 'sans_montant':
          parts.add('${l.mois} : entrez le montant');
          break;
      }
    }
    return parts.join('\n');
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // --------------------------------------------------------------------------
  // Actions de l'interface
  // --------------------------------------------------------------------------
  void _cocherJusquAuMoisCourant() {
    final String? courant = fs.currentSchoolMonthName;
    final int idx = courant == null ? -1 : fs.months.indexOf(courant);
    _moisCoches.clear();
    final int fin = idx < 0 ? fs.months.length - 1 : idx;
    for (var i = 0; i <= fin; i++) {
      _moisCoches.add(fs.months[i]);
    }
    _recalc();
  }

  Future<void> _choisirDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = DateTime(
        _datePaiement.year, _datePaiement.month, _datePaiement.day);
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (d != null && mounted) setState(() => _datePaiement = d);
  }

  List<String> _classesDisponibles() {
    final List<String> liste = _filtreSection != null
        ? fs.getAllDisplayClassesForSection(_filtreSection!)
        : fs.getAllDisplayClasses();
    return LinkedHashSet<String>.from(liste).toList();
  }

  Widget _carte({required String titre, String? sousTitre, required Widget child}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre,
                style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            if (sousTitre != null) ...[
              const SizedBox(height: 3),
              Text(sousTitre,
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Enregistrement du lot
  // --------------------------------------------------------------------------
  Future<void> _enregistrer() async {
    if (_enCours) return;
    if (_moisCoches.isEmpty) {
      _snack("Cochez au moins un mois.", color: Colors.orange);
      return;
    }
    if (_modeMontant == 'fixe' && (_montantFixe == null || _montantFixe! <= 0)) {
      _snack("Entrez un montant valide.", color: Colors.orange);
      return;
    }

    final selectionnes = _plans
        .where((p) => _selection.contains(p.eleve.id) && p.aEnregistrer)
        .toList();
    if (selectionnes.isEmpty) {
      _snack("Sélectionnez au moins un élève.", color: Colors.orange);
      return;
    }

    double totalPrevu = 0;
    int nbPaiementsPrevus = 0;
    for (final p in selectionnes) {
      totalPrevu += p.total;
      nbPaiementsPrevus += p.lignesOk.length;
    }
    final bool imprimer = _imprimerRecus && !widget.receiptsLocked;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer la saisie groupée"),
        content: SingleChildScrollView(
          child: Text(
            "Élèves : ${selectionnes.length}\n"
                "Mois : ${_moisCochesOrdonnes().join(', ')}\n"
                "Paiements à créer : $nbPaiementsPrevus\n"
                "Total : ${formatMontant(totalPrevu)} FC\n"
                "Date des paiements : ${_fmtDate(_datePaiement)}\n"
                "Reçus : ${imprimer ? 'imprimés (ou mis en attente)' : 'non imprimés (ancien paiement du cahier)'}\n\n"
                "Les paiements seront enregistrés comme des paiements normaux. "
                "En cas d'erreur, vous pourrez annuler ce lot pendant "
                "$_delaiAnnulationLotHeures heures depuis le bouton "
                "« Lots saisis » en haut de cette page.",
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Retour")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _enCours = true;
      _progression = 'Enregistrement...';
    });

    try {
      final String lotId = 'LOT${DateTime.now().millisecondsSinceEpoch}';
      final String creeLe = DateTime.now().toIso8601String();
      final String dateStr =
      DateTime(_datePaiement.year, _datePaiement.month, _datePaiement.day)
          .toString()
          .split(' ')[0];

      final List<MapEntry<Eleve, Map<String, dynamic>>> nouvelles = [];
      int nbEleves = 0;
      double totalEnregistre = 0;
      int nbPlafonnes = 0;
      int nbBloques = 0;

      for (final sel in selectionnes) {
        final Eleve e = sel.eleve;
        // Recalcul au moment de l'enregistrement (état le plus récent).
        final plan = _planifier(e);
        bool touche = false;

        for (final l in plan.lignes) {
          if (l.statut == 'bloque') nbBloques++;
          if (l.statut != 'ok' || l.montant <= 0) continue;

          final Map<String, dynamic> t = <String, dynamic>{
            'id': 'TXB${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
            'date': dateStr,
            'mois': l.mois,
            'amount': l.montant,
            'saisieGroupee': true,
            'lotSaisie': lotId,
            'lotCreeLe': creeLe,
          };
          if (l.deblocage) t['moisDebloque'] = true;

          e.paid[l.mois] = (e.paid[l.mois] ?? 0.0) + l.montant;
          e.transactions.add(t);
          nouvelles.add(MapEntry(e, t));
          totalEnregistre += l.montant;
          if (l.plafonne) nbPlafonnes++;
          touche = true;
        }

        if (touche) {
          nbEleves++;
          // Même nettoyage que le paiement normal.
          if (e.moisDebloque != null) {
            final String moisDeb = e.moisDebloque!;
            final double requisDeb = fs.getRequiredForMonthForEleve(e, moisDeb);
            if ((e.paid[moisDeb] ?? 0.0) >= requisDeb) e.moisDebloque = null;
          }
        }
      }

      if (!imprimer) {
        for (final en in nouvelles) {
          en.value['receiptConfirmed'] = true;
        }
      }

      // Sauvegarde AVANT toute impression : les paiements sont sécurisés.
      await fs.saveData();

      int nbImprimes = 0;
      if (imprimer) {
        int i = 0;
        for (final en in nouvelles) {
          i++;
          if (mounted) {
            setState(() => _progression = 'Impression des reçus $i/${nouvelles.length}...');
          }
          final bool printed = await fs.printOrQueuePrincipalReceipt(
              eleve: en.key, transaction: en.value);
          en.value['receiptConfirmed'] = printed;
          if (printed) nbImprimes++;
        }
        await fs.saveData();
      }

      if (!mounted) return;
      setState(() {
        _selection.clear();
      });
      _recalc();

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("✅ Saisie groupée terminée"),
          content: SingleChildScrollView(
            child: Text(
              "$nbEleves élève(s) • ${nouvelles.length} paiement(s)\n"
                  "Total enregistré : ${formatMontant(totalEnregistre)} FC\n"
                  "Date des paiements : ${_fmtDate(_datePaiement)}\n"
                  "${imprimer ? 'Reçus imprimés : $nbImprimes/${nouvelles.length} (les autres sont en attente)\n' : ''}"
                  "${nbPlafonnes > 0 ? '$nbPlafonnes paiement(s) plafonné(s) au reste dû\n' : ''}"
                  "${nbBloques > 0 ? '$nbBloques mois ignoré(s) (mois précédent non soldé)\n' : ''}"
                  "\nNuméro du lot : $lotId",
            ),
          ),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        _snack("❌ Erreur pendant l'enregistrement : $e", color: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _enCours = false;
          _progression = '';
        });
      }
    }
  }

  // --------------------------------------------------------------------------
  // Interface
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final int nbSel = _selection.length;
    double totalSel = 0;
    for (final p in _plans) {
      if (_selection.contains(p.eleve.id)) totalSel += p.total;
    }
    final List<String> sections = LinkedHashSet<String>.from(fs.config.sections).toList();
    final List<String> classes = _classesDisponibles();
    if (_filtreClasse != null && !classes.contains(_filtreClasse)) {
      classes.add(_filtreClasse!);
    }
    final int nbSelectionnables = _plans.where((p) => p.aEnregistrer).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Saisie groupée des anciens paiements"),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "Lots saisis (voir / annuler)",
            onPressed: _enCours
                ? null
                : () => _LotsSaisie.afficher(context, fs, _recalc),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _enCours,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "Cette page sert à enregistrer rapidement les paiements "
                            "déjà faits avant l'utilisation de l'application "
                            "(cahier) : 1) cochez le(s) mois, 2) choisissez le "
                            "montant, 3) sélectionnez les élèves, 4) enregistrez.",
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    _carte(
                      titre: "1. Mois à enregistrer",
                      sousTitre:
                      "Vous pouvez cocher plusieurs mois : chaque élève sera "
                          "enregistré pour chacun d'eux.",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: fs.months
                                .map((m) => FilterChip(
                              label: Text(m),
                              selected: _moisCoches.contains(m),
                              onSelected: (v) {
                                if (v) {
                                  _moisCoches.add(m);
                                } else {
                                  _moisCoches.remove(m);
                                }
                                _recalc();
                              },
                            ))
                                .toList(),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              TextButton(
                                onPressed: _cocherJusquAuMoisCourant,
                                child: const Text("Jusqu'au mois en cours"),
                              ),
                              TextButton(
                                onPressed: () {
                                  _moisCoches.clear();
                                  _recalc();
                                },
                                child: const Text("Effacer"),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _carte(
                      titre: "2. Montant",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'complet',
                                label: Text("Montant complet"),
                                icon: Icon(Icons.done_all),
                              ),
                              ButtonSegment(
                                value: 'fixe',
                                label: Text("Montant unique"),
                                icon: Icon(Icons.pin),
                              ),
                            ],
                            selected: {_modeMontant},
                            onSelectionChanged: (s) {
                              _modeMontant = s.first;
                              _recalc();
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _modeMontant == 'complet'
                                ? "Chaque élève est enregistré pour le montant "
                                "complet de chaque mois coché (selon les "
                                "paramètres, exceptions comprises)."
                                : "Le même montant est enregistré pour chaque "
                                "mois coché et chaque élève (jamais plus que "
                                "ce qui reste à payer pour le mois).",
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.grey),
                          ),
                          if (_modeMontant == 'fixe') ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _montantCtrl,
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9., ]')),
                              ],
                              decoration: const InputDecoration(
                                labelText: "Montant par élève et par mois",
                                suffixText: "FC",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => _recalc(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _carte(
                      titre: "3. Date des paiements",
                      sousTitre:
                      "Choisissez la date réelle des paiements du cahier, "
                          "pour que les rapports journaliers restent exacts.",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.event, color: Colors.indigo),
                              const SizedBox(width: 8),
                              Text(_fmtDate(_datePaiement),
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              OutlinedButton(
                                onPressed: _choisirDate,
                                child: const Text("Changer la date"),
                              ),
                            ],
                          ),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text("Options",
                                style: TextStyle(fontSize: 13.5)),
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _autoriserSansPrecedents,
                                onChanged: (v) {
                                  _autoriserSansPrecedents = v;
                                  _recalc();
                                },
                                title: const Text(
                                    "Autoriser même si les mois précédents ne sont pas soldés",
                                    style: TextStyle(fontSize: 13)),
                                subtitle: const Text(
                                    "Par défaut, un mois n'est enregistré que si les "
                                        "mois d'avant sont soldés (comme d'habitude).",
                                    style: TextStyle(fontSize: 11)),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _imprimerRecus && !widget.receiptsLocked,
                                onChanged: widget.receiptsLocked
                                    ? null
                                    : (v) => setState(() => _imprimerRecus = v),
                                title: const Text(
                                    "Imprimer un reçu pour chaque paiement",
                                    style: TextStyle(fontSize: 13)),
                                subtitle: Text(
                                    widget.receiptsLocked
                                        ? "🔒 L'impression est bloquée."
                                        : "Désactivé par défaut : ce sont d'anciens "
                                        "paiements, déjà notés dans le cahier.",
                                    style: const TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _carte(
                      titre: "4. Élèves",
                      sousTitre:
                      "Filtrez par section / classe, puis « Tout sélectionner » "
                          "et décochez ceux qui n'ont pas payé.",
                      child: Column(
                        children: [
                          TextField(
                            controller: _rechercheCtrl,
                            decoration: const InputDecoration(
                              labelText: "Rechercher par ID ou nom",
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _recalc(),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  value: _filtreSection,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: "Section",
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text("Toutes")),
                                    ...sections.map((s) =>
                                        DropdownMenuItem<String?>(
                                            value: s, child: Text(s))),
                                  ],
                                  onChanged: (v) {
                                    _filtreSection = v;
                                    if (_filtreClasse != null &&
                                        !_classesDisponibles()
                                            .contains(_filtreClasse)) {
                                      _filtreClasse = null;
                                    }
                                    _recalc();
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  value: _filtreClasse,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: "Classe",
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text("Toutes")),
                                    ...classes.map((c) =>
                                        DropdownMenuItem<String?>(
                                            value: c, child: Text(c))),
                                  ],
                                  onChanged: (v) {
                                    _filtreClasse = v;
                                    _recalc();
                                  },
                                ),
                              ),
                            ],
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _masquerSoldes,
                            onChanged: (v) {
                              _masquerSoldes = v;
                              _recalc();
                            },
                            title: const Text(
                                "Masquer ceux qui ont déjà soldé les mois cochés",
                                style: TextStyle(fontSize: 13)),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "${_plans.length} élève(s) affiché(s) • $nbSelectionnables sélectionnable(s)",
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              TextButton(
                                onPressed: nbSelectionnables == 0
                                    ? null
                                    : () => setState(() {
                                  _selection.addAll(_plans
                                      .where((p) => p.aEnregistrer)
                                      .map((p) => p.eleve.id));
                                }),
                                child: const Text("Tout sélectionner"),
                              ),
                              TextButton(
                                onPressed: _selection.isEmpty
                                    ? null
                                    : () => setState(() => _selection.clear()),
                                child: const Text("Aucun"),
                              ),
                            ],
                          ),
                          if (_moisCoches.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                "⚠ Cochez d'abord au moins un mois (étape 1) pour pouvoir sélectionner des élèves.",
                                style: TextStyle(
                                    color: Colors.deepOrange, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                  final p = _plans[i];
                  final e = p.eleve;
                  final bool selectionnable = p.aEnregistrer;
                  return Card(
                    margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    child: CheckboxListTile(
                      value: _selection.contains(e.id),
                      onChanged: selectionnable
                          ? (v) => setState(() {
                        if (v == true) {
                          _selection.add(e.id);
                        } else {
                          _selection.remove(e.id);
                        }
                      })
                          : null,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('${e.nom} ${e.postNom} ${e.prenom}'),
                      subtitle: Text(
                        '${e.classe} | ${e.section}\n${_resume(p)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: selectionnable ? null : Colors.grey,
                        ),
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
                childCount: _plans.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 6),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_enCours) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text(_progression, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "$nbSel élève(s) sélectionné(s)\n"
                          "Total : ${formatMontant(totalSel)} FC",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text("Enregistrer"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    onPressed: (nbSel > 0 && !_enCours) ? _enregistrer : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ⚡ NOUVEAU — GRILLE TYPE CAHIER (élèves × mois)
// ============================================================================
// Un tableau comme dans le cahier : une ligne par élève, une colonne par mois.
//   - Appuyer sur une case la COCHE, et coche aussi tous les mois précédents
//     non encore payés de cet élève (règle normale : on paie dans l'ordre).
//     Appuyer sur une case cochée la décoche, ainsi que les mois suivants.
//   - Appuyer sur le NOM D'UN MOIS (en-tête) coche (ou décoche) ce mois pour
//     tous les élèves affichés.
//   - Les cases vertes sont déjà soldées : elles ne se modifient pas.
//   - Chaque case cochée est enregistrée pour le montant COMPLET restant du
//     mois (exceptions de montant respectées).
// Rien n'est enregistré tant qu'on n'appuie pas sur « Enregistrer ».
// Les paiements créés portent les mêmes marqueurs de lot que la saisie
// groupée : ils sont visibles et annulables dans « Lots saisis ».
// ============================================================================

class _ResumeGrille {
  final int eleves;
  final int paiements;
  final double total;

  const _ResumeGrille(this.eleves, this.paiements, this.total);
}

class GrilleCahierScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  final bool receiptsLocked;

  const GrilleCahierScreen({
    super.key,
    required this.fraisScolaires,
    required this.receiptsLocked,
  });

  @override
  State<GrilleCahierScreen> createState() => _GrilleCahierScreenState();
}

class _GrilleCahierScreenState extends State<GrilleCahierScreen> {
  static const double _largeurNom = 190;
  static const double _largeurCelluleMin = 58;
  static const double _hauteurLigne = 54;
  static const double _hauteurEntete = 42;

  // eleveId -> mois cochés (nouveaux paiements à enregistrer)
  final Map<String, Set<String>> _coches = {};
  final TextEditingController _rechercheCtrl = TextEditingController();
  String? _filtreSection;
  String? _filtreClasse;
  bool _masquerSoldes = true;
  bool _cocherSeulementCeMois = false;
  bool _imprimerRecus = false;
  DateTime _datePaiement = DateTime.now();
  List<Eleve> _eleves = [];
  bool _enCours = false;
  String _progression = '';
  int _seq = 0;

  FraisScolaires get fs => widget.fraisScolaires;

  @override
  void initState() {
    super.initState();
    _recalc();
  }

  @override
  void dispose() {
    _rechercheCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Utilitaires
  // --------------------------------------------------------------------------
  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  List<String> _classesDisponibles() {
    final List<String> liste = _filtreSection != null
        ? fs.getAllDisplayClassesForSection(_filtreSection!)
        : fs.getAllDisplayClasses();
    return LinkedHashSet<String>.from(liste).toList();
  }

  String _libelleMois(String m) => m.length >= 3 ? m.substring(0, 3) : m;

  // 'gratuit' | 'solde' | 'coche' | 'partiel' | 'vide'
  String _statut(Eleve e, String mois) {
    final double requis = fs.getRequiredForMonthForEleve(e, mois);
    if (requis <= 0) return 'gratuit';
    final double paye = e.paid[mois] ?? 0.0;
    if (paye >= requis) return 'solde';
    if (_coches[e.id]?.contains(mois) ?? false) return 'coche';
    if (paye > 0) return 'partiel';
    return 'vide';
  }

  // --------------------------------------------------------------------------
  // Liste des élèves affichés
  // --------------------------------------------------------------------------
  void _recalc() {
    final String q = _rechercheCtrl.text.toLowerCase().trim();
    final List<Eleve> liste = [];
    for (final e in fs.currentData.eleves) {
      if (_filtreSection != null && e.section != _filtreSection) continue;
      if (_filtreClasse != null && e.classe != _filtreClasse) continue;
      if (q.isNotEmpty) {
        final nom = '${e.nom} ${e.postNom} ${e.prenom}'.toLowerCase();
        if (!nom.contains(q) && !e.id.toLowerCase().contains(q)) continue;
      }
      if (_masquerSoldes && !(_coches[e.id]?.isNotEmpty ?? false)) {
        final bool toutSolde = fs.months.every((m) {
          final s = _statut(e, m);
          return s == 'solde' || s == 'gratuit';
        });
        if (toutSolde) continue;
      }
      liste.add(e);
    }
    liste.sort((a, b) {
      final c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      final n = a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
      if (n != 0) return n;
      return a.postNom.toLowerCase().compareTo(b.postNom.toLowerCase());
    });
    setState(() => _eleves = liste);
  }

  // --------------------------------------------------------------------------
  // Cocher / décocher
  // --------------------------------------------------------------------------
  void _cocher(Eleve e, String mois) {
    final int idx = fs.months.indexOf(mois);
    if (idx < 0) return;
    final Set<String> set = _coches.putIfAbsent(e.id, () => <String>{});
    final int debut = _cocherSeulementCeMois ? idx : 0;
    for (var i = debut; i <= idx; i++) {
      final String m = fs.months[i];
      final String s = _statut(e, m);
      if (s == 'vide' || s == 'partiel') set.add(m);
    }
  }

  void _decocher(Eleve e, String mois) {
    final Set<String>? set = _coches[e.id];
    if (set == null) return;
    final int idx = fs.months.indexOf(mois);
    if (idx < 0) return;
    if (_cocherSeulementCeMois) {
      set.remove(mois);
    } else {
      for (var i = idx; i < fs.months.length; i++) {
        set.remove(fs.months[i]);
      }
    }
    if (set.isEmpty) _coches.remove(e.id);
  }

  void _tapCellule(Eleve e, String mois) {
    final String s = _statut(e, mois);
    setState(() {
      if (s == 'coche') {
        _decocher(e, mois);
      } else if (s == 'vide' || s == 'partiel') {
        _cocher(e, mois);
      }
    });
  }

  void _toggleColonne(String mois) {
    final concernes = _eleves.where((e) {
      final s = _statut(e, mois);
      return s == 'vide' || s == 'partiel' || s == 'coche';
    }).toList();
    if (concernes.isEmpty) return;
    final bool tousCoches = concernes.every((e) => _statut(e, mois) == 'coche');
    setState(() {
      for (final e in concernes) {
        if (tousCoches) {
          _decocher(e, mois);
        } else {
          _cocher(e, mois);
        }
      }
    });
  }

  void _toutEffacer() {
    setState(() => _coches.clear());
    _recalc();
  }

  Future<void> _choisirDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = DateTime(
        _datePaiement.year, _datePaiement.month, _datePaiement.day);
    final d = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (d != null && mounted) setState(() => _datePaiement = d);
  }

  // --------------------------------------------------------------------------
  // Calcul de ce qui sera enregistré (aperçu = enregistrement)
  // --------------------------------------------------------------------------
  List<_LigneLot> _lignesPour(Eleve e) {
    final Set<String> set = _coches[e.id] ?? const <String>{};
    final Map<String, double> paidSim = Map<String, double>.from(e.paid);
    final List<_LigneLot> lignes = [];
    bool precedentsSoldes = true;

    for (final m in fs.months) {
      final double requis = fs.getRequiredForMonthForEleve(e, m);
      final double dejaPaye = paidSim[m] ?? 0.0;

      if (set.contains(m)) {
        if (requis <= 0) {
          lignes.add(_LigneLot(mois: m, montant: 0, statut: 'gratuit'));
        } else if (dejaPaye >= requis) {
          lignes.add(_LigneLot(mois: m, montant: 0, statut: 'solde'));
        } else if (!precedentsSoldes && !_cocherSeulementCeMois) {
          lignes.add(_LigneLot(mois: m, montant: 0, statut: 'bloque'));
        } else {
          final double montant = requis - dejaPaye;
          paidSim[m] = dejaPaye + montant;
          lignes.add(_LigneLot(
            mois: m,
            montant: montant,
            statut: 'ok',
            deblocage: !precedentsSoldes,
          ));
        }
      }

      if (requis > 0 && (paidSim[m] ?? 0.0) < requis) {
        precedentsSoldes = false;
      }
    }
    return lignes;
  }

  _ResumeGrille _calculerResume() {
    final Map<String, Eleve> parId = {
      for (final e in fs.currentData.eleves) e.id: e
    };
    int nbEleves = 0;
    int nbPaiements = 0;
    double total = 0;
    for (final id in _coches.keys) {
      final Eleve? e = parId[id];
      if (e == null) continue;
      final ok = _lignesPour(e).where((l) => l.statut == 'ok' && l.montant > 0);
      if (ok.isEmpty) continue;
      nbEleves++;
      for (final l in ok) {
        nbPaiements++;
        total += l.montant;
      }
    }
    return _ResumeGrille(nbEleves, nbPaiements, total);
  }

  // --------------------------------------------------------------------------
  // Enregistrement
  // --------------------------------------------------------------------------
  Future<void> _enregistrer() async {
    if (_enCours) return;

    final Map<String, Eleve> parId = {
      for (final e in fs.currentData.eleves) e.id: e
    };
    final List<Eleve> aTraiter = [];
    double totalPrevu = 0;
    int nbPaiementsPrevus = 0;
    final Set<String> moisConcernes = {};

    for (final id in _coches.keys) {
      final Eleve? e = parId[id];
      if (e == null) continue;
      final ok = _lignesPour(e)
          .where((l) => l.statut == 'ok' && l.montant > 0)
          .toList();
      if (ok.isEmpty) continue;
      aTraiter.add(e);
      for (final l in ok) {
        totalPrevu += l.montant;
        nbPaiementsPrevus++;
        moisConcernes.add(l.mois);
      }
    }

    if (aTraiter.isEmpty) {
      _snack("Cochez au moins une case dans la grille.",
          color: Colors.orange);
      return;
    }

    final bool imprimer = _imprimerRecus && !widget.receiptsLocked;
    final String moisTexte =
    fs.months.where((m) => moisConcernes.contains(m)).join(', ');

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer l'enregistrement"),
        content: SingleChildScrollView(
          child: Text(
            "Élèves : ${aTraiter.length}\n"
                "Mois : $moisTexte\n"
                "Paiements à créer : $nbPaiementsPrevus\n"
                "Total : ${formatMontant(totalPrevu)} FC\n"
                "Date des paiements : ${_formatDate(_datePaiement)}\n"
                "Reçus : ${imprimer ? 'imprimés (ou mis en attente)' : 'non imprimés (ancien paiement du cahier)'}\n\n"
                "Les paiements seront enregistrés comme des paiements normaux. "
                "En cas d'erreur, vous pourrez annuler ce lot pendant "
                "${_LotsSaisie.delaiAnnulationHeures} heures depuis le bouton "
                "« Lots saisis » en haut de cette page.",
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Retour")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    setState(() {
      _enCours = true;
      _progression = 'Enregistrement...';
    });

    try {
      final String lotId = 'LOT${DateTime.now().millisecondsSinceEpoch}';
      final String creeLe = DateTime.now().toIso8601String();
      final String dateStr =
      DateTime(_datePaiement.year, _datePaiement.month, _datePaiement.day)
          .toString()
          .split(' ')[0];

      final List<MapEntry<Eleve, Map<String, dynamic>>> nouvelles = [];
      int nbEleves = 0;
      double totalEnregistre = 0;

      for (final e in aTraiter) {
        // Recalcul au dernier moment (état le plus récent).
        final lignes = _lignesPour(e)
            .where((l) => l.statut == 'ok' && l.montant > 0)
            .toList();
        bool touche = false;

        for (final l in lignes) {
          final Map<String, dynamic> t = <String, dynamic>{
            'id': 'TXB${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
            'date': dateStr,
            'mois': l.mois,
            'amount': l.montant,
            'saisieGroupee': true,
            'lotSaisie': lotId,
            'lotCreeLe': creeLe,
          };
          if (l.deblocage) t['moisDebloque'] = true;

          e.paid[l.mois] = (e.paid[l.mois] ?? 0.0) + l.montant;
          e.transactions.add(t);
          nouvelles.add(MapEntry(e, t));
          totalEnregistre += l.montant;
          touche = true;
        }

        if (touche) {
          nbEleves++;
          // Même nettoyage que le paiement normal.
          if (e.moisDebloque != null) {
            final String moisDeb = e.moisDebloque!;
            final double requisDeb = fs.getRequiredForMonthForEleve(e, moisDeb);
            if ((e.paid[moisDeb] ?? 0.0) >= requisDeb) e.moisDebloque = null;
          }
        }
      }

      if (!imprimer) {
        for (final en in nouvelles) {
          en.value['receiptConfirmed'] = true;
        }
      }

      // Sauvegarde AVANT toute impression : les paiements sont sécurisés.
      await fs.saveData();

      int nbImprimes = 0;
      if (imprimer) {
        int i = 0;
        for (final en in nouvelles) {
          i++;
          if (mounted) {
            setState(() =>
            _progression = 'Impression des reçus $i/${nouvelles.length}...');
          }
          final bool printed = await fs.printOrQueuePrincipalReceipt(
              eleve: en.key, transaction: en.value);
          en.value['receiptConfirmed'] = printed;
          if (printed) nbImprimes++;
        }
        await fs.saveData();
      }

      if (!mounted) return;
      _coches.clear();
      _recalc();

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("✅ Enregistrement terminé"),
          content: SingleChildScrollView(
            child: Text(
              "$nbEleves élève(s) • ${nouvelles.length} paiement(s)\n"
                  "Total enregistré : ${formatMontant(totalEnregistre)} FC\n"
                  "Date des paiements : ${_formatDate(_datePaiement)}\n"
                  "${imprimer ? 'Reçus imprimés : $nbImprimes/${nouvelles.length} (les autres sont en attente)\n' : ''}"
                  "\nNuméro du lot : $lotId",
            ),
          ),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        _snack("❌ Erreur pendant l'enregistrement : $e", color: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _enCours = false;
          _progression = '';
        });
      }
    }
  }

  // --------------------------------------------------------------------------
  // Interface
  // --------------------------------------------------------------------------
  Widget _icone(String statut) {
    switch (statut) {
      case 'solde':
        return Icon(Icons.check_circle, color: Colors.green.shade600, size: 22);
      case 'gratuit':
        return const Text('—',
            style: TextStyle(color: Colors.grey, fontSize: 16));
      case 'coche':
        return const Icon(Icons.check_box, color: Colors.indigo, size: 26);
      case 'partiel':
        return const Icon(Icons.indeterminate_check_box,
            color: Colors.orange, size: 26);
      default:
        return const Icon(Icons.check_box_outline_blank,
            color: Colors.grey, size: 26);
    }
  }

  Widget _barreFiltres() {
    final List<String> sections =
    LinkedHashSet<String>.from(fs.config.sections).toList();
    final List<String> classes = _classesDisponibles();
    if (_filtreClasse != null && !classes.contains(_filtreClasse)) {
      classes.add(_filtreClasse!);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _rechercheCtrl,
                  decoration: const InputDecoration(
                    labelText: "Rechercher (ID ou nom)",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => _recalc(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String?>(
                  value: _filtreSection,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Section",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text("Toutes")),
                    ...sections.map((s) => DropdownMenuItem<String?>(
                        value: s, child: Text(s))),
                  ],
                  onChanged: (v) {
                    _filtreSection = v;
                    if (_filtreClasse != null &&
                        !_classesDisponibles().contains(_filtreClasse)) {
                      _filtreClasse = null;
                    }
                    _recalc();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String?>(
                  value: _filtreClasse,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Classe",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text("Toutes")),
                    ...classes.map((c) =>
                        DropdownMenuItem<String?>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) {
                    _filtreClasse = v;
                    _recalc();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.event, size: 18, color: Colors.indigo),
              Text("Date des paiements : ${_formatDate(_datePaiement)}",
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
              OutlinedButton(
                onPressed: _choisirDate,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: const Text("Changer"),
              ),
              FilterChip(
                label: const Text("Masquer les élèves soldés"),
                selected: _masquerSoldes,
                onSelected: (v) {
                  _masquerSoldes = v;
                  _recalc();
                },
              ),
              FilterChip(
                label: const Text("Cocher seulement ce mois"),
                selected: _cocherSeulementCeMois,
                tooltip:
                "Par défaut, cocher un mois coche aussi les mois précédents non payés.",
                onSelected: (v) => setState(() => _cocherSeulementCeMois = v),
              ),
              FilterChip(
                label: const Text("Imprimer les reçus"),
                selected: _imprimerRecus && !widget.receiptsLocked,
                tooltip: widget.receiptsLocked
                    ? "L'impression est bloquée."
                    : "Désactivé par défaut : anciens paiements du cahier.",
                onSelected: widget.receiptsLocked
                    ? null
                    : (v) => setState(() => _imprimerRecus = v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Appuyez sur une case pour la cocher (les mois précédents non payés "
                  "sont cochés aussi). Appuyez sur le nom d'un mois pour toute la "
                  "colonne. Vert = déjà soldé. Orange = paiement partiel.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entete(double largeurCellule) {
    final String? courant = fs.currentSchoolMonthName;
    return Container(
      height: _hauteurEntete,
      color: Colors.indigo.shade50,
      child: Row(
        children: [
          const SizedBox(
            width: _largeurNom,
            child: Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text("Élève",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          ...fs.months.map((m) => InkWell(
            onTap: () => _toggleColonne(m),
            child: SizedBox(
              width: largeurCellule,
              height: _hauteurEntete,
              child: Center(
                child: Text(
                  _libelleMois(m),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: m == courant ? Colors.deepOrange : Colors.indigo,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _ligne(Eleve e, double largeurCellule, int index) {
    return Container(
      height: _hauteurLigne,
      decoration: BoxDecoration(
        color: index.isEven ? null : Colors.grey.withAlpha(18),
        border: Border(
          bottom: BorderSide(color: Colors.grey.withAlpha(60), width: 0.6),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _largeurNom,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.nom} ${e.postNom} ${e.prenom}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    e.classe,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          ...fs.months.map((m) {
            final String s = _statut(e, m);
            return InkWell(
              onTap: (s == 'vide' || s == 'partiel' || s == 'coche')
                  ? () => _tapCellule(e, m)
                  : null,
              child: Container(
                width: largeurCellule,
                height: _hauteurLigne,
                color: s == 'coche' ? Colors.indigo.withAlpha(22) : null,
                child: Center(child: _icone(s)),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _grille() {
    if (_eleves.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Aucun élève à afficher (ou tous sont déjà soldés).",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (ctx, c) {
        final double minLargeur =
            _largeurNom + _largeurCelluleMin * fs.months.length;
        final double largeur = c.maxWidth < minLargeur ? minLargeur : c.maxWidth;
        final double largeurCellule =
            (largeur - _largeurNom) / fs.months.length;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: largeur,
            height: c.maxHeight,
            child: Column(
              children: [
                _entete(largeurCellule),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: _eleves.length,
                    itemExtent: _hauteurLigne,
                    itemBuilder: (context, i) =>
                        _ligne(_eleves[i], largeurCellule, i),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final _ResumeGrille r = _calculerResume();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Grille type cahier"),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: "Tout décocher",
            onPressed: (_coches.isEmpty || _enCours) ? null : _toutEffacer,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: "Lots saisis (voir / annuler)",
            onPressed: _enCours
                ? null
                : () => _LotsSaisie.afficher(context, fs, _recalc),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _enCours,
        child: Column(
          children: [
            _barreFiltres(),
            const Divider(height: 1),
            Expanded(child: _grille()),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 6),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_enCours) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text(_progression, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${r.eleves} élève(s) • ${r.paiements} paiement(s)\n"
                          "Total : ${formatMontant(r.total)} FC",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text("Enregistrer"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    onPressed:
                    (r.paiements > 0 && !_enCours) ? _enregistrer : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}