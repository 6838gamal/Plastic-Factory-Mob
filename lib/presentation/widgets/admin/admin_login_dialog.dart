import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/datasources/api_datasource.dart';

class AdminLoginDialog extends ConsumerStatefulWidget {
  final VoidCallback onSuccess;
  const AdminLoginDialog({super.key, required this.onSuccess});

  @override
  ConsumerState<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends ConsumerState<AdminLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final success = await ref.read(authProvider.notifier).signIn(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
    if (success && mounted) {
      widget.onSuccess();
    }
  }

  // ── OTP Forgot-password dialog ──────────────────────────────────────────────
  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ForgotPasswordOtpDialog(dataSource: ref.read(dataSourceProvider)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.admin_panel_settings,
                  size: 48,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.adminLogin,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: AppStrings.email,
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'البريد مطلوب';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: AppStrings.password,
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'كلمة المرور مطلوبة';
                  return null;
                },
                onFieldSubmitted: (_) => _login(),
              ),
              if (authState.error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authState.error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(AppStrings.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: authState.isLoading ? null : _login,
                      child: authState.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(AppStrings.login),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _showForgotPasswordDialog,
                icon: const Icon(Icons.lock_reset, size: 16),
                label: const Text('نسيت كلمة المرور؟'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 3-step OTP reset dialog ─────────────────────────────────────────────────

class _ForgotPasswordOtpDialog extends StatefulWidget {
  final ApiDataSource dataSource;
  const _ForgotPasswordOtpDialog({required this.dataSource});

  @override
  State<_ForgotPasswordOtpDialog> createState() => _ForgotPasswordOtpDialogState();
}

class _ForgotPasswordOtpDialogState extends State<_ForgotPasswordOtpDialog> {
  // Steps: 0 = phone entry, 1 = OTP entry, 2 = new password
  int _step = 0;
  bool _loading = false;
  String? _errorMsg;

  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscurePass = true;

  String _phone = '';
  String _resetToken = '';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  // Step 0 → send OTP
  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMsg = 'أدخل رقم الهاتف');
      return;
    }
    setState(() { _loading = true; _errorMsg = null; });
    try {
      await widget.dataSource.sendOtp(phone);
      _phone = phone;
      setState(() { _step = 1; _loading = false; });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // Step 1 → verify OTP
  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMsg = 'أدخل كود التحقق');
      return;
    }
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final res = await widget.dataSource.verifyOtp(_phone, code);
      _resetToken = res['reset_token'] as String? ?? '';
      setState(() { _step = 2; _loading = false; });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // Step 2 → reset password
  Future<void> _resetPassword() async {
    final pass = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;
    if (pass.length < 6) {
      setState(() => _errorMsg = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }
    if (pass != confirm) {
      setState(() => _errorMsg = 'كلمة المرور غير متطابقة');
      return;
    }
    setState(() { _loading = true; _errorMsg = null; });
    try {
      await widget.dataSource.resetPasswordWithToken(_resetToken, pass);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم إعادة تعيين كلمة المرور — يمكنك تسجيل الدخول الآن'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    const labels = ['الهاتف', 'التحقق', 'كلمة المرور'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final done = i < _step;
        final active = i == _step;
        return Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: active ? 32 : 28,
              height: active ? 32 : 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? Colors.green
                    : active
                        ? Colors.orange
                        : Colors.grey.shade300,
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: active ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
            if (i < 2)
              Container(
                width: 28,
                height: 2,
                color: i < _step ? Colors.green : Colors.grey.shade300,
              ),
          ],
        );
      }),
    );
  }

  Widget _buildStep0() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoBox(
            Icons.sms_outlined,
            Colors.blue,
            'أدخل رقم الهاتف المسجّل في إعدادات SMS لإرسال كود التحقق',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              prefixIcon: Icon(Icons.phone_outlined),
              hintText: '+966xxxxxxxxx',
            ),
            onSubmitted: (_) => _sendOtp(),
          ),
        ],
      );

  Widget _buildStep1() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoBox(
            Icons.mark_email_read_outlined,
            Colors.orange,
            'تم إرسال كود التحقق إلى $_phone\nأدخل الكود المكوّن من 6 أرقام',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 12,
            ),
            decoration: const InputDecoration(
              labelText: 'كود التحقق',
              counterText: '',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            onSubmitted: (_) => _verifyOtp(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('إعادة الإرسال', style: TextStyle(fontSize: 13)),
              onPressed: _loading ? null : () => setState(() { _step = 0; _otpCtrl.clear(); _errorMsg = null; }),
            ),
          ),
        ],
      );

  Widget _buildStep2() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoBox(
            Icons.lock_reset,
            Colors.green,
            'تم التحقق بنجاح — أدخل كلمة المرور الجديدة',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _newPassCtrl,
            obscureText: _obscurePass,
            decoration: InputDecoration(
              labelText: 'كلمة المرور الجديدة',
              prefixIcon: const Icon(Icons.lock_open_outlined),
              suffixIcon: IconButton(
                icon: Icon(_obscurePass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPassCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'تأكيد كلمة المرور',
              prefixIcon: Icon(Icons.check_circle_outline),
            ),
            onSubmitted: (_) => _resetPassword(),
          ),
        ],
      );

  Widget _infoBox(IconData icon, Color color, String text) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, color: color.withOpacity(0.9))),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final stepTitles = ['إعادة تعيين كلمة المرور', 'أدخل كود التحقق', 'كلمة المرور الجديدة'];
    final stepActions = [
      ('إرسال الكود', _sendOtp),
      ('تحقق من الكود', _verifyOtp),
      ('إعادة التعيين', _resetPassword),
    ];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        children: [
          Row(children: [
            const Icon(Icons.lock_reset, color: Colors.orange),
            const SizedBox(width: 8),
            Text(stepTitles[_step],
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          _buildStepIndicator(),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step == 0) _buildStep0(),
            if (_step == 1) _buildStep1(),
            if (_step == 2) _buildStep2(),
            if (_errorMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_errorMsg!,
                          style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : stepActions[_step].$2,
          style: ElevatedButton.styleFrom(
            backgroundColor: _step == 2 ? Colors.green : Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(stepActions[_step].$1),
        ),
      ],
    );
  }
}
