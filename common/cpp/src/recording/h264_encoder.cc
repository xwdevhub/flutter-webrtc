#include "h264_encoder.h"
#include "flutter_webrtc_logging.h"

extern "C" {
#include <libavutil/pixdesc.h>
}

namespace flutter_webrtc_plugin {

// 获取硬件设备类型
AVHWDeviceType GetHWDeviceType(const char* codec_name) {
  if (strcmp(codec_name, "h264_nvenc") == 0) {
    return AV_HWDEVICE_TYPE_CUDA;
  } else if (strcmp(codec_name, "h264_qsv") == 0) {
    return AV_HWDEVICE_TYPE_QSV;
  } else if (strcmp(codec_name, "h264_vaapi") == 0) {
    return AV_HWDEVICE_TYPE_VAAPI;
  } else if (strcmp(codec_name, "h264_videotoolbox") == 0) {
    return AV_HWDEVICE_TYPE_VIDEOTOOLBOX;
  }
  return AV_HWDEVICE_TYPE_NONE;
}

// 检查硬件设备是否可用并提供诊断信息
bool IsHWDeviceAvailable(AVHWDeviceType type, const char* codec_name) {
  // 检查设备类型是否被FFmpeg支持
  AVHWDeviceType current = AV_HWDEVICE_TYPE_NONE;
  bool supported = false;
  while ((current = av_hwdevice_iterate_types(current)) !=
         AV_HWDEVICE_TYPE_NONE) {
    if (current == type) {
      supported = true;
      break;
    }
  }

  if (!supported) {
    RTC_LOG(LS_WARNING) << "Hardware device type "
                        << av_hwdevice_get_type_name(type)
                        << " is not supported by this FFmpeg build";
    return false;
  }

  // 尝试创建设备上下文来检查实际可用性
  AVBufferRef* test_ctx = nullptr;
  int ret = av_hwdevice_ctx_create(&test_ctx, type, nullptr, nullptr, 0);
  if (ret < 0) {
    char errbuf[AV_ERROR_MAX_STRING_SIZE];
    av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);

    // 提供具体的诊断信息
    if (type == AV_HWDEVICE_TYPE_CUDA) {
      RTC_LOG(LS_WARNING)
          << "CUDA device not available for " << codec_name
          << ". Error: " << errbuf
          << ". Please ensure NVIDIA drivers and CUDA are properly installed.";
    } else if (type == AV_HWDEVICE_TYPE_QSV) {
      RTC_LOG(LS_WARNING)
          << "Intel QSV device not available for " << codec_name
          << ". Error: " << errbuf
          << ". Please ensure Intel graphics drivers are installed.";
    } else if (type == AV_HWDEVICE_TYPE_VAAPI) {
      RTC_LOG(LS_WARNING) << "VAAPI device not available for " << codec_name
                          << ". Error: " << errbuf
                          << ". Please ensure VAAPI drivers are installed and "
                             "/dev/dri/renderD* devices exist.";
    } else {
      RTC_LOG(LS_WARNING) << "Hardware device not available for " << codec_name
                          << ". Error: " << errbuf;
    }
    return false;
  }

  // 清理测试上下文
  av_buffer_unref(&test_ctx);
  return true;
}

H264Encoder::H264Encoder(const VideoFormat& format, std::ofstream& file)
    : output_format_(format), output_file_(file) {}

H264Encoder::~H264Encoder() {
  // 发送一个 nullptr 帧以刷新编码器中缓存的帧
  if (codec_context_) {
    SendFrame(nullptr);
  }
}

