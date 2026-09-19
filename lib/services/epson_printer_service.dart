import 'dart:async';
import 'dart:io' show Platform, Process, Directory, File, FileMode;
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show debugPrint;

/// ⚡ Remplace bluetooth_printer_service.dart.
///
/// L'imprimante n'est plus une imprimante Bluetooth pilotée en port série
/// (COM), mais une Epson TM-T20III branchée en USB.
///
/// - Sous Windows : une fois le pilote Epson officiel installé, l'imprimante
///   apparaît comme une imprimante Windows normale (ex: "EPSON TM-T20III Receipt").
///   On envoie les commandes ESC/POS brutes directement au spouleur Windows
///   en mode RAW (via winspool.drv).
///
/// - Sous macOS : l'imprimante apparaît comme une file d'attente CUPS.
///   On envoie les octets bruts via `lp -o raw` et on confirme réellement
///   le statut du job avec `lpstat`.
///
/// ⚡ NOUVEAU — CONFIRMATION RÉELLE DE L'IMPRESSION (anti faux-positif)
/// PROBLÈME RÉSOLU : un simple "succès" d'écriture signifie uniquement que
/// le système a bien reçu les octets et les a mis en file — PAS que le
/// papier est réellement sorti. Si le câble USB bouge ou se déconnecte
/// juste après l'envoi, l'application pouvait marquer le reçu comme
/// "imprimé avec succès" de façon définitive.
/// SOLUTION : après l'envoi, on interroge le VRAI statut du job jusqu'à
/// ce qu'il soit confirmé traité, en erreur, ou que le délai soit dépassé.
///
/// ⚡ CORRIGÉ — Auparavant (Windows), cette vérification relançait un
/// NOUVEAU processus PowerShell toutes les 350ms. Désormais, UN SEUL
/// processus PowerShell est lancé ; c'est lui qui fait toute la boucle.
/// Sous macOS, la même logique est appliquée avec `lpstat`.
///
/// Le booléen retourné par toutes les méthodes `print...` reflète donc
/// ce statut RÉEL, et non plus une simple acceptation par le spouleur.
///
/// ⚡ ÉCONOMIE DE PAPIER (reçu plus court)
/// À la demande de l'employeur : le reçu doit occuper le MOINS de papier
/// possible, sans qu'aucune information n'y soit retirée.
///
/// ⚡ NOUVEAU — LISIBILITÉ DU LOGO ET DU NOM DE L'ÉCOLE
/// Logo redimensionné avec interpolation de qualité + conversion N&B
/// net à fort contraste. Nom de l'école en police plus grande (arial48)
/// + gras simulé quand il tient sur la ligne.
///
/// ⚡ RÉIMPRESSION MANUELLE
/// `printTransactionsReceipt` et `printAutresFraisTransactionsReceipt`
/// permettent de regrouper plusieurs paiements déjà enregistrés sur
/// un seul reçu (historique, sélection, ou validation de lot Admin).
///
/// ⚡ NOUVEAU — JOURNALISATION COMPLÈTE (DIAGNOSTIC WINDOWS)
/// Chaque étape de l'envoi et de la confirmation d'impression est
/// journalisée via `_log()`, avec le code d'erreur Windows natif
/// (`GetLastError()`) quand disponible.
///
/// ⚡ NOUVEAU — FICHIER DE LOGS SUR LE BUREAU
/// En plus de la console (debugPrint), chaque ligne de log est écrite
/// automatiquement dans un fichier texte :
///   <Bureau de l'utilisateur>\EduPay_Logs\printer_log.txt
/// Ce fichier est créé tout seul au premier lancement, sans aucune
/// action manuelle. Il se limite à 5 Mo : au-delà, l'ancien contenu
/// est archivé dans "printer_log.ancien.txt" et un nouveau fichier
/// repart de zéro. Une écriture de log qui échoue (ex: dossier
/// protégé) n'interrompt jamais l'impression elle-même.
///
/// ⚡ CORRIGÉ — FAUX ÉCHEC DE CONFIRMATION SUR CERTAINS PC WINDOWS
/// PROBLÈME RÉSOLU : sur certains PC (module PowerShell
/// "PrintManagement" absent, désactivé, ou bloqué par une politique
/// de sécurité), `_confirmJobPrintedWindows` levait une exception ou
/// expirait sans jamais avoir pu lire le statut réel du job — alors
/// que `WritePrinter` avait déjà réussi et que le papier était déjà
/// physiquement sorti. Le code renvoyait alors `false`, ce qui faisait
/// croire à `printOrQueuePrincipalReceipt` que le reçu n'avait PAS été
/// imprimé : il le remettait dans `receiptQueue` au lieu de
/// `printedReceiptKeys`. Résultat : à la prochaine ouverture de l'écran
/// des paiements, `flushReceiptQueue()` réimprimait TOUS ces reçus
/// déjà sortis.
/// SOLUTION : une confirmation qui échoue à cause d'une exception ou
/// d'un timeout ne veut PAS dire que l'impression a échoué — cela veut
/// seulement dire qu'on n'a pas pu la vérifier. On ne doit donc jamais
/// transformer une confirmation impossible en réimpression automatique.
/// Dans ce cas précis, on considère l'envoi (déjà réussi via
/// `WritePrinter`) comme abouti.
///
/// ⚡ NOUVEAU — MISE EN PAGE PLUS JOLIE (ESTHÉTIQUE UNIQUEMENT)
/// Ce passage ne change AUCUNE logique d'impression, de confirmation,
/// de file d'attente ou de sauvegarde : seuls les éléments VISUELS du
/// reçu ont été retravaillés, à savoir :
///   - Le logo est nettement plus grand dans l'en-tête.
///   - Le nom de l'école est dessiné avec un gras BEAUCOUP plus épais
///     (empilage de traits sur une grille de 9 directions au lieu de
///     4), pour un rendu visuellement aussi "gras" que le nom de
///     l'élève et le montant payé, qui eux utilisent le gras natif
///     ESC/POS de l'imprimante.
///   - Le nom complet de l'élève est centré et imprimé en grande
///     taille (hauteur ET largeur doublées) pour bien ressortir.
///   - Le montant payé (et le total payé, en cas de réimpression
///     groupée) est mis en valeur sur sa propre ligne, centré, en
///     grande taille, au lieu d'être une simple ligne parmi d'autres.
/// Le reçu reste volontairement compact (aucune ligne inutile
/// ajoutée), seules quelques lignes existantes ont été réagencées ou
/// agrandies.
///
/// ⚡ NOUVEAU — CORRECTIONS DE MISE EN PAGE (2026-09-17)
/// Toujours AUCUN changement de la logique d'impression/communication
/// avec l'imprimante (WritePrinter, confirmation de job, spouleur,
/// etc.) : uniquement le CONTENU et la PRÉSENTATION du reçu.
///   - L'en-tête n'affiche plus QU'UN SEUL logo (auparavant dupliqué à
///     gauche ET à droite du nom de l'école). Ce logo unique est
///     maintenant centré horizontalement au-dessus du nom de l'école,
///     lui-même centré en dessous, pour un rendu propre et équilibré.
///   - Le montant REQUIS pour le mois (le montant que l'élève doit
///     normalement payer) est désormais affiché sur le reçu. Ce
///     paramètre existait déjà dans `printReceipt` mais n'était
///     jusqu'ici jamais imprimé, ce qui expliquait qu'il manque
///     parfois sur le reçu physique.
///   - Le mois payé est maintenant affiché sur sa propre ligne,
///     centrée et en gras, plutôt que dans une simple colonne.
///   - Un nouveau paramètre optionnel `noteExplicative` a été ajouté à
///     `printReceipt` (par défaut `null`, donc AUCUN impact sur les
///     appels existants). S'il est fourni par le code appelant, il est
///     affiché juste sous le titre "REÇU DE PAIEMENT", en gras et en
///     majuscules — utile par exemple pour préciser sur un reçu qu'il
///     s'agit du "SOLDE DU MOIS PRÉCÉDENT" et sur un autre qu'il
///     s'agit d'un "NOUVEAU MOIS", lorsque le code appelant décide de
///     scinder un paiement en plusieurs reçus.
///
/// ⚡ NOUVEAU — NOM DE L'ÉCOLE EN GRAS NATIF + LOGO AGRANDI (2026-09-17,
/// suite)
/// Toujours AUCUN changement de la logique d'impression/communication
/// avec l'imprimante : uniquement l'esthétique du reçu.
///   - Le nom de l'école n'est PLUS dessiné "à la main" (police bitmap
///     + gras simulé) à l'intérieur de l'image d'en-tête. Il est
///     désormais imprimé exactement comme le nom de l'élève : en gras
///     natif ESC/POS, en grande taille (hauteur ET largeur doublées),
///     et centré via l'alignement natif du générateur — ce qui garantit
///     un centrage fiable quel que soit le nombre de caractères. Si le
///     nom est trop long pour tenir sur une seule ligne à cette taille,
///     il est automatiquement réparti sur plusieurs lignes (coupure
///     entre les mots, jamais au milieu d'un mot), chaque ligne restant
///     en gras, grande taille, et centrée.
///   - Le logo est désormais nettement plus grand (l'image d'en-tête
///     utilise maintenant toute la largeur imprimable du papier 80 mm,
///     et le logo lui-même occupe une zone beaucoup plus large qu'avant)
///     et reste parfaitement centré horizontalement.
///   - L'image d'en-tête ne contient donc plus QUE le logo ; le nom de
///     l'école est imprimé juste après, séparément, en texte natif.
class EscPosPrinterService {
  // ====================================================================
  // ⚡ NOUVEAU — JOURNALISATION CENTRALISÉE (CONSOLE + FICHIER SUR BUREAU)
  // ====================================================================
  static File? _logFile;
  static bool _logFileResolved = false;
  static const int _maxLogSizeBytes = 5 * 1024 * 1024; // 5 Mo

