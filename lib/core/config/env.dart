class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://luckyapp-production-ca29.up.railway.app',
  );
}
