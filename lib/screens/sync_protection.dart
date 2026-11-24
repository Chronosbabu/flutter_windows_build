// ============================================================================
// ⚡ ÉTAPE 5 — PROTECTIONS DE LA SYNCHRONISATION (écrans)
//  • afficherResumeSync : résumé avant / serveur / après d'une récupération,
//    anomalies, et choix « garder » / « annuler la récupération » quand les
//    chiffres sont anormaux ;
//  • JournalSyncScreen : journal des synchronisations de cet ordinateur ;
//  • DoublonsScreen : élèves en double / paiements identiques, réparation
//    sûre des fiches vides.
// ============================================================================
import 'package:flutter/material.dart';
import '../frais_scolaires.dart';

String _fcSync(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

/// Affiche le résumé d'une récupération (si [result] en contient un).
/// Quand les chiffres sont anormaux, la fenêtre est bloquante : l'utilisateur
/// doit choisir de garder ou d'annuler la récupération.
Future<void> afficherResumeSync(
    BuildContext context,
    FraisScolaires fs,
    Map<String, dynamic> result,
    ) async {
  final resume = result['resume'];
  if (resume is! Map) return;
  final anomalies = ((result['anomalies'] as List?) ?? const [])
      .whereType<Map>()
      .toList();
  final bool bloquant = result['bloquant'] == true ||
      result['code'] == 'ANOMALIE_FUSION';
  final bool arreteAvantEnvoi = result['code'] == 'ANOMALIE_FUSION';

  num v(String col, String cle) =>
      ((resume[col] as Map?)?[cle] as num?) ?? 0;

  TableRow ligne(String libelle, String cle, {bool argent = false}) {
    String f(num x) => argent ? '${_fcSync(x)} FC' : _fcSync(x);
    final changement = v('apres', cle) != v('avant', cle);
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(libelle, style: const TextStyle(fontSize: 12)),
      ),
      for (final col in ['avant', 'serveur', 'apres'])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Text(
            f(v(col, cle)),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: col == 'apres' && changement
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
    ]);
  }

  if (!context.mounted) return;
  final String? choix = await showDialog<String>(
    context: context,
    barrierDismissible: !bloquant,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(bloquant ? Icons.report : Icons.fact_check,
              color: bloquant ? Colors.red : Colors.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(bloquant
                ? "Chiffres anormaux — vérifiez avant de continuer"
                : "Résumé de la récupération"),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result['autreOrdinateur'] == true)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(8),
                  color: Colors.blue.withAlpha(25),
                  child: const Text(
                    "Un autre ordinateur avait sauvegardé entre-temps : ses "
                        "données ont été récupérées et fusionnées avec celles "
                        "de cet ordinateur AVANT l'envoi.",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              Table(
                columnWidths: const {0: FlexColumnWidth(1.6)},
                children: [
                  const TableRow(children: [
                    SizedBox(),
                    Text("Cet ordinateur\navant",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    Text("Serveur",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    Text("Après\nfusion",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ]),
                  ligne("Élèves", 'eleves'),
                  ligne("Paiements (frais scolaires)", 'transactions'),
                  ligne("Argent frais scolaires", 'argent', argent: true),
                  ligne("Paiements autres frais", 'paiements_autres_frais'),
                  ligne("Argent autres frais", 'argent_autres_frais',
                      argent: true),
                ],
              ),
              if (anomalies.isNotEmpty) const SizedBox(height: 12),
              for (final a in anomalies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        a['niveau'] == 'bloquant'
                            ? Icons.error
                            : Icons.warning_amber,
                        size: 18,
                        color: a['niveau'] == 'bloquant'
                            ? Colors.red
                            : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(a['message']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              if (bloquant) ...[
                const SizedBox(height: 8),
                Text(
                  arreteAvantEnvoi
                      ? "RIEN n'a été envoyé au serveur. Si vous annulez, cet "
                      "ordinateur revient exactement à l'état d'avant la "
                      "récupération. Si vous gardez, vérifiez les élèves "
                      "concernés avant de cliquer sur « Sauvegarder »."
                      : "Si vous annulez, cet ordinateur revient exactement à "
                      "l'état d'avant la récupération.",
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: bloquant
          ? [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'garder'),
          child: const Text("Garder (je vérifie)"),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.undo),
          label: const Text("Annuler la récupération"),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, 'annuler'),
        ),
      ]
          : [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, 'ok'),
          child: const Text("OK"),
        ),
      ],
    ),
  );

  if (choix == 'annuler') {
    final r = await fs.annulerDerniereRecuperation();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r['success'] == true
            ? "↩️ Récupération annulée : cet ordinateur est revenu à l'état "
            "d'avant. Rien n'a été envoyé au serveur."
            : "❌ ${r['error']}"),
        backgroundColor: r['success'] == true ? Colors.orange : Colors.red,
        duration: const Duration(seconds: 6),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// JOURNAL DE SYNCHRONISATION
// ---------------------------------------------------------------------------
class JournalSyncScreen extends StatelessWidget {
  final FraisScolaires fraisScolaires;
  const JournalSyncScreen({super.key, required this.fraisScolaires});

  static const _libelles = {
    'recuperation': 'Récupération',
    'sauvegarde': 'Sauvegarde',
    'synchronisation': 'Synchronisation',
    'deconnexion': 'Déconnexion',
    'annulation_recuperation': 'Récupération annulée',
    'reparation_doublons': 'Réparation des doublons',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Journal de synchronisation")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fraisScolaires.lireJournalSync(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final j = snap.data!;
          if (j.isEmpty) {
            return const Center(
                child: Text("Aucune synchronisation enregistrée sur cet "
                    "ordinateur."));
          }
          return ListView.separated(
            itemCount: j.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = j[i];
              final ok = e['succes'] != false;
              final anomalies = (e['anomalies'] as List?) ?? const [];
              final apres = ((e['resume'] as Map?)?['apres'] ??
                  e['resume']) as Map?;
              final date = (e['date']?.toString() ?? '')
                  .replaceFirst('T', ' ')
                  .split('.')
                  .first;
              final details = <String>[
                if (e['code'] != null) 'code : ${e['code']}',
                if (e['autre_ordinateur'] == true)
                  'un autre ordinateur avait sauvegardé entre-temps',
                if (apres != null)
                  '${apres['eleves']} élèves, '
                      '${_fcSync((apres['argent'] as num?) ?? 0)} FC',
                if (e['revision'] != null) 'révision ${e['revision']}',
                if (e['erreur'] != null) '${e['erreur']}',
                for (final a in anomalies)
                  if (a is Map) '⚠️ ${a['message']}',
                if (e['fiches_archivees'] is List)
                  'fiches archivées : ${(e['fiches_archivees'] as List).join(', ')}',
              ];
              return ListTile(
                dense: true,
                leading: Icon(
                  ok
                      ? (anomalies.isEmpty ? Icons.check_circle : Icons.warning)
                      : Icons.error,
                  color: ok
                      ? (anomalies.isEmpty ? Colors.green : Colors.orange)
                      : Colors.red,
                ),
                title: Text(
                    "${_libelles[e['action']] ?? e['action']} — $date"),
                subtitle: details.isEmpty ? null : Text(details.join('\n')),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DOUBLONS
// ---------------------------------------------------------------------------
class DoublonsScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const DoublonsScreen({super.key, required this.fraisScolaires});

  @override
  State<DoublonsScreen> createState() => _DoublonsScreenState();
}

class _DoublonsScreenState extends State<DoublonsScreen> {
  bool _enCours = false;

  @override
  Widget build(BuildContext context) {
    final groupes = widget.fraisScolaires.detecterDoublons();
    final nbSurs = groupes
        .where((g) => g['type'] == 'eleve')
        .fold<int>(0, (s, g) => s + (g['aArchiver'] as List).length);
    return Scaffold(
      appBar: AppBar(title: const Text("Vérifier les doublons")),
      body: groupes.isEmpty
          ? const Center(
          child: Text("✅ Aucun doublon détecté pour l'année en cours."))
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            "Réparation automatique : seules les fiches en double VIDES "
                "(aucun paiement, aucun autre frais, aucune information) "
                "sont archivées. Les autres cas sont à vérifier à la main : "
                "deux paiements identiques le même jour peuvent être réels.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (nbSurs > 0)
            ElevatedButton.icon(
              icon: _enCours
                  ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_fix_high),
              label: Text("Archiver les $nbSurs fiche(s) vide(s) en double"),
              onPressed: _enCours ? null : _reparer,
            ),
          const SizedBox(height: 8),
          for (final g in groupes) _carte(g),
        ],
      ),
    );
  }

  Widget _carte(Map<String, dynamic> g) {
    if (g['type'] == 'eleve') {
      final aArchiver = (g['aArchiver'] as List).cast<String>();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("👥 ${g['nom']} — ${(g['fiches'] as List).length} fiches",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              for (final f in (g['fiches'] as List).cast<Map>())
                Text(
                  "• ${f['id']} — ${f['classe']} (${f['section']}) — "
                      "${f['transactions']} paiement(s), "
                      "${_fcSync(f['argent'] as num)} FC"
                      "${aArchiver.contains(f['id']) ? '  → fiche vide, sera archivée' : ''}",
                  style: const TextStyle(fontSize: 12),
                ),
              if (aArchiver.isEmpty)
                const Text(
                  "À vérifier à la main (plusieurs fiches ont des données).",
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.receipt_long, color: Colors.orange),
        title: Text("${g['nom']} (${g['eleveId']})"),
        subtitle: Text(
          "${(g['ids'] as List).length} paiements identiques : "
              "${g['date']} — ${g['mois']} — "
              "${_fcSync((g['montant'] as num?) ?? 0)} FC. "
              "À vérifier : annulez celui en trop s'il s'agit d'une erreur.",
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Future<void> _reparer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Archiver les fiches vides en double ?"),
        content: const Text(
            "Une copie de sécurité est faite avant. Les fiches archivées "
                "restent visibles dans les élèves supprimés."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Archiver")),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _enCours = true);
    final n = await widget.fraisScolaires.reparerDoublonsSurs();
    if (!mounted) return;
    setState(() => _enCours = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("✅ $n fiche(s) vide(s) archivée(s).")),
    );
  }
}
