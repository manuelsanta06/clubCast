package com.app.rtmp_streaming

import com.app.rtmp_streaming.overlays.*
import org.junit.Assert.*
import org.junit.Test

class OverlaySpecTest{
    private fun module()=mutableMapOf<String,Any>(
        "id" to "scoreboard","width" to 320,"height" to 80,
        "x" to 10,"y" to 20,"scale" to 1,"opacity" to 0.5,"zIndex" to 2,"visible" to true,
        "elements" to listOf(mapOf("id" to "bg","type" to "rect","width" to 320,
            "height" to 80,"x" to 0,"y" to 0,"colorArgb" to 0x80FF0000L))
    )

    @Test fun parsesChannelNumbersAndArgbWithoutLosingAlpha(){
        val spec=OverlayModuleSpec.parse(module())
        assertEquals(0x80FF0000.toInt(),spec.elements.first().color)
        assertEquals(0.5f,spec.placement.opacity)
        assertEquals(320f,spec.width)
        assertTrue("overlayCommand" in CameraMethodPolicy.requiresView)
    }

    @Test fun rejectsMalformedCommandsBeforeAllocatingBitmaps(){
        for(value in listOf(Double.NaN,Double.POSITIVE_INFINITY,0,1281)){
            val data=module().apply{put("width",value)}
            assertThrows(IllegalArgumentException::class.java){OverlayModuleSpec.parse(data)}
        }
        val duplicate=module().apply{put("elements",(get("elements") as List<*>).let{it+it})}
        assertThrows(IllegalArgumentException::class.java){OverlayModuleSpec.parse(duplicate)}
        val invalidLayer=module().apply{put("zIndex",0.5)}
        assertThrows(IllegalArgumentException::class.java){OverlayModuleSpec.parse(invalidLayer)}
        val invalidAlpha=module().apply{put("opacity",1.1)}
        assertThrows(IllegalArgumentException::class.java){OverlayModuleSpec.parse(invalidAlpha)}
    }
}
