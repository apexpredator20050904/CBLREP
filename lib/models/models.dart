class UserModel {
  final int id;
  final String name;
  final String email;
  final String barangay;
  final bool verified;
  final String verificationStatus;
  final double credits;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.barangay,
    required this.verified,
    required this.verificationStatus,
    required this.credits,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['fullName'] ?? json['name'] ?? '') as String,
        email: (json['email'] ?? '') as String,
        barangay: (json['barangay_or_location'] ?? json['barangay'] ?? '') as String,
        verified: json['is_verified'] == true,
        verificationStatus: (json['verification_status'] ?? 'Pending') as String,
        credits: (json['time_bank_credits'] as num?)?.toDouble() ?? 0,
      );
}

class ListingModel {
  final int id;
  final String title;
  final String description;
  final String type;
  final String category;
  final String exchangeType;
  final String condition;
  final String location;
  final String owner;
  final bool active;

  const ListingModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.category,
    required this.exchangeType,
    required this.condition,
    required this.location,
    required this.owner,
    required this.active,
  });

  factory ListingModel.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'];
    return ListingModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      type: (json['type'] ?? 'offer') as String,
      category: (json['category'] ?? 'Tools') as String,
      exchangeType: (json['exchange_type'] ?? json['exchangeType'] ?? 'Lend') as String,
      condition: (json['condition'] ?? 'Good') as String,
      location: (json['location'] ?? '') as String,
      owner: owner is Map ? (owner['name'] ?? 'Member') as String : 'Member',
      active: json['is_active'] != false,
    );
  }
}

class ExchangeModel {
  final int id;
  final String title;
  final String type;
  final String status;
  final String? dueDate;

  const ExchangeModel({required this.id, required this.title, required this.type, required this.status, this.dueDate});

  factory ExchangeModel.fromJson(Map<String, dynamic> json) => ExchangeModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['itemTitle'] ?? json['title'] ?? 'Exchange') as String,
        type: (json['type'] ?? 'Lending') as String,
        status: (json['status'] ?? 'Pending') as String,
        dueDate: json['dueDate'] as String?,
      );
}

class MessageModel {
  final String id;
  final String body;
  final String sender;
  final DateTime? sentAt;

  const MessageModel({required this.id, required this.body, required this.sender, this.sentAt});

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: '${json['id'] ?? ''}',
        body: (json['body'] ?? json['message'] ?? '') as String,
        sender: (json['senderName'] ?? json['fromEmail'] ?? 'Member') as String,
        sentAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );
}
