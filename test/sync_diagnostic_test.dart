// ============================================================================
// DIAGNOSTIC DE SYNCHRONISATION — reproduction des symptômes
// ----------------------------------------------------------------------------
// Aucun appel réseau réel : les requêtes HTTP de l'application sont
// interceptées (runWithClient) par un FAUX SERVEUR en mémoire qui reproduit
// la logique de /Users/mac/Desktop/jsinf/app.py (/backup, /restore) et de
// payment_sync.py (/school/sync_student_payments).
// Chaque « appareil » a son propre dossier temporaire : son fichier local
// (school_fees_data.json) y est écrit et relu comme dans l'application.
// Aucun fichier de vraies données n'est lu ni écrit.
// ============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:c_schollapp/frais_scolaires.dart';
import 'package:c_schollapp/models.dart';

// ---------------------------------------------------------------------------
// FAUX SERVEUR (logique copiée de app.py / payment_sync.py)
// ---------------------------------------------------------------------------
class FauxServeur {
  final Map<String, Map<String, dynamic>> ecoles = {};
  // IDs d'élèves utilisés par d'AUTRES écoles (_get_all_ids_except).
  final Set<String> idsAutresEcoles = {};
  int nbBackups = 0;

  static dynamic _copie(dynamic v) => json.decode(json.encode(v));

  int _rev(Map<String, dynamic>? d) =>
      (d?['_revision'] as num?)?.toInt() ?? 0;

  Map<String, num> _stats(Map<String, dynamic>? d) {
    int eleves = 0, tx = 0;
    double paye = 0;
    final h = (d?['history'] as Map?) ?? {};
    for (final y in h.values) {
      for (final e in ((y as Map)['eleves'] as List? ?? [])) {
        eleves++;
        tx += ((e as Map)['transactions'] as List? ?? []).length;
        ((e['paid'] as Map?) ?? {})
            .forEach((k, v) => paye += (v as num).toDouble());
      }
    }
    return {'eleves': eleves, 'tx': tx, 'paye': paye};
  }

