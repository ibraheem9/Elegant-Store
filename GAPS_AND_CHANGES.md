# Elegant-Store Project Gaps and Required Changes

Based on the documentation provided in `pasted_content.txt` and the analysis of the current Flutter repository, here are the identified gaps and the plan for fixes.

## 1. General Configuration
- [x] **Language**: Change the app language to Arabic (RTL support).
- [x] **Currency**: Set the default currency to Shekel (₪).
- [x] **Localization**: Ensure the UI is fully translated to Arabic.

## 2. Authentication & Users
- [x] **Login Screen**: 
    - Translate to Arabic.
    - Implement real password validation.
    - Add specific users from docs.
- [x] **User Model**: Ensure roles and names match the requirements.

## 3. Sales & Invoices (Main Screen)
- [x] **Auto-date**: Automatically insert today's date and day.
- [x] **Buyer/Customer Logic**:
    - Searchable dropdown for existing customers.
    - Show total debt in red if they exist.
    - Handle "Credit Limit" (سقف الدين) for permanent customers.
- [x] **Payment Methods**:
    - App Payments (Dynamic list managed by manager).
    - Cash.
    - Deferred (Debt).

## 4. Daily Statistics
- [x] **Form/Screen**: 
    - Yesterday's cash in box.
    - Today's cash in box.
    - Calculation for Daily Income.
    - Total Purchases (Cash + App).
    - Total Sales (Cash + App).

## 5. Purchases
- [x] **Screen**:
    - Supplier name.
    - Amount.
    - Notes.
    - Payment Source.

## 6. Permanent Customers
- [x] **Management**:
    - Edit customer (Name, Credit Limit).
    - Edit Invoice with edit history.
    - Group by date.

## 7. Payments Review (End of Day)
- [x] **Screen**:
    - Review bank accounts.
    - Assign each invoice to a specific app.

## 8. Reports & Stats
- [x] **Metrics**:
    - Count of permanent vs non-permanent customers.
    - Total Debts (Cash vs App).
    - Total balance for customers.
- [-] **Analytical Reports**: (Removed per user request)

## 9. Technical Standards
- [x] Clean Code, SOLID, Modular structure.
- [x] Database normalization.
- [x] Input validation and error handling.
- [x] Professional README.
