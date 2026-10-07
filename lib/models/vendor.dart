import '../core/utils.dart';
import 'user.dart';

/// Verification states a store moves through, in pipeline order:
/// submit documents → under review → verified or rejected.
class VendorVerification {
  VendorVerification._();

  static const unverified = 'UNVERIFIED';
  static const pending = 'PENDING';
  static const verified = 'VERIFIED';
  static const rejected = 'REJECTED';

  static const all = <String>[unverified, pending, verified, rejected];
}

/// Operational status of the vendor account, set by the platform. Distinct
/// from [VendorVerification]: a store can be `VERIFIED` yet `SUSPENDED`.
class VendorAccountStatus {
  VendorAccountStatus._();

  static const active = 'ACTIVE';
  static const suspended = 'SUSPENDED';
  static const blocked = 'BLOCKED';
  static const underReview = 'UNDER_REVIEW';

  static const all = <String>[active, underReview, suspended, blocked];
}

/// One uploaded verification document (business registration, tax id, …).
class VerificationDocument {
  VerificationDocument({
    this.id,
    this.type,
    this.label,
    this.url,
    this.status,
    this.uploadedAt,
  });

  String? id;
  String? type;
  String? label;
  String? url;
  String? status;
  DateTime? uploadedAt;

  factory VerificationDocument.fromJson(Map<String, dynamic> j) => VerificationDocument(
        id: j['_id'] ?? j['id'],
        type: j['type'] ?? j['documentType'] ?? j['kind'],
        label: j['label'] ?? j['name'] ?? j['title'],
        url: j['url'] ?? j['file'] ?? j['fileUrl'] ?? j['path'],
        status: j['status'],
        uploadedAt: parseDate(j['uploadedAt'] ?? j['createdAt']),
      );

  /// Human label for the document type, falling back to the type slug.
  String get display {
    if (label != null && label!.trim().isNotEmpty) return label!;
    final t = type ?? '';
    if (t.isEmpty) return 'Document';
    return titleCase(t);
  }
}

/// The vendor's own store, as returned by `GET /stores/mine`.
///
/// Deliberately all-nullable with defensive cascade reads: the store resource
/// is written by both vendors (profile form) and the platform (verification,
/// suspensions), so its shape varies between those writers.
class StoreProfile {
  StoreProfile({
    this.id,
    this.name,
    this.slug,
    this.logo,
    this.description,
    this.email,
    this.phone,
    this.facebook,
    this.instagram,
    this.twitter,
    this.website,
    this.street,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.deliveryNote,
    this.deliveryFee,
    this.deliveryTime,
    this.verificationStatus,
    this.status,
    this.rating,
    this.ratingCount,
    this.productCount,
    this.submittedAt,
    this.rejectionReason,
    this.documents,
    this.raw,
  });

  String? id;
  String? name;
  String? slug;
  String? logo;
  String? description;
  String? email;
  String? phone;
  String? facebook;
  String? instagram;
  String? twitter;
  String? website;
  String? street;
  String? city;
  String? state;
  String? country;
  String? postalCode;
  String? deliveryNote;
  num? deliveryFee;
  String? deliveryTime;

  /// One of [VendorVerification.all].
  String? verificationStatus;

  /// One of [VendorAccountStatus.all].
  String? status;

  double? rating;
  int? ratingCount;
  int? productCount;
  DateTime? submittedAt;
  String? rejectionReason;
  List<VerificationDocument>? documents;
  Map<String, dynamic>? raw;

