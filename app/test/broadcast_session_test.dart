import 'dart:async';
import 'package:app/pages/broadcast/broadcastScenes.dart';
import 'package:app/pages/broadcast/broadcastSession.dart';
import 'package:app/pages/broadcast/broadcastSettings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel=MethodChannel('com.rtmp_streaming');
  const events=EventChannel('com.rtmp_streaming.eventchannel/91');
  final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late CameraController camera;
  late BroadcastSession session;
  late MockStreamHandlerEventSink sink;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall) handler;
  const settings=BroadcastSettings();

  Future<void> settle()=>Future<void>.delayed(Duration.zero);
  Future<void> event(String type) async{
    sink.success({'eventType':type,'errorDescription':'test'});
    await settle();
  }
  Future<void> start()=>session.start(url:'rtmp://test.invalid/live/key',settings:settings);

  setUp(() async{
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    calls=[];
    handler=(_) async=>null;
    messenger.setMockStreamHandler(events,MockStreamHandler.inline(
      onListen:(_,eventSink){sink=eventSink;},
    ));
    messenger.setMockMethodCallHandler(channel,(call) async{
      calls.add(call);
      if(call.method=='initialize'){return {
        'textureId':1,'eventId':91,'previewWidth':1280,'previewHeight':720,
      };}
      if(call.method=='getCapabilities'){return {
        'backend':'test','protocols':['rtmp'],'videoCodecs':['h264'],'audioCodecs':['aac'],
        'features':<String,bool>{},
      };}
      return handler(call);
    });
    camera=CameraController(ResolutionPreset.high);
    await camera.initialize(CameraDescription(name:'0'));
    await Future<void>.microtask((){});
    session=BroadcastSession(camera);
    calls.clear();
  });

  tearDown(() async{
    session.dispose();
    await camera.dispose();
    messenger.setMockStreamHandler(events,null);
    messenger.setMockMethodCallHandler(channel,null);
    debugDefaultTargetPlatformOverride=null;
  });

  test('native start acceptance waits for connection success and sends 3000 kbps',() async{
    await start();
    expect(session.state,BroadcastState.connecting);
    expect(session.canStart,isFalse);
    final request=calls.firstWhere((call)=>call.method=='startVideoStreaming');
    expect((request.arguments as Map)['bitrate'],3000000);
    await event('success');
    expect(session.state,BroadcastState.live);
    await session.stop();
    expect(session.state,BroadcastState.idle);
    expect(session.canStart,isTrue);
  });

  test('automatic reconnection retains scoreboard and does not start a new session',() async{
    final scenes=BroadcastScenes(camera);
    await scenes.setup();
    scenes.changeGoals(home:true,delta:1);
    scenes.adjustTime(61);
    await settle();
    final scoreboard=camera.overlays.modules['scoreboard'];
    await start();
    await event('success');
    await event('rtmp_retry');
    expect(session.state,BroadcastState.reconnecting);
    await event('wait');
    expect(session.state,BroadcastState.reconnecting);
    await event('success');
    expect(session.state,BroadcastState.live);
    expect(scenes.score,'1 – 0');
    expect(scenes.time,'01:01');
    expect(camera.overlays.modules['scoreboard'],same(scoreboard));
    expect(calls.where((call)=>call.method=='startVideoStreaming'),hasLength(1));
    scenes.dispose();
  });

  test('terminal failure cleans native state and manual retry keeps the overlay',() async{
    final scenes=BroadcastScenes(camera);
    await scenes.setup();
    scenes.adjustTime(42);
    scenes.changeGoals(home:false,delta:2);
    await settle();
    final scoreboard=camera.overlays.modules['scoreboard'];
    await start();
    await event('success');
    await event('rtmp_stopped');
    expect(session.state,BroadcastState.failed);
    expect(session.error,isNotNull);
    expect(calls.last.method,'stopStreaming');
    calls.clear();
    await session.start(url:'rtmp://test.invalid/live/key',
      settings:const BroadcastSettings(bitrateKbps:4500));
    expect(calls.map((call)=>call.method),
      ['stopStreaming','setVideoSettings','getCapabilities','startVideoStreaming']);
    expect((calls.last.arguments as Map)['bitrate'],4500000);
    await event('success');
    expect(session.state,BroadcastState.live);
    expect(session.error,isNull);
    expect(scenes.score,'0 – 2');
    expect(scenes.time,'00:42');
    expect(camera.overlays.modules['scoreboard'],same(scoreboard));
    scenes.dispose();
  });

  test('duplicate starts do not create overlapping native sessions',() async{
    final entered=Completer<void>(),reply=Completer<void>();
    handler=(call) async{
      if(call.method=='startVideoStreaming'){
        entered.complete();
        await reply.future;
      }
      return null;
    };
    final first=start();
    await entered.future;
    await start();
    expect(calls.where((call)=>call.method=='startVideoStreaming'),hasLength(1));
    reply.complete();
    await first;
  });

  test('cancel during settings preparation prevents a late native start',() async{
    final entered=Completer<void>(),reply=Completer<void>();
    handler=(call) async{
      if(call.method=='setVideoSettings'){
        entered.complete();
        await reply.future;
      }
      return null;
    };
    final starting=start();
    await entered.future;
    await session.stop();
    expect(session.state,BroadcastState.idle);
    expect(session.canStart,isFalse);
    reply.complete();
    await starting;
    expect(calls.where((call)=>call.method=='startVideoStreaming'),isEmpty);
    expect(session.canStart,isTrue);
  });

  test('cancel during native start ignores late success and completion',() async{
    final entered=Completer<void>(),reply=Completer<void>();
    handler=(call) async{
      if(call.method=='startVideoStreaming'){
        entered.complete();
        await reply.future;
      }
      return null;
    };
    final starting=start();
    await entered.future;
    final stopping=session.stop();
    await event('success');
    expect(session.state,BroadcastState.stopping);
    reply.complete();
    await Future.wait([starting,stopping]);
    await event('success');
    await event('rtmp_retry');
    expect(session.state,BroadcastState.idle);
    expect(camera.value.isStreaming,isFalse);
  });

  test('controls retaining the last retry event cannot undo successful reconnection',() async{
    await start();
    await event('rtmp_retry');
    await event('success');
    camera.value=camera.value.copyWith(previewSize:const Size(1920,1080));
    expect(session.state,BroadcastState.live);
    await session.stop();
    await start();
    // The controller still retains the preceding success in CameraValue.event.
    expect(session.state,BroadcastState.connecting);
  });

  test('failed settings or start can be retried without recreating the controller',() async{
    handler=(call) async{
      if(call.method=='setVideoSettings')throw PlatformException(code:'test');
      return null;
    };
    await start();
    expect(session.state,BroadcastState.failed);
    expect(session.canStart,isTrue);
    expect(calls.last.method,'stopStreaming');
    handler=(_) async=>null;
    await start();
    await event('success');
    expect(session.state,BroadcastState.live);
  });

  test('failed stop must succeed before retry starts a replacement',() async{
    await start();
    await event('success');
    handler=(call) async{
      if(call.method=='stopStreaming')throw PlatformException(code:'stopFailed');
      return null;
    };
    await session.stop();
    expect(session.state,BroadcastState.failed);
    await start();
    expect(session.state,BroadcastState.failed);
    expect(calls.where((call)=>call.method=='startVideoStreaming'),hasLength(1));
    handler=(_) async=>null;
    await start();
    await event('success');
    expect(session.state,BroadcastState.live);
  });

  test('retrying a failed stop stops transmission without starting it again',() async{
    await start();
    await event('success');
    handler=(call) async{
      if(call.method=='stopStreaming')throw PlatformException(code:'stopFailed');
      return null;
    };
    await session.stop();
    expect(session.stopFailed,isTrue);
    handler=(_) async=>null;
    await session.retry(url:'rtmp://test.invalid/live/key',settings:settings);
    expect(session.state,BroadcastState.idle);
    expect(session.stopFailed,isFalse);
    expect(calls.where((call)=>call.method=='startVideoStreaming'),hasLength(1));
  });

  for(final type in ['error','camera_closing']){
    test('$type during a session stops capture and offers recovery',() async{
      await start();
      await event('success');
      await event(type);
      expect(session.state,BroadcastState.failed);
      expect(session.canStart,isTrue);
      expect(camera.value.isStreaming,isFalse);
      expect(calls.last.method,'stopStreaming');
    });
  }

  test('retry events cannot extend the deadline indefinitely',() async{
    session.dispose();
    session=BroadcastSession(camera,connectionTimeout:const Duration(milliseconds:300));
    await start();
    for(var i=0;i<2;i++){
      await Future<void>.delayed(const Duration(milliseconds:100));
      await event('rtmp_retry');
    }
    await Future<void>.delayed(const Duration(milliseconds:150));
    expect(session.state,BroadcastState.failed);
    expect(session.error,contains('tardó demasiado'));
    expect(camera.value.isStreaming,isFalse);
  });

  test('successful connections cancel the deadline and a new outage gets its own',() async{
    session.dispose();
    session=BroadcastSession(camera,connectionTimeout:const Duration(milliseconds:300));
    await start();
    await event('success');
    await Future<void>.delayed(const Duration(milliseconds:350));
    expect(session.state,BroadcastState.live);
    await event('rtmp_retry');
    await Future<void>.delayed(const Duration(milliseconds:350));
    expect(session.state,BroadcastState.failed);
  });
}
