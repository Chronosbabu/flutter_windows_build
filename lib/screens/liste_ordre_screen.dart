import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import '../services/cahier_paiement_service.dart';

class ListeOrdreScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;

  const ListeOrdreScreen({super.key, required this.fraisScolaires});

  @override
  State<ListeOrdreScreen> createState() => _ListeOrdreScreenState();
}

class _ListeOrdreScreenState extends State<ListeOrdreScreen> {
  String? selectedSection;
  String? selectedClasse;
  String selectedMois = '';
  // true = "Ont déjà payé" (en ordre) | false = "N'ont pas encore payé"
  bool enOrdre = true;

  // ⚡ NOUVEAU — sélection de plusieurs mois (facultatif).
  // multiMois = false : fonctionnement habituel, un seul mois.
  bool multiMois = false;
  final Set<String> moisSelection = {};
  // true  = la condition doit être vraie pour TOUS les mois choisis
  // false = il suffit qu'elle soit vraie pour AU MOINS UN mois
  bool tousLesMois = true;

  // Résultat d'un seul mois (comportement habituel)
  List<Eleve> resultats = [];
  // ⚡ NOUVEAU — résultat sur plusieurs mois
  List<OrdreEleveMulti> resultatsMulti = [];
  // Ce que la dernière génération contenait (pour l'affichage et le PDF)
  bool resultatEstMulti = false;
  List<String> moisGeneres = [];
  bool statutGenere = true;
  bool conditionGeneree = true;

  bool listeGeneree = false;

  // ⚡ NOUVEAU — indique qu'un cahier de paiement est en cours de génération
  bool _generationCahier = false;

  FraisScolaires get fs => widget.fraisScolaires;

  @override
  void initState() {
    super.initState();
    if (fs.months.isNotEmpty) {
      selectedMois = fs.months.first;
    }
  }

  List<String> get _classesDisponibles {
    if (selectedSection != null) {
      return fs.getAllDisplayClassesForSection(selectedSection!);
    }
    return fs.getAllDisplayClasses();
  }

  // --------------------------------------------------------------------------
  // ⚡ NOUVEAU — outils de sélection des mois
  // --------------------------------------------------------------------------
  void _selectionnerJusquaCeMois() {
    final String? courant = fs.currentSchoolMonthName;
    final int idx = courant == null ? -1 : fs.months.indexOf(courant);
    // Hors année scolaire (vacances) : on prend tous les mois.
    final int fin = idx < 0 ? fs.months.length - 1 : idx;
    setState(() {
      moisSelection
        ..clear()
        ..addAll(fs.months.sublist(0, fin + 1));
      listeGeneree = false;
    });
  }

  String _texteCondition() {
    return fs.libelleConditionOrdreMulti(
      enOrdre: enOrdre,
      tousLesMois: tousLesMois,
    );
  }

  void _genererListe() {
    if (multiMois) {
      final List<String> choisis = fs.trierMoisScolaires(moisSelection);
      if (choisis.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Choisissez au moins un mois."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (choisis.length >= 2) {
        // ⚡ Plusieurs mois : nouvelle logique.
        setState(() {
          resultatsMulti = fs.getStudentsByOrderStatusMulti(
            mois: choisis,
            enOrdre: enOrdre,
            tousLesMois: tousLesMois,
            sectionFilter: selectedSection,
            classFilter: selectedClasse,
          );
          resultatEstMulti = true;
          moisGeneres = choisis;
          statutGenere = enOrdre;
          conditionGeneree = tousLesMois;
          listeGeneree = true;
        });
        return;
      }

      // Un seul mois coché : même fonctionnement que d'habitude.
      _genererListeUnMois(choisis.first);
      return;
    }

    if (selectedMois.isEmpty) return;
    _genererListeUnMois(selectedMois);
  }

  void _genererListeUnMois(String mois) {
    setState(() {
      // ⚡ getStudentsByOrderStatus utilise déjà en interne
      // isStudentEnOrdrePourMois -> getRequiredForMonthForEleve, donc un
      // élève avec une exception de paiement personnalisée est
      // automatiquement classé "en ordre" / "pas en ordre" en fonction de
      // SON propre montant requis, et non celui de sa section/classe.
      resultats = fs.getStudentsByOrderStatus(
        mois: mois,
        enOrdre: enOrdre,
        sectionFilter: selectedSection,
        classFilter: selectedClasse,
      );
      resultatEstMulti = false;
      moisGeneres = [mois];
      statutGenere = enOrdre;
      conditionGeneree = tousLesMois;
      listeGeneree = true;
    });
  }

