// Formulaire unique « Écrire aux parents » (aucun envoi réseau ici).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:c_schollapp/frais_scolaires.dart';
import 'package:c_schollapp/models.dart';
import 'package:c_schollapp/screens/messagerie_screen.dart';

FraisScolaires _ecole() {
  final fs = FraisScolaires();
  fs.currentData.eleves.addAll([
    Eleve(
        id: 'E1',
        nom: 'Kabila',
        postNom: 'Mutombo',
        prenom: 'Jean',
        classe: '1ère A',
        section: 'Primaire'),
    Eleve(
        id: 'E2',
        nom: 'Mbuyi',
        postNom: 'Ilunga',
        prenom: 'Marie',
        classe: '2ème A',
        section: 'Primaire'),
  ]);
  return fs;
}

ElevatedButton _boutonEnvoyer(WidgetTester t) => t.widget<ElevatedButton>(
    find.ancestor(
        of: find.byIcon(Icons.send),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton)));

void main() {
  Future<void> ouvrir(WidgetTester t, Widget ecran) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: ecran));
    await t.pumpAndSettle();
  }

  testWidgets('étapes : élève, message, bouton Envoyer', (t) async {
    await ouvrir(t, EcrireAuxParentsScreen(fraisScolaires: _ecole()));

    expect(find.text("Choisissez d'abord à qui écrire (étape 1)."),
        findsOneWidget);
    expect(_boutonEnvoyer(t).onPressed, isNull);

    await t.tap(find.text('Un ou des élèves'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, "Tapez le nom de l'élève"),
        'kab');
    await t.pumpAndSettle();
    await t.tap(find.text('Kabila Mutombo Jean'));
    await t.pumpAndSettle();
    expect(find.text('Kabila Mutombo Jean (1ère A)'), findsOneWidget);
    expect(find.text('→ 1 parent recevra le message.'), findsOneWidget);

    // Pas de texte : on ne peut pas envoyer.
    expect(_boutonEnvoyer(t).onPressed, isNull);
    await t.tap(find.text('Élève malade'));
    await t.pumpAndSettle();
    expect(_boutonEnvoyer(t).onPressed, isNotNull);
    expect(find.text('Envoyer'), findsOneWidget);
  });

  testWidgets("toute l'école : communiqué seulement", (t) async {
    await ouvrir(t, EcrireAuxParentsScreen(fraisScolaires: _ecole()));
    await t.tap(find.text("Toute l'école"));
    await t.pumpAndSettle();
    expect(find.text('Pour un élève précis'), findsOneWidget);
    expect(find.text('Pour des élèves ou une classe'), findsOneWidget);
    await t.tap(find.text('Réunion des parents'));
    await t.pumpAndSettle();
    expect(find.text('Envoyer à 2 parents'), findsOneWidget);
  });

  testWidgets('« Convoquer » depuis le registre : déjà rempli', (t) async {
    final fs = _ecole();
    await ouvrir(
        t,
        EcrireAuxParentsScreen(
          fraisScolaires: fs,
          eleveInitial: fs.currentData.eleves.first,
          genreInitial: GenreMessage.convocation,
        ));
    expect(find.text('Kabila Mutombo Jean (1ère A)'), findsOneWidget);
    expect(find.textContaining('comportement de votre'), findsOneWidget);
    expect(_boutonEnvoyer(t).onPressed, isNotNull);
  });

  test('erreurs lisibles', () {
    expect(erreurLisible('Aucune connexion réseau : SocketException'),
        "Pas de connexion internet.");
    expect(erreurLisible('Statut 404 : {"error": "Élève introuvable"}'),
        contains('sauvegarde'));
  });
}
