import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import '../../core/utils/battery_bot_faq.dart';
import '../../core/services/account_secure_storage.dart';
import 'notification_service.dart';

class AccountReminder {
  const AccountReminder({
    required this.id,
    required this.uid,
    required this.vehicleId,
    required this.title,
    required this.kind,
    required this.dueDate,
    this.revision = 1,
    this.pendingSync = true,
    this.notificationsEnabled = false,
    this.cancelled = false,
    this.operationId = '',
    this.syncConflict = false,
  });
  final String id, uid, vehicleId, title, kind;
  final DateTime dueDate;
  final int revision;
  final bool pendingSync, notificationsEnabled;
  final bool cancelled, syncConflict;
  final String operationId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': uid,
    'vehicleId': vehicleId,
    'title': title,
    'kind': kind,
    'dueDate': dueDate.toIso8601String(),
    'timezone': 'Asia/Ho_Chi_Minh',
    'reminderDays': [7, 1],
    'revision': revision,
    'pendingSync': pendingSync,
    'notificationsEnabled': notificationsEnabled,
    'state': cancelled ? 'cancelled' : 'active',
    'operationId': operationId.isEmpty ? id : operationId,
    'syncConflict': syncConflict,
  };
  factory AccountReminder.fromJson(Map<String, dynamic> data) =>
      AccountReminder(
        id: data['id'] as String,
        uid: data['uid'] as String,
        vehicleId: data['vehicleId'] as String,
        title: data['title'] as String,
        kind: data['kind'] as String,
        dueDate: DateTime.parse(data['dueDate'] as String),
        revision: data['revision'] as int,
        pendingSync: data['pendingSync'] == true,
        notificationsEnabled: data['notificationsEnabled'] == true,
        cancelled: data['state'] == 'cancelled',
        operationId: data['operationId'] as String? ?? data['id'] as String,
        syncConflict: data['syncConflict'] == true,
      );
  AccountReminder copyWithId(String value) => AccountReminder(
    id: value,
    uid: uid,
    vehicleId: vehicleId,
    title: title,
    kind: kind,
    dueDate: dueDate,
    revision: revision,
    pendingSync: pendingSync,
    notificationsEnabled: notificationsEnabled,
    cancelled: cancelled,
    operationId: operationId.isEmpty ? value : operationId,
    syncConflict: syncConflict,
  );
  AccountReminder withStatus({
    required bool pending,
    required bool notifications,
    bool? conflict,
  }) => AccountReminder(
    id: id,
    uid: uid,
    vehicleId: vehicleId,
    title: title,
    kind: kind,
    dueDate: dueDate,
    revision: revision,
    pendingSync: pending,
    notificationsEnabled: notifications,
    cancelled: cancelled,
    operationId: operationId,
    syncConflict: conflict ?? syncConflict,
  );

  AccountReminder revised({
    required String operation,
    DateTime? date,
    required bool cancel,
  }) => AccountReminder(
    id: id,
    uid: uid,
    vehicleId: vehicleId,
    title: title,
    kind: kind,
    dueDate: date ?? dueDate,
    revision: revision + 1,
    cancelled: cancel,
    operationId: operation,
  );

  Map<String, dynamic> get cloudData => {...toJson()}..remove('syncConflict');

  /// True for the next revision, false for an identical receipt; otherwise
  /// fail closed. Used inside the Firestore transaction, never read-then-write.
  bool requiresCloudWrite(Map<String, dynamic>? existing) {
    if (existing == null) {
      if (revision != 1 || cancelled) throw const ReminderConflictException();
      return true;
    }
    if (existing['vehicleId'] != vehicleId ||
        existing['uid'] != uid ||
        existing['id'] != id) {
      throw const ReminderConflictException();
    }
    if (existing['revision'] == revision) {
      if (existing['title'] != title ||
          existing['dueDate'] != dueDate.toIso8601String() ||
          existing['kind'] != kind ||
          (existing['state'] ?? 'active') !=
              (cancelled ? 'cancelled' : 'active') ||
          (existing['operationId'] ?? existing['id']) !=
              (operationId.isEmpty ? id : operationId)) {
        throw const ReminderConflictException();
      }
      return false;
    }
    if (existing['revision'] != revision - 1 ||
        existing['state'] == 'cancelled') {
      throw const ReminderConflictException();
    }
    return true;
  }

  static AccountReminder? parse(
    String text,
    String uid,
    String vehicleId, {
    DateTime? now,
  }) {
    final match = RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b').firstMatch(text);
    if (match == null || text.length > 240) return null;
    final day = int.parse(match[1]!),
        month = int.parse(match[2]!),
        year = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    final reference = now ?? DateTime.now();
    if (date.day != day ||
        date.month != month ||
        date.year != year ||
        date.isBefore(
          DateTime(reference.year, reference.month, reference.day),
        )) {
      return null;
    }
    final normalized = BatteryBotFaq.normalize(text);
    final kind = normalized.contains('bao hanh')
        ? 'warranty'
        : normalized.contains('bao duong')
        ? 'maintenance'
        : 'appointment';
    final title = text.replaceRange(match.start, match.end, '').trim();
    if (title.length < 3) return null;
    return AccountReminder(
      id: '',
      uid: uid,
      vehicleId: vehicleId,
      title: title,
      kind: kind,
      dueDate: date,
    );
  }
}

