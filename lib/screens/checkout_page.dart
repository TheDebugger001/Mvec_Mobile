import 'package:flutter/material.dart';
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

  final List<String> _paymentMethods = ['Mobile Money', 'Credit / Debit Card'];

  bool _isSubmitting = false;
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
                      '\$${item.totalPrice.toStringAsFixed(2)}',
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
    final isMobileMoney = _selectedPaymentMethod == 'Mobile Money';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _paymentInputController,
        keyboardType:
            isMobileMoney ? TextInputType.phone : TextInputType.number,
        decoration: InputDecoration(
          labelText:
              isMobileMoney ? 'Mobile money phone number' : 'Card number',
          hintText: isMobileMoney ? '+2507 -------' : '1234 5678 9012 3456',
          prefixIcon: Icon(
            isMobileMoney ? Icons.phone_outlined : Icons.credit_card_outlined,
          ),
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
          '\$${amount.toStringAsFixed(2)}',
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

    // Simulate API call
    await Future.delayed(const Duration(seconds: 2));

    setState(() => _isSubmitting = false);

    if (mounted) {
      // Show success
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
                  const Icon(
                    Icons.check_circle,
                    color: MvColors.successText,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Order Placed!',
                    style: TextStyle(color: context.mv.text),
                  ),
                ],
              ),
              content: const Text(
                'Your order has been placed successfully. You will receive a confirmation soon.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // close dialog
                    widget.onOrderPlaced(_buildOrder());
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    }
  }

  Order _buildOrder() {
    return Order(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      orderNumber: 'MV-${DateTime.now().millisecondsSinceEpoch}',
      orderDate: DateTime.now(),
      status: OrderStatus.confirmed,
      items: List<CartItem>.from(widget.cartItems),
      deliveryAddress: _selectedAddress!,
      paymentMethod: _selectedPaymentMethod,
      subtotal: widget.subtotal,
      shippingFee: widget.shippingFee,
      serviceFee: widget.serviceFee,
      tax: widget.tax,
      total: widget.total,
      trackingNumber: 'TRK-${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
