import '../core/api_service.dart';

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Canonical listing status. The API already normalises the legacy "closed"
/// word to "archived"; this mirrors that so an older payload cannot introduce
/// a status the client does not understand.
String _listingStatus(dynamic raw) {
  final value = '${raw ?? 'active'}';
  return value == 'closed' ? 'archived' : value;
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

/// Resolves a listing's ordered gallery from `image_urls`, falling back to the
/// single `image_url` so an older payload still yields its one photo.
List<String> _imageList(dynamic rawList, dynamic rawCover) {
  final resolved = <String>[];
  if (rawList is List) {
    for (final entry in rawList) {
      final url = _resolveImageUrl(entry is String ? entry : null);
      if (url != null) resolved.add(url);
    }
  }
  if (resolved.isEmpty) {
    final cover = _resolveImageUrl(rawCover is String ? rawCover : null);
    if (cover != null) resolved.add(cover);
  }
  return resolved;
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

  /// Absolute URL of the member's profile photo, or null when they have none
  /// (the UI then falls back to their initials). Already host-rewritten by
  /// [_resolveImageUrl] so it loads regardless of which API base won.
  final String? avatarUrl;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.barangay,
    required this.purokSitio,
    required this.verified,
    required this.verificationStatus,
    this.verificationNote,
    this.avatarUrl,
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
        avatarUrl: _resolveImageUrl(json['avatar_url'] as String?),
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
        // Carried through explicitly: refreshVerification() rebuilds the model
        // and would otherwise drop the photo on every status poll.
        avatarUrl: avatarUrl,
      );
}

class ListingModel {
  final int id;
  final String title;
  final String description;
  final String type;
  final String compensationType;
  final String compensationLabel;

  /// What the owner wants back — the return side of a barter. Null for free
  /// and paid listings, which have no return side.
  final String? wantedItem;
  final double? price;

  /// Paid-only: the owner welcomes a counter-offer, so the app shows
  /// "Negotiable" and a "Make an offer" action. Always false for free/barter
  /// (the server normalises it), so the UI never invites a price negotiation
  /// on something that has none.
  final bool priceNegotiable;
  final String category;
  final String condition;
  final String location;
  final String barangay;
  final String purokSitio;
  final String owner;
  final int ownerId;

  /// Owner's profile photo URL (null when they have none) and residency
  /// verification flag — both surfaced from `owner{}` so a card can show a
  /// photo + "Verified resident" badge.
  final String? ownerAvatarUrl;
  final bool ownerVerified;
  final String? imageUrl;

  /// The full ordered gallery. Empty when the listing has no photos. The first
  /// entry is the cover and equals [imageUrl].
  final List<String> imageUrls;
  final bool active;

  /// Canonical lifecycle status: active | paused | traded | archived, or an
  /// admin hold (flagged | hidden | removed). Distinct from [active], which is
  /// the derived "visible in the community feed" flag.
  final String status;
  final double? latitude;
  final double? longitude;

