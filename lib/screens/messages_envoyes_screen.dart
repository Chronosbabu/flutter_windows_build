import 'dart:async';
import 'package:flutter/material.dart';
import '../frais_scolaires.dart';
import 'message_receipts_screen.dart';

/// Écran « Messages envoyés » de l'école : tout ce que l'école a envoyé aux
/// parents (absences, convocations, communiqués, messages), avec pour chaque
/// envoi le nombre de parents qui l'ont LU. Un appui ouvre le détail par
/// parent (« lu à 14:32 », « pas encore lu »...).
class MessagesEnvoyesScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;

  /// Optionnel : n'afficher que les messages envoyés à un seul élève.
  final String? studentId;
  final String? studentName;

  const MessagesEnvoyesScreen({
    super.key,
    required this.fraisScolaires,
    this.studentId,
    this.studentName,
  });

  @override
  State<MessagesEnvoyesScreen> createState() => _MessagesEnvoyesScreenState();
}

class _TypeInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _TypeInfo(this.label, this.color, this.icon);
}

class _MessagesEnvoyesScreenState extends State<MessagesEnvoyesScreen> {
  static const int _pageSize = 30;

  List<Map<String, dynamic>> _batches = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  /// 'all' | 'pending' (pas encore lus) | 'urgent'
  String _filter = 'all';

