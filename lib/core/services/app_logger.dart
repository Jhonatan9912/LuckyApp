import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

final Logger appLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 90,
    colors: kDebugMode,        // colores solo en debug
    printEmojis: kDebugMode,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  level: kDebugMode ? Level.debug : Level.warning, // menos ruido en release
);
