import 'format.dart';

/// Buyer-side order rules. They mirror the backend (`order.controller.js`) so
/// the buttons shown match what the server will accept; the server still decides.
const cancelWindow = Duration(minutes: 30);
const _cancellable = ['PENDING', 'CONFIRMED', 'PROCESSING'];

bool isAwaitingPayment(Map<String, dynamic> o) => o['paymentStatus'] == 'PENDING' && o['orderStatus'] == 'PENDING';

/// Time left to cancel a paid order for a full refund (zero when not allowed).
Duration paidCancelRemaining(Map<String, dynamic> o, [DateTime? now]) {
  if (o['paymentStatus'] != 'PAID' || !_cancellable.contains(o['orderStatus'])) return Duration.zero;
  final paidAt = parseDate(o['paidAt'] ?? o['updatedAt'] ?? o['createdAt']);
  if (paidAt == null) return Duration.zero;
  final left = cancelWindow - (now ?? DateTime.now()).difference(paidAt);
  return left.isNegative ? Duration.zero : left;
}

bool canCancel(Map<String, dynamic> o, [DateTime? now]) =>
    isAwaitingPayment(o) || paidCancelRemaining(o, now) > Duration.zero;

String countdown(Duration d) {
  final s = d.inSeconds.clamp(0, 1 << 30);
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Plain-language status for buyers.
String buyerStatus(Map<String, dynamic> o) {
  final status = '${o['orderStatus'] ?? ''}';
  final pay = '${o['paymentStatus'] ?? ''}';
  if (status == 'CANCELLED') return pay == 'REFUNDED' ? 'Cancelled · refunded' : 'Cancelled';
  if (status == 'REFUNDED') return 'Refunded';
  if (pay == 'DISPUTED') return 'Problem reported · under review';
  if (isAwaitingPayment(o)) return 'Awaiting payment';
  const labels = {
    'PENDING': 'Order placed',
    'CONFIRMED': 'Confirmed',
    'PROCESSING': 'Being prepared',
    'READY_FOR_SHIPMENT': 'Ready to ship',
    'SHIPPED': 'Shipped',
    'OUT_FOR_DELIVERY': 'Out for delivery',
    'DELIVERED': 'Delivered',
    'COMPLETED': 'Completed',
    'RETURNED': 'Returned',
    'REFUNDED': 'Refunded',
    'FAILED': 'Failed',
  };
  return labels[status] ?? status;
}
