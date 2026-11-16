# Native overlay modules (Android)

Modules are part of the encoded video, including RTMP/RTMPS and local recordings.
The same RootEncoder filter draws them in the camera preview. They are not Flutter
widgets. iOS support is not implemented; calls fail explicitly on other platforms.

## First use

Import `package:rtmp_streaming/rtmp_streaming.dart`. Use `camera.overlays` after the
controller has initialized **and CameraPreview has mounted**. For the first test,
use a button after the preview becomes visible. Do not call overlay operations
from `build()` or repeatedly from a camera listener.

```dart
await camera.overlays.add(OverlayModule(
  id:'scoreboard',width:320,height:80,x:32,y:32,
  elements:const [
    OverlayRect(id:'background',width:320,height:80,colorArgb:0xCC10131D),
    OverlayText(id:'score',text:'0 – 0',x:16,y:16,width:288,height:48,
      fontSize:36,bold:true,align:OverlayTextAlign.center),
  ],
));

await camera.overlays.setText('scoreboard','score','1 – 0');
await camera.overlays.move('scoreboard',x:64,y:32);
await camera.overlays.hide('scoreboard');
await camera.overlays.show('scoreboard');
```

See `example/lib/scoreboard.dart` for a scoreboard, clock and separate sponsor.
That file is a set of helpers to call from your page, not a replacement screen.
Updating the clock is the application's responsibility: call `setText` when the
displayed second changes, and cancel your timer when leaving the page. Identical
text updates are ignored. Do not update it at camera framerate.

Native changes require a full application restart/rebuild; hot reload is not enough.

## Coordinates and elements

- The reference canvas is **1280×720**, independent of encoding resolution. It is
  mapped to the whole encoded frame. Use landscape 16:9 capture to avoid stretching.
- Module `x`/`y` identify its top-left corner. Element coordinates are relative to
  that corner. Content is clipped to the module's `width`/`height`.
- `scale` scales the whole module around its top-left corner; `opacity` is 0–1.
- Higher `zIndex` draws on top. Equal layers use module creation order. Later
  elements in a module draw over earlier ones.
- Colors are integers in **0xAARRGGBB** format. Alpha works for shapes, text, images
  with transparent pixels, and whole-module opacity.
- `OverlayRect`, `OverlayOval` and `OverlayCircle` are solid shapes. Circle `x`/`y`
  describe the bounding box, not its center.
- `OverlayText` supports size, color, bold and left/center/right alignment. It wraps
  inside its box; overflow is clipped. Uses Android's default font, independent of
  Flutter theme/text scaling. Custom fonts, borders and shadows are not included.
- `OverlayImage` stretches an image into its box. Choose matching proportions to
  preserve the image's aspect ratio. Animated files use their first frame only.
- Modules contain elements, not other modules. IDs are unique within their scope:
  module IDs globally, element IDs within a module, image IDs within the image cache.

## Editing and lifecycle

`setText(moduleId,elementId,text)` keeps all text styling. `setElement(moduleId,element)`
replaces an element with the same ID or appends a new one. `setElements` batches
multiple changes into **one** module redraw. `removeElement` removes one item.

`move`, `setScale`, `setOpacity`, `setLayer`, `show` and `hide` reuse raster content.
`fadeOut(id)` and `slideOut(id,direction:OverlayDirection.left)` currently delegate
to instant hiding. Directions are `left`, `right`, `up`, `down`; animations are
explicit placeholders, with no timers or interpolations yet.

Modules and elements are immutable Dart descriptions. Read their latest confirmed
state through `camera.overlays.modules`; perform changes through the methods above.
Keeping the original `OverlayModule` variable does not make it mutable or reactive.

`remove(id)` removes a module but retains registered images for reuse. `clear()`
removes modules **and** images. Disposing the camera releases the scene. Normal
stream restarts and recreation of the GL pipeline reattach the native scene; they
do not require adding all modules again. Disposing/unmounting the native camera
view or recreating the Flutter controller starts a new session.

Operations are serialized. Await them and catch errors; failed operations do not
update the Dart descriptions or block subsequent operations. A completed Future
means native preparation finished, not that YouTube has displayed a frame. Native
camera availability errors still apply when the preview has not mounted.

