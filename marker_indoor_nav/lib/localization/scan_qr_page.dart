// ignore_for_file: non_constant_identifier_names, avoid_types_as_parameter_names, prefer_const_literals_to_create_immutables, prefer_const_constructors, avoid_print, unused_element, use_build_context_synchronously, prefer_typing_uninitialized_variables

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:dijkstra/dijkstra.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:marker_indoor_nav/admin_account/auth.dart';
import 'package:marker_indoor_nav/admin_account/login_page.dart';
//import 'package:marker_indoor_nav/localization/aruco.dart';
import 'package:marker_indoor_nav/mapping/building_profile.dart';
import 'package:marker_indoor_nav/mapping/map.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:vibration/vibration.dart';

class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});

  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  final qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  //ArCoreController? arCoreController;
  //Circle? start;
  Map<String, dynamic> floorGraph = {};
  List<Circle> circles = [];
  //String? location, circleID;
  List<String> result = [];
  List path = [];
  int next = 1;
  String? dest_id, dest_name;
  FlutterTts flutterTts = FlutterTts();
  Circle? c;
  StreamSubscription<CompassEvent>? _compassSubscription;
  bool arAvailable = false;

  @override
  void dispose() {
    _compassSubscription?.cancel();
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
            await controller.pauseCamera();
            await showDialog(
                context: context,
                builder: (_) => AlertDialog(
                      title: Text('QR code detected'),
                    )).then((value) async => await controller.resumeCamera());

            // List<String> test = qr.code!.split('_');

            // if (test.isNotEmpty && test.length == 2) {
            //   if (result.isEmpty && path.isEmpty) {
            //     speak('Marker Detected');
            //     await controller.pauseCamera();
            //     showDialog(
            //         context: context,
            //         builder: (_) => Center(
            //               child: CircularProgressIndicator(),
            //             ));

            //     if (await loadCircles(test)) {
            //       for (var circle in circles) {
            //         if (circle.id == test[1]) {
            //           Navigator.of(context).pop();
            //           speak('Currently at ${test[0]} ${circle.name}');

            //           if (await showDestination(circle.id)) {
            //             setState(() {
            //               c = circle;
            //               result = test;
            //             });
            //           }
            //           break;
            //         }
            //       }

            //       if (path.isNotEmpty) {
            //         //todo: add direction
            //         await getDirection(
            //             c?.connected_nodes[path[next]]['direction']);
            //       }
            //     } else {
            //       Navigator.of(context).pop();
            //       speak('Unknown Marker');
            //     }
            //     await controller.resumeCamera();
            //   } else if (path.isNotEmpty && result[1] != test[1]) {
            //     _compassSubscription?.cancel();
            //     await flutterTts.stop();

            //     if (result[0] == test[0]) {
            //       if (test[1] == dest_id) {
            //         //reach destination
            //         controller.pauseCamera();

            //         speak(
            //             'You have reach your destination,${test[0]} $dest_name');
            //         Timer? timer = Timer(Duration(seconds: 7), () {
            //           Navigator.of(context, rootNavigator: true).pop();
            //         });
            //         await showDialog(
            //           context: context,
            //           builder: (BuildContext context) {
            //             return AlertDialog(
            //               title: Text('Destination Arrived'),
            //               actions: [
            //                 TextButton(
            //                   child: Text("Continue"),
            //                   onPressed: () {
            //                     Navigator.of(context).pop();
            //                   },
            //                 ),
            //               ],
            //             );
            //           },
            //         ).then((value) {
            //           controller.resumeCamera();
            //           timer?.cancel();
            //           timer = null;
            //         });
            //         setState(() {
            //           result = [];
            //           path = [];
            //         });
            //       } else if (test[1] == path[next]) {
            //         //identrify next marker
            //         setState(() {
            //           c = circles
            //               .firstWhere((circle) => circle.id == path[next]);
            //           result = test;
            //           next++;
            //         });
            //         await speak('Reach ${test[0]} ${c?.name}');
            //       } else if (floorGraph.keys.contains(test[1])) {
            //         //reroute
            //         await speak('Reach the wrong next point, Rerouting');

            //         setState(() {
            //           next = 1;
            //           path = Dijkstra.findPathFromGraph(
            //               floorGraph, test[1], dest_id);
            //           c = circles.firstWhere((circle) => circle.id == test[1]);
            //           result = test;
            //         });

            //         await speak('Reroute, Currently at ${test[0]} ${c?.name}');
            //       }

            //       if (path.isNotEmpty) {
            //         //todo: add direction
            //         await getDirection(
            //             c?.connected_nodes[path[next]]['direction']);
            //       }
            //     } else {
            //       final doc = await FirebaseFirestore.instance
            //           .collection('maps')
            //           .doc(test[0])
            //           .get();
            //       if (doc.exists) {
            //         //todo: wrong floor
            //       }
            //     }
            //   }
            // }
          });
        },
        overlay: QrScannerOverlayShape(
          borderColor: Colors.transparent,
          cutOutWidth: MediaQuery.of(context).size.width,
          cutOutHeight: MediaQuery.of(context).size.height,
        ));
  }

  Future<void> getDirection(facing_target) async {
    bool? canVibrate = await Vibration.hasVibrator();
    String speech = '';
    _compassSubscription = FlutterCompass.events?.listen((event) async {
      double gap = facing_target - event.heading;

      if (gap.truncate() >= -20 && gap.truncate() <= 20) {
        if (speech != 'Move straight') {
          speech = 'Move straight';
          await speak('Move straight');
        }
      } else if (gap.truncate() > 0 && gap.truncate() < 180) {
        if (canVibrate == true) {
          await Vibration.vibrate();
        }
        if (speech != 'Turn right') {
          speech = 'Turn right';
          await speak('Turn right');
        }
      } else {
        if (canVibrate == true) {
          await Vibration.vibrate();
        }
        if (speech != 'Turn left') {
          speech = 'Turn left';
          await speak('Turn left');
        }
      }
    });
  }

  Future<bool> showDestination(c_id) async {
    await showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Destinations'),
              scrollable: true,
              content: SizedBox(
                height: 300,
                width: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: circles.length,
                  itemBuilder: (BuildContext context, int index) {
                    if (circles[index].id == c_id) {
                      return Container();
                    }

                    return ListTile(
                      title: Text(circles[index].name ?? '',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () async {
                        // arAvailable =
                        //     await ArCoreController.checkArCoreAvailability();
                        setState(() {
                          next = 1;
                          path = Dijkstra.findPathFromGraph(
                              floorGraph, c_id, circles[index].id);
                          dest_id = circles[index].id;
                          dest_name = circles[index].name;
                        });
                        Navigator.of(context).pop();
                      },
                      onLongPress: () =>
                          speak(circles[index].name), //todo: blinder sensor
                    );
                  },
                ),
              ),
            ));
    return path.isNotEmpty;
  }

  //todo: may use in FYP2
  Future<Image?> downloadImage(String location) async {
    final imageName = '${location}_map.png';
    final ref =
        FirebaseStorage.instance.ref().child('blueprints').child(imageName);
    try {
      final img = await ref.getDownloadURL();
      return Image.network(img.toString());
    } catch (e) {
      print('Error fetching image: $e');
      return null;
    }
  }

  Future<bool> loadCircles(List<String> test) async {
    final doc =
        await FirebaseFirestore.instance.collection('maps').doc(test[0]).get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final circlesString = data['circles'];
      final pathString = data['path'];
      final img_width = data['image_width'];
      final img_height = data['image_height'];
      final circlesJson = jsonDecode(circlesString) as List;
      floorGraph = jsonDecode(pathString);

      circles = circlesJson
          .map((circleJson) => Circle.fromJson(
              circleJson,
              MediaQuery.of(context).size.width,
              MediaQuery.of(context).size.height / 1.5,
              img_width,
              img_height))
          .toList();

      return true;
    }

    return false;
  }

  //todo: no use alr

  showUserPosition(String location, String circleID) async {
    Image? uploadedImage = await downloadImage(location);

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
                              : Container(
                                  width: circle.size,
                                  height: circle.size,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.blue,
                                  ),
                                ),
                        );
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

  Future<void> speak(text) async {
    await flutterTts.awaitSpeakCompletion(true);
    await flutterTts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 30,
          ),
        ),
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
              onPressed: () async {
                _compassSubscription?.cancel();
                await flutterTts.stop();
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => Auth().currentUser == null
                            ? LoginPage()
                            : EditProfilePage()));
                result = [];
                path = [];

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
              child: Stack(children: [
            SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height / 1.2,
                child: buildQrView(context)),
            // SizedBox(
            //     width: MediaQuery.of(context).size.width,
            //     height: MediaQuery.of(context).size.height / 1.2,
            //     child: Visibility(
            //         visible: path.isNotEmpty && arAvailable,
            //         child:
            //             ArCoreView(onArCoreViewCreated: _onArCoreViewCreated))),
            Visibility(
              visible: path.isNotEmpty,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FloatingActionButton.extended(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                          onPressed: () async {
                            _compassSubscription?.cancel();
                            await flutterTts.stop();
                            speak('Navigation stop');
                            setState(() {
                              result = [];
                              path = [];
                            });
                          },
                          icon: Icon(Icons.cancel),
                          label: Text('Stop Navigation'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ])),
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
                GestureDetector(
                  onTap: () async {
                    if (result.isNotEmpty) {
                      controller?.pauseCamera();
                      // await Navigator.push(
                      //         context,
                      //         MaterialPageRoute<void>(
                      //             builder: (BuildContext context) => showResult(
                      //                   location: result[0],
                      //                   circleID: c!.id,
                      //                   floorGraph: floorGraph,
                      //                   circles: circles,
                      //                 )))
                      //     .then((value) => controller?.resumeCamera());
                      // setState(() {
                      //   result = [];
                      // });
                      await showUserPosition(result[0], c!.id);
                      controller?.resumeCamera();
                    }
                  },
                  onLongPress: () {
                    if (result.isNotEmpty) {
                      speak('${result[0]} ${c?.name}');
                    }
                  },
                  child: result.isEmpty
                      ? Text(
                          'Scan a Marker',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20),
                        )
                      : Text(
                          '${result[0]} ${c?.name}',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
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
