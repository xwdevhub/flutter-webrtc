import { Any, Log, MethodResult } from "@ohos/flutter_ohos";
import webrtc from "@xw/webrtc";
import FlutterWebrtcBase from "./FlutterWebrtcBase";
import { contextUtils, findMap, findNumber, findValue, JsonMap } from "./Utils";
import { bundleManager, WantAgent, wantAgent } from "@kit.AbilityKit";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { BusinessError } from "@kit.BasicServicesKit";

const TAG = "FlutterScreenCapture";

export default class FlutterScreenCapture {
  private base: FlutterWebrtcBase;
  private backgroundRunning = false;
  private bundleName?: string;

  constructor(base: FlutterWebrtcBase) {
    this.base = base;
  }

  public async getDisplayMedia(constraints: JsonMap, result: MethodResult) {
    let fps = 30.0;
    let width = 720;
    let height = 1280;

    let video: Any = findValue(constraints, "video");
    if (video instanceof Map) {
      let mandatory: JsonMap = findMap(video, "mandatory");
      let w = findNumber(mandatory, "width");
      if (w !== 0) {
        width = w;
      }

      let h = findNumber(mandatory, "height");
      if (h !== 0) {
        height = h;
      }

      let frameRate = findNumber(mandatory, "frameRate");
      if (frameRate !== 0) {
        fps = frameRate;
      }
    }


    let options: webrtc.DisplayMediaStreamOptions = {
      video: {
        width: width,
        height: height,
        ohosScreenCaptureAudioFilter: 'current-app', // 过滤当前应用播放的音频
        frameRate: fps,
      },
      audio: false,
      ohosSystemAudio: false,
    };

    let stream: webrtc.MediaStream = await this.base.mediaDevices.getDisplayMedia(options);

    let params: JsonMap = new Map();
    params.set("streamId", stream.id);

    params.set("audioTracks", []);

    let track = stream.getVideoTracks()[0];
    let videoTracks: JsonMap[] = [];
    let info: JsonMap = new Map();
    info.set("id", track.id);
    info.set("label", track.id);
    info.set("kind", track.kind);
    info.set("enabled", track.enabled);
    videoTracks.push(info);
    params.set("videoTracks", videoTracks);

    this.base.localTracks.set(track.id, track);

    this.base.localStreams.set(stream.id, stream);

    result.success(params);
  }

  private getBundleName() {
    if (!this.bundleName) {
      this.bundleName = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).name;
    }
    return this.bundleName;
  }

  public startBackgroundRunning(result: MethodResult) {
    if (this.backgroundRunning) {
      Log.d(TAG, "background task already running");
      result.success(null);
      return;
    }

    let wantAgentInfo: wantAgent.WantAgentInfo = {
      // 点击通知后，将要执行的动作列表
      // 添加需要被拉起应用的bundleName和abilityName
      wants: [
        {
          bundleName: this.getBundleName(),
          abilityName: "EntryAbility"
        }
      ],
      // 指定点击通知栏消息后的动作是拉起ability
      actionType: wantAgent.OperationType.START_ABILITY,
      // 使用者自定义的一个私有值
      requestCode: 0,
      // 点击通知后，动作执行属性
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      // extraInfo: { [backgroundTaskManager.BackgroundModeType.SUB_MODE] : backgroundTaskManager.BackgroundSubMode.CAR_KEY }
    };

    const context = contextUtils.getUIContext()?.getHostContext();
    if (!context) {
      result.error("startBackgroundRunning Failed", 'context invalid', null);
      return;
    }

    try {
      // 通过wantAgent模块下getWantAgent方法获取WantAgent对象
      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        try {
          let list: Array<string> = ["voip"];
          backgroundTaskManager.startBackgroundRunning(context, list, wantAgentObj)
            .then((res: backgroundTaskManager.ContinuousTaskNotification) => {
              Log.i(TAG, "Operation startBackgroundRunning succeeded");
              this.backgroundRunning = true;
              result.success(null);
              // 此处执行具体的长时任务逻辑，如录音，录制等。
            })
            .catch((error: BusinessError) => {
              Log.e(TAG,
                `Failed to Operation startBackgroundRunning. code is ${error.code} message is ${error.message}`);
              result.error("startBackgroundRunning Failed", `${error}`, null);
            });
        } catch (error) {
          Log.e(TAG,
            `Failed to Operation startBackgroundRunning. code is ${(error as BusinessError).code} message is ${(error as BusinessError).message}`);
          result.error("startBackgroundRunning Failed", `${error}`, null);
        }
      });
    } catch (error) {
      Log.e(TAG,
        `Failed to Operation getWantAgent. code is ${(error as BusinessError).code} message is ${(error as BusinessError).message}`);
      result.error("startBackgroundRunning Failed", `${error}`, null);
    }
  }

  public stopBackgroundRunning(result: MethodResult) {
    if (!this.backgroundRunning) {
      Log.d(TAG, "backgroundRunning not start");
      result.success(null);
      return;
    }

    const context = contextUtils.getUIContext()?.getHostContext();
    if (!context) {
      result.success(null);
      return;
    }

    backgroundTaskManager.stopBackgroundRunning(context)
      .then(() => {
        Log.i(TAG, `Succeeded in operationing stopBackgroundRunning.`);
        this.backgroundRunning = false;
        result.success(null);
      })
      .catch((err: BusinessError) => {
        Log.e(TAG, `Failed to operation stopBackgroundRunning. Code is ${err.code}, message is ${err.message}`);
        result.error("stopBackgroundRunning Failed", `code=${err.code}, message=${err.message}`, null);
      });
  }
}