import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/water_source.dart';
import '../services/location_service.dart';
import '../services/source_service.dart';
import '../utils/geo.dart';

class SourceProvider extends ChangeNotifier {
  final SourceService _service;
  final LocationService _location;

  // Langganan data dibuka oleh [syncUser], bukan oleh konstruktor.
  final List<StreamSubscription<SourceBatch>> _subs = [];
  bool _synced = false;
  String? _uid;
  bool _isAdmin = false;
  bool _isProvider = false;

  List<WaterSource> _all = [];
  Map<String, WaterSource> _byId = {};
  bool _loading = true;
  String? _error;
  int _skipped = 0;
  bool _fromCache = false;

  String _query = '';
  SourceType? _type;

  LatLng? _user;
  bool _sortNearest = false;
  bool _locating = false;

  List<WaterSource>? _cache; // memoisasi hasil items

  SourceProvider(this._service, this._location);

  /// Memilih aliran data menurut peran dan membukanya ulang HANYA bila tupel
  /// (uid, isAdmin, isProvider) berubah:
  /// - tamu atau warga: sumber tayang;
  /// - penyedia aktif: sumber tayang digabung sumber miliknya (dedup per id);
  /// - admin: semua (rules menolak query tanpa filter untuk non-admin).
  ///
  /// Pemanggilan pertama WAJIB terjadi sejak awal (juga untuk tamu) agar aplikasi
  /// menampilkan sumber tayang sebelum login. Dipanggil dari ProxyProvider saat
  /// build, jadi TIDAK memanggil notifyListeners; daftar lama dikosongkan dan
  /// langganan lama dibatalkan agar tidak ada data pengguna sebelumnya yang bocor.
  void syncUser(String? uid, {required bool isAdmin, required bool isProvider}) {
    if (_synced && uid == _uid && isAdmin == _isAdmin && isProvider == _isProvider) {
      return;
    }
    _synced = true;
    _uid = uid;
    _isAdmin = isAdmin;
    _isProvider = isProvider;

    _cancelSubs();
    _all = [];
    _byId = {};
    _skipped = 0;
    _fromCache = false;
    _loading = true;
    _error = null;
    _cache = null;
    _open();
  }

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _open() {
    if (_isAdmin) {
      _listenSingle(_service.watchAll());
    } else if (_isProvider && _uid != null) {
      _listenMerged(_service.watchPublished(), _service.watchOwned(_uid!));
    } else {
      _listenSingle(_service.watchPublished());
    }
  }

  void _listenSingle(Stream<SourceBatch> stream) {
    _subs.add(stream.listen((b) => _apply([b]), onError: _onError));
  }

  /// Menunggu KEDUA aliran mengirim data pertama sebelum menampilkan, agar daftar
  /// tidak berkedip dari "hanya tayang" ke "tayang + milikku".
  void _listenMerged(Stream<SourceBatch> a, Stream<SourceBatch> b) {
    SourceBatch? lastA;
    SourceBatch? lastB;
    void emit() {
      if (lastA == null || lastB == null) return;
      _apply([lastA!, lastB!]);
    }

    _subs.add(a.listen((x) {
      lastA = x;
      emit();
    }, onError: _onError));
    _subs.add(b.listen((x) {
      lastB = x;
      emit();
    }, onError: _onError));
  }

  /// Menggabungkan batch: dedup per id (batch belakangan, yaitu milik sendiri,
  /// menang), `skipped` dijumlah, `fromCache` benar bila salah satunya benar.
  void _apply(List<SourceBatch> batches) {
    final merged = <String, WaterSource>{};
    var skipped = 0;
    var cache = false;
    for (final batch in batches) {
      skipped += batch.skipped;
      cache = cache || batch.fromCache;
      for (final s in batch.sources) {
        merged[s.id] = s;
      }
    }
    _all = merged.values.toList();
    _byId = merged;
    _skipped = skipped;
    _fromCache = cache;
    _loading = false;
    _error = null;
    _cache = null;
    notifyListeners();
  }

