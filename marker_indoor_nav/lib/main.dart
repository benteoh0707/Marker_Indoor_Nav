import 'package:flutter/material.dart';
import 'package:marker_indoor_nav/home.dart';

void main() {
  runApp(MaterialApp(title: 'Flutter Demo', initialRoute: '/home', routes: {
    '/home': (context) => const MyHomePage(title: 'Flutter Demo Home Page'),
  }));
}
