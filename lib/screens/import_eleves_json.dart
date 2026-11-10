import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../frais_scolaires.dart';
import '../models.dart';

/// Import d'un fichier JSON d'informations d'élèves.
///
/// DEUX MODES :
///  - REMPLACER (par défaut) : le fichier JSON fait foi. Les informations
///    actuelles de l'élève sont remplacées par celles du fichier, et les
///    nouvelles informations sont ajoutées. Option : effacer aussi les
///    informations que le fichier laisse vides.
///  - COMPLÉTER : seules les cases vides de l'application sont remplies,
///    rien de ce qui existe déjà n'est modifié.
///
/// DANS LES DEUX MODES :
///  - Aucun élève n'est créé ni supprimé.
///  - Le numéro du fichier = la position de l'élève dans la liste de l'application
///    filtrée par section + classe (même ordre que la liste papier).
///
/// Format du fichier :
/// { "groupes": [ { "section": "Maternelle", "classe": "2ème",
///                  "eleves": [ { "numero": 1, ... }, ... ] } ] }
class StudentJsonImporter {
  // clé JSON -> libellé de la question personnalisée dans l'application
  static const Map<String, String> _champs = {
    'sexe': 'Sexe',
    'province': 'Province',
    'ecole_origine': "École d'origine",
    'numero_permanent': 'Numéro permanent',
    'religion': 'Religion',
    'profession': 'Profession',
    'date_inscription': "Date d'inscription",
    'telephone': 'Téléphone',
    'telephone2': 'Téléphone 2',
  };

