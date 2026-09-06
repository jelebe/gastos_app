import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/saved_credentials.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Si se recuerdan los datos, se rellenan solos al abrir. No se entra
  /// automáticamente: si se ha cerrado sesión a propósito, volver a entrar
  /// solo debe costar un toque, no ser inevitable.
  bool _recordar = true;

  @override
  void initState() {
    super.initState();
    SavedCredentials.cargar().then((guardadas) {
      if (guardadas == null || !mounted) return;
      setState(() {
        _emailController.text = guardadas.correo;
        _passwordController.text = guardadas.password;
      });
    });
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Solo se guardan después de que Firebase los dé por buenos: recordar
      // una contraseña equivocada sería peor que no recordar ninguna.
      if (_recordar) {
        await SavedCredentials.guardar(
          correo: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await SavedCredentials.borrar();
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'No se ha podido iniciar sesión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Nuestro hogar', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (value) =>
                        (value == null || value.isEmpty) ? 'Introduce tu correo' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    validator: (value) =>
                        (value == null || value.isEmpty) ? 'Introduce tu contraseña' : null,
                  ),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Recordar mis datos en este móvil'),
                    value: _recordar,
                    onChanged: _loading ? null : (v) => setState(() => _recordar = v ?? false),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Iniciar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
