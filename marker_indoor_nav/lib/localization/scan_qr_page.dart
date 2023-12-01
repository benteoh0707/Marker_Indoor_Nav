// ignore_for_file: non_constant_identifier_names, avoid_types_as_parameter_names, prefer_const_literals_to_create_immutables, prefer_const_constructors, avoid_print, unused_element, use_build_context_synchronously, prefer_typing_uninitialized_variables

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dijkstra/dijkstra.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:marker_indoor_nav/mapping/building_profile.dart';
import 'package:marker_indoor_nav/mapping/map.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:collection/collection.dart';

class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});

  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  final qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  Circle? start;
  Map<String, dynamic> floorGraph = {};
  List<Circle> circles = [];
  List path = [];
  bool sel_des = false;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  void reassemble() async {
    super.reassemble();
    if (Platform.isAndroid) {
      await controller!.pauseCamera();
    }
    controller!.resumeCamera();
  }

  Widget buildQrView(BuildContext context) {
    return QRView(
        key: qrKey,
        onQRViewCreated: (QRViewController controller) {
          setState(() {
            this.controller = controller;
          });
          controller.scannedDataStream.listen((qr) async {
            List<String> result = qr.code!.split('_');
            if (await loadCircles(result)) {
              controller.pauseCamera();
              await showUserPosition(result[0], result[1])
                  .then((value) => controller.resumeCamera());
            }
          });
        },
        overlay: QrScannerOverlayShape(
          borderColor: Colors.transparent,
          cutOutWidth: MediaQuery.of(context).size.width,
          cutOutHeight: MediaQuery.of(context).size.height,
        ));
  }

  Future<Image?> downloadImage(String location) async {
    final imageName = '${location}_map.png';
    final ref =
        FirebaseStorage.instance.ref().child('blueprints').child(imageName);
    try {
      final result = await ref.getDownloadURL();
      return Image.network(result.toString());
    } catch (e) {
      print('Error fetching image: $e');
      return null;
    }
  }

  Future<bool> loadCircles(List<String> result) async {
    if (result.isEmpty) return false;

    final doc = await FirebaseFirestore.instance
        .collection('maps')
        .doc(result[0])
        .get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final circlesString = data['circles'];
      final pathString = data['path'];
      final circlesJson = jsonDecode(circlesString) as List;
      floorGraph = jsonDecode(pathString);

      circles =
          circlesJson.map((circleJson) => Circle.fromJson(circleJson)).toList();
      for (var c in circles) {
        if (c.id == result[1]) return true;
      }
      return false;
    } else {
      return false;
    }
  }

  showUserPosition(String location, String circleID) async {
    Image? uploadedImage = await downloadImage(location);
    path = [];
    sel_des = false;

    return showDialog(
      context: context,
      builder: (_) => StreamBuilder<CompassEvent>(
          stream: FlutterCompass.events,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Error reading heading: ${snapshot.error}');
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            double? direction = snapshot.data!.heading;

            return Dialog(
              elevation: 0,
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.all(0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      decoration: BoxDecoration(color: Colors.transparent),
                      child: Text(
                        'Select a destination',
                        style: TextStyle(
                            backgroundColor: Colors.transparent,
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      )),
                  Stack(
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height / 1.5,
                        child: Image(
                          image: uploadedImage!.image,
                          fit: BoxFit.fill, //BoxFit.contain?
                          alignment: Alignment.center,
                        ),
                      ),
                      ...path.mapIndexed((index, current_id) {
                        if (index + 1 < path.length) {
                          Circle next = circles.firstWhere(
                              (element) => element.id == path[index + 1]);
                          Circle current = circles.firstWhere(
                              (element) => element.id == current_id);

                          return CustomPaint(
                            painter: drawEdges(current, next),
                          );
                        } else {
                          return Divider(
                            color: Colors.transparent,
                            thickness: 0,
                          );
                        }
                      }),
                      ...circles.map((circle) {
                        if (circle.id == circleID) {
                          start = circle;
                        }

                        return Positioned(
                            left: circle.id == circleID
                                ? circle.position.dx - circle.size
                                : circle.position.dx,
                            top: circle.id == circleID
                                ? circle.position.dy - circle.size
                                : circle.position.dy,
                            child: circle.id == circleID
                                ? Transform.rotate(
                                    angle: (direction! * (pi / 180)),
                                    child: Image.asset(
                                      'assets/navigation.png',
                                      scale: 1.1,
                                      width: circle.size * 3,
                                      height: circle.size * 3,
                                    ))
                                : GestureDetector(
                                    onTap: () {
                                      if (!sel_des) {
                                        path = Dijkstra.findPathFromGraph(
                                            floorGraph, start?.id, circle.id);
                                        setState(() {
                                          sel_des = true;
                                        });
                                      }
                                    },
                                    child: Container(
                                      width: circle.size,
                                      height: circle.size,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ));
                      })
                    ],
                  ),
                  SizedBox(
                    height: 10,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/navigation.png',
                            scale: 1.1,
                            width: 30,
                            height: 30,
                          ),
                          Text(
                            'Current Location',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                            ),
                          ),
                          SizedBox(
                            width: 10,
                          ),
                          Text('List of destination point',
                              style: TextStyle(color: Colors.white)),
                        ],
                      )
                    ],
                  )
                ],
              ),
            );
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          'MarkerNav',
          style: GoogleFonts.pacifico(
            textStyle: TextStyle(
              color: Colors.white,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
              padding: EdgeInsets.only(right: 16),
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => EditProfilePage()));
                setState(() {});
              },
              icon: Icon(
                Icons.login_outlined,
                color: Colors.white,
                size: 30,
              )),
        ],
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height / 1.2,
                child: buildQrView(context)),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () async {
                    await controller?.toggleFlash();
                    setState(() {});
                  },
                  icon: FutureBuilder<bool?>(
                      future: controller?.getFlashStatus(),
                      builder: (context, snapshot) {
                        if (snapshot.data != null) {
                          return Icon(
                            snapshot.data! ? Icons.flash_on : Icons.flash_off,
                            color: Colors.white,
                          );
                        } else {
                          return Divider();
                        }
                      }),
                ),
                Text(
                  'Scan a Marker',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20),
                ),
                IconButton(
                  onPressed: () async {
                    await controller?.flipCamera();
                    setState(() {});
                  },
                  icon: FutureBuilder(
                      future: controller?.getCameraInfo(),
                      builder: (context, snapshot) {
                        if (snapshot.data != null) {
                          return Icon(
                            Icons.switch_camera,
                            color: Colors.white,
                          );
                        } else {
                          return Divider();
                        }
                      }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
