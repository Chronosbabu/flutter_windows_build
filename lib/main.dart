import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Modèle de transaction
part 'main.g.dart';

@HiveType(typeId: 0)
class TransactionModel extends HiveObject {
  @HiveField(0)
  int? id;

  @HiveField(1)
  final double amount;

  @HiveField(2)
  final String type; // 'income' or 'expense'

  @HiveField(3)
  final String description;

  @HiveField(4)
  final DateTime date;

  @HiveField(5)
  final String currency; // 'USD' or 'CDF'

  TransactionModel({
    this.id,
    required this.amount,
    required this.type,
    required this.description,
    required this.date,
    required this.currency,
  });
}

// Provider pour la gestion d'état des thèmes et paramètres
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  bool _abbreviateBalance = true;

  ThemeMode get themeMode => _themeMode;
  bool get abbreviateBalance => _abbreviateBalance;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _abbreviateBalance = prefs.getBool('abbreviate_balance') ?? true;
    String? theme = prefs.getString('theme_mode');
    _themeMode = (theme == 'dark') ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('theme_mode', mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> setAbbreviateBalance(bool value) async {
    _abbreviateBalance = value;
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('abbreviate_balance', value);
    notifyListeners();
  }
}

// Provider pour la gestion de caisse
class CashProvider extends ChangeNotifier {
  final String category;
  double _balanceUSD = 0.0;
  double _balanceCDF = 0.0;
  List<TransactionModel> _transactions = [];
  late Box<TransactionModel> _box;

  double get balanceUSD => _balanceUSD;
  double get balanceCDF => _balanceCDF;
  List<TransactionModel> get transactions => _transactions;

  CashProvider(this.category);

  Future<void> initDatabase() async {
    _box = await Hive.openBox<TransactionModel>('transactions_$category');
    // Chargement/migration des soldes persistants
    final prefs = await SharedPreferences.getInstance();
    final List<TransactionModel> allTx = _box.values.toList();
    final double calculatedUSD = allTx
        .where((tx) => tx.currency == 'USD')
        .fold(0.0, (prev, tx) => prev + (tx.type == 'income' ? tx.amount : -tx.amount))
        .clamp(0.0, double.infinity);
    final double calculatedCDF = allTx
        .where((tx) => tx.currency == 'CDF')
        .fold(0.0, (prev, tx) => prev + (tx.type == 'income' ? tx.amount : -tx.amount))
        .clamp(0.0, double.infinity);
    _balanceUSD = prefs.getDouble('balance_USD_$category') ?? calculatedUSD;
    _balanceCDF = prefs.getDouble('balance_CDF_$category') ?? calculatedCDF;
    // Si c'était la première fois (pas encore de clé), on sauvegarde les soldes calculés
    if (!prefs.containsKey('balance_USD_$category')) {
      await prefs.setDouble('balance_USD_$category', _balanceUSD);
      await prefs.setDouble('balance_CDF_$category', _balanceCDF);
    }
    await _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    _transactions = _box.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  Future<void> addTransaction(double amount, String type, String description, String currency) async {
    final prefs = await SharedPreferences.getInstance();
    // Mise à jour du solde (seulement à l'ajout)
    if (currency == 'USD') {
      _balanceUSD += type == 'income' ? amount : -amount;
      _balanceUSD = _balanceUSD.clamp(0.0, double.infinity);
      await prefs.setDouble('balance_USD_$category', _balanceUSD);
    } else {
      _balanceCDF += type == 'income' ? amount : -amount;
      _balanceCDF = _balanceCDF.clamp(0.0, double.infinity);
      await prefs.setDouble('balance_CDF_$category', _balanceCDF);
    }
    final tx = TransactionModel(
      amount: amount,
      type: type,
      description: description,
      date: DateTime.now(),
      currency: currency,
    );
    await _box.add(tx);
    await _loadTransactions();
  }

  // Suppression sans impact sur le solde
  Future<void> deleteTransaction(int key) async {
    await _box.delete(key);
    await _loadTransactions();
  }

  // Réinitialisation complète
  Future<void> resetAll() async {
    await _box.clear();
    final prefs = await SharedPreferences.getInstance();
    _balanceUSD = 0.0;
    _balanceCDF = 0.0;
    await prefs.setDouble('balance_USD_$category', 0.0);
    await prefs.setDouble('balance_CDF_$category', 0.0);
    await _loadTransactions();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(TransactionModelAdapter());
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final themeProvider = ThemeProvider();
            themeProvider.init();
            return themeProvider;
          },
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Gestion de Caisse',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              secondary: Colors.green,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(elevation: 0),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              secondary: Colors.green,
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: Colors.grey[900],
            appBarTheme: const AppBarTheme(elevation: 0),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[800],
            ),
          ),
          themeMode: themeProvider.themeMode,
          home: const MainMenu(),
        );
      },
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

