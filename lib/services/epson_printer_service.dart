import 'dart:io' show Platform, Process;
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

/// ⚡ Remplace bluetooth_printer_service.dart.
///
/// L'imprimante n'est plus une imprimante Bluetooth pilotée en port série
/// (COM), mais une Epson TM-T20III branchée en USB. Sous Windows, une fois
/// le pilote Epson officiel installé, l'imprimante apparaît comme une
/// imprimante Windows normale (ex: "EPSON TM-T20III Receipt").
///
/// On envoie les commandes ESC/POS brutes directement au spouleur Windows
/// en mode RAW (via winspool.drv), ce qui est la méthode standard et fiable
/// pour piloter une imprimante ticket sous Windows — équivalent Dart de ce
/// que fait python-escpos en interne. On n'a donc PAS besoin de connaître
/// le Vendor ID / Product ID USB : on cible l'imprimante par son nom Windows,
/// ce qui évite de devoir remplacer le pilote Epson par un pilote WinUSB
/// générique (qui casserait l'impression normale de l'imprimante).
///
/// ⚡ NOUVEAU — ÉCONOMIE DE PAPIER (reçu plus court)
/// À la demande de l'employeur : le reçu doit occuper le MOINS de papier
/// possible, sans qu'aucune information n'y soit retirée. Pour y arriver,
/// on a :
///   1. Combiné plusieurs informations sur une même ligne (2 colonnes)
///      au lieu d'une ligne par information (ex: "N° Reçu" + "ID Élève"
///      sur la même ligne, "Classe" + "Section" sur la même ligne,
///      "Date" + "Heure" sur la même ligne).
///   2. Supprimé les sauts de ligne vides purement décoratifs entre les
///      sections (feed(1) qui ne servaient qu'à aérer visuellement).
///   3. Réduit l'espace de signature (feed(2) → feed(1)) et la marge de
///      découpe en fin de reçu (feed(3) → feed(2)).
///   4. Réduit la taille de l'image d'en-tête (logo + nom de l'école) :
///      marges et hauteur de ligne plus petites, sans perdre de lisibilité
///      ni couper le nom de l'école.
/// Toutes les données affichées avant restent affichées — rien n'a été
/// retiré, seulement réorganisé et compacté.
class EscPosPrinterService {
  // ====================================================================
  // LISTER LES IMPRIMANTES INSTALLÉES SUR WINDOWS
  // ====================================================================
  static Future<List<String>> getAvailablePrinters() async {
    if (!Platform.isWindows) return [];
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-Printer | Select-Object -ExpandProperty Name',
        ],
        runInShell: true,
      );
      if (result.exitCode != 0) return [];
      final output = result.stdout.toString();
      return output
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ====================================================================
  // ENVOI DES OCTETS BRUTS AU SPOULEUR WINDOWS (MODE RAW)
  // ====================================================================
  // Cible l'imprimante par son NOM Windows (ex: "EPSON TM-T20III Receipt"),
  // pas par un identifiant USB. Fonctionne quelle que soit la connexion
  // physique de l'imprimante (USB, réseau, etc.) tant qu'elle est installée
  // comme imprimante Windows.
  static Future<bool> _sendRawBytes(
      String printerName, Uint8List data) async {
    if (!Platform.isWindows) return false;

    final printerNamePtr = printerName.toNativeUtf16();
    final phPrinter = calloc<IntPtr>();
    Pointer<Utf16> docNamePtr = nullptr;
    Pointer<Utf16> dataTypePtr = nullptr;
    Pointer<DOC_INFO_1> docInfo = nullptr;
    Pointer<Uint8> dataPtr = nullptr;
    Pointer<Uint32> bytesWritten = nullptr;

    try {
      final opened = OpenPrinter(printerNamePtr, phPrinter, nullptr);
      if (opened == 0) return false;
      final hPrinter = phPrinter.value;

      docNamePtr = 'Recu EduPay'.toNativeUtf16();
      dataTypePtr = 'RAW'.toNativeUtf16();
      docInfo = calloc<DOC_INFO_1>();
      docInfo.ref
        ..pDocName = docNamePtr
        ..pOutputFile = nullptr
        ..pDatatype = dataTypePtr;

      final docId = StartDocPrinter(hPrinter, 1, docInfo.cast());
      if (docId == 0) {
        ClosePrinter(hPrinter);
        return false;
      }

      StartPagePrinter(hPrinter);

      dataPtr = calloc<Uint8>(data.length);
      dataPtr.asTypedList(data.length).setAll(0, data);

      bytesWritten = calloc<Uint32>();
      final writeOk = WritePrinter(
        hPrinter,
        dataPtr.cast(),
        data.length,
        bytesWritten,
      );

      EndPagePrinter(hPrinter);
      EndDocPrinter(hPrinter);
      ClosePrinter(hPrinter);

      return writeOk != 0 && bytesWritten.value == data.length;
    } catch (_) {
      return false;
    } finally {
      calloc.free(printerNamePtr);
      calloc.free(phPrinter);
      if (docNamePtr != nullptr) calloc.free(docNamePtr);
      if (dataTypePtr != nullptr) calloc.free(dataTypePtr);
      if (docInfo != nullptr) calloc.free(docInfo);
      if (dataPtr != nullptr) calloc.free(dataPtr);
      if (bytesWritten != nullptr) calloc.free(bytesWritten);
    }
  }

  // ====================================================================
  // ⚡ EN-TÊTE COMPOSITE : LOGO GAUCHE + NOM CENTRÉ + LOGO DROITE
  // ====================================================================
  // Une imprimante thermique ne peut pas mélanger texte ESC/POS et image
  // sur la même ligne physique. Pour avoir "logo — nom de l'école — logo"
  // sur une même ligne comme demandé, on construit donc UNE SEULE image
  // bitmap (logo dupliqué à gauche et à droite, nom du texte dessiné
  // dessus, bien centré), qu'on imprime ensuite comme un seul bloc image.
  //
  // Si le nom est trop long pour tenir entre les deux logos, la première
  // partie qui rentre reste sur la ligne du logo, et le reste du nom
  // s'affiche sur une ou plusieurs lignes en dessous, centrées sur toute
  // la largeur du reçu.
  //
  // ⚡ CORRIGÉ (économie de papier) — marges et hauteur de ligne réduites
  // par rapport à avant (margin 8→6, logoBox 82→60, lineHeight 30→24),
  // pour un en-tête plus compact sans perdre le logo ni le nom complet.
  static const int _headerWidth = 380;

  static img.Image _buildReceiptHeaderImage({
    required String schoolName,
    required Uint8List logoBytes,
  }) {
    const int margin  = 6;
    const int logoBox = 60;
    final font = img.arial24;

    final int textZoneLeft  = margin + logoBox + margin;
    final int textZoneRight = _headerWidth - margin - logoBox - margin;
    final int textZoneWidth =
    (textZoneRight - textZoneLeft).clamp(40, _headerWidth);

    // ---- Logo : décodage + redimensionnement dans un carré logoBox ----
    img.Image? logo;
    try {
      final decoded = img.decodeImage(logoBytes);
      if (decoded != null) {
        logo = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: logoBox)
            : img.copyResize(decoded, height: logoBox);
        if (logo.width > logoBox || logo.height > logoBox) {
          logo = logo.width >= logo.height
              ? img.copyResize(logo, width: logoBox)
              : img.copyResize(logo, height: logoBox);
        }
      }
    } catch (_) {
      logo = null;
    }

    // ---- Découpage du nom : 1ère partie entre les logos, le reste dessous
    final words = schoolName.trim().split(RegExp(r'\s+'));
    String firstLine = '';
    int cut = words.length;
    for (int i = 0; i < words.length; i++) {
      final candidate =
      firstLine.isEmpty ? words[i] : '$firstLine ${words[i]}';
      if (_textWidth(font, candidate) <= textZoneWidth ||
          firstLine.isEmpty) {
        firstLine = candidate;
        cut = i + 1;
      } else {
        cut = i;
        break;
      }
    }
    final remainingWords = words.sublist(cut.clamp(0, words.length));

    final List<String> extraLines = [];
    if (remainingWords.isNotEmpty) {
      final fullWidth = _headerWidth - 2 * margin;
      String line = '';
      for (final w in remainingWords) {
        final candidate = line.isEmpty ? w : '$line $w';
        if (_textWidth(font, candidate) <= fullWidth || line.isEmpty) {
          line = candidate;
        } else {
          extraLines.add(line);
          line = w;
        }
      }
      if (line.isNotEmpty) extraLines.add(line);
    }

    const int lineHeight   = 24;
    final int topRowHeight = logo != null ? logoBox : 32;
    final int extraHeight  =
    extraLines.isEmpty ? 0 : (extraLines.length * lineHeight) + 4;
    final int headerHeight = (margin * 2) + topRowHeight + extraHeight;

    final canvas = img.Image(width: _headerWidth, height: headerHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    // Logo gauche + logo droite (même image des deux côtés)
    if (logo != null) {
      final ly = margin + ((topRowHeight - logo.height) ~/ 2);
      img.compositeImage(canvas, logo, dstX: margin, dstY: ly);
      img.compositeImage(
        canvas, logo,
        dstX: _headerWidth - margin - logo.width,
        dstY: ly,
      );
    }

    // Première ligne du nom, centrée entre les deux logos
    final safeFirst  = _safeText(firstLine);
    final firstWidth = _textWidth(font, safeFirst);
    final fx = textZoneLeft +
        (((textZoneWidth - firstWidth) / 2).round())
            .clamp(0, textZoneWidth);
    final fy = margin + ((topRowHeight - 24) / 2).round();
    img.drawString(canvas, safeFirst,
        font: font, x: fx, y: fy, color: img.ColorRgb8(0, 0, 0));

    // Lignes suivantes (reste du nom), centrées sur toute la largeur
    int ey = margin + topRowHeight + 4;
    for (final line in extraLines) {
      final safeLine = _safeText(line);
      final w = _textWidth(font, safeLine);
      final ex =
      (((_headerWidth - w) / 2).round()).clamp(0, _headerWidth);
      img.drawString(canvas, safeLine,
          font: font, x: ex, y: ey, color: img.ColorRgb8(0, 0, 0));
      ey += lineHeight;
    }

    return canvas;
  }

  /// Largeur en pixels d'un texte pour une police bitmap donnée (même
  /// logique que celle utilisée en interne par drawString, pour pouvoir
  /// centrer nous-mêmes le texte avant de l'imprimer sur l'image).
  static int _textWidth(img.BitmapFont font, String text) {
    int width = 0;
    for (final c in text.codeUnits) {
      final ch = font.characters[c];
      if (ch == null) continue;
      width += ch.xAdvance;
    }
    return width;
  }

  /// Les polices bitmap intégrées à la librairie `image` ne couvrent pas
  /// forcément tous les caractères accentués français. On remplace ceux
  /// qui manqueraient par leur équivalent non accentué, pour ne jamais
  /// perdre silencieusement une lettre à l'impression (mieux vaut
  /// "Ecole" que "cole").
  static String _safeText(String text) {
    const replacements = {
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
      'à': 'a', 'â': 'a', 'ä': 'a',
      'À': 'A', 'Â': 'A', 'Ä': 'A',
      'î': 'i', 'ï': 'i', 'Î': 'I', 'Ï': 'I',
      'ô': 'o', 'ö': 'o', 'Ô': 'O', 'Ö': 'O',
      'ù': 'u', 'û': 'u', 'ü': 'u', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
      'ç': 'c', 'Ç': 'C',
      'œ': 'oe', 'Œ': 'OE',
      'ñ': 'n', 'Ñ': 'N',
    };
    final buffer = StringBuffer();
    for (final char in text.split('')) {
      final hasGlyph =
      img.arial24.characters.containsKey(char.codeUnitAt(0));
      buffer.write(hasGlyph ? char : (replacements[char] ?? char));
    }
    return buffer.toString();
  }

  // ====================================================================
  // GÉNÉRER ET IMPRIMER UN REÇU COMPLET (paiement mensuel principal)
  // ====================================================================
  // ⚡ CORRIGÉ (économie de papier) — mise en page compactée :
  //   - "N° Reçu" et "ID Élève" sur la même ligne (au lieu de 2 lignes)
  //   - "Classe" et "Section" sur la même ligne (au lieu de 2 lignes)
  //   - "Date" et "Heure" sur la même ligne (au lieu de 2 lignes)
  //   - Suppression des feed(1) purement décoratifs entre les blocs
  //   - Espace de signature réduit (feed(2) → feed(1))
  //   - Marge de découpe finale réduite (feed(3) → feed(2))
  // Toutes les informations affichées avant sont toujours présentes.
  static Future<bool> printReceipt({
    required String printerName,
    required String schoolName,
    required String currentYear,
    required String studentName,
    required String studentId,
    required String classe,
    required String section,
    required String moisPaye,
    required double montantPaye,
    required double montantRequis,
    required double resteAPayerMois,
    required double totalDejaPayeAnnee,
    required double totalRequis,
    required List<Map<String, dynamic>> historiqueTransactions,
    String? receiptNumber, // Numéro de reçu (généré automatiquement si null)
    Uint8List? logoBytes,  // ⚡ Logo choisi dans les Paramètres (optionnel)
  }) async {
    if (!Platform.isWindows) return false;

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      // Table de caractères pour les accents français (é, è, à, ç...)
      generator.setGlobalCodeTable('CP1252');

      final now = DateTime.now();
      final String today =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final String heure =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      // Numéro de reçu (auto si non fourni)
      final String numRecu = receiptNumber ??
          'RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour}${now.minute}${now.second}';

      // ==================== EN-TÊTE ÉCOLE ====================
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );

      if (logoBytes != null) {
        // ⚡ Logo gauche + nom centré + logo droite, sur une seule image.
        try {
          final headerImage = _buildReceiptHeaderImage(
            schoolName: schoolName,
            logoBytes: logoBytes,
          );
          bytes += generator.image(headerImage);
        } catch (_) {
          // Si la construction de l'image échoue pour une raison
          // quelconque (logo corrompu, etc.), on retombe sur le texte
          // simple pour ne jamais bloquer l'impression du reçu.
          bytes += generator.text(
            schoolName.toUpperCase(),
            styles: const PosStyles(
              align: PosAlign.center,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2,
            ),
          );
        }
      } else {
        bytes += generator.text(
          schoolName.toUpperCase(),
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        );
      }

      bytes += generator.text(
        'REÇU DE PAIEMENT',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          underline: true,
        ),
      );
      bytes += generator.text(
        'Année scolaire : $currentYear',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );

      // ==================== NOM COMPLET ÉLÈVE (TOUT EN HAUT) ====================
      bytes += generator.text(
        'Nom complet :',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      );
      bytes += generator.text(
        '................................',
        styles: const PosStyles(align: PosAlign.center),
      );

      // ==================== INFOS ÉLÈVE (compactées 2 par ligne) ====================
      bytes += generator.row([
        PosColumn(
          text: 'Reçu : $numRecu',
          width: 12,
          styles: const PosStyles(bold: true, fontType: PosFontType.fontB),
        ),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'ID : $studentId',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: 'Cl. : $classe',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Sect. : $section',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: '$today $heure',
          width: 6,
          styles: const PosStyles(bold: true, fontType: PosFontType.fontB),
        ),
      ]);

      // ==================== PAIEMENT ====================
      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.row([
        PosColumn(
          text: 'Mois payé :',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: moisPaye,
          width: 6,
          styles: const PosStyles(bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Montant payé :',
          width: 7,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: '${montantPaye.toStringAsFixed(0)} FC',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
      ]);

      if (resteAPayerMois > 0) {
        bytes += generator.row([
          PosColumn(
            text: 'Reste à payer :',
            width: 7,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: '${resteAPayerMois.toStringAsFixed(0)} FC',
            width: 5,
            styles: const PosStyles(bold: true),
          ),
        ]);
      } else {
        bytes += generator.text(
          '>>> MOIS COMPLÈTEMENT PAYÉ <<<',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
      }
      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );

      // ==================== SIGNATURE ====================
      bytes += generator.text(
        'Signature :',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.feed(1);
      bytes += generator.text(
        '................................',
        styles: const PosStyles(align: PosAlign.center),
      );

      // ==================== PIED DE PAGE ====================
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        'Merci pour votre paiement !',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        'Conservez ce reçu.',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.feed(2);
      bytes += generator.cut();

      return await _sendRawBytes(printerName, Uint8List.fromList(bytes));
    } catch (_) {
      return false;
    }
  }

  // ====================================================================
  // ⚡ PETIT REÇU POUR UN "AUTRE FRAIS" (frais éphémère)
  // Volontairement plus court que le reçu de paiement mensuel : nom de
  // l'école, titre du frais (ex: "Frais de l'État"), nom de l'élève,
  // classe, date de paiement, montant, et une ligne signature.
  //
  // ⚡ CORRIGÉ (économie de papier) — "Classe" et "Section" combinées sur
  // une même ligne, feed(2) de signature réduit à feed(1), même principe
  // que pour printReceipt. Aucune information retirée.
  // ====================================================================
  static Future<bool> printAutreFraisReceipt({
    required String printerName,
    required String schoolName,
    required String titreFrais,
    required String studentName,
    required String classe,
    required String section,
    required double montant,
  }) async {
    if (!Platform.isWindows) return false;

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      generator.setGlobalCodeTable('CP1252');

      final now = DateTime.now();
      final String today =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final String heure =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        schoolName.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        titreFrais.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          underline: true,
        ),
      );
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );

      bytes += generator.text(
        'Nom complet :',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size1,
        ),
      );

      bytes += generator.row([
        PosColumn(
          text: 'Cl. : $classe',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: 'Sect. : $section',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Date :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: '$today $heure', width: 7),
      ]);

      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.row([
        PosColumn(
          text: 'Montant payé :',
          width: 7,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: '${montant.toStringAsFixed(0)} FC',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
      ]);
      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );

      bytes += generator.text(
        'Signature :',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.feed(1);
      bytes += generator.text(
        '................................',
        styles: const PosStyles(align: PosAlign.center),
      );

      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        'Merci pour votre paiement !',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.feed(2);
      bytes += generator.cut();

      return await _sendRawBytes(printerName, Uint8List.fromList(bytes));
    } catch (_) {
      return false;
    }
  }
}