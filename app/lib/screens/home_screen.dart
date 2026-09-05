import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/category.dart';
import '../services/household_repository.dart';
import 'capture_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = HouseholdRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<Category>>(
        stream: _repository.watchCategories(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final categories = snapshot.data!;
          final grouped = <String, List<Category>>{};
          for (final categoria in categories) {
            grouped.putIfAbsent(categoria.grupo, () => []).add(categoria);
          }

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${categories.length} categorías',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final grupo in grouped.keys)
                ExpansionTile(
                  title: Text(grupo),
                  subtitle: Text('${grouped[grupo]!.length} categorías'),
                  children: [
                    for (final categoria in grouped[grupo]!)
                      ListTile(
                        dense: true,
                        title: Text(categoria.nombre),
                        trailing: Text(categoria.unidadDefault),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.camera_alt),
        label: const Text('Escanear ticket'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CaptureScreen(repository: _repository)),
        ),
      ),
    );
  }
}
