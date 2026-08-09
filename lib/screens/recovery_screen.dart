import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import '../app_state.dart';
import 'school_home_screen.dart';

const String _serverUrl = "https://jsinf.onrender.com";

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  // Étape courante : 'enter_id' | 'first_setup' | 'login'
  String _step = 'enter_id';

  final _idController       = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();

  bool    _isLoading    = false;
  bool    _obscure      = true;
  String? _errorMsg;

  String? _schoolName;
  String? _schoolCode;
  String? _city;
  String? _director;

  // ====================================================================
  // ⚡ NOUVEAU — Nettoyage robuste de l'ID saisi/collé.
  //
  // Sur Windows, un copier-coller depuis WhatsApp, un PDF, Word ou un
  // email peut insérer des espaces insécables (U+00A0), des retours à
  // la ligne, des tabulations ou des espaces au milieu du texte — invi-
  // sibles à l'œil. Sur Mac, le comportement du presse-papier est
  // souvent plus "propre", ce qui peut donner l'impression que "ça
  // marche sur Mac mais pas sur PC" alors que la vraie cause est un ID
  // mal collé. On retire donc TOUS les espaces/caractères invisibles,
  // pas seulement ceux en début/fin.
  // ====================================================================
  String _sanitizeId(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll('\u00A0', '')      // espace insécable
        .replaceAll(RegExp(r'\s+'), ''); // tout espace/tab/retour ligne
  }

  String _sanitizeCode(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll('\u00A0', '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  // ====================================================================
  // ÉTAPE 1 — Vérification de l'ID
  // ====================================================================
  Future<void> _verifyId() async {
    final id = _sanitizeId(_idController.text);
    if (id.isEmpty) {
      setState(() => _errorMsg = "Veuillez entrer votre ID de connexion.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg  = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/school/verify_registration_id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'registration_id': id}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['valid'] == true) {
          // ✅ Première connexion — activation
          setState(() {
            _schoolName = data['school_name'];
            _schoolCode = data['school_code'];
            _city       = data['city'];
            _director   = data['director'];
            _step       = 'first_setup';
            _errorMsg   = null;
          });
        } else if (data['already_used'] == true) {
          // ✅ École déjà activée → login normal
          // ⚡ On récupère le VRAI school_code depuis le serveur au lieu
          // d'utiliser l'ID de registration comme school_code.
          await _fetchRealSchoolCode(id, data);
        } else {
          setState(() => _errorMsg = data['error'] ?? 'ID invalide.');
        }
      } else {
        // ⚡ CORRIGÉ : on affiche le vrai statut/contenu au lieu d'un
        // message générique, pour pouvoir diagnostiquer sur le PC.
        setState(() => _errorMsg =
        "Erreur serveur (statut ${response.statusCode}).\n${response.body}");
      }
    } on SocketException catch (e) {
      setState(() => _errorMsg =
      "Aucune connexion réseau détectée sur cet appareil.\n"
          "Vérifiez votre connexion internet et le pare-feu Windows.\n"
          "Détail technique : $e");
    } on HandshakeException catch (e) {
      setState(() => _errorMsg =
      "Erreur de certificat de sécurité (TLS) sur cet appareil.\n"
          "Détail technique : $e");
    } catch (e) {
      setState(() =>
      _errorMsg = "Connexion impossible. Détail technique : $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ====================================================================
  // ⚡ CORRECTIF PROBLÈME 2
  // Récupère le vrai school_code (ex: "MAPENDO") à partir de l'ID
  // de registration (ex: "EDU-A3K9-BZ12-Q7M4").
  // Sans ça, le school_code était l'ID EDU-XXXX lui-même, ce qui
  // causait le backup sous le mauvais nom de fichier sur le serveur,
  // rendant les élèves introuvables depuis l'app parent.
  // ====================================================================
  Future<void> _fetchRealSchoolCode(
      String regId, Map<String, dynamic> verifyData) async {
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/school/get_info_by_reg_id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'registration_id': regId}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['found'] == true) {
          if (mounted) {
            setState(() {
              // ⚡ Normalisation systématique pour éviter toute
              // divergence de casse/espaces entre appareils.
              _schoolCode = _sanitizeCode(data['school_code'] as String);
              _schoolName = data['school_name'];
              _step       = 'login';
              _errorMsg   = null;
            });
          }
          return;
        }
      }
    } catch (_) {
      // Si le réseau échoue, on essaie avec les données déjà reçues
      // (voir fallback ci-dessous).
    }

    // Fallback : utiliser les données du verify_registration_id si disponibles
    if (verifyData['school_code'] != null) {
      setState(() {
        _schoolCode = _sanitizeCode(verifyData['school_code'] as String);
        _schoolName = verifyData['school_name'] ?? "Votre école";
        _step       = 'login';
        _errorMsg   = null;
      });
    } else {
      setState(() => _errorMsg =
      "Impossible de récupérer les infos de l'école.\n"
          "Vérifiez votre connexion internet sur cet appareil.");
    }
  }

  // ====================================================================
  // ÉTAPE 2 — Première activation
  // ====================================================================
  Future<void> _activateSchool() async {
    final password = _passwordController.text.trim();
    final confirm  = _confirmController.text.trim();

    if (password.length < 6) {
      setState(() =>
      _errorMsg = "Le mot de passe doit contenir au moins 6 caractères.");
      return;
    }
    if (password != confirm) {
      setState(() => _errorMsg = "Les deux mots de passe ne correspondent pas.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg  = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/school/activate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'registration_id': _sanitizeId(_idController.text),
          'password':        password,
          'school_name':     _schoolName,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          final appState = Provider.of<AppState>(context, listen: false);
          // ⚡ On sauvegarde le VRAI school_code retourné par le serveur,
          // normalisé pour rester identique sur tous les appareils.
          final realCode = _sanitizeCode(data['school_code'] as String);
          await appState.setSchoolCode(realCode);
          await appState.updateSchoolName(data['school_name']);
          await appState.setBackupPassword(password);
          await _showWelcomeDialog(data['school_name']);
        }
      } else {
        String err = 'Erreur serveur';
        try {
          err = jsonDecode(response.body)['error'] ?? err;
        } catch (_) {}
        // ⚡ CORRIGÉ : on ajoute le statut HTTP pour le diagnostic.
        setState(() => _errorMsg = "$err (statut ${response.statusCode})");
      }
    } on SocketException catch (e) {
      setState(() => _errorMsg =
      "Aucune connexion réseau détectée sur cet appareil.\n"
          "Vérifiez votre connexion internet et le pare-feu Windows.\n"
          "Détail technique : $e");
    } catch (e) {
      setState(() =>
      _errorMsg = "Connexion impossible. Détail technique : $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ====================================================================
  // ÉTAPE 3 — Login normal
  // ====================================================================
  Future<void> _loginWithPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMsg = "Veuillez entrer votre mot de passe.");
      return;
    }
    if (_schoolCode == null) {
      setState(() => _errorMsg =
      "Code école introuvable. Recommencez depuis l'étape 1.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg  = null;
    });

    try {
      // ⚡ On utilise le VRAI school_code (ex: "MAPENDO"), pas l'ID EDU-XXXX
      final verifyResponse = await http.post(
        Uri.parse('$_serverUrl/verify_password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'school_code': _schoolCode,
          'password':    password,
        }),
      ).timeout(const Duration(seconds: 15));

      if (verifyResponse.statusCode == 200) {
        final vData = jsonDecode(verifyResponse.body);
        if (vData['valid'] == true) {
          if (mounted) {
            final appState =
            Provider.of<AppState>(context, listen: false);
            await appState.setSchoolCode(_schoolCode!);
            await appState.setBackupPassword(password);

            // Récupérer le nom officiel de l'école
            try {
              final restoreResponse = await http.get(
                Uri.parse('$_serverUrl/restore?school_code=$_schoolCode'),
              ).timeout(const Duration(seconds: 10));
              if (restoreResponse.statusCode == 200) {
                final rData = jsonDecode(restoreResponse.body);
                final name  = rData['config']?['schoolName'] ?? '';
                if (name.isNotEmpty) {
                  await appState.updateSchoolName(name);
                }
              }
            } catch (_) {
              // Si le restore échoue, on continue quand même
              if (_schoolName != null) {
                await appState.updateSchoolName(_schoolName!);
              }
            }

            _goToHome();
          }
        } else {
          setState(() => _errorMsg = "Mot de passe incorrect.");
        }
      } else if (verifyResponse.statusCode == 404) {
        // ⚡ CORRIGÉ : message précis + statut, c'est exactement le cas
        // où le backup n'a jamais atteint le serveur pour ce school_code.
        setState(() => _errorMsg =
        "Aucune sauvegarde trouvée sur le serveur pour le code "
            "\"$_schoolCode\".\n"
            "Assurez-vous d'avoir fait \"Sauvegarder sur le Serveur\" "
            "au moins une fois depuis un appareil connecté à internet.");
      } else {
        setState(() => _errorMsg =
        "Erreur serveur (statut ${verifyResponse.statusCode}).\n"
            "${verifyResponse.body}");
      }
    } on SocketException catch (e) {
      setState(() => _errorMsg =
      "Aucune connexion réseau détectée sur cet appareil.\n"
          "Vérifiez votre connexion internet et le pare-feu Windows.\n"
          "Détail technique : $e");
    } catch (e) {
      setState(() =>
      _errorMsg = "Connexion impossible. Détail technique : $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ====================================================================
  // DIALOGUE DE BIENVENUE
  // ====================================================================
  Future<void> _showWelcomeDialog(String schoolName) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.school, size: 64, color: Colors.indigo),
            const SizedBox(height: 16),
            const Text(
              "Bienvenue sur EduPay !",
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              schoolName,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.indigo,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              "Votre compte a été activé avec succès.\n"
                  "Vous pouvez maintenant gérer vos frais scolaires.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _goToHome();
              },
              child: const Text("Commencer"),
            ),
          ),
        ],
      ),
    );
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SchoolHomeScreen()),
          (route) => false,
    );
  }

  // ====================================================================
  // BUILD
  // ====================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.school_rounded,
                  size: 80, color: Colors.indigo),
              const SizedBox(height: 16),
              const Text(
                "EduPay School RDC",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _stepSubtitle(),
                textAlign: TextAlign.center,
                style:
                const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 40),

              if (_step == 'enter_id')   _buildEnterIdStep(),
              if (_step == 'first_setup') _buildFirstSetupStep(),
              if (_step == 'login')      _buildLoginStep(),

              if (_errorMsg != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: TextStyle(color: Colors.red.shade700),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  String _stepSubtitle() {
    switch (_step) {
      case 'enter_id':
        return "Entrez l'ID de connexion fourni\npar l'administrateur EduPay";
      case 'first_setup':
        return "Première connexion — Définissez votre mot de passe";
      case 'login':
        return "Reconnectez-vous à votre compte";
      default:
        return '';
    }
  }

  Widget _buildEnterIdStep() {
    return Column(
      children: [
        TextField(
          controller: _idController,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: "ID de connexion",
            hintText: "Ex: EDU-A3K9-BZ12-Q7M4",
            prefixIcon:
            const Icon(Icons.vpn_key, color: Colors.indigo),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Colors.indigo, width: 2),
            ),
          ),
          onSubmitted: (_) => _verifyId(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isLoading ? null : _verifyId,
            child: _isLoading
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Text("Continuer",
                style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Cet ID vous est remis par l'administrateur\n"
              "EduPay lors de l'enregistrement de votre école.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildFirstSetupStep() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo.withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigo.withAlpha(40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "École identifiée :",
                style: TextStyle(
                    color: Colors.indigo,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                _schoolName ?? '',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
              if (_city != null) Text(_city!),
              if (_director != null)
                Text("Directeur : $_director"),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "Définissez votre mot de passe :",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: "Mot de passe (min 6 caractères)",
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility
                  : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _obscure = !_obscure),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Colors.indigo, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: "Confirmer le mot de passe",
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Colors.indigo, width: 2),
            ),
          ),
          onSubmitted: (_) => _activateSchool(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isLoading ? null : _activateSchool,
            child: _isLoading
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Text("Activer mon compte",
                style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _step     = 'enter_id';
            _errorMsg = null;
          }),
          child: const Text("← Retour"),
        ),
      ],
    );
  }

  Widget _buildLoginStep() {
    return Column(
      children: [
        if (_schoolName != null && _schoolName != "Votre école")
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _schoolName!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        TextField(
          controller: _passwordController,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: "Mot de passe",
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility
                  : Icons.visibility_off),
              onPressed: () =>
                  setState(() => _obscure = !_obscure),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Colors.indigo, width: 2),
            ),
          ),
          onSubmitted: (_) => _loginWithPassword(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isLoading ? null : _loginWithPassword,
            child: _isLoading
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
                : const Text("Se connecter",
                style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _step     = 'enter_id';
            _errorMsg = null;
            _passwordController.clear();
          }),
          child: const Text("← Utiliser un autre ID"),
        ),
      ],
    );
  }
}