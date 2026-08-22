import 'dart:convert';
import 'dart:io';
import 'frais_scolaires.dart';
import 'network_resolver.dart';

/// ⚡ NOUVEAU — Serveur HTTP local, hébergé par l'app de l'admin.
///
/// Reproduit, en local, le sous-ensemble des routes du serveur central
/// (render.com) nécessaires pour que les sous-utilisateurs (clés
/// PAY/DISC/INSC/AFR) puissent travailler EN PARALLÈLE sans internet,
/// connectés uniquement au point d'accès Windows du PC principal
/// (adresse fixe `192.168.137.1`, voir network_resolver.dart).
///
/// Principe clé : ce serveur ne duplique AUCUNE donnée. Il lit et écrit
/// directement sur l'instance `FraisScolaires` déjà chargée en mémoire
/// dans l'app de l'admin — la même que celle affichée à l'écran. Donc
/// dès qu'un sous-utilisateur envoie un paiement, il apparaît
/// immédiatement dans les "paiements en attente" du Dashboard Admin,
/// exactement comme avec le serveur central, sans étape de
/// synchronisation intermédiaire.
///
/// ⚠️ LIMITE HONNÊTE : les convocations et communiqués (module
/// Discipline) ne peuvent pas réellement atteindre les parents en mode
/// local — il n'existe aucun canal de notification (SMS/push) qui
/// fonctionne sans internet. Ce serveur les enregistre quand même
/// (`FraisScolaires.localCommunicationsLog`) pour ne rien perdre, mais
/// répond avec `notified_count: 0` et une note explicite à ce sujet,
/// plutôt que de faire croire à une livraison qui n'a pas eu lieu.
///
/// Démarré/arrêté explicitement par l'admin depuis le Dashboard (bouton
/// "Serveur local"), PAS automatiquement au lancement de l'app — comme
/// convenu, l'activation du point d'accès Windows lui-même reste
/// manuelle, enseignée aux utilisateurs.
class LocalServerService {
  static HttpServer? _server;
  static FraisScolaires? _frais;

  /// Vrai si le serveur local est actuellement démarré.
  static bool get isRunning => _server != null;

