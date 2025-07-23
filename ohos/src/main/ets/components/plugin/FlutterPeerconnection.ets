import { Any, BinaryMessenger, EventChannel, EventSink, Log, MethodResult, StreamHandler } from "@ohos/flutter_ohos";
import FlutterWebrtcBase from "./FlutterWebrtcBase";
import {
  dump,
  findArray,
  findBoolOrNull,
  findMap,
  findNumber,
  findNumberOrNull,
  findString,
  findStringOrNull,
  findValue,
  getString,
  hasKey,
  JsonMap
} from "./Utils";
import util from '@ohos.util';
import webrtc from "@xw/webrtc";

const TAG = "FlutterPeerconnection";

function rtpParametersToMap(rtpParameters: webrtc.RTCRtpParameters): Map<string, Any> {
  let info: Map<string, Any> = new Map();
  if (typeof (rtpParameters as webrtc.RTCRtpSendParameters).transactionId == "string") {
    const transactionId = (rtpParameters as webrtc.RTCRtpSendParameters).transactionId;
    info.set("transactionId", transactionId);
  }

  let rtcp: Map<string, Any> = new Map();
  rtcp.set("cname", rtpParameters.rtcp.cname);
  rtcp.set("reducedSize", rtpParameters.rtcp.reducedSize);
  info.set("rtcp", rtcp);

  let headerExtensions: Map<string, Any>[] = [];
  for (const extension of rtpParameters.headerExtensions) {
    let map: Map<string, Any> = new Map();
    map.set("uri", extension.uri);
    map.set("id", extension.id);
    map.set("encrypted", extension.encrypted);
    headerExtensions.push(map);
  }
  info.set("headerExtensions", headerExtensions);

  if ((rtpParameters as webrtc.RTCRtpSendParameters).encodings instanceof Array) {
    let encodingsInfo: Map<string, Any>[] = [];
    const encodings = (rtpParameters as webrtc.RTCRtpSendParameters).encodings;
    for (const encoding of encodings) {
      let map: Map<string, Any> = new Map();
      map.set("active", encoding.active);
      map.set("maxBitrate", encoding.maxBitrate);
      // map.set("minBitrate", encoding.minBitrate);
      map.set("maxFramerate", encoding.maxFramerate);
      map.set("scaleResolutionDownBy", encoding.scaleResolutionDownBy);
      // map.set("ssrc", encoding.ssrc);
      encodingsInfo.push(map);
    }
    info.set("encodings", encodingsInfo);
  }


  let codecsInfo: Map<string, Any>[] = [];
  for (const codec of rtpParameters.codecs) {
    let map: Map<string, Any> = new Map();
    // map.set("name", codec.name);
    map.set("payloadType", codec.payloadType);
    map.set("clockRate", codec.clockRate);
    map.set("numChannels", codec.channels);

    // let param: Map<string, Any> = new Map();
    // for (const item of codec.parameters) {
    //   param.set(item.first, item.second);
    // }
    // map.set("parameters", param);

    // map.set("kind", codec.kind);
    codecsInfo.push(map);
  }
  info.set("codecs", codecsInfo);

  // info.set("rtpParameters.codecs", rtpParameters.degradationPreference);

  return info;
}


function dtmfSenderToMap(dtmfSender: webrtc.RTCDTMFSender | null, id: string): Map<string, Any> {
  let info: Map<string, Any> = new Map();
  if (dtmfSender) {
    info.set("dtmfSenderId", id);
    // TODO: FIX interToneGap, duration
    // info.set("interToneGap", dtmfSender.interToneGap);
    // info.set("duration", dtmfSender.duration);
  }
  return info;
}

function rtpReceiverToMap(receiver: webrtc.RTCRtpReceiver): Map<string, Any> {
  let info: Map<string, Any> = new Map();
  info.set("receiverId", receiver.id);
  info.set("rtpParameters", rtpParametersToMap(receiver.getParameters()));
  info.set("track", mediaTrackToMap(receiver.track));
  return info;
}

