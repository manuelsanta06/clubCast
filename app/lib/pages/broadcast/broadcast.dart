import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState(){
    super.initState();
    _initializeCamera();
  }
  @override
  void dispose(){
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(body:SafeArea(child:
        Column(children:[
          Expanded(
            child: Center(
              child: ValueListenableBuilder<CameraValue>(
                valueListenable:_cameraController,
                builder: (context,value,child){
                  final error=_cameraError??value.errorDescription;

                  if(error!=null)
                    return Text(error);

                  if(value.isInitialized!=true)
                    return const CircularProgressIndicator();

                  return AspectRatio(
                    aspectRatio:value.aspectRatio,
                    child:CameraPreview(_cameraController),
                  );
                },
              ),
            ),
          ),
        ],)
    ));
  }

  Future<void> _initializeCamera()async{
    try{
      final cameras=await availableCameras();

      if(!mounted)return;

      final rearCamera=cameras.firstWhere(
        (camera)=>camera.lensDirection==CameraLensDirection.back,
        orElse:()=>throw StateError('No back camera available'),
      );

      await _cameraController.initialize(rearCamera);
    }catch(error){
      if(!mounted)return;

      setState((){_cameraError='could not open camera: $error';});
    }
  }
}
