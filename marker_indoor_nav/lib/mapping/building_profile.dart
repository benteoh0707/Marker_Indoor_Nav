// ignore_for_file: use_key_in_widget_constructors, prefer_const_constructors, library_private_types_in_public_api, avoid_print, use_build_context_synchronously, non_constant_identifier_names

import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:marker_indoor_nav/mapping/map.dart';

class EditProfilePage extends StatefulWidget {
  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _firestore = FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>> fetchProfiles() async {
    QuerySnapshot snapshot = await _firestore.collection('profiles').get();

    return snapshot.docs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .toList();
  }

  void _createProfile(String profileName, String numOfFloors) async {
    int numberOfFloors;

    // Ensure the profileName isn't empty
    if (profileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a profile name.'),
      ));
      return;
    }

    try {
      numberOfFloors = int.parse(numOfFloors);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a valid number for floors.'),
      ));
      return;
    }

    if (!(numberOfFloors > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a valid number for floors.'),
      ));
      return;
    }

    try {
      // Using Firestore
      await _firestore.collection("profiles").doc(profileName).set({
        'profileName': profileName,
        'numberOfFloors': numberOfFloors,
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Profile Created.'),
      ));
    } catch (error) {
      print("Error adding document: $error");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('An error occurred. Please try again.'),
      ));
    }
  }

  createProfile() {
    final TextEditingController profileNameController = TextEditingController();
    final TextEditingController numberOfFloorsController =
        TextEditingController();

    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Create Profile'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: profileNameController,
                  decoration: InputDecoration(labelText: 'Enter Profile Name'),
                ),
                SizedBox(
                  height: 20,
                ),
                TextField(
                  controller: numberOfFloorsController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration:
                      InputDecoration(labelText: 'Enter Number of Floor'),
                ),
                SizedBox(
                  height: 20,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () {
                          setState(() {
                            _createProfile(profileNameController.text.trim(),
                                numberOfFloorsController.text.trim());
                          });
                          Navigator.of(context).pop();
                        },
                        child: Text('Save')),
                  ],
                )
              ],
            ),
          );
        });
  }

  deleteProfile(String profName, int NoFloor) async {
    await _firestore.collection("profiles").doc(profName).delete();
    for (int i = 1; i <= NoFloor; i++) {
      _firestore
          .collection('maps')
          .doc('${profName}_Floor $i')
          .get()
          .then((docSnapshot) async => {
                if (docSnapshot.exists)
                  {
                    await _firestore
                        .collection('maps')
                        .doc('${profName}_Floor $i')
                        .delete()
                  }
              });

      FirebaseStorage.instance
          .ref()
          .child('blueprints')
          .child('${profName}_Floor ${i}_map.png')
          .getDownloadURL()
          .then(
            (url) async => {
              await FirebaseStorage.instance
                  .ref()
                  .child('blueprints')
                  .child('${profName}_Floor ${i}_map.png')
                  .delete()
            },
          )
          .catchError((error) => {print(error)});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Building Profile'), actions: <Widget>[
        IconButton(
          iconSize: 25,
          padding: EdgeInsets.only(right: 25.0),
          icon: Icon(
            Icons.add,
            size: 30,
            color: Colors.white,
          ),
          onPressed: () {
            createProfile();
            setState(() {});
          },
        )
      ]),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchProfiles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            final profiles = snapshot.data;

            return ListView.builder(
              itemCount: profiles?.length ?? 0,
              itemBuilder: (context, index) {
                final profile = profiles?[index];
                return Slidable(
                  startActionPane:
                      ActionPane(motion: StretchMotion(), children: [
                    SlidableAction(
                      backgroundColor: Colors.red,
                      icon: Icons.delete,
                      label: 'Delete',
                      onPressed: (context) async {
                        await deleteProfile(profile?['profileName'],
                            profile?['numberOfFloors']);
                        setState(() {});
                      },
                    ),
                  ]),
                  child: ListTile(
                      title: Text(profile?['profileName'],
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'Number of floors: ${profile?['numberOfFloors']}'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditMapPage(
                              profileName: profile?['profileName'],
                              numberOfFloors: profile?['numberOfFloors'],
                            ),
                          ),
                        );
                      }),
                );
              },
            );
          }
        },
      ),
    );
  }
}
