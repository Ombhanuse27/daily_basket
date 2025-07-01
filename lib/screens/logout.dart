import 'package:flutter/material.dart';

class LogoutPage extends StatelessWidget {
  const LogoutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logout')),
      body: const Center(child: Text('You have been logged out.')),
    );
  }
}