  void _onError(Object e) {
    debugPrint('SourceProvider stream error: $e');
    _loading = false;
    _error = 'Gagal memuat data sumber air. Periksa koneksi internet.';
    notifyListeners();
  }

  void retry() {
    _loading = true;
    _error = null;
    notifyListeners();
    _cancelSubs();
    _open();
  }

  bool get loading => _loading;
  String? get error => _error;

  /// Semua sumber yang sedang dilanggan (admin: termasuk nonaktif).
  List<WaterSource> get all => List.unmodifiable(_all);

  /// Jumlah dokumen rusak yang dilewati (ditampilkan di panel admin).
  int get skippedSources => _skipped;

  /// true bila data berasal dari cache lokal dan mungkin tidak terbaru.
  bool get fromCache => _fromCache;

  String get query => _query;
  SourceType? get selectedType => _type;
  LatLng? get userLocation => _user;
  bool get sortNearest => _sortNearest && _user != null;
  bool get locating => _locating;

  /// Daftar untuk warga: hanya sumber aktif, sudah difilter dan diurutkan.
  List<WaterSource> get items => _cache ??= _compute();

  List<WaterSource> _compute() {
    final q = _query.trim().toLowerCase();
    final list = _all.where((s) {
      if (!s.isActive) return false;
      if (_type != null && s.type != _type) return false;
      return q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.address.toLowerCase().contains(q);
    }).toList();

    if (sortNearest) {
      list.sort((a, b) => distanceTo(a)!.compareTo(distanceTo(b)!));
    } else {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  WaterSource? byId(String id) => _byId[id];

  void setQuery(String v) {
    _query = v;
    _cache = null;
    notifyListeners();
  }

  void setType(SourceType? t) {
    _type = t;
    _cache = null;
    notifyListeners();
  }

  /// Jarak (meter) dari lokasi pengguna, atau null bila lokasi belum diketahui.
  double? distanceTo(WaterSource s) {
    final u = _user;
    if (u == null) return null;
    return distanceMeters(u.latitude, u.longitude, s.latitude, s.longitude);
  }

  String? distanceLabel(WaterSource s) {
    final d = distanceTo(s);
    return d == null ? null : formatDistance(d);
  }

  /// Jarak sumber air terdekat pada daftar yang sedang tampil.
  double? get nearestDistance {
    if (!sortNearest) return null;
    final list = items;
    return list.isEmpty ? null : distanceTo(list.first);
  }

  Future<LocationStatus> locate() async {
    _locating = true;
    notifyListeners();
    final r = await _location.getCurrent();
    _locating = false;
    if (r.status == LocationStatus.ok && r.point != null) {
      _user = r.point;
      _sortNearest = true;
    }
    _cache = null;
    notifyListeners();
    return r.status;
  }

  void clearNearest() {
    _sortNearest = false;
    _user = null;
    _cache = null;
    notifyListeners();
  }

  Future<void> openLocationSettings() => _location.openLocationSettings();
  Future<void> openAppSettings() => _location.openAppSettings();

  /// Menyimpan sumber air (jalur admin). Mengembalikan pesan error, atau null jika berhasil.
  Future<String?> saveSource(
    WaterSource s, {
    required bool isNew,
    bool confirmStatus = false,
  }) async {
    final name = s.name.trim().toLowerCase();
    final duplicate = _all.any((o) =>
        o.id != s.id &&
        o.name.trim().toLowerCase() == name &&
        distanceMeters(o.latitude, o.longitude, s.latitude, s.longitude) < 50);
    if (duplicate) {
      return 'Sumber air dengan nama sama sudah terdaftar di titik ini.';
    }
    try {
      if (isNew) {
        await _service.create(s);
      } else {
        await _service.update(s, confirmStatus: confirmStatus);
      }
      return null;
    } on SourceException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('saveSource: $e');
      return 'Gagal menyimpan. Coba lagi.';
    }
  }

  /// Dipanggil hanya dari panel admin (mode debug + Firebase).
  Future<int> seedDemoData(List<WaterSource> data) => _service.seed(data);

  @override
  void dispose() {
    _cancelSubs();
    super.dispose();
  }
}
