import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-household preferences for the daily "grocery shopping today?" push
/// notification. Persisted at `households/{id}/config/restockReminder` so the
/// whole household agrees on when the reminder fires (the scheduled function
/// fans out to every member's FCM token).
class RestockReminderConfig {
  final bool enabled;

  /// How many days to wait between reminders. 1 = daily, 7 = weekly.
  final int cadenceDays;

  /// Hour of the day (0-23) the user wants the notification to land, expressed
  /// in the saver's local time. Combined with [timezoneOffsetMinutes] so the
  /// function can convert back to UTC at fire time.
  final int preferredHour;

  /// Captured from the device at save time (`DateTime.now().timeZoneOffset`).
  /// Good enough for a grocery reminder — a DST shift just nudges delivery by
  /// an hour until the user re-saves.
  final int timezoneOffsetMinutes;

  final DateTime? lastSentAt;

  const RestockReminderConfig({
    required this.enabled,
    required this.cadenceDays,
    required this.preferredHour,
    required this.timezoneOffsetMinutes,
    required this.lastSentAt,
  });

  factory RestockReminderConfig.defaults() => const RestockReminderConfig(
        enabled: false,
        cadenceDays: 2,
        preferredHour: 9,
        timezoneOffsetMinutes: 0,
        lastSentAt: null,
      );

  factory RestockReminderConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return RestockReminderConfig.defaults();
    return RestockReminderConfig(
      enabled: m['enabled'] ?? false,
      cadenceDays: (m['cadenceDays'] as int?) ?? 2,
      preferredHour: (m['preferredHour'] as int?) ?? 9,
      timezoneOffsetMinutes: (m['timezoneOffsetMinutes'] as int?) ?? 0,
      lastSentAt: (m['lastSentAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'cadenceDays': cadenceDays,
        'preferredHour': preferredHour,
        'timezoneOffsetMinutes': timezoneOffsetMinutes,
        if (lastSentAt != null) 'lastSentAt': Timestamp.fromDate(lastSentAt!),
      };

  RestockReminderConfig copyWith({
    bool? enabled,
    int? cadenceDays,
    int? preferredHour,
    int? timezoneOffsetMinutes,
    DateTime? lastSentAt,
  }) =>
      RestockReminderConfig(
        enabled: enabled ?? this.enabled,
        cadenceDays: cadenceDays ?? this.cadenceDays,
        preferredHour: preferredHour ?? this.preferredHour,
        timezoneOffsetMinutes:
            timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
        lastSentAt: lastSentAt ?? this.lastSentAt,
      );
}

class RestockReminderService {
  final FirebaseFirestore _db;
  RestockReminderService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  Stream<RestockReminderConfig> configStream(String householdId) {
    return _db
        .doc('households/$householdId/config/restockReminder')
        .snapshots()
        .map((doc) => RestockReminderConfig.fromMap(doc.data()));
  }

  /// Merges the user-editable fields; never overwrites `lastSentAt` from the
  /// client (that's owned by the scheduled cloud function).
  Future<void> save(String householdId, RestockReminderConfig config) async {
    await _db.doc('households/$householdId/config/restockReminder').set(
      {
        'enabled': config.enabled,
        'cadenceDays': config.cadenceDays,
        'preferredHour': config.preferredHour,
        'timezoneOffsetMinutes': config.timezoneOffsetMinutes,
      },
      SetOptions(merge: true),
    );
  }
}
