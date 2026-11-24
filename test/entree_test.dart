import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:c_schollapp/frais_scolaires.dart';
import 'package:c_schollapp/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // addDepense/addEntree/annulerEntree appellent saveData(), qui écrit un
  // fichier local via path_provider. On simule le canal pour que ces appels
  // ne déclenchent pas de MissingPluginException dans les tests.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final String tempDir = Directory.systemTemp
      .createTempSync('schollapp_entree_test_')
      .path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return tempDir;
    }
    return null;
  });

  late FraisScolaires fs;

  setUp(() {
    fs = FraisScolaires();
    fs.config.sections = ['Primaire'];
    fs.config.administrations = [
      Administration(nom: 'Activités', pourcentage: 100),
    ];
    final eleve = Eleve(
      id: 'E1',
      nom: 'Test',
      postNom: '',
      prenom: '',
      classe: '1ère',
      section: 'Primaire',
    );
    eleve.paid['Septembre'] = 100000;
    fs.currentData.eleves.add(eleve);
  });

  test(
      "exemple du cahier des charges : rubrique Activités — dépense, retour "
          "de reliquat, don, annulation", () async {
    // Collecte après retenues (aucune retenue configurée) = 100 000 FC.
    var stats = fs.computeDepensesStats('year');
    var rub = stats.rubriqueParNom('Activités');
    expect(rub, isNotNull);
    expect(rub!.collecte, closeTo(100000, 0.01));
    expect(rub.reste, closeTo(100000, 0.01));

    // Dépense de 60 000 FC -> reste = 40 000.
    final depense = await fs.addDepense(
      motif: 'Activité sportive',
      montant: 60000,
      rubrique: 'Activités',
    );
    stats = fs.computeDepensesStats('year');
    rub = stats.rubriqueParNom('Activités');
    expect(rub!.reste, closeTo(40000, 0.01));

    // Retour de reliquat de 15 000 lié à cette dépense -> reste = 55 000.
    final erreurRetour = await fs.addEntree(
      montant: 15000,
      type: kEntreeRetourReliquat,
      justification: "Reste non utilisé de l'activité",
      rubrique: 'Activités',
      depenseLieeId: depense.id,
    );
    expect(erreurRetour, isNull);
    stats = fs.computeDepensesStats('year');
    rub = stats.rubriqueParNom('Activités');
    expect(rub!.reste, closeTo(55000, 0.01));

    // Don de 20 000 FC dans la même rubrique -> reste = 75 000.
    final erreurDon = await fs.addEntree(
      montant: 20000,
      type: kEntreeDon,
      justification: "Don d'un parent",
      rubrique: 'Activités',
    );
    expect(erreurDon, isNull);
    stats = fs.computeDepensesStats('year');
    rub = stats.rubriqueParNom('Activités');
    expect(rub!.reste, closeTo(75000, 0.01));

    // Annulation du don -> reste = 55 000.
    final don =
    fs.getEntreesForYear().firstWhere((e) => e.type == kEntreeDon);
    final erreurAnnulation =
    await fs.annulerEntree(don.id, 'Erreur de saisie');
    expect(erreurAnnulation, isNull);
    stats = fs.computeDepensesStats('year');
    rub = stats.rubriqueParNom('Activités');
    expect(rub!.reste, closeTo(55000, 0.01));

    // Le don annulé reste visible (historique) mais n'est plus compté.
    final entreesCompletes = fs.getEntreesForYear();
    expect(entreesCompletes.length, 2);
    expect(
        entreesCompletes.firstWhere((e) => e.type == kEntreeDon).annulee,
        isTrue);

    // Les pourcentages des administrations n'ont pas bougé.
    expect(fs.config.administrations.first.pourcentage, 100);
  });

  test(
      'plafond du reliquat : blocage strict si le retour dépasse la dépense '
          'd\'origine (moins les retours déjà enregistrés)', () async {
    final depense = await fs.addDepense(
        motif: 'Achat matériel', montant: 60000, rubrique: 'Activités');

    final erreurTropGrand = await fs.addEntree(
      montant: 60001,
      type: kEntreeRetourReliquat,
      justification: 'Tentative de dépassement',
      rubrique: 'Activités',
      depenseLieeId: depense.id,
    );
    expect(erreurTropGrand, isNotNull);
    expect(fs.getEntreesForYear(), isEmpty);

    // Un premier retour partiel passe...
    final erreur1 = await fs.addEntree(
      montant: 40000,
      type: kEntreeRetourReliquat,
      justification: 'Premier retour',
      rubrique: 'Activités',
      depenseLieeId: depense.id,
    );
    expect(erreur1, isNull);

    // ... mais un second qui dépasserait le reliquat restant (20 000) est
    // refusé.
    final erreur2 = await fs.addEntree(
      montant: 20001,
      type: kEntreeRetourReliquat,
      justification: 'Second retour en trop',
      rubrique: 'Activités',
      depenseLieeId: depense.id,
    );
    expect(erreur2, isNotNull);

    // Alors qu'exactement le reliquat restant est accepté.
    final erreur3 = await fs.addEntree(
      montant: 20000,
      type: kEntreeRetourReliquat,
      justification: 'Solde du reliquat',
      rubrique: 'Activités',
      depenseLieeId: depense.id,
    );
    expect(erreur3, isNull);
  });

  test("une entrée annulée n'est plus comptée dans les totaux", () async {
    await fs.addEntree(
        montant: 10000,
        type: kEntreeDon,
        justification: 'Don',
        rubrique: 'Activités');
    expect(fs.getTotalEntrees(), closeTo(10000, 0.01));

    final entree = fs.getEntreesForYear().first;
    final erreur = await fs.annulerEntree(entree.id, 'Erreur de saisie');
    expect(erreur, isNull);

    expect(fs.getTotalEntrees(), closeTo(0, 0.01));
    expect(fs.getEntreesForYear().length, 1);
    expect(fs.getEntreesForYear().first.annulee, isTrue);
  });

  test('la justification est obligatoire', () async {
    final erreur = await fs.addEntree(
      montant: 1000,
      type: kEntreeDon,
      justification: '   ',
      rubrique: 'Activités',
    );
    expect(erreur, isNotNull);
    expect(fs.getEntreesForYear(), isEmpty);
  });

  test('le montant doit être strictement positif', () async {
    final erreurZero = await fs.addEntree(
        montant: 0,
        type: kEntreeDon,
        justification: 'x',
        rubrique: 'Activités');
    expect(erreurZero, isNotNull);

    final erreurNegatif = await fs.addEntree(
        montant: -5,
        type: kEntreeDon,
        justification: 'x',
        rubrique: 'Activités');
    expect(erreurNegatif, isNotNull);

    expect(fs.getEntreesForYear(), isEmpty);
  });

  test('la rubrique est obligatoire', () async {
    final erreur = await fs.addEntree(
      montant: 1000,
      type: kEntreeDon,
      justification: 'x',
      rubrique: '',
    );
    expect(erreur, isNotNull);
  });

  test("annuler une entrée sans motif est refusé", () async {
    await fs.addEntree(
        montant: 5000,
        type: kEntreeDon,
        justification: 'Don',
        rubrique: 'Activités');
    final entree = fs.getEntreesForYear().first;
    final erreur = await fs.annulerEntree(entree.id, '');
    expect(erreur, isNotNull);
    expect(fs.getEntreesForYear().first.annulee, isFalse);
  });

  test('getSoldeDisponibleRubrique inclut les entrées actives', () async {
    final soldeAvant = fs.getSoldeDisponibleRubrique(
        rubrique: 'Activités', portee: kDepenseGlobale);
    expect(soldeAvant, closeTo(100000, 0.01));

    await fs.addEntree(
        montant: 5000,
        type: kEntreeSubvention,
        justification: 'Subvention',
        rubrique: 'Activités');

    final soldeApres = fs.getSoldeDisponibleRubrique(
        rubrique: 'Activités', portee: kDepenseGlobale);
    expect(soldeApres, closeTo(105000, 0.01));
  });
}
