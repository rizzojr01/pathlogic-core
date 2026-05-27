import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_sense/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:smart_sense/features/auth/presentation/bloc/auth_event.dart';
import 'package:smart_sense/features/auth/presentation/bloc/auth_state.dart';
import 'package:smart_sense/shared/widgets/premium_icon_container.dart';
import 'package:smart_sense/shared/widgets/custom_button.dart';
import 'package:smart_sense/shared/widgets/custom_text_field.dart';

class ResetPasswordPage extends StatefulWidget {
  final String email;

  const ResetPasswordPage({super.key, required this.email});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isTokenVerified = false;

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  void _toggleConfirmPasswordVisibility() {
    setState(() {
      _obscureConfirmPassword = !_obscureConfirmPassword;
    });
  }

  void _handleSubmit() {
    if (_formKey.currentState!.validate()) {
      if (!_isTokenVerified) {
        context.read<AuthBloc>().add(
              VerifyResetTokenSubmitted(
                email: widget.email,
                token: _tokenController.text,
              ),
            );
      } else {
        context.read<AuthBloc>().add(
              ResetPasswordSubmitted(
                email: widget.email,
                token: _tokenController.text,
                newPassword: _passwordController.text,
              ),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is ResetTokenVerified) {
          setState(() {
            _isTokenVerified = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Token verified! Please enter your new password.'),
              backgroundColor: theme.colorScheme.primary,
            ),
          );
        } else if (state is ResetPasswordSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Password reset successfully. Please login.'),
              backgroundColor: theme.colorScheme.primary,
            ),
          );
          // Navigate back to login
          context.go('/login');
        } else if (state is AuthFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: theme.colorScheme.onSurface),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    _buildHeader(context),
                    const SizedBox(height: 32),
                    if (!_isTokenVerified) ...[
                      CustomTextField(
                        controller: _tokenController,
                        labelText: 'Reset Token',
                        hintText: 'Enter 5-character token',
                        prefixIcon: Icons.vpn_key_rounded,
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Required';
                          if (value.length != 5) return 'Must be 5 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),
                    ] else ...[
                      CustomTextField(
                        controller: _passwordController,
                        labelText: 'New Password',
                        hintText: '••••••••',
                        prefixIcon: Icons.lock_outline_rounded,
                        isPassword: true,
                        obscureText: _obscurePassword,
                        onSuffixIconTap: _togglePasswordVisibility,
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Required';
                          if (value.length < 6) return 'Min 6 chars';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      CustomTextField(
                        controller: _confirmPasswordController,
                        labelText: 'Confirm Password',
                        hintText: '••••••••',
                        prefixIcon: Icons.lock_outline_rounded,
                        isPassword: true,
                        obscureText: _obscureConfirmPassword,
                        onSuffixIconTap: _toggleConfirmPasswordVisibility,
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Required';
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthActionLoading;
                        return CustomButton(
                          text: _isTokenVerified ? 'Reset Password' : 'Verify Token',
                          onPressed: _handleSubmit,
                          isLoading: isLoading,
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        PremiumIconContainer(
          icon: Icons.password_rounded,
          size: 100,
          iconSize: 48,
          isCircle: true,
        ),
        const SizedBox(height: 24),
        Text(
          'Create New Password',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isTokenVerified ? 'Enter your new password.' : 'Enter the 5-character token sent to your email.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
