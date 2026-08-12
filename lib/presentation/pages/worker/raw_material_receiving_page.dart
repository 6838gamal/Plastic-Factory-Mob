
import 'package:flutter/material.dart';

class RawMaterialReceivingPage extends StatelessWidget {
  const RawMaterialReceivingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استلام المواد الخام'),
      ),
      body: const Center(
        child: Text(
          'شاشة استلام المواد الخام',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
