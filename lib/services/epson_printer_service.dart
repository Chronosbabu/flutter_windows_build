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
  // GÉNÉRER ET IMPRIMER UN REÇU COMPLET (VERSION COURTE & PROPRE)
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
    String? receiptNumber, // Numéro de reçu (généré automatiquement si null)
    Uint8List? logoBytes,
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

      // ==================== LOGO (optionnel) ====================
      if (logoBytes != null) {
        try {
          final decoded = img.decodeImage(logoBytes);
          if (decoded != null) {
            final resized = decoded.width > 380
                ? img.copyResize(decoded, width: 380)
                : decoded;
            bytes += generator.image(resized);
            bytes += generator.feed(1);
          }
        } catch (_) {}
      }

      // ==================== EN-TÊTE ÉCOLE ====================
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
      bytes += generator.feed(1);

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
      bytes += generator.feed(1);

      // ==================== INFOS ÉLÈVE ====================
      bytes += generator.row([
        PosColumn(
          text: 'N° Reçu :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: numRecu, width: 7),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'ID Élève :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: studentId, width: 7),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Classe :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: classe, width: 7),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Section :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: section, width: 7),
      ]);
      bytes += generator.feed(1);

      // ==================== DATE & HEURE ====================
      bytes += generator.row([
        PosColumn(
          text: 'Date :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: today, width: 7),
      ]);
      bytes += generator.row([
        PosColumn(
          text: 'Heure :',
          width: 5,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(text: heure, width: 7),
      ]);
      bytes += generator.feed(1);

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
      bytes += generator.feed(1);

      // ==================== SIGNATURE ====================
      bytes += generator.text(
        'Signature :',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.feed(2);
      bytes += generator.text(
        '................................',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.feed(1);

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
      bytes += generator.feed(3);
      bytes += generator.cut();

      return await _sendRawBytes(printerName, Uint8List.fromList(bytes));
    } catch (_) {
      return false;
    }
  }
}