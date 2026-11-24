#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ANALYSE DE SYNCHRONISATION — LECTURE SEULE
==========================================

À lancer sur une COPIE des fichiers, jamais sur les originaux :
  - fichier de l'école du serveur        : <code>.json
  - instantanés du serveur                : backups/<code>/*.json
  - fichiers des ordinateurs (dossier Documents de l'application) :
      school_fees_data.json
      school_fees_data.safety_*.json      (copies de sécurité)
      school_fees_data.corrupt_*.json

Ce que le script fait :
  1. Résumé de chaque version (date, révision, élèves, argent, transactions).
  2. Doublons d'élèves (même nom, identifiants différents ; même identifiant
     deux fois) et transactions en double.
  3. Paiements DISPARUS : présents dans au moins une version, absents de la
     version de référence (la plus récente, ou --reference).
  4. Idem pour les paiements « Autres frais ».

Il n'écrit RIEN dans le dossier analysé. Le rapport est écrit dans un
dossier séparé (--sortie), qui doit être en dehors du dossier analysé.

Utilisation :
  python3 analyse_sync.py DOSSIER_DE_COPIES --sortie DOSSIER_RAPPORT
          [--reference FICHIER] [--depuis AAAA-MM-JJ] [--annee 2025-2026]

Exemple :
  mkdir ~/Desktop/copie_ecole
  (copier dedans les fichiers, sans les déplacer)
  python3 analyse_sync.py ~/Desktop/copie_ecole --sortie ~/Desktop/rapport_ecole
"""
import argparse
import csv
import datetime
import json
import os
import re
import sys
import unicodedata

# Dossier des VRAIES données du serveur : le script refuse d'y travailler.
DOSSIERS_INTERDITS = [
    os.path.realpath(os.path.expanduser('~/Desktop/jsinf/school_data')),
    '/var/data/school_data',
]

RE_HORODATAGE = re.compile(r'(\d{8})_(\d{6})')


# ---------------------------------------------------------------------------
# Lecture
# ---------------------------------------------------------------------------
def dossier_interdit(chemin):
    reel = os.path.realpath(chemin)
    for d in DOSSIERS_INTERDITS:
        if reel == d or reel.startswith(d + os.sep):
            return True
    return False


def lister_json(dossier):
    fichiers = []
    for racine, _, noms in os.walk(dossier):
        for nom in noms:
            if nom.endswith('.json'):
                fichiers.append(os.path.join(racine, nom))
    return fichiers


def lire_json(chemin):
    try:
        with open(chemin, 'r', encoding='utf-8') as f:   # lecture seule
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except Exception as e:  # fichier illisible : signalé, jamais modifié
        print(f"  ⚠️  illisible : {chemin} ({e})", file=sys.stderr)
        return None


def est_donnees_ecole(d):
    return isinstance(d, dict) and isinstance(d.get('history'), dict)


def date_version(chemin, d):
    v = d.get('_saved_at')
    if isinstance(v, str):
        try:
            return datetime.datetime.fromisoformat(v[:26])
        except ValueError:
            pass
    m = RE_HORODATAGE.search(os.path.basename(chemin))
    if m:
        try:
            return datetime.datetime.strptime(m.group(1) + m.group(2),
                                              '%Y%m%d%H%M%S')
        except ValueError:
            pass
    return datetime.datetime.fromtimestamp(os.path.getmtime(chemin))


def num(v):
    try:
        return float(v or 0)
    except (TypeError, ValueError):
        return 0.0


def norm(s):
    s = unicodedata.normalize('NFKD', str(s or '')).encode(
        'ascii', 'ignore').decode()
    return re.sub(r'\s+', ' ', s.strip().lower())


def nom_complet(e):
    return ' '.join(x for x in [e.get('nom', ''), e.get('postNom', ''),
                                e.get('prenom', '')] if x).strip()


def cle_tx(t):
    tid = str(t.get('id') or '').strip()
    if tid:
        return tid
    return f"SIG|{t.get('date', '')}|{t.get('mois', '')}|{num(t.get('amount')):.2f}"


# ---------------------------------------------------------------------------
# Analyse d'une version
# ---------------------------------------------------------------------------
def eleves_de(d, annee=None):
    for an, yd in (d.get('history') or {}).items():
        if annee and an != annee:
            continue
        for e in (yd or {}).get('eleves', []) or []:
            if isinstance(e, dict):
                yield an, e


def resume(chemin, d, annee):
    nb_eleves = nb_tx = 0
    argent_tx = argent_paid = 0.0
    for _, e in eleves_de(d, annee):
        nb_eleves += 1
        txs = e.get('transactions') or []
        nb_tx += len(txs)
        argent_tx += sum(num(t.get('amount')) for t in txs if isinstance(t, dict))
        argent_paid += sum(num(v) for v in (e.get('paid') or {}).values())
    af = 0
    af_total = 0.0
    for an, l in (d.get('autresFraisPaiementsByYear') or {}).items():
        if annee and an != annee:
            continue
        for p in l or []:
            if isinstance(p, dict):
                af += 1
                af_total += num(p.get('montant'))
    return {
        'fichier': chemin,
        'date': date_version(chemin, d),
        'revision': d.get('_revision', d.get('serverRevision', '')),
        'eleves': nb_eleves,
        'transactions': nb_tx,
        'argent_transactions': argent_tx,
        'argent_paid': argent_paid,
        'autres_frais_paiements': af,
        'autres_frais_total': af_total,
    }


def doublons(d, annee):
    lignes = []
    par_nom, par_id = {}, {}
    for an, e in eleves_de(d, annee):
        par_nom.setdefault((an, norm(nom_complet(e))), []).append(e)
        par_id.setdefault((an, str(e.get('id', ''))), []).append(e)
    for (an, nom), l in par_nom.items():
        ids = sorted({str(e.get('id', '')) for e in l})
        if len(l) > 1 and nom:
            lignes.append([an, 'même nom, plusieurs fiches', nom,
                           ' / '.join(ids),
                           ' / '.join(f"{sum(num(t.get('amount')) for t in (e.get('transactions') or [])):.0f}"
                                      for e in l)])
    for (an, eid), l in par_id.items():
        if len(l) > 1:
            lignes.append([an, 'même identifiant, plusieurs fiches', eid,
                           ' / '.join(nom_complet(e) for e in l), ''])
    # Transactions en double dans un même élève (même date, mois, montant,
    # identifiants différents) : possible double comptage.
    for an, e in eleves_de(d, annee):
        vus = {}
        for t in e.get('transactions') or []:
            if not isinstance(t, dict):
                continue
            sig = f"{t.get('date', '')}|{t.get('mois', '')}|{num(t.get('amount')):.2f}"
            vus.setdefault(sig, []).append(str(t.get('id') or ''))
        for sig, ids in vus.items():
            if len(ids) > 1:
                lignes.append([an, 'transactions identiques (à vérifier)',
                               f"{nom_complet(e)} ({e.get('id', '')})",
                               ' / '.join(ids), sig])
    return lignes


# ---------------------------------------------------------------------------
# Programme principal
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dossier', help='dossier contenant les COPIES des fichiers')
    ap.add_argument('--sortie', required=True,
                    help='dossier où écrire le rapport (hors du dossier analysé)')
    ap.add_argument('--reference',
                    help='fichier de référence (défaut : la version la plus récente)')
    ap.add_argument('--depuis', help='ne lister que les paiements à partir de '
                                     'cette date (AAAA-MM-JJ)')
    ap.add_argument('--annee', help="année scolaire (ex : 2025-2026) ; "
                                    "défaut : toutes")
    a = ap.parse_args()

    dossier = os.path.realpath(a.dossier)
    sortie = os.path.realpath(a.sortie)
    if dossier_interdit(dossier):
        sys.exit("❌ Refusé : ce dossier contient les VRAIES données du serveur. "
                 "Copiez les fichiers dans un autre dossier et relancez.")
    if not os.path.isdir(dossier):
        sys.exit(f"❌ Dossier introuvable : {dossier}")
    if sortie == dossier or sortie.startswith(dossier + os.sep) \
            or dossier_interdit(sortie):
        sys.exit("❌ Le dossier --sortie doit être EN DEHORS du dossier analysé.")

    versions = []
    for f in lister_json(dossier):
        d = lire_json(f)
        if d is not None and est_donnees_ecole(d):
            versions.append((f, d))
    if not versions:
        sys.exit("Aucun fichier de données d'école trouvé dans ce dossier.")
    versions.sort(key=lambda v: date_version(v[0], v[1]))

    if a.reference:
        ref_chemin = os.path.realpath(a.reference)
        ref = next((v for v in versions if os.path.realpath(v[0]) == ref_chemin),
                   None)
        if ref is None:
            sys.exit("❌ --reference doit être un des fichiers du dossier analysé.")
    else:
        ref = versions[-1]

    os.makedirs(sortie, exist_ok=True)
    rel = lambda p: os.path.relpath(p, dossier)

    # 1. Résumés
    resumes = [resume(f, d, a.annee) for f, d in versions]
    with open(os.path.join(sortie, '1_versions.csv'), 'w', newline='',
              encoding='utf-8-sig') as fo:
        w = csv.writer(fo, delimiter=';')
        w.writerow(['date', 'fichier', 'révision', 'élèves', 'transactions',
                    'argent (transactions)', 'argent (paid)',
                    'paiements autres frais', 'total autres frais'])
        for r in resumes:
            w.writerow([r['date'].strftime('%Y-%m-%d %H:%M:%S'), rel(r['fichier']),
                        r['revision'], r['eleves'], r['transactions'],
                        f"{r['argent_transactions']:.0f}", f"{r['argent_paid']:.0f}",
                        r['autres_frais_paiements'], f"{r['autres_frais_total']:.0f}"])

    # 2. Doublons dans la référence
    lignes_doublons = doublons(ref[1], a.annee)
    with open(os.path.join(sortie, '2_doublons_reference.csv'), 'w', newline='',
              encoding='utf-8-sig') as fo:
        w = csv.writer(fo, delimiter=';')
        w.writerow(['année', 'type', 'élève / nom', 'identifiants / noms',
                    'détail (argent par fiche ou signature)'])
        w.writerows(lignes_doublons)

    # 3. Paiements disparus (frais scolaires)
    ref_tx = set()
    ref_ids_eleves = set()
    for an, e in eleves_de(ref[1], a.annee):
        ref_ids_eleves.add(str(e.get('id', '')))
        for t in e.get('transactions') or []:
            if isinstance(t, dict):
                ref_tx.add((an, str(e.get('id', '')), cle_tx(t)))
    # même transaction rangée sous un autre élève (identifiant changé)
    ref_tx_sans_eleve = {(an, k) for an, _, k in ref_tx}

    disparus = {}
    for f, d in versions:
        if f == ref[0]:
            continue
        for an, e in eleves_de(d, a.annee):
            eid = str(e.get('id', ''))
            for t in e.get('transactions') or []:
                if not isinstance(t, dict):
                    continue
                k = cle_tx(t)
                if (an, eid, k) in ref_tx:
                    continue
                if a.depuis and str(t.get('date', ''))[:10] < a.depuis:
                    continue
                cle = (an, eid, k)
                if cle not in disparus:
                    disparus[cle] = {
                        'annee': an, 'eleve_id': eid, 'eleve': nom_complet(e),
                        'classe': e.get('classe', ''), 'date': t.get('date', ''),
                        'mois': t.get('mois', ''), 'montant': num(t.get('amount')),
                        'tx': k,
                        'ailleurs': (an, k) in ref_tx_sans_eleve,
                        'eleve_absent': eid not in ref_ids_eleves,
                        'fichiers': [],
                    }
                disparus[cle]['fichiers'].append(rel(f))

    with open(os.path.join(sortie, '3_paiements_disparus.csv'), 'w', newline='',
              encoding='utf-8-sig') as fo:
        w = csv.writer(fo, delimiter=';')
        w.writerow(['année', 'date', 'élève', 'ID élève', 'classe', 'mois',
                    'montant', 'ID transaction', 'remarque',
                    'nb versions qui l\'ont', 'dernière version qui l\'a'])
        total_disparu = 0.0
        for p in sorted(disparus.values(), key=lambda x: (str(x['date']), x['eleve'])):
            if p['ailleurs']:
                remarque = "présente sous un autre ID d'élève (pas perdue)"
            elif p['eleve_absent']:
                remarque = 'élève absent de la référence (supprimé ou renommé ?)'
            else:
                remarque = 'PERDUE'
                total_disparu += p['montant']
            w.writerow([p['annee'], p['date'], p['eleve'], p['eleve_id'],
                        p['classe'], p['mois'], f"{p['montant']:.0f}", p['tx'],
                        remarque, len(p['fichiers']), p['fichiers'][-1]])

    # 4. Autres frais disparus
    ref_af = set()
    for an, l in (ref[1].get('autresFraisPaiementsByYear') or {}).items():
        for p in l or []:
            if isinstance(p, dict):
                ref_af.add(str(p.get('id', '')))
    annules = set(str(x) for x in (ref[1].get('paiementsAutresFraisAnnules') or []))
    af_disparus = {}
    for f, d in versions:
        if f == ref[0]:
            continue
        for an, l in (d.get('autresFraisPaiementsByYear') or {}).items():
            if a.annee and an != a.annee:
                continue
            for p in l or []:
                if not isinstance(p, dict):
                    continue
                pid = str(p.get('id', ''))
                if pid in ref_af:
                    continue
                if a.depuis and str(p.get('date', ''))[:10] < a.depuis:
                    continue
                af_disparus.setdefault(pid, (an, p, []))[2].append(rel(f))
    with open(os.path.join(sortie, '4_autres_frais_disparus.csv'), 'w',
              newline='', encoding='utf-8-sig') as fo:
        w = csv.writer(fo, delimiter=';')
        w.writerow(['année', 'date', 'frais', 'ID élève', 'montant', 'ID paiement',
                    'remarque', 'dernière version qui l\'a'])
        for pid, (an, p, fs) in sorted(af_disparus.items(),
                                       key=lambda x: str(x[1][1].get('date', ''))):
            w.writerow([an, str(p.get('date', ''))[:19], p.get('autreFraisNom', ''),
                        p.get('eleveId', ''), f"{num(p.get('montant')):.0f}", pid,
                        'annulé volontairement' if pid in annules else 'PERDU',
                        fs[-1]])

    # Rapport texte
    rapport = os.path.join(sortie, '0_RAPPORT.txt')
    with open(rapport, 'w', encoding='utf-8') as fo:
        def p(s=''):
            fo.write(s + '\n')
            print(s)
        p('ANALYSE DE SYNCHRONISATION (lecture seule)')
        p(f"Dossier analysé : {dossier}")
        p(f"Versions trouvées : {len(versions)}")
        p(f"Référence : {rel(ref[0])} ({date_version(*ref):%Y-%m-%d %H:%M})")
        p()
        p('ÉVOLUTION (élèves | argent transactions | argent paid) :')
        prec = None
        for r in resumes:
            alerte = ''
            if prec:
                if r['eleves'] > prec['eleves']:
                    alerte += f"  ⚠️ +{r['eleves'] - prec['eleves']} élève(s)"
                if r['eleves'] < prec['eleves']:
                    alerte += f"  ⚠️ {r['eleves'] - prec['eleves']} élève(s)"
                diff = r['argent_transactions'] - prec['argent_transactions']
                if diff < -0.5:
                    alerte += f"  ⚠️ argent {diff:,.0f}".replace(',', ' ')
            p(f"  {r['date']:%Y-%m-%d %H:%M}  rév {str(r['revision']):>4}  "
              f"{r['eleves']:>5} | {r['argent_transactions']:>14,.0f} | "
              f"{r['argent_paid']:>14,.0f}  {rel(r['fichier'])}{alerte}"
              .replace(',', ' '))
            prec = r
        p()
        perdues = [x for x in disparus.values()
                   if not x['ailleurs'] and not x['eleve_absent']]
        p(f"Doublons / anomalies dans la référence : {len(lignes_doublons)} "
          f"(voir 2_doublons_reference.csv)")
        p(f"Paiements absents de la référence : {len(disparus)}, dont "
          f"{len(perdues)} PERDUS pour {total_disparu:,.0f} FC "
          f"(voir 3_paiements_disparus.csv)".replace(',', ' '))
        p(f"Paiements autres frais absents : {len(af_disparus)} "
          f"(voir 4_autres_frais_disparus.csv)")
        p()
        p('Rien n\'a été modifié dans le dossier analysé.')
    print(f"\nRapport écrit dans : {sortie}")


if __name__ == '__main__':
    main()
