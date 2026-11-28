import 'dart:async';
import 'dart:io';
import 'package:app/pages/broadcast/broadcastScenes.dart';
import 'package:app/pages/broadcast/teamBadge.dart';
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

  test('setup loads badges once before creating the scoreboard and starts paused',() async{
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
    expect(calls,hasLength(4));
    expect(calls.map((call)=>(call.arguments as Map)['action']),['image','image','add','add']);
    for(final call in calls.take(2)){
      final args=call.arguments as Map;
      expect(args['maxWidth'],64);
      expect(args['maxHeight'],64);
      expect(args['trimTransparent'],isTrue);
      expect(args['padToBounds'],isTrue);
    }
    final module=camera.overlays.modules['scoreboard']!;
    expect(module.elements.map((element)=>element.id),containsAll(['homeBadge','awayBadge','score','clock']));
    expect(module.elements.whereType<OverlayImage>().map((image)=>image.imageId),['homeBadge','awayBadge']);
    expect(module.elements.whereType<OverlayText>().firstWhere((text)=>text.id=='awayName').text,'GASOLERAS');
    expect(camera.overlays.modules['sceneMessage']!.visible,isFalse);
  });

  test('pre-match shows the starting message at bottom left and retains match data',() async{
    await scenes.setup();
    scenes.changeGoals(home:true,delta:2);
    scenes.adjustTime(42);
    await settle();
    await scenes.changeScene(BroadcastScene.penalty);
    await scenes.changeScene(BroadcastScene.preMatch);
    final message=camera.overlays.modules['sceneMessage']!;
    expect(message.visible,isTrue);
    expect(message.x,32);
    expect(message.y+message.height,720-32);
    expect(message.elements.whereType<OverlayText>().single.text,'ya empieza');
    expect(camera.overlays.modules['scoreboard']!.visible,isFalse);
    expect(calls.where((call)=>call.method=='setZoom').last.arguments,{'zoom':1.0});
    scenes.changeGoals(home:false,delta:1);
    await settle();
    await scenes.changeScene(BroadcastScene.match);
    expect(camera.overlays.modules['sceneMessage']!.visible,isFalse);
    expect(camera.overlays.modules['scoreboard']!.visible,isTrue);
    expect(scenes.score,'2 – 1');
    expect(scenes.time,'00:42');
  });

  test('halftime centers horizontally at the top, shows its message and restores match placement',() async{
    await scenes.setup();
    final original=camera.overlays.modules['scoreboard']!;
    calls.clear();
    await scenes.changeScene(BroadcastScene.halftime);
    final centered=camera.overlays.modules['scoreboard']!;
    expect(centered.scale,greaterThan(1));
    expect(centered.scale,lessThanOrEqualTo(2));
    expect(centered.x+centered.width*centered.scale/2,640);
    expect(centered.y,32);
    expect(centered.elements,original.elements);
    expect(calls.where((call)=>call.method=='overlayCommand' && (call.arguments as Map)['id']=='scoreboard')
      .map((call)=>(call.arguments as Map)['action']),['place']);
    final message=camera.overlays.modules['sceneMessage']!;
    expect(message.visible,isTrue);
    expect(message.x,32);
    expect(message.y+message.height,720-32);
    expect(message.elements.whereType<OverlayText>().single.text,'entretiempo');
    scenes.changeGoals(home:true,delta:1);
    scenes.adjustTime(60);
    await settle();
    await scenes.changeScene(BroadcastScene.match);
    final restored=camera.overlays.modules['scoreboard']!;
    expect(restored.x,original.x);
    expect(restored.y,original.y);
    expect(restored.scale,1);
    expect(restored.visible,isTrue);
    expect(camera.overlays.modules['sceneMessage']!.visible,isFalse);
    expect(restored.elements.whereType<OverlayText>().firstWhere((text)=>text.id=='score').text,'1 – 0');
    expect(restored.elements.whereType<OverlayText>().firstWhere((text)=>text.id=='clock').text,'01:00');
    await scenes.changeScene(BroadcastScene.preMatch);
    expect(camera.overlays.modules['sceneMessage']!.elements.whereType<OverlayText>().single.text,'ya empieza');
  });

  test('long team names keep the enlarged halftime scoreboard inside the frame',() async{
    scenes.dispose();
    scenes=BroadcastScenes(camera,
      homeName:List.filled(200,'A').join(),awayName:List.filled(200,'B').join());
    await scenes.setup();
    await scenes.changeScene(BroadcastScene.halftime);
    final scoreboard=camera.overlays.modules['scoreboard']!;
    expect(scoreboard.scale,lessThan(2));
    expect(scoreboard.x,greaterThanOrEqualTo(32));
    expect(scoreboard.x+scoreboard.width*scoreboard.scale,lessThanOrEqualTo(1248));
  });

  test('a partial scene change restores placement and visibility on failure',() async{
    await scenes.setup();
    await scenes.changeScene(BroadcastScene.halftime);
    final original=camera.overlays.modules['scoreboard']!;
    var fail=true;
    messenger.setMockMethodCallHandler(channel,(call) async{
      if(call.method=='overlayCommand'){
        final args=call.arguments as Map;
        if(fail && args['action']=='place' && args['visible']==false){
          fail=false;
          throw PlatformException(code:'test',message:'Visibility failed');
        }
      }
      return respond(call);
    });
    await scenes.changeScene(BroadcastScene.preMatch);
    expect(scenes.scene,BroadcastScene.halftime);
    expect(scenes.error,isNotNull);
    final restored=camera.overlays.modules['scoreboard']!;
    expect(restored.x,original.x);
    expect(restored.y,original.y);
    expect(restored.scale,original.scale);
    expect(restored.visible,isTrue);
    expect(camera.overlays.modules['sceneMessage']!.visible,isTrue);
    expect(camera.overlays.modules['sceneMessage']!.elements.whereType<OverlayText>().single.text,'entretiempo');
  });

  test('setup can retry after the second module fails without duplicating the scoreboard',() async{
    var fail=true;
    messenger.setMockMethodCallHandler(channel,(call) async{
      calls.add(call);
      if(call.method=='overlayCommand'){
        final args=call.arguments as Map;
        if(fail && args['action']=='add' && (args['module'] as Map)['id']=='sceneMessage'){
          fail=false;
          throw PlatformException(code:'test',message:'Module creation failed');
        }
      }
      return respond(call);
    });
    await scenes.setup();
    expect(scenes.ready,isFalse);
    expect(camera.overlays.modules.keys,['scoreboard']);
    await scenes.setup();
    expect(scenes.ready,isTrue);
    expect(camera.overlays.modules.keys,['scoreboard','sceneMessage']);
    expect(calls.where((call){
      if(call.method!='overlayCommand')return false;
      final args=call.arguments as Map;
      return args['action']=='add' && (args['module'] as Map)['id']=='scoreboard';
    }),hasLength(1));
  });

  test('rapid goal changes retain the latest score and cannot go below zero',() async{
    await scenes.setup();
    scenes.changeGoals(home:true,delta:-1);
    scenes.changeGoals(home:false,delta:-1);
    expect(calls,hasLength(4));
    scenes.changeGoals(home:true,delta:1);
    scenes.changeGoals(home:true,delta:1);
    scenes.changeGoals(home:false,delta:1);
    scenes.changeGoals(home:true,delta:-1);
    await settle();
    expect(scenes.score,'1 – 1');
    final text=camera.overlays.modules['scoreboard']!.elements.whereType<OverlayText>()
      .firstWhere((element)=>element.id=='score');
    expect(text.text,scenes.score);
    expect(calls.where((call)=>(call.arguments as Map)['action']=='image'),hasLength(2));
  });

  test('downloaded badge files use the same normalization as bundled assets',() async{
    final directory=await Directory.systemTemp.createTemp('clubcast-badge-');
    try{
      final data=await rootBundle.load('assets/teams/home.png');
      final bytes=data.buffer.asUint8List(data.offsetInBytes,data.lengthInBytes);
      final file=await File('${directory.path}/badge.png').writeAsBytes(bytes);
      await TeamBadge.file(file.path).load(camera.overlays,'downloaded');
      final args=calls.single.arguments as Map;
      expect(args['id'],'downloaded');
      expect(args['bytes'],bytes);
      expect(args['maxWidth'],64);
      expect(args['maxHeight'],64);
      expect(args['trimTransparent'],isTrue);
      expect(args['padToBounds'],isTrue);
    }finally{
      await directory.delete(recursive:true);
    }
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

  test('clock mode changes preserve played time and update the video overlay',() async{
    await scenes.setup();
    scenes.adjustTime(5*60);
    scenes.configureClock(countdown:true);
    await settle();
    expect(scenes.time,'20:00');
    expect(scenes.elapsed,const Duration(minutes:5));
    final clock=camera.overlays.modules['scoreboard']!.elements.whereType<OverlayText>()
      .firstWhere((element)=>element.id=='clock');
    expect(clock.text,'20:00');
    scenes.toggleClock();
    scenes.configureClock(countdown:false);
    expect(scenes.time,'05:00');
    expect(scenes.running,isTrue);
  });

  test('countdown corrections change visible time and stay within the period',() async{
    await scenes.setup();
    scenes.configureClock(countdown:true);
    expect(scenes.time,'25:00');
    scenes.adjustTime(-60);
    expect(scenes.time,'24:00');
    scenes.adjustTime(1);
    expect(scenes.time,'24:01');
    scenes.adjustTime(120);
    expect(scenes.time,'25:00');
    scenes.adjustTime(-30*60);
    expect(scenes.time,'00:00');
    scenes.toggleClock();
    expect(scenes.running,isFalse);
    scenes.adjustTime(1);
    expect(scenes.time,'00:01');
    await settle();
  });

  test('period duration can change before setup and while the clock is paused',() async{
    scenes.configureClock(countdown:true,periodDuration:const Duration(minutes:20));
    expect(calls,isEmpty);
    await scenes.setup();
    expect(scenes.time,'20:00');
    scenes.adjustTime(-60);
    scenes.configureClock(countdown:true,periodDuration:const Duration(minutes:30));
    expect(scenes.time,'29:00');
    expect(scenes.elapsed,const Duration(minutes:1));
    expect(()=>scenes.configureClock(countdown:true,periodDuration:Duration.zero),throwsArgumentError);
    await settle();
  });

  test('countdown rounds up, pauses at zero and can resume after correction',() async{
    await scenes.setup();
    scenes.configureClock(countdown:true,periodDuration:const Duration(seconds:1));
    scenes.toggleClock();
    expect(scenes.time,'00:01');
    await Future<void>.delayed(const Duration(milliseconds:1400));
    expect(scenes.time,'00:00');
    expect(scenes.elapsed,const Duration(seconds:1));
    expect(scenes.running,isFalse);
    await settle();
    final clock=camera.overlays.modules['scoreboard']!.elements.whereType<OverlayText>()
      .firstWhere((element)=>element.id=='clock');
    expect(clock.text,'00:00');
    scenes.adjustTime(1);
    scenes.toggleClock();
    expect(scenes.running,isTrue);
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
