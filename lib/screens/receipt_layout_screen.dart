import 'dart:io';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart'
    show PosStyles, PosAlign, PosFontType;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../frais_scolaires.dart';
import '../services/epson_printer_service.dart';
import '../services/receipt_layout_settings.dart';
import 'dart:typed_data';

// ============================================================================
// ÉLÈVE D'EXEMPLE : utilisé à la fois par l'APERÇU et par le REÇU D'ESSAI,
// pour que le papier imprimé ressemble exactement à l'aperçu à l'écran.
// (Les vrais reçus utilisent toujours les vraies données de l'élève.)
// ============================================================================
const String _kNomExemple = 'BARAKA BININGA TIMOTHEE';
const String _kIdExemple = 'KA26E1';
const String _kClasseExemple = '3ème';
const String _kSectionExemple = 'Scient.';
const String _kAdresseExemple = 'Av. Lumumba n°12, Kolwezi';
const String _kPereExemple = 'Mukendi Pierre';
const String _kMereExemple = 'Kabeya Marie';
const String _kNaissanceExemple = '14/05/2010';
const String _kChampPersoExemple = 'Exemple';

/// Mêmes clés que le résolveur de l'écran d'accueil.
Map<String, String> _infosEleveExemple(List<String> champsPerso) {
  final Map<String, String> m = <String, String>{
    'adresse': _kAdresseExemple,
    'pere': _kPereExemple,
    'mere': _kMereExemple,
    'dateNaissance': _kNaissanceExemple,
  };
  for (final q in champsPerso) {
    m['cf:$q'] = _kChampPersoExemple;
  }
  return m;
}

class ReceiptLayoutScreen extends StatefulWidget {
  final FraisScolaires fraisScolaires;
  const ReceiptLayoutScreen({super.key, required this.fraisScolaires});

  @override
  State<ReceiptLayoutScreen> createState() => _ReceiptLayoutScreenState();
}

class _ReceiptLayoutScreenState extends State<ReceiptLayoutScreen> {
  ReceiptLayoutSettings _s = ReceiptLayoutSettings();
  bool _loading = true;
  bool _saving = false;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await receiptLayout.charger(force: true);
    _s = ReceiptLayoutSettings.fromJson(receiptLayout.toJson());
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<bool> _enregistrer({bool silencieux = false}) async {
    setState(() => _saving = true);
    receiptLayout.copierDepuis(_s);
    final ok = await receiptLayout.sauvegarder();
    if (!mounted) return ok;
    setState(() => _saving = false);
    if (!silencieux) {
      _snack(
        ok
            ? '✅ Mise en forme enregistrée. Tous les prochains reçus '
            'l\'utiliseront.'
            : '❌ Impossible d\'enregistrer les réglages.',
        color: ok ? Colors.green : Colors.red,
      );
    }
    return ok;
  }

  void _choisirFormat(String p) {
    setState(() {
      if (p == kReceiptPresetCustom && _s.preset != kReceiptPresetCustom) {
        _s.appliquerBase(_s.preset == kReceiptPresetClassic
            ? kReceiptPresetClassic
            : kReceiptPresetLarge);
      }
      _s.preset = p;
    });
  }

