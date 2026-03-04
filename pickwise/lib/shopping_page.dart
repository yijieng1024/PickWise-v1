import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'api_constants.dart';
import 'laptop_details_page.dart';
import 'cart_page.dart';
import 'chatbot_page.dart';
import 'profile_settings_page.dart';

class ShoppingPage extends StatefulWidget {
  final String userName;
  final String? userAvatar;
  final String userId;
  const ShoppingPage({
    super.key,
    required this.userName,
    this.userAvatar,
    required this.userId,
  });

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> laptops = [];
  List<Map<String, dynamic>> filteredLaptops = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool isLoading = true;
  String? token;
  final ScrollController _scrollController = ScrollController();
  int itemsPerPage = 20;
  int currentMax = 20;

  // Search and Filter
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';
  String selectedBrand = 'All';
  String selectedProcessor = 'All';
  RangeValues priceRange = const RangeValues(0, 15000);
  List<String> brands = ['All'];
  List<String> processors = ['All'];

  void _onItemTapped(int index) async {
    if (index == 1) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null || JwtDecoder.isExpired(token)) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ChatbotPage(userId: widget.userId, userName: widget.userName),
            ),
          );
        }
      }
    } else if (index == 2) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null || JwtDecoder.isExpired(token)) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CartPage()),
          );
        }
      }
    } else if (index == 3) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null || JwtDecoder.isExpired(token)) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ProfileSettingsPage(),
            ),
          );
        }
      }
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
          _scrollController.position.maxScrollExtent) {
        _loadMoreLaptops();
      }
    });
    _searchController.addListener(_onSearchChanged);
    _validateTokenAndFetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      searchQuery = _searchController.text;
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> results = List.from(laptops);

    final query = searchQuery.toLowerCase();
    if (query.isNotEmpty) {
      results = results.where((l) {
        return [
          'product_name',
          'brand',
          'processor_name',
          'model_code',
        ].any((k) => l[k]?.toString().toLowerCase().contains(query) ?? false);
      }).toList();
    }

    if (selectedBrand != 'All') {
      results = results.where((l) => l['brand'] == selectedBrand).toList();
    }

    if (selectedProcessor != 'All') {
      results = results
          .where(
            (l) =>
                l['processor_name']?.toString().contains(selectedProcessor) ??
                false,
          )
          .toList();
    }

    results = results.where((l) {
      double price = 0.0;
      final p = l['price_rm'];
      if (p is num) {
        price = p.toDouble();
      } else if (p is String)
        price = double.tryParse(p.replaceAll('RM', '').trim()) ?? 0.0;
      return price >= priceRange.start && price <= priceRange.end;
    }).toList();

    setState(() {
      filteredLaptops = results;
      currentMax = results.length < itemsPerPage
          ? results.length
          : itemsPerPage;
    });
  }

  void _extractFiltersFromLaptops() {
    Set<String> brandSet = {};
    Set<String> processorSet = {};

    // print('=== EXTRACTING FILTERS ===');

    for (var laptop in laptops) {
      // Extract brands
      if (laptop['brand'] != null && laptop['brand'].toString().isNotEmpty) {
        brandSet.add(laptop['brand'].toString());
      }

      // Extract processors - get the full processor name
      if (laptop['processor_name'] != null &&
          laptop['processor_name'].toString().isNotEmpty) {
        final processor = laptop['processor_name'].toString();
        processorSet.add(processor); // Add full processor name

        // print('Found processor: $processor');
      }
    }
    /*
    print('Total unique brands: ${brandSet.length}');
    print('Total unique processors: ${processorSet.length}');
    print('Processors: ${processorSet.toList()}');
    print('=== END EXTRACTION ===');*/

    setState(() {
      brands = ['All', ...brandSet.toList()..sort()];
      processors = ['All', ...processorSet.toList()..sort()];
    });
  }

  void _loadMoreLaptops() {
    setState(() {
      if (currentMax + itemsPerPage < filteredLaptops.length) {
        currentMax += itemsPerPage;
      } else {
        currentMax = filteredLaptops.length;
      }
    });
  }

  Future<void> _validateTokenAndFetchData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('jwt_token');

    if (savedToken == null || JwtDecoder.isExpired(savedToken)) {
      _showSessionExpiredDialog();
      return;
    }

    setState(() {
      token = savedToken;
    });

    _fetchLaptopsFromDatabase();
  }

  Future<void> _fetchLaptopsFromDatabase() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/api/laptops'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          laptops = data.map((item) => item as Map<String, dynamic>).toList();
          filteredLaptops = laptops;
          isLoading = false;
        });
        _extractFiltersFromLaptops();
      } else if (response.statusCode == 401) {
        _showSessionExpiredDialog();
      } else {
        setState(() => isLoading = false);
        debugPrint('Error fetching laptops: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('Error fetching laptops: $e');
    }
  }

  void _showSessionExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Session Expired'),
          ],
        ),
        content: const Text('Please log in again to continue.'),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('jwt_token');
              Navigator.pushReplacementNamed(context, '/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00ACC1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF263238),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            selectedBrand = 'All';
                            selectedProcessor = 'All';
                            priceRange = const RangeValues(0, 15000);
                          });
                          setState(() {
                            selectedBrand = 'All';
                            selectedProcessor = 'All';
                            priceRange = const RangeValues(0, 15000);
                            _applyFilters();
                          });
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Brand Filter
                  const Text(
                    'Brand',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF263238),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedBrand,
                        isExpanded: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFF00ACC1),
                        ),
                        items: brands.map((brand) {
                          return DropdownMenuItem(
                            value: brand,
                            child: Text(brand),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setModalState(() => selectedBrand = value!);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Processor Filter
                  const Text(
                    'Processor',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF263238),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedProcessor,
                        isExpanded: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFF00ACC1),
                        ),
                        menuMaxHeight: 300,
                        items: processors.map((proc) {
                          return DropdownMenuItem(
                            value: proc,
                            child: Text(
                              proc,
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setModalState(() => selectedProcessor = value!);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Price Range Filter
                  const Text(
                    'Price Range',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF263238),
                    ),
                  ),
                  const SizedBox(height: 8),
                  RangeSlider(
                    values: priceRange,
                    min: 0,
                    max: 15000,
                    divisions: 100,
                    activeColor: const Color(0xFF00ACC1),
                    labels: RangeLabels(
                      'RM ${priceRange.start.round()}',
                      'RM ${priceRange.end.round()}',
                    ),
                    onChanged: (values) {
                      setModalState(() => priceRange = values);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'RM ${priceRange.start.round()}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF546E7A),
                        ),
                      ),
                      Text(
                        'RM ${priceRange.end.round()}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF546E7A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Apply Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _applyFilters();
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00ACC1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Apply Filters',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  final List<Widget> _pages = [
    const Center(child: Text('Home Page')),
    const Center(child: Text('Chatbot Page')),
    const Center(child: Text('Shopping Cart Page')),
    const Center(child: Text('Profile Page')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FA),
      extendBodyBehindAppBar: false,
      body: _selectedIndex == 0
          ? SafeArea(
              top: true,
              bottom: false,
              child: Stack(
                children: [
                  // Scrollable content
                  Padding(
                    padding: const EdgeInsets.only(top: 90), // Back to original
                    child: RefreshIndicator(
                      color: const Color(0xFF00ACC1),
                      onRefresh: _fetchLaptopsFromDatabase,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        controller: _scrollController,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),

                              // Welcome Section
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFB2DFDB),
                                      Color(0xFF80CBC4),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF00ACC1,
                                      ).withOpacity(0.2),
                                      blurRadius: 15,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.waving_hand,
                                          color: Color(0xFF37474F),
                                          size: 28,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Hi, ${widget.userName.isNotEmpty ? widget.userName : 'Guest'}!',
                                            style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF263238),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Find your perfect laptop today',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFF37474F),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Section Header
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF00ACC1,
                                          ).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.laptop_mac,
                                          color: Color(0xFF00ACC1),
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Featured Laptops',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF263238),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF00ACC1,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${filteredLaptops.length} items',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF00ACC1),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // Search Bar (Now below Featured Laptops)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        decoration: InputDecoration(
                                          hintText: 'Search laptops...',
                                          hintStyle: TextStyle(
                                            color: Colors.grey[400],
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.search,
                                            color: Color(0xFF00ACC1),
                                            size: 24,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 14,
                                              ),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      height: 48,
                                      width: 1,
                                      color: Colors.grey[300],
                                    ),
                                    InkWell(
                                      onTap: _showFilterBottomSheet,
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                            right: Radius.circular(16),
                                          ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.tune,
                                              color: Color(0xFF00ACC1),
                                              size: 24,
                                            ),
                                            const SizedBox(width: 4),
                                            if (selectedBrand != 'All' ||
                                                selectedProcessor != 'All' ||
                                                priceRange.start > 0 ||
                                                priceRange.end < 15000)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  left: 4,
                                                ),
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF00ACC1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Text(
                                                  '!',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Laptop Grid
                              isLoading
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(40),
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF00ACC1),
                                        ),
                                      ),
                                    )
                                  : LaptopGrid(
                                      laptops: filteredLaptops
                                          .take(currentMax)
                                          .toList(),
                                    ),

                              const SizedBox(height: 20),

                              // Load More Button
                              if (currentMax < filteredLaptops.length)
                                Center(
                                  child: ElevatedButton.icon(
                                    onPressed: _loadMoreLaptops,
                                    icon: const Icon(
                                      Icons.expand_more,
                                      size: 20,
                                    ),
                                    label: Text(
                                      'Load More (${filteredLaptops.length - currentMax} remaining)',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00ACC1),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 80),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floating Top Bar
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB2DFDB),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Logo
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Image.asset(
                                  'assets/images/pickwise_logo_middle_rmbg.png',
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'PickWise',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF263238),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),

                          // User Avatar with Logout
                          GestureDetector(
                            onTap: () async {
                              // If username is missing (empty), immediately logout and go to /login
                              if (widget.userName.isEmpty ||
                                  widget.userId.toString() == 'Guest') {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.remove("jwt_token");
                                if (context.mounted) {
                                  Navigator.of(context).pushNamedAndRemoveUntil(
                                    '/login',
                                    (route) => false,
                                  );
                                }
                                return;
                              }

                              // Otherwise show confirmation dialog
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  title: const Text('Logout'),
                                  content: const Text(
                                    'Are you sure you want to logout?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF00ACC1,
                                        ),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Logout'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.remove("jwt_token");
                                if (context.mounted) {
                                  Navigator.of(context).pushNamedAndRemoveUntil(
                                    '/login',
                                    (route) => false,
                                  );
                                }
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child:
                                  (widget.userAvatar != null &&
                                      widget.userAvatar!.isNotEmpty)
                                  ? CircleAvatar(
                                      backgroundImage: NetworkImage(
                                        widget.userAvatar!,
                                      ),
                                      radius: 20,
                                    )
                                  : CircleAvatar(
                                      radius: 20,
                                      backgroundColor: const Color(0xFF00ACC1),
                                      child: Text(
                                        widget.userName.isNotEmpty
                                            ? widget.userName[0].toUpperCase()
                                            : "G",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF00ACC1),
          unselectedItemColor: Colors.black54,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          backgroundColor: Colors.white,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Chatbot',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart_outlined),
              activeIcon: Icon(Icons.shopping_cart),
              label: 'Cart',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class LaptopGrid extends StatelessWidget {
  final List<Map<String, dynamic>> laptops;

  const LaptopGrid({super.key, required this.laptops});

  @override
  Widget build(BuildContext context) {
    if (laptops.isEmpty) {
      return Center(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Icon(Icons.laptop_chromebook, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No laptops available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 380,
      ),
      itemCount: laptops.length,
      itemBuilder: (context, index) {
        final laptop = laptops[index];
        return LaptopCard(laptop: laptop);
      },
    );
  }
}

class LaptopCard extends StatelessWidget {
  final Map<String, dynamic> laptop;

  const LaptopCard({super.key, required this.laptop});

  Widget _buildLaptopImage(Map<String, dynamic> laptop) {
    final imageField = laptop['imageURL']?.toString().trim() ?? '';
    final imageList = imageField
        .split(RegExp(r'[;,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final firstImagePath = imageList.isNotEmpty ? imageList.first : null;

    if (firstImagePath == null) {
      return const Icon(Icons.laptop_mac, size: 80, color: Colors.grey);
    }

    final assetPath = 'assets/$firstImagePath';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('⚠️ Image load failed: $assetPath');
          return const Icon(Icons.laptop_mac, size: 80, color: Colors.grey);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawSsd = laptop['ssd_gb']?.toString().trim().toLowerCase() ?? '0';
    final numericPart =
        RegExp(r'(\d+(\.\d+)?)').firstMatch(rawSsd)?.group(0) ?? '0';
    final ssdValue = double.tryParse(numericPart) ?? 0.0;
    String formattedSsd = ssdValue >= 1000
        ? '${(ssdValue / 1000).round()}TB'
        : '${ssdValue.round()}GB';

    final specs = [
      laptop['processor_name'] ?? 'Unknown CPU',
      '${laptop['ram_gb'] ?? ''}GB RAM',
      formattedSsd,
      laptop['gpu_model'] ?? '',
      laptop['display_size_inches'] != null &&
              laptop['display_size_inches'].toString().isNotEmpty
          ? '${laptop['display_size_inches']}" Display'
          : '',
      laptop['os'] ?? '',
      laptop['weight_kg'] != null && laptop['weight_kg'].toString().isNotEmpty
          ? '${laptop['weight_kg']}kg'
          : '',
      laptop['bluetooth'] != null && laptop['bluetooth'].toString().isNotEmpty
          ? 'Bluetooth'
          : '',
    ].where((s) => s.isNotEmpty).join(' | ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LaptopDetailsPage(laptop: laptop),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: Container(
                        color: const Color(0xFFF5F5F5),
                        width: double.infinity,
                        child: _buildLaptopImage(laptop),
                      ),
                    ),
                    // Brand Badge
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          laptop['brand'] ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF263238),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Details Section
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      laptop['product_name'] ?? 'Unnamed Laptop',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      laptop['model_code'] ?? 'Unknown Model',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        specs.isNotEmpty ? specs : 'No specs available',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[700],
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          (laptop['price_rm'] != null &&
                                  laptop['price_rm'].toString().isNotEmpty)
                              ? 'RM ${laptop['price_rm'].toString()}'
                              : 'N/A',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00ACC1),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00ACC1).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Color(0xFF00ACC1),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
