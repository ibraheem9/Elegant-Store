import 'package:intl/intl.dart';

// Helper to handle Laravel's decimal-as-string and normal numbers
double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

// User Model
class User {
  final int? id;
  final String uuid;
  final int? parentId;
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
  final int version;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final int isSynced;

  User({
    this.id,
    this.uuid = '',
    this.parentId,
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
    this.version = 1,
    required this.createdAt,
    String? updatedAt,
    this.deletedAt,
    this.isSynced = 0,
  }) : this.updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'parent_id': parentId,
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
      'version': version,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'is_synced': isSynced,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      uuid: map['uuid'] ?? '',
      parentId: map['parent_id'],
      username: map['username'] ?? '',
      email: map['email'],
      name: map['name'] ?? '',
      nickname: map['nickname'],
      role: map['role'] ?? 'CUSTOMER',
      isPermanentCustomer: map['is_permanent_customer'] ?? 0,
      creditLimit: _toDouble(map['credit_limit']),
      phone: map['phone'],
      notes: map['notes'],
      transferNames: map['transfer_names'],
      balance: _toDouble(map['balance']),
      version: map['version'] ?? 1,
      createdAt: map['created_at'] ?? '',
      updatedAt: map['updated_at'] ?? '',
      deletedAt: map['deleted_at'],
      isSynced: map['is_synced'] ?? 0,
    );
  }

  int? getStoreManagerIdLocal() {
    if (role == 'STORE_MANAGER' || role == 'SUPER_ADMIN') return id;
    return parentId;
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is User && runtimeType == other.runtimeType && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

// Payment Method Model
class PaymentMethod {
  final int? id;
  final String uuid;
  final int? storeManagerId;
  final String name;
  final String type; 
  final String category; 
  final String? description;
  final int isActive;
  final int sortOrder;
  final int version;
  final String updatedAt;
  final int isSynced;

  PaymentMethod({
    this.id,
    this.uuid = '',
    this.storeManagerId,
    required this.name,
    required this.type,
    this.category = 'SALE',
    this.description,
    this.isActive = 1,
    this.sortOrder = 0,
    this.version = 1,
    String? updatedAt,
    this.isSynced = 0,
  }) : this.updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'store_manager_id': storeManagerId,
      'name': name,
      'type': type,
      'category': category,
      'description': description,
      'is_active': isActive,
      'sort_order': sortOrder,
      'version': version,
      'updated_at': updatedAt,
      'is_synced': isSynced,
    };
  }

  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    return PaymentMethod(
      id: map['id'],
      uuid: map['uuid'] ?? '',
      storeManagerId: map['store_manager_id'],
      name: map['name'] ?? '',
      type: map['type'] ?? '',
      category: map['category'] ?? 'SALE',
      description: map['description'],
      isActive: map['is_active'] ?? 1,
      sortOrder: map['sort_order'] ?? 0,
      version: map['version'] ?? 1,
      updatedAt: map['updated_at'] ?? '',
      isSynced: map['is_synced'] ?? 0,
    );
  }

  PaymentMethod copyWith({int? sortOrder}) {
    return PaymentMethod(
      id: id,
      uuid: uuid,
      storeManagerId: storeManagerId,
      name: name,
      type: type,
      category: category,
      description: description,
      isActive: isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      version: version,
      updatedAt: updatedAt,
      isSynced: isSynced,
    );
  }
}

// Invoice Model
class Invoice {
  final int? id;
  final String uuid;
  final int? storeManagerId;
  final int userId;
  final String invoiceDate;
  final double amount;
  final double paidAmount; 
  final int? paymentMethodId;
  final String paymentStatus; 
  final String type; 
  final String? notes;
  final int version;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final int isSynced;

  final String? customerName;
  final String? methodName;
  final String? userUuid;
  final int customerIsPermanent; // 0 = non-permanent, 1 = permanent

