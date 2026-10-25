import 'package:sqflite/sqflite.dart';

import 'package:songjiang_reader/dao/base_dao.dart';
import 'package:songjiang_reader/dao/local_cache_database.dart';

/// 本地缓存库（`local_cache.db`）上的 DAO 基类。
///
/// [BaseDao] 的读写方法内部都通过可覆盖的 `this.database` 取库，这里把它重定向到
/// [LocalCacheDb]，于是所有继承本类的 DAO（深读产物 / 阅读会话）自动落在本地库，
/// 而**既有继承 [BaseDao] 的 DAO 行为完全不变**（仍指向主库 `app_database.db`）。
///
/// 为什么要有这条分界线：主库会被 WebDAV **整库文件快照替换**同步，
/// 本地库里放的是「本设备数据 / 端内缓存」，产品决策 #3 要求它永不参与同步。
abstract class LocalCacheDao extends BaseDao {
  @override
  Future<Database> get database => LocalCacheDb().database;
}
