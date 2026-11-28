// ignore_for_file: file_names
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'scoreboard.dart';
import 'teamBadge.dart';

enum BroadcastScene{preMatch,match,penalty,halftime}

class SceneConfig{
  const SceneConfig({required this.zoom,required this.visibleModules,
    this.scoreboardScale=1,this.centerScoreboardX=false,this.message});

  final double zoom;
  final Set<String> visibleModules;
  final double scoreboardScale;
  final bool centerScoreboardX;
  final String? message;
}

class BroadcastScenes extends ChangeNotifier{
  BroadcastScenes(this.camera,{
    this.homeName='SAGAB',this.awayName='Gasoleras',
    this.homeBadge=const TeamBadge.asset('assets/teams/home.png'),
    this.awayBadge=const TeamBadge.asset('assets/teams/away.png'),
    Duration periodDuration=const Duration(minutes:25),
  }):_periodDuration=periodDuration{
    if(periodDuration<=Duration.zero)throw ArgumentError.value(periodDuration,'periodDuration');
  }

  final CameraController camera;
  final String homeName,awayName;
  final TeamBadge homeBadge,awayBadge;
  static const configs={
    BroadcastScene.preMatch:SceneConfig(zoom:1,visibleModules:{'sceneMessage'},message:'ya empieza'),
    BroadcastScene.match:SceneConfig(zoom:1,visibleModules:{'scoreboard'}),
    BroadcastScene.penalty:SceneConfig(zoom:2,visibleModules:{'scoreboard'}),
    BroadcastScene.halftime:SceneConfig(zoom:1,visibleModules:{'scoreboard','sceneMessage'},
      scoreboardScale:2,centerScoreboardX:true,message:'entretiempo'),
  };

  BroadcastScene scene=BroadcastScene.match;
  int homeGoals=0,awayGoals=0;
  bool ready=false,changing=false;
  String? error;

  final Stopwatch _clock=Stopwatch();
  Duration _elapsed=Duration.zero;
  Duration _periodDuration;
  bool _countdown=false;
  Timer? _timer;
  bool _disposed=false;
  String _lastTime='00:00';

  bool get running=>_clock.isRunning;
  bool get countdown=>_countdown;
  Duration get periodDuration=>_periodDuration;
  Duration get elapsed=>_elapsed+_clock.elapsed;
  String get score=>'$homeGoals – $awayGoals';
  String get time{
    final remaining=periodDuration-elapsed;
    final duration=countdown?(remaining.isNegative?Duration.zero:remaining):elapsed;
    // Round remaining time up so 25:00 stays visible during the first second.
    final seconds=countdown
      ?(duration.inMicroseconds+Duration.microsecondsPerSecond-1)~/Duration.microsecondsPerSecond
      :duration.inSeconds;
    return '${(seconds~/60).toString().padLeft(2,'0')}:${(seconds%60).toString().padLeft(2,'0')}';
  }

  Future<void> setup() async{
    if(_disposed||ready||changing)return;
    changing=true;
    error=null;
    notifyListeners();
    try{
      await homeBadge.load(camera.overlays,'homeBadge');
      if(_disposed)return;
      await awayBadge.load(camera.overlays,'awayBadge');
      if(_disposed)return;
      if(!camera.overlays.modules.containsKey('scoreboard')){
        await camera.overlays.add(createScoreboard(
          homeName:homeName,awayName:awayName,score:score,time:time,
        ));
      }
      if(_disposed)return;
      if(!camera.overlays.modules.containsKey('sceneMessage')){
        await camera.overlays.add(OverlayModule(
          id:'sceneMessage',width:260,height:64,x:32,y:720-64-32,visible:false,zIndex:10,
          elements:const [
            OverlayRect(id:'background',width:260,height:64,colorArgb:0xB010131D),
            OverlayText(id:'message',text:'ya empieza',x:12,y:7,width:236,height:50,
              fontSize:36,bold:true),
          ],
        ));
      }
      if(_disposed)return;
      ready=true;
      _lastTime=time;
    }catch(exception){
      if(!_disposed){
        error='No se pudo preparar el tanteador. Toca para reintentar.';
        debugPrint('Scoreboard setup failed: $exception');
      }
    }finally{
      changing=false;
      if(!_disposed)notifyListeners();
    }
  }

