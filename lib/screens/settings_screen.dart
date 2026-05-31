
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';
import '../models.dart';

class SettingsScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const SettingsScreen({super.key, required this.fraisScolaires});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final nameController = TextEditingController();
  final feeController = TextEditingController();
  String? selectedYear;
  String? selectedSectionForFee;
  String? selectedSectionForException;
  String? selectedMonthForException;

  @override
  void initState() {
    super.initState();
    nameController.text = widget.fraisScolaires.config.schoolName;
    selectedYear = widget.fraisScolaires.currentYear;
    selectedSectionForFee = widget.fraisScolaires.config.sections.isNotEmpty
        ? widget.fraisScolaires.config.sections.first
        : null;
  }

  // ==================== VÉRIFICATION MOT DE PASSE ====================
  Future<bool> _verifyBackupPassword() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez d'abord définir un mot de passe de sauvegarde")),
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
            const Text("Entrez votre mot de passe de sauvegarde pour continuer"),
            const SizedBox(height: 15),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (passController.text.trim() == appState.backupPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mot de passe incorrect")));
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
    return isCorrect ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Paramètres")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Nom de l'établissement
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "Nom de l'établissement")),
            const SizedBox(height: 20),

            const Text("Gestion des Sections", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Ajouter une nouvelle Section"),
              onPressed: _addNewSection,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: widget.fraisScolaires.config.sections.map((section) => Chip(
                label: Text(section),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => _removeSection(section),
              )).toList(),
            ),

            const Divider(),
            const Text("Frais Mensuel par Section", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: selectedSectionForFee,
              isExpanded: true,
              items: widget.fraisScolaires.config.sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (value) => setState(() => selectedSectionForFee = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: feeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: selectedSectionForFee != null ? "Frais mensuel pour ${selectedSectionForFee}" : "Frais mensuel",
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedSectionForFee == null) return;
                if (await _verifyBackupPassword()) {
                  double? amount = double.tryParse(feeController.text);
                  if (amount != null) {
                    widget.fraisScolaires.config.feesBySection[selectedSectionForFee!] = amount;
                    await widget.fraisScolaires.saveData();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Frais mis à jour")));
                  }
                }
              },
              child: const Text("Enregistrer Frais pour cette Section"),
            ),

            const Divider(),
            const Text("Exceptions par Mois et par Section", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: selectedSectionForException,
              hint: const Text("Choisir une section"),
              isExpanded: true,
              items: widget.fraisScolaires.config.sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (value) => setState(() => selectedSectionForException = value),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedMonthForException,
              hint: const Text("Choisir un mois"),
              isExpanded: true,
              items: widget.fraisScolaires.months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (value) => setState(() => selectedMonthForException = value),
            ),
            ElevatedButton(
              onPressed: () => _editExceptionForSection(),
              child: const Text("Ajouter / Modifier Exception"),
            ),

            const Divider(),

            // Année Scolaire
            const Text("Année Scolaire", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: selectedYear,
              isExpanded: true,
              items: [
                ...widget.fraisScolaires.history.keys.map((year) => DropdownMenuItem(value: year, child: Text(year))),
                const DropdownMenuItem(value: "Nouvelle Annee", child: Text("Créer nouvelle année")),
              ],
              onChanged: (value) async {
                if (value == "Nouvelle Annee") {
                  final controller = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Nouvelle Année Scolaire"),
                      content: TextField(controller: controller, decoration: const InputDecoration(labelText: "Ex: 2026-2027")),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
                        ElevatedButton(
                          onPressed: () async {
                            if (controller.text.isNotEmpty) {
                              if (await _verifyBackupPassword()) {
                                await widget.fraisScolaires.changeYear(controller.text.trim());
                                if (mounted) setState(() => selectedYear = controller.text.trim());
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

            // Synchronisation Serveur
            const Text("Synchronisation Serveur", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (appState.schoolCode == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.lock),
                label: const Text("Définir Code École"),
                onPressed: () => _setSchoolCode(context, appState),
              )
            else
              ListTile(
                title: const Text("Code de l'école"),
                subtitle: Text(appState.schoolCode!),
                trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _setSchoolCode(context, appState)),
              ),

            const SizedBox(height: 10),

            if (appState.backupPassword == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.password),
                label: const Text("Définir Mot de Passe Sauvegarde"),
                onPressed: () => _setBackupPassword(context, appState),
              )
            else
              ListTile(
                title: const Text("Mot de Passe Sauvegarde"),
                subtitle: const Text("••••••••"),
                trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _setBackupPassword(context, appState)),
              ),

            const SizedBox(height: 15),

            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text("Sauvegarder sur le Serveur"),
              onPressed: () async {
                if (appState.schoolCode == null || appState.backupPassword == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Définissez le code et le mot de passe")));
                  return;
                }
                bool success = await widget.fraisScolaires.backupToServer(appState.schoolCode!, appState.backupPassword!);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? "✅ Sauvegarde réussie" : "❌ Erreur de sauvegarde")));
              },
            ),

            const SizedBox(height: 10),

            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_download),
              label: const Text("Récupérer depuis le Serveur"),
              onPressed: () async {
                if (appState.schoolCode == null || appState.backupPassword == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Définissez le code et le mot de passe")));
                  return;
                }
                bool success = await widget.fraisScolaires.restoreFromServer(appState.schoolCode!, appState.backupPassword!);
                if (success && mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Données récupérées et fusionnées")));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Échec (mot de passe incorrect ou aucune donnée)")));
                }
              },
            ),

            const Divider(),
            SwitchListTile(
              title: const Text("Mode Sombre"),
              value: appState.isDarkMode,
              onChanged: (v) => appState.toggleTheme(),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== GESTION DES SECTIONS ====================
  void _addNewSection() async {
    if (!await _verifyBackupPassword()) return;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouvelle Section"),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: "Nom de la section")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                final newSection = controller.text.trim();
                if (!widget.fraisScolaires.config.sections.contains(newSection)) {
                  widget.fraisScolaires.config.sections.add(newSection);
                  widget.fraisScolaires.config.feesBySection[newSection] = 35000;
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vous devez garder au moins une section")));
      return;
    }
    setState(() {
      widget.fraisScolaires.config.sections.remove(section);
      widget.fraisScolaires.config.feesBySection.remove(section);
      widget.fraisScolaires.config.monthlyExceptionsBySection.remove(section);
    });
    await widget.fraisScolaires.saveData();
  }

  void _editExceptionForSection() async {
    if (selectedSectionForException == null || selectedMonthForException == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Veuillez choisir une section et un mois")));
      return;
    }
    if (!await _verifyBackupPassword()) return;

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Exception - $selectedMonthForException (${selectedSectionForException})"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Montant (FC)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(controller.text);
              if (amount != null) {
                widget.fraisScolaires.config.monthlyExceptionsBySection
                    .putIfAbsent(selectedSectionForException!, () => {})
                [selectedMonthForException!] = amount;
              } else {
                widget.fraisScolaires.config.monthlyExceptionsBySection[selectedSectionForException!]?.remove(selectedMonthForException);
              }
              widget.fraisScolaires.saveData();
              if (mounted) setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  // ==================== CODE & MOT DE PASSE ====================
  void _setSchoolCode(BuildContext context, AppState appState) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Code de Récupération"),
        content: TextField(controller: codeController, decoration: const InputDecoration(labelText: "Code unique")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
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
          decoration: const InputDecoration(labelText: "Mot de passe (min 6 caractères)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (passController.text.trim().length >= 6) {
                appState.setBackupPassword(passController.text.trim());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mot de passe enregistré")));
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }
}