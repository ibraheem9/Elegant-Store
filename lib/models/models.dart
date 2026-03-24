import 'package:intl/intl.dart';

// User Model
class User {
  final int? id;
  final String username;
  final String email;
  final String name;
  final String role; // 'accountant', 'manager', 'customer'
  final int isPermanentCustomer; // 0 for no, 1 for yes
  final double? creditLimit;
  final String createdAt;

  User({
    this.id,
    required this.username,
    required this.email,
    required this.name,
    required this.role,
    this.isPermanentCustomer = 0,
    this.creditLimit,
    required this.createdAt,
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
      'created_at': createdAt,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'],
      email: map['email'],
      name: map['name'],
      role: map['role'],
      isPermanentCustomer: map['is_permanent_customer'] ?? 0,
      creditLimit: map['credit_limit']?.toDouble(),
      createdAt: map['created_at'],
    );
  }
}

// Payment Method Model
class PaymentMethod {
  final int? id;
  final String name;
  final String type; // 'cash', 'app', 'deferred'
  final String? description;
  final int isActive;

  PaymentMethod({
    this.id,
    required this.name,
    required this.type,
    this.description,
    this.isActive = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'description': description,
      'is_active': isActive,
    };
  }

  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    return PaymentMethod(
      id: map['id'],
      name: map['name'],
      type: map['type'],
      description: map['description'],
      isActive: map['is_active'] ?? 1,
    );
  }
}

// Invoice Model
class Invoice {
  final int? id;
  final int userId;
  final String invoiceDate; // Format: 21-03-2026 Saturday
  final double amount;
  final String? notes;
  final String paymentStatus; // 'pending', 'paid'
  final int? paymentMethodId;
  final String createdAt;
  final String? updatedAt;
  final String? editHistory;

  Invoice({
    this.id,
    required this.userId,
    required this.invoiceDate,
    required this.amount,
    this.notes,
    required this.paymentStatus,
    this.paymentMethodId,
    required this.createdAt,
    this.updatedAt,
    this.editHistory,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'invoice_date': invoiceDate,
      'amount': amount,
      'notes': notes,
      'payment_status': paymentStatus,
      'payment_method_id': paymentMethodId,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'edit_history': editHistory,
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      userId: map['user_id'],
      invoiceDate: map['invoice_date'],
      amount: map['amount']?.toDouble() ?? 0.0,
      notes: map['notes'],
      paymentStatus: map['payment_status'],
      paymentMethodId: map['payment_method_id'],
      createdAt: map['created_at'],
      updatedAt: map['updated_at'],
      editHistory: map['edit_history'],
    );
  }
}

// Purchase Model
class Purchase {
  final int? id;
  final String supplier;
  final double amount;
  final int? paymentMethodId; // Links to app (Ibrahim, Hamoda) or Cash
  final String purchaseDate;
  final String? notes;
  final String createdAt;

  Purchase({
    this.id,
    required this.supplier,
    required this.amount,
    this.paymentMethodId,
    required this.purchaseDate,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier': supplier,
      'amount': amount,
      'payment_method_id': paymentMethodId,
      'purchase_date': purchaseDate,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory Purchase.fromMap(Map<String, dynamic> map) {
    return Purchase(
      id: map['id'],
      supplier: map['supplier'],
      amount: map['amount']?.toDouble() ?? 0.0,
      paymentMethodId: map['payment_method_id'],
      purchaseDate: map['purchase_date'],
      notes: map['notes'],
      createdAt: map['created_at'],
    );
  }
}

// Daily Statistics Model
class DailyStatistics {
  final int? id;
  final String statisticDate;
  final double yesterdayCashInBox;
  final double todayCashInBox;
  final double totalCashDebtRepayment;
  final double totalAppDebtRepayment;
  final double totalCashPurchases;
  final double totalAppPurchases;
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
    required this.createdAt,
  });

  // Calculated fields based on docs formula
  // دخل اليوم بالشيكل = مجموع الكاش بالصندوق اليوم + الدين النقدي اليوم + المشتريات نقدي – الصندوق أمس نقدي – سداد دين نقدي
  // Note: The formula in docs is slightly confusing. Let's stick to providing the raw values and calculate in UI/Service.
  
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
      'created_at': createdAt,
    };
  }

  factory DailyStatistics.fromMap(Map<String, dynamic> map) {
    return DailyStatistics(
      id: map['id'],
      statisticDate: map['statistic_date'],
      yesterdayCashInBox: map['yesterday_cash_in_box']?.toDouble() ?? 0.0,
      todayCashInBox: map['today_cash_in_box']?.toDouble() ?? 0.0,
      totalCashDebtRepayment: map['total_cash_debt_repayment']?.toDouble() ?? 0.0,
      totalAppDebtRepayment: map['total_app_debt_repayment']?.toDouble() ?? 0.0,
      totalCashPurchases: map['total_cash_purchases']?.toDouble() ?? 0.0,
      totalAppPurchases: map['total_app_purchases']?.toDouble() ?? 0.0,
      createdAt: map['created_at'],
    );
  }
}

// Customer Payment Model
class CustomerPayment {
  final int? id;
  final int userId;
  final int? invoiceId;
  final double amount;
  final int? paymentMethodId;
  final String paymentDate;
  final String createdAt;

  CustomerPayment({
    this.id,
    required this.userId,
    this.invoiceId,
    required this.amount,
    this.paymentMethodId,
    required this.paymentDate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'invoice_id': invoiceId,
      'amount': amount,
      'payment_method_id': paymentMethodId,
      'payment_date': paymentDate,
      'created_at': createdAt,
    };
  }

  factory CustomerPayment.fromMap(Map<String, dynamic> map) {
    return CustomerPayment(
      id: map['id'],
      userId: map['user_id'],
      invoiceId: map['invoice_id'],
      amount: map['amount']?.toDouble() ?? 0.0,
      paymentMethodId: map['payment_method_id'],
      paymentDate: map['payment_date'],
      createdAt: map['created_at'],
    );
  }
}
