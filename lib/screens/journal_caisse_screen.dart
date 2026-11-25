import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../frais_scolaires.dart';
import '../models.dart';

// ============================================================================
// JOURNAL DE CAISSE — PREUVES DE L'ARGENT REÇU, JOUR PAR JOUR
// ----------------------------------------------------------------------------
// Pourquoi cet écran ?
//   La personne qui compte l'argent à la main compte ce qui est ENTRÉ dans la
//   caisse un jour donné. L'écran « Preuves de paiement (mois par mois) »
//   range l'argent par MOIS PAYÉ (septembre, octobre…) : un parent qui paie
//   septembre + octobre le même jour apparaît dans deux mois différents.
//   Les deux totaux ne se comparent donc pas directement.
//
// Méthode utilisée ici (la même qu'un vrai cahier de caisse) :
//   1. L'argent est rangé par JOUR DE RÉCEPTION.
//   2. Une ligne = un versement = un reçu (même si le versement couvre
//      plusieurs mois), numérotée, avec l'heure, l'élève, la classe, le
//      détail des mois et l'état du reçu.
//   3. On sépare l'argent qui est VRAIMENT dans la caisse (espèces) de
//      l'argent qui n'y est pas : Mobile Money et anciens paiements du
//      cahier saisis plus tard.
//   4. On compare avec l'argent compté à la main : l'écart est calculé et
//      l'application cherche ce qui peut l'expliquer (annulations, montants
//      modifiés, dépenses, filtre de classe…).
//
// LECTURE SEULE : aucune donnée de l'école n'est modifiée.
// ============================================================================

enum ModeVersement { especes, mobile, cahier }

enum PeriodeCaisse { aujourdhui, hier, septJours, ceMois, annee, choisie }

String _deux(int n) => n.toString().padLeft(2, '0');

String isoDate(DateTime d) => '${d.year}-${_deux(d.month)}-${_deux(d.day)}';

String affDateIso(String iso) {
  final p = iso.split('-');
  if (p.length == 3 && p[0].length == 4) return '${p[2]}/${p[1]}/${p[0]}';
  return iso.isEmpty ? 'Date inconnue' : iso;
}

String affDate(DateTime d) => '${_deux(d.day)}/${_deux(d.month)}/${d.year}';

String affHeure(DateTime d) => '${_deux(d.hour)}:${_deux(d.minute)}';

const List<String> _jours = [
  'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
];

String affJourComplet(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iso)) {
    return affDateIso(iso);
  }
  return '${_jours[d.weekday - 1]} ${affDate(d)}';
}

/// Les identifiants de paiement contiennent l'instant exact de
/// l'enregistrement (ex : TX1732540000000000_0). On en tire l'heure.
DateTime? heureDepuisId(String id) {
  final m = RegExp(r'^TXB?(\d{13,17})').firstMatch(id);
  if (m == null) return null;
  final String chiffres = m.group(1)!;
  final int? n = int.tryParse(chiffres);
  if (n == null) return null;
  final DateTime d = chiffres.length >= 16
      ? DateTime.fromMicrosecondsSinceEpoch(n)
      : DateTime.fromMillisecondsSinceEpoch(n);
  if (d.year < 2015 || d.year > 2100) return null;
  return d;
}

/// Lit un montant saisi à la main (« 150 000 », « 150.000 », « 150000 FC »).
double? lireMontantSaisi(String texte) {
  final String chiffres = texte.replaceAll(RegExp(r'[^0-9]'), '');
  if (chiffres.isEmpty) return null;
  return double.tryParse(chiffres);
}

// ============================================================================
// DONNÉES
// ============================================================================

/// Un versement = l'argent remis en une fois (= un reçu).
class LigneVersement {
  final String date; // AAAA-MM-JJ ('' si inconnue)
  final DateTime? heure;
  final String nom;
  final String classe;
  final String section;
  final ModeVersement mode;
  final bool autreFrais;
  final List<String> detail; // ex : « Septembre : 20 000 »
  final double montant;
  final bool? recuImprime; // null = sans objet
  final List<String> remarques;
  final String reference;

  const LigneVersement({
    required this.date,
    required this.heure,
    required this.nom,
    required this.classe,
    required this.section,
    required this.mode,
    required this.autreFrais,
    required this.detail,
    required this.montant,
    required this.recuImprime,
    required this.remarques,
    required this.reference,
  });

  String get libelleMode {
    switch (mode) {
      case ModeVersement.mobile:
        return 'Mobile Money';
      case ModeVersement.cahier:
        return 'Cahier (ancien)';
      case ModeVersement.especes:
        return 'Espèces';
    }
  }

  String get libelleRecu {
    if (recuImprime == null) return '-';
    return recuImprime! ? 'Imprimé' : 'Non imprimé';
  }
}

class JourCaisse {
  final String date;
  final List<LigneVersement> lignes;

  JourCaisse(this.date, this.lignes);

  double _somme(bool Function(LigneVersement) f) =>
      lignes.where(f).fold(0.0, (s, l) => s + l.montant);

  double get especes => _somme((l) => l.mode == ModeVersement.especes);
  double get mobile => _somme((l) => l.mode == ModeVersement.mobile);
  double get cahier => _somme((l) => l.mode == ModeVersement.cahier);
  double get total => _somme((_) => true);
  int get nbEspeces =>
      lignes.where((l) => l.mode == ModeVersement.especes).length;
}

/// Une opération qui peut expliquer un écart (annulation, modification,
/// dépense, entrée d'argent).
class OperationCaisse {
  final DateTime date;
  final String libelle;
  final double montant;
  const OperationCaisse(this.date, this.libelle, this.montant);
}

class JournalCaisse {
  final List<JourCaisse> jours; // le plus récent en premier
  final List<OperationCaisse> annulations;
  final List<OperationCaisse> modifications; // montant = nouveau - ancien
  final List<OperationCaisse> depenses;
  final List<OperationCaisse> entrees;
  final int nbDatesCorrigees;
  final int nbSansRecu;
  final double sansRecu;

  const JournalCaisse({
    required this.jours,
    required this.annulations,
    required this.modifications,
    required this.depenses,
    required this.entrees,
    required this.nbDatesCorrigees,
    required this.nbSansRecu,
    required this.sansRecu,
  });

  Iterable<LigneVersement> get lignes => jours.expand((j) => j.lignes);

  double _somme(bool Function(LigneVersement) f) =>
      lignes.where(f).fold(0.0, (s, l) => s + l.montant);

  double get especes => _somme((l) => l.mode == ModeVersement.especes);
  double get especesScolarite => _somme(
          (l) => l.mode == ModeVersement.especes && !l.autreFrais);
  double get especesAutresFrais =>
      _somme((l) => l.mode == ModeVersement.especes && l.autreFrais);
  double get mobile => _somme((l) => l.mode == ModeVersement.mobile);
  double get cahier => _somme((l) => l.mode == ModeVersement.cahier);
  double get total => _somme((_) => true);
  int get nbVersements => lignes.length;
  int get nbMobile => lignes.where((l) => l.mode == ModeVersement.mobile).length;
  int get nbCahier => lignes.where((l) => l.mode == ModeVersement.cahier).length;
  int get nbEleves => lignes.map((l) => '${l.nom}|${l.classe}').toSet().length;

