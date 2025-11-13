#ifndef FLUTTER_WEBRTC_RTC_AUDIO_RECORDER_HXX
#define FLUTTER_WEBRTC_RTC_AUDIO_RECORDER_HXX

#include <atomic>
#include <fstream>
#include <shared_mutex>
#include <thread>
#include <unordered_map>
#include <vector>

#include "aac_encoder.h"
// #include "audio_jitter_buffer.h"
#include "flutter_common.h"
#include "flutter_media_recorder.h"
#include "flutter_remote_track_observer.h"
#include "rtc_audio_track.h"
#include "rtc_peerconnection_factory.h"
#include "rtc_resampler.h"
#include "task_thread.h"
#include "thread_queue.h"
#include "timer.h"
#include "types.h"

namespace flutter_webrtc_plugin {

// class AudioJitterBuffer;
class FlutterWebRTCBase;

class FlutterAudioRecorder : public FlutterRecorderInterface,
                             public libwebrtc::RTCAudioTrackSinkInterface,
                             public libwebrtc::RTCLocalAudioTrackObserver,
                             public FlutterRemoteTrackObserver {
 public:
  FlutterAudioRecorder(FlutterWebRTCBase* base,
                       FlutterMediaRecorder* media_recorder,
                       const AudioFormat& audio_format);

  ~FlutterAudioRecorder();

  void AddAudioTrack(libwebrtc::RTCAudioTrack* track);

  void RemoveAudioTrack(libwebrtc::RTCAudioTrack* track);

  void OnData(const void* audio_data,
              int bits_per_sample,
              int sample_rate,
              size_t number_of_channels,
              size_t number_of_frames,
              int64_t absolute_capture_timestamp_ms,
              libwebrtc::string track_id) override;

  void OnProcessedData(const int16_t* audio_data,
                       int sample_rate,
                       size_t number_of_channels,
                       size_t number_of_frames,
                       int64_t absolute_capture_timestamp_ms) override;

  bool Start(const std::string& filepath) override;

  void Stop() override;

  void Resume() override;

  void Pause() override;

  RecordingState State() const { return state_; }

  void OnAddTrack(libwebrtc::RTCMediaTrack* track) override;

  void OnRemoveTrack(libwebrtc::RTCMediaTrack* track) override;

 private:
  /**
   * @brief 音轨上下文结构体，封装每个音轨的所有相关数据
   */
  struct TrackContext {
    std::string id;

    // 音轨指针, 本地音轨为空
    libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> track;

    // 音频缓冲队列
    std::shared_ptr<ThreadQueue<AudioFrame>> frame_queue;

    // 预处理重采样器
    libwebrtc::scoped_refptr<libwebrtc::RTCResampler> resampler;

    // 首帧到达时间戳
    int64_t first_frame_arrival_timestamp_{0};

    // 上一帧到达时间戳
    int64_t last_frame_arrival_timestamp_{0};

    // 帧数
    int64_t frame_count{0};

    // mutable std::mutex mutex;  // 保护该音轨的数据访问

    explicit TrackContext(std::string id,
                          libwebrtc::RTCAudioTrack* track = nullptr,
                          std::shared_ptr<ThreadQueue<AudioFrame>> frame_queue =
                              std::make_shared<ThreadQueue<AudioFrame>>(200))
        : id(std::move(id)), track(track), frame_queue(std::move(frame_queue)) {};

    int64_t CalculateTimestamp(int64_t current_frame_arrival_timestamp,
                               int64_t record_start_ts,
                               int64_t record_pause_elapsed_ts);
  };

  void ProcessThread();
  void EncodeAudioFrame(int64_t timestamp, const std::vector<int16_t>& audio_frame);

  bool AreAllQueuesEmpty();

  void BaseTrackTimerCallback();

  AudioFormat audio_format_;

  std::ofstream output_file_;
  std::unique_ptr<AACEncoder> encoder_;
  std::mutex output_file_mutex_;

  std::atomic<RecordingState> state_{RecordingState::kStopped};
  std::mutex state_mutex_;
  std::condition_variable state_cv_;

  // 远程音轨数据，key为track_id
  std::unordered_map<std::string, std::shared_ptr<TrackContext>> remote_track_contexts_;
  std::shared_mutex contexts_mutex_;

  std::unique_ptr<TaskThread> producer_thread_;
  std::shared_mutex producer_thread_mutex_;

  // 本地音轨数据
  std::shared_ptr<TrackContext> local_track_context_;

  // 空包音频数据，其pts作为主时钟
  std::unique_ptr<TrackContext> base_track_context_;
  std::shared_mutex base_track_mutex_;
  Timer base_track_timer_;

  std::thread process_thread_;

  FlutterWebRTCBase* base_;
  FlutterMediaRecorder* media_recorder_;
};

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_WEBRTC_RTC_AUDIO_RECORDER_HXX