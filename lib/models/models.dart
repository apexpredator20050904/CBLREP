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
  final int ownerId;
  final String? imageUrl;
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
    required this.ownerId,
    this.imageUrl,
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
      ownerId: owner is Map
          ? (owner['id'] as num?)?.toInt() ?? (json['user_id'] as num?)?.toInt() ?? 0
          : (json['user_id'] as num?)?.toInt() ?? 0,
      imageUrl: json['image_url'] as String?,
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

class NotificationModel {
  final int id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: '${json['type'] ?? 'general'}',
        title: '${json['title'] ?? 'Notification'}',
        body: '${json['body'] ?? ''}',
        read: json['read_at'] != null,
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );
}

class ConversationModel {
  final int id;
  final String memberName;
  final String memberEmail;
  final int unreadCount;
  final DateTime? lastMessageAt;

  const ConversationModel({
    required this.id,
    required this.memberName,
    required this.memberEmail,
    required this.unreadCount,
    this.lastMessageAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    final member = json['member'] is Map ? Map<String, dynamic>.from(json['member'] as Map) : const {};
    return ConversationModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      memberName: '${member['name'] ?? 'Member'}',
      memberEmail: '${member['email'] ?? ''}',
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessageAt: DateTime.tryParse('${json['last_message_at'] ?? ''}'),
    );
  }
}

class TimeBankModel {
  final double balance;
  final double earned;
  final double spent;
  final double pending;

  const TimeBankModel({required this.balance, required this.earned, required this.spent, required this.pending});

  factory TimeBankModel.fromJson(Map<String, dynamic> json) => TimeBankModel(
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        earned: (json['earned'] as num?)?.toDouble() ?? 0,
        spent: (json['spent'] as num?)?.toDouble() ?? 0,
        pending: (json['pending'] as num?)?.toDouble() ?? 0,
      );
}

class ChatMessageModel {
  final String id;
  final String body;
  final String sender;
  final int senderId;
  final DateTime? sentAt;

  const ChatMessageModel({required this.id, required this.body, required this.sender, required this.senderId, this.sentAt});

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] is Map ? Map<String, dynamic>.from(json['sender'] as Map) : const {};
    return ChatMessageModel(
      id: '${json['id'] ?? ''}',
      body: (json['body'] ?? json['message'] ?? '') as String,
      sender: (sender['name'] ?? json['senderName'] ?? json['fromEmail'] ?? 'Member') as String,
      senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
      sentAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
    );
  }
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
