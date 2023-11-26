// ignore_for_file: use_key_in_widget_constructors, no_logic_in_create_state, must_be_immutable, prefer_const_constructors_in_immutables, prefer_const_constructors

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:marker_indoor_nav/mapping/map.dart';
import 'package:qr_flutter/qr_flutter.dart';

class AddNodePage extends StatefulWidget {
  Circle circle;
  AddNodePage(this.circle);

  @override
  State<AddNodePage> createState() => _AddNodePageState();
}

class _AddNodePageState extends State<AddNodePage> {
  late Circle circle = widget.circle;
  final GlobalKey _qrkey = GlobalKey();

  bool dirExists = false;
  dynamic externalDir = '/storage/emulated/0/Download/Qr_code';

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
          IconButton(
            iconSize: 35,
            padding: EdgeInsets.only(right: 25.0),
            icon: Icon(
              size: 35,
              Icons.download_rounded,
            ),
            onPressed: () {
              _captureAndSavePng(nameController.text.isNotEmpty
                  ? nameController.text
                  : circle.id.replaceAll(RegExp(r'[:.]'), '-'));
            },
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RepaintBoundary(
                    key: _qrkey,
                    child: QrImageView(
                      data: circle.id,
                      size: 200,
                      backgroundColor: Colors.white,
                    )),
                SizedBox(
                  height: 30,
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
                const SizedBox(height: 10),
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

  Future<void> _captureAndSavePng(String id) async {
    try {
      RenderRepaintBoundary boundary =
          _qrkey.currentContext!.findRenderObject() as RenderRepaintBoundary;
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
      const snackBar = SnackBar(content: Text('QR code saved to gallery'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } catch (e) {
      if (!mounted) return;
      const snackBar = SnackBar(content: Text('Something went wrong!!!'));
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }
}
