// ignore_for_file: library_private_types_in_public_api, prefer_const_constructors, non_constant_identifier_names, use_build_context_synchronously, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dv;
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:dijkstra/dijkstra.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_aruco_detector/aruco_detector.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:marker_indoor_nav/admin_account/auth.dart';
import 'package:marker_indoor_nav/admin_account/login_page.dart';
import 'package:marker_indoor_nav/localization/layer.dart';
import 'package:marker_indoor_nav/localization/scan_qr_page.dart';
import 'package:marker_indoor_nav/mapping/building_profile.dart';
import 'package:marker_indoor_nav/mapping/map.dart';
import 'package:vibration/vibration.dart';

class DetectionPage extends StatefulWidget {
  const DetectionPage({Key? key}) : super(key: key);

  @override
  _DetectionPageState createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage>
    with WidgetsBindingObserver {
  late CameraController _camController;
  late Future<void> _initializeControllerFuture;
  late ArucoDetectorAsync _arucoDetector;
  CameraDescription? desc;
  int _camFrameRotation = 0;
  double _camFrameToScreenScale = 0;
  int _lastRun = 0;
  bool _detectionInProgress = false;
  List<List<double>> _arucos = List.empty();
  Orientation? screen_orient;

  FlutterTts flutterTts = FlutterTts();
  Map<String, dynamic> ar_floorGraph = {}, qr_floorGraph = {};
  List<Circle> circles = [];
  Map<String, int?> result = {}; //markerID, profileID, floorID
  List ar_path = [], qr_path = [];
  String? profileName;
  String? dest_qr_id;
  int? dest_marker_id;
  String? dest_name;
  int nextDest = 1;
  Circle? cur_c;
  StreamSubscription<CompassEvent>? _compassSubscription;
  bool skipfirstScan = false;
  bool onGuidance = false, onNavigation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arucoDetector = ArucoDetectorAsync();
    initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController cameraController = _camController;

    // App state changed before we got the chance to initialize.
    if (!cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arucoDetector.destroy();
    _camController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    setState(() {});
  }

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    var idx =
        cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (idx < 0) {
      dv.log("No Back camera found - weird");
      return;
    }
    screen_orient = MediaQuery.of(context).orientation;
    desc = cameras[idx];
    _camFrameRotation = (Platform.isAndroid ? desc?.sensorOrientation : 0)!;
    _camController = CameraController(
      desc!,
      ResolutionPreset.high, // 720p
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    try {
      _initializeControllerFuture = _camController.initialize();
      _initializeControllerFuture.whenComplete(() => _camController
          .startImageStream((image) => _processCameraImage(image)));
    } catch (e) {
      dv.log("Error initializing camera, error: ${e.toString()}");
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (skipfirstScan) {
      skipfirstScan = false;
      return;
    }

    if (_detectionInProgress ||
        !mounted ||
        DateTime.now().millisecondsSinceEpoch - _lastRun < 30) {
      return;
    }

    // calc the scale factor to convert from camera frame coords to screen coords.
    // NOTE!!!! We assume camera frame takes the entire screen width, if that's not the case
    // (like if camera is landscape or the camera frame is limited to some area) then you will
    // have to find the correct scale factor somehow else

    if (_camFrameToScreenScale == 0 ||
        screen_orient != MediaQuery.of(context).orientation) {
      screen_orient = MediaQuery.of(context).orientation;

      var w =
          (screen_orient == Orientation.landscape) ? image.width : image.height;
      _camFrameToScreenScale = MediaQuery.of(context).size.width / w;
    }

    // Call the detector
    _detectionInProgress = true;

    //markerId, headPoint: {x: ,y:}, corners:[top left, top right, bottom right, bottom left]
    var res = await _arucoDetector.detect(
        image, _camFrameRotation, DICTIONARY.DICT_ARUCO_ORIGINAL);

    _detectionInProgress = false;
    _lastRun = DateTime.now().millisecondsSinceEpoch;

    // Make sure we are still mounted, the background thread can return a response after we navigate away from this
    // screen but before bg thread is killed
    if (!mounted || res == null || res.isEmpty) {
      setState(() {
        _arucos = List.empty();
      });
      return;
    }

    if (res.length >= 3) {
      detectionHandling(res);
      if ((res[0]['corners'].length / 8) != (res[0]['corners'].length ~/ 8)) {
        dv.log(
            'Got invalid response from ArucoDetector, number of coords is ${res[0]['corners'].length} and does not represent complete arucos with 4 corners');
        return;
      }

      // //convert arucos from camera frame coords to screen coords

      List<List<double>> arucos = [];

      if (screen_orient == Orientation.portrait) {
        for (var r in res) {
          List<double> corners = List<double>.from(r['corners']);

          final aruco = corners
              .map((double x) => x * _camFrameToScreenScale)
              .toList(growable: false);

          arucos.add(aruco);
        }
      }
      setState(() {
        _arucos = arucos;
      });
    }
  }

  Future<void> detectionHandling(List detectResult) async {
    int? markerID, profileID, floorID;
    List markerInfo = [];
    double marker_area = 0;

    for (var r in detectResult) {
      int id = r['markerId'];
      if (id < 500) {
        //marker
        markerInfo.add(r);
      } else if (id >= 500 && id < 1000) {
        //profile
        profileID = id;
      } else {
        //floor
        floorID = id;
      }
    }

    if (markerInfo.isNotEmpty) {
      for (var marker in markerInfo) {
        double start_x = marker['headPoint']['x'] * _camFrameToScreenScale;
        double start_y = marker['headPoint']['y'] * _camFrameToScreenScale;
        double end_x = marker['corners'][2] * _camFrameToScreenScale;
        double end_y = marker['corners'][3] * _camFrameToScreenScale;

        Offset start = Offset(start_x, start_y);
        Offset end = Offset(end_x, end_y);

        double area = ((end - start) * 2).distanceSquared;
        if (area > marker_area) {
          marker_area = area;
          markerID = marker['markerId'];
        }
      }
    } else {
      return;
    }

    if (markerID == null || profileID == null || floorID == null) {
      return;
    }

    if (marker_area > 0) {
      double min_screen = min(MediaQuery.of(context).size.width,
          MediaQuery.of(context).size.height);
      num screen = pow(min_screen, 2);
      double percent = (marker_area / screen) * 100;
      print('markerid: $markerID area: $marker_area ;percentage : $percent');

      if (percent < 0.3) {
        return;
      }
    } else {
      return;
    }

    if (!onNavigation) {
      startNavigation(markerID, profileID, floorID)
          .whenComplete(() => onNavigation = false);
    }
  }

  Future<void> startNavigation(int markerID, int profileID, int floorID) async {
    onNavigation = true;

    if (result.isEmpty && ar_path.isEmpty && qr_path.isEmpty) {
      //first time detected

      await speak('Marker Detected');

      await _camController.stopImageStream();
      await _camController.pausePreview();

      showDialog(
          context: context,
          builder: (_) => Center(
                child: CircularProgressIndicator(),
              ));

      if (await loadCircles(profileID, floorID)) {
        for (var circle in circles) {
          if (circle.marker_id == markerID) {
            await speak(
                'Currently at $profileName Floor ${floorID - 999} ${circle.name}');
            Navigator.of(context).pop();

            if (await showDestination(circle.marker_id.toString(), circle.id)) {
              setState(() {
                cur_c = circle;
                result = {
                  'markerID': markerID,
                  'profileID': profileID,
                  'floorID': floorID
                };
              });
            }
            break;
          }
        }

        if (ar_path.isNotEmpty && qr_path.isNotEmpty && !onGuidance) {
          //todo: add direction
          await getDirection(
              cur_c?.connected_nodes[qr_path[nextDest]]['direction']);
        } else {
          setState(() {
            skipfirstScan = true;
          });
        }
      } else {
        Navigator.of(context).pop();
        speak('Unknown Marker');
        setState(() {
          skipfirstScan = true;
        });
      }

      await _camController.resumePreview();
      await _camController
          .startImageStream((image) => _processCameraImage(image));
    } else if (ar_path.isNotEmpty &&
        qr_path.isNotEmpty &&
        markerID != result['markerID']) {
      await flutterTts.stop();
      await _compassSubscription
          ?.cancel()
          .whenComplete(() => onGuidance = false);

      if (result['profileID'] == profileID && result['floorID'] == floorID) {
        //detected another marker

        if (markerID == dest_marker_id) {
          await speak("Stop");
          //reach destination
          await _camController.stopImageStream();
          _camController.pausePreview();
          skipfirstScan = true;
          speak(
              'You have reach your destination,$profileName Floor ${result['floorID']! - 999} $dest_name');

          Timer? timer = Timer(Duration(seconds: 7), () {
            Navigator.of(context, rootNavigator: true).pop();
          });

          await showDialog(
            context: context,
            builder: (BuildContext context) {
              return ExcludeSemantics(
                child: AlertDialog(
                  title: Text('Destination Arrived'),
                  actions: [
                    TextButton(
                      child: Text("Continue"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              );
            },
          ).then((value) async {
            await _camController.resumePreview();
            await _camController
                .startImageStream((image) => _processCameraImage(image));

            timer?.cancel();
            timer = null;
          });
          setState(() {
            result = {};
            ar_path = [];
            qr_path = [];
          });
        } else if (markerID == int.parse(ar_path[nextDest])) {
          await speak("Reach a new checkpoint");
          cur_c = circles.firstWhere(
              (circle) => circle.marker_id == int.parse(ar_path[nextDest]));
          result['markerID'] = markerID;
          nextDest++;
          setState(() {});
        } else if (ar_floorGraph.keys.contains(markerID.toString())) {
          //reroute
          await speak('Stop, rerouting');

          nextDest = 1;
          cur_c = circles.firstWhere((circle) => circle.marker_id == markerID);

          ar_path = Dijkstra.findPathFromGraph(
              ar_floorGraph, markerID.toString(), dest_marker_id.toString());
          qr_path =
              Dijkstra.findPathFromGraph(qr_floorGraph, cur_c?.id, dest_qr_id);

          result['markerID'] = markerID;

          setState(() {});
        }

        if (ar_path.isNotEmpty && qr_path.isNotEmpty && !onGuidance) {
          //todo: add direction
          await getDirection(
              cur_c?.connected_nodes[qr_path[nextDest]]['direction']);
        }
      } else {}
    }
  }

  Future<void> getDirection(facing_target) async {
    onGuidance = true;
    bool? canVibrate = await Vibration.hasVibrator();
    String speech = '';
    int skip = 0;

    _compassSubscription = FlutterCompass.events?.listen((event) async {
      if (skip < 3) {
        ++skip;
      } else {
        double gap = facing_target - event.heading;
        if (gap > 180 || gap < -180) {
          if (event.heading!.isNegative) {
            gap = gap - 360;
          } else {
            gap = 360 + gap;
          }
        }

        if (gap.truncate() >= -40 && gap.truncate() <= 40) {
          if (speech != 'Move straight') {
            await speak('Move straight');
            speech = 'Move straight';
          }
        } else if (gap.truncate() > 0 && gap.truncate() < 180) {
          if (canVibrate == true) {
            await Vibration.vibrate(duration: 100);
          }
          if (speech != 'Turn right') {
            await speak('Turn right');
            speech = 'Turn right';
          }
        } else {
          if (canVibrate == true) {
            await Vibration.vibrate(duration: 100);
          }
          if (speech != 'Turn left') {
            await speak('Turn left');
            speech = 'Turn left';
          }
        }
      }
    });
  }

  Future<bool> showDestination(c_marker_id, c_id) async {
    //await speak('choose your destination');
    await showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => AlertDialog(
        title:
            Semantics(focused: true, child: Text('Choose Your Destinations')),
        scrollable: true,
        content: Column(
          children: [
            SizedBox(
              height: 300,
              width: 300,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: circles.length,
                itemBuilder: (BuildContext context, int index) {
                  if (circles[index].id == c_id ||
                      circles[index].connected_nodes.isEmpty) {
                    return Container();
                  }

                  return ListTile(
                    title: Text(circles[index].name ?? '',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () async {
                      setState(() {
                        nextDest = 1;
                        ar_path = Dijkstra.findPathFromGraph(ar_floorGraph,
                            c_marker_id, circles[index].marker_id.toString());
                        qr_path = Dijkstra.findPathFromGraph(
                            qr_floorGraph, c_id, circles[index].id);
                        dest_qr_id = circles[index].id;
                        dest_marker_id = circles[index].marker_id;
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
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'))
          ],
        ),
      ),
    );

    return ar_path.isNotEmpty && qr_path.isNotEmpty;
  }

  Future<bool> loadCircles(int profileID, int floorID) async {
    final profileDoc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(profileID.toString())
        .get();
    if (profileDoc.exists) {
      final profileData = profileDoc.data() as Map<String, dynamic>;
      profileName = profileData['profileName'] as String;
      String mapName = '$profileName Floor ${floorID - 999}';

      final doc = await FirebaseFirestore.instance
          .collection('maps')
          .doc(mapName)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final circlesString = data['circles'];
        final ar_pathString = data['ar_path'];
        final qr_pathString = data['qr_path'];
        final img_width = data['image_width'];
        final img_height = data['image_height'];
        final circlesJson = jsonDecode(circlesString) as List;
        ar_floorGraph = jsonDecode(ar_pathString);
        qr_floorGraph = jsonDecode(qr_pathString);

        circles = circlesJson
            .map((circleJson) => Circle.fromJson(
                circleJson,
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).size.height / 1.5,
                img_width,
                img_height))
            .toList();
        setState(() {});
        return circles.isNotEmpty;
      }
    }

    return false;
  }

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
                      ...qr_path.mapIndexed((index, current_id) {
                        if (index + 1 < qr_path.length) {
                          Circle next = circles.firstWhere(
                              (element) => element.id == qr_path[index + 1]);
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
        backgroundColor: Colors.black,
        leading: ExcludeSemantics(
          child: TextButton(
              onPressed: () async {
                await _camController.stopImageStream();
                await _camController.pausePreview();

                _compassSubscription
                    ?.cancel()
                    .whenComplete(() => onGuidance = false);
                await flutterTts.stop();
                await Navigator.push(context,
                    MaterialPageRoute(builder: (context) => QRScanPage()));

                result = {}; //markerID, profileID, floorID
                ar_path = [];
                qr_path = [];

                initCamera();

                setState(() {});
              },
              child: Text(
                'QR',
                style: TextStyle(color: Colors.white, fontSize: 20),
              )),
        ),
        title: ExcludeSemantics(
          child: Text(
            'MarkerNav',
            style: GoogleFonts.pacifico(
              textStyle: TextStyle(
                color: Colors.white,
              ),
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          ExcludeSemantics(
            child: IconButton(
                padding: EdgeInsets.only(right: 16),
                onPressed: () async {
                  await _camController.stopImageStream();
                  await _camController.pausePreview();

                  _compassSubscription
                      ?.cancel()
                      .whenComplete(() => onGuidance = false);
                  await flutterTts.stop();
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => Auth().currentUser == null
                              ? LoginPage()
                              : EditProfilePage()));

                  result = {}; //markerID, profileID, floorID
                  ar_path = [];
                  qr_path = [];

                  await _camController.resumePreview();
                  await _camController
                      .startImageStream((image) => _processCameraImage(image));

                  setState(() {});
                },
                icon: Icon(
                  Icons.login_outlined,
                  color: Colors.white,
                  size: 30,
                )),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              width: MediaQuery.of(context).size.width,
              child: Stack(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height,
                    width: MediaQuery.of(context).size.width,
                    child: FutureBuilder<void>(
                        future: _initializeControllerFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.done) {
                            // If the Future is complete, display the preview.
                            return CameraPreview(_camController);
                          } else {
                            // Otherwise, display a loading indicator.
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                        }),
                  ),
                  ..._arucos.map(
                    (aru) => DetectionsLayer(
                      arucos: aru,
                      //screen_orient: screen_orient,
                    ),
                  ),
                  Visibility(
                    visible: ar_path.isNotEmpty && qr_path.isNotEmpty,
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
                                  await _compassSubscription
                                      ?.cancel()
                                      .whenComplete(() => onGuidance = false);
                                  await flutterTts.stop();
                                  await speak('Navigation stop');
                                  setState(() {
                                    skipfirstScan = true;
                                    result = {};
                                    ar_path = [];
                                    qr_path = [];
                                  });
                                },
                                icon:
                                    ExcludeSemantics(child: Icon(Icons.cancel)),
                                label: ExcludeSemantics(
                                    child: Text('Stop Navigation')),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Container(
                    padding: EdgeInsets.all(8.0),
                    child: GestureDetector(
                      onTap: () async {
                        if (result.isNotEmpty) {
                          await _camController.stopImageStream();
                          await _camController.pausePreview();

                          await showUserPosition(
                              '$profileName Floor ${result['floorID']! - 999}',
                              cur_c!.id);

                          await _camController.resumePreview();
                          await _camController.startImageStream(
                              (image) => _processCameraImage(image));
                        }
                      },
                      onLongPress: () {
                        if (result.isNotEmpty) {
                          speak(
                              '$profileName Floor ${result['floorID']! - 999} ${cur_c?.name}');
                        } else {
                          speak('Scan a Marker');
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
                              '$profileName Floor ${result['floorID']! - 999} ${cur_c?.name}',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20),
                            ),
                    )),
              ),
            ],
          )
        ],
      ),
    );
  }
}
