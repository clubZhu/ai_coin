import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/position_record.dart';

abstract interface class PositionRepository {
  Future<List<PositionRecord>> load();

  Future<void> save(List<PositionRecord> records);
}

class LocalPositionRepository implements PositionRepository {
  static const _storageKey = 'cryptopilot.position_records.v1';

  @override
  Future<List<PositionRecord>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encodedRecords = preferences.getStringList(_storageKey) ?? const [];
    final records = <PositionRecord>[];
    for (final encodedRecord in encodedRecords) {
      try {
        final json = jsonDecode(encodedRecord) as Map<String, dynamic>;
        records.add(PositionRecord.fromJson(json));
      } on FormatException {
        // Ignore a malformed record so one bad entry never blocks the list.
      } on TypeError {
        // Ignore data written by an incompatible older schema.
      }
    }
    return records;
  }

  @override
  Future<void> save(List<PositionRecord> records) async {
    final preferences = await SharedPreferences.getInstance();
    final encodedRecords = records
        .map((record) => jsonEncode(record.toJson()))
        .toList(growable: false);
    await preferences.setStringList(_storageKey, encodedRecords);
  }
}
