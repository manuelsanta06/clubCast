import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/widgets/glintedButton.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

enum BroadcastScene{preMatch,match,halftime,penalty,postMatch}
enum BroadcastState{
  idle,
  connecting,
  live,
  reconnecting,
  stopping,
  failed,
}

abstract final class BroadcastColors{
  //BG
  static const background =Color(0xFF10131D);
  static const surface    =Color(0xFF22283A);

  //Colors
  static const primary  =Color(0xFF7656B3);
  static const positive =Color(0xFF249D48);
  static const negative =Color(0xFFC83C42);
  static const grey     =Color(0xFF424242);

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
  final streamUrl='rtmp://192.168.1.74:1935';
  final streamKey='test';

  final _cameraController=CameraController(
    ResolutionPreset.veryHigh,
    enableAudio:false,
  );

  String? _cameraError;
  BroadcastState state=BroadcastState.connecting;
  BroadcastScene scene=BroadcastScene.preMatch;

  @override
  void initState(){
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      //DeviceOrientation.landscapeRight,
    ]);
    _initializeCamera().then((v){
      if(!mounted)return;
      _cameraController.addListener(_onCameraChanged);
      setState((){
        state=_cameraController.value.isInitialized==true
          ?BroadcastState.idle
          :BroadcastState.failed;
      });
    },onError:(error){
      debugPrint(error);
    });
  }
  @override
  void dispose(){
    _cameraController.removeListener(_onCameraChanged);
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
  _cameraController.setOverlayText(text:"hola")
    final l10n=AppLocalizations.of(context)!;
    return Scaffold(body:SafeArea(child:
        Row(children:[
          Expanded(flex:60,child:Column(children:[
            Expanded(child:Center(
              child:ValueListenableBuilder<CameraValue>(
                valueListenable:_cameraController,
                builder:(context,value,child){
                  if(_cameraError!=null){
                    return Text(l10n.cameraUnavailable);
                  }

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
              _buildBroadcastControl(),
              const Spacer(),
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
                mainColor:BroadcastColors.grey,
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
                mainColor:BroadcastColors.grey,
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

  void _onCameraChanged(){
    if(!mounted)return;

    final event=_cameraController.value.event;
    if(event==null)return;

    final sessionActive=
      state ==BroadcastState.connecting||
      state ==BroadcastState.live||
      state ==BroadcastState.reconnecting;
      if(!sessionActive)return;

      BroadcastState nextState;

      switch(event['eventType']){
        case 'success':
          nextState=BroadcastState.live;
          break;

        case 'rtmp_retry':
          nextState=BroadcastState.reconnecting;
          break;

        case 'rtmp_stopped':
        case 'camera_closing':
          nextState=BroadcastState.failed;
          debugPrint('Transmisión interrumpida: $event');
          break;

        default:
          return;
      }

      if(nextState==state)return;

      setState((){state=nextState;});
  }

  Widget _buildBroadcastControl(){
    switch (state){
      case BroadcastState.idle:
        return GlintedButton(
          onPressed:_startStreaming,
          mainColor:BroadcastColors.positive,
          padding:EdgeInsets.symmetric(vertical:5,horizontal:3),
          child:Row(children:[Icon(Icons.play_arrow),Text('Transmitir')]),
        );

      case BroadcastState.live:
      case BroadcastState.reconnecting:
        return GlintedButton(
          onPressed:_stopStreaming,
          mainColor:BroadcastColors.negative,
          padding:EdgeInsets.symmetric(vertical:5,horizontal:3),
          child:Row(children:state==BroadcastState.live?[
            Icon(Icons.cell_tower),
            Text("Transmitiendo")
          ]:[
            SizedBox.square(
              dimension:IconTheme.of(context).size,
              child:const CircularProgressIndicator(strokeWidth:2),
            ),
            Text("Reconectando · Detener"),
          ]),
        );

      case BroadcastState.connecting:
      case BroadcastState.stopping:
        return GlintedButton(
          onPressed:null,
          mainColor:BroadcastColors.grey,
          padding:EdgeInsets.symmetric(vertical:5,horizontal:3),
          child:Row(children:[
            SizedBox.square(
              dimension:IconTheme.of(context).size,
              child:const CircularProgressIndicator(strokeWidth:2),
            ),
            Text(state==BroadcastState.connecting
              ?'Conectando…':'Deteniendo…',
            ),
          ]),
        );

      case BroadcastState.failed:
        return GlintedButton(
          onPressed:_retryStreaming,
          mainColor:BroadcastColors.positive,
          padding:EdgeInsets.symmetric(vertical:5,horizontal:3),
          child:Text('Reintentar'),
        );
    }
  }

  void _startStreaming()async{
    setState((){state=BroadcastState.connecting;});
    try{
      await _cameraController.startVideoStreaming(
        '$streamUrl/$streamKey',protocol:StreamingProtocol.rtmp);
    }catch(error){
      debugPrint('No se pudo iniciar: $error');
      if(!mounted)return;
      setState((){state=BroadcastState.failed;});
    }
  }

  Future<void> _stopStreaming()async{
    setState((){state=BroadcastState.stopping;});

    try{
      await _cameraController.stopVideoStreaming();

      if(!mounted)return;

      setState((){state=BroadcastState.idle;});
    }catch(error){
      debugPrint('No se pudo detener la transmisión: $error');

      if(!mounted)return;

      setState((){state=BroadcastState.failed;});
    }
  }

  void _retryStreaming(){
  }
}
