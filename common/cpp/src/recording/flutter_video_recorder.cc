#include "flutter_video_recorder.h"

#include <windows.h>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <iostream>

#include "flutter_media_recorder.h"
#include "flutter_webrtc_logging.h"
#include "utils.h"

namespace flutter_webrtc_plugin {
FlutterVideoRecorder::FlutterVideoRecorder(FlutterWebRTCBase* base,
                                           FlutterMediaRecorder* media_recorder,
                                           const VideoFormat& output_format)
    : base_(base),
      media_recorder_(media_recorder),
      output_format_(output_format),
      source_id_(0),
      frame_queue_(std::make_unique<ThreadQueue<VideoFrame>>(
          static_cast<size_t>(output_format_.fps * 2))),
      recorder_factory_(libwebrtc::RTCWindowRecorderFactory::Create()) {}

FlutterVideoRecorder::~FlutterVideoRecorder() {
  Stop();
}

bool FlutterVideoRecorder::Start(const std::string& filepath) {
  // Stop any existing recording
  Stop();

  {
    std::lock_guard<std::mutex> lock(output_file_mutex_);

#if defined(WIN32) || defined(_WINDOWS)
    std::wstring wpath = utf8_to_wstring(filepath);
    std::filesystem::path path(wpath);
    output_file_.open(path, std::ios::binary | std::ios::out | std::ios::app);
#else
    output_file_.open(filepath,
                      std::ios::binary | std::ios::out | std::ios::app);
#endif

    if (!output_file_.is_open()) {
      RTC_LOG(LS_ERROR) << "Failed to open output file: " << filepath;
      return false;
    }
  }

  // Get target window handle
  source_id_ = GetSourceId();
#if defined(WIN32) || defined(_WINDOWS)
  if (!source_id_ || !IsWindow((HWND)source_id_)) {
    RTC_LOG(LS_ERROR) << "Invalid window handle";
    return false;
  }
#endif

  recorder_ = recorder_factory_->CreateWindowRecorder(source_id_);
  recorder_->RegisterObserver(this);

  // Start capture
  recorder_->Start(output_format_.fps);

  // Start threads
  process_thread_ = std::thread(&FlutterVideoRecorder::ProcessThread, this);

  // Set state
  state_ = RecordingState::kRecording;
  return true;
}

void FlutterVideoRecorder::Stop() {
  RTC_LOG(LS_INFO) << "Stopping video recorder...";

  // --- 阶段 0: 状态检查 ---
  if (state_.exchange(RecordingState::kStopped) == RecordingState::kStopped) {
    RTC_LOG(LS_WARNING) << "Video recorder is already stopped or stopping.";
    return;
  }

  // --- 阶段 1 & 2: 信号 & 分离 (Signal & Detach) ---
  // 首先停止数据源，确保不再有新的 OnFrameCaptured 回调。
  if (recorder_) {
    recorder_->Stop();                // 停止捕获
    recorder_->UnregisterObserver();  // 解除回调
    recorder_ = nullptr;
  }
  RTC_LOG(LS_INFO) << "Video source has been stopped and detached.";

  // --- 阶段 3: 排空 (Drain) ---
  // 唤醒 process_thread_，让它处理完 frame_queue_ 中的所有剩余帧。
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    state_cv_.notify_one();
  }
  RTC_LOG(LS_INFO) << "Notified video process thread to drain and stop.";

  // --- 阶段 4: 连接 (Join) ---
  // 等待 process_thread_ 完成排空并退出。
  if (process_thread_.joinable()) {
    process_thread_.join();
  }
  RTC_LOG(LS_INFO) << "Video process thread has joined.";

  // --- 阶段 5: 清理 (Cleanup) ---
  // 此刻，可以保证没有任何线程会再访问这些资源了。
  {
    std::lock_guard<std::mutex> lock(output_file_mutex_);

    // 队列此时应该是空的，但以防万一可以清一下
    frame_queue_->Clear();

    // 刷新并重置编码器
    encoder_.reset();

    // 关闭输出文件
    if (output_file_.is_open()) {
      output_file_.flush();
      output_file_.close();
    }
  }

  RTC_LOG(LS_INFO) << "Video recorder stopped successfully.";
}

void FlutterVideoRecorder::Pause() {
  if (state_.load() != RecordingState::kRecording)
    return;

  state_ = RecordingState::kPaused;

  if (recorder_) {
    recorder_->Stop();
    recorder_->UnregisterObserver();
    recorder_ = nullptr;
  }

  RTC_LOG(LS_INFO) << "Recording paused";
}

