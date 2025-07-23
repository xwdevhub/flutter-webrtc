import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import common from '@ohos.app.ability.common';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import {
  Any,
  EventChannel,
  EventSink,
  FlutterPluginBinding,
  Log,
  MessageCodec,
  MethodResult,
  PlatformViewFactory,
  StandardMessageCodec,
  StreamHandler,
  TextureRegistry
} from '@ohos/flutter_ohos';
import webrtc, { ScalingMode, VideoRenderController } from '@xw/webrtc';
import FlutterWebrtcBase from './FlutterWebrtcBase';
import { contextUtils, dump, findNumber } from './Utils';

const TAG: string = 'FlutterVideoRenderer';

let textureIdSource = 0;

export class FlutterVideoRenderer implements StreamHandler {
  private eventChannel?: EventChannel;
  private eventSink: EventSink | null = null;
  private textureId: number;
  track: webrtc.MediaStreamTrack | null = null;

  constructor(registry: TextureRegistry, messenger: BinaryMessenger) {
    this.textureId = ++textureIdSource;
    this.eventChannel = new EventChannel(messenger, `FlutterWebRTC/Texture${this.textureId}`);
    this.eventChannel.setStreamHandler(this);
  }

  setVideoTrack(track: webrtc.MediaStreamTrack | null) {
    if (this.track != track) {
      this.track = track;
      let context = contextUtils.getUIContext()?.getHostContext();
      context?.eventHub.emit(`RTCVideoView.setVideoTrack${this.textureId}`, track);
    }
  }

  public getTextureId(): number {
    return this.textureId;
  }

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events;
  }

  onCancel(args: Any): void {
    this.eventSink = null;
  }
}

export class FlutterVideoRendererManager {
  static renderers = new Map<number, FlutterVideoRenderer>();
  private base: FlutterWebrtcBase;

  constructor(base: FlutterWebrtcBase) {
    this.base = base;
  }

  static register(binding: FlutterPluginBinding) {
    binding.getPlatformViewRegistry().registerViewFactory(
      'FlutterWebRTC/RTCVideoView',
      new RTCVideoViewFactory(binding.getBinaryMessenger(), StandardMessageCodec.INSTANCE));
  }

  createVideoRendererTexture(result: MethodResult) {
    const render = new FlutterVideoRenderer(this.base.registry, this.base.messenger);
    const textureId: number = render.getTextureId();
    FlutterVideoRendererManager.renderers.set(textureId, render);
    let params: Map<string, Any> = new Map();
    params.set("textureId", textureId);
    Log.d(TAG, `createVideoRenderer: ${dump(params)}`);
    result.success(params);
  }

  videoRendererDispose(textureId: number, result: MethodResult) {
    let renderers = FlutterVideoRendererManager.renderers;
    const renderer = renderers.get(textureId);
    if (renderer) {
      renderers.delete(textureId);
      Log.d(TAG, `videoRendererDispose: ${textureId}`);
      result.success(null);
      return;
    }
    result.error("VideoRendererDisposeFailed", "VideoRendererDispose() texture not found!", null);
  }

  setMediaStream(textureId: number, streamId: string, ownerTag: string) {
    const stream = this.base.mediaStreamForId(streamId, ownerTag);
    const renderer = FlutterVideoRendererManager.renderers.get(textureId)
    if (renderer) {
      if (stream) {
        const videoTracks = stream.getVideoTracks();
        if (videoTracks.length > 0) {
          renderer.setVideoTrack(videoTracks[0])
        }
      } else {
        renderer.setVideoTrack(null);
      }
    }
  }
}

export class RTCVideoViewFactory extends PlatformViewFactory {
  message: BinaryMessenger;

  constructor(message: BinaryMessenger, createArgsCodes: MessageCodec<Object>) {
    super(createArgsCodes);
    this.message = message;
  }

  public create(context: common.Context, viewId: number, args: Any): PlatformView {
    Log.d(TAG, "RTCVideoViewFactory create, args: " + dump(args));
    const textureId = findNumber(args, "textureId");
    return new RTCVideoView(textureId);
  }
}

@Observed
class RTCVideoView extends PlatformView {
  public textureId: number

  constructor(textureId: number) {
    super();
    this.textureId = textureId;
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(RTCVideoViewBuilder);
  }

  dispose(): void {
  }
}

@Builder
function RTCVideoViewBuilder(params: Params) {
  RTCVideoViewComponent({ params: params })
}

@Component
struct RTCVideoViewComponent {
  @Prop params: Params
  platformView = this.params.platformView as RTCVideoView
  private videoRenderController = new VideoRenderController();

  private getTextureId(): number {
    return this.platformView.textureId;
  }

  private setVideoTrack(track: webrtc.MediaStreamTrack | null) {
    setTimeout(() => {
      try {
        this.videoRenderController.setVideoTrack(track);
        // this.videoRenderController.setMirror(true);
        this.videoRenderController.setScalingMode(ScalingMode.AspectFit);
      } catch (e) {
        Log.e(TAG, 'set video track failed: ' + e);
      }
    }, 0);
  };

  aboutToAppear() {
    Log.d(TAG, "RTCVideoViewComponent aboutToAppear, textureId: " + this.getTextureId());
    const context = this.getUIContext().getHostContext();
    context?.eventHub.on(`RTCVideoView.setVideoTrack${this.getTextureId()}`,
      (track: webrtc.MediaStreamTrack | null) => {
        Log.d(TAG, "set video track on event, textureId: " + this.getTextureId() + ", " + dump(track));
        this.setVideoTrack(track);
      });
  }

  aboutToDisappear(): void {
    Log.d(TAG, "RTCVideoViewComponent aboutToDisappear");
    const context = contextUtils.getUIContext()?.getHostContext();
    context?.eventHub.off(`RTCVideoView.setVideoTrack${this.getTextureId()}`);
  }

  build() {
    XComponent({
      id: "RTCVideoView" + this.platformView.textureId,
      type: XComponentType.SURFACE,
      controller: this.videoRenderController,
    })
      .onLoad((context?) => {
        Log.d(TAG, "XComponent onLoad context: " + context);
        // Log.d(TAG, "surfaceId: " + this.videoRenderController.getXComponentSurfaceId());
        let track = FlutterVideoRendererManager.renderers.get(this.getTextureId())?.track;
        if (track != undefined) {
          Log.d(TAG, "XComponent set video track on load, textureId: " + this.getTextureId() + ", " + dump(track));
          this.setVideoTrack(track);
        }
      })
      .onDestroy(() => {
        Log.d(TAG, "XComponent onDestroy");
        this.setVideoTrack(null);
      })
  }
}

