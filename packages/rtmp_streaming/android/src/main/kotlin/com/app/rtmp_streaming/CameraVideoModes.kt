package com.app.rtmp_streaming

import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.util.Size
import com.pedro.encoder.input.video.Camera2ResolutionCalculator

/** Normal capture modes for the camera + H.264 surface encoder pipeline.
 * High-speed capture sessions are deliberately excluded. */
internal object CameraVideoModes{
    fun read(context:Context,cameraId:String):List<Map<String,Any>>{
        val manager=context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val camera=manager.getCameraCharacteristics(cameraId)
        val streams=requireNotNull(camera.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)){
            "Camera does not report stream configurations"
        }
        val sizes=streams.getOutputSizes(SurfaceTexture::class.java)
            ?.filter{it.width>=it.height && it.width%2==0 && it.height%2==0}
            ?.toTypedArray()?:emptyArray()
        require(sizes.isNotEmpty()){"Camera does not report landscape video sizes"}
        val maxCameraFps=requireNotNull(camera.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES))
            .maxOf{it.upper}
        val encoders=MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter{it.isEncoder && it.supportedTypes.any{type->type.equals("video/avc",true)}}
            .mapNotNull{codec->runCatching{
                codec.getCapabilitiesForType("video/avc").takeIf{
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface in it.colorFormats
                }?.videoCapabilities
            }.getOrNull()}
        val outputs=sizes.filter{it.width<=1920 && it.height<=1080}.toMutableSet()
        // The output can be downscaled from a larger camera frame.
        for(size in listOf(Size(1280,720),Size(1920,1080))){
            if(sizes.any{it.width>=size.width && it.height>=size.height})outputs.add(size)
        }
        val rates=(listOf(15,24,25,30,50,60)+minOf(maxCameraFps,60))
            .filter{it>0}.distinct().sorted()
        return outputs.sortedBy{it.width.toLong()*it.height}.mapNotNull{output->
            // Use RootEncoder's own selection rule for the source frame size.
            val source=Camera2ResolutionCalculator.getOptimalResolution(output,sizes)
            val duration=streams.getOutputMinFrameDuration(SurfaceTexture::class.java,source)
            val fps=rates.filter{rate->
                cameraRateSupported(rate,maxCameraFps,duration) && encoders.any{encoder->
                    runCatching{encoder.areSizeAndRateSupported(output.width,output.height,rate.toDouble())}
                        .getOrDefault(false)
                }
            }
            if(fps.isEmpty())null
            else mapOf("width" to output.width,"height" to output.height,"frameRates" to fps)
        }
    }

    internal fun cameraRateSupported(fps:Int,maxFps:Int,minFrameDuration:Long):Boolean{
        if(fps<=0 || fps>maxFps)return false
        // Legacy devices may not report per-size durations. Stay at 30 FPS or below.
        if(minFrameDuration<=0)return fps<=30
        // Allow nominal 30/60 for sensors reporting 29.97/59.94.
        return minFrameDuration<=1_010_000_000L/fps
    }
}