  static String? _clean(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  // 2023-11-11 -> 11/11/2023
  static String _isoToFr(String s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return s;
    return '${m.group(3)}/${m.group(2)}/${m.group(1)}';
  }

  static String _norm(String s) => s.trim().toLowerCase();

  static Future<void> run(BuildContext context, FraisScolaires fs) async {
    final messenger = ScaffoldMessenger.of(context);

    // ---------- 1) Choix du fichier (ouvre le Bureau du Mac) ----------
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    final String? desktop = home == null ? null : '$home/Desktop';

    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON / TXT', extensions: ['json', 'txt'])
        ],
        initialDirectory:
        (desktop != null && Directory(desktop).existsSync())
            ? desktop
            : null,
      );
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text("Impossible d'ouvrir le sélecteur : $e")));
      return;
    }
    if (file == null) return;

    // ---------- 2) Lecture du fichier ----------
    List<dynamic> groupes;
    try {
      final contenu = await file.readAsString();
      final decoded = json.decode(contenu);
      if (decoded is Map && decoded['groupes'] is List) {
        groupes = decoded['groupes'] as List;
      } else if (decoded is List) {
        groupes = decoded;
      } else {
        throw const FormatException('Structure non reconnue');
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Fichier invalide : $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // ---------- 3) Préparation : groupe -> élèves de l'application ----------
    final plans = <_Plan>[];
    for (final g in groupes) {
      if (g is! Map) continue;
      final section = _clean(g['section']) ?? '';
      final classe = _clean(g['classe']) ?? '';
      final fiches = (g['eleves'] as List? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final cible = fs.currentData.eleves
          .where((e) =>
      _norm(e.section) == _norm(section) &&
          _norm(e.classe) == _norm(classe))
          .toList();
      plans.add(_Plan(section, classe, fiches, cible));
    }

    if (plans.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Aucun groupe trouvé dans le fichier.")));
      return;
    }

    // ---------- 4) Résumé + choix du mode + confirmation ----------
    if (!context.mounted) return;
    bool modeRemplacer = true;
    bool effacerVides = false;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text("Importer les informations"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in plans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      "${p.section} — ${p.classe}\n"
                          "Fichier : ${p.fiches.length} fiche(s)  |  "
                          "Application : ${p.cible.length} élève(s)"
                          "${p.fiches.length != p.cible.length ? "\n⚠️ Les nombres ne correspondent pas : seules les fiches ayant un élève au même numéro seront importées." : ""}",
                      style: TextStyle(
                        fontSize: 13,
                        color: p.fiches.length != p.cible.length
                            ? Colors.orange.shade800
                            : Colors.black87,
                      ),
                    ),
                  ),
                const Divider(),
                const Text(
                  "Mode d'importation",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: true,
                  groupValue: modeRemplacer,
                  onChanged: (v) =>
                      setStateDialog(() => modeRemplacer = v ?? true),
                  title: const Text(
                    "Remplacer (le fichier fait foi)",
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    "Les informations actuelles des élèves sont remplacées par "
                        "celles du fichier. Les nouvelles informations sont ajoutées.",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: false,
                  groupValue: modeRemplacer,
                  onChanged: (v) =>
                      setStateDialog(() => modeRemplacer = v ?? false),
                  title: const Text(
                    "Compléter seulement",
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    "Seules les cases vides sont remplies. Rien de ce qui "
                        "existe déjà n'est modifié.",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (modeRemplacer)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: effacerVides,
                    onChanged: (v) =>
                        setStateDialog(() => effacerVides = v ?? false),
                    title: const Text(
                      "Effacer aussi les informations que le fichier laisse vides",
                      style: TextStyle(fontSize: 12.5),
                    ),
                    subtitle: const Text(
                      "L'élève correspondra exactement au fichier : une case "
                          "vide dans le fichier efface l'information actuelle.",
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  modeRemplacer
                      ? "⚠️ Les informations actuelles des élèves concernés "
                      "seront remplacées par celles du fichier."
                      : "Les informations déjà présentes ne seront JAMAIS "
                      "remplacées. Seules les cases vides seront complétées.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: modeRemplacer
                        ? Colors.red.shade700
                        : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler")),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Importer")),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final bool remplacer = modeRemplacer;
    final bool effacer = modeRemplacer && effacerVides;

    // ---------- 5) Questions personnalisées nécessaires ----------
    final Set<String> cleUtilisees = {};
    for (final p in plans) {
      for (final f in p.fiches) {
        for (final cle in _champs.keys) {
          if (_clean(f[cle]) != null) cleUtilisees.add(cle);
        }
      }
    }
    final Map<String, String> libelleFinal = {};
    for (final cle in _champs.keys) {
      if (!cleUtilisees.contains(cle)) continue;
      final label = _champs[cle]!;
      await fs.registerCustomFieldQuestion(label);
      String final_ = label;
      for (final q in fs.config.customFieldQuestions) {
        if (_norm(q) == _norm(label)) {
          final_ = q;
          break;
        }
      }
      libelleFinal[cle] = final_;
    }

    // ---------- 6) Application ----------
    int elevesTouches = 0;
    int champsModifies = 0;
    int sansCorrespondance = 0;

    // Applique une valeur à un champ texte simple. Retourne true si changé.
    bool appliquerTexte({
      required String actuel,
      required String? nouveau,
      required void Function(String) setter,
    }) {
      final vide = actuel.trim().isEmpty;
      if (nouveau != null) {
        if (remplacer) {
          if (actuel.trim() != nouveau) {
            setter(nouveau);
            return true;
          }
        } else if (vide) {
          setter(nouveau);
          return true;
        }
      } else if (effacer && !vide) {
        setter('');
        return true;
      }
      return false;
    }

    for (final p in plans) {
      for (final f in p.fiches) {
        final n = (f['numero'] as num?)?.toInt() ?? 0;
        if (n < 1 || n > p.cible.length) {
          sansCorrespondance++;
          continue;
        }
        final e = p.cible[n - 1];
        int modifies = 0;

        // ----- Champs de base -----
        if (appliquerTexte(
          actuel: e.pereNom,
          nouveau: _clean(f['pere']),
          setter: (v) => e.pereNom = v,
        )) {
          modifies++;
        }
        if (appliquerTexte(
          actuel: e.mereNom,
          nouveau: _clean(f['mere']),
          setter: (v) => e.mereNom = v,
        )) {
          modifies++;
        }
        if (appliquerTexte(
          actuel: e.adresse,
          nouveau: _clean(f['adresse']),
          setter: (v) => e.adresse = v,
        )) {
          modifies++;
        }
        final naissanceBrute = _clean(f['date_naissance']);
        if (appliquerTexte(
          actuel: e.dateNaissance,
          nouveau: naissanceBrute == null ? null : _isoToFr(naissanceBrute),
          setter: (v) => e.dateNaissance = v,
        )) {
          modifies++;
        }

        // ----- Questions personnalisées -----
        libelleFinal.forEach((cle, label) {
          final brute = _clean(f[cle]);
          final String? v = brute == null
              ? null
              : (cle == 'date_inscription' ? _isoToFr(brute) : brute);

          String? cleExistante;
          for (final k in e.customFields.keys) {
            if (_norm(k) == _norm(label)) {
              cleExistante = k;
              break;
            }
          }
          final String actuel =
          cleExistante == null ? '' : (e.customFields[cleExistante] ?? '');
          final bool vide = actuel.trim().isEmpty;

          if (v != null) {
            if (cleExistante == null) {
              e.customFields[label] = v;
              modifies++;
            } else if (remplacer) {
              if (actuel.trim() != v) {
                e.customFields[cleExistante] = v;
                modifies++;
              }
            } else if (vide) {
              e.customFields[cleExistante] = v;
              modifies++;
            }
          } else if (effacer && cleExistante != null && !vide) {
            e.customFields.remove(cleExistante);
            modifies++;
          }
        });

        if (modifies > 0) {
          elevesTouches++;
          champsModifies += modifies;
        }
      }
    }

    await fs.saveData();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          "✅ Import terminé (${remplacer ? "remplacement" : "complément"}) : "
              "$elevesTouches élève(s) mis à jour, "
              "$champsModifies information(s) ${remplacer ? "ajoutée(s) ou remplacée(s)" : "ajoutée(s)"}"
              "${sansCorrespondance > 0 ? ", $sansCorrespondance fiche(s) sans élève correspondant" : ""}. "
              "Pensez à sauvegarder sur le serveur.",
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }
}

class _Plan {
  final String section;
  final String classe;
  final List<Map<String, dynamic>> fiches;
  final List<Eleve> cible;
  _Plan(this.section, this.classe, this.fiches, this.cible);
}