  double get totalAnnulations =>
      annulations.fold(0.0, (s, o) => s + o.montant);
  double get totalDepenses => depenses.fold(0.0, (s, o) => s + o.montant);
  double get totalEntrees => entrees.fold(0.0, (s, o) => s + o.montant);
}

class JournalCaisseCalcul {
  /// [debut] et [fin] : jours inclus ; null = toute l'année scolaire.
  static JournalCaisse calculer(
      FraisScolaires fs, {
        String? section,
        String? classe,
        DateTime? debut,
        DateTime? fin,
        bool archives = true,
        bool autresFrais = true,
      }) {
    final String? isoDebut = debut == null ? null : isoDate(debut);
    final String? isoFin = fin == null ? null : isoDate(fin);
    final bool toutLAnnee = isoDebut == null || isoFin == null;

    bool dansPeriode(String iso) {
      if (toutLAnnee) return true;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iso)) return false;
      return iso.compareTo(isoDebut) >= 0 && iso.compareTo(isoFin) <= 0;
    }

    bool dansPeriodeDate(DateTime d) => dansPeriode(isoDate(d));

    bool eleveRetenu(Eleve e) {
      if (section != null && e.section != section) return false;
      if (classe != null && e.classe != classe) return false;
      return true;
    }

    String nomComplet(Eleve e) => '${e.nom} ${e.postNom} ${e.prenom}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final Set<String> idsArchives =
    fs.elevesSupprimesData.eleves.map((e) => e.id).toSet();

    final List<LigneVersement> lignes = [];
    int nbDatesCorrigees = 0;

    // ----------------------------------------------------------------------
    // 1. FRAIS SCOLAIRES : regroupement des transactions en versements
    // ----------------------------------------------------------------------
    final List<MapEntry<Eleve, bool>> eleves = [
      for (final e in fs.currentData.eleves) MapEntry(e, false),
      if (archives)
        for (final e in fs.elevesSupprimesData.eleves) MapEntry(e, true),
    ];

    for (final entry in eleves) {
      final Eleve e = entry.key;
      final bool archive = entry.value;
      if (!eleveRetenu(e)) continue;

      final List<Map<String, dynamic>> txs = e.transactions
          .where((t) => dansPeriode(t['date']?.toString().trim() ?? ''))
          .toList();
      if (txs.isEmpty) continue;

      ModeVersement modeDe(Map<String, dynamic> t) {
        if (t['from_parent'] == true) return ModeVersement.mobile;
        if (t['saisieGroupee'] == true) return ModeVersement.cahier;
        return ModeVersement.especes;
      }

      String cle(Map<String, dynamic> t) {
        final ModeVersement m = modeDe(t);
        final String date = t['date']?.toString().trim() ?? '';
        final String lot =
        m == ModeVersement.cahier ? (t['lotSaisie']?.toString() ?? '') : '';
        return '$date|${m.name}|$lot';
      }

      DateTime? heureDe(Map<String, dynamic> t) =>
          heureDepuisId(t['id']?.toString() ?? '');

      txs.sort((a, b) {
        final ha = heureDe(a);
        final hb = heureDe(b);
        if (ha == null && hb == null) return 0;
        if (ha == null) return 1;
        if (hb == null) return -1;
        return ha.compareTo(hb);
      });

      // Regroupement : même jour, même mode, enregistrés à moins de
      // 2 minutes d'intervalle = un seul versement (un seul reçu).
      final Map<String, List<List<Map<String, dynamic>>>> groupes = {};
      for (final t in txs) {
        final liste = groupes.putIfAbsent(cle(t), () => []);
        final DateTime? h = heureDe(t);
        if (liste.isNotEmpty) {
          final dernier = liste.last;
          final DateTime? hDernier = heureDe(dernier.last);
          final bool memeGroupe = (h == null && hDernier == null) ||
              (h != null &&
                  hDernier != null &&
                  h.difference(hDernier).inSeconds.abs() <= 120);
          if (memeGroupe) {
            dernier.add(t);
            continue;
          }
        }
        liste.add([t]);
      }

      for (final groupesCle in groupes.values) {
        for (final g in groupesCle) {
          final Map<String, dynamic> t0 = g.first;
          final ModeVersement mode = modeDe(t0);
          final String date = t0['date']?.toString().trim() ?? '';
          DateTime? heure = heureDe(t0);
          // L'heure n'a de sens que si elle tombe le jour du paiement
          // (après une correction de date, ce n'est plus le cas).
          if (heure != null && isoDate(heure) != date) heure = null;

          double montant = 0;
          final List<String> detail = [];
          final List<String> remarques = [];
          bool tousImprimes = true;
          final List<String> refs = [];

          for (final t in g) {
            final double a = (t['amount'] as num?)?.toDouble() ?? 0.0;
            montant += a;
            final String mois = t['mois']?.toString() ?? '';
            detail.add('${mois.isEmpty ? 'Mois inconnu' : mois} : '
                '${formatMontant(a)}');
            if (t['receiptConfirmed'] != true) tousImprimes = false;
            final String id = t['id']?.toString() ?? '';
            if (id.isNotEmpty) refs.add(id);

            if (t['excedent'] == true) {
              remarques.add('Excédent placé sur $mois');
            }
            if (t['moisDebloque'] == true) {
              remarques.add('Mois déverrouillé ($mois)');
            }
            final String modifiePar = t['modifiePar']?.toString() ?? '';
            if (modifiePar.isNotEmpty) {
              final String le = t['modifieLe']?.toString() ?? '';
              final double? ancien = _ancienMontant(fs, e, mois, a);
              remarques.add('Montant de $mois modifié'
                  '${le.isNotEmpty ? ' le ${affDateIso(le)}' : ''}'
                  '${ancien != null ? ' (ancien : ${formatMontant(ancien)} FC)' : ''}');
            }
            final String dateOriginale =
                t['dateOriginale']?.toString() ?? '';
            if (dateOriginale.isNotEmpty) {
              nbDatesCorrigees++;
              remarques.add('Date corrigée (ancienne date : '
                  '${affDateIso(dateOriginale)})');
            }
          }

          if (mode == ModeVersement.mobile) {
            remarques.insert(0,
                'Payé par ${t0['network'] ?? 'Mobile Money'} : pas dans la caisse');
          } else if (mode == ModeVersement.cahier) {
            final String creeLe = t0['lotCreeLe']?.toString() ?? '';
            remarques.insert(
                0,
                'Ancien paiement recopié du cahier'
                    '${creeLe.isNotEmpty ? ' (saisi le ${_affDateHeureLibre(creeLe)})' : ''}'
                    ' : argent reçu avant');
          }
          if (archive) remarques.add('Élève supprimé (archivé)');

          lignes.add(LigneVersement(
            date: date,
            heure: heure,
            nom: nomComplet(e),
            classe: e.classe,
            section: e.section,
            mode: mode,
            autreFrais: false,
            detail: detail,
            montant: montant,
            recuImprime: mode == ModeVersement.mobile ? null : tousImprimes,
            remarques: remarques,
            reference: refs.isEmpty
                ? ''
                : (refs.length == 1 ? refs.first : '${refs.first} (+${refs.length - 1})'),
          ));
        }
      }
    }

    // ----------------------------------------------------------------------
    // 2. AUTRES FRAIS (un paiement = un versement)
    // ----------------------------------------------------------------------
    if (autresFrais) {
      final paiements = fs.autresFraisPaiementsByYear[fs.currentYear] ??
          const <AutreFraisPaiement>[];
      for (final p in paiements) {
        if (!dansPeriodeDate(p.date)) continue;
        final Eleve? e = fs.trouverEleveParId(p.eleveId);
        final bool archive = idsArchives.contains(p.eleveId) &&
            !fs.currentData.eleves.any((x) => x.id == p.eleveId);
        if (archive && !archives) continue;
        if (e == null) {
          if (section != null || classe != null) continue;
        } else if (!eleveRetenu(e)) {
          continue;
        }
        final bool aUneHeure = p.date.hour != 0 || p.date.minute != 0;
        String libelle = p.autreFraisNom;
        if (p.trancheNom.isNotEmpty) {
          libelle += ' - ${p.trancheNom}';
        } else if (p.trancheNumero > 0) {
          libelle += ' - tranche ${p.trancheNumero}/${p.trancheTotal}';
        }
        lignes.add(LigneVersement(
          date: isoDate(p.date),
          heure: aUneHeure ? p.date : null,
          nom: e == null ? 'Élève introuvable (${p.eleveId})' : nomComplet(e),
          classe: e?.classe ?? '',
          section: e?.section ?? '',
          mode: ModeVersement.especes,
          autreFrais: true,
          detail: ['$libelle : ${formatMontant(p.montant)}'],
          montant: p.montant,
          recuImprime: null,
          remarques: [
            'Autre frais',
            if (archive) 'Élève supprimé (archivé)',
          ],
          reference: p.id,
        ));
      }
    }

    // ----------------------------------------------------------------------
    // 3. Jours (le plus récent en premier), lignes par heure
    // ----------------------------------------------------------------------
    final Map<String, List<LigneVersement>> parJour = {};
    for (final l in lignes) {
      parJour.putIfAbsent(l.date, () => []).add(l);
    }
    final List<JourCaisse> jours = [];
    final dates = parJour.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return b.compareTo(a);
      });
    for (final d in dates) {
      final l = parJour[d]!
        ..sort((a, b) {
          if (a.heure != null && b.heure != null) {
            return a.heure!.compareTo(b.heure!);
          }
          if (a.heure != null) return -1;
          if (b.heure != null) return 1;
          final c = a.classe.compareTo(b.classe);
          return c != 0 ? c : a.nom.compareTo(b.nom);
        });
      jours.add(JourCaisse(d, l));
    }

    // ----------------------------------------------------------------------
    // 4. Opérations qui peuvent expliquer un écart
    // ----------------------------------------------------------------------
    bool auditRetenu(AdminAuditLog a) {
      if (!dansPeriodeDate(a.date)) return false;
      if (section == null && classe == null) return true;
      final Eleve? e = fs.trouverEleveParId(a.eleveId);
      if (section != null && (e == null || e.section != section)) {
        return false;
      }
      if (classe != null && a.classe != classe && e?.classe != classe) {
        return false;
      }
      return true;
    }

    final List<OperationCaisse> annulations = [];
    final List<OperationCaisse> modifications = [];
    for (final a in fs.adminAuditLog) {
      if (!auditRetenu(a)) continue;
      if (a.action == 'annulation' && a.montantAvant > 0) {
        annulations.add(OperationCaisse(
          a.date,
          'Paiement annulé : ${a.eleveNomComplet} (${a.classe}) - ${a.mois}',
          a.montantAvant,
        ));
      } else if (a.action == 'modification' &&
          (a.montantAvant - a.montantApres).abs() > 0.5) {
        modifications.add(OperationCaisse(
          a.date,
          'Montant modifié : ${a.eleveNomComplet} (${a.classe}) - ${a.mois} : '
              '${formatMontant(a.montantAvant)} -> ${formatMontant(a.montantApres)} FC',
          a.montantApres - a.montantAvant,
        ));
      }
    }

    // Dépenses et entrées : concernent toute la caisse de l'école, donc
    // seulement quand aucune section / classe n'est choisie.
    final List<OperationCaisse> depenses = [];
    final List<OperationCaisse> entrees = [];
    if (section == null && classe == null) {
      for (final d in fs.depensesByYear[fs.currentYear] ?? const <Depense>[]) {
        if (!dansPeriodeDate(d.date)) continue;
        depenses.add(OperationCaisse(
            d.date, 'Dépense : ${d.motif}', d.montant));
      }
      for (final en in fs.entreesByYear[fs.currentYear] ?? const <Entree>[]) {
        if (en.annulee || !dansPeriodeDate(en.date)) continue;
        entrees.add(OperationCaisse(
            en.date,
            'Entrée d\'argent : '
                '${en.motif.trim().isNotEmpty ? en.motif : en.justification}',
            en.montant));
      }
    }

    final sansRecu = lignes.where((l) =>
    l.mode == ModeVersement.especes &&
        !l.autreFrais &&
        l.recuImprime == false);

    return JournalCaisse(
      jours: jours,
      annulations: annulations..sort((a, b) => b.date.compareTo(a.date)),
      modifications: modifications..sort((a, b) => b.date.compareTo(a.date)),
      depenses: depenses..sort((a, b) => b.date.compareTo(a.date)),
      entrees: entrees..sort((a, b) => b.date.compareTo(a.date)),
      nbDatesCorrigees: nbDatesCorrigees,
      nbSansRecu: sansRecu.length,
      sansRecu: sansRecu.fold(0.0, (s, l) => s + l.montant),
    );
  }

  static double? _ancienMontant(
      FraisScolaires fs, Eleve e, String mois, double actuel) {
    for (final a in fs.adminAuditLog.reversed) {
      if (a.action == 'modification' &&
          a.eleveId == e.id &&
          a.mois == mois &&
          (a.montantApres - actuel).abs() < 0.5 &&
          (a.montantAvant - a.montantApres).abs() > 0.5) {
        return a.montantAvant;
      }
    }
    return null;
  }

  static String _affDateHeureLibre(String brut) {
    final d = DateTime.tryParse(brut);
    if (d == null) return brut;
    return '${affDate(d)} ${affHeure(d)}';
  }
}

