import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'services/epson_printer_service.dart';

const String serverUrl = "https://jsinf.onrender.com";

// ==========================================================================
// ⚡ NOUVEAU — MODÈLE DÉPENSE (sortie de caisse)
// Autonome (pas besoin de toucher models.dart) : motif/justification,
// montant, date/heure exacte, et qui l'a enregistrée.
// ==========================================================================
class Depense {
  String id;
  String motif;
  double montant;
  DateTime date;
  String enregistrePar;

  Depense({
    required this.id,
    required this.motif,
    required this.montant,
    required this.date,
    this.enregistrePar = 'Direction',
  });

  factory Depense.fromJson(Map<String, dynamic> json) => Depense(
    id: json['id'] as String? ?? '',
    motif: json['motif'] as String? ?? '',
    montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.tryParse(json['date'] as String? ?? '') ??
        DateTime.now(),
    enregistrePar: json['enregistrePar'] as String? ?? 'Direction',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'motif': motif,
    'montant': montant,
    'date': date.toIso8601String(),
    'enregistrePar': enregistrePar,
  };

  /// Ex: "14/08/2026 à 10:32"
  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

// ==========================================================================
// ⚡ NOUVEAU — MODÈLE AUTRE FRAIS (frais additionnel/éphémère)
// Contrairement aux frais mensuels principaux (feesBySection/feesByClasse),
// ce sont des frais ponctuels propres à chaque école (ex: Frais de l'État,
// Frais d'Aide...) que l'utilisateur peut ajouter ou supprimer librement,
// à tout moment, depuis les Paramètres.
// ==========================================================================
class AutreFrais {
  String id;
  String nom;
  double montant;
  // 'all'     = toute l'école
  // 'section' = une section précise (voir `section`)
  // 'classe'  = une classe précise (voir `classe`, nom complet avec
  //             éventuelle sous-classe, ex: "6eme A")
  String scope;
  String? section;
  String? classe;
  DateTime dateCreation;

  AutreFrais({
    required this.id,
    required this.nom,
    required this.montant,
    this.scope = 'all',
    this.section,
    this.classe,
    DateTime? dateCreation,
  }) : dateCreation = dateCreation ?? DateTime.now();

  factory AutreFrais.fromJson(Map<String, dynamic> json) => AutreFrais(
    id: json['id'] as String? ?? '',
    nom: json['nom'] as String? ?? '',
    montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
    scope: json['scope'] as String? ?? 'all',
    section: json['section'] as String?,
    classe: json['classe'] as String?,
    dateCreation:
    DateTime.tryParse(json['dateCreation'] as String? ?? '') ??
        DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'montant': montant,
    'scope': scope,
    'section': section,
    'classe': classe,
    'dateCreation': dateCreation.toIso8601String(),
  };
}

// ==========================================================================
// ⚡ NOUVEAU — PAIEMENT D'UN AUTRE FRAIS
// On conserve une "photo" du nom du frais au moment du paiement
// (autreFraisNom), pour que l'historique reste lisible même si le frais
// correspondant a été supprimé entretemps par l'utilisateur (frais
// éphémères, contrairement au frais mensuel principal).
// ==========================================================================
class AutreFraisPaiement {
  String id;
  String autreFraisId;
  String autreFraisNom;
  String eleveId;
  double montant;
  DateTime date;
  String enregistrePar;

  AutreFraisPaiement({
    required this.id,
    required this.autreFraisId,
    required this.autreFraisNom,
    required this.eleveId,
    required this.montant,
    required this.date,
    this.enregistrePar = 'Direction',
  });

  factory AutreFraisPaiement.fromJson(Map<String, dynamic> json) =>
      AutreFraisPaiement(
        id: json['id'] as String? ?? '',
        autreFraisId: json['autreFraisId'] as String? ?? '',
        autreFraisNom: json['autreFraisNom'] as String? ?? '',
        eleveId: json['eleveId'] as String? ?? '',
        montant: (json['montant'] as num?)?.toDouble() ?? 0.0,
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        enregistrePar: json['enregistrePar'] as String? ?? 'Direction',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'autreFraisId': autreFraisId,
    'autreFraisNom': autreFraisNom,
    'eleveId': eleveId,
    'montant': montant,
    'date': date.toIso8601String(),
    'enregistrePar': enregistrePar,
  };

  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

// ==========================================================================
// ⚡ NOUVEAU — DÉTAIL DE RÉPARTITION (par Option ou par Section pédagogique)
// Structure légère de sortie utilisée par les méthodes de répartition
// ci-dessous. Purement calculée à la volée (rien n'est persisté ici) :
// un simple libellé, un montant total, et la répartition théorique de
// ce montant selon les pourcentages des administrations.
// ==========================================================================
class RepartitionDetail {
  final String label;
  final double total;
  final Map<String, double> parAdministration;

  RepartitionDetail({
    required this.label,
    required this.total,
    required this.parAdministration,
  });
}

// ==========================================================================
// ⚡ NOUVEAU — JOURNAL D'AUDIT ADMINISTRATEUR (mode caché)
// Chaque annulation ou modification d'un paiement déjà enregistré passe
// forcément par ici, pour garder une trace complète (qui/quoi/quand/
// combien). C'est la contrepartie indispensable d'une fonctionnalité
// cachée : elle doit rester traçable pour celui qui la détient.
// ==========================================================================
class AdminAuditLog {
  String id;
  String action; // 'annulation' | 'modification'
  String eleveId;
  String eleveNomComplet;
  String classe;
  String mois;
  double montantAvant;
  double montantApres;
  DateTime date;

  AdminAuditLog({
    required this.id,
    required this.action,
    required this.eleveId,
    required this.eleveNomComplet,
    required this.classe,
    required this.mois,
    required this.montantAvant,
    required this.montantApres,
    DateTime? date,
  }) : date = date ?? DateTime.now();

  factory AdminAuditLog.fromJson(Map<String, dynamic> json) => AdminAuditLog(
    id: json['id'] as String? ?? '',
    action: json['action'] as String? ?? '',
    eleveId: json['eleveId'] as String? ?? '',
    eleveNomComplet: json['eleveNomComplet'] as String? ?? '',
    classe: json['classe'] as String? ?? '',
    mois: json['mois'] as String? ?? '',
    montantAvant: (json['montantAvant'] as num?)?.toDouble() ?? 0.0,
    montantApres: (json['montantApres'] as num?)?.toDouble() ?? 0.0,
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action,
    'eleveId': eleveId,
    'eleveNomComplet': eleveNomComplet,
    'classe': classe,
    'mois': mois,
    'montantAvant': montantAvant,
    'montantApres': montantApres,
    'date': date.toIso8601String(),
  };

  String get dateFormatee {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} à '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

// ==========================================================================
// ⚡ NOUVEAU — SIGNATAIRE (personnes devant signer les rapports PDF)
// Utilisé pour afficher, en bas des rapports PDF générés depuis l'écran
// "Rapport PDF", un bloc de signatures professionnel (nom + fonction de
// chaque personne, avec un espace et une ligne pour signer à la main),
// sur le modèle des rapports financiers utilisés dans les écoles en RDC
// (ex: Le Caissier / Le Préfet des Études / Le Chef d'Établissement).
// Cette liste est configurée une seule fois (ajout/modification/
// suppression depuis l'écran de génération de rapport) et réutilisée
// automatiquement sur chaque rapport généré, comme le fait déjà
// `config.administrations` pour la répartition.
// ==========================================================================
class Signataire {
  String id;
  String nom;
  String fonction;

  Signataire({
    required this.id,
    required this.nom,
    required this.fonction,
  });

  factory Signataire.fromJson(Map<String, dynamic> json) => Signataire(
    id: json['id'] as String? ?? '',
    nom: json['nom'] as String? ?? '',
    fonction: json['fonction'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'fonction': fonction,
  };
}

class FraisScolaires {
  SchoolConfig config;
  SchoolYearData currentData = SchoolYearData(eleves: []);
  String currentYear = '2025-2026';
  Map<String, SchoolYearData> history = {};
  String? _dataFilePath;
  String? lastSelectedClassFilter;
  String? lastSelectedSectionFilter;

  // ⚡ CORRIGÉ : le school_code est maintenant persisté dans le JSON
  // local (saveData/loadData) — voir plus bas. Avant, ce champ n'était
  // rempli qu'en mémoire pendant la session en cours, et redevenait
  // "null" après chaque redémarrage tant qu'aucun backup/restore
  // n'avait été relancé manuellement.
  String? schoolCode;

  // ⚡ NOUVEAU — sorties de caisse (dépenses), classées par année scolaire
  // comme "history", pour rester cohérent avec le reste de l'appli.
  Map<String, List<Depense>> depensesByYear = {};

  // ⚡ NOUVEAU — frais additionnels (éphémères, propres à chaque école)
  // et leurs paiements, classés par année scolaire comme "depensesByYear".
  List<AutreFrais> autresFrais = [];
  Map<String, List<AutreFraisPaiement>> autresFraisPaiementsByYear = {};

  // ==========================================================================
  // ⚡ NOUVEAU — MODE ADMINISTRATEUR CACHÉ (annulation / modification de
  // paiements déjà enregistrés).
  //
  // Le "code masqué" est totalement indépendant du mot de passe de
  // sauvegarde/restauration : c'est un code que l'admin choisit lui-même
  // au premier déclenchement du geste secret, dans l'écran des
  // paiements. Le caissier à qui l'appareil est confié n'a normalement
  // jamais connaissance de son existence.
  //
  // Sécurité : on ne stocke JAMAIS le code en clair. On stocke un hash
  // SHA-256 du code combiné à un sel aléatoire unique. Même en ouvrant
  // le fichier school_fees_data.json avec un éditeur de texte, il est
  // impossible de retrouver le code original.
  // ==========================================================================
  String? hiddenCodeHash;
  String? hiddenCodeSalt;

  // ⚡ NOUVEAU — journal d'audit des annulations/modifications de
  // paiements effectuées via le mode administrateur caché.
  List<AdminAuditLog> adminAuditLog = [];

  // ⚡ NOUVEAU — liste des personnes devant signer les rapports PDF
  // (voir la classe Signataire ci-dessus).
  List<Signataire> signataires = [];

  // ⚡ NOUVEAU — dernière ville utilisée pour générer un rapport PDF
  // (ex: "Lubumbashi"), mémorisée exactement comme
  // `lastSelectedClassFilter` : simple commodité pour pré-remplir
  // automatiquement le champ "Ville" de l'écran de génération de
  // rapport la prochaine fois, sans avoir à la ressaisir à chaque
  // fois. N'a aucune incidence sur les calculs, uniquement sur le
  // texte "Fait à ..., le ..." imprimé au bas des rapports PDF (voir
  // `_buildSignatureSection`).
  String? lastReportCity;

  // ==========================================================================
  // ⚡ NOUVEAU — IMPRESSION DES REÇUS : ANTI-DOUBLON + FILE D'ATTENTE
  // PERSISTANTE
  //
  // `printedReceiptKeys` retient, de façon DÉFINITIVE, la clé de chaque
  // reçu déjà imprimé avec succès (frais principal : un par élève et par
  // mois ; autre frais : un par élève et par type de frais) — dès
  // qu'une clé y figure, plus aucune impression n'est jamais retentée
  // pour elle, quel que soit l'écran d'où la demande provient.
  //
  // `receiptQueue` retient les reçus dont l'impression a été demandée
  // mais n'a pas encore abouti (imprimante débranchée/non configurée
  // au moment du paiement) — chaque entrée contient tout ce qu'il faut
  // pour imprimer plus tard EXACTEMENT le même reçu, sans redemander
  // quoi que ce soit. Les deux listes vivent dans le MÊME fichier JSON
  // que le reste (voir loadData/saveData) : elles survivent donc aussi
  // bien à la fermeture de l'application qu'à l'extinction complète de
  // l'ordinateur — rien n'est perdu, et rien n'est jamais imprimé deux
  // fois. Voir la section "IMPRESSION DES REÇUS" plus bas pour le
  // détail des méthodes.
  // ==========================================================================
  List<String> printedReceiptKeys = [];
  List<Map<String, dynamic>> receiptQueue = [];

  // ==========================================================================
  // ⚡ NOUVEAU — MODE RÉSEAU LOCAL (sans internet, via le point d'accès
  // Windows du PC principal, adresse fixe 192.168.137.1)
  //
  // Quand l'appareil n'a pas internet, les clés d'accès ne sont plus
  // générées/vérifiées par le serveur central (render.com) mais
  // directement ici, en local. Ces données vivent dans le MÊME fichier
  // school_fees_data.json que le reste (voir loadData/saveData), donc
  // elles survivent aux redémarrages exactement comme les élèves ou les
  // paiements.
  //
  // Le petit serveur HTTP local (voir local_server_service.dart) lit et
  // modifie directement CES champs sur l'instance FraisScolaires déjà en
  // mémoire de l'app principale — il n'y a donc aucune duplication de
  // données entre "l'admin" et "le serveur qu'il héberge" : c'est
  // littéralement la même instance.
  // ==========================================================================

  /// Clés d'accès générées localement : {key, type, sections, classe,
  /// createdAt}. Indépendant des clés générées par le serveur central —
  /// les deux formats peuvent coexister sans collision (préfixe "LOC-"
  /// réservé aux clés locales).
  List<Map<String, dynamic>> localAccessKeys = [];

  /// Paiements de frais mensuels envoyés par des sous-utilisateurs
  /// connectés en local, en attente de validation par l'admin — même
  /// principe que la file d'attente côté serveur central, mais tenue
  /// ici pour fonctionner entièrement sans internet.
  List<Map<String, dynamic>> localPendingPayments = [];

  /// Inscriptions d'élèves envoyées en local, en attente de validation.
  List<Map<String, dynamic>> localPendingRegistrations = [];

  /// Paiements d'"autres frais" envoyés en local, en attente de
  /// validation.
  List<Map<String, dynamic>> localPendingAutresFraisPayments = [];

  /// Registre de présence local : clé "classe|date" -> liste des ID
  /// d'élèves absents ce jour-là pour cette classe.
  Map<String, List<String>> localAttendance = {};

  /// Journal des convocations/communiqués envoyés en mode local. ⚠️
  /// IMPORTANT : en l'absence d'internet, il n'existe aucun canal pour
  /// notifier réellement les parents (pas de SMS/push possible hors
  /// ligne) — ces entrées sont donc conservées avec `delivered: false`
  /// pour rappeler qu'elles devront être renvoyées une fois l'appareil
  /// reconnecté à internet, plutôt que de laisser croire qu'un message a
  /// été livré alors qu'il ne l'a pas été.
  List<Map<String, dynamic>> localCommunicationsLog = [];

  int _localIdCounter = 0;

  final List<String> months = [
    'Septembre', 'Octobre', 'Novembre', 'Decembre',
    'Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin'
  ];

  // ⚡ NOUVEAU — noms des jours de la semaine (pour l'affichage "date et
  // jour de génération" demandé par les utilisateurs sur les rapports
  // PDF). Index 0 = Lundi (DateTime.weekday commence à 1 pour Lundi).
  static const List<String> _joursSemaine = [
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
  ];

  FraisScolaires() : config = SchoolConfig(schoolName: "EduPay School RDC");

  // ====================================================================
  // ⚡ CORRIGÉ — MOIS SCOLAIRE COURANT
  //
  // BUG TROUVÉ : `months` est ordonné selon l'ANNÉE SCOLAIRE
  // (Septembre → Juin, index 0 à 9), pas selon le calendrier normal
  // (Janvier → Décembre). Le code faisait auparavant, à 3 endroits
  // différents, `months[DateTime.now().month - 1]` en supposant que
  // l'index 0 correspond à Janvier — ce qui est faux ici.
  //
  // Conséquence concrète : en Août (mois calendaire 8), l'ancien code
  // calculait `months[7]`, qui vaut "Avril" dans cette liste. C'est
  // exactement le symptôme décrit ("le rapport journalier affiche le
  // mois d'Avril") : la ligne "Total ce Mois (...)" du PDF utilisait ce
  // mauvais mapping, quel que soit le type de rapport choisi. Pire
  // encore : en Novembre/Décembre (mois calendaire 11 ou 12), l'index
  // calculé (10 ou 11) sortait carrément des limites du tableau (10
  // éléments), ce qui pouvait planter `getPaidStudentsThisMonth()`.
  //
  // Cette méthode centralise le bon calcul : Septembre(9)->0,
  // Octobre(10)->1, ..., Décembre(12)->3, Janvier(1)->4, ...,
  // Juin(6)->9. Juillet et Août (grandes vacances) ne font partie
  // d'aucune année scolaire : on renvoie -1 dans ce cas, et tous les
  // appelants doivent gérer ce cas (pas de "mois en cours" pendant les
  // vacances).
  // ====================================================================
  int _schoolMonthIndexForToday() {
    final calendarMonth = DateTime.now().month; // 1 (Janvier)..12 (Décembre)
    if (calendarMonth >= 9 && calendarMonth <= 12) {
      return calendarMonth - 9; // Sept->0, Oct->1, Nov->2, Dec->3
    } else if (calendarMonth >= 1 && calendarMonth <= 6) {
      return calendarMonth + 3; // Jan->4, Fev->5, Mar->6, Avr->7, Mai->8, Jun->9
    }
    // Juillet / Août : hors année scolaire.
    return -1;
  }

