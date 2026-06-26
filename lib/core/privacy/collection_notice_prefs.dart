import 'package:shared_preferences/shared_preferences.dart';

/// One-time dismissal flags for APP 5 collection notices. Each notice is
/// shown once per device and stored in SharedPreferences. These are UI
/// acknowledgements (not consent records) — they do not need to be tied
/// to a specific user account.
class CollectionNoticePrefs {
  CollectionNoticePrefs._();

  static const _profileKey = 'collection_notice_profile_seen';
  static const _photoUploadKey = 'collection_notice_photo_upload_seen';

  static Future<bool> isProfileSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_profileKey) ?? false;
    } catch (_) {
      return true; // fail-safe: don't block the form if prefs unavailable
    }
  }

  static Future<void> setProfileSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_profileKey, true);
    } catch (_) {}
  }

  static Future<bool> isPhotoUploadSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_photoUploadKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setPhotoUploadSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_photoUploadKey, true);
    } catch (_) {}
  }
}
