import 'dart:convert';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// RÉGLAGES DE MISE EN FORME DES REÇUS
// ----------------------------------------------------------------------------
// Ce fichier ne contient AUCUNE communication avec l'imprimante. Il décrit
// seulement l'apparence des reçus (tailles, logos, informations de l'élève).
// Les réglages sont enregistrés sur l'appareil (SharedPreferences).
// ============================================================================

const String kReceiptPresetClassic = 'classic'; // première version (compacte)
const String kReceiptPresetLarge = 'large'; // version actuelle (gros caractères)
const String kReceiptPresetCustom = 'custom'; // personnalisé (experts)

// Codes de taille d'une zone de texte
const int kSizeNormal = 0;
const int kSizeHaut = 1; // x2 en hauteur
const int kSizeLarge = 2; // x2 en largeur
const int kSizeTresGrand = 3; // x2 en hauteur et largeur
const int kSizePetit = 4; // police B (petite)

PosStyles styleForSizeCode(
    int code, {
      bool bold = true,
      PosAlign align = PosAlign.left,
      bool underline = false,
    }) {
  switch (code) {
    case kSizeHaut:
      return PosStyles(
        bold: bold,
        underline: underline,
        align: align,
        height: PosTextSize.size2,
      );
    case kSizeLarge:
      return PosStyles(
        bold: bold,
        underline: underline,
        align: align,
        width: PosTextSize.size2,
      );
    case kSizeTresGrand:
      return PosStyles(
        bold: bold,
        underline: underline,
        align: align,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      );
    case kSizePetit:
      return PosStyles(
        bold: bold,
        underline: underline,
        align: align,
        fontType: PosFontType.fontB,
      );
    default:
      return PosStyles(bold: bold, underline: underline, align: align);
  }
}

class ReceiptLayoutSettings {
  /// 'classic' | 'large' | 'custom'
  String preset = kReceiptPresetLarge;

  /// Modèle de départ du mode personnalisé.
  String customBase = kReceiptPresetLarge;

  // ---- Informations de l'élève à imprimer (valables pour TOUS les modes) ----
  bool showAdresse = false;
  bool showPere = false;
  bool showMere = false;
  bool showDateNaissance = false;
  List<String> champsPerso = <String>[];

  // ---- Mode personnalisé ----
  int zoneSchool = 3; // nom de l'école (quand pas de logo)
  int zoneTitle = 1; // titre du reçu
  int zoneName = -1; // nom de l'élève (-1 = automatique)
  int zoneBody = 1; // lignes courantes (0 ou 1)
  int zoneTotals = 1; // totaux (0 ou 1)
  int zoneDetails = 1; // dates, n° de reçu (0, 1 ou 4=petit)
  int zoneSignature = 3; // libellé « Signature »
  bool bold = true;
  int cols = 42; // caractères par ligne des séparateurs
  int signatureFeed = 7; // lignes vides pour signature + cachet
  int logoCount = 2; // 0 à 3
  int logoBox = 110; // taille d'un logo en points
  int headerWidth = 512; // largeur de l'en-tête en points
  bool signatureOnHistory = true;
  bool showMerci = true;
  bool showConserver = true;
  bool bigSchoolName = true;

  bool _charge = false;
  static const String _cleStockage = 'receipt_layout_v1';

  ReceiptLayoutSettings();

  factory ReceiptLayoutSettings.fromJson(Map<String, dynamic> j) =>
      ReceiptLayoutSettings().._lire(j);

  bool get afficherInfosSup =>
      showAdresse ||
          showPere ||
          showMere ||
          showDateNaissance ||
          champsPerso.isNotEmpty;

  /// Copie les valeurs d'un des deux formats par défaut dans le mode
  /// personnalisé (point de départ de l'expert).
  void appliquerBase(String base) {
    customBase = base;
    if (base == kReceiptPresetClassic) {
      zoneSchool = 3;
      zoneTitle = 0;
      zoneName = 1;
      zoneBody = 0;
      zoneTotals = 1;
      zoneDetails = 4;
      zoneSignature = 0;
      bold = true;
      cols = 32;
      signatureFeed = 1;
      logoCount = 2;
      logoBox = 60;
      headerWidth = 380;
      signatureOnHistory = false;
    } else {
      zoneSchool = 3;
      zoneTitle = 1;
      zoneName = -1;
      zoneBody = 1;
      zoneTotals = 1;
      zoneDetails = 1;
      zoneSignature = 3;
      bold = true;
      cols = 42;
      signatureFeed = 7;
      logoCount = 2;
      logoBox = 110;
      headerWidth = 512;
      signatureOnHistory = true;
    }
    showMerci = true;
    showConserver = true;
    bigSchoolName = true;
  }

