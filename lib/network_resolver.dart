import 'dart:async';
import 'dart:io';

/// ⚡ NOUVEAU — Résolveur d'adresse serveur côté application CLIENT
/// (sous-utilisateur), strictement symétrique du NetworkResolver côté
/// admin (voir lib/network_resolver.dart du projet admin).
///
/// Contexte : le PC principal (admin) peut activer manuellement le
/// "Point d'accès mobile" de Windows. Windows attribue TOUJOURS la même
/// adresse IP de passerelle à ce point d'accès : `192.168.137.1` (c'est
/// une constante du système d'exploitation — technologie ICS — pas une
/// IP de routeur, elle ne change donc jamais). Un appareil client
/// connecté à ce même WiFi peut donc toujours essayer cette IP en
/// premier, sans qu'aucune saisie manuelle d'adresse ne soit nécessaire.
///
/// Stratégie : un test de connexion TCP (pas une requête HTTP complète)
/// vers `192.168.137.1:8089` avec un délai court (600 ms). Si ça
/// répond, on est sur le réseau local du point d'accès de l'admin — on
/// l'utilise en priorité. Sinon, on bascule sur le serveur internet.
///
/// TOUT appel HTTP de l'app cliente doit désormais passer par
/// `await NetworkResolver.resolve()` au lieu d'utiliser directement la
/// constante `serverUrl` codée en dur.
class NetworkResolver {
  /// IP fixe et permanente du PC hébergeant le point d'accès Windows.
  static const String localHost = '192.168.137.1';

  /// Port du petit serveur local embarqué dans l'app admin (voir
  /// local_server_service.dart du projet admin).
  static const int localPort = 8089;

  static const String localBaseUrl = 'http://$localHost:$localPort';
  static const String internetBaseUrl = 'https://jsinf.onrender.com';

  static String? _cachedBase;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(seconds: 15);

  /// Renvoie la base d'URL à utiliser MAINTENANT pour un appel HTTP,
  /// par exemple : `'${await NetworkResolver.resolve()}/verify_key'`.
  ///
  /// `forceRefresh: true` ignore le cache et refait le test tout de
  /// suite — à utiliser après une action explicite (bouton
  /// "Rafraîchir") où on veut la situation la plus récente.
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
  /// pour afficher un petit badge "Mode local" dans les écrans.
  static bool get lastResolvedWasLocal => _cachedBase == localBaseUrl;

  /// Force une nouvelle détection au prochain appel de `resolve()`.
  static void invalidateCache() {
    _cachedBase = null;
    _cachedAt = null;
  }
}