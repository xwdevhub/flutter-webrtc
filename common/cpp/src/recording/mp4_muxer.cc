#include "mp4_muxer.h"

#include <cmath>
#include <fstream>
#include <memory>
#include "flutter_webrtc_logging.h"

#ifdef _WIN32
#include <windows.h>
#endif

#ifndef __STDC_CONSTANT_MACROS
#define __STDC_CONSTANT_MACROS
#endif

extern "C" {
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/mem.h>
}

namespace {

template <typename T>
struct AVDeleter;

template <>
struct AVDeleter<AVFormatContext> {
  void operator()(AVFormatContext* ptr) const {
    if (ptr) {
      if (ptr->pb) {
        avio_closep(&ptr->pb);
      }
      avformat_free_context(ptr);
    }
  }
};

template <>
struct AVDeleter<AVPacket> {
  void operator()(AVPacket* ptr) const { av_packet_free(&ptr); }
};

using AVFormatContextPtr =
    std::unique_ptr<AVFormatContext, AVDeleter<AVFormatContext>>;
using AVPacketPtr = std::unique_ptr<AVPacket, AVDeleter<AVPacket>>;

std::string ff_error_str(int errnum) {
  char errbuf[AV_ERROR_MAX_STRING_SIZE];
  av_strerror(errnum, errbuf, sizeof(errbuf));
  return std::string(errbuf);
}

/**
 * @brief 将 GBK 编码的字符串转换为 UTF-8 编码
 *
 * @param gbk_str 从 e.what() 获取的 GBK 字符串
 * @return std::string UTF-8 编码的字符串
 */
std::string gbk_to_utf8(const std::string& gbk_str) {
#ifdef _WIN32
  if (gbk_str.empty()) {
    return std::string();
  }
  // 1. GBK to Wide Char (UTF-16)
  // CP_ACP 代表系统默认的 ANSI 代码页，在中文 Windows 上是 GBK
  int wide_len = MultiByteToWideChar(CP_ACP, 0, gbk_str.c_str(), -1, NULL, 0);
  if (wide_len == 0)
    return "";
  std::wstring wide_str(wide_len, 0);
  MultiByteToWideChar(CP_ACP, 0, gbk_str.c_str(), -1, &wide_str[0], wide_len);

  // 2. Wide Char (UTF-16) to UTF-8
  int utf8_len = WideCharToMultiByte(CP_UTF8, 0, wide_str.c_str(), -1, NULL, 0,
                                     NULL, NULL);
  if (utf8_len == 0)
    return "";
  std::string utf8_str(utf8_len, 0);
  WideCharToMultiByte(CP_UTF8, 0, wide_str.c_str(), -1, &utf8_str[0], utf8_len,
                      NULL, NULL);

  // 移除 WideCharToMultiByte 可能在末尾添加的空字符
  if (!utf8_str.empty() && utf8_str.back() == '\0') {
    utf8_str.pop_back();
  }

  return utf8_str;
#else
  // 非 Windows 平台，假设输入已经是 UTF-8，直接返回
  return gbk_str;
#endif
}

}  // namespace

