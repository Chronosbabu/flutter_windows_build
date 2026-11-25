import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../frais_scolaires.dart';
import '../screens/subscription_service.dart';

// ============================================================================
// CENTRE DE NOTIFICATIONS DE L'ÉCOLE
// ----------------------------------------------------------------------------
// Fonctionnement (comme les notifications du Mac, en mieux) :
//   • Les notifications apparaissent EN HAUT À DROITE, sur n'importe quelle
//     page de l'application.
//   • Elles RESTENT affichées (même après fermeture de l'application) jusqu'à
//     ce que l'utilisateur :
//       - clique dessus  -> la page concernée s'ouvre et la notification
//                           disparaît ;
//       - ou la supprime (croix).
//   • Plusieurs notifications s'empilent ; au-delà de 3, « + N autres ».
//   • « Réduire » les range dans une cloche avec le nombre ; une nouvelle
//     notification les fait réapparaître.
//
// Sources surveillées (lecture seule, aucune donnée modifiée) :
//   1. Nouveaux messages des parents              -> Messagerie parents
//   2. Paiements Mobile Money à confirmer         -> Paiements
//   3. Réponse du promoteur à une demande         -> Paiements
//   4. Abonnement qui expire bientôt (7 jours)    -> Paramètres
//   5. Nouveau mois : élèves qui n'ont pas payé   -> Liste En Ordre
//      le mois précédent (exonérés non comptés)
// ============================================================================

/// Clé du navigateur principal : permet d'ouvrir une page depuis une
/// notification, quelle que soit la page affichée.
final GlobalKey<NavigatorState> navigateurPrincipal =
GlobalKey<NavigatorState>();

class TypeNotification {
  static const String messagesParents = 'messages_parents';
  static const String mobileMoney = 'mobile_money';
  static const String promoteur = 'promoteur';
  static const String abonnement = 'abonnement';
  static const String rappelPaiements = 'rappel_paiements';
  static const String info = 'info';
}

class NotificationEcole {
  final String id;
  final String type;
  final String cle; // une seule notification par clé (mise à jour sinon)
  String titre;
  String message;
  DateTime date;
  final String ecole;

  NotificationEcole({
    required this.id,
    required this.type,
    required this.cle,
    required this.titre,
    required this.message,
    required this.date,
    required this.ecole,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'cle': cle,
    'titre': titre,
    'message': message,
    'date': date.toIso8601String(),
    'ecole': ecole,
  };

  static NotificationEcole? fromJson(dynamic j) {
    if (j is! Map) return null;
    final String id = j['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return NotificationEcole(
      id: id,
      type: j['type']?.toString() ?? TypeNotification.info,
      cle: j['cle']?.toString() ?? id,
      titre: j['titre']?.toString() ?? '',
      message: j['message']?.toString() ?? '',
      date: DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
      ecole: j['ecole']?.toString() ?? '',
    );
  }
}

// ============================================================================
// LE CENTRE (données + persistance)
// ============================================================================
class CentreNotifications extends ChangeNotifier {
  CentreNotifications._();
  static final CentreNotifications instance = CentreNotifications._();

  static const String _cleStockage = 'notifications_ecole_v1';
  static const int _maximum = 60;

  final List<NotificationEcole> _toutes = [];
  bool _charge = false;
  String _ecole = '';
  void Function(NotificationEcole n)? _ouvrir;

  /// Réduites dans la cloche.
  bool reduit = false;

  /// Le centre ne s'affiche que lorsqu'une école est ouverte (après
  /// connexion), car c'est elle qui sait ouvrir les pages.
  bool get actif => _ouvrir != null;

  /// Notifications de l'école ouverte, la plus récente en premier.
  List<NotificationEcole> get notifications => _toutes
      .where((n) => n.ecole == _ecole)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  int get nombre => notifications.length;