  factory StoreProfile.fromJson(Map<String, dynamic> j) {
    final vendor = j['vendor'] is Map ? Map<String, dynamic>.from(j['vendor']) : j;
    final addr = vendor['address'] is Map ? Map<String, dynamic>.from(vendor['address']) : const <String, dynamic>{};
    final socials = vendor['socials'] is Map ? Map<String, dynamic>.from(vendor['socials']) : const <String, dynamic>{};
    final contact = vendor['contact'] is Map ? Map<String, dynamic>.from(vendor['contact']) : const <String, dynamic>{};
    final owner = vendor['owner'] is Map ? Map<String, dynamic>.from(vendor['owner']) : const <String, dynamic>{};
    final docs = vendor['documents'];
    return StoreProfile(
      id: vendor['_id'] ?? vendor['id'] ?? j['_id'] ?? j['id'],
      name: vendor['businessName'] ?? vendor['storeName'] ?? vendor['name'] ?? vendor['companyName'],
      slug: vendor['slug'],
      logo: vendor['logoUrl'] ?? vendor['logo'] ?? vendor['image'] ?? vendor['bannerUrl'],
      description: vendor['description'] ?? vendor['about'] ?? vendor['bio'],
      email: vendor['email'] ?? contact['email'] ?? owner['email'],
      phone: vendor['phone'] ?? vendor['telephone'] ?? vendor['contactNumber'] ?? contact['phone'] ?? owner['phone'],
      facebook: vendor['facebook'] ?? vendor['facebookUrl'] ?? socials['facebook'],
      instagram: vendor['instagram'] ?? vendor['instagramUrl'] ?? socials['instagram'],
      twitter: vendor['twitter'] ?? vendor['twitterUrl'] ?? socials['twitter'] ?? vendor['x'],
      website: vendor['website'] ?? vendor['webUrl'] ?? socials['website'],
      street: vendor['street'] ?? vendor['addressLine'] ?? addr['street'] ?? addr['address'] ?? (vendor['location'] is Map ? vendor['location']['street'] : null),
      city: vendor['city'] ?? vendor['town'] ?? addr['city'] ?? (vendor['location'] is String ? vendor['location'] : (vendor['location'] is Map ? (vendor['location']['city'] ?? vendor['location']['name']) : null)),
      state: vendor['state'] ?? vendor['province'] ?? addr['state'] ?? addr['province'],
      country: vendor['country'] ?? addr['country'],
      postalCode: vendor['postalCode'] ?? vendor['zip'] ?? vendor['zipCode'] ?? addr['postalCode'] ?? addr['zip'],
      deliveryNote: vendor['deliveryNote'] ?? vendor['deliveryInstructions'] ?? (vendor['delivery'] is Map ? (vendor['delivery'] as Map)['note']?.toString() : null),
      deliveryFee: (vendor['deliveryFee'] ?? (vendor['delivery'] is Map ? (vendor['delivery'] as Map)['fee'] : null)) as num?,
      deliveryTime: vendor['deliveryTime'] ?? (vendor['delivery'] is Map ? (vendor['delivery'] as Map)['time']?.toString() : null),
      verificationStatus: _up(vendor['verificationStatus'] ?? vendor['verification'] ?? vendor['verified']),
      status: _up(vendor['status'] ?? vendor['accountStatus'] ?? vendor['operationalStatus']),
      rating: (vendor['rating'] ?? vendor['averageRating'] ?? vendor['storeRating'])?.toDouble(),
      ratingCount: _int(vendor['ratingCount'] ?? vendor['totalRatings'] ?? vendor['reviewsCount']),
      productCount: _int(vendor['productCount'] ?? vendor['productsCount'] ?? vendor['totalProducts']),
      submittedAt: parseDate(vendor['submittedAt'] ?? vendor['verificationSubmittedAt'] ?? vendor['createdAt']),
      rejectionReason: vendor['rejectionReason'] ?? vendor['verificationNote'] ?? vendor['rejectionNote'],
      documents: docs is List
          ? docs
              .whereType<Map>()
              .map((e) => VerificationDocument.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : null,
      raw: vendor,
    );
  }

  static String? _up(dynamic v) => v?.toString().trim().toUpperCase().replaceAll('-', '_');

  static int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));

  String get display => name ?? 'Unnamed store';

  /// Normalised verification status; a store with no record yet is unverified.
  String get verification =>
      verificationStatus == null || verificationStatus!.isEmpty ? VendorVerification.unverified : verificationStatus!;

  /// Normalised account status; a store with no record yet is active.
  String get accountStatus => status == null || status!.isEmpty ? VendorAccountStatus.active : status!;

  bool get isVerified => verification == VendorVerification.verified;

  /// The vendor still owes the platform documents, or is waiting on a decision.
  bool get needsVerification =>
      verification == VendorVerification.unverified || verification == VendorVerification.pending;

  /// The store can trade: verified and not blocked by the platform.
  bool get canOperate =>
      isVerified &&
      accountStatus != VendorAccountStatus.blocked &&
      accountStatus != VendorAccountStatus.suspended;

  /// Document types the platform asks for before it can verify a store.
  static const requiredDocumentTypes = <String>[
    'BUSINESS_REGISTRATION',
    'TAX_ID',
    'PROOF_OF_ADDRESS',
  ];

  /// Required document types the vendor has not supplied yet.
  List<String> get missingDocuments {
    final have = (documents ?? const <VerificationDocument>[])
        .map((d) => (d.type ?? '').trim().toUpperCase().replaceAll('-', '_'))
        .toSet();
    return [
      for (final t in requiredDocumentTypes)
        if (!have.contains(t)) t,
    ];
  }

  /// The request body for the vendor profile endpoints.
  ///
  /// The backend only accepts the vendor profile fields it owns
  /// (`businessName`, `email`, `phone`, `logoUrl`, `bannerUrl`, `location` and a
  /// few text fields). Keep the payload limited to those keys so a partial edit
  /// does not silently null out fields the seller left untouched.
  Map<String, dynamic> toBody() => {
        if ((name ?? '').trim().isNotEmpty) 'businessName': name!.trim(),
        if ((description ?? '').trim().isNotEmpty) 'description': description!.trim(),
        if ((logo ?? '').trim().isNotEmpty) 'logoUrl': logo!.trim(),
        if ((email ?? '').trim().isNotEmpty) 'email': email!.trim(),
        if ((phone ?? '').trim().isNotEmpty) 'phone': phone!.trim(),
        if ((website ?? '').trim().isNotEmpty) 'website': website!.trim(),
        if ((city ?? '').trim().isNotEmpty) 'location': city!.trim(),
      }..removeWhere((_, v) => v == null);

  static Object? _v(String? s) {
    final t = (s ?? '').trim();
    return t.isEmpty ? null : t;
  }
}