class ReminderConflictException implements Exception {
  const ReminderConflictException();
}

/// Resolves a reminder only by explicit date/kind in the current vehicle.
/// Ambiguous selections require clarification, never the first list entry.
class ReminderChatSelection {
  const ReminderChatSelection(this.item, this.newDate);
  final AccountReminder item;
  final DateTime? newDate;

  static ReminderChatSelection? parse(
    String text,
    List<AccountReminder> items, {
    required bool cancel,
    DateTime? now,
  }) {
    final matches = RegExp(
      r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b',
    ).allMatches(text).toList();
    if (matches.length != (cancel ? 1 : 2)) return null;
    final dates = <DateTime>[];
    for (final match in matches) {
      final day = int.parse(match[1]!),
          month = int.parse(match[2]!),
          year = int.parse(match[3]!);
      final date = DateTime(year, month, day);
      if (date.day != day || date.month != month || date.year != year) {
        return null;
      }
      dates.add(date);
    }
    final normalized = BatteryBotFaq.normalize(text);
    final kind = normalized.contains('bao hanh')
        ? 'warranty'
        : normalized.contains('bao duong')
        ? 'maintenance'
        : normalized.contains('lich hen')
        ? 'appointment'
        : null;
    if (kind == null) return null;
    final candidates = items
        .where(
          (e) =>
              !e.cancelled &&
              e.kind == kind &&
              e.dueDate.year == dates.first.year &&
              e.dueDate.month == dates.first.month &&
              e.dueDate.day == dates.first.day,
        )
        .toList();
    if (candidates.length != 1) return null;
    if (!cancel) {
      final reference = now ?? DateTime.now();
      if (dates.last.isBefore(
        DateTime(reference.year, reference.month, reference.day),
      )) {
        return null;
      }
    }
    return ReminderChatSelection(candidates.single, cancel ? null : dates.last);
  }
}

/// Local-first date reminders. No relay actions or cloud AI calls.
class AccountReminderService with WidgetsBindingObserver {
  static final instance = AccountReminderService();
  AccountReminderService({
    String? Function()? uidResolver,
    FlutterSecureStorage? storage,
    Future<bool> Function(AccountReminder)? scheduleNotification,
    Future<void> Function(AccountReminder)? cancelNotification,
    Future<void> Function(AccountReminder)? uploadReminder,
  }) : _uidResolver = uidResolver ?? _firebaseUid,
       _scheduleOverride = scheduleNotification,
       _cancelOverride = cancelNotification,
       _uploadOverride = uploadReminder,
       _storage = storage ?? accountSecureStorage;
  final String? Function() _uidResolver;
  final FlutterSecureStorage _storage;
  final Future<bool> Function(AccountReminder)? _scheduleOverride;
  final Future<void> Function(AccountReminder)? _cancelOverride;
  final Future<void> Function(AccountReminder)? _uploadOverride;
  StreamSubscription<User?>? _auth;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remote;
  String? _owner;
  bool _remoteVerified = false;
  bool get remoteVerified => _remoteVerified && _owner == _uidResolver();
  int _generation = 0;
  Future<void> _tail = Future.value();
  static String? _firebaseUid() =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  String _key(String uid) => 'account_reminders_v1.${Uri.encodeComponent(uid)}';
  bool _current(String uid, int generation) =>
      uid == _uidResolver() && generation == _generation;

