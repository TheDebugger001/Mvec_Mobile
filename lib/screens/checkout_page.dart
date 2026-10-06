import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../core/utils/app_theme.dart';
import '../models/cart_item.dart';
import '../models/address.dart';
import '../models/order.dart';

class CheckoutPage extends StatefulWidget {
  final List<CartItem> cartItems;
  final double subtotal;
  final double shippingFee;
  final double serviceFee;
  final double tax;
  final double total;
  final ValueChanged<Order> onOrderPlaced;

  const CheckoutPage({
    super.key,
    required this.cartItems,
    required this.subtotal,
    required this.shippingFee,
    required this.serviceFee,
    required this.tax,
    required this.total,
    required this.onOrderPlaced,
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final List<Address> _addresses = [];

  Address? _selectedAddress;
  String _selectedPaymentMethod = 'Mobile Money';

  final List<String> _paymentMethods = ['Mobile Money'];

  bool _isSubmitting = false;
  String? _pendingOrderId;
  Map<String, dynamic>? _pendingOrder;
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _regionController = TextEditingController();
  final _paymentInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    _paymentInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Checkout',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== 1. Delivery Address ==========
            _buildSectionTitle('Delivery Address'),
            const SizedBox(height: 10),
            _buildAddressSection(),
            const SizedBox(height: 24),

            // ========== 2. Order Review ==========
            _buildSectionTitle('Order Review'),
            const SizedBox(height: 10),
            _buildOrderReview(),
            const SizedBox(height: 24),

            // ========== 3. Payment Method ==========
            _buildSectionTitle('Payment Method'),
            const SizedBox(height: 10),
            _buildPaymentMethods(),
            const SizedBox(height: 24),

            // ========== 4. Order Summary ==========
            _buildSectionTitle('Order Summary'),
            const SizedBox(height: 10),
            _buildOrderSummary(),
            const SizedBox(height: 30),

            // ========== Place Order Button ==========
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child:
                    _isSubmitting
                        ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                        : const Text(
                          'Confirm & Place Order',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ==================== SECTION TITLE ====================
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: context.mv.text,
      ),
    );
  }

