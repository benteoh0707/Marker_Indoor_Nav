// ignore_for_file: library_private_types_in_public_api, prefer_const_constructors, non_constant_identifier_names, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dv;
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dijkstra/dijkstra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_aruco_detector/aruco_detector.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:marker_indoor_nav/admin_account/auth.dart';
import 'package:marker_indoor_nav/admin_account/login_page.dart';
import 'package:marker_indoor_nav/localization/layer.dart';
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
  int _camFrameRotation = 0;
  double _camFrameToScreenScale = 0;
  int _lastRun = 0;
  bool _detectionInProgress = false;
  List<List<double>> _arucos = List.empty();

  FlutterTts flutterTts = FlutterTts();
  Map<String, dynamic> ar_floorGraph = {}, qr_floorGraph = {};
  List<Circle> circles = [];
  Map<String, int?> result = {}; //markerID, profileID, floorID
  List ar_path = [], qr_path = [];
  String? profileName;
  int? dest_marker_id;
  String? dest_name;
  int nextDest = 1;
  Circle? cur_c;
  StreamSubscription<CompassEvent>? _compassSubscription;

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

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    var idx =
        cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (idx < 0) {
      dv.log("No Back camera found - weird");
      return;
    }

    var desc = cameras[idx];
    _camFrameRotation = Platform.isAndroid ? desc.sensorOrientation : 0;
    _camController = CameraController(
      desc,
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
    if (_detectionInProgress ||
        !mounted ||
        DateTime.now().millisecondsSinceEpoch - _lastRun < 30) {
      return;
    }

    // calc the scale factor to convert from camera frame coords to screen coords.
    // NOTE!!!! We assume camera frame takes the entire screen width, if that's not the case
    // (like if camera is landscape or the camera frame is limited to some area) then you will
    // have to find the correct scale factor somehow else
    if (_camFrameToScreenScale == 0) {
      var w = (_camFrameRotation == 0 || _camFrameRotation == 180)
          ? image.width
          : image.height;
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

    if (res.length == 3) {
      detectionHandling(res);
    }

    // // Check that the number of coords we got divides by 8 exactly, each aruco has 8 coords (4 corners x/y)
    if ((res[0]['corners'].length / 8) != (res[0]['corners'].length ~/ 8)) {
      dv.log(
          'Got invalid response from ArucoDetector, number of coords is ${res[0]['corners'].length} and does not represent complete arucos with 4 corners');
      return;
    }

    // //convert arucos from camera frame coords to screen coords

    List<List<double>> arucos = [];
    for (var r in res) {
      List<double> corners = List<double>.from(r['corners']);

      final aruco = corners
          .map((double x) => x * _camFrameToScreenScale)
          .toList(growable: false);

      arucos.add(aruco);
    }

    setState(() {
      _arucos = arucos;
    });
  }

  Future<void> detectionHandling(List detectResult) async {
    int? markerID, profileID, floorID;
    Offset? start, end;

    for (var r in detectResult) {
      int id = r['markerId'];
      if (id < 500) {
        //marker
        markerID = id;
      } else if (id >= 500 && id < 1000) {
        //profile
        profileID = id;
        double x = r['headPoint']['x'] * _camFrameToScreenScale;
        double y = r['headPoint']['y'] * _camFrameToScreenScale;
        start = Offset(x, y);
      } else {
        //floor
        floorID = id;
        double x = r['corners'][2] * _camFrameToScreenScale;
        double y = r['corners'][3] * _camFrameToScreenScale;
        end = Offset(x, y);
      }
    }

    if (markerID == null || profileID == null || floorID == null) {
      return;
    }

    if (start != null && end != null) {
      double area = (end - start).distanceSquared;
      num screen = pow(MediaQuery.of(context).size.width, 2);
      double percent = (area / screen) * 100;
      //print('area: $area ;percentage : $percent');

      if (percent < 0.6) {
        return;
      }
    } else {
      return;
    }

    startNavigation(markerID, profileID, floorID);
  }

  Future<void> startNavigation(int markerID, int profileID, int floorID) async {
    if (result.isEmpty && ar_path.isEmpty && qr_path.isEmpty) {
      //first time detected

      speak('Marker Detected');

      await _camController.stopImageStream();
      _camController.pausePreview();

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

        if (ar_path.isNotEmpty && qr_path.isNotEmpty) {
          //todo: add direction
          await getDirection(
              cur_c?.connected_nodes[qr_path[nextDest]]['direction']);
        }
      } else {
        Navigator.of(context).pop();
        speak('Unknown Marker');
      }

      await _camController.resumePreview();
      await _camController
          .startImageStream((image) => _processCameraImage(image));
    } else if (ar_path.isNotEmpty &&
        qr_path.isNotEmpty &&
        markerID != result['markerID']) {
      _compassSubscription?.cancel();
      await flutterTts.stop();

      if (result['profileID'] == profileID && result['floorID'] == floorID) {
        //detected another marker

        if (markerID == dest_marker_id) {
          //reach destination
          await _camController.stopImageStream();
          _camController.pausePreview();
          speak(
              'You have reach your destination,$profileName Floor ${result['floorID']! - 999} $dest_name');

          Timer? timer = Timer(Duration(seconds: 7), () {
            Navigator.of(context, rootNavigator: true).pop();
          });

          await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Destination Arrived'),
                actions: [
                  TextButton(
                    child: Text("Continue"),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
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
          setState(() {
            cur_c = circles.firstWhere(
                (circle) => circle.marker_id == int.parse(ar_path[nextDest]));
            result['markerID'] = markerID;
            nextDest++;
          });
          await speak(
              'Reach $profileName Floor ${result['floorID']! - 999} ${cur_c?.name}');
        } else if (ar_floorGraph.keys.contains(markerID.toString())) {
          //reroute
          speak('Reach the wrong next point, Rerouting');

          setState(() {
            nextDest = 1;
            ar_path = Dijkstra.findPathFromGraph(
                ar_floorGraph, markerID.toString(), dest_marker_id.toString());
            cur_c =
                circles.firstWhere((circle) => circle.marker_id == markerID);
            result['markerID'] = markerID;
          });

          speak(
              'Reroute, Currently at $profileName Floor ${result['floorID']! - 999} ${cur_c?.name}');
        }

        if (ar_path.isNotEmpty && qr_path.isNotEmpty) {
          //todo: add direction
          await getDirection(
              cur_c?.connected_nodes[qr_path[nextDest]]['direction']);
        }
      } else {}
    }
  }

  Future<void> getDirection(facing_target) async {
    bool? canVibrate = await Vibration.hasVibrator();
    String speech = '';
    _compassSubscription = FlutterCompass.events?.listen((event) async {
      double gap = facing_target - event.heading;
      //print('gap: $gap, face: $facing_target , head: ${event.heading}');
      if (gap > 180 || gap < -180) {
        if (event.heading!.isNegative) {
          gap = gap - 360;
        } else {
          gap = 360 + gap;
        }
      }

      if (gap.truncate() >= -40 && gap.truncate() <= 40) {
        if (speech != 'Move straight') {
          speech = 'Move straight';
          await speak('Move straight');
        }
      } else if (gap.truncate() > 0 && gap.truncate() < 180) {
        if (canVibrate == true) {
          await Vibration.vibrate(duration: 100);
        }
        if (speech != 'Turn right') {
          speech = 'Turn right';
          await speak('Turn right');
        }
      } else {
        if (canVibrate == true) {
          await Vibration.vibrate(duration: 100);
        }
        if (speech != 'Turn left') {
          speech = 'Turn left';
          await speak('Turn left');
        }
      }
    });
  }

  Future<bool> showDestination(c_marker_id, c_id) async {
    await speak('choose your destination');
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
                        speak(circles[index].name);
                        setState(() {
                          nextDest = 1;
                          ar_path = Dijkstra.findPathFromGraph(ar_floorGraph,
                              c_marker_id, circles[index].marker_id.toString());
                          qr_path = Dijkstra.findPathFromGraph(
                              qr_floorGraph, c_id, circles[index].id);
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
            ));

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
        return true;
      }
    }

    return false;
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
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => Auth().currentUser == null
                            ? LoginPage()
                            : EditProfilePage()));

                setState(() {});
              },
              icon: Icon(
                Icons.login_outlined,
                color: Colors.white,
                size: 30,
              )),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height / 1.2,
            child: Expanded(
              child: Stack(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height,
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
                                  _compassSubscription?.cancel();
                                  await flutterTts.stop();
                                  speak('Navigation stop');
                                  setState(() {
                                    result = {};
                                    ar_path = [];
                                    qr_path = [];
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
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  padding: EdgeInsets.all(8.0),
                  child: GestureDetector(
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
                                fontSize: 15),
                          ),
                  )),
            ],
          )
        ],
      ),
    );
  }
}
