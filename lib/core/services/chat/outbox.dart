/// 发件箱：发送失败的消息持久化到 SQLite，按指数退避自动重试。
///
/// 为什么需要它：以前发送失败只在聊天里留一条 `is_success=0` 的消息，用户必须
/// 长按手动重发；关掉会话/重启后那条记录还在，但没有任何自动补偿。断网、切网、
/// 服务端瞬时 `code=9/23` 都走同一条失败路径。
///
/// 职责边界：本类只负责队列与调度，真正的发送由构造注入的 [OutboxSender]
/// 完成（由 state 层接上 ChatService），因此可以脱离网络单测。
library;

import 'dart:async';
import 'dart:math';

import '../../models/messages.dart';
import '../../models/session_key.dart' show sessionKeyOf;
import '../../storage/app_database.dart';
import '../../utils/log.dart';

/// 队列里的一条待发送消息。
class OutboxMessage {
  const OutboxMessage({
    required this.id,
    required this.type,
    required this.sessionId,
    required this.text,
    required this.attempts,
    required this.createdAt,
  });

  final int id;
  final ChatSessionType type;
  final int sessionId;
  final String text;

  /// 已尝试次数（0 = 首次发送失败后入队）。
  final int attempts;

  /// 失败回显那条本地消息的时间（epoch 秒）；重试成功时用它把气泡标回成功。
  final int createdAt;

  String get sessionKey => sessionKeyOf(type, sessionId);
}

/// 队列快照（按会话计数），供 UI 显示「N 条待重发」。
class OutboxSnapshot {
  const OutboxSnapshot(this.perSession);

  final Map<String, int> perSession;

  int get total => perSession.values.fold(0, (a, b) => a + b);

  int countFor(String sessionKey) => perSession[sessionKey] ?? 0;
}

/// 发送一条队列消息：返回 true 表示服务端已接受；抛异常表示失败。
typedef OutboxSender = Future<bool> Function(OutboxMessage message);

/// 重试退避：base * 2^attempts，封顶 [cap]，再叠加全抖动。
///
/// 纯函数（随机源可注入），便于单测精确断言。
Duration outboxBackoff(
  int attempts, {
  Duration base = const Duration(seconds: 2),
  Duration cap = const Duration(minutes: 5),
  double Function()? random,
}) {
  final rng = random ?? Random().nextDouble;
  final computedMs = base.inMilliseconds * pow(2, attempts.clamp(0, 20));
  final cappedMs = computedMs.isFinite && computedMs < cap.inMilliseconds
      ? computedMs.toDouble()
      : cap.inMilliseconds.toDouble();
  final jittered = (rng() * cappedMs).round().clamp(1, cap.inMilliseconds);
  return Duration(milliseconds: jittered);
}

/// 发件箱服务。
class OutboxService {
  OutboxService({
    required this.getDb,
    required this.getMyUin,
    required this.send,
    DateTime Function()? now,
    this.random,
    this.autoFlush = true,
  }) : _now = now ?? DateTime.now;

  final AppDatabase? Function() getDb;
  final int Function() getMyUin;
  final OutboxSender send;
  final DateTime Function() _now;
  final double Function()? random;

  /// 入队后是否立即尝试发送。测试关掉它以便手动控制时机。
  final bool autoFlush;

  static const String _logTag = 'Outbox';

  /// 达到这个失败次数后不再自动重试（仍保留在队列里供手动重试）。
  static const int maxAttempts = 8;

  final StreamController<OutboxSnapshot> _changes =
      StreamController<OutboxSnapshot>.broadcast();

  Stream<OutboxSnapshot> get changes => _changes.stream;

  Timer? _timer;
  bool _flushing = false;

  int _sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  /// 入队一条失败消息。相同会话/正文且时间相近的重复入队会被忽略
  /// （双击发送、catch 被调用两次都不会产生两条重试）。
  Future<void> enqueue({
    required ChatSessionType type,
    required int sessionId,
    required String text,
  }) async {
    final db = getDb();
    final owner = getMyUin();
    if (db == null || owner == 0 || text.trim().isEmpty) return;
    final created = _sec(_now());
    try {
      final existing = await db.allOutbox(owner);
      final duplicate = existing.any(
        (r) =>
            r.sessionKey == sessionKeyOf(type, sessionId) &&
            r.content == text &&
            (r.createdAt - created).abs() <= 3,
      );
      if (duplicate) return;
      await db.enqueueOutbox(
        ChatOutboxCompanion.insert(
          ownerUin: owner,
          sessionKey: sessionKeyOf(type, sessionId),
          typeId: type == ChatSessionType.friend ? 1 : 2,
          sessionId: sessionId,
          content: text,
          createdAt: created,
          nextAttemptAt: created + 2,
        ),
      );
      await _emit();
    } catch (e) {
      log.warn('enqueue failed: $e', tag: _logTag);
      return;
    }
    if (autoFlush) unawaited(flushDue());
  }

