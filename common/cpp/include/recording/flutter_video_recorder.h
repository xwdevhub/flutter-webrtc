#ifndef FLUTTER_WEBRTC_RTC_VIDEO_RECORDER_WIN_HXX
#define FLUTTER_WEBRTC_RTC_VIDEO_RECORDER_WIN_HXX

#if defined(_WIN32) || defined(_WINDOWS)
#include <windows.h>
#endif

#include <atomic>
#include <condition_variable>
#include <fstream>
#include <memory>
#include <queue>
#include <thread>
#include "flutter_common.h"
#include "flutter_media_recorder.h"
#include "flutter_webrtc_base.h"
#include "h264_encoder.h"
#include "thread_queue.h"
#include "types.h"

namespace flutter_webrtc_plugin {

class FlutterVideoRecorder : public FlutterRecorderInterface,
                             public libwebrtc::RTCWindowRecorderOberver {
 public:
  FlutterVideoRecorder(FlutterWebRTCBase* base,
                       FlutterMediaRecorder* media_recorder,
                       const VideoFormat& output_format);

  ~FlutterVideoRecorder();

  bool Start(const std::string& filepath) override;

  void Stop() override;

  void Resume() override;

  void Pause() override;

  RecordingState State() const override;

  void OnFrameCaptured(libwebrtc::scoped_refptr<libwebrtc::RTCWindowRecorder::I420Buffer> frame,
                       uint32_t timestamp_ms) override;

 private:
  libwebrtc::RTCWindowRecorder::SourceId GetSourceId();

  void ProcessThread();
  void EncodeVideoFrame(const VideoFrame& video_frame);

 private:
  FlutterWebRTCBase* base_;
  FlutterMediaRecorder* media_recorder_;
  VideoFormat output_format_;
  libwebrtc::RTCWindowRecorder::SourceId source_id_;

  std::atomic<RecordingState> state_{RecordingState::kStopped};
  std::mutex state_mutex_;
  std::condition_variable state_cv_;

  std::ofstream output_file_;
  std::mutex output_file_mutex_;

  std::unique_ptr<H264Encoder> encoder_;

  std::thread process_thread_;

  std::unique_ptr<ThreadQueue<VideoFrame>> frame_queue_;

  libwebrtc::scoped_refptr<libwebrtc::RTCWindowRecorderFactory> recorder_factory_;
  libwebrtc::scoped_refptr<libwebrtc::RTCWindowRecorder> recorder_;

  std::atomic<int64_t> first_frame_arrival_timestamp_{0};
  std::atomic<int64_t> last_frame_arrival_timestamp_{0};
  std::atomic<int64_t> first_frame_captured_timestamp_{0};
};

}  // namespace flutter_webrtc_plugin

#endif