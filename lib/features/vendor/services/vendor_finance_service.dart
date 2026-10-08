import '../../../core/api_client.dart';
import '../models/vendor_finance.dart';

/// Contract for the vendor's money: summary metrics, the transaction ledger and
/// withdrawal requests.
///
/// [ApiVendorFinanceService] is the shipped implementation; see
/// `vendor_dependencies.dart` for the wiring.
abstract class VendorFinanceService {
  /// True only when this service is answering from a bundled/local dataset.
  bool get isDemo;

  /// The four headline balances plus the commission rate and the daily series.
  Future<VendorFinanceSummary> summary();

  /// The money ledger, newest first, optionally narrowed to one [kind].
  Future<List<LedgerEntry>> ledger({LedgerEntryKind? kind, int limit = 50});

  /// Withdrawal requests, newest first. Pending ones are excluded from the
  /// available balance, so this list is what the payout form validates against.
  Future<List<PayoutRequest>> payouts();

  /// Requests a withdrawal of [amount].
  ///
  /// Throws when [amount] exceeds the available balance, falls under the
  /// platform minimum, or the destination is missing for the chosen [method].
  Future<PayoutRequest> requestPayout({
    required num amount,
    required PayoutMethod method,
    required String accountName,
    required String destination,
    String? note,
  });
}

/// Minimum withdrawal the platform will process, in RWF.
const double kMinPayoutAmount = 50000;

/// Talks to the platform's finance API.
class ApiVendorFinanceService implements VendorFinanceService {
  ApiVendorFinanceService(this._api);
  final ApiClient _api;

  @override
  bool get isDemo => false;

  @override
  Future<VendorFinanceSummary> summary() async {
    final res = await _api.get('/payouts/balance');
    final balance = singleJson(res, ['balance']);
    final earned = _number(balance['totalEarned']) ?? 0;
    final commissionRate = _number(
      res is Map ? res['commissionRate'] : null,
    );
    return VendorFinanceSummary(
      grossRevenue: earned + (_number(balance['commissionPaid']) ?? 0),
      commission: _number(balance['commissionPaid']) ?? 0,
      netEarnings: earned,
      escrowHeld: _number(balance['pendingBalance']) ?? 0,
      availablePayout: _number(balance['availableBalance']) ?? 0,
      commissionRate: commissionRate == null ? 0.1 : commissionRate / 100,
    );
  }

  @override
  Future<List<LedgerEntry>> ledger({LedgerEntryKind? kind, int limit = 50}) async {
    throw ApiException(
      'The backend does not expose a vendor transaction-ledger endpoint.',
    );
  }

  @override
  Future<List<PayoutRequest>> payouts() async {
    final res = await _api.get('/payouts/history');
    return listJson(res, ['payouts', 'withdrawals', 'data']).map(PayoutRequest.fromJson).toList();
  }

  @override
  Future<PayoutRequest> requestPayout({
    required num amount,
    required PayoutMethod method,
    required String accountName,
    required String destination,
    String? note,
  }) async {
    if (method == PayoutMethod.bankTransfer) {
      throw ApiException('The backend currently supports mobile-money payouts only.');
    }
    final res = await _api.post('/payouts/request', body: {
      'amount': amount,
      'payoutMethod': method == PayoutMethod.mtnMomo ? 'MOMO' : 'AIRTEL',
      'payoutDetails': {
        'accountName': accountName.trim(),
        'accountNumber': destination.trim(),
      },
    });
    return PayoutRequest.fromJson(singleJson(res, ['payout']));
  }

  static num? _number(dynamic value) =>
      value is num ? value : num.tryParse(value?.toString().replaceAll('%', '') ?? '');
}
