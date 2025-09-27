import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:daily_basket/screens/login_screen.dart';
import 'package:daily_basket/screens/reg_screen.dart';
import 'package:daily_basket/screens/admin_panel.dart';
import 'package:daily_basket/screens/landing_screen.dart'; // <== ADD this
import 'package:daily_basket/screens/add_product.dart';
import 'package:daily_basket/screens/update_product.dart';
import 'package:daily_basket/screens/delete_product.dart';
import 'package:daily_basket/screens/buy_product.dart';
import 'package:daily_basket/screens/product_list.dart';
import 'package:daily_basket/screens/logout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const daily_basketApp());
}

class daily_basketApp extends StatelessWidget {
  const daily_basketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'daily_basket',
      debugShowCheckedModeBanner: false,
      home: const LandingScreen(), // ✅ Important!
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/admin': (context) => const AdminPanel(),
        '/addProduct': (context) => const AddProductPage(),
        '/updateProduct': (context) => const UpdateProductPage(),
        '/deleteProduct': (context) => const DeleteProductPage(),
        '/buyProduct': (context) => const BuyProductPage(),
        '/productList': (context) => const ProductListPage(),
        '/logout': (context) => const LogoutPage(),
      },
    );
  }
}