  Future<void> charger() async {
    if (_charge) return;
    _charge = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final brut = prefs.getString(_cleStockage);
      if (brut != null && brut.isNotEmpty) {
        final d = json.decode(brut);
        if (d is List) {
          for (final x in d) {
            final n = NotificationEcole.fromJson(x);
            if (n != null) _toutes.add(n);
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _sauvegarder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _cleStockage, json.encode(_toutes.map((n) => n.toJson()).toList()));
    } catch (_) {}
  }

  /// Appelé par l'écran d'accueil : école ouverte + façon d'ouvrir les pages.
  Future<void> activer({
    required String ecole,
    required void Function(NotificationEcole n) ouvrir,
  }) async {
    await charger();
    _ecole = ecole;
    _ouvrir = ouvrir;
    notifyListeners();
  }

  void desactiver() {
    _ouvrir = null;
    notifyListeners();
  }

  void changerEcole(String ecole) {
    if (ecole == _ecole) return;
    _ecole = ecole;
    notifyListeners();
  }

  /// Ajoute une notification, ou met à jour celle qui a la même [cle]
  /// (pas de doublon). Elle remonte en haut et le centre se rouvre.
  void publier({
    required String type,
    required String cle,
    required String titre,
    required String message,
  }) {
    final existante = _toutes
        .where((n) => n.cle == cle && n.ecole == _ecole)
        .toList();
    if (existante.isNotEmpty) {
      final n = existante.first
        ..titre = titre
        ..message = message
        ..date = DateTime.now();
      _toutes.remove(n);
      _toutes.add(n);
    } else {
      _toutes.add(NotificationEcole(
        id: 'N${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        cle: cle,
        titre: titre,
        message: message,
        date: DateTime.now(),
        ecole: _ecole,
      ));
    }
    while (_toutes.length > _maximum) {
      _toutes.removeAt(0);
    }
    reduit = false;
    notifyListeners();
    _sauvegarder();
  }

  void supprimer(NotificationEcole n) {
    _toutes.removeWhere((x) => x.id == n.id);
    if (nombre == 0) reduit = false;
    notifyListeners();
    _sauvegarder();
  }

  void toutEffacer() {
    _toutes.removeWhere((x) => x.ecole == _ecole);
    reduit = false;
    notifyListeners();
    _sauvegarder();
  }

  /// Clic sur une notification : ouvre la page concernée puis la retire.
  void ouvrir(NotificationEcole n) {
    final f = _ouvrir;
    supprimer(n);
    if (f != null) f(n);
  }

  void basculerReduit() {
    reduit = !reduit;
    notifyListeners();
  }
}

// ============================================================================
// SURVEILLANCE : détecte les événements et publie les notifications
// ============================================================================
class SurveillanceNotifications {
  SurveillanceNotifications(this.fs);

  final FraisScolaires fs;
  static const String _serverUrl = 'https://jsinf.onrender.com';
  static const String _cleEtat = 'notifications_etat_v1';

  Timer? _timer;
  bool _enCours = false;
  Map<String, dynamic> _etat = {};
  bool _etatCharge = false;

  CentreNotifications get _centre => CentreNotifications.instance;
  String get _ecole => fs.schoolCode ?? '';

  void demarrer() {
    _timer?.cancel();
    // Première vérification peu après l'ouverture, puis toutes les 2 minutes.
    Future.delayed(const Duration(seconds: 8), verifier);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => verifier());
  }

  void arreter() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _chargerEtat() async {
    if (_etatCharge) return;
    _etatCharge = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final brut = prefs.getString(_cleEtat);
      if (brut != null && brut.isNotEmpty) {
        final d = json.decode(brut);
        if (d is Map) _etat = Map<String, dynamic>.from(d);
      }
    } catch (_) {}
  }