// ============================================================================
// COMPARAISON AVEC L'ARGENT COMPTÉ À LA MAIN
// ============================================================================

class ResultatComparaison {
  final double attendu; // argent qui devrait être dans la caisse
  final double compte;
  final List<String> correspondances; // explications EXACTES trouvées
  final List<String> pistes; // autres causes possibles

  const ResultatComparaison({
    required this.attendu,
    required this.compte,
    required this.correspondances,
    required this.pistes,
  });

  double get ecart => compte - attendu; // > 0 : trop d'argent
  bool get egal => ecart.abs() < 0.5;
}

ResultatComparaison comparerCaisse(
    JournalCaisse j,
    double compte, {
      required bool deduireDepenses,
      required bool ajouterEntrees,
      required bool filtreActif,
      required bool autresFraisInclus,
      double autresFraisExclus = 0,
    }) {
  double attendu = j.especes;
  if (deduireDepenses) attendu -= j.totalDepenses;
  if (ajouterEntrees) attendu += j.totalEntrees;
  final double ecart = compte - attendu;
  final double absEcart = ecart.abs();
  bool egal(double v) => (v - absEcart).abs() < 0.5;

  final List<String> corr = [];
  final List<String> pistes = [];
  if (absEcart < 0.5) {
    return ResultatComparaison(
        attendu: attendu, compte: compte, correspondances: corr, pistes: pistes);
  }

  // ---- Correspondances exactes (l'écart a exactement ce montant) ----
  if (ecart < 0) {
    for (final l in j.lignes) {
      if (l.mode == ModeVersement.especes && egal(l.montant)) {
        corr.add('Le versement de ${l.nom} (${l.classe}) du '
            '${affDateIso(l.date)}${l.heure != null ? ' à ${affHeure(l.heure!)}' : ''}'
            ' : ${formatMontant(l.montant)} FC. Vérifiez que cet argent a bien '
            'été reçu${l.recuImprime == false ? ' (son reçu n\'a pas été imprimé)' : ''}.');
      }
    }
    if (!deduireDepenses && j.totalDepenses > 0 && egal(j.totalDepenses)) {
      corr.add('Le total des dépenses de la période '
          '(${formatMontant(j.totalDepenses)} FC) : si elles ont été payées '
          'avec l\'argent de la caisse, cochez « Retirer les dépenses ».');
    }
    for (final d in j.depenses) {
      if (!deduireDepenses && egal(d.montant)) {
        corr.add('${d.libelle} du ${affDate(d.date)} : '
            '${formatMontant(d.montant)} FC (payée avec la caisse ?).');
      }
    }
    if (j.sansRecu > 0 && egal(j.sansRecu)) {
      corr.add('Le total des versements sans reçu imprimé '
          '(${formatMontant(j.sansRecu)} FC).');
    }
  } else {
    if (j.mobile > 0 && egal(j.mobile)) {
      corr.add('Le total Mobile Money (${formatMontant(j.mobile)} FC) : ces '
          'paiements ne sont pas dans la caisse. L\'argent Mobile Money a-t-il '
          'été retiré et mis dans la caisse ?');
    }
    if (j.cahier > 0 && egal(j.cahier)) {
      corr.add('Le total des anciens paiements du cahier '
          '(${formatMontant(j.cahier)} FC).');
    }
    if (!autresFraisInclus && autresFraisExclus > 0 && egal(autresFraisExclus)) {
      corr.add('L\'argent des autres frais (${formatMontant(autresFraisExclus)} '
          'FC) : activez « Inclure les autres frais ».');
    }
    if (j.totalAnnulations > 0 && egal(j.totalAnnulations)) {
      corr.add('Le total des paiements annulés '
          '(${formatMontant(j.totalAnnulations)} FC) : l\'argent n\'a peut-être '
          'pas été rendu au parent.');
    }
    for (final a in j.annulations) {
      if (egal(a.montant)) {
        corr.add('${a.libelle}, annulé le ${affDate(a.date)} : '
            '${formatMontant(a.montant)} FC (argent non rendu ?).');
      }
    }
    if (!ajouterEntrees && j.totalEntrees > 0 && egal(j.totalEntrees)) {
      corr.add('Les autres entrées d\'argent (${formatMontant(j.totalEntrees)} '
          'FC) : cochez « Ajouter les entrées d\'argent ».');
    }
    for (final en in j.entrees) {
      if (!ajouterEntrees && egal(en.montant)) {
        corr.add('${en.libelle} du ${affDate(en.date)} : '
            '${formatMontant(en.montant)} FC.');
      }
    }
  }
  for (final m in j.modifications) {
    if (egal(m.montant.abs())) {
      corr.add('${m.libelle} (le ${affDate(m.date)}).');
    }
  }

  // ---- Pistes générales ----
  if (filtreActif) {
    pistes.add('Une section ou une classe est choisie : l\'argent des autres '
        'classes n\'est pas compté ici. Pour contrôler la caisse entière, '
        'choisissez « Toutes les sections » et « Toutes les classes ».');
  }
  if (ecart > 0) {
    pistes.add('Il y a plus d\'argent que dans l\'ordinateur : un paiement '
        'a peut-être été reçu sans être enregistré, ou enregistré à une autre '
        'date.');
    if (j.annulations.isNotEmpty) {
      pistes.add('${j.annulations.length} paiement(s) annulé(s) pendant la '
          'période (${formatMontant(j.totalAnnulations)} FC) : si l\'argent '
          'n\'a pas été rendu, il est encore dans la caisse.');
    }
    if (!autresFraisInclus && autresFraisExclus > 0) {
      pistes.add('Les autres frais (${formatMontant(autresFraisExclus)} FC) '
          'ne sont pas comptés : activez « Inclure les autres frais ».');
    }
    if (!ajouterEntrees && j.totalEntrees > 0) {
      pistes.add('Autres entrées d\'argent (dons, subventions…) : '
          '${formatMontant(j.totalEntrees)} FC non ajoutées.');
    }
  } else {
    pistes.add('Il manque de l\'argent dans la caisse : vérifiez les '
        'versements un par un dans la liste « Jour par jour » (chaque ligne '
        'correspond à un reçu).');
    if (!deduireDepenses && j.totalDepenses > 0) {
      pistes.add('Des dépenses ont été enregistrées pendant la période '
          '(${formatMontant(j.totalDepenses)} FC). Si elles ont été payées avec '
          'l\'argent de la caisse, cochez « Retirer les dépenses ».');
    }
    if (j.nbSansRecu > 0) {
      pistes.add('${j.nbSansRecu} versement(s) sans reçu imprimé '
          '(${formatMontant(j.sansRecu)} FC) : vérifiez que cet argent a bien '
          'été reçu.');
    }
  }
  if (j.modifications.isNotEmpty) {
    pistes.add('${j.modifications.length} montant(s) modifié(s) pendant la '
        'période : l\'ordinateur garde le NOUVEAU montant.');
  }
  if (j.nbDatesCorrigees > 0) {
    pistes.add('${j.nbDatesCorrigees} paiement(s) avec une date corrigée : '
        'ils sont comptés à leur NOUVELLE date.');
  }
  if (j.mobile > 0) {
    pistes.add('Rappel : ${formatMontant(j.mobile)} FC payés par Mobile Money '
        'ne sont PAS comptés dans les espèces (ils ne sont pas dans la caisse).');
  }
  if (j.cahier > 0) {
    pistes.add('Rappel : ${formatMontant(j.cahier)} FC d\'anciens paiements '
        'recopiés du cahier ne sont PAS comptés dans les espèces du jour.');
  }

  return ResultatComparaison(
      attendu: attendu, compte: compte, correspondances: corr, pistes: pistes);
}

// ============================================================================
// ÉCRAN
// ============================================================================

class JournalCaisseScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const JournalCaisseScreen({super.key, required this.fraisScolaires});

  @override
  State<JournalCaisseScreen> createState() => _JournalCaisseScreenState();
}

