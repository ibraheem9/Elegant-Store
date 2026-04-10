import 'package:intl/intl.dart';

// User Model
class User {
  final int? id;
  final String username;
  final String? email;
  final String name;
  final String? nickname; 
  final String role; 
  final int isPermanentCustomer; 
  final double? creditLimit; 
  final String? phone;
  final String? notes; 
  final String? transferNames; 
  final double balance; 
  final String createdAt;
  final String? deletedAt;

  User({
    this.id,
    required this.username,
    this.email,
    required this.name,
    this.nickname,
    required this.role,
    this.isPermanentCustomer = 0,
    this.creditLimit = 0.0,
    this.phone,
    this.notes,
    this.transferNames,
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
      'nickname': nickname,
      'role': role,
      'is_permanent_customer': isPermanentCustomer,
      'credit_limit': creditLimit,
      'phone': phone,
      'notes': notes,
      'transfer_names': transferNames,
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
      nickname: map['nickname'],
      role: map['role'] ?? 'CUSTOMER',
      isPermanentCustomer: map['is_permanent_customer'] ?? 0,
      creditLimit: map['credit_limit']?.toDouble() ?? 0.0,
      phone: map['phone'],
      notes: map['notes'],
      transferNames: map['transfer_names'],
      balance: map['balance']?.toDouble() ?? 0.0,
      createdAt: map['created_at'] ?? '',
      deletedAt: map['deleted_at'],
    );
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is User && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

// Payment Method Model
class PaymentMethod {
  final int? id;
  final String name;
  final String type; 
  final String category; 
  final String? description;
  final int isActive;
  final int sortOrder;

  PaymentMethod({
    this.id,
    required this.name,
    required this.type,
    this.category = 'SALE',
    this.description,
    this.isActive = 1,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'category': category,
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
      category: map['category'] ?? 'SALE',
      description: map['description'],
      isActive: map['is_active'] ?? 1,
      sortOrder: map['sort_order'] ?? 0,
    );
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is PaymentMethod && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;

  PaymentMethod copyWith({int? sortOrder}) {
    return PaymentMethod(
      id: id,
      name: name,
      type: type,
      category: category,
      description: description,
      isActive: isActive,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

// Invoice Model
class Invoice {
  final int? id;
  final int userId; 
  final String invoiceDate;
  final double amount;
  final double paidAmount; 
  final int? paymentMethodId;
  final String paymentStatus; 
  final String type; 
  final String? notes;
  final String createdAt;
  final String? updatedAt;
  final String? deletedAt;

  final String? customerName;
  final String? customerPhone;
  final String? methodName;

  Invoice({
    this.id,
    required this.userId,
    required this.invoiceDate,
    required this.amount,
    this.paidAmount = 0.0,
    this.paymentMethodId,
    required this.paymentStatus,
    this.type = 'SALE',
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
      'paid_amount': paidAmount,
      'payment_method_id': paymentMethodId,
      'payment_status': paymentStatus,
      'type': type,
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
      paidAmount: map['paid_amount']?.toDouble() ?? 0.0,
      paymentMethodId: map['payment_method_id'],
      paymentStatus: map['payment_status'] ?? 'UNPAID',
      type: map['type'] ?? 'SALE',
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

// Transaction Model
class FinancialTransaction {
  final int? id;
  final int buyerId;
  final int? invoiceId;
  final String type; 
  final double amount;
  final double usedAmount; 
  final int? paymentMethodId; 
  final String? notes; 
  final String createdAt;
  final String? methodName;

  FinancialTransaction({
    this.id,
    required this.buyerId,
    this.invoiceId,
    required this.type,
    required this.amount,
    this.usedAmount = 0.0,
    this.paymentMethodId,
    this.notes,
    required this.createdAt,
    this.methodName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buyer_id': buyerId,
      'invoice_id': invoiceId,
      'type': type,
      'amount': amount,
      'used_amount': usedAmount,
      'payment_method_id': paymentMethodId,
      'notes': notes,
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
      usedAmount: map['used_amount']?.toDouble() ?? 0.0,
      paymentMethodId: map['payment_method_id'],
      notes: map['notes'],
      createdAt: map['created_at'] ?? '',
      methodName: map['method_name'],
    );
  }
}

// Purchase Model
class Purchase {
  final int? id;
  final String merchantName;
  final double amount;
  final String paymentSource; 
  final int? paymentMethodId;
  final String? notes;
  final String createdAt;
  final String? updatedAt;
  final String? deletedAt;
  final String? methodName;

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
    this.methodName,
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
      methodName: map['method_name'],
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
