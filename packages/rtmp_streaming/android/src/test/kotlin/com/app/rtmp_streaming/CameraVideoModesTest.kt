package com.app.rtmp_streaming

import org.junit.Assert.*
import org.junit.Test

class CameraVideoModesTest{
    @Test fun limitsFrameRateByResolutionAndCameraRange(){
        assertTrue(CameraVideoModes.cameraRateSupported(30,60,33_333_333))
        assertFalse(CameraVideoModes.cameraRateSupported(60,60,33_333_333))
        assertTrue(CameraVideoModes.cameraRateSupported(60,60,16_666_667))
        assertFalse(CameraVideoModes.cameraRateSupported(60,30,16_666_667))
    }

    @Test fun acceptsNominalRatesAndUsesConservativeLegacyLimit(){
        assertTrue(CameraVideoModes.cameraRateSupported(30,30,33_366_667))
        assertTrue(CameraVideoModes.cameraRateSupported(60,60,16_683_333))
        assertTrue(CameraVideoModes.cameraRateSupported(30,60,0))
        assertFalse(CameraVideoModes.cameraRateSupported(60,60,0))
        assertFalse(CameraVideoModes.cameraRateSupported(30,15,0))
        assertFalse(CameraVideoModes.cameraRateSupported(0,60,0))
    }
}
