import { Any, Log, MethodResult } from "@ohos/flutter_ohos";
import webrtc from "@xw/webrtc";
import {
  dump,
  findMap,
  findNumber,
  findNumberOrNull,
  findString,
  findStringOrNull,
  findValue,
  JsonMap,
  contextUtils,
  toJsonReady
} from "./Utils";
import abilityAccessCtrl, { PermissionRequestResult, Permissions } from '@ohos.abilityAccessCtrl';
import FlutterWebrtcBase from "./FlutterWebrtcBase";
import util from "@ohos.util";
import { camera } from "@kit.CameraKit";
import { audio } from "@kit.AudioKit";

const TAG = "FlutterMediaStream";

const kDefaultWidth: number = 1280;
const kDefaultHeight: number = 720;
const kDefaultFps: number = 30;
const kDefaultFaceMode: string = "user";

export default class FlutterMediaStream {
  private mediaDevices = new webrtc.MediaDevices();
  private base: FlutterWebrtcBase;
  private audioManager: audio.AudioManager;
  private audioRoutingManager: audio.AudioRoutingManager;
  private audioRendererInfo: audio.AudioRendererInfo;

  constructor(base: FlutterWebrtcBase) {
    this.base = base;
    this.audioManager = audio.getAudioManager();
    this.audioRoutingManager = this.audioManager.getRoutingManager();
    this.audioRoutingManager.on('deviceChange', audio.DeviceFlag.ALL_DEVICES_FLAG,
      (deviceChanged: audio.DeviceChangeAction) => {
        Log.i(TAG, 'device change type : ' + deviceChanged.type); // 设备连接状态变化，0为连接，1为断开连接。
        Log.i(TAG, 'device descriptor size : ' + deviceChanged.deviceDescriptors.length);
        Log.i(TAG, 'device change descriptor : ' + deviceChanged.deviceDescriptors[0].deviceRole); // 设备角色。
        Log.i(TAG, 'device change descriptor : ' + deviceChanged.deviceDescriptors[0].deviceType); // 设备类型。
        let info: JsonMap = new Map();
        info.set("event", "onDeviceChange");
        this.base.getEventSink()?.success(info);
      });
    this.audioRendererInfo = {
      // 需使用通话场景相应的参数。
      usage: audio.StreamUsage.STREAM_USAGE_VIDEO_COMMUNICATION, // 音频流使用类型：VOIP视频通话，默认为扬声器。
      rendererFlags: 0 // 音频渲染器标志：默认为0即可。
    }
    this.audioRoutingManager.on("preferOutputDeviceChangeForRendererInfo", this.audioRendererInfo,
      (desc: audio.AudioDeviceDescriptors) => {
        Log.i(TAG, 'preferOutputDeviceChangeForRendererInfo, desc=' + dump(desc));
        let info: JsonMap = new Map();
        info.set("event", "onDeviceChange");
        this.base.getEventSink()?.success(info);
      });
  }

  async getUserMedia(constraints: Map<string, Any>, result: MethodResult) {
    let stream: webrtc.MediaStream = new webrtc.MediaStream();

    let params: Map<string, Any> = new Map();
    params.set("streamId", stream.id);

    const audio: Any = findValue(constraints, "audio");
    if (audio) {
      if (!(await this.requestAccess(["ohos.permission.MICROPHONE"]))) {
        result.error("getUserMediaFailed", `MICROPHONE Permission Not Granted`, null);
        return;
      }
      if (typeof audio === 'boolean') {
        this.getUserAudio(constraints, stream, params);
      } else if (audio instanceof Map) {
        this.getUserAudio(constraints, stream, params);
      } else {
        params.set("audioTracks", []);
      }
    } else {
      params.set("audioTracks", []);
    }

    const video: Any = findValue(constraints, "video");
    params.set("videoTracks", []);
    if (video) {
      if (!(await this.requestAccess(["ohos.permission.CAMERA"]))) {
        result.error("getUserMediaFailed", `CAMERA Permission Not Granted`, null);
        return;
      }
      if (typeof video === "boolean") {
        this.getUserVideo(constraints, stream, params);
      } else if (video instanceof Map) {
        this.getUserVideo(constraints, stream, params);
      }
    }

    this.base.localStreams.set(stream.id, stream);
    result.success(params);
  }

