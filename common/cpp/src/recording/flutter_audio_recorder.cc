#include "flutter_audio_recorder.h"
#include <algorithm>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <thread>

#include "flutter_peerconnection.h"
#include "flutter_webrtc_base.h"
#include "flutter_webrtc_logging.h"
#include "rtc_resampler.h"
#include "utils.h"

namespace flutter_webrtc_plugin {

FlutterAudioRecorder::FlutterAudioRecorder(FlutterWebRTCBase* base,
                                           FlutterMediaRecorder* media_recorder,
                                           const AudioFormat& audio_format)
    : base_(base),
      media_recorder_(media_recorder),
      audio_format_(audio_format) {
  base_->RegisterRemoteTrackObserver(this);
}

FlutterAudioRecorder::~FlutterAudioRecorder() {
  base_->factory_->UnregisterLocalAudioTrackObserver(this);
  base_->UnregisterRemoteTrackObserver(this);
  Stop();
}

void FlutterAudioRecorder::AddAudioTrack(libwebrtc::RTCAudioTrack* track) {
  std::unique_lock<std::shared_mutex> lock(contexts_mutex_);

  if (!track) {
    return;
  }

  std::string track_id = track->id().std_string();
  RTC_LOG(LS_DEBUG) << __FUNCTION__ << ": " << track_id;

  // 检查是否已存在
  if (remote_track_contexts_.find(track_id) != remote_track_contexts_.end()) {
    return;
  }

  // 创建新的上下文
  // remote_track_contexts_[track_id] = std::make_shared<TrackContext>(track_id,
  // track);
  remote_track_contexts_.try_emplace(
      track_id, std::make_shared<TrackContext>(track_id, track));
  RTC_LOG(LS_DEBUG) << __FUNCTION__
                    << ": add audio track, track_id=" << track_id
                    << ", audio track count=" << remote_track_contexts_.size();

  // 只在录制状态下添加sink
  if (state_ == RecordingState::kRecording) {
    track->AddSink(this);
  }
}

void FlutterAudioRecorder::RemoveAudioTrack(libwebrtc::RTCAudioTrack* track) {
  std::unique_lock<std::shared_mutex> lock(contexts_mutex_);

  if (!track) {
    return;
  }

  std::string track_id = track->id().std_string();
  RTC_LOG(LS_DEBUG) << __FUNCTION__ << ": " << track_id;

  auto it = remote_track_contexts_.find(track_id);
  if (it != remote_track_contexts_.end()) {
    // 如果当前正在录制，需要移除sink
    if (state_ == RecordingState::kRecording) {
      track->RemoveSink(this);
    }

    RTC_LOG(LS_DEBUG) << __FUNCTION__
                      << ": remove audio track, track_id=" << track_id;
    remote_track_contexts_.erase(it);
  }
}

void FlutterAudioRecorder::OnProcessedData(
    const int16_t* audio_data,
    int sample_rate,
    size_t number_of_channels,
    size_t number_of_frames,
    int64_t absolute_capture_timestamp_ms) {
  // {
  //   RTC_LOG(LS_DEBUG) << __FUNCTION__ << ": sample_rate=" << sample_rate
  //                     << ", number_of_channels=" << number_of_channels
  //                     << ", number_of_frames=" << number_of_frames
  //                     << ", absolute_capture_timestamp_ms="
  //                     << absolute_capture_timestamp_ms;
  // }

  // 检查参数有效性
  if (!audio_data || sample_rate <= 0 || number_of_channels <= 0 ||
      number_of_frames <= 0) {
    RTC_LOG(LS_ERROR) << __FUNCTION__ << ": Invalid audio parameters";
    return;
  }

  auto current_frame_arrival_timestamp =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count();

  const int16_t* samples = audio_data;
  size_t input_samples = number_of_frames * number_of_channels;

  std::shared_ptr<TrackContext> local_track_context = local_track_context_;
  int64_t timestamp = timestamp = local_track_context->CalculateTimestamp(
      current_frame_arrival_timestamp, media_recorder_->start_timestamp_,
      media_recorder_->pause_elapsed_ts_);
  std::shared_ptr<ThreadQueue<AudioFrame>> frame_queue =
      local_track_context->frame_queue;

  std::vector<int16_t> resampled_buffer;

  bool need_remix_or_resample =
      static_cast<uint32_t>(sample_rate) != audio_format_.sample_rate ||
      number_of_channels != audio_format_.channels;

  if (!need_remix_or_resample) {
    // 无需重采样
    resampled_buffer.assign(samples, samples + input_samples);
  } else {
    libwebrtc::scoped_refptr<libwebrtc::RTCResampler> resampler;

    if (!local_track_context->resampler) {
      local_track_context->resampler = libwebrtc::RTCResampler::Create();
    }
    resampler = local_track_context->resampler;

    if (!resampler) {
      return;
    }

    // 估算输出缓冲区大小，增加20%余量以防万一
    size_t output_frames_estimation =
        (number_of_frames * audio_format_.sample_rate) / sample_rate;
    size_t output_capacity = static_cast<size_t>(
        std::ceil(output_frames_estimation * audio_format_.channels * 1.2));
    resampled_buffer.resize(output_capacity);

    size_t dst_samples_per_channel = 0;
    uint32_t dst_timestamp = 0;  // RTP时间戳在此处不可用

    int result = resampler->RemixAndResample(
        audio_data, number_of_frames, number_of_channels, sample_rate,
        0,  // src_timestamp
        audio_format_.sample_rate, audio_format_.channels,
        resampled_buffer.data(), resampled_buffer.size(),
        &dst_samples_per_channel, &dst_timestamp);

    if (result != 0) {
      RTC_LOG(LS_ERROR) << ": RemixAndResample failed with code " << result;
      return;
    }

    resampled_buffer.resize(dst_samples_per_channel * audio_format_.channels);
  }

  {
    std::shared_lock<std::shared_mutex> lock(producer_thread_mutex_);
    if (producer_thread_) {
      producer_thread_->PostTask([frame_queue, timestamp,
                                  resampled_buffer =
                                      std::move(resampled_buffer)]() mutable {
        // RTC_LOG(LS_INFO) << "local audio frame queue size: "
        //                  << frame_queue->Size();
        frame_queue->Push(AudioFrame{timestamp, std::move(resampled_buffer)});
      });
    }
  }
}

void FlutterAudioRecorder::OnData(const void* audio_data,
                                  int bits_per_sample,
                                  int sample_rate,
                                  size_t number_of_channels,
                                  size_t number_of_frames,
                                  int64_t absolute_capture_timestamp_ms,
                                  libwebrtc::string track_id) {
  auto current_frame_arrival_timestamp =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count();

  // 拷贝音频数据
  std::vector<int16_t> audio_data_copy(
      static_cast<const int16_t*>(audio_data),
      static_cast<const int16_t*>(audio_data) +
          number_of_frames * number_of_channels);

  // 拷贝数据到任务线程处理，避免阻塞音频线程
  std::shared_lock<std::shared_mutex> lock(producer_thread_mutex_);
  if (!producer_thread_)
    return;
  producer_thread_->PostTask([this,
                              audio_data_copy = std::move(audio_data_copy),
                              sample_rate, number_of_channels, number_of_frames,
                              absolute_capture_timestamp_ms,
                              track_id = track_id.std_string(),
                              current_frame_arrival_timestamp]() {
    if (audio_data_copy.empty()) {
      return;
    }

    const int16_t* samples = audio_data_copy.data();
    size_t input_samples = number_of_frames * number_of_channels;

    int64_t timestamp = 0;
    std::vector<int16_t> resampled_buffer;
    std::shared_ptr<ThreadQueue<AudioFrame>> frame_queue;

    bool need_remix_or_resample =
        static_cast<uint32_t>(sample_rate) != audio_format_.sample_rate ||
        number_of_channels != audio_format_.channels;

    if (!need_remix_or_resample) {
      // 无需重采样
      resampled_buffer.assign(samples, samples + input_samples);
      std::shared_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
      auto ctx_it = remote_track_contexts_.find(track_id);
      if (ctx_it != remote_track_contexts_.end() && ctx_it->second) {
        timestamp = ctx_it->second->CalculateTimestamp(
            current_frame_arrival_timestamp, media_recorder_->start_timestamp_,
            media_recorder_->pause_elapsed_ts_);
        frame_queue = ctx_it->second->frame_queue;
      }
    } else {
      libwebrtc::scoped_refptr<libwebrtc::RTCResampler> resampler;

      {
        std::shared_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
        auto ctx_it = remote_track_contexts_.find(track_id);
        if (ctx_it != remote_track_contexts_.end() && ctx_it->second) {
          if (!ctx_it->second->resampler) {
            ctx_it->second->resampler = libwebrtc::RTCResampler::Create();
          }
          resampler = ctx_it->second->resampler;
          timestamp = ctx_it->second->CalculateTimestamp(
              current_frame_arrival_timestamp,
              media_recorder_->start_timestamp_,
              media_recorder_->pause_elapsed_ts_);
          frame_queue = ctx_it->second->frame_queue;
        }
      }

      if (!resampler) {
        return;
      }

      // 估算输出缓冲区大小，增加20%余量以防万一
      size_t output_frames_estimation =
          (number_of_frames * audio_format_.sample_rate) / sample_rate;
      size_t output_capacity = static_cast<size_t>(
          std::ceil(output_frames_estimation * audio_format_.channels * 1.2));
      resampled_buffer.resize(output_capacity);

      size_t dst_samples_per_channel = 0;
      uint32_t dst_timestamp = 0;  // RTP时间戳在此处不可用

      int result = resampler->RemixAndResample(
          samples, number_of_frames, number_of_channels, sample_rate,
          0,  // src_timestamp
          audio_format_.sample_rate, audio_format_.channels,
          resampled_buffer.data(), resampled_buffer.size(),
          &dst_samples_per_channel, &dst_timestamp);

      if (result != 0) {
        RTC_LOG(LS_DEBUG) << __FUNCTION__
                          << ": RemixAndResample failed with code " << result;
        return;
      }

      resampled_buffer.resize(dst_samples_per_channel * audio_format_.channels);
    }

    // RTC_LOG(LS_INFO) << "remote audio frame queue size: "
    //                  << frame_queue->Size();
    frame_queue->Push(AudioFrame{timestamp, std::move(resampled_buffer)});
  });
}

void FlutterAudioRecorder::ProcessThread() {
  RTC_LOG(LS_INFO) << "Audio Process thread started.";

  // 1. [性能] 在循环外部分配内存，以复用
  std::vector<std::vector<int16_t>> track_data_buffer;
  std::vector<int16_t> mixed_data_buffer;

  // 定义固定的块大小 (48kHz, 2ch, 10ms = 960 samples)
  size_t smples_per_chunk =
      (audio_format_.sample_rate * audio_format_.channels * 10) / 1000;

  int64_t target_pts = 0;

  while (state_.load() != RecordingState::kStopped || !AreAllQueuesEmpty()) {
    if (state_.load() == RecordingState::kStopped)
      RTC_LOG(LS_INFO) << "Drain Consumer ...";

    RTC_LOG(LS_INFO) << "will check pause";
    // --- 暂停处理逻辑 ---
    {
      std::unique_lock<std::mutex> lock(state_mutex_);
      // 当状态为 Paused 时，线程会在这里“睡眠”
      // state_cv_.wait 会自动解锁，直到被 notify 唤醒
      state_cv_.wait(lock, [this] {
        // 如果已停止，则不再等待，直接进入排空阶段
        // 如果录制中，正常工作
        // if (state_.load() == RecordingState::kStopped)
        //   return true;
        return state_.load() != RecordingState::kPaused;
      });
    }
    RTC_LOG(LS_INFO) << "did check pause";

    // 如果线程被唤醒后发现状态是 Stopped 且所有队列都为空，则退出循环
    if (state_.load() == RecordingState::kStopped && AreAllQueuesEmpty()) {
      RTC_LOG(LS_INFO) << "Drain Consumer ..., No data to process";
      break;
    }

    // 清空上次使用的数据
    track_data_buffer.clear();

    RTC_LOG(LS_INFO) << "will add all process audio context";
    std::vector<std::shared_ptr<TrackContext>> all_contexts;
    all_contexts.reserve(remote_track_contexts_.size() + 1);
    all_contexts.push_back(local_track_context_);
    {
      std::shared_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
      for (auto& [_, context] : remote_track_contexts_) {
        all_contexts.push_back(context);
      }
    }
    RTC_LOG(LS_INFO) << "did add all process audio context";

    {
      std::shared_lock<std::shared_mutex> lock(base_track_mutex_);
      if (!base_track_context_) {
        RTC_LOG(LS_INFO) << "base audio track context not initial";
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        continue;
      }
      // RTC_LOG(LS_INFO) << "will pop base audio frame, size="
      //                  << base_track_context_->frame_queue->Size();
      auto [audio_frame, _] = base_track_context_->frame_queue->Pop();
      if (!audio_frame) {
        // 不可能执行到这里，base track timer 是在消费者线程结束后才停止的
        continue;
      }
      target_pts = audio_frame->timestamp;
      track_data_buffer.push_back(audio_frame->data);
      // RTC_LOG(LS_INFO) << "did pop base audio frame, size="
      //                  << base_track_context_->frame_queue->Size();
    }

    for (auto& context : all_contexts) {
      auto [audio_frame, _] =
          context->frame_queue->TryPopIf([&](const AudioFrame& frame) {
            return frame.timestamp < target_pts + 10;
          });
      if (!audio_frame) {
        continue;
      }

      RTC_LOG(LS_INFO) << "混合音频 trackId=" << context->id
                       << ", target_pts=" << target_pts
                       << ", frame.timestamp=" << audio_frame->timestamp
                       << ", frame.size=" << audio_frame->data.size();
      track_data_buffer.push_back(audio_frame->data);
    }

    // 调整混合缓冲区大小
    mixed_data_buffer.assign(smples_per_chunk, 0);

    // 混音 (所有数据块长度都是kSamplesPerChunk)
    for (size_t i = 0; i < smples_per_chunk; ++i) {
      int32_t sum = 0;
      for (const auto& data : track_data_buffer) {
        if (i < data.size()) {
          sum += data[i];
        }
      }
      // sum = sum / static_cast<int32_t>(track_data_buffer.size());
      mixed_data_buffer[i] =
          static_cast<int16_t>(std::clamp(sum, static_cast<int32_t>(INT16_MIN),
                                          static_cast<int32_t>(INT16_MAX)));
    }

    // if (pcm_file.is_open()) {
    //   pcm_file.write(reinterpret_cast<const
    //   char*>(mixed_data_buffer.data()),
    //                  mixed_data_buffer.size() * sizeof(int16_t));
    // }

    RTC_LOG(LS_INFO) << "will encode audio frame";
    EncodeAudioFrame(target_pts, mixed_data_buffer);
    RTC_LOG(LS_INFO) << "did encode audio frame";
  }

  RTC_LOG(LS_INFO) << "Audio Process thread stopped.";
}

void FlutterAudioRecorder::EncodeAudioFrame(
    int64_t ts,
    const std::vector<int16_t>& audio_frame) {
  std::lock_guard<std::mutex> lock(output_file_mutex_);
  if (!encoder_) {
    // 确保 output_file_ 已经打开
    if (!output_file_.is_open()) {
      // 处理文件未打开的错误
      RTC_LOG(LS_ERROR) << "Output file is not open!";
      return;
    }
    encoder_ = std::make_unique<AACEncoder>(audio_format_, output_file_);
  }

  // 调用编码器进行编码
  if (!encoder_->Encode(ts, audio_frame)) {
    RTC_LOG(LS_ERROR) << "Failed to encode audio frame at ts " << ts;
    // 这里可以添加更复杂的错误处理逻辑
  }
}

bool FlutterAudioRecorder::Start(const std::string& filepath) {
  // 如果已经在录制中或暂停，先停止。
  Stop();

  local_track_context_ = std::make_shared<TrackContext>("local");

  // 远程所有音轨
  for (const auto& [id, observer] : base_->peerconnection_observers_) {
    const auto& streams = observer->RemoteStreams();
    for (const auto& [_, stream] : streams) {
      auto audio_tracks = stream->audio_tracks().std_vector();
      for (const auto& track : audio_tracks) {
        if (track && track->kind().std_string() == "audio") {
          AddAudioTrack(static_cast<libwebrtc::RTCAudioTrack*>(track.get()));
        }
      }
    }
  }

  {
    std::lock_guard<std::mutex> lock(output_file_mutex_);

    // 打开新文件
    if (output_file_.is_open()) {
      output_file_.close();
    }

#if defined(WIN32) || defined(_WINDOWS)
    std::wstring wpath = utf8_to_wstring(filepath);
    std::filesystem::path path(wpath);
    output_file_.open(path, std::ios::binary | std::ios::out | std::ios::app);
#else
    output_file_.open(filepath,
                      std::ios::binary | std::ios::out | std::ios::app);
#endif

    if (!output_file_.is_open()) {
      return false;
    }

    if (!encoder_) {
      encoder_ = std::make_unique<AACEncoder>(audio_format_, output_file_);
    }
  }

  // 更新状态
  state_ = RecordingState::kRecording;

  // 启动混音线程
  process_thread_ = std::thread(&FlutterAudioRecorder::ProcessThread, this);

  {
    std::unique_lock<std::shared_mutex> lock(producer_thread_mutex_);
    producer_thread_ =
        std::make_unique<TaskThread>("audio data producer thread");
  }

  // 添加本地音频数据源
  base_->factory_->RegisterLocalAudioTrackObserver(this);

  // 添加所有音轨的sink
  std::shared_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
  // RTC_LOG(LS_INFO) << "远程音轨数量=" << remote_track_contexts_.size();
  for (auto& [_, context] : remote_track_contexts_) {
    if (context && context->track) {
      context->track->AddSink(this);
    }
  }

  // 开启空音频定时器
  {
    std::unique_lock<std::shared_mutex> lock(base_track_mutex_);
    base_track_context_ = std::make_unique<TrackContext>("base");
    base_track_timer_.Start(10, [this]() { BaseTrackTimerCallback(); });
  }

  RTC_LOG(LS_INFO) << "audio recorder start end";
  return true;
}

void FlutterAudioRecorder::Stop() {
  // --- 阶段 0: 状态检查 ---
  // 检查是否已经在停止过程中，防止重入
  if (state_.exchange(RecordingState::kStopped) == RecordingState::kStopped) {
    RTC_LOG(LS_WARNING) << "Recorder is already stopped or stopping.";
    return;
  }

  // --- 阶段 1 & 2: 信号 & 分离 (Signal & Detach) ---
  // 停止所有新数据的流入。
  // 这会停止向 producer_thread_ 提交新的任务。
  base_->factory_->UnregisterLocalAudioTrackObserver(this);
  RTC_LOG(LS_INFO) << "Unregistered local audio track observer.";
  local_track_context_->frame_queue->Close();

  // 移除所有远程音轨sink
  // 这会立即停止 OnData 回调，不再有新数据 Push 到远程 Jitter Buffer
  {
    std::shared_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
    for (auto& [_, context] : remote_track_contexts_) {
      if (context->track) {
        context->track->RemoveSink(this);
        context->frame_queue->Close();
      }
    }
    // 注意：这里不要 clear track_contexts_，因为 ProcessThread 可能还在使用它
  }
  RTC_LOG(LS_INFO) << "Removed all remote audio track sinks.";

  // --- 阶段 3: 等待生产者 (Wait for Producer) ---
  // producer_thread_->Stop() 会阻塞，直到所有已提交的任务
  // (即所有 Push 到 Jitter Buffer 的操作) 都完成。
  // 当 Stop() 返回时，我们可以确信 Jitter Buffer 不会再有任何新数据进入。
  {
    std::unique_lock<std::shared_mutex> lock(producer_thread_mutex_);
    if (producer_thread_) {
      RTC_LOG(LS_INFO) << "Stopping audio producer thread...";
      producer_thread_->Stop();
      producer_thread_.reset();
      RTC_LOG(LS_INFO) << "Producer audio thread has stopped.";
    }
  }

  // --- 阶段 4: 排空消费者 (Drain Consumer) ---
  // 现在 Jitter Buffer 已经是一个封闭的、只出不进的系统，
  // 我们可以安全地唤醒消费者线程来排空它。
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    state_cv_.notify_one();  // 唤醒 process_thread_
  }
  RTC_LOG(LS_INFO) << "Notified audio process thread to drain and stop.";

