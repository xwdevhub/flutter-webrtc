import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  Log,
  Any,
} from '@ohos/flutter_ohos';
import FlutterMediaStream from './FlutterMediaStream';
import webrtc, { LoggingSeverity } from '@xw/webrtc';
import { FlutterVideoRendererManager } from './FlutterVideoRenderer';
import { dump, findArray, findBool, findMap, findNumber, findString, findValue, getString } from './Utils';
import FlutterWebrtcBase from './FlutterWebrtcBase';
import FlutterPeerconnection from './FlutterPeerconnection';
import FlutterAudioUtils, { RTCAVCastPickerFactory } from './FlutterAudioUtils';
import FlutterScreenCapture from './FlutterScreenCapture';

const TAG = "FlutterWebrtcPlugin";

export let localVideoTrack: webrtc.MediaStreamTrack | undefined;

/** FlutterWebrtcPlugin **/
export default class FlutterWebrtcPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private base?: FlutterWebrtcBase;
  private mediaStream?: FlutterMediaStream;
  private videoRendererManager?: FlutterVideoRendererManager;
  private peerconnection?: FlutterPeerconnection;
  private audioUtils?: FlutterAudioUtils;
  private screenCapture?: FlutterScreenCapture;

  constructor() {
    // `Logging.enableLogToDebugOutput(Logging.Severity.LS_INFO)`.
    webrtc.NativeLogging.enableLogToDebugOutput(LoggingSeverity.VERBOSE);
  }

  getUniqueClassName(): string {
    return "FlutterWebrtcPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    FlutterVideoRendererManager.register(binding);
    RTCAVCastPickerFactory.register(binding);

    this.base = new FlutterWebrtcBase(binding.getTextureRegistry(), binding.getBinaryMessenger());
    this.videoRendererManager = new FlutterVideoRendererManager(this.base);
    this.mediaStream = new FlutterMediaStream(this.base);
    this.peerconnection = new FlutterPeerconnection(this.base);
    this.audioUtils = new FlutterAudioUtils();
    this.screenCapture = new FlutterScreenCapture(this.base);

    this.channel = new MethodChannel(binding.getBinaryMessenger(), "FlutterWebRTC.Method");
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    Log.i(TAG, "onMethodCall, method: " + call.method + ", args: " + dump(call.args));

    if (call.method == "getPlatformVersion") {
      result.success("OpenHarmony ^ ^ ")
    } else if (call.method == "getSources") {
      this.mediaStream?.getSources(result);
    } else if (call.method == "getUserMedia") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const constraints: Map<string, Any> = findMap(call.args, "constraints");
      this.mediaStream?.getUserMedia(constraints, result);
    } else if (call.method == "createVideoRenderer") {
      this.videoRendererManager?.createVideoRendererTexture(result);
    } else if (call.method == 'videoRendererDispose') {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const textureId = findNumber(call.args, "textureId");
      this.videoRendererManager?.videoRendererDispose(textureId, result);
    } else if (call.method == "videoRendererSetSrcObject") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const textureId = findNumber(call.args, "textureId");
      const streamId = findString(call.args, "streamId");
      const ownerTag = findString(call.args, "ownerTag");
      Log.d(TAG, `videoRendererSetSrcObject: textureId=${textureId}, streamId=${streamId}, ownerTag=${ownerTag}`);
      this.videoRendererManager?.setMediaStream(textureId, streamId, ownerTag);
      result.success(null);
    } else if (call.method == "streamDispose") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const streamId: string = findString(call.args, "streamId");
      this.mediaStream?.mediaStreamDispose(streamId, result);
    } else if (call.method == "createPeerConnection") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const configuration: Any = findValue(call.args, "configuration");
      const constraints: Any = findValue(call.args, "constraints");
      this.peerconnection?.createRTCPeerConnection(configuration, constraints, result);
    } else if (call.method == "peerConnectionClose") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("peerConnectionCloseFailed",
          "peerConnectionClose() peerConnection is null", null);
        return;
      }
      this.peerconnection?.rtcPeerConnectionClose(pc, peerConnectionId, result);
    } else if (call.method == "addTransceiver") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const transceiverInit: Map<Any, Any> = findMap(call.args, "transceiverInit");
      const mediaType = findString(call.args, "mediaType");
      const trackId = findString(call.args, "trackId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("addTransceiver",
          "addTransceiver() peerConnection is null", null);
        return;
      }
      this.peerconnection?.addTransceiver(pc, trackId, mediaType, transceiverInit, result);
    } else if (call.method == "addTrack") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }

      const peerConnectionId = findString(call.args, "peerConnectionId");
      const trackId = findString(call.args, "trackId");
      const streamIds: Any[] = findArray(call.args, "streamIds");

      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("AddTrack", "AddTrack() peerConnection is null", null);
        return;
      }

      const track = this.base?.mediaTrackForId(trackId);
      if (!track) {
        result.error("AddTrack", "AddTrack() track is null", null);
        return;
      }

      let ids: string[] = [];
      for (let i = 0; i < streamIds.length; i++) {
        ids.push(getString(streamIds[i]));
      }

      this.peerconnection?.addTrack(pc, track, streamIds, result);
    } else if (call.method == "removeTrack") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const senderId = findString(call.args, "senderId");

      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("removeTrack", "removeTrack() peerConnection is null", null);
        return;
      }

      this.peerconnection?.removeTrack(pc, senderId, result);

    } else if (call.method == "createOffer") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const constraints: Map<Any, Any> = findMap(call.args, "constraints");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("createOfferFailed", "createOffer() peerConnection is null", null);
        return;
      }
      this.peerconnection?.createOffer(constraints, pc, result);

    } else if (call.method == "setLocalDescription") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const constraints: Map<Any, Any> = findMap(call.args, "description");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("setLocalDescriptionFailed",
          "setLocalDescription() peerConnection is null", null);
        return;
      }
      this.peerconnection?.setLocalDescription(constraints, pc, result);
    } else if (call.method == "setRemoteDescription") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const constraints: Map<Any, Any> = findMap(call.args, "description");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("setLocalDescriptionFailed",
          "setLocalDescription() peerConnection is null", null);
        return;
      }
      this.peerconnection?.setRemoteDescription(constraints, pc, result);
    } else if (call.method == "createAnswer") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const constraints: Map<Any, Any> = findMap(call.args, "constraints");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("createAnswer Failed", "createAnswer() peerConnection is null", null);
        return;
      }
      this.peerconnection?.createAnswer(constraints, pc, result);
    } else if (call.method == "addCandidate") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const constraints: Map<Any, Any> = findMap(call.args, "candidate");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("addCandidateFailed", "addCandidate() peerConnection is null", null);
        return;
      }
      this.peerconnection?.addIceCandidate(constraints, pc, result);
    } else if (call.method == "trackDispose") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const trackId = findString(call.args, "trackId");
      this.mediaStream?.mediaStreamTrackDispose(trackId, result);
    } else if (call.method == "rtpSenderSetParameters") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("rtpSenderSetParameters", "rtpSenderSetParameters() peerConnection is null", null);
        return;
      }
      this.peerconnection?.rtpSenderSetParameters(call.args, pc, result);
    } else if (call.method == "rtpSenderReplaceTrack") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("rtpSenderReplaceTrack", "rtpSenderReplaceTrack() peerConnection is null", null);
        return;
      }

      const trackId = findString(call.args, "trackId");
      const track = this.base?.mediaTrackForId(trackId) ?? null;

      const rtpSenderId = findString(call.args, "rtpSenderId");
      if (rtpSenderId.length == 0) {
        result.error("rtpSenderReplaceTrack",
          "rtpSenderReplaceTrack() rtpSenderId is null or empty", null);
        return;
      }
      this.peerconnection?.rtpSenderReplaceTrack(pc, track, rtpSenderId, result);
    } else if (call.method == "rtpSenderSetTrack") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("rtpSenderSetTrack", "rtpSenderSetTrack() peerConnection is null", null);
        return;
      }

      const trackId = findString(call.args, "trackId");
      const track = this.base?.mediaTrackForId(trackId) ?? null;

      const rtpSenderId = findString(call.args, "rtpSenderId");
      if (rtpSenderId.length == 0) {
        result.error("rtpSenderSetTrack",
          "rtpSenderSetTrack() rtpSenderId is null or empty", null);
        return;
      }
      this.peerconnection?.rtpSenderSetTrack(pc, track, rtpSenderId, result);
    } else if (call.method == "getTransceivers") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("rtpSenderSetTrack", "rtpSenderSetTrack() peerConnection is null", null);
        return;
      }

      this.peerconnection?.getTransceivers(pc, result);
    } else if (call.method == "getStats") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("rtpSenderSetTrack", "rtpSenderSetTrack() peerConnection is null", null);
        return;
      }
      const trackId = findString(call.args, "trackId");
      this.peerconnection?.getStats(trackId, pc, result);
    } else if (call.method == "getLocalDescription") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("rtpSenderSetTrack", "rtpSenderSetTrack() peerConnection is null", null);
        return;
      }
      this.peerconnection?.getLocalDescription(pc, result);
    } else if (call.method == "mediaStreamTrackHasTorch") {
      const trackId = findString(call.args, "trackId");
      this.mediaStream?.mediaStreamTrackHasTorch(trackId, result);
    } else if (call.method == "mediaStreamTrackSetTorch") {
      const trackId = findString(call.args, "trackId");
      const torch = findBool(call.args, "torch");
      this.mediaStream?.mediaStreamTrackSetTorch(trackId, torch, result);
    } else if (call.method == "selectAudioOutput") {
      const deviceId = findString(call.args, "deviceId");
      this.mediaStream?.selectAudioOutput(deviceId, result);
    } else if (call.method == "setCodecPreferences") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      const peerConnectionId = findString(call.args, "peerConnectionId");
      const pc = this.base?.peerConnectionForId(peerConnectionId);
      if (!pc) {
        result.error("setCodecPreferences", "setCodecPreferences() peerConnection is null", null);
        return;
      }
      let transceiverId = findString(call.args, "transceiverId")
      if (transceiverId.length == 0) {
        result.error("setCodecPreferences", "transceiverId is null or empty", null);
        return;
      }
      const codecs: Any[] = findArray(call.args, "codecs");
      if (codecs.length == 0) {
        result.error("Bad Arguments", "Codecs is required", null);
        return;
      }
      this.peerconnection?.rtpTransceiverSetCodecPreferences(pc, transceiverId, codecs, result);
    } else if (call.method == "enableSpeakerphone") {
      let enable = findBool(call.args, "enable");
      this.mediaStream?.setEnableSpeakerphone(enable, result);
    } else if (call.method == "createAVSession") {
      this.audioUtils?.createAVSession(result);
    } else if (call.method == "destroyAVSession") {
      this.audioUtils?.destroyAVSession(result);
    } else if (call.method == "getPreferOutputDevice") {
      this.mediaStream?.getPreferOutputDevice(result);
    } else if (call.method == "getDisplayMedia") {
      if (!call.args) {
        result.error("Bad Arguments", "Null constraints arguments received", null);
        return;
      }
      let constraints: Map<string, Any> = findMap(call.args, "constraints");
      this.screenCapture?.getDisplayMedia(constraints, result);
    } else if (call.method == "startBackgroundRunning") {
      this.screenCapture?.startBackgroundRunning(result);
    } else if (call.method == "stopBackgroundRunning") {
      this.screenCapture?.stopBackgroundRunning(result);
    } else {
      const errMsg = call.method + ' not implemented';
      Log.e(TAG, errMsg);
      // result.notImplemented()
      result.error('-501', errMsg, null)
    }
  }
}
