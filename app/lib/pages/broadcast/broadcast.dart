import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/widgets/glintedButton.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

enum BroadcastScene{preMatch,match,halftime,penalty,postMatch}

abstract final class BroadcastColors{
  //BG
  static const background =Color(0xFF10131D);
  static const surface    =Color(0xFF22283A);

  //Colors
  static const primary  =Color(0xFF7656B3);
  static const positive =Color(0xFF249D48);
  static const negative =Color(0xFFC83C42);

  //Text
  static const text         =Color(0xFFF5F5F7);
  static const textSecondary=Color(0xFFB0B3C0);
}

class BroadcastPage extends StatefulWidget{
  const new({super.key});

  @override
  State<BroadcastPage> createState()=>_BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage>{
  final _cameraController=CameraController(
    ResolutionPreset.veryHigh,
    enableAudio:false,
  );

  String? _cameraError;
  BroadcastScene scene=BroadcastScene.preMatch;

  @override
  void initState(){
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      //DeviceOrientation.landscapeRight,
    ]);
    _initializeCamera();
  }
  @override
  void dispose(){
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    final l10n=AppLocalizations.of(context)!;
    return Scaffold(body:SafeArea(child:
        Row(children:[
          Expanded(flex:60,child:Column(children:[
            if(true)
            Expanded(child:Center(
              child:ValueListenableBuilder<CameraValue>(
                valueListenable:_cameraController,
                builder:(context,value,child){
                  final error=_cameraError??value.errorDescription;

                  if(error!=null)
                    return Text(l10n.cameraUnavailable);

                  if(value.isInitialized!=true)
                    return const CircularProgressIndicator();

                  return AspectRatio(
                    aspectRatio:value.aspectRatio,
                    child:CameraPreview(_cameraController),
                  );
                },
              ),
            )),
            SegmentedButton<BroadcastScene>(
              showSelectedIcon:false,
              selected:{scene},
              segments:const[
                ButtonSegment<BroadcastScene>(
                  value:BroadcastScene.preMatch,
                  label:Text("pre")
                ),
                ButtonSegment<BroadcastScene>(
                  value:BroadcastScene.match,
                  label:Text("partido")
                ),
                ButtonSegment<BroadcastScene>(
                  value:BroadcastScene.penalty,
                  label:Text("zoom")
                ),
                ButtonSegment<BroadcastScene>(
                  value:BroadcastScene.halftime,
                  label:Text("entre tiempo")
                ),
                ButtonSegment<BroadcastScene>(
                  value:BroadcastScene.postMatch,
                  label:Text("fin")
                ),
              ],
              onSelectionChanged:(Set<BroadcastScene> newSelection){
                setState((){scene=newSelection.first;});
              },
              style:SegmentedButton.styleFrom(
                side:BorderSide(color:Colors.red),
              )
            ),

          ])),
          Expanded(flex:40,child:Column(spacing:8,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            //TOP BAR
            Row(spacing:5,children:[
              GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.positive,
                padding:EdgeInsets.all(5),
                child:Row(children:[Icon(Icons.cell_tower),Text("transmitiendo")]),
              ),
              Expanded(child:SizedBox()),
              GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.negative,
                padding:EdgeInsets.all(5),
                borderRadius:BorderRadius.circular(10),
                child:Icon(Icons.mic_off),
              ),
              GlintedButton(
                onPressed:(){},
                mainColor:Colors.yellow.shade700,
                padding:EdgeInsets.all(5),
                borderRadius:BorderRadius.circular(10),
                child:Icon(Icons.qr_code),
              ),
              GlintedButton(
                onPressed:(){},
                mainColor:Colors.yellow,
                padding:EdgeInsets.all(5),
                borderRadius:BorderRadius.circular(10),
                child:Icon(Icons.settings),
              )
            ]),
            //INFO
            Row(spacing:8,children:[
              Expanded(child:AspectRatio(aspectRatio:4,child:GlintedButton(
                onPressed:(){},
                mainColor:Colors.grey.shade800,
                child:Icon(Icons.abc),
              ))),
            ]),
            //GOLES
            Row(spacing:8,children:[
              Expanded(child:AspectRatio(aspectRatio:1,child:GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.positive,
                child:Text("+1 L"),
              ))),
              Expanded(child:AspectRatio(aspectRatio:1,child:GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.negative,
                child:Text("-1 L")
              ))),
              Expanded(child:AspectRatio(aspectRatio:1,child:GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.positive,
                child:Text("+1 V")
              ))),
              Expanded(child:AspectRatio(aspectRatio:1,child:GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.negative,
                child:Text("-1 V")
              ))),
            ]),
            //TIME
            Row(spacing:8,children:[
              Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.positive,
                child:Text("+60s"),
              ))),
              Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.positive,
                child:Text("+1s")
              ))),
              Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
                onPressed:(){},
                mainColor:Colors.grey.shade800,
                child:Icon(Icons.play_arrow),
              ))),
              Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.negative,
                child:Text("-60s")
              ))),
              Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
                onPressed:(){},
                mainColor:BroadcastColors.negative,
                child:Text("-1s")
              ))),
            ]),
          ])),
        ])
    ));
  }

  Future<void> _initializeCamera()async{
    try{
      final cameras=await availableCameras();

      if(!mounted)return;

      final l10n=AppLocalizations.of(context)!;
      final rearCamera=cameras.firstWhere(
        (camera)=>camera.lensDirection==CameraLensDirection.back,
        orElse:()=>throw StateError(l10n.cameraUnavailable),
      );

      await _cameraController.initialize(rearCamera);
    }catch(error){
      if(!mounted)return;

      setState((){_cameraError='could not open camera: $error';});
    }
  }
}
