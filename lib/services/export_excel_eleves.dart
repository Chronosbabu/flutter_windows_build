import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../frais_scolaires.dart';
import '../models.dart';
import '../utils/age_utils.dart';
import 'registre_eleves_pdf.dart';

/// Une colonne du fichier Excel : un titre et la façon de lire la valeur
/// pour un élève. Une valeur manquante donne simplement une cellule vide.
class ColonneExcel {
  final String id;
  final String titre;
  final String Function(Eleve) lire;
  const ColonneExcel(this.id, this.titre, this.lire);
}

class ExportExcelEleves {
  // ---------------------------------------------------------------------
  // Libellés acceptés (insensibles aux accents, majuscules, ponctuation)
  // pour retrouver chaque information dans les champs personnalisés.
  // ---------------------------------------------------------------------
  static const List<String> _libTelephone = [
    'Téléphone du parent',
    'Téléphone des parents',
    'Téléphone parent',
    'Numéro de téléphone du parent',
    'Numéro du parent',
    'Tél. du parent',
    'Tél parent',
    'Téléphone',
    'Numéro de téléphone',
    'Tél',
    'Contact',
    'Contact du parent',
  ];
  static const List<String> _libDateNaissance = [
    'Date de naissance',
    'Né le',
    'Née le',
  ];
  static const List<String> _libLieuNaissance = [
    'Lieu de naissance',
    'Lieu naissance',
    'Né à',
    'Née à',
  ];
  static const List<String> _libNationalite = [
    'Nationalité',
    'Nationalite',
    'Pays',
  ];
  static const List<String> _libNumeroSerie = [
    'Numéro de série',
    'Numéro série',
    'N° de série',
    'N° série',
    'No de série',
    'Num série',
    'Série',
  ];
  static const List<String> _libSexe = ['Sexe', 'Genre'];

  static String _sexe(Eleve e) {
    final s = RegistreEleves.lireSexe(e);
    if (s.isNotEmpty) return s;
    // Valeur non reconnue (ex. « Masculin » mal orthographié) : on la
    // recopie telle quelle plutôt que de la perdre.
    return RegistreEleves.champ(e, _libSexe);
  }

  static String _dateNaissance(Eleve e) {
    final d = e.dateNaissance.trim();
    return d.isNotEmpty ? d : RegistreEleves.champ(e, _libDateNaissance);
  }

  /// Les colonnes demandées par défaut, dans l'ordre.
  static List<ColonneExcel> colonnesDeBase() => [
        ColonneExcel('tel', 'Téléphone du parent',
            (e) => RegistreEleves.champ(e, _libTelephone)),
        ColonneExcel('nom', 'Nom', (e) => e.nom.trim()),
        ColonneExcel('postnom', 'Post-nom', (e) => e.postNom.trim()),
        ColonneExcel('prenom', 'Prénom', (e) => e.prenom.trim()),
        ColonneExcel('sexe', 'Sexe', _sexe),
        ColonneExcel('naissance', 'Date de naissance', _dateNaissance),
        ColonneExcel('lieu', 'Lieu de naissance',
            (e) => RegistreEleves.champ(e, _libLieuNaissance)),
        ColonneExcel('nationalite', 'Nationalité',
            (e) => RegistreEleves.champ(e, _libNationalite)),
        ColonneExcel('serie', 'Numéro de série',
            (e) => RegistreEleves.champ(e, _libNumeroSerie)),
      ];

  /// Colonnes supplémentaires que chaque école peut cocher : informations
  /// fixes + toutes les questions personnalisées de l'école (et tout autre
  /// champ trouvé chez les élèves), sauf celles déjà couvertes par la base.
  static List<ColonneExcel> colonnesSupplementaires(
      FraisScolaires fs, List<Eleve> eleves) {
    final cols = <ColonneExcel>[
      ColonneExcel('classe', 'Classe', (e) => e.classe.trim()),
      ColonneExcel('section', 'Section', (e) => e.section.trim()),
      ColonneExcel('age', 'Âge', (e) => AgeUtils.libelle(e.dateNaissance)),
      ColonneExcel('pere', 'Nom du père', (e) => e.pereNom.trim()),
      ColonneExcel('mere', 'Nom de la mère', (e) => e.mereNom.trim()),
      ColonneExcel('adresse', 'Adresse', (e) => e.adresse.trim()),
    ];

    final dejaPris = <String>{
      for (final l in [
        ..._libTelephone,
        ..._libDateNaissance,
        ..._libLieuNaissance,
        ..._libNationalite,
        ..._libNumeroSerie,
        ..._libSexe,
        'Nom',
        'Post-nom',
        'Postnom',
        'Prénom',
        'Classe',
        'Section',
        'Âge',
        'Age',
        'Nom du père',
        'Nom de la mère',
        'Adresse',
      ])
        RegistreEleves.normaliser(l),
    };

    final questions = <String>[
      ...fs.config.customFieldQuestions,
      for (final e in eleves) ...e.customFields.keys,
    ];
    for (final q in questions) {
      final titre = q.trim();
      final n = RegistreEleves.normaliser(titre);
      if (n.isEmpty || dejaPris.contains(n)) continue;
      dejaPris.add(n);
      cols.add(ColonneExcel('custom:$n', titre,
          (e) => RegistreEleves.champ(e, [titre])));
    }
    return cols;
  }

