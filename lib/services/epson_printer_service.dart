import 'dart:io' show Platform, Process;
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

/// ⚡ NOUVEAU — Remplace bluetooth_printer_service.dart.
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
  // GÉNÉRER ET IMPRIMER UN REÇU COMPLET
  // ====================================================================
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
    Uint8List? logoBytes, // ⚡ NOUVEAU : logo optionnel (PNG/JPG en mémoire)
  }) async {
    if (!Platform.isWindows) return false;

    try {
      // Epson TM-T20III : papier 80mm, résolution 203dpi.
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      // ⚡ Table de caractères pour un rendu correct des accents français
      // (é, è, à, ç, ê, etc.) sur l'Epson TM-T20III.
      generator.setGlobalCodeTable('CP1252');

      final String today = DateTime.now().toString().split(' ')[0];
      final String heure =
      DateTime.now().toString().split(' ')[1].substring(0, 5);

      // ==================== LOGO (optionnel) ====================
      if (logoBytes != null) {
        try {
          final decoded = img.decodeImage(logoBytes);
          if (decoded != null) {
            // Redimensionne pour rester lisible sur 80mm (~576px max utiles)
            final resized = decoded.width > 380
                ? img.copyResize(decoded, width: 380)
                : decoded;
            bytes += generator.image(resized);
            bytes += generator.feed(1);
          }
        } catch (_) {
          // Logo illisible : on continue sans bloquer l'impression du reçu
        }
      }

      // ==================== EN-TÊTE ====================
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        schoolName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        'RECU DE PAIEMENT',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          underline: true,
        ),
      );
      bytes += generator.text(
        'Annee : $currentYear',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.feed(1);

      // ==================== DATE ET HEURE ====================
      bytes += generator.row([
        PosColumn(
          text: 'Date :',
          width: 4,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: today, width: 8),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Heure :',
          width: 4,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: heure, width: 8),
      ]);
      bytes += generator.feed(1);

      // ==================== INFOS ÉLÈVE ====================
      bytes += generator.text(
        '--- INFORMATIONS ELEVE ---',
        styles: const PosStyles(bold: true, align: PosAlign.center),
      );
      bytes += generator.row([
        PosColumn(
          text: 'ID :',
          width: 4,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: studentId, width: 8),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Nom :',
          width: 4,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: studentName, width: 8),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Classe :',
          width: 4,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: classe, width: 8),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Section :',
          width: 4,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: section, width: 8),
      ]);
      bytes += generator.feed(1);

      // ==================== PAIEMENT DU JOUR ====================
      bytes += generator.text(
        '--- PAIEMENT DU JOUR ---',
        styles: const PosStyles(bold: true, align: PosAlign.center),
      );
      bytes += generator.row([
        PosColumn(
          text: 'Mois :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: moisPaye,
          width: 7,
          styles: const PosStyles(bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Verse :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: '${montantPaye.toStringAsFixed(0)} FC',
          width: 7,
          styles: const PosStyles(bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Requis :', width: 5),
        PosColumn(
          text: '${montantRequis.toStringAsFixed(0)} FC',
          width: 7,
        ),
      ]);

      if (resteAPayerMois > 0) {
        bytes += generator.row([
          PosColumn(
            text: 'Reste :',
            width: 5,
            styles: const PosStyles(bold: true),
          ),
          PosColumn(
            text: '${resteAPayerMois.toStringAsFixed(0)} FC',
            width: 7,
            styles: const PosStyles(bold: true),
          ),
        ]);
      } else {
        bytes += generator.text(
          '>>> MOIS COMPLETEMENT PAYE <<<',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
      }
      bytes += generator.feed(1);

      // ==================== BILAN ANNUEL ====================
      bytes += generator.text(
        '--- BILAN ANNUEL ---',
        styles: const PosStyles(bold: true, align: PosAlign.center),
      );
      bytes += generator.row([
        PosColumn(text: 'Total paye :', width: 7),
        PosColumn(
          text: '${totalDejaPayeAnnee.toStringAsFixed(0)} FC',
          width: 5,
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Total requis :', width: 7),
        PosColumn(
          text: '${totalRequis.toStringAsFixed(0)} FC',
          width: 5,
        ),
      ]);
      final double resteAnnee = totalRequis - totalDejaPayeAnnee;
      bytes += generator.row([
        PosColumn(
          text: 'Reste annuel :',
          width: 7,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text:
          '${resteAnnee > 0 ? resteAnnee.toStringAsFixed(0) : "0"} FC',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
      ]);
      bytes += generator.feed(1);

      // ==================== HISTORIQUE DES PAIEMENTS ====================
      if (historiqueTransactions.isNotEmpty) {
        bytes += generator.text(
          '--- HISTORIQUE ---',
          styles: const PosStyles(bold: true, align: PosAlign.center),
        );

        final sorted =
        List<Map<String, dynamic>>.from(historiqueTransactions)
          ..sort(
                (a, b) => (a['date'] ?? '')
                .toString()
                .compareTo((b['date'] ?? '').toString()),
          );

        for (var t in sorted) {
          final tDate = t['date']?.toString() ?? '??-??-????';
          final tMois = t['mois']?.toString() ?? '';
          final tAmount = (t['amount'] as num?)?.toDouble() ?? 0;
          final tMoisCourt =
          tMois.length > 4 ? tMois.substring(0, 4) : tMois;
          bytes += generator.row([
            PosColumn(
              text: tDate,
              width: 6,
              styles: const PosStyles(fontType: PosFontType.fontB),
            ),
            PosColumn(
              text: tMoisCourt,
              width: 3,
              styles: const PosStyles(fontType: PosFontType.fontB),
            ),
            PosColumn(
              text: '${tAmount.toStringAsFixed(0)}FC',
              width: 3,
              styles: const PosStyles(fontType: PosFontType.fontB),
            ),
          ]);
        }
        bytes += generator.feed(1);
      }

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
        'Conservez ce recu.',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.feed(3);
      bytes += generator.cut(); // Coupe automatique (l'Epson TM-T20III a un autocutter)

      return await _sendRawBytes(printerName, Uint8List.fromList(bytes));
    } catch (_) {
      return false;
    }
  }
}