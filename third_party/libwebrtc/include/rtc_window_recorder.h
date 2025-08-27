#ifndef LIB_WEBRTC_RTC_WINDOW_RECORDER_HXX
#define LIB_WEBRTC_RTC_WINDOW_RECORDER_HXX

#include "base/refcount.h"
#include "rtc_types.h"

namespace libwebrtc {

class RTCWindowRecorderOberver;

class RTCWindowRecorder : public RefCountInterface {
 public:
  class I420Buffer : public RefCountInterface {
   public:
    virtual int width() const = 0;
    virtual int height() const = 0;
    virtual const uint8_t* DataY() const = 0;
    virtual const uint8_t* DataU() const = 0;
    virtual const uint8_t* DataV() const = 0;
    virtual int StrideY() const = 0;
    virtual int StrideU() const = 0;
    virtual int StrideV() const = 0;
  };

  enum class State { kRunning, kStopped, kFailed };

  using SourceId = uintptr_t;

  virtual ~RTCWindowRecorder() = default;

  virtual void RegisterObserver(RTCWindowRecorderOberver* observer) = 0;

  virtual void UnregisterObserver() = 0;

  virtual State Start(uint32_t fps) = 0;

  virtual void Stop() = 0;

  virtual bool IsRecording() = 0;
};

class RTCWindowRecorderOberver {
 public:
  virtual ~RTCWindowRecorderOberver() = default;
  virtual void OnFrameCaptured(
      scoped_refptr<RTCWindowRecorder::I420Buffer> frame,
      uint32_t timestamp_ms) = 0;
};

}  // namespace libwebrtc

#endif