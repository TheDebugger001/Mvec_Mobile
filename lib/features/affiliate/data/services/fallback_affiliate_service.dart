
import '../../../../core/api_client.dart';
import '../models/affiliate_earnings.dart';
import '../models/affiliate_marketing.dart';
import '../models/affiliate_profile.dart';
import 'affiliate_service.dart';
import 'api_affiliate_service.dart';

/// Backend-first affiliate service. Any unavailable route is surfaced as an
/// error instead of falling back to bundled demo data.
class FallbackAffiliateService implements AffiliateService {
  FallbackAffiliateService(ApiClient api, {AffiliateService? fallback, bool? forceDemo})
      : _api = ApiAffiliateService(api),
        _fallback = fallback,
        _forceDemo = forceDemo ?? false;

  final ApiAffiliateService _api;
  final AffiliateService? _fallback;
  final bool _forceDemo;

  @override
  bool get isDemo => false;

  String? get fallbackReason => null;

  Future<T> _resolve<T>(Future<T> Function(AffiliateService s) call, {required String sourceLabel}) async {
    return call(_api);
  }

  @override
  Future<AffiliateProfile> fetchProfile() => _resolve((s) => s.fetchProfile(), sourceLabel: 'profile');

  @override
  Future<AffiliateProfile> updateProfile(AffiliateProfile draft) => _resolve((s) => s.updateProfile(draft), sourceLabel: 'profile');

  @override
  Future<AffiliateVerification> fetchVerification() => _resolve((s) => s.fetchVerification(), sourceLabel: 'verification');

  @override
  Future<AffiliateOverview> fetchOverview() => _resolve((s) => s.fetchOverview(), sourceLabel: 'overview');

  @override
  Future<AffiliateDashboard> fetchDashboard() => _resolve((s) => s.fetchDashboard(), sourceLabel: 'dashboard');

  @override
  Future<List<AffiliateLink>> fetchLinks() => _resolve((s) => s.fetchLinks(), sourceLabel: 'links');

  @override
  Future<AffiliateLink> generateLink({String? productId, String? campaignId, String? label}) =>
      _resolve((s) => s.generateLink(productId: productId, campaignId: campaignId, label: label), sourceLabel: 'links');

  @override
  Future<AffiliateLink> setLinkActive(String id, bool active) => _resolve((s) => s.setLinkActive(id, active), sourceLabel: 'links');

  @override
  Future<void> deleteLink(String id) => _resolve((s) => s.deleteLink(id), sourceLabel: 'links');

  @override
  Future<List<PromotableProduct>> fetchPromotableProducts({String? search, String? campaignId}) =>
      _resolve((s) => s.fetchPromotableProducts(search: search, campaignId: campaignId), sourceLabel: 'products');

  @override
  Future<List<AffiliateCampaign>> fetchCampaigns() => _resolve((s) => s.fetchCampaigns(), sourceLabel: 'campaigns');

  @override
  Future<AffiliateCampaign> joinCampaign(String id) => _resolve((s) => s.joinCampaign(id), sourceLabel: 'campaigns');

  @override
  Future<AffiliateStats> fetchStats({String range = '30d'}) => _resolve((s) => s.fetchStats(range: range), sourceLabel: 'stats');

  @override
  Future<AffiliateWallet> fetchWallet() => _resolve((s) => s.fetchWallet(), sourceLabel: 'wallet');

  @override
  Future<List<AffiliateCommission>> fetchCommissions({String? status}) => _resolve((s) => s.fetchCommissions(status: status), sourceLabel: 'commissions');

  @override
  Future<List<AffiliateConversion>> fetchConversions() => _resolve((s) => s.fetchConversions(), sourceLabel: 'conversions');

  @override
  Future<void> trackClick(String code) => _resolve((s) => s.trackClick(code), sourceLabel: 'track');

  @override
  Future<List<AffiliatePayout>> fetchPayouts() => _resolve((s) => s.fetchPayouts(), sourceLabel: 'payouts');

  @override
  Future<AffiliatePayout> requestPayout({required num amount, required String paymentMethod, required String accountName, required String phoneNumber, String? bankName}) =>
      _resolve(
        (s) => s.requestPayout(amount: amount, paymentMethod: paymentMethod, accountName: accountName, phoneNumber: phoneNumber, bankName: bankName),
        sourceLabel: 'payouts',
      );

  @override
  Future<List<AffiliateNotification>> fetchNotifications() => _resolve((s) => s.fetchNotifications(), sourceLabel: 'notifications');

  @override
  Future<void> markNotificationsRead([String? id]) => _resolve((s) => s.markNotificationsRead(id), sourceLabel: 'notifications');

  @override
  Future<AffiliateSettings> fetchSettings() => _resolve((s) => s.fetchSettings(), sourceLabel: 'settings');

  @override
  Future<AffiliateSettings> updateSettings(AffiliateSettings settings) => _resolve((s) => s.updateSettings(settings), sourceLabel: 'settings');
}