  async requestAccess(permissionList: Permissions[]): Promise<boolean> {
    const status: PermissionRequestResult = await abilityAccessCtrl.createAtManager()
      .requestPermissionsFromUser(contextUtils.getUIContext()!.getHostContext()!, permissionList);

    let granted = true;
    for (let index = 0; index < status.permissions.length; index++) {
      Log.i(TAG, "request permission [" + status.permissions[index] + "] with result: " + status.authResults[index]);
      if (status.authResults[index] != abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        granted = false;
      }
    }
    return granted;
  }

  async getUserAudio(constraints: Map<string, Any>, stream: webrtc.MediaStream, params: Map<string, Any>) {
    let enableAudio = false;
    let audioConstraints: webrtc.MediaTrackConstraintSet = {};
    let audio: Any = findValue(constraints, "audio");
    if (typeof audio === "boolean") {
      enableAudio = audio;
      audioConstraints.autoGainControl = true;
      audioConstraints.echoCancellation = true;
      audioConstraints.noiseSuppression = true;
    } else if (audio instanceof Map) {
      enableAudio = true;
      audioConstraints = this.parseMediaConstraints(audio);
      audioConstraints.autoGainControl = true;
      audioConstraints.echoCancellation = true;
      audioConstraints.noiseSuppression = true;
    }

    if (!enableAudio) {
      return;
    }

    if (!this.base.factory) {
      return;
    }

    const source = this.base.factory.createAudioSource(audioConstraints);
    const uuid = util.generateRandomUUID(true);
    const track = this.base.factory.createAudioTrack(uuid, source);

    let trackInfo: Map<string, Any> = new Map();
    trackInfo.set("id", track.id);
    trackInfo.set("label", track.id);
    trackInfo.set("kind", track.kind);
    trackInfo.set("enabled", track.enabled);

    let settings: Map<string, Any> = new Map();
    settings.set("deviceId", audioConstraints.deviceId);
    settings.set("kind", "audioinput");
    settings.set("autoGainControl", true);
    settings.set("echoCancellation", true);
    settings.set("noiseSuppression", true);
    settings.set("channelCount", 1);
    settings.set("latency", 0);
    trackInfo.set("settings", settings);

    let audioTracks: JsonMap[] = [];
    audioTracks.push(trackInfo);
    params.set("audioTracks", audioTracks);
    stream.addTrack(track);

    this.base.localTracks.set(track.id, track);
  }

  getUserVideo(constraints: Map<string, Any>, stream: webrtc.MediaStream, params: Map<string, Any>) {
    let video: JsonMap = findMap(constraints, "video");

    const videoConstraints = this.parseMediaConstraints(video);

    if (!this.base.factory) {
      return;
    }

    const source = this.base.factory.createVideoSource(videoConstraints, false);
    source.startCapture();
    const uuid = util.generateRandomUUID(true);
    const track = this.base.factory.createVideoTrack(uuid, source);

    let videoTracks: JsonMap[] = [];
    let info: JsonMap = new Map();
    info.set("id", track.id);
    info.set("label", track.id);
    info.set("kind", track.kind);
    info.set("enabled", track.enabled);

    let settings: JsonMap = new Map();
    settings.set("deviceId", videoConstraints.deviceId);
    settings.set("kind", "videoinput");
    settings.set("width", videoConstraints.width);
    settings.set("height", videoConstraints.height);
    settings.set("frameRate", videoConstraints.frameRate);
    info.set("settings", settings);

    videoTracks.push(info);
    params.set("videoTracks", videoTracks);
    stream.addTrack(track);

    this.base.localTracks.set(track.id, track);
    this.base.videoSources.set(track.id, source);
  }

