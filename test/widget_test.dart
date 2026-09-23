// Smoke tests for the marketplace app shell: top menu + home feed render.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mvec_mobile/features/marketplace/presentation/Screens/home_screen.dart';
import 'package:mvec_mobile/main.dart';
import 'package:mvec_mobile/models/address.dart';
import 'package:mvec_mobile/models/cart_item.dart';
import 'package:mvec_mobile/models/order.dart';
import 'package:mvec_mobile/screens/track_order_page.dart';

void main() {
  testWidgets('App boots to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MvecAdminApp()));

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ADMIN CONTROL'), findsOneWidget);
    expect(find.text('Email or telephone'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  testWidgets('product detail screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Classic Leather Backpack'), findsOneWidget);
    expect(find.text('Add to Cart'), findsOneWidget);
  });

  testWidgets('wishlist stays connected to product detail',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Open wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('My Wishlist'), findsOneWidget);
    expect(find.text('Classic Leather Backpack'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pump();

    expect(find.text('Your wishlist is empty'), findsOneWidget);
  });

  testWidgets('wishlist product can be moved to cart',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Open wishlist'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move to Cart'));
    await tester.pump();
    expect(find.text('Your wishlist is empty'), findsOneWidget);

    await tester.tap(find.byTooltip('Open cart'));
    await tester.pumpAndSettle();

    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Classic Leather Backpack'), findsOneWidget);
  });

  testWidgets('cart shows added products and supports removal',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Add to Cart'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Open cart'));
    await tester.pumpAndSettle();

    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Classic Leather Backpack'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from cart'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Are you sure you want to delete Classic Leather Backpack from your cart?',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.text('Classic Leather Backpack'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('cart opens checkout with the current order',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Add to Cart'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.byTooltip('Open cart'));
    await tester.pumpAndSettle();

    final checkoutButton = find.text('Proceed to Checkout');
    await tester.ensureVisible(checkoutButton);
    final checkoutAction = tester.widget<ElevatedButton>(
      find.ancestor(
        of: checkoutButton,
        matching: find.byType(ElevatedButton),
      ),
    );
    checkoutAction.onPressed!();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('No delivery address added yet. Add one to continue.'),
      findsOneWidget);
    expect(find.text('Order Review'), findsOneWidget);
    expect(find.text('Classic Leather Backpack'), findsOneWidget);
    expect(find.text('Confirm & Place Order'), findsOneWidget);
    expect(find.text('Cash on Delivery'), findsNothing);
    expect(find.text('Mobile money phone number'), findsOneWidget);

    final cardMethod = tester.widget<GestureDetector>(
      find.ancestor(
        of: find.text('Credit / Debit Card'),
        matching: find.byType(GestureDetector),
      ),
    );
    cardMethod.onTap!();
    await tester.pump();
    expect(find.text('Card number'), findsOneWidget);
    expect(find.text('Mobile money phone number'), findsNothing);

    await tester.tap(find.text('Add New Address'));
    await tester.pumpAndSettle();

    final addressFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(addressFields.at(0), '');
    await tester.enterText(addressFields.at(1), '');
    await tester.enterText(addressFields.at(2), '');
    await tester.enterText(addressFields.at(3), '');
    await tester.enterText(addressFields.at(4), '');
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();

    expect(
      find.text('No delivery address added yet. Add one to continue.'),
      findsOneWidget,
    );
    expect(find.text('Enter Full name'), findsOneWidget);
  });

  testWidgets('track order page displays the placed order',
      (WidgetTester tester) async {
    final order = Order(
      id: 'order-1',
      orderNumber: 'MV-1001',
      orderDate: DateTime(2026, 9, 22),
      status: OrderStatus.confirmed,
      items: [CartItem(product: demoProduct)],
      deliveryAddress: Address(
        id: 'address-1',
        fullName: 'Amina Hassan',
        phone: '+2507 -------',
        addressLine: '12 Mlimani Road',
        city: 'Kigali',
        region: 'Kigali',
      ),
      paymentMethod: 'Mobile Money',
      subtotal: demoProduct.price,
      shippingFee: 5,
      serviceFee: 2.5,
      tax: demoProduct.price * 0.08,
      total: demoProduct.price + 5 + 2.5 + demoProduct.price * 0.08,
      trackingNumber: 'TRK-1001',
    );

    await tester.pumpWidget(
      MaterialApp(home: TrackOrderPage(order: order)),
    );

    expect(find.text('Track Order'), findsOneWidget);
    expect(find.text('Order #MV-1001'), findsOneWidget);
    expect(find.text('Confirmed'), findsAtLeastNWidgets(1));
    expect(find.text('Amina Hassan'), findsOneWidget);
    expect(find.textContaining('TRK-1001'), findsOneWidget);
  testWidgets('renders the top menu and home feed', (WidgetTester tester) async {
    await tester.pumpWidget(const MvecApp());
    await tester.pumpAndSettle();

    // The horizontally scrollable top menu shows the marketplace tabs.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.textContaining('You are previewing demo data'), findsOneWidget);

    // Scroll the home feed down to reveal the featured products row.
    final homeList = find.descendant(
      of: find.byType(HomeScreen),
      matching: find.byType(ListView),
    );
    await tester.drag(homeList, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Wireless Over-Ear Headphones'), findsWidgets);
  });

  testWidgets('tapping a top menu item switches the body',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MvecApp());
    await tester.pumpAndSettle();

    // Scroll the top menu to reach the trailing Orders tab.
    final menu = find.byType(ListView).first;
    await tester.drag(menu, const Offset(-800, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();

    expect(find.text('#MV-20415'), findsOneWidget);
  });
}