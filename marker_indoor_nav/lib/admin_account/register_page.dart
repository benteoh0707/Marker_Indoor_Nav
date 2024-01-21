// ignore_for_file: use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:marker_indoor_nav/admin_account/auth.dart';
import 'package:marker_indoor_nav/admin_account/login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<bool> checkIfEmailInUse() async {
    showDialog(
        context: context,
        builder: (_) => const Center(
              child: CircularProgressIndicator(),
            ));

    if (await Auth().checkIfEmailInUse(emailController.text.trim())) {
      Navigator.of(context).pop();
      const snackBar = SnackBar(content: Text('Email Address Existed'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
      return false;
    } else {
      Navigator.of(context).pop();
      return true;
    }
  }

  Future<bool> storeRegisterAcc() async {
    showDialog(
        context: context,
        builder: (_) => const Center(
              child: CircularProgressIndicator(),
            ));

    try {
      // Using Firestore
      await _firestore.collection("regAcc").add({
        'Name': nameController.text,
        'Email': emailController.text,
        'Password': passwordController.text,
      });
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please wait for the admin approval'),
      ));
      return true;
    } catch (error) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('An error occurred. Please try again.'),
      ));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary, //change your color here
        ),
        title: Text('Create An Account',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 25,
                fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const Text('Name',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter your name',
                    ),
                    validator: (value) {
                      if (value!.isEmpty) {
                        return "Name cannot be empty";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('Email address',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter your email',
                    ),
                    validator: (value) {
                      if (value!.isEmpty) {
                        return "Email cannot be empty";
                      }
                      if (!RegExp("^[a-zA-Z0-9+_.-]+@[a-zA-Z0-9.-]+.[a-z]")
                          .hasMatch(value)) {
                        return ("Please enter a valid email");
                      } else {
                        return null;
                      }
                    },
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),
                  const Text('Password',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter your password',
                    ),
                    validator: (value) {
                      if (value!.isEmpty) {
                        return "Password cannot be empty";
                      }
                      return null;
                    },
                    obscureText: true,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (_formKey.currentState!.validate() &&
                                await checkIfEmailInUse() &&
                                await storeRegisterAcc()) {
                              Navigator.of(context).pop();
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => const LoginPage()));
                              setState(() {});
                            }
                          },
                          child: const Text(
                            'Sign Up',
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
                    const Text("Already have an account? "),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const LoginPage()));

                        setState(() {});
                      }, //login page
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            )),
      ),
    );
  }
}
