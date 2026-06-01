import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../licences/licences.dart';
import '../../worker_house/worker_house.dart';

part 'alerts_scheduler.g.dart';

class AlertsScheduler {
  AlertsScheduler() : _plugin = FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'expiry_alerts';
  static const _channelName = 'Licence expiry alerts';
  static const _channelDesc =
      'Reminders 90, 30 and 7 days before a licence expires';
  static const _alertDays = [90, 30, 7];

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    if (kIsWeb) {
      // Local notifications aren't supported on web in v1; the home shell
      // calls syncAll on every platform, so we mark init complete and let
      // every other method short-circuit.
      _initialised = true;
      return;
    }
    tz_data.initializeTimeZones();
    // V1 hardcodes Australia/Sydney since the user base is Aussie tradies.
    // Without this, `tz.local` defaults to UTC and alerts fire ~10h off.
    // v1.1: detect via flutter_native_timezone for users who travel.
    tz.setLocalLocation(tz.getLocation('Australia/Sydney'));

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: initSettings);

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
      await androidPlugin?.requestNotificationsPermission();
    }
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    _initialised = true;
  }

  /// Cancel everything currently scheduled and re-schedule for the given list.
  /// Pass [credentials] to also schedule renewal reminders for worker-house
  /// credentials (seeded via Intake). Both lists are synced in a single
  /// cancelAll → re-schedule pass so they don't clobber each other.
  Future<void> syncAll(
    List<Licence> licences, {
    List<WorkerCredential> credentials = const [],
  }) async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancelAll();
    for (final licence in licences) {
      // Individual failures skip the entry rather than aborting the whole
      // sync — cancelAll already ran, so a mid-loop throw would leave the
      // user with zero notifications.
      try { await _scheduleForLicence(licence); } catch (_) {}
    }
    for (final credential in credentials) {
      try { await _scheduleForCredential(credential); } catch (_) {}
    }
  }

  Future<void> scheduleForLicence(Licence licence) async {
    if (kIsWeb) return;
    await init();
    if (licence.id != null) await _cancelForLicenceId(licence.id!);
    await _scheduleForLicence(licence);
  }

  Future<void> cancelForLicence(String licenceId) async {
    if (kIsWeb) return;
    await init();
    await _cancelForLicenceId(licenceId);
  }

  Future<void> _scheduleForLicence(Licence licence) async {
    if (licence.id == null) return;
    final now = DateTime.now();
    for (final daysBefore in _alertDays) {
      final fireAt = licence.expiryDate.subtract(Duration(days: daysBefore));
      if (fireAt.isBefore(now)) continue;
      await _plugin.zonedSchedule(
        id: _idFor(licence.id!, daysBefore),
        title: 'Licence expires in $daysBefore days',
        body: '${licence.licenceType} ${licence.licenceNumber} expires '
            '${_formatDate(licence.expiryDate)}',
        scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: licence.id ?? '',
      );
    }
  }

  Future<void> _scheduleForCredential(WorkerCredential credential) async {
    if (credential.expiryDate == null) return;
    final now = DateTime.now();
    final label = workerCredentialTypeLabels[credential.credentialType]
        ?? credential.credentialType;
    for (final daysBefore in _alertDays) {
      final fireAt =
          credential.expiryDate!.subtract(Duration(days: daysBefore));
      if (fireAt.isBefore(now)) continue;
      await _plugin.zonedSchedule(
        // 'wc_' prefix keeps the int32 hash space separate from licence IDs.
        id: _idFor('wc_${credential.id}', daysBefore),
        title: '$label expires in $daysBefore days',
        body: '${credential.licenceNumber != null ? '${credential.licenceNumber} — ' : ''}'
            '$label expires ${_formatDate(credential.expiryDate!)}',
        scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: credential.id,
      );
    }
  }

  Future<void> _cancelForLicenceId(String licenceId) async {
    for (final daysBefore in _alertDays) {
      await _plugin.cancel(id: _idFor(licenceId, daysBefore));
    }
  }

  /// Stable int hash from licenceId + daysBefore. Constrained to int32 range.
  int _idFor(String licenceId, int daysBefore) {
    final raw = '${licenceId}_$daysBefore';
    var hash = 0;
    for (final unit in raw.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

@Riverpod(keepAlive: true)
AlertsScheduler alertsScheduler(Ref ref) {
  return AlertsScheduler();
}