bool H264Encoder::InitializeEncoder(int width, int height) {
  // 优先尝试硬件编码器
  const char* hardware_codecs[] = {"h264_nvenc", "h264_qsv", "h264_vaapi",
                                   "h264_vulkan"};
  const char* fallback_codec = "libx264";

  const AVCodec* codec = nullptr;
  bool encoder_found = false;

  // 尝试硬件编码器
  for (const char* codec_name : hardware_codecs) {
    codec = avcodec_find_encoder_by_name(codec_name);
    if (!codec) {
      RTC_LOG(LS_DEBUG) << "Encoder not found: " << codec_name;
      continue;
    }

    RTC_LOG(LS_DEBUG) << "Found encoder: " << codec_name
                      << ", capabilities: " << codec->capabilities;

    codec_context_.reset(avcodec_alloc_context3(codec));
    if (!codec_context_) {
      RTC_LOG(LS_ERROR) << "Failed to allocate codec context for "
                        << codec_name;
      continue;
    }

    codec_context_->width = width;
    codec_context_->height = height;
    codec_context_->bit_rate = output_format_.bit_rate;
    codec_context_->time_base = {1, (int)output_format_.fps};
    codec_context_->framerate = {(int)output_format_.fps, 1};
    codec_context_->gop_size = output_format_.fps * 2;  // I-frame interval
    codec_context_->max_b_frames = 0;                   // 禁用b帧
    codec_context_->codec_type = AVMEDIA_TYPE_VIDEO;
    // 像素格式稍后根据硬件配置设置

    // 检查硬件编码器是否需要硬件帧上下文
    if (codec->capabilities & AV_CODEC_CAP_HARDWARE) {
      RTC_LOG(LS_DEBUG)
          << "Hardware encoder detected, initializing hardware contexts.";

      // 获取硬件设备类型
      AVHWDeviceType hw_device_type = GetHWDeviceType(codec_name);
      if (hw_device_type == AV_HWDEVICE_TYPE_NONE) {
        RTC_LOG(LS_WARNING)
            << "Unknown hardware device type for codec: " << codec_name;
        continue;
      }

      // 检查硬件设备是否可用
      if (!IsHWDeviceAvailable(hw_device_type, codec_name)) {
        continue;
      }

      // 创建硬件设备上下文
      AVBufferRef* hw_device_ctx_raw = nullptr;
      int ret = av_hwdevice_ctx_create(&hw_device_ctx_raw, hw_device_type,
                                       nullptr, nullptr, 0);
      if (ret < 0) {
        // IsHWDeviceAvailable 已经记录了详细的错误信息，这里只需要跳过
        continue;
      }
      hw_device_ctx_.reset(hw_device_ctx_raw);

      // 设置编码器上下文的硬件设备上下文
      codec_context_->hw_device_ctx = av_buffer_ref(hw_device_ctx_raw);

      // 获取硬件配置以确定正确的像素格式
      const AVCodecHWConfig* config = nullptr;
      bool config_found = false;
      for (int i = 0; (config = avcodec_get_hw_config(codec, i)); ++i) {
        if (config->device_type == hw_device_type) {
          config_found = true;
          break;
        }
      }

      if (!config_found || !config) {
        RTC_LOG(LS_WARNING)
            << "No suitable hardware config found for " << codec_name
            << " with device " << av_hwdevice_get_type_name(hw_device_type);
        hw_device_ctx_.reset();
        continue;
      }

      // 设置编码器像素格式为硬件格式
      codec_context_->pix_fmt = config->pix_fmt;

      // 创建硬件帧上下文
      AVBufferRef* hw_frames_ctx_raw = av_hwframe_ctx_alloc(hw_device_ctx_raw);
      if (!hw_frames_ctx_raw) {
        RTC_LOG(LS_WARNING)
            << "Failed to allocate hardware frames context for " << codec_name;
        hw_device_ctx_.reset();
        continue;
      }
      hw_frames_ctx_.reset(hw_frames_ctx_raw);

      // 配置硬件帧上下文
      AVHWFramesContext* frames_ctx =
          (AVHWFramesContext*)hw_frames_ctx_raw->data;
      frames_ctx->format = config->pix_fmt;
      frames_ctx->sw_format = AV_PIX_FMT_YUV420P;  // 输入格式
      frames_ctx->width = width;
      frames_ctx->height = height;
      frames_ctx->initial_pool_size = 20;  // 设置初始池大小

      // 初始化硬件帧上下文
      ret = av_hwframe_ctx_init(hw_frames_ctx_raw);
      if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
        RTC_LOG(LS_WARNING)
            << "Failed to initialize hardware frames context for " << codec_name
            << ". Error: " << errbuf;
        hw_frames_ctx_.reset();
        hw_device_ctx_.reset();
        continue;
      }

      // 设置编码器上下文的硬件帧上下文
      codec_context_->hw_frames_ctx = av_buffer_ref(hw_frames_ctx_raw);

      RTC_LOG(LS_INFO) << "Hardware contexts initialized successfully for "
                       << codec_name << " (device: "
                       << av_hwdevice_get_type_name(hw_device_type)
                       << ", format: " << av_get_pix_fmt_name(config->pix_fmt)
                       << ")";
    } else {
      // 软件编码器或混合编码器
      if (codec->capabilities & AV_CODEC_CAP_HYBRID) {
        RTC_LOG(LS_DEBUG) << "Hybrid encoder detected (has hardware "
                             "acceleration but may fallback to software). "
                          << "Treating as software encoder for compatibility.";
      } else {
        RTC_LOG(LS_DEBUG) << "Software encoder selected.";
      }
      codec_context_->pix_fmt = AV_PIX_FMT_YUV420P;
    }

    RTC_LOG(LS_DEBUG) << "Codec context setup - Width: "
                      << codec_context_->width
                      << ", Height: " << codec_context_->height
                      << ", Bitrate: " << codec_context_->bit_rate
                      << ", Timebase: " << codec_context_->time_base.num << "/"
                      << codec_context_->time_base.den
                      << ", Framerate: " << codec_context_->framerate.num << "/"
                      << codec_context_->framerate.den
                      << ", GOP size: " << codec_context_->gop_size
                      << ", PixFmt: "
                      << av_get_pix_fmt_name(codec_context_->pix_fmt);

    // 在设置完通用参数后，为特定编码器添加选项
    if (strcmp(codec_name, "h264_qsv") == 0) {
      // QSV特定的配置
      av_opt_set(codec_context_->priv_data, "preset", "veryfast", 0);
      av_opt_set(codec_context_->priv_data, "low_power", "0", 0);  // 性能模式
      av_opt_set(codec_context_->priv_data, "async_depth", "1",
                 0);  // 降低异步深度
      av_opt_set(codec_context_->priv_data, "idr_interval", "0",
                 0);  // 禁用IDR间隔
      // 尝试设置QSV特定的设备参数
      av_opt_set(codec_context_->priv_data, "gpu_copy", "on", 0);
    } else if (strcmp(codec_name, "h264_nvenc") == 0) {
      // NVENC特定的配置
      av_opt_set(codec_context_->priv_data, "preset", "fast", 0);
      av_opt_set(codec_context_->priv_data, "rc", "cbr", 0);  // 恒定码率
    } else if (strcmp(codec_name, "h264_vaapi") == 0) {
      // VAAPI特定的配置
      av_opt_set(codec_context_->priv_data, "low_power", "0", 0);
    }

    codec_context_->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    int open_result = avcodec_open2(codec_context_.get(), codec, nullptr);
    if (open_result >= 0) {
      RTC_LOG(LS_INFO) << "Successfully opened encoder: " << codec_name;
      encoder_found = true;
      break;
    } else {
      char errbuf[AV_ERROR_MAX_STRING_SIZE];
      av_strerror(open_result, errbuf, AV_ERROR_MAX_STRING_SIZE);
      RTC_LOG(LS_WARNING) << "Failed to open codec '" << codec_name
                          << "'. Error: " << errbuf << " (code: " << open_result
                          << ")";
      if (strcmp(codec_name, "h264_qsv") == 0) {
        RTC_LOG(LS_WARNING) << "QSV encoder failed. This may be due to missing "
                               "Intel graphics drivers, "
                            << "incompatible hardware, or QSV not being "
                               "supported on this system. "
                            << "Consider updating Intel graphics drivers or "
                               "using software encoding.";
      }
      codec_context_.reset();  // 释放上下文，尝试下一个
    }
  }

  // 如果所有硬件编码器都失败，尝试回退到 libx264
  if (!encoder_found) {
    RTC_LOG(LS_WARNING) << "All hardware encoders failed, trying fallback "
                           "software encoder (libx264). Hardware acceleration "
                           "may not be available on this system or requires "
                           "additional driver installation.";

    codec = avcodec_find_encoder_by_name(fallback_codec);
    if (!codec) {
      RTC_LOG(LS_ERROR) << "Fallback encoder 'libx264' not found.";
      RTC_LOG(LS_ERROR) << "Please ensure FFmpeg is properly installed with "
                           "H.264 encoding support";
      return false;
    }

    codec_context_.reset(avcodec_alloc_context3(codec));
    if (!codec_context_) {
      RTC_LOG(LS_ERROR) << "Failed to allocate codec context for libx264.";
      return false;
    }

    codec_context_->width = width;
    codec_context_->height = height;
    // codec_context_->bit_rate = output_format_.bit_rate; 改用 crf 提高质量
    codec_context_->time_base = {1, (int)output_format_.fps};
    codec_context_->framerate = {(int)output_format_.fps, 1};
    codec_context_->gop_size = output_format_.fps * 2;
    codec_context_->max_b_frames = 0;
    codec_context_->pix_fmt = AV_PIX_FMT_YUV420P;

    // 设置软件编码器优化
    // 使用CRF代替固定比特率，数值越小质量越高 (例如 18-22)
    av_opt_set(codec_context_->priv_data, "crf", "20", 0);
    // 可选参数: ultrafast, superfastm, veryfast, faster, fast, medium, slow,
    // slower, veryslow, placebo
    av_opt_set(codec_context_->priv_data, "preset", "slow", 0);
    av_opt_set(codec_context_->priv_data, "tune", "zerolatency", 0);
    // 可选参数: baseline, main, high, high10, high422, high444
    av_opt_set(codec_context_->priv_data, "profile", "high", 0);
    av_opt_set(codec_context_->priv_data, "level", "4.0", 0);

    RTC_LOG(LS_DEBUG) << "Codec context setup for libx264 - Width: "
                      << codec_context_->width
                      << ", Height: " << codec_context_->height
                      << ", Bitrate: " << codec_context_->bit_rate
                      << ", Timebase: " << codec_context_->time_base.num << "/"
                      << codec_context_->time_base.den
                      << ", Framerate: " << codec_context_->framerate.num << "/"
                      << codec_context_->framerate.den
                      << ", GOP size: " << codec_context_->gop_size
                      << ", PixFmt: "
                      << av_get_pix_fmt_name(codec_context_->pix_fmt);

    codec_context_->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    int open_result = avcodec_open2(codec_context_.get(), codec, nullptr);
    if (open_result < 0) {
      char errbuf[AV_ERROR_MAX_STRING_SIZE];
      av_strerror(open_result, errbuf, AV_ERROR_MAX_STRING_SIZE);
      RTC_LOG(LS_ERROR) << "Failed to open fallback codec 'libx264'. Error: "
                        << errbuf;
      return false;
    }

    RTC_LOG(LS_INFO)
        << "Successfully opened fallback software encoder 'libx264'";
    encoder_found = true;
  }

  sw_frame_.reset(av_frame_alloc());
  sw_frame_->width = width;
  sw_frame_->height = height;
  sw_frame_->format = AV_PIX_FMT_YUV420P;
  if (av_frame_get_buffer(sw_frame_.get(), 0) < 0) {
    RTC_LOG(LS_ERROR) << "Failed to allocate frame buffer.";
    return false;
  }

  return true;
}

