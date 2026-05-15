import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image_picker/image_picker.dart';
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
      home: const MainNavigationPage(),
    );
  }
}

enum ImageViewType { original, grayscale, edges }

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  final ImagePicker _picker = ImagePicker();

  int _selectedIndex = 0;

  File? _originalFile;
  Uint8List? _originalBytes;
  Uint8List? _grayscaleBytes;
  Uint8List? _edgeBytes;

  ImageViewType _selectedView = ImageViewType.original;

  bool _isProcessing = false;

  static const int _fixedThreshold = 4;

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

      await _processImage();

      setState(() {
        _selectedIndex = 1;
      });
    } catch (e) {
      _showSnackBar('Erro ao capturar imagem: $e');
    }
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
      final edges = _applyEdgeDetection(gray, _fixedThreshold);

      final grayBytes = Uint8List.fromList(img.encodeJpg(gray, quality: 95));
      final edgeBytes = Uint8List.fromList(img.encodeJpg(edges, quality: 95));

      setState(() {
        _grayscaleBytes = grayBytes;
        _edgeBytes = edgeBytes;
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

  Widget _buildCaptureScreen() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 260,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt, size: 70, color: Colors.deepPurple),
                SizedBox(height: 12),
                Text(
                  'Capture uma foto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _captureImage,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Capturar Foto'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
            ),
          ),
          if (_isProcessing) ...[
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ],
      ),
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
            'Nenhuma imagem disponível.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.grey.shade300,
        child: Image.memory(
          bytes,
          height: 280,
          width: double.infinity,
          fit: BoxFit.contain,
        ),
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

  Widget _buildResultScreen() {
    final hasImage = _originalBytes != null;

    return SingleChildScrollView(
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
          ElevatedButton.icon(
            onPressed: hasImage ? _saveProcessedImage : null,
            icon: const Icon(Icons.save),
            label: const Text('Salvar Bordas'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildCaptureScreen(),
      _buildResultScreen(),
    ];

    final titles = [
      'Captura',
      'Resultado',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_selectedIndex]),
        centerTitle: true,
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt),
            label: 'Captura',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.image),
            label: 'Resultado',
          ),
        ],
      ),
    );
  }
}