  Future<void> _sauverEtat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cleEtat, json.encode(_etat));
    } catch (_) {}
  }

  /// État propre à l'école ouverte (un ordinateur peut changer d'école).
  Map<String, dynamic> get _etatEcole {
    final e = _etat[_ecole];
    if (e is Map<String, dynamic>) return e;
    final nouveau = <String, dynamic>{};
    _etat[_ecole] = nouveau;
    return nouveau;
  }

  Future<void> verifier() async {
    if (_enCours || _ecole.isEmpty) return;
    _enCours = true;
    try {
      await _chargerEtat();
      _centre.changerEcole(_ecole);
      _verifierAbonnement();
      _verifierDebutDeMois();
      await _verifierMobileMoney();
      await _verifierDemandesPromoteur();
      await _sauverEtat();
    } catch (_) {
      // Jamais bloquant : on réessaiera au prochain passage.
    } finally {
      _enCours = false;
    }
  }

  // --------------------------------------------------------------------------
  // 1. MESSAGES DES PARENTS (appelé par l'écran d'accueil, qui interroge déjà
  //    le serveur toutes les 30 secondes pour la pastille rouge)
  // --------------------------------------------------------------------------
  Future<void> signalerMessagesParents(int nonLus) async {
    if (_ecole.isEmpty) return;
    await _chargerEtat();
    final e = _etatEcole;
    final int avant = (e['messagesNonLus'] as num?)?.toInt() ?? 0;
    if (nonLus > avant) {
      final int nouveaux = nonLus - avant;
      _centre.publier(
        type: TypeNotification.messagesParents,
        cle: 'messages_parents',
        titre: nouveaux == 1
            ? 'Nouveau message d\'un parent'
            : '$nouveaux nouveaux messages de parents',
        message: 'Vous avez $nonLus message(s) non lu(s) de parents. '
            'Cliquez pour les lire.',
      );
    }
    if (nonLus != avant) {
      e['messagesNonLus'] = nonLus;
      await _sauverEtat();
    }
  }

  // --------------------------------------------------------------------------
  // 2. PAIEMENTS MOBILE MONEY À CONFIRMER
  // --------------------------------------------------------------------------
  Future<void> _verifierMobileMoney() async {
    try {
      final r = await http
          .get(Uri.parse('$_serverUrl/get_mobile_payments?school_code='
          '${Uri.encodeQueryComponent(_ecole)}'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final data = json.decode(r.body);
      final List liste =
      (data is Map ? data['mobile_payments'] as List? : null) ?? const [];
      final e = _etatEcole;
      final Set<String> vus = {
        ...((e['mobileVus'] as List?) ?? const []).map((x) => x.toString())
      };
      final List<Map> paiements = liste.whereType<Map>().toList();
      final ids = paiements.map((p) => p['id']?.toString() ?? '').toSet()
        ..remove('');
      final nouveaux = ids.difference(vus);
      if (nouveaux.isNotEmpty) {
        double total = 0;
        final noms = <String>[];
        for (final p in paiements) {
          total += (p['amount'] as num?)?.toDouble() ?? 0;
          if (nouveaux.contains(p['id']?.toString()) && noms.length < 2) {
            noms.add('${p['nom'] ?? ''} ${p['prenom'] ?? ''}'.trim());
          }
        }
        _centre.publier(
          type: TypeNotification.mobileMoney,
          cle: 'mobile_money',
          titre: '${paiements.length} paiement(s) Mobile Money à confirmer',
          message: '${formatMontant(total)} FC payés par téléphone'
              '${noms.isNotEmpty ? ' (dont ${noms.join(', ')}${nouveaux.length > noms.length ? '…' : ''})' : ''}'
              '. Cliquez pour les vérifier et les confirmer.',
        );
      }
      // On garde seulement les paiements encore en attente.
      e['mobileVus'] = ids.toList();
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // 3. RÉPONSE DU PROMOTEUR À UNE DEMANDE (annulation, modification…)
  // --------------------------------------------------------------------------
  Future<void> _verifierDemandesPromoteur() async {
    final e = _etatEcole;
    final Set<String> signalees = {
      ...((e['demandesSignalees'] as List?) ?? const []).map((x) => x.toString())
    };
    final Set<String> enAttente = {};
    int verifiees = 0;
    for (final eleve in fs.currentData.eleves) {
      for (final t in eleve.transactions) {
        final String reqId = t['pendingRequestId']?.toString() ?? '';
        if (reqId.isEmpty) continue;
        enAttente.add(reqId);
        if (signalees.contains(reqId) || verifiees >= 20) continue;
        verifiees++;
        final status = await fs.checkPromoterRequestStatus(reqId);
        final String st = status['status']?.toString() ?? 'pending';
        if (st != 'approved' && st != 'rejected') continue;
        signalees.add(reqId);
        final String type = t['pendingRequestType']?.toString() ?? '';
        final String quoi = type == 'cancel'
            ? 'l\'annulation'
            : (type == 'modify'
            ? 'la modification'
            : (type == 'reprint' ? 'la réimpression' : 'la demande'));
        final String nom =
        '${eleve.nom} ${eleve.postNom} ${eleve.prenom}'.trim();
        final bool ok = st == 'approved';
        _centre.publier(
          type: TypeNotification.promoteur,
          cle: 'promoteur_$reqId',
          titre: ok
              ? 'Demande APPROUVÉE par le promoteur'
              : 'Demande REFUSÉE par le promoteur',
          message: 'Le promoteur a ${ok ? 'approuvé' : 'refusé'} $quoi du '
              'paiement de ${t['mois'] ?? ''} de $nom (${eleve.classe}). '
              '${ok ? 'Cliquez pour ouvrir Paiements : la décision y est appliquée.' : 'Cliquez pour ouvrir Paiements.'}',
        );
      }
    }
    // On n'oublie que les demandes qui ne sont plus en attente.
    e['demandesSignalees'] =
        signalees.where((id) => enAttente.contains(id)).toList();
  }

  // --------------------------------------------------------------------------
  // 4. ABONNEMENT QUI EXPIRE BIENTÔT (une fois par jour)
  // --------------------------------------------------------------------------
  void _verifierAbonnement() {
    final Duration? reste = SubscriptionService.instance.remaining;
    final DateTime? fin = SubscriptionService.instance.expiresAt;
    if (reste == null || fin == null) return;
    if (reste.inDays > 7 || reste == Duration.zero) return;
    final e = _etatEcole;
    final String aujourdhui = DateTime.now().toIso8601String().substring(0, 10);
    if (e['abonnementJour'] == aujourdhui) return;
    e['abonnementJour'] = aujourdhui;
    final int jours = reste.inDays;
    String deux(int n) => n.toString().padLeft(2, '0');
    _centre.publier(
      type: TypeNotification.abonnement,
      cle: 'abonnement',
      titre: jours <= 0
          ? 'Votre abonnement expire aujourd\'hui'
          : 'Votre abonnement expire dans $jours jour(s)',
      message: 'Date de fin : ${deux(fin.day)}/${deux(fin.month)}/${fin.year}. '
          'Pensez à le renouveler pour ne pas être bloqué.',
    );
  }

  // --------------------------------------------------------------------------
  // 5. DÉBUT D'UN NOUVEAU MOIS : rappel des élèves qui n'ont pas tout payé
  //    le mois précédent (exonérés non comptés). Une fois par mois.
  // --------------------------------------------------------------------------
  void _verifierDebutDeMois() {
    final String? courant = fs.currentSchoolMonthName;
    if (courant == null) return;
    final int idx = fs.months.indexOf(courant);
    if (idx <= 0) return;
    final e = _etatEcole;
    if (e['rappelMois'] == courant) return;
    e['rappelMois'] = courant;
    final String precedent = fs.months[idx - 1];
    final r = fs.resumeOrdre(mois: [precedent]);
    final int n = r.total.pasEnOrdre;
    if (n <= 0) return;
    _centre.publier(
      type: TypeNotification.rappelPaiements,
      cle: 'rappel_$precedent',
      titre: 'Nouveau mois : $n élève(s) n\'ont pas tout payé $precedent',
      message: 'Sur ${r.total.effectif - r.total.exoneres} élève(s) qui '
          'devaient payer $precedent, ${r.total.enOrdre} ont tout payé. '
          'Cliquez pour voir la liste.',
    );
  }
}

// ============================================================================
// AFFICHAGE : couche posée au-dessus de TOUTES les pages
// ============================================================================

class _Style {
  final IconData icone;
  final Color couleur;
  const _Style(this.icone, this.couleur);
}

_Style _styleDe(String type) {
  switch (type) {
    case TypeNotification.messagesParents:
      return const _Style(Icons.forum, Color(0xFF3949AB));
    case TypeNotification.mobileMoney:
      return const _Style(Icons.phone_android, Color(0xFF2E7D32));
    case TypeNotification.promoteur:
      return const _Style(Icons.verified_user, Color(0xFF6A1B9A));
    case TypeNotification.abonnement:
      return const _Style(Icons.workspace_premium, Color(0xFFEF6C00));
    case TypeNotification.rappelPaiements:
      return const _Style(Icons.fact_check, Color(0xFFC62828));
    default:
      return const _Style(Icons.notifications, Color(0xFF546E7A));
  }
}

String _ilYA(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays == 1) return 'hier';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} jours';
  String deux(int n) => n.toString().padLeft(2, '0');
  return 'le ${deux(d.day)}/${deux(d.month)}/${d.year}';
}

/// À placer dans MaterialApp.builder : affiche les notifications par-dessus
/// l'application, sur toutes les pages.
class CoucheNotifications extends StatefulWidget {
  final Widget child;
  const CoucheNotifications({super.key, required this.child});

  @override
  State<CoucheNotifications> createState() => _CoucheNotificationsState();
}

class _CoucheNotificationsState extends State<CoucheNotifications> {
  final CentreNotifications _centre = CentreNotifications.instance;
  bool _toutVoir = false;
  bool _confirmerEffacement = false;
  Timer? _horloge;
  Timer? _delaiConfirmation;

  @override
  void initState() {
    super.initState();
    _centre.addListener(_maj);
    _centre.charger();
    // Rafraîchit « il y a X min ».
    _horloge = Timer.periodic(const Duration(minutes: 1), (_) => _maj());
  }

  @override
  void dispose() {
    _centre.removeListener(_maj);
    _horloge?.cancel();
    _delaiConfirmation?.cancel();
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final liste = _centre.actif ? _centre.notifications : <NotificationEcole>[];
    final double haut = MediaQuery.of(context).padding.top + 62;
    final double hauteurMax = MediaQuery.of(context).size.height - haut - 24;
    final double largeur =
    (MediaQuery.of(context).size.width - 24).clamp(240.0, 370.0);

    return Stack(
      children: [
        widget.child,
        if (liste.isNotEmpty)
          Positioned(
            top: haut,
            right: 12,
            width: _centre.reduit ? null : largeur,
            child: Material(
              type: MaterialType.transparency,
              child: _centre.reduit
                  ? _cloche(liste.length)
                  : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: hauteurMax),
                child: _pile(liste),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cloche(int n) {
    // Pas de Tooltip ici : cette couche est au-dessus du Navigator (aucun
    // Overlay disponible pour l'infobulle).
    return Semantics(
      label: 'Afficher les notifications',
      button: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _centre.basculerReduit,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 3)),
                ],
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: const Icon(Icons.notifications_active,
                  color: Colors.indigo, size: 26),
            ),
            Positioned(
              top: -4,
              right: -4,
              child: _pastille(n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pastille(int n) => Container(
    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFC62828),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: Text(n > 99 ? '99+' : '$n',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
  );

  Widget _pile(List<NotificationEcole> liste) {
    final int n = liste.length;
    final bool deplie = _toutVoir || n <= 3;
    final visibles = deplie ? liste : liste.take(3).toList();

    final entete = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications, size: 18, color: Colors.indigo),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Notifications ($n)',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87)),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor:
              _confirmerEffacement ? Colors.red : Colors.black54,
            ),
            onPressed: () {
              _delaiConfirmation?.cancel();
              if (_confirmerEffacement) {
                _confirmerEffacement = false;
                _toutVoir = false;
                _centre.toutEffacer();
              } else {
                setState(() => _confirmerEffacement = true);
                // Sans 2e clic dans les 4 secondes, on annule.
                _delaiConfirmation = Timer(const Duration(seconds: 4), () {
                  if (mounted && _confirmerEffacement) {
                    setState(() => _confirmerEffacement = false);
                  }
                });
              }
            },
            child: Text(_confirmerEffacement ? 'Confirmer ?' : 'Tout effacer',
                style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.expand_less, size: 20),
            onPressed: () {
              _toutVoir = false;
              _centre.basculerReduit();
            },
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        entete,
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final notif in visibles)
                  _CarteNotification(
                    key: ValueKey(notif.id),
                    notif: notif,
                    onOuvrir: () => _centre.ouvrir(notif),
                    onSupprimer: () => _centre.supprimer(notif),
                  ),
              ],
            ),
          ),
        ),
        if (n > 3)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: Icon(deplie ? Icons.expand_less : Icons.expand_more,
                    size: 18),
                label: Text(deplie
                    ? 'Afficher moins'
                    : '+ ${n - 3} autre(s) notification(s)'),
                onPressed: () => setState(() => _toutVoir = !_toutVoir),
              ),
            ),
          ),
      ],
    );
  }
}

