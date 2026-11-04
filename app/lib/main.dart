import 'package:flutter/material.dart';
import 'package:app/pages/broadcast/broadcast.dart';

void main(){
  runApp(const MainApp());
}

class MainApp extends StatelessWidget{
  const MainApp({super.key});

  @override
  Widget build(BuildContext context){
    return const MaterialApp(
      title: "clubCast",
      themeMode:ThemeMode.system,
      home:BroadcastPage()
    );
  }
}
