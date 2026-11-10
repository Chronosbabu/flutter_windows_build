import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/registre_eleves_pdf.dart';
import 'import_eleves_json.dart';

class StudentListScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const StudentListScreen({super.key, required this.fraisScolaires});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  String searchQuery = "";
  String? selectedSectionFilter;
  String? selectedClassFilter;

  bool onlyWithoutInfo = false;

  bool showAdvancedFilters = false;
  String? selectedSexeFilter;
  String? selectedReligionFilter;
  String? selectedProfessionFilter;
  String? selectedProvinceFilter;

  bool promotionMode = false;
  String? targetPromotionYear;
  final Map<String, bool> passToNextYear = {};
  final Map<String, bool> monterClasse = {};

  bool deletionMode = false;

  Uint8List? _schoolLogoBytes;

  @override
  void initState() {
    super.initState();
    _loadSchoolLogo();
  }

  Future<void> _loadSchoolLogo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/school_logo.png');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() => _schoolLogoBytes = bytes);
      }
    } catch (_) {}
  }

  bool _hasExtraInfo(Eleve e) {
    return e.pereNom.trim().isNotEmpty ||
        e.mereNom.trim().isNotEmpty ||
        e.adresse.trim().isNotEmpty ||
        e.dateNaissance.trim().isNotEmpty ||
        e.customFields.values.any((v) => v.trim().isNotEmpty);
  }

  List<Eleve> _baseEleves() {
    final allEleves = widget.fraisScolaires.currentData.eleves;
    final q = searchQuery.toLowerCase();
    return allEleves.where((eleve) {
      final matchesSearch = eleve.nom.toLowerCase().contains(q) ||
          eleve.postNom.toLowerCase().contains(q) ||
          eleve.prenom.toLowerCase().contains(q) ||
          eleve.id.toLowerCase().contains(q);
      final matchesSection =
          selectedSectionFilter == null || eleve.section == selectedSectionFilter;
      final matchesClass =
          selectedClassFilter == null || eleve.classe == selectedClassFilter;
      final matchesInfo = !onlyWithoutInfo || !_hasExtraInfo(eleve);
      return matchesSearch && matchesSection && matchesClass && matchesInfo;
    }).toList();
  }

  List<Eleve> _applyAdvancedFilters(List<Eleve> base) {
    return base
        .where((e) => RegistreEleves.correspond(
      e,
      filtreSexe: selectedSexeFilter,
      filtreReligion: selectedReligionFilter,
      filtreProfession: selectedProfessionFilter,
      filtreProvince: selectedProvinceFilter,
    ))
        .toList();
  }

  List<Eleve> _filteredEleves() => _applyAdvancedFilters(_baseEleves());

  int get _activeAdvancedCount {
    int n = 0;
    if (selectedSexeFilter != null) n++;
    if (selectedReligionFilter != null) n++;
    if (selectedProfessionFilter != null) n++;
    if (selectedProvinceFilter != null) n++;
    return n;
  }

  void _resetAdvancedFilters() {
    setState(() {
      selectedSexeFilter = null;
      selectedReligionFilter = null;
      selectedProfessionFilter = null;
      selectedProvinceFilter = null;
    });
  }

  String _libelleSexeFiltre(String cle) {
    if (cle == 'M') return 'Garçons';
    if (cle == 'F') return 'Filles';
    return 'Sexe non précisé';
  }

  String _descriptionFiltres() {
    final all = widget.fraisScolaires.currentData.eleves;
    final parts = <String>[];
    if (selectedSectionFilter != null) {
      parts.add("Section : $selectedSectionFilter");
    }
    if (selectedClassFilter != null) {
      parts.add("Classe : $selectedClassFilter");
    }
    if (selectedSexeFilter != null) {
      parts.add("Sexe : ${_libelleSexeFiltre(selectedSexeFilter!)}");
    }
    if (selectedReligionFilter != null) {
      parts.add(
          "Religion : ${RegistreEleves.libelleDeCle(all, RegistreEleves.lireReligion, selectedReligionFilter!)}");
    }
    if (selectedProfessionFilter != null) {
      parts.add(
          "Profession : ${RegistreEleves.libelleDeCle(all, RegistreEleves.lireProfession, selectedProfessionFilter!)}");
    }
    if (selectedProvinceFilter != null) {
      parts.add(
          "Province : ${RegistreEleves.libelleDeCle(all, RegistreEleves.lireProvince, selectedProvinceFilter!)}");
    }
    if (searchQuery.trim().isNotEmpty) {
      parts.add("Recherche : ${searchQuery.trim()}");
    }
    if (onlyWithoutInfo) {
      parts.add("Élèves sans informations");
    }
    return parts.join(" | ");
  }

  List<DropdownMenuItem<String>> _itemsFromStats(
      List<StatLigne> options,
      String? selected,
      String Function(Eleve) lire,
      ) {
    final items = options
        .map((o) => DropdownMenuItem<String>(
      value: o.cle,
      child: Text(
        "${o.libelle} (${o.nombre})",
        overflow: TextOverflow.ellipsis,
      ),
    ))
        .toList();
    if (selected != null && !options.any((o) => o.cle == selected)) {
      items.add(DropdownMenuItem<String>(
        value: selected,
        child: Text(
          "${RegistreEleves.libelleDeCle(widget.fraisScolaires.currentData.eleves, lire, selected)} (0)",
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }
    return items;
  }

  Widget _buildAdvancedDropdown({
    required String hint,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButton<String>(
      isExpanded: true,
      hint: Text(hint),
      value: value,
      items: [
        DropdownMenuItem<String>(value: null, child: Text(hint)),
        ...items,
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseEleves = _baseEleves();
    final filteredEleves = _applyAdvancedFilters(baseEleves);
    final sexesFiltres = RegistreEleves.compterSexes(filteredEleves);
    final sexesBase = RegistreEleves.compterSexes(baseEleves);

    final classOptions = selectedSectionFilter != null
        ? List<String>.from(
        widget.fraisScolaires.getAllDisplayClassesForSection(selectedSectionFilter!))
        : List<String>.from(widget.fraisScolaires.getAllDisplayClasses());
    if (selectedClassFilter != null && !classOptions.contains(selectedClassFilter)) {
      classOptions.add(selectedClassFilter!);
    }

    final religionOptions =
    RegistreEleves.statistiques(baseEleves, RegistreEleves.lireReligion);
    final professionOptions =
    RegistreEleves.statistiques(baseEleves, RegistreEleves.lireProfession);
    final provinceOptions =
    RegistreEleves.statistiques(baseEleves, RegistreEleves.lireProvince);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          promotionMode
              ? "Passation vers $targetPromotionYear"
              : deletionMode
              ? "Sélectionner un élève à supprimer"
              : "Registre des Élèves",
        ),
        actions: _buildAppBarActions(),
      ),
      floatingActionButton: (promotionMode || deletionMode)
          ? null
          : FloatingActionButton(
        onPressed: () => _downloadCurrentListAsPdf(),
        tooltip: "Télécharger PDF",
        child: const Icon(Icons.download),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (promotionMode) _buildPromotionBanner(),
            if (deletionMode) _buildDeletionBanner(),
            TextField(
              decoration: const InputDecoration(
                labelText: "Rechercher par nom, post-nom, ID...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => searchQuery = value);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Toutes Sections"),
                    value: selectedSectionFilter,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text("Toutes Sections")),
                      ...widget.fraisScolaires.config.sections
                          .map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        selectedSectionFilter = val;
                        final validClasses = val != null
                            ? widget.fraisScolaires
                            .getAllDisplayClassesForSection(val)
                            : widget.fraisScolaires.getAllDisplayClasses();
                        if (selectedClassFilter != null &&
                            !validClasses.contains(selectedClassFilter)) {
                          selectedClassFilter = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Toutes Classes"),
                    value: selectedClassFilter,
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text("Toutes Classes")),
                      ...classOptions
                          .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (val) =>
                        setState(() => selectedClassFilter = val),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: Icon(showAdvancedFilters
                    ? Icons.expand_less
                    : Icons.expand_more),
                label: Text(
                  _activeAdvancedCount > 0
                      ? "Filtres avancés ($_activeAdvancedCount actif(s))"
                      : "Filtres avancés (sexe, religion, profession, province)",
                ),
                onPressed: () =>
                    setState(() => showAdvancedFilters = !showAdvancedFilters),
              ),
            ),
            if (showAdvancedFilters) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildAdvancedDropdown(
                      hint: "Tous les sexes",
                      value: selectedSexeFilter,
                      items: [
                        DropdownMenuItem<String>(
                            value: 'M',
                            child: Text("Garçons (${sexesBase['M']})")),
                        DropdownMenuItem<String>(
                            value: 'F',
                            child: Text("Filles (${sexesBase['F']})")),
                        DropdownMenuItem<String>(
                            value: RegistreEleves.sexeNonPrecise,
                            child: Text(
                                "Sexe non précisé (${sexesBase['?']})")),
                      ],
                      onChanged: (v) =>
                          setState(() => selectedSexeFilter = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildAdvancedDropdown(
                      hint: "Toutes religions",
                      value: selectedReligionFilter,
                      items: _itemsFromStats(religionOptions,
                          selectedReligionFilter, RegistreEleves.lireReligion),
                      onChanged: (v) =>
                          setState(() => selectedReligionFilter = v),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildAdvancedDropdown(
                      hint: "Toutes professions",
                      value: selectedProfessionFilter,
                      items: _itemsFromStats(
                          professionOptions,
                          selectedProfessionFilter,
                          RegistreEleves.lireProfession),
                      onChanged: (v) =>
                          setState(() => selectedProfessionFilter = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildAdvancedDropdown(
                      hint: "Toutes provinces",
                      value: selectedProvinceFilter,
                      items: _itemsFromStats(provinceOptions,
                          selectedProvinceFilter, RegistreEleves.lireProvince),
                      onChanged: (v) =>
                          setState(() => selectedProvinceFilter = v),
                    ),
                  ),
                ],
              ),
              if (_activeAdvancedCount > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    label: const Text("Réinitialiser les filtres avancés"),
                    onPressed: _resetAdvancedFilters,
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Total : ${filteredEleves.length} élève(s)",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        "Garçons : ${sexesFiltres['M']}  |  Filles : ${sexesFiltres['F']}"
                            "${(sexesFiltres['?'] ?? 0) > 0 ? "  |  Non précisé : ${sexesFiltres['?']}" : ""}",
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                if (!promotionMode && !deletionMode)
                  FilterChip(
                    avatar: const Icon(Icons.person_off_outlined, size: 18),
                    label: const Text("Sans infos"),
                    selected: onlyWithoutInfo,
                    onSelected: (v) => setState(() => onlyWithoutInfo = v),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredEleves.isEmpty
                  ? const Center(child: Text("Aucun élève trouvé"))
                  : ListView.builder(
                itemCount: filteredEleves.length,
                itemBuilder: (context, index) {
                  final e = filteredEleves[index];
                  if (promotionMode) return _buildPromotionCard(e);
                  if (deletionMode) return _buildDeletionCard(e);
                  return _buildNormalCard(e);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (promotionMode) {
      return [
        IconButton(
          icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
          tooltip: "Valider la passation",
          onPressed: _validatePromotion,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: "Annuler la passation",
          onPressed: _cancelPromotionMode,
        ),
      ];
    }

    if (deletionMode) {
      return [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: "Quitter le mode suppression",
          onPressed: _cancelDeletionMode,
        ),
      ];
    }

    return [
      IconButton(
        icon: const Icon(Icons.bar_chart, color: Colors.lightBlueAccent),
        tooltip: "Statistiques et comptage (sexe, religion, profession...)",
        onPressed: _openStatistics,
      ),
      IconButton(
        icon: const Icon(Icons.table_view, color: Colors.orangeAccent),
        tooltip: "Générer le registre en PDF (mise en page du registre)",
        onPressed: _openExportDialog,
      ),
      IconButton(
        icon: const Icon(Icons.flash_on, color: Colors.amber),
        tooltip: "Saisie rapide des informations des élèves",
        onPressed: _openFastEntry,
      ),
      IconButton(
        icon: const Icon(Icons.upload_file, color: Colors.lightGreenAccent),
        tooltip: "Importer des informations depuis un fichier JSON",
        onPressed: _importFromJsonFile,
      ),
      IconButton(
        icon: const Icon(Icons.move_up),
        tooltip: "Passation vers la nouvelle année",
        onPressed: _startPromotionMode,
      ),
      IconButton(
        icon: const Icon(Icons.delete_forever, color: Colors.red),
        tooltip: "Supprimer un élève",
        onPressed: _startDeletionMode,
      ),
      IconButton(
        icon: const Icon(Icons.history),
        tooltip: "Élèves Supprimés",
        onPressed: _openElevesSupprimesScreen,
      ),
      IconButton(
        icon: const Icon(Icons.picture_as_pdf),
        tooltip: "Télécharger la liste en PDF",
        onPressed: () => _downloadCurrentListAsPdf(),
      ),
    ];
  }

  Widget _statRow(String label, int n, int total, {VoidCallback? onTap}) {
    final pct = total <= 0 ? "0 %" : "${(n * 100 / total).toStringAsFixed(1)} %";
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13.5)),
            ),
            Text(
              "$n",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 58,
              child: Text(
                pct,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _statTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo),
      ),
    );
  }

  void _openStatistics() {
    final eleves = _filteredEleves();
    final total = eleves.length;
    final sexes = RegistreEleves.compterSexes(eleves);
    final religions =
    RegistreEleves.statistiques(eleves, RegistreEleves.lireReligion);
    final professions =
    RegistreEleves.statistiques(eleves, RegistreEleves.lireProfession);
    final provinces =
    RegistreEleves.statistiques(eleves, RegistreEleves.lireProvince);
    final groupes = RegistreEleves.grouper(widget.fraisScolaires, eleves);
    final description = _descriptionFiltres();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Statistiques et comptage"),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description.isEmpty
                      ? "Tous les élèves affichés"
                      : "Filtres : $description",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Appuyez sur une ligne pour filtrer la liste.",
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                _statTitle("Effectif total : $total élève(s)"),
                _statRow("Garçons", sexes['M'] ?? 0, total, onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    selectedSexeFilter = 'M';
                    showAdvancedFilters = true;
                  });
                }),
                _statRow("Filles", sexes['F'] ?? 0, total, onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    selectedSexeFilter = 'F';
                    showAdvancedFilters = true;
                  });
                }),
                if ((sexes['?'] ?? 0) > 0)
                  _statRow("Sexe non précisé", sexes['?'] ?? 0, total,
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          selectedSexeFilter = RegistreEleves.sexeNonPrecise;
                          showAdvancedFilters = true;
                        });
                      }),
                _statTitle("Par classe"),
                ...groupes.map((g) => _statRow(
                    "${g.section} — ${g.classe}", g.eleves.length, total)),
                _statTitle("Par religion"),
                ...religions.map((l) => _statRow(l.libelle, l.nombre, total,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        selectedReligionFilter = l.cle;
                        showAdvancedFilters = true;
                      });
                    })),
                _statTitle("Par profession des parents"),
                ...professions.map((l) => _statRow(l.libelle, l.nombre, total,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        selectedProfessionFilter = l.cle;
                        showAdvancedFilters = true;
                      });
                    })),
                _statTitle("Par province d'origine"),
                ...provinces.map((l) => _statRow(l.libelle, l.nombre, total,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        selectedProvinceFilter = l.cle;
                        showAdvancedFilters = true;
                      });
                    })),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.table_view),
            label: const Text("Générer le PDF"),
            onPressed: () {
              Navigator.pop(ctx);
              _openExportDialog();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openExportDialog() async {
    bool toutEcole = false;
    bool unePageParClasse = true;
    bool avecStats = true;
    final filtrees = _filteredEleves();
    final toute = widget.fraisScolaires.currentData.eleves;
    final description = _descriptionFiltres();

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text("Générer le registre en PDF"),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: false,
                    groupValue: toutEcole,
                    onChanged: (v) => setD(() => toutEcole = v ?? false),
                    title: Text(
                        "Selon les filtres actuels (${filtrees.length} élève(s))",
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                      description.isEmpty
                          ? "Aucun filtre : tous les élèves affichés"
                          : description,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: true,
                    groupValue: toutEcole,
                    onChanged: (v) => setD(() => toutEcole = v ?? true),
                    title: Text("Toute l'école (${toute.length} élève(s))",
                        style: const TextStyle(fontSize: 13.5)),
                    subtitle: const Text(
                      "Ignore tous les filtres et la recherche",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: unePageParClasse,
                    onChanged: (v) =>
                        setD(() => unePageParClasse = v ?? true),
                    title: const Text("Une classe par page",
                        style: TextStyle(fontSize: 13)),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: avecStats,
                    onChanged: (v) => setD(() => avecStats = v ?? true),
                    title: const Text(
                        "Ajouter les statistiques à la fin (sexe, classe, religion, profession, province)",
                        style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Colonnes : noms, post-noms et prénoms, sexe, noms des parents, "
                        "date de naissance, province d'origine, école de provenance, "
                        "numéro permanent, confession religieuse, profession du parent, "
                        "adresse, date d'inscription, numéro de téléphone.",
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text("Générer le PDF"),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final liste = toutEcole ? List<Eleve>.from(toute) : _filteredEleves();
    if (liste.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Aucun élève ne correspond aux filtres choisis.")),
      );
      return;
    }

    final String filename = toutEcole
        ? "Registre_Eleves_Toute_Ecole"
        : "Registre_Eleves_${selectedSectionFilter ?? 'Toutes_Sections'}_${selectedClassFilter ?? 'Toutes_Classes'}";

    final result = await RegistreEleves.genererPdf(
      fs: widget.fraisScolaires,
      eleves: liste,
      filename: filename,
      description: toutEcole ? "Toute l'école" : description,
      unePageParClasse: unePageParClasse,
      inclureStatistiques: avecStats,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? "✅ Registre PDF généré (${liste.length} élève(s))."
              : "Erreur : ${result['error']}",
        ),
        backgroundColor: result['success'] == true ? null : Colors.red,
      ),
    );
  }

  Future<void> _importFromJsonFile() async {
    await StudentJsonImporter.run(context, widget.fraisScolaires);
    if (mounted) setState(() {});
  }

  Widget _buildNormalCard(Eleve e) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: () => _showStudentCard(e),
        leading: CircleAvatar(
          backgroundImage: (e.photoBase64 != null && e.photoBase64!.isNotEmpty)
              ? MemoryImage(base64Decode(e.photoBase64!))
              : null,
          child: (e.photoBase64 == null || e.photoBase64!.isEmpty)
              ? Text(
            e.id.isNotEmpty ? e.id.substring(0, 2) : "?",
            style: const TextStyle(fontWeight: FontWeight.bold),
          )
              : null,
        ),
        title: Text("${e.nom} ${e.postNom} ${e.prenom}"),
        subtitle: Text("${e.section} - ${e.classe}"),
        trailing: Text(
          e.id,
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: Colors.indigo),
        ),
      ),
    );
  }

  void _showStudentCard(Eleve eleve) {
    final list = _filteredEleves();
    int idx = list.indexWhere((x) => x.id == eleve.id);
    if (idx < 0) {
      idx = 0;
    }
    _openCardDialog(list, idx, startEditing: false);
  }

  void _openFastEntry() {
    final list = _filteredEleves();
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucun élève dans la liste affichée.")),
      );
      return;
    }
    _openCardDialog(list, 0, startEditing: true);
  }

  void _openCardDialog(List<Eleve> list, int index,
      {required bool startEditing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StudentCardDialog(
        eleves: list,
        startIndex: index,
        startEditing: startEditing,
        fraisScolaires: widget.fraisScolaires,
        schoolLogoBytes: _schoolLogoBytes,
        onSaved: () {
          if (mounted) setState(() {});
        },
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openElevesSupprimesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ElevesSupprimesScreen(fraisScolaires: widget.fraisScolaires),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _buildDeletionBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Utilisez la recherche ou les filtres ci-dessous pour trouver "
                  "l'élève à supprimer, puis appuyez sur la corbeille 🗑 à côté "
                  "de son nom. Le mot de passe administrateur sera demandé.",
              style: TextStyle(fontSize: 12.5, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeletionCard(Eleve e) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.shade50,
          backgroundImage: (e.photoBase64 != null && e.photoBase64!.isNotEmpty)
              ? MemoryImage(base64Decode(e.photoBase64!))
              : null,
          child: (e.photoBase64 == null || e.photoBase64!.isEmpty)
              ? Text(
            e.id.isNotEmpty ? e.id.substring(0, 2) : "?",
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.red),
          )
              : null,
        ),
        title: Text("${e.nom} ${e.postNom} ${e.prenom}"),
        subtitle: Text("${e.section} - ${e.classe}  |  ID : ${e.id}"),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red, size: 28),
          tooltip: "Supprimer cet élève",
          onPressed: () => _requestDeleteStudent(e),
        ),
      ),
    );
  }

  void _startDeletionMode() {
    setState(() {
      deletionMode = true;
      searchQuery = "";
    });
  }

  void _cancelDeletionMode() {
    setState(() {
      deletionMode = false;
      searchQuery = "";
    });
  }

  Future<void> _requestDeleteStudent(Eleve eleve) async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Aucun mot de passe administrateur défini. "
                  "Définissez-en un dans les Paramètres avant de supprimer un élève."),
        ),
      );
      return;
    }

    final passController = TextEditingController();
    final bool? passwordOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vérification Administrateur"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Entrez le mot de passe administrateur pour continuer.",
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passController,
              obscureText: true,
              decoration:
              const InputDecoration(labelText: "Mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (passController.text.trim() == appState.backupPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Mot de passe incorrect.")),
                );
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );

    if (passwordOk != true) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text("Suppression de l'élève",
                style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Vous êtes sur le point de retirer du registre actif l'élève "
                  "suivant de l'année scolaire en cours :",
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${eleve.nom} ${eleve.postNom} ${eleve.prenom}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text("ID : ${eleve.id}"),
                  Text(
                      "Classe : ${eleve.classe}  |  Section : ${eleve.section}"),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "ℹ️  L'élève n'apparaîtra plus dans ce registre. Cependant, "
                  "l'argent déjà payé reste comptabilisé dans la caisse de "
                  "l'école, et son historique complet (paiements, "
                  "informations) reste consultable dans \"Élèves "
                  "Supprimés\" tant qu'on ne le supprime pas définitivement "
                  "depuis cette page. Si vous voulez aussi retirer son "
                  "argent de la caisse, vous pourrez annuler ses paiements "
                  "depuis \"Élèves Supprimés\".\n\n"
                  "Après cette action, pensez à sauvegarder sur le serveur "
                  "(Paramètres → Sauvegarder sur le Serveur) pour que la "
                  "modification soit prise en compte sur tous les appareils.",
              style: TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.fraisScolaires.archiverEtSupprimerEleve(
      eleve,
      motif: 'Suppression manuelle depuis le registre des élèves',
    );
    if (mounted) setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ ${eleve.nom} ${eleve.postNom} ${eleve.prenom} a été retiré(e) "
                "du registre actif (visible dans \"Élèves Supprimés\"). "
                "Pensez à sauvegarder sur le serveur dans Paramètres.",
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Widget _buildPromotionBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Passation vers \"$targetPromotionYear\"",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            "Toutes les cases sont cochées par défaut. Décochez \"Passe\" pour "
                "un abandon (l'élève ne sera pas transféré). Décochez \"Monte\" "
                "pour un redoublant (il garde la même classe). Appuyez ensuite "
                "sur ✅ en haut pour valider.",
            style: TextStyle(fontSize: 12.5, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.check_box, size: 18),
                label: const Text("Tous passent"),
                onPressed: () => _bulkSetPass(true),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.check_box_outline_blank, size: 18),
                label: const Text("Aucun ne passe"),
                onPressed: () => _bulkSetPass(false),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_upward, size: 18),
                label: const Text("Tous montent"),
                onPressed: () => _bulkSetMonter(true),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.horizontal_rule, size: 18),
                label: const Text("Aucun ne monte"),
                onPressed: () => _bulkSetMonter(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromotionCard(Eleve e) {
    final bool passe = passToNextYear[e.id] ?? true;
    final bool monte = monterClasse[e.id] ?? true;
    final String classeApercu = passe
        ? (monte ? widget.fraisScolaires.computePromotedClasse(e) : e.classe)
        : "—";

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            CircleAvatar(
              child: Text(
                e.id.isNotEmpty ? e.id.substring(0, 2) : "?",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${e.nom} ${e.postNom} ${e.prenom}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    "${e.section} - ${e.classe}  →  $classeApercu",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: passe ? Colors.indigo : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Passe", style: TextStyle(fontSize: 11)),
                    Checkbox(
                      value: passe,
                      onChanged: (v) => setState(() {
                        passToNextYear[e.id] = v ?? true;
                      }),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Monte", style: TextStyle(fontSize: 11)),
                    Checkbox(
                      value: monte,
                      onChanged: !passe
                          ? null
                          : (v) => setState(() {
                        monterClasse[e.id] = v ?? true;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _bulkSetPass(bool value) {
    setState(() {
      for (var e in widget.fraisScolaires.currentData.eleves) {
        passToNextYear[e.id] = value;
      }
    });
  }

  void _bulkSetMonter(bool value) {
    setState(() {
      for (var e in widget.fraisScolaires.currentData.eleves) {
        monterClasse[e.id] = value;
      }
    });
  }

  void _startPromotionMode() async {
    final years = widget.fraisScolaires.history.keys
        .where((y) => y != widget.fraisScolaires.currentYear)
        .toList();

    String? chosenYear;
    final newYearController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Passation vers la nouvelle année"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Choisissez une année scolaire déjà créée dans les "
                      "Paramètres, ou tapez directement le nom d'une "
                      "nouvelle année à créer.",
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                if (years.isNotEmpty) ...[
                  DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Choisir une année existante"),
                    value: chosenYear,
                    items: years
                        .map((y) =>
                        DropdownMenuItem(value: y, child: Text(y)))
                        .toList(),
                    onChanged: (v) => setStateDialog(() {
                      chosenYear = v;
                      newYearController.clear();
                    }),
                  ),
                  const SizedBox(height: 14),
                  const Text("— ou —", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: newYearController,
                  decoration: const InputDecoration(
                    labelText: "Nouvelle année (ex: 2026-2027)",
                  ),
                  onChanged: (_) => setStateDialog(() => chosenYear = null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler")),
            ElevatedButton(
              onPressed: () {
                final value = chosenYear ?? newYearController.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(ctx, value);
              },
              child: const Text("Continuer"),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty) return;

    setState(() {
      promotionMode = true;
      targetPromotionYear = result;
      passToNextYear.clear();
      monterClasse.clear();
      for (var e in widget.fraisScolaires.currentData.eleves) {
        passToNextYear[e.id] = true;
        monterClasse[e.id] = true;
      }
    });
  }

  void _cancelPromotionMode() {
    setState(() {
      promotionMode = false;
      targetPromotionYear = null;
      passToNextYear.clear();
      monterClasse.clear();
    });
  }

  void _validatePromotion() async {
    if (targetPromotionYear == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer la passation"),
        content: Text(
          "Les élèves cochés \"Passe\" vont être copiés dans l'année "
              "\"$targetPromotionYear\", avec leur classe supérieure si "
              "\"Monte\" est cochée. Cette action ne supprime ni ne modifie "
              "rien dans l'année actuelle (${widget.fraisScolaires.currentYear}). "
              "Voulez-vous continuer ?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Confirmer")),
        ],
      ),
    );
    if (confirm != true) return;

    final result = await widget.fraisScolaires.promoteStudents(
      studentsToProcess: widget.fraisScolaires.currentData.eleves,
      passToNextYear: passToNextYear,
      monterClasse: monterClasse,
      targetYear: targetPromotionYear!,
    );

    if (mounted) {
      final year = targetPromotionYear;
      setState(() {
        promotionMode = false;
        targetPromotionYear = null;
        passToNextYear.clear();
        monterClasse.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ ${result['promoted']} élève(s) envoyé(s) vers \"$year\" "
                "(${result['redoublants']} sans changement de classe), "
                "${result['abandoned']} non transféré(s) (abandons). "
                "Pensez à sauvegarder sur le serveur dans Paramètres.",
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _downloadCurrentListAsPdf() async {
    final String sectionText = selectedSectionFilter ?? "Toutes_Sections";
    final String classText = selectedClassFilter ?? "Toutes_Classes";
    final filename =
        "Liste_Eleves_${sectionText}_${classText}_${DateTime.now().toString().split(' ')[0]}";

    await widget.fraisScolaires.generatePdf(
      filename: filename,
      reportType: "student_list",
      sectionFilter: selectedSectionFilter,
      classFilter: selectedClassFilter,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("✅ Liste des élèves téléchargée en PDF")),
      );
    }
  }
}

class _DateSlashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsAll = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final digits =
    digitsAll.length > 8 ? digitsAll.substring(0, 8) : digitsAll;
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _StudentCardDialog extends StatefulWidget {
  final List<Eleve> eleves;
  final int startIndex;
  final bool startEditing;
  final FraisScolaires fraisScolaires;
  final Uint8List? schoolLogoBytes;
  final VoidCallback onSaved;

  const _StudentCardDialog({
    required this.eleves,
    required this.startIndex,
    required this.startEditing,
    required this.fraisScolaires,
    required this.schoolLogoBytes,
    required this.onSaved,
  });

  @override
  State<_StudentCardDialog> createState() => _StudentCardDialogState();
}

class _StudentCardDialogState extends State<_StudentCardDialog> {
  late int index;
  late bool editing;
  bool photoChanged = false;
  int savedCount = 0;
  String? statusMessage;

  final pereCtrl = TextEditingController();
  final mereCtrl = TextEditingController();
  final adresseCtrl = TextEditingController();
  final dateCtrl = TextEditingController();
  final pereFocus = FocusNode();
  final mereFocus = FocusNode();
  final adresseFocus = FocusNode();
  final dateFocus = FocusNode();

  final List<String> _questions = [];
  final Map<String, TextEditingController> _qCtrl = {};
  final Map<String, FocusNode> _qFocus = {};

  Uint8List? photoBytes;

  Timer? _saveTimer;
  bool _dirty = false;
  bool _writing = false;

  Eleve get eleve => widget.eleves[index];

  @override
  void initState() {
    super.initState();
    index = widget.startIndex;
    editing = widget.startEditing;
    for (final q in widget.fraisScolaires.config.customFieldQuestions) {
      final t = q.trim();
      if (t.isEmpty) continue;
      if (_indexOfQuestion(t) == -1) {
        _questions.add(t);
        _ensureQuestionControllers(t);
      }
    }
    _loadStudent();
    if (editing) _focusFirst();
  }

  int _indexOfQuestion(String q) {
    final low = q.trim().toLowerCase();
    return _questions.indexWhere((x) => x.trim().toLowerCase() == low);
  }

  void _ensureQuestionControllers(String q) {
    _qCtrl.putIfAbsent(q, () => TextEditingController());
    _qFocus.putIfAbsent(q, () => FocusNode());
  }

  void _loadStudent() {
    final e = eleve;
    pereCtrl.text = e.pereNom;
    mereCtrl.text = e.mereNom;
    adresseCtrl.text = e.adresse;
    dateCtrl.text = e.dateNaissance;
    photoBytes = (e.photoBase64 != null && e.photoBase64!.isNotEmpty)
        ? base64Decode(e.photoBase64!)
        : null;
    photoChanged = false;

    for (final key in e.customFields.keys) {
      final k = key.trim();
      if (k.isEmpty) continue;
      if (_indexOfQuestion(k) == -1) {
        _questions.add(k);
        _ensureQuestionControllers(k);
        widget.fraisScolaires.registerCustomFieldQuestion(k);
      }
    }

    for (final q in _questions) {
      String value = '';
      e.customFields.forEach((k, v) {
        if (k.trim().toLowerCase() == q.trim().toLowerCase()) value = v;
      });
      _qCtrl[q]!.text = value;
    }
  }

  List<FocusNode> _orderedNodes() => [
    ..._questions.map((q) => _qFocus[q]!),
    pereFocus,
    mereFocus,
    adresseFocus,
    dateFocus,
  ];

  void _focusFirst() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editing) {
        _orderedNodes().first.requestFocus();
      }
    });
  }

  void _next(FocusNode current) {
    final nodes = _orderedNodes();
    final i = nodes.indexOf(current);
    if (i >= 0 && i < nodes.length - 1) {
      nodes[i + 1].requestFocus();
    } else {
      _saveAndNext();
    }
  }

  DateTime? _parseDateStrict(String s) {
    final parts = s.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (parts[2].length != 4) return null;
    if (year < 1950 || year > DateTime.now().year) return null;
    final d = DateTime(year, month, day);
    if (d.day != day || d.month != month || d.year != year) return null;
    return d;
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = _parseDateStrict(dateCtrl.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 10),
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => dateCtrl.text = _formatDate(picked));
    }
    dateFocus.requestFocus();
  }

  Future<void> _pickPhoto() async {
    const typeGroup = XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      photoBytes = bytes;
      photoChanged = true;
    });
  }

  Future<void> _addCustomField() async {
    final questionController = TextEditingController();
    final question = await showDialog<String>(
      context: context,
      builder: (ctx2) => AlertDialog(
        title: const Text("Nouvelle Question Personnalisée"),
        content: TextField(
          controller: questionController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: "Ex: Numéro de téléphone du parent",
            helperText:
            "Elle sera ajoutée pour tous les élèves, restera en mémoire et "
                "passera avant les champs de base.",
          ),
          onSubmitted: (v) {
            final q = v.trim();
            if (q.isNotEmpty) Navigator.pop(ctx2, q);
          },
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
    if (question == null || question.trim().isEmpty) return;
    final q = question.trim();

    final existing = _indexOfQuestion(q);
    if (existing != -1) {
      _qFocus[_questions[existing]]?.requestFocus();
      return;
    }

    await widget.fraisScolaires.registerCustomFieldQuestion(q);
    if (!mounted) return;
    setState(() {
      _questions.add(q);
      _ensureQuestionControllers(q);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _qFocus[q]?.requestFocus();
    });
  }

  Future<void> _deleteQuestion(String q) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text("Supprimer cette question",
                  style: TextStyle(color: Colors.red, fontSize: 17)),
            ),
          ],
        ),
        content: Text(
          "Question : \"$q\"\n\n"
              "Elle sera supprimée pour TOUS les élèves de l'école, et les "
              "réponses déjà saisies pour cette question seront effacées. "
              "Cette action est définitive.\n\n"
              "Pensez ensuite à sauvegarder sur le serveur.",
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final fs = widget.fraisScolaires;
    final low = q.trim().toLowerCase();

    fs.config.customFieldQuestions
        .removeWhere((x) => x.trim().toLowerCase() == low);

    void clean(Iterable<Eleve> list) {
      for (final e in list) {
        e.customFields.removeWhere((k, v) => k.trim().toLowerCase() == low);
      }
    }

    clean(fs.currentData.eleves);
    for (final y in fs.history.values) {
      clean(y.eleves);
    }
    clean(fs.elevesSupprimesData.eleves);

    final ctrl = _qCtrl.remove(q);
    final foc = _qFocus.remove(q);
    setState(() {
      _questions.removeWhere((x) => x.trim().toLowerCase() == low);
      statusMessage = "Question supprimée";
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl?.dispose();
      foc?.dispose();
    });

    widget.onSaved();
    _scheduleSave();
    _focusFirst();
  }

  void _applyToEleve(String dateOut) {
    final e = eleve;
    e.pereNom = pereCtrl.text.trim();
    e.mereNom = mereCtrl.text.trim();
    e.adresse = adresseCtrl.text.trim();
    e.dateNaissance = dateOut;
    if (photoChanged) {
      e.photoBase64 = photoBytes != null ? base64Encode(photoBytes!) : null;
    }
    final Map<String, String> newCustom = {};
    for (final q in _questions) {
      final v = _qCtrl[q]!.text.trim();
      if (v.isNotEmpty) newCustom[q] = v;
    }
    e.customFields = newCustom;
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1000), () {
      _flushNow();
    });
  }

  Future<void> _flushNow() async {
    _saveTimer?.cancel();
    while (_dirty) {
      if (_writing) {
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }
      _dirty = false;
      _writing = true;
      try {
        await widget.fraisScolaires.saveData();
      } finally {
        _writing = false;
      }
    }
  }

  Future<void> _saveAndNext() async {
    if (!editing) return;
    final dateText = dateCtrl.text.trim();
    String dateOut = '';
    if (dateText.isNotEmpty) {
      final d = _parseDateStrict(dateText);
      if (d == null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Date de naissance invalide (format jj/mm/aaaa)."),
            backgroundColor: Colors.red,
          ),
        );
        dateFocus.requestFocus();
        return;
      }
      dateOut = _formatDate(d);
    }

    final nomComplet = "${eleve.nom} ${eleve.postNom}";
    _applyToEleve(dateOut);
    savedCount++;
    widget.onSaved();
    _scheduleSave();

    if (index < widget.eleves.length - 1) {
      setState(() {
        statusMessage = "✓ $nomComplet enregistré";
        index++;
        _loadStudent();
      });
      _focusFirst();
    } else {
      final messenger = ScaffoldMessenger.of(context);
      await _flushNow();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              "✅ Fin de la liste. $savedCount élève(s) enregistré(s). "
                  "Pensez à sauvegarder sur le serveur."),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _skip() {
    if (index < widget.eleves.length - 1) {
      setState(() {
        statusMessage = null;
        index++;
        _loadStudent();
      });
      _focusFirst();
    }
  }

  void _go(int delta) {
    final n = index + delta;
    if (n < 0 || n >= widget.eleves.length) return;
    setState(() {
      statusMessage = null;
      index = n;
      _loadStudent();
    });
  }

  Future<void> _close() async {
    await _flushNow();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty && !_writing) {
      _dirty = false;
      widget.fraisScolaires.saveData();
    }
    pereCtrl.dispose();
    mereCtrl.dispose();
    adresseCtrl.dispose();
    dateCtrl.dispose();
    pereFocus.dispose();
    mereFocus.dispose();
    adresseFocus.dispose();
    dateFocus.dispose();
    for (final c in _qCtrl.values) {
      c.dispose();
    }
    for (final f in _qFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Widget _infoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editField({
    required TextEditingController controller,
    required FocusNode focus,
    required String label,
    TextCapitalization capitalization = TextCapitalization.sentences,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? hint,
    Widget? suffix,
    VoidCallback? onDelete,
  }) {
    final Widget? suffixWidget = onDelete != null
        ? IconButton(
      icon: const Icon(Icons.close, color: Colors.red, size: 20),
      tooltip: "Supprimer cette question",
      onPressed: onDelete,
    )
        : suffix;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        focusNode: focus,
        textInputAction: TextInputAction.next,
        textCapitalization: capitalization,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        onSubmitted: (_) => _next(focus),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffixWidget,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = eleve;
    final schoolName = widget.fraisScolaires.config.schoolName;
    final total = widget.eleves.length;

    final bool hasAnyExtraInfo = e.pereNom.isNotEmpty ||
        e.mereNom.isNotEmpty ||
        e.adresse.isNotEmpty ||
        e.dateNaissance.isNotEmpty ||
        e.customFields.values.any((v) => v.trim().isNotEmpty);

    final bool isLast = index >= total - 1;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
        _saveAndNext,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
        _saveAndNext,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
        _saveAndNext,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
        _saveAndNext,
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo, Color(0xFF3F51B5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                  BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.schoolLogoBytes != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              widget.schoolLogoBytes!,
                              width: 30,
                              height: 30,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Text(
                            schoolName.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (widget.schoolLogoBytes != null) ...[
                          const SizedBox(width: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(
                              widget.schoolLogoBytes!,
                              width: 30,
                              height: 30,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      editing
                          ? "SAISIE RAPIDE — Élève ${index + 1} / $total"
                          : "CARTE D'IDENTITÉ SCOLAIRE — ${index + 1} / $total",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (!editing)
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              tooltip: "Élève précédent",
                              onPressed: index > 0 ? () => _go(-1) : null,
                            )
                          else
                            const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      radius: editing ? 38 : 55,
                                      backgroundColor: Colors.grey.shade200,
                                      backgroundImage: photoBytes != null
                                          ? MemoryImage(photoBytes!)
                                          : null,
                                      child: photoBytes == null
                                          ? Icon(Icons.person,
                                          size: editing ? 38 : 55,
                                          color: Colors.grey)
                                          : null,
                                    ),
                                    if (editing)
                                      CircleAvatar(
                                        radius: 15,
                                        backgroundColor: Colors.indigo,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.camera_alt,
                                              size: 15, color: Colors.white),
                                          tooltip: "Changer la photo",
                                          onPressed: _pickPhoto,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "${e.nom} ${e.postNom} ${e.prenom}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${e.section} — ${e.classe}",
                                  style: const TextStyle(
                                    color: Colors.indigo,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "ID : ${e.id}",
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!editing)
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              tooltip: "Élève suivant",
                              onPressed: !isLast ? () => _go(1) : null,
                            )
                          else
                            const SizedBox(width: 8),
                        ],
                      ),
                      if (editing && statusMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          statusMessage!,
                          style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 6),

                      if (!editing) ...[
                        ..._questions.map((q) {
                          String v = '';
                          e.customFields.forEach((k, val) {
                            if (k.trim().toLowerCase() ==
                                q.trim().toLowerCase()) {
                              v = val;
                            }
                          });
                          return _infoRow(q, v);
                        }),
                        _infoRow("Père", e.pereNom),
                        _infoRow("Mère", e.mereNom),
                        _infoRow("Adresse", e.adresse),
                        _infoRow("Naissance", e.dateNaissance),
                        if (!hasAnyExtraInfo)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              "Aucune information additionnelle enregistrée pour cet élève.",
                              style:
                              TextStyle(color: Colors.grey, fontSize: 12.5),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ] else ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text(
                                  "Ajouter une Question Personnalisée"),
                              onPressed: _addCustomField,
                            ),
                          ),
                        ),
                        if (_questions.isNotEmpty) ...[
                          _sectionLabel("Questions Personnalisées"),
                          ..._questions.map(
                                (q) => _editField(
                              controller: _qCtrl[q]!,
                              focus: _qFocus[q]!,
                              label: q,
                              onDelete: () => _deleteQuestion(q),
                            ),
                          ),
                          const Divider(),
                          _sectionLabel("Informations de base"),
                        ],
                        _editField(
                          controller: pereCtrl,
                          focus: pereFocus,
                          label: "Nom du père",
                          capitalization: TextCapitalization.words,
                        ),
                        _editField(
                          controller: mereCtrl,
                          focus: mereFocus,
                          label: "Nom de la mère",
                          capitalization: TextCapitalization.words,
                        ),
                        _editField(
                          controller: adresseCtrl,
                          focus: adresseFocus,
                          label: "Adresse",
                        ),
                        _editField(
                          controller: dateCtrl,
                          focus: dateFocus,
                          label: "Date de naissance",
                          hint: "jj/mm/aaaa (tapez seulement les chiffres)",
                          keyboardType: TextInputType.number,
                          formatters: [_DateSlashFormatter()],
                          suffix: IconButton(
                            icon: const Icon(Icons.calendar_today, size: 18),
                            tooltip: "Choisir dans le calendrier",
                            onPressed: _pickDate,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            "Astuce : Ctrl+Entrée (ou Cmd+Entrée) enregistre et "
                                "passe à l'élève suivant depuis n'importe quel champ.",
                            style: TextStyle(color: Colors.grey, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: _close,
                        child: const Text("Fermer"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (editing) ...[
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: isLast ? null : _skip,
                          child: const Text("Passer"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: ElevatedButton.icon(
                          icon: Icon(isLast ? Icons.save : Icons.skip_next),
                          label: Text(
                              isLast ? "Enregistrer" : "Enregistrer et suivant"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _saveAndNext,
                        ),
                      ),
                    ] else
                      Expanded(
                        flex: 4,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text("Modifier"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              editing = true;
                              statusMessage = null;
                            });
                            _focusFirst();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ElevesSupprimesScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const ElevesSupprimesScreen({super.key, required this.fraisScolaires});

  @override
  State<ElevesSupprimesScreen> createState() => _ElevesSupprimesScreenState();
}

class _ElevesSupprimesScreenState extends State<ElevesSupprimesScreen> {
  String searchQuery = "";

  String _formatDateSuppression(String? iso) {
    if (iso == null || iso.trim().isEmpty) return "Date inconnue";
    final date = DateTime.tryParse(iso);
    if (date == null) return "Date inconnue";
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }

  Future<bool> _verifyAdminPassword() async {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.backupPassword == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Aucun mot de passe administrateur défini. "
                  "Définissez-en un dans les Paramètres avant de continuer."),
        ),
      );
      return false;
    }

    final passController = TextEditingController();
    final bool? passwordOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vérification Administrateur"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Entrez le mot de passe administrateur pour continuer.",
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passController,
              obscureText: true,
              decoration:
              const InputDecoration(labelText: "Mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              if (passController.text.trim() == appState.backupPassword) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Mot de passe incorrect.")),
                );
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );

    return passwordOk == true;
  }

  Future<void> _openGestionPaiements(Eleve eleve) async {
    await showDialog(
      context: context,
      builder: (ctx) => _PaiementsEleveSupprimeDialog(
        eleve: eleve,
        fraisScolaires: widget.fraisScolaires,
        verifyAdminPassword: _verifyAdminPassword,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _requestDeleteForever(Eleve eleve) async {
    final bool passwordOk = await _verifyAdminPassword();
    if (!passwordOk) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text("Suppression définitive",
                style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Vous êtes sur le point de supprimer définitivement l'historique "
                  "de l'élève suivant :",
              style: TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${eleve.nom} ${eleve.postNom} ${eleve.prenom}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text("ID : ${eleve.id}"),
                  Text(
                      "Classe : ${eleve.classe}  |  Section : ${eleve.section}"),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "⚠️  Cette action est IRRÉVERSIBLE : l'historique nominatif de "
                  "cet élève (informations, transactions) disparaîtra "
                  "complètement du logiciel. L'argent déjà payé reste acquis "
                  "à la caisse de l'école, puisqu'il a déjà été comptabilisé "
                  "au moment du paiement.\n\n"
                  "Si vous voulez aussi retirer son argent de la caisse, "
                  "annulez d'abord ses paiements avec le bouton 💳 "
                  "avant de le supprimer définitivement.\n\n"
                  "Après suppression, pensez à sauvegarder sur le serveur "
                  "(Paramètres → Sauvegarder sur le Serveur).",
              style: TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer définitivement",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.fraisScolaires.supprimerDefinitivementEleveArchive(eleve.id);
    if (mounted) setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "✅ Historique de ${eleve.nom} ${eleve.postNom} ${eleve.prenom} "
                "supprimé définitivement. Pensez à sauvegarder sur le serveur.",
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _requestClearAll() async {
    if (widget.fraisScolaires.getElevesSupprimes().isEmpty) return;

    final bool passwordOk = await _verifyAdminPassword();
    if (!passwordOk) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text("Vider tout l'historique",
                style: TextStyle(color: Colors.red)),
          ],
        ),
        content: const Text(
          "Vous êtes sur le point de supprimer définitivement TOUT "
              "l'historique des élèves supprimés. Cette action est "
              "IRRÉVERSIBLE. L'argent déjà payé par ces élèves reste acquis "
              "à la caisse de l'école, puisqu'il a déjà été comptabilisé au "
              "moment du paiement.\n\n"
              "Voulez-vous vraiment continuer ?",
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Tout supprimer",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.fraisScolaires.viderHistoriqueElevesSupprimes();
    if (mounted) setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "✅ Historique des élèves supprimés vidé. Pensez à sauvegarder "
                  "sur le serveur."),
          duration: Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSupprimes = widget.fraisScolaires.getElevesSupprimes();
    final filtered = allSupprimes.where((e) {
      return e.nom.toLowerCase().contains(searchQuery.toLowerCase()) ||
          e.postNom.toLowerCase().contains(searchQuery.toLowerCase()) ||
          e.prenom.toLowerCase().contains(searchQuery.toLowerCase()) ||
          e.id.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Élèves Supprimés"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: "Vider tout l'historique",
            onPressed: allSupprimes.isEmpty ? null : _requestClearAll,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.indigo, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Ces élèves ne figurent plus dans le registre actif, "
                          "mais l'argent qu'ils ont déjà payé reste comptabilisé "
                          "dans la caisse de l'école. Avec le bouton 💳 vous "
                          "pouvez annuler leurs paiements si vous voulez "
                          "retirer cet argent de la caisse. La suppression "
                          "définitive d'un historique nécessite le mot de "
                          "passe administrateur.",
                      style: TextStyle(fontSize: 12.5, color: Colors.indigo),
                    ),
                  ),
                ],
              ),
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: "Rechercher par nom, post-nom, ID...",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => searchQuery = value);
              },
            ),
            const SizedBox(height: 16),
            Text(
              "Total : ${filtered.length} élève(s) supprimé(s)",
              style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text("Aucun élève supprimé trouvé"))
                  : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final e = filtered[index];
                  final double totalPaye =
                  widget.fraisScolaires.getStudentTotalPaid(e);
                  final String? dateSuppr = widget.fraisScolaires
                      .getDateSuppressionEleve(e.id);
                  final String? motif = widget.fraisScolaires
                      .getMotifSuppressionEleve(e.id);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.grey.shade300,
                            backgroundImage: (e.photoBase64 != null &&
                                e.photoBase64!.isNotEmpty)
                                ? MemoryImage(base64Decode(e.photoBase64!))
                                : null,
                            child: (e.photoBase64 == null ||
                                e.photoBase64!.isEmpty)
                                ? Text(
                              e.id.isNotEmpty
                                  ? e.id.substring(0, 2)
                                  : "?",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${e.nom} ${e.postNom} ${e.prenom}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14.5),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${e.section} - ${e.classe}  |  ID : ${e.id}",
                                  style: const TextStyle(
                                      fontSize: 12.5, color: Colors.black54),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Total déjà payé : ${formatMontant(totalPaye)} FC",
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Supprimé le : ${_formatDateSuppression(dateSuppr)}",
                                  style: const TextStyle(
                                      fontSize: 11.5, color: Colors.grey),
                                ),
                                if (motif != null && motif.trim().isNotEmpty)
                                  Text(
                                    "Motif : $motif",
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.payments_outlined,
                                    color: Colors.orange, size: 26),
                                tooltip: "Gérer / annuler les paiements",
                                onPressed: () => _openGestionPaiements(e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever,
                                    color: Colors.red, size: 26),
                                tooltip:
                                "Supprimer définitivement l'historique",
                                onPressed: () => _requestDeleteForever(e),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaiementsEleveSupprimeDialog extends StatefulWidget {
  final Eleve eleve;
  final FraisScolaires fraisScolaires;
  final Future<bool> Function() verifyAdminPassword;

  const _PaiementsEleveSupprimeDialog({
    required this.eleve,
    required this.fraisScolaires,
    required this.verifyAdminPassword,
  });

  @override
  State<_PaiementsEleveSupprimeDialog> createState() =>
      _PaiementsEleveSupprimeDialogState();
}

