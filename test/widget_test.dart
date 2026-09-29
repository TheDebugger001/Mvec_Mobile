// Smoke tests for the merged MVEC app: the authentication flow (login /
// registration / forgot password) and the role-based routing behind it, plus
// the marketplace shell (floating bottom nav, home feed, cart, wishlist).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mvec_mobile/features/marketplace/presentation/Screens/home_screen.dart';
import 'package:mvec_mobile/features/marketplace/presentation/Screens/main_navigation.dart';
import 'package:mvec_mobile/features/marketplace/presentation/providers/commerce_provider.dart';
import 'package:mvec_mobile/main.dart';
import 'package:mvec_mobile/models/product.dart';
import 'package:mvec_mobile/models/supplier.dart';
import 'package:mvec_mobile/models/user.dart';
import 'package:mvec_mobile/providers/auth_provider.dart';
import 'package:mvec_mobile/screens/auth/auth_validation.dart';
import 'package:mvec_mobile/screens/suppliers/supplier_shell.dart';

Product _demoProduct() => Product(
      id: 'p1',
      name: 'Test Product',
      description: 'A product used by the provider tests.',
      price: 10,
      oldPrice: 12,
      stock: 5,
      images: const <String>[],
      colors: const <String>[],
      sizes: const <String>[],
      vendor: Vendor(id: 'v1', name: 'Test Vendor', logo: '', rating: 4.5, totalProducts: 1),
    );

/// Auth controller stub so a test can boot the app as a signed-in role
/// without touching secure storage or the network.
class _StubAuthController extends AuthController {
  _StubAuthController(this.user);

  final UserRecord? user;

  @override
  AuthState build() => AuthState(
        session: user == null
            ? null
            : AuthSession(token: 'test-token', user: user!),
      );
}

UserRecord _user(String role) => UserRecord(
      id: 'u1',
      fullname: 'Test User',
      email: 'test@example.com',
      role: role,
    );

/// Boots the signed-out app (login screen).
Future<void> _pumpSignedOut(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: MvecApp()));
  await tester.pumpAndSettle();
}

/// Boots the app as [role]; the router then sends the user to the landing
/// route for that role.
Future<void> _pumpSignedIn(WidgetTester tester, String role) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _StubAuthController(_user(role))),
      ],
      child: const MvecApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Like [_pumpSignedIn] but for dashboards, whose live providers never settle
/// (they poll the network), so we advance a bounded number of frames instead.
Future<void> _pumpDashboard(WidgetTester tester, String role) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _StubAuthController(_user(role))),
      ],
      child: const MvecApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}
/// The marketplace is served by mock data in tests, so the home feed and its
/// product grids always have content.
Future<void> _pumpMarketplace(WidgetTester tester) async {
  await _pumpSignedIn(tester, 'buyer');
  expect(find.byType(MainNavigation), findsOneWidget);
}

