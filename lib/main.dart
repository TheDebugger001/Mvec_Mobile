import 'package:flutter/material.dart';
import 'models/cart_item.dart';
import 'models/order.dart';
import 'models/product.dart';
import 'screens/product_detail_page.dart';
import 'screens/wishlist_page.dart';
import 'screens/cart_page.dart';
import 'screens/checkout_page.dart';
import 'screens/track_order_page.dart';

final demoProduct = Product(
  id: 'demo-backpack',
  name: 'Classic Leather Backpack',
  description:
      'A durable everyday backpack with a clean design, padded laptop sleeve, and room for all your essentials.',
  price: 79.99,
  oldPrice: 99.99,
  stock: 8,
  images: [
    'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=1200',
    'https://images.unsplash.com/photo-1548036328-c9fa89d128fa?w=1200',
  ],
  colors: ['Black', 'Brown', 'Navy'],
  sizes: ['Standard'],
  vendor: Vendor(
    id: 'demo-vendor',
    name: 'Mvec Outfitters',
    logo: '',
    rating: 4.8,
    totalProducts: 42,
  ),
);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final List<Product> _wishlistItems = [];
  final List<CartItem> _cartItems = [];

  void _toggleWishlist(Product product) {
    setState(() {
      final alreadyWishlisted = _wishlistItems.any((item) => item.id == product.id);
      if (alreadyWishlisted) {
        _wishlistItems.removeWhere((item) => item.id == product.id);
      } else {
        _wishlistItems.add(product);
      }
    });
  }

  void _removeFromWishlist(Product product) {
    setState(() {
      _wishlistItems.removeWhere((item) => item.id == product.id);
    });
  }

  void _moveToCart(Product product) {
    setState(() {
      _wishlistItems.removeWhere((item) => item.id == product.id);
      _addToCart(product);
    });
  }

  void _addToCart(Product product) {
    setState(() {
      final existingItem = _cartItems.where(
        (item) => item.product.id == product.id,
      );
      if (existingItem.isEmpty) {
        _cartItems.add(CartItem(product: product));
      } else if (existingItem.first.quantity < product.stock) {
        existingItem.first.quantity++;
      }
    });
  }

  void _updateCartQuantity(CartItem item) {
    setState(() {});
  }

  void _removeCartItem(CartItem item) {
    setState(() {
      _cartItems.removeWhere((cartItem) => cartItem.product.id == item.product.id);
    });
  }

  void _proceedToCheckout() {
    final subtotal = _cartItems.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );
    const shippingFee = 5.00;
    const serviceFee = 2.50;
    final tax = subtotal * 0.08;

    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (context) => CheckoutPage(
          cartItems: _cartItems,
          subtotal: subtotal,
          shippingFee: shippingFee,
          serviceFee: serviceFee,
          tax: tax,
          total: subtotal + shippingFee + serviceFee + tax,
          onOrderPlaced: (Order order) {
            setState(() {
              _cartItems.clear();
            });
            _navigatorKey.currentState!.pop();
            _navigatorKey.currentState!.push(
              MaterialPageRoute(
                builder: (context) => TrackOrderPage(order: order),
              ),
            );
          },
        ),
      ),
    );
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: ProductDetailPage(
        product: demoProduct,
        isWishlisted: _wishlistItems.any((item) => item.id == demoProduct.id),
        onToggleWishlist: _toggleWishlist,
        onOpenWishlist: () {
          _navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => WishlistPage(
                wishlistItems: _wishlistItems,
                onRemoveFromWishlist: _removeFromWishlist,
                onMoveToCart: _moveToCart,
                onToggleWishlist: _toggleWishlist,
                onOpenCart: () {
                  _navigatorKey.currentState!.push(
                    MaterialPageRoute(
                      builder: (context) => CartPage(
                        cartItems: _cartItems,
                        onUpdateQuantity: _updateCartQuantity,
                        onRemoveItem: _removeCartItem,
                        onProceedToCheckout: _proceedToCheckout,
                      ),
                    ),
                  );
                },
                onAddToCart: _addToCart,
              ),
            ),
          );
        },
        onAddToCart: _addToCart,
        onOpenCart: () {
          _navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => CartPage(
                cartItems: _cartItems,
                onUpdateQuantity: _updateCartQuantity,
                onRemoveItem: _removeCartItem,
                onProceedToCheckout: _proceedToCheckout,
              ),
            ),
          );
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