  /// 立即尝试所有到期消息；[force] 时连未到期的也试（用户点「重试」）。
  Future<int> flushDue({bool force = false, int limit = 20}) async {
    if (_flushing) return 0;
    final db = getDb();
    final owner = getMyUin();
    if (db == null || owner == 0) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final now = _sec(_now());
      final rows = force
          ? (await db.allOutbox(owner)).take(limit).toList()
          : await db.dueOutbox(owner, now, limit: limit);
      for (final r in rows) {
        final type = r.typeId == 2 ? ChatSessionType.group : ChatSessionType.friend;
        final message = OutboxMessage(
          id: r.id,
          type: type,
          sessionId: r.sessionId,
          text: r.content,
          attempts: r.attempts,
          createdAt: r.createdAt,
        );
        try {
          final ok = await send(message);
          if (!ok) throw StateError('server rejected');
          await db.deleteOutbox(r.id);
          sent++;
        } catch (e) {
          final attempts = r.attempts + 1;
          if (attempts >= maxAttempts) {
            // 保留在队列里等用户手动重试，指示 UI 不再自动跑。
            await db.markOutboxRetry(
              r.id,
              attempts: attempts,
              nextAttemptAt: now + 24 * 3600,
              lastError: '$e',
            );
          } else {
            final delay = outboxBackoff(attempts, random: random);
            await db.markOutboxRetry(
              r.id,
              attempts: attempts,
              nextAttemptAt: now + delay.inSeconds.clamp(1, 300),
              lastError: '$e',
            );
          }
          log.warn('retry ${r.id} failed (attempt $attempts): $e', tag: _logTag);
        }
      }
      await _emit();
    } finally {
      _flushing = false;
    }
    _scheduleNext();
    return sent;
  }

  /// 当前队列快照（数据库为准）。
  Future<OutboxSnapshot> snapshot() async {
    final db = getDb();
    final owner = getMyUin();
    if (db == null || owner == 0) return const OutboxSnapshot({});
    try {
      final rows = await db.allOutbox(owner);
      final map = <String, int>{};
      for (final r in rows) {
        map[r.sessionKey] = (map[r.sessionKey] ?? 0) + 1;
      }
      return OutboxSnapshot(map);
    } catch (_) {
      return const OutboxSnapshot({});
    }
  }

  /// 手动重试某会话的全部消息。
  Future<int> retrySession(String sessionKey) async {
    final db = getDb();
    final owner = getMyUin();
    if (db == null || owner == 0) return 0;
    final rows = (await db.allOutbox(owner))
        .where((r) => r.sessionKey == sessionKey)
        .toList();
    var sent = 0;
    for (final r in rows) {
      try {
        final type = r.typeId == 2
            ? ChatSessionType.group
            : ChatSessionType.friend;
        final ok = await send(
          OutboxMessage(
            id: r.id,
            type: type,
            sessionId: r.sessionId,
            text: r.content,
            attempts: r.attempts,
            createdAt: r.createdAt,
          ),
        );
        if (!ok) continue;
        await db.deleteOutbox(r.id);
        sent++;
      } catch (_) {
        // 单条失败不影响其它条；下一次 flush 会继续按退避重试。
      }
    }
    await _emit();
    return sent;
  }

  Future<void> _emit() async {
    if (_changes.isClosed) return;
    _changes.add(await snapshot());
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = null;
    final db = getDb();
    final owner = getMyUin();
    if (db == null || owner == 0) return;
    unawaited(() async {
      final rows = await db.allOutbox(owner);
      if (rows.isEmpty || _changes.isClosed) return;
      var soonest = rows
          .map((r) => r.nextAttemptAt)
          .reduce((a, b) => a < b ? a : b);
      final now = _sec(_now());
      final wait = Duration(seconds: (soonest - now).clamp(1, 300));
      _timer = Timer(wait, () => unawaited(flushDue()));
    }());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_changes.close());
  }
}
