/// Text is laid out inside its box, starting at its top edge.
enum OverlayTextAlign{left,center,right}

/// Coordinates are relative to the module's top-left corner, in reference pixels.
sealed class OverlayElement{
  const OverlayElement({required this.id,this.x=0,this.y=0});

  final String id;
  final double x,y;

  Map<String,Object> toMap();

  Map<String,Object> geometry(String type,double width,double height){
    checkId(id);
    checkNumber(x,'x',min:-100000,max:100000);
    checkNumber(y,'y',min:-100000,max:100000);
    checkSize(width,height);
    return {'id':id,'type':type,'x':x,'y':y,'width':width,'height':height};
  }
}

class OverlayText extends OverlayElement{
  const OverlayText({
    required super.id,required this.text,required this.width,required this.height,
    super.x,super.y,this.fontSize=32,this.colorArgb=0xFFFFFFFF,
    this.bold=false,this.align=OverlayTextAlign.left,
  });

  final String text;
  final double width,height,fontSize;
  final int colorArgb;
  final bool bold;
  final OverlayTextAlign align;

  OverlayText withText(String text)=>OverlayText(
    id:id,text:text,width:width,height:height,x:x,y:y,
    fontSize:fontSize,colorArgb:colorArgb,bold:bold,align:align,
  );

  @override
  Map<String,Object> toMap(){
    checkNumber(fontSize,'fontSize',min:1,max:720);
    checkColor(colorArgb);
    if(text.length>4096)throw ArgumentError('Overlay text is limited to 4096 characters.');
    return {...geometry('text',width,height),'text':text,'fontSize':fontSize,
      'colorArgb':colorArgb,'bold':bold,'align':align.name};
  }
}

class OverlayRect extends OverlayElement{
  const OverlayRect({
    required super.id,required this.width,required this.height,
    super.x,super.y,this.colorArgb=0xFFFFFFFF,
  });
  final double width,height;
  final int colorArgb;

  @override
  Map<String,Object> toMap(){
    checkColor(colorArgb);
    return {...geometry('rect',width,height),'colorArgb':colorArgb};
  }
}

class OverlayOval extends OverlayElement{
  const OverlayOval({
    required super.id,required this.width,required this.height,
    super.x,super.y,this.colorArgb=0xFFFFFFFF,
  });
  final double width,height;
  final int colorArgb;

  @override
  Map<String,Object> toMap(){
    checkColor(colorArgb);
    return {...geometry('oval',width,height),'colorArgb':colorArgb};
  }
}

/// x/y locate the bounding box, not the center.
class OverlayCircle extends OverlayElement{
  const OverlayCircle({required super.id,required this.radius,
    super.x,super.y,this.colorArgb=0xFFFFFFFF});
  final double radius;
  final int colorArgb;

  @override
  Map<String,Object> toMap(){
    checkColor(colorArgb);
    return {...geometry('oval',radius*2,radius*2),'colorArgb':colorArgb};
  }
}

/// The image is stretched into this box. Preserve its aspect ratio when sizing.
class OverlayImage extends OverlayElement{
  const OverlayImage({
    required super.id,required this.imageId,required this.width,required this.height,
    super.x,super.y,
  });
  final String imageId;
  final double width,height;

  @override
  Map<String,Object> toMap(){
    checkId(imageId);
    return {...geometry('image',width,height),'imageId':imageId};
  }
}

void checkId(String id){
  if(id.isEmpty || id.length>128)throw ArgumentError('IDs must contain 1–128 characters.');
}

void checkNumber(double value,String name,{double? min,double? max}){
  if(!value.isFinite || (min!=null && value<min) || (max!=null && value>max)){
    throw ArgumentError.value(value,name);
  }
}

void checkSize(double width,double height){
  checkNumber(width,'width',min:1,max:1280);
  checkNumber(height,'height',min:1,max:720);
}

void checkColor(int color){
  if(color<0 || color>0xFFFFFFFF)throw ArgumentError.value(color,'colorArgb');
}
