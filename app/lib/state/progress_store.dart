import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

/// Local, crash-safe record of listening positions for one user.
///
/// Every position change is written here first (dirty = 1) and pushed to the
/// server later. The server answers with what it stored; a newer server value
/// (from another device) only replaces a local value that is not dirty.
class ProgressStore {
  final Database db;
  ProgressStore._(this.db);

  static Future<ProgressStore> open(String userKey) async {
    final dir = await getDatabasesPath();
    final safe = userKey.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final db = await openDatabase(
      p.join(dir, 'progress_$safe.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE progress(book_id TEXT PRIMARY KEY, position REAL NOT NULL, '
            'finished INTEGER NOT NULL, updated_at INTEGER NOT NULL, device TEXT, dirty INTEGER NOT NULL)');
      },
    );
    return ProgressStore._(db);
  }

  Future<Map<String, Progress>> all() async {
    final rows = await db.query('progress');
    return {
      for (final r in rows)
        r['book_id'] as String: Progress(r['book_id'] as String, (r['position'] as num).toDouble(),
            (r['finished'] as int) == 1, r['updated_at'] as int, r['device'] as String?)
    };
  }

  Future<void> saveLocal(Progress pr) => db.insert(
        'progress',
        {
          'book_id': pr.bookId,
          'position': pr.position,
          'finished': pr.finished ? 1 : 0,
          'updated_at': pr.updatedAt,
          'device': pr.device,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Progress>> dirty() async {
    final rows = await db.query('progress', where: 'dirty = 1');
    return rows
        .map((r) => Progress(r['book_id'] as String, (r['position'] as num).toDouble(), (r['finished'] as int) == 1,
            r['updated_at'] as int, r['device'] as String?))
        .toList();
  }

  /// Applies server state. Returns the book ids whose local value changed.
  Future<Set<String>> applyRemote(List<Progress> remote, {bool fromPush = false}) async {
    final changed = <String>{};
    await db.transaction((txn) async {
      for (final r in remote) {
        final cur = await txn.query('progress', where: 'book_id = ?', whereArgs: [r.bookId]);
        if (cur.isEmpty) {
          await txn.insert('progress', {
            'book_id': r.bookId,
            'position': r.position,
            'finished': r.finished ? 1 : 0,
            'updated_at': r.updatedAt,
            'device': r.device,
            'dirty': 0,
          });
          changed.add(r.bookId);
          continue;
        }
        final localTs = cur.first['updated_at'] as int;
        final isDirty = (cur.first['dirty'] as int) == 1;
        final samePos = ((cur.first['position'] as num).toDouble() - r.position).abs() < 0.01 &&
            ((cur.first['finished'] as int) == 1) == r.finished;
        if (fromPush && isDirty && samePos) {
          // Server stored our value (maybe with a clamped timestamp).
          await txn.update('progress', {'dirty': 0}, where: 'book_id = ?', whereArgs: [r.bookId]);
          continue;
        }
        if (r.updatedAt >= localTs) {
          // The server holds this exact value or a newer one from another device.
          if (isDirty && r.updatedAt == localTs && fromPush) {
            await txn.update('progress', {'dirty': 0}, where: 'book_id = ?', whereArgs: [r.bookId]);
          } else if (r.updatedAt > localTs) {
            await txn.update(
                'progress',
                {
                  'position': r.position,
                  'finished': r.finished ? 1 : 0,
                  'updated_at': r.updatedAt,
                  'device': r.device,
                  'dirty': 0,
                },
                where: 'book_id = ?',
                whereArgs: [r.bookId]);
            changed.add(r.bookId);
          } else if (!isDirty) {
            // same timestamp, nothing to do
          }
        }
        // r older than local: our value wins and stays dirty until pushed.
      }
    });
    return changed;
  }

  Future<void> remove(String bookId) => db.delete('progress', where: 'book_id = ?', whereArgs: [bookId]);

  Future<void> close() => db.close();
}
