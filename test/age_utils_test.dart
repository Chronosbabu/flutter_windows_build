import 'package:flutter_test/flutter_test.dart';
import 'package:c_schollapp/utils/age_utils.dart';

void main() {
  group('AgeUtils.prochainAnniversaire', () {
    test("exemple du cahier des charges : né le 15/03/2014, vu le "
        "23/11/2026 à 12h00", () {
      final reference = DateTime(2026, 11, 23, 12, 0, 0);
      final info =
      AgeUtils.prochainAnniversaire('15/03/2014', reference: reference);

      expect(info, isNotNull);
      expect(info!.ageActuel, 12);
      expect(info.ageProchain, 13);
      expect(info.estAujourdHui, isFalse);
      expect(info.mois, 3);
      expect(info.jours, 20);
      expect(info.heures, 12);
      expect(info.minutes, 0);
      expect(info.secondes, 0);

      final libelle =
      AgeUtils.libelleProchainAnniversaire('15/03/2014', reference: reference);
      expect(libelle, "Aura 13 ans dans 3 mois, 20 jours, 12 h 0 min 0 s");
    });

    test('anniversaire aujourd\'hui', () {
      final reference = DateTime(2026, 11, 23, 14, 30, 0);
      final info =
      AgeUtils.prochainAnniversaire('23/11/2014', reference: reference);

      expect(info, isNotNull);
      expect(info!.estAujourdHui, isTrue);
      expect(info.ageActuel, 12);

      final libelle =
      AgeUtils.libelleProchainAnniversaire('23/11/2014', reference: reference);
      expect(libelle, "Anniversaire aujourd'hui !");
    });

    test('naissance le 29 février : anniversaire observé le 1er mars '
        'les années non bissextiles', () {
      // 2023 n'est pas bissextile.
      final veille = DateTime(2023, 2, 28, 10, 0, 0);
      final infoVeille =
      AgeUtils.prochainAnniversaire('29/02/2000', reference: veille);
      expect(infoVeille, isNotNull);
      expect(infoVeille!.estAujourdHui, isFalse);
      expect(infoVeille.dateProchainAnniversaire, DateTime(2023, 3, 1));

      final jourJ = DateTime(2023, 3, 1, 9, 0, 0);
      final infoJourJ =
      AgeUtils.prochainAnniversaire('29/02/2000', reference: jourJ);
      expect(infoJourJ, isNotNull);
      expect(infoJourJ!.estAujourdHui, isTrue);
      expect(infoJourJ.ageActuel, 23);
    });

    test('naissance le 29 février sur une année bissextine : anniversaire '
        'reste le 29 février', () {
      // 2024 est bissextile.
      final reference = DateTime(2024, 2, 29, 8, 0, 0);
      final info =
      AgeUtils.prochainAnniversaire('29/02/2000', reference: reference);
      expect(info, isNotNull);
      expect(info!.estAujourdHui, isTrue);
    });

    test('mois de longueurs différentes : décomposition calendaire exacte '
        '(pas une approximation de 30 jours)', () {
      // Né le 31 janvier, vu le 1er janvier -> anniversaire dans 30 jours
      // (janvier a 31 jours), ni 1 mois tout rond ni 30 jours fixes partout.
      final reference = DateTime(2026, 1, 1, 0, 0, 0);
      final info =
      AgeUtils.prochainAnniversaire('31/01/2010', reference: reference);
      expect(info, isNotNull);
      expect(info!.mois, 0);
      expect(info.jours, 30);
    });

    test('date de naissance vide -> null', () {
      expect(AgeUtils.prochainAnniversaire(''), isNull);
      expect(AgeUtils.libelleProchainAnniversaire(''), '');
    });

    test('date de naissance invalide -> null, sans exception', () {
      expect(AgeUtils.prochainAnniversaire('pas une date'), isNull);
      expect(AgeUtils.prochainAnniversaire('32/13/2020'), isNull);
      expect(AgeUtils.libelleProchainAnniversaire('pas une date'), '');
    });

    test('date de naissance dans le futur -> null', () {
      final reference = DateTime(2026, 11, 23);
      final info = AgeUtils.prochainAnniversaire('01/01/2099',
          reference: reference);
      expect(info, isNull);
    });
  });

  group('AgeUtils.libelleAnniversaireProche', () {
    test('affiche le compte en jours si dans le seuil (30 jours par défaut)',
            () {
          final reference = DateTime(2026, 11, 23);
          // Anniversaire dans 10 jours.
          final libelle = AgeUtils.libelleAnniversaireProche('03/12/2015',
              reference: reference);
          expect(libelle, 'Anniversaire dans 10 jours');
        });

    test("n'affiche rien si l'anniversaire est au-delà du seuil", () {
      final reference = DateTime(2026, 11, 23);
      // Anniversaire dans ~6 mois.
      final libelle = AgeUtils.libelleAnniversaireProche('15/05/2015',
          reference: reference);
      expect(libelle, '');
    });

    test("aujourd'hui -> message court sans compte en jours", () {
      final reference = DateTime(2026, 11, 23, 9, 0, 0);
      final libelle = AgeUtils.libelleAnniversaireProche('23/11/2015',
          reference: reference);
      expect(libelle, "Anniversaire aujourd'hui");
    });
  });
}