  void copierDepuis(ReceiptLayoutSettings autre) => _lire(autre.toJson());

  Map<String, dynamic> toJson() => {
    'preset': preset,
    'customBase': customBase,
    'showAdresse': showAdresse,
    'showPere': showPere,
    'showMere': showMere,
    'showDateNaissance': showDateNaissance,
    'champsPerso': champsPerso,
    'zoneSchool': zoneSchool,
    'zoneTitle': zoneTitle,
    'zoneName': zoneName,
    'zoneBody': zoneBody,
    'zoneTotals': zoneTotals,
    'zoneDetails': zoneDetails,
    'zoneSignature': zoneSignature,
    'bold': bold,
    'cols': cols,
    'signatureFeed': signatureFeed,
    'logoCount': logoCount,
    'logoBox': logoBox,
    'headerWidth': headerWidth,
    'signatureOnHistory': signatureOnHistory,
    'showMerci': showMerci,
    'showConserver': showConserver,
    'bigSchoolName': bigSchoolName,
  };

  int _entier(dynamic v, int defaut, int min, int max) {
    if (v is num) {
      final int n = v.toInt();
      if (n < min) return min;
      if (n > max) return max;
      return n;
    }
    return defaut;
  }

  bool _bool(dynamic v, bool defaut) => v is bool ? v : defaut;

  void _lire(Map<String, dynamic> j) {
    final String p = j['preset']?.toString() ?? preset;
    preset = (p == kReceiptPresetClassic ||
        p == kReceiptPresetLarge ||
        p == kReceiptPresetCustom)
        ? p
        : kReceiptPresetLarge;
    final String b = j['customBase']?.toString() ?? customBase;
    customBase =
    b == kReceiptPresetClassic ? kReceiptPresetClassic : kReceiptPresetLarge;

    showAdresse = _bool(j['showAdresse'], showAdresse);
    showPere = _bool(j['showPere'], showPere);
    showMere = _bool(j['showMere'], showMere);
    showDateNaissance = _bool(j['showDateNaissance'], showDateNaissance);
    if (j['champsPerso'] is List) {
      champsPerso = (j['champsPerso'] as List)
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    zoneSchool = _entier(j['zoneSchool'], zoneSchool, 0, 3);
    zoneTitle = _entier(j['zoneTitle'], zoneTitle, 0, 3);
    zoneName = _entier(j['zoneName'], zoneName, -1, 3);
    zoneBody = _entier(j['zoneBody'], zoneBody, 0, 1);
    zoneTotals = _entier(j['zoneTotals'], zoneTotals, 0, 1);
    int details = _entier(j['zoneDetails'], zoneDetails, 0, 4);
    if (details != 0 && details != 1 && details != 4) details = 1;
    zoneDetails = details;
    zoneSignature = _entier(j['zoneSignature'], zoneSignature, 0, 3);
    bold = _bool(j['bold'], bold);
    cols = _entier(j['cols'], cols, 28, 48);
    signatureFeed = _entier(j['signatureFeed'], signatureFeed, 0, 15);
    logoCount = _entier(j['logoCount'], logoCount, 0, 3);
    logoBox = _entier(j['logoBox'], logoBox, 40, 160);
    headerWidth = _entier(j['headerWidth'], headerWidth, 300, 576);
    signatureOnHistory = _bool(j['signatureOnHistory'], signatureOnHistory);
    showMerci = _bool(j['showMerci'], showMerci);
    showConserver = _bool(j['showConserver'], showConserver);
    bigSchoolName = _bool(j['bigSchoolName'], bigSchoolName);
  }

  Future<void> charger({bool force = false}) async {
    if (_charge && !force) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? brut = prefs.getString(_cleStockage);
      if (brut != null && brut.isNotEmpty) {
        final d = json.decode(brut);
        if (d is Map) _lire(Map<String, dynamic>.from(d));
      }
    } catch (_) {
      // Problème de lecture : on garde les valeurs par défaut (format actuel).
    }
    _charge = true;
  }

  Future<bool> sauvegarder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_cleStockage, json.encode(toJson()));
    } catch (_) {
      return false;
    }
  }
}

/// Instance unique utilisée par toute l'application.
final ReceiptLayoutSettings receiptLayout = ReceiptLayoutSettings();

// ============================================================================
// THÈME DE REÇU : traduit les réglages en styles ESC/POS
// ============================================================================
class ReceiptTheme {
  final int cols;
  final int signatureFeed;
  final int headerWidth;
  final int logoBox;
  final int lineHeight;
  final int logoCount;
  final int dateLabelWidth;
  final bool signatureOnHistory;
  final bool showMerci;
  final bool showConserver;
  final bool bigSchoolName;
  final bool monthHeight;
  final bool monthBold;
  final String signatureLabel;

