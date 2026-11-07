// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get cameraUnavailable => 'No se pudo abrir la cámara.';

  @override
  String get startBroadcast => 'Iniciar transmisión';

  @override
  String get stopBroadcast => 'Detener transmisión';
}
