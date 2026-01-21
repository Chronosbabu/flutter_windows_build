import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// Modèle de transaction
class TransactionModel {
  final int? id;
  final double amount;
  final String type; // 'income' or 'expense'
  final String description;
  final DateTime date;
  final String currency; // 'USD' or 'CDF'

  TransactionModel({
    this.id,
    required this.amount,
    required this.type,
    required this.description,
    required this.date,
    required this.currency,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'description': description,
      'date': date.toIso8601String(),
      'currency': currency,
    };
  }

  static TransactionModel fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      amount: map['amount'],
      type: map['type'],
      description: map['description'],
      date: DateTime.parse(map['date']),
      currency: map['currency'] ?? 'CDF', // Default to CDF if null (for old data)
    );
  }
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
  double _balanceUSD = 0.0;
  double _balanceCDF = 0.0;
  List<TransactionModel> _transactions = [];
  Database? _database;

  double get balanceUSD => _balanceUSD;
  double get balanceCDF => _balanceCDF;
  List<TransactionModel> get transactions => _transactions;

  Future<void> initDatabase() async {
    String path = join(await getDatabasesPath(), 'cash_app.db');
    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE transactions(id INTEGER PRIMARY KEY, amount REAL, type TEXT, description TEXT, date TEXT, currency TEXT)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE transactions ADD COLUMN currency TEXT');
        }
      },
    );
    await _loadData();
  }

  Future<void> _loadData() async {
    final List<Map<String, dynamic>> maps = await _database!.query('transactions', orderBy: 'date DESC');
    _transactions = List.generate(maps.length, (i) => TransactionModel.fromMap(maps[i]));
    _balanceUSD = _transactions
        .where((tx) => tx.currency == 'USD')
        .fold(0.0, (prev, tx) => prev + (tx.type == 'income' ? tx.amount : -tx.amount))
        .clamp(0.0, double.infinity);
    _balanceCDF = _transactions
        .where((tx) => tx.currency == 'CDF')
        .fold(0.0, (prev, tx) => prev + (tx.type == 'income' ? tx.amount : -tx.amount))
        .clamp(0.0, double.infinity);
    notifyListeners();
  }

  Future<void> addTransaction(double amount, String type, String description, String currency) async {
    final tx = TransactionModel(
      amount: amount,
      type: type,
      description: description,
      date: DateTime.now(),
      currency: currency,
    );
    await _database!.insert('transactions', tx.toMap());
    await _loadData();
  }

  Future<void> deleteTransaction(int id) async {
    await _database!.delete('transactions', where: 'id = ?', whereArgs: [id]);
    await _loadData();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final provider = CashProvider();
            provider.initDatabase();
            return provider;
          },
        ),
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
            appBarTheme: const AppBarTheme(
              elevation: 0,
            ),
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
            appBarTheme: const AppBarTheme(
              elevation: 0,
            ),
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
          home: const HomePage(),
        );
      },
    );
  }
}

// Utility function for formatting balance
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

// Widget for displaying a single balance card
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
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
        ),
        child: Column(
          children: [
            Text(title, style: TextStyle(color: textColor, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              '${formatBalance(balance, abbreviate)} $symbol',
              style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// Widget for action buttons (Entrée and Sortie)
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

// Widget for the transaction list
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
                      content: const Text('Voulez-vous vraiment supprimer cette transaction ?'),
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

// Dialog for adding transactions
class AddTransactionDialog extends StatefulWidget {
  final String type;
  final Function(double, String, String, String) onAdd;

  const AddTransactionDialog({
    super.key,
    required this.type,
    required this.onAdd,
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
          onPressed: () {
            final amount = double.tryParse(amountController.text) ?? 0.0;
            if (amount > 0) {
              final provider = Provider.of<CashProvider>(context, listen: false);
              bool sufficient = true;
              if (widget.type == 'expense') {
                double balance = selectedCurrency == 'USD' ? provider.balanceUSD : provider.balanceCDF;
                if (amount > balance) {
                  sufficient = false;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Erreur'),
                      content: const Text('Impossible, le solde de votre compte est insuffisant.'),
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
                widget.onAdd(amount, widget.type, descController.text, selectedCurrency);
                Navigator.pop(context);
              }
            }
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _showAddDialog(BuildContext context, String type) {
    final provider = Provider.of<CashProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AddTransactionDialog(
        type: type,
        onAdd: provider.addTransaction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cashProvider = Provider.of<CashProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion de Caisse', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
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
          const Text('Historique des Transactions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          TransactionList(
            transactions: cashProvider.transactions,
            onDelete: (tx) => cashProvider.deleteTransaction(tx.id!),
            incomeColor: theme.colorScheme.secondary,
            expenseColor: theme.colorScheme.error,
            deleteColor: theme.colorScheme.error,
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
              if (value != null) {
                themeProvider.setThemeMode(value);
              }
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Mode Sombre'),
            value: ThemeMode.dark,
            groupValue: themeProvider.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                themeProvider.setThemeMode(value);
              }
            },
          ),
        ],
      ),
    );
  }
}
