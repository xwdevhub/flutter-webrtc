import { Any, BinaryMessenger, EventChannel, EventSink, Log, StreamHandler, TextureRegistry } from "@ohos/flutter_ohos";
import webrtc from "@xw/webrtc";
import { contextUtils, dump } from "./Utils";
import { audio } from "@kit.AudioKit";
import { BusinessError } from "@kit.BasicServicesKit";
import { FlutterPeerConnectionObserver } from "./FlutterPeerconnection";
import { JSON } from "@kit.ArkTS";
import { avSession } from "@kit.AVSessionKit";

const TAG = "FlutterWebrtcBase";

const kEventChannelName = "FlutterWebRTC.Event";

export default class FlutterWebrtcBase implements StreamHandler {
  public registry: TextureRegistry;
  public messenger: BinaryMessenger;
  public peerconnections: Map<string, webrtc.RTCPeerConnection> = new Map();
  public localStreams: Map<string, webrtc.MediaStream> = new Map();
  public localTracks: Map<string, webrtc.MediaStreamTrack> = new Map();
  public videoSources: Map<string, webrtc.VideoSource> = new Map();
  public peerconnectionObservers: Map<string, FlutterPeerConnectionObserver> = new Map();
  public factory?: webrtc.PeerConnectionFactory;
  public adm?: webrtc.AudioDeviceModule;
  private eventChannel: EventChannel;
  private eventSink: EventSink | null = null;
  private avSession?: avSession.AVSession;

  constructor(registry: TextureRegistry, messenger: BinaryMessenger) {
    this.registry = registry;
    this.messenger = messenger;

    // 设置音频策略，允许和其它音频流并发
    let strategy: audio.AudioSessionStrategy = {
      concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
    };
    let audioManager = audio.getAudioManager();
    let audioSessionManager = audioManager.getSessionManager();
    audioSessionManager.activateAudioSession(strategy).then(() => {
      Log.i(TAG, 'activateAudioSession SUCCESS');
    }).catch((err: BusinessError) => {
      Log.e(TAG, `ERROR: ${err}`);
    });

    this.createAudioDeviceModule();
    this.createPeerConnectionFactory();

    this.eventChannel = new EventChannel(messenger, kEventChannelName);
    this.eventChannel.setStreamHandler(this);
  }

  public peerConnectionForId(id: string): webrtc.RTCPeerConnection | null {
    const v = this.peerconnections.get(id);
    if (v) {
      return v;
    }
    return null;
  }

  public getRtpSenderById(pc: webrtc.RTCPeerConnection, id: string): webrtc.RTCRtpSender | null {
    for (const item of pc.getSenders()) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  private createPeerConnectionFactory() {
    this.factory = new webrtc.PeerConnectionFactory({
      // videoEncoderFactory: new webrtc.HardwareVideoEncoderFactory,
      // videoDecoderFactory: new webrtc.HardwareVideoDecoderFactory,
      adm: this.adm
    });
    Log.i(TAG, 'this.pcf: ' + dump(this.factory));

    // MediaDevices 依赖默认的 PeerConnnectionFactory，且需要与创建 PeerConnection 的是同一个。
    webrtc.PeerConnectionFactory.setDefault(this.factory);

    // let filesDir = getContext().filesDir;
    // let file = fs.openSync(filesDir + '/test.txt', fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    // this.factory.startAecDump(file.fd, -1);
  }

  private createAudioDeviceModule() {
    this.adm = new webrtc.AudioDeviceModule({ useStereoInput: true, useStereoOutput: true });
    this.adm.oncapturererror = (event) => {
      Log.e(TAG, 'oncapturererror: ' + dump(event));
    };
    this.adm.oncapturerstatechange = (event) => {
      Log.i(TAG, 'oncapturerstatechange: ' + dump(event));
    };
    this.adm.oncapturersamplesready = (event) => {
      Log.d(TAG, 'oncapturersamplesready: ' + dump(event));
    };
    this.adm.onrenderererror = (event) => {
      Log.e(TAG, 'onrenderererror: ' + dump(event));
    };
    this.adm.onrendererstatechange = (event) => {
      Log.i(TAG, 'onrendererstatechange: ' + dump(event));
    };
    Log.d(TAG, 'this.adm: ' + dump(this.adm));
  }

  getEventSink(): EventSink | null {
    return this.eventSink;
  }

  public mediaStreamForId(id: string, ownerTag: string = ""): webrtc.MediaStream | null {
    if (ownerTag.length > 0) {
      if (ownerTag == "local") {
        const stream = this.localStreams.get(id)
        if (stream) {
          return stream;
        }
      } else {
        const pco = this.peerconnectionObservers.get(ownerTag);
        const stream = pco?.mediaStreamForId(id);
        if (stream) {
          return stream;
        }
      }
    }

    if (this.localStreams.has(id)) {
      return this.localStreams.get(id) as webrtc.MediaStream
    }

    return null
  }

  public removeStreamForId(id: string): void {
    this.localStreams.delete(id);
  }

  public mediaTrackForId(id: string): webrtc.MediaStreamTrack | null {
    const track = this.localTracks.get(id);
    if (track) {
      return track;
    }

    for (const it of this.peerconnectionObservers) {
      const pco = it[1];
      const t = pco.mediaTrackForId(id);
      if (t) {
        return t;
      }
    }

    return null;
  }

  public removeMediaTrackForId(id: string): void {
    this.localTracks.delete(id);
  }

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events;
  }

  onCancel(args: Any): void {
    this.eventSink = null
  }
}