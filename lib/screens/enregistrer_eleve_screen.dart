import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
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

  // ==========================================================================
  // ⚡ NOUVEAU — AUTRES INFORMATIONS SUR L'IDENTITÉ DE L'ÉLÈVE (OPTIONNEL)
  // ==========================================================================
  // Champs par défaut toujours proposés (mais jamais obligatoires) : nom du
  // père, nom de la mère, adresse, date de naissance, photo. En plus de ça,
  // l'utilisateur peut ajouter librement ses propres questions
  // personnalisées via customFieldsControllers (question -> contrôleur de
  // réponse). Toutes ces données sont saisies dans une boîte de dialogue
  // dédiée (_showAutresInfosDialog) ouverte depuis le bouton tout en bas du
  // formulaire.
  final pereNomController = TextEditingController();
  final mereNomController = TextEditingController();
  final adresseController = TextEditingController();
  DateTime? selectedDateNaissance;
  Uint8List? photoBytes;
  final Map<String, TextEditingController> customFieldsControllers = {};

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
    // ⚡ NOUVEAU
    pereNomController.dispose();
    mereNomController.dispose();
    adresseController.dispose();
    for (var c in customFieldsControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _clearFields() {
    nomController.clear();
    postNomController.clear();
    prenomController.clear();
    // ⚡ NOUVEAU — on vide les valeurs saisies pour cet élève, mais on garde
    // les QUESTIONS personnalisées déjà créées (elles restent proposées
    // pour l'élève suivant, très utile lors d'une saisie en série).
    pereNomController.clear();
    mereNomController.clear();
    adresseController.clear();
    for (var c in customFieldsControllers.values) {
      c.clear();
    }
    setState(() {
      selectedClasseNumero = null;
      selectedSousClasse = null;
      // On garde la section sélectionnée pour accélérer la saisie en série
      // ⚡ NOUVEAU
      selectedDateNaissance = null;
      photoBytes = null;
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
  //
  // ⚡ CORRIGÉ : les initiales de l'école sont désormais extraites
  // uniquement à partir des caractères alphanumériques (lettres et
  // chiffres) du nom de l'école. Avant, un nom d'école commençant par
  // un symbole (ex: "####") produisait un ID contenant ce symbole
  // (ex: "BB27#1"). Certains symboles comme '#' sont des caractères
  // RÉSERVÉS dans une URL : '#' marque le début d'un "fragment" et tout
  // ce qui le suit est tronqué silencieusement par Uri.parse() côté
  // client, avant même que la requête n'atteigne le serveur. Résultat :
  // le parent tape l'ID exact donné par l'école, le serveur ne reçoit
  // que la partie avant le '#', et répond "élève introuvable" alors que
  // les données existent bel et bien côté serveur.
  String _generateLocalStudentId() {
    final config = widget.fraisScolaires.config;

    String schoolInitials = config.schoolName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''))
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

  // ==========================================================================
  // ⚡ NOUVEAU — BOÎTE DE DIALOGUE "AUTRES INFORMATIONS" (OPTIONNEL)
  // ==========================================================================
  // Ouverte depuis le bouton tout en bas du formulaire. Contient :
  //   - Photo de l'élève (sélection depuis le PC via file_selector)
  //   - Nom du père / Nom de la mère / Adresse / Date de naissance
  //   - Un bouton "Ajouter une Question Personnalisée" qui permet à
  //     l'utilisateur de créer autant de champs libres qu'il le souhaite ;
  //     chaque question ajoutée fait apparaître immédiatement son propre
  //     champ de saisie dans la boîte de dialogue.
  // Toutes les valeurs vivent dans les contrôleurs de l'écran parent (pas
  // seulement dans la boîte de dialogue), donc rien n'est perdu si
  // l'utilisateur ferme puis rouvre la boîte de dialogue avant d'enregistrer
  // l'élève.
  Future<void> _showAutresInfosDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickPhoto() async {
            const typeGroup = XTypeGroup(
              label: 'images',
              extensions: ['png', 'jpg', 'jpeg'],
            );
            final file = await openFile(acceptedTypeGroups: [typeGroup]);
            if (file == null) return;
            final bytes = await file.readAsBytes();
            setDialogState(() => photoBytes = bytes);
          }

          Future<void> pickDate() async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: ctx,
              initialDate: selectedDateNaissance ?? DateTime(now.year - 10),
              firstDate: DateTime(1990),
              lastDate: now,
            );
            if (picked != null) {
              setDialogState(() => selectedDateNaissance = picked);
            }
          }

          Future<void> addCustomField() async {
            final questionController = TextEditingController();
            final question = await showDialog<String>(
              context: ctx,
              builder: (ctx2) => AlertDialog(
                title: const Text("Nouvelle Question Personnalisée"),
                content: TextField(
                  controller: questionController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: "Ex: Numéro de téléphone du parent",
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2),
                    child: const Text("Annuler"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final q = questionController.text.trim();
                      if (q.isNotEmpty) Navigator.pop(ctx2, q);
                    },
                    child: const Text("Ajouter"),
                  ),
                ],
              ),
            );
            if (question != null && question.isNotEmpty) {
              if (!customFieldsControllers.containsKey(question)) {
                setDialogState(() {
                  customFieldsControllers[question] = TextEditingController();
                });
              }
            }
          }

          void removeCustomField(String question) {
            setDialogState(() {
              customFieldsControllers[question]?.dispose();
              customFieldsControllers.remove(question);
            });
          }

          final dateLabel = selectedDateNaissance != null
              ? "${selectedDateNaissance!.day.toString().padLeft(2, '0')}/"
              "${selectedDateNaissance!.month.toString().padLeft(2, '0')}/"
              "${selectedDateNaissance!.year}"
              : "Non renseignée";

          return AlertDialog(
            title: const Text("Autres Informations (Optionnel)"),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Ces informations sont facultatives. Remplissez uniquement "
                          "ce dont votre école a besoin.",
                      style: TextStyle(color: Colors.grey, fontSize: 12.5),
                    ),
                    const SizedBox(height: 16),

                    // ---- Photo ----
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 45,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: photoBytes != null
                                ? MemoryImage(photoBytes!)
                                : null,
                            child: photoBytes == null
                                ? const Icon(Icons.person, size: 45, color: Colors.grey)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.photo_camera, size: 18),
                            label: Text(
                              photoBytes == null ? "Choisir une photo" : "Changer la photo",
                            ),
                            onPressed: pickPhoto,
                          ),
                          if (photoBytes != null)
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              label: const Text("Retirer", style: TextStyle(color: Colors.red)),
                              onPressed: () => setDialogState(() => photoBytes = null),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    TextField(
                      controller: pereNomController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Nom du père",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mereNomController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Nom de la mère",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: adresseController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: "Adresse",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Date de naissance",
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(dateLabel),
                      ),
                    ),

                    if (customFieldsControllers.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        "Questions Personnalisées",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...customFieldsControllers.entries.map(
                            (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: entry.value,
                                  decoration: InputDecoration(
                                    labelText: entry.key,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                                tooltip: "Supprimer cette question",
                                onPressed: () => removeCustomField(entry.key),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text("Ajouter une Question Personnalisée"),
                      onPressed: addCustomField,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Terminé"),
              ),
            ],
          );
        },
      ),
    );
    // Rafraîchit l'écran principal (ex: le résumé sous le bouton).
    if (mounted) setState(() {});
  }

  // ⚡ NOUVEAU — Nombre de champs optionnels actuellement remplis, affiché
  // en résumé sous le bouton "Autres Informations".
  int _countFilledExtras() {
    int count = 0;
    if (pereNomController.text.trim().isNotEmpty) count++;
    if (mereNomController.text.trim().isNotEmpty) count++;
    if (adresseController.text.trim().isNotEmpty) count++;
    if (selectedDateNaissance != null) count++;
    if (photoBytes != null) count++;
    count += customFieldsControllers.values
        .where((c) => c.text.trim().isNotEmpty)
        .length;
    return count;
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

      // ⚡ NOUVEAU — formatage de la date de naissance en "JJ/MM/AAAA"
      String dateNaissanceStr = '';
      if (selectedDateNaissance != null) {
        final d = selectedDateNaissance!;
        String two(int n) => n.toString().padLeft(2, '0');
        dateNaissanceStr = "${two(d.day)}/${two(d.month)}/${d.year}";
      }

      // ⚡ NOUVEAU — construction de la carte des questions personnalisées
      // (on ne garde que celles qui ont réellement une réponse remplie)
      final Map<String, String> customFieldsMap = {
        for (var entry in customFieldsControllers.entries)
          entry.key: entry.value.text.trim(),
      }..removeWhere((k, v) => v.isEmpty);

      final nouvelEleve = Eleve(
        id: generatedId,
        nom: nomController.text.trim(),
        postNom: postNomController.text.trim(),
        prenom: prenomController.text.trim(),
        classe: classeFinale,
        section: selectedSection!,
        // ⚡ NOUVEAU
        pereNom: pereNomController.text.trim(),
        mereNom: mereNomController.text.trim(),
        adresse: adresseController.text.trim(),
        dateNaissance: dateNaissanceStr,
        photoBase64: photoBytes != null ? base64Encode(photoBytes!) : null,
        customFields: customFieldsMap,
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

    // ⚡ NOUVEAU
    final extrasCount = _countFilledExtras();

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

            // ==========================================================================
            // ⚡ NOUVEAU — BOUTON "AUTRES INFORMATIONS" (TOUT EN BAS)
            // ==========================================================================
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.badge_outlined),
                label: Text(
                  extrasCount > 0
                      ? "Autres Informations ($extrasCount rempli(s))"
                      : "Autres Informations (Optionnel)",
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  side: const BorderSide(color: Colors.indigo),
                ),
                onPressed: _showAutresInfosDialog,
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                "Nom du père, nom de la mère, adresse, date de naissance, photo, "
                    "et vos propres questions personnalisées.",
                style: TextStyle(color: Colors.grey, fontSize: 11.5),
                textAlign: TextAlign.center,
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