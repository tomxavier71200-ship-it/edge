import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

const _format = 1;
const _rowId = 'koop_delta_rowid';

String _id(String name) => '"${name.replaceAll('"', '""')}"';

class _Table {
  final String name;
  final List<String> columns;
  final List<String> keys;
  final bool usesRowId;

  const _Table(this.name, this.columns, this.keys, this.usesRowId);

  String get table => _id(name);
  String get upserts => _id('put_$name');
  String get deletes => _id('del_$name');
  String get columnList => columns.map(_id).join(', ');
  String get insertColumns => usesRowId ? 'rowid, $columnList' : columnList;
  String get keyList => keys.map(_id).join(', ');
  String get destinationKeys => usesRowId ? 'rowid' : keyList;

  String matchingKeys(String a, String b) => usesRowId
      ? '$a.rowid = $b.rowid'
      : keys.map((key) => '$a.${_id(key)} = $b.${_id(key)}').join(' AND ');
}

Future<List<Map<String, Object?>>> _schema(
  DatabaseExecutor db,
  String schema,
) => db.rawQuery('''
      SELECT type, name, sql FROM $schema.sqlite_master
      WHERE name NOT GLOB 'sqlite_*' AND name != 'android_metadata'
      ORDER BY type, name
    ''');

Future<int> _version(DatabaseExecutor db, String schema) async =>
    (await db.rawQuery('PRAGMA $schema.user_version')).single['user_version']
        as int;

Future<bool> _hasSequence(DatabaseExecutor db, String schema) async =>
    (await db.rawQuery(
      "SELECT 1 FROM $schema.sqlite_master "
      "WHERE type = 'table' AND name = 'sqlite_sequence'",
    )).isNotEmpty;

Future<_Table> _table(DatabaseExecutor db, String schema, String name) async {
  if (name == 'sqlite_sequence') {
    return const _Table('sqlite_sequence', ['name', 'seq'], ['name'], false);
  }
  final info = await db.rawQuery('PRAGMA $schema.table_info(${_id(name)})');
  final columns = [for (final row in info) row['name'] as String];
  final keyed = info.where((row) => (row['pk'] as int) > 0).toList()
    ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
  final keys = [for (final row in keyed) row['name'] as String];
  // SQLite permits NULL in some declared primary keys. Use rowid for those
  // tables so even a legacy row with a NULL key survives a round trip.
  final nullKey =
      keys.isNotEmpty &&
      (await db.rawQuery(
        'SELECT 1 FROM $schema.${_id(name)} WHERE '
        "${keys.map((key) => '${_id(key)} IS NULL').join(' OR ')} LIMIT 1",
      )).isNotEmpty;
  final rowId = keys.isEmpty || nullKey;
  if (rowId && columns.contains(_rowId)) {
    throw const FormatException('Reserved Cloud delta column.');
  }
  return _Table(name, columns, rowId ? const [_rowId] : keys, rowId);
}

Future<String> _digest(File file) => Isolate.run(
  () async => (await sha256.bind(file.openRead()).first).toString(),
);

/// Build a SQLite change file for two consistent, standalone backups. Both
/// inputs stay read-only. False means a new full checkpoint is required.
Future<bool> createCloudDelta(File base, File current, File delta) async {
  if (!await base.exists() || !await current.exists() || await delta.exists()) {
    throw ArgumentError(
      'Cloud delta requires an existing source and new output.',
    );
  }
  final baseDigest = await _digest(base);
  final db = await openDatabase(delta.path, singleInstance: false);
  try {
    await db.execute('ATTACH DATABASE ? AS base', [base.path]);
    await db.execute('ATTACH DATABASE ? AS current', [current.path]);
    final before = await _schema(db, 'base');
    final after = await _schema(db, 'current');
    final version = await _version(db, 'current');
    if (jsonEncode(before) != jsonEncode(after) ||
        version != await _version(db, 'base')) {
      return false;
    }
    final names = [
      for (final row in after)
        if (row['type'] == 'table') row['name'] as String,
      if (await _hasSequence(db, 'current')) 'sqlite_sequence',
    ];
    await db.transaction((txn) async {
      await txn.execute(
        'CREATE TABLE delta_meta (format INTEGER, base_sha TEXT)',
      );
      await txn.insert('delta_meta', {
        'format': _format,
        'base_sha': baseDigest,
      });
      await txn.execute(
        'CREATE TABLE delta_tables (name TEXT PRIMARY KEY, row_id INTEGER)',
      );
      for (final name in names) {
        final oldTable = await _table(txn, 'base', name);
        final table = await _table(txn, 'current', name);
        if (oldTable.usesRowId != table.usesRowId) {
          throw const FormatException('Cloud delta key changed.');
        }
        final fields = [
          if (table.usesRowId) 'c.rowid AS ${_id(_rowId)}',
          ...table.columns.map((col) => 'c.${_id(col)}'),
        ].join(', ');
        final changed = table.columns
            .map((col) {
              final id = _id(col);
              return '(c.$id COLLATE BINARY IS NOT b.$id '
                  'OR typeof(c.$id) != typeof(b.$id))';
            })
            .join(' OR ');
        final sentinel = table.usesRowId ? 'rowid' : _id(table.keys.first);
        final removed = table.usesRowId
            ? 'b.rowid AS ${_id(_rowId)}'
            : table.keys.map((col) => 'b.${_id(col)}').join(', ');
        await txn.execute('''
          CREATE TABLE ${table.upserts} AS
          SELECT $fields FROM current.${table.table} c
          LEFT JOIN base.${table.table} b ON ${table.matchingKeys('c', 'b')}
          WHERE b.$sentinel IS NULL OR $changed
        ''');
        await txn.execute('''
          CREATE TABLE ${table.deletes} AS
          SELECT $removed FROM base.${table.table} b
          LEFT JOIN current.${table.table} c ON ${table.matchingKeys('b', 'c')}
          WHERE c.$sentinel IS NULL
        ''');
        await txn.insert('delta_tables', {
          'name': name,
          'row_id': table.usesRowId ? 1 : 0,
        });
      }
    });
    return true;
  } finally {
    await db.close();
  }
}

