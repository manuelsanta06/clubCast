import 'package:rtmp_streaming/rtmp_streaming.dart';

// Call once from an event after CameraPreview is mounted, never from build().
Future<void> createScoreboard(CameraController camera) async{
  await camera.overlays.add(OverlayModule(
    id:'scoreboard',width:360,height:100,x:32,y:32,zIndex:10,
    elements:const [
      OverlayRect(id:'background',width:360,height:100,colorArgb:0xD910131D),
      OverlayRect(id:'accent',width:8,height:100,colorArgb:0xFF7656B3),
      OverlayText(id:'home',text:'HOME',x:20,y:12,width:100,height:30,fontSize:22),
      OverlayText(id:'away',text:'AWAY',x:240,y:12,width:100,height:30,
        fontSize:22,align:OverlayTextAlign.right),
      OverlayText(id:'score',text:'0 – 0',x:100,y:10,width:160,height:50,
        fontSize:38,bold:true,align:OverlayTextAlign.center),
      OverlayText(id:'clock',text:'00:00',x:100,y:60,width:160,height:32,
        fontSize:24,align:OverlayTextAlign.center),
    ],
  ));
}

Future<void> updateScore(CameraController camera,int home,int away)=>
  camera.overlays.setText('scoreboard','score','$home – $away');

Future<void> updateClock(CameraController camera,Duration elapsed){
  final minutes=elapsed.inMinutes.toString().padLeft(2,'0');
  final seconds=(elapsed.inSeconds%60).toString().padLeft(2,'0');
  return camera.overlays.setText('scoreboard','clock','$minutes:$seconds');
}

// Keep the sponsor separate: clock updates then repaint only the scoreboard.
Future<void> createSponsor(CameraController camera,String asset) async{
  await camera.overlays.loadAssetImage('sponsorLogo',asset,maxWidth:200,maxHeight:80);
  await camera.overlays.add(OverlayModule(
    id:'sponsor',width:200,height:80,x:1048,y:608,visible:false,
    elements:const [OverlayImage(id:'logo',imageId:'sponsorLogo',width:200,height:80)],
  ));
  await camera.overlays.show('sponsor');
}