  String _nomFichierParDefaut() {
    final String base =
    statutGenere ? "Liste_En_Ordre" : "Liste_Pas_En_Ordre";
    if (!resultatEstMulti) {
      return "${base}_${moisGeneres.isNotEmpty ? moisGeneres.first : selectedMois}";
    }
    if (moisGeneres.length <= 4) {
      return "${base}_${moisGeneres.map(fs.libelleMoisCourt).join('-')}";
    }
    return "${base}_${moisGeneres.length}_mois";
  }

  Future<void> _genererPdf() async {
    if (!listeGeneree) return;

    final controller = TextEditingController(text: _nomFichierParDefaut());

    final filename = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Titre du fichier PDF"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Nom du fichier",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Générer"),
          ),
        ],
      ),
    );

    if (filename == null || filename.isEmpty) return;

    if (resultatEstMulti) {
      // ⚡ NOUVEAU — PDF sur plusieurs mois (une colonne par mois).
      await fs.generateOrderStatusMultiPdf(
        filename: filename,
        mois: moisGeneres,
        enOrdre: statutGenere,
        tousLesMois: conditionGeneree,
        sectionFilter: selectedSection,
        classFilter: selectedClasse,
      );
    } else {
      // ⚡ generateOrderStatusPdf utilise déjà en interne
      // getRequiredForMonthForEleve pour la colonne "Payé / Requis", donc
      // le PDF reflète lui aussi correctement les montants personnalisés.
      await fs.generateOrderStatusPdf(
        filename: filename,
        mois: moisGeneres.first,
        enOrdre: statutGenere,
        sectionFilter: selectedSection,
        classFilter: selectedClasse,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Fichier PDF généré avec succès"),
        ),
      );
    }
  }

  // ==========================================================================
  // ⚡ NOUVEAU — CAHIER DE PAIEMENT (PDF)
  // ==========================================================================
  // Génère un cahier de paiement pour la section / classe actuellement
  // choisies dans les filtres ci-dessus (toutes si rien n'est choisi).
  // Le mois et le statut "Ont déjà payé / Pas encore payé" ne sont PAS
  // utilisés : le cahier montre tous les mois, de Septembre à Juin.
  // Fonction en lecture seule : aucune donnée de l'école n'est modifiée.
  Future<void> _genererCahier() async {
    if (_generationCahier) return;

    final String sectionTxt = selectedSection ?? "Toutes les sections";
    final String classeTxt = selectedClasse ?? "Toutes les classes";
    final String nomParDefaut =
    "Cahier_Paiement_${selectedSection ?? 'Toutes_Sections'}_${selectedClasse ?? 'Toutes_Classes'}"
        .replaceAll(' ', '_');

    final controller = TextEditingController(text: nomParDefaut);

    final filename = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cahier de paiement (PDF)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Section : $sectionTxt\nClasse : $classeTxt",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              "Une page (ou plus) par classe, avec tous les élèves et les "
                  "mois de Septembre à Juin : montant payé, mois soldé ou "
                  "reste à payer.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "Nom du fichier",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Générer"),
          ),
        ],
      ),
    );

    if (filename == null || filename.isEmpty) return;

    setState(() => _generationCahier = true);

    final resultat = await genererCahierPaiementPdf(
      fraisScolaires: fs,
      filename: filename,
      sectionFilter: selectedSection,
      classFilter: selectedClasse,
    );

    if (!mounted) return;
    setState(() => _generationCahier = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resultat.succes
              ? "✅ Cahier généré : ${resultat.nbEleves} élève(s), "
              "${resultat.nbClasses} classe(s).\nFichier : ${resultat.chemin}"
              : "❌ ${resultat.erreur ?? 'Erreur inconnue'}",
        ),
        backgroundColor: resultat.succes ? Colors.green : Colors.red,
        duration: const Duration(seconds: 7),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ⚡ NOUVEAU — blocs d'affichage pour la sélection de plusieurs mois
  // --------------------------------------------------------------------------
  Widget _blocMultiMois() {
    final List<String> choisis = fs.trierMoisScolaires(moisSelection);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 0,
          children: fs.months.map((m) {
            final bool sel = moisSelection.contains(m);
            return FilterChip(
              label: Text(m, style: const TextStyle(fontSize: 12)),
              selected: sel,
              selectedColor: Colors.indigo.shade100,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    moisSelection.add(m);
                  } else {
                    moisSelection.remove(m);
                  }
                  listeGeneree = false;
                });
              },
            );
          }).toList(),
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton(
              onPressed: () => setState(() {
                moisSelection
                  ..clear()
                  ..addAll(fs.months);
                listeGeneree = false;
              }),
              child: const Text("Tout"),
            ),
            TextButton(
              onPressed: _selectionnerJusquaCeMois,
              child: const Text("Jusqu'à ce mois"),
            ),
            TextButton(
              onPressed: () => setState(() {
                moisSelection.clear();
                listeGeneree = false;
              }),
              child: const Text("Aucun"),
            ),
          ],
        ),
        if (choisis.length >= 2) ...[
          const SizedBox(height: 4),
          const Text(
            "Condition",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text("Tous les mois",
                      style: TextStyle(fontSize: 12)),
                  selected: tousLesMois,
                  onSelected: (_) => setState(() {
                    tousLesMois = true;
                    listeGeneree = false;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text("Au moins un mois",
                      style: TextStyle(fontSize: 12)),
                  selected: !tousLesMois,
                  onSelected: (_) => setState(() {
                    tousLesMois = false;
                    listeGeneree = false;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Seront listés : ${_texteCondition().toLowerCase()} "
                "(${choisis.map(fs.libelleMoisCourt).join(', ')}).",
            style: const TextStyle(fontSize: 12, color: Colors.indigo),
          ),
        ] else if (choisis.length == 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Un seul mois choisi (${choisis.first}) : la liste fonctionne "
                  "comme d'habitude. Cochez un 2ᵉ mois pour comparer plusieurs "
                  "mois.",
              style: const TextStyle(fontSize: 12, color: Colors.indigo),
            ),
          ),
      ],
    );
  }

  Widget _puceMois(OrdreMoisDetail d) {
    final bool ok = d.enOrdre;
    final Color c = ok ? Colors.green.shade700 : Colors.red.shade700;
    final String court = fs.libelleMoisCourt(d.mois);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Text(
        ok ? "$court ✓" : "$court −${formatMontant(d.reste)}",
        style: TextStyle(
          fontSize: 11,
          color: c,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _carteEleveMulti(int index, OrdreEleveMulti l) {
    final Eleve e = l.eleve;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(
          backgroundColor: statutGenere ? Colors.green : Colors.red,
          child: Text(
            "${index + 1}",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                "${e.nom} ${e.postNom} ${e.prenom}",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (e.montantMensuelPersonnalise != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.star, size: 16, color: Colors.indigo),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${e.section} - ${e.classe}"),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: l.details.map(_puceMois).toList(),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${l.totalPaye.toStringAsFixed(0)} / ${l.totalRequis.toStringAsFixed(0)} FC",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: statutGenere
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
            ),
            if (l.totalReste > 0)
              Text(
                "Reste ${formatMontant(l.totalReste)} FC",
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
          ],
        ),
      ),
    );
  }

  Widget _carteEleveUnMois(int index, Eleve e) {
    final String mois = moisGeneres.first;
    final paye = e.paid[mois] ?? 0;
    // ⚡ CORRIGÉ — utilise désormais
    // getRequiredForMonthForEleve pour que le montant
    // affiché soit bien celui de CET élève (montant
    // personnalisé si exception, sinon montant normal
    // de sa section/classe).
    final requis = fs.getRequiredForMonthForEleve(e, mois);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statutGenere ? Colors.green : Colors.red,
          child: Text(
            "${index + 1}",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                "${e.nom} ${e.postNom} ${e.prenom}",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            // ⚡ NOUVEAU — petit badge si l'élève a une
            // exception de paiement personnalisée, pour
            // que ce soit visible directement dans la liste.
            if (e.montantMensuelPersonnalise != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.star, size: 16, color: Colors.indigo),
              ),
          ],
        ),
        subtitle: Text("${e.section} - ${e.classe}"),
        trailing: Text(
          "${paye.toStringAsFixed(0)} / ${requis.toStringAsFixed(0)} FC",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: statutGenere ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectionLabel = selectedSection ?? "Toutes les sections";
    final classeLabel = selectedClasse ?? "Toutes les classes";
    final int nbResultats =
    resultatEstMulti ? resultatsMulti.length : resultats.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Liste En Ordre / Pas En Ordre"),
        centerTitle: true,
        actions: [
          if (listeGeneree && nbResultats > 0)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: "Générer le PDF",
              onPressed: _genererPdf,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ==================== FILTRES ====================
            // Zone défilable : avec la sélection de plusieurs mois, les
            // filtres peuvent devenir hauts sur un petit écran.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: const Text("Toutes Sections"),
                            value: selectedSection,
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text("Toutes Sections"),
                              ),
                              ...fs.config.sections.map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s))),
                            ],
                            onChanged: (val) {
                              setState(() {
                                selectedSection = val;
                                selectedClasse = null;
                                listeGeneree = false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            hint: const Text("Toutes Classes"),
                            value: selectedClasse,
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text("Toutes Classes"),
                              ),
                              ..._classesDisponibles.map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c))),
                            ],
                            onChanged: (val) {
                              setState(() {
                                selectedClasse = val;
                                listeGeneree = false;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ⚡ NOUVEAU — interrupteur facultatif « plusieurs mois »
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: multiMois,
                      onChanged: (v) {
                        setState(() {
                          multiMois = v;
                          if (v && moisSelection.isEmpty &&
                              selectedMois.isNotEmpty) {
                            moisSelection.add(selectedMois);
                          }
                          listeGeneree = false;
                        });
                      },
                      title: const Text("Choisir plusieurs mois"),
                      subtitle: const Text(
                        "Facultatif. Désactivé : un seul mois, comme avant.",
                        style: TextStyle(fontSize: 11),
                      ),
                    ),

                    if (!multiMois)
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              hint: const Text("Mois"),
                              value: selectedMois.isEmpty ? null : selectedMois,
                              items: fs.months
                                  .map((m) => DropdownMenuItem(
                                  value: m, child: Text(m)))
                                  .toList(),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  selectedMois = val;
                                  listeGeneree = false;
                                });
                              },
                            ),
                          ),
                        ],
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _blocMultiMois(),
                      ),

                    const SizedBox(height: 12),
                    // Statut de paiement
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("Ont déjà payé"),
                            selected: enOrdre == true,
                            onSelected: (_) {
                              setState(() {
                                enOrdre = true;
                                // Par défaut : en ordre pour TOUS les mois.
                                tousLesMois = true;
                                listeGeneree = false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("Pas encore payé"),
                            selected: enOrdre == false,
                            onSelected: (_) {
                              setState(() {
                                enOrdre = false;
                                // Par défaut : il manque quelque chose sur AU
                                // MOINS UN mois (liste complémentaire de
                                // « Ont déjà payé »).
                                tousLesMois = false;
                                listeGeneree = false;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.filter_alt),
                label: const Text("Générer la Liste"),
                onPressed: _genererListe,
              ),
            ),
            const SizedBox(height: 8),

            // ==================== ⚡ NOUVEAU — CAHIER DE PAIEMENT ====================
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _generationCahier
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.menu_book),
                label: Text(_generationCahier
                    ? "Génération du cahier..."
                    : "Cahier de paiement (PDF)"),
                onPressed: _generationCahier ? null : _genererCahier,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "Le cahier utilise la section et la classe choisies ci-dessus "
                    "(toutes si rien n'est choisi) et montre tous les mois.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),

            // ==================== RÉSUMÉ ====================
            if (listeGeneree)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statutGenere
                      ? Colors.green.withOpacity(0.08)
                      : Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statutGenere
                        ? Colors.green.withOpacity(0.35)
                        : Colors.red.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resultatEstMulti
                          ? (statutGenere
                          ? "Élèves qui ont déjà payé (${moisGeneres.length} mois)"
                          : "Élèves qui n'ont pas encore payé (${moisGeneres.length} mois)")
                          : (statutGenere
                          ? "Élèves qui ont déjà payé ${moisGeneres.first}"
                          : "Élèves qui n'ont pas encore payé ${moisGeneres.first}"),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (resultatEstMulti) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Mois : ${moisGeneres.join(', ')}",
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Condition : ${fs.libelleConditionOrdreMulti(enOrdre: statutGenere, tousLesMois: conditionGeneree)}",
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      "Section : $sectionLabel  |  Classe : $classeLabel",
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Total : $nbResultats élève(s)",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

            // ==================== LISTE ====================
            Expanded(
              child: !listeGeneree
                  ? const Center(
                child: Text(
                  "Sélectionnez les filtres puis appuyez sur « Générer la Liste »",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
                  : nbResultats == 0
                  ? const Center(
                child: Text(
                  "Aucun élève ne correspond à ces critères.",
                  style: TextStyle(color: Colors.grey),
                ),
              )
                  : ListView.builder(
                itemCount: nbResultats,
                itemBuilder: (context, index) {
                  if (resultatEstMulti) {
                    return _carteEleveMulti(
                        index, resultatsMulti[index]);
                  }
                  return _carteEleveUnMois(index, resultats[index]);
                },
              ),
            ),

            // Bouton PDF en bas si liste générée
            if (listeGeneree && nbResultats > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("Générer le PDF"),
                  onPressed: _genererPdf,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}