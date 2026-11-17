import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../frais_scolaires.dart';
import '../app_state.dart';
import '../services/epson_printer_service.dart';
import 'enregistrer_eleve_screen.dart';
import 'paiement_eleve_screen.dart';
import 'repartition_screen.dart';
import 'settings_screen.dart';
import 'student_list_screen.dart';
import 'admin_dashboard_screen.dart';
import 'recus_screen.dart';
import 'liste_ordre_screen.dart';
// ⚡ NOUVEAU — Module Discipline
import 'discipline_registre_screen.dart';
// ⚡ NOUVEAU — Autres Frais de Paiement (éphémères)
import 'autres_frais_screen.dart';
// ⚡ NOUVEAU — Écran dédié à la génération de rapport PDF (remplace
// l'ancienne boîte de dialogue) : filtres + gestion des signataires.
import 'report_generation_screen.dart';
// ⚡ NOUVEAU — Messagerie école ⇄ parents (confirmation de lecture +
// réception des messages des parents)
import 'messages_envoyes_screen.dart';
import 'messages_parents_screen.dart';
// ⚡ NOUVEAU — Mise en forme des reçus (formats par défaut + personnalisé)
import 'receipt_layout_screen.dart';

class SchoolHomeScreen extends StatefulWidget {
  const SchoolHomeScreen({super.key});

  @override
  State<SchoolHomeScreen> createState() => _SchoolHomeScreenState();
}

class _SchoolHomeScreenState extends State<SchoolHomeScreen> {
  late FraisScolaires fraisScolaires;

  // ⚡ évite de ré-écraser schoolCode à chaque frame/build tant que le
  // chargement initial n'est pas terminé.
  bool _initialLoadDone = false;

  // ⚡ NOUVEAU — état du bouton SOS de sauvegarde rapide
  bool _sosBackupEnCours = false;

  // ⚡ NOUVEAU — nombre de messages de parents non lus (pastille rouge)
  int _parentUnread = 0;
  bool _refreshingUnread = false;
  Timer? _unreadTimer;

