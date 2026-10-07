import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/models/character_extras.dart';

/// 自设卡 / 穿越场景 / 原著知识 / 剧情回顾 的持久化访问层。
class CharacterExtrasDao extends BaseDao {
  CharacterExtrasDao();

  static const String tableSelfCard = 'tb_self_cards';
  static const String tableCrossover = 'tb_crossover_scenes';
  static const String tableKnowledge = 'tb_knowledge_items';
  static const String tableRecap = 'tb_story_recaps';

  // ---- 自设卡 / 开局模板 ----

  Future<List<SelfCard>> listSelfCards(
    int bookId, {
    SelfCardKind? kind,
    String? keyword,
  }) {
    final kw = keyword?.trim() ?? '';
    final clauses = <String>['book_id = ?'];
    final args = <Object?>[bookId];
    if (kind != null) {
      clauses.add('kind = ?');
      args.add(kind.code);
    }
    if (kw.isNotEmpty) {
      clauses.add('(title LIKE ? OR content LIKE ?)');
      args.addAll(['%$kw%', '%$kw%']);
    }
    return queryList(
      tableSelfCard,
      mapper: SelfCard.fromMap,
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
    );
  }

  Future<int> saveSelfCard(SelfCard card) async {
    final now = DateTime.now();
    if (card.id != null) {
      await update(
        tableSelfCard,
        card.copyWith(updatedAt: now).toMap(),
        where: 'id = ?',
        whereArgs: [card.id],
      );
      return card.id!;
    }
    return insert(tableSelfCard, card.copyWith(updatedAt: now).toMap());
  }

  Future<void> deleteSelfCard(int id) =>
      delete(tableSelfCard, where: 'id = ?', whereArgs: [id]);

  // ---- 穿越场景 ----

  Future<List<CrossoverScene>> listCrossoverScenes() => queryList(
        tableCrossover,
        mapper: CrossoverScene.fromMap,
        orderBy: 'updated_at DESC',
      );

  Future<int> saveCrossoverScene(CrossoverScene scene) async {
    final now = DateTime.now();
    if (scene.id != null) {
      await update(
        tableCrossover,
        scene.copyWith(updatedAt: now).toMap(),
        where: 'id = ?',
        whereArgs: [scene.id],
      );
      return scene.id!;
    }
    return insert(tableCrossover, scene.copyWith(updatedAt: now).toMap());
  }

  Future<void> deleteCrossoverScene(int id) =>
      delete(tableCrossover, where: 'id = ?', whereArgs: [id]);

  // ---- 原著知识 ----

  Future<List<KnowledgeItem>> listKnowledge(
    int bookId, {
    String? keyword,
  }) {
    final kw = keyword?.trim() ?? '';
    return queryList(
      tableKnowledge,
      mapper: KnowledgeItem.fromMap,
      where: kw.isEmpty
          ? 'book_id = ?'
          : 'book_id = ? AND (topic LIKE ? OR summary LIKE ?)',
      whereArgs: kw.isEmpty ? [bookId] : [bookId, '%$kw%', '%$kw%'],
      orderBy: 'id ASC',
    );
  }

  Future<void> replaceKnowledge(int bookId, List<KnowledgeItem> items) async {
    await transaction((txn) async {
      await txn.delete(tableKnowledge,
          where: 'book_id = ?', whereArgs: [bookId]);
      for (final i in items) {
        await txn.insert(tableKnowledge, i.toMap());
      }
    });
  }

  // ---- 剧情回顾 ----

  Future<StoryRecap?> getRecap(int bookId, int chapterIndex) async {
    final list = await queryList(
      tableRecap,
      mapper: StoryRecap.fromMap,
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, chapterIndex],
      limit: 1,
    );
    return list.isEmpty ? null : list.first;
  }

  Future<List<StoryRecap>> listRecaps(int bookId) => queryList(
        tableRecap,
        mapper: StoryRecap.fromMap,
        where: 'book_id = ?',
        whereArgs: [bookId],
        orderBy: 'chapter_index DESC',
      );

  Future<int> saveRecap(StoryRecap recap) => insert(tableRecap, recap.toMap());

  Future<void> deleteRecap(int id) =>
      delete(tableRecap, where: 'id = ?', whereArgs: [id]);
}

/// 全局单例。
final characterExtrasDao = CharacterExtrasDao();
