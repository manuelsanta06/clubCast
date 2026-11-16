package com.app.rtmp_streaming.overlays

internal const val overlayWidth=1280
internal const val overlayHeight=720
internal const val modulePixelBudget=4L*overlayWidth*overlayHeight
internal const val imageByteBudget=16L*1024*1024

internal data class OverlayPlacement(
    val x:Float,val y:Float,val scale:Float,val opacity:Float,val zIndex:Int,val visible:Boolean
){
    companion object{
        fun parse(data:Map<*,*>)=OverlayPlacement(
            data.number("x",-100000.0,100000.0),data.number("y",-100000.0,100000.0),
            data.number("scale",0.01,16.0),data.number("opacity",0.0,1.0),
            data.integer("zIndex",-100000,100000),data["visible"] as? Boolean
                ?:throw IllegalArgumentException("visible must be a boolean")
        )
    }
}

internal data class OverlayElementSpec(
    val id:String,val type:String,val x:Float,val y:Float,val width:Float,val height:Float,
    val color:Int=0,val text:String="",val fontSize:Float=32f,val bold:Boolean=false,
    val align:String="left",val imageId:String=""
){
    companion object{
        fun parse(data:Map<*,*>):OverlayElementSpec{
            val type=data["type"] as? String
            require(type in listOf("rect","oval","text","image")){"Unknown element type: $type"}
            val base=OverlayElementSpec(
                data.id(),type!!,data.number("x",-100000.0,100000.0),data.number("y",-100000.0,100000.0),
                data.number("width",1.0,1280.0),data.number("height",1.0,720.0)
            )
            if(type=="image")return base.copy(imageId=data.id("imageId"))
            val color=(data["colorArgb"] as? Number)?.toLong()
            require(color!=null && color in 0..0xFFFFFFFFL){"colorArgb must be an unsigned ARGB value"}
            if(type!="text")return base.copy(color=color.toInt())
            val text=data["text"] as? String?:throw IllegalArgumentException("text is required")
            require(text.length<=4096){"Text is limited to 4096 characters"}
            val align=data["align"] as? String
            require(align in listOf("left","center","right")){"Unknown text alignment"}
            return base.copy(color=color.toInt(),text=text,
                fontSize=data.number("fontSize",1.0,720.0),bold=data["bold"]==true,align=align!!)
        }
    }
}

internal data class OverlayModuleSpec(
    val id:String,val width:Float,val height:Float,val placement:OverlayPlacement,
    val elements:List<OverlayElementSpec>
){
    companion object{
        fun parse(data:Map<*,*>)=OverlayModuleSpec(
            data.id(),data.number("width",1.0,1280.0),data.number("height",1.0,720.0),
            OverlayPlacement.parse(data),parseElements(data["elements"])
        )
    }
}

internal fun parseElements(value:Any?):List<OverlayElementSpec>{
    val list=value as? List<*>?:throw IllegalArgumentException("elements must be a list")
    require(list.size<=128){"A module supports up to 128 elements"}
    val elements=list.map{OverlayElementSpec.parse(it as? Map<*,*>
        ?:throw IllegalArgumentException("Invalid element"))}
    require(elements.map{it.id}.toSet().size==elements.size){"Duplicate element IDs"}
    return elements
}

internal fun Map<*,*>.id(key:String="id"):String{
    val value=this[key] as? String
    require(value!=null && value.isNotEmpty() && value.length<=128){"$key must contain 1–128 characters"}
    return value
}

internal fun Map<*,*>.number(key:String,min:Double,max:Double):Float{
    val value=(this[key] as? Number)?.toDouble()
    require(value!=null && value.isFinite() && value in min..max){"Invalid $key"}
    return value.toFloat()
}

internal fun Map<*,*>.integer(key:String,min:Int,max:Int):Int{
    val value=(this[key] as? Number)?.toDouble()
    require(value!=null && value.isFinite() && value in min.toDouble()..max.toDouble()
        && value%1==0.0){"Invalid $key"}
    return value.toInt()
}