  // --- 阶段 5: 连接消费者 (Join Consumer) ---
  // 定时器可能暂停，需要先恢复下
  base_track_timer_.Resume();
  // 等待 process_thread_ 完成排空并退出。
  if (process_thread_.joinable()) {
    process_thread_.join();
  }
  RTC_LOG(LS_INFO) << "audio Process thread has joined.";

  // 等待消费者线程退出，才能停止生产空包
  {
    std::unique_lock<std::shared_mutex> lock(base_track_mutex_);
    base_track_context_->frame_queue->Clear();
    base_track_context_.reset();
    base_track_timer_.Stop();
    RTC_LOG(LS_INFO) << "Base track timer has stopped.";
  }

  // --- 阶段 6: 清理 (Cleanup) ---
  // 此刻，所有线程都已停止，可以安全地清理剩余资源。
  // local_track_context_->frame_queue->Clear();
  {
    std::unique_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
    remote_track_contexts_.clear();
  }
  {
    std::lock_guard<std::mutex> lock(output_file_mutex_);
    encoder_.reset();
    if (output_file_.is_open()) {
      output_file_.flush();
      output_file_.close();
    }
  }

  RTC_LOG(LS_INFO) << "Audio recorder stopped successfully.";
}

void FlutterAudioRecorder::Resume() {
  RTC_LOG(LS_INFO) << __FUNCTION__;

  // 只有在暂停状态才能恢复
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    if (state_.exchange(RecordingState::kRecording) !=
        RecordingState::kPaused) {
      return;
    }
  }

  state_cv_.notify_one();

  base_->factory_->RegisterLocalAudioTrackObserver(this);

  {
    std::shared_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
    for (auto& [_, context] : remote_track_contexts_) {
      if (context->track) {
        context->track->AddSink(this);
      }
    }
  }

  base_track_timer_.Resume();
}

