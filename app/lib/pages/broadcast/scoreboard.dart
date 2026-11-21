import 'package:flutter/painting.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

OverlayModule createScoreboard({
  required String homeName,required String awayName,
  required String score,required String time,
}){
  const height=44.0;
  const border=2.0;
  const badgeSize=26.0;
  const padding=10.0;
  const gap=8.0;
  const scoreWidth=112.0;
  const clockWidth=104.0;
  const fontSize=20.0;

  // Only measured during setup. Leave some room for Android's native font metrics.
  ({String text,double width}) teamLabel(String name){
    final painter=TextPainter(textDirection:TextDirection.ltr);
    double measure(String text){
      painter.text=TextSpan(text:text,style:const TextStyle(fontFamily:'Roboto',fontSize:fontSize));
      painter.layout();
      return painter.width;
    }

    var text=name.trim().toUpperCase();
    var width=measure(text);
    const maxWidth=340.0;
    if(width>maxWidth){
      final ellipsisWidth=measure('…');
      measure(text);
      final end=painter.getPositionForOffset(Offset(maxWidth-ellipsisWidth-8,0)).offset;
      text='${text.substring(0,end).trimRight()}…';
      width=measure(text);
    }
    painter.dispose();
    return (text:text,width:(width+8).ceilToDouble().clamp(40,maxWidth).toDouble());
  }

  final home=teamLabel(homeName);
  final away=teamLabel(awayName);
  final homeWidth=padding+badgeSize+gap+home.width+padding;
  final awayWidth=padding+away.width+gap+badgeSize+padding;
  final scoreX=border+homeWidth;
  final awayX=scoreX+scoreWidth;
  final clockX=awayX+awayWidth;
  final width=clockX+clockWidth+border;

  return OverlayModule(
    id:'scoreboard',width:width,height:height,x:32,y:32,zIndex:10,
    elements:[
      OverlayRect(id:'frame',width:width,height:height,colorArgb:0xFF5C778A),
      OverlayRect(id:'homeBackground',x:border,y:border,width:homeWidth,height:height-border*2,
        colorArgb:0xFF5C8B2B),
      OverlayRect(id:'scoreBackground',x:scoreX,y:border,width:scoreWidth,height:height-border*2,
        colorArgb:0xFFF2F4F5),
      OverlayRect(id:'awayBackground',x:awayX,y:border,width:awayWidth,height:height-border*2,
        colorArgb:0xFF294E70),
      OverlayRect(id:'clockBackground',x:clockX,y:border,width:clockWidth,height:height-border*2,
        colorArgb:0xFFF2F4F5),
      // Reserve badge space at the outside edge of each team's block.
      const OverlayRect(id:'homeBadge',x:border+padding,y:9,width:badgeSize,height:badgeSize,
        colorArgb:0x35FFFFFF),
      OverlayRect(id:'awayBadge',x:awayX+padding+away.width+gap,y:9,width:badgeSize,height:badgeSize,
        colorArgb:0x35FFFFFF),
      OverlayText(id:'homeName',text:home.text,x:border+padding+badgeSize+gap,y:10,
        width:home.width,height:28,fontSize:fontSize),
      OverlayText(id:'awayName',text:away.text,x:awayX+padding,y:10,
        width:away.width,height:28,fontSize:fontSize),
      OverlayText(id:'score',text:score,x:scoreX,y:6,width:scoreWidth,height:34,
        fontSize:26,bold:true,colorArgb:0xFF14212B,align:OverlayTextAlign.center),
      OverlayText(id:'clock',text:time,x:clockX,y:7,width:clockWidth,height:32,
        fontSize:24,colorArgb:0xFF14212B,align:OverlayTextAlign.center),
    ],
  );
}
