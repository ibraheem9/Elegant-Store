# Elegant Store - SQLite Database Schema

This document outlines the complete SQLite database schema used in the Elegant Store Flutter mobile application. The database is designed to support offline-first capabilities with synchronization (`is_synced`, `version`, `uuid` fields) and soft deletes (`deleted_at`).

## Tables

### 1. `users`
Stores all users including store managers, staff, and customers.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Local primary key |
| `uuid` | TEXT | UNIQUE NOT NULL | Global unique identifier for sync |
| `parent_id` | INTEGER | | ID of the parent user (e.g., manager) |
| `username` | TEXT | UNIQUE NOT NULL | Login username |
| `password` | TEXT | NOT NULL | Hashed password |
| `email` | TEXT | | User email address |
| `name` | TEXT | NOT NULL | Full name |
| `nickname` | TEXT | | Optional nickname |
| `role` | TEXT | NOT NULL | User role (e.g., 'MANAGER', 'CUSTOMER') |
| `is_permanent_customer` | INTEGER | DEFAULT 0 | Boolean flag (1 = true, 0 = false) |
| `credit_limit` | REAL | DEFAULT 0.0 | Maximum allowed debt |
| `phone` | TEXT | | Contact phone number |
| `notes` | TEXT | | Additional notes |
| `transfer_names` | TEXT | | Names for money transfers |
| `balance` | REAL | DEFAULT 0.0 | Current account balance (calculated via triggers) |
| `version` | INTEGER | DEFAULT 1 | Record version for sync conflict resolution |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `deleted_at` | TEXT | | Soft delete timestamp |
| `is_synced` | INTEGER | DEFAULT 0 | Sync status flag (1 = synced, 0 = pending) |

### 2. `payment_methods`
Defines available payment methods (e.g., Cash, Credit Card, Bank Transfer).

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Local primary key |
| `uuid` | TEXT | UNIQUE NOT NULL | Global unique identifier |
| `store_manager_id` | INTEGER | | ID of the store manager who owns this |
| `name` | TEXT | NOT NULL | Name of the payment method |
| `type` | TEXT | NOT NULL | Type identifier |
| `category` | TEXT | DEFAULT 'SALE' | Category (e.g., 'SALE', 'PURCHASE') |
| `description` | TEXT | | Optional description |
| `is_active` | INTEGER | DEFAULT 1 | Boolean flag for active status |
| `sort_order` | INTEGER | DEFAULT 0 | Display order |
| `version` | INTEGER | DEFAULT 1 | Record version |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `deleted_at` | TEXT | | Soft delete timestamp |
| `is_synced` | INTEGER | DEFAULT 0 | Sync status flag |

### 3. `invoices`
Records sales invoices and customer debts.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Local primary key |
| `uuid` | TEXT | UNIQUE NOT NULL | Global unique identifier |
| `store_manager_id` | INTEGER | | ID of the store manager |
| `user_id` | INTEGER | NOT NULL, FOREIGN KEY | Reference to `users(id)` (the customer) |
| `invoice_date` | TEXT | NOT NULL | Date of the invoice |
| `amount` | REAL | NOT NULL | Total invoice amount |
| `paid_amount` | REAL | DEFAULT 0.0 | Amount paid so far |
| `payment_method_id` | INTEGER | FOREIGN KEY | Reference to `payment_methods(id)` |
| `payment_status` | TEXT | NOT NULL | Status (e.g., 'PAID', 'UNPAID', 'DEFERRED') |
| `type` | TEXT | DEFAULT 'SALE' | Invoice type |
| `notes` | TEXT | | Additional notes |
| `version` | INTEGER | DEFAULT 1 | Record version |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `deleted_at` | TEXT | | Soft delete timestamp |
| `is_synced` | INTEGER | DEFAULT 0 | Sync status flag |

### 4. `transactions`
Records payments, deposits, and withdrawals.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Local primary key |
| `uuid` | TEXT | UNIQUE NOT NULL | Global unique identifier |
| `store_manager_id` | INTEGER | | ID of the store manager |
| `buyer_id` | INTEGER | NOT NULL, FOREIGN KEY | Reference to `users(id)` |
| `invoice_id` | INTEGER | FOREIGN KEY | Reference to `invoices(id)` (optional) |
| `type` | TEXT | NOT NULL | Transaction type ('DEPOSIT', 'WITHDRAWAL', etc.) |
| `amount` | REAL | NOT NULL | Transaction amount |
| `used_amount` | REAL | DEFAULT 0.0 | Amount applied to invoices |
| `payment_method_id` | INTEGER | FOREIGN KEY | Reference to `payment_methods(id)` |
| `notes` | TEXT | | Additional notes |
| `version` | INTEGER | DEFAULT 1 | Record version |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `deleted_at` | TEXT | | Soft delete timestamp |
| `is_synced` | INTEGER | DEFAULT 0 | Sync status flag |