void FlutterAudioRecorder::Pause() {
  RTC_LOG(LS_INFO) << __FUNCTION__;

  // 只有在录制状态才能暂停
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    if (state_.exchange(RecordingState::kPaused) !=
        RecordingState::kRecording) {
      return;
    }
  }

  base_->factory_->UnregisterLocalAudioTrackObserver(this);

  // 暂停远程音轨数据源
  {
    std::shared_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
    for (auto& [_, context] : remote_track_contexts_) {
      if (context->track) {
        context->track->RemoveSink(this);
      }
    }
  }

  base_track_timer_.Pause();
}

void FlutterAudioRecorder::OnAddTrack(libwebrtc::RTCMediaTrack* track) {
  if (track && track->kind().std_string() == "audio") {
    // RTC_LOG(LS_DEBUG) << track->state();
    AddAudioTrack(static_cast<libwebrtc::RTCAudioTrack*>(track));
  }
}

void FlutterAudioRecorder::OnRemoveTrack(libwebrtc::RTCMediaTrack* track) {
  if (track && track->kind().std_string() == "audio") {
    RemoveAudioTrack(static_cast<libwebrtc::RTCAudioTrack*>(track));
  }
}

bool FlutterAudioRecorder::AreAllQueuesEmpty() {
  std::shared_ptr<TrackContext> locacl_track_context = local_track_context_;
  if (locacl_track_context && !locacl_track_context->frame_queue->IsEmpty()) {
    return false;
  }

  {
    // 检查所有远程音频缓冲区
    std::shared_lock<std::shared_mutex> contexts_lock(contexts_mutex_);
    for (const auto& [_, context] : remote_track_contexts_) {
      if (context && !context->frame_queue->IsEmpty()) {
        return false;
      }
    }
  }

  return true;
}