  final PosStyles row;
  final PosStyles rowRight;
  final PosStyles amountSingle;
  final PosStyles strong;
  final PosStyles strongRight;
  final PosStyles center;
  final PosStyles bodyCenter;
  final PosStyles label;
  final PosStyles small;
  final PosStyles detail;
  final PosStyles dateValue;
  final PosStyles conserver;
  final PosStyles historyLeft;
  final PosStyles empty;
  final PosStyles signature;

  final PosStyles Function(String) titleFor;
  final PosStyles Function(String) schoolFor;
  final PosStyles Function(String) nameStyle;

  ReceiptTheme._({
    required this.cols,
    required this.signatureFeed,
    required this.headerWidth,
    required this.logoBox,
    required this.lineHeight,
    required this.logoCount,
    required this.dateLabelWidth,
    required this.signatureOnHistory,
    required this.showMerci,
    required this.showConserver,
    required this.bigSchoolName,
    required this.monthHeight,
    required this.monthBold,
    required this.signatureLabel,
    required this.row,
    required this.rowRight,
    required this.amountSingle,
    required this.strong,
    required this.strongRight,
    required this.center,
    required this.bodyCenter,
    required this.label,
    required this.small,
    required this.detail,
    required this.dateValue,
    required this.conserver,
    required this.historyLeft,
    required this.empty,
    required this.signature,
    required this.titleFor,
    required this.schoolFor,
    required this.nameStyle,
  });

  /// Style d'une ligne « mois » du bilan financier.
  PosStyles monthStyle(bool bold, {PosAlign align = PosAlign.left}) {
    return PosStyles(
      bold: monthBold && bold,
      height: monthHeight ? PosTextSize.size2 : PosTextSize.size1,
      align: align,
    );
  }

  static ReceiptTheme fromSettings(ReceiptLayoutSettings s) {
    switch (s.preset) {
      case kReceiptPresetClassic:
        return ReceiptTheme.classic();
      case kReceiptPresetCustom:
        return ReceiptTheme.custom(s);
      default:
        return ReceiptTheme.large();
    }
  }