  /// Nom du mois scolaire courant (ex: "Aout" retournerait null, "Avril"
  /// si on est en Avril), ou `null` si on est en Juillet/Août
  /// (grandes vacances, hors année scolaire).
  String? get currentSchoolMonthName {
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return null;
    return months[idx];
  }

  /// ⚡ NOUVEAU — date ET jour de génération, formatés pour affichage
  /// sur les rapports PDF (demande explicite des utilisateurs). Reprend
  /// le même style que `dateFormatee` déjà utilisé ailleurs dans ce
  /// fichier (Depense, AutreFraisPaiement, AdminAuditLog), au lieu du
  /// format ISO brut (`DateTime.now().toString()`) utilisé jusqu'ici
  /// dans les rapports, qui n'indiquait pas le jour de la semaine.
  /// Ex: "Lundi 24/08/2026 à 10:32".
  String get _dateGenerationFormatee {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final jour = _joursSemaine[now.weekday - 1];
    return '$jour ${two(now.day)}/${two(now.month)}/${now.year} à '
        '${two(now.hour)}:${two(now.minute)}';
  }

  // ====================================================================
  // ⚡ NOUVEAU — MOIS CONCERNÉ(S) PAR LES PAIEMENTS D'UN JOUR PRÉCIS
  //
  // Sert au RAPPORT JOURNALIER : à côté du montant déjà affiché pour
  // chaque élève, on veut aussi savoir POUR QUEL(S) MOIS il a payé
  // aujourd'hui (un élève peut très bien régler, en une seule fois,
  // le mois courant ET un ou plusieurs mois d'arriéré — voir
  // `handlePayment`, qui répartit automatiquement un paiement sur
  // plusieurs mois si besoin).
  //
  // On relit simplement les transactions de l'élève dont la date
  // correspond à `date` (aujourd'hui par défaut), on additionne les
  // mois distincts concernés, et on les remet dans l'ordre de l'année
  // scolaire (et non l'ordre d'ajout) pour un affichage cohérent, ex:
  // "Septembre" ou "Septembre, Octobre" (arriéré + mois courant réglés
  // le même jour).
  //
  // Renvoie une chaîne vide si l'élève n'a aucune transaction à cette
  // date (ne devrait normalement pas arriver pour un élève déjà
  // filtré par `getPaidStudentsToday()`, mais reste défensif).
  // ====================================================================
  String getMoisPayesPourDate(Eleve eleve, [String? date]) {
    final targetDate = date ?? DateTime.now().toString().split(' ')[0];
    final moisDuJour = <String>[];
    for (final t in eleve.transactions) {
      if (t['date'] == targetDate) {
        final mois = t['mois']?.toString() ?? '';
        if (mois.isNotEmpty && !moisDuJour.contains(mois)) {
          moisDuJour.add(mois);
        }
      }
    }
    moisDuJour.sort(
            (a, b) => months.indexOf(a).compareTo(months.indexOf(b)));
    return moisDuJour.join(', ');
  }

  // ====================================================================
  // ⚡ NOUVEAU — BLOC DE SIGNATURES (bas des rapports PDF)
  //
  // Reprend la mise en page classique utilisée dans les rapports
  // financiers scolaires en RDC : une ligne "Fait à <Ville>, le ...",
  // puis une rangée de colonnes (3 maximum par ligne, pour rester
  // lisible sur une page A4) — chaque colonne réservant un espace vide
  // pour la signature manuscrite, une ligne, puis le nom et la fonction
  // de la personne imprimés en dessous. Si aucun signataire n'est
  // configuré, ne renvoie rien (le rapport garde exactement son
  // apparence actuelle, sans bloc vide).
  //
  // ⚡ NOUVEAU — cette même méthode est désormais réutilisée aussi bien
  // par le rapport "Frais Principal" (generatePdf / _generateStudentListPdf)
  // que par le nouveau rapport "Autres Frais de Paiement"
  // (generateAutresFraisPdf, voir plus bas) : les deux rapports partagent
  // donc exactement le même bloc de signatures, configuré une seule fois.
  //
  // ⚡ NOUVEAU — `city` : la ville saisie par l'utilisateur dans l'écran
  // de génération de rapport (ex: "Lubumbashi"), reprise ici pour
  // composer "Fait à <Ville>, le ...", conformément à la formule
  // standard utilisée dans les documents administratifs et scolaires
  // en RDC ("Fait à [Ville], le [date]"). Si aucune ville n'est fournie
  // (champ laissé vide), on retombe sur "Lubumbashi" par défaut plutôt
  // que d'afficher une virgule flottant dans le vide.
  // ====================================================================
  List<pw.Widget> _buildSignatureSection([String? city]) {
    if (signataires.isEmpty) return [];

    final villeAffichee =
    (city != null && city.trim().isNotEmpty) ? city.trim() : 'Lubumbashi';

    final rows = <List<Signataire>>[];
    for (var i = 0; i < signataires.length; i += 3) {
      final end = (i + 3 > signataires.length) ? signataires.length : i + 3;
      rows.add(signataires.sublist(i, end));
    }

    pw.Widget buildColonne(Signataire s) {
      return pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Espace réservé à la signature manuscrite.
              pw.SizedBox(height: 34),
              // Ligne de signature.
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(width: 0.8, color: PdfColors.black),
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                s.nom.isNotEmpty ? s.nom : ' ',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                s.fonction.isNotEmpty ? s.fonction : ' ',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return [
      pw.SizedBox(height: 36),
      pw.Divider(thickness: 0.6, color: PdfColors.grey400),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Fait à $villeAffichee, le : $_dateGenerationFormatee',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      pw.SizedBox(height: 26),
      ...rows.map((rowSignataires) {
        final widgets = rowSignataires.map(buildColonne).toList();
        // Complète la dernière rangée avec des colonnes vides pour que
        // les lignes de signature restent alignées même si le nombre
        // de signataires n'est pas un multiple de 3.
        while (widgets.length < 3) {
          widgets.add(pw.Expanded(child: pw.SizedBox()));
        }
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 24),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: widgets,
          ),
        );
      }),
    ];
  }

  // ====================================================================
  // ⚡ NOUVEAU — GESTION DU CODE MASQUÉ (mode administrateur caché)
  // ====================================================================

  /// Vrai si un code masqué a déjà été défini sur cette installation
  /// (ou reçu via une restauration serveur).
  bool get hiddenCodeIsConfigured =>
      hiddenCodeHash != null && hiddenCodeHash!.isNotEmpty;

  String _hashWithSalt(String code, String salt) {
    final bytes = utf8.encode('$salt::$code');
    return sha256.convert(bytes).toString();
  }

  /// Définit (ou redéfinit) le code masqué. À utiliser uniquement lors
  /// de la première configuration par l'admin — l'écran doit s'assurer
  /// qu'il ne propose ceci que si `hiddenCodeIsConfigured` est faux,
  /// pour ne pas laisser n'importe qui l'écraser.
  Future<void> setHiddenCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    final rand = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final salt = base64Url.encode(saltBytes);
    hiddenCodeSalt = salt;
    hiddenCodeHash = _hashWithSalt(trimmed, salt);
    await saveData();
  }

  /// Vérifie un code saisi par rapport au hash stocké. Ne révèle jamais
  /// le code réel, seulement vrai/faux.
  bool verifyHiddenCode(String code) {
    if (!hiddenCodeIsConfigured) return false;
    return _hashWithSalt(code.trim(), hiddenCodeSalt!) == hiddenCodeHash;
  }

  // ====================================================================
  // ⚡ NOUVEAU — ANNULATION / MODIFICATION D'UN PAIEMENT DÉJÀ ENREGISTRÉ
  // (réservé au mode administrateur caché)
  //
  // Contrairement au reste de l'application, aucun paiement n'est
  // normalement modifiable après coup — ces deux méthodes sont les
  // SEULES portes d'entrée qui permettent de le faire, et elles
  // journalisent systématiquement l'action dans `adminAuditLog`.
  //
  // Important : `transaction` doit être la RÉFÉRENCE exacte de l'entrée
  // telle que lue depuis `eleve.transactions` (ex: via `.where(...)`),
  // pas une copie — la suppression/modification se fait par identité
  // d'objet, ce qui évite d'avoir à ajouter un identifiant unique à
  // chaque transaction existante.
  // ====================================================================