  /// null = tous les types
  String? _type;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Actualisation automatique : l'école voit les lectures arriver.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _loading || _loadingMore) return;
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
  List<Map<String, dynamic>> _readBatches(Map<String, dynamic> r) {
    return (r['batches'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await widget.fraisScolaires.getSentMessages(
      limit: _pageSize,
      studentId: widget.studentId,
      type: _type,
      urgentOnly: _filter == 'urgent',
      pendingOnly: _filter == 'pending',
    );
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _batches = _readBatches(r);
        _stats = Map<String, dynamic>.from(r['stats'] as Map? ?? {});
        _hasMore = r['has_more'] == true;
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

  Future<void> _loadMore() async {
    if (_loadingMore || _batches.isEmpty) return;
    setState(() => _loadingMore = true);
    final lastSeq = (_batches.last['max_seq'] as num?)?.toInt() ?? 0;
    final r = await widget.fraisScolaires.getSentMessages(
      limit: _pageSize,
      beforeSeq: lastSeq,
      studentId: widget.studentId,
      type: _type,
      urgentOnly: _filter == 'urgent',
      pendingOnly: _filter == 'pending',
    );
    if (!mounted) return;
    if (r['success'] == true) {
      final more = _readBatches(r);
      final known = _batches.map((b) => b['batch_id']).toSet();
      setState(() {
        _batches.addAll(more.where((b) => !known.contains(b['batch_id'])));
        _hasMore = r['has_more'] == true;
        _loadingMore = false;
      });
    } else {
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${r['error'] ?? 'Erreur inconnue'}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    _load();
  }

  void _setType(String? value) {
    setState(() => _type = value);
    _load();
  }

  // ------------------------------------------------------------------
  // Outils d'affichage
  // ------------------------------------------------------------------
  _TypeInfo _typeInfo(String type) {
    switch (type) {
      case 'absence':
        return const _TypeInfo('Absence', Color(0xFFEF6C00), Icons.person_off);
      case 'convocation':
        return const _TypeInfo(
            'Convocation', Color(0xFFD32F2F), Icons.gavel);
      case 'announcement':
        return const _TypeInfo(
            'Communiqué', Color(0xFF1976D2), Icons.campaign);
      case 'message':
        return const _TypeInfo(
            'Message', Color(0xFF2E7D32), Icons.chat_bubble_outline);
      default:
        return const _TypeInfo(
            'Information', Color(0xFF616161), Icons.info_outline);
    }
  }

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

  String _formatDate(String? iso) {
    final d = _parse(iso);
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    final hm = '${_two(d.hour)}:${_two(d.minute)}';
    if (diff == 0) return "Aujourd'hui $hm";
    if (diff == 1) return 'Hier $hm';
    return '${_two(d.day)}/${_two(d.month)}/${d.year} $hm';
  }

  int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  // ------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final titre = widget.studentName != null
        ? 'Messages envoyés — ${widget.studentName}'
        : 'Messages envoyés';

    return Scaffold(
      appBar: AppBar(
        title: Text(titre, style: const TextStyle(fontSize: 18)),
        centerTitle: true,
        actions: [
          PopupMenuButton<String?>(
            icon: Icon(
              Icons.filter_list,
              color: _type != null ? Colors.amber : null,
            ),
            tooltip: 'Filtrer par type',
            onSelected: _setType,
            itemBuilder: (_) => const [
              PopupMenuItem<String?>(value: null, child: Text('Tous les types')),
              PopupMenuItem<String?>(
                  value: 'absence', child: Text('Absences')),
              PopupMenuItem<String?>(
                  value: 'convocation', child: Text('Convocations')),
              PopupMenuItem<String?>(
                  value: 'announcement', child: Text('Communiqués')),
              PopupMenuItem<String?>(
                  value: 'message', child: Text('Messages libres')),
            ],
          ),
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
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

    return Column(
      children: [
        _buildStats(),
        _buildFilters(),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _batches.isEmpty
                ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Icon(Icons.mark_email_read_outlined,
                    size: 70, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _filter == 'all' && _type == null
                        ? "Aucun message envoyé pour l'instant."
                        : 'Aucun message pour ce filtre.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            )
                : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
              itemCount: _batches.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _batches.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator()
                          : OutlinedButton.icon(
                        onPressed: _loadMore,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Charger plus'),
                      ),
                    ),
                  );
                }
                return _buildBatchCard(_batches[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    final sent = _int(_stats['sent']);
    final read = _int(_stats['read']);
    final unread = _int(_stats['unread']);
    final urgentUnread = _int(_stats['urgent_unread']);

    Widget chip(String label, int value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(label, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(
        children: [
          Row(
            children: [
              chip('Envoyés', sent, Colors.blueGrey),
              const SizedBox(width: 8),
              chip('Lus', read, Colors.green),
              const SizedBox(width: 8),
              chip('Pas encore lus', unread, Colors.orange.shade800),
            ],
          ),
          if (urgentUnread > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      urgentUnread > 1
                          ? '$urgentUnread messages URGENTS ne sont pas encore lus.'
                          : '1 message URGENT n\'est pas encore lu.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilters() {
    Widget f(String value, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == value,
          onSelected: (_) => _setFilter(value),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: Row(
        children: [
          f('all', 'Tous'),
          f('pending', 'Pas encore lus'),
          f('urgent', 'Urgents'),
        ],
      ),
    );
  }

  Widget _buildBatchCard(Map<String, dynamic> b) {
    final type = (b['type'] ?? 'message').toString();
    final info = _typeInfo(type);
    final urgent = b['urgent'] == true;
    final total = _int(b['total']);
    final readCount = _int(b['read_count']);
    final unreadCount = _int(b['unread_count']);
    final reminders = _int(b['reminders_sent']);
    final allRead = total > 0 && readCount >= total;
    final title = (b['title'] ?? '').toString().trim();
    final message = (b['message'] ?? '').toString().trim();
    final unreadNames = (b['unread_names'] as List? ?? [])
        .map((e) => e.toString())
        .toList();

    final Color progressColor = allRead
        ? Colors.green
        : (urgent ? const Color(0xFFC62828) : Colors.orange);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: urgent && !allRead
            ? const BorderSide(color: Color(0xFFC62828), width: 1.5)
            : BorderSide.none,
      ),
      color: urgent && !allRead ? const Color(0xFFFFF5F5) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MessageReceiptsScreen(
                fraisScolaires: widget.fraisScolaires,
                batchId: (b['batch_id'] ?? '').toString(),
                titreInitial: title.isNotEmpty ? title : info.label,
              ),
            ),
          );
          if (mounted) _load(silent: true);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(info.icon, size: 18, color: info.color),
                  const SizedBox(width: 6),
                  Text(
                    info.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: info.color,
                    ),
                  ),
                  if (urgent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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
                  ],
                  const Spacer(),
                  Text(
                    _formatDate(b['created_at']?.toString()),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : readCount / total,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    allRead ? Icons.done_all : Icons.done,
                    size: 16,
                    color: allRead
                        ? const Color(0xFF34B7F1)
                        : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      total == 1
                          ? (allRead ? 'Lu par le parent' : 'Pas encore lu')
                          : '$readCount / $total parents ont lu',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: allRead
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                  if (urgent && !allRead && reminders > 0)
                    Text(
                      '$reminders rappel(s)',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFC62828)),
                    ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              if (!allRead && unreadNames.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Pas lu : ${unreadNames.join(', ')}'
                      '${unreadCount > unreadNames.length ? '…' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}