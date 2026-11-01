import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cut_optimiser_models.dart';

abstract class ProjectRepository {
  Future<List<Project>> loadProjects();
  Future<void> saveProjects(List<Project> projects);
  Future<List<StockConfig>> loadStocks();
  Future<void> saveStocks(List<StockConfig> stocks);
}

class SharedPreferencesProjectRepository implements ProjectRepository {
  SharedPreferencesProjectRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _storageKey = 'cut_optimiser_projects_v1';
  static const _stocksStorageKey = 'cut_optimiser_stocks_v1';

  @override
  Future<List<Project>> loadProjects() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    final projects = (jsonDecode(raw) as List)
        .map((entry) =>
            Project.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    final stocks = await loadStocks();
    for (final project in projects) {
      for (final stock in project.stocks) {
        if (!stocks.any((item) => item.id == stock.id)) stocks.add(stock);
      }
      project.bindStocks(stocks);
    }
    if (stocks.isNotEmpty) await saveStocks(stocks);
    return projects;
  }

  @override
  Future<void> saveProjects(List<Project> projects) async {
    final encoded = jsonEncode(projects
        .map((project) => project.toJson(includeStockDefinitions: false))
        .toList());

    await _prefs.setString(_storageKey, encoded);
    final stocks = await loadStocks();
    for (final project in projects) {
      for (final stock in project.stocks) {
        final index = stocks.indexWhere((item) => item.id == stock.id);
        if (index < 0) {
          stocks.add(stock);
        } else {
          stocks[index] = stock;
        }
      }
    }
    await saveStocks(stocks);
  }

  @override
  Future<List<StockConfig>> loadStocks() async {
    final raw = _prefs.getString(_stocksStorageKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((entry) =>
            StockConfig.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
  }

  @override
  Future<void> saveStocks(List<StockConfig> stocks) async {
    await _prefs.setString(
      _stocksStorageKey,
      jsonEncode(stocks.map((stock) => stock.toJson()).toList()),
    );
  }
}
