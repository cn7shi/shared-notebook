import 'package:flutter/material.dart';

import '../application/session_controller.dart';
import 'common.dart';

class LoginScreen extends StatefulWidget {
  final SessionController controller;
  const LoginScreen({super.key, required this.controller});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void submit() {
    if (!widget.controller.busy && form.currentState!.validate()) {
      widget.controller.authenticate(
        email.text,
        password.text,
        register: register,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.auto_stories_outlined,
                      size: 52,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    '双方记事本',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '写下自己的生活，\n决定分享给谁。',
                    style: TextStyle(fontSize: 23, height: 1.6),
                  ),
                  const SizedBox(height: 36),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: '邮箱'),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v != null &&
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(v.trim())
                        ? null
                        : '请输入邮箱',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onFieldSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      helperText: register ? '至少 12 位，最多 128 位' : null,
                    ),
                    validator: (v) =>
                        v != null && v.length >= 12 && v.length <= 128
                        ? null
                        : '密码需要 12–128 位',
                  ),
                  if (widget.controller.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        widget.controller.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: widget.controller.busy ? null : submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.controller.busy
                            ? '正在连接…'
                            : register
                            ? '创建我的账户'
                            : '打开双方记事本',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.controller.busy
                        ? null
                        : () => setState(() => register = !register),
                    child: Text(register ? '已有账户，登录' : '第一次来，创建账户'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
