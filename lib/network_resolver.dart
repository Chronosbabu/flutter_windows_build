import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// ⚡ CORRIGÉ — Résolveur d'adresse serveur côté application CLIENT
/// (sous-utilisateur).
///
/// Auparavant : ce fichier testait une IP FIXE codée en dur
/// (192.168.137.1, garantie uniquement par le partage de connexion
/// Windows). Cela cassait dès que le réseau local n'était plus fourni
/// par ce mécanisme précis (par exemple un point d'accès ESP32 dédié).
///
/// Maintenant : découverte AUTOMATIQUE par diffusion UDP. Le serveur
/// admin (voir local_server_service.dart, méthode
/// `_startDiscoveryResponder`) répond déjà à toute demande de
/// découverte avec SA vraie adresse IP actuelle, quel que soit le
/// matériel qui fournit le réseau (PC en partage de connexion, ESP32,
/// routeur classique...). Ce fichier n'a donc plus besoin de connaître
/// une IP à l'avance : il la demande au réseau.
///
/// Ordre de résolution, du plus rapide/fiable au plus lent :
/// 1. Dernière IP locale qui a fonctionné (reconnexion instantanée).
/// 2. Découverte automatique par diffusion UDP (cas normal).
/// 3. Adresse IP saisie manuellement par l'utilisateur, UNIQUEMENT si
///    les deux étapes précédentes ont échoué (filet de sécurité pour
///    les rares réseaux qui bloquent les diffusions UDP).
/// 4. Serveur internet, en dernier recours.
class NetworkResolver {
  static const int localPort = 8089;
  static const int discoveryPort = 8090;
  static const String _discoveryMessage = 'SCHOOLAPP_DISCOVER';

  static const String internetBaseUrl = 'https://jsinf.onrender.com';

  static const String _kManualIpPrefKey = 'sub_manual_server_ip';
  static const String _kLastKnownHostPrefKey = 'sub_last_known_local_host';

  static String? _cachedBase;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(seconds: 15);

  /// Renvoie la base d'URL à utiliser MAINTENANT pour un appel HTTP,
  /// par exemple : `'${await NetworkResolver.resolve()}/verify_key'`.
  ///
  /// `forceRefresh: true` ignore le cache et refait la détection tout
  /// de suite — à utiliser après une action explicite (bouton
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
    // 1) Reconnexion rapide : on retente d'abord la dernière adresse
    // qui fonctionnait, sans attendre la diffusion UDP.
    final lastHost = await _getLastKnownHost();
    if (lastHost != null &&
        await _canReachTcp(lastHost, localPort, timeoutMs: 500)) {
      return 'http://$lastHost:$localPort';
    }

    // 2) Découverte automatique — le cas normal, sans aucune saisie.
    final discovered = await _discoverViaUdp();
    if (discovered != null) {
      await _rememberLastKnownHost(discovered);
      return 'http://$discovered:$localPort';
    }

    // 3) Filet de sécurité : adresse indiquée manuellement par
    // l'utilisateur dans les Paramètres, si la découverte a échoué.
    final manualIp = await getManualIp();
    if (manualIp != null && manualIp.isNotEmpty) {
      if (await _canReachTcp(manualIp, localPort, timeoutMs: 700)) {
        await _rememberLastKnownHost(manualIp);
        return 'http://$manualIp:$localPort';
      }
    }

    // 4) Rien de local trouvé : serveur internet.
    return internetBaseUrl;
  }

  static Future<bool> _canReachTcp(String host, int port,
      {int timeoutMs = 600}) async {
    try {
      final socket = await Socket.connect(host, port,
          timeout: Duration(milliseconds: timeoutMs));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Diffuse une demande de découverte sur le réseau local et attend
  /// la réponse du serveur admin (voir local_server_service.dart côté
  /// admin, qui répond déjà à ce message avec sa vraie IP actuelle).
  static Future<String?> _discoverViaUdp() async {
    RawDatagramSocket? socket;
    StreamSubscription? sub;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final completer = Completer<String?>();
      final payload = utf8.encode(_discoveryMessage);

      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        try {
          final message = utf8.decode(datagram.data);
          final decoded = jsonDecode(message) as Map<String, dynamic>;
          if (decoded['service'] == 'schoolapp' && decoded['host'] != null) {
            if (!completer.isCompleted) {
              completer.complete(decoded['host'].toString());
            }
          }
        } catch (_) {
          // Paquet non conforme — ignoré, ce n'est pas notre serveur.
        }
      });

      void broadcast() {
        try {
          socket?.send(
              payload, InternetAddress('255.255.255.255'), discoveryPort);
        } catch (_) {}
      }

      // Deux envois successifs : un paquet UDP isolé se perd parfois
      // sur WiFi, ce petit doublon rend la découverte plus fiable sans
      // ralentir sensiblement le cas où tout fonctionne du premier coup.
      broadcast();
      Future.delayed(const Duration(milliseconds: 300), broadcast);

      final result = await completer.future.timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () => null,
      );
      return result;
    } catch (_) {
      return null;
    } finally {
      await sub?.cancel();
      socket?.close();
    }
  }

  static Future<void> _rememberLastKnownHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastKnownHostPrefKey, host);
  }

  static Future<String?> _getLastKnownHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastKnownHostPrefKey);
  }

  /// ⚡ NOUVEAU — Adresse IP de secours, saisie manuellement par
  /// l'utilisateur dans les Paramètres. N'est utilisée QUE si la
  /// découverte automatique échoue (voir `_detect()`), jamais en
  /// priorité — pour les rares réseaux qui bloquent les diffusions UDP
  /// (certains routeurs avec "isolation des clients").
  static Future<String?> getManualIp() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kManualIpPrefKey);
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  static Future<void> setManualIp(String? ip) async {
    final prefs = await SharedPreferences.getInstance();
    if (ip == null || ip.trim().isEmpty) {
      await prefs.remove(_kManualIpPrefKey);
    } else {
      await prefs.setString(_kManualIpPrefKey, ip.trim());
    }
    invalidateCache();
  }

  /// Vrai si la dernière résolution a choisi une adresse locale
  /// (découverte, reconnexion rapide, ou secours manuel) plutôt que le
  /// serveur internet.
  static bool get lastResolvedWasLocal =>
      _cachedBase != null && _cachedBase != internetBaseUrl;

  /// Force une nouvelle détection au prochain appel de `resolve()`.
  static void invalidateCache() {
    _cachedBase = null;
    _cachedAt = null;
  }
}