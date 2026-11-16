import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../frais_scolaires.dart';
import '../models.dart';

/// Envoie SILENCIEUSEMENT l'état des paiements des élèves au serveur pour que
/// les parents le voient en temps réel (paiement, annulation, modification).
///
///  • Aucun dialogue, aucune attente de validation.
///  • Les élèves à envoyer sont mémorisés sur l'appareil (file persistante) :
///    sans internet, tout reste en attente puis part automatiquement dès le
///    retour de la connexion.
///  • On envoie l'ÉTAT complet de l'élève (pas des « événements ») : renvoyer
///    plusieurs fois ne crée jamais de doublon.
///  • Un détecteur compare régulièrement les paiements de tous les élèves :
///    toute modification faite n'importe où dans l'application est envoyée,
///    même sans appel explicite à [markDirty].
class ParentSyncService {
  ParentSyncService._();
  static final ParentSyncService instance = ParentSyncService._();

  static const String _serverUrl = 'https://jsinf.onrender.com';
  static const String _kQueue = 'parent_sync_queue_v1';
  static const String _kFingerprints = 'parent_sync_fp_v1';
  static const int _batchSize = 15;

  /// Nombre d'élèves bloqués en attente (0 = tout est envoyé). Sert au
  /// bandeau « pas de connexion » de l'écran des paiements.
  final ValueNotifier<int> stuckCount = ValueNotifier<int>(0);

  FraisScolaires? _fs;
  String? _password;

  /// élève → version (incrémentée à chaque modification)
  final Map<String, int> _dirty = {};

  /// élève → empreinte de ses paiements au dernier passage du détecteur
  final Map<String, String> _fp = {};
  bool _hasBaseline = false;

  Future<void>? _loading;
  bool _flushing = false;
  bool _ticking = false;
  Timer? _ticker;
  Timer? _debounce;

  // ------------------------------------------------------------------
  // Démarrage
  // ------------------------------------------------------------------
  Future<void> attach(FraisScolaires fs, {String? password}) async {
    _fs = fs;
    if (password != null && password.isNotEmpty) _password = password;
    await _ensureLoaded();
    _ticker ??= Timer.periodic(const Duration(seconds: 10), (_) => _tick());
    unawaited(_tick());
  }

  Future<void> _ensureLoaded() => _loading ??= _doLoad();

