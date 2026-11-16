package com.app.rtmp_streaming.overlays

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/** Serializes drawing/image decoding off both Flutter's UI thread and the GL thread. */
internal class OverlayEngine{
    val scene=OverlayScene()
    private val worker=Executors.newSingleThreadExecutor{task->Thread(task,"OverlayCanvas")}
    private val main=Handler(Looper.getMainLooper())
    @Volatile private var disposed=false

    fun execute(data:Map<*,*>,result:MethodChannel.Result,onReady:()->Unit){
        if(disposed){result.error("overlayDisposed","Overlay scene has been disposed",null);return}
        try{
            worker.execute{
                try{
                    check(!disposed){"Overlay scene has been disposed"}
                    scene.execute(data)
                    main.post{
                        if(disposed){result.error("overlayDisposed","Overlay scene has been disposed",null)}
                        else{
                            try{
                                onReady()
                                result.success(null)
                            }catch(error:Exception){
                                result.error("overlayError",error.message,null)
                            }
                        }
                    }
                }catch(error:Exception){
                    main.post{result.error("overlayError",error.message,null)}
                }catch(error:OutOfMemoryError){
                    main.post{result.error("overlayMemory","Not enough memory for this overlay",null)}
                }
            }
        }catch(error:RejectedExecutionException){
            result.error("overlayDisposed","Overlay scene has been disposed",null)
        }
    }

    fun dispose(){
        if(disposed)return
        disposed=true
        // Let pending requests finish with an error, then release CPU resources.
        worker.execute{scene.execute(mapOf("action" to "clear"))}
        worker.shutdown()
    }
}
