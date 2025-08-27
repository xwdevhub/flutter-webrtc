#ifndef FLUTTER_WEBRTC_MEDIA_RECORDER_HXX
#define FLUTTER_WEBRTC_MEDIA_RECORDER_HXX

#include <memory>
#include "flutter_webrtc_base.h"
#include "task_thread.h"
#include "types.h"

namespace flutter_webrtc_plugin {

class FlutterRecorderInterface {
 public:
  virtual ~FlutterRecorderInterface() {};

  virtual bool Start(const std::string& filepath) = 0;

  virtual void Stop() = 0;

  virtual void Resume() = 0;

  virtual void Pause() = 0;

  virtual RecordingState State() const = 0;
};

class FlutterMediaRecorder {
 public:
  friend class FlutterAudioRecorder;
  friend class FlutterVideoRecorder;

 public:
  /**
   * @brief 构造函数，初始化音频/视频录制器及MP4合成功能
   * @param base Flutter WebRTC基础对象
   */
  FlutterMediaRecorder(FlutterWebRTCBase* base);

  /**
   * @brief 开始媒体录制
   *
   * 创建临时音频/视频文件 并开始录制
   * @param filepath 输出MP4文件路径（录制完成后自动合成到此路径）
   * @param result 结果回调
   */
  void StartRecordToFile(std::string filepath, std::unique_ptr<MethodResultProxy> result);

  /**
   * @brief 停止媒体录制并启动MP4合成
   *
   * 停止音频/视频录制器，异步读取临时文件合成MP4
   * 支持音画同步和进度回调，完成后自动清理临时文件
   * @param result 结果回调（合成成功或失败）
   */
  void StopRecordToFile(std::unique_ptr<MethodResultProxy> result);

  void TransRecordToFile(std::string path, std::unique_ptr<MethodResultProxy> result);

 private:
  FlutterWebRTCBase* base_;
  const AudioFormat audio_format_;
  const VideoFormat video_format_;
  // 录制相关的临时文件和时间戳
  std::string current_filepath_;

  std::atomic<int64_t> start_timestamp_{0};   // 录制开始时间戳
  std::atomic<int64_t> pause_timestamp_{0};   // 录制暂停时间戳
  std::atomic<int64_t> pause_elapsed_ts_{0};  // 暂停时长

  std::unique_ptr<FlutterRecorderInterface> audio_recorder_;
  std::unique_ptr<FlutterRecorderInterface> video_recorder_;

  std::unordered_map<std::string, std::unique_ptr<EventChannelProxy>> event_channels_;

  std::unique_ptr<TaskThread> recording_thread_;
  std::unique_ptr<TaskThread> muxing_thread_;
};

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_WEBRTC_MEDIA_RECORDER_HXX