namespace flutter_webrtc_plugin {

MP4Muxer::MP4Muxer() {
  // 初始化进度报告限制变量
  last_progress_time_ = std::chrono::steady_clock::now();
  last_progress_value_ = -1.0f;

  // 初始化PTS跟踪变量
  last_audio_pts_ = -1;
  last_video_pts_ = -1;
}

/**
 * 从临时文件中读取下一个媒体数据包
 * 格式：[时间戳(64bit)][大小(32bit)][数据]
 */
bool MP4Muxer::ReadNextPacket(std::ifstream& file, MediaPacket& packet) {
  if (!file.is_open() || file.eof()) {
    return false;
  }

  int64_t timestamp;
  uint32_t size;

  // 读取时间戳
  file.read(reinterpret_cast<char*>(&timestamp), sizeof(timestamp));
  if (file.gcount() != sizeof(timestamp)) {
    RTC_LOG(LS_DEBUG) << "Failed to read timestamp, gcount: " << file.gcount();
    return false;
  }

  // 读取数据大小
  file.read(reinterpret_cast<char*>(&size), sizeof(size));
  if (file.gcount() != sizeof(size)) {
    RTC_LOG(LS_DEBUG) << "Failed to read size, gcount: " << file.gcount();
    return false;
  }

  // 读取数据内容
  packet.timestamp = timestamp;
  packet.data.resize(size);
  file.read(reinterpret_cast<char*>(packet.data.data()), size);
  if (file.gcount() != size) {
    RTC_LOG(LS_DEBUG) << "Failed to read data, expected: " << size
                      << ", got: " << file.gcount();
    return false;
  }

  return true;
}

/**
 * 执行音视频混合的主函数
 * 将音频和视频临时文件混合成最终的MP4文件
 */
void MP4Muxer::Mux(const AudioFormat& audio_format,
                   const VideoFormat& video_format,
                   const std::string& audio_tmp_path,
                   const std::string& video_tmp_path,
                   const std::string& output_path,
                   OnProgressCallback on_progress,
                   OnSuccessCallback on_success,
                   OnFailureCallback on_failure) {
  try {
    // 打开临时文件
    std::ifstream audio_file(audio_tmp_path, std::ios::binary);
    std::ifstream video_file(video_tmp_path, std::ios::binary);

    if (!audio_file.is_open()) {
      on_failure("Failed to open audio temp file: " + audio_tmp_path);
      return;
    }
    if (!video_file.is_open()) {
      on_failure("Failed to open video temp file: " + video_tmp_path);
      return;
    }

    // 重置PTS跟踪变量
    last_audio_pts_ = -1;
    last_video_pts_ = -1;

    // 初始化输出上下文
    AVFormatContext* format_ctx_raw = nullptr;
    int ret = avformat_alloc_output_context2(&format_ctx_raw, nullptr, "mp4",
                                             output_path.c_str());
    if (ret < 0) {
      throw std::runtime_error("Could not open output file: " +
                               ff_error_str(ret));
    }
    AVFormatContextPtr format_context(format_ctx_raw);
    if (!format_context) {
      on_failure("Failed to initialize output context");
      return;
    }

    // 读取配置数据并创建流
    MediaPacket audio_config, video_config;
    if (!ReadNextPacket(audio_file, audio_config) ||
        audio_config.timestamp != 0) {
      on_failure("Failed to read audio config packet");
      return;
    }
    if (!ReadNextPacket(video_file, video_config) ||
        video_config.timestamp != 0) {
      on_failure("Failed to read video config packet");
      return;
    }

    // 创建音频和视频流
    AVStream* audio_stream = CreateAudioStream(format_context.get(),
                                               audio_format, audio_config.data);
    AVStream* video_stream = CreateVideoStream(format_context.get(),
                                               video_format, video_config.data);

    if (!audio_stream || !video_stream) {
      on_failure("Failed to create audio or video stream");
      return;
    }

    // 写入文件头
    WriteHeader(format_context.get());

    // 交织写入媒体包
    WriteInterleavedPackets(format_context.get(), audio_stream, video_stream,
                            audio_file, video_file, on_progress);

    // 写入文件尾
    av_write_trailer(format_context.get());
    if (on_progress)
      on_progress(1.0f);
    if (on_success)
      on_success();

  } catch (const std::exception& e) {
    std::string err_msg = gbk_to_utf8(e.what());
    RTC_LOG(LS_ERROR) << "Muxing failed: " << err_msg;
    on_failure(err_msg);
  }
}

/**
 * 创建并配置音频流
 */
AVStream* MP4Muxer::CreateAudioStream(AVFormatContext* format_context,
                                      const AudioFormat& audio_format,
                                      const std::vector<uint8_t>& config_data) {
  AVStream* stream = avformat_new_stream(format_context, nullptr);
  if (!stream) {
    throw std::runtime_error("Failed to create audio stream");
  }

  // 配置音频流参数
  stream->codecpar->codec_type = AVMEDIA_TYPE_AUDIO;
  stream->codecpar->codec_id = AV_CODEC_ID_AAC;

  // 设置音频配置数据（ASC - Audio Specific Config）
  stream->codecpar->extradata = static_cast<uint8_t*>(
      av_mallocz(config_data.size() + AV_INPUT_BUFFER_PADDING_SIZE));
  if (!stream->codecpar->extradata) {
    throw std::runtime_error("Failed to allocate audio extradata");
  }
  memcpy(stream->codecpar->extradata, config_data.data(), config_data.size());
  stream->codecpar->extradata_size = static_cast<int>(config_data.size());

  // 设置音频参数
  stream->codecpar->sample_rate = audio_format.sample_rate;
  stream->codecpar->bit_rate = audio_format.bit_rate;
  stream->codecpar->format = AV_SAMPLE_FMT_FLTP;  // AAC使用浮点格式

  // 设置通道布局
  av_channel_layout_default(&stream->codecpar->ch_layout,
                            audio_format.channels);
  if (audio_format.channels > 2) {
    throw std::runtime_error("Unsupported number of channels");
  }

  // 设置时间基为采样率的倒数
  // stream->time_base = {1, static_cast<int>(audio_format.sample_rate)};
  stream->time_base = {1, 90000};

  RTC_LOG(LS_INFO) << "Audio stream configured - sample_rate: "
                   << stream->codecpar->sample_rate
                   << ", channels: " << stream->codecpar->ch_layout.nb_channels
                   << ", time_base: " << stream->time_base.num << "/"
                   << stream->time_base.den;

  return stream;
}

/**
 * 创建并配置视频流
 */
AVStream* MP4Muxer::CreateVideoStream(AVFormatContext* format_context,
                                      const VideoFormat& video_format,
                                      const std::vector<uint8_t>& config_data) {
  AVStream* stream = avformat_new_stream(format_context, nullptr);
  if (!stream) {
    throw std::runtime_error("Failed to create video stream");
  }

  // 配置视频流参数
  stream->codecpar->codec_type = AVMEDIA_TYPE_VIDEO;
  stream->codecpar->codec_id = AV_CODEC_ID_H264;

  // 设置视频配置数据（SPS/PPS）
  stream->codecpar->extradata = static_cast<uint8_t*>(
      av_mallocz(config_data.size() + AV_INPUT_BUFFER_PADDING_SIZE));
  if (!stream->codecpar->extradata) {
    throw std::runtime_error("Failed to allocate video extradata");
  }
  memcpy(stream->codecpar->extradata, config_data.data(), config_data.size());
  stream->codecpar->extradata_size = static_cast<int>(config_data.size());

  // 设置视频参数
  stream->codecpar->width = static_cast<int>(video_format.width);
  stream->codecpar->height = static_cast<int>(video_format.height);
  stream->codecpar->bit_rate = video_format.bit_rate;
  stream->codecpar->format = AV_PIX_FMT_YUV420P;

  // 设置时间基为帧率的倒数（毫秒精度）
  // stream->time_base = {1, static_cast<int>(video_format.fps * 1000)};
  stream->time_base = {1, 90000};

  RTC_LOG(LS_INFO) << "Video stream configured - width: "
                   << stream->codecpar->width
                   << ", height: " << stream->codecpar->height
                   << ", fps: " << video_format.fps
                   << ", time_base: " << stream->time_base.num << "/"
                   << stream->time_base.den;

  return stream;
}

/**
 * 写入MP4文件头信息
 */
void MP4Muxer::WriteHeader(AVFormatContext* format_context) {
  // 打开输出文件
  if (!(format_context->oformat->flags & AVFMT_NOFILE)) {
    int ret =
        avio_open(&format_context->pb, format_context->url, AVIO_FLAG_WRITE);
    if (ret < 0) {
      throw std::runtime_error("Could not open output file: " +
                               ff_error_str(ret));
    }
  }

  // 设置优化选项，将moov atom移到文件头
  AVDictionary* opt = nullptr;
  av_dict_set(&opt, "movflags", "faststart", 0);

  // 写入文件头
  int ret = avformat_write_header(format_context, &opt);
  if (ret < 0) {
    av_dict_free(&opt);
    throw std::runtime_error("Error writing header: " + ff_error_str(ret));
  }

  av_dict_free(&opt);
}

/**
 * 交织写入音频和视频数据包
 */
void MP4Muxer::WriteInterleavedPackets(AVFormatContext* format_context,
                                       AVStream* audio_stream,
                                       AVStream* video_stream,
                                       std::ifstream& audio_file,
                                       std::ifstream& video_file,
                                       OnProgressCallback on_progress) {
  // 计算总文件大小用于进度报告
  audio_file.seekg(0, std::ios::end);
  video_file.seekg(0, std::ios::end);
  long long total_size = audio_file.tellg() + video_file.tellg();
  audio_file.seekg(0, std::ios::beg);
  video_file.seekg(0, std::ios::beg);

  // 跳过配置块
  MediaPacket temp_config;
  ReadNextPacket(audio_file, temp_config);
  ReadNextPacket(video_file, temp_config);

  // 读取第一个数据包
  MediaPacket audio_packet, video_packet;
  bool has_audio = ReadNextPacket(audio_file, audio_packet);
  bool has_video = ReadNextPacket(video_file, video_packet);

  // 交织写入循环
  while (has_audio || has_video) {
    // 选择时间戳较早的包
    bool use_audio = has_audio && (!has_video || audio_packet.timestamp <=
                                                     video_packet.timestamp);

    AVStream* out_stream = use_audio ? audio_stream : video_stream;
    MediaPacket* current_packet = use_audio ? &audio_packet : &video_packet;
    current_packet->is_video = !use_audio;

    // 验证数据包
    if (current_packet->data.empty()) {
      RTC_LOG(LS_WARNING) << "Skipping invalid packet - empty: "
                          << (current_packet->data.empty() ? "true" : "false")
                          << ", timestamp: " << current_packet->timestamp;
      if (use_audio) {
        has_audio = ReadNextPacket(audio_file, audio_packet);
      } else {
        has_video = ReadNextPacket(video_file, video_packet);
      }
      continue;
    }

    // 写入数据包
    WritePacket(format_context, out_stream, *current_packet);

    // 读取下一个包
    if (use_audio) {
      has_audio = ReadNextPacket(audio_file, audio_packet);
    } else {
      has_video = ReadNextPacket(video_file, video_packet);
    }

    // 限制进度回调频率，避免回调次数过多
    if (on_progress) {
      auto now = std::chrono::steady_clock::now();
      auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          now - last_progress_time_);

      // 至少间隔100ms才报告进度，或进度值发生较大变化时
      float progress = CalculateProgress(audio_file, video_file, total_size);
      if (progress > 0 && (elapsed >= std::chrono::milliseconds(100) ||
                           abs(progress - last_progress_value_) > 0.02f)) {
        on_progress(progress);
        last_progress_time_ = now;
        last_progress_value_ = progress;
      }
    }
  }
}