### 5. `purchases`
Records store expenses and supplier purchases.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Local primary key |
| `uuid` | TEXT | UNIQUE NOT NULL | Global unique identifier |
| `store_manager_id` | INTEGER | | ID of the store manager |
| `merchant_name` | TEXT | NOT NULL | Name of the supplier/merchant |
| `amount` | REAL | NOT NULL | Purchase amount |
| `payment_source` | TEXT | NOT NULL | Source of funds |
| `payment_method_id` | INTEGER | FOREIGN KEY | Reference to `payment_methods(id)` |
| `notes` | TEXT | | Additional notes |
| `version` | INTEGER | DEFAULT 1 | Record version |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `deleted_at` | TEXT | | Soft delete timestamp |
| `is_synced` | INTEGER | DEFAULT 0 | Sync status flag |

### 6. `daily_statistics`
Stores aggregated daily financial summaries.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Local primary key |
| `uuid` | TEXT | UNIQUE NOT NULL | Global unique identifier |
| `store_manager_id` | INTEGER | | ID of the store manager |
| `statistic_date` | TEXT | UNIQUE NOT NULL | Date of the statistics |
| `yesterday_cash_in_box` | REAL | NOT NULL | Cash carried over from yesterday |
| `today_cash_in_box` | REAL | NOT NULL | Current cash in register |
| `total_cash_debt_repayment` | REAL | NOT NULL | Debts paid in cash |
| `total_app_debt_repayment` | REAL | NOT NULL | Debts paid via app/transfer |
| `total_cash_purchases` | REAL | NOT NULL | Purchases paid in cash |
| `total_app_purchases` | REAL | NOT NULL | Purchases paid via app/transfer |
| `total_sales_cash` | REAL | NOT NULL | Cash sales |
| `total_sales_credit` | REAL | NOT NULL | Credit/deferred sales |
| `version` | INTEGER | DEFAULT 1 | Record version |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `deleted_at` | TEXT | | Soft delete timestamp |
| `is_synced` | INTEGER | DEFAULT 0 | Sync status flag |

### 7. `edit_history`
Audit log for tracking changes to records.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Local primary key |
| `uuid` | TEXT | UNIQUE NOT NULL | Global unique identifier |
| `store_manager_id` | INTEGER | | ID of the store manager |
| `edited_by_id` | INTEGER | | ID of the user who made the edit |
| `edited_by_name` | TEXT | | Name of the user who made the edit |
| `target_id` | INTEGER | | ID of the modified record |
| `target_type` | TEXT | | Table/Entity type modified |
| `field_name` | TEXT | | Name of the modified field |
| `old_value` | TEXT | | Previous value |
| `new_value` | TEXT | | New value |
| `edit_reason` | TEXT | | Reason for the edit |
| `version` | INTEGER | DEFAULT 1 | Record version |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `updated_at` | TEXT | NOT NULL | ISO 8601 timestamp |
| `deleted_at` | TEXT | | Soft delete timestamp |
| `is_synced` | INTEGER | DEFAULT 0 | Sync status flag |

### 8. `notifications`
Stores persistent system notifications and alerts.

| Column | Type | Constraints | Description |
| :--- | :--- | :--- | :--- |
| `id` | INTEGER | PRIMARY KEY AUTOINCREMENT | Local primary key |
| `type` | TEXT | NOT NULL | Notification type (e.g., 'debt_limit') |
| `title` | TEXT | NOT NULL | Notification title |
| `body` | TEXT | NOT NULL | Notification content |
| `customer_id` | INTEGER | | Associated customer ID (optional) |
| `customer_name` | TEXT | | Associated customer name (optional) |
| `extra_data` | TEXT | | JSON string with additional data |
| `is_read` | INTEGER | NOT NULL DEFAULT 0 | Read status (1 = read, 0 = unread) |
| `created_at` | TEXT | NOT NULL | ISO 8601 timestamp |

## Database Triggers

The database uses SQLite triggers to automatically maintain the `balance` field in the `users` table based on invoice operations.

### 1. `trg_invoice_insert`
Fires after an `INSERT` on `invoices`.
Updates the user's balance by adding the unpaid amount of a sale/withdrawal, or subtracting for a deposit.

### 2. `trg_invoice_update`
Fires after an `UPDATE` on `invoices`.
Reverses the effect of the old invoice values on the user's balance, and applies the effect of the new invoice values.

### 3. `trg_invoice_delete`
Fires after a `DELETE` on `invoices`.
Reverses the effect of the deleted invoice on the user's balance.

## Performance Indexes

To optimize query performance, the following indexes are created:

- **invoices**: `user_id`, `created_at`, `deleted_at`, `payment_status`, `type`, `payment_method_id`
- **users**: `role`, `deleted_at`
- **transactions**: `buyer_id`, `invoice_id`, `deleted_at`
- **purchases**: `created_at`, `payment_method_id`, `deleted_at`
- **edit_history**: `target_id`, `target_type`
- **daily_statistics**: `statistic_date`
