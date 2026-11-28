// ignore_for_file: file_names
import 'package:rtmp_streaming/rtmp_streaming.dart';

/// A bundled badge today, or a downloaded file kept for the broadcast later.
class TeamBadge{
  const TeamBadge.asset(this.path):isAsset=true;
  const TeamBadge.file(this.path):isAsset=false;

  final String path;
  final bool isAsset;

  Future<void> load(OverlayModules overlays,String id){
    // Decode and normalize once natively. The scoreboard reuses this bitmap.
    if(isAsset){
      return overlays.loadAssetImage(id,path,maxWidth:64,maxHeight:64,
        trimTransparent:true,padToBounds:true);
    }
    return overlays.loadFileImage(id,path,maxWidth:64,maxHeight:64,
      trimTransparent:true,padToBounds:true);
  }
}