String formatBalance(double value, bool abbreviate) {
  value = value.clamp(0.0, double.infinity);
  if (!abbreviate) {
    return NumberFormat("#,##0.00").format(value);
  }
  String suffix = '';
  double formattedValue = value;
  if (value >= 1e9) {
    formattedValue /= 1e9;
    suffix = 'B';
  } else if (value >= 1e6) {
    formattedValue /= 1e6;
    suffix = 'M';
  } else if (value >= 1e3) {
    formattedValue /= 1e3;
    suffix = 'K';
  }
  return '${NumberFormat("#,##0.#").format(formattedValue)}$suffix';
}

class BalanceCard extends StatelessWidget {
  final String title;
  final double balance;
  final String symbol;
  final Color color;
  final Color textColor;
  final bool abbreviate;

  const BalanceCard({
    super.key,
    required this.title,
    required this.balance,
    required this.symbol,
    required this.color,
    required this.textColor,
    required this.abbreviate,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: TextStyle(color: textColor, fontSize: 16)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.fitWidth,
              child: Text(
                '${formatBalance(balance, abbreviate)} $symbol',
                style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActionButtons extends StatelessWidget {
  final VoidCallback onIncomePressed;
  final VoidCallback onExpensePressed;
  final Color incomeColor;
  final Color expenseColor;

  const ActionButtons({
    super.key,
    required this.onIncomePressed,
    required this.onExpensePressed,
    required this.incomeColor,
    required this.expenseColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            onPressed: onIncomePressed,
            icon: const Icon(Icons.add),
            label: const Text('Entrée'),
            style: ElevatedButton.styleFrom(backgroundColor: incomeColor),
          ),
          ElevatedButton.icon(
            onPressed: onExpensePressed,
            icon: const Icon(Icons.remove),
            label: const Text('Sortie'),
            style: ElevatedButton.styleFrom(backgroundColor: expenseColor),
          ),
        ],
      ),
    );
  }
}

class TransactionList extends StatelessWidget {
  final List<TransactionModel> transactions;
  final Function(TransactionModel) onDelete;
  final Color incomeColor;
  final Color expenseColor;
  final Color deleteColor;

