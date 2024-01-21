// ignore_for_file: prefer_const_constructors, non_constant_identifier_names, camel_case_types, avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:dijkstra/dijkstra.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:marker_indoor_nav/mapping/map.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

// ignore: must_be_immutable
class showResult extends StatefulWidget {
  String location, circleID;
  Map<String, dynamic> floorGraph = {};
  List<Circle> circles = [];

  showResult(
      {super.key,
      required this.location,
      required this.circleID,
      required this.floorGraph,
      required this.circles});

  @override
  State<showResult> createState() => _showResultState();
}

class _showResultState extends State<showResult> {
  Circle? start;
  List path = [];
  bool sel_des = false;
  Image? uploadedImage;
  final qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

  @override
  initState() {
    super.initState();
    downloadImage(widget.location);
  }

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

  downloadImage(String location) async {
    final imageName = '${location}_map.png';
    final ref =
        FirebaseStorage.instance.ref().child('blueprints').child(imageName);
    try {
      final img = await ref.getDownloadURL();
      uploadedImage = Image.network(img.toString());
      setState(() {});
    } catch (e) {
      print('Error fetching image: $e');
    }
  }

  Widget buildQrView(BuildContext context) {
    return QRView(
        key: qrKey,
        onQRViewCreated: (QRViewController controller) {
          setState(() {
            this.controller = controller;
          });
          controller.scannedDataStream.listen((qr) async {
            List<String> test = qr.code!.split('_');
            if (widget.location == test[0]) {
              if (!path.contains(test[1]) ||
                  (test[1] == path[path.length - 1] && sel_des)) {
                path = [];
                sel_des = false;
              }
              setState(() {
                widget.circleID = test[1];
              });
            } else if (await loadCircles(test) && widget.location != test[0]) {
              //controller.pauseCamera();
              path = [];
              sel_des = false;
              await downloadImage(test[0]);
              setState(() {
                widget.location = test[0];
                widget.circleID = test[1];
              });
              //controller.resumeCamera();
              //controller.pauseCamera();
              // await showUserPosition(result[0], result[1])
              //     .then((value) => controller.resumeCamera());
            }
          });
        },
        overlay: QrScannerOverlayShape(
          borderColor: Colors.transparent,
          cutOutWidth: MediaQuery.of(context).size.width,
          cutOutHeight: MediaQuery.of(context).size.height,
        ));
  }

  Future<bool> loadCircles(List<String> test) async {
    if (test.isEmpty) return false;

    final doc =
        await FirebaseFirestore.instance.collection('maps').doc(test[0]).get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final circlesString = data['circles'];
      final pathString = data['path'];
      final img_width = data['image_width'];
      final img_height = data['image_height'];
      final circlesJson = jsonDecode(circlesString) as List;
      widget.floorGraph = jsonDecode(pathString);

      widget.circles = circlesJson
          .map((circleJson) => Circle.fromJson(
              circleJson,
              MediaQuery.of(context).size.width,
              MediaQuery.of(context).size.height / 1.5,
              img_width,
              img_height))
          .toList();
      for (var c in widget.circles) {
        if (c.id == test[1]) return true;
      }
      return false;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
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

          return Scaffold(
            appBar: AppBar(
              title: Text('Demo'),
              leading: IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
              ),
            ),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: SizedBox(child: buildQrView(context)),
                ),
                Stack(
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height / 1.5,
                      child: uploadedImage != null
                          ? Image(
                              image: uploadedImage!.image,
                              fit: BoxFit.fill, //BoxFit.contain?
                              alignment: Alignment.center,
                            )
                          : null,
                    ),
                    ...path.mapIndexed((index, current_id) {
                      if (index + 1 < path.length) {
                        Circle next = widget.circles.firstWhere(
                            (element) => element.id == path[index + 1]);
                        Circle current = widget.circles
                            .firstWhere((element) => element.id == current_id);

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
                    ...widget.circles.map((circle) {
                      if (circle.id == widget.circleID) {
                        start = circle;
                        if (sel_des) {
                          circle.selected = true;
                        }
                      }

                      if (!sel_des) {
                        circle.selected = false;
                      }

                      return Positioned(
                          left: circle.id == widget.circleID
                              ? circle.position.dx - circle.size
                              : circle.position.dx,
                          top: circle.id == widget.circleID
                              ? circle.position.dy - circle.size
                              : circle.position.dy,
                          child: circle.id == widget.circleID
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
                                          widget.floorGraph,
                                          start?.id,
                                          circle.id);
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
                                      color: circle.selected == true
                                          ? Colors.green
                                          : Colors.blue,
                                    ),
                                  ),
                                ));
                    })
                  ],
                ),
              ],
            ),
          );
        });
  }
}