  /// Démarre le serveur local sur toutes les interfaces réseau de la
  /// machine, port `NetworkResolver.localPort`. Utiliser
  /// `InternetAddress.anyIPv4` (et non `loopbackIPv4`) est essentiel :
  /// c'est ce qui permet aux AUTRES appareils connectés au point d'accès
  /// de joindre ce serveur, pas seulement le PC lui-même.
  static Future<bool> start(FraisScolaires fraisScolaires) async {
    if (_server != null) return true; // déjà démarré, rien à faire
    _frais = fraisScolaires;
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        NetworkResolver.localPort,
        shared: true,
      );
      _server!.listen(
        _handleRequest,
        onError: (_) {}, // une requête individuelle mal formée ne doit
        // jamais faire planter le serveur entier
      );
      return true;
    } catch (_) {
      // Port déjà utilisé, pas de droit réseau, etc. — on ne bloque
      // jamais l'admin : il peut réessayer, ou fonctionner sans le
      // serveur local (mode internet classique).
      _server = null;
      _frais = null;
      return false;
    }
  }

  /// Arrête le serveur local proprement.
  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _frais = null;
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    // CORS permissif : utile si un jour un client web local (navigateur
    // sur le même réseau) doit aussi s'y connecter.
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      response.statusCode = 200;
      await response.close();
      return;
    }

    final frais = _frais;
    if (frais == null) {
      response.statusCode = 503;
      response.write(jsonEncode({'error': 'Serveur local non initialisé'}));
      await response.close();
      return;
    }

    try {
      final path = request.uri.path;
      Map<String, dynamic> body = {};
      if (request.method == 'POST') {
        final content = await utf8.decoder.bind(request).join();
        if (content.trim().isNotEmpty) {
          body = jsonDecode(content) as Map<String, dynamic>;
        }
      }

      switch (path) {
        case '/ping':
          _write(response, 200, {'ok': true});
          break;

        case '/restore':
          _write(response, 200, frais.exportSnapshotForClients());
          break;

        case '/generate_key':
          await _handleGenerateKey(body, response, frais);
          break;

        case '/verify_key':
          _handleVerifyKey(body, response, frais);
          break;

        case '/record_payment':
          await _handleRecordPayment(body, response, frais);
          break;

        case '/get_pending_payments':
          _write(response, 200, {'pending_payments': frais.localPendingPayments});
          break;

        case '/validate_payments':
          await _handleValidatePayments(body, response, frais);
          break;

        case '/school/submit_registration':
          await _handleSubmitRegistration(body, response, frais);
          break;

        case '/school/get_pending_registrations':
          _write(response, 200,
              {'pending_registrations': frais.localPendingRegistrations});
          break;

        case '/school/validate_registrations':
          await _handleValidateRegistrations(body, response, frais);
          break;

        case '/school/get_autres_frais':
          _write(response, 200, {
            'autres_frais': frais.getAutresFrais().map((f) => f.toJson()).toList(),
          });
          break;

        case '/school/submit_autre_frais_payment':
          await _handleSubmitAutreFraisPayment(body, response, frais);
          break;

        case '/school/get_pending_autres_frais':
          _write(response, 200, {
            'pending_autres_frais': frais.localPendingAutresFraisPayments,
          });
          break;

        case '/school/validate_autres_frais_payments':
          await _handleValidateAutresFraisPayments(body, response, frais);
          break;

        case '/school/record_absences':
          await _handleRecordAbsences(body, response, frais);
          break;

        case '/school/get_attendance':
          _handleGetAttendance(request, response, frais);
          break;

        case '/school/send_convocation':
          await _handleSendConvocation(body, response, frais);
          break;

        case '/school/send_announcement':
          await _handleSendAnnouncement(body, response, frais);
          break;

        default:
          _write(response, 404, {'error': 'Route inconnue : $path'});
      }
    } catch (e) {
      _write(response, 500, {'error': 'Erreur serveur local : $e'});
    }

    await response.close();
  }

  static void _write(HttpResponse response, int status, Map<String, dynamic> data) {
    response.statusCode = status;
    response.write(jsonEncode(data));
  }

  // ==================== CLÉS D'ACCÈS ====================

  static Future<void> _handleGenerateKey(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    final sections =
    (body['sections'] as List? ?? []).map((e) => e.toString()).toList();
    final type = (body['type'] ?? 'PAY').toString();
    final classe = body['classe']?.toString();
    final entry =
    await frais.generateLocalKey(sections: sections, type: type, classe: classe);
    _write(response, 200, {
      'key': entry['key'],
      'sections': entry['sections'],
      'type': entry['type'],
      'classe': entry['classe'],
    });
  }

  static void _handleVerifyKey(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) {
    final key = (body['key'] ?? '').toString().trim();
    final entry = frais.verifyLocalKey(key);
    if (entry == null) {
      _write(response, 200, {'valid': false});
      return;
    }
    _write(response, 200, {
      'valid': true,
      'school_code': frais.schoolCode ?? '',
      'school_name': frais.config.schoolName,
      'sections': entry['sections'],
      'type': entry['type'],
      'classe': entry['classe'],
      'current_year': frais.currentYear,
    });
  }

  // ==================== PAIEMENTS (frais mensuel principal) ====================

  static Future<void> _handleRecordPayment(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    final eleveId = (body['eleve_id'] ?? '').toString();
    final mois = (body['mois'] ?? '').toString();
    final amount = (body['amount'] as num?)?.toDouble() ?? 0.0;
    await frais.addLocalPendingPayment(eleveId: eleveId, mois: mois, amount: amount);
    _write(response, 200, {'success': true});
  }

  static Future<void> _handleValidatePayments(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    final ids = (body['payment_ids'] as List? ?? []).map((e) => e.toString()).toList();
    final count = await frais.validateLocalPendingPayments(ids);
    _write(response, 200, {'success': true, 'validated_count': count});
  }

  // ==================== INSCRIPTIONS ====================

  static Future<void> _handleSubmitRegistration(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    await frais.addLocalPendingRegistration(body);
    _write(response, 200, {'success': true});
  }

  static Future<void> _handleValidateRegistrations(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    final ids =
    (body['registration_ids'] as List? ?? []).map((e) => e.toString()).toList();
    final count = await frais.validateLocalPendingRegistrations(ids);
    _write(response, 200, {'success': true, 'created_count': count});
  }

  // ==================== AUTRES FRAIS ====================

  static Future<void> _handleSubmitAutreFraisPayment(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    final eleveId = (body['eleve_id'] ?? '').toString();
    final autreFraisId = (body['autre_frais_id'] ?? '').toString();
    final montant = (body['montant'] as num?)?.toDouble() ?? 0.0;
    final enregistrePar = (body['enregistre_par'] ?? 'Agent').toString();
    await frais.addLocalPendingAutreFraisPayment(
      eleveId: eleveId,
      autreFraisId: autreFraisId,
      montant: montant,
      enregistrePar: enregistrePar,
    );
    _write(response, 200, {'success': true});
  }

  static Future<void> _handleValidateAutresFraisPayments(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    final ids = (body['payment_ids'] as List? ?? []).map((e) => e.toString()).toList();
    final count = await frais.validateLocalPendingAutresFraisPayments(ids);
    _write(response, 200, {'success': true, 'validated_count': count});
  }

  // ==================== DISCIPLINE ====================

  static Future<void> _handleRecordAbsences(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    final classe = (body['classe'] ?? '').toString();
    final section = (body['section'] ?? '').toString();
    final date = (body['date'] ?? '').toString();
    final absentIds =
    (body['absent_ids'] as List? ?? []).map((e) => e.toString()).toList();
    final recordedBy = (body['recorded_by'] ?? 'Direction').toString();

    await frais.recordLocalAbsences(
      classe: classe,
      section: section,
      date: date,
      absentIds: absentIds,
      recordedBy: recordedBy,
    );

    // ⚠️ Honnête : pas de canal de notification réel hors ligne.
    _write(response, 200, {
      'notified_count': 0,
      'note': 'Enregistré localement. Les parents seront notifiés une '
          'fois cet appareil reconnecté à internet.',
    });
  }

  static void _handleGetAttendance(
      HttpRequest request, HttpResponse response, FraisScolaires frais) {
    final classe = request.uri.queryParameters['classe'] ?? '';
    final date = request.uri.queryParameters['date'] ?? '';
    _write(response, 200, {'absents': frais.getLocalAttendance(classe, date)});
  }

  static Future<void> _handleSendConvocation(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    await frais.logLocalCommunication({
      'type': 'convocation',
      'student_id': body['student_id'],
      'title': body['title'],
      'message': body['message'],
    });
    _write(response, 200, {
      'success': true,
      'note': 'Enregistré localement. Le parent sera notifié une fois '
          'cet appareil reconnecté à internet.',
    });
  }

  static Future<void> _handleSendAnnouncement(
      Map<String, dynamic> body, HttpResponse response, FraisScolaires frais) async {
    await frais.logLocalCommunication({
      'type': 'announcement',
      'title': body['title'],
      'message': body['message'],
      'target': body['target'],
      'classe': body['classe'],
      'section': body['section'],
      'sections': body['sections'],
      'student_ids': body['student_ids'],
    });
    // ⚠️ Honnête : notified_count reste 0 en local (voir doc de classe).
    _write(response, 200, {
      'notified_count': 0,
      'note': 'Communiqué enregistré localement. Les parents seront '
          'notifiés une fois cet appareil reconnecté à internet.',
    });
  }
}