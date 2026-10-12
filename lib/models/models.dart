import '../core/api_service.dart';

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Rewrite the image URL's origin to the API host the app is actually
/// talking to, so photos load no matter which base-URL candidate won
/// (LAN IP, emulator alias, or adb reverse) and regardless of APP_URL.
String? _resolveImageUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (raw.startsWith('/storage') || raw.startsWith('storage')) {
    final host = ApiService.instance.baseUrl
        .replaceFirst(RegExp(r'/api/?$'), '');
    return '$host/${raw.startsWith('/') ? raw.substring(1) : raw}';
  }
  if (uri.hasScheme) {
    try {
      final apiBase = Uri.parse(ApiService.instance.baseUrl);
      return uri.replace(scheme: apiBase.scheme, host: apiBase.host, port: apiBase.port).toString();
    } catch (_) {
      return raw;
    }
  }
  return raw;
}

class UserModel {
  final int id;
  final String name;
  final String email;
  final String barangay;
  final String purokSitio;
  final bool verified;
  final String verificationStatus;
  final String? verificationNote;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.barangay,
    required this.purokSitio,
    required this.verified,
    required this.verificationStatus,
    this.verificationNote,
  });

  /// Normalises any server value — the raw `unverified`/`pending`/`verified`/
  /// `rejected` status or the display label — to one canonical label.
  static String labelForStatus(Object? raw) {
    switch ('${raw ?? ''}'.toLowerCase()) {
      case 'verified':
        return 'Verified';
      case 'pending':
        return 'Pending';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Unverified';
    }
  }

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['fullName'] ?? json['name'] ?? '') as String,
        email: (json['email'] ?? '') as String,
        barangay: (json['barangay'] ?? json['barangay_or_location'] ?? '') as String,
        purokSitio: (json['purok_sitio'] ?? '') as String,
        verified: json['is_verified'] == true,
        verificationStatus: labelForStatus(json['verification_status']),
        verificationNote: json['verification_note'] as String?,
      );

  UserModel copyWith({
    bool? verified,
    String? verificationStatus,
    String? verificationNote,
  }) =>
      UserModel(
        id: id,
        name: name,
        email: email,
        barangay: barangay,
        purokSitio: purokSitio,
        verified: verified ?? this.verified,
        verificationStatus: verificationStatus ?? this.verificationStatus,
        verificationNote: verificationNote ?? this.verificationNote,
      );
}

class ListingModel {
  final int id;
  final String title;
  final String description;
  final String type;
  final String compensationType;
  final String compensationLabel;
  final double? price;
  final String category;
  final String condition;
  final String location;
  final String barangay;
  final String purokSitio;
  final String owner;
  final int ownerId;
  final String? imageUrl;
  final bool active;
  final double? latitude;
  final double? longitude;

  const ListingModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    this.compensationType = 'barter',
    this.compensationLabel = 'BARTER',
    this.price,
    required this.category,
    required this.condition,
    required this.location,
    required this.barangay,
    required this.purokSitio,
    required this.owner,
    required this.ownerId,
    this.imageUrl,
    required this.active,
    this.latitude,
    this.longitude,
  });

  bool get isFree => compensationType == 'free';
  bool get isPaid => compensationType == 'paid';
  bool get isBarter => !isFree && !isPaid;

  factory ListingModel.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'];
    final compensation = '${json['compensation_type'] ?? 'barter'}';
    final label = json['compensation_label'] as String?;
    return ListingModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      type: (json['type'] ?? 'offer') as String,
      compensationType: compensation,
      compensationLabel: label ??
          { 'free': 'FREE SHARING', 'paid': 'PAID' }[compensation] ??
          'BARTER',
      price: _asDouble(json['price']),
      category: (json['category'] ?? 'Tools') as String,
      condition: (json['condition'] ?? 'Good') as String,
      location: (json['location'] ?? '') as String,
      barangay: (json['barangay'] ?? '') as String,
      purokSitio: (json['purok_sitio'] ?? '') as String,
      owner: owner is Map ? (owner['name'] ?? 'Member') as String : 'Member',
      ownerId: owner is Map
          ? (owner['id'] as num?)?.toInt() ?? (json['user_id'] as num?)?.toInt() ?? 0
          : (json['user_id'] as num?)?.toInt() ?? 0,
      imageUrl: _resolveImageUrl(json['image_url'] as String?),
      active: json['is_active'] != false,
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
    );
  }
}

class ExchangeModel {
  final int id;
  final String title;
  final String status;
  final String? offeredItem;

  const ExchangeModel({required this.id, required this.title, required this.status, this.offeredItem});

  factory ExchangeModel.fromJson(Map<String, dynamic> json) => ExchangeModel(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: (json['itemTitle'] ?? json['title'] ?? 'Exchange') as String,
        status: (json['status'] ?? 'Pending') as String,
        offeredItem: json['offeredItem'] as String?,
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

  /// Listing this inquiry is about (null for plain member-to-member chat).
  final String? listingTitle;
  final String? compensationType;
  final String? compensationLabel;
  final double? listingPrice;

  const ConversationModel({
    required this.id,
    required this.memberName,
    required this.memberEmail,
    required this.unreadCount,
    this.lastMessageAt,
    this.listingTitle,
    this.compensationType,
    this.compensationLabel,
    this.listingPrice,
  });

  bool get hasListing => (listingTitle ?? '').isNotEmpty;

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    final member = json['member'] is Map ? Map<String, dynamic>.from(json['member'] as Map) : const {};
    final listing = json['listing'] is Map ? Map<String, dynamic>.from(json['listing'] as Map) : null;
    final rawPrice = listing?['price'];
    return ConversationModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      memberName: '${member['name'] ?? 'Member'}',
      memberEmail: '${member['email'] ?? ''}',
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessageAt: DateTime.tryParse('${json['last_message_at'] ?? ''}'),
      listingTitle: listing == null ? null : '${listing['title'] ?? ''}',
      compensationType: listing == null ? null : '${listing['compensation_type'] ?? 'barter'}',
      compensationLabel: listing == null ? null : '${listing['compensation_label'] ?? 'BARTER'}',
      listingPrice: listing == null ? null : _asDouble(rawPrice),
    );
  }
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
