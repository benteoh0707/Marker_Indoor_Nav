// ignore_for_file: use_key_in_widget_constructors, prefer_const_constructors, library_private_types_in_public_api, avoid_print, use_build_context_synchronously, non_constant_identifier_names, iterable_contains_unrelated_type, unrelated_type_equality_checks

import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:marker_indoor_nav/admin_account/auth.dart';
import 'package:marker_indoor_nav/admin_account/login_page.dart';
import 'package:marker_indoor_nav/mapping/map.dart';

class EditProfilePage extends StatefulWidget {
  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _firestore = FirebaseFirestore.instance;
  final GlobalKey _alertKey = GlobalKey();
  int num_profile = 0;
  List profileManager = [];

  Future<List<Map<String, dynamic>>> fetchProfiles() async {
    QuerySnapshot snapshot = await _firestore.collection('profiles').get();
    final Manager_doc = await _firestore
        .collection('profileManager')
        .doc('profileManager')
        .get();

    profileManager = Manager_doc.data()?['deleted_id'];

    return snapshot.docs.map((doc) {
      final doc_data = doc.data() as Map<String, dynamic>;
      doc_data['id'] = doc.id;
      return doc_data;
    }).toList();
  }

  Future<bool> _createProfile(
      String profileName, String numOfFloors, BuildContext context) async {
    int numberOfFloors;

    // Ensure the profileName isn't empty
    if (profileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a profile name.'),
      ));
      return false;
    }

    if (numOfFloors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter the number of floors.'),
      ));
      return false;
    }
    bool profileExisted = false;

    await _firestore
        .collection("profiles")
        .where("profileName", isEqualTo: profileName)
        .get()
        .then(
      (querySnapshot) {
        if (querySnapshot.docs.isNotEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Profile existed.')));
          profileExisted = true;
        }
      },
      onError: (e) => print("Error completing: $e"),
    );

    if (profileExisted) return false;

    try {
      numberOfFloors = int.parse(numOfFloors);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a valid number for floors.'),
      ));
      return false;
    }

    if (!(numberOfFloors > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter a valid number for floors.'),
      ));
      return false;
    }

    if (!(numberOfFloors <= 24)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please enter less than 30 number for floors.'),
      ));
      return false;
    }

    try {
      // Using Firestore
      int id = num_profile + 500;
      if (profileManager.isNotEmpty) {
        id = profileManager.removeLast() as int;
        await _firestore
            .collection('profileManager')
            .doc('profileManager')
            .set({'deleted_id': profileManager});
      }
      await _firestore.collection("profiles").doc(id.toString()).set({
        'profileName': profileName,
        'numberOfFloors': numberOfFloors,
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Profile Created.'),
      ));
      return true;
    } catch (error) {
      print("Error adding document: $error");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('An error occurred. Please try again.'),
      ));
      return false;
    }
  }

  createProfile() {
    final TextEditingController profileNameController = TextEditingController();
    final TextEditingController numberOfFloorsController =
        TextEditingController();

    showDialog(
        context: context,
        builder: (BuildContext context) {
          return ScaffoldMessenger(
            child: Builder(builder: (context) {
              return Scaffold(
                backgroundColor: Colors.transparent,
                body: AlertDialog(
                  title: Text(
                    'Create Profile',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: profileNameController,
                        decoration:
                            InputDecoration(labelText: 'Enter Profile Name'),
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
                        height: 10,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('Cancel')),
                          TextButton(
                              onPressed: () async {
                                if (await _createProfile(
                                    profileNameController.text.trim(),
                                    numberOfFloorsController.text.trim(),
                                    context)) {
                                  Navigator.of(context).pop();
                                }
                                setState(() {});
                              },
                              child: Text('Save')),
                        ],
                      )
                    ],
                  ),
                ),
              );
            }),
          );
        });
  }

  deleteProfile(String id, String profName, int NoFloor) async {
    profileManager.add(int.parse(id));
    await _firestore
        .collection('profileManager')
        .doc('profileManager')
        .set({'deleted_id': profileManager});
    await _firestore.collection("profiles").doc(id).delete();

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

  editProfile(String id, String profName) {
    final TextEditingController profileNameController =
        TextEditingController(text: profName);
    bool exit = false;

    showDialog(
        context: context,
        builder: (BuildContext context) {
          return ScaffoldMessenger(
            child: Builder(builder: (context) {
              return Scaffold(
                backgroundColor: Colors.transparent,
                body: AlertDialog(
                  title: Text(
                    'Edit Profile',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: profileNameController,
                        decoration:
                            InputDecoration(labelText: 'Enter Profile Name'),
                      ),
                      SizedBox(
                        height: 10,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('Cancel')),
                          TextButton(
                              onPressed: () async {
                                if (profName == profileNameController.text) {
                                  exit = true;
                                } else if (profileNameController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Please enter a profile name.')));
                                } else {
                                  await _firestore
                                      .collection("profiles")
                                      .where("profileName",
                                          isEqualTo: profileNameController.text)
                                      .get()
                                      .then(
                                    (querySnapshot) async {
                                      if (querySnapshot.docs.isNotEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    'Profile name existed.')));
                                      } else {
                                        await _firestore
                                            .collection('profiles')
                                            .doc(id)
                                            .update({
                                          "profileName":
                                              profileNameController.text
                                        });
                                        exit = true;
                                      }
                                    },
                                    onError: (e) =>
                                        print("Error completing: $e"),
                                  );
                                }

                                setState(() {});
                                if (exit) Navigator.of(context).pop();
                              },
                              child: Text('Save')),
                        ],
                      )
                    ],
                  ),
                ),
              );
            }),
          );
        });
  }

  PopupMenuItem _buildPopupMenuItem(String title, IconData iconData) {
    return PopupMenuItem(
      value: title,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(
            iconData,
            color: Colors.black,
          ),
          Text(title),
        ],
      ),
    );
  }

  _onMenuItemSelected(String value) async {
    setState(() {});

    if (value == 'Message') {
      await showMsg();
    } else if (value == 'Sign Out') {
      Auth().signOut();
      await Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (context) => LoginPage()));
    } else {}
  }

  showMsg() async {
    QuerySnapshot snapshot = await _firestore.collection('regAcc').get();
    List checkAccID = [], regAcc = [];

    List acc_list = snapshot.docs.map((doc) {
      final doc_data = doc.data() as Map<String, dynamic>;
      doc_data['id'] = doc.id;
      doc_data['selected'] = false;
      return doc_data;
    }).toList();

    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              key: _alertKey,
              scrollable: true,
              title: Text('Messages'),
              content: Column(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height / 2,
                    width: double.maxFinite,
                    child: StatefulBuilder(
                      builder: (BuildContext context,
                          void Function(void Function()) setState) {
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: acc_list.length,
                          itemBuilder: (BuildContext context, int index) {
                            return ListTile(
                              enabled: !acc_list[index]['selected'],
                              contentPadding: EdgeInsets.all(0),
                              title: Text(acc_list[index]['Name'],
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(acc_list[index]['Email']),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                        onPressed: acc_list[index]['selected']
                                            ? null
                                            : () {
                                                regAcc.add(acc_list[index]);
                                                checkAccID
                                                    .add(acc_list[index]['id']);
                                                setState(() {
                                                  acc_list[index]['selected'] =
                                                      true;
                                                });
                                              },
                                        child: Text('Accept')),
                                    TextButton(
                                        onPressed: acc_list[index]['selected']
                                            ? null
                                            : () {
                                                checkAccID
                                                    .add(acc_list[index]['id']);

                                                setState(() {
                                                  acc_list[index]['selected'] =
                                                      true;
                                                });
                                              },
                                        child: Text('Decline')),
                                  ]),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  TextButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        showDialog(
                            context: context,
                            builder: (_) => const Center(
                                  child: CircularProgressIndicator(),
                                ));
                        if (regAcc.isNotEmpty) {
                          for (var acc in regAcc) {
                            Auth().createUserWithEmailAndPassword(
                                email: acc['Email'], password: acc['Password']);
                          }
                        }

                        if (checkAccID.isNotEmpty) {
                          for (var id in checkAccID) {
                            await _firestore
                                .collection("regAcc")
                                .doc(id)
                                .delete();
                          }
                        }
                        Navigator.of(context).pop();
                      },
                      child: Text('Save'))
                ],
              ),
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary, //change your color here
        ),
        title: Text('Building Profile',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 25,
                fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: PopupMenuButton(
              onSelected: (value) => _onMenuItemSelected(value),
              offset: Offset(0.0, AppBar().preferredSize.height),
              itemBuilder: (BuildContext context) => [
                _buildPopupMenuItem('Message', Icons.messenger_rounded),
                _buildPopupMenuItem('Sign Out', Icons.logout),
              ],
            ),
          )
        ],
        //elevation: 20.0,
      ),
      floatingActionButton: Hero(
        tag: 'back',
        child: Container(
          height: 70,
          width: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary,
            boxShadow: const [
              BoxShadow(
                color: Colors.grey,
                blurRadius: 4,
                offset: Offset(0, 5), // Shadow position
              ),
            ],
          ),
          child: IconButton(
            onPressed: createProfile,
            icon: const Icon(
              Icons.add,
              color: Colors.white,
              size: 35,
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchProfiles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            final profiles = snapshot.data;
            num_profile = profiles?.length ?? 0;

            return ListView.builder(
              itemCount: num_profile,
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
                        await deleteProfile(
                            profile?['id'],
                            profile?['profileName'],
                            profile?['numberOfFloors']);
                        setState(() {});
                      },
                    ),
                    SlidableAction(
                      backgroundColor: Colors.green,
                      icon: Icons.edit,
                      label: 'Edit',
                      onPressed: (context) async {
                        editProfile(profile?['id'], profile?['profileName']);
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
                              profileID: profile?['id'],
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
