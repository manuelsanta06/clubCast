import 'elements.dart';

/// A flat group of elements, clipped to its bounds. Later elements draw on top.
/// All coordinates use a fixed 1280×720 landscape canvas, regardless of encoder size.
class OverlayModule{
  OverlayModule({
    required this.id,required this.width,required this.height,
    this.x=0,this.y=0,this.scale=1,this.opacity=1,this.zIndex=0,this.visible=true,
    List<OverlayElement> elements=const [],
  }):elements=List.unmodifiable(elements);

  final String id;
  final double width,height,x,y,scale,opacity;
  final int zIndex;
  final bool visible;
  final List<OverlayElement> elements;

  OverlayModule copyWith({
    double? x,double? y,double? scale,double? opacity,int? zIndex,bool? visible,
    List<OverlayElement>? elements,
  })=>OverlayModule(
    id:id,width:width,height:height,x:x??this.x,y:y??this.y,
    scale:scale??this.scale,opacity:opacity??this.opacity,
    zIndex:zIndex??this.zIndex,visible:visible??this.visible,
    elements:elements??this.elements,
  );

  Map<String,Object> placement(){
    checkNumber(x,'x',min:-100000,max:100000);
    checkNumber(y,'y',min:-100000,max:100000);
    checkNumber(scale,'scale',min:0.01,max:16);
    checkNumber(opacity,'opacity',min:0,max:1);
    if(zIndex.abs()>100000)throw ArgumentError.value(zIndex,'zIndex');
    return {'x':x,'y':y,'scale':scale,'opacity':opacity,'zIndex':zIndex,'visible':visible};
  }

  Map<String,Object> toMap(){
    checkId(id);
    checkSize(width,height);
    if(elements.length>128)throw ArgumentError('A module supports up to 128 elements.');
    if(elements.map((element)=>element.id).toSet().length!=elements.length){
      throw ArgumentError('Element IDs must be unique inside a module.');
    }
    return {'id':id,'width':width,'height':height,...placement(),
      'elements':elements.map((element)=>element.toMap()).toList()};
  }
}
