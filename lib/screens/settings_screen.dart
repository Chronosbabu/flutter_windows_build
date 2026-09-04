import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../frais_scolaires.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/epson_printer_service.dart';
import 'recovery_screen.dart';
import 'aide.dart';

class SettingsScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const SettingsScreen({super.key, required this.fraisScolaires});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final nameController  = TextEditingController();
  final feeController   = TextEditingController();
  String? selectedYear;

  String? selectedSectionForFee;
  String? selectedClasseScopeForFee;
  String? selectedSectionForException;
  String? selectedMonthForException;
  String? selectedClasseScopeForException;
  final TextEditingController newClasseController = TextEditingController();

  // ⚡ Imprimante Epson TM-T20III en USB (via spouleur Windows),
  // remplace l'ancienne détection de ports COM Bluetooth.
  List<String> _availablePrinters = [];
  String?      _selectedPrinterName;
  bool         _loadingPrinters = false;
  bool         _testingPrint    = false;

  // ⚡ NOUVEAU — Logo de l'école imprimé sur les reçus (gauche + droite,
  // avec le nom de l'établissement centré entre les deux).
  Uint8List? _logoBytes;
  bool       _loadingLogo = false;

  bool _showBackupReminder = true;

  @override
  void initState() {
    super.initState();
    nameController.text = widget.fraisScolaires.config.schoolName;
    selectedYear        = widget.fraisScolaires.currentYear;
    selectedSectionForFee =
    widget.fraisScolaires.config.sections.isNotEmpty
        ? widget.fraisScolaires.config.sections.first
        : null;
    _loadPrinterConfig();
    _loadSavedLogo();
  }

  Future<void> _loadPrinterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    // ⚡ Clé de préférence : on stocke le NOM de l'imprimante Windows
    // (ex: "EPSON TM-T20III Receipt") au lieu d'un port COM Bluetooth.
    final saved = prefs.getString('printer_name');
    if (saved != null && saved.isNotEmpty) {
      setState(() => _selectedPrinterName = saved);
    }
  }

  void _openAide() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AideScreen()));
  }

  // ====================================================================
  // VÉRIFICATION MOT DE PASSE
  // ====================================================================
  Future<bool> _verifyBackupPassword() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Veuillez d'abord définir un mot de passe de sauvegarde")),
      );
      return false;
    }

    final passController = TextEditingController();
    bool? isCorrect = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vérification de Sécurité"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                "Entrez votre mot de passe de sauvegarde pour continuer"),
            const SizedBox(height: 15),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: "Mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (passController.text.trim() ==
                  appState.backupPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Mot de passe incorrect")),
                );
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
    return isCorrect ?? false;
  }

  // ====================================================================
  // NOM DE L'ÉCOLE
  // ====================================================================
  void _saveSchoolName() async {
    final newName = nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Le nom ne peut pas être vide")),
      );
      return;
    }
    widget.fraisScolaires.config.schoolName = newName;
    await widget.fraisScolaires.saveData();
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.updateSchoolName(newName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "✅ Nom de l'école enregistré — il sera utilisé sur les "
                    "prochains PDF et reçus imprimés")),
      );
    }
  }

  // ====================================================================
  // MOT DE PASSE
  // ====================================================================
  void _changeBackupPassword(BuildContext context, AppState appState) async {
    if (appState.backupPassword == null) {
      _setBackupPassword(context, appState);
      return;
    }

    final oldPassController = TextEditingController();
    bool? oldCorrect = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Changer le mot de passe"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Entrez votre ancien mot de passe"),
            const SizedBox(height: 10),
            TextField(
              controller: oldPassController,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: "Ancien mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (oldPassController.text.trim() ==
                  appState.backupPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Ancien mot de passe incorrect")),
                );
              }
            },
            child: const Text("Continuer"),
          ),
        ],
      ),
    );

    if (oldCorrect != true) return;

    final newPassController    = TextEditingController();
    final confirmPassController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouveau mot de passe"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassController,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: "Nouveau mot de passe (min 6 caractères)"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmPassController,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: "Confirmer le nouveau mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final newPass     = newPassController.text.trim();
              final confirmPass = confirmPassController.text.trim();
              if (newPass.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          "Le mot de passe doit contenir au moins 6 caractères")),
                );
                return;
              }
              if (newPass != confirmPass) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          "Les deux mots de passe ne correspondent pas")),
                );
                return;
              }
              appState.setBackupPassword(newPass);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text("✅ Mot de passe changé avec succès")),
              );
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // DÉCONNEXION — AVEC AVERTISSEMENT ET SAUVEGARDE OBLIGATOIRE
  // ====================================================================
  void _deconnexion() async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text("Déconnexion"),
          ],
        ),
        content: const Text(
          "⚠️ ATTENTION — La déconnexion va supprimer TOUTES les données "
              "locales de votre PC (élèves, paiements, configuration).\n\n"
              "Pour ne pas perdre vos données, vous devez absolument les "
              "sauvegarder sur le serveur avant de vous déconnecter.\n\n"
              "Que voulez-vous faire ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text("Annuler"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.cloud_upload),
            label: const Text("Sauvegarder puis déconnecter"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'save_then_logout'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text("Déconnecter sans sauvegarder"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'logout_only'),
          ),
        ],
      ),
    );

    if (action == null || action == 'cancel') return;

    if (action == 'save_then_logout') {
      final appState =
      Provider.of<AppState>(context, listen: false);
      if (appState.schoolCode == null ||
          appState.backupPassword == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Impossible de sauvegarder : code école ou mot de passe manquant")),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("⏳ Sauvegarde en cours..."),
              duration: Duration(seconds: 2)),
        );
      }

      final backupResult = await widget.fraisScolaires.backupToServer(
        appState.schoolCode!,
        appState.backupPassword!,
      );
      final bool backupSuccess = backupResult['success'] == true;

      if (!backupSuccess) {
        if (mounted) {
          final String errMsg =
              backupResult['error']?.toString() ?? "Erreur inconnue";
          final forceLogout = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Échec de la sauvegarde"),
              content: Text(
                "La sauvegarde sur le serveur a échoué :\n$errMsg\n\n"
                    "Voulez-vous quand même vous déconnecter ?\n"
                    "(Vos données locales seront perdues)",
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("Annuler")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Déconnecter quand même"),
                ),
              ],
            ),
          );
          if (forceLogout != true) return;
        } else {
          return;
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Sauvegarde réussie !"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    await widget.fraisScolaires.clearLocalData();

    if (mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.logout();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RecoveryScreen()),
            (route) => false,
      );
    }
  }

  // ====================================================================
  // IMPRIMANTE — détection des imprimantes Windows (Epson TM-T20III en USB).
  // ====================================================================
  Future<void> _detectPrinters() async {
    setState(() => _loadingPrinters = true);
    final printers = await EscPosPrinterService.getAvailablePrinters();
    setState(() {
      _availablePrinters = printers;
      _loadingPrinters   = false;
      if (_selectedPrinterName != null &&
          !_availablePrinters.contains(_selectedPrinterName)) {
        _availablePrinters.insert(0, _selectedPrinterName!);
      }
    });
    if (printers.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Aucune imprimante détectée. Vérifiez que l'Epson TM-T20III "
                  "est branchée en USB et que son pilote est installé "
                  "(elle doit apparaître dans \"Imprimantes et scanners\" "
                  "de Windows)."),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _saveSelectedPrinter(String printerName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_name', printerName);
    setState(() => _selectedPrinterName = printerName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Imprimante \"$printerName\" sauvegardée")),
      );
    }
  }

  // ====================================================================
  // ⚡ NOUVEAU — LOGO DE L'ÉCOLE POUR LES REÇUS
  // ====================================================================
  // Le logo est stocké localement sur ce PC (comme le nom de
  // l'imprimante), pas dans la sauvegarde serveur : chaque poste peut
  // donc avoir son propre fichier logo. Il est toujours réenregistré en
  // PNG pour garder un chemin de fichier stable quel que soit le format
  // d'origine (jpg, png...) choisi par l'utilisateur.
  Future<String> _logoFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/school_logo.png';
  }

  Future<void> _loadSavedLogo() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLogo = prefs.getBool('has_logo') ?? false;
    if (!hasLogo) return;
    try {
      final path = await _logoFilePath();
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() => _logoBytes = bytes);
      }
    } catch (_) {}
  }

  Future<void> _pickLogo() async {
    setState(() => _loadingLogo = true);
    try {
      const typeGroup = XTypeGroup(
        label: 'images',
        extensions: ['png', 'jpg', 'jpeg'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) {
        setState(() => _loadingLogo = false);
        return;
      }

      final rawBytes = await file.readAsBytes();
      final decoded  = img.decodeImage(rawBytes);
      if (decoded == null) {
        setState(() => _loadingLogo = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                Text("⚠️ Image invalide ou format non supporté")),
          );
        }
        return;
      }

      final pngBytes = Uint8List.fromList(img.encodePng(decoded));
      final path     = await _logoFilePath();
      await File(path).writeAsBytes(pngBytes);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_logo', true);

      setState(() {
        _logoBytes   = pngBytes;
        _loadingLogo = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "✅ Logo enregistré — il apparaîtra sur les prochains reçus"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _loadingLogo = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
              Text("⚠️ Erreur lors de la sélection du logo : $e")),
        );
      }
    }
  }

  Future<void> _removeLogo() async {
    try {
      final path = await _logoFilePath();
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_logo', false);
    setState(() => _logoBytes = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Logo retiré")),
      );
    }
  }

  Future<void> _testPrint() async {
    if (_selectedPrinterName == null) return;
    setState(() => _testingPrint = true);
    final ok = await EscPosPrinterService.printReceipt(
      printerName:  _selectedPrinterName!,
      schoolName:   widget.fraisScolaires.config.schoolName,
      currentYear:  widget.fraisScolaires.currentYear,
      studentName:  'TEST ELEVE',
      studentId:    'TEST-001',
      classe:       '7eme A',
      section:      'Secondaire',
      moisPaye:     'Septembre',
      montantPaye:  35000,
      montantRequis: 35000,
      resteAPayerMois: 0,
      totalDejaPayeAnnee: 35000,
      totalRequis:  350000,
      historiqueTransactions: [
        {
          'date':   DateTime.now().toString().split(' ')[0],
          'mois':   'Septembre',
          'amount': 35000,
        }
      ],
      logoBytes: _logoBytes, // ⚡ logo choisi (ou null si aucun)
    );
    setState(() => _testingPrint = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? "✅ Page de test imprimée avec succès"
              : "❌ Échec — vérifiez que l'Epson TM-T20III est allumée, "
              "branchée en USB, et bien sélectionnée ci-dessus "
              "($_selectedPrinterName)"),
          backgroundColor: ok ? Colors.green : Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ====================================================================
  // ⚡ NOUVEAU — AUTRES FRAIS DE PAIEMENT (ÉPHÉMÈRES)
  // ====================================================================
  String _autreFraisScopeLabel(AutreFrais f) {
    switch (f.scope) {
      case 'section':
        return "Section : ${f.section ?? ''}";
      case 'classe':
        return "Classe : ${f.classe ?? ''}";
      default:
        return "Toutes les classes (toute l'école)";
    }
  }

  void _showAddAutreFraisDialog() async {
    if (!await _verifyBackupPassword()) return;

    final nomController      = TextEditingController();
    final montantController  = TextEditingController();
    String? dialogSection;
    String? dialogClasse;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final classesOptions = dialogSection != null
              ? widget.fraisScolaires.getClassesForSection(dialogSection!)
              : <String>[];
          return AlertDialog(
            title: const Text("Nouveau Frais Additionnel"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomController,
                    decoration: const InputDecoration(
                      labelText: "Nom du frais",
                      hintText: "Ex: Frais de l'État, Frais d'Aide...",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: montantController,
                    keyboardType: TextInputType.number,
                    decoration:
                    const InputDecoration(labelText: "Montant (FC)"),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Ce frais concerne :",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: dialogSection,
                    hint: const Text(
                        "Toutes les classes (toute l'école)"),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child:
                        Text("Toutes les classes (toute l'école)"),
                      ),
                      ...widget.fraisScolaires.config.sections.map(
                            (s) => DropdownMenuItem(
                          value: s,
                          child: Text("Section : $s"),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      dialogSection = value;
                      dialogClasse  = null;
                    }),
                  ),
                  if (dialogSection != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: dialogClasse,
                        hint: const Text(
                            "Toutes les classes de cette section"),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text(
                                "Toutes les classes de cette section"),
                          ),
                          ...classesOptions.map(
                                (c) => DropdownMenuItem(
                                value: c, child: Text(c)),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => dialogClasse = value),
                      ),
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
                  final nom     = nomController.text.trim();
                  final montant = double.tryParse(montantController.text);
                  if (nom.isEmpty || montant == null || montant <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "Veuillez entrer un nom et un montant valides")),
                    );
                    return;
                  }
                  final scope = dialogSection == null
                      ? 'all'
                      : (dialogClasse == null ? 'section' : 'classe');
                  await widget.fraisScolaires.addAutreFrais(
                    nom: nom,
                    montant: montant,
                    scope: scope,
                    section: dialogSection,
                    classe: dialogClasse,
                  );
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("✅ Frais ajouté avec succès")),
                    );
                  }
                },
                child: const Text("Ajouter"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteAutreFrais(AutreFrais frais) async {
    if (!await _verifyBackupPassword()) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ce frais ?"),
        content: Text(
          "Voulez-vous vraiment supprimer \"${frais.nom}\" ?\n\n"
              "Les paiements déjà enregistrés pour ce frais resteront "
              "dans l'historique, mais il ne sera plus proposé pour de "
              "nouveaux paiements.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.fraisScolaires.deleteAutreFrais(frais.id);
      if (mounted) setState(() {});
    }
  }

  // ====================================================================
  // ⚡ NOUVEAU — RENOMMER / SUPPRIMER UN NUMÉRO DE CLASSE
  // Permet de corriger une classe mal orthographiée (ex: "6eme" tapé
  // "6eem" par erreur) sans devoir recréer la classe et réaffecter
  // chaque élève à la main. Le renommage se propage automatiquement à
  // TOUS les élèves concernés (année en cours + historique), aux frais
  // spécifiques et aux exceptions déjà configurés pour cette classe —
  // donc à tous les écrans qui affichent ces données (accueil, listes,
  // PDF, reçus...).
  // ====================================================================
  void _renameClasseNumeroDialog(String section, String oldNumero) async {
    if (!await _verifyBackupPassword()) return;

    final controller = TextEditingController(text: oldNumero);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Renommer \"$oldNumero\""),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration:
              const InputDecoration(labelText: "Nouveau nom de la classe"),
            ),
            const SizedBox(height: 10),
            const Text(
              "Ce changement sera appliqué immédiatement à tous les élèves "
                  "déjà inscrits dans cette classe (année en cours et années "
                  "précédentes), ainsi qu'aux frais et exceptions déjà "
                  "configurés pour elle.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Le nom ne peut pas être vide")),
                );
                return;
              }
              await widget.fraisScolaires
                  .renameClasseNumero(section, oldNumero, newName);
              if (mounted) {
                Navigator.pop(ctx);
                setState(() {
                  if (selectedClasseScopeForFee == oldNumero) {
                    selectedClasseScopeForFee = newName;
                  }
                  if (selectedClasseScopeForException == oldNumero) {
                    selectedClasseScopeForException = newName;
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        "✅ Classe renommée en \"$newName\" — mis à jour "
                            "partout dans l'application"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text("Renommer"),
          ),
        ],
      ),
    );
  }

  void _deleteClasseNumeroDialog(String section, String numero) async {
    if (!await _verifyBackupPassword()) return;

    final result =
    await widget.fraisScolaires.deleteClasseNumero(section, numero);

    if (result['success'] == true) {
      if (mounted) {
        setState(() {
          if (selectedClasseScopeForFee == numero) {
            selectedClasseScopeForFee = null;
          }
          if (selectedClasseScopeForException == numero) {
            selectedClasseScopeForException = null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Classe supprimée")),
        );
      }
      return;
    }

    // La classe contient encore des élèves : on demande une
    // confirmation explicite avant de forcer la suppression.
    final int count = result['studentCount'] as int? ?? 0;
    if (!mounted) return;
    final forceDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Classe non vide"),
        content: Text(
          "$count élève(s) sont actuellement dans la classe \"$numero\" "
              "(année en cours ou années précédentes).\n\n"
              "Si vous supprimez cette classe, elle n'apparaîtra plus dans "
              "les listes de choix, mais les élèves concernés garderont "
              "\"$numero\" comme classe jusqu'à ce que vous les "
              "réaffectiez manuellement (ou que vous renommiez cette "
              "classe au lieu de la supprimer).\n\n"
              "Voulez-vous continuer ?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer quand même"),
          ),
        ],
      ),
    );

    if (forceDelete == true) {
      await widget.fraisScolaires
          .deleteClasseNumero(section, numero, force: true);
      if (mounted) {
        setState(() {
          if (selectedClasseScopeForFee == numero) {
            selectedClasseScopeForFee = null;
          }
          if (selectedClasseScopeForException == numero) {
            selectedClasseScopeForException = null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Classe supprimée")),
        );
      }
    }
  }

  // ====================================================================
  // BUILD
  // ====================================================================
  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    final classesForFeeSection = selectedSectionForFee != null
        ? widget.fraisScolaires
        .getClassesForSection(selectedSectionForFee!)
        : <String>[];

    final classesForExceptionSection =
    selectedSectionForException != null
        ? widget.fraisScolaires
        .getClassesForSection(selectedSectionForException!)
        : <String>[];

    final classFeesForSection = selectedSectionForFee != null
        ? widget.fraisScolaires.config.feesByClasse.entries
        .where((e) =>
        e.key.startsWith("${selectedSectionForFee!}|"))
        .toList()
        : <MapEntry<String, double>>[];

    final autresFraisList = widget.fraisScolaires.getAutresFrais();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Paramètres"),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: "Aide",
            onPressed: _openAide,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [

            if (_showBackupReminder)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload,
                        color: Colors.orange),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "💡 Pensez à sauvegarder régulièrement sur le serveur "
                            "pour permettre aux parents de retrouver leurs enfants "
                            "et pour sécuriser vos données.",
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Colors.orange),
                      onPressed: () =>
                          setState(() => _showBackupReminder = false),
                    ),
                  ],
                ),
              ),

            // ==================== NOM DE L'ÉCOLE ====================
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                        labelText: "Nom de l'établissement"),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _saveSchoolName,
                  child: const Text("Enregistrer"),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "Ce nom apparaît sur les PDF générés et sur les reçus "
                  "imprimés.",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),

            if (appState.schoolCode != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Text(
                      "Code école : ${appState.schoolCode}",
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "(à retenir pour la reconnexion)",
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // ==================== SECTIONS ====================
            const Text("Gestion des Sections",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Ajouter une nouvelle Section"),
              onPressed: _addNewSection,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: widget.fraisScolaires.config.sections
                  .map(
                    (section) => Chip(
                  label: Text(section),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => _removeSection(section),
                ),
              )
                  .toList(),
            ),
            const Divider(),

            // ==================== FRAIS MENSUEL ====================
            const Text("Frais Mensuel par Section ou par Classe",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Choisissez \"Toutes les classes\" pour fixer le frais de toute "
                  "la section, ou une classe précise si elle paie un montant différent.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedSectionForFee,
              isExpanded: true,
              items: widget.fraisScolaires.config.sections
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (value) => setState(() {
                selectedSectionForFee        = value;
                selectedClasseScopeForFee    = null;
              }),
            ),
            const SizedBox(height: 10),
            if (selectedSectionForFee != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newClasseController,
                        decoration: InputDecoration(
                          labelText:
                          "Ajouter une classe à \"$selectedSectionForFee\"",
                          hintText: "Ex: 1ère, 2ème, Niveau 1...",
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () async {
                        final value = newClasseController.text.trim();
                        if (value.isEmpty) return;
                        if (!await _verifyBackupPassword()) return;
                        await widget.fraisScolaires.addClasseNumero(
                            selectedSectionForFee!, value);
                        newClasseController.clear();
                        if (mounted) {
                          setState(() =>
                          selectedClasseScopeForFee = value);
                        }
                      },
                      child: const Text("Ajouter"),
                    ),
                  ],
                ),
              ),

            // ⚡ NOUVEAU — Liste des classes existantes de la section
            // sélectionnée, avec un bouton pour RENOMMER (corriger une
            // faute de frappe) et un bouton pour SUPPRIMER chacune.
            if (selectedSectionForFee != null &&
                classesForFeeSection.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Classes existantes (touchez l'icône crayon pour "
                          "corriger un nom, ou la croix pour supprimer) :",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: classesForFeeSection.map((c) {
                        return Container(
                          padding: const EdgeInsets.only(
                              left: 12, right: 4, top: 2, bottom: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withAlpha(18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.indigo.shade100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 2),
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    size: 16, color: Colors.indigo),
                                tooltip: "Renommer cette classe",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 30, minHeight: 30),
                                onPressed: () => _renameClasseNumeroDialog(
                                    selectedSectionForFee!, c),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 16, color: Colors.red),
                                tooltip: "Supprimer cette classe",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 30, minHeight: 30),
                                onPressed: () => _deleteClasseNumeroDialog(
                                    selectedSectionForFee!, c),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

            DropdownButton<String>(
              value: selectedClasseScopeForFee,
              isExpanded: true,
              hint: const Text("Toutes les classes"),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text("Toutes les classes")),
                ...classesForFeeSection.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (value) =>
                  setState(() => selectedClasseScopeForFee = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: feeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: selectedClasseScopeForFee != null
                    ? "Frais mensuel pour ${selectedSectionForFee ?? ''} - $selectedClasseScopeForFee"
                    : "Frais mensuel pour toute la section ${selectedSectionForFee ?? ''}",
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                if (selectedSectionForFee == null) return;
                if (await _verifyBackupPassword()) {
                  final amount = double.tryParse(feeController.text);
                  if (amount != null) {
                    if (selectedClasseScopeForFee == null) {
                      widget.fraisScolaires.config
                          .feesBySection[selectedSectionForFee!] =
                          amount;
                    } else {
                      final key =
                          "${selectedSectionForFee!}|${selectedClasseScopeForFee!}";
                      widget.fraisScolaires.config
                          .feesByClasse[key] = amount;
                    }
                    await widget.fraisScolaires.saveData();
                    // ⚡ NOUVEAU — Après un changement de frais, on
                    // recalcule automatiquement la répartition mois par
                    // mois de tous les élèves concernés, pour que les
                    // mois "déjà payés" reflètent vraiment le nouveau
                    // montant (report automatique de l'excédent ou du
                    // manque sur les mois suivants, sans jamais perdre
                    // un seul FC déjà payé). Les reçus non encore
                    // imprimés sont aussi mis à jour automatiquement.
                    final int nbRecalcules =
                    await widget.fraisScolaires.recalculerPaiementsPour(
                      section: selectedSectionForFee,
                      classeNumero: selectedClasseScopeForFee,
                    );
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              "✅ Frais mis à jour — $nbRecalcules élève(s) "
                                  "recalculé(s) automatiquement pour rester "
                                  "cohérents avec le nouveau montant"),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  }
                }
              },
              child: Text(
                selectedClasseScopeForFee == null
                    ? "Enregistrer pour Toute la Section"
                    : "Enregistrer pour $selectedClasseScopeForFee Uniquement",
              ),
            ),
            if (selectedClasseScopeForFee != null &&
                widget.fraisScolaires.config.feesByClasse
                    .containsKey(
                    "${selectedSectionForFee}|${selectedClasseScopeForFee}"))
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: Text(
                  "Retirer l'exception pour $selectedClasseScopeForFee",
                  style: const TextStyle(color: Colors.red),
                ),
                onPressed: () async {
                  if (!await _verifyBackupPassword()) return;
                  widget.fraisScolaires.config.feesByClasse
                      .remove(
                      "${selectedSectionForFee}|${selectedClasseScopeForFee}");
                  await widget.fraisScolaires.saveData();
                  // ⚡ NOUVEAU — même recalcul automatique qu'au-dessus.
                  final int nbRecalcules =
                  await widget.fraisScolaires.recalculerPaiementsPour(
                    section: selectedSectionForFee,
                    classeNumero: selectedClasseScopeForFee,
                  );
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            "Exception retirée — $nbRecalcules élève(s) "
                                "recalculé(s) automatiquement"),
                      ),
                    );
                  }
                },
              ),
            if (classFeesForSection.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                "Frais spécifiques déjà définis pour cette section :",
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
              ...classFeesForSection.map((entry) {
                final classeNumero = entry.key.split('|')[1];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(classeNumero),
                  trailing:
                  Text("${entry.value.toStringAsFixed(0)} FC"),
                );
              }),
            ],
            const Divider(),

            // ==================== EXCEPTIONS ====================
            const Text("Exceptions par Mois, par Section ou par Classe",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedSectionForException,
              hint: const Text("Choisir une section"),
              isExpanded: true,
              items: widget.fraisScolaires.config.sections
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (value) => setState(() {
                selectedSectionForException      = value;
                selectedClasseScopeForException  = null;
              }),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedClasseScopeForException,
              hint: const Text("Toutes les classes"),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text("Toutes les classes")),
                ...classesForExceptionSection.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (value) => setState(
                      () => selectedClasseScopeForException = value),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedMonthForException,
              hint: const Text("Choisir un mois"),
              isExpanded: true,
              items: widget.fraisScolaires.months
                  .map((m) =>
                  DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (value) =>
                  setState(() => selectedMonthForException = value),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _editExceptionForSection(),
              child: const Text("Ajouter / Modifier Exception"),
            ),
            const Divider(),

            // ==================== ⚡ NOUVEAU — RECALCUL DE SÉCURITÉ ====================
            const Text("Recalcul de Sécurité des Paiements",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "À utiliser si vous avez remarqué qu'un frais était mal "
                  "configuré (ex: montant par défaut jamais corrigé) et que "
                  "des élèves ont déjà payé avec l'ancien montant. Ce bouton "
                  "ne supprime ni n'ajoute aucun argent : il redistribue "
                  "simplement, mois par mois et pour chaque élève, ce qu'il "
                  "a déjà payé, en respectant les montants requis ACTUELS. "
                  "Un mois ne sera donc à nouveau marqué comme \"entièrement "
                  "payé\" que s'il l'est vraiment au tarif courant ; le "
                  "manque ou l'excédent est automatiquement reporté sur les "
                  "mois voisins. Les reçus déjà imprimés ne sont jamais "
                  "modifiés ; seuls les reçus en attente d'impression sont "
                  "mis à jour.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_fix_high),
              label: const Text(
                  "Recalculer TOUS les paiements de l'année en cours"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
              ),
              onPressed: () async {
                if (!await _verifyBackupPassword()) return;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Confirmer le recalcul général"),
                    content: const Text(
                      "Ceci va recalculer, pour TOUS les élèves de l'année "
                          "en cours, la répartition mois par mois de ce "
                          "qu'ils ont déjà payé, selon les montants requis "
                          "actuels.\n\n"
                          "Aucun montant payé ne sera perdu ni ajouté : "
                          "seule la répartition entre les mois sera "
                          "corrigée.\n\n"
                          "Continuer ?",
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text("Annuler")),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("Confirmer"),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
                final int nbRecalcules =
                await widget.fraisScolaires.recalculerPaiementsPour();
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          "✅ Recalcul terminé — $nbRecalcules élève(s) "
                              "mis à jour"),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
            ),
            const Divider(),

            // ==================== ADMINISTRATIONS ====================
            const Text("Administrations & Répartition (%)",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            ...widget.fraisScolaires.config.administrations
                .map(
                  (admin) => ListTile(
                title: Text(admin.nom),
                subtitle: Text("${admin.pourcentage}%"),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editAdministration(admin),
                ),
              ),
            )
                .toList(),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Ajouter Administration"),
              onPressed: _addAdministration,
            ),
            const Divider(),

            // ==================== ⚡ NOUVEAU — AUTRES FRAIS DE PAIEMENT ====================
            const Text("Autres Frais de Paiement",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Frais ponctuels propres à votre école (ex: Frais de l'État, "
                  "Frais d'Aide...). Contrairement au frais mensuel principal, "
                  "vous pouvez les ajouter ou les supprimer librement à tout "
                  "moment. Ils sont ensuite payables depuis le bouton "
                  "\"Autres Frais\" de l'écran d'accueil.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (autresFraisList.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "Aucun frais additionnel défini pour le moment.",
                  style: TextStyle(
                      color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              )
            else
              ...autresFraisList.map(
                    (f) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(f.nom),
                    subtitle: Text(
                      "${f.montant.toStringAsFixed(0)} FC — "
                          "${_autreFraisScopeLabel(f)}",
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      onPressed: () => _deleteAutreFrais(f),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_box),
              label: const Text("Ajouter un Frais Additionnel"),
              onPressed: _showAddAutreFraisDialog,
            ),
            const Divider(),

            // ==================== ANNÉE SCOLAIRE ====================
            const Text("Année Scolaire",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: selectedYear,
              isExpanded: true,
              items: [
                ...widget.fraisScolaires.history.keys.map(
                        (year) => DropdownMenuItem(
                        value: year, child: Text(year))),
                const DropdownMenuItem(
                    value: "Nouvelle Annee",
                    child: Text("Créer nouvelle année")),
              ],
              onChanged: (value) async {
                if (value == "Nouvelle Annee") {
                  final controller = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Nouvelle Année Scolaire"),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                            labelText: "Ex: 2026-2027"),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("Annuler")),
                        ElevatedButton(
                          onPressed: () async {
                            if (controller.text.isNotEmpty) {
                              if (await _verifyBackupPassword()) {
                                await widget.fraisScolaires
                                    .changeYear(
                                    controller.text.trim());
                                if (mounted) {
                                  setState(() => selectedYear =
                                      controller.text.trim());
                                }
                              }
                            }
                            Navigator.pop(ctx);
                          },
                          child: const Text("Créer"),
                        ),
                      ],
                    ),
                  );
                } else if (value != null) {
                  if (await _verifyBackupPassword()) {
                    await widget.fraisScolaires.changeYear(value);
                    if (mounted) setState(() => selectedYear = value);
                  }
                }
              },
            ),
            const Divider(),

            // ==================== SYNCHRONISATION SERVEUR ====================
            const Text("Synchronisation Serveur",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Text(
                "⚠️ Sauvegardez régulièrement pour que les parents "
                    "puissent retrouver leurs enfants via l'app parent et "
                    "pour récupérer vos données depuis n'importe quel PC.",
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 10),
            if (appState.schoolCode == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.lock),
                label: const Text("Définir Code École"),
                onPressed: () =>
                    _setSchoolCode(context, appState),
              )
            else
              ListTile(
                title: const Text("Code de l'école"),
                subtitle: Text(appState.schoolCode!),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () =>
                      _setSchoolCode(context, appState),
                ),
              ),
            const SizedBox(height: 10),
            if (appState.backupPassword == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.password),
                label: const Text("Définir Mot de Passe Sauvegarde"),
                onPressed: () =>
                    _setBackupPassword(context, appState),
              )
            else
              ListTile(
                title: const Text("Mot de Passe Sauvegarde"),
                subtitle: const Text("••••••••"),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () =>
                      _changeBackupPassword(context, appState),
                ),
              ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text("Sauvegarder sur le Serveur"),
              onPressed: () async {
                if (appState.schoolCode == null ||
                    appState.backupPassword == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Définissez le code et le mot de passe")),
                  );
                  return;
                }
                final result =
                await widget.fraisScolaires.backupToServer(
                  appState.schoolCode!,
                  appState.backupPassword!,
                );
                final bool success = result['success'] == true;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? "✅ Sauvegarde réussie — les parents peuvent maintenant accéder aux données"
                          : "❌ Erreur de sauvegarde : ${result['error'] ?? 'inconnue'}"),
                      backgroundColor:
                      success ? Colors.green : Colors.red,
                      duration: Duration(seconds: success ? 3 : 6),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download),
              label: const Text("Récupérer depuis le Serveur"),
              onPressed: () async {
                if (appState.schoolCode == null ||
                    appState.backupPassword == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Définissez le code et le mot de passe")),
                  );
                  return;
                }
                final result =
                await widget.fraisScolaires.restoreFromServer(
                  appState.schoolCode!,
                  appState.backupPassword!,
                );
                final bool success = result['success'] == true;
                if (success && mounted) {
                  setState(() {
                    selectedYear =
                        widget.fraisScolaires.currentYear;
                    nameController.text =
                        widget.fraisScolaires.config.schoolName;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "✅ Données récupérées et fusionnées")),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          "❌ Échec : ${result['error'] ?? 'mot de passe incorrect ou aucune donnée'}"),
                      duration: const Duration(seconds: 6),
                    ),
                  );
                }
              },
            ),
            const Divider(),

            // ==================== IMPRIMANTE EPSON TM-T20III (USB) ====================
            const Text("Imprimante de Reçus (Epson TM-T20III — USB)",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "1. Branchez l'Epson TM-T20III en USB et installez son pilote "
                  "Epson (elle doit apparaître dans \"Imprimantes et scanners\" "
                  "de Windows).\n"
                  "2. Cliquez \"Détecter\" pour voir les imprimantes installées.\n"
                  "3. Sélectionnez l'Epson dans la liste.\n"
                  "4. Testez avec \"Imprimer page de test\".\n"
                  "Après ça, chaque paiement imprimera automatiquement le reçu.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Choisir l'imprimante"),
                    value: _selectedPrinterName,
                    items: _availablePrinters
                        .map((p) => DropdownMenuItem(
                        value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) _saveSelectedPrinter(val);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: _loadingPrinters
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  )
                      : const Icon(Icons.search),
                  label: const Text("Détecter"),
                  onPressed:
                  _loadingPrinters ? null : _detectPrinters,
                ),
              ],
            ),
            if (_selectedPrinterName != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "Imprimante actuelle : $_selectedPrinterName",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo),
                ),
              ),
            const SizedBox(height: 18),

            // ==================== ⚡ NOUVEAU — LOGO DU REÇU ====================
            const Text("Logo de l'établissement (sur les reçus)",
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Le logo choisi sera imprimé à gauche ET à droite, en haut "
                  "du reçu, avec le nom de l'établissement bien centré "
                  "entre les deux. Une image carrée donne le meilleur "
                  "résultat.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _logoBytes != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(_logoBytes!,
                          fit: BoxFit.contain),
                    )
                        : const Icon(Icons.image_not_supported,
                        color: Colors.grey),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _logoBytes != null
                          ? "Logo actuel"
                          : "Aucun logo sélectionné",
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: _loadingLogo
                        ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                        : const Icon(Icons.upload, size: 18),
                    label: Text(
                        _logoBytes == null ? "Choisir" : "Changer"),
                    onPressed: _loadingLogo ? null : _pickLogo,
                  ),
                  if (_logoBytes != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      tooltip: "Retirer le logo",
                      onPressed: _loadingLogo ? null : _removeLogo,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              icon: _testingPrint
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.print),
              label: Text(_testingPrint
                  ? "Impression en cours..."
                  : "Imprimer page de test"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed:
              (_selectedPrinterName == null || _testingPrint)
                  ? null
                  : _testPrint,
            ),
            const Divider(),

            // ==================== MODE SOMBRE ====================
            SwitchListTile(
              title: const Text("Mode Sombre"),
              value: appState.isDarkMode,
              onChanged: (_) => appState.toggleTheme(),
            ),
            const Divider(),

            // ==================== DÉCONNEXION ====================
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                "Déconnexion",
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(vertical: 14),
                minimumSize:
                const Size(double.infinity, 52),
              ),
              onPressed: _deconnexion,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ====================================================================
  // GESTION DES SECTIONS
  // ====================================================================
  void _addNewSection() async {
    if (!await _verifyBackupPassword()) return;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouvelle Section"),
        content: TextField(
          controller: controller,
          decoration:
          const InputDecoration(labelText: "Nom de la section"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                final newSection = controller.text.trim();
                if (!widget.fraisScolaires.config.sections
                    .contains(newSection)) {
                  widget.fraisScolaires.config.sections
                      .add(newSection);
                  widget.fraisScolaires.config
                      .feesBySection[newSection] = 35000;
                  widget.fraisScolaires.saveData();
                  if (mounted) setState(() {});
                }
                Navigator.pop(ctx);
              }
            },
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
  }

  void _removeSection(String section) async {
    if (!await _verifyBackupPassword()) return;
    if (widget.fraisScolaires.config.sections.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
            Text("Vous devez garder au moins une section")),
      );
      return;
    }
    setState(() {
      widget.fraisScolaires.config.sections.remove(section);
      widget.fraisScolaires.config.feesBySection.remove(section);
      widget.fraisScolaires.config.monthlyExceptionsBySection
          .remove(section);
      widget.fraisScolaires.config.feesByClasse
          .removeWhere((key, _) => key.startsWith("$section|"));
      widget.fraisScolaires.config.monthlyExceptionsByClasse
          .removeWhere((key, _) => key.startsWith("$section|"));
      widget.fraisScolaires.config.classesBySection
          .remove(section);
    });
    await widget.fraisScolaires.saveData();
  }

  // ====================================================================
  // EXCEPTIONS
  // ====================================================================
  void _editExceptionForSection() async {
    if (selectedSectionForException == null ||
        selectedMonthForException == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
            Text("Veuillez choisir une section et un mois")),
      );
      return;
    }
    if (!await _verifyBackupPassword()) return;

    final controller = TextEditingController();
    final scopeLabel =
        selectedClasseScopeForException ?? "Toutes les classes";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            "Exception - $selectedMonthForException ($selectedSectionForException - $scopeLabel)"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Montant (FC)",
            helperText:
            "Laisser vide pour supprimer l'exception existante",
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final amount =
              double.tryParse(controller.text);
              if (selectedClasseScopeForException == null) {
                if (amount != null) {
                  widget.fraisScolaires.config
                      .monthlyExceptionsBySection
                      .putIfAbsent(
                      selectedSectionForException!, () => {})
                  [selectedMonthForException!] = amount;
                } else {
                  widget.fraisScolaires.config
                      .monthlyExceptionsBySection[
                  selectedSectionForException!]
                      ?.remove(selectedMonthForException);
                }
              } else {
                final key =
                    "${selectedSectionForException!}|${selectedClasseScopeForException!}";
                if (amount != null) {
                  widget.fraisScolaires.config
                      .monthlyExceptionsByClasse
                      .putIfAbsent(key, () => {})
                  [selectedMonthForException!] = amount;
                } else {
                  widget.fraisScolaires.config
                      .monthlyExceptionsByClasse[key]
                      ?.remove(selectedMonthForException);
                }
              }
              await widget.fraisScolaires.saveData();
              // ⚡ NOUVEAU — même logique de recalcul automatique que
              // pour un changement de frais mensuel classique : on
              // redistribue les paiements déjà effectués selon les
              // montants requis actuels (donc l'exception qu'on vient
              // de modifier).
              final int nbRecalcules =
              await widget.fraisScolaires.recalculerPaiementsPour(
                section: selectedSectionForException,
                classeNumero: selectedClasseScopeForException,
              );
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        "Exception enregistrée — $nbRecalcules élève(s) "
                            "recalculé(s) automatiquement"),
                  ),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  void _addAdministration() async {
    if (!await _verifyBackupPassword()) return;
    final nomController     = TextEditingController();
    final percentController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouvelle Administration"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nomController,
                decoration:
                const InputDecoration(labelText: "Nom")),
            TextField(
              controller: percentController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: "Pourcentage (%)"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final percent =
              double.tryParse(percentController.text);
              if (nomController.text.isNotEmpty &&
                  percent != null) {
                widget.fraisScolaires.config.administrations
                    .add(Administration(
                  nom:         nomController.text,
                  pourcentage: percent,
                ));
                widget.fraisScolaires.saveData();
                if (mounted) setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
  }

  void _editAdministration(Administration admin) async {
    if (!await _verifyBackupPassword()) return;
    final nomController =
    TextEditingController(text: admin.nom);
    final percentController =
    TextEditingController(text: admin.pourcentage.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier Administration"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nomController,
                decoration:
                const InputDecoration(labelText: "Nom")),
            TextField(
              controller: percentController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: "Pourcentage (%)"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final percent =
              double.tryParse(percentController.text);
              if (nomController.text.isNotEmpty &&
                  percent != null) {
                admin.nom         = nomController.text;
                admin.pourcentage = percent;
                widget.fraisScolaires.saveData();
                if (mounted) setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  void _setSchoolCode(BuildContext context, AppState appState) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Code de Récupération"),
        content: TextField(
          controller: codeController,
          decoration:
          const InputDecoration(labelText: "Code unique (ex: MAPENDO)"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (codeController.text.trim().isNotEmpty) {
                appState.setSchoolCode(codeController.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  void _setBackupPassword(BuildContext context, AppState appState) {
    final passController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Mot de Passe de Sauvegarde"),
        content: TextField(
          controller: passController,
          obscureText: true,
          decoration: const InputDecoration(
              labelText: "Mot de passe (min 6 caractères)"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (passController.text.trim().length >= 6) {
                appState.setBackupPassword(
                    passController.text.trim());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Mot de passe enregistré")),
                );
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }
}