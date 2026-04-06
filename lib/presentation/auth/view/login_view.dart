import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/responsive/dpi_scale.dart';
import '../../../domain/auth/saved_account.dart';
import '../../../presentation/theme/theme_data_factory.dart';
import '../viewmodel/auth_gate_view_model.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  List<SavedAccount> _savedAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await ref.read(savedAccountsServiceProvider).loadAccounts();
    if (mounted) {
      setState(() => _savedAccounts = accounts);
    }
  }

  Future<void> _removeSavedAccount(String email) async {
    await ref.read(savedAccountsServiceProvider).removeAccount(email);
    await _loadSavedAccounts();
  }

  void _selectSavedAccount(SavedAccount account) {
    _emailController.text = account.email;
    _passwordController.clear();
    _passwordFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cuentas guardadas
                if (_savedAccounts.isNotEmpty) ...[
                  _SavedAccountsList(
                    accounts: _savedAccounts,
                    selectedEmail: _emailController.text,
                    onSelect: _selectSavedAccount,
                    onRemove: _removeSavedAccount,
                  ),
                  SizedBox(height: dpi.space(16)),
                ],

                // Formulario de login
                Container(
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
                                  _savedAccounts.isNotEmpty
                                      ? 'Ingresa o selecciona una cuenta'
                                      : 'Acceso administrativo',
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
                        focusNode: _passwordFocusNode,
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
              ],
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
    );
  }
}

class _SavedAccountsList extends StatelessWidget {
  const _SavedAccountsList({
    required this.accounts,
    required this.selectedEmail,
    required this.onSelect,
    required this.onRemove,
  });

  final List<SavedAccount> accounts;
  final String selectedEmail;
  final ValueChanged<SavedAccount> onSelect;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final dpi = DpiScale.of(context);

    return Container(
      padding: EdgeInsets.all(dpi.space(16)),
      decoration: BoxDecoration(
        color: MangoThemeFactory.cardColor(context),
        borderRadius: BorderRadius.circular(dpi.radius(20)),
        border: Border.all(color: MangoThemeFactory.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline_rounded, size: dpi.icon(20), color: MangoThemeFactory.mango),
              SizedBox(width: dpi.space(8)),
              Text(
                'Cuentas guardadas',
                style: TextStyle(
                  fontSize: dpi.font(14),
                  fontWeight: FontWeight.w700,
                  color: MangoThemeFactory.textColor(context),
                ),
              ),
            ],
          ),
          SizedBox(height: dpi.space(12)),
          ...accounts.map((account) {
            final isSelected = account.email == selectedEmail;
            return Padding(
              padding: EdgeInsets.only(bottom: dpi.space(8)),
              child: InkWell(
                onTap: () => onSelect(account),
                borderRadius: BorderRadius.circular(dpi.radius(14)),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: dpi.space(14),
                    vertical: dpi.space(12),
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? MangoThemeFactory.mango.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(dpi.radius(14)),
                    border: Border.all(
                      color: isSelected
                          ? MangoThemeFactory.mango
                          : MangoThemeFactory.borderColor(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: dpi.scale(38),
                        height: dpi.scale(38),
                        decoration: BoxDecoration(
                          color: MangoThemeFactory.mango.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          account.displayName.isNotEmpty
                              ? account.displayName[0].toUpperCase()
                              : account.email[0].toUpperCase(),
                          style: TextStyle(
                            fontSize: dpi.font(16),
                            fontWeight: FontWeight.w800,
                            color: MangoThemeFactory.mango,
                          ),
                        ),
                      ),
                      SizedBox(width: dpi.space(12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.displayName,
                              style: TextStyle(
                                fontSize: dpi.font(14),
                                fontWeight: FontWeight.w700,
                                color: isSelected ? MangoThemeFactory.mango : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              account.email,
                              style: TextStyle(
                                fontSize: dpi.font(12),
                                color: MangoThemeFactory.mutedText(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (account.businessName != null)
                              Text(
                                account.businessName!,
                                style: TextStyle(
                                  fontSize: dpi.font(11),
                                  color: MangoThemeFactory.mutedText(context),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => onRemove(account.email),
                        icon: Icon(
                          Icons.close_rounded,
                          size: dpi.icon(18),
                          color: MangoThemeFactory.mutedText(context),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(
                          minWidth: dpi.scale(32),
                          minHeight: dpi.scale(32),
                        ),
                        tooltip: 'Eliminar cuenta guardada',
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
