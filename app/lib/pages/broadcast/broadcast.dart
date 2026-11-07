import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

enum BroadcastScene{preMatch,match,halftime,penalty,postMatch}

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
            Row(children:[
              FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.green,
                  foregroundColor:Colors.white,
                ),
                child:Row(children:[Icon(Icons.cell_tower),Text("transmitiendo")]),
              ),
              Expanded(child:SizedBox()),
              FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.red,
                  foregroundColor:Colors.black,
                  minimumSize:const Size.square(40),
                  padding:EdgeInsets.zero,
                  shape:RoundedRectangleBorder(
                    borderRadius:BorderRadius.circular(5),
                  ),
                ),
                child:Icon(Icons.mic_off),
              ),
              FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.yellow.shade700,
                  foregroundColor:Colors.black,
                  minimumSize:const Size.square(40),
                  padding:EdgeInsets.zero,
                  shape:RoundedRectangleBorder(
                    borderRadius:BorderRadius.circular(5),
                  ),
                ),
                child:Icon(Icons.qr_code),
              ),
              FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.yellow,
                  foregroundColor:Colors.black,
                  minimumSize:const Size.square(40),
                  padding:EdgeInsets.zero,
                  shape:RoundedRectangleBorder(
                    borderRadius:BorderRadius.circular(5),
                  ),
                ),
                child:Icon(Icons.settings),
              )
            ]),
            //INFO
            Expanded(child:Row(spacing:8,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.grey.shade800,
                  foregroundColor:Colors.white,
                ),
                child:Icon(Icons.abc),
              )),
            ])),
            //GOLES
            Expanded(child:Row(spacing:8,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.green.shade700,
                  foregroundColor:Colors.white,
                ),
                child:Text("+1 L"),
              )),
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.red.shade700,
                  foregroundColor:Colors.white,
                ),
                child:Text("-1 L")
              )),
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.green.shade700,
                  foregroundColor:Colors.white,
                ),
                child:Text("+1 V")
              )),
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.red.shade700,
                  foregroundColor:Colors.white,
                ),
                child:Text("-1 V")
              )),
            ])),
            //TIME
            Expanded(child:Row(spacing:8,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.green.shade700,
                  foregroundColor:Colors.white,
                ),
                child:Text("+60s"),
              )),
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.green.shade700,
                  foregroundColor:Colors.white,
                ),
                child:Text("+1s")
              )),
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.grey.shade800,
                  foregroundColor:Colors.white,
                ),
                child:Icon(Icons.play_arrow),
              )),
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.red.shade700,
                  foregroundColor:Colors.white,
                ),
                child:Text("-60s")
              )),
              Expanded(child:FilledButton(
                onPressed:(){},
                style:FilledButton.styleFrom(
                  backgroundColor:Colors.red.shade700,
                  foregroundColor:Colors.white,
                ),
                child:Text("-1s")
              )),
            ])),
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
