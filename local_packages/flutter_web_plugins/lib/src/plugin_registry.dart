// Stub Registrar for flutter_web_plugins
// This stub is only used for dependency resolution on non-web platforms.

import 'package:flutter/services.dart';

/// A stub [Registrar] for non-web platforms.
class Registrar {
  /// Registers a plugin with the given name.
  void registerMessageHandler() {}

  /// The [BinaryMessenger] that is used for plugin communication.
  BinaryMessenger get messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
}
