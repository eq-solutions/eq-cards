abstract class Routes {
  static const splash = '/';
  static const phoneEntry = '/auth/phone';
  static const otp = '/auth/otp';
  static const home = '/home';
  static const profile = '/profile';
  static const profileEdit = '/profile/edit';
  static const licencesList = '/licences';
  static const licenceCreate = '/licences/new';
  static const licenceCapture = '/licences/capture';
  static const licenceDetail = '/licences/:id';
  static const licenceEdit = '/licences/:id/edit';
  static const settings = '/settings';

  /// URL builders for path-parameter routes. Use these instead of hand-rolled
  /// string interpolation so the route shapes stay in one place.
  static String licenceDetailFor(String id) => '/licences/$id';
  static String licenceEditFor(String id) => '/licences/$id/edit';
}