  Future<void> changeScene(BroadcastScene next)async{
    if(_disposed||!ready||changing||next==scene)return;
    changing=true;
    error=null;
    notifyListeners();
    final previous=configs[scene]!;
    try{
      final controls=await camera.getCameraControls();
      if(_disposed)return;
      await _apply(configs[next]!,controls);
      if(!_disposed)scene=next;
    }catch(exception){
      if(_disposed)return;
      debugPrint('Scene change failed: $exception');
      try{
        final controls=await camera.getCameraControls();
        if(!_disposed)await _apply(previous,controls);
      }catch(restoreError){
        debugPrint('Scene restore failed: $restoreError');
        if(!_disposed)error='No se pudo restaurar el encuadre. Volvé a abrir la pantalla.';
      }
      if(!_disposed)error??='No se pudo cambiar de escena. Intentá nuevamente.';
    }finally{
      changing=false;
      if(!_disposed)notifyListeners();
    }
  }

  Future<void> _apply(SceneConfig config,CameraControls controls) async{
    final zoom=config.zoom.clamp(controls.minZoom,controls.maxZoom).toDouble();
    await camera.setZoom(zoom);
    if(_disposed)return;
    final scoreboard=camera.overlays.modules['scoreboard']!;
    final scale=config.centerScoreboardX
      ?config.scoreboardScale.clamp(0.01,(1280-64)/scoreboard.width).toDouble()
      :config.scoreboardScale;
    final x=config.centerScoreboardX?(1280-scoreboard.width*scale)/2:32.0;
    const y=32.0;
    if(scoreboard.x!=x || scoreboard.y!=y || scoreboard.scale!=scale){
      await camera.overlays.place('scoreboard',x:x,y:y,scale:scale);
    }
    if(config.message!=null){
      await camera.overlays.setText('sceneMessage','message',config.message!);
    }
    // Reuse both modules; scene changes only update placement and visibility.
    for(final module in camera.overlays.modules.values){
      if(_disposed)return;
      final visible=config.visibleModules.contains(module.id);
      if(visible==module.visible)continue;
      if(visible){
        await camera.overlays.show(module.id);
      }else{
        await camera.overlays.hide(module.id);
      }
    }
  }

  void changeGoals({required bool home,required int delta}){
    if(_disposed || !ready)return;
    final goals=home?homeGoals:awayGoals;
    final next=goals+delta;
    if(next<0 || next==goals)return;
    if(home){
      homeGoals=next;
    }else{
      awayGoals=next;
    }
    notifyListeners();
    unawaited(_writeText('score',score));
  }

  void toggleClock(){
    if(_disposed || !ready)return;
    if(countdown && !running && elapsed>=periodDuration)return;
    if(running){
      _clock.stop();
      _timer?.cancel();
    }else{
      _clock.start();
      // The stopwatch measures elapsed time. The timer only refreshes its display.
      _timer=Timer.periodic(const Duration(milliseconds:200),(_)=>_refreshTime());
    }
    _refreshTime();
    notifyListeners();
  }

  void adjustTime(int seconds){
    if(_disposed || !ready)return;
    final adjusted=elapsed+Duration(seconds:countdown?-seconds:seconds);
    _elapsed=adjusted.isNegative?Duration.zero:
      (countdown && adjusted>periodDuration?periodDuration:adjusted);
    _clock.reset();
    _refreshTime();
  }

  void configureClock({required bool countdown,Duration? periodDuration}){
    if(_disposed)return;
    if(periodDuration!=null && periodDuration<=Duration.zero){
      throw ArgumentError.value(periodDuration,'periodDuration');
    }
    _periodDuration=periodDuration??_periodDuration;
    _countdown=countdown;
    _refreshTime();
    notifyListeners();
  }

  void _refreshTime(){
    if(_disposed)return;
    var stopped=false;
    if(countdown && elapsed>=periodDuration){
      stopped=running;
      _elapsed=periodDuration;
      _clock.stop();
      _clock.reset();
      _timer?.cancel();
    }
    final text=time;
    if(text==_lastTime && !stopped)return;
    _lastTime=text;
    notifyListeners();
    if(ready)unawaited(_writeText('clock',text));
  }

  Future<void> _writeText(String id,String text) async{
    try{
      await camera.overlays.setText('scoreboard',id,text);
    }catch(exception){
      if(_disposed)return;
      error='No se pudo actualizar el tanteador.';
      debugPrint('Scoreboard update failed: $exception');
      notifyListeners();
    }
  }

  @override
  void dispose(){
    _disposed=true;
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }
}