bool H264Encoder::InitializeScaler(int src_w, int src_h, int dst_w, int dst_h) {
  sws_context_.reset(sws_getContext(src_w, src_h, AV_PIX_FMT_YUV420P, dst_w,
                                    dst_h, AV_PIX_FMT_YUV420P, SWS_BILINEAR,
                                    nullptr, nullptr, nullptr));
  if (!sws_context_) {
    RTC_LOG(LS_ERROR) << "Failed to create SWS context.";
    return false;
  }
  current_input_width_ = src_w;
  current_input_height_ = src_h;
  return true;
}

void H264Encoder::WritePacket(uint64_t ts, const AVPacket* packet) {
  uint32_t data_size = packet->size;
  output_file_.write(reinterpret_cast<const char*>(&ts), sizeof(ts));
  output_file_.write(reinterpret_cast<const char*>(&data_size),
                     sizeof(data_size));
  output_file_.write(reinterpret_cast<const char*>(packet->data), data_size);
}

bool H264Encoder::SendFrame(const AVFrame* frame) {
  int ret = avcodec_send_frame(codec_context_.get(), frame);
  if (ret < 0) {
    if (ret != AVERROR_EOF && ret != AVERROR(EAGAIN)) {
      RTC_LOG(LS_ERROR) << "Error sending frame to encoder.";
    }
    return false;
  }

  AVPacket* packet = av_packet_alloc();
  while (ret >= 0) {
    ret = avcodec_receive_packet(codec_context_.get(), packet);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
      break;
    } else if (ret < 0) {
      RTC_LOG(LS_ERROR) << "Error receiving packet from encoder.";
      av_packet_free(&packet);
      return false;
    }

    WritePacket(packet->pts, packet);
  }
  av_packet_free(&packet);
  return true;
}