  // ==================== ADDRESS SECTION ====================
  Widget _buildAddressSection() {
    return Column(
      children: [
        if (_addresses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.mv.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.mv.border),
            ),
            child: Text(
              'No delivery address added yet. Add one to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.mv.textMuted),
            ),
          ),
        ..._addresses.map((address) {
          final isSelected = _selectedAddress?.id == address.id;
          final mv = context.mv;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedAddress = address;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: mv.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.primary : mv.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isSelected ? AppColors.primary : mv.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          address.fullName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: mv.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          address.phone,
                          style: TextStyle(color: mv.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${address.addressLine}, ${address.city}',
                          style: TextStyle(color: mv.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        // Add New Address Button
        OutlinedButton.icon(
          onPressed: _showAddAddressDialog,
          icon: const Icon(Icons.add),
          label: const Text('Add New Address'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddAddressDialog() async {
    final formKey = GlobalKey<FormState>();
    _fullNameController.clear();
    _phoneController.clear();
    _addressController.clear();
    _cityController.clear();
    _regionController.clear();

    final address = await showDialog<Address>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Add delivery address'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _addressField(_fullNameController, 'Full name'),
                    _addressField(
                      _phoneController,
                      'Phone number',
                      keyboardType: TextInputType.phone,
                    ),
                    _addressField(_addressController, 'Street address'),
                    _addressField(_cityController, 'City'),
                    _addressField(_regionController, 'Region'),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) {
                    return;
                  }
                  FocusScope.of(dialogContext).unfocus();
                  Navigator.pop(
                    dialogContext,
                    Address(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      fullName: _fullNameController.text.trim(),
                      phone: _phoneController.text.trim(),
                      addressLine: _addressController.text.trim(),
                      city: _cityController.text.trim(),
                      region: _regionController.text.trim(),
                      isDefault: _addresses.isEmpty,
                    ),
                  );
                },
                child: const Text('Save address'),
              ),
            ],
          ),
    );

    if (address != null && mounted) {
      setState(() {
        _addresses.add(address);
        _selectedAddress = address;
      });
    }
  }

  Widget _addressField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator:
            (value) =>
                value == null || value.trim().isEmpty ? 'Enter $label' : null,
      ),
    );
  }

  // ==================== ORDER REVIEW ====================
  Widget _buildOrderReview() {
    final mv = context.mv;
    return Container(
      decoration: BoxDecoration(
        color: mv.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mv.border),
      ),
      child: Column(
        children:
            widget.cartItems.map((item) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          item.product.images.isNotEmpty
                              ? Image.network(
                                item.product.images.first,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, _, _) => Container(
                                      width: 60,
                                      height: 60,
                                      color: mv.soft,
                                      child: const Icon(Icons.image),
                                    ),
                              )
                              : Container(
                                width: 60,
                                height: 60,
                                color: mv.soft,
                                child: const Icon(Icons.image),
                              ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: mv.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Qty: ${item.quantity}',
                            style: TextStyle(color: mv.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'RWF ${item.totalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: mv.text,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }

  // ==================== PAYMENT METHODS ====================
  Widget _buildPaymentMethods() {
    return Column(
      children:
          _paymentMethods.map((method) {
            final isSelected = _selectedPaymentMethod == method;
            final mv = context.mv;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPaymentMethod = method;
                  _paymentInputController.clear();
                });
              },
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: mv.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : mv.border,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: isSelected ? AppColors.primary : mv.textMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            method,
                            style: TextStyle(fontSize: 15, color: mv.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected) _buildPaymentInput(),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _buildPaymentInput() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _paymentInputController,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Mobile money phone number',
          hintText: '+2507 -------',
          prefixIcon: const Icon(Icons.phone_outlined),
        ),
      ),
    );
  }

  // ==================== ORDER SUMMARY ====================
  Widget _buildOrderSummary() {
    final mv = context.mv;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mv.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mv.border),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Subtotal', widget.subtotal),
          const SizedBox(height: 8),
          _buildSummaryRow('Shipping Fee', widget.shippingFee),
          const SizedBox(height: 8),
          _buildSummaryRow('Service Fee', widget.serviceFee),
          const SizedBox(height: 8),
          _buildSummaryRow('Tax', widget.tax),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(),
          ),
          _buildSummaryRow('Total', widget.total, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isTotal ? context.mv.text : context.mv.textMuted,
          ),
        ),
        Text(
          'RWF ${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: isTotal ? 17 : 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
            color: isTotal ? AppColors.primary : context.mv.text,
          ),
        ),
      ],
    );
  }

  // ==================== SUBMIT ORDER ====================
  Future<void> _submitOrder() async {
    if (_selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a delivery address')),
      );
      return;
    }

    if (_paymentInputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedPaymentMethod == 'Mobile Money'
                ? 'Enter your mobile money phone number'
                : 'Enter your card number',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final order =
          _pendingOrder ??
          singleJson(
            await ApiClient.instance.post(
              '/orders/direct-checkout',
              body: {
                'items': [
                  for (final item in widget.cartItems)
                    {'productId': item.product.id, 'qty': item.quantity},
                ],
                'shippingAddress': {
                  'fullName': _selectedAddress!.fullName,
                  'phone': _selectedAddress!.phone,
                  'street': _selectedAddress!.addressLine,
                  'city': _selectedAddress!.city,
                  'state': _selectedAddress!.region,
                  'country': 'Rwanda',
                },
                'paymentMethod': 'MOMO',
              },
            ),
            ['order'],
          );
      final orderId = _pendingOrderId ?? order['_id']?.toString();
      if (orderId == null || orderId.isEmpty) {
        throw const FormatException(
          'The backend created no order ID, so payment cannot be started.',
        );
      }
      _pendingOrderId = orderId;
      _pendingOrder = order;
      final payment = await ApiClient.instance.post(
        '/payments/pay',
        body: {
          'orderId': orderId,
          'phoneNumber': _paymentInputController.text.trim(),
        },
      );
      final paymentData = singleJson(payment, ['payment']);
      final paid = '${paymentData['status'] ?? ''}'.toUpperCase() == 'SUCCESS';
      final refreshedOrder = <String, dynamic>{
        ...order,
        if (paid) 'paymentStatus': 'PAID',
        if (paid) 'orderStatus': 'CONFIRMED',
      };
      _pendingOrderId = null;
      _pendingOrder = null;
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    paid ? Icons.check_circle : Icons.info_outline,
                    color: paid ? MvColors.successText : AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    paid ? 'Order Placed!' : 'Payment requested',
                    style: TextStyle(color: context.mv.text),
                  ),
                ],
              ),
              content: Text(
                paid
                    ? 'Payment confirmed. Your order has been placed.'
                    : 'Approve the payment prompt on your phone to complete the order.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // close dialog
                    widget.onOrderPlaced(_buildOrder(refreshedOrder));
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Checkout failed: $error')));
    }
  }

  Order _buildOrder(Map<String, dynamic> data) {
    final status = '${data['orderStatus'] ?? 'PENDING'}'.toUpperCase();
    return Order(
      id: '${data['_id'] ?? _pendingOrderId ?? ''}',
      orderNumber: '${data['orderNumber'] ?? '—'}',
      orderDate:
          DateTime.tryParse('${data['createdAt'] ?? ''}') ?? DateTime.now(),
      status: switch (status) {
        'CONFIRMED' => OrderStatus.confirmed,
        'PROCESSING' => OrderStatus.processing,
        'SHIPPED' => OrderStatus.shipped,
        'OUT_FOR_DELIVERY' => OrderStatus.outForDelivery,
        'DELIVERED' || 'COMPLETED' => OrderStatus.delivered,
        'CANCELLED' => OrderStatus.cancelled,
        _ => OrderStatus.pending,
      },
      items: List<CartItem>.from(widget.cartItems),
      deliveryAddress: _selectedAddress!,
      paymentMethod: _selectedPaymentMethod,
      subtotal: _number(data['totalAmount']) ?? widget.subtotal,
      shippingFee: widget.shippingFee,
      serviceFee: widget.serviceFee,
      tax: widget.tax,
      total: _number(data['totalAmount']) ?? widget.total,
    );
  }

  double? _number(dynamic value) =>
      value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
}