class _JournalCaisseScreenState extends State<JournalCaisseScreen> {
  String? _section;
  String? _classe;
  bool _archives = true;
  bool _autresFrais = true;
  bool _deduireDepenses = false;
  bool _ajouterEntrees = false;
  PeriodeCaisse _periode = PeriodeCaisse.aujourdhui;
  DateTime? _debutChoisi;
  DateTime? _finChoisie;
  final TextEditingController _compteCtrl = TextEditingController();
  bool _pdfEnCours = false;

  FraisScolaires get fs => widget.fraisScolaires;

  @override
  void dispose() {
    _compteCtrl.dispose();
    super.dispose();
  }

  DateTime get _aujourdhui {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// [début, fin] de la période ; (null, null) = toute l'année.
  (DateTime?, DateTime?) get _bornes {
    final a = _aujourdhui;
    switch (_periode) {
      case PeriodeCaisse.aujourdhui:
        return (a, a);
      case PeriodeCaisse.hier:
        final h = a.subtract(const Duration(days: 1));
        return (h, h);
      case PeriodeCaisse.septJours:
        return (a.subtract(const Duration(days: 6)), a);
      case PeriodeCaisse.ceMois:
        return (DateTime(a.year, a.month, 1), a);
      case PeriodeCaisse.annee:
        return (null, null);
      case PeriodeCaisse.choisie:
        return (_debutChoisi ?? a, _finChoisie ?? _debutChoisi ?? a);
    }
  }

  String get _libellePeriode {
    final (d, f) = _bornes;
    if (d == null || f == null) {
      return "Toute l'année scolaire ${fs.currentYear}";
    }
    if (isoDate(d) == isoDate(f)) return affJourComplet(isoDate(d));
    return 'Du ${affDate(d)} au ${affDate(f)}';
  }

  String get _portee {
    if (_section == null && _classe == null) return "Toute l'école";
    return [
      if (_section != null) 'Section : $_section',
      if (_classe != null) 'Classe : $_classe',
    ].join(' | ');
  }

  bool get _filtreActif => _section != null || _classe != null;

  List<String> _sections() {
    final set = <String>{...fs.config.sections};
    for (final e in fs.currentData.eleves) {
      if (e.section.trim().isNotEmpty) set.add(e.section);
    }
    return set.toList();
  }

  List<String> _classes() {
    final set = <String>{
      ...(_section != null
          ? fs.getAllDisplayClassesForSection(_section!)
          : fs.getAllDisplayClasses()),
    };
    for (final e in fs.currentData.eleves) {
      if (_section != null && e.section != _section) continue;
      if (e.classe.trim().isNotEmpty) set.add(e.classe);
    }
    return set.toList();
  }

  JournalCaisse _calculer({bool? autresFrais}) {
    final (d, f) = _bornes;
    return JournalCaisseCalcul.calculer(
      fs,
      section: _section,
      classe: _classe,
      debut: d,
      fin: f,
      archives: _archives,
      autresFrais: autresFrais ?? _autresFrais,
    );
  }

  double _autresFraisExclus(JournalCaisse j) {
    if (_autresFrais) return 0;
    final avec = _calculer(autresFrais: true);
    return avec.especesAutresFrais;
  }

  Future<void> _choisirDates() async {
    final a = _aujourdhui;
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(a.year - 2),
      lastDate: a,
      initialDateRange: DateTimeRange(
        start: _debutChoisi ?? a,
        end: _finChoisie ?? a,
      ),
      helpText: 'Choisir la période',
      saveText: 'Valider',
    );
    if (r == null) return;
    setState(() {
      _debutChoisi = r.start;
      _finChoisie = r.end;
      _periode = PeriodeCaisse.choisie;
    });
  }