/// Reconstruct a standalone backup from its exact checkpoint and change file.
/// Changes are applied to a disposable copy and published only on success.
Future<void> applyCloudDelta(File base, File delta, File output) async {
  final digest = await _digest(base);
  if (!await delta.exists() || await output.exists()) {
    throw ArgumentError(
      'Cloud delta requires an existing source and new output.',
    );
  }
  await base.copy(output.path);
  try {
    final db = await openDatabase(output.path, singleInstance: false);
    try {
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('ATTACH DATABASE ? AS delta', [delta.path]);
      final meta = (await db.rawQuery('SELECT * FROM delta.delta_meta')).single;
      if (meta['format'] != _format || meta['base_sha'] != digest) {
        throw const FormatException(
          'Cloud delta does not match its checkpoint.',
        );
      }
      final schema = await _schema(db, 'main');
      final expected = {
        for (final row in schema)
          if (row['type'] == 'table') row['name'] as String,
        if (await _hasSequence(db, 'main')) 'sqlite_sequence',
      };
      final triggers = schema.where((row) => row['type'] == 'trigger');
      final tables = <_Table>[];
      for (final row in await db.rawQuery(
        "SELECT * FROM delta.delta_tables ORDER BY name = 'sqlite_sequence'",
      )) {
        final name = row['name'];
        if (name is! String || !expected.remove(name)) {
          throw const FormatException('Unexpected Cloud delta table.');
        }
        final table = await _table(db, 'main', name);
        if (row['row_id'] != (table.usesRowId ? 1 : 0)) {
          throw const FormatException('Cloud delta key mismatch.');
        }
        tables.add(table);
      }
      if (expected.isNotEmpty) {
        throw const FormatException('Incomplete Cloud delta.');
      }
      await db.transaction((txn) async {
        for (final trigger in triggers) {
          await txn.execute('DROP TRIGGER ${_id(trigger['name'] as String)}');
        }
        Future<void> removeChanged(_Table table) async {
          final keys = table.destinationKeys;
          for (final source in [table.deletes, table.upserts]) {
            await txn.execute(
              'DELETE FROM ${table.table} WHERE ($keys) IN '
              '(SELECT ${table.keyList} FROM delta.$source)',
            );
          }
        }

        // Clear updated keys too, before any INSERT. A changed row may take a
        // secondary UNIQUE value another changed row was using.
        for (final table in tables) {
          if (table.name != 'sqlite_sequence') await removeChanged(table);
        }
        for (final table in tables) {
          // AUTOINCREMENT inserts can change the sequence themselves.
          if (table.name == 'sqlite_sequence') await removeChanged(table);
          final columns = table.insertColumns;
          final values = table.usesRowId
              ? '${_id(_rowId)}, ${table.columnList}'
              : table.columnList;
          await txn.execute(
            'INSERT INTO ${table.table} ($columns) '
            'SELECT $values FROM delta.${table.upserts}',
          );
        }
        for (final trigger in triggers) {
          await txn.execute(trigger['sql'] as String);
        }
      });
    } finally {
      await db.close();
    }
  } catch (_) {
    await output.delete();
    rethrow;
  }
}