  /// Annule complètement un paiement : retire l'entrée de l'historique
  /// et déduit son montant du total payé pour le mois concerné.
  Future<void> cancelTransaction({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
  }) async {
    final mois = transaction['mois']?.toString() ?? '';
    final montant = (transaction['amount'] as num?)?.toDouble() ?? 0.0;

    final currentPaid = eleve.paid[mois] ?? 0;
    double newPaid = currentPaid - montant;
    if (newPaid < 0) newPaid = 0;
    eleve.paid[mois] = newPaid;

    eleve.transactions.remove(transaction);

    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().millisecondsSinceEpoch}',
      action: 'annulation',
      eleveId: eleve.id,
      eleveNomComplet: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      mois: mois,
      montantAvant: montant,
      montantApres: 0,
    ));

    await saveData();
  }

  /// Modifie le montant d'un paiement déjà enregistré. Ajuste le total
  /// payé du mois par la différence entre l'ancien et le nouveau
  /// montant (et non en le remplaçant brutalement), pour rester
  /// cohérent si d'autres paiements existent pour le même mois.
  Future<void> modifyTransactionAmount({
    required Eleve eleve,
    required Map<String, dynamic> transaction,
    required double newAmount,
  }) async {
    final mois = transaction['mois']?.toString() ?? '';
    final oldAmount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;

    final currentPaid = eleve.paid[mois] ?? 0;
    double newPaid = currentPaid - oldAmount + newAmount;
    if (newPaid < 0) newPaid = 0;
    eleve.paid[mois] = newPaid;

    transaction['amount'] = newAmount;
    transaction['modifiePar'] = 'Admin';
    transaction['modifieLe'] = DateTime.now().toString().split(' ')[0];

    adminAuditLog.add(AdminAuditLog(
      id: 'AUD${DateTime.now().millisecondsSinceEpoch}',
      action: 'modification',
      eleveId: eleve.id,
      eleveNomComplet: '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      classe: eleve.classe,
      mois: mois,
      montantAvant: oldAmount,
      montantApres: newAmount,
    ));

    await saveData();
  }

  /// Journal d'audit, du plus récent au plus ancien.
  List<AdminAuditLog> getAdminAuditLog() {
    final list = List<AdminAuditLog>.from(adminAuditLog);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // ====================================================================
  // ⚡ NOUVEAU — GESTION DES SIGNATAIRES (SIGNATURES SUR LES RAPPORTS PDF)
  // ====================================================================

  /// Liste des signataires actuellement configurés, dans l'ordre où ils
  /// ont été ajoutés (ordre d'affichage sur les rapports PDF).
  List<Signataire> getSignataires() => List<Signataire>.from(signataires);

  /// Ajoute un nouveau signataire (nom + fonction, ex: "Jean Kalala" /
  /// "Le Préfet des Études") et sauvegarde immédiatement.
  Future<Signataire> addSignataire({
    required String nom,
    required String fonction,
  }) async {
    final signataire = Signataire(
      id: 'SIG${DateTime.now().millisecondsSinceEpoch}',
      nom: nom.trim(),
      fonction: fonction.trim(),
    );
    signataires.add(signataire);
    await saveData();
    return signataire;
  }

  /// Modifie le nom et/ou la fonction d'un signataire existant.
  Future<void> updateSignataire(
      String id, {
        required String nom,
        required String fonction,
      }) async {
    for (var s in signataires) {
      if (s.id == id) {
        s.nom = nom.trim();
        s.fonction = fonction.trim();
        break;
      }
    }
    await saveData();
  }

  /// Supprime un signataire. Les rapports déjà générés (PDF déjà
  /// enregistrés sur le disque) ne sont évidemment pas affectés — seuls
  /// les PROCHAINS rapports générés ne l'incluront plus.
  Future<void> deleteSignataire(String id) async {
    signataires.removeWhere((s) => s.id == id);
    await saveData();
  }

  // ====================================================================
  // ⚡ NOUVEAU — VILLE UTILISÉE SUR LES RAPPORTS PDF
  // ====================================================================

  /// Mémorise la ville saisie dans l'écran de génération de rapport
  /// (ex: "Lubumbashi"), pour qu'elle soit pré-remplie automatiquement
  /// la prochaine fois — même principe que `lastSelectedClassFilter`.
  Future<void> setLastReportCity(String city) async {
    final trimmed = city.trim();
    lastReportCity = trimmed.isEmpty ? null : trimmed;
    await saveData();
  }

  // ====================================================================
  // ⚡ NOUVEAU — IMPRESSION DES REÇUS : ANTI-DOUBLON + FILE D'ATTENTE
  // PERSISTANTE (voir aussi les champs `printedReceiptKeys` et
  // `receiptQueue` déclarés plus haut)
  //
  // Toute la logique d'impression des reçus de paiement (frais
  // principal ET autres frais) passe désormais PAR ICI, et seulement
  // par ici — sur demande explicite de la direction, aucun écran ne
  // propose plus de bouton d'impression manuelle/réimpression : le
  // personnel s'y perdait entre plusieurs reçus imprimés à des moments
  // différents pour le même paiement. La seule impression possible est
  // donc automatique, immédiatement après un paiement, et garantie
  // UNIQUE.
  //
  // PRINCIPE GÉNÉRAL :
  //  - Chaque reçu potentiel a une clé stable et unique :
  //      • Frais principal : "principal|<eleveId>|<mois>"
  //        (un seul reçu par élève et par mois, même si ce mois a été
  //        soldé en plusieurs paiements différents)
  //      • Autre frais     : "autre_frais|<eleveId>|<autreFraisId>"
  //        (un seul reçu par élève et par type de frais additionnel —
  //        cohérent avec le fait qu'un autre frais ne peut de toute
  //        façon être payé qu'une seule fois, voir `hasPaidAutreFrais`)
  //  - Si cette clé figure déjà dans `printedReceiptKeys`, AUCUNE
  //    tentative d'impression n'est faite : le reçu a déjà été imprimé
  //    avec succès une fois, il ne le sera plus jamais, d'où que vienne
  //    la demande (paiement direct, inscription...).
  //  - Sinon, si une imprimante est configurée : on imprime
  //    immédiatement. En cas de succès, la clé est ajoutée à
  //    `printedReceiptKeys` (définitif) et sauvegardée.
  //  - Si aucune imprimante n'est configurée (ou si l'impression
  //    échoue), le reçu est mis dans `receiptQueue` avec toutes les
  //    données nécessaires pour le réimprimer plus tard, à l'IDENTIQUE,
  //    sans rien redemander à l'utilisateur.
  //  - `flushReceiptQueue()` doit être appelée à l'ouverture des écrans
  //    de paiement (Paiements des Élèves / Autres Frais / Inscription) :
  //    elle tente d'imprimer tout ce qui est encore en attente. Dès que
  //    l'imprimante redevient joignable, tous les reçus accumulés
  //    pendant qu'elle était débranchée sortent automatiquement, dans
  //    leur ordre d'ajout — même si l'application ou l'ordinateur a été
  //    complètement éteint entretemps, puisque `receiptQueue` est
  //    persistée dans le même fichier JSON que le reste (voir
  //    loadData/saveData).
  // ====================================================================

  bool isReceiptPrinted(String key) => printedReceiptKeys.contains(key);

  Future<Uint8List?> _loadLogoBytesForPrinting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasLogo = prefs.getBool('has_logo') ?? false;
      if (!hasLogo) return null;
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/school_logo.png');
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _currentPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_name') ?? '';
  }

  /// Marque une clé comme définitivement imprimée, et la retire de la
  /// file d'attente si elle s'y trouvait.
  Future<void> _markReceiptPrinted(String key) async {
    if (!printedReceiptKeys.contains(key)) {
      printedReceiptKeys.add(key);
    }
    receiptQueue.removeWhere((r) => r['key'] == key);
    await saveData();
  }

  /// Ajoute (ou met à jour si déjà en attente) un reçu dans la file
  /// d'attente. La mise à jour conserve toujours les données les PLUS
  /// RÉCENTES pour cette clé, au cas où d'autres paiements seraient
  /// intervenus pour le même mois/frais avant que l'impression n'ait
  /// pu aboutir.
  Future<void> _enqueueReceipt({
    required String key,
    required String type,
    required String eleveId,
    required Map<String, dynamic> data,
  }) async {
    final existingIndex = receiptQueue.indexWhere((r) => r['key'] == key);
    final entry = <String, dynamic>{
      'key': key,
      'type': type,
      'eleveId': eleveId,
      'data': data,
      'dateAjout': DateTime.now().toIso8601String(),
    };
    if (existingIndex != -1) {
      receiptQueue[existingIndex] = entry;
    } else {
      receiptQueue.add(entry);
    }
    await saveData();
  }

  /// ⚡ NOUVEAU — Reçu du FRAIS PRINCIPAL : imprime immédiatement si une
  /// imprimante est configurée et joignable, sinon met en file
  /// d'attente pour impression automatique ultérieure (voir
  /// `flushReceiptQueue`). Ne fait STRICTEMENT RIEN si un reçu a déjà
  /// été imprimé avec succès pour ce même élève et ce même mois.
  /// Renvoie `true` si le reçu a été imprimé À L'INSTANT, `false` s'il
  /// a été mis en attente (ou ignoré car déjà imprimé auparavant).
  Future<bool> printOrQueuePrincipalReceipt({
    required Eleve eleve,
    required String mois,
    required double montantPaye,
  }) async {
    final key = 'principal|${eleve.id}|$mois';
    if (isReceiptPrinted(key)) return false;

    final double montantRequis =
    getRequiredForMonth(mois, eleve.section, eleve.classe);
    final double totalPaye = getStudentTotalPaid(eleve);
    final double totalRequis = getStudentPending(eleve) + totalPaye;
    final double resteAPayerMoisBrut = montantRequis - (eleve.paid[mois] ?? 0);
    final double resteAPayerMois =
    resteAPayerMoisBrut < 0 ? 0.0 : resteAPayerMoisBrut;

    final data = <String, dynamic>{
      'studentName': '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      'studentId': eleve.id,
      'classe': eleve.classe,
      'section': eleve.section,
      'moisPaye': mois,
      'montantPaye': montantPaye,
      'montantRequis': montantRequis,
      'resteAPayerMois': resteAPayerMois,
      'totalDejaPayeAnnee': totalPaye,
      'totalRequis': totalRequis,
      'historiqueTransactions':
      eleve.transactions.map((t) => Map<String, dynamic>.from(t)).toList(),
    };

    final printerName = await _currentPrinterName();
    if (printerName.isNotEmpty) {
      final logoBytes = await _loadLogoBytesForPrinting();
      final bool ok = await EscPosPrinterService.printReceipt(
        printerName: printerName,
        schoolName: config.schoolName,
        currentYear: currentYear,
        studentName: data['studentName'] as String,
        studentId: data['studentId'] as String,
        classe: data['classe'] as String,
        section: data['section'] as String,
        moisPaye: mois,
        montantPaye: montantPaye,
        montantRequis: montantRequis,
        resteAPayerMois: resteAPayerMois,
        totalDejaPayeAnnee: totalPaye,
        totalRequis: totalRequis,
        historiqueTransactions: List<Map<String, dynamic>>.from(
            data['historiqueTransactions'] as List),
        logoBytes: logoBytes,
      );
      if (ok) {
        await _markReceiptPrinted(key);
        return true;
      }
    }

    await _enqueueReceipt(
      key: key,
      type: 'principal',
      eleveId: eleve.id,
      data: data,
    );
    return false;
  }

  /// ⚡ NOUVEAU — Reçu d'un AUTRE FRAIS : même principe que
  /// `printOrQueuePrincipalReceipt` ci-dessus, avec une clé unique par
  /// élève + type de frais.
  Future<bool> printOrQueueAutreFraisReceipt({
    required Eleve eleve,
    required AutreFrais frais,
  }) async {
    final key = 'autre_frais|${eleve.id}|${frais.id}';
    if (isReceiptPrinted(key)) return false;

    final data = <String, dynamic>{
      'titreFrais': frais.nom,
      'studentName': '${eleve.nom} ${eleve.postNom} ${eleve.prenom}',
      'classe': eleve.classe,
      'section': eleve.section,
      'montant': frais.montant,
    };

    final printerName = await _currentPrinterName();
    if (printerName.isNotEmpty) {
      final bool ok = await EscPosPrinterService.printAutreFraisReceipt(
        printerName: printerName,
        schoolName: config.schoolName,
        titreFrais: data['titreFrais'] as String,
        studentName: data['studentName'] as String,
        classe: data['classe'] as String,
        section: data['section'] as String,
        montant: data['montant'] as double,
      );
      if (ok) {
        await _markReceiptPrinted(key);
        return true;
      }
    }

    await _enqueueReceipt(
      key: key,
      type: 'autre_frais',
      eleveId: eleve.id,
      data: data,
    );
    return false;
  }

  /// ⚡ NOUVEAU — Tente d'imprimer tous les reçus encore en attente
  /// (voir `receiptQueue`). À appeler à l'ouverture de chaque écran de
  /// paiement : dès que l'imprimante redevient configurée/joignable,
  /// tout ce qui s'est accumulé pendant qu'elle était débranchée sort
  /// automatiquement, un par un, dans l'ordre d'ajout — y compris après
  /// un redémarrage complet de l'application ou de l'ordinateur, grâce
  /// à la persistance de `receiptQueue`. Chaque tentative revérifie
  /// `isReceiptPrinted` juste avant d'imprimer, pour ne jamais
  /// réimprimer un reçu qui aurait entretemps déjà été marqué comme
  /// imprimé (ex: restauration depuis le serveur central après
  /// impression sur un autre appareil de la même école).
  Future<int> flushReceiptQueue() async {
    if (receiptQueue.isEmpty) return 0;
    final printerName = await _currentPrinterName();
    if (printerName.isEmpty) return 0;

    final logoBytes = await _loadLogoBytesForPrinting();
    int printedCount = 0;
    final items = List<Map<String, dynamic>>.from(receiptQueue);

    for (final item in items) {
      final key = item['key']?.toString() ?? '';
      if (key.isEmpty) continue;
      if (isReceiptPrinted(key)) {
        receiptQueue.removeWhere((r) => r['key'] == key);
        continue;
      }
      final type = item['type']?.toString() ?? '';
      final data = Map<String, dynamic>.from(item['data'] as Map? ?? {});
      bool ok = false;

      if (type == 'principal') {
        ok = await EscPosPrinterService.printReceipt(
          printerName: printerName,
          schoolName: config.schoolName,
          currentYear: currentYear,
          studentName: data['studentName'] as String? ?? '',
          studentId: data['studentId'] as String? ?? '',
          classe: data['classe'] as String? ?? '',
          section: data['section'] as String? ?? '',
          moisPaye: data['moisPaye'] as String? ?? '',
          montantPaye: (data['montantPaye'] as num?)?.toDouble() ?? 0.0,
          montantRequis: (data['montantRequis'] as num?)?.toDouble() ?? 0.0,
          resteAPayerMois:
          (data['resteAPayerMois'] as num?)?.toDouble() ?? 0.0,
          totalDejaPayeAnnee:
          (data['totalDejaPayeAnnee'] as num?)?.toDouble() ?? 0.0,
          totalRequis: (data['totalRequis'] as num?)?.toDouble() ?? 0.0,
          historiqueTransactions:
          ((data['historiqueTransactions'] as List?) ?? [])
              .map((t) => Map<String, dynamic>.from(t as Map))
              .toList(),
          logoBytes: logoBytes,
        );
      } else if (type == 'autre_frais') {
        ok = await EscPosPrinterService.printAutreFraisReceipt(
          printerName: printerName,
          schoolName: config.schoolName,
          titreFrais: data['titreFrais'] as String? ?? '',
          studentName: data['studentName'] as String? ?? '',
          classe: data['classe'] as String? ?? '',
          section: data['section'] as String? ?? '',
          montant: (data['montant'] as num?)?.toDouble() ?? 0.0,
        );
      }

      if (ok) {
        await _markReceiptPrinted(key);
        printedCount++;
      }
    }

    return printedCount;
  }

  // ====================================================================
  // GÉNÉRATION D'ID LOCALE
  // ====================================================================
  String generateLocalStudentId(String nom) {
    final yearShort = currentYear.length >= 2
        ? currentYear.substring(currentYear.length - 2)
        : '26';
    final schoolLetter = config.schoolName.isNotEmpty
        ? config.schoolName[0].toUpperCase()
        : 'B';
    final nameRaw    = nom.trim().toUpperCase();
    final namePrefix = nameRaw.length >= 2
        ? nameRaw.substring(0, 2)
        : nameRaw.padRight(2, 'X');

    final allIds = history.values
        .expand((yd) => yd.eleves)
        .map((e) => e.id)
        .where((id) => id.isNotEmpty)
        .toSet();

    _localIdCounter++;
    String candidate = '$namePrefix$yearShort$schoolLetter$_localIdCounter';

    while (allIds.contains(candidate)) {
      _localIdCounter++;
      candidate = '$namePrefix$yearShort$schoolLetter$_localIdCounter';
    }
    return candidate;
  }

  Future<String> generateUniqueStudentId(
      String nom, String schoolCodeForServer) async {
    if (nom.trim().isEmpty) {
      throw Exception("Le nom est requis pour générer un identifiant.");
    }
    return generateLocalStudentId(nom);
  }

  void _applyIdCorrections(Map<String, dynamic> corrections) {
    if (corrections.isEmpty) return;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (corrections.containsKey(eleve.id)) {
          eleve.id = corrections[eleve.id] as String;
        }
      }
    }
  }

  // ====================================================================
  // ⚡ NOUVEAU — RECHERCHE D'UN ÉLÈVE PAR NOM COMPLET
  //
  // Utile lorsqu'on ne dispose que du nom/post-nom/prénom d'un élève —
  // typiquement les paiements en attente reçus du serveur central côté
  // Dashboard Admin, qui ne portent pas toujours l'ID local de l'élève
  // — et qu'on a besoin de retrouver sa fiche complète (ID, classe,
  // section exacts) pour, par exemple, imprimer un reçu correct après
  // validation. Même logique de clé (nom_postnom_prenom en minuscules)
  // que celle utilisée dans `mergeRestoredData` pour fusionner les
  // données restaurées du serveur, afin de rester cohérent avec le
  // reste de l'application.
  //
  // Cherche d'abord dans `currentData` (année en cours) par défaut, ou
  // dans l'année précisée si fournie. Renvoie `null` si aucun élève ne
  // correspond (ex: élève supprimé entretemps).
  // ====================================================================
  Eleve? findStudentByFullName(
      String nom, String postNom, String prenom, [String? year]) {
    final targetKey =
        '${nom.trim().toLowerCase()}_${postNom.trim().toLowerCase()}_${prenom.trim().toLowerCase()}';
    final list = year != null
        ? (history[year]?.eleves ?? currentData.eleves)
        : currentData.eleves;
    for (final e in list) {
      final key =
          '${e.nom.trim().toLowerCase()}_${e.postNom.trim().toLowerCase()}_${e.prenom.trim().toLowerCase()}';
      if (key == targetKey) return e;
    }
    return null;
  }

  // ====================================================================
  // ⚡ NOUVEAU — UNICITÉ STRICTE DU TRIPLET NOM + POST-NOM + PRÉNOM
  //
  // Consigne explicite de la direction : deux élèves peuvent très bien
  // partager DEUX de ces trois informations (même nom et même
  // post-nom, ou même nom et même prénom, ou même post-nom et même
  // prénom...), mais JAMAIS les TROIS en même temps. Ce triplet complet
  // doit rester unique pour toute l'école (année en cours), afin
  // d'éliminer tout risque de confusion entre deux élèves strictement
  // homonymes — l'utilisateur est alors obligé de corriger au moins un
  // des trois champs (typiquement le prénom) avant de pouvoir
  // continuer.
  //
  // Comparaison insensible à la casse et aux espaces superflus, sur le
  // même principe que `findStudentByFullName` ci-dessus.
  //
  // Volontairement limité à `currentData.eleves` (l'année scolaire en
  // cours) : c'est la seule liste où deux élèves peuvent réellement se
  // côtoyer au quotidien (mêmes listes, mêmes paiements) ; un élève
  // promu d'une année à l'autre conserve de toute façon son ID (voir
  // `promoteStudents`), ce n'est donc jamais une "nouvelle" inscription
  // à valider ici.
  //
  // `excludeId` permet d'exclure l'élève en cours de modification
  // lorsqu'on vérifie après une MODIFICATION (et non une création) —
  // sinon un élève entrerait toujours en conflit avec lui-même.
  // ====================================================================
  Eleve? findDuplicateFullName({
    required String nom,
    required String postNom,
    required String prenom,
    String? excludeId,
  }) {
    final nomN = nom.trim().toLowerCase();
    final postNomN = postNom.trim().toLowerCase();
    final prenomN = prenom.trim().toLowerCase();
    for (final e in currentData.eleves) {
      if (excludeId != null && e.id == excludeId) continue;
      if (e.nom.trim().toLowerCase() == nomN &&
          e.postNom.trim().toLowerCase() == postNomN &&
          e.prenom.trim().toLowerCase() == prenomN) {
        return e;
      }
    }
    return null;
  }

  // ====================================================================
  // ⚡ NOUVEAU — EXPORT "SNAPSHOT" (utilisé par le serveur local pour
  // répondre à GET /restore exactement comme le fait le serveur central,
  // sans passer par le réseau puisque c'est la même instance qui sert
  // ses propres données)
  // ====================================================================
  Map<String, dynamic> exportSnapshotForClients() {
    return {
      'config': config.toJson(),
      'currentYear': currentYear,
      'localIdCounter': _localIdCounter,
      'lastSelectedClassFilter': lastSelectedClassFilter,
      'lastSelectedSectionFilter': lastSelectedSectionFilter,
      'history': history.map((key, value) => MapEntry(key, value.toJson())),
      'depensesByYear': depensesByYear.map(
            (key, value) =>
            MapEntry(key, value.map((d) => d.toJson()).toList()),
      ),
      'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
      'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
            (key, value) =>
            MapEntry(key, value.map((p) => p.toJson()).toList()),
      ),
      'hiddenCodeHash': hiddenCodeHash,
      'hiddenCodeSalt': hiddenCodeSalt,
      'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
      // ⚡ NOUVEAU
      'signataires': signataires.map((s) => s.toJson()).toList(),
      // ⚡ NOUVEAU — reçus déjà imprimés + file d'attente (anti-double
      // impression, voir plus haut).
      'printedReceiptKeys': printedReceiptKeys,
      'receiptQueue': receiptQueue,
      // Le serveur local ne protège pas /restore par mot de passe (les
      // sous-utilisateurs n'en fournissent jamais un) — ce champ reste
      // donc toujours null ici, contrairement à backupToServer qui
      // l'envoie au serveur central pour la restauration protégée.
      'backup_password': null,
    };
  }

  // ====================================================================
  // ⚡ NOUVEAU — CLÉS D'ACCÈS LOCALES (générées et vérifiées sans
  // internet, par le petit serveur HTTP local — voir
  // local_server_service.dart)
  // ====================================================================

  /// Génère une nouvelle clé d'accès locale et la sauvegarde
  /// immédiatement. Format : "LOC-<CodeEcole>-<Type>-<8 caractères
  /// aléatoires>" — le préfixe "LOC-" permet de reconnaître au premier
  /// coup d'œil une clé générée en local plutôt que par le serveur
  /// central, ce qui aide au diagnostic si jamais une clé ne fonctionne
  /// pas comme attendu.
  Future<Map<String, dynamic>> generateLocalKey({
    required List<String> sections,
    required String type,
    String? classe,
  }) async {
    final rand = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final suffix =
    List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    final prefix =
    (schoolCode != null && schoolCode!.isNotEmpty) ? schoolCode! : 'ECOLE';
    final key = 'LOC-$prefix-$type-$suffix';

    final entry = <String, dynamic>{
      'key': key,
      'type': type,
      'sections': sections,
      'classe': classe,
      'createdAt': DateTime.now().toIso8601String(),
    };
    localAccessKeys.add(entry);
    await saveData();
    return entry;
  }

  /// Vérifie une clé locale saisie par un sous-utilisateur. Renvoie
  /// l'entrée complète si elle existe, sinon `null`. Les clés locales
  /// n'expirent jamais automatiquement (contrairement à la session
  /// client, gérée côté app sous-utilisateur avec sa propre durée de
  /// 24h) — elles restent valables tant que l'admin ne les révoque pas
  /// manuellement.
  Map<String, dynamic>? verifyLocalKey(String key) {
    for (final entry in localAccessKeys) {
      if (entry['key'] == key) return entry;
    }
    return null;
  }

  /// Révoque (supprime) une clé locale — ex: un agent qui ne devrait
  /// plus avoir accès.
  Future<void> revokeLocalKey(String key) async {
    localAccessKeys.removeWhere((e) => e['key'] == key);
    await saveData();
  }

  // ====================================================================
  // ⚡ NOUVEAU — FILE D'ATTENTE LOCALE : PAIEMENTS DE FRAIS MENSUELS
  // ====================================================================

  /// Enregistre un paiement envoyé par un sous-utilisateur connecté en
  /// local, en attente de validation admin. On capture le nom/section/
  /// classe de l'élève AU MOMENT de l'envoi (comme le fait le serveur
  /// central), pour que la liste "en attente" reste lisible même si
  /// l'élève venait à être modifié entretemps.
  Future<Map<String, dynamic>> addLocalPendingPayment({
    required String eleveId,
    required String mois,
    required double amount,
  }) async {
    Eleve? eleve;
    for (final e in currentData.eleves) {
      if (e.id == eleveId) {
        eleve = e;
        break;
      }
    }
    final entry = <String, dynamic>{
      'id': 'LPP${DateTime.now().millisecondsSinceEpoch}',
      'eleve_id': eleveId,
      'nom': eleve?.nom ?? '',
      'postNom': eleve?.postNom ?? '',
      'prenom': eleve?.prenom ?? '',
      'section': eleve?.section ?? '',
      'classe': eleve?.classe ?? '',
      'mois': mois,
      'amount': amount,
      'date': DateTime.now().toString().split(' ')[0],
    };
    localPendingPayments.add(entry);
    await saveData();
    return entry;
  }

  /// Valide un lot de paiements en attente : applique chacun d'eux sur
  /// la fiche de l'élève concerné (exactement comme `handlePayment`),
  /// puis retire l'entrée de la file d'attente. Renvoie le nombre de
  /// paiements effectivement appliqués (un paiement est ignoré s'il ne
  /// correspond plus à aucun élève connu — ex: élève supprimé
  /// entretemps).
  Future<int> validateLocalPendingPayments(List<String> ids) async {
    int count = 0;
    final toValidate =
    localPendingPayments.where((p) => ids.contains(p['id'])).toList();
    for (final p in toValidate) {
      Eleve? eleve;
      for (final e in currentData.eleves) {
        if (e.id == p['eleve_id']) {
          eleve = e;
          break;
        }
      }
      eleve ??= findStudentByFullName(
        (p['nom'] ?? '').toString(),
        (p['postNom'] ?? '').toString(),
        (p['prenom'] ?? '').toString(),
      );
      if (eleve != null) {
        handlePayment(
            eleve, p['mois'].toString(), (p['amount'] as num).toDouble());
        count++;
      }
    }
    localPendingPayments.removeWhere((p) => ids.contains(p['id']));
    await saveData();
    return count;
  }

  // ====================================================================
  // ⚡ NOUVEAU — FILE D'ATTENTE LOCALE : INSCRIPTIONS
  // ====================================================================

  /// Enregistre une inscription envoyée en local, en attente de
  /// validation. ⚠️ Comme documenté déjà côté écran sous-utilisateur
  /// (limitation identique côté serveur central) : seuls nom, post-nom,
  /// prénom, section et classe sont conservés jusqu'à la création de
  /// l'élève — les champs additionnels (père/mère/adresse/date de
  /// naissance) restent disponibles dans la fiche "en attente" pour
  /// consultation par l'admin, mais ne sont pas reportés sur la fiche
  /// élève finale (le modèle `Eleve` ne les stocke pas).
  Future<Map<String, dynamic>> addLocalPendingRegistration(
      Map<String, dynamic> data) async {
    final entry = <String, dynamic>{
      'id': 'LPR${DateTime.now().millisecondsSinceEpoch}',
      ...data,
    };
    localPendingRegistrations.add(entry);
    await saveData();
    return entry;
  }

  // ⚡ CORRIGÉ — refuse désormais toute inscription en attente qui
  // créerait un doublon strict (nom + post-nom + prénom identiques à un
  // élève déjà existant) : voir `findDuplicateFullName`. Une telle
  // inscription reste dans la file d'attente (elle n'est ni créée, ni
  // supprimée) pour que l'admin la corrige manuellement — un doublon
  // homonyme ne doit jamais être créé silencieusement.
  Future<int> validateLocalPendingRegistrations(List<String> ids) async {
    int count = 0;
    final toValidate = localPendingRegistrations
        .where((r) => ids.contains(r['id']))
        .toList();
    final processedIds = <String>[];
    for (final r in toValidate) {
      final nom = (r['nom'] ?? '').toString().trim();
      final section = (r['section'] ?? '').toString().trim();
      final classe = (r['classe'] ?? '').toString().trim();
      final postNom = (r['postNom'] ?? '').toString().trim();
      final prenom = (r['prenom'] ?? '').toString().trim();
      if (nom.isEmpty || section.isEmpty || classe.isEmpty) {
        processedIds.add(r['id'] as String);
        continue;
      }

      // ⚡ NOUVEAU — refus des doublons stricts (voir
      // `findDuplicateFullName`) : l'entrée reste en attente, elle
      // n'est ni créée ni retirée de la file.
      if (findDuplicateFullName(nom: nom, postNom: postNom, prenom: prenom) !=
          null) {
        continue;
      }

      final id = generateLocalStudentId(nom);
      currentData.eleves.add(Eleve(
        id: id,
        nom: nom,
        postNom: postNom,
        prenom: prenom,
        classe: classe,
        section: section,
      ));
      count++;
      processedIds.add(r['id'] as String);
    }
    localPendingRegistrations
        .removeWhere((r) => processedIds.contains(r['id']));
    await saveData();
    return count;
  }

  // ====================================================================
  // ⚡ NOUVEAU — FILE D'ATTENTE LOCALE : AUTRES FRAIS
  // ====================================================================

  Future<Map<String, dynamic>> addLocalPendingAutreFraisPayment({
    required String eleveId,
    required String autreFraisId,
    required double montant,
    String enregistrePar = 'Agent',
  }) async {
    Eleve? eleve;
    for (final e in currentData.eleves) {
      if (e.id == eleveId) {
        eleve = e;
        break;
      }
    }
    AutreFrais? frais;
    for (final f in autresFrais) {
      if (f.id == autreFraisId) {
        frais = f;
        break;
      }
    }
    final entry = <String, dynamic>{
      'id': 'LPAF${DateTime.now().millisecondsSinceEpoch}',
      'eleveId': eleveId,
      'nom': eleve?.nom ?? '',
      'postNom': eleve?.postNom ?? '',
      'prenom': eleve?.prenom ?? '',
      'autreFraisId': autreFraisId,
      'autreFraisNom': frais?.nom ?? '',
      'montant': montant,
      'enregistrePar': enregistrePar,
    };
    localPendingAutresFraisPayments.add(entry);
    await saveData();
    return entry;
  }

  Future<int> validateLocalPendingAutresFraisPayments(
      List<String> ids) async {
    int count = 0;
    final toValidate = localPendingAutresFraisPayments
        .where((p) => ids.contains(p['id']))
        .toList();
    for (final p in toValidate) {
      Eleve? eleve;
      for (final e in currentData.eleves) {
        if (e.id == p['eleveId']) {
          eleve = e;
          break;
        }
      }
      eleve ??= findStudentByFullName(
        (p['nom'] ?? '').toString(),
        (p['postNom'] ?? '').toString(),
        (p['prenom'] ?? '').toString(),
      );
      AutreFrais? frais;
      for (final f in autresFrais) {
        if (f.id == p['autreFraisId']) {
          frais = f;
          break;
        }
      }
      if (eleve != null && frais != null) {
        await payAutreFrais(
          frais: frais,
          eleve: eleve,
          enregistrePar: (p['enregistrePar'] ?? 'Agent').toString(),
        );
        count++;
      }
    }
    localPendingAutresFraisPayments.removeWhere((p) => ids.contains(p['id']));
    await saveData();
    return count;
  }

  // ====================================================================
  // ⚡ NOUVEAU — DISCIPLINE EN LOCAL (présence + journal de
  // communications)
  // ====================================================================

  Future<void> recordLocalAbsences({
    required String classe,
    required String section,
    required String date,
    required List<String> absentIds,
    String recordedBy = 'Direction',
  }) async {
    localAttendance['$classe|$date'] = absentIds;
    localCommunicationsLog.add({
      'type': 'absences',
      'classe': classe,
      'section': section,
      'date': date,
      'absent_ids': absentIds,
      'recordedBy': recordedBy,
      'loggedAt': DateTime.now().toIso8601String(),
      'delivered': false,
    });
    await saveData();
  }

  List<String> getLocalAttendance(String classe, String date) {
    return localAttendance['$classe|$date'] ?? [];
  }

  /// Journalise une convocation ou un communiqué envoyé en mode local.
  /// Ne notifie PAS réellement les parents (aucun canal disponible hors
  /// ligne) — l'entrée reste marquée `delivered: false` pour que l'admin
  /// sache qu'un renvoi sera nécessaire une fois de retour en ligne.
  Future<void> logLocalCommunication(Map<String, dynamic> entry) async {
    localCommunicationsLog.add({
      ...entry,
      'loggedAt': DateTime.now().toIso8601String(),
      'delivered': false,
    });
    await saveData();
  }

  // ====================================================================
  // GESTION DES CLASSES & SOUS-CLASSES
  // ====================================================================
  String _classeKey(String section, String classeNumero) =>
      "$section|$classeNumero";

  List<String> getClassesForSection(String section) {
    if (config.classesBySection.containsKey(section) &&
        config.classesBySection[section]!.isNotEmpty) {
      return config.classesBySection[section]!;
    }
    final autoClasses = SchoolConfig.defaultClassesForSectionName(section);
    if (autoClasses.isNotEmpty) {
      config.classesBySection[section] = List<String>.from(autoClasses);
    }
    return config.classesBySection[section] ?? [];
  }

  Future<void> addClasseNumero(String section, String classeNumero) async {
    final trimmed = classeNumero.trim();
    if (trimmed.isEmpty) return;
    final list = config.classesBySection.putIfAbsent(section, () => []);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await saveData();
    }
  }

  // ====================================================================
  // ⚡ NOUVEAU — RENOMMAGE / SUPPRESSION D'UN NUMÉRO DE CLASSE
  //
  // Sert à corriger une faute de frappe (ex: "6eme" écrit "6eem") sans
  // avoir à recréer la classe et réaffecter tous les élèves un par un.
  // Le renommage met à jour TOUT ce qui référence ce numéro de classe :
  // - la liste des classes de la section (config.classesBySection)
  // - les sous-classes rattachées (config.subClassesByClasse)
  // - les frais spécifiques à cette classe (config.feesByClasse)
  // - les exceptions mensuelles de cette classe
  //   (config.monthlyExceptionsByClasse)
  // - CHAQUE ÉLÈVE, dans l'année en cours ET dans tout l'historique des
  //   années précédentes, dont la classe correspond à cet ancien numéro
  //   (en conservant sa sous-classe si elle en a une, ex: "6eme A"
  //   devient "6A A" si on renomme "6eme" en "6A").
  //
  // Comme `currentData` est la MÊME référence que `history[currentYear]`
  // (voir loadData), il suffit de parcourir `history.values` pour que
  // l'année en cours soit également mise à jour — et donc que le
  // changement soit immédiatement visible sur tous les écrans qui lisent
  // `currentData` (accueil, listes, PDF, reçus...).
  // ====================================================================
  Future<void> renameClasseNumero(
      String section, String oldNumero, String newNumero) async {
    final trimmedNew = newNumero.trim();
    if (trimmedNew.isEmpty || trimmedNew == oldNumero) return;

    // 1. Liste des numéros de classe de la section.
    final list = config.classesBySection[section];
    if (list != null) {
      final idx = list.indexOf(oldNumero);
      if (idx != -1) {
        if (list.contains(trimmedNew)) {
          // Le nouveau nom existe déjà dans la liste : on fusionne en
          // retirant simplement l'ancien pour éviter un doublon.
          list.removeAt(idx);
        } else {
          list[idx] = trimmedNew;
        }
      }
    }

    final oldKey = _classeKey(section, oldNumero);
    final newKey = _classeKey(section, trimmedNew);

    // 2. Sous-classes rattachées à ce numéro de classe.
    if (config.subClassesByClasse.containsKey(oldKey)) {
      final subs = config.subClassesByClasse.remove(oldKey)!;
      if (config.subClassesByClasse.containsKey(newKey)) {
        for (var s in subs) {
          if (!config.subClassesByClasse[newKey]!.contains(s)) {
            config.subClassesByClasse[newKey]!.add(s);
          }
        }
      } else {
        config.subClassesByClasse[newKey] = subs;
      }
    }

    // 3. Frais spécifiques déjà définis pour cette classe.
    if (config.feesByClasse.containsKey(oldKey)) {
      final fee = config.feesByClasse.remove(oldKey)!;
      config.feesByClasse[newKey] = fee;
    }

    // 4. Exceptions mensuelles déjà définies pour cette classe.
    if (config.monthlyExceptionsByClasse.containsKey(oldKey)) {
      final exc = config.monthlyExceptionsByClasse.remove(oldKey)!;
      config.monthlyExceptionsByClasse[newKey] = exc;
    }

    // 5. Tous les élèves (année en cours + historique complet) dont le
    // numéro de classe correspond à l'ancien nom, en gardant leur
    // éventuelle sous-classe.
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.section != section) continue;
        final numero = classeNumeroFromFullClasse(eleve.classe);
        if (numero == oldNumero) {
          final sub = subClasseFromFullClasse(eleve.classe);
          eleve.classe = buildFullClasseName(trimmedNew, sub);
        }
      }
    }

    // 6. Filtres mémorisés (écran d'accueil) qui pointaient sur
    // l'ancien nom.
    if (lastSelectedClassFilter == oldNumero) {
      lastSelectedClassFilter = trimmedNew;
    }

    await saveData();
  }

  /// Supprime un numéro de classe d'une section.
  ///
  /// Si des élèves (année en cours OU historique) sont encore inscrits
  /// dans cette classe et que `force` est faux, la suppression est
  /// refusée et le nombre d'élèves concernés est renvoyé, afin que
  /// l'écran puisse demander une confirmation explicite avant de
  /// continuer (les élèves ne sont jamais supprimés ni modifiés
  /// silencieusement).
  ///
  /// Avec `force: true`, la classe est retirée de la configuration
  /// (elle n'apparaîtra plus dans les listes de choix) ; les élèves déjà
  /// affectés à cette classe conservent ce nom jusqu'à ce qu'ils soient
  /// réaffectés manuellement (via le renommage ou une modification de
  /// leur fiche).
  Future<Map<String, dynamic>> deleteClasseNumero(
      String section,
      String numero, {
        bool force = false,
      }) async {
    int studentCount = 0;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.section == section &&
            classeNumeroFromFullClasse(eleve.classe) == numero) {
          studentCount++;
        }
      }
    }

    if (studentCount > 0 && !force) {
      return {'success': false, 'studentCount': studentCount};
    }

    config.classesBySection[section]?.remove(numero);
    final key = _classeKey(section, numero);
    config.subClassesByClasse.remove(key);
    config.feesByClasse.remove(key);
    config.monthlyExceptionsByClasse.remove(key);

    if (lastSelectedClassFilter == numero) {
      lastSelectedClassFilter = null;
    }

    await saveData();
    return {'success': true, 'studentCount': studentCount};
  }

  List<String> getSubClassesFor(String section, String classeNumero) {
    return config.subClassesByClasse[_classeKey(section, classeNumero)] ?? [];
  }

  Future<void> addSubClasse(
      String section, String classeNumero, String subClasse) async {
    final trimmed = subClasse.trim();
    if (trimmed.isEmpty) return;
    final key  = _classeKey(section, classeNumero);
    final list = config.subClassesByClasse.putIfAbsent(key, () => []);
    if (!list.contains(trimmed)) {
      list.add(trimmed);
      await saveData();
    }
  }

  Future<void> removeSubClasse(
      String section, String classeNumero, String subClasse) async {
    final key = _classeKey(section, classeNumero);
    config.subClassesByClasse[key]?.remove(subClasse);
    await saveData();
  }

  String buildFullClasseName(String classeNumero, String? subClasse) {
    if (subClasse == null || subClasse.trim().isEmpty) return classeNumero;
    return "$classeNumero ${subClasse.trim()}";
  }

  String classeNumeroFromFullClasse(String classeComplete) {
    final trimmed = classeComplete.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.split(' ').first;
  }

  String? subClasseFromFullClasse(String classeComplete) {
    final parts = classeComplete.trim().split(' ');
    if (parts.length > 1) {
      final rest = parts.sublist(1).join(' ').trim();
      return rest.isEmpty ? null : rest;
    }
    return null;
  }

  List<String> getAllDisplayClassesForSection(String section) {
    final result = <String>[];
    for (var numero in getClassesForSection(section)) {
      final subs = getSubClassesFor(section, numero);
      if (subs.isEmpty) {
        result.add(numero);
      } else {
        for (var sub in subs) {
          result.add(buildFullClasseName(numero, sub));
        }
      }
    }
    return result;
  }

  List<String> getAllDisplayClasses() {
    final result = <String>{};
    for (var section in config.sections) {
      result.addAll(getAllDisplayClassesForSection(section));
    }
    return result.toList();
  }

  // ====================================================================
  // PASSATION VERS LA CLASSE/ANNÉE SUPÉRIEURE
  // ====================================================================
  String? getNextClasseNumero(String section, String classeNumero) {
    final list = getClassesForSection(section);
    final idx  = list.indexOf(classeNumero);
    if (idx == -1 || idx == list.length - 1) return null;
    return list[idx + 1];
  }

  String computePromotedClasse(Eleve eleve) {
    final numero     = classeNumeroFromFullClasse(eleve.classe);
    final subClasse  = subClasseFromFullClasse(eleve.classe);
    final nextNumero = getNextClasseNumero(eleve.section, numero);
    if (nextNumero == null) return eleve.classe;
    return buildFullClasseName(nextNumero, subClasse);
  }

  Future<Map<String, int>> promoteStudents({
    required List<Eleve> studentsToProcess,
    required Map<String, bool> passToNextYear,
    required Map<String, bool> monterClasse,
    required String targetYear,
  }) async {
    int promoted    = 0;
    int abandoned   = 0;
    int redoublants = 0;

    if (!history.containsKey(targetYear)) {
      history[targetYear] = SchoolYearData(eleves: []);
    }
    final targetData  = history[targetYear]!;
    final existingIds = targetData.eleves.map((e) => e.id).toSet();

    for (var eleve in studentsToProcess) {
      final shouldPass = passToNextYear[eleve.id] ?? true;
      if (!shouldPass) {
        abandoned++;
        continue;
      }
      final shouldMonter = monterClasse[eleve.id] ?? true;
      String newClasse;
      if (shouldMonter) {
        final promotedClasse = computePromotedClasse(eleve);
        if (promotedClasse == eleve.classe) redoublants++;
        newClasse = promotedClasse;
      } else {
        newClasse = eleve.classe;
        redoublants++;
      }

      if (existingIds.contains(eleve.id)) {
        final existing =
        targetData.eleves.firstWhere((e) => e.id == eleve.id);
        existing.classe  = newClasse;
        existing.section = eleve.section;
      } else {
        targetData.eleves.add(Eleve(
          id:      eleve.id,
          nom:     eleve.nom,
          postNom: eleve.postNom,
          prenom:  eleve.prenom,
          classe:  newClasse,
          section: eleve.section,
        ));
        existingIds.add(eleve.id);
      }
      promoted++;
    }

    await saveData();
    return {
      'promoted':    promoted,
      'abandoned':   abandoned,
      'redoublants': redoublants,
    };
  }

  // ====================================================================
  // FILTRES
  // ====================================================================
  List<Eleve> getStudentsBySection(String section) =>
      currentData.eleves.where((e) => e.section == section).toList();

  List<Eleve> getStudentsByClass(String classe) =>
      currentData.eleves.where((e) => e.classe == classe).toList();

  List<Eleve> getStudentsBySectionAndClass(
      String? section, String? classe) {
    return currentData.eleves.where((e) {
      final matchSection = section == null || e.section == section;
      final matchClass   = classe  == null || e.classe  == classe;
      return matchSection && matchClass;
    }).toList();
  }

  // ====================================================================
  // CALCULS FINANCIERS
  // ====================================================================
  double getRequiredForMonth(String mois, String section,
      [String? classe]) {
    if (classe != null && classe.trim().isNotEmpty) {
      final classeNumero = classeNumeroFromFullClasse(classe);
      final key          = _classeKey(section, classeNumero);
      final classExc     = config.monthlyExceptionsByClasse[key];
      if (classExc != null && classExc.containsKey(mois)) {
        return classExc[mois]!;
      }
      if (config.feesByClasse.containsKey(key)) {
        return config.feesByClasse[key]!;
      }
    }
    final exc = config.monthlyExceptionsBySection[section];
    if (exc != null && exc.containsKey(mois)) return exc[mois]!;
    return config.feesBySection[section] ?? 35000;
  }

  Map<String, double> getTotalBySection() {
    final totals = <String, double>{};
    for (var e in currentData.eleves) {
      totals[e.section] = (totals[e.section] ?? 0) + getStudentTotalPaid(e);
    }
    return totals;
  }

  Map<String, double> getTotalByClass() {
    final totals = <String, double>{};
    for (var e in currentData.eleves) {
      final key = "${e.section} - ${e.classe}";
      totals[key] = (totals[key] ?? 0) + getStudentTotalPaid(e);
    }
    return totals;
  }

  double getYearTotalCollected() =>
      months.fold(
          0.0,
              (sum, m) =>
          sum +
              currentData.eleves.fold(
                  0.0, (s, e) => s + (e.paid[m] ?? 0)));

  // ⚡ CORRIGÉ — utilisait auparavant `months[DateTime.now().month - 1]`
  // en supposant à tort que `months` suit l'ordre calendaire. Utilise
  // maintenant `_schoolMonthIndexForToday()`, qui fait la conversion
  // correcte vers l'ordre "année scolaire" de `months`, et renvoie 0.0
  // pendant les grandes vacances (Juillet/Août), où il n'y a pas de
  // "mois courant" au sens de l'année scolaire.
  double getCurrentMonthTotalCollected() {
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return 0.0;
    final moisCourant = months[idx];
    return currentData.eleves
        .fold(0.0, (sum, e) => sum + (e.paid[moisCourant] ?? 0));
  }

  List<Eleve> getPaidStudentsToday() {
    final today = DateTime.now().toString().split(' ')[0];
    return currentData.eleves
        .where((e) => e.transactions.any((t) => t['date'] == today))
        .toList();
  }

  // ⚡ CORRIGÉ — même bug que `getCurrentMonthTotalCollected` :
  // `months[DateTime.now().month - 1]` pointait sur le mauvais mois
  // (ex: "Avril" en Août), et pouvait même planter en Novembre/Décembre
  // (index hors limites du tableau, qui n'a que 10 éléments). Utilise
  // maintenant le bon mapping via `_schoolMonthIndexForToday()`.
  List<Eleve> getPaidStudentsThisMonth() {
    final idx = _schoolMonthIndexForToday();
    if (idx < 0 || idx >= months.length) return [];
    final moisCourant = months[idx];
    return currentData.eleves
        .where((e) =>
    e.paid.containsKey(moisCourant) &&
        e.paid[moisCourant]! > 0)
        .toList();
  }

  Map<String, double> calculateAdminDistribution(double totalAmount) {
    final distribution = <String, double>{};
    for (var admin in config.administrations) {
      distribution[admin.nom] = totalAmount * (admin.pourcentage / 100);
    }
    return distribution;
  }

  // ====================================================================
  // ⚡ NOUVEAU — GESTION DES DÉPENSES (SORTIES DE CAISSE)
  // Le principe retenu : une dépense enregistrée diminue directement le
  // solde disponible en caisse pour l'année scolaire en cours. Comme il
  // n'existe pas de règle officielle unique documentée pour ce cas
  // précis, la répartition entre administrations est calculée sur le
  // SOLDE NET (total collecté - dépenses), puisqu'on ne peut pas
  // redistribuer un montant déjà sorti de la caisse. Ce comportement
  // est isolé ici et facile à modifier si votre pratique réelle diffère.
  // ====================================================================

  /// Liste des dépenses de l'année donnée (par défaut l'année courante),
  /// triée de la plus récente à la plus ancienne.
  List<Depense> getDepensesForYear([String? year]) {
    final y = year ?? currentYear;
    final list = List<Depense>.from(depensesByYear[y] ?? []);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Total des sorties de caisse pour l'année donnée.
  double getTotalDepenses([String? year]) {
    final y = year ?? currentYear;
    return (depensesByYear[y] ?? [])
        .fold(0.0, (sum, d) => sum + d.montant);
  }

  /// Solde net en caisse = total collecté - total des dépenses,
  /// pour l'année donnée (par défaut l'année courante).
  double getSoldeNetActuel([String? year]) {
    final y = year ?? currentYear;
    final totalCollecte = (y == currentYear)
        ? getYearTotalCollected()
        : months.fold<double>(
      0.0,
          (sum, m) =>
      sum +
          (history[y]?.eleves.fold<double>(
              0.0, (s, e) => s + (e.paid[m] ?? 0)) ??
              0.0),
    );
    return totalCollecte - getTotalDepenses(y);
  }

  /// Enregistre une nouvelle sortie de caisse (motif + montant), horodatée
  /// automatiquement, et sauvegarde immédiatement.
  Future<Depense> addDepense({
    required String motif,
    required double montant,
    String enregistrePar = 'Direction',
  }) async {
    final depense = Depense(
      id: 'DEP${DateTime.now().millisecondsSinceEpoch}',
      motif: motif.trim(),
      montant: montant,
      date: DateTime.now(),
      enregistrePar: enregistrePar,
    );
    depensesByYear.putIfAbsent(currentYear, () => []).add(depense);
    await saveData();
    return depense;
  }

  /// Supprime une dépense (ex: erreur de saisie) et sauvegarde.
  Future<void> deleteDepense(String id, [String? year]) async {
    final y = year ?? currentYear;
    depensesByYear[y]?.removeWhere((d) => d.id == id);
    await saveData();
  }

  /// ⚡ NOUVEAU — Vide complètement l'historique des dépenses d'une année
  /// donnée (par défaut l'année courante). Action irréversible, protégée
  /// côté écran par le mot de passe de sauvegarde (comme dans les
  /// Paramètres).
  Future<void> clearDepensesForYear([String? year]) async {
    final y = year ?? currentYear;
    depensesByYear[y] = [];
    await saveData();
  }

  // ====================================================================
  // ⚡ NOUVEAU — GESTION DES AUTRES FRAIS DE PAIEMENT (ÉPHÉMÈRES)
  // Frais ponctuels propres à chaque école (ex: Frais de l'État, Frais
  // d'Aide...), différents du frais mensuel principal : l'utilisateur
  // peut les ajouter ou les supprimer librement à tout moment depuis les
  // Paramètres.
  // ====================================================================

  /// Liste des frais additionnels actuellement définis, triée par nom.
  List<AutreFrais> getAutresFrais() {
    final list = List<AutreFrais>.from(autresFrais);
    list.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return list;
  }

  /// Crée un nouveau frais additionnel et sauvegarde immédiatement.
  Future<AutreFrais> addAutreFrais({
    required String nom,
    required double montant,
    String scope = 'all',
    String? section,
    String? classe,
  }) async {
    final frais = AutreFrais(
      id: 'AF${DateTime.now().millisecondsSinceEpoch}',
      nom: nom.trim(),
      montant: montant,
      scope: scope,
      section: scope == 'all' ? null : section,
      classe: scope == 'classe' ? classe : null,
    );
    autresFrais.add(frais);
    await saveData();
    return frais;
  }

  /// Supprime un frais additionnel. Les paiements déjà enregistrés pour
  /// ce frais restent dans l'historique (avec le nom du frais tel qu'il
  /// était au moment du paiement), mais il ne sera plus proposé pour de
  /// nouveaux paiements.
  Future<void> deleteAutreFrais(String id) async {
    autresFrais.removeWhere((f) => f.id == id);
    await saveData();
  }

  /// Détermine si un frais additionnel donné s'applique à un élève donné,
  /// selon son périmètre (toute l'école / une section / une classe).
  bool autreFraisAppliesToStudent(AutreFrais frais, Eleve eleve) {
    switch (frais.scope) {
      case 'section':
        return frais.section != null && eleve.section == frais.section;
      case 'classe':
        return frais.classe != null && eleve.classe == frais.classe;
      case 'all':
      default:
        return true;
    }
  }

  /// Liste des élèves concernés par un frais additionnel donné, triée
  /// par classe puis par nom.
  List<Eleve> getEligibleStudentsForAutreFrais(AutreFrais frais) {
    final students = currentData.eleves
        .where((e) => autreFraisAppliesToStudent(frais, e))
        .toList();
    students.sort((a, b) {
      final c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      return a.nom.compareTo(b.nom);
    });
    return students;
  }

  /// Vérifie si un élève a déjà payé un frais additionnel donné, pour
  /// l'année donnée (par défaut l'année courante).
  bool hasPaidAutreFrais(Eleve eleve, AutreFrais frais, [String? year]) {
    final y = year ?? currentYear;
    return (autresFraisPaiementsByYear[y] ?? []).any(
            (p) => p.autreFraisId == frais.id && p.eleveId == eleve.id);
  }

  /// Enregistre le paiement d'un frais additionnel par un élève,
  /// horodaté automatiquement, et sauvegarde immédiatement.
  Future<AutreFraisPaiement> payAutreFrais({
    required AutreFrais frais,
    required Eleve eleve,
    String enregistrePar = 'Direction',
  }) async {
    final paiement = AutreFraisPaiement(
      id: 'AFP${DateTime.now().millisecondsSinceEpoch}',
      autreFraisId: frais.id,
      autreFraisNom: frais.nom,
      eleveId: eleve.id,
      montant: frais.montant,
      date: DateTime.now(),
      enregistrePar: enregistrePar,
    );
    autresFraisPaiementsByYear
        .putIfAbsent(currentYear, () => [])
        .add(paiement);
    await saveData();
    return paiement;
  }

  /// Supprime un paiement d'autre frais (ex: erreur de saisie) et
  /// sauvegarde.
  Future<void> deleteAutreFraisPaiement(String id, [String? year]) async {
    final y = year ?? currentYear;
    autresFraisPaiementsByYear[y]?.removeWhere((p) => p.id == id);
    await saveData();
  }

  /// Liste des paiements d'autres frais pour l'année donnée (par défaut
  /// l'année courante), triée de la plus récente à la plus ancienne.
  List<AutreFraisPaiement> getAutresFraisPaiementsForYear([String? year]) {
    final y = year ?? currentYear;
    final list = List<AutreFraisPaiement>.from(
        autresFraisPaiementsByYear[y] ?? []);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // ====================================================================
  // ⚡ NOUVEAU — RÉPARTITION PAR OPTION (Primaire / Secondaire /
  // Maternelle...) ET PAR SECTION PÉDAGOGIQUE (ex: Électricité,
  // Commerciale...) À L'INTÉRIEUR D'UNE OPTION.
  //
  // Dans cette application, ce que la direction appelle une "Option"
  // (Primaire, Secondaire, Maternelle) correspond au champ `section` de
  // l'élève (`config.sections`). Ce que la direction appelle une
  // "Section" pédagogique (ex: Électricité, Commerciale...) correspond
  // à la SOUS-CLASSE de l'élève (subClasseFromFullClasse) : dans le
  // système éducatif de la RDC, ces sections ne démarrent qu'à partir
  // de la 1ère (cycle long des Humanités) — la 7ème et la 8ème forment
  // le Cycle d'Orientation / Éducation de Base (tronc commun) et
  // n'appartiennent à aucune section pédagogique précise. C'est
  // pourquoi, pour toute classe sans sous-classe, on regroupe par
  // numéro de classe ("7ème", "8ème"...) sous forme d'"Éducation de
  // Base", plutôt que par une section qui n'existe pas encore à ce
  // niveau.
  //
  // Cette répartition est purement informative pour la direction/les
  // autorités scolaires : elle additionne les montants BRUTS collectés
  // (sans déduire les dépenses, qui sont globales à l'école et non
  // rattachées à une option ou section précise). Elle est calculée à la
  // volée et ne modifie/ne persiste rien.
  // ====================================================================

  /// Liste des options actuellement configurées (alias de
  /// config.sections, conservé séparément pour la lisibilité de cette
  /// API dédiée à la répartition).
  List<String> getOptions() => List<String>.from(config.sections);

  /// Répartition globale (total + par administration) pour une option
  /// donnée (ex: "Secondaire"), toutes classes confondues — c'est la
  /// combinaison totale de toutes les sections/tronc commun de cette
  /// option.
  RepartitionDetail getRepartitionForOption(String option) {
    final total = getStudentsBySection(option)
        .fold(0.0, (sum, e) => sum + getStudentTotalPaid(e));
    return RepartitionDetail(
      label: option,
      total: total,
      parAdministration: calculateAdminDistribution(total),
    );
  }

  /// Libellé de regroupement "section pédagogique" d'un élève à
  /// l'intérieur de son option : le nom de la sous-classe si elle
  /// existe (ex: "Électricité"), sinon "Éducation de Base (<classe>)"
  /// pour les classes sans section pédagogique (ex: 7ème, 8ème).
  String _sousSectionLabelFor(Eleve eleve) {
    final sousClasse = subClasseFromFullClasse(eleve.classe);
    if (sousClasse != null && sousClasse.trim().isNotEmpty) {
      return sousClasse.trim();
    }
    final numero = classeNumeroFromFullClasse(eleve.classe);
    return "Éducation de Base ($numero)";
  }

  /// Répartition détaillée par section pédagogique (ou "Éducation de
  /// Base" pour les classes sans section, ex: 7ème/8ème) à l'intérieur
  /// d'une option donnée.
  List<RepartitionDetail> getSousSectionsForOption(String option) {
    final students = getStudentsBySection(option);
    final Map<String, double> totalsByLabel = {};
    for (var e in students) {
      final label = _sousSectionLabelFor(e);
      totalsByLabel[label] =
          (totalsByLabel[label] ?? 0) + getStudentTotalPaid(e);
    }
    final details = totalsByLabel.entries
        .map((entry) => RepartitionDetail(
      label: entry.key,
      total: entry.value,
      parAdministration: calculateAdminDistribution(entry.value),
    ))
        .toList();
    // Tri : "Éducation de Base" d'abord (7ème avant 8ème par ordre
    // naturel du libellé), puis les sections pédagogiques par ordre
    // alphabétique.
    details.sort((a, b) {
      final aBase = a.label.startsWith("Éducation de Base");
      final bBase = b.label.startsWith("Éducation de Base");
      if (aBase && !bBase) return -1;
      if (!aBase && bBase) return 1;
      return a.label.compareTo(b.label);
    });
    return details;
  }

  /// Vrai si cette option comporte au moins une classe organisée en
  /// sections pédagogiques (sous-classes) — sert à savoir si l'écran
  /// "Autres Répartitions" doit proposer le détail par section pour
  /// cette option, ou seulement son total.
  bool optionHasSousSections(String option) {
    return getStudentsBySection(option).any((e) {
      final sc = subClasseFromFullClasse(e.classe);
      return sc != null && sc.trim().isNotEmpty;
    });
  }

  // ====================================================================
  // ⚡ NOUVEAU — COURBE D'ÉVOLUTION MENSUELLE (par Option / Section /
  // Classe), pour l'écran "Courbe d'Évolution" de la Répartition.
  // ====================================================================

  /// Totaux mensuels collectés (Septembre → Juin), filtrés selon option,
  /// section pédagogique et/ou classe. Chaque filtre est optionnel ;
  /// laissé à null, il n'est pas appliqué. Renvoie une liste alignée
  /// sur `months`.
  List<double> getMonthlyEvolution({
    String? option,
    String? sousSectionLabel,
    String? classe,
  }) {
    List<Eleve> students = currentData.eleves;
    if (option != null) {
      students = students.where((e) => e.section == option).toList();
    }
    if (sousSectionLabel != null) {
      students = students
          .where((e) => _sousSectionLabelFor(e) == sousSectionLabel)
          .toList();
    }
    if (classe != null) {
      students = students.where((e) => e.classe == classe).toList();
    }
    return months
        .map((m) =>
        students.fold<double>(0.0, (sum, e) => sum + (e.paid[m] ?? 0)))
        .toList();
  }

  /// Classes complètes (avec sous-classe) appartenant à une option et,
  /// éventuellement, à une section pédagogique donnée (ou "Éducation de
  /// Base (<classe>)" pour les classes sans section) — sert à peupler
  /// le filtre "Classe" de l'écran d'évolution.
  List<String> getClassesForOptionAndSousSection(
      String option, [
        String? sousSectionLabel,
      ]) {
    final classes = getAllDisplayClassesForSection(option);
    if (sousSectionLabel == null) return classes;
    return classes.where((c) {
      final sousClasse = subClasseFromFullClasse(c);
      final label = (sousClasse != null && sousClasse.trim().isNotEmpty)
          ? sousClasse.trim()
          : "Éducation de Base (${classeNumeroFromFullClasse(c)})";
      return label == sousSectionLabel;
    }).toList();
  }

  // ====================================================================
  // STATUT DE PAIEMENT PAR MOIS (EN ORDRE / PAS EN ORDRE)
  // ====================================================================
  bool isStudentEnOrdrePourMois(Eleve eleve, String mois) {
    final required     = getRequiredForMonth(mois, eleve.section, eleve.classe);
    final paidForMonth = eleve.paid[mois] ?? 0;
    return paidForMonth >= required;
  }

  List<Eleve> getStudentsByOrderStatus({
    required String mois,
    required bool enOrdre,
    String? sectionFilter,
    String? classFilter,
  }) {
    List<Eleve> students = currentData.eleves;
    if (sectionFilter != null) {
      students = students.where((e) => e.section == sectionFilter).toList();
    }
    if (classFilter != null) {
      students = students.where((e) => e.classe == classFilter).toList();
    }
    students = students
        .where((e) => isStudentEnOrdrePourMois(e, mois) == enOrdre)
        .toList();

    students.sort((a, b) {
      final c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      return a.nom.compareTo(b.nom);
    });
    return students;
  }

  // ====================================================================
  // GÉNÉRATION PDF
  // ====================================================================

  // ⚡ CORRIGÉ — cette méthode renvoie maintenant un `Map<String, dynamic>`
  // ({'success': bool, 'error': String?, 'path': String?}) au lieu de
  // `void`. Avant, si la sauvegarde du PDF échouait (voir `_savePdf`,
  // qui avalait silencieusement toute exception avec `catch (_) {}`),
  // l'écran appelant affichait quand même "Rapport PDF généré avec
  // succès" — ce qui est trompeur pour vos utilisateurs. Les anciens
  // appels `await fraisScolaires.generatePdf(...)` sans utiliser le
  // retour restent parfaitement valides : ce changement est rétro-
  // compatible.
  //
  // ⚡ NOUVEAU — paramètre `city` (ville affichée dans le bloc "Fait à
  // ..., le ..." des signatures, voir `_buildSignatureSection`) et
  // enrichissement du contenu du tableau/rapport selon le type :
  //   - "daily"   : ajoute une colonne "Mois Concerné(s)" indiquant,
  //     pour chaque élève, le(s) mois couvert(s) par SON paiement du
  //     jour (et non le total annuel affiché dans "Montant Payé").
  //   - "annual"  : ajoute un petit récapitulatif mensuel (Mois / Total
  //     Collecté) après la liste des élèves, pratique courante des
  //     rapports financiers scolaires en RDC pour une situation
  //     annuelle, sans avoir à répéter le détail mois par mois pour
  //     chaque élève (ce qui surchargerait la feuille).
  //   - "monthly" : inchangé — le mois concerné est déjà indiqué dans
  //     le titre et dans la ligne "Total ce Mois (...)", un rapport
  //     mensuel ne portant que sur un seul mois à la fois.
  Future<Map<String, dynamic>> generatePdf({
    required String filename,
    required String reportType,
    String? sectionFilter,
    String? classFilter,
    String? city,
  }) async {
    if (reportType == "student_list") {
      return await _generateStudentListPdf(
        filename:      filename,
        sectionFilter: sectionFilter,
        classFilter:   classFilter,
        city:          city,
      );
    }

    final pdf     = pw.Document();
    List<Eleve> students;
    String title;

    if (reportType == "daily") {
      students = getPaidStudentsToday();
      title    = "RAPPORT JOURNALIER";
    } else if (reportType == "monthly") {
      students = getPaidStudentsThisMonth();
      title    = "RAPPORT MENSUEL";
    } else {
      students = currentData.eleves;
      title    = "RAPPORT ANNUEL";
    }

    if (sectionFilter != null) {
      students = students
          .where((e) => e.section == sectionFilter)
          .toList();
      title += " - $sectionFilter";
    }
    if (classFilter != null) {
      students = students
          .where((e) => e.classe == classFilter)
          .toList();
      title += " - $classFilter";
    }

    final double total              = students.fold(
        0.0, (sum, e) => sum + getStudentTotalPaid(e));
    final adminDistribution         = calculateAdminDistribution(total);
    final double totalMoisEcole     = getCurrentMonthTotalCollected();
    final double totalAnneeEcole    = getYearTotalCollected();
    // ⚡ CORRIGÉ — utilisait `months[DateTime.now().month - 1]`, qui
    // affichait le mauvais mois (ex: "Avril" en plein mois d'Août).
    // Utilise maintenant `currentSchoolMonthName`, basé sur le bon
    // mapping calendrier -> année scolaire.
    final String currentMonthName =
        currentSchoolMonthName ?? "Hors année scolaire (vacances)";

    // ⚡ NOUVEAU — la colonne "Mois Concerné(s)" n'a de sens que pour le
    // rapport journalier : c'est le seul cas où deux élèves listés côte
    // à côte peuvent avoir payé pour des mois différents le même jour
    // (règlement d'arriéré, avance sur plusieurs mois...).
    final bool showMoisConcerne = reportType == "daily";

    final headers = [
      'ID', 'Nom Complet', 'Section', 'Classe', 'Montant Payé (FC)',
      if (showMoisConcerne) 'Mois Concerné(s)',
      ...config.administrations.map(
              (a) => '${a.nom} (${a.pourcentage.toStringAsFixed(0)}%)'),
    ];

    final rows = students.map((e) {
      final montant = getStudentTotalPaid(e);
      final row = [
        e.id.isNotEmpty ? e.id : "N/A",
        "${e.nom} ${e.postNom} ${e.prenom}",
        e.section,
        e.classe,
        montant.toStringAsFixed(0),
      ];
      if (showMoisConcerne) {
        final moisConcernes = getMoisPayesPourDate(e);
        row.add(moisConcernes.isNotEmpty
            ? moisConcernes
            : (currentSchoolMonthName ?? '-'));
      }
      for (var admin in config.administrations) {
        row.add(
            (montant * (admin.pourcentage / 100)).toStringAsFixed(0));
      }
      return row;
    }).toList();

    // ⚡ NOUVEAU — récapitulatif mensuel pour le rapport annuel (voir
    // explication au-dessus de `generatePdf`).
    final List<double> recapMensuel =
    reportType == "annual" ? getMonthlyEvolution() : const [];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text('${config.schoolName} - $currentYear'),
          // ⚡ CORRIGÉ — affiche maintenant la date ET le jour de
          // génération (demande explicite des utilisateurs), au lieu
          // du format ISO brut précédent (ex: "2026-08-24") qui
          // n'indiquait pas le jour de la semaine.
          pw.Text('Généré le : $_dateGenerationFormatee'),
          pw.SizedBox(height: 20),
          pw.Text(
            "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
            style: pw.TextStyle(
                fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            "Total ce Mois ($currentMonthName) : "
                "${totalMoisEcole.toStringAsFixed(0)} FC",
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.Text(
            "Total cette Année ($currentYear) : "
                "${totalAnneeEcole.toStringAsFixed(0)} FC",
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 20),
          pw.Text("LISTE DES ÉLÈVES",
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers:   headers,
            data:      rows,
            headerStyle: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          // ⚡ NOUVEAU — récapitulatif mensuel, uniquement pour le
          // rapport annuel : une petite table "Mois / Total Collecté"
          // qui donne la vue mensualisée attendue sur une situation
          // annuelle, sans dupliquer le détail par élève pour chaque
          // mois (ce qui rendrait la feuille illisible).
          if (reportType == "annual") ...[
            pw.SizedBox(height: 26),
            pw.Text("RÉCAPITULATIF MENSUEL",
                style: pw.TextStyle(
                    fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: const ['Mois', 'Total Collecté (FC)'],
              data: List<List<String>>.generate(
                months.length,
                    (i) => [
                  months[i],
                  (i < recapMensuel.length ? recapMensuel[i] : 0.0)
                      .toStringAsFixed(0),
                ],
              ),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
              },
              oddRowDecoration:
              const pw.BoxDecoration(color: PdfColors.indigo50),
            ),
          ],
          pw.SizedBox(height: 30),
          pw.Text(
            "RÉPARTITION GLOBALE PAR ADMINISTRATION",
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          ...adminDistribution.entries.map(
                (entry) => pw.Text(
              "${entry.key} : ${entry.value.toStringAsFixed(0)} FC "
                  "(${config.administrations.firstWhere((a) => a.nom == entry.key).pourcentage.toStringAsFixed(0)}%)",
            ),
          ),
          // ⚡ NOUVEAU — bloc de signatures (voir _buildSignatureSection),
          // avec la ville saisie par l'utilisateur.
          ..._buildSignatureSection(city),
        ],
      ),
    );

    return await _savePdf(pdf, filename, reportType);
  }

  // ⚡ CORRIGÉ — renvoie maintenant `Map<String, dynamic>` (voir
  // `generatePdf` ci-dessus pour l'explication).
  // ⚡ NOUVEAU — paramètre `city`, transmis au bloc de signatures.
  Future<Map<String, dynamic>> _generateStudentListPdf({
    required String filename,
    String? sectionFilter,
    String? classFilter,
    String? city,
  }) async {
    List<Eleve> students = currentData.eleves;
    if (sectionFilter != null) {
      students =
          students.where((e) => e.section == sectionFilter).toList();
    }
    if (classFilter != null) {
      students =
          students.where((e) => e.classe == classFilter).toList();
    }
    students.sort((a, b) {
      final c = a.classe.compareTo(b.classe);
      if (c != 0) return c;
      return a.nom.compareTo(b.nom);
    });

    final sectionLabel = sectionFilter ?? "Toutes les sections";
    final classeLabel  = classFilter   ?? "Toutes les classes";
    // ⚡ CORRIGÉ — date + jour, voir `_dateGenerationFormatee`.
    final dateStr      = _dateGenerationFormatee;

    final rows = <List<String>>[];
    for (int i = 0; i < students.length; i++) {
      final e = students[i];
      rows.add(['${i + 1}', e.nom, e.postNom, e.prenom, e.classe]);
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "REGISTRE DES ÉLÈVES — Année $currentYear",
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel | Classe : $classeLabel",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Imprimé le : $dateStr | Total : ${students.length} élève(s)",
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['N°', 'Nom', 'Post-nom', 'Prénom', 'Classe'],
            data:    rows,
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo),
            cellStyle:   const pw.TextStyle(fontSize: 10),
            cellHeight:  22,
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.center,
            },
            oddRowDecoration:
            const pw.BoxDecoration(color: PdfColors.indigo50),
          ),
          // ⚡ NOUVEAU — bloc de signatures (voir _buildSignatureSection),
          // avec la ville saisie par l'utilisateur.
          ..._buildSignatureSection(city),
        ],
      ),
    );

    return await _savePdf(pdf, filename, "student_list");
  }

  // ====================================================================
  // GÉNÉRATION PDF — LISTE PAR STATUT DE PAIEMENT
  // ====================================================================

  // ⚡ CORRIGÉ — renvoie maintenant `Map<String, dynamic>` (voir
  // `generatePdf` ci-dessus pour l'explication).
  Future<Map<String, dynamic>> generateOrderStatusPdf({
    required String filename,
    required String mois,
    required bool enOrdre,
    String? sectionFilter,
    String? classFilter,
  }) async {
    final students = getStudentsByOrderStatus(
      mois:          mois,
      enOrdre:       enOrdre,
      sectionFilter: sectionFilter,
      classFilter:   classFilter,
    );

    final sectionLabel = sectionFilter ?? "Toutes les sections";
    final classeLabel  = classFilter   ?? "Toutes les classes";
    // ⚡ CORRIGÉ — date + jour, voir `_dateGenerationFormatee`.
    final dateStr      = _dateGenerationFormatee;
    final statutLabel  =
    enOrdre ? "QUI ONT DÉJÀ PAYÉ" : "QUI N'ONT PAS ENCORE PAYÉ";

    final title = "LISTE DES ÉLÈVES DE $classeLabel - $sectionLabel "
        "DU $dateStr $statutLabel $mois";

    final rows = <List<String>>[];
    for (int i = 0; i < students.length; i++) {
      final e              = students[i];
      final montantPaye    = e.paid[mois] ?? 0;
      final montantRequis  =
      getRequiredForMonth(mois, e.section, e.classe);
      rows.add([
        '${i + 1}',
        e.nom,
        e.postNom,
        e.prenom,
        e.classe,
        '${montantPaye.toStringAsFixed(0)} / ${montantRequis.toStringAsFixed(0)} FC',
      ]);
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              config.schoolName.toUpperCase(),
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              "Section : $sectionLabel | Classe : $classeLabel | Mois : $mois",
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "Année $currentYear | Imprimé le : $dateStr | "
                  "Total : ${students.length} élève(s)",
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'N°', 'Nom', 'Post-nom', 'Prénom', 'Classe',
              'Payé / Requis ($mois)',
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(
              color: enOrdre ? PdfColors.green700 : PdfColors.red700,
            ),
            cellStyle:  const pw.TextStyle(fontSize: 9),
            cellHeight: 22,
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.center,
              5: pw.Alignment.center,
            },
            oddRowDecoration: pw.BoxDecoration(
              color: enOrdre ? PdfColors.green50 : PdfColors.red50,
            ),
          ),
        ],
      ),
    );

    return await _savePdf(
      pdf,
      filename,
      enOrdre ? 'en_ordre_$mois' : 'pas_en_ordre_$mois',
    );
  }

  // ====================================================================
  // ⚡ NOUVEAU — GÉNÉRATION PDF — RAPPORT DES "AUTRES FRAIS DE PAIEMENT"
  //
  // Contrairement à `generatePdf` (réservé au frais mensuel PRINCIPAL,
  // inchangé ci-dessus), cette méthode génère un rapport dédié aux
  // frais additionnels/éphémères (ex: "Frais de l'État", "Frais
  // d'Aide"...) gérés depuis l'écran `AutresFraisScreen`.
  //
  // Paramètres :
  //  - `autreFraisId` : si fourni, ne reprend QUE les paiements de ce
  //    type de frais précis. Si `null`, reprend TOUS les types de
  //    frais additionnels confondus (utile pour un rapport global).
  //  - `sectionFilter` / `classFilter` : mêmes filtres que le rapport
  //    principal — l'utilisateur peut générer par classe précise, par
  //    section (option) précise, ou sans filtre du tout (toute
  //    l'école), exactement comme pour `generatePdf`.
  //  - `city` : ⚡ NOUVEAU — ville affichée dans le bloc de signatures
  //    ("Fait à ..., le ..."), transmise telle quelle à
  //    `_buildSignatureSection`.
  //
  // On repart des paiements déjà enregistrés (jamais des frais eux-
  // mêmes) : un frais additionnel supprimé entretemps reste donc bien
  // visible dans les rapports déjà émis, avec son nom "photographié"
  // au moment du paiement (`AutreFraisPaiement.autreFraisNom`).
  //
  // Comme pour `generatePdf`, le bloc de signatures configuré dans les
  // Paramètres (voir `_buildSignatureSection`) est automatiquement
  // ajouté en bas du rapport.
  //
  // Renvoie {'success': bool, 'error': String?, 'path': String?}, au
  // même format que les autres méthodes de génération PDF de cette
  // classe.
  // ====================================================================
  Future<Map<String, dynamic>> generateAutresFraisPdf({
    required String filename,
    String? autreFraisId,
    String? sectionFilter,
    String? classFilter,
    String? city,
  }) async {
    // Retrouve le frais sélectionné (uniquement pour l'affichage du
    // titre) — reste `null` si `autreFraisId` est `null` (rapport
    // "tous types confondus") ou si le frais a été supprimé entretemps
    // (le rapport reste alors possible, juste sans nom précis dans le
    // titre : les paiements gardent de toute façon leur propre nom
    // "photographié").
    AutreFrais? fraisSelectionne;
    if (autreFraisId != null) {
      for (final f in autresFrais) {
        if (f.id == autreFraisId) {
          fraisSelectionne = f;
          break;
        }
      }
    }

    var paiements = getAutresFraisPaiementsForYear();
    if (autreFraisId != null) {
      paiements =
          paiements.where((p) => p.autreFraisId == autreFraisId).toList();
    }

    final rows = <List<String>>[];
    double total = 0;

    for (final p in paiements) {
      Eleve? eleve;
      for (final e in currentData.eleves) {
        if (e.id == p.eleveId) {
          eleve = e;
          break;
        }
      }
      final section = eleve?.section ?? '';
      final classe  = eleve?.classe  ?? '';

      // Filtres section/classe : un paiement dont l'élève est
      // introuvable (élève supprimé entretemps) n'est inclus que si
      // AUCUN filtre n'est demandé, pour ne jamais l'attribuer à tort
      // à une section/classe qu'il n'a peut-être jamais eue.
      if (sectionFilter != null && section != sectionFilter) continue;
      if (classFilter != null && classe != classFilter) continue;

      rows.add([
        (eleve != null && eleve.id.isNotEmpty) ? eleve.id : 'N/A',
        eleve != null
            ? "${eleve.nom} ${eleve.postNom} ${eleve.prenom}"
            : "Élève introuvable",
        section.isEmpty ? '-' : section,
        classe.isEmpty ? '-' : classe,
        p.autreFraisNom,
        p.montant.toStringAsFixed(0),
        p.dateFormatee,
      ]);
      total += p.montant;
    }

    final adminDistribution = calculateAdminDistribution(total);

    String title = "RAPPORT — AUTRES FRAIS DE PAIEMENT";
    if (fraisSelectionne != null) {
      title += " : ${fraisSelectionne.nom}";
    } else if (autreFraisId != null) {
      // Le frais existait au moment des paiements mais a depuis été
      // supprimé de la configuration : on retombe sur le nom du
      // premier paiement trouvé, sinon un libellé générique.
      title += paiements.isNotEmpty
          ? " : ${paiements.first.autreFraisNom}"
          : "";
    } else {
      title += " (TOUS TYPES CONFONDUS)";
    }
    if (sectionFilter != null) title += " - $sectionFilter";
    if (classFilter != null) title += " - $classFilter";

    final headers = [
      'ID', 'Nom Complet', 'Section', 'Classe', 'Type de Frais',
      'Montant (FC)', 'Date de Paiement',
    ];

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('${config.schoolName} - $currentYear'),
          pw.Text('Généré le : $_dateGenerationFormatee'),
          pw.SizedBox(height: 20),
          pw.Text(
            "Total Collecté (ce rapport) : ${total.toStringAsFixed(0)} FC",
            style:
            pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            "Nombre de paiements : ${rows.length}",
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            "DÉTAIL DES PAIEMENTS",
            style:
            pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (rows.isEmpty)
            pw.Text(
              "Aucun paiement enregistré pour ce filtre.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              headerStyle:
              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          pw.SizedBox(height: 30),
          pw.Text(
            "RÉPARTITION GLOBALE PAR ADMINISTRATION",
            style:
            pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (total == 0)
            pw.Text(
              "Aucun montant à répartir.",
              style:
              const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            )
          else
            ...adminDistribution.entries.map(
                  (entry) => pw.Text(
                "${entry.key} : ${entry.value.toStringAsFixed(0)} FC "
                    "(${config.administrations.firstWhere((a) => a.nom == entry.key).pourcentage.toStringAsFixed(0)}%)",
              ),
            ),
          // ⚡ NOUVEAU — même bloc de signatures que le rapport
          // principal (voir _buildSignatureSection), demandé
          // explicitement pour le rapport des autres frais, avec la
          // ville saisie par l'utilisateur.
          ..._buildSignatureSection(city),
        ],
      ),
    );

    return await _savePdf(pdf, filename, "autres_frais");
  }

  // ⚡ CORRIGÉ — BUG DE FIABILITÉ : avant, cette méthode avalait
  // silencieusement toute erreur (`catch (_) {}`), et ne renvoyait
  // rien (`void`). L'écran appelant (`_showReportDialog` dans
  // school_home_screen.dart) affichait donc TOUJOURS "✅ Rapport PDF
  // généré avec succès", même quand :
  //  - l'écriture du fichier échouait (permissions, disque plein...),
  //  - l'utilisateur annulait la boîte de dialogue "Enregistrer sous"
  //    (cas desktop sans dossier Téléchargements).
  // Renvoie maintenant {'success': bool, 'error': String?, 'path': String?}
  // pour que l'écran puisse informer correctement l'utilisateur.
  Future<Map<String, dynamic>> _savePdf(
      pw.Document pdf, String filename, String reportType) async {
    try {
      final bytes     = await pdf.save();
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        final fileName =
            '${filename}_${reportType}_${DateTime.now().toString().split(' ')[0]}.pdf';
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFile.open(file.path);
        return {'success': true, 'path': file.path};
      } else {
        final saveLocation = await getSaveLocation(
          suggestedName: '${filename}_$reportType.pdf',
          acceptedTypeGroups: [
            XTypeGroup(label: 'PDF', extensions: ['pdf'])
          ],
        );
        if (saveLocation != null) {
          final file = File(saveLocation.path);
          await file.writeAsBytes(bytes);
          await OpenFile.open(file.path);
          return {'success': true, 'path': file.path};
        }
        // L'utilisateur a annulé la boîte de dialogue : ce n'est pas un
        // succès, on ne doit pas le dire à l'écran appelant.
        return {'success': false, 'error': 'Enregistrement annulé.'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ====================================================================
  // GESTION DES DONNÉES LOCALES
  // ====================================================================
  Future<void> loadData() async {
    final dir       = await getApplicationDocumentsDirectory();
    _dataFilePath   = '${dir.path}/school_fees_data.json';
    final file      = File(_dataFilePath!);

    if (await file.exists()) {
      try {
        final jsonStr = await file.readAsString();
        final data    = json.decode(jsonStr) as Map<String, dynamic>;

        config       = SchoolConfig.fromJson(data['config'] ?? {});
        currentYear  = data['currentYear'] ?? '2025-2026';
        lastSelectedClassFilter   = data['lastSelectedClassFilter'];
        lastSelectedSectionFilter = data['lastSelectedSectionFilter'];
        // ⚡ NOUVEAU — dernière ville utilisée pour les rapports PDF.
        lastReportCity = data['lastReportCity'] as String?;

        schoolCode = data['schoolCode'] as String?;

        // ⚡ NOUVEAU — chargement du code masqué (mode administrateur
        // caché) et du journal d'audit associé.
        hiddenCodeHash = data['hiddenCodeHash'] as String?;
        hiddenCodeSalt = data['hiddenCodeSalt'] as String?;
        if (data['adminAuditLog'] != null) {
          adminAuditLog = (data['adminAuditLog'] as List<dynamic>)
              .map((e) => AdminAuditLog.fromJson(e as Map<String, dynamic>))
              .toList();
        }

        // ⚡ NOUVEAU — chargement des signataires (signatures sur les
        // rapports PDF).
        if (data['signataires'] != null) {
          signataires = (data['signataires'] as List<dynamic>)
              .map((e) => Signataire.fromJson(e as Map<String, dynamic>))
              .toList();
        }

        if (data['history'] != null) {
          history = (data['history'] as Map<String, dynamic>).map(
                (key, value) =>
                MapEntry(key, SchoolYearData.fromJson(value)),
          );
        }

        // ⚡ NOUVEAU — chargement des dépenses par année
        if (data['depensesByYear'] != null) {
          depensesByYear =
              (data['depensesByYear'] as Map<String, dynamic>).map(
                    (key, value) => MapEntry(
                  key,
                  (value as List<dynamic>)
                      .map((e) => Depense.fromJson(e as Map<String, dynamic>))
                      .toList(),
                ),
              );
        }

        // ⚡ NOUVEAU — chargement des autres frais + leurs paiements
        if (data['autresFrais'] != null) {
          autresFrais = (data['autresFrais'] as List<dynamic>)
              .map((e) => AutreFrais.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (data['autresFraisPaiementsByYear'] != null) {
          autresFraisPaiementsByYear = (data['autresFraisPaiementsByYear']
          as Map<String, dynamic>)
              .map(
                (key, value) => MapEntry(
              key,
              (value as List<dynamic>)
                  .map((e) => AutreFraisPaiement.fromJson(
                  e as Map<String, dynamic>))
                  .toList(),
            ),
          );
        }

        if (history.containsKey(currentYear)) {
          currentData = history[currentYear]!;
        } else {
          currentData          = SchoolYearData(eleves: []);
          history[currentYear] = currentData;
        }

        if (data['localIdCounter'] != null) {
          _localIdCounter = data['localIdCounter'] as int;
        } else {
          _localIdCounter = _inferCounterFromExistingIds();
        }

        // ⚡ NOUVEAU — chargement des données du mode réseau local (clés,
        // files d'attente, présence, communications).
        if (data['localAccessKeys'] != null) {
          localAccessKeys = (data['localAccessKeys'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        if (data['localPendingPayments'] != null) {
          localPendingPayments =
              (data['localPendingPayments'] as List<dynamic>)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
        }
        if (data['localPendingRegistrations'] != null) {
          localPendingRegistrations =
              (data['localPendingRegistrations'] as List<dynamic>)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
        }
        if (data['localPendingAutresFraisPayments'] != null) {
          localPendingAutresFraisPayments =
              (data['localPendingAutresFraisPayments'] as List<dynamic>)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
        }
        if (data['localAttendance'] != null) {
          localAttendance =
              (data['localAttendance'] as Map<String, dynamic>).map(
                    (key, value) => MapEntry(
                  key,
                  (value as List<dynamic>).map((e) => e.toString()).toList(),
                ),
              );
        }
        if (data['localCommunicationsLog'] != null) {
          localCommunicationsLog =
              (data['localCommunicationsLog'] as List<dynamic>)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
        }

        // ⚡ NOUVEAU — chargement des reçus déjà imprimés et de la file
        // d'attente d'impression (anti-double impression, persistant).
        if (data['printedReceiptKeys'] != null) {
          printedReceiptKeys = (data['printedReceiptKeys'] as List<dynamic>)
              .map((e) => e.toString())
              .toList();
        }
        if (data['receiptQueue'] != null) {
          receiptQueue = (data['receiptQueue'] as List<dynamic>)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }

        await _assignMissingIds();
      } catch (_) {
        _initDefaultData();
      }
    } else {
      _initDefaultData();
    }
  }

  int _inferCounterFromExistingIds() {
    int maxCounter = 0;
    final regex    = RegExp(r'(\d+)$');
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        final match = regex.firstMatch(eleve.id);
        if (match != null) {
          final n = int.tryParse(match.group(1) ?? '') ?? 0;
          if (n > maxCounter) maxCounter = n;
        }
      }
    }
    return maxCounter;
  }

  Future<void> _assignMissingIds() async {
    bool changed = false;
    for (var yearData in history.values) {
      for (var eleve in yearData.eleves) {
        if (eleve.id.isEmpty || eleve.id == "N/A") {
          eleve.id = generateLocalStudentId(eleve.nom);
          changed  = true;
        }
      }
    }
    if (changed) await saveData();
  }

  void _initDefaultData() {
    currentData          = SchoolYearData(eleves: []);
    history[currentYear] = currentData;
    _localIdCounter      = 0;
  }

  Future<void> saveData() async {
    if (_dataFilePath == null) {
      final dir     = await getApplicationDocumentsDirectory();
      _dataFilePath = '${dir.path}/school_fees_data.json';
    }
    history[currentYear] = currentData;
    final file = File(_dataFilePath!);
    final data = {
      'config':                  config.toJson(),
      'currentYear':             currentYear,
      'localIdCounter':          _localIdCounter,
      'lastSelectedClassFilter': lastSelectedClassFilter,
      'lastSelectedSectionFilter': lastSelectedSectionFilter,
      // ⚡ NOUVEAU — dernière ville utilisée pour les rapports PDF.
      'lastReportCity': lastReportCity,
      'schoolCode':              schoolCode,
      'history':                 history.map(
              (key, value) => MapEntry(key, value.toJson())),
      // ⚡ NOUVEAU
      'depensesByYear': depensesByYear.map(
            (key, value) =>
            MapEntry(key, value.map((d) => d.toJson()).toList()),
      ),
      // ⚡ NOUVEAU
      'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
      'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
            (key, value) =>
            MapEntry(key, value.map((p) => p.toJson()).toList()),
      ),
      // ⚡ NOUVEAU — mode administrateur caché
      'hiddenCodeHash': hiddenCodeHash,
      'hiddenCodeSalt': hiddenCodeSalt,
      'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
      // ⚡ NOUVEAU — signataires des rapports PDF
      'signataires': signataires.map((s) => s.toJson()).toList(),
      // ⚡ NOUVEAU — mode réseau local (clés, files d'attente, présence)
      'localAccessKeys': localAccessKeys,
      'localPendingPayments': localPendingPayments,
      'localPendingRegistrations': localPendingRegistrations,
      'localPendingAutresFraisPayments': localPendingAutresFraisPayments,
      'localAttendance': localAttendance,
      'localCommunicationsLog': localCommunicationsLog,
      // ⚡ NOUVEAU — reçus déjà imprimés + file d'attente d'impression.
      'printedReceiptKeys': printedReceiptKeys,
      'receiptQueue': receiptQueue,
    };
    await file.writeAsString(json.encode(data));
  }

  // ====================================================================
  // SUPPRESSION DES DONNÉES LOCALES (déconnexion)
  // ====================================================================
  Future<void> clearLocalData() async {
    if (_dataFilePath == null) {
      final dir     = await getApplicationDocumentsDirectory();
      _dataFilePath = '${dir.path}/school_fees_data.json';
    }
    final file = File(_dataFilePath!);
    if (await file.exists()) {
      await file.delete();
    }
    config      = SchoolConfig(schoolName: "EduPay School RDC");
    currentData = SchoolYearData(eleves: []);
    currentYear = '2025-2026';
    history     = {};
    _localIdCounter = 0;
    lastSelectedClassFilter   = null;
    lastSelectedSectionFilter = null;
    lastReportCity = null; // ⚡ NOUVEAU
    schoolCode  = null;
    depensesByYear = {}; // ⚡ NOUVEAU
    autresFrais = []; // ⚡ NOUVEAU
    autresFraisPaiementsByYear = {}; // ⚡ NOUVEAU
    hiddenCodeHash = null; // ⚡ NOUVEAU
    hiddenCodeSalt = null; // ⚡ NOUVEAU
    adminAuditLog = []; // ⚡ NOUVEAU
    signataires = []; // ⚡ NOUVEAU
    localAccessKeys = []; // ⚡ NOUVEAU
    localPendingPayments = []; // ⚡ NOUVEAU
    localPendingRegistrations = []; // ⚡ NOUVEAU
    localPendingAutresFraisPayments = []; // ⚡ NOUVEAU
    localAttendance = {}; // ⚡ NOUVEAU
    localCommunicationsLog = []; // ⚡ NOUVEAU
    printedReceiptKeys = []; // ⚡ NOUVEAU
    receiptQueue = []; // ⚡ NOUVEAU
  }

  Future<void> changeYear(String newYear) async {
    if (currentYear == newYear) return;
    history[currentYear] = currentData;
    currentYear = newYear;
    if (history.containsKey(newYear)) {
      currentData = history[newYear]!;
    } else {
      currentData          = SchoolYearData(eleves: []);
      history[newYear]     = currentData;
    }
    await saveData();
  }

  void handlePayment(Eleve eleve, String mois, double payment) {
    int    index     = months.indexOf(mois);
    if (index == -1) return;

    final String today     = DateTime.now().toString().split(' ')[0];
    double       remaining = payment;
    String       currentMonth = mois;

    while (remaining > 0 && index < months.length) {
      double required    =
      getRequiredForMonth(currentMonth, eleve.section, eleve.classe);
      double alreadyPaid = eleve.paid[currentMonth] ?? 0;
      double needed      = required - alreadyPaid;

      if (needed > 0) {
        double toAdd = remaining > needed ? needed : remaining;
        eleve.paid[currentMonth] = alreadyPaid + toAdd;
        eleve.transactions.add({
          'date':   today,
          'mois':   currentMonth,
          'amount': toAdd,
        });
        remaining -= toAdd;
      }

      index++;
      if (index < months.length) currentMonth = months[index];
    }
  }

  double getStudentTotalPaid(Eleve eleve) =>
      eleve.paid.values.fold(0.0, (sum, p) => sum + p);

  double getStudentPending(Eleve eleve) {
    return months.fold(
        0.0,
            (sum, m) =>
        sum +
            (getRequiredForMonth(m, eleve.section, eleve.classe) -
                (eleve.paid[m] ?? 0)));
  }

  // ====================================================================
  // BACKUP & RESTORE
  // ====================================================================
  Future<Map<String, dynamic>> backupToServer(
      String schoolCodeParam, String password) async {
    final normalizedCode = schoolCodeParam.trim().toUpperCase();
    try {
      schoolCode = normalizedCode;
      await saveData();

      final data = {
        'config':          config.toJson(),
        'currentYear':     currentYear,
        'localIdCounter':  _localIdCounter,
        'lastSelectedClassFilter':   lastSelectedClassFilter,
        'lastSelectedSectionFilter': lastSelectedSectionFilter,
        'history':         history.map(
                (key, value) => MapEntry(key, value.toJson())),
        // ⚡ NOUVEAU — les dépenses suivent aussi la sauvegarde serveur
        'depensesByYear': depensesByYear.map(
              (key, value) =>
              MapEntry(key, value.map((d) => d.toJson()).toList()),
        ),
        // ⚡ NOUVEAU — les autres frais et leurs paiements suivent aussi
        // la sauvegarde serveur
        'autresFrais': autresFrais.map((f) => f.toJson()).toList(),
        'autresFraisPaiementsByYear': autresFraisPaiementsByYear.map(
              (key, value) =>
              MapEntry(key, value.map((p) => p.toJson()).toList()),
        ),
        // ⚡ NOUVEAU — le mode administrateur caché suit aussi la
        // sauvegarde serveur, pour que l'annulation/modification d'un
        // paiement se propage vers les autres appareils (app admin
        // desktop, app parent) et que le code masqué soit récupérable
        // en cas de restauration sur un nouvel appareil.
        'hiddenCodeHash': hiddenCodeHash,
        'hiddenCodeSalt': hiddenCodeSalt,
        'adminAuditLog': adminAuditLog.map((a) => a.toJson()).toList(),
        // ⚡ NOUVEAU — les signataires suivent aussi la sauvegarde
        // serveur, pour rester disponibles sur les autres appareils.
        'signataires': signataires.map((s) => s.toJson()).toList(),
        // ⚡ NOUVEAU — les reçus déjà imprimés et la file d'attente
        // suivent aussi la sauvegarde serveur, pour qu'aucun reçu ne
        // soit réimprimé en double si l'école utilise plusieurs
        // appareils (ex: caisse + bureau de la direction).
        'printedReceiptKeys': printedReceiptKeys,
        'receiptQueue': receiptQueue,
        'backup_password': password,
      };

      final response = await http
          .post(
        Uri.parse('$serverUrl/backup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'school_code': normalizedCode, 'data': data}),
      )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final corrections  =
            responseData['corrections'] as Map<String, dynamic>? ?? {};
        if (corrections.isNotEmpty) {
          _applyIdCorrections(corrections);
          await saveData();
        }
        return {'success': true};
      }
      return {
        'success': false,
        'error':
        'Le serveur a répondu avec le statut ${response.statusCode} : '
            '${response.body}',
      };
    } on SocketException catch (e) {
      return {
        'success': false,
        'error': 'Aucune connexion réseau (vérifiez internet / pare-feu) : $e',
      };
    } on HandshakeException catch (e) {
      return {
        'success': false,
        'error': 'Erreur de certificat TLS/SSL sur cet appareil : $e',
      };
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  Future<Map<String, dynamic>> restoreFromServer(
      String schoolCodeParam, String password) async {
    final normalizedCode = schoolCodeParam.trim().toUpperCase();
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/restore?school_code=$normalizedCode'))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['backup_password'] != null &&
            data['backup_password'] != password) {
          return {'success': false, 'error': 'Mot de passe incorrect'};
        }
        schoolCode = normalizedCode;
        await mergeRestoredData(data);
        await saveData();
        return {'success': true};
      }
      if (response.statusCode == 404) {
        return {
          'success': false,
          'error':
          'Aucune sauvegarde trouvée pour le code "$normalizedCode". '
              'Vérifiez que ce code est exactement celui utilisé lors '
              'du dernier "Sauvegarder sur le Serveur".',
        };
      }
      return {
        'success': false,
        'error':
        'Le serveur a répondu avec le statut ${response.statusCode} : '
            '${response.body}',
      };
    } on SocketException catch (e) {
      return {
        'success': false,
        'error': 'Aucune connexion réseau (vérifiez internet / pare-feu) : $e',
      };
    } catch (e) {
      return {'success': false, 'error': 'Erreur inattendue : $e'};
    }
  }

  Future<Map<String, dynamic>> checkSchoolCodeExists(
      String schoolCodeParam) async {
    final normalizedCode = schoolCodeParam.trim().toUpperCase();
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/restore?school_code=$normalizedCode'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final name = (data['config']?['schoolName'] ?? '') as String;
        return {'exists': true, 'schoolName': name};
      }
      if (response.statusCode == 404) {
        return {'exists': false, 'error': 'Aucune école trouvée avec ce code.'};
      }
      return {
        'exists': false,
        'error': 'Statut HTTP ${response.statusCode} : ${response.body}',
      };
    } catch (e) {
      return {'exists': false, 'error': 'Erreur réseau : $e'};
    }
  }

  Future<void> mergeRestoredData(Map<String, dynamic> serverData) async {
    config = SchoolConfig.fromJson(serverData['config'] ?? {});

    if (serverData['localIdCounter'] != null) {
      final serverCounter = serverData['localIdCounter'] as int;
      if (serverCounter > _localIdCounter) {
        _localIdCounter = serverCounter;
      }
    }

    if (serverData['history'] != null) {
      final serverHistory =
      (serverData['history'] as Map<String, dynamic>).map(
            (key, value) =>
            MapEntry(key, SchoolYearData.fromJson(value)),
      );

      for (var entry in serverHistory.entries) {
        final year           = entry.key;
        final serverYearData = entry.value;

        if (history.containsKey(year)) {
          final localEleves  = history[year]!.eleves;
          final existingByKey = <String, Eleve>{};
          for (var e in localEleves) {
            final key =
                "${e.nom.trim().toLowerCase()}_${e.postNom.trim().toLowerCase()}_${e.prenom.trim().toLowerCase()}";
            existingByKey[key] = e;
          }

          for (var serverEleve in serverYearData.eleves) {
            final key =
                "${serverEleve.nom.trim().toLowerCase()}_${serverEleve.postNom.trim().toLowerCase()}_${serverEleve.prenom.trim().toLowerCase()}";

            if (existingByKey.containsKey(key)) {
              final localEleve = existingByKey[key]!;
              localEleve.id    = serverEleve.id.isNotEmpty
                  ? serverEleve.id
                  : localEleve.id;
              localEleve.classe   = serverEleve.classe;
              localEleve.section  = serverEleve.section;
              localEleve.paid
                ..clear()
                ..addAll(serverEleve.paid);
              localEleve.transactions
                ..clear()
                ..addAll(serverEleve.transactions);
            } else {
              localEleves.add(serverEleve);
            }
          }
        } else {
          history[year] = serverYearData;
        }
      }
    }

    // ⚡ NOUVEAU — fusion des dépenses reçues du serveur (sans doublons,
    // en se basant sur l'id unique de chaque dépense).
    if (serverData['depensesByYear'] != null) {
      final serverDepenses =
      (serverData['depensesByYear'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map((e) => Depense.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );

      for (var entry in serverDepenses.entries) {
        final year       = entry.key;
        final serverList = entry.value;

        if (depensesByYear.containsKey(year)) {
          final existingIds =
          depensesByYear[year]!.map((d) => d.id).toSet();
          for (var d in serverList) {
            if (!existingIds.contains(d.id)) {
              depensesByYear[year]!.add(d);
            }
          }
        } else {
          depensesByYear[year] = serverList;
        }
      }
    }

    // ⚡ NOUVEAU — fusion des autres frais (types) reçus du serveur :
    // on ajoute simplement ceux qu'on n'a pas encore localement, en se
    // basant sur leur id. On ne touche pas à ceux qui existent déjà
    // localement (l'utilisateur a pu les supprimer volontairement).
    if (serverData['autresFrais'] != null) {
      final serverAutresFrais = (serverData['autresFrais'] as List<dynamic>)
          .map((e) => AutreFrais.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingFraisIds = autresFrais.map((f) => f.id).toSet();
      for (var f in serverAutresFrais) {
        if (!existingFraisIds.contains(f.id)) {
          autresFrais.add(f);
        }
      }
    }

    // ⚡ NOUVEAU — fusion des paiements d'autres frais reçus du serveur
    // (sans doublons, en se basant sur l'id unique de chaque paiement).
    if (serverData['autresFraisPaiementsByYear'] != null) {
      final serverPaiements = (serverData['autresFraisPaiementsByYear']
      as Map<String, dynamic>)
          .map(
            (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map((e) =>
              AutreFraisPaiement.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );

      for (var entry in serverPaiements.entries) {
        final year       = entry.key;
        final serverList = entry.value;

        if (autresFraisPaiementsByYear.containsKey(year)) {
          final existingIds =
          autresFraisPaiementsByYear[year]!.map((p) => p.id).toSet();
          for (var p in serverList) {
            if (!existingIds.contains(p.id)) {
              autresFraisPaiementsByYear[year]!.add(p);
            }
          }
        } else {
          autresFraisPaiementsByYear[year] = serverList;
        }
      }
    }

    // ⚡ NOUVEAU — le code masqué : on ne l'écrase JAMAIS silencieusement
    // s'il est déjà configuré sur cet appareil (pour éviter qu'une
    // restauration ne remplace le code choisi par l'admin sur place).
    // On ne l'adopte depuis le serveur que si cet appareil n'en a pas
    // encore — utile lors de la toute première restauration sur un
    // nouvel appareil.
    if (!hiddenCodeIsConfigured) {
      hiddenCodeHash =
          serverData['hiddenCodeHash'] as String? ?? hiddenCodeHash;
      hiddenCodeSalt =
          serverData['hiddenCodeSalt'] as String? ?? hiddenCodeSalt;
    }

    // ⚡ NOUVEAU — fusion du journal d'audit (sans doublons, par id).
    if (serverData['adminAuditLog'] != null) {
      final serverAudit = (serverData['adminAuditLog'] as List<dynamic>)
          .map((e) => AdminAuditLog.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingAuditIds = adminAuditLog.map((a) => a.id).toSet();
      for (var a in serverAudit) {
        if (!existingAuditIds.contains(a.id)) {
          adminAuditLog.add(a);
        }
      }
    }

    // ⚡ NOUVEAU — fusion des signataires reçus du serveur (sans
    // doublons, en se basant sur leur id).
    if (serverData['signataires'] != null) {
      final serverSignataires = (serverData['signataires'] as List<dynamic>)
          .map((e) => Signataire.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingSignataireIds = signataires.map((s) => s.id).toSet();
      for (var s in serverSignataires) {
        if (!existingSignataireIds.contains(s.id)) {
          signataires.add(s);
        }
      }
    }

    // ⚡ NOUVEAU — fusion des reçus déjà imprimés (union simple, sans
    // jamais retirer une clé locale) et de la file d'attente (on
    // n'ajoute que les clés qui ne sont ni déjà imprimées, ni déjà en
    // attente localement) — pour ne jamais réimprimer, sur cet
    // appareil, un reçu déjà sorti sur un autre appareil de la même
    // école.
    if (serverData['printedReceiptKeys'] != null) {
      final serverKeys = (serverData['printedReceiptKeys'] as List<dynamic>)
          .map((e) => e.toString());
      for (var k in serverKeys) {
        if (!printedReceiptKeys.contains(k)) {
          printedReceiptKeys.add(k);
        }
      }
    }
    if (serverData['receiptQueue'] != null) {
      final serverQueue = (serverData['receiptQueue'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map));
      for (var item in serverQueue) {
        final key = item['key']?.toString() ?? '';
        if (key.isEmpty || printedReceiptKeys.contains(key)) continue;
        final alreadyQueued = receiptQueue.any((r) => r['key'] == key);
        if (!alreadyQueued) {
          receiptQueue.add(item);
        }
      }
    }

    currentYear = serverData['currentYear'] ?? currentYear;
    if (history.containsKey(currentYear)) {
      currentData = history[currentYear]!;
    } else {
      currentData          = SchoolYearData(eleves: []);
      history[currentYear] = currentData;
    }

    await _assignMissingIds();
  }

  // ====================================================================
  // ⚡ NOUVEAU — MODULE DISCIPLINE
  // Centralise tous les appels réseau liés aux absences, convocations
  // et communiqués, sur le modèle de backupToServer/restoreFromServer
  // (retour Map avec 'success' + 'error' pour rester cohérent avec le
  // reste de l'appli).
  // ====================================================================

  /// Enregistre le registre d'absence d'une classe pour une date donnée
  /// et déclenche l'envoi automatique d'un message aux parents des
  /// élèves cochés absents.
  Future<Map<String, dynamic>> recordAbsences({
    required List<String> absentIds,
    required String classe,
    required String section,
    String? date,
    String? message,
    String recordedBy = 'Direction',
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {
        'success': false,
        'error': "Code école manquant. Sauvegardez d'abord sur le serveur "
            "(Paramètres) avant d'utiliser le module Discipline.",
      };
    }
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/school/record_absences'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCode,
          'annee':       currentYear,
          'classe':      classe,
          'section':     section,
          'date':        date ?? DateTime.now().toString().split(' ')[0],
          'absent_ids':  absentIds,
          'message':     message ?? '',
          'recorded_by': recordedBy,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'notified_count': data['notified_count'] ?? 0,
        };
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

  /// Récupère le registre déjà enregistré pour une classe/date, pour
  /// rouvrir l'écran sans perdre les cases déjà cochées.
  Future<Map<String, dynamic>> getAttendance({
    required String classe,
    String? date,
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {'success': false, 'absents': <String>[]};
    }
    try {
      final dateStr = date ?? DateTime.now().toString().split(' ')[0];
      final response = await http.get(
        Uri.parse('$serverUrl/school/get_attendance'
            '?school_code=$schoolCode&date=$dateStr'
            '&classe=${Uri.encodeComponent(classe)}'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'absents': List<String>.from(data['absents'] ?? []),
        };
      }
      return {'success': false, 'absents': <String>[]};
    } catch (_) {
      return {'success': false, 'absents': <String>[]};
    }
  }

  /// Envoie une convocation individuelle (comportement, discipline...)
  /// au parent d'un élève précis.
  Future<Map<String, dynamic>> sendConvocation({
    required String studentId,
    required String title,
    required String message,
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {'success': false, 'error': 'Code école manquant.'};
    }
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/school/send_convocation'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCode,
          'student_id':  studentId,
          'title':       title,
          'message':     message,
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return {'success': true};
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

  /// Envoie un communiqué aux parents, ciblé par élèves sélectionnés,
  /// par classe, par section, ou à toute l'école.
  Future<Map<String, dynamic>> sendAnnouncement({
    required String title,
    required String message,
    required String target, // 'all' | 'section' | 'classe' | 'students'
    String? classe,
    String? section,
    List<String>? studentIds,
  }) async {
    if (schoolCode == null || schoolCode!.isEmpty) {
      return {'success': false, 'error': 'Code école manquant.'};
    }
    try {
      final response = await http.post(
        Uri.parse('$serverUrl/school/send_announcement'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'school_code': schoolCode,
          'annee':       currentYear,
          'title':       title,
          'message':     message,
          'target':      target,
          'classe':      classe ?? '',
          'section':     section ?? '',
          'student_ids': studentIds ?? [],
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'notified_count': data['notified_count'] ?? 0,
        };
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
}