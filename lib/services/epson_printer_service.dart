import 'dart:async';
import 'dart:io' show Platform, Process, Directory, File, FileMode;
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show debugPrint;
import 'receipt_layout_settings.dart';

class EscPosPrinterService {
  static File? _logFile;
  static bool _logFileResolved = false;
  static const int _maxLogSizeBytes = 5 * 1024 * 1024;

  // ---------------------------------------------------------------------------
  // INFORMATIONS DE L'ÉLÈVE (adresse, père, mère…) — fournies par l'écran
  // d'accueil. Retourne une table : 'adresse', 'pere', 'mere',
  // 'dateNaissance' et 'cf:<question>' pour les champs personnalisés.
  // ---------------------------------------------------------------------------
  static Map<String, String> Function(String studentId, String studentName)?
  studentInfoResolver;

  // ---------------------------------------------------------------------------
  // MISE EN PAGE DES REÇUS (pilotée par ReceiptTheme)
  // ---------------------------------------------------------------------------

  static Future<ReceiptTheme> _loadTheme() async {
    try {
      await receiptLayout.charger();
      return ReceiptTheme.fromSettings(receiptLayout);
    } catch (e, st) {
      _log('EXCEPTION lecture des réglages de mise en forme, format actuel '
          'utilisé par défaut : $e\n$st');
      return ReceiptTheme.fromSettings(ReceiptLayoutSettings());
    }
  }

  static List<int> _sepLine(Generator g, ReceiptTheme t, String ch) {
    return g.text(ch * t.cols, styles: t.center);
  }