  parseMediaConstraints(constraints: Map<string, Any>): webrtc.MediaTrackConstraintSet {
    let media: webrtc.MediaTrackConstraintSet = {};
    const mandatory: Map<string, Any> = findMap(constraints, "mandatory");

    media.width = findNumber(constraints, "width", findNumber(mandatory, "width", kDefaultWidth));
    media.height = findNumber(constraints, "height", findNumber(mandatory, "height", kDefaultHeight));
    media.frameRate = this.findFrameRate(constraints) ?? this.findFrameRate(mandatory) ?? kDefaultFps;
    media.facingMode = findString(constraints, "facingMode", findString(mandatory, "facingMode", kDefaultFaceMode));
    media.deviceId = this.findDeviceId(constraints);

    return media;
  }

  findFrameRate(constraints: JsonMap): number | null {
    let frameRate = findNumberOrNull(constraints, "frameRate");
    if (frameRate) {
      return frameRate;
    }
    const str = findStringOrNull(constraints, "frameRate");
    if (!str) {
      return null;
    }
    const num = Number(str);
    return isNaN(num) ? null : num;
  }

  async getSources(result: MethodResult) {
    try {
      let devices = await this.mediaDevices.enumerateDevices();
      Log.i(TAG, `devices: ${dump(devices)}`);
      let resultMap: Map<string, Any> = new Map();
      const sources = devices.map((value: webrtc.MediaDeviceInfo) => {
        let source: Map<string, string> = new Map();
        source.set('deviceId', value.deviceId);
        source.set('groupId', value.groupId);
        source.set('label', value.label);
        source.set('kind', value.kind.toString());
        return source;
      })
      resultMap.set('sources', sources);
      result.success(resultMap);
    } catch (e) {
      Log.e(TAG, "dart -> ts fail, method: %{public}s, err: %{public}s", 'getSources', e.toString());
      result.error('-1', `${e.toString()}`, null);
      return;
    }
  }

  mediaStreamDispose(streamId: string, result: MethodResult) {
    const stream: webrtc.MediaStream | null = this.base.mediaStreamForId(streamId);

    if (!stream) {
      result.error("MediaStreamDisposeFailed",
        "stream [" + streamId + "] not found!", null);
      return;
    }

    const audioTracks = stream.getAudioTracks();
    for (const track of audioTracks) {
      stream.removeTrack(track);
      this.base.localTracks.delete(track.id);
      track.stop();
    }


    const videoTracks = stream.getVideoTracks();
    for (const track of videoTracks) {
      stream.removeTrack(track);
      this.base.localTracks.delete(track.id);
      track.stop();
      const source = this.base.videoSources.get(track.id);
      if (source && source.state != "ended") {
        source.stopCapture();
      }
    }

    this.base.removeStreamForId(streamId);
    result.success(null);
  }

  findDeviceId(mandatory: Any): string {
    let deviceId = findString(mandatory, "deviceId");
    if (deviceId.length == 0) {
      let optional: JsonMap[] = findValue(mandatory, "optional") ?? [];
      for (let v of optional) {
        const id = findString(v, "sourceId");
        if (id.length > 0) {
          deviceId = id;
          break;
        }
      }
    }
    return deviceId;
  }

  public mediaStreamTrackDispose(trackId: string, result: MethodResult) {
    for (const p of this.base.localStreams) {
      const stream = p[1];
      const audioTracks = stream.getAudioTracks();
      for (const track of audioTracks) {
        if (track.id == trackId) {
          Log.d(TAG, 'track dispose: ' + trackId);
          stream.removeTrack(track);
          track.stop();
        }
      }
      const videoTracks = stream.getVideoTracks();
      for (const track of videoTracks) {
        if (track.id == trackId) {
          Log.d(TAG, 'track dispose: ' + trackId);
          stream.removeTrack(track);
          track.stop();
          const source = this.base.videoSources.get(track.id);
          if (source && source.state != "ended") {
            source.stopCapture();
          }
        }
      }
    }
    this.base.removeMediaTrackForId(trackId);
    result.success(null);
  }

