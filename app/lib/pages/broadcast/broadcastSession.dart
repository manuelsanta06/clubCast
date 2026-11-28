// ignore_for_file: file_names
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';
import 'broadcastSettings.dart';

enum BroadcastState{idle,connecting,live,reconnecting,stopping,failed}

class BroadcastSession extends ChangeNotifier{
  BroadcastSession(this.camera,{this.connectionTimeout=const Duration(minutes:2)}){
    _lastEvent=camera.value.event;
    camera.addListener(_onCameraChanged);
  }

  final CameraController camera;
  final Duration connectionTimeout;
  BroadcastState state=BroadcastState.idle;
  String? error;
  bool stopFailed=false;
  bool _disposed=false,_starting=false;
  int _generation=0;
  Object? _lastEvent;
  Timer? _timeout;
  Future<void>? _stopFuture;

  bool get active=>state==BroadcastState.connecting || state==BroadcastState.live ||
    state==BroadcastState.reconnecting;
  bool get busy=>_starting || state==BroadcastState.stopping;
  bool get canStart=>!_disposed && !busy && _stopFuture==null &&
    (state==BroadcastState.idle || state==BroadcastState.failed);
  bool _current(int generation)=>!_disposed && generation==_generation;

  Future<void> start({required String url,required BroadcastSettings settings}) async{
    if(!canStart)return;
    final cleanup=state==BroadcastState.failed || camera.value.isStreaming==true;
    final generation=++_generation;
    _starting=true;
    stopFailed=false;
    error=null;
    state=BroadcastState.connecting;
    _lastEvent=camera.value.event;
    _watchConnection(generation);
    notifyListeners();
    try{
      // A failed attempt can still have a native retry or surface restore pending.
      if(cleanup)await _stopNative();
      if(!_current(generation))return;
      await settings.apply(camera,streaming:false);
      if(!_current(generation))return;
      await camera.startVideoStreaming(url,protocol:StreamingProtocol.rtmp,bitrate:settings.bitrate);
      // Only a native success event confirms the connection, not this Future.
    }catch(exception){
      if(_current(generation)){
        debugPrint('Broadcast start failed: $exception');
        await _fail('No se pudo iniciar la transmisión. Revisá la conexión y tocá Reintentar.');
      }
    }finally{
      _starting=false;
      if(!_disposed)notifyListeners();
    }
  }

  Future<void> stop() async{
    if(_disposed || state==BroadcastState.stopping)return;
    final generation=++_generation;
    _timeout?.cancel();
    error=null;
    stopFailed=false;
    state=BroadcastState.stopping;
    notifyListeners();
    try{
      await _stopNative();
      if(_current(generation))state=BroadcastState.idle;
    }catch(exception){
      debugPrint('Broadcast stop failed: $exception');
      if(_current(generation)){
        state=BroadcastState.failed;
        stopFailed=true;
        error='No se pudo detener la transmisión. Tocá Reintentar detención.';
      }
    }
    if(_current(generation))notifyListeners();
  }

  Future<void> retry({required String url,required BroadcastSettings settings}) async{
    if(!canStart)return;
    // Retrying a failed stop must not start publishing again.
    if(stopFailed){
      await stop();
    }else{
      await start(url:url,settings:settings);
    }
  }

  Future<void> _stopNative()=>_stopFuture??=camera.stopVideoStreaming().whenComplete((){
    _stopFuture=null;
  });

  Future<void> _fail(String message) async{
    if(_disposed || !active)return;
    final generation=++_generation;
    _timeout?.cancel();
    state=BroadcastState.stopping;
    notifyListeners();
    try{
      await _stopNative();
    }catch(exception){
      debugPrint('Broadcast cleanup failed: $exception');
    }
    if(!_current(generation))return;
    error=message;
    state=BroadcastState.failed;
    notifyListeners();
  }

  void _watchConnection(int generation){
    _timeout?.cancel();
    // One deadline for the whole outage; repeated retry events cannot extend it.
    _timeout=Timer(connectionTimeout,(){
      if(_current(generation) && active){
        unawaited(_fail('La conexión tardó demasiado. Revisá internet y tocá Reintentar.'));
      }
    });
  }

  void _onCameraChanged(){
    final event=camera.value.event;
    // CameraValue retains the previous event when unrelated controls change.
    if(_disposed || event==null || identical(event,_lastEvent))return;
    _lastEvent=event;
    if(!active)return;
    switch(event['eventType']){
      case 'success':
        _timeout?.cancel();
        state=BroadcastState.live;
        notifyListeners();
        break;
      case 'rtmp_retry':
        if(state==BroadcastState.live)_watchConnection(_generation);
        state=BroadcastState.reconnecting;
        notifyListeners();
        break;
      case 'rtmp_stopped':
      case 'camera_closing':
      case 'error':
        debugPrint('Broadcast interrupted: $event');
        unawaited(_fail('La transmisión se interrumpió. Revisá la conexión y tocá Reintentar.'));
        break;
    }
  }

  @override
  void dispose(){
    _disposed=true;
    _generation++;
    _timeout?.cancel();
    camera.removeListener(_onCameraChanged);
    super.dispose();
  }
}