void main() {
  // Keep widget tests offline and deterministic: never fetch fonts at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;

  group('validation helpers', () {
    test('email / phone validation', () {
      expect(validateEmailOrPhone(''), isNotNull);
      expect(validateEmailOrPhone('not-an-email'), isNotNull);
      expect(validateEmailOrPhone('72xxxxxx'), isNotNull);
      expect(validateEmailOrPhone('user@example.com'), isNull);
      expect(validateEmailOrPhone('+250791234567'), isNull);
      expect(validatePhone('abcd'), isNotNull);
      expect(validatePhone('+250 791 234 567'), isNull);
      expect(validateEmail(''), isNull);
      expect(validateEmail('bad'), isNotNull);
    });

    test('password validation', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('123'), isNotNull);
      expect(validatePassword('123456'), isNull);
      expect(validateConfirmPassword('123', '456'), isNotNull);
      expect(validateConfirmPassword('456', '456'), isNull);
    });

    test('full name and otp validation', () {
      expect(validateFullName('Narada'), isNotNull);
      expect(validateFullName('Narada Test'), isNull);
      expect(validateOtp('123'), isNotNull);
      expect(validateOtp('abcdef'), isNotNull);
      expect(validateOtp('123456'), isNull);
    });
  });

  group('role routing', () {
    test('super admin goes to the dashboard', () {
      expect(roleHome(_user('super_admin')), '/admin');
    });

    test('supplier lands on the supplier portal', () {
      expect(roleHome(_user('supplier')), '/supplier');
    });

    test('buyer, vendor and affiliate land on the home feed', () {
      for (final role in ['buyer', 'vendor', 'affiliate']) {
        expect(roleHome(_user(role)), '/home', reason: role);
      }
    });
  });

  group('app boot', () {
    testWidgets('boots to the login screen', (tester) async {
      await _pumpSignedOut(tester);

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Email or telephone'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('empty login submit shows validation errors',
        (tester) async {
      await _pumpSignedOut(tester);

      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email or telephone.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('invalid email shows a validation error', (tester) async {
      await _pumpSignedOut(tester);

      await tester.enterText(find.byType(TextFormField).first, 'bad@email');
      await tester.enterText(find.byType(TextFormField).last, 'password1');
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });
  });

  group('registration', () {
    Future<void> openRegister(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Create one'));
      await tester.tap(find.text('Create one'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens from the login screen and shows four user types',
        (tester) async {
      await _pumpSignedOut(tester);
      await openRegister(tester);

      expect(find.text('Create your account'), findsOneWidget);
      for (final role in ['Buyer', 'Vendor', 'Supplier', 'Affiliate']) {
        expect(find.text(role), findsOneWidget, reason: role);
      }
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Telephone'), findsOneWidget);
    });

    testWidgets('selecting a vendor shows the company field',
        (tester) async {
      await _pumpSignedOut(tester);
      await openRegister(tester);

      expect(find.text('Company name'), findsNothing);

      await tester.tap(find.text('Vendor'));
      await tester.pumpAndSettle();

      expect(find.text('Company name'), findsOneWidget);
    });

    testWidgets('register validation catches missing and mismatched fields',
        (tester) async {
      await _pumpSignedOut(tester);
      await openRegister(tester);

      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Enter your telephone number.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);

      // Field order for a buyer: name, telephone, email, password, confirm.
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(3), 'password1');
      await tester.enterText(fields.at(4), 'password2');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });
  });

  group('forgot password', () {
    testWidgets('opens from login and renders the request form',
        (tester) async {
      await _pumpSignedOut(tester);

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('Forgot your password?'), findsOneWidget);
      expect(find.text('Email or telephone'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('validates the identity before sending', (tester) async {
      await _pumpSignedOut(tester);

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email or telephone.'), findsOneWidget);
    });
  });

  group('signed-in routing', () {
    testWidgets('a buyer lands on the marketplace home feed',
        (tester) async {
      await _pumpSignedIn(tester, 'buyer');

      expect(find.byType(MainNavigation), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
    });

    testWidgets('a super admin lands on the control-center dashboard',
        (tester) async {
      // The dashboard loads live providers, so its spinners never settle in a
      // test: pump a bounded number of frames instead of pumpAndSettle.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _StubAuthController(_user('super_admin')),
            ),
          ],
          child: const MvecApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('SUPER ADMIN DASHBOARD'), findsOneWidget);
      expect(find.byType(MainNavigation), findsNothing);
      expect(find.text('Welcome back'), findsNothing);
    });
  });

  group('marketplace shell', () {
    testWidgets('renders the floating bottom nav, categories and home feed',
        (tester) async {
      await _pumpMarketplace(tester);

      // Bottom nav is icons only: the four primary destinations.
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pie_chart_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

      // Top bar keeps search, wishlist, cart and account reachable.
      expect(find.text('Search products, brands & more'), findsOneWidget);
      expect(find.byTooltip('Wishlist'), findsOneWidget);
      expect(find.byTooltip('Cart'), findsOneWidget);
      expect(find.byTooltip('Account'), findsOneWidget);

      // The destinations that do not fit in the bottom nav stay reachable.
      expect(find.byTooltip('All Categories'), findsOneWidget);
      expect(find.byTooltip('Vendors'), findsOneWidget);
      expect(find.byTooltip('Orders'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);

      expect(find.textContaining('demo data'), findsOneWidget);
    });

    testWidgets('tapping a bottom nav icon switches the body',
        (tester) async {
      await _pumpMarketplace(tester);

      await tester.tap(find.byIcon(Icons.pie_chart_rounded));
      await tester.pumpAndSettle();

      // The For You screen renders its sections once it is active.
      expect(find.text('Recently Viewed'), findsOneWidget);
    });

    testWidgets('tapping a category pill filters the shop catalog',
        (tester) async {
      await _pumpMarketplace(tester);

      // Category pills jump straight to the Shop tab.
      await tester.tap(find.widgetWithText(Ink, 'Electronics'));
      await tester.pumpAndSettle();

      // Electronics product visible, Fashion product filtered out.
      expect(find.text('Gaming Mechanical Keyboard'), findsOneWidget);
      expect(find.text('Linen Summer Dress'), findsNothing);
    });

    testWidgets('opens search, categories, vendors and orders pages',
        (tester) async {
      await _pumpMarketplace(tester);

      await tester.tap(find.text('Search products, brands & more'));
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('All Categories'));
      await tester.pumpAndSettle();
      expect(find.text('All Categories'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Vendors'));
      await tester.pumpAndSettle();
      expect(find.text('Vendors'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Orders'));
      await tester.pumpAndSettle();
      expect(find.text('My Orders'), findsWidgets);
    });
  });

  group('marketplace cart and wishlist', () {
    /// Scrolls the home feed far enough to bring the product rows onstage.
    Future<void> scrollToProducts(WidgetTester tester) async {
      final homeList = find
          .descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(ListView),
          )
          .first;
      await tester.drag(homeList, const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    Badge badgeFor(WidgetTester tester, String countKey) =>
        tester.widget<Badge>(find.byKey(ValueKey<String>(countKey)));

    testWidgets('product cards add directly to cart and wishlist',
        (tester) async {
      await _pumpMarketplace(tester);
      await scrollToProducts(tester);

      expect(find.byTooltip('Add to cart'), findsWidgets);
      expect(badgeFor(tester, 'home-cart-count').isLabelVisible, isFalse);

      await tester.tap(find.byTooltip('Add to cart').first);
      await tester.pumpAndSettle();
      expect((badgeFor(tester, 'home-cart-count').label as Text).data, '1');

      await tester.tap(find.byTooltip('Add to wishlist').first);
      await tester.pumpAndSettle();
      expect((badgeFor(tester, 'home-wishlist-count').label as Text).data, '1');
    });

    testWidgets('adding a wishlisted product to cart clears the wishlist',
        (tester) async {
      await _pumpMarketplace(tester);
      await scrollToProducts(tester);

      await tester.tap(find.byTooltip('Add to wishlist').first);
      await tester.pumpAndSettle();
      expect(badgeFor(tester, 'home-wishlist-count').isLabelVisible, isTrue);

      await tester.tap(find.byTooltip('Add to cart').first);
      await tester.pumpAndSettle();

      expect(badgeFor(tester, 'home-wishlist-count').isLabelVisible, isFalse);
      expect((badgeFor(tester, 'home-cart-count').label as Text).data, '1');

      await tester.tap(find.byTooltip('Cart'));
      await tester.pumpAndSettle();
      expect(find.text('My Cart'), findsOneWidget);
      expect(
        find.textContaining('Wireless Over-Ear Headphones'),
        findsOneWidget,
      );
    });

    testWidgets('product detail opens, adds to cart and reaches the cart',
        (tester) async {
      await _pumpMarketplace(tester);
      await scrollToProducts(tester);

      await tester.tap(find.text('Wireless Over-Ear Headphones').first);
      await tester.pumpAndSettle();

      expect(find.text('In Stock (42)'), findsOneWidget);
      expect(find.text('Add to Cart'), findsOneWidget);
      expect(find.byTooltip('Open wishlist'), findsOneWidget);
      expect(find.byTooltip('Open cart'), findsOneWidget);

      await tester.tap(find.text('Add to Cart'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open cart'));
      await tester.pumpAndSettle();
      expect(find.text('My Cart'), findsOneWidget);
      expect(
        find.textContaining('Wireless Over-Ear Headphones'),
        findsWidgets,
      );
    });

    testWidgets('wishlist page moves an item into the cart',
        (tester) async {
      await _pumpMarketplace(tester);
      await scrollToProducts(tester);

      await tester.tap(find.byTooltip('Add to wishlist').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Wishlist'));
      await tester.pumpAndSettle();
      expect(find.text('My Wishlist'), findsOneWidget);
      expect(find.text('Wireless Over-Ear Headphones'), findsWidgets);

      await tester.tap(find.text('Move to Cart'));
      await tester.pumpAndSettle();
      expect(find.text('Your wishlist is empty'), findsOneWidget);

      await tester.tap(find.byTooltip('Open cart'));
      await tester.pumpAndSettle();
      expect(find.text('My Cart'), findsOneWidget);
      // The cart line and the confirmation snackbar both name the product.
      expect(
        find.textContaining('Wireless Over-Ear Headphones'),
        findsWidgets,
      );
    });
  });

  group('providers', () {
    test('commerce provider keeps cart and wishlist in sync', () {
      final provider = CommerceProvider();
      final product = _demoProduct();

      expect(provider.isWishlisted(product), isFalse);
      provider.toggleWishlist(product);
      expect(provider.isWishlisted(product), isTrue);
      expect(provider.wishlistItems, hasLength(1));

      provider.addToCart(product);
      expect(provider.isWishlisted(product), isFalse);
      expect(provider.cartItems, hasLength(1));

      provider.addToCart(product);
      expect(provider.cartItems.single.quantity, 2);

      provider.clearCart();
      expect(provider.cartItems, isEmpty);
    });
  });

  group('supplier models', () {
    test('profile is unverified until the backend says otherwise', () {
      final s = SupplierDetail.fromJson({'id': 's1', 'businessName': 'Rwanda Fresh'});
      expect(s.display, 'Rwanda Fresh');
      expect(s.isVerified, isFalse);
      expect(s.isPending, isFalse);
      // No verification state and no account status reported yet.
      expect(s.effectiveStatus, 'UNVERIFIED');
    });

    test('verified suppliers report verified regardless of account status', () {
      final s = SupplierDetail.fromJson({
        'id': 's1',
        'status': 'ACTIVE',
        'verificationStatus': 'VERIFIED',
      });
      expect(s.isVerified, isTrue);
      expect(s.effectiveStatus, 'VERIFIED');
    });

    test('a supplier without a profile is reported as not onboarded', () {
      final s = SupplierDetail.fromJson({'id': 's1'});
      expect(s.isOnboarded, isFalse);
      expect(s.display, 'Unnamed supplier');
    });

    test('stock quantity drives the availability label', () {
      SupplierProduct at(int stock, {int? moq}) => SupplierProduct.fromJson({
            'id': 'p1',
            'name': 'Coffee',
            'stockQuantity': stock,
            if (moq != null) 'moq': moq,
          });

      expect(at(0).isOutOfStock, isTrue);
      expect(at(0).stockStatus, 'Out of Stock');
      // Low stock is derived from the MOQ: fewer units left than one order needs.
      expect(at(3, moq: 5).isLowStock, isTrue);
      expect(at(50, moq: 5).stockStatus, 'In Stock');
    });

    test('metrics are derived from the catalogue', () {
      final m = SupplierMetrics.fromCatalog([
        SupplierProduct.fromJson({
          'id': 'p1',
          'name': 'Coffee',
          'status': 'ACTIVE',
          'stockQuantity': 10,
          'wholesalePrice': 1000,
        }),
        SupplierProduct.fromJson({
          'id': 'p2',
          'name': 'Sugar',
          'stockQuantity': 0,
        }),
        SupplierProduct.fromJson({
          'id': 'p3',
          'name': 'Archived thing',
          'status': 'ARCHIVED',
          'stockQuantity': 4,
          'wholesalePrice': 500,
        }),
      ]);

      expect(m.totalProducts, 3);
      expect(m.activeProducts, 1);
      expect(m.outOfStockProducts, 1);
      // Archived products are skipped entirely by `fromCatalog`.
      expect(m.totalUnitsInStock, 10);
      expect(m.totalCatalogValue, 10000);
    });

    test('bulk discount is applied to the effective unit price', () {
      final p = SupplierProduct.fromJson({
        'id': 'p1',
        'name': 'Coffee',
        'wholesalePrice': 1000,
        'bulkDiscount': 25,
      });
      expect(p.effectivePrice, 750);
    });
  });

  group('supplier portal routing', () {
    testWidgets('a supplier lands on the supplier dashboard shell',
        (tester) async {
      await _pumpDashboard(tester, 'supplier');

      expect(find.byType(SupplierShell), findsOneWidget);
      expect(find.text('SUPPLIER DASHBOARD'), findsOneWidget);
      expect(find.text('SUPPLIER'), findsOneWidget);
    });

    testWidgets('a buyer is kept out of the supplier portal', (tester) async {
      await _pumpSignedIn(tester, 'buyer');

      expect(find.byType(SupplierShell), findsNothing);
      expect(find.byType(MainNavigation), findsOneWidget);
    });
  });
}
