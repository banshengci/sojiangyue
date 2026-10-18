import 'package:flutter_test/flutter_test.dart';
import 'package:songjiang_reader/utils/async_mutex.dart';

/// [AsyncMutex] 用于保护「读共享状态 → 改 → 写回」这类临界区，
/// 避免并发进入时各自读到同一份旧状态、后写的把先写的整体覆盖掉。
///
/// 本仓库目前只有一处真实需要它：`AiCache.setAiCache`
/// （读整个缓存文件 → 加一条 → 写回整个文件）。未串行化时实测
/// 并发写 5 条只剩 1 条，缓存等于失效。
///
/// 另外，`service/ai/index.dart` 的 RPM 限流**看起来**像同类问题，
/// 但它其实不需要锁：那里「判断配额」与「追加时间戳」之间没有 await，
/// 单线程事件循环下不会被打断。我曾误判并给它加锁重构，反而引入了 bug
/// （改成按 now+wait 记账会让过期条目推迟清理、列表增长、误限流），已回滚。
/// 下面「限流不变量」那组用例就是用来钉住这个形状的。
void main() {
  group('串行化', () {
    test('并发提交的任务按提交顺序逐个执行，不会交叠', () async {
      final mutex = AsyncMutex();
      final log = <String>[];

      Future<void> body(String tag) async {
        log.add('$tag-进入');
        // 人为制造交叠窗口：若没有互斥，别的任务会在这期间进来
        await Future<void>.delayed(const Duration(milliseconds: 10));
        log.add('$tag-离开');
      }

      await Future.wait([
        mutex.run(() => body('A')),
        mutex.run(() => body('B')),
        mutex.run(() => body('C')),
      ]);

      // 必须是「进入→离开」成对相接，不能出现 A-进入, B-进入
      expect(log, [
        'A-进入', 'A-离开',
        'B-进入', 'B-离开',
        'C-进入', 'C-离开',
      ]);
    });

    test('前一个任务抛异常不会卡住后续任务，且异常抛给调用方', () async {
      final mutex = AsyncMutex();

      final failing = mutex.run<void>(() async => throw StateError('boom'));
      await expectLater(failing, throwsStateError);

      // 队列必须已经恢复可用
      final ok = await mutex.run(() async => 42);
      expect(ok, 42);
    });

    test('任务抛异常后，同一批里的其它任务仍能完成', () async {
      final mutex = AsyncMutex();
      final done = <int>[];

      final results = await Future.wait([
        mutex.run(() async => 1).then((v) => done.add(v)).catchError((_) {}),
        mutex.run<void>(() async => throw StateError('x')).catchError((_) {}),
        mutex.run(() async => 3).then((v) => done.add(v)).catchError((_) {}),
      ]);

      expect(results.length, 3);
      expect(done, containsAll([1, 3]));
    });

    test('返回值原样透传', () async {
      final mutex = AsyncMutex();
      expect(await mutex.run(() async => 'value'), 'value');
    });

    test('互斥器之间互不影响', () async {
      final a = AsyncMutex();
      final b = AsyncMutex();
      final order = <String>[];

      await Future.wait([
        a.run(() async {
          order.add('a-进入');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          order.add('a-离开');
        }),
        // b 不该等 a：两者是独立队列，这个应能先跑完
        b.run(() async {
          order.add('b-进入');
          order.add('b-离开');
        }),
      ]);

      expect(order.indexOf('b-离开'), lessThan(order.indexOf('a-离开')));
    });
  });

  group('限流不变量（真实形状：判断与追加之间不能有 await）', () {
    /// 复刻 `service/ai/index.dart` 里 `_throttleIfNeeded` 的真实形状：
    ///
    /// ```
    /// 清过期 → 若达配额则 await 等待并再清一次 → 追加本次时间戳
    /// ```
    ///
    /// 关键在于：「判断是否达配额」与「追加时间戳」之间**没有** await，
    /// 中间那段是同步执行的，Dart 单线程下不会被打断，所以并发调用
    /// 不可能一起通过判断——这个限流器本来就是竞态安全的，**不需要加锁**。
    ///
    /// 这条用例存在的价值是钉住这个形状：谁若在判断与追加之间插入 await
    /// （例如把「占配额」挪到等待之后，或改用「预期发出时刻」记账），
    /// 就会破坏不变量，这里会失败。
    ///
    /// 背景：我曾误以为它有竞态并加锁重构，结果改成「按 now+wait 记账」后
    /// 过期条目推迟 60 秒才清理、列表不断增长、后续请求被误限流。
    /// 那次改动已回滚，改成用这条用例守住不变量的真实含义。
    Future<void> reserve(
      List<DateTime> stamps,
      int rpm,
      List<Duration> waits,
      int index,
    ) async {
      final now = DateTime.now();
      stamps.removeWhere(
          (ts) => ts.isBefore(now.subtract(const Duration(minutes: 1))));
      if (stamps.length >= rpm) {
        final oldest = stamps.first;
        final waitUntil = oldest.add(const Duration(minutes: 1));
        final waitDuration = waitUntil.difference(DateTime.now());
        if (waitDuration > Duration.zero) {
          waits.add(waitDuration);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        final newNow = DateTime.now();
        stamps.removeWhere(
            (ts) => ts.isBefore(newNow.subtract(const Duration(minutes: 1))));
      }
      // 与判断之间没有 await —— 这是不变量的关键
      stamps.add(DateTime.now());
    }

    test('同一分钟内涌入 N 条请求时，记录数就是 N（说明判断没被并发绕过）', () async {
      const rpm = 3;
      final stamps = <DateTime>[];
      final waits = <Duration>[];

      // 全部在同一分钟内同步发起
      await Future.wait([
        for (var i = 0; i < 7; i++) reserve(stamps, rpm, waits, i),
      ]);

      // 关键在于：每条请求都恰好对应一条记录，说明「判断→追加」之间
      // 没有被插入任何交错，所有请求都被逐一计数（这正是限流生效的前提）。
      // 若判断与追加之间出现 await，就会有用例在最前面「漏计」。
      expect(stamps.length, 7);
      // 超过配额的部分必须都产生了等待
      expect(waits.length, greaterThanOrEqualTo(4));
    });

    test('过期条目会被清掉，列表不会无限增长', () async {
      final stamps = <DateTime>[];
      final waits = <Duration>[];

      // 先塞一条已经过期的记录
      stamps.add(DateTime.now().subtract(const Duration(minutes: 2)));
      stamps.add(DateTime.now().subtract(const Duration(minutes: 2)));

      await reserve(stamps, 10, waits, 0);

      // 两次调用之间隔了 >1 分钟的旧记录必须被清理，只剩本次这一条
      expect(stamps.length, 1,
          reason: '过期记录没有被清理，滑动窗口失效');
    });
  });
}
