part of frais_scolaires;

/// Messagerie école ⇄ parents : messages envoyés, confirmations de lecture,
/// réponses des parents. Tout passe par les routes du serveur (app.py).
extension FraisScolairesMessagerie on FraisScolaires {
  // ------------------------------------------------------------------
  // Outils internes
  // ------------------------------------------------------------------
  Map<String, dynamic> _msgSansCode() => {
    'success': false,
    'error': "Code école manquant. Sauvegardez d'abord sur le serveur "
        "(Paramètres).",
  };

  Future<Map<String, dynamic>> _msgGet(
      String path, Map<String, String> params) async {
    if (schoolCode == null || schoolCode!.isEmpty) return _msgSansCode();
    try {
      final uri = Uri.parse('$serverUrl$path').replace(
        queryParameters: {'school_code': schoolCode!, ...params},
      );
      final response =
      await http.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(json.decode(response.body) as Map);
        return {'success': true, ...data};
      }
      return {
        'success': false,
        'error': 'Statut ${response.statusCode} : ${response.body}',
      };
    } on SocketException catch (e) {
      return {'success': false, 'error': 'Aucune connexion réseau : $e'};
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  Future<Map<String, dynamic>> _msgPost(
      String path, Map<String, dynamic> body) async {
    if (schoolCode == null || schoolCode!.isEmpty) return _msgSansCode();
    try {
      final response = await http
          .post(
        Uri.parse('$serverUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'school_code': schoolCode, ...body}),
      )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(json.decode(response.body) as Map);
        return {'success': true, ...data};
      }
      return {
        'success': false,
        'error': 'Statut ${response.statusCode} : ${response.body}',
      };
    } on SocketException catch (e) {
      return {'success': false, 'error': 'Aucune connexion réseau : $e'};
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  // ------------------------------------------------------------------
  // MESSAGES ENVOYÉS + CONFIRMATION DE LECTURE
  // ------------------------------------------------------------------

  /// Liste des envois de l'école (un communiqué à 30 élèves = 1 ligne).
  /// Réponse : success, batches, has_more, stats{sent, read, unread,
  /// urgent_unread}. Page suivante : beforeSeq = max_seq du dernier envoi.
  Future<Map<String, dynamic>> getSentMessages({
    int limit = 50,
    int beforeSeq = 0,
    String? studentId,
    String? type,
    bool urgentOnly = false,
    bool pendingOnly = false,
  }) {
    return _msgGet('/school/get_sent_messages', {
      'limit': '$limit',
      if (beforeSeq > 0) 'before_seq': '$beforeSeq',
      if (studentId != null && studentId.isNotEmpty) 'student_id': studentId,
      if (type != null && type.isNotEmpty) 'type': type,
      if (urgentOnly) 'urgent_only': '1',
      if (pendingOnly) 'pending_only': '1',
    });
  }

  /// Détail d'un envoi : pour chaque élève/parent → read | delivered | sent,
  /// read_at, delivered_at, nombre de téléphones enregistrés.
  Future<Map<String, dynamic>> getMessageReceipts(String batchId) {
    return _msgGet('/school/get_message_receipts', {'batch_id': batchId});
  }

  /// Arrête les rappels vibrants d'un message urgent (ex. parent joint par
  /// téléphone). Donner batchId OU messageId.
  Future<Map<String, dynamic>> stopUrgentReminders({
    String? batchId,
    String? messageId,
  }) {
    return _msgPost('/school/stop_reminders', {
      if (batchId != null && batchId.isNotEmpty) 'batch_id': batchId,
      if (messageId != null && messageId.isNotEmpty) 'message_id': messageId,
    });
  }

  // ------------------------------------------------------------------
  // MESSAGES DES PARENTS + RÉPONSES
  // ------------------------------------------------------------------

  /// Conversations (une par élève), la plus récente d'abord.
  /// Réponse : success, conversations[], total_unread.
  Future<Map<String, dynamic>> getParentConversations() {
    return _msgGet('/school/get_conversations', {});
  }

  /// Messages d'une conversation, ordre chronologique.
  /// afterSeq = nouveautés seulement ; beforeSeq = « charger plus ancien ».
  Future<Map<String, dynamic>> getParentConversation(
      String studentId, {
        int afterSeq = 0,
        int beforeSeq = 0,
        int limit = 100,
      }) {
    return _msgGet('/school/get_conversation', {
      'student_id': studentId,
      'limit': '$limit',
      if (afterSeq > 0) 'after_seq': '$afterSeq',
      if (beforeSeq > 0) 'before_seq': '$beforeSeq',
    });
  }

  /// L'école écrit au parent d'un élève. urgent = true → rappels vibrants
  /// jusqu'à la lecture. clientId rend l'envoi sans doublon si on réessaie.
  Future<Map<String, dynamic>> replyToParent({
    required String studentId,
    required String text,
    bool urgent = false,
    String title = "Message de l'école",
    String? clientId,
    String senderName = 'Direction',
  }) {
    return _msgPost('/school/reply_message', {
      'student_id': studentId,
      'text': text,
      'urgent': urgent,
      'title': title,
      'sender_name': senderName,
      'client_id': clientId ??
          'sch_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}',
    });
  }

  /// L'école a ouvert la conversation : les messages du parent passent à
  /// « lu » (le parent voit alors les ✓✓ bleus).
  Future<Map<String, dynamic>> markParentConversationRead(String studentId) {
    return _msgPost('/school/mark_conversation_read', {
      'student_id': studentId,
    });
  }

  /// Total des messages de parents non lus (pastille sur l'accueil).
  Future<int> getParentUnreadTotal() async {
    final r = await getParentConversations();
    if (r['success'] != true) return 0;
    return (r['total_unread'] as num?)?.toInt() ?? 0;
  }
}