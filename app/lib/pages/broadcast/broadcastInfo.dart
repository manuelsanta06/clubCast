// ignore_for_file: file_names
import 'package:flutter/material.dart';

class BroadcastInfo extends StatelessWidget{
  const BroadcastInfo({
    super.key,required this.homeGoals,required this.awayGoals,required this.time,
  });

  final int homeGoals,awayGoals;
  final String time;

  @override
  Widget build(BuildContext context){
    return AspectRatio(aspectRatio:4,child:LayoutBuilder(builder:(context,constraints){
      final scale=constraints.maxWidth/720;
      final radius=BorderRadius.circular(30*scale);
      return Container(
        padding:EdgeInsets.all(2*scale),
        decoration:BoxDecoration(
          borderRadius:radius,
          gradient:const LinearGradient(
            begin:Alignment.topLeft,end:Alignment.bottomRight,
            colors:[Color(0xFFA5BED5),Color(0xFF526577),Color(0xFF677E86)],
          ),
          boxShadow:[BoxShadow(color:const Color(0x203C759E),blurRadius:12*scale)],
        ),
        child:DecoratedBox(
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(28*scale),
            gradient:const LinearGradient(
              begin:Alignment.topCenter,end:Alignment.bottomCenter,
              colors:[Color(0xFF253344),Color(0xFF101620),Color(0xFF111C21)],
            ),
          ),
          child:Padding(
            padding:EdgeInsets.symmetric(horizontal:32*scale,vertical:14*scale),
            child:Row(children:[
              Expanded(child:_buildTeam('Local',homeGoals,scale,const [
                Color(0xFFDBE9FF),Color(0xFFA18AEB),Color(0xFFA6D9CB),
              ])),
              _buildDivider(scale),
              Expanded(child:Padding(
                padding:EdgeInsets.symmetric(horizontal:16*scale),
                child:Center(child:FittedBox(
                  fit:BoxFit.scaleDown,
                  child:Text(time,style:TextStyle(
                    color:const Color(0xFFF5F5F7),fontSize:46*scale,
                    fontWeight:FontWeight.w800,height:1.1,
                    fontFeatures:const [FontFeature.tabularFigures()],
                  )),
                )),
              )),
              _buildDivider(scale),
              Expanded(child:_buildTeam('Visitante',awayGoals,scale,const [
                Color(0xFFDDF9FF),Color(0xFF8BAAD9),Color(0xFFC9EFF0),
              ])),
            ]),
          ),
        ),
      );
    }));
  }

  Widget _buildTeam(String label,int goals,double scale,List<Color> borderColors){
    return Column(children:[
      SizedBox(height:6*scale),
      SizedBox(height:36*scale,child:FittedBox(
        fit:BoxFit.scaleDown,
        child:Text(label,style:TextStyle(
          color:const Color(0xFFF5F5F7),fontSize:32*scale,
          fontWeight:FontWeight.w700,height:1.1,
        )),
      )),
      SizedBox(height:10*scale),
      Container(
        width:136*scale,height:88*scale,
        padding:EdgeInsets.all(2.5*scale),
        decoration:BoxDecoration(
          borderRadius:BorderRadius.circular(21*scale),
          gradient:LinearGradient(
            begin:Alignment.topLeft,end:Alignment.bottomRight,colors:borderColors,
          ),
          boxShadow:[BoxShadow(
            color:borderColors.first.withValues(alpha:0.15),blurRadius:10*scale,
          )],
        ),
        child:DecoratedBox(
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(18.5*scale),
            gradient:const LinearGradient(
              begin:Alignment.topCenter,end:Alignment.bottomCenter,
              colors:[Color(0xFF0C121E),Color(0xFF10191F)],
            ),
          ),
          child:Padding(
            padding:EdgeInsets.symmetric(horizontal:8*scale,vertical:4*scale),
            child:Center(child:FittedBox(
              fit:BoxFit.scaleDown,
              child:Text('$goals',style:TextStyle(
                color:const Color(0xFFF5F5F7),fontSize:58*scale,
                fontWeight:FontWeight.w800,height:1,
                fontFeatures:const [FontFeature.tabularFigures()],
              )),
            )),
          ),
        ),
      ),
    ]);
  }

  Widget _buildDivider(double scale){
    return Align(
      alignment:const Alignment(0,0.25),
      child:Container(width:2*scale,height:84*scale,decoration:const BoxDecoration(
        gradient:LinearGradient(
          begin:Alignment.topCenter,end:Alignment.bottomCenter,
          colors:[Color(0x508C979F),Color(0xA08C979F),Color(0x308C979F)],
        ),
      )),
    );
  }
}
