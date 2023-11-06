// ignore_for_file: constant_identifier_names, use_build_context_synchronously, avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';

// Firebase setup and function

class EditMapPage extends StatefulWidget {
  final String profileName;
  final int numberOfFloors;

  const EditMapPage(
      {super.key, required this.profileName, required this.numberOfFloors});

  @override
  // ignore: library_private_types_in_public_api
  _EditMapPageState createState() => _EditMapPageState();
}

class _EditMapPageState extends State<EditMapPage> {
  List<String> floorOptions = [];
  String? selectedFloor;
  Image? uploadedImage;
  bool hasImage = false;

  final GlobalKey imageKey = GlobalKey();

  List<Circle> circles = [];

  static const double MIN_SIZE = 10.0; // Minimum circle size
  static const double MAX_SIZE = 100.0; // Maximum circle size
  static const double SCALE_MULTIPLIER =
      0.05; // Adjust this value to control the scaling effect

  @override
  void initState() {
    super.initState();
    _generateFloorOptions(widget.numberOfFloors);
    _checkAndDownloadImage();
    _loadCirclesFromFirebase();
  }

  Future<void> _saveCirclesToFirebase() async {
    final circlesJson = circles.map((circle) => circle.toJson()).toList();
    final circlesString = jsonEncode(circlesJson);

    final mapId = '${widget.profileName}_$selectedFloor';

    final ref = FirebaseFirestore.instance.collection('maps').doc(mapId);

    await ref.set({'circles': circlesString});
  }