  Invoice({
    this.id,
    this.uuid = '',
    this.storeManagerId,
    required this.userId,
    required this.invoiceDate,
    required this.amount,
    this.paidAmount = 0.0,
    this.paymentMethodId,
    required this.paymentStatus,
    this.type = 'SALE',
    this.notes,
    this.version = 1,
    required this.createdAt,
    String? updatedAt,
    this.deletedAt,
    this.isSynced = 0,
    this.customerName,
    this.methodName,
    this.userUuid,
    this.customerIsPermanent = 0,
  }) : this.updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'store_manager_id': storeManagerId,
      'user_id': userId,
      'invoice_date': invoiceDate,
      'amount': amount,
      'paid_amount': paidAmount,
      'payment_method_id': paymentMethodId,
      'payment_status': paymentStatus,
      'type': type,
      'notes': notes,
      'version': version,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'is_synced': isSynced,
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      uuid: map['uuid'] ?? '',
      storeManagerId: map['store_manager_id'],
      userId: map['user_id'] ?? 0,
      invoiceDate: map['invoice_date'] ?? '',
      amount: _toDouble(map['amount']),
      paidAmount: _toDouble(map['paid_amount']),
      paymentMethodId: map['payment_method_id'],
      paymentStatus: map['payment_status'] ?? 'UNPAID',
      type: map['type'] ?? 'SALE',
      notes: map['notes'],
      version: map['version'] ?? 1,
      createdAt: map['created_at'] ?? '',
      updatedAt: map['updated_at'] ?? '',
      deletedAt: map['deleted_at'],
      isSynced: map['is_synced'] ?? 0,
      customerName: map['customer_name'],
      methodName: map['method_name'],
      userUuid: map['user_uuid'],
      customerIsPermanent: map['customer_is_permanent'] ?? 0,
    );
  }
}

// Transaction Model
class FinancialTransaction {
  final int? id;
  final String uuid;
  final int? storeManagerId;
  final int buyerId;
  final int? invoiceId;
  final String type; 
  final double amount;
  final double usedAmount; 
  final int? paymentMethodId; 
  final String? notes; 
  final int version;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final int isSynced;
  final String? buyerUuid;
  final String? invoiceUuid;

  FinancialTransaction({
    this.id,
    this.uuid = '',
    this.storeManagerId,
    required this.buyerId,
    this.invoiceId,
    required this.type,
    required this.amount,
    this.usedAmount = 0.0,
    this.paymentMethodId,
    this.notes,
    this.version = 1,
    required this.createdAt,
    String? updatedAt,
    this.deletedAt,
    this.isSynced = 0,
    this.buyerUuid,
    this.invoiceUuid,
  }) : this.updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'store_manager_id': storeManagerId,
      'buyer_id': buyerId,
      'invoice_id': invoiceId,
      'type': type,
      'amount': amount,
      'used_amount': usedAmount,
      'payment_method_id': paymentMethodId,
      'notes': notes,
      'version': version,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'is_synced': isSynced,
    };
  }

  factory FinancialTransaction.fromMap(Map<String, dynamic> map) {
    return FinancialTransaction(
      id: map['id'],
      uuid: map['uuid'] ?? '',
      storeManagerId: map['store_manager_id'],
      buyerId: map['buyer_id'] ?? 0,
      invoiceId: map['invoice_id'],
      type: map['type'] ?? '',
      amount: _toDouble(map['amount']),
      usedAmount: _toDouble(map['used_amount']),
      paymentMethodId: map['payment_method_id'],
      notes: map['notes'],
      version: map['version'] ?? 1,
      createdAt: map['created_at'] ?? '',
      updatedAt: map['updated_at'] ?? '',
      deletedAt: map['deleted_at'],
      isSynced: map['is_synced'] ?? 0,
      buyerUuid: map['buyer_uuid'],
      invoiceUuid: map['invoice_uuid'],
    );
  }
}

// Purchase Model
class Purchase {
  final int? id;
  final String uuid;
  final int? storeManagerId;
  final String merchantName;
  final double amount;
  final String paymentSource; 
  final int? paymentMethodId;
  final String? notes;
  final int version;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final int isSynced;

