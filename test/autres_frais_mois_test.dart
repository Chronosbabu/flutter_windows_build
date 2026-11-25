import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:c_schollapp/frais_scolaires.dart';
import 'package:c_schollapp/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final String tempDir =
      Directory.systemTemp.createTempSync('schollapp_af_mois_test_').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') return tempDir;
    return null;
  });

  late FraisScolaires fs;
  late AutreFrais frais;
  late Eleve e1, e2, e3;

  Eleve eleve(String id, String classe) => Eleve(
        id: id,
        nom: 'Eleve$id',
        postNom: '',
        prenom: '',
        classe: classe,
        section: 'Primaire',
      );

  setUp(() {
    fs = FraisScolaires();
    fs.config.sections = ['Primaire'];
    e1 = eleve('E1', '1ère');
    e2 = eleve('E2', '1ère');
    e3 = eleve('E3', '2ème');
    fs.currentData.eleves.addAll([e1, e2, e3]);
    frais = AutreFrais(id: 'F1', nom: 'Transport', montant: 15000);
    fs.autresFrais.add(frais);
  });

  test('mois ajoutés dans l\'ordre, payés dans l\'ordre, liste par mois',
      () async {
    final cle = fs.cleTranchePourCible(section: 'Primaire');
    final n = await fs.addMoisPourAutreFrais(
      autreFraisId: 'F1',
      cle: cle,
      mois: ['Novembre', 'Octobre', 'Décembre'],
      montantParMois: 5000,
    );
    expect(n, 3);
    expect(fs.cleEstParMois(frais, cle), isTrue);
    expect(fs.getTranchesPourEleve(frais, e1).map((t) => t.mois),
        ['Novembre', 'Octobre', 'Décembre']);
    // Liste des mois du frais triée selon l'année scolaire.
    expect(fs.moisDefinisAutreFrais(frais),
        ['Octobre', 'Novembre', 'Décembre']);

    // Doublon ignoré.
    expect(
        await fs.addMoisPourAutreFrais(
            autreFraisId: 'F1', cle: cle, mois: ['novembre'], montantParMois: 1),
        0);

    // Changement d'ordre : Octobre devient le 1er mois.
    final idOct =
        frais.tranchesParCle[cle]!.firstWhere((t) => t.mois == 'Octobre').id;
    expect(
        await fs.deplacerTranchePourAutreFrais(
            autreFraisId: 'F1', cle: cle, trancheId: idOct, delta: -1),
        isTrue);

    final p = await fs.payAutreFrais(frais: frais, eleve: e1);
    expect(p.trancheNom, 'Octobre');
    expect(p.montant, 5000);

    var rec = fs.recouvrementAutreFraisParMois(frais, 'Octobre');
    expect(rec.payes.map((l) => l.eleve.id), ['E1']);
    expect(rec.nonPayes.map((l) => l.eleve.id).toSet(), {'E2', 'E3'});
    rec = fs.recouvrementAutreFraisParMois(frais, 'Novembre');
    expect(rec.payes, isEmpty);

    // Ordre bloqué dès qu'un paiement existe.
    expect(
        await fs.deplacerTranchePourAutreFrais(
            autreFraisId: 'F1', cle: cle, trancheId: idOct, delta: 1),
        isFalse);

    // Persistance JSON du champ mois.
    final copie = AutreFrais.fromJson(frais.toJson());
    expect(copie.tranchesParCle[cle]!.first.mois, 'Octobre');
  });

  test('copier les mois vers une classe ; la classe passe avant la section',
      () async {
    final cleSec = fs.cleTranchePourCible(section: 'Primaire');
    await fs.addMoisPourAutreFrais(
        autreFraisId: 'F1',
        cle: cleSec,
        mois: ['Septembre', 'Octobre'],
        montantParMois: 7500);
    final cleC2 = fs.cleTranchePourCible(
        section: 'Primaire', classeNumero: fs.classeNumeroFromFullClasse('2ème'));
    final cleC1 = fs.cleTranchePourCible(
        section: 'Primaire', classeNumero: fs.classeNumeroFromFullClasse('1ère'));
    await fs.addMoisPourAutreFrais(
        autreFraisId: 'F1', cle: cleC1, mois: ['Mars'], montantParMois: 15000);
    final res = await fs.copierTranchesVersCibles(
        autreFraisId: 'F1', cleSource: cleC1, clesCibles: [cleC2]);
    expect(res.copiees, 1);
    expect(fs.getTranchesPourEleve(frais, e3).map((t) => t.mois), ['Mars']);
    // Septembre ne concerne plus personne (les deux classes paient Mars).
    final rec = fs.recouvrementAutreFraisParMois(frais, 'Septembre');
    expect(rec.payes.length + rec.nonPayes.length, 0);
  });

  test('refus d\'ajouter des mois sur une cible à tranches classiques',
      () async {
    await fs.addTranchePourAutreFrais(
        autreFraisId: 'F1',
        cle: FraisScolaires.kTrancheCleTous,
        nom: 'Première tranche',
        montant: 5000);
    expect(
        () => fs.addMoisPourAutreFrais(
            autreFraisId: 'F1',
            cle: FraisScolaires.kTrancheCleTous,
            mois: ['Mai'],
            montantParMois: 100),
        throwsException);
  });
}
