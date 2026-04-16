import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ArCameraPreview extends StatelessWidget {
  static const String viewType = 'unav/tracking/ar_preview_view';

  const ArCameraPreview({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return const UiKitView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: {},
        creationParamsCodec: StandardMessageCodec(),
      );
    } else if (Platform.isAndroid) {
      return const AndroidView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: {},
        creationParamsCodec: StandardMessageCodec(),
      );
    } else {
      return const Center(
        child: Text('AR is only supported on iOS and Android'),
      );
    }
  }
}
