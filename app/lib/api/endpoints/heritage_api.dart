import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/heritage_item.dart';

class HeritageUploadData {
  final String title;
  final String type;
  final String artist;
  final String genre;
  final String composer;
  final String performers;
  final String artisans;
  final String collector;
  final String recordedTime;
  final String location;
  final String source;
  final String license;
  final String lyrics;
  final String instruments;
  final String tonal;
  final String description;
  final String notes;
  final String bpm;

  const HeritageUploadData({
    this.title = '',
    this.type = '',
    this.artist = '',
    this.genre = '',
    this.composer = '',
    this.performers = '',
    this.artisans = '',
    this.collector = '',
    this.recordedTime = '',
    this.location = '',
    this.source = '',
    this.license = '',
    this.lyrics = '',
    this.instruments = '',
    this.tonal = '',
    this.description = '',
    this.notes = '',
    this.bpm = '',
  });
}

class HeritageApi {
  final Dio dio;

  HeritageApi(this.dio);

  Future<List<HeritageItem>> list({String q = ''}) async {
    final res = await dio.get('/api/heritage', queryParameters: {'q': q});
    final data = res.data as List;
    return data.map((e) => HeritageItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<HeritageItem> upload({
    required String filePath,
    required HeritageUploadData data,
  }) async {
    final name = filePath.split('/').last.split('\\').last;
    final form = FormData.fromMap({
      ..._metaMap(data),
      'file': await MultipartFile.fromFile(filePath, filename: name),
    });
    final res = await dio.post('/api/heritage/upload', data: form);
    return HeritageItem.fromJson(res.data as Map<String, dynamic>);
  }

  Future<HeritageItem> uploadBytes({
    required Uint8List bytes,
    required String filename,
    required HeritageUploadData data,
  }) async {
    final form = FormData.fromMap({
      ..._metaMap(data),
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await dio.post('/api/heritage/upload', data: form);
    return HeritageItem.fromJson(res.data as Map<String, dynamic>);
  }

  Map<String, dynamic> _metaMap(HeritageUploadData d) => {
        'title': d.title,
        'type': d.type,
        'artist': d.artist,
        'genre': d.genre,
        'composer': d.composer,
        'performers': d.performers,
        'artisans': d.artisans,
        'collector': d.collector,
        'recorded_time': d.recordedTime,
        'location': d.location,
        'source': d.source,
        'license': d.license,
        'lyrics': d.lyrics,
        'instruments': d.instruments,
        'tonal': d.tonal,
        'description': d.description,
        'notes': d.notes,
        'bpm': d.bpm,
      };

  String audioUrl(String id) {
    return '${dio.options.baseUrl}/api/heritage/$id/audio';
  }

  Future<Uint8List> audioBytes(String id) async {
    final res = await dio.get<List<int>>(
      audioUrl(id),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? <int>[]);
  }

  Future<String> downloadAudio(String id, String savePath) async {
    await dio.download(audioUrl(id), savePath);
    return savePath;
  }
}
