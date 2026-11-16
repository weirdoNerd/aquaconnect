import 'dart:async';
import 'package:aquaconnect/models/provider_application.dart';
import 'package:aquaconnect/services/location_service.dart';
import 'package:aquaconnect/services/provider_service.dart';
import 'package:aquaconnect/services/source_service.dart';

class NoLocation implements LocationService {
  @override
  Future<LocationResult> getCurrent() async =>
      const LocationResult(LocationStatus.error);
  @override
  Future<void> openLocationSettings() async {}
  @override
  Future<void> openAppSettings() async {}
}

/// Satu "keran" per pemanggilan watch*, agar tes bisa memeriksa aliran mana yang
/// dibuka, kapan dibatalkan, dan mengirim data atau galat secara manual.
class Tap {
  final String name;
  final String? arg;
  bool cancelled = false;
  late final StreamController<SourceBatch> ctrl;

  Tap(this.name, this.arg) {
    ctrl = StreamController<SourceBatch>(onCancel: () => cancelled = true);
  }
}

class FakeSourceService implements SourceService {
  final taps = <Tap>[];

  Stream<SourceBatch> _tap(String name, [String? arg]) {
    final t = Tap(name, arg);
    taps.add(t);
    return t.ctrl.stream;
  }

  /// Nama aliran yang MASIH aktif (belum dibatalkan).
  List<String> get active => [for (final t in taps) if (!t.cancelled) t.name];

  @override
  Stream<SourceBatch> watchAll() => _tap('all');
  @override
  Stream<SourceBatch> watchPublished() => _tap('published');
  @override
  Stream<SourceBatch> watchOwned(String uid) => _tap('owned', uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class AppTap {
  final String uid;
  bool cancelled = false;
  late final StreamController<ProviderApplication?> ctrl;

  AppTap(this.uid) {
    ctrl = StreamController<ProviderApplication?>(onCancel: () => cancelled = true);
  }
}

class FakeProviderService implements ProviderService {
  final taps = <AppTap>[];
  final List<ProviderApplication> submitted = [];
  Object? nextApplyError;

  List<String> get active => [for (final t in taps) if (!t.cancelled) t.uid];

  @override
  Stream<ProviderApplication?> watchMyApplication(String uid) {
    final t = AppTap(uid);
    taps.add(t);
    return t.ctrl.stream;
  }

  @override
  Future<void> apply(ProviderApplication application) async {
    final err = nextApplyError;
    if (err != null) throw err;
    submitted.add(application);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
