import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'signup_page.dart';
import 'api_constants.dart';
import 'password_reset_page.dart';
import 'shopping_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();

  Future<void> _loginUser() async {
  if (!(_formKey.currentState?.validate() ?? false)) return;

  setState(() => _isLoading = true);

  try {
    final response = await http.post(
      Uri.parse("${ApiConstants.baseUrl}/api/auth/login"),
      headers: {
        "Content-Type": "application/json",
        "ngrok-skip-browser-warning": "true",
      },
      body: jsonEncode({
        "email": _emailController.text.trim(),
        "password": _passwordController.text.trim(),
      }),
    );

    print("STATUS: ${response.statusCode}");
    print("BODY: ${response.body}");

    Map<String, dynamic> data = {};

    // ✅ Safe JSON decoding
    try {
      data = jsonDecode(response.body);
    } catch (e) {
      throw Exception("Server returned invalid JSON");
    }

    // ✅ Success case
    if (response.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('jwt_token', data['token'] ?? '');
      await prefs.setString('username', data['user']?['username'] ?? '');
      await prefs.setString('user_id', data['user']?['id'] ?? '');
      await prefs.setString('user_avatar', data['user']?['avatar'] ?? '');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ShoppingPage(
            userName: data['user']?['username'] ?? '',
            userAvatar: data['user']?['avatar'] ?? '',
            userId: data['user']?['id'] ?? '',
          ),
        ),
      );
    } else {
      // ✅ Handle 400 / 401 properly
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['message'] ?? "Login failed"),
        ),
      );
    }
  } catch (e) {
    print("LOGIN ERROR: $e");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Login error: $e"),
      ),
    );
  } finally {
    setState(() => _isLoading = false);
  }
}
/*
  Future<void> _signInWithGoogle() async {
  try {
    final googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize(
      serverClientId: 'stay tune',  // For backend idToken verification; get from Google Cloud Console
    );

    // Authenticate and get user directly (returns GoogleSignInAccount on success; throws on fail/cancel)
    final GoogleSignInAccount googleUser = await googleSignIn.authenticate(
      scopeHint: ['email', 'profile'],  // Optional hint; configure full scopes in Google Console
    );

    // Fetch idToken synchronously (no await in v7.x)
    final GoogleSignInAuthentication auth = googleUser.authentication;
    final String? idToken = auth.idToken;
    if (idToken == null) {
      throw Exception('Failed to retrieve idToken');
    }

    // Send idToken to backend (update backend to verify with Google)
    final response = await http.post(
      Uri.parse("${ApiConstants.baseUrl}/api/auth/google"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "idToken": idToken,  // Secure: Backend verifies this
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', data['token']);
      await prefs.setString('username', data['user']['username']);

      // Navigate on success
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ShoppingPage(
              userName: data['user']['username'],
              userAvatar: data['user']['avatar'] ?? '',
              userId: data['user']['id'],
            ),
          ),
        );
      }
    } else {
      // Parse error safely
      dynamic errorData = response.body;
      try {
        errorData = jsonDecode(response.body);
      } catch (_) {
        // Fallback if not JSON
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google login failed: ${errorData['message'] ?? response.body ?? 'Unknown error'}")),
      );
    }
  } on GoogleSignInException catch (e) {
    // Handle Google-specific errors (e.code is now an enum like GoogleSignInExceptionCode)
    String message;
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        message = 'Sign-in was canceled';  // User closed dialog
        break;
      default:
        message = 'Sign-in failed: ${e.description ?? e.toString()}';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  } catch (e) {
    // Other errors (HTTP, JSON, etc.)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Google sign-in error: $e")),
    );
  }
}
*/

  Widget _buildTextFormField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    required bool obscure,
    String? Function(String?)? validator,
    VoidCallback? toggle,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF757575)),
        suffixIcon: toggle != null
            ? IconButton(
                onPressed: toggle,
                icon: Icon(
                  obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: const Color(0xFF757575),
                ),
              )
            : null,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 16),
        filled: true,
        fillColor: Colors.white.withOpacity(0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF81C784), Color(0xFF4DD0E1)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/images/pickwise_logo_middle_rmbg.png',
                              width: 120,
                              height: 120,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Log in to PickWise',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF37474F),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  _buildTextFormField(
                                    controller: _emailController,
                                    icon: Icons.email_outlined,
                                    hint: 'Email Address',
                                    obscure: false,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) return 'Email cannot be empty';
                                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) return 'Enter a valid email';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextFormField(
                                    controller: _passwordController,
                                    icon: Icons.lock_outline,
                                    hint: 'Password',
                                    obscure: _obscurePassword,
                                    toggle: () {
                                      setState(() => _obscurePassword = !_obscurePassword);
                                    },
                                    validator: (value) {
                                      if (value == null || value.isEmpty) return 'Password cannot be empty';
                                      if (value.length < 6) return 'Password must be at least 6 characters';
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => PasswordResetPage()),
                                );
                              },
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Color(0xFF37474F),
                                  fontSize: 14,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _loginUser,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFD54F),
                                  foregroundColor: const Color(0xFF37474F),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(color: Colors.black)
                                    : const Text(
                                        'Log In',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(child: Container(height: 1, color: Color(0xFFBDBDBD))),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                      color: Color(0xFF757575),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(child: Container(height: 1, color: Color(0xFFBDBDBD))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // SizedBox(
                            //   width: double.infinity,
                            //   height: 56,
                            //   child: ElevatedButton(
                            //     onPressed: _isLoading ? null : // _signInWithGoogle,
                            //     style: ElevatedButton.styleFrom(
                            //       backgroundColor: Colors.white.withOpacity(0.9),
                            //       foregroundColor: const Color(0xFF37474F),
                            //       side: BorderSide(color: Colors.white.withOpacity(0.5)),
                            //       shape: RoundedRectangleBorder(
                            //         borderRadius: BorderRadius.circular(12),
                            //       ),
                            //     ),
                            //     child: Row(
                            //       mainAxisAlignment: MainAxisAlignment.center,
                            //       children: [
                            //         SizedBox(
                            //           width: 20,
                            //           height: 20,
                            //           child: Image.asset('assets/images/google_icon.png'),
                            //         ),
                            //         const SizedBox(width: 12),
                            //         const Text(
                            //           'Continue with Google',
                            //           style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            //         ),
                            //       ],
                            //     ),
                            //   ),
                            // ),
                            const SizedBox(height: 24),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const SignUpPage()),
                                );
                              },
                              child: RichText(
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: "Don't have an account? ",
                                      style: TextStyle(color: Color(0xFF757575), fontSize: 14),
                                    ),
                                    TextSpan(
                                      text: "Sign Up",
                                      style: TextStyle(
                                        color: Color(0xFF37474F),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),
                  const Text('© 2025 PickWise', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