function rtpSenderToMap(sender: webrtc.RTCRtpSender): Map<string, Any> {
  let info: Map<string, Any> = new Map();
  const id = sender.id;
  info.set("senderId", id);
  info.set("ownsTrack", true);
  info.set("dtmfSender", dtmfSenderToMap(sender.dtmf, id));
  info.set("rtpParameters", rtpParametersToMap(sender.getParameters()));
  info.set("track", mediaTrackToMap(sender.track));
  return info;
}

function transceiverToMap(transceiver: webrtc.RTCRtpTransceiver): Map<string, Any> {
  let info: Map<string, Any> = new Map();
  const mid = transceiver.mid ?? "";
  info.set("transceiverId", mid);
  info.set("mid", mid);
  info.set("direction", transceiver.direction);
  info.set("sender", rtpSenderToMap(transceiver.sender));
  info.set("receiver", rtpReceiverToMap(transceiver.receiver));
  return info;
}

function mediaTrackToMap(track: webrtc.MediaStreamTrack | null): Map<string, Any> {
  let info: Map<string, Any> = new Map();
  if (!track) {
    return info;
  }
  info.set("id", track.id);
  info.set("kind", track.kind);
  if ("video" == track.kind) {
    info.set("readyState", track.readyState);
    info.set("label", "video");
  } else if ("audio" == track.kind) {
    info.set("readyState", track.readyState);
    info.set("label", "audio");
  }
  info.set("enabled", track.enabled);
  return info;
}

function mediaStreamToMap(stream: webrtc.MediaStream, id: string): Map<string, Any> {
  let params: Map<string, Any> = new Map();
  params.set("streamId", stream.id);
  params.set("ownerTag", id);
  let audioTracks: Any[] = [];
  for (const val of stream.getAudioTracks()) {
    audioTracks.push(mediaTrackToMap(val));
  }
  params.set("audioTracks", audioTracks);

  let videoTracks: Any[] = [];
  for (const val of stream.getVideoTracks()) {
    videoTracks.push(mediaTrackToMap(val));
  }
  params.set("videoTracks", videoTracks);
  return params;
}


export class FlutterPeerConnectionObserver implements StreamHandler {
  private base: FlutterWebrtcBase;
  private peerconnection: webrtc.RTCPeerConnection;
  private eventSink: EventSink | null = null;
  private id: string
  private remoteStreams: Map<string, webrtc.MediaStream> = new Map();

  constructor(base: FlutterWebrtcBase, peerconnection: webrtc.RTCPeerConnection, messenger: BinaryMessenger,
    channelName: string, peerConnectionId: string) {
    const eventChannel = new EventChannel(messenger, channelName);
    eventChannel.setStreamHandler(this);
    this.peerconnection = peerconnection;
    this.base = base;
    this.id = peerConnectionId;
    this.registerRTCPeerConnectionObserver();
  }

  public mediaStreamForId(id: string): webrtc.MediaStream | null {
    const v = this.remoteStreams.get(id);
    if (v) {
      return v
    }
    return null;
  }

  public mediaTrackForId(id: string): webrtc.MediaStreamTrack | null {
    for (const kv of this.remoteStreams) {
      const remoteStream = kv[1];
      const audioTracks = remoteStream.getAudioTracks();
      for (const track of audioTracks) {
        if (track.id == id) {
          return track;
        }
      }
      const videoTracks = remoteStream.getVideoTracks();
      for (const track of videoTracks) {
        if (track.id == id) {
          return track;
        }
      }
    }
    return null;
  }

  private registerRTCPeerConnectionObserver() {
    this.peerconnection.onnegotiationneeded = this.onnegotiationneeded;
    this.peerconnection.onicecandidate = this.onicecandidate;
    this.peerconnection.onicecandidateerror = this.onicecandidateerror;
    this.peerconnection.oniceconnectionstatechange = this.oniceconnectionstatechange;
    this.peerconnection.onicegatheringstatechange = this.onicegatheringstatechange;
    this.peerconnection.onsignalingstatechange = this.onsignalingstatechange;
    this.peerconnection.onconnectionstatechange = this.onconnectionstatechange;
    this.peerconnection.ontrack = this.ontrack;
    this.peerconnection.onaddstream = this.onaddstream;
    this.peerconnection.ondatachannel = this.ondatachannel;
  }

