// ============================================================================
// ⚡ NOUVEAU — GÉNÉRATEUR DU "CAHIER DE PAIEMENT" (PDF)
// ============================================================================
// À placer dans : lib/services/cahier_paiement_service.dart
//
// Génère un PDF au format "cahier de paiement" (comme l'ancien cahier papier
// des écoles) :
//   - une ou plusieurs pages PAR CLASSE,
//   - une ligne par élève : N°, Nom + Post-nom + Prénom,
//   - une colonne par mois (Septembre → Juin) avec le montant payé,
//       * fond VERT   + "Soldé"   → le mois est entièrement payé,
//       * fond ORANGE + "Reste X" → paiement partiel,
//       * case VIDE               → rien payé pour ce mois,
//       * fond GRIS   + "Gratuit" → mois gratuit (exception à 0),
//   - une colonne "Total" par élève et une ligne "TOTAL CLASSE".
//
// Ce fichier est en LECTURE SEULE : il ne modifie aucune donnée de l'école
// (ni paiements, ni reçus, ni paramètres). Il utilise les mêmes fonctions que
// le reste de l'application pour connaître le montant requis de chaque élève
// (donc les exceptions de paiement par élève sont respectées).
// ============================================================================
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../frais_scolaires.dart';
import '../models.dart';

class CahierPaiementResultat {
  final bool succes;
  final String? chemin;
  final String? erreur;
  final int nbEleves;
  final int nbClasses;

  const CahierPaiementResultat({
    required this.succes,
    this.chemin,
    this.erreur,
    this.nbEleves = 0,
    this.nbClasses = 0,
  });
}

class _GroupeCahier {
  final String section;
  final String classe;
  final List<Eleve> eleves;
  _GroupeCahier(this.section, this.classe, this.eleves);
}

String _libelleMois(String m) {
  switch (m) {
    case 'Decembre':
      return 'Décembre';
    case 'Fevrier':
      return 'Février';
    default:
      return m;
  }
}

pw.Widget _cellTexte(
    String texte, {
      double taille = 7,
      bool gras = false,
      PdfColor couleur = PdfColors.black,
      pw.Alignment alignement = pw.Alignment.center,
      PdfColor? fond,
      double? hauteur,
    }) {
  return pw.Container(
    height: hauteur,
    color: fond,
    alignment: alignement,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
    child: pw.Text(
      texte,
      style: pw.TextStyle(
        fontSize: taille,
        fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: couleur,
      ),
    ),
  );
}

pw.Widget _cellMois(FraisScolaires fs, Eleve e, String mois) {
  const double hauteur = 21;
  final double requis = fs.getRequiredForMonthForEleve(e, mois);
  final double paye = e.paid[mois] ?? 0.0;

  // Mois gratuit (exception à 0)
  if (requis <= 0) {
    return pw.Container(
      height: hauteur,
      color: PdfColors.grey200,
      alignment: pw.Alignment.center,
      child: paye > 0.5
          ? pw.Text(formatMontant(paye),
          style: const pw.TextStyle(fontSize: 7))
          : pw.Text('Gratuit',
          style: const pw.TextStyle(
              fontSize: 6, color: PdfColors.grey700)),
    );
  }

  // Mois soldé
  if (paye >= requis - 0.5) {
    return pw.Container(
      height: hauteur,
      color: PdfColors.green100,
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(formatMontant(paye),
              style:
              pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          pw.Text('Soldé',
              style: const pw.TextStyle(
                  fontSize: 5.5, color: PdfColors.green900)),
        ],
      ),
    );
  }

  // Paiement partiel
  if (paye > 0.5) {
    return pw.Container(
      height: hauteur,
      color: PdfColors.orange100,
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(formatMontant(paye),
              style:
              pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          pw.Text('Reste ${formatMontant(requis - paye)}',
              style: const pw.TextStyle(
                  fontSize: 5.5, color: PdfColors.deepOrange900)),
        ],
      ),
    );
  }

  // Rien payé : case vide
  return pw.Container(height: hauteur);
}

