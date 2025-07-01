import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> _getDatabase() async {
    if (_db != null) return _db!;

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    Directory documentsDirectory;

    if (Platform.isAndroid || Platform.isIOS) {
      documentsDirectory = await getApplicationDocumentsDirectory();
    } else {
      documentsDirectory = Directory.current;
    }

    final path = join(documentsDirectory.path, 'products.db');

    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              rate TEXT,
              type TEXT,
              image TEXT,
              quantity TEXT,
              unit TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT UNIQUE
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS units (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT UNIQUE
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 3) {
            await db.execute("ALTER TABLE products ADD COLUMN unit TEXT");
            await db.execute('''
              CREATE TABLE IF NOT EXISTS units (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE
              )
            ''');
          }
        },
      ),
    );

    return _db!;
  }

  static Future<void> insertProduct(
      String name, String rate, String type, String imagePath, String quantity, String unit) async {
    final db = await _getDatabase();
    await db.insert(
      'products',
      {
        'name': name,
        'rate': rate,
        'type': type,
        'image': imagePath,
        'quantity': quantity,
        'unit': unit,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await _getDatabase();
    return db.query('products');
  }

  static Future<void> deleteProduct(int id) async {
    final db = await _getDatabase();
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> updateProduct(
      int id, String name, String rate, String type, String image, String quantity, String unit) async {
    final db = await _getDatabase();
    await db.update(
      'products',
      {
        'name': name,
        'rate': rate,
        'type': type,
        'image': image,
        'quantity': quantity,
        'unit': unit,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> reduceProductQuantity(int id, int quantityToReduce) async {
    final db = await _getDatabase();
    final result = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if (result.isNotEmpty) {
      int currentQuantity = int.tryParse(result.first['quantity'].toString()) ?? 0;
      int newQuantity = currentQuantity - quantityToReduce;
      if (newQuantity < 0) newQuantity = 0;
      await db.update(
        'products',
        {'quantity': newQuantity.toString()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  static Future<void> insertCategory(String category) async {
    final db = await _getDatabase();
    await db.insert(
      'categories',
      {'name': category},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<List<String>> getAllCategories() async {
    final db = await _getDatabase();
    final result = await db.query('categories');
    return result.map((e) => e['name'] as String).toList();
  }

  static Future<void> insertUnit(String unit) async {
    final db = await _getDatabase();
    await db.insert(
      'units',
      {'name': unit},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<List<String>> getAllUnits() async {
    final db = await _getDatabase();
    final result = await db.query('units');
    return result.map((e) => e['name'] as String).toList();
  }
}