  private onaddstream = (ev: webrtc.RTCAddStreamEvent) => {
    let stream = ev.stream;

    let params: JsonMap = new Map();
    params.set("event", "onAddStream");
    params.set("streamId", stream.id);
    let audioTracks: JsonMap[] = [];
    for (const track of stream.getAudioTracks()) {
      let audioTrack: JsonMap = new Map();
      audioTrack.set("id", track.id);
      audioTrack.set("label", track.id);
      audioTrack.set("kind", track.kind);
      audioTrack.set("enabled", track.enabled);
      audioTrack.set("remote", true);
      audioTrack.set("readyState", "live");
      audioTracks.push(audioTrack);
    }
    params.set("audioTracks", audioTracks);

    let videoTracks: JsonMap[] = [];
    for (const track of stream.getVideoTracks()) {
      let videoTrack: JsonMap = new Map();
      videoTrack.set("id", track.id);
      videoTrack.set("label", track.id);
      videoTrack.set("kind", track.kind);
      videoTrack.set("enabled", track.enabled);
      videoTrack.set("remote", true);
      videoTrack.set("readyState", "live");
      audioTracks.push(videoTrack);
    }
    params.set("videoTracks", videoTracks);

    Log.d(TAG, "onAddStream " + dump(params));
    this.eventSink?.success(params);
  }
  private ondatachannel = (ev: webrtc.RTCDataChannelEvent) => {
    const dataChannel = ev.channel;
    const channelId = ev.channel.id;
    const channelUuid = util.generateRandomUUID(true);

    const eventChannel = "FlutterWebRTC/dataChannelEvent" + this.id + channelUuid;
    // TODO: 1. 创建 FlutterRTCDataChannelObserver 2. 添加到 data_channel_observers_

    let params: Map<string, Any> = new Map();
    params.set("event", "didOpenDataChannel");
    params.set("id", channelId);
    params.set("label", dataChannel.label);
    params.set("flutterId", channelUuid);
    this.eventSink?.success(params);
  };
  private ontrack = (ev: webrtc.RTCTrackEvent) => {
    let params: Map<string, Any> = new Map();
    let streamsInfo: Any[] = [];
    const streams = ev.streams;
    for (const item of streams) {
      streamsInfo.push(mediaStreamToMap(item, this.id));
    }
    params.set("event", "onTrack");
    params.set("streams", streamsInfo);
    params.set("track", mediaTrackToMap(ev.track));
    params.set("receiver", rtpReceiverToMap(ev.receiver));
    params.set("transceiver", transceiverToMap(ev.transceiver));

    if (streams.length > 0) {
      this.remoteStreams.set(streams[0].id, streams[0]);
    }

    Log.d(TAG, "ontrack " + dump(params));
    this.eventSink?.success(params);
  };
  private onnegotiationneeded = (ev: webrtc.Event) => {
    let params: Map<string, Any> = new Map();
    params.set("event", "onRenegotiationNeeded");
    this.eventSink?.success(params);
  };
  private onicecandidateerror = (ev: webrtc.RTCPeerConnectionIceErrorEvent) => {
    let params: Map<string, Any> = new Map();
    params.set("event", "onCandidateError");
    this.eventSink?.success(params);
  };
  private onicecandidate = (ev: webrtc.RTCPeerConnectionIceEvent) => {
    let params: Map<string, Any> = new Map();
    params.set("event", "onCandidate");
    let cand: Map<string, Any> = new Map();
    cand.set("candidate", ev.candidate?.candidate);
    cand.set("sdpMLineIndex", ev.candidate?.sdpMLineIndex);
    cand.set("sdpMid", ev.candidate?.sdpMid);
    params.set("candidate", cand);
    this.eventSink?.success(params);
  };
  private onsignalingstatechange = (ev: webrtc.Event) => {
    let params: Map<string, Any> = new Map();
    params.set("event", "signalingState");
    params.set("state", this.peerconnection.signalingState);
    this.eventSink?.success(params);
  };
  private onconnectionstatechange = (ev: webrtc.Event) => {
    let params: Map<string, Any> = new Map();
    params.set("event", "peerConnectionState");
    params.set("state", this.peerconnection.connectionState);
    this.eventSink?.success(params);
  };
  private onicegatheringstatechange = (ev: webrtc.Event) => {
    let params: Map<string, Any> = new Map();
    params.set("event", "iceGatheringState");
    params.set("state", this.peerconnection.iceGatheringState);
    this.eventSink?.success(params);
  };
  private oniceconnectionstatechange = (ev: webrtc.Event) => {
    let params: Map<string, Any> = new Map();
    params.set("event", "iceConnectionState");
    params.set("state", this.peerconnection.iceConnectionState);
    this.eventSink?.success(params);
  };

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events;
  }

  onCancel(args: Any): void {
    this.eventSink = null;
  }
}

