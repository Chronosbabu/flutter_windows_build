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

  String? selectedClasse;
  String? selectedSection;

  final List<String> availableClasses = ['7ème', '8ème', '1ère', '2ème', '3ème', '4ème'];

  // Focus pour navigation rapide
  final FocusNode nomFocus = FocusNode();
  final FocusNode postNomFocus = FocusNode();
  final FocusNode prenomFocus = FocusNode();

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
      selectedClasse = null;
      selectedSection = null;
    });
    nomFocus.requestFocus();
  }

  Future<void> _ajouterEleve() async {
    if (nomController.text.trim().isEmpty ||
        postNomController.text.trim().isEmpty ||
        prenomController.text.trim().isEmpty ||
        selectedClasse == null ||
        selectedSection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez remplir tous les champs")),
      );
      return;
    }

    // Génération automatique de l'ID unique
    String nomComplet = nomController.text.trim();
    String generatedId = widget.fraisScolaires.generateUniqueStudentId(
      nomComplet,
      widget.fraisScolaires.config.schoolName,
    );

    final nouvelEleve = Eleve(
      id: generatedId,
      nom: nomController.text.trim(),
      postNom: postNomController.text.trim(),
      prenom: prenomController.text.trim(),
      classe: selectedClasse!,
      section: selectedSection!,
    );

    widget.fraisScolaires.currentData.eleves.add(nouvelEleve);
    await widget.fraisScolaires.saveData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("✅ ${nouvelEleve.nom} ${nouvelEleve.postNom} ajouté\nID: ${nouvelEleve.id}"),
        duration: const Duration(seconds: 3),
      ),
    );

    _clearFields(); // Prépare pour l’élève suivant
  }

  @override
  Widget build(BuildContext context) {
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

            DropdownButtonFormField<String>(
              value: selectedClasse,
              decoration: const InputDecoration(
                labelText: "Classe",
                border: OutlineInputBorder(),
              ),
              items: availableClasses.map((classe) {
                return DropdownMenuItem(value: classe, child: Text(classe));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedClasse = value);
              },
            ),
            const SizedBox(height: 20),

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
                setState(() => selectedSection = value);
              },
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add, size: 28),
                label: const Text("Ajouter l'Élève", style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                onPressed: _ajouterEleve,
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
                    "L'ID unique est généré automatiquement pour chaque élève",
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
