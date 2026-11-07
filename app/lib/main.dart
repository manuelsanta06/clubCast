import 'package:flutter/material.dart';
import 'package:app/l10n/app_localizations.dart';

import 'package:app/pages/broadcast/broadcast.dart';

void main(){
  runApp(const MainApp());
}

class MainApp extends StatelessWidget{
  const MainApp({super.key});

  @override
  Widget build(BuildContext context){
    return MaterialApp(
      title:"clubCast",
      themeMode:ThemeMode.system,
      darkTheme:ThemeData.dark().copyWith(
        filledButtonTheme:FilledButtonThemeData(
          style:FilledButton.styleFrom(
            padding:EdgeInsets.zero,
            shape:RoundedRectangleBorder(
              borderRadius:BorderRadius.circular(20),
            ),
          ),
        ),
      ),
      localizationsDelegates:AppLocalizations.localizationsDelegates,
      supportedLocales:AppLocalizations.supportedLocales,
      home:BroadcastPage()
    );
  }
}
