import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../frais_scolaires.dart';
import '../models.dart';

class StatLigne {
  final String cle;
  final String libelle;
  final int nombre;
  const StatLigne(this.cle, this.libelle, this.nombre);
}

class GroupeRegistre {
  final String section;
  final String classe;
  final List<Eleve> eleves;
  GroupeRegistre(this.section, this.classe, this.eleves);
}

class RegistreEleves {
  static const String cleVide = '__vide__';
  static const String libelleVide = 'Non précisé';
  static const String sexeNonPrecise = '?';

  static const String _accentsDe = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœ';
  static const String _accentsVers = 'aaaaaaceeeeiiiinooooouuuuyyo';

  static String normaliser(String texte) {
    final bas = texte.toLowerCase();
    final sb = StringBuffer();
    for (final unite in bas.runes) {
      final c = String.fromCharCode(unite);
      final i = _accentsDe.indexOf(c);
      sb.write(i >= 0 ? _accentsVers[i] : c);
    }
    return sb.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static String champ(Eleve e, List<String> libelles) {
    final cibles = libelles.map(normaliser).toSet();
    for (final entree in e.customFields.entries) {
      if (cibles.contains(normaliser(entree.key))) {
        final v = entree.value.trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  static String lireSexe(Eleve e) {
    final v = normaliser(champ(e, ['Sexe', 'Genre']));
    if (v.isEmpty) return '';
    if (v == 'm' ||
        v == 'h' ||
        v.startsWith('masc') ||
        v.startsWith('gar') ||
        v.startsWith('hom')) {
      return 'M';
    }
    if (v == 'f' || v.startsWith('fem') || v.startsWith('fil')) {
      return 'F';
    }
    return '';
  }

  static String lireReligion(Eleve e) =>
      champ(e, ['Religion', 'Confession religieuse', 'Confession']);

  static String lireProfession(Eleve e) => champ(
      e, ['Profession', 'Profession du parent', 'Profession parent', 'Travail']);

  static String lireProvince(Eleve e) =>
      champ(e, ['Province', "Province d'origine"]);

  static String lireEcole(Eleve e) => champ(
      e, ["École d'origine", 'École de provenance', 'Ecole de provenance']);

  static String lireMatricule(Eleve e) => champ(e, [
    'Numéro permanent',
    'Numero permanent',
    'Matricule',
    'Numéro matricule'
  ]);

  static String lireInscription(Eleve e) => champ(e, ["Date d'inscription"]);

  static String lireTelephone(Eleve e) =>
      champ(e, ['Téléphone', 'Telephone', 'Numéro de téléphone']);

  static String lireTelephone2(Eleve e) =>
      champ(e, ['Téléphone 2', 'Telephone 2']);

  static String cleDe(String valeur) {
    final n = normaliser(valeur);
    return n.isEmpty ? cleVide : n;
  }

  static bool correspond(
      Eleve e, {
        String? filtreSexe,
        String? filtreReligion,
        String? filtreProfession,
        String? filtreProvince,
      }) {
    if (filtreSexe != null) {
      final s = lireSexe(e);
      if (filtreSexe == sexeNonPrecise) {
        if (s.isNotEmpty) return false;
      } else if (s != filtreSexe) {
        return false;
      }
    }
    if (filtreReligion != null && cleDe(lireReligion(e)) != filtreReligion) {
      return false;
    }
    if (filtreProfession != null &&
        cleDe(lireProfession(e)) != filtreProfession) {
      return false;
    }
    if (filtreProvince != null && cleDe(lireProvince(e)) != filtreProvince) {
      return false;
    }
    return true;
  }

  static List<StatLigne> statistiques(
      List<Eleve> eleves, String Function(Eleve) lire) {
    final comptes = <String, int>{};
    final libelles = <String, String>{};
    for (final e in eleves) {
      final brut = lire(e).trim();
      final k = cleDe(brut);
      comptes[k] = (comptes[k] ?? 0) + 1;
      libelles.putIfAbsent(k, () => k == cleVide ? libelleVide : brut);
    }
    final liste = comptes.entries
        .map((en) => StatLigne(en.key, libelles[en.key]!, en.value))
        .toList();
    liste.sort((a, b) {
      if (a.cle == cleVide && b.cle != cleVide) return 1;
      if (b.cle == cleVide && a.cle != cleVide) return -1;
      final c = b.nombre.compareTo(a.nombre);
      if (c != 0) return c;
      return a.libelle.toLowerCase().compareTo(b.libelle.toLowerCase());
    });
    return liste;
  }

  static String libelleDeCle(
      List<Eleve> eleves, String Function(Eleve) lire, String cle) {
    for (final l in statistiques(eleves, lire)) {
      if (l.cle == cle) return l.libelle;
    }
    return cle == cleVide ? libelleVide : cle;
  }

  static Map<String, int> compterSexes(List<Eleve> eleves) {
    int m = 0;
    int f = 0;
    int n = 0;
    for (final e in eleves) {
      final s = lireSexe(e);
      if (s == 'M') {
        m++;
      } else if (s == 'F') {
        f++;
      } else {
        n++;
      }
    }
    return {'M': m, 'F': f, '?': n};
  }

  static List<GroupeRegistre> grouper(
      FraisScolaires fs, List<Eleve> eleves) {
    final Map<String, GroupeRegistre> parCle = {};
    for (final e in eleves) {
      final k = '${e.section}\u0001${e.classe}';
      parCle
          .putIfAbsent(k, () => GroupeRegistre(e.section, e.classe, []))
          .eleves
          .add(e);
    }
    final groupes = parCle.values.toList();
    int indexSection(String s) {
      final i = fs.config.sections.indexOf(s);
      return i < 0 ? (1 << 20) : i;
    }

    int indexClasse(GroupeRegistre g) {
      final i = fs.getAllDisplayClassesForSection(g.section).indexOf(g.classe);
      return i < 0 ? (1 << 20) : i;
    }

    groupes.sort((a, b) {
      int c = indexSection(a.section).compareTo(indexSection(b.section));
      if (c != 0) return c;
      c = a.section.toLowerCase().compareTo(b.section.toLowerCase());
      if (c != 0) return c;
      c = indexClasse(a).compareTo(indexClasse(b));
      if (c != 0) return c;
      return a.classe.toLowerCase().compareTo(b.classe.toLowerCase());
    });
    return groupes;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dateHeure() {
    final n = DateTime.now();
    return '${_two(n.day)}/${_two(n.month)}/${n.year} à ${_two(n.hour)}:${_two(n.minute)}';
  }

  static String _pct(int n, int total) {
    if (total <= 0) return '0 %';
    return '${(n * 100 / total).toStringAsFixed(1)} %';
  }

  static pw.Widget _cell(String texte,
      {bool gras = false, bool centre = false, double taille = 7}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: pw.Text(
        texte,
        textAlign: centre ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: taille,
          fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static String _deuxLignes(String a, String b) {
    if (a.isNotEmpty && b.isNotEmpty) return '$a\n$b';
    return a.isNotEmpty ? a : b;
  }

  static pw.Widget _tableau(List<Eleve> eleves) {
    const titres = [
      'N°',
      'NOMS, POST-NOMS ET PRÉNOMS',
      'SEXE',
      'NOMS DES PARENTS\n(père / mère)',
      'DATE DE\nNAISSANCE',
      "PROVINCE\nD'ORIGINE",
      'ÉCOLE DE\nPROVENANCE',
      'NUMÉRO\nPERMANENT',
      'CONFESSION\nRELIGIEUSE',
      'PROFESSION\nPARENT',
      'ADRESSE',
      "DATE\nD'INSCRIPTION",
      'NUMÉRO\nTÉLÉPHONE',
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: titres
            .map((t) => _cell(t, gras: true, centre: true, taille: 6.5))
            .toList(),
      ),
    ];

    for (var i = 0; i < eleves.length; i++) {
      final e = eleves[i];
      rows.add(
        pw.TableRow(
          children: [
            _cell('${i + 1}', centre: true),
            _cell('${e.nom} ${e.postNom} ${e.prenom}'.trim()),
            _cell(lireSexe(e), centre: true),
            _cell(_deuxLignes(e.pereNom.trim(), e.mereNom.trim())),
            _cell(e.dateNaissance.trim(), centre: true),
            _cell(lireProvince(e)),
            _cell(lireEcole(e)),
            _cell(lireMatricule(e)),
            _cell(lireReligion(e)),
            _cell(lireProfession(e)),
            _cell(e.adresse.trim()),
            _cell(lireInscription(e), centre: true),
            _cell(_deuxLignes(lireTelephone(e), lireTelephone2(e)),
                centre: true),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey800),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(0.45),
        1: pw.FlexColumnWidth(2.6),
        2: pw.FlexColumnWidth(0.5),
        3: pw.FlexColumnWidth(2.0),
        4: pw.FlexColumnWidth(1.1),
        5: pw.FlexColumnWidth(1.2),
        6: pw.FlexColumnWidth(1.2),
        7: pw.FlexColumnWidth(1.5),
        8: pw.FlexColumnWidth(1.3),
        9: pw.FlexColumnWidth(1.2),
        10: pw.FlexColumnWidth(1.7),
        11: pw.FlexColumnWidth(1.1),
        12: pw.FlexColumnWidth(1.2),
      },
      children: rows,
    );
  }

  static List<pw.Widget> _enteteGroupe(FraisScolaires fs, GroupeRegistre g,
      String description, String dateHeure) {
    final s = compterSexes(g.eleves);
    return [
      pw.Center(
        child: pw.Text(
          fs.config.schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Center(
        child: pw.Text(
          'REGISTRE DES ÉLÈVES — ${g.classe}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Center(
        child: pw.Text(
          'Section : ${g.section}  |  Classe : ${g.classe}  |  '
              'Année scolaire ${fs.currentYear}  |  Effectif : ${g.eleves.length} '
              '(${s['M']} garçon(s), ${s['F']} fille(s)'
              '${(s['?'] ?? 0) > 0 ? ', ${s['?']} non précisé' : ''})',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      if (description.trim().isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'Filtres : $description',
            style: pw.TextStyle(
                fontSize: 8.5,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey800),
          ),
        ),
      ],
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          'Imprimé le : $dateHeure',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      pw.SizedBox(height: 8),
    ];
  }

  static List<pw.Widget> _tableStat(
      String titre, List<StatLigne> lignes, int total) {
    return [
      pw.Text(titre,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: const ['Libellé', 'Nombre', 'Pourcentage'],
        data: lignes
            .map((l) => [l.libelle, '${l.nombre}', _pct(l.nombre, total)])
            .toList(),
        columnWidths: const {
          0: pw.FlexColumnWidth(4),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1.2),
        },
        headerStyle: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.center,
        },
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
      ),
      pw.SizedBox(height: 14),
    ];
  }

  static List<pw.Widget> _pageStatistiques(
      FraisScolaires fs,
      List<Eleve> eleves,
      List<GroupeRegistre> groupes,
      String description,
      String dateHeure,
      ) {
    final total = eleves.length;
    final s = compterSexes(eleves);

    final sexes = <StatLigne>[
      StatLigne('M', 'Garçons', s['M'] ?? 0),
      StatLigne('F', 'Filles', s['F'] ?? 0),
      if ((s['?'] ?? 0) > 0) StatLigne('?', 'Sexe non précisé', s['?'] ?? 0),
    ];

    final lignesClasses = groupes.map((g) {
      final sg = compterSexes(g.eleves);
      return [
        '${g.section} — ${g.classe}',
        '${g.eleves.length}',
        '${sg['M']}',
        '${sg['F']}',
        '${sg['?']}',
      ];
    }).toList();

    return [
      pw.Center(
        child: pw.Text(
          fs.config.schoolName.toUpperCase(),
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Center(
        child: pw.Text(
          'STATISTIQUES DU REGISTRE — Année scolaire ${fs.currentYear}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Center(
        child: pw.Text(
          description.trim().isEmpty
              ? 'Effectif total : $total élève(s)'
              : 'Effectif total : $total élève(s)  |  Filtres : $description',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          'Imprimé le : $dateHeure',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      pw.SizedBox(height: 12),
      ..._tableStat('Répartition par sexe', sexes, total),
      pw.Text('Répartition par classe',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Section — Classe',
          'Effectif',
          'Garçons',
          'Filles',
          'Non précisé'
        ],
        data: lignesClasses,
        columnWidths: const {
          0: pw.FlexColumnWidth(4),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(1),
          4: pw.FlexColumnWidth(1),
        },
        headerStyle: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.center,
          2: pw.Alignment.center,
          3: pw.Alignment.center,
          4: pw.Alignment.center,
        },
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
      ),
      pw.SizedBox(height: 14),
      ..._tableStat(
          'Répartition par religion', statistiques(eleves, lireReligion), total),
      ..._tableStat('Répartition par profession des parents',
          statistiques(eleves, lireProfession), total),
      ..._tableStat('Répartition par province d\'origine',
          statistiques(eleves, lireProvince), total),
    ];
  }

  static String _nomSur(String texte) {
    final propre = texte
        .trim()
        .replaceAll(RegExp(r"[’'`]"), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return propre.isEmpty ? 'Registre_Eleves' : propre;
  }

  static Future<Map<String, dynamic>> _enregistrer(
      pw.Document pdf, String filename) async {
    try {
      final bytes = await pdf.save();
      final nom =
          '${_nomSur(filename)}_${DateTime.now().toString().split(' ')[0]}.pdf';
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        final file = File('${directory.path}/$nom');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
        return {'success': true, 'path': file.path};
      }
      final saveLocation = await getSaveLocation(
        suggestedName: nom,
        acceptedTypeGroups: [
          XTypeGroup(label: 'PDF', extensions: ['pdf'])
        ],
      );
      if (saveLocation != null) {
        final file = File(saveLocation.path);
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
        return {'success': true, 'path': file.path};
      }
      return {'success': false, 'error': 'Enregistrement annulé.'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> genererPdf({
    required FraisScolaires fs,
    required List<Eleve> eleves,
    required String filename,
    String description = '',
    bool unePageParClasse = true,
    bool inclureStatistiques = true,
  }) async {
    final pdf = pw.Document();
    final dateHeure = _dateHeure();
    final groupes = grouper(fs, eleves);
    final widgets = <pw.Widget>[];

    for (var i = 0; i < groupes.length; i++) {
      final g = groupes[i];
      if (i > 0) {
        if (unePageParClasse) {
          widgets.add(pw.NewPage());
        } else {
          widgets.add(pw.SizedBox(height: 20));
        }
      }
      widgets.addAll(_enteteGroupe(fs, g, description, dateHeure));
      widgets.add(_tableau(g.eleves));
    }

    if (groupes.isEmpty) {
      widgets.add(
        pw.Center(
          child: pw.Text(
            'Aucun élève ne correspond à ces filtres.',
            style: const pw.TextStyle(fontSize: 12),
          ),
        ),
      );
    }

    if (inclureStatistiques && eleves.isNotEmpty) {
      widgets.add(pw.NewPage());
      widgets.addAll(
          _pageStatistiques(fs, eleves, groupes, description, dateHeure));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        footer: (pw.Context context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (pw.Context context) => widgets,
      ),
    );

    return await _enregistrer(pdf, filename);
  }
}