pw.Widget _legende() {
  pw.Widget item(PdfColor couleur, String texte) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 9,
          height: 9,
          decoration: pw.BoxDecoration(
            color: couleur,
            border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
          ),
        ),
        pw.SizedBox(width: 3),
        pw.Text(texte, style: const pw.TextStyle(fontSize: 7)),
        pw.SizedBox(width: 12),
      ],
    );
  }

  return pw.Row(
    children: [
      item(PdfColors.green100, 'Mois soldé'),
      item(PdfColors.orange100, 'Paiement partiel (reste indiqué)'),
      item(PdfColors.white, 'Rien payé'),
      item(PdfColors.grey200, 'Mois gratuit'),
    ],
  );
}

/// Génère le cahier de paiement et l'ouvre.
///
/// [sectionFilter] / [classFilter] : null = toutes les sections / classes.
/// Le fichier est enregistré dans le dossier Téléchargements (ou, à défaut,
/// dans le dossier Documents de l'application), puis ouvert.
Future<CahierPaiementResultat> genererCahierPaiementPdf({
  required FraisScolaires fraisScolaires,
  required String filename,
  String? sectionFilter,
  String? classFilter,
}) async {
  try {
    final fs = fraisScolaires;

    final eleves = fs.currentData.eleves.where((e) {
      if (sectionFilter != null && e.section != sectionFilter) return false;
      if (classFilter != null && e.classe != classFilter) return false;
      return true;
    }).toList();

    if (eleves.isEmpty) {
      return const CahierPaiementResultat(
        succes: false,
        erreur: 'Aucun élève ne correspond à la section / classe choisie.',
      );
    }

    // ---------- Regroupement : section -> classe ----------
    final sectionsOrdre = <String>[...fs.config.sections];
    for (final e in eleves) {
      if (!sectionsOrdre.contains(e.section)) sectionsOrdre.add(e.section);
    }

    final groupes = <_GroupeCahier>[];
    for (final s in sectionsOrdre) {
      final deSection = eleves.where((e) => e.section == s).toList();
      if (deSection.isEmpty) continue;

      final classesOrdre = <String>[...fs.getAllDisplayClassesForSection(s)];
      final autres = deSection
          .map((e) => e.classe)
          .toSet()
          .where((c) => !classesOrdre.contains(c))
          .toList()
        ..sort();

      for (final c in [...classesOrdre, ...autres]) {
        final liste = deSection.where((e) => e.classe == c).toList();
        if (liste.isEmpty) continue;
        liste.sort((a, b) {
          int r = a.nom.toLowerCase().compareTo(b.nom.toLowerCase());
          if (r != 0) return r;
          r = a.postNom.toLowerCase().compareTo(b.postNom.toLowerCase());
          if (r != 0) return r;
          return a.prenom.toLowerCase().compareTo(b.prenom.toLowerCase());
        });
        groupes.add(_GroupeCahier(s, c, liste));
      }
    }

    final doc = pw.Document(title: 'Cahier de paiement');
    final mois = fs.months;
    final String ecole = fs.config.schoolName.toUpperCase();
    final DateTime now = DateTime.now();
    String deux(int n) => n.toString().padLeft(2, '0');
    final String dateEdition = '${deux(now.day)}/${deux(now.month)}/${now.year}';

    for (final g in groupes) {
      // ---------- En-tête du tableau ----------
      final enTete = pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
        children: [
          _cellTexte('N°',
              taille: 7,
              gras: true,
              couleur: PdfColors.white,
              hauteur: 20),
          _cellTexte('NOM, POST-NOM ET PRÉNOM',
              taille: 7,
              gras: true,
              couleur: PdfColors.white,
              hauteur: 20,
              alignement: pw.Alignment.centerLeft),
          for (final m in mois)
            _cellTexte(_libelleMois(m),
                taille: 6.5,
                gras: true,
                couleur: PdfColors.white,
                hauteur: 20),
          _cellTexte('TOTAL',
              taille: 7,
              gras: true,
              couleur: PdfColors.white,
              hauteur: 20),
        ],
      );

      // ---------- Lignes élèves ----------
      final lignes = <pw.TableRow>[];
      for (var i = 0; i < g.eleves.length; i++) {
        final e = g.eleves[i];
        lignes.add(pw.TableRow(
          children: [
            _cellTexte('${i + 1}', taille: 7, hauteur: 21),
            _cellTexte(
              '${e.nom} ${e.postNom} ${e.prenom}'.trim(),
              taille: 7.5,
              alignement: pw.Alignment.centerLeft,
              hauteur: 21,
            ),
            for (final m in mois) _cellMois(fs, e, m),
            _cellTexte(
              formatMontant(fs.getStudentTotalPaid(e)),
              taille: 7,
              gras: true,
              hauteur: 21,
            ),
          ],
        ));
      }

      // ---------- Ligne de totaux de la classe ----------
      double totalGeneral = 0;
      final totauxMois = <double>[];
      for (final m in mois) {
        double t = 0;
        for (final e in g.eleves) {
          t += e.paid[m] ?? 0.0;
        }
        totauxMois.add(t);
        totalGeneral += t;
      }
      final ligneTotal = pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cellTexte('', hauteur: 20),
          _cellTexte('TOTAL CLASSE',
              taille: 7.5,
              gras: true,
              alignement: pw.Alignment.centerLeft,
              hauteur: 20),
          for (final t in totauxMois)
            _cellTexte(t > 0.5 ? formatMontant(t) : '',
                taille: 6.5, gras: true, hauteur: 20),
          _cellTexte(formatMontant(totalGeneral),
              taille: 7, gras: true, hauteur: 20),
        ],
      );

      final largeurs = <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(0.55),
        1: const pw.FlexColumnWidth(3.4),
        for (var i = 0; i < mois.length; i++)
          2 + i: const pw.FlexColumnWidth(1.25),
        2 + mois.length: const pw.FlexColumnWidth(1.45),
      };

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
          footer: (ctx) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Cahier de paiement — $ecole — édité le $dateEdition',
                  style: const pw.TextStyle(
                      fontSize: 6.5, color: PdfColors.grey700)),
              pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: const pw.TextStyle(
                      fontSize: 6.5, color: PdfColors.grey700)),
            ],
          ),
          build: (ctx) => [
            pw.Center(
              child: pw.Text(
                ecole,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'CAHIER DE PAIEMENT',
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Année scolaire : ${fs.currentYear}',
                    style: const pw.TextStyle(fontSize: 8.5)),
                pw.Text('Section : ${g.section}',
                    style: pw.TextStyle(
                        fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                pw.Text('Classe : ${g.classe}',
                    style: pw.TextStyle(
                        fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                pw.Text('Effectif : ${g.eleves.length} élève(s)',
                    style: const pw.TextStyle(fontSize: 8.5)),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
              columnWidths: largeurs,
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [enTete, ...lignes, ligneTotal],
            ),
            pw.SizedBox(height: 8),
            _legende(),
          ],
        ),
      );
    }

    // ---------- Enregistrement + ouverture ----------
    Directory dossier;
    try {
      final d = await getDownloadsDirectory();
      dossier = d ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      dossier = await getApplicationDocumentsDirectory();
    }

    String propre = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (propre.isEmpty) propre = 'Cahier_Paiement';
    final String stamp =
        '${now.year}${deux(now.month)}${deux(now.day)}_${deux(now.hour)}${deux(now.minute)}${deux(now.second)}';
    final file = File('${dossier.path}/${propre}_$stamp.pdf');
    await file.writeAsBytes(await doc.save());

    try {
      await OpenFile.open(file.path);
    } catch (_) {
      // Le fichier est bien enregistré même si l'ouverture automatique échoue.
    }

    return CahierPaiementResultat(
      succes: true,
      chemin: file.path,
      nbEleves: eleves.length,
      nbClasses: groupes.length,
    );
  } catch (e) {
    return CahierPaiementResultat(
      succes: false,
      erreur: 'Erreur lors de la génération du cahier : $e',
    );
  }
}