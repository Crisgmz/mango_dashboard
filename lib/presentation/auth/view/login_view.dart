import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/responsive/dpi_scale.dart';
import '../../../presentation/theme/theme_data_factory.dart';
import '../viewmodel/auth_gate_view_model.dart';

const _keepSessionKey = 'keep_session';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _keepSession = true;

  @override
  void initState() {
    super.initState();
    _loadKeepSession();
  }

  Future<void> _loadKeepSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _keepSession = prefs.getBool(_keepSessionKey) ?? true);
    }
  }

  Future<void> _saveKeepSession(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepSessionKey, value);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);
    final state = ref.watch(authGateViewModelProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(dpi.space(22)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: EdgeInsets.all(dpi.space(24)),
              decoration: BoxDecoration(
                color: MangoThemeFactory.cardColor(context),
                borderRadius: BorderRadius.circular(dpi.radius(20)),
                border: Border.all(color: MangoThemeFactory.borderColor(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo + título
                  Row(
                    children: [
                      Container(
                        width: dpi.scale(46),
                        height: dpi.scale(46),
                        padding: EdgeInsets.all(dpi.space(6)),
                        decoration: BoxDecoration(
                          color: MangoThemeFactory.mango.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(dpi.radius(12)),
                        ),
                        child: Image.asset('assets/logo/logo.png', fit: BoxFit.contain),
                      ),
                      SizedBox(width: dpi.space(12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mango Dashboard', style: Theme.of(context).textTheme.titleLarge),
                            SizedBox(height: dpi.space(2)),
                            Text(
                              'Acceso administrativo',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: dpi.space(24)),

                  // Email
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Correo',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(dpi.radius(10))),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(dpi.radius(10)),
                        borderSide: BorderSide(color: MangoThemeFactory.borderColor(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(dpi.radius(10)),
                        borderSide: const BorderSide(color: MangoThemeFactory.mango, width: 1.5),
                      ),
                    ),
                  ),

                  SizedBox(height: dpi.space(14)),

                  // Password
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(dpi.radius(10))),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(dpi.radius(10)),
                        borderSide: BorderSide(color: MangoThemeFactory.borderColor(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(dpi.radius(10)),
                        borderSide: const BorderSide(color: MangoThemeFactory.mango, width: 1.5),
                      ),
                    ),
                  ),

                  SizedBox(height: dpi.space(10)),

                  // Mantener sesión
                  GestureDetector(
                    onTap: () {
                      final next = !_keepSession;
                      setState(() => _keepSession = next);
                      _saveKeepSession(next);
                    },
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _keepSession,
                            onChanged: (v) {
                              final next = v ?? true;
                              setState(() => _keepSession = next);
                              _saveKeepSession(next);
                            },
                            activeColor: MangoThemeFactory.mango,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                        SizedBox(width: dpi.space(8)),
                        Text(
                          'Mantener sesión iniciada',
                          style: TextStyle(
                            fontSize: dpi.font(13),
                            color: MangoThemeFactory.mutedText(context),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Error
                  if (state.error != null) ...[
                    SizedBox(height: dpi.space(14)),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(dpi.space(12)),
                      decoration: BoxDecoration(
                        color: MangoThemeFactory.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(dpi.radius(10)),
                        border: Border.all(color: MangoThemeFactory.danger.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        state.error!,
                        style: TextStyle(color: MangoThemeFactory.danger, fontSize: dpi.font(12)),
                      ),
                    ),
                  ],

                  SizedBox(height: dpi.space(20)),

                  // Botón entrar
                  SizedBox(
                    width: double.infinity,
                    height: dpi.scale(48),
                    child: FilledButton(
                      onPressed: state.isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: MangoThemeFactory.mango,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(dpi.radius(10))),
                      ),
                      child: state.isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withValues(alpha: 0.8)),
                            )
                          : Text(
                              'Entrar',
                              style: TextStyle(fontSize: dpi.font(15), fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    ref.read(authGateViewModelProvider.notifier).signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      keepSession: _keepSession,
    );
  }
}