/// One row in the unified vendor activity timeline: a financial, order or
/// operational event. The backend returns them interleaved in a single feed.
class VendorActivity {
  VendorActivity({
    this.id,
    this.type,
    this.title,
    this.description,
    this.amount,
    this.status,
    this.reference,
    this.product,
    this.date,
    this.raw,
  });

  String? id;

  /// Raw type from the API; see [bucket] for the normalised filter value.
  String? type;

  String? title;
  String? description;
  num? amount;
  String? status;
  String? reference;
  String? product;
  DateTime? date;
  Map<String, dynamic>? raw;

  factory VendorActivity.fromJson(Map<String, dynamic> j) {
    final product = j['product'];
    return VendorActivity(
      id: j['_id'] ?? j['id'] ?? j['entryId'],
      type: j['type'] ?? j['activityType'] ?? j['entryType'] ?? j['category'],
      title: j['title'] ?? j['event'] ?? j['name'] ?? j['narration'] ?? j['description'],
      description: j['description'] ?? j['details'] ?? j['note'],
      amount: (j['amount'] ?? j['value'] ?? j['total']) as num?,
      status: j['status'],
      reference: _ref(j['order']) ??
          _ref(j['payout']) ??
          _ref(j['relatedOrder']) ??
          j['reference']?.toString() ??
          j['orderNumber']?.toString(),
      product: product is Map ? (product['name'] ?? product['_id'])?.toString() : product?.toString(),
      date: parseDate(j['createdAt'] ?? j['date'] ?? j['timestamp']),
      raw: j,
    );
  }

  static String? _ref(dynamic v) => v is Map ? (v['orderNumber'] ?? v['_id'] ?? v['reference'])?.toString() : v?.toString();

  /// Activity groups offered by the history filter.
  static const buckets = <String>['ORDERS', 'PAYOUTS', 'INVENTORY'];

  /// Normalised filter bucket. The feed mixes three event families, so each row
  /// is folded into one of [buckets]; anything unrecognised is treated as an
  /// order event, which is the most common kind of entry.
  String get bucket {
    final t = (type ?? '').toLowerCase();
    if (t.contains('payout') || t.contains('payment') || t.contains('settle') || t.contains('transaction')) {
      return 'PAYOUTS';
    }
    if (t.contains('stock') || t.contains('inventory') || t.contains('product')) return 'INVENTORY';
    return 'ORDERS';
  }

  String get display => title ?? description ?? type ?? 'Activity';
}

/// Headline numbers for the vendor dashboard summary cards.
class VendorStats {
  VendorStats({
    this.dailySales,
    this.salesDelta,
    this.activeOrders,
    this.lowStock,
    this.rating,
    this.ratingCount,
    this.totalProducts,
    this.totalOrders,
    this.pendingPayout,
  });

  num? dailySales;
  num? salesDelta;
  num? activeOrders;
  num? lowStock;
  double? rating;
  int? ratingCount;
  num? totalProducts;
  num? totalOrders;
  num? pendingPayout;

  factory VendorStats.fromJson(Map<String, dynamic> j) {
    final overview = j['overview'] is Map ? Map<String, dynamic>.from(j['overview']) : j;
    return VendorStats(
      dailySales: (overview['dailySales'] ?? overview['todaySales'] ?? overview['salesToday'] ?? overview['revenue'] ?? overview['sales']) as num?,
      salesDelta: (overview['salesDelta'] ?? overview['salesChange'] ?? overview['revenueChange']) as num?,
      activeOrders: (overview['activeOrders'] ?? overview['openOrders'] ?? overview['orders'] ?? overview['pendingOrders']) as num?,
      lowStock: (overview['lowStock'] ?? overview['lowStockProducts'] ?? overview['lowStockAlerts'] ?? overview['outOfStock']) as num?,
      rating: (overview['rating'] ?? overview['averageRating'] ?? overview['storeRating'])?.toDouble(),
      ratingCount: _int(overview['ratingCount'] ?? overview['totalRatings'] ?? overview['reviewsCount']),
      totalProducts: (overview['totalProducts'] ?? overview['productCount']) as num?,
      totalOrders: (overview['totalOrders'] ?? overview['ordersCount']) as num?,
      pendingPayout: (overview['pendingPayout'] ?? overview['pendingPayouts'] ?? overview['balance']) as num?,
    );
  }

  static int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
}
