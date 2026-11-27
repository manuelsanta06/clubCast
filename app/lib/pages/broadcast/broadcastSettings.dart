// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

class BroadcastSettings{
  const BroadcastSettings({
    this.resolution=preferredResolution,this.fps=30,this.bitrateKbps=1200,
    this.countdown=false,
  });

  static const preferredResolution=CameraVideoMode(width:1280,height:720,frameRates:[30]);

  factory BroadcastSettings.forModes(List<CameraVideoMode> modes){
    if(modes.isEmpty)throw StateError('No compatible camera/encoder video modes.');
    final resolution=modes.firstWhere(
      (mode)=>mode==preferredResolution,
      orElse:()=>modes.reduce((a,b)=>a.pixels>=b.pixels?a:b),
    );
    return BroadcastSettings(resolution:resolution,fps:resolution.preferredFrameRate());
  }

  final CameraVideoMode resolution;
  final int fps,bitrateKbps;
  final bool countdown;
  int get bitrate=>bitrateKbps*1000;

  Future<void> apply(CameraController camera,{required bool streaming}) async{
    await camera.setVideoSettings(
      bitrate:bitrate,
      width:streaming?null:resolution.width,
      height:streaming?null:resolution.height,
      expectedFrameRate:streaming?null:fps.toDouble(),
    );
  }
}

class BroadcastSettingsDialog extends StatefulWidget{
  const BroadcastSettingsDialog({
    super.key,required this.settings,required this.modes,required this.camera,
    required this.isLocked,required this.onApply,
  });

  final BroadcastSettings settings;
  final List<CameraVideoMode> modes;
  final CameraController camera;
  final bool Function() isLocked;
  final Future<void> Function(BroadcastSettings) onApply;

  @override
  State<BroadcastSettingsDialog> createState()=>_BroadcastSettingsDialogState();
}

class _BroadcastSettingsDialogState extends State<BroadcastSettingsDialog>{
  late CameraVideoMode _resolution=widget.settings.resolution;
  late int _fps=widget.settings.fps;
  late int _bitrateKbps=widget.settings.bitrateKbps;
  late bool _countdown=widget.settings.countdown;
  bool _saving=false;
  String? _error;

  bool get _locked=>widget.isLocked();

  Future<void> _save() async{
    if(_saving)return;
    setState((){_saving=true;_error=null;});
    try{
      await widget.onApply(BroadcastSettings(
        resolution:_locked?widget.settings.resolution:_resolution,
        fps:_locked?widget.settings.fps:_fps,
        bitrateKbps:_bitrateKbps,
        countdown:_countdown,
      ));
      if(mounted){Navigator.of(context).pop();}
    }catch(error){
      debugPrint('Broadcast settings failed: $error');
      if(mounted){
        setState((){
          _saving=false;
          _error='No se pudieron aplicar los ajustes. Intentá nuevamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context){
    return Theme(
      data:ThemeData.dark().copyWith(colorScheme:ColorScheme.fromSeed(
        seedColor:const Color(0xFF7656B3),brightness:Brightness.dark,
      )),
      child:PopScope(canPop:!_saving,child:ValueListenableBuilder<CameraValue>(
        valueListenable:widget.camera,
        builder:(context,value,child){
          final resolution=_locked?widget.settings.resolution:_resolution;
          return AlertDialog(
            backgroundColor:const Color(0xFF22283A).withValues(alpha:0.96),
            insetPadding:const EdgeInsets.all(20),
            scrollable:true,
            title:const Text('Configuración'),
            content:SizedBox(width:320,child:Column(mainAxisSize:MainAxisSize.min,children:[
              DropdownButtonFormField<CameraVideoMode>(
                key:ValueKey(('resolution',_locked)),
                initialValue:resolution,
                decoration:const InputDecoration(labelText:'Resolución'),
                items:[for(final resolution in widget.modes)
                  DropdownMenuItem(value:resolution,
                    child:Text(resolution.label)),
                ],
                onChanged:_locked || _saving?null:
                  (value)=>setState((){
                    _resolution=value!;
                    _fps=_resolution.preferredFrameRate(_fps);
                  }),
              ),
              const SizedBox(height:12),
              DropdownButtonFormField<int>(
                key:ValueKey(('fps',_locked,resolution)),
                initialValue:_locked?widget.settings.fps:_fps,
                decoration:const InputDecoration(labelText:'Fotogramas por segundo'),
                items:[for(final fps in resolution.frameRates)
                  DropdownMenuItem(value:fps,child:Text('$fps FPS')),
                ],
                onChanged:_locked || _saving?null:
                  (value)=>setState((){_fps=value!;}),
              ),
              const SizedBox(height:20),
              Text('Bitrate de video: $_bitrateKbps kbps'),
              Slider(
                value:_bitrateKbps.toDouble(),min:100,max:20000,divisions:199,
                label:'$_bitrateKbps kbps',
                onChanged:_saving?null:(value)=>setState((){_bitrateKbps=value.round();}),
              ),
              Text(_locked
                ?'Resolución y FPS bloqueados al transmitir.'
                :'Resolución y FPS se aplican al iniciar.',
                style:Theme.of(context).textTheme.bodySmall),
              const SizedBox(height:12),
              SwitchListTile(
                contentPadding:EdgeInsets.zero,
                title:const Text('Cuenta regresiva'),
                subtitle:Text(_countdown?'Muestra el tiempo restante.':'Muestra el tiempo transcurrido.'),
                value:_countdown,
                onChanged:_saving?null:(value)=>setState((){_countdown=value;}),
              ),
              if(_error!=null)Padding(
                padding:const EdgeInsets.only(top:12),
                child:Text(_error!,style:const TextStyle(color:Color(0xFFFFB4AB))),
              ),
            ])),
            actions:[
              TextButton(onPressed:_saving?null:()=>Navigator.of(context).pop(),
                child:const Text('Cancelar')),
              FilledButton(onPressed:_saving?null:_save,
                child:Text(_saving?'Aplicando…':'Aplicar')),
            ],
          );
        },
      )),
    );
  }
}
