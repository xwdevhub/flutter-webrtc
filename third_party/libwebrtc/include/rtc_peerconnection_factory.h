#ifndef LIB_WEBRTC_RTC_PEERCONNECTION_FACTORY_HXX
#define LIB_WEBRTC_RTC_PEERCONNECTION_FACTORY_HXX

#include "rtc_audio_source.h"
#include "rtc_audio_track.h"
#include "rtc_types.h"
#ifdef RTC_DESKTOP_DEVICE
#include "rtc_desktop_device.h"
#endif
#include "rtc_media_stream.h"
#include "rtc_mediaconstraints.h"
#include "rtc_video_device.h"
#include "rtc_video_source.h"

namespace libwebrtc {

class RTCPeerConnection;
class RTCAudioDevice;
class RTCVideoDevice;
class RTCRtpCapabilities;
class RTCLocalAudioTrackObserver;

class RTCPeerConnectionFactory : public RefCountInterface {
 public:
  virtual bool Initialize() = 0;

  virtual bool Terminate() = 0;

  virtual scoped_refptr<RTCPeerConnection> Create(
      const RTCConfiguration& configuration,
      scoped_refptr<RTCMediaConstraints> constraints) = 0;

  virtual void Delete(scoped_refptr<RTCPeerConnection> peerconnection) = 0;

  virtual scoped_refptr<RTCAudioDevice> GetAudioDevice() = 0;

  virtual scoped_refptr<RTCVideoDevice> GetVideoDevice() = 0;
#ifdef RTC_DESKTOP_DEVICE
  virtual scoped_refptr<RTCDesktopDevice> GetDesktopDevice() = 0;
#endif
  virtual scoped_refptr<RTCAudioSource> CreateAudioSource(
      const string audio_source_label) = 0;

  virtual scoped_refptr<RTCVideoSource> CreateVideoSource(
      scoped_refptr<RTCVideoCapturer> capturer, const string video_source_label,
      scoped_refptr<RTCMediaConstraints> constraints) = 0;
#ifdef RTC_DESKTOP_DEVICE
  virtual scoped_refptr<RTCVideoSource> CreateDesktopSource(
      scoped_refptr<RTCDesktopCapturer> capturer,
      const string video_source_label,
      scoped_refptr<RTCMediaConstraints> constraints) = 0;
#endif
  virtual scoped_refptr<RTCAudioTrack> CreateAudioTrack(
      scoped_refptr<RTCAudioSource> source, const string track_id) = 0;

  virtual scoped_refptr<RTCVideoTrack> CreateVideoTrack(
      scoped_refptr<RTCVideoSource> source, const string track_id) = 0;

  virtual scoped_refptr<RTCMediaStream> CreateStream(
      const string stream_id) = 0;

  virtual scoped_refptr<RTCRtpCapabilities> GetRtpSenderCapabilities(
      RTCMediaType media_type) = 0;

  virtual scoped_refptr<RTCRtpCapabilities> GetRtpReceiverCapabilities(
      RTCMediaType media_type) = 0;

  virtual void RegisterLocalAudioTrackObserver(RTCLocalAudioTrackObserver* observer) = 0;

  virtual void UnregisterLocalAudioTrackObserver(RTCLocalAudioTrackObserver* observer) = 0;
};

/**
 * @brief 本地音频数据观察者接口。
 * 库的使用者可以实现这个接口，以接收经过 APM 处理后的本地麦克风数据。
 */
class RTCLocalAudioTrackObserver {
 public:
  virtual ~RTCLocalAudioTrackObserver() = default;

  virtual void OnProcessedData(const int16_t* audio_data,
                               int sample_rate,
                               size_t number_of_channels,
                               size_t number_of_frames,
                               int64_t absolute_capture_timestamp_ms) = 0;
};

}  // namespace libwebrtc

#endif  // LIB_WEBRTC_RTC_PEERCONNECTION_FACTORY_HXX
