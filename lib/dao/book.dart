import 'package:sqflite/sqflite.dart';
import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/book.dart';
import 'package:songjiang_reader/utils/log/common.dart';

class BookDao extends BaseDao {
  BookDao();

  static const String table = 'tb_books';

  /// 有 id → UPDATE，无 id → INSERT。
  ///
  /// **命中 0 行时抛 [StateError]，不再返回假成功。**
  /// 依据：sqlite 的 UPDATE 命中 0 行不报错，原实现 `await updateBook(book); return book.id;`
  /// 会让调用方以为写成功了（阶段三 harness I6 复现：书明明已从库里消失，
  /// 表里 0 行，调用方拿到的仍是 book.id 且无异常）。
  ///
  /// 影响面（已逐个核对，全部是"行存在"的场景，行为不变）：
  ///   · `lib/service/book.dart:696` `book.id = await bookDao.insertBook(book)`
  ///     —— 唯一走 save() 的调用点；命中 0 行时现在会**提前抛错**，
  ///     而 saveBook 原本靠 `:701-717` 的"落库后回查"才拦下来，属于同一语义的更早失败。
  ///   · `updateBook` 的 13 处直接调用点（见 patch 说明）**不受影响**：
  ///     它们不经过 save()，且 updateBook 现在只把受影响行数**返回**出去，不抛。
  Future<int> save(Book book) async {
    if (book.id != -1) {
      final affected = await updateBook(book);
      if (affected == 0) {
        throw StateError(
            'BookDao.save: 更新 book.id=${book.id} 影响 0 行（该行已不存在）。'
            '拒绝返回假成功——请重新插入或刷新书架后重试。');
      }
      return book.id;
    }
    return insert(table, book.toMap());
  }

  Future<int> insertBook(Book book) => save(book);

  /// 返回受影响行数（原先丢弃）。**保持不抛**，以免改变 13 处既有调用点的语义；
  /// 需要 fail-fast 的地方请用 [save]，或自行判断返回值。
  Future<int> updateBook(Book book) async {
    book.updateTime = DateTime.now();
    return update(
      table,
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  Future<List<Book>> selectBooks({bool includeDeleted = true}) {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectNotDeleteBooks() {
    return selectBooks(includeDeleted: false);
  }

  Future<Book> selectBookById(int id) async {
    final book = await querySingle(
      table,
      mapper: Book.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (book == null) {
      throw StateError('Book with id $id not found');
    }
    return book;
  }

  Future<List<String>> getCurrentBooks() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.filePath).toList(growable: false);
  }

  Future<List<String>> getCurrentCover() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.coverPath).toList(growable: false);
  }

  Future<List<Book>> selectAllBooks() {
    return selectBooks();
  }

  /// 按 md5 查书。**空串与 NULL 一样，语义是"没有 md5"**（patch 0011）。
  ///
  /// 统一前的行为：`getBookByMd5('')` 会命中"file_md5 = ''"的行，于是同一行在两处
  /// 口径相反 —— `getBooksWithoutMd5()` 的 `IS NULL OR = ''` 把它当"缺失"，
  /// 这里却把它当"就是这本书"。统一后这里直接返回 null（不参与查重）。
  ///
  /// 调用点影响：`MD5Service.checkDuplicateByMd5`（公开方法）与
  /// `service/book.dart` 的落库去重 —— 两处传进来的都是
  /// `MD5Service.dedupKeyFor()` 的结果，**永不为空串**，因此实际行为不变；
  /// 变的是"外部/历史数据直接传空串"时的结果（从"可能命中一行"改为"必然 null"）。
  Future<Book?> getBookByMd5(String md5) async {
    final key = md5.trim();
    if (key.isEmpty) return null;
    return querySingle(
      table,
      mapper: Book.fromDb,
      where: 'file_md5 = ?',
      whereArgs: [key],
    );
  }

  Future<List<Book>> searchBooks(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    return queryList(
      table,
      mapper: Book.fromDb,
      where: 'is_deleted = 0 AND (title LIKE ? OR author LIKE ?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectBooksByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    return rawQueryList(
      'SELECT * FROM $table WHERE is_deleted = 0 AND id IN ($placeholders)',
      arguments: ids,
      mapper: Book.fromDb,
    );
  }

  /// 回填/重算 md5。返回**受影响行数**。
  ///
  /// 加了 `idx_books_file_md5_unique`（patch 0010）之后，写入一个"已属于另一本书"的
  /// md5 会撞唯一约束。这里用 `ConflictAlgorithm.ignore` 把它降级成"不写入、不抛"，
  /// 由调用方看返回值决定怎么记账 —— 否则 `batchCalculateMd5` 的整批回填会中途抛异常。
  /// （`ignore` 只跳过该行，`update_time` 也不会被改，符合"不丢数据"的要求。）
  Future<int> updateBookMd5(int bookId, String md5) {
    final key = md5.trim();
    if (key.isEmpty) {
      // 与 getBookByMd5 / getBooksWithoutMd5 统一：空串 = 缺失，不写进库里。
      SjLog.warning('BookDao.updateBookMd5: 拒绝写入空 md5（按「缺失」处理）bookId=$bookId');
      return Future.value(0);
    }
    return update(
      table,
      {
        'file_md5': key,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 没有 md5 的书。**这是 `''` 语义的权威口径**（patch 0011）：
  /// `IS NULL OR = ''` 都算"缺失"，`getBookByMd5('')` 也按缺失处理（返回 null）。
  /// 注：patch 0010 之后库里已不再有 `file_md5 = ''` 的行（自愈时统一置 NULL），
  /// 这里的 `= ''` 保留是为了兼容"迁移尚未跑过"的中间状态。
  Future<List<Book>> getBooksWithoutMd5() {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: "is_deleted = 0 AND (file_md5 IS NULL OR file_md5 = '')",
      orderBy: 'update_time DESC',
    );
  }
}

final bookDao = BookDao();
