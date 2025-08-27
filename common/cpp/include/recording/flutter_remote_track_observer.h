#ifndef FLUTTER_WEBRTC_REMOTE_TRACK_OBSERVER_HXX
#define FLUTTER_WEBRTC_REMOTE_TRACK_OBSERVER_HXX

namespace flutter_webrtc_plugin {
  
class FlutterRemoteTrackObserver {
 public:
  virtual void OnAddTrack(libwebrtc::RTCMediaTrack* track) = 0;
  virtual void OnRemoveTrack(libwebrtc::RTCMediaTrack* track) = 0;

 protected:
  virtual ~FlutterRemoteTrackObserver() = default;
};

}  // namespace flutter_webrtc_plugin

#endif