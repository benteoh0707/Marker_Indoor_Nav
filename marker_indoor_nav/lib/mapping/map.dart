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

import 'package:marker_indoor_nav/mapping/edit_connection_page.dart';

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
  final GlobalKey paddingKey = GlobalKey();
  final GlobalKey ancestor = GlobalKey();

  bool dirExists = false;
  dynamic externalDir = '/storage/emulated/0/Download/Qr_code';

  List<Circle> circles = [];
  List<String> circles_id = [];

  static const double MIN_SIZE = 16.0; // Minimum circle size
  static const double MAX_SIZE = 100.0; // Maximum circle size
  static const double SCALE_MULTIPLIER =
      0.05; // Adjust this value to control the scaling effect

  @override
  void initState() {
    super.initState();
    _generateFloorOptions(widget.numberOfFloors);
    _checkAndDownloadImage();
  }

  Future<void> _saveCirclesToFirebase() async {
    final circlesJson = circles.map((circle) => circle.toJson()).toList();
    final circlesString = jsonEncode(circlesJson);

    final mapId = '${widget.profileName} $selectedFloor';

    final ref = FirebaseFirestore.instance.collection('maps').doc(mapId);

    await ref.set({'circles': circlesString});
  }

  Future<void> _loadCirclesFromFirebase() async {
    final mapId = '${widget.profileName} $selectedFloor';
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

    final imageName = '${widget.profileName} ${selectedFloor}_map.png';
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
    final imageName = '${widget.profileName} ${selectedFloor}_map.png';
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

    await _loadCirclesFromFirebase();
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
                              circle: circle,
                              location:
                                  '${widget.profileName} $selectedFloor'))); // Use your existing method to show the prompt
                },
              ),
              ListTile(
                leading: const Icon(Icons.social_distance),
                title: const Text('Marker Connection'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => EditConnectPage(
                          start: circle,
                          circles: circles,
                        ),
                      )) as bool;

                  setState(() {
                    if (!result) {
                      showOption = result;
                      circles_id.add(circle.id);
                    }
                  }); // Use your existing method to show the prompt
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
    TextEditingController distanceController = TextEditingController(
        text: start.connected_nodes[end.id]['distance'].toString());
    bool validate = false;
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
                showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return StatefulBuilder(builder: (context, setState) {
                        return AlertDialog(
                          title: Text(
                            'Distance',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: distanceController,
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                decoration: InputDecoration(
                                    labelText: 'Enter Distance',
                                    errorText: validate
                                        // ignore: dead_code
                                        ? "Value Can't Be Empty"
                                        : null),
                              ),
                              SizedBox(
                                height: 10,
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                      onPressed: () {
                                        setState(() {
                                          if (distanceController.text.isEmpty) {
                                            validate =
                                                distanceController.text.isEmpty;
                                          } else {
                                            start.connected_nodes[end.id]
                                                    ['distance'] =
                                                num.parse(
                                                    distanceController.text);
                                            end.connected_nodes[start.id]
                                                    ['distance'] =
                                                num.parse(
                                                    distanceController.text);
                                            Navigator.of(context).pop();
                                          }
                                        });
                                      },
                                      child: Text('Save')),
                                ],
                              )
                            ],
                          ),
                        );
                      });
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
      appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () async {
              await _saveCirclesToFirebase();
              Navigator.pop(context);
            },
          ),
          title: Text('Edit ${widget.profileName}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 25,
                  fontWeight: FontWeight.bold)),
          iconTheme: IconThemeData(
            color:
                Theme.of(context).colorScheme.primary, //change your color here
          ),
          actions: <Widget>[
            IconButton(
              iconSize: 35,
              padding: EdgeInsets.only(right: 25.0),
              icon: Icon(
                Icons.add_photo_alternate_outlined,
                size: 35,
              ),
              onPressed: showOption ? _uploadImage : null,
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
          key: ancestor,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  key: paddingKey,
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
                          onChanged: showOption
                              ? (newValue) async {
                                  setState(() {
                                    selectedFloor = newValue;
                                  });
                                  await _checkAndDownloadImage();
                                }
                              : null,
                        ),
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
                                border: Border(
                                    top: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2),
                                    bottom: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2)),
                              ),
                              key: imageKey,
                              width: MediaQuery.of(context)
                                  .size
                                  .width, // Use the full width
                              height: MediaQuery.of(context).size.height /
                                  1.5, // Use half the available height
                              child: Image(
                                image: uploadedImage!.image,
                                fit: BoxFit.fill, //BoxFit.contain?
                                alignment: Alignment.center,
                              ),
                            )
                          : Container(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height / 1.5,
                              decoration: BoxDecoration(
                                border: Border(
                                    top: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2),
                                    bottom: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2)),
                              ),
                              child: Center(
                                child: Text(
                                  "Please upload a map.",
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
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
                          if (showOption) {
                            Offset position = Offset.zero;
                            // final RenderBox renderBox = paddingKey.currentContext!.findRenderObject() as RenderBox;
                            bool touched = false;
                            await showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                insetPadding: EdgeInsets.all(0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                        decoration: BoxDecoration(
                                            color: Colors.transparent),
                                        child: Text(
                                          "Select a location to add a node",
                                          style: TextStyle(
                                              backgroundColor:
                                                  Colors.transparent,
                                              fontSize: 25,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white),
                                        )),
                                    GestureDetector(
                                      onTapDown: (details) {
                                        position = Offset(
                                            details.localPosition.dx - 15,
                                            details.localPosition.dy - 15);
                                        Navigator.pop(context);
                                        touched = true;
                                      },
                                      child: SizedBox(
                                        width:
                                            MediaQuery.of(context).size.width,
                                        height:
                                            MediaQuery.of(context).size.height /
                                                1.5,
                                        child: Image(
                                          image: uploadedImage!.image,
                                          fit: BoxFit.fill, //BoxFit.contain?
                                          alignment: Alignment.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            if (touched) {
                              Circle circle = Circle(
                                  position, DateTime.now().toIso8601String());
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                      builder: (BuildContext context) =>
                                          AddNodePage(
                                              circle: circle,
                                              location:
                                                  '${widget.profileName} $selectedFloor')));
                              if (circle.name!.isNotEmpty) {
                                setState(() {
                                  circles.add(circle);
                                });
                              }
                            }
                          } else {
                            showOption = true;
                            setState(() {
                              for (var c in circles) {
                                c.selected = false;
                              }
                              circles_id = [];
                            });
                          }
                        },
                        child: showOption ? Text('Add Node') : Text('Cancel'),
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
                                      .connected_nodes[circles_id[i + 1]] = {
                                    'distance': 0,
                                    'direction': '-'
                                  };
                                }
                                if (i != 0) {
                                  current_circle
                                      .connected_nodes[circles_id[i - 1]] = {
                                    'distance': 0,
                                    'direction': '-'
                                  };
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
                  painter: drawEdges(start, end, imageKey, ancestor),
                );
              }

              return Divider(
                color: Colors.transparent,
                thickness: 0,
              );
            }),
            ...circles.map((start) {
              for (var dest_id in start.connected_nodes.keys) {
                Circle end =
                    circles.firstWhere((element) => element.id == dest_id);
                final RenderBox renderBox =
                    imageKey.currentContext!.findRenderObject() as RenderBox;
                final start_position = renderBox.localToGlobal(start.position,
                    ancestor: ancestor.currentContext!.findRenderObject());
                final end_position = renderBox.localToGlobal(end.position,
                    ancestor: ancestor.currentContext!.findRenderObject());

                Offset start_mid = Offset(start_position.dx + start.size / 2,
                    start_position.dy + start.size / 2);
                Offset end_mid = Offset(end_position.dx + end.size / 2,
                    end_position.dy + end.size / 2);
                double box_width = (start_mid.dx - end_mid.dx).abs();
                double box_height = (start_mid.dy - end_mid.dy).abs();

                return Positioned(
                  left: (box_width / 2) + min(start_mid.dx, end_mid.dx) - 8,
                  top: (box_height / 2) + min(start_mid.dy, end_mid.dy) - 8,
                  child: GestureDetector(
                    onTap: () {
                      showEdgeOptions(start, end);
                    },
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 3),
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              }

              return Divider(
                color: Colors.transparent,
                thickness: 0,
              );
            }),
            ...circles.map((circle) {
              final RenderBox renderBox =
                  imageKey.currentContext!.findRenderObject() as RenderBox;
              final circle_position = renderBox.localToGlobal(circle.position,
                  ancestor: ancestor.currentContext!.findRenderObject());
              return Positioned(
                left: circle_position.dx,
                top: circle_position.dy,
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
                  onLongPress: () {
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
                  onPanUpdate: (details) {
                    if (circle.selected == true) {
                      double dx = 0, dy = 0;
                      if ((circle.position.dy + details.delta.dy) < 0.0) {
                        dy = 0.0;
                      } else if ((circle.position.dy + details.delta.dy) >
                          (imageKey.currentContext!.size!.height -
                              circle.size)) {
                        dy = imageKey.currentContext!.size!.height +
                            -circle.size;
                      } else {
                        dy = circle.position.dy + details.delta.dy;
                      }

                      if ((circle.position.dx + details.delta.dx) >
                          (imageKey.currentContext!.size!.width -
                              circle.size)) {
                        dx = imageKey.currentContext!.size!.width - circle.size;
                      } else {
                        dx = circle.position.dx + details.delta.dx;
                      }

                      setState(() {
                        circle.position = Offset(dx, dy);
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
  Offset position; //refer to local position of image key
  final String id;
  bool? selected;
  double size; // New property for size
  String? name;
  String? description;
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
  GlobalKey key = GlobalKey(), ancestor = GlobalKey();

  drawEdges(this.start, this.end, this.key, this.ancestor);

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill
      ..strokeWidth = 5;

    final RenderBox renderBox =
        key.currentContext!.findRenderObject() as RenderBox;
    final start_position = renderBox.localToGlobal(start.position,
        ancestor: ancestor.currentContext!.findRenderObject());
    final end_position = renderBox.localToGlobal(end.position,
        ancestor: ancestor.currentContext!.findRenderObject());

    canvas.drawLine(
        Offset(start_position.dx + start.size / 2,
            start_position.dy + start.size / 2),
        Offset(end_position.dx + end.size / 2, end_position.dy + end.size / 2),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
    //throw UnimplementedError();
  }
}
