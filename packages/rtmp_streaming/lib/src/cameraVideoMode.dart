// ignore_for_file: file_names
/// An encoded video size and candidate FPS reported by the Android camera and
/// H.264 encoders. Actual capture rate can vary with device load and lighting.
class CameraVideoMode{
  const CameraVideoMode({required this.width,required this.height,required this.frameRates});

  final int width,height;
  final List<int> frameRates;

  factory CameraVideoMode.fromMap(Map<dynamic,dynamic> data)=>CameraVideoMode(
    width:(data['width'] as num).toInt(),height:(data['height'] as num).toInt(),
    frameRates:List.unmodifiable((data['frameRates'] as List).map((fps)=>(fps as num).toInt())),
  );

  int get pixels=>width*height;
  String get label=>'${height}p ($width×$height)';

  int preferredFrameRate([int preferred=30]){
    final sorted=frameRates.toList()..sort();
    if(sorted.isEmpty)throw StateError('Video mode has no frame rates.');
    return sorted.lastWhere((fps)=>fps<=preferred,orElse:()=>sorted.first);
  }

  @override
  bool operator ==(Object other)=>other is CameraVideoMode && width==other.width && height==other.height;

  @override
  int get hashCode=>Object.hash(width,height);
}
