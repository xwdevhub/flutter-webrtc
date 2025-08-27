#ifndef LIB_WEBRTC_RTC_WINDOW_RECORDER_FACTORY_HXX
#define LIB_WEBRTC_RTC_WINDOW_RECORDER_FACTORY_HXX

#include <functional>
#include "rtc_types.h"
#include "rtc_window_recorder.h"

namespace libwebrtc {

class RTCWindowRecorderFactory : public RefCountInterface {
 public:
  LIB_WEBRTC_API static scoped_refptr<RTCWindowRecorderFactory> Create();

  virtual ~RTCWindowRecorderFactory() = default;

  virtual scoped_refptr<RTCWindowRecorder> CreateWindowRecorder(
      RTCWindowRecorder::SourceId source_id) = 0;
};

}  // namespace libwebrtc

#endif