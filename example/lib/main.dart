import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/location_dto.dart';
import 'package:background_locator_2/settings/android_settings.dart';
import 'package:background_locator_2/settings/ios_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'file_manager.dart';
import 'location_callback_handler.dart';
import 'location_service_repository.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ReceivePort port = ReceivePort();

  String logStr = '';
  bool? isRunning;
  LocationDto? lastLocation;

  @override
  void initState() {
    super.initState();

    if (IsolateNameServer.lookupPortByName(
            LocationServiceRepository.isolateName) !=
        null) {
      IsolateNameServer.removePortNameMapping(
          LocationServiceRepository.isolateName);
    }

    IsolateNameServer.registerPortWithName(
        port.sendPort, LocationServiceRepository.isolateName);

    port.listen(
      (dynamic data) async {
        await updateUI(data);
      },
    );
    initPlatformState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> updateUI(dynamic data) async {
    final log = await FileManager.readLogFile();

    LocationDto? locationDto =
        (data != null) ? LocationDto.fromJson(data) : null;

    if (locationDto == null) return;

    await _updateNotificationText(locationDto);

    setState(() {
      if (data != null) {
        lastLocation = locationDto;
      }
      logStr = log;
    });
  }

  Future<void> _updateNotificationText(LocationDto data) async {
    await BackgroundLocator.updateNotificationText(
        title: "new location received",
        msg: "${DateTime.now()}",
        bigMsg: "${data.latitude}, ${data.longitude}");
  }

  Future<void> initPlatformState() async {
    PermissionStatus locationWhenInUse =
        await Permission.locationWhenInUse.request();
    if (locationWhenInUse != PermissionStatus.granted) {
      return;
    }

    PermissionStatus locationAlways = await Permission.locationAlways.request();

    if (locationAlways != PermissionStatus.granted) {
      return;
    }

    print('Initializing...');
    await BackgroundLocator.initialize();
    logStr = await FileManager.readLogFile();
    print('Initialization done');
    final running = await BackgroundLocator.isServiceRunning();
    setState(() {
      isRunning = running;
    });
    print('Running ${isRunning.toString()}');
  }

  @override
  Widget build(BuildContext context) {
    final isServiceEnableBtn = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: Text('Is service enabled'),
        onPressed: () {
          _isLocationServiceEnabled();
        },
      ),
    );

    final start = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: Text('Start'),
        onPressed: () {
          _onStart();
        },
      ),
    );
    final stop = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: Text('Stop'),
        onPressed: () {
          onStop();
        },
      ),
    );
    final clear = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: Text('Clear Log'),
        onPressed: () {
          FileManager.clearLogFile();
          setState(() {
            logStr = '';
          });
        },
      ),
    );
    String msgStatus = "-";
    if (isRunning != null) {
      if (isRunning!) {
        msgStatus = 'Is running';
      } else {
        msgStatus = 'Is not running';
      }
    }
    final status = Text("Status: $msgStatus");

    final log = Text(logStr);

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter background Locator'),
        ),
        body: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                isServiceEnableBtn,
                start,
                stop,
                clear,
                status,
                log
              ],
            ),
          ),
        ),
      ),
    );
  }

  void onStop() async {
    await BackgroundLocator.unRegisterLocationUpdate();
    final bool running = await BackgroundLocator.isServiceRunning();
    setState(() {
      isRunning = running;
    });
  }

  void _onStart() async {
    if (await _checkLocationPermission()) {
      await _startLocator();
      final running = await BackgroundLocator.isServiceRunning();

      setState(() {
        isRunning = running;
        lastLocation = null;
      });
    } else {
      // show error
    }
  }

  Future<bool> _checkLocationPermission() async {
    final access = await Permission.location.status;
    if (access == PermissionStatus.granted) {
      return true;
    } else {
      final permission = await Permission.location.request();
      if (permission == PermissionStatus.granted) {
        return true;
      } else {
        return false;
      }
    }
  }

  Future<void> _startLocator() async {
    Map<String, dynamic> data = {'countInit': 1};
    return await BackgroundLocator.registerLocationUpdate(
        LocationCallbackHandler.callback,
        initCallback: LocationCallbackHandler.initCallback,
        initDataCallback: data,
        disposeCallback: LocationCallbackHandler.disposeCallback,
        iosSettings: IOSSettings(
            accuracy: LocationAccuracy.NAVIGATION,
            distanceFilter: 0,
            stopWithTerminate: true),
        autoStop: false,
        androidSettings: AndroidSettings(
            accuracy: LocationAccuracy.NAVIGATION,
            interval: 5,
            distanceFilter: 0,
            client: LocationClient.google,
            androidNotificationSettings: AndroidNotificationSettings(
                notificationChannelName: 'Location tracking',
                notificationTitle: 'Start Location Tracking',
                notificationMsg: 'Track location in background',
                notificationBigMsg:
                    'Background location is on to keep the app up-tp-date with your location. This is required for main features to work properly when the app is not running.',
                notificationIconColor: Colors.grey,
                notificationTapCallback:
                    LocationCallbackHandler.notificationCallback)));
  }

  Future<void> _isLocationServiceEnabled() async {
    final bool serviceEnabled =
        await BackgroundLocator.isLocationServicesEnabled();
    print('serviceEnabled: $serviceEnabled');
  }
}
