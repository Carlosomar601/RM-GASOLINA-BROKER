import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'ui.dart';

/// Escáner del QR del surtidor. Devuelve el contenido crudo del código
/// (`pumps.qr_token` del broker) o `null` si el cliente cierra.
///
/// Se abre con:
/// ```dart
/// final token = await QrScanSheet.open(context);
/// ```
class QrScanSheet extends StatefulWidget {
  const QrScanSheet({super.key});

  static Future<String?> open(BuildContext context) => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: C.ink,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (_) => const QrScanSheet(),
      );

  @override
  State<QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends State<QrScanSheet> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .where((v) => v != null && v.trim().isNotEmpty)
        .cast<String>()
        .toList();
    if (raw.isEmpty) return;
    _done = true;
    Navigator.pop(context, raw.first.trim());
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.72;
    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Escanea el QR del surtidor', style: display(size: 19)),
                      Gap.h4,
                      Text('Está pegado en la cara de la bomba.',
                          style: body(size: 13, color: C.mutedDim)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: C.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: Radii.card,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (_, __, ___) => _cameraFallback(),
                    ),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 210,
                          height: 210,
                          decoration: BoxDecoration(
                            borderRadius: Radii.card,
                            border: Border.all(color: C.green, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: OButton(
              label: 'Prefiero escoger el número',
              variant: OButtonVariant.ghost,
              onTap: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraFallback() => Container(
        color: C.inkDeep,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 44, color: C.mutedDim),
              Gap.h12,
              Text(
                'No pudimos abrir la cámara.\nEscoge el surtidor por número.',
                textAlign: TextAlign.center,
                style: body(size: 14, color: C.muted),
              ),
            ],
          ),
        ),
      );
}