  Purchase({
    this.id,
    this.uuid = '',
    this.storeManagerId,
    required this.merchantName,
    required this.amount,
    required this.paymentSource,
    this.paymentMethodId,
    this.notes,
    this.version = 1,
    required this.createdAt,
    String? updatedAt,
    this.deletedAt,
    this.isSynced = 0,
  }) : this.updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'store_manager_id': storeManagerId,
      'merchant_name': merchantName,
      'amount': amount,
      'payment_source': paymentSource,
      'payment_method_id': paymentMethodId,
      'notes': notes,
      'version': version,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'is_synced': isSynced,
    };
  }

  factory Purchase.fromMap(Map<String, dynamic> map) {
    return Purchase(
      id: map['id'],
      uuid: map['uuid'] ?? '',
      storeManagerId: map['store_manager_id'],
      merchantName: map['merchant_name'] ?? '',
      amount: _toDouble(map['amount']),
      paymentSource: map['payment_source'] ?? 'CASH',
      paymentMethodId: map['payment_method_id'],
      notes: map['notes'],
      version: map['version'] ?? 1,
      createdAt: map['created_at'] ?? '',
      updatedAt: map['updated_at'] ?? '',
      deletedAt: map['deleted_at'],
      isSynced: map['is_synced'] ?? 0,
    );
  }
}

// Daily Statistics Model
class DailyStatistics {
  final int? id;
  final String uuid;
  final int? storeManagerId;
  final String statisticDate;
  final double yesterdayCashInBox;
  final double todayCashInBox;
  final double totalCashDebtRepayment;
  final double totalAppDebtRepayment;
  final double totalCashPurchases;
  final double totalAppPurchases;
  final double totalSalesCash;
  final double totalSalesCredit;
  final int version;
  final String createdAt;
  final String updatedAt;
  final int isSynced;

  DailyStatistics({
    this.id,
    this.uuid = '',
    this.storeManagerId,
    required this.statisticDate,
    required this.yesterdayCashInBox,
    required this.todayCashInBox,
    required this.totalCashDebtRepayment,
    required this.totalAppDebtRepayment,
    required this.totalCashPurchases,
    required this.totalAppPurchases,
    this.totalSalesCash = 0.0,
    this.totalSalesCredit = 0.0,
    this.version = 1,
    required this.createdAt,
    String? updatedAt,
    this.isSynced = 0,
  }) : this.updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'store_manager_id': storeManagerId,
      'statistic_date': statisticDate,
      'yesterday_cash_in_box': yesterdayCashInBox,
      'today_cash_in_box': todayCashInBox,
      'total_cash_debt_repayment': totalCashDebtRepayment,
      'total_app_debt_repayment': totalAppDebtRepayment,
      'total_cash_purchases': totalCashPurchases,
      'total_app_purchases': totalAppPurchases,
      'total_sales_cash': totalSalesCash,
      'total_sales_credit': totalSalesCredit,
      'version': version,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_synced': isSynced,
    };
  }

  factory DailyStatistics.fromMap(Map<String, dynamic> map) {
    return DailyStatistics(
      id: map['id'],
      uuid: map['uuid'] ?? '',
      storeManagerId: map['store_manager_id'],
      statisticDate: map['statistic_date'] ?? '',
      yesterdayCashInBox: _toDouble(map['yesterday_cash_in_box']),
      todayCashInBox: _toDouble(map['today_cash_in_box']),
      totalCashDebtRepayment: _toDouble(map['total_cash_debt_repayment']),
      totalAppDebtRepayment: _toDouble(map['total_app_debt_repayment']),
      totalCashPurchases: _toDouble(map['total_cash_purchases']),
      totalAppPurchases: _toDouble(map['total_app_purchases']),
      totalSalesCash: _toDouble(map['total_sales_cash']),
      totalSalesCredit: _toDouble(map['total_sales_credit']),
      version: map['version'] ?? 1,
      createdAt: map['created_at'] ?? '',
      updatedAt: map['updated_at'] ?? '',
      isSynced: map['is_synced'] ?? 0,
    );
  }
}
