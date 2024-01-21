// ignore_for_file: prefer_const_constructors, use_build_context_synchronously

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:marker_indoor_nav/admin_account/auth.dart';
import 'package:marker_indoor_nav/admin_account/register_page.dart';
import 'package:marker_indoor_nav/mapping/building_profile.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<bool> resetPassword() async {
    showDialog(
        context: context,
        builder: (_) => Center(
              child: CircularProgressIndicator(),
            ));

    try {
      await Auth().resetPassword(email: emailController.text);
      Navigator.of(context).pop();
      return true;
      // ignore: unused_catch_clause
    } on FirebaseAuthException catch (e) {
      Navigator.of(context).pop();
      const snackBar = SnackBar(content: Text('Reset Password Failed'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      return false;
    }
  }

  Future<bool> signInWithEmailAndPassword() async {
    showDialog(
        context: context,
        builder: (_) => Center(
              child: CircularProgressIndicator(),
            ));

    try {
      await Auth().signInWithEmailAndPassword(
          email: emailController.text, password: passwordController.text);
      Navigator.of(context).pop();
      return true;
      // ignore: unused_catch_clause
    } on FirebaseAuthException catch (e) {
      Navigator.of(context).pop();
      const snackBar = SnackBar(content: Text('Login Failed'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      return false;
    }
  }

  Future<void> confirmEmail() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
          title: Text(
            'Confirm Email Address',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("A reset password link will send to this email address"),
              SizedBox(
                height: 10,
              ),
              TextField(
                controller: emailController,
                decoration: InputDecoration(labelText: 'Enter Email Address'),
              ),
              SizedBox(
                height: 20,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () async {
                        if (await resetPassword()) {
                          Navigator.of(context).pop();
                          const snackBar =
                              SnackBar(content: Text('Password Reset'));
                          ScaffoldMessenger.of(context).showSnackBar(snackBar);
                        }
                      },
                      child: Text('Reset Password')),
                ],
              )
            ],
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary, //change your color here
        ),
        title: Text('Sign In',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 25,
                fontWeight: FontWeight.bold)),
      ),
      body: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Email address',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
              const SizedBox(height: 10),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter your email',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              const Text('Password',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
              const SizedBox(height: 10),
              TextFormField(
                controller: passwordController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter your password',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: confirmEmail, //forgot password
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (await signInWithEmailAndPassword()) {
                          Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => EditProfilePage()));
                          setState(() {});
                        }
                      }, //signin
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Don't have an account? "),
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => RegisterPage()));

                    setState(() {});
                  }, //register page
                  child: Text(
                    'Sign Up',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ]),
            ],
          )),
    );
  }
}