  /// Trie les élèves comme dans le registre (section, classe, puis nom).
  static List<Eleve> ordonner(FraisScolaires fs, List<Eleve> eleves) => [
        for (final g in RegistreEleves.grouper(fs, eleves)) ...g.eleves,
      ];

  // ---------------------------------------------------------------------
  // Nom de fichier et dossier Bureau
  // ---------------------------------------------------------------------

  static String nomDeFichierPropre(String saisie) {
    var n = saisie.trim();
    if (n.toLowerCase().endsWith('.xlsx')) {
      n = n.substring(0, n.length - 5);
    }
    n = n
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    while (n.endsWith('.')) {
      n = n.substring(0, n.length - 1).trim();
    }
    return n;
  }

  /// Dossier « Bureau » réel de l'utilisateur (y compris un Bureau déplacé
  /// dans OneDrive sous Windows).
  static Future<Directory?> dossierBureau() async {
    final candidats = <String>[];
    if (Platform.isWindows) {
      try {
        final r = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            "[Environment]::GetFolderPath('Desktop')",
          ],
          stdoutEncoding: utf8,
        );
        final p = (r.stdout as String? ?? '').trim();
        if (r.exitCode == 0 && p.isNotEmpty) candidats.add(p);
      } catch (_) {}
      final profil = Platform.environment['USERPROFILE'];
      final oneDrive = Platform.environment['OneDrive'];
      if (oneDrive != null) candidats.add('$oneDrive\\Desktop');
      if (oneDrive != null) candidats.add('$oneDrive\\Bureau');
      if (profil != null) candidats.add('$profil\\Desktop');
      if (profil != null) candidats.add('$profil\\Bureau');
    } else {
      final home = Platform.environment['HOME'];
      if (home != null) {
        candidats.add('$home/Desktop');
        candidats.add('$home/Bureau');
      }
    }
    for (final c in candidats) {
      final d = Directory(c);
      if (await d.exists()) return d;
    }
    return null;
  }

  /// Chemin libre sur le Bureau : « nom.xlsx », sinon « nom (2).xlsx »…
  /// (un fichier existant n'est jamais écrasé).
  static Future<File> _fichierLibre(Directory dossier, String nom) async {
    final sep = Platform.pathSeparator;
    var f = File('${dossier.path}$sep$nom.xlsx');
    var i = 2;
    while (await f.exists()) {
      f = File('${dossier.path}$sep$nom ($i).xlsx');
      i++;
    }
    return f;
  }

  /// Génère le fichier et l'enregistre sur le Bureau.
  /// Retourne {'success': bool, 'path' | 'error': String}.
  static Future<Map<String, dynamic>> genererSurBureau({
    required String nomFichier,
    required String titreFeuille,
    required List<ColonneExcel> colonnes,
    required List<Eleve> eleves,
  }) async {
    try {
      final nom = nomDeFichierPropre(nomFichier);
      if (nom.isEmpty) {
        return {'success': false, 'error': 'Nom de fichier invalide.'};
      }
      final bureau = await dossierBureau();
      if (bureau == null) {
        return {
          'success': false,
          'error': 'Dossier « Bureau » introuvable sur cet ordinateur.'
        };
      }
      final lignes = <List<String>>[
        [for (final c in colonnes) c.titre],
        for (final e in eleves) [for (final c in colonnes) c.lire(e)],
      ];
      final bytes = construireXlsx(lignes, titreFeuille);
      final fichier = await _fichierLibre(bureau, nom);
      await fichier.writeAsBytes(bytes, flush: true);
      return {'success': true, 'path': fichier.path};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------
  // Écriture du fichier .xlsx (format Office Open XML, sans dépendance)
  // ---------------------------------------------------------------------

  static String _xml(String s) {
    final propre =
        s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    return propre
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _colonne(int index) {
    var n = index + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _nomFeuille(String titre) {
    var t = titre.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    if (t.isEmpty) t = 'Élèves';
    if (t.length > 31) t = t.substring(0, 31);
    return t;
  }

  /// [lignes][0] = en-têtes (en gras). Toutes les cellules sont du texte,
  /// pour garder intacts les numéros de téléphone (0 initial) et les dates.
  static List<int> construireXlsx(List<List<String>> lignes, String titre) {
    final nbCols = lignes.isEmpty ? 0 : lignes.first.length;

    // Largeur des colonnes adaptée au contenu.
    final largeurs = List<int>.filled(nbCols, 8);
    for (final l in lignes) {
      for (var c = 0; c < nbCols && c < l.length; c++) {
        final len = l[c].length + 2;
        if (len > largeurs[c]) largeurs[c] = len > 60 ? 60 : len;
      }
    }

    final sheet = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
      ..write('<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
          '</sheetView></sheetViews>')
      ..write('<sheetFormatPr defaultRowHeight="15"/>');
    if (nbCols > 0) {
      sheet.write('<cols>');
      for (var c = 0; c < nbCols; c++) {
        sheet.write(
            '<col min="${c + 1}" max="${c + 1}" width="${largeurs[c]}" customWidth="1"/>');
      }
      sheet.write('</cols>');
    }
    sheet.write('<sheetData>');
    for (var r = 0; r < lignes.length; r++) {
      final ligne = lignes[r];
      sheet.write('<row r="${r + 1}">');
      for (var c = 0; c < ligne.length; c++) {
        final v = ligne[c];
        final ref = '${_colonne(c)}${r + 1}';
        final style = r == 0 ? ' s="1"' : ' s="2"';
        if (v.isEmpty) {
          sheet.write('<c r="$ref"$style/>');
        } else {
          sheet.write('<c r="$ref" t="inlineStr"$style><is><t xml:space="preserve">'
              '${_xml(v)}</t></is></c>');
        }
      }
      sheet.write('</row>');
    }
    sheet.write('</sheetData>');
    if (nbCols > 0 && lignes.length > 1) {
      sheet.write(
          '<autoFilter ref="A1:${_colonne(nbCols - 1)}${lignes.length}"/>');
    }
    sheet.write('</worksheet>');

    final nomFeuille = _xml(_nomFeuille(titre));

    final fichiers = <String, String>{
      '[Content_Types].xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
              '<Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
              '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
              '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
              '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
              '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
              '</Types>',
      '_rels/.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
              '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
              '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
              '</Relationships>',
      'docProps/core.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
              'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
              'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
              '<dc:title>$nomFeuille</dc:title><dc:creator>Gestion des Frais Scolaires</dc:creator>'
              '<dcterms:created xsi:type="dcterms:W3CDTF">${DateTime.now().toUtc().toIso8601String().split('.').first}Z</dcterms:created>'
              '</cp:coreProperties>',
      'docProps/app.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
              '<Application>Microsoft Excel</Application></Properties>',
      'xl/workbook.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
              'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<sheets><sheet name="$nomFeuille" sheetId="1" r:id="rId1"/></sheets>'
              '${nbCols > 0 && lignes.length > 1 ? '<definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">\'$nomFeuille\'!\$A\$1:\$${_colonne(nbCols - 1)}\$${lignes.length}</definedName></definedNames>' : ''}'
              '</workbook>',
      'xl/_rels/workbook.xml.rels':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
              '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
              '</Relationships>',
      'xl/styles.xml':
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
              '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
              '<fills count="3"><fill><patternFill patternType="none"/></fill>'
              '<fill><patternFill patternType="gray125"/></fill>'
              '<fill><patternFill patternType="solid"><fgColor rgb="FF1F4E79"/><bgColor indexed="64"/></patternFill></fill></fills>'
              '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
              '<border><left style="thin"><color rgb="FFBFBFBF"/></left><right style="thin"><color rgb="FFBFBFBF"/></right>'
              '<top style="thin"><color rgb="FFBFBFBF"/></top><bottom style="thin"><color rgb="FFBFBFBF"/></bottom><diagonal/></border></borders>'
              '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
              '<cellXfs count="3">'
              '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
              '<xf numFmtId="49" fontId="1" fillId="2" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
              '<xf numFmtId="49" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'
              '</cellXfs>'
              '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
              '</styleSheet>',
      'xl/worksheets/sheet1.xml': sheet.toString(),
    };

    final archive = Archive();
    fichiers.forEach((chemin, contenu) {
      final data = utf8.encode(contenu);
      archive.addFile(ArchiveFile(chemin, data.length, data));
    });
    return ZipEncoder().encode(archive);
  }
}
