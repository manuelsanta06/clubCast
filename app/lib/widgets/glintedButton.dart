import 'package:flutter/material.dart';

class GlintedButton extends StatelessWidget{
  final VoidCallback onPressed;

  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  final Color mainColor;
  final Widget child;

  const GlintedButton({
    super.key,
    required this.onPressed,
    required this.mainColor,
    required this.child,
    this.borderRadius=const BorderRadius.all(Radius.circular(20)),
    this.padding=EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context){
    return Material(
      color:Colors.transparent,
      child:Ink(
        decoration:BoxDecoration(
          gradient:LinearGradient(
            begin:Alignment.topCenter,
            end:Alignment.bottomCenter,
            colors:[
              Color.lerp(mainColor,Colors.white,0.25)!,
              mainColor,
              Color.lerp(mainColor,Colors.black,0.30)!,
            ],
            //stops:const[0.0,0.35,1.0],
          ),
          borderRadius:borderRadius,
          border:Border.all(
            color:Colors.white24,
            width:1.5,
          ),
          boxShadow:[
            BoxShadow(
              color:mainColor.withValues(alpha:0.2),
              blurRadius:14,
              offset:Offset(0,5),
            ),
          ],
        ),
        child:InkWell(
          borderRadius:borderRadius,
          onTap:onPressed,
          child:Padding(
            padding:padding,
            child:Center(child:child)
          ),
        ),
      ),
    );
  }
}