/**
 * 写入单个AVPacket到输出流
 */
void MP4Muxer::WritePacket(AVFormatContext* format_context,
                           AVStream* stream,
                           const MediaPacket& packet) {
  AVPacketPtr pkt(av_packet_alloc());
  if (!pkt) {
    throw std::runtime_error("Failed to allocate packet");
  }

  int packet_size = static_cast<int>(packet.data.size());
  int ret = av_new_packet(pkt.get(), packet_size);
  if (ret < 0) {
    throw std::runtime_error("Failed to allocate packet data: " +
                             ff_error_str(ret));
  }

  // 复制数据
  memcpy(pkt->data, packet.data.data(), packet_size);
  pkt->stream_index = stream->index;

  // 转换时间戳
  // AVRational time_base = {1, 1000000000};
  AVRational time_base = {1, 1000};
  int64_t converted_pts =
      av_rescale_q(packet.timestamp, time_base, stream->time_base);
  if (converted_pts < 0) {
    RTC_LOG(LS_WARNING) << "Invalid timestamp converted to negative value: "
                        << converted_pts
                        << " for packet with timestamp: " << packet.timestamp
                        << " , is_video: " << packet.is_video
                        << ", time_base=" << stream->time_base.num << "/"
                        << stream->time_base.den;
    converted_pts = 0;
  }

    RTC_LOG(LS_INFO) << "Writing packet with time_base=" << stream->time_base.num
                   << "/" << stream->time_base.den
                   << ", timestamp=" << packet.timestamp
                   << ", pts=" << converted_pts
                   << ", is_video=" << packet.is_video;

  // 确保PTS单调递增
  int64_t* last_pts = packet.is_video ? &last_video_pts_ : &last_audio_pts_;
  // PTS 增量 = 期望时长(秒) / 时间基单位(秒)
  // 视频 (1/30) / (1/90000) = 90000 / 30 = 3000
  // 音频 (1/100) / (1/48000) = 48000 / 100 = 480
  // int64_t expected_duration = packet.is_video ? 3000 : 480;
  if (*last_pts >= 0 && converted_pts <= *last_pts) {
    RTC_LOG(LS_WARNING) << (packet.is_video ? "Video" : "Audio")
                        << " non-monotonic timestamp detected! Original PTS: "
                        << converted_pts << ", Last PTS: " << *last_pts
                        << ". Adjusting PTS.";

    // 使用期望的帧时长来生成新的PTS，而不是简单+1
    // converted_pts = *last_pts + expected_duration;
    converted_pts = *last_pts + 1;
  } else {
    // RTC_LOG(LS_DEBUG) << (packet.is_video ? "video " : "audio ")
    //                   << " pts = " << converted_pts;
  }
  *last_pts = converted_pts;

  pkt->pts = pkt->dts = converted_pts;
  pkt->duration = 0;
  pkt->pos = -1;

  // 检测关键帧
  if (packet.is_video && pkt->size > 4) {
    if (IsKeyFrame(pkt->data, pkt->size)) {
      pkt->flags |= AV_PKT_FLAG_KEY;
    }
  }

  // RTC_LOG(LS_INFO) << "Writing packet - Stream: " << pkt->stream_index
  //                  << ", Size: " << pkt->size << ", PTS: " << pkt->pts
  //                  << ", Is_video: " << packet.is_video
  //                  << ", Timestamp: " << packet.timestamp;

  // 写入帧
  ret = av_interleaved_write_frame(format_context, pkt.get());
  if (ret < 0) {
    std::string err_msg = ff_error_str(ret);
    RTC_LOG(LS_ERROR) << "Error writing frame: " << err_msg;
    throw std::runtime_error("Error writing frame: " + err_msg);
  }
}

/**
 * 检测视频帧是否为关键帧（H.264 IDR帧）
 */
bool MP4Muxer::IsKeyFrame(const uint8_t* data, int size) {
  for (int i = 0; i < size - 4; ++i) {
    // 检查NAL单元起始码
    if ((data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 &&
         data[i + 3] == 1) ||
        (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1)) {
      int offset = (data[i + 2] == 1) ? 3 : 4;
      if (i + offset < size) {
        uint8_t nal_type = data[i + offset] & 0x1F;
        if (nal_type == 5) {  // IDR帧
          return true;
        }
      }
      break;
    }
  }
  return false;
}

/**
 * 计算文件处理进度
 */
float MP4Muxer::CalculateProgress(std::ifstream& audio_file,
                                  std::ifstream& video_file,
                                  long long total_size) {
  std::streampos audio_pos = audio_file.tellg();
  std::streampos video_pos = video_file.tellg();

  if (audio_pos < 0 || video_pos < 0 || total_size <= 0) {
    return -1.0f;
  }

  long long current_pos =
      static_cast<long long>(audio_pos) + static_cast<long long>(video_pos);
  return static_cast<float>(current_pos) / total_size;
}

}  // namespace flutter_webrtc_plugin
