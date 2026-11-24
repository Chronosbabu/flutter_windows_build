import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:c_schollapp/services/export_excel_eleves.dart';
import 'package:flutter_test/flutter_test.dart';

String _lire(List<int> xlsx, String chemin) {
  final a = ZipDecoder().decodeBytes(xlsx);
  return utf8.decode(a.findFile(chemin)!.content as List<int>);
}

void main() {
  test("nom de feuille avec apostrophe : référence valide pour Excel", () {
    final b = ExportExcelEleves.construireXlsx([
      ['Tél', 'Nom'],
      ['0812345678', 'Kabila & <fils>'],
    ], "L'école 1ère A");
    final wb = _lire(b, 'xl/workbook.xml');
    expect(wb, contains('name="L\'école 1ère A"'));
    expect(wb, contains("'L''école 1ère A'!\$A\$1:\$B\$2"));
    final sheet = _lire(b, 'xl/worksheets/sheet1.xml');
    expect(sheet, contains('0812345678'));
    expect(sheet, contains('Kabila &amp; &lt;fils&gt;'));
  });

  test("nom de feuille : apostrophes en bord retirées, 31 caractères max", () {
    final b = ExportExcelEleves.construireXlsx([
      ['A']
    ], "'${'x' * 40}'");
    final wb = _lire(b, 'xl/workbook.xml');
    expect(wb, contains('name="${'x' * 31}"'));
  });

  test("nom de fichier nettoyé", () {
    expect(ExportExcelEleves.nomDeFichierPropre(' Liste: 1ère/A.xlsx '),
        'Liste 1èreA');
    expect(ExportExcelEleves.nomDeFichierPropre('...'), '');
  });
}