void FlutterVideoRecorder::Resume() {
  if (state_.load() != RecordingState::kPaused)
    return;

  RTC_LOG(LS_INFO) << "Recording resumed";
  {
    // 1. 加锁以保护状态改变和通知的原子性
    std::lock_guard<std::mutex> lock(state_mutex_);
    state_.store(RecordingState::kRecording);
  }
  // 2. 唤醒正在等待的 ProcessThread
  state_cv_.notify_one();

  recorder_ = recorder_factory_->CreateWindowRecorder(source_id_);
  recorder_->RegisterObserver(this);
  recorder_->Start(output_format_.fps);
}

RecordingState FlutterVideoRecorder::State() const {
  return state_;
}
libwebrtc::RTCWindowRecorder::SourceId FlutterVideoRecorder::GetSourceId() {
  if (source_id_ > 0) {
    return source_id_;
  }
#if defined(WIN32) || defined(_WINDOWS)
  source_id_ = reinterpret_cast<libwebrtc::RTCWindowRecorder::SourceId>(
      GetForegroundWindow());
  return source_id_;
#else
  return 0;
#endif
}

void FlutterVideoRecorder::OnFrameCaptured(
    libwebrtc::scoped_refptr<libwebrtc::RTCWindowRecorder::I420Buffer> frame,
    uint32_t timestamp_ms) {
  // 如果不是在录制状态，直接丢弃帧
  if (state_.load() != RecordingState::kRecording || !frame) {
    return;
  }

  auto frame_arrival_timestamp =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count();

  if (!last_frame_arrival_timestamp_ ||
      frame_arrival_timestamp - last_frame_arrival_timestamp_ > 200) {
    first_frame_arrival_timestamp_ = frame_arrival_timestamp;
    first_frame_captured_timestamp_ = timestamp_ms;
  }

  int64_t pts = first_frame_arrival_timestamp_ -
                media_recorder_->start_timestamp_ -
                media_recorder_->pause_elapsed_ts_ + timestamp_ms -
                first_frame_captured_timestamp_;

  last_frame_arrival_timestamp_ = frame_arrival_timestamp;

  // RTC_LOG(LS_INFO) << "Video PTS calculation: "
  //                  << "pts=" << pts << ", first_frame_arrival_timestamp_="
  //                  << first_frame_arrival_timestamp_
  //                  << ", media_recorder_->start_timestamp_="
  //                  << media_recorder_->start_timestamp_
  //                  << ", media_recorder_->pause_elapsed_ts_="
  //                  << media_recorder_->pause_elapsed_ts_
  //                  << ", timestamp_ms=" << timestamp_ms
  //                  << ", first_frame_captured_timestamp_="
  //                  << first_frame_captured_timestamp_;

  if (!frame_queue_->TryPush(VideoFrame(std::move(frame), pts))) {
    RTC_LOG(LS_WARNING) << "[statis] Dropped video frame due to full queue.";
  }
}

void FlutterVideoRecorder::ProcessThread() {
  RTC_LOG(LS_INFO) << "Video Process thread started";

  while (state_.load() != RecordingState::kStopped ||
         !frame_queue_->IsEmpty()) {
    // --- 暂停处理逻辑 ---
    {
      std::unique_lock<std::mutex> lock(state_mutex_);
      state_cv_.wait(lock, [this] {
        // 如果已停止，则不再等待，直接进入排空阶段
        if (state_.load() == RecordingState::kStopped)
          return true;
        // 否则，当不处于暂停状态，或队列中有数据时，继续工作
        return state_.load() != RecordingState::kPaused ||
               !frame_queue_->IsEmpty();
      });
    }

    // 如果被唤醒后发现可以彻底退出了
    if (state_.load() == RecordingState::kStopped && frame_queue_->IsEmpty()) {
      break;
    }

    auto [video_frame, _] = frame_queue_->PopWaitFor(std::chrono::milliseconds(
        static_cast<int>(1000.0 / output_format_.fps)));
    if (video_frame) {
      EncodeVideoFrame(*video_frame);
    }
  }

  RTC_LOG(LS_INFO) << "Video Process thread stopped";
}

void FlutterVideoRecorder::EncodeVideoFrame(const VideoFrame& video_frame) {
  // std::lock_guard<std::mutex> lock(mutex_);
  // 懒汉式初始化 encoder_
  if (!encoder_) {
    // 确保 output_file_ 已经打开
    if (!output_file_.is_open()) {
      // 处理文件未打开的错误
      RTC_LOG(LS_ERROR) << "Output file is not open!";
      return;
    }
    encoder_ = std::make_unique<H264Encoder>(output_format_, output_file_);
  }

  if (!encoder_->Encode(video_frame)) {
    // 可以根据返回值进行错误处理，例如停止录制
    RTC_LOG(LS_ERROR) << "Failed to encode video frame.";
  }
}

}  // namespace flutter_webrtc_plugin
