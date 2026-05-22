class ApiConfig {
  static const String baseUrl = 'http://api.elegant.vironna.com/api/';
  
  /// Endpoint for syncing general data (users, invoices, etc.)
  static const String dataSyncEndpoint = 'sync/device';
  
  /// Endpoint for syncing store profile and business metrics.
  /// User will provide the actual link later.
  static const String profileSyncEndpoint = 'profile/sync'; // Placeholder
}
