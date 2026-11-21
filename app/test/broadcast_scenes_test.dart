import 'dart:async';
import 'package:app/pages/broadcast/broadcastScenes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel=MethodChannel('com.rtmp_streaming');
  final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late CameraController camera;
  late BroadcastScenes scenes;
  late List<MethodCall> calls;

  Object? respond(MethodCall call){
    if(call.method=='getCameraControls'){
      return {'zoom':1.0,'minZoom':1.0,'maxZoom':4.0,'autoFocus':true,'exposure':0,'torch':false};
    }
    return null;
  }

  Future<void> settle()=>Future<void>.delayed(Duration.zero);

  setUp((){
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    calls=[];
    camera=CameraController(ResolutionPreset.high);
    camera.value=camera.value.copyWith(isInitialized:true);
    scenes=BroadcastScenes(camera);
    messenger.setMockMethodCallHandler(channel,(call) async{
      calls.add(call);
      return respond(call);
    });
  });

  tearDown(() async{
    scenes.dispose();
    await camera.dispose();
    messenger.setMockMethodCallHandler(channel,null);
    debugDefaultTargetPlatformOverride=null;
  });

  test('setup creates one scoreboard with badge spaces and starts paused',() async{
    scenes.changeGoals(home:true,delta:1);
    scenes.toggleClock();
    expect(calls,isEmpty);
    await scenes.setup();
    await scenes.setup();
    expect(scenes.ready,isTrue);
    expect(scenes.scene,BroadcastScene.match);
    expect(scenes.score,'0 – 0');
    expect(scenes.time,'00:00');
    expect(scenes.running,isFalse);
    expect(calls,hasLength(1));
    final module=camera.overlays.modules['scoreboard']!;
    expect(module.elements.map((element)=>element.id),containsAll(['homeBadge','awayBadge','score','clock']));
  });

  test('rapid goal changes retain the latest score and cannot go below zero',() async{
    await scenes.setup();
    scenes.changeGoals(home:true,delta:-1);
    scenes.changeGoals(home:false,delta:-1);
    expect(calls,hasLength(1));
    scenes.changeGoals(home:true,delta:1);
    scenes.changeGoals(home:true,delta:1);
    scenes.changeGoals(home:false,delta:1);
    scenes.changeGoals(home:true,delta:-1);
    await settle();
    expect(scenes.score,'1 – 1');
    final text=camera.overlays.modules['scoreboard']!.elements.whereType<OverlayText>()
      .firstWhere((element)=>element.id=='score');
    expect(text.text,scenes.score);
  });

  test('time corrections work while paused, preserve minutes and clamp at zero',() async{
    await scenes.setup();
    scenes.adjustTime(60);
    scenes.adjustTime(1);
    expect(scenes.time,'01:01');
    scenes.adjustTime(-1);
    expect(scenes.time,'01:00');
    scenes.adjustTime(-120);
    expect(scenes.time,'00:00');
    scenes.adjustTime(100*60);
    await settle();
    expect(scenes.time,'100:00');
    expect(scenes.running,isFalse);
  });

  test('clock measures elapsed time, preserves running status during corrections and pauses',() async{
    await scenes.setup();
    scenes.toggleClock();
    scenes.adjustTime(60);
    expect(scenes.running,isTrue);
    await Future<void>.delayed(const Duration(milliseconds:1250));
    scenes.toggleClock();
    expect(scenes.elapsed.inSeconds,greaterThanOrEqualTo(61));
    final paused=scenes.elapsed;
    await Future<void>.delayed(const Duration(milliseconds:250));
    expect(scenes.elapsed,paused);
    expect(scenes.running,isFalse);
    await settle();
    final text=camera.overlays.modules['scoreboard']!.elements.whereType<OverlayText>()
      .firstWhere((element)=>element.id=='clock');
    expect(text.text,scenes.time);
  });

  test('penalty changes camera zoom while retaining scoreboard and clock state',() async{
    await scenes.setup();
    scenes.changeGoals(home:true,delta:1);
    scenes.adjustTime(42);
    await settle();
    final scoreboard=camera.overlays.modules['scoreboard'];
    await scenes.changeScene(BroadcastScene.penalty);
    expect(scenes.scene,BroadcastScene.penalty);
    expect(calls.last.method,'setZoom');
    expect(calls.last.arguments,{'zoom':2.0});
    expect(camera.overlays.modules['scoreboard'],same(scoreboard));
    expect(scenes.score,'1 – 0');
    expect(scenes.time,'00:42');
    await scenes.changeScene(BroadcastScene.match);
    expect(calls.last.arguments,{'zoom':1.0});
    expect(scenes.scene,BroadcastScene.match);
  });

  test('zoom respects the device range',() async{
    await scenes.setup();
    messenger.setMockMethodCallHandler(channel,(call) async{
      calls.add(call);
      if(call.method=='getCameraControls'){
        return {'zoom':1.0,'minZoom':1.0,'maxZoom':1.5,'autoFocus':true,'exposure':0,'torch':false};
      }
      return null;
    });
    await scenes.changeScene(BroadcastScene.penalty);
    expect(calls.last.arguments,{'zoom':1.5});
  });

  test('failed transitions restore the previous scene and report the error',() async{
    await scenes.setup();
    var fail=true;
    messenger.setMockMethodCallHandler(channel,(call) async{
      calls.add(call);
      if(call.method=='setZoom' && fail){
        fail=false;
        throw PlatformException(code:'test',message:'Zoom failed');
      }
      return respond(call);
    });
    await scenes.changeScene(BroadcastScene.penalty);
    expect(scenes.scene,BroadcastScene.match);
    expect(scenes.changing,isFalse);
    expect(scenes.error,isNotNull);
    expect(calls.last.arguments,{'zoom':1.0});
    await scenes.changeScene(BroadcastScene.penalty);
    expect(scenes.scene,BroadcastScene.penalty);
    expect(scenes.error,isNull);
  });

  test('overlapping scene changes are ignored until the active request completes',() async{
    await scenes.setup();
    final gate=Completer<void>();
    messenger.setMockMethodCallHandler(channel,(call) async{
      calls.add(call);
      if(call.method=='setZoom')await gate.future;
      return respond(call);
    });
    final change=scenes.changeScene(BroadcastScene.penalty);
    await settle();
    expect(scenes.changing,isTrue);
    await scenes.changeScene(BroadcastScene.match);
    gate.complete();
    await change;
    expect(scenes.scene,BroadcastScene.penalty);
    expect(calls.where((call)=>call.method=='setZoom'),hasLength(1));
  });

  test('setup errors can be retried without enabling controls prematurely',() async{
    messenger.setMockMethodCallHandler(channel,(call) async{
      throw PlatformException(code:'test',message:'No native view');
    });
    await scenes.setup();
    expect(scenes.ready,isFalse);
    expect(scenes.error,isNotNull);
    messenger.setMockMethodCallHandler(channel,(call) async=>respond(call));
    await scenes.setup();
    expect(scenes.ready,isTrue);
    expect(scenes.error,isNull);
  });
}
