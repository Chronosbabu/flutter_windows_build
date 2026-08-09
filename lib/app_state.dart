import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  bool isDarkMode = false;
  String schoolName = "MAPENDO TCC";
  String? schoolCode;
  String? backupPassword;

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

  // ⚡ CORRIGÉ : le code est normalisé (trim + majuscules + suppression des
  // espaces internes) pour qu'il soit STRICTEMENT identique quel que soit
  // le PC/Mac sur lequel il est saisi. C'était la source la plus probable
  // du "ID invalide" : un code légèrement différent entre le Mac (utilisé
  // pour le premier backup) et le PC (retapé manuellement, avec une
  // majuscule/espace en moins ou en plus) pointe vers un fichier
  // totalement différent côté serveur.
  Future<void> setSchoolCode(String code) async {
    final normalized = code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    schoolCode = normalized;
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