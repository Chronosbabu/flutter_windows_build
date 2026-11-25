import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';
import '../services/cahier_paiement_service.dart';
import 'recouvrement_autres_frais_screen.dart';

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

  // ⚡ NOUVEAU — élèves en exception.
  // Exonérés (0 FC à payer pour le mois) : exclus par défaut, car ils n'ont
  // rien payé et ne doivent rien.
  bool inclureExoneres = false;
  // Élèves qui paient un montant différent : inclus par défaut (ils paient).
  bool inclureMontantDifferent = true;
  // Choix utilisés pour la dernière liste générée (pour le PDF).
  bool exoneresGeneres = false;
  bool montantDifferentGeneres = true;
  ResumeOrdre? resumeGenere;
  bool _generationExceptions = false;

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
            inclureExoneres: inclureExoneres,
            inclureMontantDifferent: inclureMontantDifferent,
          );
          resultatEstMulti = true;
          moisGeneres = choisis;
          statutGenere = enOrdre;
          conditionGeneree = tousLesMois;
          _memoriserChoixExceptions(choisis);
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
      resultats = fs.getStudentsByOrderStatusAvecExceptions(
        mois: mois,
        enOrdre: enOrdre,
        sectionFilter: selectedSection,
        classFilter: selectedClasse,
        inclureExoneres: inclureExoneres,
        inclureMontantDifferent: inclureMontantDifferent,
      );
      resultatEstMulti = false;
      moisGeneres = [mois];
      statutGenere = enOrdre;
      conditionGeneree = tousLesMois;
      _memoriserChoixExceptions([mois]);
      listeGeneree = true;
    });
  }

  /// À appeler dans un setState : garde les choix « exceptions » et calcule
  /// le résumé (effectif, ont payé, pas payé, exonérés, montant différent).
  void _memoriserChoixExceptions(List<String> mois) {
    exoneresGeneres = inclureExoneres;
    montantDifferentGeneres = inclureMontantDifferent;
    resumeGenere = fs.resumeOrdre(
      mois: mois,
      sectionFilter: selectedSection,
      classFilter: selectedClasse,
    );
  }

  /// Mois actuellement choisis dans les filtres.
  List<String> _moisCourants() {
    if (multiMois) return fs.trierMoisScolaires(moisSelection);
    return selectedMois.isEmpty ? <String>[] : <String>[selectedMois];
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
        inclureExoneres: exoneresGeneres,
        inclureMontantDifferent: montantDifferentGeneres,
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
        inclureExoneres: exoneresGeneres,
        inclureMontantDifferent: montantDifferentGeneres,
        avecResume: true,
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

  // ==========================================================================
  // ⚡ NOUVEAU — ÉLÈVES EN EXCEPTION
  // ==========================================================================

  /// Cases à cocher affichées avant « Générer la Liste ».
  Widget _blocExceptions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.blue),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Élèves en exception",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              "Élèves à qui l'école a fixé un montant personnel.",
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: inclureExoneres,
            onChanged: (v) => setState(() {
              inclureExoneres = v ?? false;
              listeGeneree = false;
            }),
            title: const Text("Inclure les élèves exonérés (0 FC)"),
            subtitle: const Text(
              "Ils ne doivent rien pour ce mois. Décoché : ils ne sont pas "
                  "comptés comme « ont payé », mais le résumé les signale.",
              style: TextStyle(fontSize: 11),
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: inclureMontantDifferent,
            onChanged: (v) => setState(() {
              inclureMontantDifferent = v ?? true;
              listeGeneree = false;
            }),
            title: const Text(
                "Inclure les élèves qui paient un montant différent"),
            subtitle: const Text(
              "Ils paient, mais un autre montant que celui de leur classe. "
                  "Ils sont marqués dans la liste.",
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// Repère affiché à côté du nom d'un élève en exception.
  Widget? _badgeException(Eleve e) {
    if (moisGeneres.isEmpty) return null;
    final a = fs.analyserExceptionsEleve(e, moisGeneres);
    String? texte;
    Color couleur = Colors.blue.shade700;
    if (a.totalementExonere) {
      texte = "EXONÉRÉ";
    } else if (a.aMoisExonere && a.aMontantDifferent) {
      texte = "EXCEPTION";
      couleur = Colors.deepPurple;
    } else if (a.aMontantDifferent) {
      texte = "MONTANT DIFFÉRENT";
      couleur = Colors.deepPurple;
    } else if (a.aMoisExonere) {
      texte = "EXO CERTAINS MOIS";
    }
    if (texte == null) return null;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: couleur.withValues(alpha: 0.45)),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: couleur,
        ),
      ),
    );
  }

  Widget _puceChiffre(String libelle, int n, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        "$libelle : $n",
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }

  /// Chiffres clés + explication sur les exceptions (dans le résumé).
  Widget _resumeChiffres(ResumeOrdre r) {
    final t = r.total;
    final String moisTxt =
    r.plusieursMois ? "les mois choisis" : "ce mois";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _puceChiffre("Effectif", t.effectif, Colors.blueGrey),
            _puceChiffre(r.libelleColonnePaye, t.enOrdre, Colors.green.shade700),
            _puceChiffre(
                r.libelleColonneNonPaye, t.pasEnOrdre, Colors.red.shade700),
            _puceChiffre("Exonérés (0 FC)", t.exoneres, Colors.blue.shade700),
            _puceChiffre(
                "Montant différent", t.montantDifferent, Colors.deepPurple),
          ],
        ),
        if (t.exoneres > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              exoneresGeneres
                  ? "• ${t.exoneres} élève(s) exonéré(s) pour $moisTxt : "
                  "ils sont inclus dans la liste (mention EXONÉRÉ)."
                  : "• ${t.exoneres} élève(s) exonéré(s) pour $moisTxt ne "
                  "sont pas dans la liste : ils ne doivent rien payer.",
              style: const TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ),
        if (t.montantDifferent > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              montantDifferentGeneres
                  ? "• ${t.montantDifferent} élève(s) paient un montant "
                  "différent : déjà comptés dans « ${r.libelleColonnePaye} » "
                  "ou « ${r.libelleColonneNonPaye} »."
                  : "• ${t.montantDifferent} élève(s) qui paient un montant "
                  "différent ne sont pas dans la liste (option choisie).",
              style: const TextStyle(fontSize: 12, color: Colors.deepPurple),
            ),
          ),
        if (r.parSection.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text("Voir le détail par section"),
              onPressed: () => _afficherDetailParSection(r),
            ),
          ),
      ],
    );
  }

  void _afficherDetailParSection(ResumeOrdre r) {
    final lignes = [
      ...r.parSection,
      if (r.parSection.length != 1) r.total,
    ];
    DataCell c(String t, {bool gras = false}) => DataCell(Text(t,
        style: TextStyle(
            fontWeight: gras ? FontWeight.bold : FontWeight.normal)));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.plusieursMois
            ? "Détail par section (${r.mois.length} mois)"
            : "Détail par section — ${r.mois.first}"),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              columnSpacing: 18,
              columns: [
                const DataColumn(label: Text("Section")),
                const DataColumn(label: Text("Effectif"), numeric: true),
                DataColumn(label: Text(r.libelleColonnePaye), numeric: true),
                DataColumn(
                    label: Text(r.libelleColonneNonPaye), numeric: true),
                const DataColumn(label: Text("Exonérés"), numeric: true),
                const DataColumn(
                    label: Text("Montant\ndifférent"), numeric: true),
              ],
              rows: lignes.map((s) {
                final bool tot = identical(s, r.total);
                return DataRow(cells: [
                  c(s.section, gras: tot),
                  c('${s.effectif}', gras: tot),
                  c('${s.enOrdre}', gras: tot),
                  c('${s.pasEnOrdre}', gras: tot),
                  c('${s.exoneres}', gras: tot),
                  c('${s.montantDifferent}', gras: tot),
                ]);
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer"),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ⚡ NOUVEAU — AUTRES FRAIS PAYÉS PAR MOIS
  // Comme pour le minerval : on choisit un frais (payé selon les mois) et un
  // mois, puis on obtient la liste des élèves qui ont déjà payé ce mois et
  // de ceux qui ne l'ont pas encore payé (PDF possible). La section et la
  // classe choisies ci-dessus sont reprises.
  // ==========================================================================
  Future<void> _ouvrirAutresFraisParMois() async {
    final fs = widget.fraisScolaires;
    final List<AutreFrais> fraisMois =
    fs.getAutresFrais().where(fs.autreFraisAMois).toList();
    if (fraisMois.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Aucun autre frais ne se paie encore par mois. "
              "Ouvrez « Autres frais » > Tranches / Mois, choisissez "
              "« Selon les mois » et ajoutez les mois."),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    AutreFrais fraisChoisi = fraisMois.first;
    String? moisChoisi;
    String? moisPour(AutreFrais f) {
      final mois = fs.moisDefinisAutreFrais(f);
      if (mois.isEmpty) return null;
      if (selectedMois.isNotEmpty) {
        for (final m in mois) {
          if (FraisScolaires.memeMois(m, selectedMois)) return m;
        }
      }
      return mois.first;
    }

    moisChoisi = moisPour(fraisChoisi);

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final moisDispo = fs.moisDefinisAutreFrais(fraisChoisi);
          return AlertDialog(
            title: const Text("Autres frais — liste par mois"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: fraisChoisi.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Type de frais",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: fraisMois
                      .map((f) =>
                      DropdownMenuItem(value: f.id, child: Text(f.nom)))
                      .toList(),
                  onChanged: (v) => setD(() {
                    fraisChoisi =
                        fraisMois.firstWhere((f) => f.id == v);
                    moisChoisi = moisPour(fraisChoisi);
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('mois_${fraisChoisi.id}'),
                  initialValue: moisChoisi,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Mois",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: moisDispo
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setD(() => moisChoisi = v),
                ),
                const SizedBox(height: 8),
                Text(
                  "Section : ${selectedSection ?? 'toutes'} | Classe : "
                      "${selectedClasse ?? 'toutes'}",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler"),
              ),
              ElevatedButton(
                onPressed: moisChoisi == null
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text("Générer la liste"),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecouvrementAutresFraisScreen(
          fraisScolaires: fs,
          frais: fraisChoisi,
          sectionInitiale: selectedSection,
          classeInitiale: selectedClasse,
          moisInitial: moisChoisi,
        ),
      ),
    );
  }

  /// PDF : liste des élèves en exception, selon le type choisi.
  Future<void> _genererListeExceptions() async {
    if (_generationExceptions) return;
    final List<String> mois = _moisCourants();
    if (mois.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Choisissez au moins un mois."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final toutes = fs.getElevesEnException(
      mois: mois,
      sectionFilter: selectedSection,
      classFilter: selectedClasse,
    );
    int nb(FiltreExceptions f) => toutes.where((a) => a.correspond(f)).length;

    FiltreExceptions filtre = FiltreExceptions.toutes;
    final String moisNom = mois.length == 1
        ? mois.first
        : (mois.length <= 4
        ? mois.map(fs.libelleMoisCourt).join('-')
        : "${mois.length}_mois");
    final controller =
    TextEditingController(text: "Eleves_En_Exception_$moisNom");

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Widget choix(FiltreExceptions f, String titre, String detail) {
            final bool actif = filtre == f;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                actif
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: actif ? Colors.indigo : Colors.grey,
              ),
              onTap: () => setD(() => filtre = f),
              title: Text("$titre (${nb(f)})"),
              subtitle: Text(detail, style: const TextStyle(fontSize: 11)),
            );
          }

          return AlertDialog(
            title: const Text("Liste des élèves en exception"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Mois : ${mois.join(', ')}\n"
                        "Section : ${selectedSection ?? 'Toutes les sections'}\n"
                        "Classe : ${selectedClasse ?? 'Toutes les classes'}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  choix(FiltreExceptions.toutes, "Tous les élèves en exception",
                      "Exonérés et montants différents."),
                  choix(FiltreExceptions.exoneres, "Exonérés (ne paient rien)",
                      "Montant à payer : 0 FC pour au moins un des mois."),
                  choix(
                      FiltreExceptions.montantDifferent,
                      "Paient un montant différent",
                      "Ils paient, mais pas le montant normal de leur classe."),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    decoration:
                    const InputDecoration(labelText: "Nom du fichier"),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Générer le PDF"),
              ),
            ],
          );
        },
      ),
    );

    final String filename = controller.text.trim();
    if (ok != true || filename.isEmpty || !mounted) return;

    setState(() => _generationExceptions = true);
    final res = await fs.generateExceptionsPdf(
      filename: filename,
      mois: mois,
      filtre: filtre,
      sectionFilter: selectedSection,
      classFilter: selectedClasse,
    );
    if (!mounted) return;
    setState(() => _generationExceptions = false);

    final bool succes = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(succes
            ? "✅ Liste des élèves en exception générée (${nb(filtre)} élève(s))."
            : "❌ ${res['error'] ?? 'Erreur inconnue'}"),
        backgroundColor: succes ? Colors.green : Colors.red,
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
    final Color c = d.exonere
        ? Colors.blue.shade700
        : (ok ? Colors.green.shade700 : Colors.red.shade700);
    final String court = fs.libelleMoisCourt(d.mois);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Text(
        d.exonere
            ? "$court EXO"
            : (ok ? "$court ✓" : "$court −${formatMontant(d.reste)}"),
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
            if (_badgeException(e) != null) _badgeException(e)!,
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
            // ⚡ Repère si l'élève est en exception pour ce mois
            // (EXONÉRÉ ou MONTANT DIFFÉRENT).
            if (_badgeException(e) != null) _badgeException(e)!,
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
                    const SizedBox(height: 10),
                    // ⚡ NOUVEAU — élèves en exception
                    _blocExceptions(),
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
            const SizedBox(height: 8),

            // ==================== ⚡ NOUVEAU — ÉLÈVES EN EXCEPTION ====================
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _generationExceptions
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.person_search),
                label: Text(_generationExceptions
                    ? "Génération de la liste..."
                    : "Liste des élèves en exception (PDF)"),
                onPressed:
                _generationExceptions ? null : _genererListeExceptions,
              ),
            ),
            const SizedBox(height: 8),

            // ==================== ⚡ NOUVEAU — AUTRES FRAIS PAR MOIS ====================
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: const Text("Autres frais : élèves en ordre par mois"),
                onPressed: _ouvrirAutresFraisParMois,
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
                    // ⚡ NOUVEAU — chiffres clés et élèves en exception
                    if (resumeGenere != null) _resumeChiffres(resumeGenere!),
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