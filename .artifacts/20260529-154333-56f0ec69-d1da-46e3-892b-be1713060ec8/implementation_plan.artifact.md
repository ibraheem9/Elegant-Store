# Make Sidebar Fully Scrollable

The goal is to make the entire sidebar (aside) scrollable as a single unit, removing the fixed footer (User Card) and ensuring that all items, including settings and logout, scroll together if the content exceeds the screen height.

## Proposed Changes

### [Screens]

#### [dashboard_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/dashboard_screen.dart)

- **Consolidate `_buildFullSidebar`**:
    - Remove the `Column` and `Expanded` wrapper.
    - Replace the middle `ListView` with a single `ListView` that wraps all content (Header, Main Items, Settings Items, Divider, and User Card).
    - Adjust padding to maintain consistent layout.

- **Consolidate `_buildMobileDrawer`**:
    - Apply the same logic to the `Drawer` content to ensure consistency across mobile and desktop.
    - Remove `Expanded` and the fixed `SafeArea` at the bottom, moving `_buildUserCard` inside the scrollable list.

---

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure no syntax errors.

### Manual Verification
1.  **Sidebar Scrolling**: Reduce the window height until the sidebar items overflow. Verify that the entire sidebar (including the logo at the top and the user card at the bottom) scrolls together.
2.  **User Card Visibility**: Verify that the user card is reachable at the end of the scrollable list.
3.  **Mobile Drawer**: Open the drawer on mobile (or small window) and verify it is also fully scrollable.
4.  **Layout Consistency**: Ensure the width and horizontal alignment of items remain correct after switching to a single `ListView`.
