import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/widgets/glintedButton.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'broadcastScenes.dart';
import 'broadcastInfo.dart';
import 'broadcastSettings.dart';

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
  final streamUrl='rtmp://192.168.1.25:1935';
  final streamKey='test';

  final _cameraController=CameraController(
    ResolutionPreset.high,
    enableAudio:true,
  );

  String? _cameraError;
  bool _audioMuted=false;
  bool _changingAudio=false;
  bool _settingsOpen=false;
  bool _videoModesReady=false;
  List<CameraVideoMode> videoModes=const [];
  BroadcastSettings settings=const BroadcastSettings();
  bool get _settingsLocked=>_cameraController.value.isStreaming==true ||
    _cameraController.value.isRecordingVideo==true ||
    state==BroadcastState.connecting || state==BroadcastState.live ||
    state==BroadcastState.reconnecting || state==BroadcastState.stopping;
  BroadcastState state=BroadcastState.connecting;
  late final BroadcastScenes scenes;

  @override
  void initState(){
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    scenes=BroadcastScenes(_cameraController);
    scenes.addListener(_onScenesChanged);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      //DeviceOrientation.landscapeRight,
    ]);
    _initializeCamera().then((v){
      if(!mounted)return;
      _cameraController.addListener(_onCameraChanged);
      setState((){
        state=_videoModesReady && _cameraError==null
          ?BroadcastState.idle
          :BroadcastState.failed;
      });
    },onError:(error){
      debugPrint(error);
    });
  }
  @override
  void dispose(){
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    scenes.removeListener(_onScenesChanged);
    scenes.dispose();
    _cameraController.removeListener(_onCameraChanged);
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    final l10n=AppLocalizations.of(context)!;
    return Scaffold(body:SafeArea(left:false,right:false,child:
      Row(spacing:5,children:[
        Expanded(flex:60,child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[
          ValueListenableBuilder<CameraValue>(
            valueListenable:_cameraController,
            builder:(context,value,child){
              if(_cameraError!=null){
                return Text(l10n.cameraUnavailable);
              }

              if(value.isInitialized!=true || !_videoModesReady){
                return const CircularProgressIndicator();
              }

              return AspectRatio(
                aspectRatio:value.aspectRatio,
                child:CameraPreview(_cameraController,onCreated:scenes.setup),
              );
            },
          ),
          Expanded(child:SegmentedButton<BroadcastScene>(
            showSelectedIcon:false,
            selected:{scenes.scene},
            segments:const[
              ButtonSegment<BroadcastScene>(
                value:BroadcastScene.match,
                label:Text("partido")
              ),
              ButtonSegment<BroadcastScene>(
                value:BroadcastScene.penalty,
                label:Text("zoom")
              ),
            ],
            onSelectionChanged:scenes.ready && !scenes.changing
              ?(selection)=>scenes.changeScene(selection.first):null,
            style:SegmentedButton.styleFrom(
              side:BorderSide(color:Colors.red),
            )
          )),
        ])),
        Expanded(flex:40,child:Column(spacing:6,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          //SizedBox(height:8),
          //TOP BAR
          Row(spacing:5,children:[
            _buildBroadcastControl(),
            const Spacer(),
            Tooltip(
              message:_audioMuted?'Activar micrófono':'Silenciar micrófono',
              child:GlintedButton(
                onPressed:scenes.ready&&!_changingAudio&&
                    state!=BroadcastState.connecting&&state!=BroadcastState.stopping
                  ?_toggleMicrophone:null,
                mainColor:_changingAudio?BroadcastColors.grey:
                  (_audioMuted?BroadcastColors.negative:BroadcastColors.positive),
                padding:EdgeInsets.all(5),
                borderRadius:BorderRadius.circular(10),
                child:Icon(_changingAudio?Icons.more_horiz:(_audioMuted?Icons.mic_off:Icons.mic)),
              ),
            ),
            GlintedButton(
              onPressed:(){},
              mainColor:Colors.yellow.shade700,
              padding:EdgeInsets.all(5),
              borderRadius:BorderRadius.circular(10),
              child:Icon(Icons.qr_code),
            ),
            GlintedButton(
              onPressed:scenes.ready && !scenes.changing &&
                  state!=BroadcastState.connecting && state!=BroadcastState.stopping
                ?_showSettings:null,
              mainColor:Colors.yellow,
              padding:EdgeInsets.all(5),
              borderRadius:BorderRadius.circular(10),
              child:Icon(Icons.settings),
            )
          ]),
          //INFO
          _buildInfo(),
          //GOLES
          Row(spacing:5,children:[
            Expanded(child:AspectRatio(aspectRatio:1,child:GlintedButton(
              onPressed:scenes.ready?()=>scenes.changeGoals(home:true,delta:1):null,
              mainColor:BroadcastColors.positive,
              child:Text("+1 L"),
            ))),
            Expanded(child:AspectRatio(aspectRatio:1,child:GlintedButton(
              onPressed:scenes.ready?()=>scenes.changeGoals(home:true,delta:-1):null,
              mainColor:BroadcastColors.negative,
              child:Text("-1 L")
            ))),
            Expanded(child:AspectRatio(aspectRatio:1,child:GlintedButton(
              onPressed:scenes.ready?()=>scenes.changeGoals(home:false,delta:1):null,
              mainColor:BroadcastColors.positive,
              child:Text("+1 V")
            ))),
            Expanded(child:AspectRatio(aspectRatio:1,child:GlintedButton(
              onPressed:scenes.ready?()=>scenes.changeGoals(home:false,delta:-1):null,
              mainColor:BroadcastColors.negative,
              child:Text("-1 V")
            ))),
          ]),
          //TIME
          Row(spacing:5,children:[
            Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
              onPressed:scenes.ready?()=>scenes.adjustTime(60):null,
              mainColor:BroadcastColors.positive,
              child:Text("+60s"),
            ))),
            Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
              onPressed:scenes.ready?()=>scenes.adjustTime(1):null,
              mainColor:BroadcastColors.positive,
              child:Text("+1s")
            ))),
            Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
              onPressed:scenes.ready?scenes.toggleClock:null,
              mainColor:scenes.running?BroadcastColors.negative:BroadcastColors.positive,
              child:Icon(scenes.running?Icons.pause:Icons.play_arrow),
            ))),
            Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
              onPressed:scenes.ready?()=>scenes.adjustTime(-60):null,
              mainColor:BroadcastColors.negative,
              child:Text("-60s")
            ))),
            Expanded(child:AspectRatio(aspectRatio:1/1.25,child:GlintedButton(
              onPressed:scenes.ready?()=>scenes.adjustTime(-1):null,
              mainColor:BroadcastColors.negative,
              child:Text("-1s")
            ))),
          ]),
        ])),
      ])
    ));
  }

  Widget _buildInfo(){
    if(scenes.ready&&scenes.error==null){
      return BroadcastInfo(homeGoals:scenes.homeGoals,awayGoals:scenes.awayGoals,time:scenes.time);
    }
    return AspectRatio(aspectRatio:4,child:GlintedButton(
      onPressed:!scenes.ready&&!scenes.changing?scenes.setup:null,
      mainColor:scenes.error==null?BroadcastColors.grey:BroadcastColors.negative,
      child:Text(scenes.error??'Preparando tanteador…',textAlign:TextAlign.center),
    ));
  }

  void _onScenesChanged(){
    if(mounted)setState((){});
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
      final modes=await availableVideoModes(rearCamera);
      if(!mounted)return;
      final initialSettings=BroadcastSettings.forModes(modes);
      await initialSettings.apply(_cameraController,streaming:false);
      if(!mounted)return;
      setState((){
        videoModes=modes;
        settings=initialSettings;
        _videoModesReady=true;
      });
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
          onPressed:scenes.ready && !scenes.changing?_startStreaming:null,
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

  Future<void> _showSettings()async{
    if(_settingsOpen)return;
    _settingsOpen=true;
    try{
      await showDialog<void>(
        context:context,barrierDismissible:false,barrierColor:Colors.black54,
        builder:(context)=>BroadcastSettingsDialog(
          settings:settings,modes:videoModes,camera:_cameraController,
          isLocked:()=>_settingsLocked,onApply:_applySettings,
        ),
      );
    }finally{
      _settingsOpen=false;
    }
  }

  Future<void> _applySettings(BroadcastSettings next)async{
    final previous=settings;
    final streaming=_settingsLocked;
    if(!videoModes.any((mode)=>mode==next.resolution && mode.frameRates.contains(next.fps))){
      throw ArgumentError('This resolution/FPS combination is not supported.');
    }
    if(streaming && (next.resolution!=previous.resolution || next.fps!=previous.fps)){
      throw StateError('Stop streaming before changing resolution or FPS.');
    }
    try{
      await next.apply(_cameraController,streaming:streaming);
    }catch(error){
      // A platform call can fail after changing part of the encoder configuration.
      try{
        await previous.apply(_cameraController,
          streaming:_settingsLocked);
      }catch(restoreError){
        debugPrint('Broadcast settings restore failed: $restoreError');
      }
      rethrow;
    }
    if(mounted){
      scenes.configureClock(countdown:next.countdown);
      setState((){
        settings=next;
        if(state==BroadcastState.failed && !streaming && _cameraError==null){
          state=BroadcastState.idle;
        }
      });
    }
  }

  Future<void> _toggleMicrophone()async{
    if(_changingAudio)return;
    final muted=!_audioMuted;
    setState((){_changingAudio=true;});
    try{
      await _cameraController.setAudioMuted(muted);
      if(!mounted)return;
      setState((){_audioMuted=muted;});
    }catch(error){
      debugPrint('Microphone toggle failed: $error');
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('No se pudo cambiar el estado del micrófono. Intentá nuevamente.'),
      ));
    }finally{
      if(mounted)setState((){_changingAudio=false;});
    }
  }

  void _startStreaming()async{
    setState((){state=BroadcastState.connecting;});
    try{
      await settings.apply(_cameraController,streaming:false);
      await _cameraController.startVideoStreaming(
        '$streamUrl/$streamKey',protocol:StreamingProtocol.rtmp,bitrate:settings.bitrate);
    }catch(error){
      debugPrint('No se pudo iniciar: $error');
      if(!mounted)return;
      setState((){state=BroadcastState.failed;});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('No se pudo iniciar la transmisión. Revisá la conexión y los ajustes de video.'),
      ));
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
