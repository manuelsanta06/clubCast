package com.app.rtmp_streaming.overlays

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

internal data class RenderedModule(val spec:OverlayModuleSpec,val bitmap:Bitmap,val revision:Long)

/** Only the worker mutates scene state. Published bitmaps are never changed or
 * recycled: a GL frame may still be uploading an older snapshot. Android frees
 * them once both the worker and GL snapshots release their references. */
internal class OverlayScene{
    private val modules=linkedMapOf<String,RenderedModule>()
    private val images=mutableMapOf<String,Bitmap>()
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val textPaint=TextPaint(Paint.ANTI_ALIAS_FLAG)
    private var revision=0L

    @Volatile var frame:List<RenderedModule> = emptyList()
        private set

    fun execute(data:Map<*,*>){
        when(data["action"]){
            "add"->{
                val spec=OverlayModuleSpec.parse(data["module"] as? Map<*,*>
                    ?:throw IllegalArgumentException("module is required"))
                require(!modules.containsKey(spec.id)){"Module already exists: ${spec.id}"}
                require(modules.size<32){"At most 32 modules can be retained"}
                val pixels=modules.values.sumOf{it.bitmap.width.toLong()*it.bitmap.height}
                require(pixels+ceil(spec.width).toLong()*ceil(spec.height).toLong()<=modulePixelBudget){
                    "Module bitmap budget exceeded (14 MiB)"
                }
                modules[spec.id]=render(spec)
            }
            "elements"->{
                val current=module(data)
                val elements=current.spec.elements.associateBy{it.id}.toMutableMap()
                parseElements(data["elements"]).forEach{elements[it.id]=it}
                require(elements.size<=128){"A module supports up to 128 elements"}
                val spec=current.spec.copy(elements=elements.values.toList())
                if(spec==current.spec)return
                modules[spec.id]=render(spec)
            }
            "removeElement"->{
                val current=module(data)
                val id=data.id("elementId")
                val spec=current.spec.copy(elements=current.spec.elements.filter{it.id!=id})
                if(spec==current.spec)return
                modules[spec.id]=render(spec)
            }
            "place"->{
                val current=module(data)
                val spec=current.spec.copy(placement=OverlayPlacement.parse(data))
                if(spec==current.spec)return
                modules[spec.id]=current.copy(spec=spec)
            }
            "remove"->{modules.remove(module(data).spec.id)}
            "clear"->{
                modules.clear()
                images.values.forEach{it.recycle()}
                images.clear()
            }
            "image"->loadImage(data)
            "removeImage"->{
                val id=data.id()
                require(modules.values.none{module->module.spec.elements.any{it.imageId==id}}){
                    "Image is still used by a module: $id"
                }
                images.remove(id)?.recycle()
            }
            else->throw IllegalArgumentException("Unknown overlay action")
        }
        frame=modules.values.sortedBy{it.spec.placement.zIndex}
    }

    private fun module(data:Map<*,*>)=modules[data.id()]
        ?:throw IllegalArgumentException("Unknown module: ${data.id()}")

    private fun render(spec:OverlayModuleSpec,imageSource:Map<String,Bitmap> = images):RenderedModule{
        spec.elements.filter{it.type=="image"}.forEach{
            require(imageSource.containsKey(it.imageId)){"Unknown image: ${it.imageId}"}
        }
        val bitmap=Bitmap.createBitmap(ceil(spec.width).toInt(),ceil(spec.height).toInt(),Bitmap.Config.ARGB_8888)
        val canvas=Canvas(bitmap)
        // Match the logical dimensions, including fractional module sizes.
        canvas.scale(bitmap.width/spec.width,bitmap.height/spec.height)
        spec.elements.forEach{element->
            val x=element.x
            val y=element.y
            val right=x+element.width
            val bottom=y+element.height
            paint.color=element.color
            when(element.type){
                "rect"->canvas.drawRect(x,y,right,bottom,paint)
                "oval"->canvas.drawOval(x,y,right,bottom,paint)
                "image"->{
                    paint.alpha=255
                    canvas.drawBitmap(imageSource.getValue(element.imageId),null,RectF(x,y,right,bottom),paint)
                }
                "text"->{
                    textPaint.color=element.color
                    textPaint.textSize=element.fontSize
                    textPaint.typeface=if(element.bold)Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                    val alignment=when(element.align){
                        "center"->Layout.Alignment.ALIGN_CENTER
                        "right"->Layout.Alignment.ALIGN_OPPOSITE
                        else->Layout.Alignment.ALIGN_NORMAL
                    }
                    // API 21-compatible; layout happens only when content changes.
                    @Suppress("DEPRECATION")
                    val layout=StaticLayout(element.text,textPaint,ceil(element.width).toInt(),
                        alignment,1f,0f,false)
                    canvas.save()
                    canvas.clipRect(x,y,right,bottom)
                    canvas.translate(x,y)
                    layout.draw(canvas)
                    canvas.restore()
                }
            }
        }
        return RenderedModule(spec,bitmap,++revision)
    }

