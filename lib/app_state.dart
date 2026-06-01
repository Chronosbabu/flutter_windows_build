import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  bool isDarkMode = false;
  String schoolName = "MAPENDO TCC";
  String? schoolCode;        // Sera l'ID unique de l'école (fourni par l'admin)
  String? backupPassword;    // Mot de passe de sauvegarde

  AppState() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    isDarkMode = prefs.getBool('isDarkMode') ?? false;
    schoolName = prefs.getString('schoolName') ?? "MAPENDO TCC";
    schoolCode = prefs.getString('schoolCode');
    backupPassword = prefs.getString('backupPassword');

    notifyListeners();
  }

  Future<void> toggleTheme() async {
    isDarkMode = !isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
    notifyListeners();
  }

  Future<void> updateSchoolName(String newName) async {
    schoolName = newName.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schoolName', schoolName);
    notifyListeners();
  }

  Future<void> setSchoolCode(String code) async {
    schoolCode = code.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schoolCode', schoolCode!);
    notifyListeners();
  }

  Future<void> setBackupPassword(String password) async {
    backupPassword = password.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backupPassword', backupPassword!);
    notifyListeners();
  }
}