## Images, including HTTP downloads

Register each image once, then reference its ID:

```dart
await camera.overlays.loadAssetImage('clubLogo','assets/club.png',
  maxWidth:128,maxHeight:128);

await camera.overlays.setElement('scoreboard',const OverlayImage(
  id:'logo',imageId:'clubLogo',x:8,y:8,width:64,height:64,
));
```

Assets must be declared in your app's pubspec. `loadFileImage` reads a local file.
`loadImageBytes(id,bytes,maxWidth:...,maxHeight:...)` accepts encoded PNG/JPEG/WebP
bytes, so your app can download/cache/authenticate images using its own HTTP layer.
No HTTP client or file-writing workflow is introduced by this API.

Decode bounds default to 512×512 and preserve aspect ratio without upscaling.
Set bounds near the largest size you actually display. Registering an existing ID
replaces its image and refreshes every referencing module atomically. For a carousel,
preload a few images under separate IDs and change the `OverlayImage.imageId` through
`setElement`. `removeImage` fails while any module still references that image,
including hidden modules.

## Rendering cost and limits

Android Canvas rasterizes **only a changed module** on a serial background worker.
No PNG encoding, disk writes or Flutter screenshots are used. Each prepared bitmap
is immutable after publication, avoiding races with OpenGL uploads. Older snapshots
are released by Android when the renderer no longer references them.

One custom RootEncoder filter copies the camera into its output framebuffer, then
blends one rectangle per visible module. Each module has a cached GPU texture;
content updates use `texSubImage2D` when dimensions match. Movement, opacity, layer
and visibility changes do not redraw or upload its content. Hidden modules retain
their resources for quick reuse and are skipped during compositing. The filter is
removed when no modules remain; hiding all modules still retains the camera pass.

CPU bitmaps, image cache, GPU textures and the framebuffer all cost memory. This
implementation does not promise a particular battery or temperature result.
For example, a 360×100 scoreboard bitmap occupies about 141 KiB; updating it once
per second creates/uploads that amount of raster data, rather than a full 720p PNG.
Keep large static content separate from frequently changing clocks/scores.

Guardrails (retained resources, not a total process or transient-allocation cap):

| Resource | Limit |
| --- | --- |
| Module dimensions | 1280×720 reference pixels |
| All module bitmap pixels | 4 × 1280 × 720, about 14 MiB of ARGB |
| Modules / elements per module | 32 / 128 |
| Registered images | 128, at most 16 MiB decoded in total |
| Encoded image input | 8 MiB per image |
| Image decode bounds | 2048×2048 maximum |
| Text per element | 4096 characters |

## Code map and verification

- `lib/src/overlays/`: public Dart models and command API.
- `android/.../overlays/OverlaySpec.kt`: native validation and immutable descriptions.
- `OverlayScene.kt`: Canvas rasterization, retained modules and decoded images.
- `OverlayEngine.kt`: background worker and platform-channel responses.
- `OverlayFilter.kt`: GPU composition, texture updates and resource cleanup.
- `CameraNativeView.kt`: attachment to the active preview/stream pipeline.

Run Dart tests from this package with `flutter test`. From the consuming app's
Android directory, run `./gradlew :rtmp_streaming:testDebugUnitTest` and, with an
Android emulator/device connected, `./gradlew :rtmp_streaming:connectedDebugAndroidTest`.
The latter checks actual Canvas/GLES output pixels, alpha, layering, hidden updates,
image replacement and EGL context recreation. It is not a battery benchmark.

For a real-device check: show modules in preview, transmit to MediaMTX, change the
clock/score, hide/show/move them, stop/start transmission, background/return to the
app, and verify the received video. Compare 15–30 minute runs with and without
overlays at the same resolution/framerate/bitrate, recording FPS, dropped frames,
temperature and battery usage. Emulator timing cannot establish low-end phone cost.

Implementation references: [RootEncoder BaseFilterRender 2.8.1](https://github.com/pedroSG94/RootEncoder/blob/2.8.1/encoder/src/main/java/com/pedro/encoder/input/gl/render/filters/BaseFilterRender.java),
[Android GLUtils texture uploads](https://developer.android.com/reference/android/opengl/GLUtils).
