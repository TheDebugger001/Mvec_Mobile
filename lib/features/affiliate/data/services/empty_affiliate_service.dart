import '../../../../core/api_client.dart';
import '../models/affiliate_earnings.dart';
import '../models/affiliate_marketing.dart';
import '../models/affiliate_profile.dart';
import 'affiliate_service.dart';

/// Empty-state implementation of [AffiliateService].
///
/// The bundled dataset this used to serve is gone, so every read now resolves to
/// the zeroed shape [ApiAffiliateService] would produce for an affiliate with no
/// activity yet: an empty profile, no links, no campaigns, no commissions, no
/// payouts and flat series. The affiliate screens therefore render their empty
/// states and zeroed metrics instead of invented figures while the affiliate
/// routes are being connected.
///
/// Reads are safe and always succeed. Writes throw an [ApiException] so the
/// forms report a real failure rather than acknowledging records the backend
/// never stored.
class EmptyAffiliateService implements AffiliateService {
  EmptyAffiliateService({this.delay = Duration.zero});

  final Duration delay;

  @override
  bool get isDemo => false;

  Future<T> _latency<T>(T value) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return value;
  }

  Never _writeUnsupported(String what) => throw ApiException(
    '$what is not available yet — this endpoint has not shipped.',
    statusCode: 501,
  );

  // ---------- Profile & verification ----------

  @override
  Future<AffiliateProfile> fetchProfile() => _latency(const AffiliateProfile());

  @override
  Future<AffiliateProfile> updateProfile(AffiliateProfile draft) =>
      _writeUnsupported('Saving the affiliate profile');

  @override
  Future<AffiliateVerification> fetchVerification() =>
      _latency(const AffiliateVerification(status: 'UNVERIFIED'));

  // ---------- Dashboard ----------

  @override
  Future<AffiliateOverview> fetchOverview() => _latency(const AffiliateOverview());

  // ---------- Referral links ----------

  @override
  Future<List<AffiliateLink>> fetchLinks() => _latency(const <AffiliateLink>[]);

  @override
  Future<AffiliateLink> generateLink({
    String? productId,
    String? campaignId,
    String? label,
  }) => _writeUnsupported('Referral links');

  @override
  Future<AffiliateLink> setLinkActive(String id, bool active) =>
      _writeUnsupported('Referral links');

  @override
  Future<void> deleteLink(String id) => _writeUnsupported('Referral links');

  // ---------- Sharing ----------

  @override
  Future<List<PromotableProduct>> fetchPromotableProducts({
    String? search,
    String? campaignId,
  }) => _latency(const <PromotableProduct>[]);

  @override
  Future<List<AffiliateCampaign>> fetchCampaigns() =>
      _latency(const <AffiliateCampaign>[]);

  @override
  Future<AffiliateCampaign> joinCampaign(String id) =>
      _writeUnsupported('Campaigns');

  // ---------- Statistics ----------

  @override
  Future<AffiliateStats> fetchStats({String range = '30d'}) =>
      _latency(const AffiliateStats());

  // ---------- Earnings ----------

  @override
  Future<AffiliateWallet> fetchWallet() => _latency(const AffiliateWallet());

  @override
  Future<List<AffiliateCommission>> fetchCommissions({String? status}) =>
      _latency(const <AffiliateCommission>[]);

  // ---------- Payouts ----------

  @override
  Future<List<AffiliatePayout>> fetchPayouts() =>
      _latency(const <AffiliatePayout>[]);

  @override
  Future<AffiliatePayout> requestPayout({
    required num amount,
    required String paymentMethod,
    required String accountName,
    required String phoneNumber,
    String? bankName,
  }) => _writeUnsupported('Withdrawals');

  // ---------- Notifications ----------

  @override
  Future<List<AffiliateNotification>> fetchNotifications() =>
      _latency(const <AffiliateNotification>[]);

  @override
  Future<void> markNotificationsRead([String? id]) =>
      _writeUnsupported('Notifications');

  // ---------- Settings ----------

  @override
  Future<AffiliateSettings> fetchSettings() =>
      _latency(const AffiliateSettings());

  @override
  Future<AffiliateSettings> updateSettings(AffiliateSettings settings) =>
      _writeUnsupported('Saving affiliate settings');
}
