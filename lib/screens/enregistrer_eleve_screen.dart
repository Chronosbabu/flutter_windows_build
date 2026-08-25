import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import '../services/epson_printer_service.dart';

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

  // ==========================================================================
  // ⚡ CORRIGÉ — PAIEMENT OPTIONNEL DÈS L'INSCRIPTION (demande explicite de
  // la direction), maintenant CUMULABLE.
  //
  // AVANT : un unique SegmentedButton ("principal" xor "autres") empêchait
  // l'utilisateur de payer les DEUX en même temps lors de l'inscription —
  // c'était le bug signalé : il fallait choisir l'un OU l'autre, jamais les
  // deux à la fois.
  //
  // MAINTENANT : deux interrupteurs totalement INDÉPENDANTS,
  // `_payerPrincipal` et `_payerAutreFrais`. Chacun peut être activé seul,
  // les deux ensemble, ou aucun des deux (comportement par défaut,
  // inchangé). Chaque bloc affiche son propre champ de saisie une fois
  // activé, exactement comme avant, mais sans qu'activer l'un désactive
  // l'autre.
  //
  // Le paiement est appliqué à l'élève APRÈS sa création (une fois qu'il
  // existe réellement dans `currentData.eleves`), en réutilisant EXACTEMENT
  // les mêmes méthodes que les écrans dédiés :
  //   - Frais Principal -> `fs.handlePayment(...)`, la même méthode que
  //     `PaiementEleveScreen` : l'élève apparaîtra donc immédiatement, avec
  //     son paiement déjà à jour, dans l'écran "Paiements des Élèves".
  //   - Autre Frais -> `fs.payAutreFrais(...)`, la même méthode que
  //     `AutresFraisScreen` : l'élève apparaîtra donc immédiatement, marqué
  //     "Payé", dans l'écran "Autres Frais de Paiement".
  // Si les DEUX interrupteurs sont activés, les DEUX méthodes sont appelées
  // l'une après l'autre pour le même élève, et les DEUX reçus sont imprimés
  // (si une imprimante est configurée). Aucune nouvelle logique de calcul
  // n'est inventée ici — uniquement une interface qui appelle les mêmes
  // méthodes, indépendamment l'une de l'autre.
  // ==========================================================================
  bool _payerPrincipal = false;
  final _montantPrincipalController = TextEditingController();

  bool _payerAutreFrais = false;
  AutreFrais? _selectedAutreFraisPaiement;

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
    // ⚡ NOUVEAU — paiement à l'inscription
    _montantPrincipalController.dispose();
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
      // ⚡ CORRIGÉ — on réinitialise les DEUX paiements à chaque nouvel
      // élève : un paiement ne doit jamais être appliqué par erreur à
      // l'élève suivant lors d'une saisie en série.
      _payerPrincipal = false;
      _montantPrincipalController.clear();
      _payerAutreFrais = false;
      _selectedAutreFraisPaiement = null;
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
                    // ⚡ NOUVEAU — la classe change, l'éligibilité aux
                    // autres frais aussi : on réinitialise le choix.
                    _selectedAutreFraisPaiement = null;
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
                    // ⚡ NOUVEAU
                    _selectedAutreFraisPaiement = null;
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
  // ⚡ NOUVEAU — HELPERS POUR LE PAIEMENT À L'INSCRIPTION
  // ==========================================================================

  /// Nom complet de la classe telle que sélectionnée dans le formulaire
  /// (numéro + sous-classe), ou `null` si le numéro de classe n'est pas
  /// encore choisi. Utilisé uniquement pour prévisualiser le montant requis
  /// et pour filtrer les "autres frais" éligibles AVANT que l'élève
  /// n'existe réellement (donc sans pouvoir utiliser
  /// `autreFraisAppliesToStudent`, qui a besoin d'un `Eleve`).
  String? get _classeCompleteSelectionnee {
    if (selectedClasseNumero == null) return null;
    return widget.fraisScolaires
        .buildFullClasseName(selectedClasseNumero!, selectedSousClasse);
  }

  /// Montant mensuel requis pour la section/classe actuellement
  /// sélectionnée (affiché à titre indicatif à côté du champ "Montant" du
  /// frais principal, pour éviter les erreurs de saisie).
  double? get _montantMensuelIndicatif {
    if (selectedSection == null) return null;
    return widget.fraisScolaires.getRequiredForMonth(
      widget.fraisScolaires.months.first,
      selectedSection!,
      _classeCompleteSelectionnee,
    );
  }

  /// "Autres Frais" applicables à la section/classe actuellement
  /// sélectionnée dans le formulaire, selon le même principe que
  /// `FraisScolaires.autreFraisAppliesToStudent` (reproduit ici car
  /// l'élève n'existe pas encore au moment où ce filtre est affiché).
  List<AutreFrais> get _autresFraisEligibles {
    if (selectedSection == null) return [];
    final classeComplete = _classeCompleteSelectionnee;
    return widget.fraisScolaires.getAutresFrais().where((f) {
      switch (f.scope) {
        case 'section':
          return f.section == selectedSection;
        case 'classe':
          return classeComplete != null && f.classe == classeComplete;
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  // ⚡ NOUVEAU — recharge le logo depuis le disque, comme les autres écrans
  // de paiement (PaiementEleveScreen / AutresFraisScreen), pour que le
  // reçu imprimé ici utilise le même logo que partout ailleurs.
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

  /// Imprime le reçu du paiement de frais principal effectué à
  /// l'inscription — reprend exactement la même logique que
  /// `PaiementEleveScreen._printReceiptAfterPayment`. Silencieux (ne fait
  /// rien) si aucune imprimante n'est configurée : l'inscription elle-même
  /// n'est jamais bloquée par l'impression.
  Future<void> _imprimerRecuPrincipalSiPossible(
      Eleve eleve, String mois, double montantPaye) async {
    final prefs = await SharedPreferences.getInstance();
    final printerName = prefs.getString('printer_name') ?? '';
    if (printerName.isEmpty) return;

    final logoBytes = await _loadLogoBytesFromDisk();
    final double montantRequis = widget.fraisScolaires
        .getRequiredForMonth(mois, eleve.section, eleve.classe);
    final double totalPaye = widget.fraisScolaires.getStudentTotalPaid(eleve);
    final double totalRequis =
        widget.fraisScolaires.getStudentPending(eleve) + totalPaye;
    final double resteAPayerMois = montantRequis - (eleve.paid[mois] ?? 0);

    await EscPosPrinterService.printReceipt(
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
      logoBytes: logoBytes,
    );
  }

  /// Imprime le reçu d'un "autre frais" payé à l'inscription — reprend
  /// exactement la même logique que `AutresFraisScreen._imprimerRecu`.
  /// Silencieux si aucune imprimante n'est configurée.
  Future<void> _imprimerRecuAutreFraisSiPossible(
      Eleve eleve, AutreFrais frais) async {
    final prefs = await SharedPreferences.getInstance();
    final printerName = prefs.getString('printer_name') ?? '';
    if (printerName.isEmpty) return;

    await EscPosPrinterService.printAutreFraisReceipt(
      printerName: printerName,
      schoolName: widget.fraisScolaires.config.schoolName,
      titreFrais: frais.nom,
      studentName: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      section: eleve.section,
      montant: frais.montant,
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

    // ==========================================================================
    // ⚡ CORRIGÉ — VALIDATION DES DEUX PAIEMENTS OPTIONNELS, INDÉPENDAMMENT
    // L'UN DE L'AUTRE (avant toute création d'élève, pour ne jamais
    // inscrire un élève à moitié à cause d'une erreur de saisie sur l'un
    // des deux paiements).
    // ==========================================================================
    double? montantPrincipalAPayer;
    if (_payerPrincipal) {
      montantPrincipalAPayer =
          double.tryParse(_montantPrincipalController.text.trim());
      if (montantPrincipalAPayer == null || montantPrincipalAPayer <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Veuillez indiquer un montant valide pour le paiement du frais principal, "
                    "ou décochez \"Payer le Frais Principal\"."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (_payerAutreFrais && _selectedAutreFraisPaiement == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Veuillez choisir un frais additionnel à payer, ou "
                  "décochez \"Payer un Autre Frais\"."),
          backgroundColor: Colors.red,
        ),
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

      // ==========================================================================
      // ⚡ CORRIGÉ — APPLICATION DES DEUX PAIEMENTS OPTIONNELS, DE MANIÈRE
      // CUMULABLE.
      //
      // On réutilise ici EXACTEMENT les mêmes méthodes que les écrans dédiés
      // (`fs.handlePayment` pour le frais principal, `fs.payAutreFrais` pour
      // un autre frais), maintenant que `nouvelEleve` existe réellement dans
      // `currentData.eleves`. Les deux blocs ci-dessous sont indépendants :
      // si les DEUX interrupteurs sont activés, les DEUX paiements sont
      // enregistrés l'un après l'autre pour le même élève — c'est le point
      // qui était bloqué avant (un seul des deux pouvait être choisi).
      // C'est ce qui garantit que l'élève apparaîtra avec son paiement déjà
      // à jour dans "Paiements des Élèves" ET/OU "Autres Frais de Paiement",
      // sans logique de calcul dupliquée.
      // ==========================================================================
      String? moisPrincipalPaye;
      if (_payerPrincipal && montantPrincipalAPayer != null) {
        // Un élève qui vient d'être inscrit n'a évidemment aucun mois déjà
        // payé : on démarre donc toujours sur le premier mois de l'année
        // scolaire (Septembre) — `handlePayment` répartit ensuite
        // automatiquement sur les mois suivants si le montant les
        // dépasse, exactement comme dans "Paiements des Élèves".
        moisPrincipalPaye = widget.fraisScolaires.months.first;
        widget.fraisScolaires.handlePayment(
          nouvelEleve,
          moisPrincipalPaye,
          montantPrincipalAPayer,
        );
      }

      AutreFrais? autreFraisPaye;
      if (_payerAutreFrais && _selectedAutreFraisPaiement != null) {
        final fraisChoisi = _selectedAutreFraisPaiement!;
        await widget.fraisScolaires.payAutreFrais(
          frais: fraisChoisi,
          eleve: nouvelEleve,
          enregistrePar: 'Direction',
        );
        autreFraisPaye = fraisChoisi;
      }

      await widget.fraisScolaires.saveData(); // Sauvegarde locale (fichier sur l'appareil)

      // ⚡ CORRIGÉ — impression des DEUX reçus correspondants, si une
      // imprimante est configurée (comportement silencieux sinon, comme
      // partout ailleurs). Avant, seul un des deux pouvait être imprimé
      // (else if) ; maintenant chaque paiement réellement effectué
      // déclenche sa propre impression, indépendamment de l'autre.
      if (moisPrincipalPaye != null && montantPrincipalAPayer != null) {
        await _imprimerRecuPrincipalSiPossible(
            nouvelEleve, moisPrincipalPaye, montantPrincipalAPayer);
      }
      if (autreFraisPaye != null) {
        await _imprimerRecuAutreFraisSiPossible(nouvelEleve, autreFraisPaye);
      }

      if (!mounted) return;

      // ⚡ CORRIGÉ — message de confirmation enrichi du détail des DEUX
      // paiements, le cas échéant (chacun sur sa propre ligne, si les deux
      // ont été effectués).
      String messagePaiement = '';
      if (moisPrincipalPaye != null && montantPrincipalAPayer != null) {
        messagePaiement +=
        "\n💰 Frais Principal : ${montantPrincipalAPayer.toStringAsFixed(0)} FC";
      }
      if (autreFraisPaye != null) {
        messagePaiement +=
        "\n💰 ${autreFraisPaye.nom} : ${autreFraisPaye.montant.toStringAsFixed(0)} FC";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "✅ ${nouvelEleve.nom} ${nouvelEleve.postNom} ajouté\nID: ${nouvelEleve.id}$messagePaiement"),
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

  // ==========================================================================
  // ⚡ CORRIGÉ — BLOC "PAIEMENT À L'INSCRIPTION (OPTIONNEL)"
  //
  // Remplace l'ancien SegmentedButton exclusif par DEUX cartes/interrupteurs
  // totalement indépendants : "Payer le Frais Principal" et "Payer un Autre
  // Frais". Chacun peut être activé seul ou en même temps que l'autre.
  // ==========================================================================
  Widget _buildPaiementInscriptionSection() {
    final montantMensuel = _montantMensuelIndicatif;
    final autresFraisEligibles = _autresFraisEligibles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Paiement à l'inscription (optionnel)",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        const Text(
          "Vous pouvez encaisser le Frais Principal, un Autre Frais, "
              "ou les deux à la fois, directement ici sans repasser par "
              "un autre écran.",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        // ---- BLOC 1 : FRAIS PRINCIPAL (indépendant du bloc 2) ----
        Card(
          elevation: 2,
          color: Colors.indigo.withAlpha(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.indigo.withAlpha(60)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Row(
                    children: [
                      Icon(Icons.school, size: 20, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        "Payer le Frais Principal",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  subtitle: const Text(
                    "Optionnel — encaisse le frais mensuel principal dès "
                        "l'inscription.",
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _payerPrincipal,
                  activeColor: Colors.indigo,
                  onChanged: (value) =>
                      setState(() => _payerPrincipal = value),
                ),
                if (_payerPrincipal) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _montantPrincipalController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: "Montant à payer (FC)",
                      border: const OutlineInputBorder(),
                      helperText: montantMensuel != null
                          ? "Frais mensuel habituel pour cette classe : "
                          "${montantMensuel.toStringAsFixed(0)} FC"
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Le paiement démarre automatiquement au premier mois de "
                        "l'année scolaire (Septembre), comme dans \"Paiements "
                        "des Élèves\". Si le montant dépasse un mois, il est "
                        "reporté automatiquement sur les mois suivants.",
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ---- BLOC 2 : AUTRE FRAIS (indépendant du bloc 1) ----
        Card(
          elevation: 2,
          color: Colors.teal.withAlpha(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.teal.withAlpha(60)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Row(
                    children: [
                      Icon(Icons.receipt_long, size: 20, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(
                        "Payer un Autre Frais",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  subtitle: const Text(
                    "Optionnel — encaisse un frais additionnel (ex: Frais "
                        "de l'État, Frais d'Aide...) dès l'inscription.",
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _payerAutreFrais,
                  activeColor: Colors.teal,
                  onChanged: (value) =>
                      setState(() => _payerAutreFrais = value),
                ),
                if (_payerAutreFrais) ...[
                  const SizedBox(height: 8),
                  if (autresFraisEligibles.isEmpty)
                    const Text(
                      "Aucun frais additionnel ne s'applique à la section/classe "
                          "sélectionnée. Allez dans Paramètres > \"Autres Frais de "
                          "Paiement\" pour en ajouter.",
                      style: TextStyle(color: Colors.red, fontSize: 12.5),
                    )
                  else
                    DropdownButtonFormField<AutreFrais>(
                      value: autresFraisEligibles
                          .contains(_selectedAutreFraisPaiement)
                          ? _selectedAutreFraisPaiement
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "Frais additionnel à payer",
                        border: OutlineInputBorder(),
                      ),
                      items: autresFraisEligibles
                          .map(
                            (f) => DropdownMenuItem(
                          value: f,
                          child: Text(
                              "${f.nom} — ${f.montant.toStringAsFixed(0)} FC"),
                        ),
                      )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedAutreFraisPaiement = value),
                    ),
                ],
              ],
            ),
          ),
        ),

        // ⚡ NOUVEAU — petit récapitulatif visuel si les deux sont activés,
        // pour rassurer l'utilisateur que les deux seront bien enregistrés
        // ensemble au moment de l'ajout.
        if (_payerPrincipal && _payerAutreFrais) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Les deux paiements (Frais Principal + Autre Frais) "
                        "seront enregistrés en même temps pour cet élève.",
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
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
                  // ⚡ NOUVEAU — la section change, l'éligibilité aux
                  // autres frais aussi.
                  _selectedAutreFraisPaiement = null;
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
                        // ⚡ NOUVEAU
                        _selectedAutreFraisPaiement = null;
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
                      setState(() {
                        selectedSousClasse = value;
                        // ⚡ NOUVEAU
                        _selectedAutreFraisPaiement = null;
                      });
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

            // ==========================================================================
            // ⚡ CORRIGÉ — PAIEMENT À L'INSCRIPTION (OPTIONNEL, CUMULABLE),
            // placé après le choix de la section/classe (nécessaire pour
            // connaître le montant mensuel indicatif et les "autres frais"
            // éligibles) et avant le bouton d'ajout.
            // ==========================================================================
            const SizedBox(height: 24),
            _buildPaiementInscriptionSection(),

            const SizedBox(height: 30),
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