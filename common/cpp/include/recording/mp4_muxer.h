#ifndef FLUTTER_WEBRTC_MP4MUXER_HPP
#define FLUTTER_WEBRTC_MP4MUXER_HPP

#include <chrono>
#include <fstream>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "types.h"

// 前向声明FFmpeg结构体
struct AVFormatContext;
struct AVStream;

namespace flutter_webrtc_plugin {

/**
 * MP4混合器类，用于将音频和视频流混合成MP4文件
 * 该类使用RAII管理FFmpeg资源，不可拷贝和移动
 */
class MP4Muxer {
 public:
  // 定义回调函数类型
  using OnProgressCallback = std::function<void(float)>;  // 进度 0.0f - 1.0f
  using OnSuccessCallback = std::function<void()>;
  using OnFailureCallback = std::function<void(std::string)>;

  /**
   * 构造函数
   */
  MP4Muxer();

  /**
   * 析构函数，确保资源正确释放
   */
  ~MP4Muxer() = default;

  // 禁用拷贝构造和拷贝赋值
  MP4Muxer(const MP4Muxer&) = delete;
  MP4Muxer& operator=(const MP4Muxer&) = delete;

  // 禁用移动构造和移动赋值
  MP4Muxer(MP4Muxer&&) = delete;
  MP4Muxer& operator=(MP4Muxer&&) = delete;

  /**
   * 执行音视频混合操作
   * @param audio_format 音频格式参数
   * @param video_format 视频格式参数
   * @param audio_tmp_path 音频临时文件路径
   * @param video_tmp_path 视频临时文件路径
   * @param output_path 输出MP4文件路径
   * @param on_progress 进度回调函数
   * @param on_success 成功回调函数
   * @param on_failure 失败回调函数
   */
  void Mux(const AudioFormat& audio_format,
           const VideoFormat& video_format,
           const std::string& audio_tmp_path,
           const std::string& video_tmp_path,
           const std::string& output_path,
           OnProgressCallback on_progress,
           OnSuccessCallback on_success,
           OnFailureCallback on_failure);

 private:
  // 进度报告限制相关成员变量
  std::chrono::steady_clock::time_point last_progress_time_;  // 最后一次进度报告时间
  float last_progress_value_;  // 最后一次报告的进度值

  // PTS单调递增相关成员变量
  int64_t last_audio_pts_;  // 音频流最后的PTS值
  int64_t last_video_pts_;  // 视频流最后的PTS值

  // 内部结构，用于存储从临时文件读取的数据包
  struct MediaPacket {
    int64_t timestamp = 0;  // 时间戳
    std::vector<uint8_t> data;
    bool is_video = false;
  };

  /**
   * 从临时文件中读取下一个数据包
   * @param file 输入文件流
   * @param packet 输出的媒体包
   * @return 成功返回true，失败返回false
   */
  bool ReadNextPacket(std::ifstream& file, MediaPacket& packet);

  /**
   * 创建并配置音频流
   * @param format_context FFmpeg格式上下文
   * @param audio_format 音频格式参数
   * @param config_data 音频配置数据
   * @return 创建的音频流指针
   */
  AVStream* CreateAudioStream(AVFormatContext* format_context,
                              const AudioFormat& audio_format,
                              const std::vector<uint8_t>& config_data);

  /**
   * 创建并配置视频流
   * @param format_context FFmpeg格式上下文
   * @param video_format 视频格式参数
   * @param config_data 视频配置数据
   * @return 创建的视频流指针
   */
  AVStream* CreateVideoStream(AVFormatContext* format_context,
                              const VideoFormat& video_format,
                              const std::vector<uint8_t>& config_data);

  /**
   * 写入文件头信息
   * @param format_context FFmpeg格式上下文
   */
  void WriteHeader(AVFormatContext* format_context);

  /**
   * 交错写入媒体包
   * @param format_context FFmpeg格式上下文
   * @param audio_stream 音频流
   * @param video_stream 视频流
   * @param audio_file 音频文件流
   * @param video_file 视频文件流
   * @param on_progress 进度回调
   */
  void WriteInterleavedPackets(AVFormatContext* format_context,
                               AVStream* audio_stream,
                               AVStream* video_stream,
                               std::ifstream& audio_file,
                               std::ifstream& video_file,
                               OnProgressCallback on_progress);

  /**
   * 写入单个AVPacket到输出流
   * @param format_context FFmpeg格式上下文
   * @param stream 目标流
   * @param packet 媒体包数据
   */
  void WritePacket(AVFormatContext* format_context,
                   AVStream* stream,
                   const MediaPacket& packet);

  /**
   * 检测视频帧是否为关键帧
   * @param data 帧数据
   * @param size 数据大小
   * @return 是关键帧返回true
   */
  bool IsKeyFrame(const uint8_t* data, int size);

  /**
   * 计算文件处理进度
   * @param audio_file 音频文件流
   * @param video_file 视频文件流
   * @param total_size 总文件大小
   * @return 进度百分比(0.0-1.0)
   */
  float CalculateProgress(std::ifstream& audio_file,
                          std::ifstream& video_file,
                          long long total_size);
};

}  // namespace flutter_webrtc_plugin

#endif