    private fun loadImage(data:Map<*,*>){
        val id=data.id()
        val bytes=data["bytes"] as? ByteArray?:throw IllegalArgumentException("Encoded image bytes required")
        require(bytes.isNotEmpty() && bytes.size<=8*1024*1024){"Encoded image limit is 8 MiB"}
        val maxWidth=data.integer("maxWidth",1,2048)
        val maxHeight=data.integer("maxHeight",1,2048)
        val trimTransparent=data["trimTransparent"]==true
        val padToBounds=data["padToBounds"]==true
        require(images.containsKey(id) || images.size<128){"At most 128 images can be retained"}
        val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true}
        BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
        require(bounds.outWidth>0 && bounds.outHeight>0){"Unsupported or invalid image"}
        val ratio=min(1.0,min(maxWidth.toDouble()/bounds.outWidth,maxHeight.toDouble()/bounds.outHeight))
        val width=max(1,(bounds.outWidth*ratio).toInt())
        val height=max(1,(bounds.outHeight*ratio).toInt())
        val retainedBytes=images.filterKeys{it!=id}.values.sumOf{it.allocationByteCount.toLong()}
        val pixels=if(padToBounds)maxWidth.toLong()*maxHeight else width.toLong()*height
        require(retainedBytes+pixels*4<=imageByteBudget){"Decoded image budget exceeded (16 MiB)"}
        var sample=1
        while(sample<(1 shl 20) && sample*2<=1/ratio){
            sample*=2
        }
        val options=BitmapFactory.Options().apply{inSampleSize=sample;inPreferredConfig=Bitmap.Config.ARGB_8888}
        val decoded=BitmapFactory.decodeByteArray(bytes,0,bytes.size,options)
            ?:throw IllegalArgumentException("Image could not be decoded")
        var image=Bitmap.createScaledBitmap(decoded,width,height,true)
        if(image!==decoded)decoded.recycle()
        try{
            if(trimTransparent){
                // Scan only the small decoded bitmap, never the full source image.
                val cropped=trimImage(image)
                if(cropped!==image)image.recycle()
                image=cropped
            }
            if(padToBounds){
                val padded=Bitmap.createBitmap(maxWidth,maxHeight,Bitmap.Config.ARGB_8888)
                val scale=min(maxWidth.toFloat()/image.width,maxHeight.toFloat()/image.height)
                val w=image.width*scale
                val h=image.height*scale
                val x=(maxWidth-w)/2
                val y=(maxHeight-h)/2
                paint.alpha=255
                Canvas(padded).drawBitmap(image,null,RectF(x,y,x+w,y+h),paint)
                image.recycle()
                image=padded
            }
            require(retainedBytes+image.allocationByteCount<=imageByteBudget){"Decoded image budget exceeded (16 MiB)"}
            val source=images+Pair(id,image)
            // Prepare every affected module before publishing, so a failure is atomic.
            val updates=modules.values.filter{it.spec.elements.any{element->element.imageId==id}}
                .associate{it.spec.id to render(it.spec,source)}
            val old=images.put(id,image)
            modules.putAll(updates)
            old?.recycle()
        }catch(error:Throwable){
            image.recycle()
            throw error
        }
    }

    private fun trimImage(image:Bitmap):Bitmap{
        val pixels=IntArray(image.width*image.height)
        image.getPixels(pixels,0,image.width,0,0,image.width,image.height)
        var left=image.width
        var top=image.height
        var right=-1
        var bottom=-1
        for(y in 0 until image.height)for(x in 0 until image.width){
            if((pixels[y*image.width+x] ushr 24)==0)continue
            left=min(left,x)
            top=min(top,y)
            right=max(right,x)
            bottom=max(bottom,y)
        }
        if(right<left)return image // A fully transparent image stays transparent.
        return Bitmap.createBitmap(image,left,top,right-left+1,bottom-top+1)
    }
}
