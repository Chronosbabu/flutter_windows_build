import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';
import '../models.dart';
import 'recovery_screen.dart';
import 'aide.dart';

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

  // ---- Frais mensuel par section / classe ----
  String? selectedSectionForFee;
  // null = "Toutes les classes" (comportement section entière, comme avant)
  String? selectedClasseScopeForFee;

  // ---- Exceptions par mois, par section / classe ----
  String? selectedSectionForException;
  String? selectedMonthForException;
  // null = "Toutes les classes"
  String? selectedClasseScopeForException;

  // ---- Ajout manuel de numéro de classe (sections personnalisées) ----
  final TextEditingController newClasseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    nameController.text = widget.fraisScolaires.config.schoolName;
    selectedYear = widget.fraisScolaires.currentYear;
    selectedSectionForFee = widget.fraisScolaires.config.sections.isNotEmpty
        ? widget.fraisScolaires.config.sections.first
        : null;
  }

  // ==================== ÉCRAN D'AIDE ====================
  void _openAide() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AideScreen()),
    );
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

  // ==================== ENREGISTRER NOM DE L'ÉCOLE ====================
  void _saveSchoolName() async {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Le nom ne peut pas être vide")));
      return;
    }

    if (!await _verifyBackupPassword()) return;

    widget.fraisScolaires.config.schoolName = nameController.text.trim();
    await widget.fraisScolaires.saveData();

    final appState = Provider.of<AppState>(context, listen: false);
    await appState.updateSchoolName(nameController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Nom de l'école enregistré avec succès")),
      );
    }
  }

  // ==================== CHANGEMENT SÉCURISÉ DU MOT DE PASSE ====================
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
              decoration: const InputDecoration(labelText: "Ancien mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (oldPassController.text.trim() == appState.backupPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ancien mot de passe incorrect")));
              }
            },
            child: const Text("Continuer"),
          ),
        ],
      ),
    );

    if (oldCorrect != true) return;

    final newPassController = TextEditingController();
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
              decoration: const InputDecoration(labelText: "Nouveau mot de passe (min 6 caractères)"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmPassController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Confirmer le nouveau mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              String newPass = newPassController.text.trim();
              String confirmPass = confirmPassController.text.trim();

              if (newPass.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Le mot de passe doit contenir au moins 6 caractères")));
                return;
              }
              if (newPass != confirmPass) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Les deux mots de passe ne correspondent pas")));
                return;
              }

              appState.setBackupPassword(newPass);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("✅ Mot de passe changé avec succès")),
              );
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  // ==================== DÉCONNEXION ====================
  void _deconnexion() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RecoveryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    final classesForFeeSection = selectedSectionForFee != null
        ? widget.fraisScolaires.getClassesForSection(selectedSectionForFee!)
        : <String>[];

    final classesForExceptionSection = selectedSectionForException != null
        ? widget.fraisScolaires.getClassesForSection(selectedSectionForException!)
        : <String>[];

    final classFeesForSection = selectedSectionForFee != null
        ? widget.fraisScolaires.config.feesByClasse.entries
        .where((e) => e.key.startsWith("${selectedSectionForFee!}|"))
        .toList()
        : <MapEntry<String, double>>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Paramètres"),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: "Aide : à quoi sert chaque bouton ?",
            onPressed: _openAide,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Nom de l'établissement"),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _saveSchoolName,
                  child: const Text("Enregistrer"),
                ),
              ],
            ),
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

            const Text("Frais Mensuel par Section ou par Classe", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Choisissez \"Toutes les classes\" pour fixer le frais de toute la section, "
                  "ou une classe précise (ex: 1ère, 6ème...) si elle paie un montant différent.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedSectionForFee,
              isExpanded: true,
              items: widget.fraisScolaires.config.sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (value) => setState(() {
                selectedSectionForFee = value;
                selectedClasseScopeForFee = null;
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
                          labelText: "Ajouter une classe à \"$selectedSectionForFee\"",
                          hintText: "Ex: 1ère, 2ème, Niveau 1...",
                          helperText: classesForFeeSection.isEmpty
                              ? "Aucune classe pour cette section : ajoutez-en une ici"
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () async {
                        final value = newClasseController.text.trim();
                        if (value.isEmpty) return;
                        if (!await _verifyBackupPassword()) return;
                        await widget.fraisScolaires.addClasseNumero(selectedSectionForFee!, value);
                        newClasseController.clear();
                        if (mounted) {
                          setState(() {
                            selectedClasseScopeForFee = value;
                          });
                        }
                      },
                      child: const Text("Ajouter"),
                    ),
                  ],
                ),
              ),

            DropdownButton<String>(
              value: selectedClasseScopeForFee,
              isExpanded: true,
              hint: const Text("Toutes les classes"),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text("Toutes les classes")),
                ...classesForFeeSection.map((c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (value) => setState(() => selectedClasseScopeForFee = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: feeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: selectedClasseScopeForFee != null
                    ? "Frais mensuel pour ${selectedSectionForFee ?? ''} - ${selectedClasseScopeForFee}"
                    : "Frais mensuel pour toute la section ${selectedSectionForFee ?? ''}",
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                if (selectedSectionForFee == null) return;
                if (await _verifyBackupPassword()) {
                  double? amount = double.tryParse(feeController.text);
                  if (amount != null) {
                    if (selectedClasseScopeForFee == null) {
                      widget.fraisScolaires.config.feesBySection[selectedSectionForFee!] = amount;
                    } else {
                      final key = "${selectedSectionForFee!}|${selectedClasseScopeForFee!}";
                      widget.fraisScolaires.config.feesByClasse[key] = amount;
                    }
                    await widget.fraisScolaires.saveData();
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Frais mis à jour")));
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
                    .containsKey("${selectedSectionForFee}|${selectedClasseScopeForFee}"))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: Text(
                    "Retirer l'exception pour $selectedClasseScopeForFee (revient au frais de la section)",
                    style: const TextStyle(color: Colors.red),
                  ),
                  onPressed: () async {
                    if (!await _verifyBackupPassword()) return;
                    widget.fraisScolaires.config.feesByClasse
                        .remove("${selectedSectionForFee}|${selectedClasseScopeForFee}");
                    await widget.fraisScolaires.saveData();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            if (classFeesForSection.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text("Frais spécifiques déjà définis pour cette section :", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ...classFeesForSection.map((entry) {
                final classeNumero = entry.key.split('|')[1];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(classeNumero),
                  trailing: Text("${entry.value.toStringAsFixed(0)} FC"),
                );
              }),
            ],
            const Divider(),

            const Text("Exceptions par Mois, par Section ou par Classe", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              "Choisissez \"Toutes les classes\" pour appliquer l'exception à toute la section "
                  "ce mois-là, ou une classe précise pour ne l'appliquer qu'à elle. "
                  "(Les classes ajoutées plus haut, dans \"Frais Mensuel\", apparaissent aussi ici.)",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedSectionForException,
              hint: const Text("Choisir une section"),
              isExpanded: true,
              items: widget.fraisScolaires.config.sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (value) => setState(() {
                selectedSectionForException = value;
                selectedClasseScopeForException = null;
              }),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedClasseScopeForException,
              hint: const Text("Toutes les classes"),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String>(value: null, child: Text("Toutes les classes")),
                ...classesForExceptionSection.map((c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (value) => setState(() => selectedClasseScopeForException = value),
            ),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: selectedMonthForException,
              hint: const Text("Choisir un mois"),
              isExpanded: true,
              items: widget.fraisScolaires.months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (value) => setState(() => selectedMonthForException = value),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _editExceptionForSection(),
              child: const Text("Ajouter / Modifier Exception"),
            ),
            const Divider(),

            const Text("Administrations & Répartition (%)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...widget.fraisScolaires.config.administrations.map((admin) => ListTile(
              title: Text(admin.nom),
              subtitle: Text("${admin.pourcentage}%"),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _editAdministration(admin),
              ),
            )).toList(),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Ajouter Administration"),
              onPressed: _addAdministration,
            ),
            const Divider(),

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
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _changeBackupPassword(context, appState),
                ),
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
            const Divider(),

            ElevatedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text("Déconnexion", style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _deconnexion,
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
      widget.fraisScolaires.config.feesByClasse.removeWhere((key, _) => key.startsWith("$section|"));
      widget.fraisScolaires.config.monthlyExceptionsByClasse.removeWhere((key, _) => key.startsWith("$section|"));
      widget.fraisScolaires.config.classesBySection.remove(section);
    });
    await widget.fraisScolaires.saveData();
  }

  // ==================== EXCEPTION PAR SECTION OU PAR CLASSE ====================
  void _editExceptionForSection() async {
    if (selectedSectionForException == null || selectedMonthForException == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Veuillez choisir une section et un mois")));
      return;
    }
    if (!await _verifyBackupPassword()) return;

    final controller = TextEditingController();
    final String scopeLabel = selectedClasseScopeForException ?? "Toutes les classes";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Exception - $selectedMonthForException ($selectedSectionForException - $scopeLabel)"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Montant (FC)",
            helperText: "Laisser vide pour supprimer l'exception existante",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(controller.text);

              if (selectedClasseScopeForException == null) {
                if (amount != null) {
                  widget.fraisScolaires.config.monthlyExceptionsBySection
                      .putIfAbsent(selectedSectionForException!, () => {})
                  [selectedMonthForException!] = amount;
                } else {
                  widget.fraisScolaires.config.monthlyExceptionsBySection[selectedSectionForException!]
                      ?.remove(selectedMonthForException);
                }
              } else {
                final key = "${selectedSectionForException!}|${selectedClasseScopeForException!}";
                if (amount != null) {
                  widget.fraisScolaires.config.monthlyExceptionsByClasse
                      .putIfAbsent(key, () => {})
                  [selectedMonthForException!] = amount;
                } else {
                  widget.fraisScolaires.config.monthlyExceptionsByClasse[key]
                      ?.remove(selectedMonthForException);
                }
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

  void _addAdministration() async {
    if (!await _verifyBackupPassword()) return;
    final nomController = TextEditingController();
    final percentController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouvelle Administration"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nomController, decoration: const InputDecoration(labelText: "Nom")),
            TextField(controller: percentController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Pourcentage (%)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final percent = double.tryParse(percentController.text);
              if (nomController.text.isNotEmpty && percent != null) {
                widget.fraisScolaires.config.administrations.add(
                  Administration(nom: nomController.text, pourcentage: percent),
                );
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
    final nomController = TextEditingController(text: admin.nom);
    final percentController = TextEditingController(text: admin.pourcentage.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier Administration"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nomController, decoration: const InputDecoration(labelText: "Nom")),
            TextField(controller: percentController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Pourcentage (%)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final percent = double.tryParse(percentController.text);
              if (nomController.text.isNotEmpty && percent != null) {
                admin.nom = nomController.text;
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