  // --------------------------------------------------------------------------
  // FORMAT 1 : PREMIÈRE VERSION (compacte) — reproduit à l'identique
  // --------------------------------------------------------------------------
  factory ReceiptTheme.classic() {
    return ReceiptTheme._(
      cols: 32,
      signatureFeed: 1,
      headerWidth: 380,
      logoBox: 60,
      lineHeight: 24,
      logoCount: 2,
      dateLabelWidth: 5,
      signatureOnHistory: false,
      showMerci: true,
      showConserver: true,
      bigSchoolName: true,
      monthHeight: false,
      monthBold: true,
      signatureLabel: 'Signature :',
      row: const PosStyles(bold: true),
      rowRight: const PosStyles(bold: true, align: PosAlign.right),
      amountSingle: const PosStyles(bold: true),
      strong: const PosStyles(bold: true, height: PosTextSize.size2),
      strongRight: const PosStyles(
          bold: true, height: PosTextSize.size2, align: PosAlign.right),
      center: const PosStyles(align: PosAlign.center),
      bodyCenter: const PosStyles(align: PosAlign.center, bold: true),
      label: const PosStyles(bold: true),
      small: const PosStyles(bold: true, fontType: PosFontType.fontB),
      detail: const PosStyles(fontType: PosFontType.fontB),
      dateValue: const PosStyles(),
      conserver: const PosStyles(align: PosAlign.center),
      historyLeft: const PosStyles(),
      empty: const PosStyles(align: PosAlign.center),
      signature: const PosStyles(bold: true),
      titleFor: (_) => const PosStyles(
        align: PosAlign.center,
        bold: true,
        underline: true,
      ),
      schoolFor: (_) => const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      nameStyle: (_) => const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // FORMAT 2 : VERSION ACTUELLE (gros caractères) — reproduit à l'identique
  // --------------------------------------------------------------------------
  factory ReceiptTheme.large() {
    const int cols = 42;
    return ReceiptTheme._(
      cols: cols,
      signatureFeed: 7,
      headerWidth: 512,
      logoBox: 110,
      lineHeight: 28,
      logoCount: 2,
      dateLabelWidth: 4,
      signatureOnHistory: true,
      showMerci: true,
      showConserver: true,
      bigSchoolName: true,
      monthHeight: true,
      monthBold: true,
      signatureLabel: 'Signature / Cachet :',
      row: const PosStyles(bold: true, height: PosTextSize.size2),
      rowRight: const PosStyles(
          bold: true, height: PosTextSize.size2, align: PosAlign.right),
      amountSingle: const PosStyles(
          bold: true, height: PosTextSize.size2, align: PosAlign.right),
      strong: const PosStyles(bold: true, height: PosTextSize.size2),
      strongRight: const PosStyles(
          bold: true, height: PosTextSize.size2, align: PosAlign.right),
      center: const PosStyles(align: PosAlign.center),
      bodyCenter: const PosStyles(
          bold: true, height: PosTextSize.size2, align: PosAlign.center),
      label: const PosStyles(bold: true, height: PosTextSize.size2),
      small: const PosStyles(bold: true, height: PosTextSize.size2),
      detail: const PosStyles(height: PosTextSize.size2),
      dateValue: const PosStyles(bold: true, height: PosTextSize.size2),
      conserver: const PosStyles(
          align: PosAlign.center, height: PosTextSize.size2),
      historyLeft: const PosStyles(height: PosTextSize.size2),
      empty:
      const PosStyles(align: PosAlign.center, height: PosTextSize.size2),
      signature: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      titleFor: (_) => const PosStyles(
        align: PosAlign.center,
        bold: true,
        underline: true,
        height: PosTextSize.size2,
      ),
      schoolFor: (_) => const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      nameStyle: (String name) {
        if (name.length <= (cols ~/ 2)) {
          return const PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          );
        }
        return const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // FORMAT 3 : PERSONNALISÉ (experts)
  // --------------------------------------------------------------------------
  factory ReceiptTheme.custom(ReceiptLayoutSettings s) {
    final bool b = s.bold;
    final int cols = s.cols.clamp(28, 48);
    final int half = cols ~/ 2;

    PosStyles st(int code,
        {bool bold = true,
          PosAlign align = PosAlign.left,
          bool underline = false}) =>
        styleForSizeCode(code, bold: bold, align: align, underline: underline);

    // Une taille « large » est automatiquement réduite si le texte est trop
    // long pour tenir sur la ligne (évite les retours à la ligne).
    PosStyles adaptive(int code, String text,
        {bool bold = true,
          PosAlign align = PosAlign.left,
          bool underline = false}) {
      int c = code;
      if ((c == kSizeLarge || c == kSizeTresGrand) && text.length > half) {
        c = (c == kSizeTresGrand) ? kSizeHaut : kSizeNormal;
      }
      return st(c, bold: bold, align: align, underline: underline);
    }

    final int body = s.zoneBody == kSizeHaut ? kSizeHaut : kSizeNormal;
    final int totals = s.zoneTotals == kSizeHaut ? kSizeHaut : kSizeNormal;
    final int details =
    (s.zoneDetails == kSizeHaut || s.zoneDetails == kSizePetit)
        ? s.zoneDetails
        : kSizeNormal;

    final PosStyles centerPlain = const PosStyles(align: PosAlign.center);

    return ReceiptTheme._(
      cols: cols,
      signatureFeed: s.signatureFeed,
      headerWidth: s.headerWidth,
      logoBox: s.logoBox,
      lineHeight: 28,
      logoCount: s.logoCount,
      dateLabelWidth: body == kSizeNormal ? 5 : 4,
      signatureOnHistory: s.signatureOnHistory,
      showMerci: s.showMerci,
      showConserver: s.showConserver,
      bigSchoolName: s.bigSchoolName,
      monthHeight: body == kSizeHaut,
      monthBold: b,
      signatureLabel:
      s.signatureFeed >= 3 ? 'Signature / Cachet :' : 'Signature :',
      row: st(body, bold: b),
      rowRight: st(body, bold: b, align: PosAlign.right),
      amountSingle: st(body, bold: b, align: PosAlign.right),
      strong: st(totals, bold: b),
      strongRight: st(totals, bold: b, align: PosAlign.right),
      center: centerPlain,
      bodyCenter: st(body, bold: b, align: PosAlign.center),
      label: st(body, bold: b),
      small: st(details, bold: b),
      detail: st(details, bold: false),
      dateValue: st(body, bold: b),
      conserver: st(body, bold: false, align: PosAlign.center),
      historyLeft: st(body, bold: false),
      empty: st(body, bold: false, align: PosAlign.center),
      signature: st(s.zoneSignature, bold: b),
      titleFor: (String text) => adaptive(s.zoneTitle, text,
          bold: b, align: PosAlign.center, underline: true),
      schoolFor: (String text) =>
          adaptive(s.zoneSchool, text, bold: b, align: PosAlign.center),
      nameStyle: (String name) {
        if (s.zoneName == -1) {
          return name.length <= half
              ? st(kSizeTresGrand, bold: b)
              : st(kSizeHaut, bold: b);
        }
        return adaptive(s.zoneName, name, bold: b);
      },
    );
  }
}