# Profile Page and Store Metrics Implementation

Implement a store profile page, update the database schema for device-specific metrics, and ensure metrics are recalculated before synchronization.

## Proposed Changes

### Database Layer
Group files by component and order logically.

#### [models.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/models/models.dart)
- Added `StoreProfile` model for managing store information and business metrics.
- Added `DeviceInfoModel` model for tracking device-specific technical details.

#### [database_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/database_service.dart)
- Bumped database version to `10`.
- Added `product_customers` and `product_device_info` tables in `_createTables` and `onUpgrade`.
- Implemented `recalculateStoreMetrics()` to aggregate total customers, invoices, sales, and purchases.
- Added CRUD methods for `StoreProfile` and `DeviceInfoModel`.
- Added `updateStoreProfileMetrics()` to refresh metrics and update `last_active_time`.

---

### Synchronization Layer

#### [api_config.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/core/config/api_config.dart)
- Added `profileSyncEndpoint` to separate the profile/metrics sync from the main data sync.

#### [device_sync_service.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/device_sync_service.dart)
- Added `syncStoreProfileOnly()` method which POSTs `StoreProfile` and `DeviceInfoModel` to the `profileSyncEndpoint`.
- Updated `performFullSync()` to trigger `updateStoreProfileMetrics()` before sync starts.
- Updated `completeSync()` to save `last_sync_time` in the `product_customers` table upon successful completion.
- Improved device name retrieval for Windows using `windowsInfo.computerName`.

#### [sync_manager.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/services/sync_manager.dart)
- Updated unified sync flow to include a third step: calling `_deviceSyncService.syncStoreProfileOnly()`.

---

### UI Layer

#### [NEW] [profile_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/profile_screen.dart)
- Implemented the Profile Screen with editable fields for Managers:
    - Store Name, Owner Name, Address, City.
    - Mobile (Palestinian format), WhatsApp (+970 / +972).
- Added a dashboard of business metrics (Sales, Purchases, Invoices, Customers) - **Hidden for Sellers**.
- Displayed read-only device information (Device ID, Device Name) - **Hidden for Sellers**.
- Restricted editing of store information and profile saving to Managers only.

#### [dashboard_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/dashboard_screen.dart)
- Registered `ProfileScreen` in the navigation system.
- Added "الملف الشخصي للمتجر" (Store Profile) to the side menu and mobile drawer, positioned before "Settings".

#### [sync_details_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/sync_details_screen.dart)
- Added a "Reset Data" button to clear local data and reset the database state (already implemented in `DatabaseService` but exposed to UI).

---

## Verification Plan

### Automated Tests
- Run `flutter test` to ensure no regressions in existing models or logic (if tests exist).
- *Note*: I will verify the new functionality manually as automated UI tests for SQLite migrations are complex in this environment.

### Manual Verification
1. **Database Migration**:
    - Launch the app to trigger the migration to version 10.
    - Verify tables `product_customers` and `product_device_info` exist using `adb shell sqlite3` if possible, or by checking if the Profile screen loads without errors.
2. **Profile Page**:
    - Navigate to the new "Profile" screen from the side menu.
    - Fill in store details and click "Save".
    - Verify data persists after app restart.
    - Check if metrics (Total Sales, etc.) match the Dashboard numbers.
3. **Sync Integration**:
    - Perform a manual sync from the Dashboard.
    - Verify "Last Sync Time" in the Profile screen updates after the sync completes.
    - Verify `last_active_time` updates when saving profile changes.
4. **Data Reset**:
    - Click "Reset Data" in the Sync Details screen.
    - Verify all local data (customers, invoices) is cleared.
    - Verify Developer account is re-seeded.
