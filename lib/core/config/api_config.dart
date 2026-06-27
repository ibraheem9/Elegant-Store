class ApiConfig {
  static const String baseUrl = 'http://api.elegant.vironna.com/api/';
  
  /// Endpoint for syncing general data (users, invoices, etc.)
  static const String dataSyncEndpoint = 'sync/device';
  
  /// Endpoint for syncing store profile and business metrics.
  static const String profileSyncEndpoint = 'app-customer/sync';
  
  /// Endpoint for syncing app customer tracking and usage stats.
  static const String appCustomerSyncEndpoint = 'app-customer/sync';

  /// Default WhatsApp support number used as a fallback.
  static const String defaultWhatsApp = '970567228380';
}
