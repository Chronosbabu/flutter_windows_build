// Écrans de protection de la synchronisation (étape 5d).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:c_schollapp/frais_scolaires.dart';
import 'package:c_schollapp/models.dart';
import 'package:c_schollapp/screens/sync_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory.systemTemp.createTempSync('sync_ui_').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => dir);

  Map<String, num> r(num e, num a) => {
    'eleves': e,
    'transactions': 1,
    'argent': a,
    'paiements_autres_frais': 0,
    'argent_autres_frais': 0,
  };

  Future<void> ouvrir(WidgetTester t, FraisScolaires fs,
      Map<String, dynamic> result) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => afficherResumeSync(ctx, fs, result),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
  }

  testWidgets('fenêtre BLOQUANTE : chiffres, anomalie, deux choix',
      (t) async {
    final fs = FraisScolaires();
    await ouvrir(t, fs, {
      'success': false,
      'code': 'ANOMALIE_FUSION',
      'bloquant': true,
      'resume': {
        'avant': r(5, 10000),
        'serveur': r(5, 3000),
        'apres': r(6, 16000)
      },
      'anomalies': [
        {'niveau': 'bloquant', 'message': 'Hausse inexpliquée du test'}
      ],
    });
    expect(find.text('Chiffres anormaux — vérifiez avant de continuer'),
        findsOneWidget);
    expect(find.text('16 000 FC'), findsOneWidget);
    expect(find.text('Hausse inexpliquée du test'), findsOneWidget);
    expect(find.textContaining("RIEN n'a été envoyé"), findsOneWidget);
    expect(find.text('Annuler la récupération'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
    // Un clic hors de la fenêtre ne la ferme pas.
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.text('Annuler la récupération'), findsOneWidget);
    await t.tap(find.text('Garder (je vérifie)'));
    await t.pumpAndSettle();
    expect(find.text('Annuler la récupération'), findsNothing);
  });

  testWidgets('fenêtre simple : résumé + « autre ordinateur »', (t) async {
    final fs = FraisScolaires();
    await ouvrir(t, fs, {
      'success': true,
      'autreOrdinateur': true,
      'resume': {
        'avant': r(4, 1000),
        'serveur': r(4, 4000),
        'apres': r(4, 5000)
      },
      'anomalies': [],
    });
    expect(find.text('Résumé de la récupération'), findsOneWidget);
    expect(find.textContaining('Un autre ordinateur avait sauvegardé'),
        findsOneWidget);
    expect(find.text('5 000 FC'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Résumé de la récupération'), findsNothing);
  });

  testWidgets('aucun résumé : rien ne s\'affiche', (t) async {
    await ouvrir(t, FraisScolaires(), {'success': true});
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('écran des doublons : fiche vide proposée à l\'archivage',
      (t) async {
    final fs = FraisScolaires();
    fs.config.feesBySection['Primaire'] = 10000;
    final e = Eleve(
        id: 'A1', nom: 'KABILA', postNom: 'P', prenom: 'J',
        classe: '1ère', section: 'Primaire');
    fs.handlePayment(e, 'Septembre', 2000);
    fs.currentData.eleves
      ..add(e)
      ..add(Eleve(
          id: 'A2', nom: 'KABILA', postNom: 'P', prenom: 'J',
          classe: '1ère', section: 'Primaire'));
    await t.pumpWidget(MaterialApp(home: DoublonsScreen(fraisScolaires: fs)));
    expect(find.textContaining('KABILA P J — 2 fiches'), findsOneWidget);
    expect(find.text('Archiver les 1 fiche(s) vide(s) en double'),
        findsOneWidget);
    expect(find.textContaining('fiche vide, sera archivée'), findsOneWidget);
  });
}