  void _controlerJour(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return;
    setState(() {
      _debutChoisi = d;
      _finChoisie = d;
      _periode = PeriodeCaisse.choisie;
      _compteCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Période : ${affJourComplet(iso)}. Saisissez en haut '
          'l\'argent compté à la main pour ce jour.'),
    ));
  }

  // --------------------------------------------------------------------------
  // PETITS WIDGETS
  // --------------------------------------------------------------------------

  Widget _ligneMontant(String libelle, double v, Color c,
      {bool gras = false, String? aide, double taille = 13}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(libelle,
                    style: TextStyle(
                        fontSize: taille,
                        fontWeight: gras ? FontWeight.bold : FontWeight.w500)),
                if (aide != null)
                  Text(aide,
                      style:
                      const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${formatMontant(v)} FC',
              style: TextStyle(
                  fontSize: taille,
                  fontWeight: FontWeight.bold,
                  color: c)),
        ],
      ),
    );
  }

  Widget _etiquette(String texte, Color c) => Container(
    margin: const EdgeInsets.only(right: 4, top: 2),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.withValues(alpha: 0.45)),
    ),
    child: Text(texte,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: c)),
  );

  Widget _carteResume(JournalCaisse j) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_libellePeriode  |  $_portee',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ARGENT EN ESPÈCES',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                  const Text('C\'est cet argent qu\'on doit retrouver dans la '
                      'caisse.',
                      style: TextStyle(fontSize: 11, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text('${formatMontant(j.especes)} FC',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.green.shade800)),
                  if (j.especesAutresFrais > 0) ...[
                    const SizedBox(height: 4),
                    _ligneMontant('dont frais scolaires', j.especesScolarite,
                        Colors.black87),
                    _ligneMontant('dont autres frais', j.especesAutresFrais,
                        Colors.black87),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (j.mobile > 0)
              _ligneMontant('Mobile Money (${j.nbMobile})', j.mobile,
                  Colors.blue.shade700,
                  aide: 'Payé sur le téléphone : cet argent n\'est PAS dans la '
                      'caisse.'),
            if (j.cahier > 0)
              _ligneMontant('Anciens paiements du cahier (${j.nbCahier})',
                  j.cahier, Colors.brown,
                  aide: 'Recopiés plus tard depuis le cahier : l\'argent avait '
                      'été reçu avant, il n\'est pas dans la caisse du jour.'),
            if (j.mobile > 0 || j.cahier > 0) ...[
              const Divider(height: 16),
              _ligneMontant('TOTAL ENREGISTRÉ DANS L\'ORDINATEUR', j.total,
                  Colors.black87,
                  gras: true),
            ],
            const SizedBox(height: 6),
            Text(
              '${j.nbVersements} versement(s) (= ${j.nbVersements} reçu(s)) '
                  'de ${j.nbEleves} élève(s) sur ${j.jours.length} jour(s).',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carteComparaison(JournalCaisse j) {
    final double? compte = lireMontantSaisi(_compteCtrl.text);
    final ResultatComparaison? r = compte == null
        ? null
        : comparerCaisse(
      j,
      compte,
      deduireDepenses: _deduireDepenses,
      ajouterEntrees: _ajouterEntrees,
      filtreActif: _filtreActif,
      autresFraisInclus: _autresFrais,
      autresFraisExclus: _autresFraisExclus(j),
    );

    Color couleur = Colors.grey;
    String titre = '';
    if (r != null) {
      if (r.egal) {
        couleur = Colors.green.shade700;
        titre = '✅ TOUT CORRESPOND : l\'argent compté est égal à l\'argent '
            'de l\'ordinateur.';
      } else if (r.ecart < 0) {
        couleur = Colors.red.shade700;
        titre = '❗ IL MANQUE ${formatMontant(-r.ecart)} FC dans la caisse.';
      } else {
        couleur = Colors.orange.shade800;
        titre = '❗ IL Y A ${formatMontant(r.ecart)} FC DE PLUS dans la caisse '
            'que dans l\'ordinateur.';
      }
    }

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.calculate, color: Colors.indigo),
              SizedBox(width: 6),
              Expanded(
                child: Text('Comparer avec l\'argent compté à la main',
                    style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Comptez les billets de la caisse pour la même période, '
                  'puis écrivez le montant ici.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _compteCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Argent compté à la main (FC)',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (!_filtreActif && j.totalDepenses > 0)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _deduireDepenses,
                onChanged: (v) =>
                    setState(() => _deduireDepenses = v ?? false),
                title: Text('Retirer les dépenses de la période '
                    '(${formatMontant(j.totalDepenses)} FC)'),
                subtitle: const Text(
                    'À cocher si ces dépenses ont été payées avec l\'argent '
                        'de cette caisse.',
                    style: TextStyle(fontSize: 11)),
              ),
            if (!_filtreActif && j.totalEntrees > 0)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _ajouterEntrees,
                onChanged: (v) =>
                    setState(() => _ajouterEntrees = v ?? false),
                title: Text('Ajouter les entrées d\'argent de la période '
                    '(${formatMontant(j.totalEntrees)} FC)'),
                subtitle: const Text(
                    'Dons, subventions, retours de reliquat… si cet argent est '
                        'dans la caisse.',
                    style: TextStyle(fontSize: 11)),
              ),
            if (r != null) ...[
              const SizedBox(height: 10),
              _ligneMontant('Argent qui doit être dans la caisse', r.attendu,
                  Colors.black87),
              _ligneMontant('Argent compté à la main', r.compte,
                  Colors.black87),
              _ligneMontant(
                  'Écart', r.ecart, r.egal ? Colors.green : couleur,
                  gras: true),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: couleur.withValues(alpha: 0.5)),
                ),
                child: Text(titre,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: couleur)),
              ),
              if (r.correspondances.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '🔎 L\'écart de ${formatMontant(r.ecart.abs())} FC '
                      'correspond EXACTEMENT à :',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                ...r.correspondances.take(8).map((c) => Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text('• $c', style: const TextStyle(fontSize: 12.5)),
                )),
              ],
              if (r.pistes.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Pistes pour trouver la différence :',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...r.pistes.map((p) => Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text('• $p',
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.black87)),
                )),
              ],
              if (!r.egal &&
                  (j.annulations.isNotEmpty || j.modifications.isNotEmpty))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Voir les annulations et modifications'),
                    onPressed: () => _afficherOperations(j),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _afficherOperations(JournalCaisse j) {
    Widget bloc(String titre, List<OperationCaisse> ops) {
      if (ops.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(titre,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...ops.map((o) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
                '${affDate(o.date)} ${affHeure(o.date)} - ${o.libelle}'
                    '${titre.startsWith('Annul') ? ' : ${formatMontant(o.montant)} FC' : ''}',
                style: const TextStyle(fontSize: 12.5)),
          )),
        ],
      );
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annulations et modifications'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ces opérations ont été faites pendant la période. Elles '
                      'changent l\'argent enregistré dans l\'ordinateur, mais '
                      'pas forcément l\'argent de la caisse.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                bloc('Annulations (${j.annulations.length})', j.annulations),
                bloc('Modifications de montant (${j.modifications.length})',
                    j.modifications),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer')),
        ],
      ),
    );
  }

  Widget _ligneVersement(int n, LigneVersement l) {
    final Color couleurMode = l.mode == ModeVersement.mobile
        ? Colors.blue.shade700
        : (l.mode == ModeVersement.cahier
        ? Colors.brown
        : Colors.green.shade700);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text('$n.',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.black54)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l.heure != null ? '${affHeure(l.heure!)}  ' : ''}${l.nom}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [l.classe, l.section].where((s) => s.isNotEmpty).join(' • '),
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
                Text(l.detail.join('  +  '),
                    style: const TextStyle(fontSize: 12)),
                Wrap(children: [
                  _etiquette(l.libelleMode.toUpperCase(), couleurMode),
                  if (l.autreFrais) _etiquette('AUTRE FRAIS', Colors.teal),
                  if (l.recuImprime == true)
                    _etiquette('REÇU IMPRIMÉ', Colors.green.shade700),
                  if (l.recuImprime == false)
                    _etiquette('REÇU NON IMPRIMÉ', Colors.red.shade700),
                ]),
                ...l.remarques
                    .where((r) => r != 'Autre frais')
                    .map((r) => Text('↳ $r',
                    style: TextStyle(
                        fontSize: 11, color: Colors.orange.shade900))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${formatMontant(l.montant)} FC',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: couleurMode)),
        ],
      ),
    );
  }

  Widget _carteJour(JourCaisse jour) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Row(
          children: [
            Expanded(
              child: Text(affJourComplet(jour.date),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Text('${formatMontant(jour.especes)} FC',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800)),
          ],
        ),
        subtitle: Text(
          '${jour.lignes.length} versement(s) • espèces : '
              '${jour.nbEspeces}'
              '${jour.mobile > 0 ? ' • Mobile Money : ${formatMontant(jour.mobile)} FC' : ''}'
              '${jour.cahier > 0 ? ' • cahier : ${formatMontant(jour.cahier)} FC' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          for (int i = 0; i < jour.lignes.length; i++)
            _ligneVersement(i + 1, jour.lignes[i]),
          Container(
            color: Colors.green.withValues(alpha: 0.06),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              children: [
                _ligneMontant('Total espèces du jour', jour.especes,
                    Colors.green.shade800,
                    gras: true),
                if (jour.date.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.calculate, size: 18),
                      label: const Text('Contrôler la caisse de ce jour'),
                      onPressed: () => _controlerJour(jour.date),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // PDF
  // --------------------------------------------------------------------------

  Future<void> _genererPdf(JournalCaisse j) async {
    if (_pdfEnCours) return;
    setState(() => _pdfEnCours = true);
    try {
      final double? compte = lireMontantSaisi(_compteCtrl.text);
      final ResultatComparaison? r = compte == null
          ? null
          : comparerCaisse(
        j,
        compte,
        deduireDepenses: _deduireDepenses,
        ajouterEntrees: _ajouterEntrees,
        filtreActif: _filtreActif,
        autresFraisInclus: _autresFrais,
        autresFraisExclus: _autresFraisExclus(j),
      );
      final doc = construirePdfJournalCaisse(
        fs: fs,
        journal: j,
        periode: _libellePeriode,
        portee: _portee,
        autresFraisInclus: _autresFrais,
        comparaison: r,
        deduireDepenses: _deduireDepenses,
        ajouterEntrees: _ajouterEntrees,
      );
      final (d, f) = _bornes;
      final String suffixe = d == null
          ? 'Annee'
          : (isoDate(d) == isoDate(f!)
          ? isoDate(d)
          : '${isoDate(d)}_au_${isoDate(f)}');
      final String nom = 'Journal_Caisse_${_section ?? 'Toutes'}_'
          '${_classe ?? 'Toutes'}_$suffixe'
          .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
      final chemin = await _enregistrerPdf(doc, nom);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(chemin == null
            ? 'Enregistrement annulé.'
            : '✅ Journal de caisse enregistré : $chemin'),
        backgroundColor: chemin == null ? Colors.orange : Colors.green,
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Impossible de créer le PDF : $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _pdfEnCours = false);
    }
  }

  Future<String?> _enregistrerPdf(pw.Document doc, String nom) async {
    final bytes = await doc.save();
    String? chemin;
    final dir = await getDownloadsDirectory();
    if (dir != null) {
      final f = File('${dir.path}/$nom.pdf');
      await f.writeAsBytes(bytes);
      chemin = f.path;
    } else {
      final loc = await getSaveLocation(
        suggestedName: '$nom.pdf',
        acceptedTypeGroups: [
          XTypeGroup(label: 'PDF', extensions: ['pdf'])
        ],
      );
      if (loc == null) return null;
      await File(loc.path).writeAsBytes(bytes);
      chemin = loc.path;
    }
    try {
      await OpenFile.open(chemin);
    } catch (_) {}
    return chemin;
  }

  // --------------------------------------------------------------------------
  // BUILD
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    if (_section != null && !sections.contains(_section)) {
      sections.add(_section!);
    }
    final classes = _classes();
    if (_classe != null && !classes.contains(_classe)) classes.add(_classe!);

    final JournalCaisse j = _calculer();

    Widget chipPeriode(PeriodeCaisse p, String libelle) => ChoiceChip(
      label: Text(libelle),
      selected: _periode == p,
      onSelected: (_) => setState(() {
        _periode = p;
        _compteCtrl.clear();
      }),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal de caisse'),
        actions: [
          IconButton(
            tooltip: 'Imprimer / enregistrer en PDF',
            icon: _pdfEnCours
                ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf),
            onPressed: _pdfEnCours ? null : () => _genererPdf(j),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.withValues(alpha: 0.25)),
            ),
            child: const Text(
              'Ici, l\'argent est rangé par JOUR où il a été reçu, comme dans '
                  'la caisse.\n'
                  '• Une ligne = un versement = un reçu (même s\'il paie '
                  'plusieurs mois).\n'
                  '• « Espèces » = l\'argent qui doit se trouver dans la caisse. '
                  'Le Mobile Money et les anciens paiements du cahier sont '
                  'montrés à part.\n'
                  '• Comptez l\'argent, écrivez le montant dans « Comparer » : '
                  'l\'application calcule l\'écart et cherche son explication.',
              style: TextStyle(fontSize: 12.5, color: Colors.indigo),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('section_$_section'),
                  initialValue: _section,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Section',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Toutes les sections')),
                    ...sections.map((s) =>
                        DropdownMenuItem<String?>(value: s, child: Text(s))),
                  ],
                  onChanged: (v) => setState(() {
                    _section = v;
                    _classe = null;
                    _compteCtrl.clear();
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('classe_${_section}_$_classe'),
                  initialValue: _classe,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Classe',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Toutes les classes')),
                    ...classes.map((c) =>
                        DropdownMenuItem<String?>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setState(() {
                    _classe = v;
                    _compteCtrl.clear();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Période',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chipPeriode(PeriodeCaisse.aujourdhui, "Aujourd'hui"),
              chipPeriode(PeriodeCaisse.hier, 'Hier'),
              chipPeriode(PeriodeCaisse.septJours, '7 derniers jours'),
              chipPeriode(PeriodeCaisse.ceMois, 'Ce mois-ci'),
              chipPeriode(PeriodeCaisse.annee, "Toute l'année"),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_periode == PeriodeCaisse.choisie
                    ? 'Autres dates ✓'
                    : 'Choisir les dates'),
                onPressed: _choisirDates,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_libellePeriode,
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.indigo,
                  fontWeight: FontWeight.w600)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _autresFrais,
            onChanged: (v) => setState(() => _autresFrais = v),
            title: const Text('Inclure les autres frais'),
            subtitle: const Text(
                'À garder activé si l\'argent des autres frais est mis dans la '
                    'même caisse.',
                style: TextStyle(fontSize: 11)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _archives,
            onChanged: (v) => setState(() => _archives = v),
            title: const Text('Inclure les élèves supprimés (archivés)'),
            subtitle: const Text(
                'Leur argent a été reçu : gardez activé pour ne rien oublier.',
                style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(height: 6),
          _carteResume(j),
          const SizedBox(height: 10),
          _carteComparaison(j),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text('Jour par jour',
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('PDF à signer'),
                onPressed: _pdfEnCours ? null : () => _genererPdf(j),
              ),
            ],
          ),
          const Text('Appuyez sur un jour pour voir chaque versement.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          if (j.jours.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text('Aucun argent reçu pendant cette période.',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...j.jours.map(_carteJour),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================================================================
// PDF « JOURNAL DE CAISSE » (à imprimer et à signer)
// ============================================================================

/// Les polices PDF par défaut ne connaissent que les caractères latins.
String _pdfTexte(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x2014 || r == 0x2013) {
      b.write('-');
    } else if (r == 0x2026) {
      b.write('...');
    } else if (r == 0x2019) {
      b.write("'");
    } else if (r <= 255) {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

pw.Document construirePdfJournalCaisse({
  required FraisScolaires fs,
  required JournalCaisse journal,
  required String periode,
  required String portee,
  required bool autresFraisInclus,
  ResultatComparaison? comparaison,
  bool deduireDepenses = false,
  bool ajouterEntrees = false,
}) {
  final j = journal;
  final now = DateTime.now();
  String t(String s) => _pdfTexte(s);

  pw.Widget ligneTotal(String l, double v, {bool gras = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(children: [
      pw.Expanded(
          child: pw.Text(t(l),
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight:
                  gras ? pw.FontWeight.bold : pw.FontWeight.normal))),
      pw.Text('${formatMontant(v)} FC',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    ]),
  );

  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(26),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (ctx) => [
        pw.Center(
          child: pw.Text(t(fs.config.schoolName.toUpperCase()),
              style:
              pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 3),
        pw.Center(
          child: pw.Text('JOURNAL DE CAISSE - PREUVES DE L\'ARGENT RECU',
              style:
              pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 3),
        pw.Center(
          child: pw.Text(t('Période : $periode  |  $portee'),
              style: const pw.TextStyle(fontSize: 10)),
        ),
        pw.Center(
          child: pw.Text(
              t('Année scolaire ${fs.currentYear}  |  Imprimé le '
                  '${affDate(now)} à ${affHeure(now)}  |  Autres frais : '
                  '${autresFraisInclus ? 'inclus' : 'non inclus'}'),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ),
        pw.SizedBox(height: 10),

        // ---------------- RÉSUMÉ ----------------
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey600),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('RÉSUMÉ',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              ligneTotal('ARGENT EN ESPÈCES (doit être dans la caisse)',
                  j.especes,
                  gras: true),
              if (j.especesAutresFrais > 0) ...[
                ligneTotal('   dont frais scolaires', j.especesScolarite),
                ligneTotal('   dont autres frais', j.especesAutresFrais),
              ],
              if (j.mobile > 0)
                ligneTotal('Mobile Money (pas dans la caisse)', j.mobile),
              if (j.cahier > 0)
                ligneTotal(
                    'Anciens paiements recopiés du cahier (pas dans la caisse '
                        'du jour)',
                    j.cahier),
              ligneTotal('TOTAL ENREGISTRÉ DANS L\'ORDINATEUR', j.total,
                  gras: true),
              pw.SizedBox(height: 3),
              pw.Text(
                  t('${j.nbVersements} versement(s) = ${j.nbVersements} '
                      'reçu(s), ${j.nbEleves} élève(s), ${j.jours.length} '
                      'jour(s).'),
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        pw.SizedBox(height: 8),

        // ---------------- CONTRÔLE ----------------
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey600),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('CONTRÔLE DE LA CAISSE',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              if (comparaison == null) ...[
                ligneTotal('Argent qui doit être dans la caisse (espèces)',
                    j.especes),
                pw.SizedBox(height: 6),
                pw.Text('Argent compté à la main : ______________________ FC',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 8),
                pw.Text('Écart : ______________________ FC',
                    style: const pw.TextStyle(fontSize: 10)),
              ] else ...[
                if (deduireDepenses)
                  pw.Text(t('Dépenses de la période retirées : '
                      '${formatMontant(j.totalDepenses)} FC'),
                      style: const pw.TextStyle(fontSize: 9)),
                if (ajouterEntrees)
                  pw.Text(t('Entrées d\'argent ajoutées : '
                      '${formatMontant(j.totalEntrees)} FC'),
                      style: const pw.TextStyle(fontSize: 9)),
                ligneTotal('Argent qui doit être dans la caisse',
                    comparaison.attendu),
                ligneTotal('Argent compté à la main', comparaison.compte),
                ligneTotal('Écart', comparaison.ecart, gras: true),
                pw.SizedBox(height: 3),
                pw.Text(
                  t(comparaison.egal
                      ? 'RÉSULTAT : TOUT CORRESPOND.'
                      : (comparaison.ecart < 0
                      ? 'RÉSULTAT : IL MANQUE ${formatMontant(-comparaison.ecart)} FC DANS LA CAISSE.'
                      : 'RÉSULTAT : IL Y A ${formatMontant(comparaison.ecart)} FC DE PLUS DANS LA CAISSE.')),
                  style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: comparaison.egal
                          ? PdfColors.green800
                          : PdfColors.red800),
                ),
                if (comparaison.correspondances.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('L\'écart correspond exactement à :',
                      style: pw.TextStyle(
                          fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  ...comparaison.correspondances.take(8).map((c) =>
                      pw.Text(t('- $c'), style: const pw.TextStyle(fontSize: 9))),
                ],
                if (comparaison.pistes.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('Pistes :',
                      style: pw.TextStyle(
                          fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  ...comparaison.pistes.map((p) =>
                      pw.Text(t('- $p'), style: const pw.TextStyle(fontSize: 9))),
                ],
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 12),

        // ---------------- JOUR PAR JOUR ----------------
        if (j.jours.isEmpty)
          pw.Text('Aucun argent reçu pendant cette période.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        for (final jour in j.jours) ...[
          pw.Container(
            color: PdfColors.grey300,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Row(children: [
              pw.Expanded(
                child: pw.Text(t(affJourComplet(jour.date).toUpperCase()),
                    style: pw.TextStyle(
                        fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
              ),
              pw.Text(
                  t('${jour.lignes.length} versement(s) - Espèces : '
                      '${formatMontant(jour.especes)} FC'),
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.TableHelper.fromTextArray(
            headers: const [
              'N°', 'Heure', 'Élève', 'Classe', 'Détail', 'Mode', 'Reçu',
              'Montant'
            ].map(_pdfTexte).toList(),
            data: [
              for (int i = 0; i < jour.lignes.length; i++)
                [
                  '${i + 1}',
                  jour.lignes[i].heure == null
                      ? '-'
                      : affHeure(jour.lignes[i].heure!),
                  t(jour.lignes[i].nom),
                  t(jour.lignes[i].classe),
                  t([
                    ...jour.lignes[i].detail,
                    ...jour.lignes[i].remarques
                        .where((r) => r != 'Autre frais')
                        .map((r) => '> $r'),
                  ].join('\n')),
                  t(jour.lignes[i].libelleMode),
                  t(jour.lignes[i].libelleRecu),
                  formatMontant(jour.lignes[i].montant),
                ],
            ],
            headerStyle: pw.TextStyle(
                fontSize: 8, fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
            cellStyle: const pw.TextStyle(fontSize: 7.8),
            cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.45),
              1: pw.FlexColumnWidth(0.6),
              2: pw.FlexColumnWidth(2.0),
              3: pw.FlexColumnWidth(0.9),
              4: pw.FlexColumnWidth(2.6),
              5: pw.FlexColumnWidth(0.9),
              6: pw.FlexColumnWidth(0.8),
              7: pw.FlexColumnWidth(0.9),
            },
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.center,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.center,
              6: pw.Alignment.center,
              7: pw.Alignment.centerRight,
            },
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3, bottom: 2),
            child: pw.Column(children: [
              ligneTotal('Total espèces du jour', jour.especes, gras: true),
              if (jour.mobile > 0)
                ligneTotal('Mobile Money du jour (pas dans la caisse)',
                    jour.mobile),
              if (jour.cahier > 0)
                ligneTotal('Anciens paiements du cahier', jour.cahier),
            ]),
          ),
          pw.Text(
              'Compté à la main pour ce jour : ________________ FC      '
                  'Visa : ____________',
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800)),
          pw.SizedBox(height: 10),
        ],

        // ---------------- SIGNATURES ----------------
        pw.SizedBox(height: 14),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            for (final s in ['Caissier(ère)', 'Vérifié par', 'Direction'])
              pw.Column(children: [
                pw.Text(t(s),
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 30),
                pw.Text('______________________',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Nom et signature',
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey700)),
              ]),
          ],
        ),
      ],
    ),
  );
  return pdf;
}