export default class FlutterPeerConnection {
  private base: FlutterWebrtcBase;

  constructor(base: FlutterWebrtcBase) {
    this.base = base;
  }

  public createRTCPeerConnection(configuration: Any, constraints: Any, result: MethodResult): void {
    let config: webrtc.RTCConfiguration = {};

    let iceServers: webrtc.RTCIceServer[] = [];
    const iceServersArray: JsonMap[] = findArray(configuration, "iceServers");
    for (const iceServersMap of iceServersArray) {
      if (iceServersMap instanceof Map && (hasKey(iceServersMap, "url") || hasKey(iceServersMap, "urls"))) {
        iceServers.push({
          urls: findStringOrNull(iceServersMap, "url") ?? findString(iceServersMap, "urls"),
          username: findString(iceServersMap, "username"),
          credential: findString(iceServersMap, "credential"),
        });
      }
    }
    if (iceServers.length > 0) {
      config.iceServers = iceServers;
    }

    if (hasKey(configuration, "iceTransportPolicy")) {
      const v = findString(configuration, "iceTransportPolicy")
      if (v == "all" || v == "relay") {
        config.iceTransportPolicy = v;
      }
    }

    if (hasKey(configuration, "bundlePolicy")) {
      const v = findString(configuration, "bundlePolicy")
      if (v == "balanced" || v == "max-compat" || v == "max-bundle") {
        config.bundlePolicy = v;
      }
    }

    if (hasKey(configuration, "rtcpMuxPolicy")) {
      const v = findString(configuration, "rtcpMuxPolicy")
      if (v == "require") {
        config.rtcpMuxPolicy = v;
      }
    }

    if (hasKey(configuration, "iceCandidatePoolSize")) {
      config.iceCandidatePoolSize = findNumber(configuration, "iceCandidatePoolSize")
    }

    let uuid = util.generateRandomUUID(true);
    const pc = this.base.factory!.createPeerConnection(config);
    this.base.peerconnections.set(uuid, pc);

    const eventChannel = "FlutterWebRTC/peerConnectionEvent" + uuid;

    const observer = new FlutterPeerConnectionObserver(this.base, pc, this.base.messenger, eventChannel, uuid);

    this.base.peerconnectionObservers.set(uuid, observer);

    let params: Map<string, Any> = new Map();
    params.set("peerConnectionId", uuid);
    result.success(params);
  }

  public rtcPeerConnectionClose(pc: webrtc.RTCPeerConnection, uuid: string, result: MethodResult): void {
    const peerconnection = this.base.peerconnections.get(uuid);
    if (peerconnection) {
      peerconnection.close();
      this.base.peerconnections.delete(uuid);
    }

    const pco = this.base.peerconnectionObservers.get(uuid)
    if (pco) {
      this.base.peerconnectionObservers.delete(uuid);
    }

    result.success(null);
  }

  public addTransceiver(
    pc: webrtc.RTCPeerConnection,
    trackId: string,
    mediaType: string,
    transceiverInit: Map<Any, Any>,
    result: MethodResult): void {
    const track = this.base.mediaTrackForId(trackId);
    const type = mediaType;

    if (transceiverInit.size > 0) {
      const transceiver =
        track != null ?
        pc.addTransceiver(track, this.mapToRtpTransceiverInit(transceiverInit)) :
        pc.addTransceiver(type, this.mapToRtpTransceiverInit(transceiverInit));
      // Log.d(TAG, "addTransceiver success: " + dump(transceiverToMap(transceiver)));
      result.success(transceiverToMap(transceiver));
      return;
    } else {
      const transceiver =
        track != null ? pc.addTransceiver(track) : pc.addTransceiver(type);
      // Log.d(TAG, "addTransceiver success: " + dump(transceiverToMap(transceiver)));
      result.success(transceiverToMap(transceiver));
      return;
    }
  }


