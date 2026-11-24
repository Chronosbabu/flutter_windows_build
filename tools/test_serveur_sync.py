#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tests de la correction serveur de la synchronisation (étape 2).

  • Teste le code de /Users/mac/Desktop/jsinf (app.py + payment_sync.py)
    avec le client de test Flask : AUCUN appel réseau, rien n'est déployé.
  • DATA_DIR pointe vers un dossier TEMPORAIRE créé pour le test ; le test
    refuse de tourner s'il pointait vers les vraies données (school_data).
  • Firebase est remplacé par un faux module ; les notifications sont
    neutralisées.

Lancement (Flask requis, par exemple dans un environnement virtuel) :
  python3 tools/test_serveur_sync.py
"""
import json
import os
import shutil
import sys
import tempfile
import types
import unittest

DOSSIER_SERVEUR = os.environ.get(
    'DOSSIER_SERVEUR', os.path.expanduser('~/Desktop/jsinf'))
VRAIES_DONNEES = [
    os.path.realpath(os.path.join(DOSSIER_SERVEUR, 'school_data')),
    '/var/data/school_data',
]

# --- dossier de données temporaire (jamais les vraies données) ------------
DATA_TMP = tempfile.mkdtemp(prefix='test_serveur_sync_')
for interdit in VRAIES_DONNEES:
    assert not os.path.realpath(DATA_TMP).startswith(interdit), 'DATA_DIR interdit'
os.environ['DATA_DIR'] = DATA_TMP
os.environ.pop('STRICT_AUTH', None)
os.environ.pop('REQUIRE_BASE_REVISION', None)
sys.dont_write_bytecode = True          # aucun __pycache__ dans jsinf

# --- faux Firebase (aucun appel réseau) -----------------------------------
fb = types.ModuleType('firebase_admin')
fb.credentials = types.SimpleNamespace(Certificate=lambda *a, **k: None)
fb.messaging = types.SimpleNamespace()
fb.initialize_app = lambda *a, **k: None
sys.modules['firebase_admin'] = fb
sys.modules['firebase_admin.credentials'] = fb.credentials
sys.modules['firebase_admin.messaging'] = fb.messaging

sys.path.insert(0, DOSSIER_SERVEUR)
import app as serveur                   # noqa: E402
import payment_sync                     # noqa: E402

assert serveur.DATA_DIR == DATA_TMP and payment_sync.DATA_DIR == DATA_TMP

# Neutralise toute notification (parents / promoteur).
NOTIFS = []
serveur._run_async = lambda f, *a, **k: NOTIFS.append((f.__name__, a))
serveur.notify_school_role = lambda *a, **k: None

CODE = 'TESTECOLE'
MDP = 'mdp-test-123'
ANNEE = '2025-2026'


def tx(i, date, montant, mois='Septembre'):
    return {'id': i, 'date': date, 'mois': mois, 'amount': montant}


def eleve(i, nom, txs):
    paid = {}
    for t in txs:
        paid[t['mois']] = paid.get(t['mois'], 0) + t['amount']
    return {'id': i, 'nom': nom, 'postNom': '', 'prenom': '',
            'classe': '1ère', 'section': 'Primaire',
            'paid': paid, 'transactions': txs}


class TestSyncPaiements(unittest.TestCase):
    def setUp(self):
        for n in os.listdir(DATA_TMP):
            p = os.path.join(DATA_TMP, n)
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
        self.chemin = os.path.join(DATA_TMP, CODE.lower() + '.json')
        self.ecrire({
            'backup_password': MDP,
            'currentYear': ANNEE,
            '_revision': 3,
            'history': {ANNEE: {'eleves': [
                eleve('E1', 'KABILA', [tx('T1', '2026-11-17', 3000)]),
                eleve('E2', 'MUKENDI', []),
            ]}},
        })
        self.client = serveur.app.test_client()
        NOTIFS.clear()

    # -- outils --
    def ecrire(self, d):
        with open(self.chemin, 'w', encoding='utf-8') as f:
            json.dump(d, f)

    def lire(self):
        with open(self.chemin, encoding='utf-8') as f:
            return json.load(f)

    def octets(self):
        with open(self.chemin, 'rb') as f:
            return f.read()

    def envoyer(self, students, password=MDP, code=CODE):
        body = {'school_code': code, 'students': students}
        if password is not None:
            body['password'] = password
        r = self.client.post('/school/sync_student_payments', json=body)
        return r.status_code, r.get_json()

    def snap(self, i, nom, txs):
        e = eleve(i, nom, txs)
        return {k: e[k] for k in
                ('id', 'nom', 'postNom', 'prenom', 'classe', 'section',
                 'paid', 'transactions')}

    def eleve_serveur(self, i):
        for e in self.lire()['history'][ANNEE]['eleves']:
            if e['id'] == i:
                return e
        return None

    # -- mot de passe / compatibilité anciennes versions --
    def test_sans_mot_de_passe_rien_ecrit_mais_done(self):
        avant = self.octets()
        code, rep = self.envoyer(
            [self.snap('E1', 'KABILA', [tx('T9', '2026-11-24', 500)])],
            password=None)
        self.assertEqual(code, 200)
        self.assertEqual(rep['done'], ['E1'])
        self.assertTrue(rep['auth_refused'])
        self.assertEqual(rep['changed'], 0)
        self.assertEqual(self.octets(), avant, 'fichier inchangé')

    def test_mauvais_mot_de_passe_rien_ecrit_mais_done(self):
        avant = self.octets()
        code, rep = self.envoyer(
            [self.snap('E1', 'KABILA', [tx('T9', '2026-11-24', 500)])],
            password='faux')
        self.assertEqual(code, 200)
        self.assertEqual(rep['done'], ['E1'])
        self.assertTrue(rep['auth_refused'])
        self.assertEqual(self.octets(), avant)

    def test_ecole_inconnue_ou_code_invalide(self):
        for code_ecole in ('INCONNUE', '../etc', 'a b'):
            code, rep = self.envoyer([self.snap('E1', 'K', [])], code=code_ecole)
            self.assertEqual(code, 200, code_ecole)
            self.assertEqual(rep['done'], ['E1'])
            self.assertEqual(rep['changed'], 0)
        self.assertFalse(os.path.exists(os.path.join(DATA_TMP, 'inconnue.json')))

    # -- fusion sans suppression --
    def test_ajoute_un_paiement_nouveau(self):
        code, rep = self.envoyer([self.snap('E1', 'KABILA', [
            tx('T1', '2026-11-17', 3000), tx('T2', '2026-11-24', 2000)])])
        self.assertEqual(code, 200)
        self.assertEqual(rep['changed'], 1)
        self.assertFalse(rep['auth_refused'])
        e = self.eleve_serveur('E1')
        self.assertEqual(sorted(t['id'] for t in e['transactions']), ['T1', 'T2'])
        self.assertEqual(e['paid'], {'Septembre': 5000})
        d = self.lire()
        self.assertEqual(d['_revision'], 4, 'révision +1')
        self.assertEqual(d['backup_password'], MDP)
        instantanes = os.listdir(os.path.join(DATA_TMP, 'backups', CODE.lower()))
        self.assertEqual(len(instantanes), 1, 'instantané avant écriture')
        self.assertGreater(payment_sync.get_payment_version(CODE, 'E1'), 0)

    def test_ordinateur_en_retard_ne_supprime_rien(self):
        # Le serveur a T1 ; l'ordinateur en retard ne l'a pas et envoie T3.
        self.envoyer([self.snap('E1', 'KABILA', [tx('T3', '2026-11-24', 1000)])])
        e = self.eleve_serveur('E1')
        self.assertEqual(sorted(t['id'] for t in e['transactions']), ['T1', 'T3'])
        self.assertEqual(e['paid'], {'Septembre': 4000})

    def test_fiche_vide_ne_supprime_rien(self):
        avant = self.octets()
        code, rep = self.envoyer([self.snap('E1', 'KABILA', [])])
        self.assertEqual(rep['changed'], 0)
        self.assertEqual(self.octets(), avant)

    def test_eleve_inconnu_non_cree(self):
        code, rep = self.envoyer([self.snap('E9', 'NOUVEAU', [
            tx('T5', '2026-11-24', 7000)])])
        self.assertEqual(code, 200)
        self.assertEqual(rep['done'], ['E9'])
        self.assertEqual(rep['ignored'], ['E9'])
        self.assertIsNone(self.eleve_serveur('E9'))
        self.assertEqual(self.lire()['_revision'], 3, 'rien écrit')

    def test_envoi_repete_idempotent(self):
        s = [self.snap('E1', 'KABILA', [tx('T1', '2026-11-17', 3000),
                                        tx('T2', '2026-11-24', 2000)])]
        self.envoyer(s)
        apres1 = self.octets()
        code, rep = self.envoyer(s)
        self.assertEqual(rep['changed'], 0)
        self.assertEqual(self.octets(), apres1)
        self.assertEqual(self.lire()['_revision'], 4)

    def test_transactions_sans_id_comparees_par_signature(self):
        d = self.lire()
        d['history'][ANNEE]['eleves'][1]['transactions'] = [
            {'id': 'LEG_abc', 'date': '2026-10-01', 'mois': 'Septembre',
             'amount': 1500}]
        d['history'][ANNEE]['eleves'][1]['paid'] = {'Septembre': 1500}
        self.ecrire(d)
        # L'ancienne version renvoie la même transaction SANS id : pas de double.
        self.envoyer([self.snap('E2', 'MUKENDI', [
            {'date': '2026-10-01', 'mois': 'Septembre', 'amount': 1500}])])
        e = self.eleve_serveur('E2')
        self.assertEqual(len(e['transactions']), 1)
        self.assertEqual(e['paid'], {'Septembre': 1500})

    def test_mois_sans_transaction_conserve(self):
        d = self.lire()
        d['history'][ANNEE]['eleves'][0]['paid']['Octobre'] = 4000  # ancien
        self.ecrire(d)
        self.envoyer([self.snap('E1', 'KABILA', [
            tx('T1', '2026-11-17', 3000), tx('T2', '2026-11-24', 2000)])])
        self.assertEqual(self.eleve_serveur('E1')['paid'],
                         {'Septembre': 5000, 'Octobre': 4000})

    def test_backup_suivant_refuse_si_revision_ancienne(self):
        # Après un ajout (révision 4), un ordinateur resté à la révision 3
        # doit d'abord récupérer : STALE_REVISION.
        self.envoyer([self.snap('E1', 'KABILA', [tx('T2', '2026-11-24', 2000)])])
        data = self.lire()
        data.pop('_revision')
        r = self.client.post('/backup', json={
            'school_code': CODE, 'data': data, 'base_revision': 3})
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.get_json()['code'], 'STALE_REVISION')

    # -- paiements annulés : jamais réajoutés --
    def sauvegarder(self, transformer):
        data = self.lire()
        rev = data.pop('_revision')
        data.pop('_tx_supprimees', None)   # l'application ne la renvoie pas
        data.pop('_saved_at', None)
        transformer(data)
        r = self.client.post('/backup', json={
            'school_code': CODE, 'data': data, 'base_revision': rev})
        self.assertEqual(r.status_code, 200, r.get_json())

    def enrichir(self):
        # Un autre élève a beaucoup payé : annuler T1 (3 000) ne déclenche
        # pas le garde-fou « perte d'argent » de /backup.
        d = self.lire()
        d['history'][ANNEE]['eleves'][1] = eleve(
            'E2', 'MUKENDI', [tx('T0', '2026-11-01', 50000)])
        self.ecrire(d)

    def test_paiement_annule_ne_revient_pas(self):
        self.enrichir()

        def annuler_t1(d):
            e1 = d['history'][ANNEE]['eleves'][0]
            e1['transactions'] = []
            e1['paid'] = {}
        self.sauvegarder(annuler_t1)
        self.assertEqual(self.lire()['_tx_supprimees'], ['E1|T1'])

        # Un ancien ordinateur en retard renvoie T1 (et un vrai nouveau T2).
        code, rep = self.envoyer([self.snap('E1', 'KABILA', [
            tx('T1', '2026-11-17', 3000), tx('T2', '2026-11-24', 2000)])])
        e = self.eleve_serveur('E1')
        self.assertEqual([t['id'] for t in e['transactions']], ['T2'])
        self.assertEqual(e['paid'], {'Septembre': 2000})

        # /restore ne renvoie pas la liste interne.
        r = self.client.get(f'/restore?school_code={CODE}',
                            headers={'X-Backup-Password': MDP})
        self.assertNotIn('_tx_supprimees', r.get_json())

        # Sauvegarde suivante sans la liste : elle est conservée.
        self.sauvegarder(lambda d: None)
        self.assertEqual(self.lire()['_tx_supprimees'], ['E1|T1'])

    def test_paiement_retabli_par_sauvegarde_sort_de_la_liste(self):
        self.enrichir()

        def annuler(d):
            d['history'][ANNEE]['eleves'][0]['transactions'] = []
        self.sauvegarder(annuler)

        def retablir(d):
            d['history'][ANNEE]['eleves'][0]['transactions'] = [
                tx('T1', '2026-11-17', 3000)]
        self.sauvegarder(retablir)
        self.assertEqual(self.lire()['_tx_supprimees'], [])

    def test_eleve_absent_de_la_sauvegarde_non_concerne(self):
        self.enrichir()

        def archiver_e1(d):
            d['history'][ANNEE]['eleves'] = d['history'][ANNEE]['eleves'][1:]
        self.sauvegarder(archiver_e1)
        self.assertEqual(self.lire()['_tx_supprimees'], [])

    def test_liste_plafonnee(self):
        ancien = serveur._MAX_TX_SUPPRIMEES
        serveur._MAX_TX_SUPPRIMEES = 2
        try:
            self.enrichir()
            d = self.lire()
            d['_tx_supprimees'] = ['X|1', 'X|2']
            self.ecrire(d)
            self.sauvegarder(lambda d: d['history'][ANNEE]['eleves'][0]
                             .update({'transactions': []}))
            self.assertEqual(self.lire()['_tx_supprimees'], ['X|2', 'E1|T1'])
        finally:
            serveur._MAX_TX_SUPPRIMEES = ancien

    # -- /backup : version des paiements des parents --
    def test_backup_met_a_jour_version_des_eleves_modifies(self):
        data = self.lire()
        data.pop('_revision')
        data['history'][ANNEE]['eleves'][1]['transactions'] = [
            tx('T7', '2026-11-24', 2500)]
        data['history'][ANNEE]['eleves'][1]['paid'] = {'Septembre': 2500}
        v1_avant = payment_sync.get_payment_version(CODE, 'E1')
        r = self.client.post('/backup', json={
            'school_code': CODE, 'data': data, 'base_revision': 3})
        self.assertEqual(r.status_code, 200, r.get_json())
        self.assertGreater(payment_sync.get_payment_version(CODE, 'E2'), 0)
        self.assertEqual(payment_sync.get_payment_version(CODE, 'E1'), v1_avant,
                         'élève non modifié : version inchangée')


if __name__ == '__main__':
    try:
        unittest.main(verbosity=2)
    finally:
        shutil.rmtree(DATA_TMP, ignore_errors=True)