class _CarteNotification extends StatefulWidget {
  final NotificationEcole notif;
  final VoidCallback onOuvrir;
  final VoidCallback onSupprimer;

  const _CarteNotification({
    super.key,
    required this.notif,
    required this.onOuvrir,
    required this.onSupprimer,
  });

  @override
  State<_CarteNotification> createState() => _CarteNotificationState();
}

class _CarteNotificationState extends State<_CarteNotification> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.notif;
    final st = _styleDe(n.type);
    // Arrivée en glissant depuis la droite (comme sur Mac).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(60 * (1 - v), 0), child: child),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _survol = true),
        onExit: (_) => setState(() => _survol = false),
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: st.couleur, width: 4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _survol ? 0.22 : 0.14),
                blurRadius: _survol ? 16 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onOuvrir,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: st.couleur.withValues(alpha: 0.12),
                      child: Icon(st.icone, color: st.couleur, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.titre,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: Colors.black87)),
                          const SizedBox(height: 2),
                          Text(n.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5, color: Colors.black87)),
                          const SizedBox(height: 4),
                          Row(children: [
                            Text(_ilYA(n.date),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black45)),
                            const Spacer(),
                            Text('Ouvrir ›',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: st.couleur)),
                          ]),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close,
                          size: 18, color: Colors.black45),
                      onPressed: widget.onSupprimer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