  @override
  void initState() {
    super.initState();
    fraisScolaires = FraisScolaires();
    _installerResolveurInfosEleve();
    _loadData();
    // Actualisation automatique de la pastille « messages des parents ».
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !_initialLoadDone) return;
      _refreshParentUnread();
    });
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // ⚡ NOUVEAU — INFORMATIONS DE L'ÉLÈVE POUR LES REÇUS
  // (adresse, père, mère, date de naissance, champs personnalisés).
  // Utilisé uniquement pour la mise en page : ne touche pas à
  // la communication avec l'imprimante.
  // ============================================================
  String _normaliserNom(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _formaterDate(String brut) {
    final v = brut.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v)) {
      final p = v.substring(0, 10).split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return v;
  }

  void _installerResolveurInfosEleve() {
    EscPosPrinterService.studentInfoResolver =
        (String studentId, String studentName) {
      final Map<String, String> out = <String, String>{};
      try {
        dynamic eleve;
        if (studentId.isNotEmpty) {
          eleve = fraisScolaires.trouverEleveParId(studentId);
        }
        if (eleve == null) {
          final cible = _normaliserNom(studentName);
          for (final e in fraisScolaires.currentData.eleves) {
            if (_normaliserNom('${e.nom} ${e.postNom} ${e.prenom}') == cible) {
              eleve = e;
              break;
            }
          }
        }
        if (eleve == null) return out;

        String lire(dynamic Function() f) {
          try {
            final v = f();
            return v == null ? '' : v.toString().trim();
          } catch (_) {
            return '';
          }
        }

        out['adresse'] = lire(() => eleve.adresse);
        out['pere'] = lire(() => eleve.pereNom);
        out['mere'] = lire(() => eleve.mereNom);
        out['dateNaissance'] = _formaterDate(lire(() => eleve.dateNaissance));
        try {
          final cf = eleve.customFields;
          if (cf is Map) {
            cf.forEach((k, v) {
              out['cf:$k'] = v == null ? '' : v.toString().trim();
            });
          }
        } catch (_) {}
      } catch (_) {}
      return out;
    };
  }

  Future<void> _loadData() async {
    final appState = Provider.of<AppState>(context, listen: false);

    await fraisScolaires.loadData();

    final localCode = fraisScolaires.schoolCode;
    final stateCode = appState.schoolCode;

    if (stateCode != null && stateCode.isNotEmpty) {
      if (localCode != stateCode) {
        fraisScolaires.schoolCode = stateCode;
        await fraisScolaires.saveData();
      }
    } else if (localCode != null && localCode.isNotEmpty) {
      await appState.setSchoolCode(localCode);
    }

    _initialLoadDone = true;
    if (mounted) setState(() {});
    _refreshParentUnread();
  }

  // ⚡ NOUVEAU — interroge le serveur pour la pastille rouge.
  Future<void> _refreshParentUnread() async {
    if (_refreshingUnread) return;
    final code = fraisScolaires.schoolCode;
    if (code == null || code.isEmpty) return;
    _refreshingUnread = true;
    try {
      final n = await fraisScolaires.getParentUnreadTotal();
      if (mounted && n != _parentUnread) {
        setState(() => _parentUnread = n);
      }
    } catch (_) {
      // hors-ligne : on garde la dernière valeur
    } finally {
      _refreshingUnread = false;
    }
  }

  // ⚡ NOUVEAU — ouvre un écran puis rafraîchit la pastille au retour.
  Future<void> _openAndRefresh(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (mounted) _refreshParentUnread();
  }

  // ============================================================
  // ⚡ NOUVEAU — BOUTON SOS : SAUVEGARDE RAPIDE SUR LE SERVEUR
  // ============================================================
  Future<void> _confirmerSosBackup() async {
    final appState = Provider.of<AppState>(context, listen: false);

    // Si le code école ou le mot de passe de sauvegarde ne sont pas
    // encore configurés, impossible de sauvegarder — on prévient
    // l'utilisateur au lieu de planter silencieusement.
    if (appState.schoolCode == null ||
        appState.schoolCode!.isEmpty ||
        appState.backupPassword == null ||
        appState.backupPassword!.isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text("Configuration requise"),
            ],
          ),
          content: const Text(
            "Pour utiliser la sauvegarde rapide, vous devez d'abord "
                "définir un Code École et un Mot de Passe de Sauvegarde "
                "dans les Paramètres (une seule fois).",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Fermer"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SettingsScreen(fraisScolaires: fraisScolaires),
                  ),
                );
              },
              child: const Text("Aller aux Paramètres"),
            ),
          ],
        ),
      );
      return;
    }

    // Boîte de dialogue d'alerte de confirmation rapide
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_upload, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text("Sauvegarde Rapide"),
          ],
        ),
        content: const Text(
          "Voulez-vous sauvegarder immédiatement toutes les données "
              "sur le serveur ?\n\n"
              "Cela mettra à jour le résumé du promoteur et permettra "
              "aux parents de retrouver leurs enfants.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.cloud_upload),
            label: const Text("Sauvegarder Maintenant"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _sosBackupEnCours = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⏳ Sauvegarde en cours..."),
          duration: Duration(seconds: 2),
        ),
      );
    }

    final result = await fraisScolaires.backupToServer(
      appState.schoolCode!,
      appState.backupPassword!,
    );

    if (!mounted) return;

    setState(() => _sosBackupEnCours = false);

    final bool success = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? "✅ Sauvegarde réussie ! Données à jour sur le serveur."
            : "❌ Échec de la sauvegarde : ${result['error'] ?? 'erreur inconnue'}"),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: Duration(seconds: success ? 3 : 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    if (_initialLoadDone &&
        appState.schoolCode != null &&
        appState.schoolCode!.isNotEmpty &&
        fraisScolaires.schoolCode != appState.schoolCode) {
      fraisScolaires.schoolCode = appState.schoolCode;
      fraisScolaires.saveData();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${appState.schoolName} - ${fraisScolaires.currentYear}",
        ),
        centerTitle: true,
        actions: [
          // ⚡ NOUVEAU — bouton SOS également accessible depuis l'AppBar
          IconButton(
            icon: _sosBackupEnCours
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(Icons.cloud_upload),
            tooltip: "Sauvegarde Rapide (SOS)",
            onPressed: _sosBackupEnCours ? null : _confirmerSosBackup,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    SettingsScreen(fraisScolaires: fraisScolaires),
              ),
            ),
          ),
        ],
      ),
      // ⚡ NOUVEAU — Bouton SOS flottant, très visible, en forme d'alerte
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sosBackupEnCours ? null : _confirmerSosBackup,
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        icon: _sosBackupEnCours
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : const Icon(Icons.sos),
        label: Text(_sosBackupEnCours ? "Sauvegarde..." : "SOS Sauvegarde"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ==================== BANDEAU SOS D'ALERTE ====================
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade300, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red.shade700, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Besoin de sauvegarder rapidement ? Utilisez le "
                          "bouton SOS ci-dessous ou en haut à droite — "
                          "pas besoin d'aller dans les Paramètres.",
                      style: TextStyle(fontSize: 12.5, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: _sosBackupEnCours
                        ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.sos, size: 18),
                    label: const Text("SOS"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _sosBackupEnCours ? null : _confirmerSosBackup,
                  ),
                ],
              ),
            ),

            // ==================== CARTE RÉSUMÉ ====================
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      'Année : ${fraisScolaires.currentYear}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Élèves : ${fraisScolaires.currentData.eleves.length}',
                    ),
                    Text(
                      'Total Collecté : '
                          '${fraisScolaires.getYearTotalCollected().toStringAsFixed(0)} FC',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ==================== GRILLE DES BOUTONS ====================
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
              children: [
                _buildCard(
                  Icons.person_add,
                  "Ajouter Élève",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EnregistrerEleveScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.payment,
                  "Paiements",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaiementEleveScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                // ⚡ NOUVEAU — Autres Frais de Paiement (éphémères, ex:
                // Frais de l'État, Frais d'Aide...).
                _buildCard(
                  Icons.request_page,
                  "Autres Frais",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AutresFraisScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.list_alt,
                  "Registre des Élèves",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentListScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                // ⚡ CORRIGÉ — ouvre désormais une vraie page dédiée
                // (ReportGenerationScreen) au lieu d'une boîte de
                // dialogue, avec gestion des signataires du rapport.
                _buildCard(
                  Icons.picture_as_pdf,
                  "Rapport PDF",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportGenerationScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.share,
                  "Répartition",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RepartitionScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.admin_panel_settings,
                  "Admin Dashboard",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminDashboardScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.receipt_long,
                  "Historique Reçus",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RecusScreen(fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                // ⚡ NOUVEAU — choix du format des reçus (grand format,
                // classique compact ou personnalisé) + infos de l'élève.
                _buildCard(
                  Icons.tune,
                  "Mise en forme reçus",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptLayoutScreen(
                          fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                _buildCard(
                  Icons.fact_check,
                  "Liste En Ordre",
                      () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ListeOrdreScreen(fraisScolaires: fraisScolaires),
                    ),
                  ),
                ),
                // ⚡ NOUVEAU — Module Discipline : registre d'absences,
                // convocations individuelles et communiqués aux parents.
                _buildCard(
                  Icons.rule_folder,
                  "Discipline",
                      () => _openAndRefresh(
                    DisciplineRegistreScreen(fraisScolaires: fraisScolaires),
                  ),
                ),
                // ⚡ NOUVEAU — tout ce que l'école a envoyé aux parents,
                // avec la confirmation de lecture (lu à 14:32, pas lu...).
                _buildCard(
                  Icons.mark_email_read,
                  "Messages envoyés",
                      () => _openAndRefresh(
                    MessagesEnvoyesScreen(fraisScolaires: fraisScolaires),
                  ),
                ),
                // ⚡ NOUVEAU — messages écrits par les parents + réponses,
                // avec la pastille rouge des messages non lus.
                _buildCard(
                  Icons.forum,
                  "Messages des parents",
                      () => _openAndRefresh(
                    MessagesParentsScreen(fraisScolaires: fraisScolaires),
                  ),
                  badge: _parentUnread,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(IconData icon, String label, VoidCallback onTap,
      {int badge = 0}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 50, color: Colors.indigo),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                constraints:
                const BoxConstraints(minWidth: 26, minHeight: 26),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFC62828),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}