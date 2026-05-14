import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detector de Bordas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EdgeDetectorPage(),
    );
  }
}

enum ImageViewType { original, grayscale, edges }

class EdgeDetectorPage extends StatefulWidget {
  const EdgeDetectorPage({super.key});

  @override
  State<EdgeDetectorPage> createState() => _EdgeDetectorPageState();
}

class _EdgeDetectorPageState extends State<EdgeDetectorPage> {
  final ImagePicker _picker = ImagePicker();

  File? _originalFile;
  Uint8List? _originalBytes;
  Uint8List? _grayscaleBytes;
  Uint8List? _edgeBytes;

  ImageViewType _selectedView = ImageViewType.original;

  double _threshold = 40;
  bool _isProcessing = false;

  String _processingInfo = 'Nenhum processamento realizado.';
  String _dateTimeInfo = '-';
  String _locationInfo = '-';

  Future<void> _captureImage() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

      if (photo == null) return;

      final file = File(photo.path);
      final bytes = await file.readAsBytes();

      setState(() {
        _originalFile = file;
        _originalBytes = bytes;
        _grayscaleBytes = null;
        _edgeBytes = null;
        _selectedView = ImageViewType.original;
      });

      await _registerMetadata();
      await _processImage();
    } catch (e) {
      _showSnackBar('Erro ao capturar imagem: $e');
    }
  }

  Future<void> _registerMetadata() async {
    final now = DateTime.now();
    String locationText = 'Localização indisponível';

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        locationText = 'GPS desativado';
      } else {
        LocationPermission permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied) {
          locationText = 'Permissão de localização negada';
        } else if (permission == LocationPermission.deniedForever) {
          locationText = 'Permissão negada permanentemente';
        } else {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );

          locationText =
              'Lat: ${position.latitude.toStringAsFixed(5)}, '
              'Lon: ${position.longitude.toStringAsFixed(5)}';
        }
      }
    } catch (_) {
      locationText = 'Erro ao obter localização';
    }

    setState(() {
      _dateTimeInfo = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
      _locationInfo = locationText;
    });
  }

  Future<void> _processImage() async {
    if (_originalBytes == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final decoded = img.decodeImage(_originalBytes!);

      if (decoded == null) {
        throw Exception('Não foi possível decodificar a imagem.');
      }

      final gray = img.grayscale(decoded);
      final edges = _applyEdgeDetection(gray, _threshold.toInt());

      final grayBytes = Uint8List.fromList(img.encodeJpg(gray, quality: 95));
      final edgeBytes = Uint8List.fromList(img.encodeJpg(edges, quality: 95));

      setState(() {
        _grayscaleBytes = grayBytes;
        _edgeBytes = edgeBytes;
        _processingInfo =
            'Filtro aplicado: tons de cinza + detecção de bordas por diferença entre pixels vizinhos. '
            'Threshold atual: ${_threshold.toInt()}. '
            'Tamanho: ${decoded.width}x${decoded.height}px.';
      });
    } catch (e) {
      _showSnackBar('Erro ao processar imagem: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  img.Image _applyEdgeDetection(img.Image grayImage, int threshold) {
    final width = grayImage.width;
    final height = grayImage.height;
    final output = img.Image(width: width, height: height);

    for (int y = 0; y < height - 1; y++) {
      for (int x = 0; x < width - 1; x++) {
        final p = grayImage.getPixel(x, y);
        final px = grayImage.getPixel(x + 1, y);
        final py = grayImage.getPixel(x, y + 1);

        final v = img.getLuminance(p);
        final vx = img.getLuminance(px);
        final vy = img.getLuminance(py);

        final diffX = (v - vx).abs();
        final diffY = (v - vy).abs();
        final magnitude = diffX + diffY;

        final edgeValue = magnitude > threshold ? 255 : 0;
        output.setPixelRgb(x, y, edgeValue, edgeValue, edgeValue);
      }
    }

    return output;
  }

  Uint8List? _getCurrentDisplayedBytes() {
    switch (_selectedView) {
      case ImageViewType.original:
        return _originalBytes;
      case ImageViewType.grayscale:
        return _grayscaleBytes;
      case ImageViewType.edges:
        return _edgeBytes;
    }
  }

  String _getViewLabel() {
    switch (_selectedView) {
      case ImageViewType.original:
        return 'Imagem Original';
      case ImageViewType.grayscale:
        return 'Tons de Cinza';
      case ImageViewType.edges:
        return 'Bordas Detectadas';
    }
  }

  Future<void> _saveProcessedImage() async {
    if (_edgeBytes == null) {
      _showSnackBar('Nenhuma imagem processada para salvar.');
      return;
    }

    try {
      if (Platform.isAndroid) {
        await Permission.storage.request();
        await Permission.photos.request();
        await Permission.manageExternalStorage.request();
      }

      final fileName = 'bordas_${DateTime.now().millisecondsSinceEpoch}';

      final result = await ImageGallerySaverPlus.saveImage(
        _edgeBytes!,
        quality: 100,
        name: fileName,
      );

      _showSnackBar('Imagem salva com sucesso: $result');
    } catch (e) {
      _showSnackBar('Erro ao salvar imagem: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildImageArea() {
    final bytes = _getCurrentDisplayedBytes();

    if (bytes == null) {
      return Container(
        height: 280,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: const Center(
          child: Text(
            'Capture uma imagem para iniciar o processamento.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.memory(
        bytes,
        height: 280,
        width: double.infinity,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildSelector() {
    return SegmentedButton<ImageViewType>(
      segments: const [
        ButtonSegment<ImageViewType>(
          value: ImageViewType.original,
          label: Text('Original'),
          icon: Icon(Icons.photo),
        ),
        ButtonSegment<ImageViewType>(
          value: ImageViewType.grayscale,
          label: Text('Cinza'),
          icon: Icon(Icons.filter_b_and_w),
        ),
        ButtonSegment<ImageViewType>(
          value: ImageViewType.edges,
          label: Text('Bordas'),
          icon: Icon(Icons.edgesensor_high),
        ),
      ],
      selected: {_selectedView},
      onSelectionChanged: (value) {
        setState(() {
          _selectedView = value.first;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _originalBytes != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detector de Bordas'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildImageArea(),
            const SizedBox(height: 16),
            if (hasImage) ...[
              Center(
                child: Text(
                  _getViewLabel(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              _buildSelector(),
              const SizedBox(height: 20),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ajuste do threshold',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      value: _threshold,
                      min: 0,
                      max: 255,
                      divisions: 255,
                      label: _threshold.toInt().toString(),
                      onChanged: hasImage
                          ? (value) async {
                              setState(() {
                                _threshold = value;
                              });
                              await _processImage();
                            }
                          : null,
                    ),
                    Text('Threshold atual: ${_threshold.toInt()}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Informações do processamento',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_processingInfo),
                    const SizedBox(height: 8),
                    Text('Data/Hora: $_dateTimeInfo'),
                    const SizedBox(height: 4),
                    Text('Localização: $_locationInfo'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isProcessing)
              const Center(child: CircularProgressIndicator()),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _captureImage,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Capturar Foto'),
                ),
                ElevatedButton.icon(
                  onPressed: hasImage ? _processImage : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reprocessar'),
                ),
                ElevatedButton.icon(
                  onPressed: hasImage ? _saveProcessedImage : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar Bordas'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}