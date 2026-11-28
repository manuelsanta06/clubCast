import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel=MethodChannel('com.rtmp_streaming');
  final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late CameraController camera;
  late List<MethodCall> calls;

  OverlayModule scoreboard()=>OverlayModule(
    id:'scoreboard',width:320,height:80,x:20,y:30,
    elements:const [
      OverlayRect(id:'background',width:320,height:80,colorArgb:0x80000000),
      OverlayText(id:'score',text:'0–0',width:140,height:60,x:20,y:10,bold:true),
    ],
  );

  setUp((){
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    calls=[];
    camera=CameraController(ResolutionPreset.high);
    camera.value=camera.value.copyWith(isInitialized:true);
    messenger.setMockMethodCallHandler(channel,(call) async{calls.add(call);return null;});
  });
  tearDown(() async{
    await camera.dispose();
    messenger.setMockMethodCallHandler(channel,null);
    debugDefaultTargetPlatformOverride=null;
  });

  test('text patches preserve styling and placement never resends content',() async{
    await camera.overlays.add(scoreboard());
    await camera.overlays.setText('scoreboard','score','2–1');
    final element=camera.overlays.modules['scoreboard']!.elements[1] as OverlayText;
    expect(element.text,'2–1');
    expect(element.bold,isTrue);
    expect(element.x,20);
    final update=calls.last.arguments as Map;
    expect(update['action'],'elements');
    expect((update['elements'] as List).length,1);
    await camera.overlays.move('scoreboard',x:100,y:200);
    expect((calls.last.arguments as Map).containsKey('elements'),isFalse);
    expect(camera.overlays.modules['scoreboard']!.x,100);
    final count=calls.length;
    await camera.overlays.setText('scoreboard','score','2–1');
    expect(calls.length,count);
  });

  test('creation and edits are serialized even without intermediate awaits',() async{
    final gate=Completer<void>();
    messenger.setMockMethodCallHandler(channel,(call) async{
      calls.add(call);
      if((call.arguments as Map)['action']=='add')await gate.future;
      return null;
    });
    final creating=camera.overlays.add(scoreboard());
    final changing=camera.overlays.setText('scoreboard','score','1–0');
    await Future<void>.delayed(Duration.zero);
    expect(calls.length,1);
    expect(camera.overlays.modules,isEmpty);
    gate.complete();
    await Future.wait([creating,changing]);
    expect(calls.length,2);
    expect((camera.overlays.modules['scoreboard']!.elements[1] as OverlayText).text,'1–0');
  });

  test('combined placement sends one update and retains the existing elements',() async{
    await camera.overlays.add(scoreboard());
    final elements=camera.overlays.modules['scoreboard']!.elements;
    calls.clear();
    await camera.overlays.place('scoreboard',x:320,y:280,scale:2);
    final args=calls.single.arguments as Map;
    expect(args['action'],'place');
    expect(args['x'],320);
    expect(args['y'],280);
    expect(args['scale'],2);
    expect(args.containsKey('elements'),isFalse);
    expect(camera.overlays.modules['scoreboard']!.elements,elements);
    await expectLater(camera.overlays.place('scoreboard',x:0,y:0,scale:0),throwsArgumentError);
    expect(camera.overlays.modules['scoreboard']!.scale,2);
    expect(calls,hasLength(1));
  });

  test('failed updates preserve local state and do not poison later requests',() async{
    await camera.overlays.add(scoreboard());
    var fail=true;
    messenger.setMockMethodCallHandler(channel,(call) async{
      if(fail)throw PlatformException(code:'overlayError',message:'Unknown image');
      return null;
    });
    await expectLater(camera.overlays.setText('scoreboard','score','1–0'),throwsA(isA<CameraException>()));
    expect((camera.overlays.modules['scoreboard']!.elements[1] as OverlayText).text,'0–0');
    fail=false;
    await camera.overlays.setText('scoreboard','score','2–0');
    expect((camera.overlays.modules['scoreboard']!.elements[1] as OverlayText).text,'2–0');
  });

  test('hide variants are instant and show retains module content',() async{
    await camera.overlays.add(scoreboard());
    for(final hide in <Future<void> Function()>[
      ()=>camera.overlays.hide('scoreboard'),
      ()=>camera.overlays.fadeOut('scoreboard'),
      ()=>camera.overlays.slideOut('scoreboard',direction:OverlayDirection.right),
    ]){
      await hide();
      expect(camera.overlays.modules['scoreboard']!.visible,isFalse);
      await camera.overlays.show('scoreboard');
      expect(camera.overlays.modules['scoreboard']!.elements.length,2);
    }
  });

  test('batched changes retain element ordering and add new elements last',() async{
    await camera.overlays.add(scoreboard());
    await camera.overlays.setElements('scoreboard',const [
      OverlayText(id:'score',text:'3–2',width:140,height:60),
      OverlayCircle(id:'live',radius:8,x:290,y:20,colorArgb:0xFFFF0000),
    ]);
    expect(camera.overlays.modules['scoreboard']!.elements.map((element)=>element.id),
      ['background','score','live']);
    expect((calls.last.arguments as Map)['elements'],hasLength(2));
    await camera.overlays.removeElement('scoreboard','live');
    expect(camera.overlays.modules['scoreboard']!.elements,hasLength(2));
  });

  test('reject invalid input before passing it to native rendering',() async{
    await expectLater(camera.overlays.add(OverlayModule(id:'bad',width:double.nan,height:20)),throwsArgumentError);
    await expectLater(camera.overlays.add(OverlayModule(id:'bad',width:2000,height:20)),throwsArgumentError);
    await expectLater(camera.overlays.add(OverlayModule(id:'bad',width:20,height:20,elements:const [
      OverlayRect(id:'same',width:10,height:10),OverlayRect(id:'same',width:10,height:10),
    ])),throwsArgumentError);
    expect(calls,isEmpty);
    await camera.overlays.add(scoreboard());
    await expectLater(camera.overlays.add(scoreboard()),throwsStateError);
    await expectLater(camera.overlays.setOpacity('scoreboard',2),throwsArgumentError);
    await expectLater(camera.overlays.setText('scoreboard','background','oops'),throwsStateError);
    await expectLater(camera.overlays.move('missing',x:0,y:0),throwsStateError);
    expect(calls.length,1);
  });

  test('encoded image input is copied before asynchronous dispatch',() async{
    final bytes=Uint8List.fromList([1,2,3]);
    final loading=camera.overlays.loadImageBytes('logo',bytes,maxWidth:128,maxHeight:64);
    bytes[0]=9;
    await loading;
    expect((calls.single.arguments as Map)['bytes'],[1,2,3]);
    expect((calls.single.arguments as Map)['maxWidth'],128);
    await camera.overlays.add(scoreboard());
    await camera.overlays.clear();
    expect(camera.overlays.modules,isEmpty);
  });

  test('image byte limits reject oversized input without copying or native work',() async{
    await expectLater(camera.overlays.loadImageBytes('logo',Uint8List(0)),throwsArgumentError);
    await expectLater(camera.overlays.loadImageBytes('logo',Uint8List(8*1024*1024+1)),throwsArgumentError);
    expect(calls,isEmpty);
  });

  test('unsupported platform fails explicitly without native calls',() async{
    debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    await expectLater(camera.overlays.add(scoreboard()),throwsUnsupportedError);
    expect(calls,isEmpty);
  });

  test('initialization and disposal checks include queued operations',() async{
    camera.value=camera.value.copyWith(isInitialized:false);
    await expectLater(camera.overlays.add(scoreboard()),throwsA(isA<CameraException>()));
    camera.value=camera.value.copyWith(isInitialized:true);
    final adding=camera.overlays.add(scoreboard());
    await camera.dispose();
    await expectLater(adding,throwsStateError);
    expect(camera.overlays.modules,isEmpty);
    await expectLater(camera.overlays.show('scoreboard'),throwsStateError);
    expect(calls,isEmpty);
  });
}