  const TransactionList({
    super.key,
    required this.transactions,
    required this.onDelete,
    required this.incomeColor,
    required this.expenseColor,
    required this.deleteColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ListView.builder(
        itemCount: transactions.length,
        itemBuilder: (context, index) {
          final tx = transactions[index];
          String currencySymbol = tx.currency == 'USD' ? '\$' : 'FC';
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Icon(
                tx.type == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                color: tx.type == 'income' ? incomeColor : expenseColor,
              ),
              title: Text('${tx.amount.toStringAsFixed(2)} $currencySymbol - ${tx.description}'),
              subtitle: Text('${DateFormat('dd/MM/yyyy HH:mm').format(tx.date)} - ${tx.currency}'),
              trailing: IconButton(
                icon: Icon(Icons.delete, color: deleteColor),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Confirmation'),
                      content: const Text('Voulez-vous vraiment supprimer cette Transaction ?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Annuler'),
                        ),
                        TextButton(
                          onPressed: () {
                            onDelete(tx);
                            Navigator.pop(ctx);
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class AddTransactionDialog extends StatefulWidget {
  final String type;
  final Function(double, String, String, String) onAdd;
  final CashProvider cashProvider;

  const AddTransactionDialog({
    super.key,
    required this.type,
    required this.onAdd,
    required this.cashProvider,
  });

  @override
  State<AddTransactionDialog> createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  final amountController = TextEditingController();
  final descController = TextEditingController();
  String selectedCurrency = 'CDF';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.type == 'income' ? 'Ajouter Entrée' : 'Ajouter Sortie'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Montant'),
          ),
          TextField(
            controller: descController,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          DropdownButton<String>(
            value: selectedCurrency,
            items: const [
              DropdownMenuItem<String>(value: 'USD', child: Text('USD')),
              DropdownMenuItem<String>(value: 'CDF', child: Text('CDF')),
            ],
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  selectedCurrency = newValue;
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () async {
            final amount = double.tryParse(amountController.text) ?? 0.0;
            if (amount <= 0) return;
            bool sufficient = true;
            if (widget.type == 'expense') {
              double balance = selectedCurrency == 'USD'
                  ? widget.cashProvider.balanceUSD
                  : widget.cashProvider.balanceCDF;
              if (amount > balance) {
                sufficient = false;
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Erreur'),
                    content: const Text('Impossible, le solde   est insuffisant.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
            }
            if (sufficient) {
              await widget.onAdd(amount, widget.type, descController.text, selectedCurrency);
              if (mounted) Navigator.pop(context);
            }
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class CategoryHomePage extends StatelessWidget {
  final String category;

  const CategoryHomePage({super.key, required this.category});

  void _showAddDialog(BuildContext context, String type) {
    final provider = Provider.of<CashProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (dialogContext) => AddTransactionDialog(
        type: type,
        onAdd: provider.addTransaction,
        cashProvider: provider,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CashProvider>(
      create: (context) {
        final provider = CashProvider(category);
        provider.initDatabase();
        return provider;
      },
      child: Builder(
        builder: (context) {
          final cashProvider = Provider.of<CashProvider>(context);
          final themeProvider = Provider.of<ThemeProvider>(context);
          final theme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text('Gestion de Caisse - ${category.capitalize()}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SettingsPage(cashProvider: cashProvider)),
                    );
                  },
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      BalanceCard(
                        title: 'Solde USD',
                        balance: cashProvider.balanceUSD,
                        symbol: '\$',
                        color: theme.colorScheme.primary,
                        textColor: theme.colorScheme.onPrimary,
                        abbreviate: themeProvider.abbreviateBalance,
                      ),
                      BalanceCard(
                        title: 'Solde CDF',
                        balance: cashProvider.balanceCDF,
                        symbol: 'FC',
                        color: theme.colorScheme.secondary,
                        textColor: theme.colorScheme.onSecondary,
                        abbreviate: themeProvider.abbreviateBalance,
                      ),
                    ],
                  ),
                ),
                ActionButtons(
                  onIncomePressed: () => _showAddDialog(context, 'income'),
                  onExpensePressed: () => _showAddDialog(context, 'expense'),
                  incomeColor: theme.colorScheme.secondary,
                  expenseColor: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                const Text('Historique des Transactions',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                TransactionList(
                  transactions: cashProvider.transactions,
                  onDelete: (tx) => cashProvider.deleteTransaction(tx.key ?? 0),
                  incomeColor: theme.colorScheme.secondary,
                  expenseColor: theme.colorScheme.error,
                  deleteColor: theme.colorScheme.error,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final CashProvider cashProvider;

  const SettingsPage({super.key, required this.cashProvider});

  Future<void> _downloadHistory(BuildContext context) async {
    final filenameController = TextEditingController();
    String? filename;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom du fichier'),
        content: TextField(
          controller: filenameController,
          decoration: const InputDecoration(labelText: 'Entrez le nom du fichier (sans extension)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (filenameController.text.isNotEmpty) {
                filename = filenameController.text;
                Navigator.pop(ctx);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (filename == null) return;
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context pwContext) => [
          pw.Text('Solde USD: ${formatBalance(cashProvider.balanceUSD, false)} \$'),
          pw.Text('Solde CDF: ${formatBalance(cashProvider.balanceCDF, false)} FC'),
          pw.SizedBox(height: 20),
          pw.Text('Historique des Transactions'),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: ['Date', 'Type', 'Montant', 'Devise', 'Description'],
            data: cashProvider.transactions.map((tx) => [
              DateFormat('dd/MM/yyyy HH:mm').format(tx.date),
              tx.type == 'income' ? 'Entrée' : 'Sortie',
              tx.amount.toStringAsFixed(2),
              tx.currency,
              tx.description,
            ]).toList(),
          ),
        ],
      ),
    );
    final bytes = await pdf.save();
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename.pdf');
    await file.writeAsBytes(bytes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fichier sauvegardé : ${file.path}')),
    );
  }

  Future<void> _showResetConfirmation(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réinitialiser tout ?'),
        content: const Text(
          'ATTENTION ! Cette action est irréversible.\n\n'
              'Tous les soldes seront remis à zéro.\n'
              'L\'historique complet des transactions sera effacé.\n'
              'Tout sera perdu définitivement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Réinitialiser', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await cashProvider.resetAll();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tout a été réinitialisé à zéro.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Abréger les soldes (ex: 1000 → 1K)'),
            value: themeProvider.abbreviateBalance,
            onChanged: (bool value) {
              themeProvider.setAbbreviateBalance(value);
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Mode Clair'),
            value: ThemeMode.light,
            groupValue: themeProvider.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) themeProvider.setThemeMode(value);
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Mode Sombre'),
            value: ThemeMode.dark,
            groupValue: themeProvider.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) themeProvider.setThemeMode(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Télécharger l\'historique'),
            onTap: () => _downloadHistory(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore_page, color: Colors.red),
            title: const Text('Réinitialiser tout', style: TextStyle(color: Colors.red)),
            onTap: () => _showResetConfirmation(context),
          ),
        ],
      ),
    );
  }
}

class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('C-Finance', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.scaffoldBackgroundColor, theme.colorScheme.primary.withOpacity(0.1)],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Bienvenue dans Gestion de Caisse',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CategoryHomePage(category: 'paroisse'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.church),
                          label: const Text('Paroisse'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CategoryHomePage(category: 'secondaire'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.school),
                          label: const Text('Secondaire'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CategoryHomePage(category: 'primaire'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.school),
                          label: const Text('Primaire'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CategoryHomePage(category: 'maternelle'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.child_care),
                          label: const Text('Maternelle'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
