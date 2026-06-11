# WhatsApp Number Input with Country Code Dropdown

This plan outlines the changes to force users to choose between `+970` or `+972` for their **WhatsApp** numbers using a dropdown. This will be implemented using a reusable widget and applied to all relevant screens.

## User Review Required

> [!IMPORTANT]
> - The dropdown will be added **ONLY** to the WhatsApp field.
> - The WhatsApp number will be stored as a combination of the selected country code and the number entered (e.g., `+970597228389`).
> - The validator will accept 9 digits (e.g., `597228389`). If the user enters 10 digits (e.g., `0597228389`), the leading `0` will be stripped.

## Proposed Changes

### Shared Widgets

#### [NEW] [whatsapp_input.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/widgets/whatsapp_input.dart)

- Create a new reusable widget `WhatsAppInput` that contains:
    - A dropdown for country codes (`+970`, `+972`).
    - A `TextFormField` for the rest of the number.
- Handle `Directionality` to ensure the phone number is displayed LTR even in RTL mode.
- Support `onChanged` and `initialValue` for easy integration.

---

### Screens

#### [profile_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/profile_screen.dart)

- Add `_whatsappCountryCode` state variable.
- Update `_loadData` to split the existing `whatsapp` string into the code and the number part.
- Replace the WhatsApp `TextFormField` with the new `WhatsAppInput`.
- Update `_saveProfile` to join the code and number before saving.

#### [store_profile_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/store_profile_screen.dart)

- Replace the manual dropdown/textfield implementation with the new `WhatsAppInput` widget.

#### [profile_setup_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/profile_setup_screen.dart)

- Replace the manual dropdown/textfield implementation with the new `WhatsAppInput` widget.

## Verification Plan

### Automated Tests
- Run `analyze_file` on all modified files to ensure no syntax errors.

### Manual Verification
1. Open the **Store Profile** screen.
2. Verify that the WhatsApp field has a dropdown with `+970` and `+972`.
3. Enter a number (e.g., `597228389`) and save.
4. Refresh/Re-open the screen and verify the number is loaded correctly with the selected code.
5. Repeat for **Profile Setup** and the main **Profile** screen.
