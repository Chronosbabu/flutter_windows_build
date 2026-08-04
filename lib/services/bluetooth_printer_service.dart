import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:serial_port_win32/serial_port_win32.dart';

class BluetoothPrinterService {
  // ====================================================================
  // LISTER LES PORTS COM DISPONIBLES
  // ====================================================================
  static List<String> getAvailablePorts() {
    if (!Platform.isWindows) return [];
    try {
      return SerialPort.getAvailablePorts();
    } catch (_) {
      return [];
    }
  }

  // ====================================================================
  // ENVOYER DES OCTETS BRUTS SUR LE PORT COM
  // ====================================================================
  static Future<bool> _sendBytes(String portName, Uint8List data) async {
    if (!Platform.isWindows) return false;
    SerialPort? port;
    try {
      port = SerialPort(
        portName,
        openNow: false,
        BaudRate: 9600,
        ByteSize: 8,
        StopBits: 0,
        Parity: 0,
      );
      await port.open();
      if (!port.isOpened) return false;
      final written = await port.writeBytesFromUint8List(data);
      return written;
    } catch (_) {
      return false;
    } finally {
      try {
        port?.close();
      } catch (_) {}
    }
  }

  // ====================================================================
  // GÉNÉRER ET IMPRIMER UN REÇU COMPLET
  // ====================================================================
  static Future<bool> printReceipt({
    required String portName,
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
  }) async {
    if (!Platform.isWindows) return false;

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      final String today = DateTime.now().toString().split(' ')[0];
      final String heure =
      DateTime.now().toString().split(' ')[1].substring(0, 5);

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
      bytes += generator.cut();

      return await _sendBytes(portName, Uint8List.fromList(bytes));
    } catch (_) {
      return false;
    }
  }
}