import 'dart:async';
import 'package:flutter/material.dart';
import '../frais_scolaires.dart';

/// Détail d'UN envoi de l'école : pour chaque élève (donc chaque parent) :
///   ✓✓ bleu  « Lu à 14:32 »
///   ✓✓ gris  « Reçu sur le téléphone, pas encore lu »
///   ✓  gris  « Pas encore reçu »
/// + avertissement si aucun téléphone de parent n'est enregistré, et bouton
/// pour arrêter les rappels vibrants d'un message urgent.
class MessageReceiptsScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  final String batchId;
  final String titreInitial;

  const MessageReceiptsScreen({
    super.key,
    required this.fraisScolaires,
    required this.batchId,
    this.titreInitial = 'Détail de l\'envoi',
  });

  @override
  State<MessageReceiptsScreen> createState() => _MessageReceiptsScreenState();
}

class _MessageReceiptsScreenState extends State<MessageReceiptsScreen> {
  Map<String, dynamic> _batch = {};
  List<Map<String, dynamic>> _recipients = [];
  bool _loading = true;
  bool _stopping = false;
  String? _error;

  /// 'all' | 'read' | 'unread'
  String _filter = 'all';

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _loading || _stopping) return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Chargement
  // ------------------------------------------------------------------
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await widget.fraisScolaires.getMessageReceipts(widget.batchId);
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _batch = Map<String, dynamic>.from(r['batch'] as Map? ?? {});
        _recipients = (r['recipients'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  // ------------------------------------------------------------------
  // Arrêt des rappels
  // ------------------------------------------------------------------
  Future<void> _stopReminders({String? messageId, String? nom}) async {
    final bool pourUn = messageId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrêter les rappels ?'),
        content: Text(
          pourUn
              ? 'Le téléphone du parent de ${nom ?? 'cet élève'} ne vibrera '
              'plus pour ce message. Faites-le par exemple si vous avez '
              'déjà joint le parent par téléphone.'
              : 'Les téléphones des parents qui n\'ont pas encore lu ce '
              'message ne vibreront plus. Faites-le par exemple si vous '
              'avez déjà joint les parents par téléphone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _stopping = true);
    final r = await widget.fraisScolaires.stopUrgentReminders(
      batchId: pourUn ? null : widget.batchId,
      messageId: messageId,
    );
    if (!mounted) return;
    setState(() => _stopping = false);

    if (r['success'] == true) {
      final n = (r['stopped'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n > 0
              ? '✅ Rappels arrêtés ($n message(s))'
              : 'Aucun rappel à arrêter.'),
          backgroundColor: Colors.green,
        ),
      );
      _load(silent: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${r['error'] ?? 'Erreur inconnue'}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ------------------------------------------------------------------
  // Outils d'affichage
  // ------------------------------------------------------------------
  DateTime? _parse(String? s) {
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

  /// « 14:32 » si aujourd'hui, « hier à 14:32 », sinon « 12/11 à 14:32 ».
  String _quand(String? iso) {
    final d = _parse(iso);
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    final hm = '${_two(d.hour)}:${_two(d.minute)}';
    if (diff == 0) return hm;
    if (diff == 1) return 'hier à $hm';
    return '${_two(d.day)}/${_two(d.month)} à $hm';
  }

  int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case 'read':
        return _recipients.where((r) => r['read'] == true).toList();
      case 'unread':
        return _recipients.where((r) => r['read'] != true).toList();
      default:
        return _recipients;
    }
  }

  // ------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final titreBatch = (_batch['title'] ?? '').toString().trim();
    final titre = titreBatch.isNotEmpty ? titreBatch : widget.titreInitial;

    return Scaffold(
      appBar: AppBar(
        title: Text(titre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _loading ? null : () => _load(),
          ),
        ],
      ),
      body: _buildBody(),
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

    final list = _filtered;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
        children: [
          _buildSummary(),
          const SizedBox(height: 8),
          _buildUrgentBox(),
          _buildNoDeviceBox(),
          const SizedBox(height: 4),
          _buildFilters(),
          const SizedBox(height: 4),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _filter == 'read'
                      ? "Personne n'a encore lu ce message."
                      : (_filter == 'unread'
                      ? 'Tous les parents ont lu ce message. ✅'
                      : 'Aucun destinataire.'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...list.map(_buildRecipientTile),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final total = _int(_batch['total']);
    final readCount = _int(_batch['read_count']);
    final urgent = _batch['urgent'] == true;
    final message = (_batch['message'] ?? '').toString().trim();
    final created = _quand(_batch['created_at']?.toString());
    final allRead = total > 0 && readCount >= total;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (urgent)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC62828),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'URGENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    created.isEmpty ? 'Envoi' : 'Envoyé $created',
                    style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 14, height: 1.3)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : readCount / total,
                minHeight: 8,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                    allRead ? Colors.green : Colors.orange),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              total == 1
                  ? (allRead ? 'Lu par le parent' : 'Pas encore lu')
                  : '$readCount sur $total parents ont lu',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:
                allRead ? Colors.green.shade700 : Colors.orange.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Boîte rouge « message urgent pas lu » + bouton d'arrêt des rappels.
  Widget _buildUrgentBox() {
    final urgent = _batch['urgent'] == true;
    final unread = _int(_batch['unread_count']);
    if (!urgent || unread <= 0) return const SizedBox.shrink();

    final actifs = _recipients.where((r) =>
    r['read'] != true &&
        r['reminders_stopped'] != true &&
        _int(r['devices']) > 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        border: Border.all(color: const Color(0xFFC62828)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.vibration, color: Color(0xFFC62828)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  actifs.isNotEmpty
                      ? 'Le système fait vibrer les téléphones des parents '
                      'qui n\'ont pas lu ce message urgent, de plus en '
                      'plus insistamment, jusqu\'à la lecture.'
                      : 'Aucun rappel n\'est en cours pour ce message.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          if (actifs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _stopping ? null : () => _stopReminders(),
                icon: _stopping
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.notifications_off, size: 18),
                label: const Text('Arrêter tous les rappels'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC62828),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Avertissement : parents sans téléphone enregistré (pas de notification).
  Widget _buildNoDeviceBox() {
    final n = _int(_batch['no_device_count']);
    if (n <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.phonelink_erase, color: Color(0xFF856404)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              n == 1
                  ? '1 parent n\'a aucun téléphone enregistré : il ne reçoit '
                  'pas de notification et verra le message seulement en '
                  'ouvrant l\'application.'
                  : '$n parents n\'ont aucun téléphone enregistré : ils ne '
                  'reçoivent pas de notification et verront le message '
                  'seulement en ouvrant l\'application.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF856404)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final total = _recipients.length;
    final read = _recipients.where((r) => r['read'] == true).length;
    Widget f(String value, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == value,
          onSelected: (_) => setState(() => _filter = value),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          f('all', 'Tous ($total)'),
          f('unread', 'Pas lus (${total - read})'),
          f('read', 'Lus ($read)'),
        ],
      ),
    );
  }

  Widget _buildRecipientTile(Map<String, dynamic> r) {
    final status = (r['status'] ?? 'sent').toString();
    final nom = (r['nom_eleve'] ?? r['student_id'] ?? '').toString();
    final classe = (r['classe'] ?? '').toString();
    final devices = _int(r['devices']);
    final reminders = _int(r['reminder_count']);
    final stopped = r['reminders_stopped'] == true;
    final urgent = _batch['urgent'] == true;
    final isRead = r['read'] == true;

    IconData icon;
    Color color;
    String libelle;
    switch (status) {
      case 'read':
        icon = Icons.done_all;
        color = const Color(0xFF34B7F1);
        final q = _quand(r['read_at']?.toString());
        libelle = q.isEmpty ? 'Lu' : 'Lu $q';
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.grey.shade600;
        final q = _quand(r['delivered_at']?.toString());
        libelle = q.isEmpty
            ? 'Reçu, pas encore lu'
            : 'Reçu $q — pas encore lu';
        break;
      default:
        icon = Icons.done;
        color = Colors.grey.shade600;
        libelle = devices == 0
            ? 'Pas reçu (aucun téléphone enregistré)'
            : 'Envoyé, pas encore reçu';
    }

    String? ligne3;
    if (urgent && !isRead) {
      if (stopped) {
        ligne3 = 'Rappels arrêtés par l\'école';
      } else if (reminders > 0) {
        ligne3 = '$reminders rappel(s) envoyé(s)';
      }
    }

    final bool peutArreter =
        urgent && !isRead && !stopped && devices > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: color, size: 26),
        title: Text(
          nom,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (classe.isNotEmpty)
              Text(classe,
                  style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            Text(
              libelle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isRead ? Colors.green.shade700 : color,
              ),
            ),
            if (ligne3 != null)
              Text(
                ligne3,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFFC62828)),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: peutArreter
            ? IconButton(
          icon: const Icon(Icons.notifications_off_outlined,
              color: Color(0xFFC62828)),
          tooltip: 'Arrêter les rappels pour ce parent',
          onPressed: _stopping
              ? null
              : () => _stopReminders(
            messageId: (r['message_id'] ?? '').toString(),
            nom: nom,
          ),
        )
            : null,
      ),
    );
  }
}