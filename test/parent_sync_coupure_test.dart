// Étape 1 de la correction de la synchronisation : l'envoi automatique des
// paiements (ParentSyncService -> /school/sync_student_payments) est coupé.
// Aucun appel réseau réel : un faux client HTTP compte les requêtes.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:c_schollapp/frais_scolaires.dart';
import 'package:c_schollapp/models.dart';
import 'package:c_schollapp/services/parent_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final String dir =
      Directory.systemTemp.createTempSync('parent_sync_coupure_').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async => dir);

  test("l'envoi automatique est coupé : aucune requête, file effacée",
      () async {
    expect(ParentSyncService.envoiAutomatiqueActif, isFalse);

    // Une ancienne file d'attente (version précédente de l'application).
    SharedPreferences.setMockInitialValues({
      'parent_sync_queue_v1': '{"E1":3}',
      'parent_sync_fp_v1': '{"E1":"Septembre=1000.00;#1#1000.00"}',
    });

    final fs = FraisScolaires()..schoolCode = 'TESTECOLE';
    final e = Eleve(
        id: 'E1',
        nom: 'KABILA',
        postNom: '',
        prenom: '',
        classe: '1ère',
        section: 'Primaire');
    fs.currentData.eleves.add(e);
    fs.config.feesBySection['Primaire'] = 10000;

    final requetes = <http.Request>[];
    final client = MockClient((req) async {
      requetes.add(req);
      return http.Response('{"done":["E1"]}', 200);
    });

    await http.runWithClient(() async {
      final s = ParentSyncService.instance;
      await s.attach(fs, password: 'x');
      fs.handlePayment(e, 'Septembre', 5000);
      await s.markDirty(e);
      await s.markDirtyMany([e]);
      await s.flush();
      // Laisse passer un éventuel minuteur (anti-rebond 800 ms).
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(s.stuckCount.value, 0);
    }, () => client);

    expect(requetes, isEmpty,
        reason: 'aucune fiche ne doit partir vers le serveur');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('parent_sync_queue_v1'), isNull,
        reason: "l'ancienne file d'attente est effacée");
    expect(prefs.getString('parent_sync_fp_v1'), isNull);
  });
}
