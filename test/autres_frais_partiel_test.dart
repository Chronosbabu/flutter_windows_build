import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:c_schollapp/frais_scolaires.dart';
import 'package:c_schollapp/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // payAutreFrais / annuler / modifier appellent saveData(), qui écrit un
  // fichier local via path_provider : on simule le canal.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final String tempDir = Directory.systemTemp
      .createTempSync('schollapp_autres_frais_test_')
      .path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') return tempDir;
    return null;
  });

  late FraisScolaires fs;
  late Eleve eleve;
  late AutreFrais frais;

  Eleve nouvelEleve(String id) => Eleve(
    id: id,
    nom: 'Eleve$id',
    postNom: '',
    prenom: '',
    classe: '1ère',
    section: 'Primaire',
  );

  setUp(() {
    fs = FraisScolaires();
    fs.config.sections = ['Primaire'];
    eleve = nouvelEleve('E1');
    fs.currentData.eleves.add(eleve);
    frais = AutreFrais(
      id: 'F1',
      nom: "Frais de l'État",
      montant: 30000,
      tranchesParCle: {
        FraisScolaires.kTrancheCleTous: [
          AutreFraisTranche(id: 'T1', nom: 'Première tranche', montant: 10000),
          AutreFraisTranche(id: 'T2', nom: 'Deuxième tranche', montant: 10000),
          AutreFraisTranche(id: 'T3', nom: 'Troisième tranche', montant: 10000),
        ],
      },
    );
    fs.autresFrais.add(frais);
  });

  List<AutreFraisEtatTranche> etats() => fs
      .getStatutAutreFrais(frais, eleve)
      .etatsTranches
      .map((e) => e.etat)
      .toList();

  // Les paiements créés dans le même instant doivent rester ordonnés.
  Future<AutreFraisPaiement> payer(double? montant) async {
    final p = await fs.payAutreFrais(
        frais: frais, eleve: eleve, montantSaisi: montant);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return p;
  }

  test("exemple du cahier des charges : 3 tranches de 10 000 FC", () async {
    // 4 000 : tranche 1 partielle.
    final p1 = await payer(4000);
    var st = fs.getStatutAutreFrais(frais, eleve);
    expect(st.totalPaye, closeTo(4000, 0.01));
    expect(st.reste, closeTo(26000, 0.01));
    expect(etats(), [
      AutreFraisEtatTranche.partielle,
      AutreFraisEtatTranche.nonPayee,
      AutreFraisEtatTranche.nonPayee,
    ]);
    expect(st.etatsTranches[0].verse, closeTo(4000, 0.01));
    expect(st.etatsTranches[0].reste, closeTo(6000, 0.01));
    expect(p1.trancheId, 'T1');
    expect(st.partiel, isTrue);

    var rec = fs.recouvrementAutreFrais(frais, 2);
    expect(rec.nonPayes.single.reste, closeTo(10000, 0.01));
    expect(rec.payes, isEmpty);

    // 6 000 : tranche 1 payée.
    final p2 = await payer(6000);
    st = fs.getStatutAutreFrais(frais, eleve);
    expect(st.totalPaye, closeTo(10000, 0.01));
    expect(st.nbPayees, 1);
    expect(etats().first, AutreFraisEtatTranche.payee);
    expect(p2.trancheId, 'T1');

    // 15 000 : tranche 2 payée, tranche 3 partielle (5 000).
    final p3 = await payer(15000);
    st = fs.getStatutAutreFrais(frais, eleve);
    expect(st.totalPaye, closeTo(25000, 0.01));
    expect(st.reste, closeTo(5000, 0.01));
    expect(etats(), [
      AutreFraisEtatTranche.payee,
      AutreFraisEtatTranche.payee,
      AutreFraisEtatTranche.partielle,
    ]);
    expect(st.etatsTranches[2].verse, closeTo(5000, 0.01));
    expect(p3.trancheId, 'T2');
    rec = fs.recouvrementAutreFrais(frais, 2);
    expect(rec.nonPayes, isEmpty);
    expect(rec.payes.single.montantPaye, closeTo(10000, 0.01));

    // Reçu du paiement de 15 000 : cumul 25 000, reste 5 000.
    final sit = fs.situationApresPaiementAutreFrais(frais, eleve, p3);
    expect(sit['cumulPaye'], closeTo(25000, 0.01));
    expect(sit['resteAPayer'], closeTo(5000, 0.01));
    expect(sit['tranchesCouvertes'] as String, contains('Deuxième tranche'));
    expect(sit['tranchesCouvertes'] as String, contains('Troisième tranche'));

    // 6 000 : refusé (maximum 5 000).
    await expectLater(
      payer(6000),
      throwsA(predicate((e) => e.toString().contains('5000 FC'))),
    );
    expect(fs.getStatutAutreFrais(frais, eleve).totalPaye,
        closeTo(25000, 0.01));

    // 5 000 : tout soldé, plus aucun paiement possible.
    await payer(5000);
    st = fs.getStatutAutreFrais(frais, eleve);
    expect(st.solde, isTrue);
    expect(st.reste, 0);
    await expectLater(payer(1000), throwsA(isA<Exception>()));
    await expectLater(payer(null), throwsA(isA<Exception>()));

    // Annulation du paiement de 15 000 : cumul 15 000 -> tranche 2 partielle
    // à 5 000 (les 5 000 du dernier paiement passent sur la tranche 2).
    await fs.annulerPaiementAutreFrais(paiement: p3, eleve: eleve);
    st = fs.getStatutAutreFrais(frais, eleve);
    expect(st.totalPaye, closeTo(15000, 0.01));
    expect(st.nbPayees, 1);
    expect(etats()[1], AutreFraisEtatTranche.partielle);
    expect(st.solde, isFalse);
    // Le dernier paiement (5 000) est maintenant rattaché à la tranche 2.
    final restants = fs.paiementsOrdonnesAutreFrais(eleve, frais);
    expect(restants.map((p) => p.trancheId).toList(), ['T1', 'T1', 'T2']);
    rec = fs.recouvrementAutreFrais(frais, 2);
    expect(rec.nonPayes.single.reste, closeTo(5000, 0.01));
    expect(rec.nonPayes.single.partiel, isTrue);
  });

  test("annulation du 15 000 avant le paiement final : cumul 10 000",
      () async {
    await payer(4000);
    await payer(6000);
    final p3 = await payer(15000);
    await fs.annulerPaiementAutreFrais(paiement: p3, eleve: eleve);
    final st = fs.getStatutAutreFrais(frais, eleve);
    expect(st.totalPaye, closeTo(10000, 0.01));
    expect(etats(), [
      AutreFraisEtatTranche.payee,
      AutreFraisEtatTranche.nonPayee,
      AutreFraisEtatTranche.nonPayee,
    ]);
    final rec = fs.recouvrementAutreFrais(frais, 2);
    expect(rec.nonPayes.single.reste, closeTo(10000, 0.01));
    expect(rec.nonPayes.single.partiel, isFalse);
  });

  test("garde-fous : montant nul ou négatif refusé", () async {
    await expectLater(payer(0), throwsA(isA<Exception>()));
    await expectLater(payer(-100), throwsA(isA<Exception>()));
    expect(fs.getPaiementsEleveAutreFrais(eleve, frais), isEmpty);
  });

  test("bouton tranche entière après un partiel : complète la tranche",
      () async {
    await payer(4000);
    final p = await payer(null);
    expect(p.montant, closeTo(6000, 0.01));
    expect(fs.getStatutAutreFrais(frais, eleve).nbPayees, 1);
  });

  test("modification : plafond et cohérence des tranches", () async {
    final p1 = await payer(10000);
    await payer(10000);
    await expectLater(
      fs.modifierMontantPaiementAutreFrais(
          paiement: p1, eleve: eleve, newMontant: 25000),
      throwsA(predicate((e) => e.toString().contains('20000 FC'))),
    );
    await fs.modifierMontantPaiementAutreFrais(
        paiement: p1, eleve: eleve, newMontant: 4000);
    final st = fs.getStatutAutreFrais(frais, eleve);
    expect(st.totalPaye, closeTo(14000, 0.01));
    expect(etats(), [
      AutreFraisEtatTranche.payee,
      AutreFraisEtatTranche.partielle,
      AutreFraisEtatTranche.nonPayee,
    ]);
    // Le 2e paiement commence dans la tranche 1 (cumul avant = 4 000).
    expect(fs.paiementsOrdonnesAutreFrais(eleve, frais).last.trancheId, 'T1');
  });

  group("frais sans tranches", () {
    late AutreFrais simple;
    setUp(() {
      simple = AutreFrais(id: 'F2', nom: 'Tenue', montant: 12000);
      fs.autresFrais.add(simple);
    });

    test("ancien paiement (montant plein, sans tranche) : soldé comme avant",
        () {
      // Ancien paiement chargé depuis une sauvegarde (pas de champ
      // saisieLibre), même si le montant du frais a changé depuis.
      final ancien = AutreFraisPaiement.fromJson({
        'id': 'OLD1',
        'autreFraisId': 'F2',
        'autreFraisNom': 'Tenue',
        'eleveId': 'E1',
        'montant': 10000,
        'date': '2025-10-01T10:00:00.000',
      });
      expect(ancien.saisieLibre, isFalse);
      expect(ancien.toJson().containsKey('saisieLibre'), isFalse);
      fs.autresFraisPaiementsByYear[fs.currentYear] = [ancien];
      final st = fs.getStatutAutreFrais(simple, eleve);
      expect(st.solde, isTrue);
      expect(st.reste, 0);
      expect(st.partiel, isFalse);
    });

    test("paiement partiel cumulé jusqu'au montant du frais", () async {
      final p1 = await fs.payAutreFrais(
          frais: simple, eleve: eleve, montantSaisi: 5000);
      expect(p1.saisieLibre, isTrue);
      expect(p1.toJson()['saisieLibre'], isTrue);
      expect(AutreFraisPaiement.fromJson(p1.toJson()).saisieLibre, isTrue);
      var st = fs.getStatutAutreFrais(simple, eleve);
      expect(st.partiel, isTrue);
      expect(st.reste, closeTo(7000, 0.01));

      var rec = fs.recouvrementAutreFrais(simple, 0);
      expect(rec.nonPayes.single.montantPaye, closeTo(5000, 0.01));
      expect(rec.nonPayes.single.reste, closeTo(7000, 0.01));

      await expectLater(
        fs.payAutreFrais(frais: simple, eleve: eleve, montantSaisi: 8000),
        throwsA(predicate((e) => e.toString().contains('7000 FC'))),
      );

      // Bouton "payer en entier" : paie le reste, et compte au cumul.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final p2 = await fs.payAutreFrais(frais: simple, eleve: eleve);
      expect(p2.montant, closeTo(7000, 0.01));
      expect(p2.saisieLibre, isTrue);
      st = fs.getStatutAutreFrais(simple, eleve);
      expect(st.solde, isTrue);

      // Annuler le premier paiement : 7 000 / 12 000 -> partiel, pas soldé.
      await fs.annulerPaiementAutreFrais(paiement: p1, eleve: eleve);
      st = fs.getStatutAutreFrais(simple, eleve);
      expect(st.solde, isFalse);
      expect(st.reste, closeTo(5000, 0.01));
      rec = fs.recouvrementAutreFrais(simple, 0);
      expect(rec.nonPayes.single.reste, closeTo(5000, 0.01));
    });

    test("paiement plein classique : identique à avant", () async {
      final p = await fs.payAutreFrais(frais: simple, eleve: eleve);
      expect(p.montant, closeTo(12000, 0.01));
      expect(p.saisieLibre, isFalse);
      expect(fs.getStatutAutreFrais(simple, eleve).solde, isTrue);
    });

    test("modification d'un ancien paiement : compte au cumul, plafonné",
        () async {
      final p = await fs.payAutreFrais(frais: simple, eleve: eleve);
      await expectLater(
        fs.modifierMontantPaiementAutreFrais(
            paiement: p, eleve: eleve, newMontant: 13000),
        throwsA(isA<Exception>()),
      );
      await fs.modifierMontantPaiementAutreFrais(
          paiement: p, eleve: eleve, newMontant: 2000);
      final st = fs.getStatutAutreFrais(simple, eleve);
      expect(st.solde, isFalse);
      expect(st.reste, closeTo(10000, 0.01));
    });
  });

  test("ventilation : un paiement sur plusieurs tranches", () {
    final tranches = fs.getTranchesPourEleve(frais, eleve);
    AutreFraisPaiement p(String id, double m) => AutreFraisPaiement(
        id: id,
        autreFraisId: 'F1',
        autreFraisNom: '',
        eleveId: 'E1',
        montant: m,
        date: DateTime(2025));
    final v = FraisScolaires.ventilerPaiementsAutreFrais(
        tranches, [p('a', 4000), p('b', 6000), p('c', 15000)]);
    expect(v[0], {0: 4000.0});
    expect(v[1], {0: 6000.0});
    expect(v[2], {1: 10000.0, 2: 5000.0});
  });

  test("recouvrement : filtre par classe", () async {
    final e2 = nouvelEleve('E2')..classe = '2ème';
    fs.currentData.eleves.add(e2);
    await payer(20000);
    final tous = fs.recouvrementAutreFrais(frais, 2);
    expect(tous.payes.map((l) => l.eleve.id), ['E1']);
    expect(tous.nonPayes.map((l) => l.eleve.id), ['E2']);
    final c2 = fs.recouvrementAutreFrais(frais, 2, classe: '2ème');
    expect(c2.payes, isEmpty);
    expect(c2.nonPayes.single.reste, closeTo(10000, 0.01));
  });
}
