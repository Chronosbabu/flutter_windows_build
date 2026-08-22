import 'dart:async';
import 'dart:io';

/// ⚡ NOUVEAU — Résolveur d'adresse serveur (LOCAL vs INTERNET).
///
/// Contexte : l'application peut désormais fonctionner de deux façons :
///   1. EN RÉSEAU LOCAL (LAN pur, sans internet) — le PC principal active
///      manuellement le "Point d'accès mobile" de Windows. Windows lui
///      attribue TOUJOURS la même adresse IP de passerelle :
///      `192.168.137.1`. C'est une constante du système d'exploitation
///      (technologie ICS), pas une IP attribuée par un routeur — elle ne
///      change donc jamais, peu importe l'école ou l'appareil.
///   2. EN LIGNE — le serveur central sur Render (`jsinf.onrender.com`),
///      utilisé quand l'appareil a une vraie connexion internet.
///
/// Ce fichier centralise la décision "à qui je parle maintenant ?" pour
/// que TOUT le reste du code (admin, sous-utilisateurs) n'ait plus jamais
/// à écrire une URL en dur : il appelle `NetworkResolver.resolve()` et
/// obtient la bonne base d'URL, sans configuration manuelle d'IP nulle
/// part dans l'app.
///
/// Stratégie de détection : un simple test de connexion TCP (pas une
/// requête HTTP complète) vers `192.168.137.1:8089` avec un délai très
/// court (600 ms). Si ça répond, on est sur le réseau local du point
/// d'accès — on l'utilise en priorité (c'est toujours le cas le plus
/// rapide, et il n'a pas besoin d'internet). Sinon, on bascule sur le
/// serveur internet.
///
/// Le résultat est mis en cache quelques secondes pour ne pas refaire ce
/// test avant chaque appel HTTP (ce qui ralentirait inutilement l'app) —
/// mais il est réévalué régulièrement, pour qu'un changement de situation
/// (l'admin vient d'éteindre le point d'accès, ou vient de retrouver
/// internet) soit pris en compte rapidement, sans redémarrer l'app.
class NetworkResolver {
  /// IP fixe et permanente du PC hébergeant le point d'accès Windows.
  /// Ne JAMAIS rendre ce champ configurable dans un écran : c'est une
  /// constante du système d'exploitation, pas un réglage utilisateur.
  static const String localHost = '192.168.137.1';

  /// Port du petit serveur local embarqué (voir local_server_service.dart).
  /// Choisi au hasard dans la plage des ports "utilisateur" pour éviter
  /// les collisions avec des services Windows connus.
  static const int localPort = 8089;

  static const String localBaseUrl = 'http://$localHost:$localPort';
  static const String internetBaseUrl = 'https://jsinf.onrender.com';

  static String? _cachedBase;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(seconds: 15);

  /// Renvoie la base d'URL à utiliser MAINTENANT pour un appel HTTP,
  /// par exemple : `'${await NetworkResolver.resolve()}/restore?...'`.
  ///
  /// `forceRefresh: true` ignore le cache et refait le test tout de
  /// suite — utile après une action explicite de l'utilisateur (bouton
  /// "Rafraîchir") où on veut être sûr d'avoir la situation la plus
  /// récente plutôt qu'une valeur en cache potentiellement périmée.
  static Future<String> resolve({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedBase != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cachedBase!;
    }
    final base = await _detect();
    _cachedBase = base;
    _cachedAt = DateTime.now();
    return base;
  }

  static Future<String> _detect() async {
    if (await _canReachLocal()) return localBaseUrl;
    return internetBaseUrl;
  }

  static Future<bool> _canReachLocal() async {
    try {
      final socket = await Socket.connect(
        localHost,
        localPort,
        timeout: const Duration(milliseconds: 600),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Vrai si la dernière résolution a choisi le serveur local — utile
  /// pour afficher un petit badge "Mode local (sans internet)" dans les
  /// écrans, si on veut informer l'utilisateur de la situation actuelle.
  static bool get lastResolvedWasLocal => _cachedBase == localBaseUrl;

  /// Force une nouvelle détection au prochain appel de `resolve()`,
  /// ignorant le cache. À utiliser après un changement connu de réseau
  /// (ex: bouton "Rafraîchir" dans un écran, retour d'arrière-plan).
  static void invalidateCache() {
    _cachedBase = null;
    _cachedAt = null;
  }
}