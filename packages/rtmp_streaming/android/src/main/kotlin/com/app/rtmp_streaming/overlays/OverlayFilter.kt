package com.app.rtmp_streaming.overlays

import android.content.Context
import android.opengl.GLES20.*
import android.opengl.GLUtils
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** One camera pass, then one small blended quad per visible module. All GL
 * operations, including texture uploads and deletion, run on RootEncoder's GL thread. */
internal class OverlayFilter(private val scene:OverlayScene):BaseFilterRender(){
    private data class Texture(val id:Int,var revision:Long=-1,var width:Int=0,var height:Int=0)
    private val textures=mutableMapOf<String,Texture>()
    private val vertices=ByteBuffer.allocateDirect(8*4).order(ByteOrder.nativeOrder())
        .asFloatBuffer().apply{put(floatArrayOf(0f,0f,1f,0f,0f,1f,1f,1f));position(0)}
    private val textureName=IntArray(1)
    private var program=0
    private var position=0
    private var bounds=0
    private var flip=0
    private var opacity=0
    private var lastFrame:List<RenderedModule>?=null
    @Volatile var released=false
        private set

    override fun initGlFilter(context:Context){
        released=false
        program=GlUtil.createProgram("""
            attribute vec2 position;
            uniform vec4 bounds;
            uniform float flip;
            varying vec2 uv;
            void main(){
                gl_Position=vec4(bounds.xy+position*bounds.zw,0.0,1.0);
                uv=vec2(position.x,mix(position.y,1.0-position.y,flip));
            }
        """.trimIndent(),"""
            precision mediump float;
            uniform sampler2D image;
            uniform float opacity;
            varying vec2 uv;
            void main(){gl_FragColor=texture2D(image,uv)*opacity;}
        """.trimIndent())
        check(program!=0){"Unable to compile overlay shader"}
        position=glGetAttribLocation(program,"position")
        bounds=glGetUniformLocation(program,"bounds")
        flip=glGetUniformLocation(program,"flip")
        opacity=glGetUniformLocation(program,"opacity")
        glUseProgram(program)
        glUniform1i(glGetUniformLocation(program,"image"),0)
    }

    override fun draw(){
        val frame=scene.frame
        if(frame!==lastFrame){
            val ids=frame.map{it.spec.id}.toSet()
            val iterator=textures.iterator()
            while(iterator.hasNext()){
                val entry=iterator.next()
                if(entry.key !in ids){delete(entry.value.id);iterator.remove()}
            }
            lastFrame=frame
        }
        glBindFramebuffer(GL_FRAMEBUFFER,getRenderHandler().fboId[0])
        glViewport(0,0,getWidth(),getHeight())
        glUseProgram(program)
        vertices.position(0)
        glVertexAttribPointer(position,2,GL_FLOAT,false,0,vertices)
        glEnableVertexAttribArray(position)
        glActiveTexture(GL_TEXTURE0)
        glDisable(GL_BLEND)
        glBindTexture(GL_TEXTURE_2D,previousTexId)
        glUniform4f(bounds,-1f,-1f,2f,2f)
        glUniform1f(flip,0f)
        glUniform1f(opacity,1f)
        glDrawArrays(GL_TRIANGLE_STRIP,0,4)

        glEnable(GL_BLEND)
        // Android Canvas produces premultiplied ARGB. SRC_ALPHA would darken edges twice.
        glBlendFunc(GL_ONE,GL_ONE_MINUS_SRC_ALPHA)
        glUniform1f(flip,1f)
        for(module in frame){
            val spec=module.spec
            val placement=spec.placement
            val width=spec.width*placement.scale
            val height=spec.height*placement.scale
            if(!placement.visible || placement.opacity==0f || placement.x>=overlayWidth ||
                placement.y>=overlayHeight || placement.x+width<=0 || placement.y+height<=0)continue
            val texture=textures.getOrPut(spec.id){
                glGenTextures(1,textureName,0)
                Texture(textureName[0]).also{
                    glBindTexture(GL_TEXTURE_2D,it.id)
                    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR)
                    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR)
                    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE)
                    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE)
                }
            }
            glBindTexture(GL_TEXTURE_2D,texture.id)
            if(texture.revision!=module.revision){
                val bitmap=module.bitmap
                if(texture.width==bitmap.width && texture.height==bitmap.height){
                    GLUtils.texSubImage2D(GL_TEXTURE_2D,0,0,0,bitmap)
                }else{
                    GLUtils.texImage2D(GL_TEXTURE_2D,0,bitmap,0)
                    texture.width=bitmap.width
                    texture.height=bitmap.height
                }
                texture.revision=module.revision
            }
            glUniform4f(bounds,placement.x*2/overlayWidth-1,
                1-(placement.y+height)*2/overlayHeight,width*2/overlayWidth,height*2/overlayHeight)
            glUniform1f(opacity,placement.opacity)
            glDrawArrays(GL_TRIANGLE_STRIP,0,4)
        }
        glDisable(GL_BLEND)
        disableResources()
        glBindFramebuffer(GL_FRAMEBUFFER,0)
    }

    // draw() owns the whole FBO pass; the base implementation draws only one quad.
    override fun drawFilter()=Unit

    override fun disableResources(){
        glDisableVertexAttribArray(position)
        glBindTexture(GL_TEXTURE_2D,0)
    }

    override fun release(){
        if(released)return
        released=true
        textures.values.forEach{delete(it.id)}
        textures.clear()
        lastFrame=null
        glDeleteProgram(program)
        program=0
        // This filter is only added/removed, never replaced with setFilter().
        // RootEncoder otherwise retains the FBO on removal until EGL teardown.
        val handler=getRenderHandler()
        glDeleteFramebuffers(1,handler.fboId,0)
        glDeleteRenderbuffers(1,handler.rboId,0)
        glDeleteTextures(1,handler.texId,0)
        handler.fboId[0]=0
        handler.rboId[0]=0
        handler.texId[0]=0
    }

    private fun delete(id:Int){
        textureName[0]=id
        glDeleteTextures(1,textureName,0)
    }
}
