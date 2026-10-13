/// 把异步任务排队串行执行的极简互斥器。
///
/// 用途：保护「读共享状态 → 改 → 写回」这类临界区。这类操作如果并发进入，
/// 各自读到的都是同一份旧状态，后写的会把先写的整体覆盖掉。
///
/// 本仓库有两处真实踩过/差点踩到的场景：
/// - `AiCache.setAiCache`：读整个缓存文件 → 加一条 → 写回整个文件。
///   未串行化时实测并发写 5 条只剩 1 条，缓存等于失效。
/// - `service/ai/index.dart` 的 RPM 限流：读时间戳列表 → 判断是否超配额 → 追加。
///   未串行化时并发请求会同时通过配额判断，一轮发出超过配置的请求数。
///
/// 只解决**同进程内、事件循环上**的并发；跨 isolate 或多进程不覆盖
/// （本项目这两处都只在主 isolate 上访问）。
///
/// 实现上不引入 `package:synchronized`：一条 Future 链就够了，
/// 也避免为此增加依赖。
class AsyncMutex {
  Future<void> _tail = Future<void>.value();

  /// 排队执行 [task]，返回它自己的结果。
  ///
  /// 前一个任务抛异常不会卡住后续任务：队列本身吞掉异常，
  /// 真正的错误通过返回的 Future 抛给调用方。
  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_, __) {});
    return result;
  }
}