  public mediaStreamTrackHasTorch(trackId: string, result: MethodResult) {
    let track = this.base.mediaTrackForId(trackId);
    if (!track) {
      result.error("mediaStreamTrackHasTorchFailed", `track(${trackId}) not found`, null);
      return;
    }
    result.success(isTorchSupported());
  }

  public mediaStreamTrackSetTorch(trackId: string, torch: boolean, result: MethodResult) {
    let track = this.base.mediaTrackForId(trackId);
    if (!track) {
      result.error("mediaStreamTrackSetTorch failed", `track(${trackId}) not found`, null);
      return;
    }
    const source = this.base.videoSources.get(trackId);
    if (source?.state != "live") {
      result.error("mediaStreamTrackSetTorch failed", `video capture not working`, null);
      return;
    }
    let cm = camera.getCameraManager(contextUtils.getUIContext()!.getHostContext()!);
    cm.setTorchMode(torch ? camera.TorchMode.ON : camera.TorchMode.OFF);
    result.success(null);
  }

  public async selectAudioOutput(deviceId: string, result: MethodResult) {
    let deviceType = await this.audioDeviceIdToType(deviceId);
    if (deviceType != audio.DeviceType.EARPIECE && deviceType != audio.DeviceType.SPEAKER) {
      deviceType = audio.DeviceType.DEFAULT;
    }
    this.base.adm?.setDefaultOutputDevice(deviceType);
    result.success(null);
  }

  public setEnableSpeakerphone(enable: boolean, result: MethodResult) {
    // this.audioManager.getRoutingManager().setCommunicationDevice(audio.CommunicationDeviceType.SPEAKER, enable);
    this.base.adm?.setDefaultOutputDevice(enable ? audio.DeviceType.SPEAKER : audio.DeviceType.EARPIECE);
    result.success(null);
  }

  async audioDeviceIdToType(id: string): Promise<audio.DeviceType> {
    let devices = await this.mediaDevices.enumerateDevices();
    for (const device of devices) {
      if (device.deviceId == id) {
        let typeName = device.label.split(" (")[0];
        Log.d(TAG, "audioDeviceIdToType, typeName=" + typeName);
        switch (typeName) {
          case "Invalid":
            return audio.DeviceType.INVALID;
          case "Earpiece":
            return audio.DeviceType.EARPIECE;
          case "Speaker":
            return audio.DeviceType.SPEAKER;
          case "Headset":
            return audio.DeviceType.WIRED_HEADSET;
          case "Wired headphones":
            return audio.DeviceType.WIRED_HEADPHONES;
          case "Bluetooth SCO":
            return audio.DeviceType.BLUETOOTH_SCO;
          case "Bluetooth A2DP":
            return audio.DeviceType.BLUETOOTH_A2DP;
          case "Microphone":
            return audio.DeviceType.MIC;
          case "USB headset":
            return audio.DeviceType.USB_HEADSET;
          case "Display port":
            return audio.DeviceType.DISPLAY_PORT;
          case "Remote cast":
            return audio.DeviceType.REMOTE_CAST;
          default:
            return audio.DeviceType.DEFAULT;
        }
      }
    }
    return audio.DeviceType.DEFAULT;
  }

  public async getPreferOutputDevice(result: MethodResult) {
    try {
      let descs = this.audioRoutingManager.getPreferredOutputDeviceForRendererInfoSync(this.audioRendererInfo);
      if (descs.length == 0) {
        result.error("getPreferOutputDevice failed", `no device`, null);
        return;
      }
      let params: JsonMap = new Map;
      params.set("deviceId", descs[0].id.toString());
      params.set("name", descs[0].name);
      params.set("deviceType", descs[0].deviceType);
      result.success(params);
    } catch (error) {
      result.error("getPreferOutputDevice failed", `${error}`, null);
    }
  }
}

function isTorchSupported(): boolean {
  let torchSupport: boolean = false;
  try {
    let cm = camera.getCameraManager(contextUtils.getUIContext()!.getHostContext()!);
    torchSupport = cm.isTorchModeSupported(camera.TorchMode.ON);
  } catch (error) {
    torchSupport = false;
  }
  return torchSupport;
}

