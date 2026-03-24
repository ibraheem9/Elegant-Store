# Elegant-Store Project Gaps and Required Changes

Based on the documentation provided in `pasted_content.txt` and the analysis of the current Flutter repository, here are the identified gaps and the plan for fixes.

## 1. General Configuration
- [ ] **Language**: Change the app language to Arabic (RTL support).
- [ ] **Currency**: Set the default currency to Shekel (₪).
- [ ] **Localization**: Ensure the UI is fully translated to Arabic.

## 2. Authentication & Users
- [ ] **Login Screen**: 
    - Translate to Arabic.
    - Implement real password validation (currently only checks if username is not empty).
    - Add specific users from docs:
        - Accountants: Hamoda (محمد ياغي), El Daj (محمد عبد الهادي), Ahmed Yaghi (أحمد ياغي).
        - Managers: Ibrahim (إبراهيم عبد الهادي), Hamoda.
- [ ] **User Model**: Ensure roles and names match the requirements.

## 3. Sales & Invoices (Main Screen)
- [ ] **Auto-date**: Automatically insert today's date and day (e.g., 21-03-2026 Saturday).
- [ ] **Buyer/Customer Logic**:
    - Searchable dropdown for existing customers.
    - Show total debt in red if they exist.
    - If name is new, add as a non-permanent customer (cannot buy on credit, must pay next day).
    - Handle "Credit Limit" (سقف الدين) for permanent customers.
    - Notifications/Reminders when near credit limit or overdue.
- [ ] **Payment Methods**:
    - App Payments: Ibrahim, Hamoda, Mahmoud, Ahmed, El Daj, Omar (Dynamic list managed by manager).
    - Cash.
    - Deferred (Debt).

## 4. Daily Statistics
- [ ] **Form/Screen**: 
    - Yesterday's cash in box.
    - Today's cash in box.
    - Calculation for Daily Income: `Today Cash + Today Cash Debt Repayment + Today Cash Purchases - Yesterday Cash - Cash Debt Repayment (Wait, formula in docs: مجموع الكاش بالصندوق اليوم + الدين النقدي اليوم + المشتريات نقدي – الصندوق أمس نقدي – سداد دين نقدي)`.
    - Total Purchases (Cash + App).
    - Total Sales (Cash + App).

## 5. Purchases
- [ ] **Screen**:
    - Supplier name.
    - Amount.
    - Notes.
    - Payment Source (Hamoda App, Ibrahim App, or Box/Cash).
    - Totals for Hamoda/Ibrahim apps.

## 6. Permanent Customers
- [ ] **Management**:
    - Edit customer (Name, Credit Limit).
    - Edit Invoice (Amount, Notes, Payment Method) with edit history.
    - Show last purchases covering the current debt amount.
    - Group by date.

## 7. Payments Review (End of Day)
- [ ] **Screen**:
    - Review bank accounts.
    - Assign each invoice to a specific app (Ibrahim, Hamoda, etc.).
    - Show summary by Day/Date.

## 8. Reports & Stats
- [ ] **Metrics**:
    - Count of permanent vs non-permanent customers.
    - Top buyer.
    - Total Debts (Cash vs App).
    - Total balance for customers.

## 9. Technical Standards
- [ ] Clean Code, SOLID, Modular structure.
- [ ] Database normalization.
- [ ] Input validation and error handling.
- [ ] Professional README.
