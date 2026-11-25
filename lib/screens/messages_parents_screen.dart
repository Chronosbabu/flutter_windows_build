import 'dart:async';
import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import 'messagerie_screen.dart';

// ======================================================================
// Couleurs fixes de la messagerie (style WhatsApp) — elles ne dépendent
// PAS du thème de l'application, donc tout reste lisible en mode clair
// comme en mode sombre.
// ======================================================================
const Color _kChatBackground = Color(0xFFEFEAE2); // fond beige
const Color _kBubbleMine     = Color(0xFFD9FDD3); // bulle de l'école (vert clair)
const Color _kBubbleOther    = Color(0xFFFFFFFF); // bulle du parent (blanc)
const Color _kTextMain       = Color(0xFF111B21); // texte des messages (quasi noir)
const Color _kTextSecondary  = Color(0xFF54656F); // heure, textes secondaires
const Color _kReadBlue       = Color(0xFF53BDEB); // coches bleues « lu »
const Color _kAppBarGreen    = Color(0xFF075E54); // barre du haut
const Color _kAccentGreen    = Color(0xFF128C7E); // boutons

// ======================================================================
// Outils communs d'affichage (dates en français, heure locale)
// ======================================================================
DateTime? _parseServerDate(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  var v = s.trim();
  final hasTz =
      RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(v) && v.contains('T');
  if (!hasTz) {
    v = v.contains('T') ? '${v}Z' : '${v}T00:00:00Z';
  }
  try {
    return DateTime.parse(v).toLocal();
  } catch (_) {
    return null;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

const List<String> _mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
  'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
const List<String> _jours = [
  'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
];
const List<String> _joursCourts = [
  'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.',
];

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return "Aujourd'hui";
  final diff = _daysBetween(d, now);
  if (diff == 1) return 'Hier';
  if (diff > 1 && diff < 7) return _jours[d.weekday - 1];
  return '${d.day} ${_mois[d.month - 1]} ${d.year}';
}

String _listTime(DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return _hm(d);
  final diff = _daysBetween(d, now);
  if (diff == 1) return 'Hier';
  if (diff > 1 && diff < 7) return _joursCourts[d.weekday - 1];
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

int _asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

String _initials(String nom) {
  final parts =
  nom.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final a = parts[0][0];
  final b = parts.length > 1 ? parts[1][0] : '';
  return '$a$b'.toUpperCase();
}

// ======================================================================
// ÉCRAN 1 — LISTE DES CONVERSATIONS
// ======================================================================

/// Boîte de réception de l'école : une ligne par élève dont le parent a
/// écrit (ou à qui l'école a écrit), la plus récente en premier.
class MessagesParentsScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;

  const MessagesParentsScreen({super.key, required this.fraisScolaires});

  @override
  State<MessagesParentsScreen> createState() => _MessagesParentsScreenState();
}

class _MessagesParentsScreenState extends State<MessagesParentsScreen> {
  List<Map<String, dynamic>> _convs = [];
  int _totalUnread = 0;
  bool _loading = true;
  String? _error;

  /// 'all' | 'unread'
  String _filter = 'all';
  String _search = '';

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // ⚡ 8 s (avant 15 s) : les messages des parents apparaissent plus vite.
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _loading) return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _busy = false; // une actualisation est déjà en cours

  Future<void> _load({bool silent = false}) async {
    if (silent && _busy) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _busy = true;
    final Map<String, dynamic> r;
    try {
      r = await widget.fraisScolaires.getParentConversations();
    } finally {
      _busy = false;
    }
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _convs = (r['conversations'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _totalUnread = _asInt(r['total_unread']);
        _loading = false;
        _error = null;
      });
    } else if (!silent) {
      setState(() {
        _loading = false;
        _error = (r['error'] ?? 'Erreur inconnue').toString();
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.trim().toLowerCase();
    return _convs.where((c) {
      if (_filter == 'unread' && _asInt(c['unread_count']) <= 0) return false;
      if (q.isNotEmpty) {
        final nom = (c['nom_eleve'] ?? '').toString().toLowerCase();
        final classe = (c['classe'] ?? '').toString().toLowerCase();
        if (!nom.contains(q) && !classe.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SchoolChatScreen(
          fraisScolaires: widget.fraisScolaires,
          studentId: (c['student_id'] ?? '').toString(),
          nomEleve: (c['nom_eleve'] ?? '').toString(),
          classe: (c['classe'] ?? '').toString(),
        ),
      ),
    );
    if (mounted) _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages reçus des parents'),
        centerTitle: true,
        actions: [
          if (_totalUnread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _totalUnread > 99 ? '99+' : '$_totalUnread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  EcrireAuxParentsScreen(fraisScolaires: widget.fraisScolaires),
            ),
          );
          if (mounted) _load(silent: true);
        },
        icon: const Icon(Icons.edit),
        label: const Text('Écrire à un parent'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 60, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final list = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Rechercher un élève ou une classe',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
          child: Row(
            children: [
              _chip('all', 'Toutes'),
              _chip('unread', 'Pas encore lues ($_totalUnread)'),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: list.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Icon(Icons.forum_outlined,
                    size: 70, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _convs.isEmpty
                          ? "Aucun message pour l'instant. Les messages "
                          'des parents apparaîtront ici.\n\nPour écrire '
                          'à un parent : bouton « Écrire à un parent » en bas.'
                          : _filter == 'unread'
                          ? 'Aucun message à lire. Tout est lu ✅'
                          : 'Aucun élève ne correspond à la recherche.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            )
                : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 76),
              padding: const EdgeInsets.only(bottom: 90),
            itemBuilder: (context, i) => _tile(list[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final nom = (c['nom_eleve'] ?? '').toString();
    final classe = (c['classe'] ?? '').toString();
    final unread = _asInt(c['unread_count']);
    final last = Map<String, dynamic>.from(c['last_message'] as Map? ?? {});
    final fromParent = last['sender'] == 'parent';
    final text = (last['text'] ?? '').toString();
    final when = _parseServerDate(last['created_at']?.toString());
    final bold = unread > 0;
    // ⚡ Couleur qui s'adapte au thème (clair ou sombre) : lisible partout.
    final Color mainTextColor = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: () => _open(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: bold ? Colors.green : Colors.blueGrey,
              child: Text(
                _initials(nom),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            color: mainTextColor,
                            fontWeight:
                            bold ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (when != null)
                        Text(
                          _listTime(when),
                          style: TextStyle(
                            fontSize: 12,
                            color: bold
                                ? const Color(0xFF25A244)
                                : Colors.grey.shade600,
                            fontWeight:
                            bold ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                  if (classe.isNotEmpty)
                    Text(classe,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${fromParent ? '' : 'Vous : '}$text',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: bold
                                ? mainTextColor
                                : mainTextColor.withAlpha(170),
                            fontWeight:
                            bold ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(
                              minWidth: 22, minHeight: 22),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// ÉCRAN 2 — CONVERSATION AVEC LE PARENT D'UN ÉLÈVE
// ======================================================================

/// À gauche : le parent (blanc). À droite : l'école (vert) avec les
/// coches de lecture (✓ envoyé, ✓✓ gris reçu, ✓✓ bleu lu + heure de lecture).
/// L'école peut marquer sa réponse URGENTE : le parent reçoit alors des
/// rappels vibrants tant qu'il ne l'a pas lue.
///
/// ⚡ Toutes les couleurs sont FIXES (style WhatsApp) : l'écran est lisible
/// que le téléphone soit en mode clair ou en mode sombre.
class SchoolChatScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  final String studentId;
  final String nomEleve;
  final String classe;

  const SchoolChatScreen({
    super.key,
    required this.fraisScolaires,
    required this.studentId,
    required this.nomEleve,
    this.classe = '',
  });

  @override
  State<SchoolChatScreen> createState() => _SchoolChatScreenState();
}

class _SchoolChatScreenState extends State<SchoolChatScreen> {
  static const Color _urgentColor = Color(0xFFC62828);
  static const Color _urgentBg = Color(0xFFFFEBEE);

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMoreOlder = false;
  bool _sending = false;
  bool _urgent = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load(first: true);
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _loading || _sending) return;
      _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Chargement
  // ------------------------------------------------------------------
  int _seqOf(Map<String, dynamic> m) => _asInt(m['seq']);

  bool get _nearBottom {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset < 160;
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated) {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  /// Charge les 100 derniers messages et les fusionne avec ce qu'on a déjà
  /// (les anciens déjà chargés sont conservés). Cela met aussi à jour les
  /// coches de lecture des messages déjà affichés.
  bool _busy = false; // un chargement est déjà en cours

  Future<void> _load({bool first = false}) async {
    if (!first && _busy) return;
    if (first) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _busy = true;
    final Map<String, dynamic> r;
    try {
      r = await widget.fraisScolaires
          .getParentConversation(widget.studentId, limit: 100);
    } finally {
      _busy = false;
    }
    if (!mounted) return;

    if (r['success'] != true) {
      if (first) {
        setState(() {
          _loading = false;
          _error = (r['error'] ?? 'Erreur inconnue').toString();
        });
      }
      return;
    }

    final fetched = (r['messages'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final bool wasNearBottom = _nearBottom;
    final int oldLast = _messages.isEmpty ? 0 : _seqOf(_messages.last);

    List<Map<String, dynamic>> merged;
    if (first || _messages.isEmpty) {
      merged = fetched;
    } else if (fetched.isEmpty) {
      merged = _messages;
    } else {
      final int minFetched =
      fetched.map(_seqOf).reduce((a, b) => a < b ? a : b);
      merged = [
        ..._messages.where((m) => _seqOf(m) < minFetched),
        ...fetched,
      ];
    }

    final int newLast = merged.isEmpty ? 0 : _seqOf(merged.last);
    final bool hasNew = newLast > oldLast;

    setState(() {
      _messages = merged;
      if (first) _hasMoreOlder = r['has_more_older'] == true;
      _loading = false;
      _error = null;
    });

    if (first) {
      _scrollToBottom(animated: false);
    } else if (hasNew && wasNearBottom) {
      _scrollToBottom();
    }

    // Des messages du parent ne sont pas encore marqués « lus » → l'école
    // vient de les voir : on le dit au serveur (le parent verra ✓✓ bleus).
    final bool unreadParent =
    fetched.any((m) => m['sender'] == 'parent' && m['read'] != true);
    if (unreadParent) {
      unawaited(widget.fraisScolaires
          .markParentConversationRead(widget.studentId));
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    final before = _messages.map(_seqOf).reduce((a, b) => a < b ? a : b);
    final r = await widget.fraisScolaires.getParentConversation(
      widget.studentId,
      beforeSeq: before,
      limit: 100,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      final older = (r['messages'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final double oldMax =
      _scroll.hasClients ? _scroll.position.maxScrollExtent : 0;
      final double oldOffset = _scroll.hasClients ? _scroll.offset : 0;
      setState(() {
        _messages = [...older, ..._messages];
        _hasMoreOlder = r['has_more_older'] == true;
        _loadingOlder = false;
      });
      // garde la position de lecture après l'ajout en haut
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final diff = _scroll.position.maxScrollExtent - oldMax;
        _scroll.jumpTo(oldOffset + diff);
      });
    } else {
      setState(() => _loadingOlder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${r['error'] ?? 'Erreur inconnue'}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ------------------------------------------------------------------
  // Envoi d'une réponse
  // ------------------------------------------------------------------
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    // ⚡ PROTECTION — jamais plus de 2000 caractères
    if (text.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Message trop long (2000 caractères maximum).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    final r = await widget.fraisScolaires.replyToParent(
      studentId: widget.studentId,
      text: text,
      urgent: _urgent,
    );
    if (!mounted) return;

    if (r['success'] == true) {
      final msg = Map<String, dynamic>.from(r['message'] as Map? ?? {});
      setState(() {
        _sending = false;
        _controller.clear();
        _urgent = false;
        if (msg.isNotEmpty &&
            !_messages.any((m) => m['id'] == msg['id'])) {
          _messages = [..._messages, msg];
        }
      });
      _scrollToBottom();
    } else {
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${r['error'] ?? "Échec de l'envoi"}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kChatBackground,
      appBar: AppBar(
        backgroundColor: _kAppBarGreen,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Text(
                _initials(widget.nomEleve),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Parent de ${widget.nomEleve}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.classe.isNotEmpty)
                    Text(widget.classe,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kAccentGreen),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 60, color: _kTextSecondary),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _kTextMain, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccentGreen,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _load(first: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Aucun message pour cet élève. Écrivez ci-dessous pour contacter "
                'son parent.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kTextSecondary, fontSize: 15),
          ),
        ),
      );
    }

    final children = <Widget>[];
    if (_hasMoreOlder) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: _loadingOlder
              ? const CircularProgressIndicator(color: _kAccentGreen)
              : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAccentGreen,
              backgroundColor: Colors.white,
              side: const BorderSide(color: _kAccentGreen),
            ),
            onPressed: _loadOlder,
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Messages plus anciens'),
          ),
        ),
      ));
    }

    DateTime? previousDay;
    for (final m in _messages) {
      final d = _parseServerDate(m['created_at']?.toString());
      if (d != null && (previousDay == null || !_sameDay(previousDay, d))) {
        children.add(_daySeparator(d));
        previousDay = d;
      }
      children.add(_bubble(m, d));
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: children,
    );
  }

  Widget _daySeparator(DateTime d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(25),
                blurRadius: 1.5,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            _dayLabel(d),
            style: const TextStyle(
              fontSize: 12.5,
              color: _kTextSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// Citation écrite par l'application des parents en tête de message :
  /// (auteur, extrait, texte) ou null.
  (String, String, String)? _citation(String text) {
    if (!text.startsWith('↪ ')) return null;
    final nl = text.indexOf('\n');
    if (nl < 0) return null;
    final head = text.substring(2, nl);
    final sep = head.indexOf(' : ');
    final body = text.substring(nl + 1);
    if (sep <= 0 || body.trim().isEmpty) return null;
    return (head.substring(0, sep).trim(), head.substring(sep + 3).trim(), body);
  }

  Widget _quoteBox(String auteur, String extrait) {
    // Vu de l'école : « École » = vous-même.
    final ecole = auteur.toLowerCase().startsWith('école');
    final couleur = ecole ? _kAccentGreen : const Color(0xFF1976D2);
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(13),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: couleur, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ecole ? 'Vous (école)' : 'Parent',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.bold, color: couleur)),
          Text(extrait,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: _kTextSecondary)),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m, DateTime? when) {
    final fromParent = m['sender'] == 'parent';
    final mine = !fromParent; // à droite = l'école
    final urgent = mine && m['urgent'] == true;
    final text = (m['message'] ?? '').toString();
    final title = (m['title'] ?? '').toString().trim();
    final type = (m['type'] ?? 'message').toString();
    final isRead = m['read'] == true;
    final readAt = _parseServerDate(m['read_at']?.toString());
    final delivered =
        (m['delivered_at'] ?? '').toString().trim().isNotEmpty || isRead;
    final maxWidth = MediaQuery.of(context).size.width * 0.80;

    String? typeLabel;
    if (mine) {
      switch (type) {
        case 'absence':
          typeLabel = 'ABSENCE';
          break;
        case 'convocation':
          typeLabel = 'CONVOCATION';
          break;
        case 'announcement':
          typeLabel = 'COMMUNIQUÉ';
          break;
      }
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 4),
            decoration: BoxDecoration(
              color: mine ? (urgent ? _urgentBg : _kBubbleMine) : _kBubbleOther,
              border:
              urgent ? Border.all(color: _urgentColor, width: 1.5) : null,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(mine ? 12 : 2),
                bottomRight: Radius.circular(mine ? 2 : 12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(35),
                  blurRadius: 1.5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (urgent) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _urgentColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'URGENT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                if (typeLabel != null) ...[
                  Text(
                    typeLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: _kAccentGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                if (mine &&
                    title.isNotEmpty &&
                    title != "Message de l'école") ...[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _kTextMain,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                // ⚡ Réponse d'un parent à un message (glisser sur WhatsApp) :
                // « ↪ École : extrait\ntexte » → encadré de citation.
                if (_citation(text) case final q?) ...[
                  _quoteBox(q.$1, q.$2),
                  const SizedBox(height: 4),
                ],
                Text(
                  _citation(text)?.$3 ?? text,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    color: _kTextMain,
                  ),
                ),
                const SizedBox(height: 3),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (mine && isRead && readAt != null) ...[
                        Text(
                          'Lu ${_hm(readAt)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: _kReadBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        when == null ? '' : _hm(when),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: _kTextSecondary,
                        ),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 3),
                        Icon(
                          delivered ? Icons.done_all : Icons.done,
                          size: 17,
                          color: isRead ? _kReadBlue : _kTextSecondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      color: _kChatBackground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_urgent)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _urgentBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _urgentColor),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.vibration, size: 16, color: _urgentColor),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Message URGENT : le téléphone du parent vibrera '
                              'par rappels successifs jusqu\'à ce qu\'il le lise.',
                          style: TextStyle(fontSize: 12.5, color: _urgentColor),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Marquer comme urgent',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _sending
                          ? null
                          : () => setState(() => _urgent = !_urgent),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _urgent ? _urgentColor : Colors.white,
                          border: Border.all(
                            color: _urgent
                                ? _urgentColor
                                : Colors.grey.shade400,
                          ),
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 22,
                          color: _urgent ? Colors.white : _kTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      cursorColor: _kAccentGreen,
                      // ⚡ Texte tapé : noir fixe, jamais blanc
                      style: const TextStyle(
                        fontSize: 16,
                        color: _kTextMain,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _urgent
                            ? 'Message urgent au parent…'
                            : 'Répondre au parent…',
                        hintStyle: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 16,
                        ),
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 11),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                              color: _kAccentGreen, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: _urgent ? _urgentColor : _kAccentGreen,
                    child: _sending
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                        : IconButton(
                      icon: const Icon(Icons.send,
                          color: Colors.white, size: 21),
                      onPressed: _send,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}