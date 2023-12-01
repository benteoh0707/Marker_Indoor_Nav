// ignore_for_file: non_constant_identifier_names, avoid_types_as_parameter_names, prefer_const_literals_to_create_immutables, prefer_const_constructors, avoid_print, unused_element, use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:marker_indoor_nav/mapping/building_profile.dart';
import 'package:marker_indoor_nav/mapping/map.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});

  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  final qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

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
          controller.pauseCamera();
          List<String> result = qr.code!.split('_');
          await showUserPosition(result[0], result[1])
              .then((value) => controller.resumeCamera());
        });
      },
      overlay: QrScannerOverlayShape(
          borderColor: Colors.transparent,
          cutOutWidth: MediaQuery.of(context).size.width,
          cutOutHeight: MediaQuery.of(context).size.height),
    );
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

  Future<Circle?> loadCircle(String location, String circleID) async {
    final doc =
        await FirebaseFirestore.instance.collection('maps').doc(location).get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final circlesString = data['circles'];
      final circlesJson = jsonDecode(circlesString) as List;
      final loadedCircles =
          circlesJson.map((circleJson) => Circle.fromJson(circleJson)).toList();
      final circle =
          loadedCircles.firstWhere((element) => element.id == circleID);
      return circle;
    } else {
      return null;
    }
  }

  showUserPosition(String location, String circleID) async {
    Image? uploadedImage = await downloadImage(location);
    Circle? circle = await loadCircle(location, circleID);
    print(circle?.position.toString());

    return showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(0),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    decoration: BoxDecoration(color: Colors.transparent),
                    child: Text(
                      "Here You Are",
                      style: TextStyle(
                          backgroundColor: Colors.transparent,
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    )),
                SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height / 1.5,
                  child: Image(
                    image: uploadedImage!.image,
                    fit: BoxFit.fill, //BoxFit.contain?
                    alignment: Alignment.center,
                  ),
                ),
              ],
            ),
            Positioned(
                left: circle?.position.dx,
                top: circle!.position.dy,
                child: Container(
                  width: circle.size,
                  height: circle.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue,
                  ),
                ))
          ],
        ),
      ),
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
              padding: EdgeInsets.all(16),
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
          SizedBox(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height / 1.2,
              child: buildQrView(context)),
          Padding(
            padding: EdgeInsets.fromLTRB(16.0, 0, 16.0, 0),
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
