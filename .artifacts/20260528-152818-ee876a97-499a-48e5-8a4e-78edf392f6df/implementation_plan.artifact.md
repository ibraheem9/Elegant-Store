# Fix Store Profile Screen and Sidebar Disappearance on Resize

The goal is to fix the behavior of the "Store Profile" screen (`ProfileScreen`) and resolve the issue where the sidebar disappears upon minimizing/maximizing (resizing) the window.

## Root Cause Analysis
1.  **Index Mismatch**: The `NavigationRail` (used for tablet widths) has a conditional "Manage Accountants" item. The indexing logic in `getRailIndex` and `onDestinationSelected` did not account for this shift when the user is not a manager. This causes the dashboard to enter an invalid navigation state upon resize.
2.  **Parent Scaffold Interference**: While `ProfileScreen` now returns a `Scaffold`, having a `Scaffold` inside another `Scaffold` (in `DashboardScreen`) can sometimes cause layout issues or hide the parent's sidebar if not handled carefully, especially during transitions.

## Proposed Changes

### [Screens]

#### [dashboard_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/dashboard_screen.dart)

- **Fix Navigation Rail Indexing**: Update `getRailIndex` and `onDestinationSelected` to dynamically handle the optional "Manage Accountants" item (index 5) so that all subsequent indices (6, 9, 10, 11, 12, 13, 14, 15) map correctly regardless of the user's role.
- **Ensure Consistent Layout**: Verify that the `Expanded` column containing the app bar and screen content correctly maintains its position during width transitions.

#### [profile_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/profile_screen.dart)

- **Remove Inner Scaffold**: To perfectly match `SettingsScreen.dart`, I will remove the `Scaffold` from `ProfileScreen`. `SettingsScreen` returns a `Scaffold` but its background is set to `Colors.transparent` when in dark mode or a specific color in light mode, and it is hosted within the `DashboardScreen`'s `body` Row.
- **Align Background Logic**: Ensure `ProfileScreen` uses the exact same background and container constraints as `SettingsScreen`.

```diff
// profile_screen.dart
-    return Scaffold(
-      backgroundColor: isDark ? Colors.transparent : const Color(0xFFF1F5F9),
-      body: Center(
+    return Center(
        child: Container(
          // ...
        ),
-      ),
-    );
```

---

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure no syntax errors.

### Manual Verification
1.  **Sidebar Persistence**: Log in as a non-manager accountant. Go to "Store Profile". Resize the window (minimize/maximize). Verify the sidebar (or rail) remains visible.
2.  **Navigation Accuracy**: Verify that clicking "Store Profile" in the sidebar correctly highlights the icon in the navigation rail when resizing to tablet width.
3.  **UI Consistency**: Verify that "Store Profile" and "Settings" screens look identical in terms of layout and background.
