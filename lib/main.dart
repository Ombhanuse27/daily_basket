import 'package:daily_basket/screens/stocks_sales.dart';
import 'package:flutter/material.dart';
import 'screens/add_product.dart';
import 'screens/product_list.dart';
import 'screens/delete_product.dart';
import 'screens/update_product.dart';
import 'screens/buy_product.dart';
import 'screens/logout.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  // void notification(BuildContext context) {
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(builder: (_) => const StockAndSalesPage()),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'DailyBascket',
          style: TextStyle(
            fontFamily: 'OpenSans',
            fontSize: 22,
            color: Colors.black87,
          ),
        ),
        // actions: [
        //   IconButton(
        //     icon: Image.asset('assets/images/notify.png'),
        //     iconSize: 30,
        //     onPressed: () => notification(context),
        //   ),
        // ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.builder(
          itemCount: _dashboardItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 180,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) {
            final item = _dashboardItems[index];
            return _buildCard(item['title']!, item['image']!, context);
          },
        ),
      ),
    );
  }

  Widget _buildCard(String title, String imagePath, BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (title == 'Add Product') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductPage()));
        } else if (title == 'Delete Product') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const DeleteProductPage()));
        } else if (title == 'Update Product') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdateProductPage()));
        } else if (title == 'Buy Product') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BuyProductPage()));
        } else if (title == 'Logout') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const LogoutPage()));
        } else if (title == 'Stock & Sales') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const StockAndSalesPage()));
        }
      },
      child: Card(
        elevation: 4,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(imagePath, width: 70, height: 70, fit: BoxFit.contain),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'OpenSans',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final List<Map<String, String>> _dashboardItems = [
  {'title': 'Add Product', 'image': 'assets/images/add.png'},
  {'title': 'Delete Product', 'image': 'assets/images/delete.png'},
  {'title': 'Update Product', 'image': 'assets/images/img_1.png'},
  {'title': 'Buy Product', 'image': 'assets/images/img_2.png'},
  {'title': 'Stock & Sales', 'image': 'assets/images/stocks.png'}, // ✅ New Item
  {'title': 'Logout', 'image': 'assets/images/img_3.png'},
];

void main() {
  runApp(const MaterialApp(
    home: AdminDashboard(),
    debugShowCheckedModeBanner: false,
  ));
}
