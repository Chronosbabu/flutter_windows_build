import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../frais_scolaires.dart';
import '../models.dart';
import 'messages_envoyes_screen.dart';
import 'messages_parents_screen.dart';

// ======================================================================
// ⚡ MESSAGERIE DES PARENTS — une seule entrée, très simple
// ----------------------------------------------------------------------
// Trois gros boutons, rien d'autre :
//   1. Écrire aux parents (message, convocation ou communiqué)
//   2. Messages reçus des parents
//   3. Qui a lu mes messages ?
// ======================================================================

const int _kMaxMessage = 2000;
const int _kMaxTitre = 80;

/// Écran d'accueil de la messagerie.
class MessagerieScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;

  const MessagerieScreen({super.key, required this.fraisScolaires});

  @override
  State<MessagerieScreen> createState() => _MessagerieScreenState();
}

class _MessagerieScreenState extends State<MessagerieScreen>
    with WidgetsBindingObserver {
  int? _nonLusParents; // messages des parents pas encore ouverts
  int? _pasEncoreLus; // messages de l'école que des parents n'ont pas lus
  bool _horsLigne = false;

  // ⚡ Actualisation automatique : sans elle, un message de parent arrivé
  // pendant qu'on reste sur cette page n'apparaissait jamais (il fallait
  // ressortir et revenir).
  Timer? _timer;
  bool _chargement = false;
  bool _ecranOuvert = false; // un sous-écran est ouvert (il s'actualise seul)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _charger();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && !_ecranOuvert) _charger();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_ecranOuvert) _charger();
  }

  Future<void> _charger() async {
    if (_chargement) return;
    _chargement = true;
    final fs = widget.fraisScolaires;
    final List<Map<String, dynamic>> r;
    try {
      r = await Future.wait([
        fs.getParentConversations(),
        fs.getSentMessages(limit: 1),
      ]);
    } finally {
      _chargement = false;
    }
    if (!mounted) return;
    setState(() {
      _horsLigne = r[0]['success'] != true && r[1]['success'] != true;
      _nonLusParents = r[0]['success'] == true
          ? (r[0]['total_unread'] as num?)?.toInt() ?? 0
          : null;
      final stats = Map<String, dynamic>.from(r[1]['stats'] as Map? ?? {});
      _pasEncoreLus = r[1]['success'] == true
          ? (stats['unread'] as num?)?.toInt() ?? 0
          : null;
    });
  }

  Future<void> _ouvrir(Widget ecran) async {
    _ecranOuvert = true;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ecran));
    _ecranOuvert = false;
    if (mounted) _charger();
  }

  @override
  Widget build(BuildContext context) {
    final fs = widget.fraisScolaires;
    final nonLus = _nonLusParents ?? 0;
    final pasLus = _pasEncoreLus ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messagerie des parents'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _charger,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_horsLigne)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Pas de connexion au serveur. La messagerie a besoin "
                        "d'internet.",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            _GrosBouton(
              icone: Icons.edit,
              couleur: Colors.indigo,
              titre: 'Écrire aux parents',
              explication:
                  'Envoyer un message, une convocation ou un communiqué.',
              onTap: () => _ouvrir(EcrireAuxParentsScreen(fraisScolaires: fs)),
            ),
            const SizedBox(height: 14),
            _GrosBouton(
              icone: Icons.inbox,
              couleur: Colors.green.shade700,
              titre: 'Messages reçus des parents',
              explication: _nonLusParents == null
                  ? 'Lire les messages des parents et leur répondre.'
                  : nonLus == 0
                  ? 'Aucun nouveau message.'
                  : nonLus == 1
                  ? '1 nouveau message à lire.'
                  : '$nonLus nouveaux messages à lire.',
              pastille: nonLus,
              onTap: () => _ouvrir(MessagesParentsScreen(fraisScolaires: fs)),
            ),
            const SizedBox(height: 14),
            _GrosBouton(
              icone: Icons.done_all,
              couleur: Colors.blue.shade700,
              titre: 'Qui a lu mes messages ?',
              explication: _pasEncoreLus == null
                  ? 'Voir les messages envoyés et les parents qui les ont lus.'
                  : pasLus == 0
                  ? 'Tous vos messages ont été lus.'
                  : '$pasLus message(s) pas encore lu(s) par les parents.',
              onTap: () => _ouvrir(MessagesEnvoyesScreen(fraisScolaires: fs)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrosBouton extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String titre;
  final String explication;
  final int pastille;
  final VoidCallback onTap;

  const _GrosBouton({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.explication,
    required this.onTap,
    this.pastille = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: couleur,
                    child: Icon(icone, color: Colors.white, size: 30),
                  ),
                  if (pastille > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC62828),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          pastille > 99 ? '99+' : '$pastille',
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
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      explication,
                      style: TextStyle(
                        fontSize: 14,
                        color: pastille > 0
                            ? const Color(0xFFC62828)
                            : Colors.grey.shade700,
                        fontWeight: pastille > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// ÉCRIRE AUX PARENTS — un seul formulaire en 3 étapes
// ======================================================================

enum PourQui { eleves, classe, section, ecole }

enum GenreMessage { message, convocation, communique }

class _Modele {
  final String nom;
  final String titre;
  final String texte;
  const _Modele(this.nom, this.titre, this.texte);
}

const Map<GenreMessage, List<_Modele>> _modeles = {
  GenreMessage.message: [
    _Modele(
      'Élève malade',
      "Message de l'école",
      "Bonjour, votre enfant ne se sent pas bien aujourd'hui. Merci de "
          "venir le chercher à l'école ou de nous appeler rapidement.",
    ),
    _Modele(
      'Frais à payer',
      "Message de l'école",
      "Bonjour, nous vous rappelons que les frais scolaires de votre "
          "enfant ne sont pas encore complètement payés. Merci de passer "
          "à la caisse de l'école.",
    ),
    _Modele(
      'Félicitations',
      "Message de l'école",
      "Bonjour, nous tenons à vous féliciter : votre enfant fait de très "
          "bons progrès à l'école. Continuez à l'encourager !",
    ),
  ],
  GenreMessage.convocation: [
    _Modele(
      'Comportement',
      'Convocation des parents',
      "Nous souhaitons vous rencontrer au sujet du comportement de votre "
          "enfant à l'école. Merci de vous présenter à l'administration "
          "dans les meilleurs délais.",
    ),
    _Modele(
      'Résultats scolaires',
      'Convocation des parents',
      "Nous souhaitons vous rencontrer au sujet des résultats scolaires "
          "de votre enfant. Merci de vous présenter à l'administration "
          "dans les meilleurs délais.",
    ),
    _Modele(
      'Absences répétées',
      'Convocation des parents',
      "Votre enfant a été absent plusieurs fois. Merci de vous présenter "
          "à l'administration pour en parler.",
    ),
  ],
  GenreMessage.communique: [
    _Modele(
      'Réunion des parents',
      'Réunion des parents',
      "Chers parents, vous êtes invités à une réunion à l'école le "
          "............ à ...... h. Votre présence est importante.",
    ),
    _Modele(
      "Fermeture de l'école",
      "Fermeture de l'école",
      "Chers parents, l'école sera fermée le ............ . Les cours "
          "reprendront le ............ .",
    ),
    _Modele(
      'Rappel des frais',
      'Rappel des frais scolaires',
      "Chers parents, nous vous rappelons de régulariser les frais "
          "scolaires de vos enfants avant le ............ . Merci.",
    ),
  ],
};

String _titreParDefaut(GenreMessage g) {
  switch (g) {
    case GenreMessage.message:
      return "Message de l'école";
    case GenreMessage.convocation:
      return 'Convocation des parents';
    case GenreMessage.communique:
      return "Communiqué de l'école";
  }
}

/// Transforme les erreurs techniques en phrases simples.
String erreurLisible(String? brute) {
  final e = (brute ?? '').toLowerCase();
  if (e.contains('connexion réseau') ||
      e.contains('socketexception') ||
      e.contains('timeout') ||
      e.contains('failed host lookup')) {
    return "Pas de connexion internet.";
  }
  if (e.contains('introuvable')) {
    return "Élève pas encore enregistré sur le serveur : faites d'abord une "
        "sauvegarde (Paramètres), puis réessayez.";
  }
  if (e.contains('code école manquant')) {
    return "L'école n'est pas encore enregistrée sur le serveur : faites "
        "d'abord une sauvegarde (Paramètres).";
  }
  if (e.contains('trop long')) {
    return "Message trop long (2000 caractères maximum).";
  }
  return brute ?? 'Erreur inconnue';
}

class EcrireAuxParentsScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;

  /// Pour ouvrir l'écran déjà rempli (ex. « Convoquer » depuis le registre).
  final Eleve? eleveInitial;
  final GenreMessage? genreInitial;

  const EcrireAuxParentsScreen({
    super.key,
    required this.fraisScolaires,
    this.eleveInitial,
    this.genreInitial,
  });

  @override
  State<EcrireAuxParentsScreen> createState() => _EcrireAuxParentsScreenState();
}

class _EcrireAuxParentsScreenState extends State<EcrireAuxParentsScreen> {
  final _titre = TextEditingController();
  final _texte = TextEditingController();
  final _recherche = TextEditingController();

  PourQui? _pour;
  GenreMessage _genre = GenreMessage.message;
  final List<Eleve> _eleves = [];
  String? _section;
  String? _classe; // clé « section\u0001classe »
  bool _urgent = false;
  bool _envoi = false;

  FraisScolaires get _fs => widget.fraisScolaires;

  @override
  void initState() {
    super.initState();
    final e = widget.eleveInitial;
    if (e != null) {
      _pour = PourQui.eleves;
      _eleves.add(e);
    }
    _genre = widget.genreInitial ?? GenreMessage.message;
    _titre.text = _titreParDefaut(_genre);
    // Convocation ouverte depuis le registre : texte habituel déjà rempli.
    if (_genre == GenreMessage.convocation) {
      _appliquerModele(_modeles[_genre]!.first);
    }
  }

  @override
  void dispose() {
    _titre.dispose();
    _texte.dispose();
    _recherche.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Destinataires
  // ------------------------------------------------------------------
  List<Eleve> get _tous => _fs.currentData.eleves;

  /// Toutes les classes, avec leur section, dans l'ordre de l'école.
  List<MapEntry<String, String>> get _classes {
    final res = <MapEntry<String, String>>[];
    final vus = <String>{};
    for (final s in _fs.config.sections) {
      for (final c in _fs.getAllDisplayClassesForSection(s)) {
        if (vus.add('$s\u0001$c')) res.add(MapEntry(s, c));
      }
    }
    // Classes présentes chez les élèves mais absentes de la configuration.
    for (final e in _tous) {
      if (e.classe.isEmpty) continue;
      if (vus.add('${e.section}\u0001${e.classe}')) {
        res.add(MapEntry(e.section, e.classe));
      }
    }
    return res;
  }

  List<Eleve> get _destinataires {
    switch (_pour) {
      case PourQui.eleves:
        return List<Eleve>.from(_eleves);
      case PourQui.classe:
        if (_classe == null) return [];
        final p = _classe!.split('\u0001');
        return _tous
            .where((e) => e.section == p[0] && e.classe == p[1])
            .toList();
      case PourQui.section:
        if (_section == null) return [];
        return _tous.where((e) => e.section == _section).toList();
      case PourQui.ecole:
        return List<Eleve>.from(_tous);
      case null:
        return [];
    }
  }

  /// Genres possibles selon les destinataires.
  List<GenreMessage> get _genresPossibles {
    switch (_pour) {
      case PourQui.eleves:
        return GenreMessage.values;
      case PourQui.classe:
        return const [GenreMessage.communique, GenreMessage.convocation];
      case PourQui.section:
      case PourQui.ecole:
        return const [GenreMessage.communique];
      case null:
        return GenreMessage.values;
    }
  }

  void _choisirPour(PourQui p) {
    setState(() {
      _pour = p;
      if (!_genresPossibles.contains(_genre)) {
        _changerGenre(_genresPossibles.first, avecSetState: false);
      }
    });
  }

  void _changerGenre(GenreMessage g, {bool avecSetState = true}) {
    void faire() {
      // Le texte d'un modèle de l'ancien genre est remplacé ; un texte écrit
      // à la main est gardé.
      final ancienModele = _modeles[_genre]!.any((m) => m.texte == _texte.text);
      final ancienTitre =
          _titre.text.trim().isEmpty ||
          _titre.text == _titreParDefaut(_genre) ||
          _modeles[_genre]!.any((m) => m.titre == _titre.text);
      _genre = g;
      if (ancienTitre) _titre.text = _titreParDefaut(g);
      if (ancienModele) _texte.clear();
    }

    if (avecSetState) {
      setState(faire);
    } else {
      faire();
    }
  }

  void _appliquerModele(_Modele m) {
    _titre.text = m.titre;
    _texte.text = m.texte;
  }

  // ------------------------------------------------------------------
  // Envoi
  // ------------------------------------------------------------------
  String? get _probleme {
    if (_pour == null) return "Choisissez d'abord à qui écrire (étape 1).";
    if (_destinataires.isEmpty) {
      switch (_pour!) {
        case PourQui.eleves:
          return "Ajoutez au moins un élève (étape 1).";
        case PourQui.classe:
          return _classe == null
              ? "Choisissez la classe (étape 1)."
              : "Aucun élève dans cette classe.";
        case PourQui.section:
          return _section == null
              ? "Choisissez la section (étape 1)."
              : "Aucun élève dans cette section.";
        case PourQui.ecole:
          return "Aucun élève dans l'école.";
      }
    }
    if (_texte.text.trim().isEmpty) return "Écrivez le message (étape 3).";
    return null;
  }

  String _nomEleve(Eleve e) => '${e.nom} ${e.postNom} ${e.prenom}'
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String get _libelleGenre {
    switch (_genre) {
      case GenreMessage.message:
        return 'ce message';
      case GenreMessage.convocation:
        return 'cette convocation';
      case GenreMessage.communique:
        return 'ce communiqué';
    }
  }

  Future<void> _envoyer() async {
    final probleme = _probleme;
    if (probleme != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(probleme), backgroundColor: Colors.orange),
      );
      return;
    }
    final dest = _destinataires;
    final n = dest.length;
    final texte = _texte.text.trim();
    final titre = _titre.text.trim().isEmpty
        ? _titreParDefaut(_genre)
        : _titre.text.trim();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Envoyer ?"),
        content: Text(
          "Envoyer $_libelleGenre "
          "${n == 1 ? 'au parent de ${_nomEleve(dest.first)}' : 'à $n parents'} ?"
          "${_urgent ? "\n\nURGENT : le téléphone du parent vibrera jusqu'à ce qu'il lise." : ''}",
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Non, revenir"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _urgent
                  ? const Color(0xFFC62828)
                  : Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send),
            label: const Text("Oui, envoyer"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _envoi = true);
    final progression = ValueNotifier<int>(0);
    final bool boucle = _genre != GenreMessage.communique && n > 1;
    if (boucle) {
      unawaited(
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              content: ValueListenableBuilder<int>(
                valueListenable: progression,
                builder: (_, v, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: n == 0 ? 0 : v / n),
                    const SizedBox(height: 12),
                    Text("Envoi en cours… $v / $n"),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    int reussis = 0;
    final echecs = <String>[]; // « Nom : raison »
    String? erreurGlobale;

    try {
      if (_genre == GenreMessage.communique) {
        final r = await _fs.sendAnnouncement(
          title: titre,
          message: texte,
          // Une classe est envoyée par la liste exacte de ses élèves : le
          // serveur ne regarde que le nom de la classe, et deux sections
          // peuvent avoir une classe du même nom.
          target: switch (_pour!) {
            PourQui.eleves || PourQui.classe => 'students',
            PourQui.section => 'section',
            PourQui.ecole => 'all',
          },
          section: _pour == PourQui.section ? _section : null,
          studentIds: _pour == PourQui.eleves || _pour == PourQui.classe
              ? dest.map((e) => e.id).toList()
              : null,
          urgent: _urgent,
        );
        if (r['success'] == true) {
          // notified_count = élèves trouvés sur le serveur.
          reussis = (r['notified_count'] as num?)?.toInt() ?? n;
          if (reussis == 0) {
            erreurGlobale = erreurLisible('introuvable');
          } else if (reussis < n) {
            echecs.add("${n - reussis} élève(s) pas encore enregistré(s) "
                "sur le serveur : faites une sauvegarde (Paramètres), puis "
                "renvoyez-leur le message.");
          }
        } else {
          erreurGlobale = erreurLisible(r['error']?.toString());
        }
      } else {
        for (final e in dest) {
          final r = _genre == GenreMessage.convocation
              ? await _fs.sendConvocation(
                  studentId: e.id,
                  title: titre,
                  message: texte,
                  urgent: _urgent,
                )
              : await _fs.replyToParent(
                  studentId: e.id,
                  text: texte,
                  urgent: _urgent,
                );
          if (r['success'] == true) {
            reussis++;
          } else {
            echecs.add(
              '${_nomEleve(e)} : '
              '${erreurLisible(r['error']?.toString())}',
            );
          }
          progression.value++;
        }
      }
    } catch (e) {
      erreurGlobale = erreurLisible('$e');
    }

    if (boucle && mounted) Navigator.of(context, rootNavigator: true).pop();
    progression.dispose();
    if (!mounted) return;
    setState(() => _envoi = false);

    final toutRate = erreurGlobale != null || reussis == 0;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              toutRate ? Icons.error_outline : Icons.check_circle,
              color: toutRate ? Colors.red : Colors.green,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(toutRate ? "Pas envoyé" : "Envoyé !")),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (erreurGlobale != null)
                Text(erreurGlobale, style: const TextStyle(fontSize: 15))
              else ...[
                if (reussis > 0)
                  Text(
                    reussis == 1
                        ? "Le message est parti vers 1 parent."
                        : "Le message est parti vers $reussis parents.",
                    style: const TextStyle(fontSize: 15),
                  ),
                if (echecs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    "Pas envoyé pour certains élèves :",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...echecs
                      .take(10)
                      .map(
                        (x) =>
                            Text("• $x", style: const TextStyle(fontSize: 13)),
                      ),
                  if (echecs.length > 10)
                    Text("… et ${echecs.length - 10} autre(s)."),
                ],
                if (reussis > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    "Pour savoir quand les parents l'ont lu : "
                    "« Qui a lu mes messages ? ».",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          if (toutRate)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Fermer"),
            )
          else ...[
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MessagesEnvoyesScreen(fraisScolaires: _fs),
                  ),
                );
              },
              child: const Text("Voir qui a lu"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text("Terminé"),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------
  Widget _etape(int numero, String titre, Widget contenu) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.indigo,
                  child: Text(
                    '$numero',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            contenu,
          ],
        ),
      ),
    );
  }

  Widget _choix({
    required IconData icone,
    required String libelle,
    String? aide,
    required bool choisi,
    required VoidCallback? onTap,
  }) {
    final actif = onTap != null;
    final couleur = choisi ? Colors.indigo : Colors.grey.shade600;
    return SizedBox(
      width: 165,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Opacity(
          opacity: actif ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: choisi ? Colors.indigo.withAlpha(25) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: choisi ? Colors.indigo : Colors.grey.shade400,
                width: choisi ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icone, color: couleur, size: 28),
                const SizedBox(height: 6),
                Text(
                  libelle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: choisi ? Colors.indigo : null,
                  ),
                ),
                if (aide != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    aide,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _etape1() {
    return _etape(
      1,
      'À qui voulez-vous écrire ?',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _choix(
                icone: Icons.person,
                libelle: 'Un ou des élèves',
                choisi: _pour == PourQui.eleves,
                onTap: _envoi ? null : () => _choisirPour(PourQui.eleves),
              ),
              _choix(
                icone: Icons.groups,
                libelle: 'Une classe',
                choisi: _pour == PourQui.classe,
                onTap: _envoi ? null : () => _choisirPour(PourQui.classe),
              ),
              _choix(
                icone: Icons.account_tree,
                libelle: 'Une section',
                choisi: _pour == PourQui.section,
                onTap: _envoi ? null : () => _choisirPour(PourQui.section),
              ),
              _choix(
                icone: Icons.school,
                libelle: "Toute l'école",
                choisi: _pour == PourQui.ecole,
                onTap: _envoi ? null : () => _choisirPour(PourQui.ecole),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_pour == PourQui.eleves) _choixEleves(),
          if (_pour == PourQui.classe)
            DropdownButtonFormField<String>(
              initialValue: _classe,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Choisissez la classe',
                border: OutlineInputBorder(),
              ),
              items: _classes
                  .map(
                    (c) => DropdownMenuItem(
                      value: '${c.key}\u0001${c.value}',
                      child: Text(
                        c.key.isEmpty ? c.value : '${c.value}  —  ${c.key}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _classe = v),
            ),
          if (_pour == PourQui.section)
            DropdownButtonFormField<String>(
              initialValue: _section,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Choisissez la section',
                border: OutlineInputBorder(),
              ),
              items: _fs.config.sections
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _section = v),
            ),
          if (_pour != null && _destinataires.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _destinataires.length == 1
                  ? '→ 1 parent recevra le message.'
                  : '→ ${_destinataires.length} parents recevront le message.',
              style: TextStyle(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _choixEleves() {
    final q = _recherche.text.trim().toLowerCase();
    final choisis = _eleves.map((e) => e.id).toSet();
    final resultats = q.isEmpty
        ? <Eleve>[]
        : (_tous
                  .where(
                    (e) =>
                        !choisis.contains(e.id) &&
                        (_nomEleve(e).toLowerCase().contains(q) ||
                            e.classe.toLowerCase().contains(q)),
                  )
                  .toList()
                ..sort((a, b) => _nomEleve(a).compareTo(_nomEleve(b))))
              .take(8)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_eleves.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _eleves
                .map(
                  (e) => InputChip(
                    avatar: const Icon(Icons.person, size: 18),
                    label: Text('${_nomEleve(e)} (${e.classe})'),
                    onDeleted: _envoi
                        ? null
                        : () => setState(() => _eleves.remove(e)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _recherche,
          enabled: !_envoi,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: _eleves.isEmpty
                ? "Tapez le nom de l'élève"
                : 'Ajouter un autre élève (facultatif)',
            border: const OutlineInputBorder(),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_recherche.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (q.isNotEmpty && resultats.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Aucun élève trouvé.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ...resultats.map(
          (e) => ListTile(
            dense: true,
            leading: const Icon(Icons.add_circle, color: Colors.indigo),
            title: Text(_nomEleve(e)),
            subtitle: Text('${e.classe} • ${e.section}'),
            onTap: () => setState(() {
              _eleves.add(e);
              _recherche.clear();
            }),
          ),
        ),
      ],
    );
  }

  Widget _etape2() {
    final possibles = _genresPossibles;
    Widget c(GenreMessage g, IconData i, String l, String aide) => _choix(
      icone: i,
      libelle: l,
      aide: possibles.contains(g)
          ? aide
          : (g == GenreMessage.message
                ? 'Pour un élève précis'
                : 'Pour des élèves ou une classe'),
      choisi: _genre == g,
      onTap: !_envoi && possibles.contains(g) ? () => _changerGenre(g) : null,
    );
    return _etape(
      2,
      'Que voulez-vous envoyer ?',
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          c(
            GenreMessage.message,
            Icons.chat,
            'Message',
            'Le parent peut vous répondre',
          ),
          c(
            GenreMessage.convocation,
            Icons.event_available,
            'Convocation',
            'Demander au parent de venir',
          ),
          c(
            GenreMessage.communique,
            Icons.campaign,
            'Communiqué',
            'Annonce : réunion, fermeture…',
          ),
        ],
      ),
    );
  }

  Widget _etape3() {
    final modeles = _modeles[_genre]!;
    return _etape(
      3,
      'Écrivez votre message',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Modèles prêts (touchez pour remplir, puis modifiez) :',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: modeles
                .map(
                  (m) => ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(m.nom),
                    onPressed: _envoi
                        ? null
                        : () => setState(() => _appliquerModele(m)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          if (_genre != GenreMessage.message) ...[
            TextField(
              controller: _titre,
              enabled: !_envoi,
              maxLength: _kMaxTitre,
              inputFormatters: [LengthLimitingTextInputFormatter(_kMaxTitre)],
              decoration: const InputDecoration(
                labelText: 'Titre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
          ],
          TextField(
            controller: _texte,
            enabled: !_envoi,
            minLines: 5,
            maxLines: 10,
            maxLength: _kMaxMessage,
            inputFormatters: [LengthLimitingTextInputFormatter(_kMaxMessage)],
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              hintText: 'Écrivez ici…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: _urgent ? const Color(0xFFFFEBEE) : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _urgent ? const Color(0xFFC62828) : Colors.grey.shade300,
              ),
            ),
            child: CheckboxListTile(
              value: _urgent,
              activeColor: const Color(0xFFC62828),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _envoi
                  ? null
                  : (v) => setState(() => _urgent = v ?? false),
              title: const Text(
                'Urgent',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                "Le téléphone du parent vibre jusqu'à ce qu'il lise.",
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final probleme = _probleme;
    final n = _destinataires.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Écrire aux parents'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [_etape1(), _etape2(), _etape3()],
                  ),
                ),
              ),
            ),
            Material(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (probleme != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              probleme,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _urgent
                                  ? const Color(0xFFC62828)
                                  : Colors.indigo,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _envoi || probleme != null
                                ? null
                                : _envoyer,
                            icon: _envoi
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            label: Text(
                              _envoi
                                  ? 'Envoi en cours…'
                                  : (n <= 1
                                        ? 'Envoyer'
                                        : 'Envoyer à $n parents'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
