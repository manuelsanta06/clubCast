import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'elements.dart';
import 'module.dart';

enum OverlayDirection{left,right,up,down}

/// Android overlay scene owned by a CameraController. Await operations; do not
/// call them from build(). Futures finish after native scene preparation, not
/// after a frame reaches the encoder or a remote viewer.
class OverlayModules{
  OverlayModules(this.send);

  @internal
  final Future<void> Function(Map<String,dynamic>) send;
  final Map<String,OverlayModule> _modules={};
  Future<void> _pending=Future.value();
  bool _closed=false;

  Map<String,OverlayModule> get modules=>Map.unmodifiable(_modules);

  Future<void> _run(Future<void> Function() action){
    final operation=_pending.then((_) async{
      if(_closed)throw StateError('The camera overlay scene has been disposed.');
      if(defaultTargetPlatform!=TargetPlatform.android){
        throw UnsupportedError('Overlay modules are implemented only on Android.');
      }
      await action();
    });
    _pending=operation.then<void>((_) {},onError:(Object error,StackTrace stack){});
    return operation;
  }

  OverlayModule _get(String id)=>_modules[id]??(throw StateError('Unknown module: $id'));

  Future<void> add(OverlayModule module)=>_run(() async{
    if(_modules.containsKey(module.id))throw StateError('Module already exists: ${module.id}');
    await send({'action':'add','module':module.toMap()});
    if(!_closed)_modules[module.id]=module;
  });

  /// Adds an element or replaces the element with the same ID, preserving order.
  Future<void> setElement(String id,OverlayElement element)=>_run(() async{
    await _setElements(id,[element]);
  });

  /// Batches changes into a single redraw, useful when both scores change.
  Future<void> setElements(String id,List<OverlayElement> elements){
    final snapshot=List<OverlayElement>.of(elements);
    return _run(() async{await _setElements(id,snapshot);});
  }

  Future<void> _setElements(String id,List<OverlayElement> elements) async{
    final current=_get(id);
    final combined={for(final element in current.elements)element.id:element};
    for(final element in elements){combined[element.id]=element;}
    final updated=current.copyWith(elements:combined.values.toList());
    updated.toMap();
    await send({'action':'elements','id':id,
      'elements':elements.map((element)=>element.toMap()).toList()});
    if(!_closed)_modules[id]=updated;
  }

  Future<void> setText(String id,String elementId,String text)=>_run(() async{
    final matches=_get(id).elements.where((element)=>element.id==elementId);
    if(matches.isEmpty || matches.first is! OverlayText){
      throw StateError('$elementId is not a text element in $id.');
    }
    final element=matches.first as OverlayText;
    if(element.text==text)return;
    await _setElements(id,[element.withText(text)]);
  });

  Future<void> removeElement(String id,String elementId)=>_run(() async{
    final current=_get(id);
    final elements=current.elements.where((element)=>element.id!=elementId).toList();
    if(elements.length==current.elements.length)return;
    await send({'action':'removeElement','id':id,'elementId':elementId});
    if(!_closed)_modules[id]=current.copyWith(elements:elements);
  });

  /// Placement changes reuse the module texture; they do not repaint its content.
  Future<void> place(String id,{required double x,required double y,double scale=1})=>
    _place(id,(module)=>module.copyWith(x:x,y:y,scale:scale));
  Future<void> move(String id,{required double x,required double y})=>
    _place(id,(module)=>module.copyWith(x:x,y:y));
  Future<void> setScale(String id,double scale)=>
    _place(id,(module)=>module.copyWith(scale:scale));
  Future<void> setOpacity(String id,double opacity)=>
    _place(id,(module)=>module.copyWith(opacity:opacity));
  Future<void> setLayer(String id,int zIndex)=>
    _place(id,(module)=>module.copyWith(zIndex:zIndex));
  Future<void> show(String id)=>_place(id,(module)=>module.copyWith(visible:true));
  Future<void> hide(String id)=>_place(id,(module)=>module.copyWith(visible:false));

  /// Placeholder: currently hides instantly. No animation timer is started.
  Future<void> fadeOut(String id)=>hide(id);

  /// Placeholder: currently hides instantly, regardless of direction.
  Future<void> slideOut(String id,{required OverlayDirection direction})=>hide(id);

  Future<void> _place(String id,OverlayModule Function(OverlayModule) change)=>_run(() async{
    final updated=change(_get(id));
    await send({'action':'place','id':id,...updated.placement()});
    if(!_closed)_modules[id]=updated;
  });

  Future<void> remove(String id)=>_run(() async{
    _get(id);
    await send({'action':'remove','id':id});
    _modules.remove(id);
  });

  /// Removes every module and registered image, releasing the scene's references.
  Future<void> clear()=>_run(() async{
    await send({'action':'clear'});
    _modules.clear();
  });

  /// Decode once, preserving aspect ratio inside the requested pixel bounds.
  /// Optionally trim transparent margins and center on a transparent bounds-sized
  /// canvas. This makes differently shaped badges safe to draw in equal boxes.
  /// Reusing an image ID replaces it and refreshes all modules referencing it.
  Future<void> loadAssetImage(String id,String asset,{int maxWidth=512,int maxHeight=512,
    bool trimTransparent=false,bool padToBounds=false})=>
    _run(() async{
      final data=await rootBundle.load(asset);
      await _loadImage(id,data.buffer.asUint8List(data.offsetInBytes,data.lengthInBytes),
        maxWidth,maxHeight,trimTransparent,padToBounds);
    });

  Future<void> loadFileImage(String id,String path,{int maxWidth=512,int maxHeight=512,
    bool trimTransparent=false,bool padToBounds=false})=>
    _run(() async{
      final file=File(path);
      _checkImageSize(await file.length());
      await _loadImage(id,await file.readAsBytes(),maxWidth,maxHeight,trimTransparent,padToBounds);
    });

  /// Accepts encoded PNG/JPEG/WebP bytes, including bytes downloaded by the app.
  /// Animated images use only their first frame. Loading does not perform HTTP.
  Future<void> loadImageBytes(String id,Uint8List bytes,{int maxWidth=512,int maxHeight=512,
    bool trimTransparent=false,bool padToBounds=false}){
    try{_checkImageSize(bytes.length);}on ArgumentError catch(error){return Future.error(error);}
    final snapshot=Uint8List.fromList(bytes);
    return _run(() async{await _loadImage(id,snapshot,maxWidth,maxHeight,trimTransparent,padToBounds);});
  }

  Future<void> _loadImage(String id,Uint8List bytes,int maxWidth,int maxHeight,
    bool trimTransparent,bool padToBounds) async{
    checkId(id);
    _checkImageSize(bytes.length);
    if(maxWidth<1 || maxWidth>2048 || maxHeight<1 || maxHeight>2048){
      throw ArgumentError('Image bounds must be within 1–2048 pixels.');
    }
    await send({'action':'image','id':id,'bytes':bytes,'maxWidth':maxWidth,'maxHeight':maxHeight,
      'trimTransparent':trimTransparent,'padToBounds':padToBounds});
  }

  void _checkImageSize(int length){
    if(length<1 || length>8*1024*1024){
      throw ArgumentError('Encoded images must contain 1 byte to 8 MiB.');
    }
  }

  /// Fails if a module still references the image, even when hidden.
  Future<void> removeImage(String id)=>_run(() async{
    checkId(id);
    await send({'action':'removeImage','id':id});
  });

  @internal
  void close(){
    _closed=true;
    _modules.clear();
  }
}
