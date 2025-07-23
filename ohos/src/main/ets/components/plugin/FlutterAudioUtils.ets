import {
  Any,
  BinaryMessenger,
  FlutterPluginBinding,
  Log,
  MessageCodec,
  MethodResult,
  PlatformViewFactory,
  StandardMessageCodec
} from "@ohos/flutter_ohos";
import common from "@ohos.app.ability.common";
import { contextUtils, dump, findNumber } from "./Utils";
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import {
  AVCastPicker,
  AVCastPickerColorMode,
  AVCastPickerState,
  AVCastPickerStyle,
  avSession
} from "@kit.AVSessionKit";
import { audio } from "@kit.AudioKit";

const TAG = "FlutterAudioUtils";

export default class FlutterAudioUtils {
  private avSession?: avSession.AVSession;

  constructor() {
  }

  public async createAVSession(result: MethodResult) {
    try {
      let context = contextUtils.getUIContext()!.getHostContext()!;
      this.avSession = await avSession.createAVSession(context, 'VOIP', 'voice_call');
      Log.i(TAG, 'createAVSession SUCCESS');
      result.success(null);
    } catch (error) {
      Log.e(TAG, `ERROR: ${error}`);
      result.error('createAVSession failed', `${error}`, null);
    }
  }

  public destroyAVSession(result: MethodResult) {
    this.avSession?.destroy();
  }
}

export class RTCAVCastPickerFactory extends PlatformViewFactory {
  message: BinaryMessenger;

  constructor(message: BinaryMessenger, createArgsCodes: MessageCodec<Object>) {
    super(createArgsCodes);
    this.message = message;
  }

  static register(binding: FlutterPluginBinding) {
    binding.getPlatformViewRegistry().registerViewFactory(
      'FlutterWebRTC/RTCAVCastPicker',
      new RTCAVCastPickerFactory(binding.getBinaryMessenger(), StandardMessageCodec.INSTANCE));
  }

  public create(context: common.Context, viewId: number, args: Any): PlatformView {
    Log.d(TAG, "RTCAVCastPickerFactory create, args: " + dump(args));
    return new RTCAVCastPicker(args);
  }
}

@Observed
export class RTCAVCastPicker extends PlatformView {
  public creationParams: Any

  constructor(creationParams: number) {
    super();
    this.creationParams = creationParams;
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(RTCAVCastPickerBuilder);
  }

  dispose(): void {
  }
}

@Builder
function RTCAVCastPickerBuilder(params: Params) {
  RTCAVCastPickerComponent({ params: params })
}

@Component
struct RTCAVCastPickerComponent {
  @Prop params: Params
  platformView = this.params.platformView as RTCAVCastPicker
  private pickerStyle: AVCastPickerStyle | undefined;
  @State pickerImage: ResourceStr = $r('app.media.ear');
  private routingManager?: audio.AudioRoutingManager;

  aboutToAppear() {
    Log.d(TAG, "RTCAVCastPickerComponent aboutToAppear, creationParams= " + dump(this.platformView.creationParams));
    let routingManager = audio.getAudioManager().getRoutingManager();
    let audioRendererInfo: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_VIDEO_COMMUNICATION,
      rendererFlags: 0
    }
    let desc = routingManager.getPreferredOutputDeviceForRendererInfoSync(audioRendererInfo);
    this.changePickerShow(desc);
    routingManager.on("preferOutputDeviceChangeForRendererInfo", audioRendererInfo, () => {
      let desc = routingManager.getPreferredOutputDeviceForRendererInfoSync(audioRendererInfo);
      this.changePickerShow(desc);
    });
    this.routingManager = routingManager;
  }

  aboutToDisappear(): void {
    Log.d(TAG, "RTCAVCastPickerComponent aboutToDisappear, creationParams= " + dump(this.platformView.creationParams));
    this.routingManager?.off("preferOutputDeviceChangeForRendererInfo");
  }

  private changePickerShow(desc: audio.AudioDeviceDescriptors | undefined) {
    if (!desc || desc.length == 0) {
      return;
    }
    switch (desc[0].deviceType) {
      case audio.DeviceType.EARPIECE:
        this.pickerImage = $r('app.media.ear');
        break;
      case audio.DeviceType.SPEAKER:
        this.pickerImage = $r('app.media.speaker');
        break;
      case audio.DeviceType.BLUETOOTH_SCO:
        this.pickerImage = $r('app.media.bluetooth');
        break;
      default:
        this.pickerImage = $r('app.media.ear');
        break;
    }
  }

  getPickerStyle(): AVCastPickerStyle {
    if (!this.pickerStyle) {
      let style = findNumber(this.platformView.creationParams, "pickerStyle");
      this.pickerStyle = style == 0 ? AVCastPickerStyle.STYLE_PANEL : AVCastPickerStyle.STYLE_MENU;
    }
    return this.pickerStyle;
  }

  build() {
    Button() {
      AVCastPicker({
        normalColor: Color.White,
        activeColor: Color.White,
        // colorMode: AVCastPickerColorMode.LIGHT,
        // pickerStyle: this.getPickerStyle(),
        customPicker: () => {
          this.ImageBuilder()
        },
        onStateChange: (state: AVCastPickerState) => {
          Log.i(TAG, `change avcastpicker: ${state}`);
        }
      })
    }
    .backgroundColor(Color.Transparent)
    .width('40vp')
    .height('40vp')
    .type(ButtonType.Circle)
  }

  @Builder
  ImageBuilder(): void {
    Image(this.pickerImage)
      .size({
        width: '18vp',
        height: '18vp',
      })
      .fillColor(Color.White)
  }
}