  Future<void> _doLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final q = prefs.getString(_kQueue);
      if (q != null) {
        final m = jsonDecode(q);
        if (m is Map) {
          m.forEach((k, v) => _dirty[k.toString()] = (v as num?)?.toInt() ?? 1);
        }
      }
      final f = prefs.getString(_kFingerprints);
      if (f != null) {
        final m = jsonDecode(f);
        if (m is Map) {
          m.forEach((k, v) => _fp[k.toString()] = v.toString());
          _hasBaseline = true;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_dirty.isEmpty) {
        await prefs.remove(_kQueue);
      } else {
        await prefs.setString(_kQueue, jsonEncode(_dirty));
      }
    } catch (_) {}
  }

  Future<void> _saveFingerprints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFingerprints, jsonEncode(_fp));
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Marquage explicite (envoi immédiat)
  // ------------------------------------------------------------------
  Future<void> markDirty(Eleve e) => markDirtyIds([e.id]);

  Future<void> markDirtyMany(Iterable<Eleve> eleves) =>
      markDirtyIds(eleves.map((e) => e.id));

  Future<void> markDirtyIds(Iterable<String> ids) async {
    await _ensureLoaded();
    final fs = _fs;
    if (fs == null) return;
    final map = {for (final e in fs.currentData.eleves) e.id: e};
    var any = false;
    for (final id in ids) {
      final e = map[id];
      if (e == null) continue;
      _dirty[id] = (_dirty[id] ?? 0) + 1;
      _fp[id] = _fingerprint(e);
      any = true;
    }
    if (!any) return;
    await _saveQueue();
    await _saveFingerprints();
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () => flush());
  }

  // ------------------------------------------------------------------
  // Détecteur de modifications (filet de sécurité)
  // ------------------------------------------------------------------
  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await _ensureLoaded();
      await _scan();
      await flush();
    } catch (_) {
    } finally {
      _ticking = false;
    }
  }

  String _fingerprint(Eleve e) {
    final b = StringBuffer();
    final keys = e.paid.keys.map((k) => k.toString()).toList()..sort();
    for (final k in keys) {
      final dynamic v = e.paid[k];
      final d = v is num ? v.toDouble() : 0.0;
      b.write('$k=${d.toStringAsFixed(2)};');
    }
    double sum = 0;
    for (final t in e.transactions) {
      final dynamic a = t['amount'];
      if (a is num) sum += a.toDouble();
    }
    b.write('#${e.transactions.length}#${sum.toStringAsFixed(2)}');
    return b.toString();
  }

  Future<void> _scan() async {
    final fs = _fs;
    if (fs == null) return;
    final eleves = fs.currentData.eleves;
    if (eleves.isEmpty) return; // données pas encore chargées

    var fpChanged = false;
    var queueChanged = false;
    for (final e in eleves) {
      final id = e.id;
      final fp = _fingerprint(e);
      final old = _fp[id];
      if (old == fp) continue;
      _fp[id] = fp;
      fpChanged = true;
      if (!_hasBaseline) continue; // premier passage : on mémorise seulement
      if (old == null && e.transactions.isEmpty) continue; // nouvel élève vide
      _dirty[id] = (_dirty[id] ?? 0) + 1;
      queueChanged = true;
    }
    if (fpChanged || !_hasBaseline) {
      _hasBaseline = true;
      await _saveFingerprints();
    }
    if (queueChanged) await _saveQueue();
  }

  // ------------------------------------------------------------------
  // Envoi
  // ------------------------------------------------------------------
  Map<String, dynamic> _snapshot(Eleve e) {
    final paid = <String, double>{};
    e.paid.forEach((k, v) {
      final dynamic x = v;
      paid[k.toString()] = x is num ? x.toDouble() : 0.0;
    });
    final txs = <Map<String, dynamic>>[];
    for (final t in e.transactions) {
      final m = Map<String, dynamic>.from(t);
      m.remove('pendingRequestId');
      m.remove('pendingRequestType');
      txs.add(m);
    }
    return {
      'id': e.id,
      'nom': e.nom,
      'postNom': e.postNom,
      'prenom': e.prenom,
      'classe': e.classe,
      'section': e.section,
      'paid': paid,
      'transactions': txs,
    };
  }

  /// Envoie tout ce qui est en attente. Sans connexion, ne perd rien :
  /// la file reste sur l'appareil et le prochain passage réessaie.
  Future<void> flush() async {
    if (_flushing) return;
    final fs = _fs;
    if (fs == null || _dirty.isEmpty) {
      stuckCount.value = 0;
      return;
    }
    final code = fs.schoolCode;
    if (code == null || code.isEmpty) return;

    _flushing = true;
    var failed = false;
    var progressed = false;
    try {
      final sent = Map<String, int>.from(_dirty);
      final map = {for (final e in fs.currentData.eleves) e.id: e};

      // élèves disparus : on les retire de la file
      for (final id in sent.keys) {
        if (!map.containsKey(id) && _dirty[id] == sent[id]) _dirty.remove(id);
      }
      final ids = sent.keys.where(map.containsKey).toList();

      for (var i = 0; i < ids.length; i += _batchSize) {
        final chunk = ids.sublist(i, math.min(i + _batchSize, ids.length));
        final body = jsonEncode(
          {
            'school_code': code,
            if (_password != null) 'password': _password,
            'students': chunk.map((id) => _snapshot(map[id]!)).toList(),
          },
          toEncodable: (o) => o.toString(),
        );

        final response = await http
            .post(
          Uri.parse('$_serverUrl/school/sync_student_payments'),
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: body,
        )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode != 200) {
          failed = true;
          break;
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final done = ((data is Map ? data['done'] : null) as List? ?? [])
            .map((e) => e.toString())
            .toSet();
        for (final id in done) {
          if (_dirty[id] == sent[id]) _dirty.remove(id);
          progressed = true;
        }
      }
    } catch (_) {
      failed = true; // pas de connexion : tout reste en attente
    } finally {
      _flushing = false;
    }

    await _saveQueue();
    stuckCount.value = (failed && _dirty.isNotEmpty) ? _dirty.length : 0;

    // des modifications sont arrivées pendant l'envoi → on les envoie aussi
    if (!failed && progressed && _dirty.isNotEmpty) _scheduleFlush();
  }
}