void FlutterAudioRecorder::BaseTrackTimerCallback() {
  auto current_frame_arrival_timestamp =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count();

  std::shared_lock<std::shared_mutex> lock(base_track_mutex_);
  if (!base_track_context_)
    return;

  int64_t timestamp = base_track_context_->CalculateTimestamp(
      current_frame_arrival_timestamp, media_recorder_->start_timestamp_,
      media_recorder_->pause_elapsed_ts_);

  size_t smples_per_chunk =
      (audio_format_.sample_rate * audio_format_.channels * 10) / 1000;  // 960

  // RTC_LOG(LS_INFO) << "BaseTrackTimerCallback, timestamp=" << timestamp;

  // 不需要判断，因为停止后需要排空其他音频队列
  // if (state_ != RecordingState::kRecording)
  //   return;

  // RTC_LOG(LS_DEBUG) << "base audio frame queue size: "
  //                   << base_track_context_->frame_queue->Size();
  base_track_context_->frame_queue->Push(
      AudioFrame{timestamp, std::vector<int16_t>(smples_per_chunk, 0)});
}

int64_t FlutterAudioRecorder::TrackContext::CalculateTimestamp(
    int64_t current_frame_arrival_timestamp,
    int64_t record_start_ts,
    int64_t record_pause_elapsed_ts) {
  if (!last_frame_arrival_timestamp_ ||
      current_frame_arrival_timestamp - last_frame_arrival_timestamp_ > 200) {
    RTC_LOG(LS_INFO) << "重置首帧到达时间戳, id=" << id
                     << ", current_frame_arrival_timestamp="
                     << current_frame_arrival_timestamp
                     << ", last_frame_arrival_timestamp="
                     << last_frame_arrival_timestamp_;
    first_frame_arrival_timestamp_ = current_frame_arrival_timestamp;
    frame_count = 0;
  }

  int64_t timestamp = first_frame_arrival_timestamp_ - record_start_ts -
                      record_pause_elapsed_ts + frame_count * 10;

  last_frame_arrival_timestamp_ = current_frame_arrival_timestamp;
  frame_count++;

  return timestamp;
}

}  // namespace flutter_webrtc_plugin