  stringToTransceiverDirection(direction: string): webrtc.RTCRtpTransceiverDirection {
    if ("sendrecv" == direction) {
      return direction;
    } else if ("sendonly" == direction) {
      return direction;
    } else if ("recvonly" == direction) {
      return direction;
    } else if ("stopped" == direction) {
      return direction;
    } else if ("inactive" == direction) {
      return direction;
    }
    return "inactive";
  }

  mapToEncoding(params: Map<Any, Any>): webrtc.RTCRtpEncodingParameters {
    const encoding: webrtc.RTCRtpEncodingParameters = {};
    encoding.active = true;
    encoding.scaleResolutionDownBy = 1.0;

    let value: Any = findValue(params, "active");
    if (typeof value == "boolean") {
      encoding.active = value;
    }

    value = findStringOrNull(params, "rid");
    if (value) {
      encoding.rid = value;
    }

    // value = findNumberIf(params, "ssrc");
    // if (value) {
    //   encoding.ssrc = value;
    // }

    // value = findNumberIf(params, "minBitrate");
    // if (value) {
    //   encoding.minBitrate = value;
    // }

    value = findNumberOrNull(params, "maxBitrate");
    if (value) {
      encoding.maxBitrate = value;
    }

    value = findNumberOrNull(params, "maxFramerate");
    if (value) {
      encoding.maxFramerate = value;
    }

    // value = findNumberIf(params, "numTemporalLayers");
    // if (value) {
    //   encoding.numTemporalLayers = value;
    // }

    value = findNumberOrNull(params, "scaleResolutionDownBy");
    if (value) {
      encoding.scaleResolutionDownBy = value;
    }

    return encoding;
  }

  public mapToRtpTransceiverInit(params: Map<Any, Any>): webrtc.RTCRtpTransceiverInit {
    const streamIds: Any[] = findArray(params, "streamIds");

    let streams: webrtc.MediaStream[] = [];
    for (let i = 0; i < streamIds.length; i++) {
      const item: Any = streamIds[i];
      const id = getString(item);
      const stream = this.base.mediaStreamForId(id);
      if (stream) {
        streams.push(stream);
      }
    }

    // export interface RTCRtpTransceiverInit {
    //   direction?: RTCRtpTransceiverDirection;
    //   streams?: MediaStream[];
    //   sendEncodings?: RTCRtpEncodingParameters[];
    // }

    let dir: webrtc.RTCRtpTransceiverDirection = "inactive";
    const direction = findStringOrNull(params, "direction");
    if (direction) {
      dir = this.stringToTransceiverDirection(direction);
    }

    const sendEncodings: Any[] = findArray(params, "sendEncodings");
    let encodings: webrtc.RTCRtpEncodingParameters[] = [];
    for (let i = 0; i < sendEncodings.length; i++) {
      encodings.push(this.mapToEncoding(sendEncodings[i]))
    }

    const init: webrtc.RTCRtpTransceiverInit = {
      direction: dir,
      streams: streams,
      sendEncodings: encodings,
    };

    return init;
  }

  public addTrack(
    pc: webrtc.RTCPeerConnection,
    track: webrtc.MediaStreamTrack,
    streamIds: string[],
    result: MethodResult) {
    const kind = track.kind;
    let streams: webrtc.MediaStream[] = [];
    for (let i = 0; i < streamIds.length; i++) {
      const s = this.base?.mediaStreamForId(streamIds[i]);
      if (s) {
        streams.push(s);
      }
    }
    if (kind == "audio") {
      const sender = pc.addTrack(track, ...streams);
      result.success(rtpSenderToMap(sender));
      return;
    }

    if (kind == "video") {
      const sender = pc.addTrack(track, ...streams);
      result.success(rtpSenderToMap(sender));
      return;
    }

    result.success(null);
  }

