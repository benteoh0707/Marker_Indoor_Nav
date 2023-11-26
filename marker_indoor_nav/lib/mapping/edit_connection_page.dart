// ignore_for_file: must_be_immutable, prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:marker_indoor_nav/mapping/map.dart';

class EditConnectPage extends StatefulWidget {
  // ignore: non_constant_identifier_names
  Circle start;
  List<Circle> circles;
  // ignore: non_constant_identifier_names
  EditConnectPage({super.key, required this.start, required this.circles});

  @override
  State<EditConnectPage> createState() => _EditConnectPageState();
}

class _EditConnectPageState extends State<EditConnectPage> {
  edgeDialog(Circle end) {
    TextEditingController distanceController = TextEditingController(
        text: widget.start.connected_nodes[end.id]['distance'].toString());
    String? selectedItem = widget.start.connected_nodes[end.id]['direction'];
    List<String> directions = ['Left', 'Right', 'Back', 'Front'];
    bool validate = false;
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              title: Text('Connection Details',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  )),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Distance',
                        style: TextStyle(
                            fontWeight: FontWeight.w400, fontSize: 17),
                      ),
                      SizedBox(
                        width: 20,
                      ),
                      Expanded(
                        child: TextField(
                          controller: distanceController,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: InputDecoration(
                              hintText: 'Enter Distance',
                              errorText: validate
                                  // ignore: dead_code
                                  ? "Value Can't Be Empty"
                                  : null),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 20,
                  ),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Direction',
                            style: TextStyle(
                                fontWeight: FontWeight.w400, fontSize: 17)),
                        SizedBox(
                          width: 20,
                        ),
                        Expanded(
                          child: DropdownButton(
                            value: selectedItem == '-' ? null : selectedItem,
                            hint: Text('Select a direction'),
                            onChanged: (newValue) {
                              setState(() {
                                selectedItem = newValue;
                              });
                            },
                            items: directions.map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  value,
                                  style: TextStyle(fontWeight: FontWeight.w400),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ]),
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
                                validate = distanceController.text.isEmpty;
                              } else {
                                widget.start.connected_nodes[end.id]
                                        ['distance'] =
                                    num.parse(distanceController.text);
                                end.connected_nodes[widget.start.id]
                                        ['distance'] =
                                    num.parse(distanceController.text);
                                widget.start.connected_nodes[end.id]
                                    ['direction'] = selectedItem;

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
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.start.connected_nodes.keys.toList();
    final val = widget.start.connected_nodes.values.toList();
    return Scaffold(
        appBar: AppBar(
            title: Text('Marker Connection',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 25,
                    fontWeight: FontWeight.bold)),
            iconTheme: IconThemeData(
              color: Theme.of(context)
                  .colorScheme
                  .primary, //change your color here
            ),
            actions: <Widget>[
              IconButton(
                iconSize: 35,
                padding: EdgeInsets.only(right: 25.0),
                icon: Icon(
                  Icons.add,
                  size: 35,
                ),
                onPressed: () {
                  widget.start.selected = true;
                  Navigator.pop(context, false);
                },
              )
            ]),
        body: ListView.builder(
          itemCount: widget.start.connected_nodes.length,
          itemBuilder: (BuildContext context, int index) {
            Circle end =
                widget.circles.firstWhere((element) => element.id == id[index]);

            return Slidable(
              startActionPane:
                  ActionPane(motion: const StretchMotion(), children: [
                SlidableAction(
                  backgroundColor: Colors.red,
                  icon: Icons.delete,
                  label: 'Delete',
                  onPressed: (context) async {
                    setState(() {
                      widget.start.connected_nodes.remove(end.id);
                      end.connected_nodes.remove(widget.start.id);
                    });
                  },
                ),
              ]),
              child: ListTile(
                title: Text(end.name ?? '',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Distance: ${val[index]['distance']}'),
                    Text('Direction: ${val[index]['direction'] ?? '-'}'),
                  ],
                ),
                onTap: () async {
                  await edgeDialog(end);
                  setState(() {});
                },
              ),
            );
          },
        ));
  }
}
