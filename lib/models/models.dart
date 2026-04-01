import 'package:intl/intl.dart';

// User Model (Blueprint 3.1 & 3.2)
class User {
  final int? id;
  final String username;
  final String? email;
  final String name;
  final String role; // SUPER_ADMIN, ACCOUNTANT, CUSTOMER
  final int isPermanentCustomer; // 0 for NON_PERMANENT, 1 for PERMANENT
  final double? creditLimit; // debt_limit in blueprint
  final String? phone;
  final String? notes;
  final double balance; // Positive = Credit, Negative = Debt (Blueprint 6.2)
  final String createdAt;
  final String? deletedAt;

  User({
    this.id,
    required this.username,
    this.email,
    required this.name,
    required this.role,
    this.isPermanentCustomer = 0,
    this.creditLimit = 0.0,
    this.phone,
    this.notes,
    this.balance = 0.0,
    required this.createdAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'name': name,
      'role': role,
      'is_permanent_customer': isPermanentCustomer,
      'credit_limit': creditLimit,
      'phone': phone,
      'notes': notes,
      'balance': balance,
      'created_at': createdAt,
      'deleted_at': deletedAt,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'] ?? '',
      email: map['email'],
      name: map['name'] ?? '',
      role: map['role'] ?? 'CUSTOMER',
      isPermanentCustomer: map['is_permanent_customer'] ?? 0,
      creditLimit: map['credit_limit']?.toDouble() ?? 0.0,
      phone: map['phone'],
      notes: map['notes'],
      balance: map['balance']?.toDouble() ?? 0.0,
      createdAt: map['created_at'] ?? '',
      deletedAt: map['deleted_at'],
    );
  }
}

// Payment Method Model (Blueprint 3.3)
class PaymentMethod {
  final int? id;
  final String name;
  final String type; // cash, app, deferred, credit_balance, unpaid
  final String? description;
  final int isActive;
  final int sortOrder;

  PaymentMethod({
    this.id,
    required this.name,
    required this.type,
    this.description,
    this.isActive = 1,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'description': description,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }

  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    return PaymentMethod(
      id: map['id'],
      name: map['name'] ?? '',
      type: map['type'] ?? '',
      description: map['description'],
      isActive: map['is_active'] ?? 1,
      sortOrder: map['sort_order'] ?? 0,
    );
  }