bool H264Encoder::Encode(const VideoFrame& video_frame) {
  // 1. 初始化编码器（如果尚未完成）
  if (!codec_context_) {
    if (!InitializeEncoder(output_format_.width, output_format_.height)) {
      return false;
    }

    // 2. 写入SPS/PPS（仅一次）
    if (!sps_pps_written_ && codec_context_->extradata_size > 0 &&
        output_file_.tellp() == 0) {
      RTC_LOG(LS_DEBUG) << "Write sps/pps, extradata_size="
                        << codec_context_->extradata_size;
      AVPacket* sps_pps_packet = av_packet_alloc();
      sps_pps_packet->data = codec_context_->extradata;
      sps_pps_packet->size = codec_context_->extradata_size;
      WritePacket(0, sps_pps_packet);  // 使用时间戳0
      sps_pps_written_ = true;
      av_packet_free(&sps_pps_packet);
    }
  }

  // 3. 计算缩放尺寸和填充偏移
  const int src_w = (int)video_frame.Width();
  const int src_h = (int)video_frame.Height();
  const int dst_w = (int)output_format_.width;
  const int dst_h = (int)output_format_.height;

  double src_aspect = (double)src_w / src_h;
  double dst_aspect = (double)dst_w / dst_h;

  int scaled_w, scaled_h;
  if (src_aspect > dst_aspect) {
    scaled_w = dst_w;
    scaled_h = static_cast<int>(dst_w / src_aspect);
  } else {
    scaled_h = dst_h;
    scaled_w = static_cast<int>(dst_h * src_aspect);
  }
  // 确保宽高是偶数
  scaled_w = (scaled_w / 2) * 2;
  scaled_h = (scaled_h / 2) * 2;

  int pad_x = (dst_w - scaled_w) / 2;
  int pad_y = (dst_h - scaled_h) / 2;

  // 4. 检查是否需要重新初始化缩放器
  if (!sws_context_ || current_input_width_ != src_w ||
      current_input_height_ != src_h) {
    if (!InitializeScaler(src_w, src_h, scaled_w, scaled_h)) {
      return false;
    }
  }

  // 5. 准备填充帧 (黑色背景)
  if (av_frame_make_writable(sw_frame_.get()) < 0) {
    RTC_LOG(LS_ERROR) << "Frame not writable.";
    return false;
  }
  // Y plane
  memset(sw_frame_->data[0], 0, sw_frame_->linesize[0] * dst_h);
  // U and V planes (128 for neutral color)
  memset(sw_frame_->data[1], 128, sw_frame_->linesize[1] * dst_h / 2);
  memset(sw_frame_->data[2], 128, sw_frame_->linesize[2] * dst_h / 2);

  // 6. 准备源数据指针
  const uint8_t* const src_data[] = {video_frame.DataY(), video_frame.DataU(),
                                     video_frame.DataV()};
  const int src_linesize[] = {(int)video_frame.StrideY(),
                              (int)video_frame.StrideU(),
                              (int)video_frame.StrideV()};

  // 7. 准备目标数据指针（指向填充帧的中心区域）
  uint8_t* dst_data[] = {
      sw_frame_->data[0] + pad_y * sw_frame_->linesize[0] + pad_x,
      sw_frame_->data[1] + (pad_y / 2) * sw_frame_->linesize[1] + (pad_x / 2),
      sw_frame_->data[2] + (pad_y / 2) * sw_frame_->linesize[2] + (pad_x / 2)};
  const int dst_linesize[] = {sw_frame_->linesize[0], sw_frame_->linesize[1],
                              sw_frame_->linesize[2]};

  // 8. 执行缩放，直接将结果写入填充帧的中心
  sws_scale(sws_context_.get(), src_data, src_linesize, 0, src_h, dst_data,
            dst_linesize);

  // 9. 设置时间戳
  // 定义纳秒的时间基
  // AVRational ns_time_base = {1, 1000000000};
  // int64_t pts = av_rescale_q(video_frame.timestamp(), ns_time_base,
  //                            codec_context_->time_base);

  int64_t pts = video_frame.timestamp();

  // 检查是否使用硬件编码器
  if (hw_frames_ctx_) {
    // 硬件编码：将软件帧传输到硬件帧
    if (!hw_frame_) {
      hw_frame_.reset(av_frame_alloc());
      if (!hw_frame_) {
        RTC_LOG(LS_ERROR) << "Failed to allocate hardware frame.";
        return false;
      }
    }

    // 从硬件帧池获取缓冲区
    if (av_hwframe_get_buffer(hw_frames_ctx_.get(), hw_frame_.get(), 0) < 0) {
      RTC_LOG(LS_ERROR) << "Failed to get hardware frame buffer.";
      return false;
    }

    // 将软件帧传输到硬件帧
    if (av_hwframe_transfer_data(hw_frame_.get(), sw_frame_.get(), 0) < 0) {
      RTC_LOG(LS_ERROR) << "Failed to transfer data to hardware frame.";
      return false;
    }

    hw_frame_->pts = pts;
    return SendFrame(hw_frame_.get());
  } else {
    // 软件编码：直接使用软件帧
    sw_frame_->pts = pts;
    return SendFrame(sw_frame_.get());
  }
}

}  // namespace flutter_webrtc_plugin