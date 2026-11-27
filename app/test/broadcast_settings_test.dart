import 'dart:async';
import 'package:app/pages/broadcast/broadcastSettings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel=MethodChannel('com.rtmp_streaming');
  final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late CameraController camera;
  late List<MethodCall> calls;
  late GlobalKey previewKey;
  late BroadcastSettings applied;
  const hd=CameraVideoMode(width:1280,height:720,frameRates:[15,24,25,30,50,60]);
  const fullHd=CameraVideoMode(width:1920,height:1080,frameRates:[15,24,25,30]);

  setUp((){
    camera=CameraController(ResolutionPreset.veryHigh);
    camera.value=camera.value.copyWith(isInitialized:true);
    calls=[];
    previewKey=GlobalKey();
    applied=const BroadcastSettings(resolution:fullHd);
    messenger.setMockMethodCallHandler(channel,(call) async{calls.add(call);return null;});
  });

  tearDown(() async{
    await camera.dispose();
    messenger.setMockMethodCallHandler(channel,null);
  });

  Future<void> open(WidgetTester tester,{bool Function()? isLocked}) async{
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(
      body:Column(children:[
        StatefulBuilder(key:previewKey,builder:(context,setState)=>const Text('Preview')),
        ElevatedButton(onPressed:()=>showDialog<void>(
          context:context,barrierDismissible:false,
          builder:(context)=>BroadcastSettingsDialog(
            settings:applied,modes:const [hd,fullHd],camera:camera,
            isLocked:isLocked??()=>camera.value.isStreaming==true,
            onApply:(next) async{
              await next.apply(camera,streaming:camera.value.isStreaming==true);
              applied=next;
            },
          ),
        ),child:const Text('Open')),
      ]),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> select720p(WidgetTester tester) async{
    await tester.tap(find.byType(DropdownButtonFormField<CameraVideoMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('720p (1280×720)').last);
    await tester.pumpAndSettle();
  }

  test('defaults prefer 720p even when a higher resolution is available',(){
    final settings=BroadcastSettings.forModes(const [fullHd,hd]);
    expect(settings.resolution,hd);
    expect(settings.fps,30);
    expect(const BroadcastSettings().resolution,hd);
  });

  test('devices below 720p use their largest mode and supported FPS',(){
    const small=CameraVideoMode(width:320,height:240,frameRates:[15,30]);
    const largest=CameraVideoMode(width:640,height:480,frameRates:[10,15]);
    final settings=BroadcastSettings.forModes(const [largest,small]);
    expect(settings.resolution,largest);
    expect(settings.fps,15);
    expect(()=>BroadcastSettings.forModes(const []),throwsStateError);
  });

  test('channel modes preserve arbitrary device sizes and frame rates',(){
    final mode=CameraVideoMode.fromMap({'width':640.0,'height':480,'frameRates':[10,15.0,30]});
    expect(mode.label,'480p (640×480)');
    expect(mode.frameRates,[10,15,30]);
    expect(mode.preferredFrameRate(25),15);
  });

  test('idle settings send resolution, FPS and bitrate in one call',() async{
    await const BroadcastSettings(resolution:hd,fps:25,bitrateKbps:2500)
      .apply(camera,streaming:false);
    expect(calls.single.method,'setVideoSettings');
    final args=calls.single.arguments as Map;
    expect(args['width'],1280);
    expect(args['height'],720);
    expect(args['expectedFrameRate'],25.0);
    expect(args['bitrate'],2500000);
  });

  test('live settings send bitrate without reconfiguring resolution or FPS',() async{
    await const BroadcastSettings(bitrateKbps:3200).apply(camera,streaming:true);
    final args=calls.single.arguments as Map;
    expect(args['bitrate'],3200000);
    expect(args['width'],isNull);
    expect(args['height'],isNull);
    expect(args['expectedFrameRate'],isNull);
    expect(calls.map((call)=>call.method),['setVideoSettings']);
  });

  testWidgets('cancel keeps current settings and the underlying view mounted',(tester) async{
    await open(tester);
    final preview=previewKey.currentState!;
    await select720p(tester);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(2500);
    await tester.pump();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(BroadcastSettingsDialog),findsNothing);
    expect(previewKey.currentState,same(preview));
    expect(preview.mounted,isTrue);
    expect(applied.resolution,fullHd);
    expect(applied.bitrateKbps,1200);
    expect(calls,isEmpty);
  });

  testWidgets('apply saves edited values and leaves the underlying view mounted',(tester) async{
    await open(tester);
    final preview=previewKey.currentState!;
    await select720p(tester);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25 FPS').last);
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(2500);
    await tester.pump();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied.resolution,hd);
    expect(applied.fps,25);
    expect(applied.bitrateKbps,2500);
    expect(previewKey.currentState,same(preview));
    expect(preview.mounted,isTrue);
    expect(find.byType(BroadcastSettingsDialog),findsNothing);
  });

  testWidgets('live dialog locks resolution and FPS but allows bitrate',(tester) async{
    camera.value=camera.value.copyWith(isStreaming:true);
    await open(tester);
    expect(tester.widget<DropdownButtonFormField<CameraVideoMode>>(
      find.byType(DropdownButtonFormField<CameraVideoMode>)).onChanged,isNull);
    expect(tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>)).onChanged,isNull);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(3000);
    await tester.pump();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied.bitrateKbps,3000);
    expect((calls.single.arguments as Map)['width'],isNull);
    expect((calls.single.arguments as Map)['expectedFrameRate'],isNull);
  });

  testWidgets('countdown can be saved live without changing capture settings',(tester) async{
    camera.value=camera.value.copyWith(isStreaming:true);
    await open(tester);
    final toggle=find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(toggle).onChanged,isNotNull);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(applied.countdown,isFalse);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied.countdown,isTrue);
    expect((calls.single.arguments as Map)['width'],isNull);
    expect((calls.single.arguments as Map)['expectedFrameRate'],isNull);
  });

  testWidgets('cancel discards clock mode changes',(tester) async{
    await open(tester);
    final toggle=find.byType(SwitchListTile);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(applied.countdown,isFalse);
    expect(calls,isEmpty);
  });

  testWidgets('changing from 720p60 to 1080p limits the FPS selection to 30',(tester) async{
    applied=const BroadcastSettings(resolution:hd,fps:60);
    await open(tester);
    await tester.tap(find.byType(DropdownButtonFormField<CameraVideoMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(fullHd.label).last);
    await tester.pumpAndSettle();
    final field=tester.widget<DropdownButtonFormField<int>>(find.byType(DropdownButtonFormField<int>));
    expect(field.initialValue,30);
    final dropdown=tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>));
    expect(dropdown.items!.map((item)=>item.value),[15,24,25,30]);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied.resolution,fullHd);
    expect(applied.fps,30);
    expect((calls.single.arguments as Map)['expectedFrameRate'],30.0);
  });

  testWidgets('a stream starting while the dialog is open locks drafted capture changes',(tester) async{
    await open(tester);
    await select720p(tester);
    camera.value=camera.value.copyWith(isStreaming:true);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<CameraVideoMode>>(
      find.byType(DropdownButtonFormField<CameraVideoMode>)).onChanged,isNull);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied.resolution,fullHd);
    expect((calls.single.arguments as Map)['width'],isNull);
  });

  testWidgets('reconnecting keeps capture controls locked even if the native flag is false',(tester) async{
    await open(tester,isLocked:()=>true);
    expect(tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>)).onChanged,isNull);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged,isNotNull);
  });

  testWidgets('native errors retain the dialog and previous settings for a retry',(tester) async{
    var fail=true;
    messenger.setMockMethodCallHandler(channel,(call) async{
      if(fail)throw PlatformException(code:'settings',message:'Encoder rejected settings');
      calls.add(call);
      return null;
    });
    await open(tester);
    await select720p(tester);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron aplicar los ajustes. Intentá nuevamente.'),findsOneWidget);
    expect(applied.resolution,fullHd);
    fail=false;
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied.resolution,hd);
    expect(find.byType(BroadcastSettingsDialog),findsNothing);
  });

  testWidgets('saving blocks repeated submission and closing until native completion',(tester) async{
    final gate=Completer<void>();
    messenger.setMockMethodCallHandler(channel,(call) async{
      calls.add(call);
      await gate.future;
      return null;
    });
    await open(tester);
    await tester.tap(find.text('Aplicar'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged,isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'Cancelar')).onPressed,isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(BroadcastSettingsDialog),findsOneWidget);
    expect(calls,hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BroadcastSettingsDialog),findsNothing);
  });
}