  Future<void> _loadCirclesFromFirebase() async {
    final mapId = '${widget.profileName}_$selectedFloor';
    final ref = FirebaseFirestore.instance.collection('maps').doc(mapId);

    final doc = await ref.get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final circlesString = data['circles'];
      final circlesJson = jsonDecode(circlesString) as List;
      final loadedCircles =
          circlesJson.map((circleJson) => Circle.fromJson(circleJson)).toList();

      setState(() {
        circles = loadedCircles;
      });
    }
  }

  _generateFloorOptions(int floors) {
    floorOptions.clear();

    for (int i = 1; i <= floors; i++) {
      floorOptions.add('Floor $i');
    }
    // Initially select the first floor
    selectedFloor = floorOptions[0];
  }

  Future<void> _uploadImage() async {
    final imagePicker = ImagePicker();
    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final imageName = '${widget.profileName}_${selectedFloor}_map.png';
    final imageFile = File(image.path);
    final ref = FirebaseStorage.instance.ref().child('maps').child(imageName);

    try {
      await ref.putFile(imageFile);
      setState(() {
        hasImage = true;
        uploadedImage = Image.file(imageFile);
      });
    } catch (e) {
      print('Error uploading image: $e');
    }
  }

  Future<void> _checkAndDownloadImage() async {
    final imageName = '${widget.profileName}_${selectedFloor}_map.png';
    final ref = FirebaseStorage.instance.ref().child('maps').child(imageName);

    // Checking if the image exists
    try {
      final result = await ref.getDownloadURL();

      setState(() {
        hasImage = true;
        uploadedImage = Image.network(
            result.toString()); // Using the image from Firebase Storage
      });
    } catch (e) {
      print('Error fetching image: $e');
      setState(() {
        hasImage = false;
      });
    }

    _loadCirclesFromFirebase();
  }

  Future<void> _showCircleInfoDialog(Circle circle) async {
    TextEditingController nameController =
        TextEditingController(text: circle.name);
    TextEditingController descriptionController =
        TextEditingController(text: circle.description);

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap the button to close the dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Circle Information'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Name',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    hintText: 'Description',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                setState(() {
                  circle.name = nameController.text.trim();
                  circle.description = descriptionController.text.trim();
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showCircleOptions(Circle circle) {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.drag_handle),
                title: const Text('Move'),
                onTap: () {
                  Navigator.pop(context);
                  // Set circle to moving state, this will allow user to drag the circle
                  setState(() {
                    for (var c in circles) {
                      c.selected = false;
                    }
                    circle.selected = true;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _showCircleInfoDialog(
                      circle); // Use your existing method to show the prompt
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Delete'),
                onTap: () async {
                  Navigator.pop(context);
                  // Delete circle from the UI
                  setState(() {
                    circles.remove(circle);
                  });
                  // Delete circle from Firebase
                  // await _deleteCircleFromFirebase(circle);
                },
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit ${widget.profileName}')),
      body: GestureDetector(
        onScaleUpdate: (ScaleUpdateDetails details) {
          setState(() {
            // Find which circle is selected
            final selectedCircle = circles.firstWhere(
                (element) => element.selected == true,
                orElse: () => Circle(Offset.zero, 'none'));

            // Update the size of the selected circle using the scale factor
            if (selectedCircle.id != 'none') {
              double scaleChange = 1 + (details.scale - 1) * SCALE_MULTIPLIER;
              double newSize = selectedCircle.size * scaleChange;

              // Apply constraints
              if (newSize < MIN_SIZE) {
                newSize = MIN_SIZE;
              } else if (newSize > MAX_SIZE) {
                newSize = MAX_SIZE;
              }

              selectedCircle.size = newSize;
            }
          });
        },
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(widget.profileName,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    // Wrap the dropdown and the button in a Row widget
                    children: [
                      Expanded(
                        // Make the dropdown take up all available horizontal space
                        child: DropdownButton<String>(
                          value: selectedFloor,
                          items: floorOptions.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              selectedFloor = newValue;
                            });
                            _checkAndDownloadImage();
                          },
                        ),
                      ),
                      const SizedBox(
                          width:
                              10), // A little spacing between the dropdown and the button
                      ElevatedButton(
                        onPressed: _uploadImage,
                        child: const Text('Upload Image'),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: hasImage && uploadedImage != null
                      ? Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.red, width: 2),
                          ),
                          key: imageKey,
                          width: MediaQuery.of(context)
                              .size
                              .width, // Use the full width
                          height: MediaQuery.of(context).size.height /
                              2, // Use half the available height
                          child: Image(
                            image: uploadedImage!.image,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          ),
                        )
                      : Container(
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.height / 2,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.red, width: 2),
                          ),
                          child: const Center(
                            child: Text(
                              "Please upload a map.",
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: ElevatedButton(
                onPressed: () {
                  final RenderBox renderBox =
                      imageKey.currentContext!.findRenderObject() as RenderBox;
                  final position = renderBox.localToGlobal(Offset.zero);

                  setState(() {
                    circles.add(
                        Circle(position, DateTime.now().toIso8601String()));
                  });
                },
                child: const Text('Add Label'),
              ),
            ),
            Positioned(
              right: 10, // 10 pixels from the right
              bottom: 10, // 10 pixels from the bottom
              child: ElevatedButton(
                onPressed: () async {
                  await _saveCirclesToFirebase();
                  Navigator.pop(context);
                },
                child: const Text('Save & Exit'),
              ),
            ),
            ...circles.map((circle) {
              return Positioned(
                left: circle.position.dx,
                top: circle.position.dy,
                child: GestureDetector(
                  onTap: () async {
                    _showCircleOptions(circle);
                  },
                  onPanUpdate: (details) {
                    if (circle.selected == true) {
                      setState(() {
                        circle.position = Offset(
                          circle.position.dx + details.delta.dx,
                          circle.position.dy + details.delta.dy,
                        );
                      });
                    }
                  },
                  child: Container(
                    width: circle.size,
                    height: circle.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          circle.selected == true ? Colors.green : Colors.blue,
                    ),
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

class Circle {
  Offset position;
  final String id;
  bool? selected;
  double size; // New property for size
  String? name;
  String? description;
  DateTime? lastTriggered;

  Circle(this.position, this.id, {this.size = 30.0, this.selected = false});

  Map<String, dynamic> toJson() {
    return {
      'position': {
        'dx': position.dx,
        'dy': position.dy,
      },
      'id': id,
      'selected': selected,
      'size': size,
      'name': name,
      'description': description,
    };
  }

  static Circle fromJson(Map<String, dynamic> json) {
    return Circle(
      Offset(json['position']['dx'], json['position']['dy']),
      json['id'],
      size: json['size'],
      // Add other fields as needed
    )
      ..name = json['name']
      ..description = json['description']
      ..selected = json['selected'];
  }
}
