import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:animate_do/animate_do.dart';
// Modèle de transaction
part 'main.g.dart';
// Version unique pour isoler les données de cette version de l'app
const String appDataPrefix = 'v2_'; // Changez ceci pour chaque nouvelle version (ex: 'v3_', etc.)
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
  late Future<void> _initFuture;
  ThemeProvider() {
    _initFuture = init();
  }
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _abbreviateBalance = prefs.getBool(appDataPrefix + 'abbreviate_balance') ?? true;
    String? theme = prefs.getString(appDataPrefix + 'theme_mode');
    _themeMode = (theme == 'dark') ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(appDataPrefix + 'theme_mode', mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }
  Future<void> setAbbreviateBalance(bool value) async {
    _abbreviateBalance = value;
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool(appDataPrefix + 'abbreviate_balance', value);
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
  late Future<void> _initFuture;
  double get balanceUSD => _balanceUSD;
  double get balanceCDF => _balanceCDF;
  List<TransactionModel> get transactions => _transactions;
  CashProvider(this.category) {
    _initFuture = initDatabase();
  }
  Future<void> initDatabase() async {
    _box = await Hive.openBox<TransactionModel>(appDataPrefix + 'transactions_$category');
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
    _balanceUSD = prefs.getDouble(appDataPrefix + 'balance_USD_$category') ?? calculatedUSD;
    _balanceCDF = prefs.getDouble(appDataPrefix + 'balance_CDF_$category') ?? calculatedCDF;
    // Si c'était la première fois (pas encore de clé), on sauvegarde les soldes calculés
    if (!prefs.containsKey(appDataPrefix + 'balance_USD_$category')) {
      await prefs.setDouble(appDataPrefix + 'balance_USD_$category', _balanceUSD);
      await prefs.setDouble(appDataPrefix + 'balance_CDF_$category', _balanceCDF);
    }
    await _loadTransactions();
  }
  Future<void> _loadTransactions() async {
    _transactions = _box.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }
  Future<void> addTransaction(double amount, String type, String description, String currency) async {
    await _initFuture;
    final prefs = await SharedPreferences.getInstance();
    // Mise à jour du solde (seulement à l'ajout)
    if (currency == 'USD') {
      _balanceUSD += type == 'income' ? amount : -amount;
      _balanceUSD = _balanceUSD.clamp(0.0, double.infinity);
      await prefs.setDouble(appDataPrefix + 'balance_USD_$category', _balanceUSD);
    } else {
      _balanceCDF += type == 'income' ? amount : -amount;
      _balanceCDF = _balanceCDF.clamp(0.0, double.infinity);
      await prefs.setDouble(appDataPrefix + 'balance_CDF_$category', _balanceCDF);
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
    await _initFuture;
    await _box.delete(key);
    await _loadTransactions();
  }
  // Réinitialisation complète
  Future<void> resetAll() async {
    await _initFuture;
    await _box.clear();
    final prefs = await SharedPreferences.getInstance();
    _balanceUSD = 0.0;
    _balanceCDF = 0.0;
    await prefs.setDouble(appDataPrefix + 'balance_USD_$category', 0.0);
    await prefs.setDouble(appDataPrefix + 'balance_CDF_$category', 0.0);
    await _loadTransactions();
  }
}
// Provider pour la gestion des kiosques
class KioskProvider extends ChangeNotifier {
  List<String> _kiosks = [];
  late Box<String> _kioskBox;
  late Future<void> _initFuture;
  List<String> get kiosks => _kiosks;
  KioskProvider() {
    _initFuture = _init();
  }
  Future<void> _init() async {
    _kioskBox = await Hive.openBox<String>(appDataPrefix + 'kiosks');
    _kiosks = _kioskBox.values.toList();
    notifyListeners();
  }
  Future<void> addKiosk(String name) async {
    await _initFuture;
    await _kioskBox.add(name);
    _kiosks.insert(0, name); // Ajouter au début pour que les nouveaux soient en haut
    notifyListeners();
  }
  Future<void> deleteKiosk(String name, int index) async {
    await _initFuture;
    // Supprimer la box des transactions
    final box = await Hive.openBox<TransactionModel>(appDataPrefix + 'transactions_$name');
    await box.clear();
    await box.close();
    // Supprimer les soldes de SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(appDataPrefix + 'balance_USD_$name');
    await prefs.remove(appDataPrefix + 'balance_CDF_$name');
    // Supprimer le kiosque de la liste
    await _kioskBox.deleteAt(index);
    _kiosks.removeAt(index);
    notifyListeners();
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
          create: (context) => ThemeProvider(),
        ),
        ChangeNotifierProvider(
          create: (context) => KioskProvider(),
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
            cardTheme: CardThemeData(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            listTileTheme: ListTileThemeData(
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            cardTheme: CardThemeData(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            listTileTheme: ListTileThemeData(
              tileColor: Colors.grey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          themeMode: themeProvider.themeMode,
          home: const PasswordGate(),
        );
      },
    );
  }
}
class PasswordGate extends StatefulWidget {
  const PasswordGate({super.key});
  @override
  State<PasswordGate> createState() => _PasswordGateState();
}
class _PasswordGateState extends State<PasswordGate> {
  bool _isAuthenticated = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPassword();
    });
  }
  Future<void> _checkPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedPassword = prefs.getString(appDataPrefix + 'app_password');
    if (storedPassword == null || storedPassword.isEmpty) {
      await _setPasswordDialog();
    }
    await _authenticateDialog();
  }
  Future<void> _setPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();
    bool passwordsMatch = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Définir un mot de passe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
              ),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmer mot de passe'),
              ),
              if (!passwordsMatch)
                const Text('Les mots de passe ne correspondent pas.', style: TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (passwordController.text == confirmController.text && passwordController.text.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(appDataPrefix + 'app_password', passwordController.text);
                  Navigator.pop(ctx);
                } else {
                  setState(() {
                    passwordsMatch = false;
                  });
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _authenticateDialog() async {
    final TextEditingController passwordController = TextEditingController();
    bool incorrect = false;
    final prefs = await SharedPreferences.getInstance();
    final String? storedPassword = prefs.getString(appDataPrefix + 'app_password');
    final String? storedResetKey = prefs.getString(appDataPrefix + 'app_reset_key');
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Entrer mot de passe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
              ),
              if (incorrect) const Text('Mot de passe incorrect.', style: TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _forgotPasswordDialog(ctx),
              child: const Text('Mot de passe oublié ?'),
            ),
            ElevatedButton(
              onPressed: () {
                if (passwordController.text == storedPassword || passwordController.text == storedResetKey) {
                  Navigator.pop(ctx);
                  this.setState(() {
                    _isAuthenticated = true;
                  });
                } else {
                  setState(() {
                    incorrect = true;
                  });
                }
              },
              child: const Text('Entrer'),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _forgotPasswordDialog(BuildContext dialogContext) async {
    final TextEditingController resetKeyController = TextEditingController();
    bool incorrect = false;
    final prefs = await SharedPreferences.getInstance();
    final String? storedResetKey = prefs.getString(appDataPrefix + 'app_reset_key');
    await showDialog(
      context: dialogContext,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Entrer clé de réinitialisation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: resetKeyController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Clé de réinitialisation'),
              ),
              if (incorrect) const Text('Clé incorrecte.', style: TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (resetKeyController.text == storedResetKey) {
                  Navigator.pop(ctx);
                  Navigator.pop(dialogContext);
                  this.setState(() {
                    _isAuthenticated = true;
                  });
                } else {
                  setState(() {
                    incorrect = true;
                  });
                }
              },
              child: const Text('Entrer'),
            ),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const MainMenu();
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
        height: 120,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.fitWidth,
              child: Text(
                '${formatBalance(balance, abbreviate)} $symbol',
                style: TextStyle(color: textColor, fontSize: 28, fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onIncomePressed,
              icon: const Icon(Icons.add_circle_outline, size: 28),
              label: const Text('Entrée', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: incomeColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 5,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onExpensePressed,
              icon: const Icon(Icons.remove_circle_outline, size: 28),
              label: const Text('Sortie', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: expenseColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 5,
              ),
            ),
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
          Color txColor = tx.type == 'income' ? incomeColor : expenseColor;
          IconData txIcon = tx.type == 'income' ? Icons.arrow_downward : Icons.arrow_upward;
          return FadeInUp(
            delay: Duration(milliseconds: index * 50),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 3,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: txColor.withOpacity(0.1),
                  child: Icon(txIcon, color: txColor),
                ),
                title: Text(
                  '${tx.amount.toStringAsFixed(2)} $currencySymbol - ${tx.description}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${DateFormat('dd/MM/yyyy HH:mm').format(tx.date)} - ${tx.currency}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.type == 'income' ? 'Ajouter Entrée' : 'Ajouter Sortie', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Montant',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: descController,
            decoration: InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.note),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
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
            decoration: InputDecoration(
              labelText: 'Devise',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.currency_exchange),
            ),
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
              double balance = selectedCurrency == 'USD' ? widget.cashProvider.balanceUSD : widget.cashProvider.balanceCDF;
              if (amount > balance) {
                sufficient = false;
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Erreur'),
                    content: const Text('Impossible, le solde est insuffisant.'),
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
class KioskHomePage extends StatelessWidget {
  final String kioskName;
  const KioskHomePage({super.key, required this.kioskName});
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
      create: (context) => CashProvider(kioskName),
      child: Builder(
        builder: (context) {
          final cashProvider = Provider.of<CashProvider>(context);
          final themeProvider = Provider.of<ThemeProvider>(context);
          final theme = Theme.of(context);
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              title: Text('Gestion - $kioskName',
                  style: const TextStyle(fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 1))])),
              centerTitle: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings, shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 1))]),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SettingsPage(cashProvider: cashProvider)),
                    );
                  },
                ),
              ],
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primary.withOpacity(0.2), theme.scaffoldBackgroundColor],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    FadeInDown(
                      child: Padding(
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
                    ),
                    ActionButtons(
                      onIncomePressed: () => _showAddDialog(context, 'income'),
                      onExpensePressed: () => _showAddDialog(context, 'expense'),
                      incomeColor: theme.colorScheme.secondary,
                      expenseColor: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    FadeIn(
                      child: const Text('Historique des Transactions',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black26, blurRadius: 2)])),
                    ),
                    TransactionList(
                      transactions: cashProvider.transactions,
                      onDelete: (tx) => cashProvider.deleteTransaction(tx.key ?? 0),
                      incomeColor: theme.colorScheme.secondary,
                      expenseColor: theme.colorScheme.error,
                      deleteColor: theme.colorScheme.error,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
Future<Map<String, double>> getAllTotals() async {
  final prefs = await SharedPreferences.getInstance();
  final kioskBox = await Hive.openBox<String>(appDataPrefix + 'kiosks');
  double totalUSD = 0.0;
  double totalCDF = 0.0;
  for (var kiosk in kioskBox.values) {
    totalUSD += prefs.getDouble(appDataPrefix + 'balance_USD_$kiosk') ?? 0.0;
    totalCDF += prefs.getDouble(appDataPrefix + 'balance_CDF_$kiosk') ?? 0.0;
  }
  return {'usd': totalUSD, 'cdf': totalCDF};
}
class SettingsPage extends StatelessWidget {
  final CashProvider cashProvider;
  const SettingsPage({super.key, required this.cashProvider});
  Future<void> _showSetResetKeyDialog(BuildContext context) async {
    final TextEditingController keyController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();
    bool keysMatch = true;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Définir Clé de Réinitialisation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Clé de Réinitialisation'),
              ),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmer Clé'),
              ),
              if (!keysMatch) const Text('Les clés ne correspondent pas.', style: TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (keyController.text == confirmController.text && keyController.text.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(appDataPrefix + 'app_reset_key', keyController.text);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Clé de réinitialisation définie.')),
                  );
                } else {
                  setState(() {
                    keysMatch = false;
                  });
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final TextEditingController resetKeyController = TextEditingController();
    bool keyCorrect = true;
    final prefs = await SharedPreferences.getInstance();
    final String? storedResetKey = prefs.getString(appDataPrefix + 'app_reset_key');
    if (storedResetKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Définissez d\'abord une clé de réinitialisation.')),
      );
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Vérifier Clé de Réinitialisation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: resetKeyController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Clé de Réinitialisation'),
              ),
              if (!keyCorrect) const Text('Clé incorrecte.', style: TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (resetKeyController.text == storedResetKey) {
                  Navigator.pop(ctx, true);
                } else {
                  setState(() {
                    keyCorrect = false;
                  });
                }
              },
              child: const Text('Vérifier'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      final TextEditingController newPasswordController = TextEditingController();
      final TextEditingController confirmController = TextEditingController();
      bool passwordsMatch = true;
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Changer Mot de Passe'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Nouveau Mot de Passe'),
                ),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirmer Nouveau Mot de Passe'),
                ),
                if (!passwordsMatch)
                  const Text('Les mots de passe ne correspondent pas.', style: TextStyle(color: Colors.red)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (newPasswordController.text == confirmController.text && newPasswordController.text.isNotEmpty) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(appDataPrefix + 'app_password', newPasswordController.text);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mot de passe changé.')),
                    );
                  } else {
                    setState(() {
                      passwordsMatch = false;
                    });
                  }
                },
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ),
      );
    }
  }
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
    final theme = Theme.of(context);
    final String category = cashProvider.category;
    final abbreviate = themeProvider.abbreviateBalance;
    final double usd = cashProvider.balanceUSD;
    final double cdf = cashProvider.balanceCDF;
    final double usdThird = usd / 3;
    final double cdfThird = cdf / 3;
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
            leading: const Icon(Icons.lock),
            title: const Text('Changer Mot de Passe'),
            onTap: () => _showChangePasswordDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Définir Clé de Réinitialisation'),
            onTap: () => _showSetResetKeyDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Télécharger l\'historique'),
            onTap: () => _downloadHistory(context),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Totaux $category',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Solde USD: ${formatBalance(usd, abbreviate)} \$',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      '1/3 USD: ${formatBalance(usdThird, abbreviate)} \$',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Solde CDF: ${formatBalance(cdf, abbreviate)} FC',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      '1/3 CDF: ${formatBalance(cdfThird, abbreviate)} FC',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FutureBuilder<Map<String, double>>(
              future: getAllTotals(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Text('Erreur de chargement des totaux');
                }
                final totals = snapshot.data ?? {'usd': 0.0, 'cdf': 0.0};
                final totalUSD = totals['usd']!;
                final totalCDF = totals['cdf']!;
                final totalUsdThird = totalUSD / 3;
                final totalCdfThird = totalCDF / 3;
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Totaux Tous les Mois',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Solde Total USD: ${formatBalance(totalUSD, abbreviate)} \$',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          '1/3 Total USD: ${formatBalance(totalUsdThird, abbreviate)} \$',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Solde Total CDF: ${formatBalance(totalCDF, abbreviate)} FC',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          '1/3 Total CDF: ${formatBalance(totalCdfThird, abbreviate)} FC',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
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
class KiosksListPage extends StatelessWidget {
  const KiosksListPage({super.key});
  Future<void> _showDeleteConfirmation(BuildContext context, String kioskName, int index) async {
    final kioskProvider = Provider.of<KioskProvider>(context, listen: false);
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le mois ?'),
        content: const Text(
          'ATTENTION ! Cette action est irréversible.\n\n'
              'Toutes les transactions de ce mois seront perdues.\n'
              'Tout sera perdu définitivement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await kioskProvider.deleteKiosk(kioskName, index);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mois supprimé.')),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    final kioskProvider = Provider.of<KioskProvider>(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste des Kiosques'),
        centerTitle: true,
      ),
      body: ListView.builder(
        itemCount: kioskProvider.kiosks.length,
        itemBuilder: (context, index) {
          final kioskName = kioskProvider.kiosks[index];
          return FadeInUp(
            delay: Duration(milliseconds: index * 100),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GestureDetector(
                onLongPress: () => _showDeleteConfirmation(context, kioskName, index),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => KioskHomePage(kioskName: kioskName),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                  ),
                  child: Text(kioskName.capitalize(), style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
class MainMenu extends StatelessWidget {
  const MainMenu({super.key});
  void _showAddKioskDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final kioskProvider = Provider.of<KioskProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter une Kiosque'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nom de la Kiosque'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                await kioskProvider.addKiosk(name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion Financière'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [theme.colorScheme.primary.withOpacity(0.1), theme.scaffoldBackgroundColor],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeInDown(
                  child: Text(
                    'Bienvenue dans Gestion Financière',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 1))],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                FadeInUp(
                  child: Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const KiosksListPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.view_list),
                            label: const Text('Voir les Kiosques', style: TextStyle(fontSize: 18)),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 60),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _showAddKioskDialog(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter une Kiosque', style: TextStyle(fontSize: 18)),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 60),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                            ),
                          ),
                        ],
                      ),
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