  static String _latin(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      b.write(r <= 255 ? String.fromCharCode(r) : '?');
    }
    return b.toString();
  }

  static List<String> _wrap(String text, int max) {
    final words = text.trim().split(RegExp(r'\s+'));
    final lines = <String>[];
    String cur = '';
    for (var w in words) {
      while (w.length > max) {
        if (cur.isNotEmpty) {
          lines.add(cur);
          cur = '';
        }
        lines.add(w.substring(0, max));
        w = w.substring(max);
      }
      final cand = cur.isEmpty ? w : '$cur $w';
      if (cand.length <= max) {
        cur = cand;
      } else {
        lines.add(cur);
        cur = w;
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines;
  }

  /// Lignes d'informations supplémentaires de l'élève (adresse, père, mère…).
  /// Ne bloque JAMAIS l'impression : en cas de souci, retourne rien.
  static List<int> _infoBlock(
      Generator generator, ReceiptTheme t, String studentId, String studentName) {
    try {
      final s = receiptLayout;
      if (!s.afficherInfosSup) return <int>[];
      final resolver = studentInfoResolver;
      if (resolver == null) return <int>[];
      final info = resolver(studentId, studentName);
      if (info.isEmpty) return <int>[];

      final lignes = <MapEntry<String, String>>[];
      if (s.showAdresse) lignes.add(MapEntry('Adresse', info['adresse'] ?? ''));
      if (s.showPere) lignes.add(MapEntry('Père', info['pere'] ?? ''));
      if (s.showMere) lignes.add(MapEntry('Mère', info['mere'] ?? ''));
      if (s.showDateNaissance) {
        lignes.add(MapEntry('Né(e) le', info['dateNaissance'] ?? ''));
      }
      for (final k in s.champsPerso) {
        lignes.add(MapEntry(k, info['cf:$k'] ?? ''));
      }

      List<int> bytes = [];
      for (final l in lignes) {
        final v = _latin(l.value).trim();
        if (v.isEmpty) continue;
        for (final ligne in _wrap('${_latin(l.key)} : $v', t.cols)) {
          bytes += generator.text(ligne, styles: t.row);
        }
      }
      return bytes;
    } catch (e, st) {
      _log('EXCEPTION lecture des informations élève pour le reçu, ignorées : '
          '$e\n$st');
      return <int>[];
    }
  }

  /// Ligne séparatrice + logo(s)/nom de l'école.
  static List<int> _schoolHeader(
      Generator generator,
      ReceiptTheme t, {
        required String schoolName,
        required Uint8List? logoBytes,
        required String contexte,
      }) {
    List<int> bytes = [];
    bytes += _sepLine(generator, t, '=');

    if (logoBytes != null && t.logoCount > 0) {
      try {
        final headerImage = _buildReceiptHeaderImage(
          schoolName: schoolName,
          logoBytes: logoBytes,
          theme: t,
        );
        bytes += generator.image(headerImage);
      } catch (e, st) {
        _log('EXCEPTION génération du logo ($contexte), logo ignoré : '
            '$e\n$st');
        bytes += generator.text(schoolName.toUpperCase(),
            styles: t.schoolFor(schoolName));
      }
    } else {
      bytes += generator.text(schoolName.toUpperCase(),
          styles: t.schoolFor(schoolName));
    }
    return bytes;
  }

  /// Bloc signature / cachet.
  static List<int> _signatureBlock(Generator generator, ReceiptTheme t) {
    List<int> bytes = [];
    bytes += generator.text(t.signatureLabel, styles: t.signature);
    if (t.signatureFeed > 0) {
      bytes += generator.feed(t.signatureFeed);
    }
    bytes += generator.text('.' * t.cols, styles: t.center);
    return bytes;
  }

  static List<int> _footer(Generator generator, ReceiptTheme t,
      {bool conserver = true}) {
    List<int> bytes = [];
    bytes += _sepLine(generator, t, '=');
    if (t.showMerci) {
      bytes += generator.text(
        'Merci pour votre paiement !',
        styles: t.bodyCenter,
      );
    }
    if (conserver && t.showConserver) {
      bytes += generator.text(
        'Conservez ce reçu.',
        styles: t.conserver,
      );
    }
    bytes += _sepLine(generator, t, '=');
    bytes += generator.feed(2);
    bytes += generator.cut();
    return bytes;
  }

  // ---------------------------------------------------------------------------
  // LOGS
  // ---------------------------------------------------------------------------

  static Future<File?> _resolveLogFile() async {
    if (_logFileResolved) return _logFile;
    _logFileResolved = true;
    try {
      String? home;
      if (Platform.isWindows) {
        home = Platform.environment['USERPROFILE'];
      } else if (Platform.isMacOS || Platform.isLinux) {
        home = Platform.environment['HOME'];
      }

      if (home == null || home.isEmpty) {
        debugPrint('[EPSON] Impossible de localiser le dossier utilisateur '
            '(Bureau) — les logs resteront uniquement dans la console.');
        return null;
      }

      final logsDir = Directory(
          '$home${Platform.pathSeparator}Desktop${Platform.pathSeparator}EduPay_Logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      final file =
      File('${logsDir.path}${Platform.pathSeparator}printer_log.txt');
      if (!await file.exists()) {
        await file.create(recursive: true);
      }

      _logFile = file;
      debugPrint('[EPSON] Fichier de logs prêt : ${file.path}');

      final ts = DateTime.now().toIso8601String();
      await file.writeAsString(
        '\n========== NOUVELLE SESSION — $ts '
            '(${Platform.operatingSystem}) ==========\n',
        mode: FileMode.append,
        flush: true,
      );

      return file;
    } catch (e, st) {
      debugPrint('[EPSON] EXCEPTION lors de la création du fichier de '
          'logs sur le Bureau : $e\n$st');
      return null;
    }
  }

  static Future<void> _rotateLogFileIfNeeded(File file) async {
    try {
      final size = await file.length();
      if (size <= _maxLogSizeBytes) return;

      final oldPath =
          '${file.path.substring(0, file.path.length - 4)}.ancien.txt';
      final oldFile = File(oldPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
      await file.copy(oldPath);
      await file.writeAsString('', mode: FileMode.write, flush: true);
      debugPrint('[EPSON] Fichier de logs archivé (dépassait 5 Mo) → '
          '$oldPath — nouveau fichier repart de zéro.');
    } catch (e, st) {
      debugPrint('[EPSON] EXCEPTION lors de la rotation du fichier de '
          'logs : $e\n$st');
    }
  }

  static Future<void> _writeToLogFile(String line) async {
    try {
      final file = await _resolveLogFile();
      if (file == null) return;
      await _rotateLogFileIfNeeded(file);
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (e, st) {
      debugPrint('[EPSON] EXCEPTION lors de l\'écriture dans le fichier '
          'de logs : $e\n$st');
    }
  }

  static void _log(String message) {
    final ts = DateTime.now().toIso8601String();
    final line = '[EPSON $ts] $message';
    debugPrint(line);
    unawaited(_writeToLogFile(line));
  }

  // ---------------------------------------------------------------------------
  // LISTE DES IMPRIMANTES
  // ---------------------------------------------------------------------------

  static Future<List<String>> getAvailablePrinters() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-Command',
            'Get-Printer | Select-Object -ExpandProperty Name',
          ],
          runInShell: true,
        );
        if (result.exitCode != 0) {
          _log('getAvailablePrinters (Windows) ÉCHEC — exitCode='
              '${result.exitCode} stderr="${result.stderr}" '
              'stdout="${result.stdout}"');
          return [];
        }
        final list = result.stdout
            .toString()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        _log('getAvailablePrinters (Windows) OK — ${list.length} '
            'imprimante(s) trouvée(s) : $list');
        return list;
      }

      if (Platform.isMacOS) {
        final result = await Process.run('lpstat', ['-a']);
        if (result.exitCode != 0) {
          _log('getAvailablePrinters (macOS) ÉCHEC — exitCode='
              '${result.exitCode} stderr="${result.stderr}" '
              'stdout="${result.stdout}"');
          return [];
        }
        final list = result.stdout
            .toString()
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map((l) => l.split(RegExp(r'\s+')).first)
            .where((name) => name.isNotEmpty)
            .toList();
        _log('getAvailablePrinters (macOS) OK — ${list.length} '
            'imprimante(s) trouvée(s) : $list');
        return list;
      }

      _log('getAvailablePrinters — plateforme non supportée '
          '(${Platform.operatingSystem})');
      return [];
    } catch (e, st) {
      _log('EXCEPTION dans getAvailablePrinters : $e\n$st');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // ENVOI DES OCTETS BRUTS (INCHANGÉ)
  // ---------------------------------------------------------------------------

  static Future<bool> _sendRawBytes(
      String printerName, Uint8List data) async {
    _log('_sendRawBytes → imprimante="$printerName" '
        'taille=${data.length} octets plateforme=${Platform.operatingSystem}');
    if (Platform.isWindows) {
      return await _sendRawBytesWindows(printerName, data);
    }
    if (Platform.isMacOS) {
      return await _sendRawBytesMacOS(printerName, data);
    }
    _log('_sendRawBytes — plateforme non supportée '
        '(${Platform.operatingSystem})');
    return false;
  }

  static Future<bool> _sendRawBytesWindows(
      String printerName, Uint8List data) async {
    final printerNamePtr = printerName.toNativeUtf16();
    final phPrinter = calloc<IntPtr>();
    Pointer<Utf16> docNamePtr = nullptr;
    Pointer<Utf16> dataTypePtr = nullptr;
    Pointer<DOC_INFO_1> docInfo = nullptr;
    Pointer<Uint8> dataPtr = nullptr;
    Pointer<Uint32> bytesWritten = nullptr;
    int docId = 0;
    bool sentOk = false;

    try {
      final opened = OpenPrinter(printerNamePtr, phPrinter, nullptr);
      if (opened == 0) {
        final err = GetLastError();
        _log('OpenPrinter ÉCHEC pour "$printerName" — code erreur Windows: '
            '$err (ex: 1801=nom de file invalide, 5=accès refusé, '
            '2=fichier/imprimante introuvable). Vérifie que ce nom exact '
            'existe encore dans "Imprimantes et scanners" — un débranchement/'
            're-branchement USB peut avoir recréé la file sous un autre nom.');
        return false;
      }
      final hPrinter = phPrinter.value;
      _log('OpenPrinter OK pour "$printerName" (handle=$hPrinter)');

      docNamePtr = 'Recu EduPay'.toNativeUtf16();
      dataTypePtr = 'RAW'.toNativeUtf16();
      docInfo = calloc<DOC_INFO_1>();
      docInfo.ref
        ..pDocName = docNamePtr
        ..pOutputFile = nullptr
        ..pDatatype = dataTypePtr;

      docId = StartDocPrinter(hPrinter, 1, docInfo.cast());
      if (docId == 0) {
        final err = GetLastError();
        _log('StartDocPrinter ÉCHEC pour "$printerName" — code erreur '
            'Windows: $err (ex: 5=accès refusé, souvent le spouleur est '
            'bloqué/en pause, ou un job précédent est resté coincé).');
        ClosePrinter(hPrinter);
        return false;
      }
      _log('StartDocPrinter OK pour "$printerName" (docId=$docId)');

      final pageStarted = StartPagePrinter(hPrinter);
      if (pageStarted == 0) {
        _log('StartPagePrinter ÉCHEC pour "$printerName" — code erreur '
            'Windows: ${GetLastError()}');
      }

      dataPtr = calloc<Uint8>(data.length);
      dataPtr.asTypedList(data.length).setAll(0, data);

      bytesWritten = calloc<Uint32>();
      final writeOk = WritePrinter(
        hPrinter,
        dataPtr.cast(),
        data.length,
        bytesWritten,
      );

      if (writeOk == 0) {
        final err = GetLastError();
        _log('WritePrinter ÉCHEC pour "$printerName" (docId=$docId) — '
            'code erreur Windows: $err (souvent 995=opération annulée car '
            'imprimante débranchée/éteinte pendant l\'envoi, ou 6=handle '
            'invalide).');
      } else if (bytesWritten.value != data.length) {
        _log('WritePrinter PARTIEL pour "$printerName" (docId=$docId) — '
            'envoyés ${bytesWritten.value}/${data.length} octets seulement.');
      } else {
        _log('WritePrinter OK pour "$printerName" (docId=$docId) — '
            '${bytesWritten.value} octets envoyés intégralement.');
      }

      EndPagePrinter(hPrinter);
      EndDocPrinter(hPrinter);
      ClosePrinter(hPrinter);

      sentOk = writeOk != 0 && bytesWritten.value == data.length;
    } catch (e, st) {
      _log('EXCEPTION dans _sendRawBytesWindows pour "$printerName": '
          '$e\n$st');
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

    if (!sentOk) {
      _log('_sendRawBytesWindows → envoi considéré ÉCHOUÉ pour '
          '"$printerName" (docId=$docId), confirmation non tentée.');
      return false;
    }

    _log('_sendRawBytesWindows → envoi réussi pour "$printerName" '
        '(docId=$docId), lancement de la confirmation réelle...');
    return await _confirmJobPrintedWindows(printerName, docId);
  }

  static Future<bool> _sendRawBytesMacOS(
      String printerName, Uint8List data) async {
    Directory? tempDir;
    File? tempFile;
    try {
      tempDir = await Directory.systemTemp.createTemp('escpos_');
      tempFile = File('${tempDir.path}/print.raw');
      await tempFile.writeAsBytes(data, flush: true);

      final result = await Process.run(
        'lp',
        [
          '-d', printerName,
          '-o', 'raw',
          tempFile.path,
        ],
      );

      if (result.exitCode != 0) {
        _log('Commande "lp" ÉCHEC pour "$printerName" — exitCode='
            '${result.exitCode} stderr="${result.stderr}" '
            'stdout="${result.stdout}"');
        return false;
      }

      final output = result.stdout.toString();
      final match = RegExp(r'request id is .+?-(\d+)').firstMatch(output);
      final jobId = match != null ? int.tryParse(match.group(1)!) : null;

      if (jobId == null) {
        _log('"lp" a réussi pour "$printerName" mais aucun jobId extrait '
            'de la sortie ("$output") → considéré OK par défaut.');
        return true;
      }

      _log('"lp" OK pour "$printerName" — jobId=$jobId, lancement de la '
          'confirmation réelle...');
      return await _confirmJobPrintedMacOS(printerName, jobId);
    } catch (e, st) {
      _log('EXCEPTION dans _sendRawBytesMacOS pour "$printerName": $e\n$st');
      return false;
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
        if (tempDir != null && await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (e, st) {
        _log('EXCEPTION lors du nettoyage du fichier temporaire macOS : '
            '$e\n$st');
      }
    }
  }

  static Future<bool> _confirmJobPrintedWindows(
      String printerName,
      int jobId, {
        Duration timeout = const Duration(seconds: 6),
      }) async {
    try {
      final double timeoutSeconds = timeout.inMilliseconds / 1000.0;

      final String script = '''
\$deadline = (Get-Date).AddSeconds($timeoutSeconds)
\$result = "TIMEOUT"
while ((Get-Date) -lt \$deadline) {
  \$status = Get-PrintJob -PrinterName "$printerName" -ErrorAction SilentlyContinue |
    Where-Object { \$_.Id -eq $jobId } |
    Select-Object -ExpandProperty JobStatus
  if (-not \$status) {
    \$result = "OK"
    break
  }
  \$lower = \$status.ToString().ToLower()
  if (\$lower -match 'error|offline|paperout|paper out|usernotified|userintervention|blocked|deleted') {
    \$result = "ERROR"
    break
  }
  Start-Sleep -Milliseconds 300
}
Write-Output \$result
''';

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', script],
        runInShell: true,
      ).timeout(timeout + const Duration(seconds: 4));

      final output = result.stdout.toString().trim().toUpperCase();
      _log('_confirmJobPrintedWindows pour "$printerName" (jobId=$jobId) → '
          'exitCode=${result.exitCode} stdout="${result.stdout.toString().trim()}" '
          'stderr="${result.stderr.toString().trim()}"');

      final bool hasExplicitError = output.contains('ERROR');
      final bool ok = !hasExplicitError;

      if (hasExplicitError) {
        _log('_confirmJobPrintedWindows → ERREUR EXPLICITE détectée pour '
            '"$printerName" (jobId=$jobId), résultat="$output" (papier '
            'coincé, imprimante hors ligne, ou autre statut d\'erreur '
            'remonté par Get-PrintJob).');
      } else if (output.contains('OK')) {
        _log('_confirmJobPrintedWindows → CONFIRMÉ pour "$printerName" '
            '(jobId=$jobId).');
      } else {
        _log('_confirmJobPrintedWindows → confirmation NON obtenue pour '
            '"$printerName" (jobId=$jobId), résultat="$output" (souvent : '
            'module PowerShell "PrintManagement" indisponible sur cette '
            'édition de Windows/ce compte, ou job déjà disparu avant la '
            'première vérification). Aucune erreur explicite détectée → '
            'on NE remet PAS ce reçu en file d\'impression, puisque '
            'WritePrinter avait déjà réussi.');
      }
      return ok;
    } catch (e, st) {
      _log('EXCEPTION/TIMEOUT dans _confirmJobPrintedWindows pour '
          '"$printerName" (jobId=$jobId) : $e\n$st\n'
          '→ WritePrinter avait déjà réussi ; on ne peut pas vérifier le '
          'statut réel (module PrintManagement absent/bloqué sur ce PC ?), '
          'mais on NE DOIT PAS renvoyer false ici, sous peine de '
          'réimprimer physiquement ce reçu à la prochaine ouverture de '
          'l\'écran des paiements (flushReceiptQueue). On considère donc '
          'l\'envoi comme réussi.');
      return true;
    }
  }

  static Future<bool> _confirmJobPrintedMacOS(
      String printerName,
      int jobId, {
        Duration timeout = const Duration(seconds: 8),
      }) async {
    try {
      final deadline = DateTime.now().add(timeout);

      while (DateTime.now().isBefore(deadline)) {
        final result = await Process.run('lpstat', ['-o', printerName]);

        if (result.exitCode != 0) {
          _log('_confirmJobPrintedMacOS pour "$printerName" (jobId=$jobId) '
              '— "lpstat -o" exitCode=${result.exitCode} '
              'stderr="${result.stderr}" → impossible d\'interroger, '
              'considéré OK (job probablement déjà parti).');
          return true;
        }

        final output = result.stdout.toString();
        final stillPresent = output.contains('-$jobId ');

        if (!stillPresent) {
          _log('_confirmJobPrintedMacOS → job $jobId disparu de la file '
              'pour "$printerName" → CONFIRMÉ imprimé.');
          return true;
        }

        final errResult = await Process.run(
            'lpstat', ['-W', 'not-completed', '-o', printerName]);
        final errOut = errResult.stdout.toString().toLowerCase();
        if (errOut.contains('error') ||
            errOut.contains('offline') ||
            errOut.contains('paper') ||
            errOut.contains('held') ||
            errOut.contains('stopped')) {
          _log('_confirmJobPrintedMacOS → erreur détectée pour '
              '"$printerName" (jobId=$jobId) : "$errOut"');
          return false;
        }

        await Future.delayed(const Duration(milliseconds: 350));
      }

      _log('_confirmJobPrintedMacOS → TIMEOUT pour "$printerName" '
          '(jobId=$jobId) après ${timeout.inSeconds}s, non certifié.');
      return false;
    } catch (e, st) {
      _log('EXCEPTION dans _confirmJobPrintedMacOS pour "$printerName" '
          '(jobId=$jobId) : $e\n$st');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // EN-TÊTE DU REÇU (LOGO(S) + NOM DE L'ÉCOLE)
  // ---------------------------------------------------------------------------

  static img.Image _prepareLogoForPrint(Uint8List logoBytes, int targetSize) {
    final decoded = img.decodeImage(logoBytes);
    if (decoded == null) {
      throw Exception('Logo illisible');
    }

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

  static img.Image _buildReceiptHeaderImage({
    required String schoolName,
    required Uint8List logoBytes,
    required ReceiptTheme theme,
  }) {
    const int margin = 6;
    final int headerWidth = theme.headerWidth;
    final int logoBox = theme.logoBox;
    final int lineHeight = theme.lineHeight;
    final int nbLogos = theme.logoCount < 1
        ? 1
        : (theme.logoCount > 3 ? 3 : theme.logoCount);
    final bool logoDroite = nbLogos >= 2;
    // 3e logo : centré, sur sa propre ligne au-dessus du nom.
    final int rangeeCentre = nbLogos >= 3 ? logoBox + margin : 0;

    final int textZoneLeft = margin + logoBox + margin;
    final int textZoneRight = logoDroite
        ? headerWidth - margin - logoBox - margin
        : headerWidth - margin;
    final int textZoneWidth =
    (textZoneRight - textZoneLeft).clamp(40, headerWidth);

    img.Image? logo;
    try {
      logo = _prepareLogoForPrint(logoBytes, logoBox);
    } catch (_) {
      logo = null;
    }

    final img.BitmapFont bigFont = img.arial48;
    final img.BitmapFont normalFont = img.arial24;

    String firstLine;
    List<String> extraLines;
    img.BitmapFont usedFont;

    final safeNameBig = _safeText(schoolName.trim(), bigFont);
    if (theme.bigSchoolName &&
        _textWidth(bigFont, safeNameBig) <= textZoneWidth) {
      firstLine = safeNameBig;
      extraLines = [];
      usedFont = bigFont;
    } else {
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
        final fullWidth = headerWidth - 2 * margin;
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

    final int topRowHeight =
    logo != null ? logoBox : (usedFont == bigFont ? 52 : 32);
    final int extraHeight =
    extraLines.isEmpty ? 0 : (extraLines.length * lineHeight) + 4;
    final int headerHeight =
        (margin * 2) + rangeeCentre + topRowHeight + extraHeight;
    final int baseY = margin + rangeeCentre;

    final canvas = img.Image(width: headerWidth, height: headerHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    if (logo != null) {
      final ly = baseY + ((topRowHeight - logo.height) ~/ 2);
      img.compositeImage(canvas, logo, dstX: margin, dstY: ly);
      if (logoDroite) {
        img.compositeImage(
          canvas,
          logo,
          dstX: headerWidth - margin - logo.width,
          dstY: ly,
        );
      }
      if (nbLogos >= 3) {
        img.compositeImage(
          canvas,
          logo,
          dstX: (headerWidth - logo.width) ~/ 2,
          dstY: margin,
        );
      }
    }

    final int fontVisualHeight = usedFont == bigFont ? 48 : 24;
    final int firstWidth = _textWidth(usedFont, firstLine);
    final int fx = textZoneLeft +
        (((textZoneWidth - firstWidth) / 2).round()).clamp(0, textZoneWidth);
    final int fy = baseY + ((topRowHeight - fontVisualHeight) / 2).round();
    _drawBoldString(canvas, firstLine,
        font: usedFont, x: fx, y: fy, color: img.ColorRgb8(0, 0, 0));

    int ey = baseY + topRowHeight + 4;
    for (final line in extraLines) {
      final w = _textWidth(normalFont, line);
      final ex = (((headerWidth - w) / 2).round()).clamp(0, headerWidth);
      _drawBoldString(canvas, line,
          font: normalFont, x: ex, y: ey, color: img.ColorRgb8(0, 0, 0));
      ey += lineHeight;
    }

    return canvas;
  }

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

  static int _textWidth(img.BitmapFont font, String text) {
    int width = 0;
    for (final c in text.codeUnits) {
      final ch = font.characters[c];
      if (ch == null) continue;
      width += ch.xAdvance;
    }
    return width;
  }

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

  // ---------------------------------------------------------------------------
  // REÇU : PAIEMENT D'UN MOIS
  // ---------------------------------------------------------------------------

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
    String? receiptNumber,
    Uint8List? logoBytes,
    String? noteExplicative,
  }) async {
    _log('printReceipt appelé — imprimante="$printerName" élève='
        '"$studentName" ($studentId) mois=$moisPaye montant=$montantPaye');

    if (!Platform.isWindows && !Platform.isMacOS) {
      _log('printReceipt — plateforme non supportée '
          '(${Platform.operatingSystem})');
      return false;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      final t = await _loadTheme();

      generator.setGlobalCodeTable('CP1252');

      final now = DateTime.now();
      final String today =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final String heure =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final String numRecu = receiptNumber ??
          'RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour}${now.minute}${now.second}';

      bytes += _schoolHeader(
        generator,
        t,
        schoolName: schoolName,
        logoBytes: logoBytes,
        contexte: 'printReceipt',
      );

      bytes += generator.text('REÇU DE PAIEMENT',
          styles: t.titleFor('REÇU DE PAIEMENT'));

      if (noteExplicative != null && noteExplicative.trim().isNotEmpty) {
        bytes += generator.text(
          noteExplicative.trim().toUpperCase(),
          styles: t.bodyCenter,
        );
      }

      bytes += generator.text(
        'Année scolaire : $currentYear',
        styles: t.bodyCenter,
      );
      bytes += _sepLine(generator, t, '=');

      bytes += generator.text('Nom complet :', styles: t.label);
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: t.nameStyle(studentName),
      );
      bytes += _infoBlock(generator, t, studentId, studentName);
      bytes += _sepLine(generator, t, '.');

      bytes += generator.row([
        PosColumn(text: 'Reçu : $numRecu', width: 12, styles: t.small),
      ]);
      bytes += generator.row([
        PosColumn(text: 'ID : $studentId', width: 6, styles: t.row),
        PosColumn(text: 'Cl. : $classe', width: 6, styles: t.row),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Sect. : $section', width: 6, styles: t.row),
        PosColumn(text: '$today $heure', width: 6, styles: t.small),
      ]);

      bytes += _sepLine(generator, t, '-');
      bytes += generator.row([
        PosColumn(text: 'Mois payé :', width: 6, styles: t.row),
        PosColumn(text: moisPaye, width: 6, styles: t.row),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Montant payé :', width: 7, styles: t.row),
        PosColumn(
          text: '${montantPaye.toStringAsFixed(0)} FC',
          width: 5,
          styles: t.amountSingle,
        ),
      ]);

      if (resteAPayerMois > 0) {
        bytes += generator.row([
          PosColumn(text: 'Reste à payer :', width: 7, styles: t.row),
          PosColumn(
            text: '${resteAPayerMois.toStringAsFixed(0)} FC',
            width: 5,
            styles: t.amountSingle,
          ),
        ]);
      } else {
        bytes += generator.text(
          '>>> MOIS COMPLÈTEMENT PAYÉ <<<',
          styles: t.bodyCenter,
        );
      }
      bytes += _sepLine(generator, t, '-');

      bytes += _signatureBlock(generator, t);
      bytes += _footer(generator, t);

      final ok = await _sendRawBytes(printerName, Uint8List.fromList(bytes));
      _log('printReceipt terminé pour "$studentName" ($studentId) — '
          'résultat=$ok');
      return ok;
    } catch (e, st) {
      _log('EXCEPTION dans printReceipt pour "$studentName" ($studentId) : '
          '$e\n$st');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // REÇU : LISTE DE TRANSACTIONS
  // ---------------------------------------------------------------------------

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
    _log('printTransactionsReceipt appelé — imprimante="$printerName" '
        'élève="$studentName" ($studentId) nbTransactions='
        '${transactions.length} duplicata=$duplicata');

    if (!Platform.isWindows && !Platform.isMacOS) {
      _log('printTransactionsReceipt — plateforme non supportée '
          '(${Platform.operatingSystem})');
      return false;
    }
    if (transactions.isEmpty) {
      _log('printTransactionsReceipt — aucune transaction fournie, abandon.');
      return false;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      final t = await _loadTheme();

      generator.setGlobalCodeTable('CP1252');

      final now = DateTime.now();
      final String today =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final String heure =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final String numRecu = receiptNumber ??
          'RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour}${now.minute}${now.second}';

      bytes += _schoolHeader(
        generator,
        t,
        schoolName: schoolName,
        logoBytes: logoBytes,
        contexte: 'printTransactionsReceipt',
      );

      final String texteTitre =
      duplicata ? 'REÇU DE PAIEMENT (DUPLICATA)' : titre;
      bytes += generator.text(texteTitre, styles: t.titleFor(texteTitre));
      bytes += generator.text(
        'Année scolaire : $currentYear',
        styles: t.bodyCenter,
      );
      bytes += _sepLine(generator, t, '=');

      bytes += generator.text('Nom complet :', styles: t.label);
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: t.nameStyle(studentName),
      );
      bytes += _infoBlock(generator, t, studentId, studentName);
      bytes += _sepLine(generator, t, '.');

      bytes += generator.row([
        PosColumn(text: 'Reçu : $numRecu', width: 12, styles: t.small),
      ]);
      bytes += generator.row([
        PosColumn(text: 'ID : $studentId', width: 6, styles: t.row),
        PosColumn(text: 'Cl. : $classe', width: 6, styles: t.row),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Sect. : $section', width: 6, styles: t.row),
        PosColumn(text: '$today $heure', width: 6, styles: t.small),
      ]);

      bytes += _sepLine(generator, t, '-');
      bytes += generator.text(
        transactions.length > 1
            ? 'DÉTAIL DES PAIEMENTS (${transactions.length})'
            : 'DÉTAIL DU PAIEMENT',
        styles: t.bodyCenter,
      );
      bytes += _sepLine(generator, t, '-');

      double total = 0;
      final sorted = List<Map<String, dynamic>>.from(transactions)
        ..sort((a, b) {
          final dateA = (a['date'] ?? '').toString();
          final dateB = (b['date'] ?? '').toString();
          return dateA.compareTo(dateB);
        });

      for (final tr in sorted) {
        final mois = (tr['mois'] ?? '').toString();
        final montant = (tr['amount'] as num?)?.toDouble() ??
            (tr['montant'] as num?)?.toDouble() ??
            0.0;
        final date = (tr['date'] ?? '').toString();
        total += montant;

        bytes += generator.row([
          PosColumn(
            text: mois.isNotEmpty ? mois : '-',
            width: 6,
            styles: t.row,
          ),
          PosColumn(
            text: '${montant.toStringAsFixed(0)} FC',
            width: 6,
            styles: t.rowRight,
          ),
        ]);
        if (date.isNotEmpty) {
          bytes += generator.text(
            '   le $date',
            styles: t.detail,
          );
        }
      }

      bytes += _sepLine(generator, t, '-');
      bytes += generator.row([
        PosColumn(text: 'TOTAL PAYÉ :', width: 6, styles: t.strong),
        PosColumn(
          text: '${total.toStringAsFixed(0)} FC',
          width: 6,
          styles: t.strongRight,
        ),
      ]);
      bytes += _sepLine(generator, t, '-');

      bytes += _signatureBlock(generator, t);
      bytes += _footer(generator, t);

      final ok = await _sendRawBytes(printerName, Uint8List.fromList(bytes));
      _log('printTransactionsReceipt terminé pour "$studentName" '
          '($studentId) — résultat=$ok');
      return ok;
    } catch (e, st) {
      _log('EXCEPTION dans printTransactionsReceipt pour "$studentName" '
          '($studentId) : $e\n$st');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // REÇU : BILAN + HISTORIQUE DES PAIEMENTS D'UN ÉLÈVE
  // ---------------------------------------------------------------------------

  static Future<bool> printStudentPaymentHistoryReceipt({
    required String printerName,
    required String schoolName,
    required String currentYear,
    required String studentName,
    required String studentId,
    required String classe,
    required String section,
    required List<String> months,
    required Map<String, double> paidByMonth,
    required Map<String, double> requiredByMonth,
    required double totalPaye,
    required double totalRequis,
    required List<Map<String, dynamic>> transactions,
    Uint8List? logoBytes,
    bool duplicata = false,
  }) async {
    _log('printStudentPaymentHistoryReceipt appelé — imprimante='
        '"$printerName" élève="$studentName" ($studentId) '
        'nbTransactions=${transactions.length} duplicata=$duplicata');

    if (!Platform.isWindows && !Platform.isMacOS) {
      _log('printStudentPaymentHistoryReceipt — plateforme non supportée '
          '(${Platform.operatingSystem})');
      return false;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      final t = await _loadTheme();

      generator.setGlobalCodeTable('CP1252');

      final now = DateTime.now();
      final String today =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final String heure =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      bytes += _schoolHeader(
        generator,
        t,
        schoolName: schoolName,
        logoBytes: logoBytes,
        contexte: 'printStudentPaymentHistoryReceipt',
      );

      final String texteTitre =
      duplicata ? 'REÇU DE PAIEMENT (DUPLICATA)' : 'REÇU DE PAIEMENT';
      bytes += generator.text(texteTitre, styles: t.titleFor(texteTitre));
      bytes += generator.text(
        'Année scolaire : $currentYear',
        styles: t.bodyCenter,
      );
      bytes += _sepLine(generator, t, '=');

      bytes += generator.text('Nom complet :', styles: t.label);
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: t.nameStyle(studentName),
      );
      bytes += _infoBlock(generator, t, studentId, studentName);
      bytes += _sepLine(generator, t, '.');

      bytes += generator.row([
        PosColumn(text: 'ID : $studentId', width: 6, styles: t.row),
        PosColumn(text: 'Promo : $classe', width: 6, styles: t.row),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Sect. : $section', width: 6, styles: t.row),
        PosColumn(text: '$today $heure', width: 6, styles: t.small),
      ]);

      bytes += _sepLine(generator, t, '-');
      bytes += generator.text('BILAN FINANCIER', styles: t.bodyCenter);
      bytes += _sepLine(generator, t, '-');

      for (final mois in months) {
        final double paye = paidByMonth[mois] ?? 0.0;
        final double requis = requiredByMonth[mois] ?? 0.0;
        final double reste = requis - paye;
        final bool nonCommence = paye == 0 && reste == requis;

        String statut;
        if (reste <= 0) {
          statut = 'OK';
        } else if (nonCommence) {
          statut = '-';
        } else {
          statut = '-${reste.toStringAsFixed(0)} FC';
        }

        bytes += generator.row([
          PosColumn(
            text: mois,
            width: 4,
            styles: t.monthStyle(!nonCommence),
          ),
          PosColumn(
            text: '${paye.toStringAsFixed(0)} / ${requis.toStringAsFixed(0)}',
            width: 5,
            styles: t.monthStyle(!nonCommence),
          ),
          PosColumn(
            text: statut,
            width: 3,
            styles: t.monthStyle(!nonCommence, align: PosAlign.right),
          ),
        ]);
      }

      final double resteTotal = totalRequis - totalPaye;

      bytes += _sepLine(generator, t, '-');
      bytes += generator.row([
        PosColumn(text: 'Total payé :', width: 6, styles: t.row),
        PosColumn(
          text: '${totalPaye.toStringAsFixed(0)} FC',
          width: 6,
          styles: t.rowRight,
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Total requis :', width: 6, styles: t.row),
        PosColumn(
          text: '${totalRequis.toStringAsFixed(0)} FC',
          width: 6,
          styles: t.rowRight,
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Reste à payer :', width: 6, styles: t.strong),
        PosColumn(
          text: '${(resteTotal > 0 ? resteTotal : 0).toStringAsFixed(0)} FC',
          width: 6,
          styles: t.strongRight,
        ),
      ]);

      bytes += _sepLine(generator, t, '-');
      bytes += generator.text('HISTORIQUE DES PAIEMENTS',
          styles: t.bodyCenter);
      bytes += _sepLine(generator, t, '-');

      final sorted = List<Map<String, dynamic>>.from(transactions)
        ..sort((a, b) => (a['date'] ?? '')
            .toString()
            .compareTo((b['date'] ?? '').toString()));

      if (sorted.isEmpty) {
        bytes += generator.text(
          'Aucune transaction enregistrée.',
          styles: t.empty,
        );
      } else {
        for (final tr in sorted) {
          final String date = (tr['date'] ?? '').toString().isEmpty
              ? '-'
              : tr['date'].toString();
          final String mois = (tr['mois'] ?? '').toString().isEmpty
              ? '-'
              : tr['mois'].toString();
          final double montant = (tr['amount'] as num?)?.toDouble() ??
              (tr['montant'] as num?)?.toDouble() ??
              0.0;

          bytes += generator.row([
            PosColumn(
              text: '$date - $mois',
              width: 8,
              styles: t.historyLeft,
            ),
            PosColumn(
              text: '${montant.toStringAsFixed(0)} FC',
              width: 4,
              styles: t.rowRight,
            ),
          ]);
        }
      }

      if (t.signatureOnHistory) {
        bytes += _sepLine(generator, t, '-');
        bytes += _signatureBlock(generator, t);
      }
      bytes += _footer(generator, t);

      final ok = await _sendRawBytes(printerName, Uint8List.fromList(bytes));
      _log('printStudentPaymentHistoryReceipt terminé pour "$studentName" '
          '($studentId) — résultat=$ok');
      return ok;
    } catch (e, st) {
      _log('EXCEPTION dans printStudentPaymentHistoryReceipt pour '
          '"$studentName" ($studentId) : $e\n$st');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // REÇU : AUTRE FRAIS (UN SEUL)
  // ---------------------------------------------------------------------------

  static Future<bool> printAutreFraisReceipt({
    required String printerName,
    required String schoolName,
    required String titreFrais,
    required String studentName,
    required String classe,
    required String section,
    required double montant,
    Uint8List? logoBytes,
    bool duplicata = false,
  }) async {
    _log('printAutreFraisReceipt appelé — imprimante="$printerName" '
        'élève="$studentName" frais="$titreFrais" montant=$montant '
        'duplicata=$duplicata');

    if (!Platform.isWindows && !Platform.isMacOS) {
      _log('printAutreFraisReceipt — plateforme non supportée '
          '(${Platform.operatingSystem})');
      return false;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      final t = await _loadTheme();

      generator.setGlobalCodeTable('CP1252');

      final now = DateTime.now();
      final String today =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final String heure =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      bytes += _schoolHeader(
        generator,
        t,
        schoolName: schoolName,
        logoBytes: logoBytes,
        contexte: 'printAutreFraisReceipt',
      );

      final String texteTitre = duplicata
          ? '${titreFrais.toUpperCase()} (DUPLICATA)'
          : titreFrais.toUpperCase();
      bytes += generator.text(texteTitre, styles: t.titleFor(texteTitre));
      bytes += _sepLine(generator, t, '=');

      bytes += generator.text('Nom complet :', styles: t.label);
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: t.nameStyle(studentName),
      );
      bytes += _infoBlock(generator, t, '', studentName);

      bytes += generator.row([
        PosColumn(text: 'Cl. : $classe', width: 6, styles: t.row),
        PosColumn(text: 'Sect. : $section', width: 6, styles: t.row),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Date :', width: t.dateLabelWidth, styles: t.row),
        PosColumn(
            text: '$today $heure',
            width: 12 - t.dateLabelWidth,
            styles: t.dateValue),
      ]);

      bytes += _sepLine(generator, t, '-');
      bytes += generator.row([
        PosColumn(text: 'Montant payé :', width: 7, styles: t.row),
        PosColumn(
          text: '${montant.toStringAsFixed(0)} FC',
          width: 5,
          styles: t.amountSingle,
        ),
      ]);
      bytes += _sepLine(generator, t, '-');

      bytes += _signatureBlock(generator, t);
      bytes += _footer(generator, t, conserver: false);

      final ok = await _sendRawBytes(printerName, Uint8List.fromList(bytes));
      _log('printAutreFraisReceipt terminé pour "$studentName" '
          '("$titreFrais") — résultat=$ok');
      return ok;
    } catch (e, st) {
      _log('EXCEPTION dans printAutreFraisReceipt pour "$studentName" '
          '("$titreFrais") : $e\n$st');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // REÇU : AUTRES FRAIS (PLUSIEURS PAIEMENTS)
  // ---------------------------------------------------------------------------

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
    _log('printAutresFraisTransactionsReceipt appelé — imprimante='
        '"$printerName" élève="$studentName" nbPaiements=${paiements.length} '
        'duplicata=$duplicata');

    if (!Platform.isWindows && !Platform.isMacOS) {
      _log('printAutresFraisTransactionsReceipt — plateforme non '
          'supportée (${Platform.operatingSystem})');
      return false;
    }
    if (paiements.isEmpty) {
      _log('printAutresFraisTransactionsReceipt — aucun paiement fourni, '
          'abandon.');
      return false;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      final t = await _loadTheme();

      generator.setGlobalCodeTable('CP1252');

      final now = DateTime.now();
      final String today =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final String heure =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      bytes += _schoolHeader(
        generator,
        t,
        schoolName: schoolName,
        logoBytes: logoBytes,
        contexte: 'printAutresFraisTransactionsReceipt',
      );

      final String texteTitre =
      duplicata ? 'AUTRES FRAIS (DUPLICATA)' : 'REÇU — AUTRES FRAIS';
      bytes += generator.text(texteTitre, styles: t.titleFor(texteTitre));
      bytes += _sepLine(generator, t, '=');

      bytes += generator.text('Nom complet :', styles: t.label);
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: t.nameStyle(studentName),
      );
      bytes += _infoBlock(generator, t, '', studentName);

      bytes += generator.row([
        PosColumn(text: 'Cl. : $classe', width: 6, styles: t.row),
        PosColumn(text: 'Sect. : $section', width: 6, styles: t.row),
      ]);
      bytes += generator.text(
        'Imprimé le : $today $heure',
        styles: t.detail,
      );

      bytes += _sepLine(generator, t, '-');
      bytes += generator.text(
        paiements.length > 1
            ? 'DÉTAIL DES FRAIS (${paiements.length})'
            : 'DÉTAIL DU FRAIS',
        styles: t.bodyCenter,
      );
      bytes += _sepLine(generator, t, '-');

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
            styles: t.row,
          ),
          PosColumn(
            text: '${montant.toStringAsFixed(0)} FC',
            width: 5,
            styles: t.rowRight,
          ),
        ]);
        if (date.isNotEmpty) {
          bytes += generator.text(
            '   $date',
            styles: t.detail,
          );
        }
      }

      bytes += _sepLine(generator, t, '-');
      bytes += generator.row([
        PosColumn(text: 'TOTAL PAYÉ :', width: 6, styles: t.strong),
        PosColumn(
          text: '${total.toStringAsFixed(0)} FC',
          width: 6,
          styles: t.strongRight,
        ),
      ]);
      bytes += _sepLine(generator, t, '-');

      bytes += _signatureBlock(generator, t);
      bytes += _footer(generator, t, conserver: false);

      final ok = await _sendRawBytes(printerName, Uint8List.fromList(bytes));
      _log('printAutresFraisTransactionsReceipt terminé pour '
          '"$studentName" — résultat=$ok');
      return ok;
    } catch (e, st) {
      _log('EXCEPTION dans printAutresFraisTransactionsReceipt pour '
          '"$studentName" : $e\n$st');
      return false;
    }
  }
}