class _PaiementsEleveSupprimeDialogState
    extends State<_PaiementsEleveSupprimeDialog> {
  bool busy = false;

  Eleve get eleve => widget.eleve;
  FraisScolaires get fs => widget.fraisScolaires;

  List<Map<String, dynamic>> _transactionsTriees() {
    final list = List<Map<String, dynamic>>.from(eleve.transactions);
    list.sort((a, b) => (b['date'] ?? '')
        .toString()
        .compareTo((a['date'] ?? '').toString()));
    return list;
  }

  List<MapEntry<String, AutreFraisPaiement>> _autresPaiements() {
    final result = <MapEntry<String, AutreFraisPaiement>>[];
    fs.autresFraisPaiementsByYear.forEach((year, liste) {
      for (final p in liste) {
        if (p.eleveId == eleve.id) {
          result.add(MapEntry(year, p));
        }
      }
    });
    result.sort((a, b) => b.value.date.compareTo(a.value.date));
    return result;
  }

  double _totalAutres() => _autresPaiements()
      .fold(0.0, (sum, e) => sum + e.value.montant);

  Future<bool> _confirmer({
    required String titre,
    required String message,
    required String boutonLabel,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(titre,
                  style: const TextStyle(color: Colors.red, fontSize: 17)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(message, style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(boutonLabel,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
    );
  }

  Future<void> _annulerUneTransaction(Map<String, dynamic> t) async {
    if (busy) return;
    final double montant = (t['amount'] as num?)?.toDouble() ?? 0.0;
    final String mois = t['mois']?.toString() ?? '';
    final String date = t['date']?.toString() ?? '';

    final bool pwd = await widget.verifyAdminPassword();
    if (!pwd) return;

    final bool ok = await _confirmer(
      titre: "Annuler ce paiement",
      message: "Vous allez annuler le paiement de ${formatMontant(montant)} FC "
          "($mois, $date) de ${eleve.nom} ${eleve.postNom} ${eleve.prenom}.\n\n"
          "Ce montant sera RETIRÉ de la caisse de l'école (montant global, "
          "section, classe, rapports). Cette action est enregistrée dans le "
          "journal d'audit.\n\n"
          "Pensez ensuite à sauvegarder sur le serveur.",
      boutonLabel: "Annuler le paiement",
    );
    if (!ok) return;

    setState(() => busy = true);
    try {
      await fs.cancelTransaction(eleve: eleve, transaction: t);
      _snack("✅ Paiement de ${formatMontant(montant)} FC annulé. "
          "Pensez à sauvegarder sur le serveur.");
    } catch (e) {
      _snack("Erreur lors de l'annulation : $e");
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _annulerToutesTransactions() async {
    if (busy) return;
    final double total = fs.getStudentTotalPaid(eleve);
    if (eleve.transactions.isEmpty && total <= 0.5) return;

    final bool pwd = await widget.verifyAdminPassword();
    if (!pwd) return;

    final bool ok = await _confirmer(
      titre: "Annuler tous les paiements de scolarité",
      message: "Vous allez annuler TOUS les paiements de scolarité de "
          "${eleve.nom} ${eleve.postNom} ${eleve.prenom}, soit "
          "${formatMontant(total)} FC.\n\n"
          "Cet argent sera RETIRÉ de la caisse de l'école (montant global, "
          "section, classe, rapports). Cette action est enregistrée dans le "
          "journal d'audit.\n\n"
          "Pensez ensuite à sauvegarder sur le serveur.",
      boutonLabel: "Tout annuler",
    );
    if (!ok) return;

    setState(() => busy = true);
    try {
      final copie = List<Map<String, dynamic>>.from(eleve.transactions);
      for (final t in copie) {
        await fs.cancelTransaction(eleve: eleve, transaction: t);
      }

      final double reste = fs.getStudentTotalPaid(eleve);
      if (reste > 0.5) {
        eleve.paid.clear();
        fs.adminAuditLog.add(AdminAuditLog(
          id: 'AUD${DateTime.now().microsecondsSinceEpoch}',
          action: 'annulation',
          eleveId: eleve.id,
          eleveNomComplet: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
          classe: eleve.classe,
          mois: 'Tous les paiements (sans historique détaillé)',
          montantAvant: reste,
          montantApres: 0,
        ));
        await fs.saveData();
      }

      _snack("✅ Tous les paiements de scolarité (${formatMontant(total)} FC) "
          "ont été annulés. Pensez à sauvegarder sur le serveur.");
    } catch (e) {
      _snack("Erreur lors de l'annulation : $e");
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _annulerUnAutrePaiement(
      String year, AutreFraisPaiement p) async {
    if (busy) return;

    final bool pwd = await widget.verifyAdminPassword();
    if (!pwd) return;

    final bool ok = await _confirmer(
      titre: "Annuler ce paiement",
      message: "Vous allez annuler le paiement \"${p.autreFraisNom}\" de "
          "${formatMontant(p.montant)} FC (${p.dateFormatee}) de "
          "${eleve.nom} ${eleve.postNom} ${eleve.prenom}.\n\n"
          "Ce montant sera RETIRÉ de la caisse de l'école. Cette action est "
          "enregistrée dans le journal d'audit.\n\n"
          "Pensez ensuite à sauvegarder sur le serveur.",
      boutonLabel: "Annuler le paiement",
    );
    if (!ok) return;

    setState(() => busy = true);
    try {
      await fs.annulerPaiementAutreFrais(
        paiement: p,
        eleve: eleve,
        year: year,
      );
      _snack("✅ Paiement \"${p.autreFraisNom}\" annulé. "
          "Pensez à sauvegarder sur le serveur.");
    } catch (e) {
      _snack("Erreur lors de l'annulation : $e");
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _annulerTousAutresPaiements() async {
    if (busy) return;
    final liste = _autresPaiements();
    if (liste.isEmpty) return;
    final double total = _totalAutres();

    final bool pwd = await widget.verifyAdminPassword();
    if (!pwd) return;

    final bool ok = await _confirmer(
      titre: "Annuler tous les autres frais payés",
      message: "Vous allez annuler TOUS les paiements d'autres frais de "
          "${eleve.nom} ${eleve.postNom} ${eleve.prenom}, soit "
          "${formatMontant(total)} FC (${liste.length} paiement(s)).\n\n"
          "Cet argent sera RETIRÉ de la caisse de l'école. Cette action est "
          "enregistrée dans le journal d'audit.\n\n"
          "Pensez ensuite à sauvegarder sur le serveur.",
      boutonLabel: "Tout annuler",
    );
    if (!ok) return;

    setState(() => busy = true);
    try {
      for (final entry in liste) {
        await fs.annulerPaiementAutreFrais(
          paiement: entry.value,
          eleve: eleve,
          year: entry.key,
        );
      }
      _snack("✅ Tous les autres frais (${formatMontant(total)} FC) ont été "
          "annulés. Pensez à sauvegarder sur le serveur.");
    } catch (e) {
      _snack("Erreur lors de l'annulation : $e");
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _sectionTitle(String label, double total, VoidCallback? onCancelAll) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "$label — ${formatMontant(total)} FC",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep, size: 18, color: Colors.red),
            label: const Text("Tout annuler",
                style: TextStyle(color: Colors.red, fontSize: 12.5)),
            onPressed: (busy || onCancelAll == null) ? null : onCancelAll,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _transactionsTriees();
    final autres = _autresPaiements();
    final double totalScolarite = fs.getStudentTotalPaid(eleve);
    final double totalAutres = _totalAutres();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "PAIEMENTS DE L'ÉLÈVE SUPPRIMÉ",
                    style: TextStyle(
                        color: Colors.white70, fontSize: 11, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${eleve.nom} ${eleve.postNom} ${eleve.prenom}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                  Text(
                    "${eleve.section} - ${eleve.classe}  |  ID : ${eleve.id}",
                    style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border:
                        Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: const Text(
                        "Annuler un paiement RETIRE cet argent de la caisse de "
                            "l'école (montant global, section, classe, "
                            "rapports). Le mot de passe administrateur est "
                            "demandé à chaque annulation.",
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 10),

                    _sectionTitle(
                      "Scolarité",
                      totalScolarite,
                      (transactions.isEmpty && totalScolarite <= 0.5)
                          ? null
                          : _annulerToutesTransactions,
                    ),
                    if (transactions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          totalScolarite > 0.5
                              ? "Aucun détail de transaction (anciens paiements). "
                              "Utilisez \"Tout annuler\" pour retirer "
                              "${formatMontant(totalScolarite)} FC."
                              : "Aucun paiement de scolarité.",
                          style: const TextStyle(
                              fontSize: 12.5, color: Colors.grey),
                        ),
                      )
                    else
                      ...transactions.map((t) {
                        final double montant =
                            (t['amount'] as num?)?.toDouble() ?? 0.0;
                        final String mois = t['mois']?.toString() ?? '';
                        final String date = t['date']?.toString() ?? '';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              "${formatMontant(montant)} FC",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green),
                            ),
                            subtitle: Text("$mois  •  $date"),
                            trailing: IconButton(
                              icon: const Icon(Icons.cancel,
                                  color: Colors.red),
                              tooltip: "Annuler ce paiement",
                              onPressed: busy
                                  ? null
                                  : () => _annulerUneTransaction(t),
                            ),
                          ),
                        );
                      }),

                    const Divider(height: 24),

                    _sectionTitle(
                      "Autres frais",
                      totalAutres,
                      autres.isEmpty ? null : _annulerTousAutresPaiements,
                    ),
                    if (autres.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          "Aucun paiement d'autres frais.",
                          style: TextStyle(fontSize: 12.5, color: Colors.grey),
                        ),
                      )
                    else
                      ...autres.map((entry) {
                        final p = entry.value;
                        final String tranche =
                        fs.libelleTranchePaiementAutreFrais(p);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              "${p.autreFraisNom} — ${formatMontant(p.montant)} FC",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green),
                            ),
                            subtitle: Text("$tranche  •  ${p.dateFormatee}"),
                            trailing: IconButton(
                              icon: const Icon(Icons.cancel,
                                  color: Colors.red),
                              tooltip: "Annuler ce paiement",
                              onPressed: busy
                                  ? null
                                  : () => _annulerUnAutrePaiement(
                                  entry.key, p),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(
                children: [
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text("Fermer"),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}