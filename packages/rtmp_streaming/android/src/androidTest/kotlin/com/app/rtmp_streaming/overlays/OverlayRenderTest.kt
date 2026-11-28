package com.app.rtmp_streaming.overlays

import android.graphics.Bitmap
import android.graphics.Color
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20.*
import android.opengl.GLUtils
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/** Exercises the actual Android Canvas + GLES2 output, without a camera/server. */
@RunWith(AndroidJUnit4::class)
class OverlayRenderTest{
    private lateinit var display:EGLDisplay
    private lateinit var context:EGLContext
    private lateinit var surface:EGLSurface
    private lateinit var filter:OverlayFilter
    private val scene=OverlayScene()
    private var cameraTexture=0
    private val width=320
    private val height=180

    @Before fun setup(){createGraphics()}
    @After fun cleanup(){destroyGraphics()}

    private fun createGraphics(){
        display=EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version=IntArray(2)
        check(EGL14.eglInitialize(display,version,0,version,1))
        val configs=arrayOfNulls<EGLConfig>(1)
        val count=IntArray(1)
        check(EGL14.eglChooseConfig(display,intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE,EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE,EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_RED_SIZE,8,EGL14.EGL_GREEN_SIZE,8,EGL14.EGL_BLUE_SIZE,8,
            EGL14.EGL_ALPHA_SIZE,8,EGL14.EGL_NONE
        ),0,configs,0,1,count,0))
        context=EGL14.eglCreateContext(display,configs[0],EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION,2,EGL14.EGL_NONE),0)
        surface=EGL14.eglCreatePbufferSurface(display,configs[0],
            intArrayOf(EGL14.EGL_WIDTH,width,EGL14.EGL_HEIGHT,height,EGL14.EGL_NONE),0)
        check(EGL14.eglMakeCurrent(display,surface,surface,context))
        val name=IntArray(1)
        glGenTextures(1,name,0)
        cameraTexture=name[0]
        glBindTexture(GL_TEXTURE_2D,cameraTexture)
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE)
        val background=Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888)
        background.eraseColor(Color.BLUE)
        GLUtils.texImage2D(GL_TEXTURE_2D,0,background,0)
        background.recycle()
        filter=OverlayFilter(scene)
        filter.initGl(width,height,InstrumentationRegistry.getInstrumentation().targetContext,width,height)
        filter.initFBOLink()
        filter.setPreviousTexId(cameraTexture)
    }

    private fun destroyGraphics(){
        filter.release()
        glDeleteTextures(1,intArrayOf(cameraTexture),0)
        EGL14.eglMakeCurrent(display,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_SURFACE,EGL14.EGL_NO_CONTEXT)
        EGL14.eglDestroySurface(display,surface)
        EGL14.eglDestroyContext(display,context)
        EGL14.eglTerminate(display)
    }

    private fun rect(id:String,color:Long,x:Int=0,y:Int=0,width:Int=200,height:Int=100)=mapOf(
        "id" to id,"type" to "rect","colorArgb" to color,"x" to x,"y" to y,
        "width" to width,"height" to height
    )

    private fun add(id:String="scoreboard",x:Int=40,y:Int=40,z:Int=0,
        elements:List<Map<String,Any>> = listOf(rect("bg",0xFFFF0000L))){
        scene.execute(mapOf("action" to "add","module" to mapOf(
            "id" to id,"width" to 200,"height" to 100,"x" to x,"y" to y,
            "scale" to 1,"opacity" to 1,"visible" to true,"zIndex" to z,"elements" to elements
        )))
    }

    private fun place(id:String="scoreboard",x:Int=40,y:Int=40,scale:Double=1.0,
        opacity:Double=1.0,visible:Boolean=true,z:Int=0){
        scene.execute(mapOf("action" to "place","id" to id,"x" to x,"y" to y,
            "scale" to scale,"opacity" to opacity,"visible" to visible,"zIndex" to z))
    }

    private fun assertPixel(x:Int,y:Int,color:Int,tolerance:Int=2){
        val bytes=ByteBuffer.allocateDirect(4)
        glBindFramebuffer(GL_FRAMEBUFFER,filter.getRenderHandler().fboId[0])
        glReadPixels(x*width/1280,height-1-y*height/720,1,1,GL_RGBA,GL_UNSIGNED_BYTE,bytes)
        val actual=(0..3).map{bytes.get(it).toInt() and 255}
        val expected=listOf(Color.red(color),Color.green(color),Color.blue(color),Color.alpha(color))
        actual.zip(expected).forEach{(value,target)->assertTrue("pixel($x,$y): $actual != $expected",
            kotlin.math.abs(value-target)<=tolerance)}
        assertEquals(GL_NO_ERROR,glGetError())
    }

    @Test fun compositesPremultipliedAlphaAtReferenceCoordinates(){
        add(elements=listOf(rect("bg",0x80FF0000L)))
        filter.draw()
        assertPixel(60,60,Color.rgb(128,0,127))
        assertPixel(300,60,Color.BLUE)
        assertPixel(60,620,Color.BLUE)
        place(opacity=0.5)
        filter.draw()
        assertPixel(60,60,Color.rgb(64,0,191))
    }

    @Test fun moduleBitmapIsNotFlippedAndElementsRespectTheirOrder(){
        add(elements=listOf(rect("bg",0xFFFF0000L),rect("top",0xFF00FF00L,height=40)))
        filter.draw()
        assertPixel(60,60,Color.GREEN)
        assertPixel(60,110,Color.RED)
    }

    @Test fun movementVisibilityScaleAndLayerReuseRasterContent(){
        add()
        add(id="front",z=1,elements=listOf(rect("bg",0xFF00FF00L)))
        val bitmap=scene.frame.first().bitmap
        filter.draw()
        assertPixel(60,60,Color.GREEN)
        place(z=2)
        assertSame(bitmap,scene.frame.last().bitmap)
        filter.draw()
        assertPixel(60,60,Color.RED)
        place(x=400,y=200,scale=2.0,z=2)
        assertSame(bitmap,scene.frame.last().bitmap)
        filter.draw()
        assertPixel(60,60,Color.GREEN)
        assertPixel(700,300,Color.RED)
        place(x=400,y=200,visible=false,z=2)
        filter.draw()
        assertPixel(700,300,Color.BLUE)
        place(x=400,y=200,z=2)
        filter.draw()
        assertPixel(420,220,Color.RED)
    }

    @Test fun contentUpdatesHiddenModulesRemovalAndRecreationKeepWorking(){
        add()
        filter.draw()
        val old=scene.frame.single().bitmap
        scene.execute(mapOf("action" to "elements","id" to "scoreboard",
            "elements" to listOf(rect("bg",0xFF00FF00L))))
        assertNotSame(old,scene.frame.single().bitmap)
        assertFalse(old.isRecycled)
        filter.draw()
        assertPixel(60,60,Color.GREEN)
        place(visible=false)
        scene.execute(mapOf("action" to "elements","id" to "scoreboard",
            "elements" to listOf(rect("bg",0xFFFFFFFFL))))
        filter.draw()
        assertPixel(60,60,Color.BLUE)
        place()
        filter.draw()
        assertPixel(60,60,Color.WHITE)
        destroyGraphics()
        createGraphics()
        filter.draw()
        assertPixel(60,60,Color.WHITE)
        scene.execute(mapOf("action" to "remove","id" to "scoreboard"))
        filter.draw()
        assertPixel(60,60,Color.BLUE)
        add()
        filter.draw()
        assertPixel(60,60,Color.RED)
    }

    @Test fun clipsAndDrawsTextAndOvalsOnAndroidCanvas(){
        val text=mapOf("id" to "text","type" to "text","text" to "GOAL\nSECOND LINE",
            "x" to 0,"y" to 0,"width" to 100,"height" to 40,"fontSize" to 30,
            "bold" to true,"align" to "left","colorArgb" to 0xFFFFFFFFL)
        val oval=rect("oval",0x8000FF00L,x=100,width=100,height=100)+("type" to "oval")
        add(elements=listOf(text,oval))
        val bitmap=scene.frame.single().bitmap
        assertEquals(Color.TRANSPARENT,bitmap.getPixel(105,5))
        assertEquals(128,Color.alpha(bitmap.getPixel(150,50)))
        assertEquals(Color.TRANSPARENT,bitmap.getPixel(20,80))
        val whitePixels=(0 until 40).sumOf{y->(0 until 100).count{x->Color.red(bitmap.getPixel(x,y))>0}}
        assertTrue(whitePixels>50)
        filter.draw()
        assertPixel(190,90,Color.rgb(0,128,127))
    }

    private fun image(color:Int):ByteArray{
        val bitmap=Bitmap.createBitmap(400,200,Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(color)
        val bytes=ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG,100,bytes)
        bitmap.recycle()
        return bytes.toByteArray()
    }

    @Test fun replacesSharedImagesAtomicallyAndRejectsRemovalWhileReferenced(){
        fun load(bytes:ByteArray){scene.execute(mapOf("action" to "image","id" to "logo",
            "bytes" to bytes,"maxWidth" to 100,"maxHeight" to 100))}
        load(image(Color.RED))
        add(elements=listOf(mapOf("id" to "logo","type" to "image","imageId" to "logo",
            "x" to 0,"y" to 0,"width" to 200,"height" to 100)))
        filter.draw()
        assertPixel(60,60,Color.RED)
        load(image(Color.GREEN))
        filter.draw()
        assertPixel(60,60,Color.GREEN)
        try{load(byteArrayOf(1,2,3));fail("Invalid image accepted")}catch(expected:IllegalArgumentException){}
        filter.draw()
        assertPixel(60,60,Color.GREEN)
        place(visible=false)
        try{
            scene.execute(mapOf("action" to "removeImage","id" to "logo"))
            fail("Referenced image removed")
        }catch(expected:IllegalArgumentException){}
        scene.execute(mapOf("action" to "clear"))
        assertTrue(scene.frame.isEmpty())
        filter.draw()
        assertPixel(60,60,Color.BLUE)
    }

    @Test fun trimsTransparentMarginsAndPadsBadgesWithoutStretching(){
        val bitmap=Bitmap.createBitmap(400,200,Bitmap.Config.ARGB_8888)
        android.graphics.Canvas(bitmap).drawRect(100f,50f,300f,150f,
            android.graphics.Paint().apply{color=Color.RED})
        val bytes=ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG,100,bytes)
        bitmap.recycle()
        fun load(data:ByteArray){scene.execute(mapOf("action" to "image","id" to "badge",
            "bytes" to data,"maxWidth" to 100,"maxHeight" to 100,
            "trimTransparent" to true,"padToBounds" to true))}
        load(bytes.toByteArray())
        add(elements=listOf(mapOf("id" to "badge","type" to "image","imageId" to "badge",
            "x" to 0,"y" to 0,"width" to 100,"height" to 100)))
        val rendered=scene.frame.single().bitmap
        // The opaque 2:1 shape occupies 100x50, centered inside a 100x100 badge.
        assertEquals(Color.TRANSPARENT,rendered.getPixel(50,10))
        assertEquals(Color.RED,rendered.getPixel(50,50))
        assertEquals(Color.TRANSPARENT,rendered.getPixel(50,90))
        filter.draw()
        assertPixel(60,50,Color.BLUE)
        assertPixel(60,90,Color.RED)
        load(image(Color.TRANSPARENT))
        filter.draw()
        assertPixel(60,90,Color.BLUE)
    }
}