  const ListingModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    this.compensationType = 'barter',
    this.compensationLabel = 'BARTER',
    this.wantedItem,
    this.price,
    this.priceNegotiable = false,
    required this.category,
    required this.condition,
    required this.location,
    required this.barangay,
    required this.purokSitio,
    required this.owner,
    required this.ownerId,
    this.ownerAvatarUrl,
    this.ownerVerified = false,
    this.imageUrl,
    this.imageUrls = const [],
    required this.active,
    this.status = 'active',
    this.latitude,
    this.longitude,
  });

  bool get isFree => compensationType == 'free';
  bool get isPaid => compensationType == 'paid';
  bool get isBarter => !isFree && !isPaid;

  /// True when a buyer should be offered the "Make an offer" route: a priced
  /// sale whose owner welcomes a counter-offer.
  bool get isNegotiable => isPaid && priceNegotiable;

  // ── Lifecycle status ─────────────────────────────────────────────────
  bool get isActiveStatus => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isTraded => status == 'traded';
  bool get isArchived => status == 'archived';

  /// Held back by a moderator — the owner cannot change it.
  bool get underReview =>
      status == 'flagged' || status == 'hidden' || status == 'removed';

  /// Human label for the "My Listings" status badge.
  String get statusLabel => const {
        'active': 'Active',
        'paused': 'Paused',
        'traded': 'Traded',
        'archived': 'Archived',
        'flagged': 'Under review',
        'hidden': 'Under review',
        'removed': 'Removed',
      }[status] ??
      status;

  /// True when the owner named what they want back. Barter-only: free and paid
  /// listings have no return side, so a stale payload cannot surface one.
  bool get hasWantedItem => isBarter && (wantedItem?.isNotEmpty ?? false);

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
      wantedItem: (json['wanted_item'] as String?)?.trim(),
      price: _asDouble(json['price']),
      // Only a paid listing can be negotiable; the server already normalises
      // this, but guard the flag here so a stale/foreign payload cannot make a
      // gift or a trade look open to offers.
      priceNegotiable: json['price_negotiable'] == true && compensation == 'paid',
      category: (json['category'] ?? 'Tools') as String,
      condition: (json['condition'] ?? 'Good') as String,
      location: (json['location'] ?? '') as String,
      barangay: (json['barangay'] ?? '') as String,
      purokSitio: (json['purok_sitio'] ?? '') as String,
      owner: owner is Map ? (owner['name'] ?? 'Member') as String : 'Member',
      ownerId: owner is Map
          ? (owner['id'] as num?)?.toInt() ?? (json['user_id'] as num?)?.toInt() ?? 0
          : (json['user_id'] as num?)?.toInt() ?? 0,
      ownerAvatarUrl: owner is Map ? _resolveImageUrl(owner['avatar_url'] as String?) : null,
      ownerVerified: owner is Map && owner['verified'] == true,
      imageUrl: _resolveImageUrl(json['image_url'] as String?),
      // The ordered gallery. Falls back to the single cover so an older API
      // payload still renders its one photo.
      imageUrls: _imageList(json['image_urls'], json['image_url']),
      active: json['is_active'] != false,
      status: _listingStatus(json['status']),
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

  /// The other participant's profile photo, or null (initials fallback).
  final String? memberAvatarUrl;
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
    this.memberAvatarUrl,
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
      memberAvatarUrl: _resolveImageUrl(member['avatar_url'] as String?),
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

  /// Set by the backend when a member edits a message, so the bubble can
  /// render a Messenger-style "Edited" marker.
  final bool edited;

  /// Optimistically-created rows (the bubble that appears the instant you hit
  /// send) have no server id yet, so actions requiring one are unavailable
  /// until the poll reconciles them with the stored copy.
  final bool isPending;

  /// Messenger-style attachment fields served by `Message::toChatPayload()`.
  /// `fileType` is `image` or `document`; `fileUrl` is absolute and already
  /// rewritten when possible, with `_resolveImageUrl` as fallback.
  final String? fileUrl;
  final String? fileType;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;

  const ChatMessageModel({
    required this.id,
    required this.body,
    required this.sender,
    required this.senderId,
    this.sentAt,
    this.edited = false,
    this.isPending = false,
    this.fileUrl,
    this.fileType,
    this.fileName,
    this.fileSize,
    this.mimeType,
  });

  /// True when this message carries a photo or document attachment — a remote
  /// URL from the server, or a local staging path on an optimistic row.
  bool get hasAttachment =>
      (fileUrl ?? '').isNotEmpty || (fileName ?? '').isNotEmpty;

  /// True for photo attachments rendered inline with rounded corners.
  /// Falls back to extension/mime sniffing when the backend type is absent,
  /// and never treats a local document staging path as an image.
  bool get isImage {
    if (fileType == 'image') return true;
    if (fileType == 'document') return false;
    if (!hasAttachment) return false;
    // Optimistic rows store `fileName` without a type until reconciled —
    // trust the name first (set from the picked file on both platforms).
    return _looksLikeImage();
  }

  bool _looksLikeImage() {
    final name = (fileName ?? '').toLowerCase();
    final mime = (mimeType ?? '').toLowerCase();
    return mime.startsWith('image/') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
  }

  /// Human-readable file size for the document card subtitle.
  String get displayFileSize {
    final bytes = fileSize ?? 0;
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Resolved absolute URL for the attachment, honouring the same host-rewrite
  /// rule as listing photos so LAN/emulator builds load correctly.
  String? get resolvedFileUrl => _resolveImageUrl(fileUrl);

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] is Map ? Map<String, dynamic>.from(json['sender'] as Map) : const {};
    final id = '${json['id'] ?? ''}';
    final sizeRaw = json['file_size'];
    return ChatMessageModel(
      id: id,
      body: (json['body'] ?? json['message'] ?? '') as String,
      sender: (sender['name'] ?? json['senderName'] ?? json['fromEmail'] ?? 'Member') as String,
      senderId: (json['sender_id'] as num?)?.toInt() ?? 0,
      sentAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      edited: json['edited_at'] != null,
      // Server ids are integers; the optimistic placeholder is "local-<ts>".
      isPending: id.startsWith('local-'),
      fileUrl: (json['file_url'] ?? json['fileUrl']) as String?,
      fileType: json['file_type'] as String?,
      fileName: json['file_name'] as String?,
      fileSize: sizeRaw is num ? sizeRaw.toInt() : int.tryParse('$sizeRaw'),
      mimeType: json['mime_type'] as String?,
    );
  }

  ChatMessageModel copyWith({String? body, bool? edited}) => ChatMessageModel(
        id: id,
        body: body ?? this.body,
        sender: sender,
        senderId: senderId,
        sentAt: sentAt,
        edited: edited ?? this.edited,
        isPending: isPending,
        fileUrl: fileUrl,
        fileType: fileType,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
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