  public removeTrack(
    pc: webrtc.RTCPeerConnection,
    senderId: string,
    result: MethodResult) {
    const sender = this.base?.getRtpSenderById(pc, senderId);
    if (!sender) {
      result.error("RemoveTrack", "not find RtpSender ", null);
      return;
    }


    let map: Map<string, boolean> = new Map();
    try {
      pc.removeTrack(sender);
      Log.e(TAG, "removeTrack() succeeded");
      map.set("result", true);
    } catch (e) {
      Log.e(TAG, "removeTrack() failed: " + e);
      map.set("result", false);
    }

    result.success(map);
  }

  public createOffer(constraintsMap: Map<Any, Any>, pc: webrtc.RTCPeerConnection, result: MethodResult): void {
    const iceRestart = findBoolOrNull(constraintsMap, "iceRestart");
    let options: webrtc.RTCOfferOptions = {};
    if (iceRestart) {
      options.iceRestart = iceRestart;
    }
    pc.createOffer(options).then((v) => {
      let params: Map<string, Any> = new Map();
      params.set("sdp", v.sdp);
      params.set("type", v.type)
      result.success(params);
    }).catch((error: Any) => {
      result.error("createOfferFailed", `${error}`, null);
    });
  }

  public createAnswer(constraintsMap: Map<Any, Any>, pc: webrtc.RTCPeerConnection, result: MethodResult) {
    let options: webrtc.RTCAnswerOptions = {};
    pc.createAnswer(options).then((v) => {
      let params: Map<string, Any> = new Map();
      params.set("sdp", v.sdp);
      params.set("type", v.type)
      result.success(params);
    }).catch((error: Any) => {
      result.error("createAnswerFailed", `${error}`, null);
    });
  }

  public setLocalDescription(constraints: Map<Any, Any>, pc: webrtc.RTCPeerConnection, result: MethodResult) {
    const sdpType = findString(constraints, "type");
    let type = stringToSdpType(sdpType);
    if (!type) {
      result.error("setLocalDescriptionFailed", `type(${sdpType}) is not supported`, null);
      return;
    }

    let description: webrtc.RTCSessionDescriptionInit = {
      type: type,
    };

    const sdp = findStringOrNull(constraints, "sdp");
    if (sdp) {
      description.sdp = sdp;
    }

    pc.setLocalDescription(description).then(() => {
      result.success(null);
    }).catch((error: Any) => {
      result.error("setLocalDescriptionFailed", `${error}`, null);
    })
  }

  public setRemoteDescription(constraints: Map<Any, Any>, pc: webrtc.RTCPeerConnection, result: MethodResult) {
    const sdpType = findString(constraints, "type");
    let type = stringToSdpType(sdpType);
    if (!type) {
      result.error("setRemoteDescriptionFailed", `type(${sdpType}) is not supported`, null);
      return;
    }

    let description: webrtc.RTCSessionDescriptionInit = {
      type: type,
    };

    const sdp = findStringOrNull(constraints, "sdp");
    if (sdp) {
      description.sdp = sdp;
    }

    pc.setRemoteDescription(description).then(() => {
      result.success(null);
    }).catch((error: Any) => {
      result.error("setRemoteDescriptionFailed", `${error}`, null);
    })
  }

  public async addIceCandidate(constraints: Map<Any, Any>, pc: webrtc.RTCPeerConnection, result: MethodResult) {
    const candidate: webrtc.RTCIceCandidateInit = {
      candidate: findString(constraints, "candidate"),
    };

    const sdpMid = findStringOrNull(constraints, "sdpMid");
    const sdpMLineIndex = findNumberOrNull(constraints, "sdpMLineIndex");
    const usernameFragment = findStringOrNull(constraints, "usernameFragment");

    if (sdpMid) {
      candidate.sdpMid = sdpMid;
    }

    if (sdpMLineIndex) {
      candidate.sdpMLineIndex = sdpMLineIndex;
    }

    if (usernameFragment) {
      candidate.usernameFragment = usernameFragment;
    }

    try {
      await pc.addIceCandidate(candidate);
      result.success(null);
    } catch (error) {
      result.error("addIceCandidateFailed", `${error}`, null);
    }
  }