  Future<void> initialize() async {
    if (_auth != null || Firebase.apps.isEmpty) return;
    WidgetsBinding.instance.addObserver(this);
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      final previous = _owner;
      _owner = user?.uid;
      _remoteVerified = false;
      final generation = ++_generation;
      final next = _owner;
      _tail = _tail
          .then((_) => _changeOwner(previous, next, generation))
          .catchError((Object _) {});
    });
  }

  Future<void> _changeOwner(
    String? previous,
    String? next,
    int generation,
  ) async {
    await _remote?.cancel();
    _remote = null;
    if (previous != null) {
      final old = await _load(previous);
      for (final item in old) {
        try {
          await _cancel(item);
        } on Object {
          /* Continue teardown of other reminders. */
        }
      }
    }
    if (next == null || !_current(next, generation)) return;
    final local = await _load(next);
    for (var index = 0; index < local.length; index++) {
      final item = local[index];
      if (!_current(next, generation)) return;
      // A crash between durable cancellation and OS cleanup must be recoverable.
      if (item.cancelled || item.syncConflict) await _cancel(item);
      final notifications = await _schedule(item, generation);
      local[index] = item.withStatus(
        pending: item.pendingSync,
        notifications: notifications,
      );
      if (item.pendingSync && !item.syncConflict) {
        try {
          await _upload(item, generation);
          local[index] = item.withStatus(
            pending: false,
            notifications: notifications,
          );
        } on ReminderConflictException {
          await _cancel(item);
          local[index] = item.withStatus(
            pending: true,
            notifications: false,
            conflict: true,
          );
        } on Object {
          /* Durable pending remains. */
        }
      }
    }
    if (_current(next, generation)) await _persist(next, local);
    if (!_current(next, generation)) return;
    _remote = FirebaseFirestore.instance
        .collection('users')
        .doc(next)
        .collection('reminders')
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (!_current(next, generation) || snapshot.metadata.isFromCache) {
              return;
            }
            _tail = _tail
                .then((_) async {
                  if (!_current(next, generation)) return;
                  final items = await _load(next);
                  final remoteIds = snapshot.docs.map((e) => e.id).toSet();
                  for (final removed
                      in items
                          .where(
                            (e) => !e.pendingSync && !remoteIds.contains(e.id),
                          )
                          .toList()) {
                    await _cancel(removed);
                    items.remove(removed);
                  }
                  for (final change in snapshot.docChanges) {
                    final index = items.indexWhere(
                      (e) => e.id == change.doc.id,
                    );
                    if (change.type == DocumentChangeType.removed) {
                      if (index >= 0 && !items[index].pendingSync) {
                        await _cancel(items.removeAt(index));
                      }
                      continue;
                    }
                    var item = AccountReminder.fromJson({
                      ...change.doc.data()!,
                      'pendingSync': false,
                    });
                    if (item.uid != next || item.id != change.doc.id) continue;
                    if (index >= 0 &&
                        (items[index].revision > item.revision ||
                            items[index].pendingSync)) {
                      continue;
                    }
                    if (index >= 0) {
                      await _cancel(items[index]);
                      items[index] = item;
                    } else {
                      items.add(item);
                    }
                    final notifications = await _schedule(item, generation);
                    item = item.withStatus(
                      pending: false,
                      notifications: notifications,
                    );
                    items[items.indexWhere((e) => e.id == item.id)] = item;
                  }
                  if (_current(next, generation)) {
                    await _persist(next, items);
                    _remoteVerified = true;
                  }
                })
                .catchError((Object _) {});
          },
          onError: (Object _) {
            if (_current(next, generation)) _remoteVerified = false;
            /* Do not convert permission/network errors to empty. */
          },
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final owner = _uidResolver();
    if (state == AppLifecycleState.resumed && owner != null) {
      final generation = _generation;
      _tail = _tail
          .then((_) => _changeOwner(null, owner, generation))
          .catchError((Object _) {});
    }
  }

  Future<List<AccountReminder>> _load(String uid) async {
    final raw = await _storage.read(key: _key(uid));
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (e) => AccountReminder.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<void> _persist(String uid, List<AccountReminder> items) =>
      _storage.write(
        key: _key(uid),
        value: jsonEncode(items.map((e) => e.toJson()).toList()),
      );
  Future<List<AccountReminder>> list(
    String vehicleId, {
    bool includeCancelled = false,
  }) async {
    final uid = _uidResolver();
    if (uid == null) return [];
    final generation = _generation;
    final items = await _load(uid);
    if (!_current(uid, generation)) return [];
    return items
        .where(
          (e) => e.vehicleId == vehicleId && (includeCancelled || !e.cancelled),
        )
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  Future<void> _upload(AccountReminder item, int generation) async {
    if (!_current(item.uid, generation)) throw StateError('accountChanged');
    if (_uploadOverride != null) return _uploadOverride(item);
    final doc = FirebaseFirestore.instance
        .collection('users')
        .doc(item.uid)
        .collection('reminders')
        .doc(item.id);
    await FirebaseFirestore.instance
        .runTransaction((tx) async {
          final existing = await tx.get(doc);
          if (!_current(item.uid, generation)) {
            throw StateError('accountChanged');
          }
          if (!item.requiresCloudWrite(existing.data())) return;
          tx.set(doc, {...item.cloudData, 'pendingSync': false});
        })
        .timeout(const Duration(seconds: 10));
  }

  Future<AccountReminder> save(AccountReminder item) {
    final owner = _uidResolver(), generation = _generation;
    final completer = Completer<AccountReminder>();
    _tail = _tail
        .then((_) async {
          if (owner == null ||
              owner != item.uid ||
              !_current(owner, generation) ||
              item.id.isEmpty) {
            throw StateError('accountChanged');
          }
          final items = await _load(owner);
          if (!_current(owner, generation)) throw StateError('accountChanged');
          final index = items.indexWhere((e) => e.id == item.id);
          if (index >= 0) {
            if (items[index].vehicleId != item.vehicleId ||
                items[index].title != item.title ||
                items[index].dueDate != item.dueDate ||
                items[index].kind != item.kind) {
              throw const ReminderConflictException();
            }
            completer.complete(items[index]);
            return;
          }
          if (items.length >= 100) throw StateError('reminderLimit');
          if (item.revision != 1 ||
              item.cancelled ||
              item.syncConflict ||
              item.id.length > 128 ||
              item.vehicleId.isEmpty ||
              item.title.trim().length < 3 ||
              item.title.length > 240 ||
              !{'maintenance', 'warranty', 'appointment'}.contains(item.kind)) {
            throw ArgumentError('invalidReminder');
          }
          items.add(item);
          if (!_current(owner, generation)) throw StateError('accountChanged');
          await _persist(
            owner,
            items,
          ); // Durable before network or notification work.
          var saved = item;
          try {
            await _upload(item, generation);
            saved = saved.withStatus(pending: false, notifications: false);
          } on ReminderConflictException {
            saved = saved.withStatus(
              pending: true,
              notifications: false,
              conflict: true,
            );
          } on Object {
            /* Keep pending. */
          }
          if (!_current(owner, generation)) throw StateError('accountChanged');
          final notifications = await _schedule(saved, generation);
          saved = saved.withStatus(
            pending: saved.pendingSync,
            notifications: notifications,
          );
          if (!_current(owner, generation)) throw StateError('accountChanged');
          items[items.length - 1] = saved;
          await _persist(owner, items);
          completer.complete(saved);
        })
        .catchError((Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        });
    return completer.future;
  }

  /// Revision-checked edit/cancel. Call only after an explicit user confirmation.
  /// One unsynced mutation at a time; cancelled records remain as tombstones.
  Future<AccountReminder> revise({
    required String vehicleId,
    required String reminderId,
    required int expectedRevision,
    required String operationId,
    DateTime? dueDate,
    bool cancel = false,
  }) {
    final owner = _uidResolver(), generation = _generation;
    final completer = Completer<AccountReminder>();
    _tail = _tail
        .then((_) async {
          if (owner == null || !_current(owner, generation)) {
            throw StateError('accountChanged');
          }
          if (operationId.isEmpty ||
              operationId.length > 128 ||
              (!cancel && dueDate == null)) {
            throw ArgumentError('invalidMutation');
          }
          final items = await _load(owner);
          if (!_current(owner, generation)) throw StateError('accountChanged');
          final index = items.indexWhere(
            (e) =>
                e.id == reminderId &&
                e.vehicleId == vehicleId &&
                e.uid == owner,
          );
          if (index < 0) throw const ReminderConflictException();
          final old = items[index];
          if (old.operationId == operationId &&
              old.revision == expectedRevision + 1 &&
              old.cancelled == cancel &&
              old.dueDate == (dueDate ?? old.dueDate)) {
            // A prior attempt may have persisted before OS cleanup failed.
            // Do not return a receipt until local notification cleanup works.
            if (old.pendingSync) {
              await _cancel(old);
              if (!_current(owner, generation)) {
                throw StateError('accountChanged');
              }
              if (!old.cancelled && !old.syncConflict) {
                await _schedule(old, generation);
              }
            }
            if (!_current(owner, generation)) {
              throw StateError('accountChanged');
            }
            completer.complete(old);
            return;
          }
          if (old.revision != expectedRevision ||
              old.pendingSync ||
              old.cancelled ||
              old.syncConflict) {
            throw const ReminderConflictException();
          }
          if (dueDate != null) {
            final now = DateTime.now();
            if (dueDate.isBefore(DateTime(now.year, now.month, now.day))) {
              throw ArgumentError('pastDate');
            }
          }
          var saved = old.revised(
            operation: operationId,
            date: dueDate,
            cancel: cancel,
          );
          items[index] = saved;
          await _persist(owner, items); // Durable before cancel/upload.
          await _cancel(old);
          if (!_current(owner, generation)) throw StateError('accountChanged');
          try {
            await _upload(saved, generation);
            saved = saved.withStatus(pending: false, notifications: false);
          } on ReminderConflictException {
            saved = saved.withStatus(
              pending: true,
              notifications: false,
              conflict: true,
            );
          } on Object {
            /* Pending mutation is durable for reconnect. */
          }
          if (!_current(owner, generation)) throw StateError('accountChanged');
          final enabled = await _schedule(saved, generation);
          if (!_current(owner, generation)) throw StateError('accountChanged');
          saved = saved.withStatus(
            pending: saved.pendingSync,
            notifications: enabled,
          );
          items[index] = saved;
          await _persist(owner, items);
          completer.complete(saved);
        })
        .catchError((Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        });
    return completer.future;
  }

  static int notificationId(String uid, String taskId, int days) {
    final bytes = sha256.convert(utf8.encode('$uid/$taskId/$days')).bytes;
    return 0x20000000 |
        ((bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]) &
            0x0fffffff);
  }

  Future<bool> _schedule(AccountReminder item, int generation) async {
    if (!_current(item.uid, generation) ||
        item.cancelled ||
        item.syncConflict) {
      return false;
    }
    if (_scheduleOverride != null) return _scheduleOverride(item);
    var enabled = true;
    for (final days in [7, 1]) {
      if (!_current(item.uid, generation)) return false;
      try {
        enabled =
            await NotificationService().scheduleAccountReminder(
              await _allocatedNotificationId(item.uid, item.id, days),
              item.dueDate,
              days,
              item.id,
            ) &&
            enabled;
        if (!_current(item.uid, generation)) {
          await _cancel(item);
          return false;
        }
      } on Object {
        enabled = false;
      }
    }
    return enabled;
  }

  Future<void> _cancel(AccountReminder item) async {
    if (_cancelOverride != null) return _cancelOverride(item);
    for (final days in [7, 1]) {
      await NotificationService().cancel(
        await _allocatedNotificationId(item.uid, item.id, days),
      );
    }
  }

  Future<int> _allocatedNotificationId(
    String uid,
    String taskId,
    int days,
  ) async {
    const key = 'account_reminder_notification_ids_v1';
    final raw = await _storage.read(key: key);
    final registry = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final scope = '$uid/$taskId/$days';
    if (registry[scope] is int) return registry[scope] as int;
    var id = notificationId(uid, taskId, days);
    final used = registry.values.toSet();
    while (used.contains(id)) {
      id = 0x20000000 | ((id + 1) & 0x0fffffff);
    }
    registry[scope] = id;
    await _storage.write(key: key, value: jsonEncode(registry));
    return id;
  }

  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_auth?.cancel());
    unawaited(_remote?.cancel());
  }
}
