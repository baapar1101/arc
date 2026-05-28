import 'package:geolocator/geolocator.dart';

/// مختصات شروع ویزیت؛ در صورت عدم دسترسی null برمی‌گرداند.
Future<({double? latitude, double? longitude})> readDistributionVisitLocation() async {
  try {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      return (latitude: null, longitude: null);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return (latitude: null, longitude: null);
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (latitude: pos.latitude, longitude: pos.longitude);
  } catch (_) {
    return (latitude: null, longitude: null);
  }
}
