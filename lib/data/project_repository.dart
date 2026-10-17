import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/project_model.dart';

abstract class ProjectRepository {
  Future<List<Project>> loadProjects();
  Future<void> saveProjects(List<Project> projects);
}

class SharedPreferencesProjectRepository implements ProjectRepository {
  SharedPreferencesProjectRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _storageKey = 'cut_optimiser_projects_v1';

  @override
  Future<List<Project>> loadProjects() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((entry) => Project(
                name: entry['name'] as String,
                mode: CutMode.values.firstWhere(
                  (mode) => mode.name == entry['mode'],
                  orElse: () => CutMode.linear,
                ),
                material: entry['material']?.toString() ?? 'Mild steel',
                variant: entry['variant']?.toString() ?? '',
                unit: entry['unit']?.toString() ?? 'mm',
                kerf: (entry['kerf'] as num? ?? 3).toDouble(),
                trim: (entry['trim'] as num? ?? 0).toDouble(),
                parts: const [],
                stocks: const [],
                updated: entry['updated']?.toString() ?? '',
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveProjects(List<Project> projects) async {
    final encoded = jsonEncode(projects
        .map((project) => {
              'name': project.name,
              'mode': project.mode.name,
              'material': project.material,
              'variant': project.variant,
              'unit': project.unit,
              'kerf': project.kerf,
              'trim': project.trim,
              'updated': project.updated,
              'parts': project.parts.map((part) => part.toJson()).toList(),
              'stocks': project.stocks.map((stock) => stock.toJson()).toList(),
            })
        .toList());

    await _prefs.setString(_storageKey, encoded);
  }
}
