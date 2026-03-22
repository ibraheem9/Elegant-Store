import 'package:json_annotation/json_annotation.dart';

part 'models.g.dart';

// User Model
@JsonSerializable()
class User {
  final int? id;
  final String username;
  final String email;
  final String name;
  final String role;
  final int isPermanentCustomer;
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

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

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
      creditLimit: map['credit_limit'],
      createdAt: map['created_at'],
    );
  }
}

// Payment Method Model
@JsonSerializable()
class PaymentMethod {
  final int? id;
  final String name;
  final String type;
  final String? description;
  final int isActive;

  PaymentMethod({
    this.id,
    required this.name,
    required this.type,
    this.description,
    this.isActive = 1,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) =>
      _$PaymentMethodFromJson(json);
  Map<String, dynamic> toJson() => _$PaymentMethodToJson(this);

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
@JsonSerializable()
class Invoice {
  final int? id;
  final int userId;
  final String invoiceDate;
  final double amount;
  final String? notes;
  final String paymentStatus;
  final int? paymentMethodId;
  final String createdAt;

  Invoice({
    this.id,
    required this.userId,
    required this.invoiceDate,
    required this.amount,
    this.notes,
    required this.paymentStatus,
    this.paymentMethodId,
    required this.createdAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) =>
      _$InvoiceFromJson(json);
  Map<String, dynamic> toJson() => _$InvoiceToJson(this);

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
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      userId: map['user_id'],
      invoiceDate: map['invoice_date'],
      amount: map['amount'],
      notes: map['notes'],
      paymentStatus: map['payment_status'],
      paymentMethodId: map['payment_method_id'],
      createdAt: map['created_at'],
    );
  }
}

// Purchase Model
@JsonSerializable()
class Purchase {
  final int? id;
  final String supplier;
  final double amount;
  final int? paymentMethodId;
  final String purchaseDate;
  final String createdAt;

  Purchase({
    this.id,
    required this.supplier,
    required this.amount,
    this.paymentMethodId,
    required this.purchaseDate,
    required this.createdAt,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) =>
      _$PurchaseFromJson(json);
  Map<String, dynamic> toJson() => _$PurchaseToJson(this);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier': supplier,
      'amount': amount,
      'payment_method_id': paymentMethodId,
      'purchase_date': purchaseDate,
      'created_at': createdAt,
    };
  }

  factory Purchase.fromMap(Map<String, dynamic> map) {
    return Purchase(
      id: map['id'],
      supplier: map['supplier'],
      amount: map['amount'],
      paymentMethodId: map['payment_method_id'],
      purchaseDate: map['purchase_date'],
      createdAt: map['created_at'],
    );
  }
}

// Daily Statistics Model
@JsonSerializable()
class DailyStatistics {
  final int? id;
  final String statisticDate;
  final double yesterdayCashInBox;
  final double todayCashInBox;
  final double dailyCashIncome;
  final double totalCashDebtRepayment;
  final double totalAppDebtRepayment;
  final double totalCashPurchases;
  final double totalAppPurchases;
  final double totalPurchases;
  final double totalDailySales;
  final String createdAt;

  DailyStatistics({
    this.id,
    required this.statisticDate,
    required this.yesterdayCashInBox,
    required this.todayCashInBox,
    required this.dailyCashIncome,
    required this.totalCashDebtRepayment,
    required this.totalAppDebtRepayment,
    required this.totalCashPurchases,
    required this.totalAppPurchases,
    required this.totalPurchases,
    required this.totalDailySales,
    required this.createdAt,
  });

  factory DailyStatistics.fromJson(Map<String, dynamic> json) =>
      _$DailyStatisticsFromJson(json);
  Map<String, dynamic> toJson() => _$DailyStatisticsToJson(this);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'statistic_date': statisticDate,
      'yesterday_cash_in_box': yesterdayCashInBox,
      'today_cash_in_box': todayCashInBox,
      'daily_cash_income': dailyCashIncome,
      'total_cash_debt_repayment': totalCashDebtRepayment,
      'total_app_debt_repayment': totalAppDebtRepayment,
      'total_cash_purchases': totalCashPurchases,
      'total_app_purchases': totalAppPurchases,
      'total_purchases': totalPurchases,
      'total_daily_sales': totalDailySales,
      'created_at': createdAt,
    };
  }

  factory DailyStatistics.fromMap(Map<String, dynamic> map) {
    return DailyStatistics(
      id: map['id'],
      statisticDate: map['statistic_date'],
      yesterdayCashInBox: map['yesterday_cash_in_box'],
      todayCashInBox: map['today_cash_in_box'],
      dailyCashIncome: map['daily_cash_income'],
      totalCashDebtRepayment: map['total_cash_debt_repayment'],
      totalAppDebtRepayment: map['total_app_debt_repayment'],
      totalCashPurchases: map['total_cash_purchases'],
      totalAppPurchases: map['total_app_purchases'],
      totalPurchases: map['total_purchases'],
      totalDailySales: map['total_daily_sales'],
      createdAt: map['created_at'],
    );
  }
}

// Customer Payment Model
@JsonSerializable()
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

  factory CustomerPayment.fromJson(Map<String, dynamic> json) =>
      _$CustomerPaymentFromJson(json);
  Map<String, dynamic> toJson() => _$CustomerPaymentToJson(this);

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
      amount: map['amount'],
      paymentMethodId: map['payment_method_id'],
      paymentDate: map['payment_date'],
      createdAt: map['created_at'],
    );
  }
}

// Debt Reminder Model
@JsonSerializable()
class DebtReminder {
  final int? id;
  final int userId;
  final double debtAmount;
  final String reminderDate;
  final String createdAt;

  DebtReminder({
    this.id,
    required this.userId,
    required this.debtAmount,
    required this.reminderDate,
    required this.createdAt,
  });

  factory DebtReminder.fromJson(Map<String, dynamic> json) =>
      _$DebtReminderFromJson(json);
  Map<String, dynamic> toJson() => _$DebtReminderToJson(this);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'debt_amount': debtAmount,
      'reminder_date': reminderDate,
      'created_at': createdAt,
    };
  }

  factory DebtReminder.fromMap(Map<String, dynamic> map) {
    return DebtReminder(
      id: map['id'],
      userId: map['user_id'],
      debtAmount: map['debt_amount'],
      reminderDate: map['reminder_date'],
      createdAt: map['created_at'],
    );
  }
}
