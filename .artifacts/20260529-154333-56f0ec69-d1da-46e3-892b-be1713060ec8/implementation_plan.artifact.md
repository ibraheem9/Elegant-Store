# Add Field Validation to Store Profile Screen

The goal is to implement validation rules for the fields in the "Store Profile" screen (`ProfileScreen`), ensuring data integrity and following specific Palestinian (Gaza) mobile number constraints.

## Proposed Changes

### [Screens]

#### [profile_screen.dart](file:///D:/Work/2026/Hamoda/Store_System/Elegant-Store/lib/screens/profile_screen.dart)

- **Update `_buildTextField`**:
    - Add a `String? Function(String?)? validator` parameter to the helper method.
    - Pass this validator to the internal `TextFormField`.

- **Implement Validation Logic**:
    - **Store Name**: Required field.
    - **Owner Name**: Required field.
    - **Address**: Required field.
    - **City**: Required field.
    - **Phone Number (Mobile)**: Required, must start with `059` or `056` and be exactly 10 digits long.
    - **WhatsApp**: Required, must follow the same Palestinian mobile format.

- **Regex for Phone Validation**: `^(059|056)[0-9]{7}$`

- **Error Messages (Arabic)**:
    - Empty field: `يرجى إدخال [اسم الحقل]`
    - Invalid phone: `رقم غير صحيح (يجب أن يبدأ بـ 059 أو 056 ويتكون من 10 أرقام)`

---

## Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure no syntax errors.

### Manual Verification
1.  **Empty Field Test**: Clear one of the required fields and click "Save Changes". Verify that an error message appears in red.
2.  **Invalid Phone Test**: Enter a number that doesn't start with 059/056 or is too short/long. Verify the specific phone error message appears.
3.  **Valid Data Test**: Enter valid Palestinian numbers and fill all fields. Verify that the "Save Changes" succeeds and shows the success snackbar.
4.  **Layout Check**: Ensure that error messages don't break the layout of the responsive grid.
