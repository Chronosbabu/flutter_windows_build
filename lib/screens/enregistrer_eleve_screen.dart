import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';

class EnregistrerEleveScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const EnregistrerEleveScreen({super.key, required this.fraisScolaires});

  @override
  State<EnregistrerEleveScreen> createState() => _EnregistrerEleveScreenState();
}

class _EnregistrerEleveScreenState extends State<EnregistrerEleveScreen> {
  final nomController = TextEditingController();
  final postNomController = TextEditingController();
  final prenomController = TextEditingController();

  String? selectedSection;
  String? selectedClasseNumero;
  String? selectedSousClasse;

  // Focus pour navigation rapide
  final FocusNode nomFocus = FocusNode();
  final FocusNode postNomFocus = FocusNode();
  final FocusNode prenomFocus = FocusNode();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.fraisScolaires.config.sections.isNotEmpty) {
      selectedSection = widget.fraisScolaires.config.sections.first;
    }
  }

  @override
  void dispose() {
    nomController.dispose();
    postNomController.dispose();
    prenomController.dispose();
    nomFocus.dispose();
    postNomFocus.dispose();
    prenomFocus.dispose();
    super.dispose();
  }

  void _clearFields() {
    nomController.clear();
    postNomController.clear();
    prenomController.clear();
    setState(() {
      selectedClasseNumero = null;
      selectedSousClasse = null;
      // On garde la section sélectionnée pour accélérer la saisie en série
    });
    nomFocus.requestFocus();
  }

  // ==================== GÉNÉRATION D'ID 100% LOCALE ====================
  //
  // Avant : l'ID était demandé au serveur via une requête HTTP, ce qui
  // bloquait totalement l'ajout d'un élève sans connexion internet.
  //
  // Maintenant : l'ID est généré instantanément en local, à partir des
  // initiales de l'école + l'année scolaire + un numéro de séquence. On
  // vérifie qu'il n'existe déjà nulle part (année courante + tout
  // l'historique) pour garantir qu'il est toujours unique, même hors ligne.
  // La synchronisation avec le serveur se fait plus tard, uniquement quand
  // l'utilisateur appuie sur "Sauvegarder sur le Serveur" dans les Paramètres.
  String _generateLocalStudentId() {
    final config = widget.fraisScolaires.config;

    String schoolInitials = config.schoolName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .join()
        .toUpperCase();
    if (schoolInitials.isEmpty) schoolInitials = "EL";

    final yearPart = widget.fraisScolaires.currentYear.split('-').first;

    // Rassemble tous les IDs déjà utilisés, toutes années confondues,
    // pour être absolument certain de ne jamais avoir de doublon.
    final existingIds = <String>{};
    for (var yearData in widget.fraisScolaires.history.values) {
      for (var e in yearData.eleves) {
        if (e.id.isNotEmpty) existingIds.add(e.id);
      }
    }
    for (var e in widget.fraisScolaires.currentData.eleves) {
      if (e.id.isNotEmpty) existingIds.add(e.id);
    }

    int sequence = widget.fraisScolaires.currentData.eleves.length + 1;
    String candidate;
    do {
      candidate = "$schoolInitials$yearPart-${sequence.toString().padLeft(4, '0')}";
      sequence++;
    } while (existingIds.contains(candidate));

    return candidate;
  }

  // ==================== AJOUT MANUEL D'UN NUMÉRO DE CLASSE ====================
  // Utile surtout pour une section personnalisée qui n'a pas de classes
  // générées automatiquement.
  Future<void> _addClasseNumeroDialog() async {
    if (selectedSection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez d'abord choisir une section")),
      );
      return;
    }
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nouveau numéro de classe"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Ex: 7ème, 1ère...",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                await widget.fraisScolaires.addClasseNumero(selectedSection!, value);
                if (mounted) {
                  setState(() {
                    selectedClasseNumero = value;
                    selectedSousClasse = null;
                  });
                }
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
  }

  // ==================== AJOUT MANUEL D'UNE SOUS-CLASSE ====================
  Future<void> _addSousClasseDialog() async {
    if (selectedSection == null || selectedClasseNumero == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez d'abord choisir une section et un numéro de classe")),
      );
      return;
    }
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Nouvelle sous-classe pour $selectedClasseNumero"),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: "Ex: A, B, C...",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                await widget.fraisScolaires.addSubClasse(
                  selectedSection!,
                  selectedClasseNumero!,
                  value,
                );
                if (mounted) {
                  setState(() {
                    selectedSousClasse = value;
                  });
                }
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
  }

  Future<void> _ajouterEleve() async {
    if (nomController.text.trim().isEmpty ||
        postNomController.text.trim().isEmpty ||
        prenomController.text.trim().isEmpty ||
        selectedSection == null ||
        selectedClasseNumero == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez remplir tous les champs")),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Génération de l'ID 100% locale et instantanée (aucune connexion requise)
      String generatedId = _generateLocalStudentId();

      // Construction du nom final de classe : numéro + sous-classe (si choisie)
      String classeFinale = widget.fraisScolaires.buildFullClasseName(
        selectedClasseNumero!,
        selectedSousClasse,
      );

      final nouvelEleve = Eleve(
        id: generatedId,
        nom: nomController.text.trim(),
        postNom: postNomController.text.trim(),
        prenom: prenomController.text.trim(),
        classe: classeFinale,
        section: selectedSection!,
      );

      widget.fraisScolaires.currentData.eleves.add(nouvelEleve);
      await widget.fraisScolaires.saveData(); // Sauvegarde locale (fichier sur l'appareil)

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ ${nouvelEleve.nom} ${nouvelEleve.postNom} ajouté\nID: ${nouvelEleve.id}"),
          duration: const Duration(seconds: 3),
        ),
      );
      _clearFields(); // Prépare pour l'élève suivant
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de l'ajout : $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final classesNumeros = selectedSection != null
        ? widget.fraisScolaires.getClassesForSection(selectedSection!)
        : <String>[];

    final sousClasses = (selectedSection != null && selectedClasseNumero != null)
        ? widget.fraisScolaires.getSubClassesFor(selectedSection!, selectedClasseNumero!)
        : <String>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ajouter des Élèves"),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Inscription Rapide d'Élève",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Remplissez le formulaire et ajoutez plusieurs élèves rapidement",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 25),
            TextField(
              controller: nomController,
              focusNode: nomFocus,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Nom",
                border: OutlineInputBorder(),
              ),
              onEditingComplete: () => postNomFocus.requestFocus(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: postNomController,
              focusNode: postNomFocus,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Post-nom",
                border: OutlineInputBorder(),
              ),
              onEditingComplete: () => prenomFocus.requestFocus(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: prenomController,
              focusNode: prenomFocus,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Prénom",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // ---- Section (Maternelle / Primaire / Secondaire / ...) ----
            DropdownButtonFormField<String>(
              value: selectedSection,
              decoration: const InputDecoration(
                labelText: "Section",
                border: OutlineInputBorder(),
                helperText: "Ex: Maternelle, Primaire, Secondaire...",
              ),
              items: widget.fraisScolaires.config.sections.map((section) {
                return DropdownMenuItem(value: section, child: Text(section));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedSection = value;
                  selectedClasseNumero = null;
                  selectedSousClasse = null;
                });
              },
            ),
            const SizedBox(height: 20),

            // ---- Numéro de classe (automatique selon la section) ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedClasseNumero,
                    decoration: const InputDecoration(
                      labelText: "Numéro de classe",
                      border: OutlineInputBorder(),
                    ),
                    items: classesNumeros.map((c) {
                      return DropdownMenuItem(value: c, child: Text(c));
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedClasseNumero = value;
                        selectedSousClasse = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: "Ajouter un numéro de classe",
                  icon: const Icon(Icons.add_circle, color: Colors.indigo),
                  onPressed: _addClasseNumeroDialog,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ---- Sous-classe (toujours manuelle, optionnelle) ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedSousClasse,
                    decoration: const InputDecoration(
                      labelText: "Sous-classe (optionnel)",
                      border: OutlineInputBorder(),
                      helperText: "Ex: A, B, C...",
                    ),
                    items: sousClasses.map((s) {
                      return DropdownMenuItem(value: s, child: Text(s));
                    }).toList(),
                    onChanged: (value) {
                      setState(() => selectedSousClasse = value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: "Ajouter une sous-classe",
                  icon: const Icon(Icons.add_circle, color: Colors.indigo),
                  onPressed: _addSousClasseDialog,
                ),
              ],
            ),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.person_add, size: 28),
                label: Text(
                  _isSaving ? "Ajout en cours..." : "Ajouter l'Élève",
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isSaving ? null : _ajouterEleve,
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text("Terminer et Retourner"),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 30),
            const Center(
              child: Text(
                "Les champs se vident automatiquement après chaque ajout\n"
                    "L'ID unique est généré automatiquement, hors ligne, pour chaque élève",
                style: TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}