  updateRtpParameters(
    newParameters: Map<Any, Any>,
    parameters: webrtc.RTCRtpSendParameters): webrtc.RTCRtpSendParameters {
    const encodings: Any[] = findArray(newParameters, "encodings");
    const params = parameters.encodings;
    for (let i = 0; i < params.length; i++) {
      if (i == encodings.length) {
        break;
      }
      let param = params[i];
      const map: Any = encodings[i];
      let value: Any = findBoolOrNull(map, "active");
      if (value) {
        param.active = value;
      }

      value = findNumberOrNull(map, "maxBitrate");
      if (value) {
        param.maxBitrate = value;
      }

      // value = findNumberOrNull(map, "minBitrate");
      // if (value) {
      //   param.minBitrate = value;
      // }

      value = findNumberOrNull(map, "maxFramerate");
      if (value) {
        param.maxFramerate = value;
      }

      value = findNumberOrNull(map, "scaleResolutionDownBy");
      if (value) {
        param.scaleResolutionDownBy = value;
      }
    }

    // const degradationPreference = findStringOrNull(newParameters, "degradationPreference");
    // if (degradationPreference) {
    //   parameters.degradationPreference = degradationPreference;
    // }

    return parameters;
  }

  public async rtpSenderSetParameters(args: Map<Any, Any>, pc: webrtc.RTCPeerConnection, result: MethodResult) {
    const rtpSenderId = findString(args, "rtpSenderId");
    if (rtpSenderId.length == 0) {
      result.error("rtpSenderSetParameters",
        "rtpSenderSetParameters() rtpSenderId is null or empty", null);
      return;
    }

    const parameters: Map<Any, Any> = findMap(args, "parameters");
    if (parameters.size == 0) {
      result.error("rtpSenderSetParameters",
        "rtpSenderSetParameters() parameters is null or empty", null);
      return;
    }

    const sender = this.base.getRtpSenderById(pc, rtpSenderId);
    if (!sender) {
      result.error("rtpSenderSetParameters", "sender is null", null);
      return;
    }

    let param = sender.getParameters();
    param = this.updateRtpParameters(parameters, param);
    let success: boolean;
    try {
      await sender.setParameters(param);
      success = true;
    } catch (e) {
      success = false;
    }

    let map: Map<string, Any> = new Map();
    map.set("result", success)
    result.success(map);
  }

  public rtpSenderReplaceTrack(
    pc: webrtc.RTCPeerConnection,
    track: webrtc.MediaStreamTrack | null,
    rtpSenderId: string,
    result: MethodResult) {
    const sender = this.base.getRtpSenderById(pc, rtpSenderId);
    if (!sender) {
      result.error("rtpSenderReplaceTrack", "sender is null", null);
      return;
    }

    Log.d(TAG, `rtpSenderReplaceTrack ${dump(track)}`);
    sender.replaceTrack(track);
    result.success(null);
  }

  public rtpSenderSetTrack(
    pc: webrtc.RTCPeerConnection,
    track: webrtc.MediaStreamTrack | null,
    rtpSenderId: string,
    result: MethodResult) {
    const sender = this.base.getRtpSenderById(pc, rtpSenderId);
    if (!sender) {
      result.error("rtpSenderReplaceTrack", "sender is null", null);
      return;
    }

    sender.replaceTrack(track).then(() => {
      Log.d(TAG, "replaceTrack succeeded");
    }).catch((error: Any) => {
      Log.d(TAG, "replaceTrack failed " + error);
    });
    result.success(null);
  }

  public getTransceivers(
    pc: webrtc.RTCPeerConnection,
    result: MethodResult) {
    let map: Map<string, Any> = new Map();
    let info: Map<string, Any>[] = [];
    const transceivers = pc.getTransceivers();
    for (const transceiver of transceivers) {
      info.push(transceiverToMap(transceiver));
    }
    map.set("transceivers", info);
    result.success(map);
  }

