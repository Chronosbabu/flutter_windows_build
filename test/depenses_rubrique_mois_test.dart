import 'package:flutter_test/flutter_test.dart';
import 'package:c_schollapp/frais_scolaires.dart';
import 'package:c_schollapp/models.dart';

void main() {
  test('dépenses par rubrique et par mois (mois d\'imputation, section)', () {
    final fs = FraisScolaires();
    fs.config.sections = ['Primaire', 'Secondaire'];
    fs.config.administrations = [
      Administration(nom: 'Fonctionnement', pourcentage: 60),
      Administration(nom: 'Construction', pourcentage: 40),
    ];
    final annee = fs.currentYear;
    final debut = int.parse(annee.split('-').first);
    fs.depensesByYear[annee] = [
      // Payée en novembre mais imputée à Octobre.
      Depense(
          id: 'D1',
          motif: 'Craies',
          montant: 10000,
          date: DateTime(debut, 11, 3),
          rubrique: 'Fonctionnement',
          moisImputation: 'Octobre'),
      Depense(
          id: 'D2',
          motif: 'Ciment',
          montant: 50000,
          date: DateTime(debut, 11, 10),
          rubrique: 'Construction'),
      Depense(
          id: 'D3',
          motif: 'Cahiers primaire',
          montant: 8000,
          date: DateTime(debut, 10, 5),
          rubrique: 'Fonctionnement',
          portee: kDepenseIndependante,
          sections: ['Primaire']),
    ];

    final oct = fs.depensesStatsPourMois('Octobre');
    expect(oct.rubriqueParNom('Fonctionnement')!.total, 18000);
    expect(oct.rubriqueParNom('Construction')!.total, 0);

    final nov = fs.depensesStatsPourMois('Novembre');
    expect(nov.rubriqueParNom('Construction')!.total, 50000);
    expect(nov.rubriqueParNom('Fonctionnement')!.total, 0);

    // Filtre section : les dépenses globales ne comptent pas.
    final octPrim =
        fs.depensesStatsPourMois('Octobre', sectionFilter: 'Primaire');
    expect(octPrim.rubriqueParNom('Fonctionnement')!.total, 8000);
    expect(fs.montantDepensePourFiltre(
        fs.depensesByYear[annee]![0], 'Primaire'), 0);

    final an = fs.depensesStatsAnnee();
    expect(an.totalDepenses, 68000);
  });
}
