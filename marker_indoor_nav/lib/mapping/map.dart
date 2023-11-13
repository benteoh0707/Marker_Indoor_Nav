// ignore_for_file: constant_identifier_names, use_build_context_synchronously, avoid_print, prefer_const_constructors, non_constant_identifier_names, camel_case_types

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:marker_indoor_nav/mapping/add_node_page.dart';
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
  bool showOption = true;

  final GlobalKey imageKey = GlobalKey();

  bool dirExists = false;
  dynamic externalDir = '/storage/emulated/0/Download/Qr_code';

  List<Circle> circles = [];
  List<String> circles_id = [];

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
    final doc =
        await FirebaseFirestore.instance.collection('maps').doc(mapId).get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final circlesString = data['circles'];
      final circlesJson = jsonDecode(circlesString) as List;
      final loadedCircles =
          circlesJson.map((circleJson) => Circle.fromJson(circleJson)).toList();
      setState(() {
        circles = loadedCircles;
      });
    } else {
      setState(() {
        circles = [];
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
    final ref =
        FirebaseStorage.instance.ref().child('blueprints').child(imageName);

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
    final ref =
        FirebaseStorage.instance.ref().child('blueprints').child(imageName);
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

  void _showCircleOptions(Circle circle) {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.drag_handle),
                title:
                    circle.selected == false ? Text('Move') : Text('Unmoved'),
                onTap: () {
                  Navigator.pop(context);
                  // Set circle to moving state, this will allow user to drag the circle
                  setState(() {
                    if (circle.selected == false) {
                      for (var c in circles) {
                        c.selected = false;
                      }
                      circle.selected = true;
                    } else {
                      circle.selected = false;
                    }
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (BuildContext context) => AddNodePage(
                              circle))); // Use your existing method to show the prompt
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Delete'),
                onTap: () async {
                  Navigator.pop(context);
                  // Delete circle from the UI
                  for (var c in circle.connected_nodes.keys) {
                    Circle connected_c =
                        circles.firstWhere((element) => element.id == c);
                    connected_c.connected_nodes.remove(circle.id);
                  }
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

  showEdgeOptions(Circle start, Circle end) {
    TextEditingController distanceController =
        TextEditingController(text: start.connected_nodes[end.id].toString());

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.social_distance),
              title: Text('Distance'),
              onTap: () {
                Navigator.pop(context);
                // Set circle to moving state, this will allow user to drag the circle
                showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text('Distance'),
                        content: TextField(
                          controller: distanceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration:
                              InputDecoration(hintText: 'Enter Distance'),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () {
                                setState(() {
                                  start.connected_nodes[end.id] =
                                      num.parse(distanceController.text);
                                  end.connected_nodes[start.id] =
                                      num.parse(distanceController.text);
                                });
                                Navigator.of(context).pop();
                              },
                              child: Text('Save'))
                        ],
                      );
                    });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(context);
                setState(() {
                  start.connected_nodes.remove(end.id);
                  end.connected_nodes.remove(start.id);
                });
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar:
          AppBar(title: Text('Edit ${widget.profileName}'), actions: <Widget>[
        IconButton(
          iconSize: 25,
          padding: EdgeInsets.only(right: 25.0),
          icon: Icon(
            Icons.save,
            size: 30,
            color: Colors.white,
          ),
          onPressed: () async {
            await _saveCirclesToFirebase();
            Navigator.pop(context);
          },
        )
      ]),
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
                  child: Row(
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
                  child: Stack(
                    children: [
                      hasImage && uploadedImage != null
                          ? Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.red, width: 2),
                              ),
                              key: imageKey,
                              width: MediaQuery.of(context)
                                  .size
                                  .width, // Use the full width
                              height: MediaQuery.of(context).size.height /
                                  1.5, // Use half the available height
                              child: Image(
                                image: uploadedImage!.image,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                              ),
                            )
                          : Container(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height / 1.5,
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
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final RenderBox renderBox = imageKey.currentContext!
                              .findRenderObject() as RenderBox;
                          final position = renderBox.localToGlobal(Offset.zero);
                          Circle circle = Circle(
                              position, DateTime.now().toIso8601String());
                          await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (BuildContext context) =>
                                      AddNodePage(circle)));
                          setState(() {
                            circles.add(circle);
                          });
                        },
                        child: const Text('Add Node'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            for (var c in circles) {
                              c.selected = false;
                            }
                            if (showOption) {
                              showOption = false;
                            } else {
                              showOption = true;
                              for (var i = 0; i < circles_id.length; i++) {
                                final current_circle = circles.firstWhere(
                                    (element) => element.id == circles_id[i]);
                                if (i + 1 != circles_id.length) {
                                  current_circle
                                      .connected_nodes[circles_id[i + 1]] = 0;
                                }
                                if (i != 0) {
                                  current_circle
                                      .connected_nodes[circles_id[i - 1]] = 0;
                                }
                              }
                              circles_id = [];
                            }
                          });
                        },
                        child:
                            showOption ? Text('Connect Nodes') : Text('Save'),
                      ),
                    ],
                  ),
                )
              ],
            ),
            ...circles.map((start) {
              for (var dest_id in start.connected_nodes.keys) {
                Circle end =
                    circles.firstWhere((element) => element.id == dest_id);

                return CustomPaint(
                  painter: drawEdges(start, end),
                );
              }

              return Divider();
            }),
            ...circles.map((start) {
              for (var dest_id in start.connected_nodes.keys) {
                Circle end =
                    circles.firstWhere((element) => element.id == dest_id);
                double box_width = (start.position.dx - end.position.dx).abs();
                double box_height = (start.position.dy - end.position.dy).abs();
                double edge_node_radius = 15.0;
                return Positioned(
                  left: (box_width / 2) +
                      min(start.position.dx, end.position.dx) +
                      edge_node_radius / 2,
                  top: (box_height / 2) +
                      min(start.position.dy, end.position.dy) +
                      edge_node_radius / 2,
                  child: GestureDetector(
                    onTap: () {
                      showEdgeOptions(start, end);
                    },
                    child: Container(
                      width: edge_node_radius,
                      height: edge_node_radius,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                );
              }

              return Divider();
            }),
            ...circles.map((circle) {
              return Positioned(
                left: circle.position.dx,
                top: circle.position.dy,
                child: GestureDetector(
                  onTap: () async {
                    if (showOption) {
                      _showCircleOptions(circle);
                    } else {
                      setState(() {
                        if (circle.selected == false) {
                          circles_id.add(circle.id);
                          circle.selected = true;
                        } else {
                          circles_id.remove(circle.id);
                          circle.selected = false;
                        }
                      });
                    }
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
                      color: circle.selected == true && showOption
                          ? Colors.green
                          : circle.selected == true && !showOption
                              ? Colors.orange
                              : Colors.blue,
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
  Map<String, dynamic> connected_nodes = {};

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
      'connected_nodes': connected_nodes,
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
      ..selected = json['selected']
      ..connected_nodes = json['connected_nodes'];
  }
}

class drawEdges extends CustomPainter {
  Circle start, end;

  drawEdges(this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill
      ..strokeWidth = 5;

    canvas.drawLine(
        Offset(start.position.dx + start.size / 2,
            start.position.dy + start.size / 2),
        Offset(end.position.dx + end.size / 2, end.position.dy + end.size / 2),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
    //throw UnimplementedError();
  }
}