  Future<Uint8List?> _logo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('has_logo') ?? false)) return null;
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/school_logo.png');
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }

  Future<void> _imprimerEssai() async {
    setState(() => _printing = true);
    try {
      await _enregistrer(silencieux: true);
      final prefs = await SharedPreferences.getInstance();
      final printerName = prefs.getString('printer_name') ?? '';
      if (printerName.isEmpty) {
        _snack('Aucune imprimante choisie. Sélectionnez-la dans les '
            'Paramètres.', color: Colors.orange);
        return;
      }
      final logo = await _logo();
      final fs = widget.fraisScolaires;
      // Reçu d'essai = élève d'exemple de l'aperçu, avec des informations
      // remplies : tout ce qui est coché apparaît donc sur le papier.
      final bool ok = await EscPosPrinterService.printReceipt(
        printerName: printerName,
        schoolName: fs.config.schoolName,
        currentYear: fs.currentYear,
        studentName: _kNomExemple,
        studentId: _kIdExemple,
        classe: _kClasseExemple,
        section: _kSectionExemple,
        infosEleveEssai: _infosEleveExemple(_s.champsPerso),
        moisPaye: 'Septembre',
        montantPaye: 30000,
        montantRequis: 35000,
        resteAPayerMois: 5000,
        totalDejaPayeAnnee: 30000,
        totalRequis: 350000,
        historiqueTransactions: const [],
        receiptNumber: 'ESSAI-0001',
        logoBytes: logo,
        noteExplicative: "REÇU D'ESSAI",
      );
      _snack(
        ok ? '🖨️ Reçu d\'essai envoyé.' : '❌ Échec de l\'impression d\'essai.',
        color: ok ? Colors.green : Colors.red,
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // ------------------------------------------------------------------------
  // INFORMATIONS DE L'ÉCOLE (adresse, téléphone…)
  // ------------------------------------------------------------------------

  static const List<String> _suggestionsInfosEcole = [
    'Adresse de l\'école',
    'Téléphone',
    'E-mail',
    'N° d\'agrément',
  ];

  bool get _peutAjouterInfoEcole => _s.infosEcole.length < kMaxInfosEcole;

  void _ajouterInfoEcole([String nom = '']) {
    if (!_peutAjouterInfoEcole) {
      _snack('Maximum $kMaxInfosEcole informations de l\'école.',
          color: Colors.orange);
      return;
    }
    setState(() => _s.infosEcole.add(InfoEcole(nom: nom)));
  }

  void _supprimerInfoEcole(InfoEcole info) {
    setState(() => _s.infosEcole.remove(info));
  }

  void _deplacerInfoEcole(InfoEcole info, int sens) {
    final int i = _s.infosEcole.indexOf(info);
    final int j = i + sens;
    if (i < 0 || j < 0 || j >= _s.infosEcole.length) return;
    setState(() {
      _s.infosEcole.removeAt(i);
      _s.infosEcole.insert(j, info);
    });
  }

  Widget _carteInfoEcole(InfoEcole info) {
    final int index = _s.infosEcole.indexOf(info);
    final bool valeurVide = info.valeur.trim().isEmpty;
    return Card(
      key: ObjectKey(info),
      color: Colors.grey.shade50,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.indigo.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: info.nom,
                    maxLength: kMaxNomInfoEcole,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nom de l\'information',
                      hintText: 'ex. Adresse de l\'école',
                      border: OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                    onChanged: (v) => setState(() => info.nom = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Monter',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed:
                  index > 0 ? () => _deplacerInfoEcole(info, -1) : null,
                ),
                IconButton(
                  tooltip: 'Descendre',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: index < _s.infosEcole.length - 1
                      ? () => _deplacerInfoEcole(info, 1)
                      : null,
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _supprimerInfoEcole(info),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextFormField(
                initialValue: info.valeur,
                maxLength: kMaxValeurInfoEcole,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Valeur',
                  hintText: 'ex. Av. Lumumba n°5, Kolwezi',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: valeurVide
                      ? 'Remplissez la valeur, sinon rien ne sera imprimé.'
                      : null,
                  helperStyle: const TextStyle(color: Colors.orange),
                ),
                onChanged: (v) => setState(() => info.valeur = v),
              ),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Imprimer sur les reçus'),
              value: info.afficher,
              onChanged: (v) => setState(() => info.afficher = v ?? true),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Écrire le nom devant la valeur'),
              subtitle: Text(
                info.valeur.trim().isEmpty
                    ? 'Sur le reçu : (rien tant que la valeur est vide)'
                    : 'Sur le reçu : ${info.texte}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: info.afficherNom,
              onChanged: (v) => setState(() => info.afficherNom = v ?? true),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _sectionInfosEcole() {
    return [
      const Text(
        'Ajoutez les informations de l\'école à imprimer sous le logo et le '
            'nom de l\'école (valable pour tous les formats et tous les reçus).',
        style: TextStyle(fontSize: 12.5, color: Colors.black54),
      ),
      const SizedBox(height: 12),
      if (_s.infosEcole.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Aucune information pour le moment.',
            style: TextStyle(
                color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
        ),
      ..._s.infosEcole.map(_carteInfoEcole),
      const Text('Ajouter rapidement :',
          style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ..._suggestionsInfosEcole.map(
                (n) => ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(n),
              onPressed: _peutAjouterInfoEcole
                  ? () => _ajouterInfoEcole(n)
                  : null,
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Autre information'),
            onPressed:
            _peutAjouterInfoEcole ? () => _ajouterInfoEcole() : null,
          ),
        ],
      ),
    ];
  }

  // ------------------------------------------------------------------------
  // WIDGETS UTILITAIRES
  // ------------------------------------------------------------------------

  static const Map<int, String> _libellesTaille = {
    -1: 'Automatique (selon la longueur du nom)',
    0: 'Normal',
    1: 'Haut (×2 en hauteur)',
    2: 'Large (×2 en largeur)',
    3: 'Très grand (×2 hauteur et largeur)',
    4: 'Petit',
  };

  Widget _taille(String titre, int valeur, List<int> permis,
      ValueChanged<int> onChanged) {
    final int v = permis.contains(valeur) ? valeur : permis.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: titre,
          border: const OutlineInputBorder(),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: v,
            isExpanded: true,
            items: permis
                .map((c) => DropdownMenuItem<int>(
                value: c, child: Text(_libellesTaille[c] ?? '$c')))
                .toList(),
            onChanged: (n) {
              if (n != null) onChanged(n);
            },
          ),
        ),
      ),
    );
  }

  Widget _curseur(String titre, int valeur, int min, int max,
      ValueChanged<int> onChanged,
      {String suffixe = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$titre : $valeur$suffixe'),
        Slider(
          value: valeur.clamp(min, max).toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (d) => onChanged(d.round()),
        ),
      ],
    );
  }

  Widget _choixFormat(String valeur, String titre, String description) {
    final bool actif = _s.preset == valeur;
    return Card(
      color: actif ? Colors.indigo.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: actif ? Colors.indigo : Colors.grey.shade300,
            width: actif ? 2 : 1),
      ),
      child: ListTile(
        leading: Icon(
          actif ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: Colors.indigo,
        ),
        title: Text(titre, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
        onTap: () => _choisirFormat(valeur),
      ),
    );
  }

  Widget _section(String titre, IconData icone, List<Widget> enfants) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icone, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(titre,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 12),
            ...enfants,
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mise en forme des reçus')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bool perso = _s.preset == kReceiptPresetCustom;
    final theme = ReceiptTheme.fromSettings(_s);
    final List<String> questions =
    List<String>.from(widget.fraisScolaires.config.customFieldQuestions);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mise en forme des reçus'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('1. Format du reçu', Icons.receipt_long, [
            _choixFormat(
              kReceiptPresetLarge,
              'Grand format (actuel)',
              'Gros caractères, grand logo, grand espace pour la signature '
                  'et le cachet.',
            ),
            _choixFormat(
              kReceiptPresetClassic,
              'Classique compact (première version)',
              'Caractères normaux, petit logo, reçu plus court.',
            ),
            _choixFormat(
              kReceiptPresetCustom,
              'Personnalisé (experts)',
              'Réglez vous-même les tailles, les logos et l\'espace de '
                  'signature.',
            ),
          ]),
          const SizedBox(height: 12),
          _section('2. Informations de l\'école sur le reçu', Icons.school,
              _sectionInfosEcole()),
          const SizedBox(height: 12),
          _section('3. Informations de l\'élève sur le reçu', Icons.badge, [
            const Text(
              'Cochez les informations à imprimer sous le nom de l\'élève '
                  '(valable pour tous les formats).',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Adresse de l\'élève'),
              value: _s.showAdresse,
              onChanged: (v) => setState(() => _s.showAdresse = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nom du père'),
              value: _s.showPere,
              onChanged: (v) => setState(() => _s.showPere = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nom de la mère'),
              value: _s.showMere,
              onChanged: (v) => setState(() => _s.showMere = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date de naissance'),
              value: _s.showDateNaissance,
              onChanged: (v) => setState(() => _s.showDateNaissance = v),
            ),
            if (questions.isNotEmpty) ...[
              const Divider(),
              const Text('Autres informations enregistrées :',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              ...questions.map(
                    (q) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(q),
                  value: _s.champsPerso.contains(q),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      if (!_s.champsPerso.contains(q)) _s.champsPerso.add(q);
                    } else {
                      _s.champsPerso.remove(q);
                    }
                  }),
                ),
              ),
            ],
          ]),
          if (perso) ...[
            const SizedBox(height: 12),
            _section('4. Personnalisation avancée', Icons.tune, [
              const Text('Repartir d\'un des deux formats :',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Grand format'),
                  onPressed: () => setState(
                          () => _s.appliquerBase(kReceiptPresetLarge)),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Classique compact'),
                  onPressed: () => setState(
                          () => _s.appliquerBase(kReceiptPresetClassic)),
                ),
              ]),
              const SizedBox(height: 16),
              const Text('Taille des caractères',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _taille("Nom de l'élève", _s.zoneName, const [-1, 0, 1, 2, 3],
                      (v) => setState(() => _s.zoneName = v)),
              _taille('Titre du reçu', _s.zoneTitle, const [0, 1, 2, 3],
                      (v) => setState(() => _s.zoneTitle = v)),
              _taille("Nom de l'école (quand il n'y a pas de logo)",
                  _s.zoneSchool, const [0, 1, 2, 3],
                      (v) => setState(() => _s.zoneSchool = v)),
              _taille('Lignes courantes (mois, montants, classe…)',
                  _s.zoneBody, const [0, 1],
                      (v) => setState(() => _s.zoneBody = v)),
              _taille('Totaux (TOTAL PAYÉ, Reste à payer)', _s.zoneTotals,
                  const [0, 1], (v) => setState(() => _s.zoneTotals = v)),
              _taille('Détails (n° de reçu, dates)', _s.zoneDetails,
                  const [4, 0, 1],
                      (v) => setState(() => _s.zoneDetails = v)),
              _taille('Libellé « Signature »', _s.zoneSignature,
                  const [0, 1, 2, 3],
                      (v) => setState(() => _s.zoneSignature = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Texte en gras'),
                value: _s.bold,
                onChanged: (v) => setState(() => _s.bold = v),
              ),
              const Divider(),
              const Text('Logo(s) de l\'école',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Aucun')),
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                ],
                selected: {_s.logoCount},
                onSelectionChanged: (sel) =>
                    setState(() => _s.logoCount = sel.first),
              ),
              const SizedBox(height: 4),
              const Text(
                '1 = à gauche · 2 = de chaque côté du nom · 3 = de chaque '
                    'côté + un au centre au-dessus du nom.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              _curseur('Taille du logo', _s.logoBox, 40, 160,
                      (v) => setState(() => _s.logoBox = v),
                  suffixe: ' pts'),
              _curseur("Largeur de l'en-tête", _s.headerWidth, 300, 576,
                      (v) => setState(() => _s.headerWidth = v),
                  suffixe: ' pts'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Nom de l\'école en grandes lettres'),
                subtitle: const Text(
                    'Si le nom est trop long, il passe automatiquement '
                        'en plus petit.'),
                value: _s.bigSchoolName,
                onChanged: (v) => setState(() => _s.bigSchoolName = v),
              ),
              const Divider(),
              const Text('Structure du reçu',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              _curseur('Espace pour signature + cachet', _s.signatureFeed, 0,
                  15, (v) => setState(() => _s.signatureFeed = v),
                  suffixe: ' lignes'),
              _curseur('Largeur des lignes de séparation', _s.cols, 28, 48,
                      (v) => setState(() => _s.cols = v),
                  suffixe: ' caractères'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Signature sur le reçu « Bilan + historique »'),
                value: _s.signatureOnHistory,
                onChanged: (v) => setState(() => _s.signatureOnHistory = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Afficher « Merci pour votre paiement ! »'),
                value: _s.showMerci,
                onChanged: (v) => setState(() => _s.showMerci = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Afficher « Conservez ce reçu. »'),
                value: _s.showConserver,
                onChanged: (v) => setState(() => _s.showConserver = v),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          _section(perso ? '5. Aperçu' : '4. Aperçu', Icons.visibility, [
            const Text(
              'Aperçu indicatif : le résultat exact dépend de l\'imprimante. '
                  'Utilisez l\'impression d\'essai pour vérifier.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _ReceiptPreview(
                  t: theme,
                  s: _s,
                  schoolName: widget.fraisScolaires.config.schoolName,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              icon: _saving
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: const Text('Enregistrer la mise en forme'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: _saving ? null : () => _enregistrer(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              icon: _printing
                  ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print),
              label: const Text('Enregistrer et imprimer un reçu d\'essai'),
              onPressed: _printing ? null : _imprimerEssai,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================================================================
// APERÇU D'UN REÇU (construit avec les mêmes styles que l'impression)
// ============================================================================
class _Col {
  final String text;
  final int width;
  final PosStyles style;
  const _Col(this.text, this.width, this.style);
}

class _ReceiptPreview extends StatelessWidget {
  final ReceiptTheme t;
  final ReceiptLayoutSettings s;
  final String schoolName;

  const _ReceiptPreview(
      {required this.t, required this.s, required this.schoolName});

  static const double _base = 11.0;
  static const double _cw = 6.6; // largeur d'un caractère de base
  static const double _paper = 48 * _cw; // 48 colonnes = papier 80 mm

  Widget _txt(String text, PosStyles st) {
    final int w = st.width.value;
    final int h = st.height.value;
    final bool petit = st.fontType == PosFontType.fontB;
    final double fs = _base * (petit ? 0.86 : 1.0) * w;
    final double ratio = h / w;
    final Alignment al = st.align == PosAlign.center
        ? Alignment.topCenter
        : (st.align == PosAlign.right
        ? Alignment.topRight
        : Alignment.topLeft);
    Widget tx = Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: fs,
        height: 1.15,
        color: Colors.black,
        fontWeight: st.bold ? FontWeight.w800 : FontWeight.w400,
        decoration:
        st.underline ? TextDecoration.underline : TextDecoration.none,
      ),
    );
    if (ratio != 1) {
      tx = SizedBox(
        height: fs * 1.15 * ratio,
        child: Transform.scale(
            scaleY: ratio, alignment: Alignment.topLeft, child: tx),
      );
    }
    return Align(alignment: al, child: tx);
  }

  Widget _ligne(String text, PosStyles st) => _txt(text, st);

  Widget _row(List<_Col> cols) => Row(
    children: cols
        .map((c) => Expanded(flex: c.width, child: _txt(c.text, c.style)))
        .toList(),
  );

  Widget _sep(String ch) => _txt(ch * t.cols, t.center);

  Widget _logoBox(double box) => Container(
    width: box,
    height: box,
    decoration: BoxDecoration(
      color: Colors.grey.shade300,
      border: Border.all(color: Colors.black54),
    ),
    alignment: Alignment.center,
    child: const Text('LOGO', style: TextStyle(fontSize: 7)),
  );

  Widget _entete() {
    if (t.logoCount <= 0) {
      return _txt(schoolName.toUpperCase(), t.schoolFor(schoolName));
    }
    final double k = _paper / 576;
    final double box = t.logoBox * k;
    final int n = t.logoCount > 3 ? 3 : t.logoCount;
    final Widget nom = Expanded(
      child: Center(
        child: Text(
          schoolName.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: t.bigSchoolName && box >= 45 ? 15 : 11,
          ),
        ),
      ),
    );
    return Center(
      child: SizedBox(
        width: t.headerWidth * k,
        child: Column(
          children: [
            if (n >= 3) _logoBox(box),
            Row(children: [
              _logoBox(box),
              nom,
              if (n >= 2) _logoBox(box),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const String nom = _kNomExemple;
    // Mêmes règles que l'impression : découpage à la largeur du reçu.
    final List<Widget> infos = [];
    void info(String l) {
      for (final ligne in decouperTexteRecu(l, t.cols)) {
        infos.add(_ligne(ligne, t.row));
      }
    }

    if (s.showAdresse) info('Adresse : $_kAdresseExemple');
    if (s.showPere) info('Père : $_kPereExemple');
    if (s.showMere) info('Mère : $_kMereExemple');
    if (s.showDateNaissance) info('Né(e) le : $_kNaissanceExemple');
    for (final q in s.champsPerso) {
      info('$q : $_kChampPersoExemple');
    }

    final List<Widget> infosEcole = [];
    for (final i in s.infosEcoleImprimables) {
      for (final ligne in decouperTexteRecu(i.texte, t.cols)) {
        infosEcole.add(_txt(ligne, t.bodyCenter));
      }
    }

    return Container(
      width: _paper + 24,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sep('='),
          _entete(),
          ...infosEcole,
          _txt('REÇU DE PAIEMENT', t.titleFor('REÇU DE PAIEMENT')),
          _txt('Année scolaire : 2025-2026', t.bodyCenter),
          _sep('='),
          _txt('Nom complet :', t.label),
          _txt(nom, t.nameStyle(nom)),
          ...infos,
          _sep('.'),
          _row([_Col('Reçu : RCP-20261117-1', 12, t.small)]),
          _row([
            _Col('ID : $_kIdExemple', 6, t.row),
            _Col('Cl. : $_kClasseExemple', 6, t.row),
          ]),
          _row([
            _Col('Sect. : $_kSectionExemple', 6, t.row),
            _Col('17/11/2026 09:30', 6, t.small),
          ]),
          _sep('-'),
          _txt('DÉTAIL DES PAIEMENTS (2)', t.bodyCenter),
          _sep('-'),
          _row([
            _Col('Septembre', 6, t.row),
            _Col('35000 FC', 6, t.rowRight),
          ]),
          _txt('   le 2026-09-05', t.detail),
          _row([
            _Col('Octobre', 6, t.row),
            _Col('20000 FC', 6, t.rowRight),
          ]),
          _txt('   le 2026-10-03', t.detail),
          _sep('-'),
          _row([
            _Col('TOTAL PAYÉ :', 6, t.strong),
            _Col('55000 FC', 6, t.strongRight),
          ]),
          _sep('-'),
          _txt(t.signatureLabel, t.signature),
          SizedBox(height: t.signatureFeed * 13.0),
          _txt('.' * t.cols, t.center),
          _sep('='),
          if (t.showMerci)
            _txt('Merci pour votre paiement !', t.bodyCenter),
          if (t.showConserver) _txt('Conservez ce reçu.', t.conserver),
          _sep('='),
        ],
      ),
    );
  }
}