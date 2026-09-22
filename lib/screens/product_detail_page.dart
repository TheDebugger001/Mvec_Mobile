import 'package:flutter/material.dart';
import '../models/product.dart';

class ProductDetailPage extends StatefulWidget {
  final Product product;
  final bool isWishlisted;
  final ValueChanged<Product>? onToggleWishlist;
  final VoidCallback? onOpenWishlist;

  const ProductDetailPage({
    super.key,
    required this.product,
    this.isWishlisted = false,
    this.onToggleWishlist,
    this.onOpenWishlist,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late final Product product;

  int _currentImageIndex = 0;
  String? _selectedColor;
  String? _selectedSize;
  int _quantity = 1;
  bool _isWishlisted = false;
  bool _isAddingToCart = false;

  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    product = widget.product;
    _isWishlisted = widget.isWishlisted;

    if (product.colors.isNotEmpty) {
      _selectedColor = product.colors.first;
    }
    if (product.sizes.isNotEmpty) {
      _selectedSize = product.sizes.first;
    }
  }

  void _toggleWishlist() {
    setState(() {
      _isWishlisted = !_isWishlisted;
    });
    widget.onToggleWishlist?.call(product);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOutOfStock = product.stock <= 0;
    final isLowStock = product.stock > 0 && product.stock <= 5;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // AppBar + Product Images
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isWishlisted ? Icons.favorite : Icons.favorite_border,
                  color: _isWishlisted ? Colors.red : null,
                ),
                onPressed: () {
                  _toggleWishlist();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _isWishlisted
                            ? 'Added to wishlist'
                            : 'Removed from wishlist',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
              if (widget.onOpenWishlist != null)
                IconButton(
                  icon: const Icon(Icons.list_alt_outlined),
                  tooltip: 'Open wishlist',
                  onPressed: widget.onOpenWishlist,
                ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  // TODO: Share product
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: product.images.isEmpty
                  ? Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported,
                          size: 80,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          itemCount: product.images.length,
                          onPageChanged: (index) {
                            setState(() {
                              _currentImageIndex = index;
                            });
                          },
                          itemBuilder: (context, index) {
                            return Image.network(
                              product.images[index],
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[200],
                                  child: const Icon(
                                    Icons.broken_image,
                                    size: 80,
                                    color: Colors.grey,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        if (product.images.length > 1)
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                product.images.length,
                                (index) => AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: _currentImageIndex == index ? 20 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _currentImageIndex == index
                                        ? theme.primaryColor
                                        : Colors.white.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Name
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Price + Stock Status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${product.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      ),
                      if (product.oldPrice != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          '\$${product.oldPrice!.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isOutOfStock
                              ? Colors.red.withValues(alpha: 0.12)
                              : isLowStock
                                  ? Colors.orange.withValues(alpha: 0.12)
                                  : Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isOutOfStock
                              ? 'Out of Stock'
                              : isLowStock
                                  ? 'Only ${product.stock} left'
                                  : 'In Stock (${product.stock})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isOutOfStock
                                ? Colors.red
                                : isLowStock
                                    ? Colors.orange[800]
                                    : Colors.green[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Vendor Information
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            product.vendor.logo,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 50,
                                height: 50,
                                color: Colors.grey[200],
                                child: const Icon(Icons.store),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.vendor.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  const Icon(Icons.star, size: 16, color: Colors.amber),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${product.vendor.rating} • ${product.vendor.totalProducts} products',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // TODO: Navigate to Vendor Store
                          },
                          child: const Text('Visit Store'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Color Options
                  if (product.colors.isNotEmpty) ...[
                    const Text(
                      'Color',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: product.colors.map((color) {
                        final isSelected = _selectedColor == color;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedColor = color;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? theme.primaryColor : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? theme.primaryColor
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              color,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Size Options
                  if (product.sizes.isNotEmpty) ...[
                    const Text(
                      'Size',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: product.sizes.map((size) {
                        final isSelected = _selectedSize == size;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedSize = size;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? theme.primaryColor : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? theme.primaryColor
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              size,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Quantity
                  const Text(
                    'Quantity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 20),
                          onPressed: _quantity > 1
                              ? () {
                                  setState(() {
                                    _quantity--;
                                  });
                                }
                              : null,
                        ),
                        Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          onPressed: _quantity < product.stock
                              ? () {
                                  setState(() {
                                    _quantity++;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Description
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    product.description,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Action Bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _toggleWishlist,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Icon(
                  _isWishlisted ? Icons.favorite : Icons.favorite_border,
                  color: _isWishlisted ? Colors.red : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isOutOfStock || _isAddingToCart
                      ? null
                      : () async {
                          setState(() {
                            _isAddingToCart = true;
                          });

                          // Simulate adding to cart
                          await Future.delayed(const Duration(milliseconds: 800));

                          if (!context.mounted) {
                            return;
                          }

                          setState(() {
                            _isAddingToCart = false;
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Added $_quantity × ${product.name} to cart',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isAddingToCart
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Add to Cart',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}