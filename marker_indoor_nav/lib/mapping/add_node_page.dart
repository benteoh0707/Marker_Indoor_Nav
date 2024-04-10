// ignore_for_file: use_key_in_widget_constructors, no_logic_in_create_state, must_be_immutable, prefer_const_constructors_in_immutables, prefer_const_constructors

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:marker_indoor_nav/mapping/map.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class AddNodePage extends StatefulWidget {
  String profileID;
  Circle circle;
  String location;
  AddNodePage(
      {required this.profileID, required this.circle, required this.location});

  @override
  State<AddNodePage> createState() => _AddNodePageState();
}

class _AddNodePageState extends State<AddNodePage> {
  List<Image> imgFlutter = List<Image>.empty(growable: true);
  late Circle circle = widget.circle;
  late int profileID = int.parse(widget.profileID);
  late int floorID =
      int.parse(widget.location.substring(widget.location.length - 1)) + 999;
  late int markerID = widget.circle.marker_id;
  final GlobalKey _arkey = GlobalKey(debugLabel: 'AR');
  bool isAR = true;

  bool dirExists = false;
  dynamic externalDir = '/storage/emulated/0/Download/Qr_code';

  @override
  void initState() {
    super.initState();
    for (int i in [profileID, floorID, markerID]) {
      cv.Mat img = cv.Mat.empty();
      cv.arucoGenerateImageMarker(
          cv.PredefinedDictionaryType.DICT_ARUCO_ORIGINAL, i, 100, img, 1);

      Uint8List imagebyte = cv.imencode('.png', img);

      Image flutterImage = Image.memory(imagebyte);
      imgFlutter.add(flutterImage);
    }
  }

  Future<void> _captureAndSavePng(String id) async {
    try {
      RenderRepaintBoundary boundary =
          _arkey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      var image = await boundary.toImage(pixelRatio: 3.0);

      //Drawing White Background because Qr Code is Black
      final whitePaint = Paint()..color = Colors.white;
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));
      canvas.drawRect(
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          whitePaint);
      canvas.drawImage(image, Offset.zero, Paint());
      final picture = recorder.endRecording();
      final img = await picture.toImage(image.width, image.height);
      ByteData? byteData = await img.toByteData(format: ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      //Check for duplicate file name to avoid Override
      String fileName = id;
      int i = 1;
      while (await File('$externalDir/$fileName.png').exists()) {
        fileName = '${fileName}_$i';
        i++;
      }

      // Check if Directory Path exists or not
      dirExists = await File(externalDir).exists();
      //if not then create the path
      if (!dirExists) {
        await Directory(externalDir).create(recursive: true);
        dirExists = true;
      }

      final file = await File('$externalDir/$fileName.png').create();

      await file.writeAsBytes(pngBytes);

      if (!mounted) return;
      const snackBar = SnackBar(content: Text('Marker saved to gallery'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } catch (e) {
      if (!mounted) return;
      const snackBar = SnackBar(content: Text('Something went wrong!!!'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }

  @override
  Widget build(BuildContext context) {
    TextEditingController nameController =
        TextEditingController(text: circle.name);
    TextEditingController descriptionController =
        TextEditingController(text: circle.description);

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary, //change your color here
        ),
        title: Text('Marker Information',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 25,
                fontWeight: FontWeight.bold)),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              iconSize: 35,
              icon: Icon(
                size: 35,
                Icons.download_rounded,
              ),
              onPressed: () {
                _captureAndSavePng(nameController.text.isNotEmpty
                    ? nameController.text
                    : circle.id.replaceAll(RegExp(r'[:.]'), '-'));
              },
            ),
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 250,
                  width: 250,
                  child: RepaintBoundary(
                      key: _arkey,
                      child: isAR
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    imgFlutter[0],
                                    SizedBox(
                                      width: 30,
                                    ),
                                    imgFlutter[1],
                                  ],
                                ),
                                SizedBox(
                                  height: 30,
                                ),
                                imgFlutter[2],
                              ],
                            )
                          : QrImageView(
                              data: '${widget.location}_${circle.id}',
                              size: 200,
                              backgroundColor: Colors.white,
                            )),
                ),
                SizedBox(
                  height: 15,
                ),
                SizedBox(
                  height: 50,
                  width: 150,
                  child: ElevatedButton(
                      onPressed: () => setState(() {
                            isAR ? isAR = false : isAR = true;
                          }),
                      child: Text(
                        'Change Marker',
                      )),
                ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                    )),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: const Text('Save'),
                      onPressed: () {
                        if (nameController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Please enter a name.'),
                          ));
                        } else {
                          setState(() {
                            circle.name = nameController.text.trim();
                            circle.description =
                                descriptionController.text.trim();
                            Navigator.pop(context);
                          });
                        }
                      },
                    ),
                  ],
                )
              ],
            )),
      ),
    );
  }
}
