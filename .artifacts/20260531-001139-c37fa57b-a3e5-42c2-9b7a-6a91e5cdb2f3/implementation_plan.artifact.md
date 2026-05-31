# Fix Sidebar Bottom Margin and Layout

The goal is to fix the bottom margin for the "aside" (sidebar) in the mobile and desktop designs, ensuring it looks consistent and handles safe areas properly on mobile devices.

## Root Cause Analysis
1.  **Layout Logic**: The current sidebar/drawer uses a `ListView` where all items (including the user card) are children. This causes the user card to follow the list content instead of staying at the bottom of the screen.
2.  **Missing Safe Area**: The `Drawer` and `FullSidebar` do not explicitly handle the bottom `SafeArea`, which can lead to layout issues on devices with navigation bars or notches.
3.  **Inconsistent Padding**: The use of hardcoded `SizedBox(height: 20)` at the bottom of the list creates an inconsistent gap that may look like a bug depending on the screen height.

## Proposed Changes

### [Screens]

#### [dashboard_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/dashboard_screen.dart)

- **Refactor `_buildMobileDrawer`**:
    - Change from `ListView` to `Column` containing an `Expanded` `ListView`.
    - This ensures the user card (`_buildUserCard`) is always at the bottom of the drawer.
    - Add `SafeArea` at the bottom to handle device navigation bars.
- **Refactor `_buildFullSidebar`**:
    - Apply the same `Column` + `Expanded` `ListView` logic to keep the user card at the bottom.
- **Update `_buildUserCard`**:
    - Adjust margins to be more consistent with the new `Column` layout.

```dart
// Example of the new structure for _buildMobileDrawer
Widget _buildMobileDrawer(bool isDark, AuthService auth) {
  return Drawer(
    backgroundColor: const Color(0xFF0F172A),
    child: Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 60),
              // ... menu items ...
            ],
          ),
        ),
        _buildUserCard(true, isDark),
        const SafeArea(top: false, child: SizedBox(height: 10)),
      ],
    ),
  );
}
```

---

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure no syntax errors.

### Manual Verification
1.  **Mobile Drawer**: Open the drawer on a mobile device (or emulator). Verify that the user card is at the bottom and there is a proper margin from the system navigation bar.
2.  **Desktop Sidebar**: Resize the window to desktop width. Verify that the sidebar fills the height and the user card is at the bottom.
3.  **Scroll Behavior**: Ensure the menu items are still scrollable when they exceed the available height, while the user card remains fixed at the bottom.