  http.Response _json(int code, Object body) =>
      http.Response(json.encode(body), code,
          headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> gerer(http.Request req) async {
    final path = req.url.path;
    if (path == '/backup' && req.method == 'POST') return _backup(req);
    if (path == '/restore' && req.method == 'GET') return _restore(req);
    if (path == '/school/sync_student_payments') return _syncPaiements(req);
    if (path == '/school/push_promoter_summary') return _json(200, {});
    return _json(404, {'error': 'route inconnue en test : $path'});
  }

  http.Response _backup(http.Request req) {
    final body = json.decode(req.body) as Map<String, dynamic>;
    final code = (body['school_code'] as String).toLowerCase();
    final data = _copie(body['data']) as Map<String, dynamic>;
    final force = body['force'] == true;
    final base = body['base_revision'];
    final existing = ecoles[code];
    final serverRev = _rev(existing);
    if (existing != null && !force) {
      if (base != null && (base as num).toInt() != serverRev) {
        return _json(409, {
          'error': 'version plus récente sur le serveur',
          'code': 'STALE_REVISION',
          'server_revision': serverRev,
        });
      }
      final o = _stats(existing), n = _stats(data);
      final problems = <String>[];
      if (o['eleves']! > 0 && n['eleves'] == 0) problems.add('aucun élève');
      if (o['eleves']! >= 5 && n['eleves']! < o['eleves']! * 0.7) {
        problems.add('élèves');
      }
      if (o['paye']! > 0 && n['paye']! < o['paye']! * 0.7) {
        problems.add('argent');
      }
      if (problems.isNotEmpty) {
        return _json(409, {
          'error': 'Sauvegarde refusée : ${problems.join(", ")}',
          'code': 'DATA_LOSS_GUARD',
        });
      }
    }
    // _resolve_id_conflicts : renomme les IDs déjà pris par une autre école.
    final corrections = <String, String>{};
    final own = <String>{};
    for (final y in (data['history'] as Map).values) {
      for (final e in ((y as Map)['eleves'] as List)) {
        own.add((e as Map)['id'] as String);
      }
    }
    final used = {...idsAutresEcoles, ...own};
    for (final y in (data['history'] as Map).values) {
      for (final e in ((y as Map)['eleves'] as List)) {
        final m = e as Map;
        final old = m['id'] as String;
        if (!idsAutresEcoles.contains(old)) continue;
        if (corrections.containsKey(old)) {
          m['id'] = corrections[old];
          continue;
        }
        final match = RegExp(r'^(.*?)(\d+)$').firstMatch(old);
        final basePrefix = match != null ? match.group(1)! : '${old}_';
        var c = 1;
        var nouveau = '$basePrefix$c';
        while (used.contains(nouveau)) {
          c++;
          nouveau = '$basePrefix$c';
        }
        corrections[old] = nouveau;
        m['id'] = nouveau;
        used.add(nouveau);
      }
    }
    if (corrections.isNotEmpty) {
      for (final l in ((data['autresFraisPaiementsByYear'] as Map?) ?? {})
          .values) {
        for (final p in (l as List)) {
          final m = p as Map;
          if (corrections.containsKey(m['eleveId'])) {
            m['eleveId'] = corrections[m['eleveId']];
          }
        }
      }
    }
    data['_revision'] = serverRev + 1;
    ecoles[code] = data;
    nbBackups++;
    return _json(200, {
      'message': 'Sauvegarde réussie',
      'corrections': corrections,
      'summary_saved': true,
      'revision': serverRev + 1,
    });
  }

  http.Response _restore(http.Request req) {
    final code = (req.url.queryParameters['school_code'] ?? '').toLowerCase();
    final d = ecoles[code];
    if (d == null) return _json(404, {'error': 'Aucune sauvegarde trouvée'});
    final out = _copie(d) as Map<String, dynamic>;
    out.remove('backup_password');
    out['revision'] = _rev(d);
    return _json(200, out);
  }

  // payment_sync.py : remplace paid + transactions de l'élève, crée l'élève
  // s'il est inconnu, N'INCRÉMENTE PAS la révision.
  http.Response _syncPaiements(http.Request req) {
    final body = json.decode(req.body) as Map<String, dynamic>;
    final code = (body['school_code'] as String).toLowerCase();
    final saved = ecoles[code];
    if (saved == null) return _json(404, {'error': 'pas de sauvegarde'});
    final year = (body['annee'] ?? saved['currentYear']).toString();
    final h = saved.putIfAbsent('history', () => <String, dynamic>{}) as Map;
    final yd = h.putIfAbsent(year, () => <String, dynamic>{}) as Map;
    final eleves = yd.putIfAbsent('eleves', () => <dynamic>[]) as List;
    final done = <String>[];
    for (final snap in (body['students'] as List)) {
      final s = snap as Map;
      final sid = s['id'].toString();
      Map? e;
      for (final x in eleves) {
        if ((x as Map)['id'].toString().toUpperCase() == sid.toUpperCase()) {
          e = x;
        }
      }
      if (e == null) {
        if (idsAutresEcoles.contains(sid)) {
          done.add(sid);
          continue;
        }
        e = {
          'id': sid,
          'nom': s['nom'],
          'postNom': s['postNom'],
          'prenom': s['prenom'],
          'classe': s['classe'],
          'section': s['section'],
          'paid': {},
          'transactions': [],
          'customFields': {},
        };
        eleves.add(e);
      }
      e['paid'] = _copie(s['paid']);
      e['transactions'] = _copie(s['transactions']);
      done.add(sid);
    }
    return _json(200, {'done': done, 'changed': done.length});
  }
}

// ---------------------------------------------------------------------------
// APPAREILS SIMULÉS
// ---------------------------------------------------------------------------
const String kCode = 'TESTECOLE';
const String kMdp = 'mdp-test';
late String dossierCourant;

class Appareil {
  final String nom;
  final String dossier;
  Appareil(this.nom)
      : dossier = Directory.systemTemp
      .createTempSync('sync_diag_${nom}_')
      .path;

