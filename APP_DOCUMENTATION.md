# Elegant Store - Documentation

## 📱 App Overview
Elegant Store is a comprehensive management and accounting solution designed for retail businesses. It focuses on tracking sales, customer debts, purchases, and providing detailed daily financial insights.

---

## 🔑 Authentication & Roles
- **SUPER_ADMIN**: Full system control, data resets, and configuration.
- **ACCOUNTANT**: Handles daily operations (sales, purchases, reports).
- **DEVELOPER**: Technical maintenance and debugging.

---

## 🛠 Core Functionalities

### 1. Sales Management
- **Invoicing**: Supports Cash, App, and Debt payments.
- **Auto-Credit Logic**: If a customer has a pre-paid balance (credit), the system automatically deducts the invoice amount from that credit before creating new debt.
- **Invoice Types**:
  - `SALE`: Regular product sale.
  - `WITHDRAWAL`: When a customer takes cash from the store as a loan/debt.
  - `DEPOSIT`: When a customer pays in advance.

### 2. Customer Debt Tracking
- **Balance Calculation**: `(Total Unpaid Invoices + Withdrawals) - (Total Deposits/Pre-payments)`.
- **Credit Limits**: Set maximum debt allowed per customer. The app triggers alerts when debt reaches 90% of this limit.
- **Permanent Status**: Flags regular customers for prioritized reporting.

### 3. Financial Transactions
- **Bulk Debt Repayment**: Payments are automatically distributed to the oldest unpaid invoices first.
- **Transaction Logs**: Every payment or deposit is logged with a timestamp and payment method.

### 4. Expense & Purchase Tracking
- Logs purchases from merchants.
- Categorizes expenses by source: `CASH` (drawer) or `APP` (digital transfer).

### 5. Daily Statistics
- Tracks "Cash in Box" from yesterday to today.
- Summarizes daily sales, debt collections, and outgoing expenses.

---

## 📋 Logic & Conditions

### Invoice Processing Logic
1. **Check Customer Balance**: If `balance < 0` (customer has credit), use credit to pay the invoice.
2. **Determine Status**:
   - If `Paid Amount >= Invoice Amount` -> Status = `PAID`.
   - If `Paid Amount > 0` and `< Invoice Amount` -> Status = `PARTIAL`.
   - If `Paid Amount == 0` -> Status = `UNPAID`.
3. **Update Debt**: Any remaining unpaid amount is added to `users.balance`.

### Notification Conditions
- Triggered daily if:
  - There are invoices marked as `UNPAID`.
  - Any customer is within 10% of their `credit_limit`.

### Data Integrity (Audit Trail)
- **Edit History**: Changes to financial records (Invoices) are logged with:
  - Field changed (e.g., amount, notes).
  - Old value vs. New value.
  - Reason for edit.

---

## 🗄 Database Schema (Highlights)
- `users`: Stores admins and customers (with balances).
- `invoices`: Main sales and withdrawal records.
- `transactions`: Records of payments and deposits.
- `purchases`: Outgoing store expenses.
- `daily_statistics`: Aggregated daily financial snapshots.
- `edit_history`: Audit logs for changes.
- `payment_methods`: Configurable payment options for sales and purchases.

---

## 🎨 User Interface
- **Responsive Design**: Supports Mobile (Bottom Nav), Tablet (Navigation Rail), and Desktop (Full Sidebar).
- **Theming**: Dynamic Light and Dark modes.
- **Localization**: Full RTL (Right-to-Left) Arabic support.
