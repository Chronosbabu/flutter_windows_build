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
/// ⚡ ÉCONOMIE DE PAPIER (reçu plus court)
/// À la demande de l'employeur : le reçu doit occuper le MOINS de papier
/// possible, sans qu'aucune information n'y soit retirée. Pour y arriver :
///   1. Plusieurs informations combinées sur une même ligne (2 colonnes)
///      au lieu d'une ligne par information.
///   2. Suppression des sauts de ligne vides purement décoratifs.
///   3. Espace de signature et marge de découpe réduits.
///   4. En-tête (logo + nom) plus compact (marges réduites).
///
/// ⚡ NOUVEAU — LISIBILITÉ DU LOGO ET DU NOM DE L'ÉCOLE
/// À la demande de l'employeur : le logo était flou et le nom de l'école
/// pas assez visible par rapport au nom de l'élève. Deux correctifs :
///   1. Le logo est maintenant redimensionné avec une interpolation de
///      qualité (cubique en agrandissement, moyenne en réduction), puis
///      converti en noir et blanc net à fort contraste — au lieu de
///      laisser l'imprimante le tramer en niveaux de gris (ce qui le
///      rendait flou/grisâtre sur du papier thermique).
///   2. Le nom de l'école est dessiné avec une police bien plus grande
///      (arial48 au lieu d'arial24) et en gras simulé (le trait est
///      épaissi), MAIS uniquement lorsque le nom tient entier sur la
///      ligne du logo — ce qui est le cas normal — pour ne JAMAIS
///      augmenter la hauteur du reçu. Si un nom est exceptionnellement
///      trop long pour cette police agrandie, l'ancien comportement
///      (police normale + retour à la ligne si besoin) reprend
///      automatiquement, pour ne jamais rien couper.
///
/// ⚡ NOUVEAU — RÉIMPRESSION MANUELLE (reçus perdus / mémoire d'impression
/// perdue si l'ordinateur s'éteint avant que l'imprimante ne soit
/// rebranchée)
/// En plus de `printReceipt` (impression AUTOMATIQUE d'UN SEUL mois juste
/// après un paiement — comportement inchangé et toujours utilisé tel
/// quel) et de `printAutreFraisReceipt` (impression AUTOMATIQUE d'UN SEUL
/// "autre frais" juste après son paiement — comportement inchangé), on
/// ajoute deux méthodes génériques qui acceptent une LISTE de paiements
/// déjà enregistrés et les impriment TOUS sur UN SEUL reçu :
///   - `printTransactionsReceipt` pour les mois du frais scolaire
///     principal (réimpression d'un seul paiement, d'une sélection, ou de
///     tout l'historique d'un élève).
///   - `printAutresFraisTransactionsReceipt` pour les "autres frais"
///     (Frais de l'État, Frais d'Aide...), même logique.
/// Ces deux méthodes sont aussi utilisées par le Dashboard Admin pour
/// imprimer automatiquement, après validation d'un lot de paiements
/// envoyés par un sous-utilisateur, UN SEUL reçu par élève regroupant
/// tout ce qu'il vient de payer (même si plusieurs mois ou plusieurs
/// frais d'un coup).
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
  // ⚡ NOUVEAU — PRÉPARATION DU LOGO POUR UNE IMPRESSION NETTE
  // ====================================================================
  // Une imprimante thermique n'a que 2 niveaux (noir/blanc). Envoyer une
  // image en niveaux de gris ou en couleur oblige le générateur ESC/POS à
  // faire du tramage (dithering) pour approximer les gris avec des points
  // noirs/blancs — c'est ce qui rendait le logo flou et grisâtre. On
  // convertit donc nous-mêmes le logo en noir et blanc NET (avec un
  // contraste renforcé avant seuillage), pour que chaque pixel envoyé à
  // l'imprimante soit déjà une décision claire noir/blanc — beaucoup plus
  // net qu'un tramage automatique, surtout pour un logo simple (texte,
  // formes, contours).
  static img.Image _prepareLogoForPrint(Uint8List logoBytes, int targetSize) {
    final decoded = img.decodeImage(logoBytes);
    if (decoded == null) {
      throw Exception('Logo illisible');
    }

    // ---- Redimensionnement avec une interpolation de qualité ----
    // Cubique en agrandissement (image source plus petite que la cible) :
    // lisse les bords sans les rendre flous.
    // Moyenne en réduction (image source plus grande que la cible) :
    // évite le moiré/l'aliasing qui donne un rendu "sale" une fois tramé.
    final bool sourceIsSmaller =
        decoded.width < targetSize && decoded.height < targetSize;
    final img.Interpolation interp =
    sourceIsSmaller ? img.Interpolation.cubic : img.Interpolation.average;

    img.Image resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: targetSize, interpolation: interp)
        : img.copyResize(decoded, height: targetSize, interpolation: interp);

    if (resized.width > targetSize || resized.height > targetSize) {
      resized = resized.width >= resized.height
          ? img.copyResize(resized,
          width: targetSize, interpolation: img.Interpolation.average)
          : img.copyResize(resized,
          height: targetSize, interpolation: img.Interpolation.average);
    }

    // ---- Conversion en noir/blanc net à fort contraste ----
    final gray = img.grayscale(resized);
    img.adjustColor(gray, contrast: 1.45);

    final out = img.Image(width: gray.width, height: gray.height);
    for (final pixel in gray) {
      final int lum = pixel.r.toInt();
      final int v = lum < 150 ? 0 : 255;
      out.setPixelRgb(pixel.x, pixel.y, v, v, v);
    }
    return out;
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
  // ⚡ NOUVEAU — le nom de l'école est dessiné en gras simulé (traits
  // épaissis) avec une police nettement plus grande (arial48) quand il
  // tient sur la ligne du logo (cas normal) — sans agrandir la hauteur
  // de l'en-tête, puisque logoBox (60px) est déjà suffisant pour cette
  // police. Si le nom est trop long pour tenir à cette taille, on repasse
  // automatiquement à l'ancien comportement (police normale, retour à la
  // ligne si nécessaire), pour ne jamais perdre une partie du nom.
  static const int _headerWidth = 380;

  static img.Image _buildReceiptHeaderImage({
    required String schoolName,
    required Uint8List logoBytes,
  }) {
    const int margin  = 6;
    const int logoBox = 60;

    final int textZoneLeft  = margin + logoBox + margin;
    final int textZoneRight = _headerWidth - margin - logoBox - margin;
    final int textZoneWidth =
    (textZoneRight - textZoneLeft).clamp(40, _headerWidth);

    // ---- Logo : nette, bien contrastée, redimensionnée avec qualité ----
    img.Image? logo;
    try {
      logo = _prepareLogoForPrint(logoBytes, logoBox);
    } catch (_) {
      logo = null;
    }

    // ---- Choix de la police du nom : grande (48) si elle tient sur une
    // seule ligne dans la zone entre les deux logos, sinon on repasse à
    // la police normale (24) avec retour à la ligne comme avant. ----
    final img.BitmapFont bigFont = img.arial48;
    final img.BitmapFont normalFont = img.arial24;

    String firstLine;
    List<String> extraLines;
    img.BitmapFont usedFont;

    final safeNameBig = _safeText(schoolName.trim(), bigFont);
    if (_textWidth(bigFont, safeNameBig) <= textZoneWidth) {
      // Le nom entier tient sur la ligne du logo avec la grande police :
      // c'est le cas idéal (le plus fréquent) — gras + grand, 0 ligne en plus.
      firstLine = safeNameBig;
      extraLines = [];
      usedFont = bigFont;
    } else {
      // Repli : comportement d'avant, avec la police normale, découpage
      // du nom en plusieurs lignes si besoin, pour ne rien perdre.
      final words = schoolName.trim().split(RegExp(r'\s+'));
      String line = '';
      int cut = words.length;
      for (int i = 0; i < words.length; i++) {
        final candidate = line.isEmpty ? words[i] : '$line ${words[i]}';
        if (_textWidth(normalFont, candidate) <= textZoneWidth ||
            line.isEmpty) {
          line = candidate;
          cut = i + 1;
        } else {
          cut = i;
          break;
        }
      }
      final remainingWords = words.sublist(cut.clamp(0, words.length));

      final List<String> wrapped = [];
      if (remainingWords.isNotEmpty) {
        final fullWidth = _headerWidth - 2 * margin;
        String wline = '';
        for (final w in remainingWords) {
          final candidate = wline.isEmpty ? w : '$wline $w';
          if (_textWidth(normalFont, candidate) <= fullWidth ||
              wline.isEmpty) {
            wline = candidate;
          } else {
            wrapped.add(wline);
            wline = w;
          }
        }
        if (wline.isNotEmpty) wrapped.add(wline);
      }

      firstLine = _safeText(line, normalFont);
      extraLines = wrapped.map((l) => _safeText(l, normalFont)).toList();
      usedFont = normalFont;
    }

    const int lineHeight   = 24;
    final int topRowHeight = logo != null ? logoBox : (usedFont == bigFont ? 52 : 32);
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

    // Première ligne du nom (ou nom entier), centrée entre les deux logos,
    // dessinée en gras simulé (traits épaissis par superposition légère).
    final int fontVisualHeight = usedFont == bigFont ? 48 : 24;
    final int firstWidth = _textWidth(usedFont, firstLine);
    final int fx = textZoneLeft +
        (((textZoneWidth - firstWidth) / 2).round()).clamp(0, textZoneWidth);
    final int fy = margin + ((topRowHeight - fontVisualHeight) / 2).round();
    _drawBoldString(canvas, firstLine,
        font: usedFont, x: fx, y: fy, color: img.ColorRgb8(0, 0, 0));

    // Lignes suivantes (reste du nom, si repli en police normale),
    // centrées sur toute la largeur, également en gras simulé.
    int ey = margin + topRowHeight + 4;
    for (final line in extraLines) {
      final w = _textWidth(normalFont, line);
      final ex = (((_headerWidth - w) / 2).round()).clamp(0, _headerWidth);
      _drawBoldString(canvas, line,
          font: normalFont, x: ex, y: ey, color: img.ColorRgb8(0, 0, 0));
      ey += lineHeight;
    }

    return canvas;
  }

  /// ⚡ NOUVEAU — Dessine un texte en gras simulé : les polices bitmap
  /// intégrées à la librairie `image` n'ont pas de variante grasse, donc
  /// on superpose le même texte à quelques pixels de décalage pour
  /// épaissir artificiellement chaque trait. Effet visuel proche d'un
  /// vrai gras, sans changer la hauteur occupée.
  static void _drawBoldString(
      img.Image canvas,
      String text, {
        required img.BitmapFont font,
        required int x,
        required int y,
        required img.Color color,
      }) {
    const offsets = [
      [0, 0],
      [1, 0],
      [0, 1],
      [1, 1],
    ];
    for (final o in offsets) {
      img.drawString(canvas, text,
          font: font, x: x + o[0], y: y + o[1], color: color);
    }
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
  /// "Ecole" que "cole"). ⚡ CORRIGÉ — vérifie désormais les glyphes de
  /// la police réellement utilisée (passée en paramètre) plutôt que
  /// toujours arial24, puisqu'on utilise maintenant aussi arial48.
  static String _safeText(String text, img.BitmapFont font) {
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
      final hasGlyph = font.characters.containsKey(char.codeUnitAt(0));
      buffer.write(hasGlyph ? char : (replacements[char] ?? char));
    }
    return buffer.toString();
  }

  // ====================================================================
  // GÉNÉRER ET IMPRIMER UN REÇU COMPLET (paiement mensuel principal)
  // ⚡ Impression AUTOMATIQUE — appelée juste après l'enregistrement d'un
  // paiement. Comportement inchangé : ne concerne qu'UN SEUL mois.
  // ====================================================================
  // Mise en page compacte pour économiser le papier :
  //   - "N° Reçu" sur sa propre ligne, "ID Élève" et "Classe" sur la même
  //     ligne, "Section" et "Date/Heure" sur la même ligne.
  //   - Suppression des sauts de ligne purement décoratifs entre les blocs.
  //   - Espace de signature et marge de découpe finale réduits.
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
  // ⚡ NOUVEAU — RÉIMPRESSION MANUELLE : REÇU REGROUPANT PLUSIEURS
  // PAIEMENTS DÉJÀ ENREGISTRÉS DU FRAIS MENSUEL PRINCIPAL.
  //
  // Utilisée pour 3 cas d'usage, tous à partir de l'écran "Paiements des
  // Élèves" (historique d'un élève) et depuis le Dashboard Admin après
  // validation d'un lot de paiements :
  //   1. Réimprimer le reçu d'UN SEUL paiement déjà effectué (reçu perdu
  //      → liste `transactions` d'un seul élément).
  //   2. Réimprimer un reçu regroupant PLUSIEURS paiements sélectionnés
  //      par l'utilisateur dans l'historique.
  //   3. Réimprimer TOUT l'historique de paiement d'un élève en un seul
  //      reçu (ex: un élève qui a payé son mois en plusieurs coupures,
  //      ou après validation groupée de plusieurs mois par l'Admin).
  //
  // Chaque entrée de `transactions` doit contenir au minimum 'mois' et
  // 'amount' (ou 'montant'), et idéalement 'date'. Le reçu reste compact
  // (même esprit que printReceipt : économie de papier) mais soigné
  // visuellement (logo + nom de l'école en en-tête, séparateurs nets,
  // montants alignés à droite).
  // ====================================================================
  static Future<bool> printTransactionsReceipt({
    required String printerName,
    required String schoolName,
    required String currentYear,
    required String studentName,
    required String studentId,
    required String classe,
    required String section,
    required List<Map<String, dynamic>> transactions,
    Uint8List? logoBytes,
    String? receiptNumber,
    String titre = 'REÇU DE PAIEMENT',
    bool duplicata = false,
  }) async {
    if (!Platform.isWindows) return false;
    if (transactions.isEmpty) return false;

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

      final String numRecu = receiptNumber ??
          'RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour}${now.minute}${now.second}';

      // ==================== EN-TÊTE ÉCOLE ====================
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );

      if (logoBytes != null) {
        try {
          final headerImage = _buildReceiptHeaderImage(
            schoolName: schoolName,
            logoBytes: logoBytes,
          );
          bytes += generator.image(headerImage);
        } catch (_) {
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
        duplicata ? 'REÇU DE PAIEMENT (DUPLICATA)' : titre,
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

      // ==================== NOM COMPLET ÉLÈVE ====================
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

      // ==================== INFOS ÉLÈVE ====================
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

      // ==================== DÉTAIL DES PAIEMENTS ====================
      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        transactions.length > 1
            ? 'DÉTAIL DES PAIEMENTS (${transactions.length})'
            : 'DÉTAIL DU PAIEMENT',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );

      double total = 0;
      // Trie chronologiquement (par date) pour une lecture claire.
      final sorted = List<Map<String, dynamic>>.from(transactions)
        ..sort((a, b) {
          final dateA = (a['date'] ?? '').toString();
          final dateB = (b['date'] ?? '').toString();
          return dateA.compareTo(dateB);
        });

      for (final t in sorted) {
        final mois = (t['mois'] ?? '').toString();
        final montant = (t['amount'] as num?)?.toDouble() ??
            (t['montant'] as num?)?.toDouble() ??
            0.0;
        final date = (t['date'] ?? '').toString();
        total += montant;

        bytes += generator.row([
          PosColumn(
            text: mois.isNotEmpty ? mois : '-',
            width: 6,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: '${montant.toStringAsFixed(0)} FC',
            width: 6,
            styles: const PosStyles(bold: true, align: PosAlign.right),
          ),
        ]);
        if (date.isNotEmpty) {
          bytes += generator.text(
            '   le $date',
            styles: const PosStyles(fontType: PosFontType.fontB),
          );
        }
      }

      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.row([
        PosColumn(
          text: 'TOTAL PAYÉ :',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: '${total.toStringAsFixed(0)} FC',
          width: 6,
          styles: const PosStyles(
              bold: true, height: PosTextSize.size2, align: PosAlign.right),
        ),
      ]);
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
  // ⚡ Impression AUTOMATIQUE — appelée juste après le paiement d'un seul
  // "autre frais". Comportement inchangé, avec en plus la possibilité
  // (optionnelle, rétro-compatible) d'afficher le logo de l'école comme
  // sur le reçu principal, pour rester joli et cohérent visuellement.
  // Volontairement plus court que le reçu de paiement mensuel : nom de
  // l'école, titre du frais (ex: "Frais de l'État"), nom de l'élève,
  // classe, date de paiement, montant, et une ligne signature.
  // "Classe" et "Section" combinées sur une même ligne, signature réduite,
  // même principe que printReceipt. Aucune information retirée.
  // ====================================================================
  static Future<bool> printAutreFraisReceipt({
    required String printerName,
    required String schoolName,
    required String titreFrais,
    required String studentName,
    required String classe,
    required String section,
    required double montant,
    Uint8List? logoBytes, // ⚡ NOUVEAU — optionnel, rétro-compatible
    bool duplicata = false, // ⚡ NOUVEAU
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

      if (logoBytes != null) {
        try {
          final headerImage = _buildReceiptHeaderImage(
            schoolName: schoolName,
            logoBytes: logoBytes,
          );
          bytes += generator.image(headerImage);
        } catch (_) {
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
        duplicata ? '${titreFrais.toUpperCase()} (DUPLICATA)'
            : titreFrais.toUpperCase(),
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

  // ====================================================================
  // ⚡ NOUVEAU — RÉIMPRESSION MANUELLE : REÇU REGROUPANT PLUSIEURS
  // "AUTRES FRAIS" DÉJÀ PAYÉS PAR UN MÊME ÉLÈVE.
  //
  // Même logique que `printTransactionsReceipt`, mais pour la liste des
  // frais additionnels (nom du frais + montant + date), avec un total en
  // bas. Utilisée pour :
  //   1. Réimprimer le reçu d'UN SEUL "autre frais" déjà payé (reçu
  //      perdu).
  //   2. Réimprimer un reçu regroupant PLUSIEURS "autres frais" payés par
  //      le même élève (sélection ou historique complet).
  //   3. L'impression automatique groupée depuis le Dashboard Admin après
  //      validation d'un lot de paiements d'"autres frais".
  // Chaque entrée de `paiements` doit contenir 'nom' (le nom du frais),
  // 'montant' et idéalement 'date'.
  // ====================================================================
  static Future<bool> printAutresFraisTransactionsReceipt({
    required String printerName,
    required String schoolName,
    required String studentName,
    required String classe,
    required String section,
    required List<Map<String, dynamic>> paiements,
    Uint8List? logoBytes,
    bool duplicata = false,
  }) async {
    if (!Platform.isWindows) return false;
    if (paiements.isEmpty) return false;

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

      if (logoBytes != null) {
        try {
          final headerImage = _buildReceiptHeaderImage(
            schoolName: schoolName,
            logoBytes: logoBytes,
          );
          bytes += generator.image(headerImage);
        } catch (_) {
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
        duplicata ? 'AUTRES FRAIS (DUPLICATA)' : 'REÇU — AUTRES FRAIS',
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
      bytes += generator.text(
        'Imprimé le : $today $heure',
        styles: const PosStyles(fontType: PosFontType.fontB),
      );

      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        paiements.length > 1
            ? 'DÉTAIL DES FRAIS (${paiements.length})'
            : 'DÉTAIL DU FRAIS',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );

      double total = 0;
      final sorted = List<Map<String, dynamic>>.from(paiements)
        ..sort((a, b) => (a['date'] ?? '')
            .toString()
            .compareTo((b['date'] ?? '').toString()));

      for (final p in sorted) {
        final nom = (p['nom'] ?? '').toString();
        final montant = (p['montant'] as num?)?.toDouble() ?? 0.0;
        final date = (p['date'] ?? '').toString();
        total += montant;

        bytes += generator.row([
          PosColumn(
            text: nom.isNotEmpty ? nom : '-',
            width: 7,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: '${montant.toStringAsFixed(0)} FC',
            width: 5,
            styles: const PosStyles(bold: true, align: PosAlign.right),
          ),
        ]);
        if (date.isNotEmpty) {
          bytes += generator.text(
            '   $date',
            styles: const PosStyles(fontType: PosFontType.fontB),
          );
        }
      }

      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.row([
        PosColumn(
          text: 'TOTAL PAYÉ :',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: '${total.toStringAsFixed(0)} FC',
          width: 6,
          styles: const PosStyles(
              bold: true, height: PosTextSize.size2, align: PosAlign.right),
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