  // Ouvre l'application sur cet appareil : relit SON fichier local (et donc
  // sa révision et sa syncBase), exactement comme au démarrage.
  Future<FraisScolaires> ouvrir() async {
    dossierCourant = dossier;
    final fs = FraisScolaires();
    await fs.loadData();
    return fs;
  }
}

late FauxServeur serveur;

Future<T> avecServeur<T>(Future<T> Function() f) =>
    http.runWithClient(f, () => MockClient(serveur.gerer));

Future<Map<String, dynamic>> sauvegarder(FraisScolaires fs) =>
    avecServeur(() => fs.backupToServer(kCode, kMdp));
Future<Map<String, dynamic>> recuperer(FraisScolaires fs) =>
    avecServeur(() => fs.restoreFromServer(kCode, kMdp));
Future<Map<String, dynamic>> synchroniser(FraisScolaires fs) =>
    avecServeur(() => fs.syncWithServer(kCode, kMdp));

// Ce que ParentSyncService envoie automatiquement après un paiement
// (_snapshot de lib/services/parent_sync_service.dart).
Future<void> envoiAutoPaiements(FraisScolaires fs, List<Eleve> eleves) async {
  await avecServeur(() => http.post(
    Uri.parse('https://jsinf.onrender.com/school/sync_student_payments'),
    headers: {'Content-Type': 'application/json; charset=utf-8'},
    body: json.encode({
      'school_code': fs.schoolCode,
      'password': kMdp,
      'students': [
        for (final e in eleves)
          {
            'id': e.id,
            'nom': e.nom,
            'postNom': e.postNom,
            'prenom': e.prenom,
            'classe': e.classe,
            'section': e.section,
            'paid': e.paid,
            'transactions': e.transactions,
          }
      ],
    }),
  ));
}

double totalArgent(FraisScolaires fs) {
  double t = 0;
  for (final e in fs.currentData.eleves) {
    for (final tx in e.transactions) {
      t += (tx['amount'] as num).toDouble();
    }
  }
  return t;
}

double totalPaid(FraisScolaires fs) {
  double t = 0;
  for (final e in fs.currentData.eleves) {
    e.paid.forEach((k, v) => t += v);
  }
  return t;
}

Eleve eleveParNom(FraisScolaires fs, String nom) =>
    fs.currentData.eleves.firstWhere((e) => e.nom == nom);

List<Eleve> elevesNommes(FraisScolaires fs, String nom) =>
    fs.currentData.eleves.where((e) => e.nom == nom).toList();

String etatCanonique(FraisScolaires fs) {
  final eleves = [...fs.currentData.eleves]
    ..sort((a, b) => a.id.compareTo(b.id));
  return json.encode([
    for (final e in eleves)
      {
        ...e.toJson(),
        'transactions': ([...e.transactions]
          ..sort((a, b) => a['id'].toString().compareTo(b['id'].toString()))),
      }
  ]);
}

Future<void> payer(FraisScolaires fs, Eleve e, double montant) async {
  fs.handlePayment(e, 'Septembre', montant);
  await fs.saveData();
}

// Petite attente : les IDs de transactions sont basés sur l'horloge.
Future<void> pause() => Future<void>.delayed(const Duration(milliseconds: 3));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(canal, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return dossierCourant;
    }
    return dossierCourant;
  });

  late Appareil a;
  late Appareil b;

  // Situation de départ commune : l'appareil A crée l'école (4 élèves),
  // sauvegarde ; l'appareil B récupère. Les deux partent du même serveur.
  Future<void> departCommun({int nbEleves = 4}) async {
    final fsA = await a.ouvrir();
    fsA.config.schoolName = 'Ecole Test';
    fsA.config.sections = ['Primaire'];
    fsA.config.feesBySection['Primaire'] = 10000;
    const noms = ['KABILA', 'MUKENDI', 'TSHIBANDA', 'ILUNGA', 'MBUYI', 'NGOY'];
    for (var i = 0; i < nbEleves; i++) {
      fsA.currentData.eleves.add(Eleve(
        id: fsA.generateLocalStudentId(noms[i]),
        nom: noms[i],
        postNom: 'P$i',
        prenom: 'Prenom$i',
        classe: '1ère',
        section: 'Primaire',
      ));
    }
    await fsA.saveData();
    final r = await sauvegarder(fsA);
    expect(r['success'], isTrue, reason: 'backup initial : $r');
    final fsB = await b.ouvrir();
    final rb = await recuperer(fsB);
    expect(rb['success'], isTrue, reason: 'restore initial B : $rb');
    expect(fsB.currentData.eleves.length, nbEleves);
  }

  setUp(() {
    serveur = FauxServeur();
    a = Appareil('A');
    b = Appareil('B');
  });

  // =========================================================================
  // 1. SCÉNARIO NORMAL — A : paiements ; B : informations + paiements,
  //    sur des élèves DIFFÉRENTS, sans envoi automatique des paiements.
  // =========================================================================
  test('1. cas normal : A paie, B saisit infos + paie, sync dans les deux '
      'ordres, plusieurs fois', () async {
    await departCommun();

    var fsA = await a.ouvrir();
    await payer(fsA, eleveParNom(fsA, 'KABILA'), 10000);
    await pause();
    await payer(fsA, eleveParNom(fsA, 'MUKENDI'), 5000);

    var fsB = await b.ouvrir();
    final t = eleveParNom(fsB, 'TSHIBANDA')
      ..pereNom = 'Papa T'
      ..mereNom = 'Maman T'
      ..adresse = 'Av. 30 juin';
    await payer(fsB, t, 7000);

    // B synchronise, puis A, puis B, puis A (2 tours).
    for (var tour = 0; tour < 2; tour++) {
      fsB = await b.ouvrir();
      expect((await synchroniser(fsB))['success'], isTrue);
      fsA = await a.ouvrir();
      expect((await synchroniser(fsA))['success'], isTrue);
    }
    fsB = await b.ouvrir();
    expect((await recuperer(fsB))['success'], isTrue);

    for (final fs in [fsA, fsB]) {
      expect(fs.currentData.eleves.length, 4, reason: 'nombre d\'élèves');
      expect(totalArgent(fs), 22000, reason: 'total transactions');
      expect(totalPaid(fs), 22000, reason: 'total paid');
      expect(eleveParNom(fs, 'TSHIBANDA').pereNom, 'Papa T');
      expect(eleveParNom(fs, 'TSHIBANDA').adresse, 'Av. 30 juin');
    }
    expect(etatCanonique(fsA), etatCanonique(fsB));

    // (d) idempotence : récupérer deux fois de suite ne change rien.
    final avant = etatCanonique(fsA);
    await recuperer(fsA);
    await recuperer(fsA);
    expect(etatCanonique(fsA), avant);
  });

  // =========================================================================
  // 2. SYMPTÔME 2 — B modifie des infos déjà remplies sur A.
  // =========================================================================
  test('2. infos élève MODIFIÉES sur B (déjà remplies sur A) : A doit les '
      'recevoir après récupération', () async {
    final fsA0 = await a.ouvrir();
    await departCommun();
    // A avait déjà rempli le nom du père (ancienne valeur).
    var fsA = await a.ouvrir();
    eleveParNom(fsA, 'ILUNGA').pereNom = 'Ancien nom';
    await fsA.saveData();
    expect((await synchroniser(fsA))['success'], isTrue);
    fsA0.toString();

    var fsB = await b.ouvrir();
    expect((await recuperer(fsB))['success'], isTrue);
    eleveParNom(fsB, 'ILUNGA')
      ..pereNom = 'Nouveau nom corrigé'
      ..adresse = 'Nouvelle adresse';
    await fsB.saveData();
    expect((await synchroniser(fsB))['success'], isTrue);

    fsA = await a.ouvrir();
    expect((await recuperer(fsA))['success'], isTrue);
    expect(eleveParNom(fsA, 'ILUNGA').adresse, 'Nouvelle adresse',
        reason: 'champ vide sur A : copié');
    expect(eleveParNom(fsA, 'ILUNGA').pereNom, 'Nouveau nom corrigé',
        reason: 'champ déjà rempli sur A : la correction faite sur B doit '
            'arriver');
  });

  test('2b. ... et la sauvegarde suivante de A ne doit pas effacer la '
      'correction de B sur le serveur', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    eleveParNom(fsA, 'ILUNGA').pereNom = 'Ancien nom';
    await fsA.saveData();
    await synchroniser(fsA);
    var fsB = await b.ouvrir();
    await recuperer(fsB);
    eleveParNom(fsB, 'ILUNGA').pereNom = 'Nouveau nom corrigé';
    await fsB.saveData();
    await synchroniser(fsB);

    fsA = await a.ouvrir();
    await synchroniser(fsA); // récupère + sauvegarde
    // Un 3e ordinateur neuf voit exactement ce que contient le serveur.
    final c = await Appareil('C').ouvrir();
    await recuperer(c);
    expect(eleveParNom(c, 'ILUNGA').pereNom, 'Nouveau nom corrigé',
        reason: 'valeur sur le serveur après la sauvegarde de A');
  });

  // =========================================================================
  // 3. SYMPTÔMES 1 et 5 — deux appareils inscrivent chacun un élève hors
  //    ligne : même préfixe de nom -> MÊME ID local.
  // =========================================================================
  test('3. inscriptions simultanées sur A et B (même ID généré) : aucun '
      'élève ne doit se multiplier ni absorber les paiements d\'un autre',
      () async {
    await departCommun();

    var fsA = await a.ouvrir();
    final pA = Eleve(
        id: fsA.generateLocalStudentId('MULUMBA'),
        nom: 'MULUMBA',
        postNom: 'Jean',
        prenom: 'Paul',
        classe: '1ère',
        section: 'Primaire');
    fsA.currentData.eleves.add(pA);
    await payer(fsA, pA, 10000);

    var fsB = await b.ouvrir();
    final pB = Eleve(
        id: fsB.generateLocalStudentId('MUTOMBO'),
        nom: 'MUTOMBO',
        postNom: 'Marie',
        prenom: 'Claire',
        classe: '1ère',
        section: 'Primaire');
    fsB.currentData.eleves.add(pB);
    await pause();
    await payer(fsB, pB, 3000);
    expect(pA.id, pB.id, reason: 'les deux appareils ont généré le même ID');

    for (var tour = 0; tour < 3; tour++) {
      fsA = await a.ouvrir();
      await synchroniser(fsA);
      fsB = await b.ouvrir();
      await synchroniser(fsB);
    }
    fsA = await a.ouvrir();
    await recuperer(fsA);

    for (final fs in [fsA, fsB]) {
      // ignore: avoid_print
      print('[3] ${fs == fsA ? "A" : "B"} : ${fs.currentData.eleves.map((e) => '${e.nom}(${e.id})=${e.transactions.fold<double>(0, (s, t) => s + (t['amount'] as num))}').join(', ')}');
    }
    for (final fs in [fsA, fsB]) {
      expect(fs.currentData.eleves.length, 6, reason: 'élèves');
      expect(elevesNommes(fs, 'MULUMBA').length, 1);
      expect(elevesNommes(fs, 'MUTOMBO').length, 1);
      expect(totalArgent(fs), 13000, reason: 'argent');
      expect(totalArgent(fs), totalPaid(fs));
      final ids = fs.currentData.eleves.map((e) => e.id).toSet();
      expect(ids.length, fs.currentData.eleves.length, reason: 'IDs uniques');
    }
  });

  test('3b. même cas, mais B synchronise EN PREMIER : l\'argent ne doit '
      'pas se multiplier', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    final pA = Eleve(
        id: fsA.generateLocalStudentId('MULUMBA'),
        nom: 'MULUMBA',
        postNom: 'Jean',
        prenom: 'Paul',
        classe: '1ère',
        section: 'Primaire');
    fsA.currentData.eleves.add(pA);
    await payer(fsA, pA, 10000);
    var fsB = await b.ouvrir();
    final pB = Eleve(
        id: fsB.generateLocalStudentId('MUTOMBO'),
        nom: 'MUTOMBO',
        postNom: 'Marie',
        prenom: 'Claire',
        classe: '1ère',
        section: 'Primaire');
    fsB.currentData.eleves.add(pB);
    await pause();
    await payer(fsB, pB, 3000);

    for (var tour = 0; tour < 3; tour++) {
      fsB = await b.ouvrir();
      await synchroniser(fsB);
      fsA = await a.ouvrir();
      await synchroniser(fsA);
      for (final fs in [fsA, fsB]) {
        // ignore: avoid_print
        print('[3b tour $tour] ${fs == fsA ? "A" : "B"} : '
            '${fs.currentData.eleves.length} élèves, total ${totalArgent(fs)} : '
            '${fs.currentData.eleves.where((e) => e.nom.startsWith("MU") && e.nom != "MUKENDI").map((e) => '${e.nom}(${e.id})=${e.transactions.fold<double>(0, (s, t) => s + (t['amount'] as num))}').join(', ')}');
      }
    }
    for (final fs in [fsA, fsB]) {
      expect(totalArgent(fs), 13000, reason: 'argent réel = 13 000');
      expect(fs.currentData.eleves.length, 6, reason: 'élèves réels = 6');
      expect(elevesNommes(fs, 'MUTOMBO').length, 1);
      expect(elevesNommes(fs, 'MULUMBA').length, 1);
    }
  });

  // =========================================================================
  // 4. SYMPTÔME 4 — envoi automatique des paiements (ParentSyncService) par
  //    un appareil EN RETARD : il remplace sur le serveur les paiements de
  //    l'élève sans changer la révision.
  // =========================================================================
  test('4. envoi automatique d\'un appareil en retard : aucun paiement ne '
      'doit disparaître', () async {
    await departCommun();

    // B encaisse 3 « jours » de paiements pour KABILA puis sauvegarde.
    var fsB = await b.ouvrir();
    final kB = eleveParNom(fsB, 'KABILA');
    await payer(fsB, kB, 3000);
    await pause();
    await payer(fsB, kB, 3000);
    await pause();
    await payer(fsB, kB, 3000);
    await envoiAutoPaiements(fsB, [kB]);
    expect((await synchroniser(fsB))['success'], isTrue);

    // A n'a pas récupéré depuis le départ. Il encaisse 1 000 pour KABILA :
    // l'envoi automatique part avec l'état de A (sans les paiements de B).
    var fsA = await a.ouvrir();
    final kA = eleveParNom(fsA, 'KABILA');
    await payer(fsA, kA, 1000);
    await envoiAutoPaiements(fsA, [kA]);

    // B récupère (révision inchangée sur le serveur).
    fsB = await b.ouvrir();
    await recuperer(fsB);
    fsA = await a.ouvrir();
    await synchroniser(fsA);
    fsB = await b.ouvrir();
    await synchroniser(fsB);

    for (final fs in [fsA, fsB]) {
      // ignore: avoid_print
      print('[4] ${fs == fsA ? "A" : "B"} : total ${totalArgent(fs)}');
    }
    for (final fs in [fsA, fsB]) {
      expect(totalArgent(fs), 10000,
          reason: '${fs.hashCode} : 3×3 000 (B) + 1 000 (A)');
    }
  });

  test('4b. envoi automatique puis sauvegarde complète d\'un autre appareil '
      '(même révision) : le paiement envoyé ne doit pas être écrasé',
      () async {
    await departCommun();
    var fsB = await b.ouvrir();
    final kB = eleveParNom(fsB, 'MUKENDI');
    await payer(fsB, kB, 4000);
    await envoiAutoPaiements(fsB, [kB]); // B ne fait pas de sauvegarde

    var fsA = await a.ouvrir();
    await payer(fsA, eleveParNom(fsA, 'ILUNGA'), 10000);
    final r = await sauvegarder(fsA); // même révision -> accepté
    expect(r['success'], isTrue, reason: '$r');

    // Le serveur doit encore contenir le paiement de B.
    final serv = serveur.ecoles[kCode.toLowerCase()]!;
    double totalServeur = 0;
    for (final y in (serv['history'] as Map).values) {
      for (final e in ((y as Map)['eleves'] as List)) {
        for (final t in ((e as Map)['transactions'] as List)) {
          totalServeur += ((t as Map)['amount'] as num).toDouble();
        }
      }
    }
    expect(totalServeur, 14000,
        reason: 'paiement de B (4 000) présent sur le serveur');
  });

  test('4c. même scénario que 4 avec l\'application corrigée (étape 1 : '
      'aucun envoi automatique) : aucun paiement perdu', () async {
    await departCommun();
    var fsB = await b.ouvrir();
    final kB = eleveParNom(fsB, 'KABILA');
    await payer(fsB, kB, 3000);
    await pause();
    await payer(fsB, kB, 3000);
    await pause();
    await payer(fsB, kB, 3000);
    expect((await synchroniser(fsB))['success'], isTrue);

    var fsA = await a.ouvrir(); // en retard, ne récupère pas
    await payer(fsA, eleveParNom(fsA, 'KABILA'), 1000);

    fsB = await b.ouvrir();
    await recuperer(fsB);
    fsA = await a.ouvrir();
    await synchroniser(fsA);
    fsB = await b.ouvrir();
    await synchroniser(fsB);
    for (final fs in [fsA, fsB]) {
      expect(totalArgent(fs), 10000);
      expect(totalPaid(fs), 10000);
    }
  });

  // =========================================================================
  // 5. Conflit d'ID avec une AUTRE école : le serveur renomme l'élève.
  // =========================================================================
  test('5. ID renommé par le serveur (conflit avec une autre école) : B ne '
      'doit pas dupliquer l\'élève', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    final k = eleveParNom(fsA, 'KABILA');
    final String ancienId = k.id;
    serveur.idsAutresEcoles.add(ancienId); // une autre école a pris cet ID
    await payer(fsA, k, 2000);
    expect((await synchroniser(fsA))['success'], isTrue);
    fsA = await a.ouvrir();
    expect(eleveParNom(fsA, 'KABILA').id, isNot(ancienId),
        reason: 'A a reçu la correction');

    // B (ancien ID) encaisse pour KABILA, puis synchronise.
    var fsB = await b.ouvrir();
    final kB = eleveParNom(fsB, 'KABILA');
    await payer(fsB, kB, 5000);
    await envoiAutoPaiements(fsB, [kB]);
    await synchroniser(fsB);
    fsA = await a.ouvrir();
    await synchroniser(fsA);
    fsB = await b.ouvrir();
    await recuperer(fsB);

    for (final fs in [fsA, fsB]) {
      expect(elevesNommes(fs, 'KABILA').length, 1, reason: 'pas de doublon');
      expect(fs.currentData.eleves.length, 4);
      expect(totalArgent(fs), 7000);
    }
  });

  // =========================================================================
  // 6. Correction d'orthographe du nom sur B pour un élève inscrit sur A.
  // =========================================================================
  test('6. nom corrigé sur B (élève récent de A) : pas de doublon', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    final n = Eleve(
        id: fsA.generateLocalStudentId('KASONGO'),
        nom: 'KASONGO',
        postNom: 'Mwamba',
        prenom: 'Eric',
        classe: '1ère',
        section: 'Primaire');
    fsA.currentData.eleves.add(n);
    await payer(fsA, n, 8000);
    await synchroniser(fsA);

    var fsB = await b.ouvrir();
    await recuperer(fsB);
    final nb = fsB.currentData.eleves.firstWhere((e) => e.id == n.id);
    nb.nom = 'KASONGO';
    nb.postNom = 'Mwambay'; // correction d'orthographe
    await fsB.saveData();
    await synchroniser(fsB);

    // A se déconnecte / reconnecte entre-temps (base effacée) puis... non :
    // A récupère simplement.
    fsA = await a.ouvrir();
    await synchroniser(fsA);
    fsB = await b.ouvrir();
    await recuperer(fsB);
    for (final fs in [fsA, fsB]) {
      expect(fs.currentData.eleves.length, 5);
      expect(totalArgent(fs), 8000);
    }
  });

  // =========================================================================
  // 7. Déconnexion / reconnexion.
  // =========================================================================
  test('7. déconnexion (sauvegarde puis effacement) et reconnexion : rien '
      'ne se perd, rien ne se multiplie', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    await payer(fsA, eleveParNom(fsA, 'KABILA'), 6000);
    var fsB = await b.ouvrir();
    eleveParNom(fsB, 'MUKENDI').mereNom = 'Maman M';
    await payer(fsB, eleveParNom(fsB, 'MUKENDI'), 2500);
    await synchroniser(fsB);

    // A : déconnexion (comme settings_screen : backup puis clearLocalData).
    fsA = await a.ouvrir();
    final r = await sauvegarder(fsA);
    expect(r['success'], isTrue, reason: '$r');
    await fsA.clearLocalData();
    // Reconnexion : nouvelle ouverture puis récupération.
    fsA = await a.ouvrir();
    expect(fsA.currentData.eleves, isEmpty);
    expect((await recuperer(fsA))['success'], isTrue);
    expect(fsA.currentData.eleves.length, 4);
    expect(totalArgent(fsA), 8500);
    expect(eleveParNom(fsA, 'MUKENDI').mereNom, 'Maman M');

    // Deuxième déconnexion / reconnexion.
    await sauvegarder(fsA);
    await fsA.clearLocalData();
    fsA = await a.ouvrir();
    await recuperer(fsA);
    expect(fsA.currentData.eleves.length, 4);
    expect(totalArgent(fsA), 8500);

    fsB = await b.ouvrir();
    await synchroniser(fsB);
    expect(fsB.currentData.eleves.length, 4);
    expect(totalArgent(fsB), 8500);
  });

  test('7b. reconnexion sur A pendant que B a encore des paiements non '
      'sauvegardés', () async {
    await departCommun();
    var fsB = await b.ouvrir();
    await payer(fsB, eleveParNom(fsB, 'NGOY'.isEmpty ? '' : 'ILUNGA'), 4000);
    var fsA = await a.ouvrir();
    await payer(fsA, eleveParNom(fsA, 'KABILA'), 1000);
    await sauvegarder(fsA);
    await fsA.clearLocalData();
    fsA = await a.ouvrir();
    await recuperer(fsA);
    fsB = await b.ouvrir();
    await synchroniser(fsB);
    fsA = await a.ouvrir();
    await synchroniser(fsA);
    for (final fs in [fsA, fsB]) {
      expect(totalArgent(fs), 5000);
      expect(fs.currentData.eleves.length, 4);
    }
  });

  // =========================================================================
  // 8. Les deux appareils encaissent le MÊME élève, le même mois.
  // =========================================================================
  test('8. A et B encaissent le même élève le même mois : total exact, '
      'idempotent', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    await payer(fsA, eleveParNom(fsA, 'MUKENDI'), 6000);
    var fsB = await b.ouvrir();
    await pause();
    await payer(fsB, eleveParNom(fsB, 'MUKENDI'), 6000);
    for (var i = 0; i < 2; i++) {
      fsA = await a.ouvrir();
      await synchroniser(fsA);
      fsB = await b.ouvrir();
      await synchroniser(fsB);
    }
    fsA = await a.ouvrir();
    await recuperer(fsA);
    for (final fs in [fsA, fsB]) {
      expect(totalArgent(fs), 12000);
      expect(totalPaid(fs), 12000);
    }
    final avant = etatCanonique(fsA);
    await recuperer(fsA);
    expect(etatCanonique(fsA), avant, reason: 'idempotence');
  });

  // =========================================================================
  // 9. Élève supprimé (archivé) sur A pendant que B l'encaisse.
  // =========================================================================
  test('9. élève archivé sur A, payé sur B : il ne doit pas revenir en '
      'double', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    await fsA.archiverEtSupprimerEleve(eleveParNom(fsA, 'ILUNGA'));
    await synchroniser(fsA);
    var fsB = await b.ouvrir();
    await payer(fsB, eleveParNom(fsB, 'ILUNGA'), 2000);
    await synchroniser(fsB);
    fsA = await a.ouvrir();
    await synchroniser(fsA);
    fsB = await b.ouvrir();
    await recuperer(fsB);
    expect(elevesNommes(fsA, 'ILUNGA').length,
        elevesNommes(fsB, 'ILUNGA').length,
        reason: 'A et B doivent montrer la même chose');
    expect(fsA.currentData.eleves.length, fsB.currentData.eleves.length);
  });

  // =========================================================================
  // 10. Annulation d'une entrée (modification « sur place ») faite sur B.
  // =========================================================================
  test('10. entrée annulée sur B : A doit voir l\'annulation, et ne pas la '
      'défaire au serveur', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    fsA.config.administrations = [Administration(nom: 'Activités', pourcentage: 100)];
    await fsA.saveData();
    final err = await fsA.addEntree(
        montant: 50000,
        type: kEntreeDon,
        justification: 'Don parent',
        rubrique: 'Activités');
    expect(err, isNull);
    await synchroniser(fsA);
    var fsB = await b.ouvrir();
    await recuperer(fsB);
    final id = fsB.entreesByYear[fsB.currentYear]!.single.id;
    expect(await fsB.annulerEntree(id, 'Erreur de saisie'), isNull);
    await synchroniser(fsB);
    fsA = await a.ouvrir();
    await synchroniser(fsA);
    expect(fsA.entreesByYear[fsA.currentYear]!.single.annulee, isTrue,
        reason: 'annulation faite sur B');
    final c = await Appareil('C').ouvrir();
    await recuperer(c);
    expect(c.entreesByYear[c.currentYear]!.single.annulee, isTrue,
        reason: 'annulation toujours présente sur le serveur');
  });

  // =========================================================================
  // 11. Modification du montant d'un paiement « Autres frais » sur B.
  // =========================================================================
  test('11. montant d\'un paiement Autres Frais modifié sur B : propagé à A',
      () async {
    await departCommun();
    var fsA = await a.ouvrir();
    final f = AutreFrais(id: 'F1', nom: 'Tenue', montant: 12000);
    fsA.autresFrais.add(f);
    await fsA.saveData();
    await fsA.payAutreFrais(
        frais: f, eleve: eleveParNom(fsA, 'KABILA'), montantSaisi: 5000);
    await synchroniser(fsA);
    var fsB = await b.ouvrir();
    await recuperer(fsB);
    final p = fsB.getAutresFraisPaiementsForYear().single;
    await fsB.modifierMontantPaiementAutreFrais(
        paiement: p, eleve: eleveParNom(fsB, 'KABILA'), newMontant: 3000);
    await synchroniser(fsB);
    fsA = await a.ouvrir();
    await synchroniser(fsA);
    expect(fsA.getAutresFraisPaiementsForYear().single.montant, 3000);
  });

  // =========================================================================
  // 12. ID en double (inscriptions simultanées) + envoi automatique.
  // =========================================================================
  test('12. ID en double + envoi automatique des paiements : l\'argent ne '
      'doit pas se multiplier', () async {
    await departCommun();
    var fsA = await a.ouvrir();
    final pA = Eleve(
        id: fsA.generateLocalStudentId('MULUMBA'),
        nom: 'MULUMBA', postNom: 'Jean', prenom: 'Paul',
        classe: '1ère', section: 'Primaire');
    fsA.currentData.eleves.add(pA);
    await payer(fsA, pA, 10000);
    await envoiAutoPaiements(fsA, [pA]);

    var fsB = await b.ouvrir();
    final pB = Eleve(
        id: fsB.generateLocalStudentId('MUTOMBO'),
        nom: 'MUTOMBO', postNom: 'Marie', prenom: 'Claire',
        classe: '1ère', section: 'Primaire');
    fsB.currentData.eleves.add(pB);
    await pause();
    await payer(fsB, pB, 3000);
    await envoiAutoPaiements(fsB, [pB]);

    for (var tour = 0; tour < 3; tour++) {
      fsA = await a.ouvrir();
      await synchroniser(fsA);
      await envoiAutoPaiements(fsA, fsA.currentData.eleves);
      fsB = await b.ouvrir();
      await synchroniser(fsB);
      await envoiAutoPaiements(fsB, fsB.currentData.eleves);
    }
    fsA = await a.ouvrir();
    await recuperer(fsA);
    for (final fs in [fsA, fsB]) {
      // ignore: avoid_print
      print('[12] ${fs == fsA ? "A" : "B"} : ${fs.currentData.eleves.length} '
          'élèves, total ${totalArgent(fs)}, paid ${totalPaid(fs)} : '
          '${fs.currentData.eleves.where((e) => e.nom.startsWith("MU") && e.nom != "MUKENDI").map((e) => '${e.nom}(${e.id})=${e.transactions.fold<double>(0, (s, t) => s + (t['amount'] as num))}').join(', ')}');
    }
    for (final fs in [fsA, fsB]) {
      expect(totalArgent(fs), 13000);
      expect(fs.currentData.eleves.length, 6);
    }
  });
}