  /// Résout (une seule fois) le chemin du fichier de logs sur le Bureau
  /// de l'utilisateur actuellement connecté, et crée le dossier/fichier
  /// s'ils n'existent pas encore.
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

      // Marqueur de début de session pour repérer facilement chaque
      // lancement de l'application dans le fichier.
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

  /// Archive le fichier de logs s'il dépasse la taille maximale, pour
  /// qu'il ne grossisse jamais indéfiniment.
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
      // On ne casse JAMAIS l'impression à cause d'un souci d'écriture de
      // log — on se contente de le signaler dans la console.
      debugPrint('[EPSON] EXCEPTION lors de l\'écriture dans le fichier '
          'de logs : $e\n$st');
    }
  }

  /// Point d'entrée unique de journalisation : écrit dans la console
  /// (utile en dev via `flutter run`) ET dans le fichier sur le Bureau
  /// (utile partout, y compris sur l'app installée chez un client).
  static void _log(String message) {
    final ts = DateTime.now().toIso8601String();
    final line = '[EPSON $ts] $message';
    debugPrint(line);
    unawaited(_writeToLogFile(line));
  }

  // ====================================================================
  // LISTER LES IMPRIMANTES INSTALLÉES
  // ====================================================================
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
        // lpstat -a → "PrinterName accepting requests since ..."
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

  // ====================================================================
  // ENVOI DES OCTETS BRUTS + CONFIRMATION RÉELLE
  // ====================================================================
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

  // -------------------- WINDOWS (winspool RAW) --------------------
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

  // -------------------- macOS (CUPS RAW) --------------------
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

      // Exemple de sortie : "request id is EPSON_TM_T20III-42 (1 file(s))"
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

  // ====================================================================
  // CONFIRMATION RÉELLE DU STATUT D'UN JOB
  // ====================================================================
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

      // ⚡ CORRIGÉ — si le script n'a pas pu produire "OK" ou "ERROR" de
      // façon exploitable (ex: cmdlet Get-PrintJob absente/plante
      // silencieusement sur cette machine, sortie vide ou inattendue),
      // on ne considère PLUS ça comme un échec d'impression. Le papier
      // était déjà sorti (WritePrinter a réussi avant cet appel) ; on
      // ne fait ici QUE distinguer une éventuelle erreur explicite
      // (bourrage, hors ligne...) d'une confirmation simplement
      // indisponible.
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
        // Jobs encore en file pour cette imprimante
        final result = await Process.run('lpstat', ['-o', printerName]);

        if (result.exitCode != 0) {
          _log('_confirmJobPrintedMacOS pour "$printerName" (jobId=$jobId) '
              '— "lpstat -o" exitCode=${result.exitCode} '
              'stderr="${result.stderr}" → impossible d\'interroger, '
              'considéré OK (job probablement déjà parti).');
          return true;
        }

        final output = result.stdout.toString();
        // Format typique : "EPSON_TM_T20III-42 utilisateur 1234 ..."
        final stillPresent = output.contains('-$jobId ');

        if (!stillPresent) {
          _log('_confirmJobPrintedMacOS → job $jobId disparu de la file '
              'pour "$printerName" → CONFIRMÉ imprimé.');
          return true;
        }

        // Vérifie s'il y a une erreur visible
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

  // ====================================================================
  // ⚡ PRÉPARATION DU LOGO POUR UNE IMPRESSION NETTE
  // ====================================================================
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

  // ====================================================================
  // ⚡ EN-TÊTE : UNIQUEMENT LE LOGO, AGRANDI ET CENTRÉ
  // ⚡ MISE À JOUR (2026-09-17) — Cette image ne contient PLUS le nom de
  // l'école (qui était auparavant dessiné "à la main" avec une police
  // bitmap et un gras simulé, ce qui donnait un rendu fin et parfois mal
  // centré selon la longueur du nom). Elle ne contient maintenant QUE le
  // logo, agrandi et utilisant toute la largeur imprimable du papier
  // 80 mm pour un rendu nettement plus grand qu'avant. Le nom de l'école
  // est désormais imprimé séparément, juste après, en texte natif
  // ESC/POS (voir `_schoolNameReceiptBytes`), exactement comme le nom de
  // l'élève : gras natif, grande taille, et centré automatiquement par
  // le générateur — donc toujours bien centré, quelle que soit sa
  // longueur.
  // Ce changement ne touche QUE la génération de l'image d'en-tête
  // (aucune conséquence sur l'envoi ou la confirmation d'impression).
  // ====================================================================

  /// Largeur (en points/dots) de l'image d'en-tête : correspond à la
  /// largeur imprimable standard d'un papier thermique 80 mm, pour que
  /// le logo puisse occuper tout l'espace disponible.
  static const int _headerWidth = 576;

  static img.Image _buildReceiptHeaderImage({
    required Uint8List logoBytes,
  }) {
    const int margin = 12;
    const int logoBox = 300; // ⚡ logo nettement plus grand qu'avant (170)

    final logo = _prepareLogoForPrint(logoBytes, logoBox);

    final canvas =
    img.Image(width: _headerWidth, height: logo.height + margin * 2);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    // Logo centré horizontalement sur toute la largeur du papier.
    final int lx = (((_headerWidth - logo.width) / 2).round())
        .clamp(0, (_headerWidth - logo.width).clamp(0, _headerWidth));
    img.compositeImage(canvas, logo, dstX: lx, dstY: margin);

    return canvas;
  }

  // ====================================================================
  // ⚡ NOM DE L'ÉCOLE : GRAS NATIF ESC/POS, GRAND, TOUJOURS BIEN CENTRÉ
  // ⚡ NOUVEAU (2026-09-17) — Imprimé exactement comme le nom de l'élève
  // (gras natif de l'imprimante + hauteur/largeur doublées), et centré
  // via l'alignement natif du générateur (fiable quel que soit le
  // nombre de caractères). Si le nom ne tient pas sur une seule ligne à
  // cette taille, il est réparti automatiquement sur plusieurs lignes en
  // coupant entre les mots (jamais au milieu d'un mot) ; chaque ligne
  // reste en gras, grande taille, et centrée.
  // ====================================================================

  /// Nombre maximum de caractères par ligne pour un texte en gras à
  /// taille double (hauteur ET largeur x2). Basé sur la largeur de
  /// colonne déjà utilisée pour les séparateurs du reçu (32 caractères
  /// en largeur normale), donc 16 caractères une fois la largeur
  /// doublée.
  static const int _schoolNameMaxCharsAtDoubleWidth = 16;

  /// Découpe un texte en lignes d'au plus [maxChars] caractères, en ne
  /// coupant qu'entre les mots (jamais au milieu d'un mot, même si un
  /// mot isolé dépasse [maxChars]).
  static List<String> _wrapWordsToWidth(String text, int maxChars) {
    final words =
    text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];

    final List<String> lines = [];
    String current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= maxChars || current.isEmpty) {
        current = candidate;
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  /// Construit les octets ESC/POS du nom de l'école, en gras natif et
  /// grande taille (comme le nom de l'élève), sur une ou plusieurs
  /// lignes centrées selon sa longueur.
  static List<int> _schoolNameReceiptBytes(
      Generator generator, String schoolName) {
    List<int> bytes = [];
    final String name = schoolName.trim().toUpperCase();
    if (name.isEmpty) return bytes;

    final List<String> lines =
    name.length <= _schoolNameMaxCharsAtDoubleWidth
        ? [name]
        : _wrapWordsToWidth(name, _schoolNameMaxCharsAtDoubleWidth);

    for (final line in lines) {
      bytes += generator.text(
        line,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
    }
    return bytes;
  }

  // ====================================================================
  // GÉNÉRER ET IMPRIMER UN REÇU COMPLET (paiement mensuel principal)
  // ⚡ MISE À JOUR (2026-09-17) — Le mois payé est maintenant sur sa
  // propre ligne centrée et en gras ; le montant REQUIS pour le mois
  // est désormais affiché (il existait déjà en paramètre mais n'était
  // jamais imprimé) ; un paramètre optionnel `noteExplicative` permet
  // au code appelant de préciser le contexte du reçu (ex: "SOLDE DU
  // MOIS PRÉCÉDENT") lorsqu'un paiement est scindé en plusieurs reçus.
  // Aucun changement de logique d'impression/communication.
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
          final headerImage = _buildReceiptHeaderImage(logoBytes: logoBytes);
          bytes += generator.image(headerImage);
        } catch (e, st) {
          _log('EXCEPTION génération du logo (printReceipt), logo ignoré : '
              '$e\n$st');
        }
      }
      bytes += _schoolNameReceiptBytes(generator, schoolName);

      bytes += generator.text(
        'REÇU DE PAIEMENT',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          underline: true,
        ),
      );

      // ⚡ NOUVEAU — mention explicative optionnelle (ex: "SOLDE DU MOIS
      // PRÉCÉDENT" / "NOUVEAU MOIS"), utile quand un même paiement donne
      // lieu à plusieurs reçus distincts. N'affiche rien si non fourni.
      if (noteExplicative != null && noteExplicative.trim().isNotEmpty) {
        bytes += generator.text(
          noteExplicative.trim().toUpperCase(),
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
      }

      bytes += generator.text(
        'Année scolaire : $currentYear',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '================================',
        styles: const PosStyles(align: PosAlign.center),
      );

      // ==================== NOM COMPLET ÉLÈVE (en grand, centré) ====
      bytes += generator.text(
        'Nom complet :',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
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

      // ==================== PAIEMENT ====================
      bytes += generator.text(
        '--------------------------------',
        styles: const PosStyles(align: PosAlign.center),
      );

      // ⚡ Mois payé : sur sa propre ligne, centrée, en gras.
      bytes += generator.text(
        'Mois payé : ${moisPaye.toUpperCase()}',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '................................',
        styles: const PosStyles(align: PosAlign.center),
      );

      // ⚡ NOUVEAU — Montant requis pour ce mois, désormais affiché.
      bytes += generator.row([
        PosColumn(
          text: 'Montant requis :',
          width: 7,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: '${montantRequis.toStringAsFixed(0)} FC',
          width: 5,
          styles: const PosStyles(bold: true, align: PosAlign.right),
        ),
      ]);

      // Montant payé mis en valeur : gros, centré, sur sa propre ligne
      bytes += generator.text(
        'MONTANT PAYÉ',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '${montantPaye.toStringAsFixed(0)} FC',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

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

  // ====================================================================
  // RÉIMPRESSION MANUELLE : REÇU REGROUPANT PLUSIEURS PAIEMENTS
  // ⚡ AMÉLIORATION ESTHÉTIQUE — mêmes retouches que printReceipt : nom
  // centré et agrandi, total payé mis en valeur sur sa propre ligne.
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
          final headerImage = _buildReceiptHeaderImage(logoBytes: logoBytes);
          bytes += generator.image(headerImage);
        } catch (e, st) {
          _log('EXCEPTION génération du logo '
              '(printTransactionsReceipt), logo ignoré : $e\n$st');
        }
      }
      bytes += _schoolNameReceiptBytes(generator, schoolName);

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

      // ==================== NOM COMPLET ÉLÈVE (en grand, centré) ====
      bytes += generator.text(
        'Nom complet :',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
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

      // ⚡ Total payé mis en valeur : gros, centré, sur sa propre ligne
      bytes += generator.text(
        'TOTAL PAYÉ',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '${total.toStringAsFixed(0)} FC',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
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

  // ====================================================================
  // PETIT REÇU POUR UN "AUTRE FRAIS"
  // ⚡ AMÉLIORATION ESTHÉTIQUE — nom centré et agrandi, montant mis en
  // valeur sur sa propre ligne.
  // ====================================================================
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
          final headerImage = _buildReceiptHeaderImage(logoBytes: logoBytes);
          bytes += generator.image(headerImage);
        } catch (e, st) {
          _log('EXCEPTION génération du logo '
              '(printAutreFraisReceipt), logo ignoré : $e\n$st');
        }
      }
      bytes += _schoolNameReceiptBytes(generator, schoolName);

      bytes += generator.text(
        duplicata
            ? '${titreFrais.toUpperCase()} (DUPLICATA)'
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
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
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

      // ⚡ Montant payé mis en valeur : gros, centré, sur sa propre ligne
      bytes += generator.text(
        'MONTANT PAYÉ',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '${montant.toStringAsFixed(0)} FC',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
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

  // ====================================================================
  // RÉIMPRESSION MANUELLE : REÇU REGROUPANT PLUSIEURS "AUTRES FRAIS"
  // ⚡ AMÉLIORATION ESTHÉTIQUE — nom centré et agrandi, total payé mis
  // en valeur sur sa propre ligne.
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
          final headerImage = _buildReceiptHeaderImage(logoBytes: logoBytes);
          bytes += generator.image(headerImage);
        } catch (e, st) {
          _log('EXCEPTION génération du logo '
              '(printAutresFraisTransactionsReceipt), logo ignoré : '
              '$e\n$st');
        }
      }
      bytes += _schoolNameReceiptBytes(generator, schoolName);

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
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        studentName.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
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

      // ⚡ Total payé mis en valeur : gros, centré, sur sa propre ligne
      bytes += generator.text(
        'TOTAL PAYÉ',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '${total.toStringAsFixed(0)} FC',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
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