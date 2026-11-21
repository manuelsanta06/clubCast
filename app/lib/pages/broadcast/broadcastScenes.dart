// ignore_for_file: file_names
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

enum BroadcastScene{match,penalty}

class SceneConfig{
  const SceneConfig({required this.zoom,required this.visibleModules});

  final double zoom;
  final Set<String> visibleModules;
}

class BroadcastScenes extends ChangeNotifier{
  BroadcastScenes(this.camera);

  final CameraController camera;
  static const configs={
    BroadcastScene.match:SceneConfig(zoom:1,visibleModules:{'scoreboard'}),
    BroadcastScene.penalty:SceneConfig(zoom:2,visibleModules:{'scoreboard'}),
  };

  BroadcastScene scene=BroadcastScene.match;
  int homeGoals=0,awayGoals=0;
  bool ready=false,changing=false;
  String? error;

  final Stopwatch _clock=Stopwatch();
  Duration _elapsed=Duration.zero;
  Timer? _timer;
  bool _disposed=false;
  String _lastTime='00:00';

  bool get running=>_clock.isRunning;
  Duration get elapsed=>_elapsed+_clock.elapsed;
  String get score=>'$homeGoals – $awayGoals';
  String get time{
    final seconds=elapsed.inSeconds;
    return '${(seconds~/60).toString().padLeft(2,'0')}:${(seconds%60).toString().padLeft(2,'0')}';
  }

  Future<void> setup() async{
    if(_disposed || ready || changing)return;
    changing=true;
    error=null;
    notifyListeners();
    try{
      await camera.overlays.add(OverlayModule(
        id:'scoreboard',width:400,height:116,x:32,y:32,zIndex:10,
        elements:[
          const OverlayRect(id:'background',width:400,height:116,colorArgb:0xE610131D),
          const OverlayRect(id:'accent',width:400,height:4,colorArgb:0xFF7656B3),
          // Reserved space for the two club badges.
          const OverlayRect(id:'homeBadge',x:12,y:20,width:52,height:52,colorArgb:0xFF30374B),
          const OverlayRect(id:'awayBadge',x:336,y:20,width:52,height:52,colorArgb:0xFF30374B),
          const OverlayText(id:'homeName',text:'LOCAL',x:72,y:8,width:100,height:24,
            fontSize:18,align:OverlayTextAlign.center),
          const OverlayText(id:'awayName',text:'VISITANTE',x:228,y:8,width:100,height:24,
            fontSize:18,align:OverlayTextAlign.center),
          OverlayText(id:'score',text:score,x:72,y:30,width:256,height:50,
            fontSize:40,bold:true,align:OverlayTextAlign.center),
          OverlayText(id:'clock',text:time,x:144,y:78,width:112,height:32,
            fontSize:24,align:OverlayTextAlign.center),
        ],
      ));
      if(_disposed)return;
      ready=true;
      _lastTime=time;
    }catch(exception){
      if(!_disposed){
        error='No se pudo preparar el tanteador. Tocá para reintentar.';
        debugPrint('Scoreboard setup failed: $exception');
      }
    }finally{
      changing=false;
      if(!_disposed)notifyListeners();
    }
  }

  Future<void> changeScene(BroadcastScene next) async{
    if(_disposed || !ready || changing || next==scene)return;
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
    // Currently both scenes share one module. Only send visibility changes when needed.
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
    final adjusted=elapsed+Duration(seconds:seconds);
    _elapsed=adjusted.isNegative?Duration.zero:adjusted;
    _clock.reset();
    _refreshTime();
  }

  void _refreshTime(){
    if(_disposed)return;
    final text=time;
    if(text==_lastTime)return;
    _lastTime=text;
    notifyListeners();
    unawaited(_writeText('clock',text));
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
