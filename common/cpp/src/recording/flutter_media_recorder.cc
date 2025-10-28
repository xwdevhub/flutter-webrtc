#include "flutter_media_recorder.h"
#include <iostream>
#include <vector>
#include "flutter_audio_recorder.h"
#include "flutter_video_recorder.h"
#include "flutter_webrtc_logging.h"
#include "mp4_muxer.h"

namespace flutter_webrtc_plugin {

const char kEventNameBase[] = "FlutterWebRTC/MediaRecorderEvent/";

FlutterMediaRecorder::FlutterMediaRecorder(FlutterWebRTCBase* base)
    : base_(base),
      audio_format_(AudioFormat{48000, 2, 16, 128000}),
      video_format_(VideoFormat{1500, 1000, 30, 4000000}),
      start_timestamp_(0),
      audio_recorder_(
          std::make_unique<FlutterAudioRecorder>(base_, this, audio_format_)),
      video_recorder_(
          std::make_unique<FlutterVideoRecorder>(base_, this, video_format_)),
      recording_thread_(std::make_unique<TaskThread>("Recording Thread")),
      muxing_thread_(std::make_unique<TaskThread>("Muxing Thread")) {}

void FlutterMediaRecorder::StartRecordToFile(
    std::string filepath,
    std::unique_ptr<MethodResultProxy> result) {
  recording_thread_->PostTask(
      [this, filepath = std::move(filepath), result = std::move(result)]() {
        if (filepath != current_filepath_) {
          // 新的录制
          // 保存原始输出文件路径
          current_filepath_ = filepath;

          size_t dot_pos = filepath.find_last_of('.');
          std::string base_path = (dot_pos != std::string::npos)
                                      ? filepath.substr(0, dot_pos)
                                      : filepath;
          std::string audio_temp_path = base_path + ".audio_temp";
          std::string video_temp_path = base_path + ".video_temp";

          // 记录开始录制时间戳
          start_timestamp_ =
              std::chrono::duration_cast<std::chrono::milliseconds>(
                  std::chrono::steady_clock::now().time_since_epoch())
                  .count();
          pause_elapsed_ts_ = 0;

          if (audio_recorder_) {
            bool success = audio_recorder_->Start(audio_temp_path);
            if (!success) {
              char buffer[256];
              strerror_s(buffer, sizeof(buffer), errno);
              result->Error("-1", "Failed to start audio recorder. filepath=" + audio_temp_path + ", error=" + buffer);
              return;
            }
          }

          if (video_recorder_) {
            bool success = video_recorder_->Start(video_temp_path);
            if (!success) {
              char buffer[256];
              strerror_s(buffer, sizeof(buffer), errno);
              result->Error("-1", "Failed to start video recorder. filepath=" + audio_temp_path + ", error=" + buffer);
              return;
            }
          }

          std::string channel_name = kEventNameBase + filepath;
          if (event_channels_.find(channel_name) == event_channels_.end()) {
            event_channels_.try_emplace(
                channel_name,
                EventChannelProxy::Create(base_->messenger_, channel_name));
          }
        } else {
          // 继续录制
          pause_elapsed_ts_ +=
              (std::chrono::duration_cast<std::chrono::milliseconds>(
                   std::chrono::steady_clock::now().time_since_epoch())
                   .count() -
               pause_timestamp_);

          if (audio_recorder_) {
            audio_recorder_->Resume();
          }

          if (video_recorder_) {
            video_recorder_->Resume();
          }
        }

        result->Success();
      });
}

void FlutterMediaRecorder::StopRecordToFile(
    std::unique_ptr<MethodResultProxy> result) {
  recording_thread_->PostTask([this, result = std::move(result)]() {
    pause_timestamp_ = std::chrono::duration_cast<std::chrono::milliseconds>(
                           std::chrono::steady_clock::now().time_since_epoch())
                           .count();

    if (audio_recorder_) {
      audio_recorder_->Pause();
    }

    if (video_recorder_) {
      video_recorder_->Pause();
    }

    result->Success();
  });
}

void FlutterMediaRecorder::TransRecordToFile(
    std::string path,
    std::unique_ptr<MethodResultProxy> result) {
  recording_thread_->PostTask(
      [this, path = std::move(path), result = std::move(result)]() {
        // 首先停止音频和视频录制器
        if (audio_recorder_) {
          RTC_LOG(LS_DEBUG) << "Stopping audio recorder";
          audio_recorder_->Stop();
        }

        if (video_recorder_) {
          RTC_LOG(LS_DEBUG) << "Stopping video recorder";
          video_recorder_->Stop();
        }

        RTC_LOG(LS_INFO) << "开始MP4合成任务...";

        result->Success();

        muxing_thread_->PostTask([this, output_path = std::move(path)]() {
          // 创建临时文件路径
          size_t dot_pos = output_path.find_last_of('.');
          std::string base_path = (dot_pos != std::string::npos)
                                      ? output_path.substr(0, dot_pos)
                                      : output_path;

          std::string audio_temp_path = base_path + ".audio_temp";
          std::string video_temp_path = base_path + ".video_temp";

          auto on_progress = [this, &output_path](float progress) {
            // RTC_LOG(LS_INFO) << "MP4合成进度:" << progress * 100.0f << "%";
            auto it = event_channels_.find(kEventNameBase + output_path);
            if (it != event_channels_.end()) {
              EncodableMap params;
              params.try_emplace(EncodableValue("event"),
                                 EncodableValue("onProgress"));
              params.try_emplace(EncodableValue("progress"), progress);
              it->second->Success(params);
            }
          };

          auto on_success = [this, &output_path]() {
            RTC_LOG(LS_INFO) << "Muxing finished successfully!";
            auto it = event_channels_.find(kEventNameBase + output_path);
            if (it != event_channels_.end()) {
              EncodableMap params;
              params.try_emplace(EncodableValue("event"),
                                 EncodableValue("onSuccess"));
              params.try_emplace(EncodableValue("path"),
                                 EncodableValue(output_path));
              it->second->Success(params);
              event_channels_.erase(it);
            }
          };

          auto on_failure = [this, &output_path](std::string error_msg) {
            RTC_LOG(LS_INFO) << "Muxing failed: " << error_msg
                             << ", output_path=" << output_path;
            auto it = event_channels_.find(kEventNameBase + output_path);
            if (it != event_channels_.end()) {
              EncodableMap params;
              params.try_emplace(EncodableValue("event"),
                                 EncodableValue("onFailure"));
              params.try_emplace(EncodableValue("error"),
                                 EncodableValue(std::move(error_msg)));
              it->second->Success(params);
              event_channels_.erase(it);
            }
          };

          MP4Muxer muxer;
          muxer.Mux(audio_format_, video_format_, audio_temp_path,
                    video_temp_path, output_path, std::move(on_progress),
                    std::move(on_success), std::move(on_failure));
        });
      });
}

}  // namespace flutter_webrtc_plugin