  public async getStats(trackId: string, pc: webrtc.RTCPeerConnection, result: MethodResult) {
    if (trackId.length == 0) {
      try {
        const reports = await pc.getStats();
        let list: Any[] = [];
        for (const kv of reports.stats) {
          list.push(statsToMap(kv[1]));
        }
        let params: Map<string, Any> = new Map();
        params.set("stats", list);
        result.success(params);
      } catch (error) {
        result.error("GetStats", `${error}`, null);
      }
      return;
    }

    let found = false;
    for (const receiver of pc.getReceivers()) {
      if (receiver.track.id == trackId) {
        found = true;
        try {
          const reports = await pc.getStats(receiver.track);
          let list: Any[] = [];
          for (const kv of reports.stats) {
            list.push(statsToMap(kv[1]));
          }
          let params: Map<string, Any> = new Map();
          params.set("stats", list);
          result.success(params);
        } catch (error) {
          result.error("GetStats", `${error}`, null);
        }
        return;
      }
    }
    for (const sender of pc.getSenders()) {
      if (sender.track?.id == trackId) {
        found = true;
        try {
          const reports = await pc.getStats(sender.track);
          let list: Any[] = [];
          for (const kv of reports.stats) {
            list.push(statsToMap(kv[1]));
          }
          let params: Map<string, Any> = new Map();
          params.set("stats", list);
          result.success(params);
        } catch (error) {
          result.error("GetStats", `${error}`, null);
        }
        return;
      }
    }
    if (!found) {
      result.error("GetStats", "Track not found", null);
    }
  }

  public async getLocalDescription(pc: webrtc.RTCPeerConnection, result: MethodResult) {
    const description: webrtc.RTCSessionDescription | undefined = pc.localDescription;
    let params: Map<string, Any> = new Map();
    params.set("sdp", description?.sdp);
    params.set("type", description?.type);
    result.success(params);
  }

  public rtpTransceiverSetCodecPreferences(
    pc: webrtc.RTCPeerConnection,
    transceiverId: string,
    codecs: JsonMap[],
    result: MethodResult) {
    let transceiver = this.getRtpTransceiverById(pc, transceiverId);
    if (transceiver == null) {
      result.error("RtpTransceiverSetCodecPreferences", "transceiver is null", null);
      return;
    }
    let codecList: webrtc.RTCRtpCodec[] = [];
    for (const codec of codecs) {
      let codecMimeType = findString(codec, "mimeType");
      let codecClockRate = findNumber(codec, "clockRate");
      let codecNumChannels = findNumber(codec, "channels");
      let codecSdpFmtpLine = findString(codec, "sdpFmtpLine");
      let codecCapability: webrtc.RTCRtpCodec = {
        mimeType: "",
        clockRate: 0,
      }
      if (codecSdpFmtpLine != "") {
        codecCapability.sdpFmtpLine = codecSdpFmtpLine;
      }
      codecCapability.clockRate = codecClockRate;
      if (codecNumChannels != 0) {
        codecCapability.channels = codecNumChannels;
      }
      codecCapability.mimeType = codecMimeType;
      codecList.push(codecCapability);
    }
    Log.d(TAG, `rtpTransceiverSetCodecPreferences ${dump(codecList)}`);
    transceiver.setCodecPreferences(codecList);
    result.success(null);
  }

  public getRtpTransceiverById(pc: webrtc.RTCPeerConnection, id: string): webrtc.RTCRtpTransceiver | null {
    let transceivers = pc.getTransceivers();
    for (const transceiver of transceivers) {
      if (transceiver.mid == id) {
        return transceiver;
      }
    }
    return null;
  }
}

function stringToSdpType(type: string): webrtc.RTCSdpType | null {
  if (type == 'offer' || type == 'answer' || type == "pranswer" || type == "rollback") {
    return type;
  }
  return null;
}


function statsToMap(stats: webrtc.RTCStats): Map<string, Any> {
  let reportMap: Map<string, Any> = new Map();
  reportMap.set("id", stats.id);
  reportMap.set("type", stats.type);
  reportMap.set("timestamp", stats.timestamp);
  reportMap.set("values", stats);
  return reportMap;
}