  PaymentMethod copyWith({int? sortOrder}) {
    return PaymentMethod(
      id: id,
      name: name,
      type: type,
      description: description,
      isActive: isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

// Invoice Model (Blueprint 3.4)
class Invoice {
  final int? id;
  final int userId; // buyer_id
  final String invoiceDate;
  final double amount;
  final int? paymentMethodId;
  final String paymentStatus; // PAID, UNPAID
  final String? notes;
  final String createdAt;
  final String? updatedAt;
  final String? deletedAt;

  // Virtual fields for joined queries
  final String? customerName;
  final String? customerPhone;
  final String? methodName;

  Invoice({
    this.id,
    required this.userId,
    required this.invoiceDate,
    required this.amount,
    this.paymentMethodId,
    required this.paymentStatus,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.customerName,
    this.customerPhone,
    this.methodName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'invoice_date': invoiceDate,
      'amount': amount,
      'payment_method_id': paymentMethodId,
      'payment_status': paymentStatus,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      userId: map['user_id'] ?? 0,
      invoiceDate: map['invoice_date'] ?? '',
      amount: map['amount']?.toDouble() ?? 0.0,
      paymentMethodId: map['payment_method_id'],
      paymentStatus: map['payment_status'] ?? 'UNPAID',
      notes: map['notes'],
      createdAt: map['created_at'] ?? '',
      updatedAt: map['updated_at'],
      deletedAt: map['deleted_at'],
      customerName: map['customer_name'],
      customerPhone: map['phone'],
      methodName: map['method_name'],
    );
  }
}

// Transaction Model (Blueprint 3.5)
class FinancialTransaction {
  final int? id;
  final int buyerId;
  final int? invoiceId;
  final String type; // INVOICE_CHARGE, DEBT_PAYMENT, DEPOSIT
  final double amount;
  final String createdAt;

  FinancialTransaction({
    this.id,
    required this.buyerId,
    this.invoiceId,
    required this.type,
    required this.amount,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buyer_id': buyerId,
      'invoice_id': invoiceId,
      'type': type,
      'amount': amount,
      'created_at': createdAt,
    };
  }

  factory FinancialTransaction.fromMap(Map<String, dynamic> map) {
    return FinancialTransaction(
      id: map['id'],
      buyerId: map['buyer_id'] ?? 0,
      invoiceId: map['invoice_id'],
      type: map['type'] ?? '',
      amount: map['amount']?.toDouble() ?? 0.0,
      createdAt: map['created_at'] ?? '',
    );
  }
}

// Purchase Model (Blueprint 3.6)
class Purchase {
  final int? id;
  final String merchantName;
  final double amount;
  final String paymentSource; // CASH, APP
  final int? paymentMethodId;
  final String? notes;
  final String createdAt;
  final String? updatedAt;
  final String? deletedAt;

  Purchase({
    this.id,
    required this.merchantName,
    required this.amount,
    required this.paymentSource,
    this.paymentMethodId,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'merchant_name': merchantName,
      'amount': amount,
      'payment_source': paymentSource,
      'payment_method_id': paymentMethodId,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };
  }

  factory Purchase.fromMap(Map<String, dynamic> map) {
    return Purchase(
      id: map['id'],
      merchantName: map['merchant_name'] ?? '',
      amount: map['amount']?.toDouble() ?? 0.0,
      paymentSource: map['payment_source'] ?? 'CASH',
      paymentMethodId: map['payment_method_id'],
      notes: map['notes'],
      createdAt: map['created_at'] ?? '',
      updatedAt: map['updated_at'],
      deletedAt: map['deleted_at'],
    );
  }
}

// Daily Statistics Model (Blueprint 5.7)
class DailyStatistics {
  final int? id;
  final String statisticDate;
  final double yesterdayCashInBox;
  final double todayCashInBox;
  final double totalCashDebtRepayment;
  final double totalAppDebtRepayment;
  final double totalCashPurchases;
  final double totalAppPurchases;
  final double totalSalesCash;
  final double totalSalesCredit;
  final String createdAt;

  DailyStatistics({
    this.id,
    required this.statisticDate,
    required this.yesterdayCashInBox,
    required this.todayCashInBox,
    required this.totalCashDebtRepayment,
    required this.totalAppDebtRepayment,
    required this.totalCashPurchases,
    required this.totalAppPurchases,
    this.totalSalesCash = 0.0,
    this.totalSalesCredit = 0.0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'statistic_date': statisticDate,
      'yesterday_cash_in_box': yesterdayCashInBox,
      'today_cash_in_box': todayCashInBox,
      'total_cash_debt_repayment': totalCashDebtRepayment,
      'total_app_debt_repayment': totalAppDebtRepayment,
      'total_cash_purchases': totalCashPurchases,
      'total_app_purchases': totalAppPurchases,
      'total_sales_cash': totalSalesCash,
      'total_sales_credit': totalSalesCredit,
      'created_at': createdAt,
    };
  }

  factory DailyStatistics.fromMap(Map<String, dynamic> map) {
    return DailyStatistics(
      id: map['id'],
      statisticDate: map['statistic_date'] ?? '',
      yesterdayCashInBox: map['yesterday_cash_in_box']?.toDouble() ?? 0.0,
      todayCashInBox: map['today_cash_in_box']?.toDouble() ?? 0.0,
      totalCashDebtRepayment: map['total_cash_debt_repayment']?.toDouble() ?? 0.0,
      totalAppDebtRepayment: map['total_app_debt_repayment']?.toDouble() ?? 0.0,
      totalCashPurchases: map['total_cash_purchases']?.toDouble() ?? 0.0,
      totalAppPurchases: map['total_app_purchases']?.toDouble() ?? 0.0,
      totalSalesCash: map['total_sales_cash']?.toDouble() ?? 0.0,
      totalSalesCredit: map['total_sales_credit']?.toDouble() ?? 0.0,
      createdAt: map['created_at'] ?? '',
    );
  }
}
