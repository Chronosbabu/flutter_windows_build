import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import '../models.dart';

/// Page des reçus : affiche l'historique complet de tous les paiements
/// de tous les élèves de l'année en cours. Chaque reçu montre :
///   - Le nom de l'école en titre principal (gras)
///   - Le nom complet de l'élève
///   - Sa promotion (classe + section)
///   - Le détail mois par mois (montant payé / requis / reste)
///   - L'historique de chaque transaction avec la date
class RecusScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const RecusScreen({super.key, required this.fraisScolaires});

  @override
  State<RecusScreen> createState() => _RecusScreenState();
}

class _RecusScreenState extends State<RecusScreen> {
  final searchController = TextEditingController();
  String? selectedSectionFilter;
  String? selectedClassFilter;
  List<Eleve> filtered = [];

  @override
  void initState() {
    super.initState();
    _filterEleves();
    searchController.addListener(_filterEleves);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _filterEleves() {
    final query = searchController.text.toLowerCase().trim();
    setState(() {
      // On n'affiche que les élèves qui ont au moins une transaction
      filtered = widget.fraisScolaires.currentData.eleves.where((e) {
        final hasTransactions = e.transactions.isNotEmpty;
        final nameMatch =
            '${e.nom} ${e.postNom} ${e.prenom}'.toLowerCase().contains(query) ||
                e.id.toLowerCase().contains(query);
        final sectionMatch =
            selectedSectionFilter == null || e.section == selectedSectionFilter;
        final classMatch =
            selectedClassFilter == null || e.classe == selectedClassFilter;
        return hasTransactions && nameMatch && sectionMatch && classMatch;
      }).toList();

      // Tri par nom
      filtered.sort((a, b) => a.nom.compareTo(b.nom));
    });
  }

  @override
  Widget build(BuildContext context) {
    final classOptions = selectedSectionFilter != null
        ? List<String>.from(
      widget.fraisScolaires
          .getAllDisplayClassesForSection(selectedSectionFilter!),
    )
        : List<String>.from(widget.fraisScolaires.getAllDisplayClasses());

    if (selectedClassFilter != null &&
        !classOptions.contains(selectedClassFilter)) {
      classOptions.add(selectedClassFilter!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historique des Reçus"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ==================== EN-TÊTE ÉCOLE ====================
          Container(
            width: double.infinity,
            color: Colors.indigo.withAlpha(20),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(
              children: [
                Text(
                  widget.fraisScolaires.config.schoolName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Année scolaire : ${widget.fraisScolaires.currentYear}",
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
          ),

          // ==================== FILTRES ====================
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: "Rechercher par nom ou ID",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text("Toutes les sections"),
                        value: selectedSectionFilter,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text("Toutes les sections"),
                          ),
                          ...widget.fraisScolaires.config.sections.map(
                                (s) => DropdownMenuItem(value: s, child: Text(s)),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            selectedSectionFilter = val;
                            selectedClassFilter = null;
                            _filterEleves();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text("Toutes les classes"),
                        value: selectedClassFilter,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text("Toutes les classes"),
                          ),
                          ...classOptions.map(
                                (c) => DropdownMenuItem(value: c, child: Text(c)),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            selectedClassFilter = val;
                            _filterEleves();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ==================== COMPTEUR ====================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "${filtered.length} élève(s) avec des paiements",
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
          ),

          // ==================== LISTE DES REÇUS ====================
          Expanded(
            child: filtered.isEmpty
                ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    "Aucun reçu trouvé",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final eleve = filtered[index];
                return _buildReceiptCard(eleve);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CARTE RÉSUMÉ D'UN ÉLÈVE ====================
  Widget _buildReceiptCard(Eleve eleve) {
    final double totalPaye =
    widget.fraisScolaires.getStudentTotalPaid(eleve);
    final double totalRequis =
        widget.fraisScolaires.getStudentPending(eleve) + totalPaye;
    final double resteTotal = totalRequis - totalPaye;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReceiptDetail(eleve),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nom de l'école en titre
              Text(
                widget.fraisScolaires.config.schoolName.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.indigo,
                  letterSpacing: 0.8,
                ),
              ),
              const Divider(height: 10),

              // Nom de l'élève
              Text(
                "${eleve.nom} ${eleve.postNom} ${eleve.prenom}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),

              // Promotion (classe + section)
              Row(
                children: [
                  const Icon(Icons.school, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    "${eleve.classe}  •  ${eleve.section}",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Montants
              Row(
                children: [
                  Expanded(
                    child: _buildAmountChip(
                      label: "Payé",
                      amount: totalPaye,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAmountChip(
                      label: "Reste",
                      amount: resteTotal > 0 ? resteTotal : 0,
                      color: resteTotal > 0 ? Colors.orange : Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAmountChip(
                      label: "Requis",
                      amount: totalRequis,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Nombre de transactions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${eleve.transactions.length} paiement(s) enregistré(s)",
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const Row(
                    children: [
                      Text(
                        "Voir détail",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.indigo,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios,
                          size: 12, color: Colors.indigo),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountChip({
    required String label,
    required double amount,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "${amount.toStringAsFixed(0)} FC",
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==================== DÉTAIL COMPLET DU REÇU ====================
  void _showReceiptDetail(Eleve eleve) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- Titre : nom de l'école ----
              Center(
                child: Text(
                  widget.fraisScolaires.config.schoolName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.indigo,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Center(
                child: Text(
                  "REÇU DE PAIEMENT",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  "Année scolaire : ${widget.fraisScolaires.currentYear}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const Divider(height: 20),

              // ---- Infos élève ----
              _detailRow("Nom complet",
                  "${eleve.nom} ${eleve.postNom} ${eleve.prenom}"),
              _detailRow("ID", eleve.id),
              _detailRow("Promotion", eleve.classe),
              _detailRow("Section", eleve.section),
              const Divider(height: 20),

              // ---- Bilan financier ----
              const Text(
                "BILAN FINANCIER",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.fraisScolaires.months.map((mois) {
                final requis = widget.fraisScolaires
                    .getRequiredForMonth(mois, eleve.section, eleve.classe);
                final paye = (eleve.paid[mois] ?? 0).toDouble();
                final reste = requis - paye;
                if (paye == 0 && reste == requis) {
                  // Mois non commencé → on l'affiche quand même en gris
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            mois,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "0 FC / ${requis.toStringAsFixed(0)} FC",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const Icon(Icons.remove, size: 14, color: Colors.grey),
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          mois,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          "${paye.toStringAsFixed(0)} / ${requis.toStringAsFixed(0)} FC",
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      reste <= 0
                          ? const Icon(Icons.check_circle,
                          size: 16, color: Colors.green)
                          : Text(
                        "-${reste.toStringAsFixed(0)} FC",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 20),

              // ---- Totaux ----
              Builder(builder: (context) {
                final totalPaye =
                widget.fraisScolaires.getStudentTotalPaid(eleve);
                final totalRequis =
                    widget.fraisScolaires.getStudentPending(eleve) + totalPaye;
                final resteTotal = totalRequis - totalPaye;
                return Column(
                  children: [
                    _totalRow(
                        "Total payé", totalPaye, Colors.green),
                    _totalRow(
                        "Total requis (annuel)", totalRequis, Colors.indigo),
                    _totalRow(
                        "Reste à payer",
                        resteTotal > 0 ? resteTotal : 0,
                        resteTotal > 0 ? Colors.red : Colors.green),
                  ],
                );
              }),
              const Divider(height: 20),

              // ---- Historique des transactions ----
              const Text(
                "HISTORIQUE DES PAIEMENTS",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              if (eleve.transactions.isEmpty)
                const Text(
                  "Aucune transaction enregistrée.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                )
              else
                ...(() {
                  final sorted =
                  List<Map<String, dynamic>>.from(eleve.transactions)
                    ..sort(
                          (a, b) => (a['date'] ?? '')
                          .toString()
                          .compareTo((b['date'] ?? '').toString()),
                    );
                  return sorted.map((t) {
                    final date = t['date']?.toString() ?? "—";
                    final mois = t['mois']?.toString() ?? "—";
                    final amount = (t['amount'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long,
                              size: 14, color: Colors.indigo),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "$date  —  $mois",
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            "${amount.toStringAsFixed(0)} FC",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                })(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fermer"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              "$label :",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            "${amount.toStringAsFixed(0)} FC",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}