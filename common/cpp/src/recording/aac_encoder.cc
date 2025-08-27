#include "aac_encoder.h"
#include "flutter_webrtc_logging.h"

namespace flutter_webrtc_plugin {

AACEncoder::AACEncoder(const AudioFormat& format, std::ofstream& file)
    : output_format_(format), output_file_(file) {
  Initialize();
}

AACEncoder::~AACEncoder() {
  // 刷新编码器和FIFO中剩余的帧
  if (codec_context_ && audio_fifo_) {
    ProcessFifo(0);      // 刷新FIFO
    SendFrame(nullptr);  // 发送nullptr以刷新编码器
  }
}

bool AACEncoder::Initialize() {
  // 添加调试日志验证AudioFormat参数
  RTC_LOG(LS_DEBUG) << "AACEncoder::Initialize() - AudioFormat details:";
  RTC_LOG(LS_DEBUG) << "  Sample rate: " << output_format_.sample_rate;
  RTC_LOG(LS_DEBUG) << "  Channels: " << output_format_.channels;
  RTC_LOG(LS_DEBUG) << "  Bits per sample: " << output_format_.bits_per_sample;
  RTC_LOG(LS_DEBUG) << "  Bit rate: " << output_format_.bit_rate;

  // 验证关键参数有效性
  if (output_format_.channels == 0) {
    RTC_LOG(LS_ERROR) << "Invalid channels count: " << output_format_.channels;
    return false;
  }

  if (output_format_.bit_rate == 0) {
    RTC_LOG(LS_WARNING)
        << "Bit rate is 0, setting default value based on channels";
    // 设置默认比特率：单声道64kbps，立体声128kbps
    const_cast<AudioFormat&>(output_format_).bit_rate =
        (output_format_.channels == 1) ? 64000 : 128000;
  }

  const AVCodec* codec = avcodec_find_encoder_by_name("aac");
  if (!codec) {
    RTC_LOG(LS_ERROR) << "AAC encoder not found.";
    return false;
  }

  codec_context_.reset(avcodec_alloc_context3(codec));
  if (!codec_context_) {
    RTC_LOG(LS_ERROR) << "Failed to allocate AAC codec context.";
    return false;
  }

  codec_context_->bit_rate = output_format_.bit_rate;
  codec_context_->sample_rate = output_format_.sample_rate;

  // 关键：设置时间基为采样率，这样PTS单位就是单个样本
  codec_context_->time_base = {1, static_cast<int>(output_format_.sample_rate)};

  // 获取编码器支持的采样格式，替换已弃用的 codec->sample_fmts
  AVSampleFormat supported_formats[16];  // 足够保存支持的格式
  int num_supported_formats = 0;

  RTC_LOG(LS_DEBUG) << "Querying supported sample formats...";
  int query_result = avcodec_get_supported_config(
      codec_context_.get(), codec, AVCodecConfig::AV_CODEC_CONFIG_SAMPLE_FORMAT,
      0, (const void**)&supported_formats, &num_supported_formats);

  if (query_result >= 0 && num_supported_formats > 0) {
    RTC_LOG(LS_DEBUG) << "  Supported sample formats: "
                      << num_supported_formats;
    bool found_valid_format = false;

    for (int i = 0; i < num_supported_formats; ++i) {
      AVSampleFormat format = supported_formats[i];
      RTC_LOG(LS_DEBUG) << "    Format " << i << ": " << format;

      // 验证格式有效性：AVSampleFormat应该是小的正整数
      if (format >= 0 && format < AV_SAMPLE_FMT_NB) {
        // 安全地获取格式名称
        const char* format_name = av_get_sample_fmt_name(format);
        const char* safe_name = format_name ? format_name : "unknown";
        RTC_LOG(LS_DEBUG) << "    Valid format " << format << " (" << safe_name
                          << ")";

        if (!found_valid_format) {
          codec_context_->sample_fmt = format;
          found_valid_format = true;
          RTC_LOG(LS_DEBUG)
              << "  Selected valid format: " << codec_context_->sample_fmt;
        }
      } else {
        RTC_LOG(LS_WARNING) << "  Invalid format detected: " << format;
      }
    }

    if (!found_valid_format) {
      RTC_LOG(LS_WARNING) << "No valid sample formats found, using fallback";
      codec_context_->sample_fmt = AV_SAMPLE_FMT_FLTP;
    }
  } else {
    // 退回到默认格式
    RTC_LOG(LS_DEBUG) << "Query failed (result: " << query_result
                      << "), using default format AV_SAMPLE_FMT_FLTP";
    codec_context_->sample_fmt = AV_SAMPLE_FMT_FLTP;
  }

  // 安全地获取最终格式名称
  const char* final_format_name =
      av_get_sample_fmt_name(codec_context_->sample_fmt);
  const char* safe_final_name =
      final_format_name ? final_format_name : "unknown";
  RTC_LOG(LS_DEBUG) << "Final sample format: " << codec_context_->sample_fmt
                    << " (" << safe_final_name << ")";

  // 根据输出格式设置声道布局
  if (output_format_.channels == 1) {
    av_channel_layout_from_mask(&codec_context_->ch_layout, AV_CH_LAYOUT_MONO);
  } else if (output_format_.channels == 2) {
    av_channel_layout_from_mask(&codec_context_->ch_layout,
                                AV_CH_LAYOUT_STEREO);
  } else {
    RTC_LOG(LS_ERROR) << "Unsupported number of channels: "
                      << output_format_.channels;
    return false;
  }

  // FFmpeg的AAC编码器需要全局头文件来存储ASC
  codec_context_->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

  RTC_LOG(LS_DEBUG) << "Opening AAC codec with parameters:";
  RTC_LOG(LS_DEBUG) << "  Codec: aac";
  RTC_LOG(LS_DEBUG) << "  Sample rate: " << codec_context_->sample_rate;
  RTC_LOG(LS_DEBUG) << "  Bit rate: " << codec_context_->bit_rate;
  RTC_LOG(LS_DEBUG) << "  Channels: " << codec_context_->ch_layout.nb_channels;
  RTC_LOG(LS_DEBUG) << "  Sample format: " << codec_context_->sample_fmt;
  RTC_LOG(LS_DEBUG) << "  Time base: " << codec_context_->time_base.num << "/"
                    << codec_context_->time_base.den;

  int ret = avcodec_open2(codec_context_.get(), codec, nullptr);
  if (ret < 0) {
    char error_msg[AV_ERROR_MAX_STRING_SIZE];
    av_strerror(ret, error_msg, sizeof(error_msg));
    RTC_LOG(LS_ERROR) << "Failed to open AAC codec. Error details:";
    RTC_LOG(LS_ERROR) << "  Error message: " << error_msg;
    RTC_LOG(LS_ERROR) << "  Sample rate: " << codec_context_->sample_rate;
    RTC_LOG(LS_ERROR) << "  Bit rate: " << codec_context_->bit_rate;
    RTC_LOG(LS_ERROR) << "  Sample format: " << codec_context_->sample_fmt;
    RTC_LOG(LS_ERROR) << "  Channels: "
                      << codec_context_->ch_layout.nb_channels;
    RTC_LOG(LS_ERROR) << "  Time base: " << codec_context_->time_base.num << "/"
                      << codec_context_->time_base.den;
    return false;
  }

  RTC_LOG(LS_DEBUG) << "Initializing resampler...";
  // 初始化重采样器
  swr_context_.reset(swr_alloc());
  if (!swr_context_) {
    RTC_LOG(LS_ERROR) << "Failed to allocate resampler context.";
    return false;
  }

  AVChannelLayout input_ch_layout;
  av_channel_layout_from_mask(&input_ch_layout, AV_CH_LAYOUT_STEREO);

  SwrContext* new_context = nullptr;
  swr_alloc_set_opts2(&new_context, &codec_context_->ch_layout,
                      codec_context_->sample_fmt, codec_context_->sample_rate,
                      &input_ch_layout, AV_SAMPLE_FMT_S16,
                      output_format_.sample_rate, 0, nullptr);
  swr_context_.reset(new_context);
  if (swr_init(swr_context_.get()) < 0) {
    RTC_LOG(LS_ERROR) << "Failed to initialize resampler.";
    return false;
  }

  RTC_LOG(LS_DEBUG) << "Initializing audio FIFO...";
  // 初始化FIFO
  audio_fifo_.reset(av_audio_fifo_alloc(codec_context_->sample_fmt,
                                        output_format_.channels, 1));
  if (!audio_fifo_) {
    RTC_LOG(LS_ERROR) << "Failed to allocate audio FIFO.";
    return false;
  }

  RTC_LOG(LS_DEBUG) << "Initializing resampled frame...";
  // 初始化用于重采样的帧
  if (!InitializeFrame(resampled_frame_, codec_context_->sample_fmt,
                       codec_context_->sample_rate,
                       codec_context_->frame_size)) {
    return false;
  }

  if (!asc_written_ && codec_context_->extradata_size > 0 &&
      output_file_.tellp() == 0) {
    AVPacket* asc_packet = av_packet_alloc();
    asc_packet->data = codec_context_->extradata;
    asc_packet->size = codec_context_->extradata_size;
    WritePacket(0, asc_packet);  // 时间戳为0
    asc_written_ = true;
    av_packet_free(&asc_packet);
  }

  RTC_LOG(LS_DEBUG) << "AAC encoder initialized successfully!";
  return true;
}

bool AACEncoder::InitializeFrame(AVFramePtr& frame,
                                 AVSampleFormat sample_fmt,
                                 int sample_rate,
                                 int nb_samples) {
  frame.reset(av_frame_alloc());
  if (!frame) {
    RTC_LOG(LS_ERROR) << "Failed to allocate AVFrame.";
    return false;
  }
  frame->format = sample_fmt;
  frame->sample_rate = sample_rate;
  frame->nb_samples = nb_samples;
  av_channel_layout_from_mask(&frame->ch_layout, AV_CH_LAYOUT_STEREO);

  if (av_frame_get_buffer(frame.get(), 0) < 0) {
    RTC_LOG(LS_ERROR) << "Failed to get frame buffer.";
    return false;
  }
  return true;
}

void AACEncoder::WritePacket(int64_t ts, const AVPacket* packet) {
  uint32_t data_size = packet->size;
  output_file_.write(reinterpret_cast<const char*>(&ts), sizeof(ts));
  output_file_.write(reinterpret_cast<const char*>(&data_size),
                     sizeof(data_size));
  output_file_.write(reinterpret_cast<const char*>(packet->data), packet->size);
}

bool AACEncoder::SendFrame(const AVFrame* frame) {
  int ret = avcodec_send_frame(codec_context_.get(), frame);
  if (ret < 0) {
    if (ret != AVERROR_EOF) {
      RTC_LOG(LS_ERROR) << "Error sending frame to audio encoder.";
    }
    return false;
  }

  AVPacket* packet = av_packet_alloc();
  while (ret >= 0) {
    ret = avcodec_receive_packet(codec_context_.get(), packet);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
      break;
    } else if (ret < 0) {
      RTC_LOG(LS_ERROR) << "Error receiving packet from audio encoder.";
      av_packet_free(&packet);
      return false;
    }

    // RTC_LOG(LS_DEBUG) << "Audio WritePacket pts=" << packet->pts;
    WritePacket(packet->pts, packet);
  }
  av_packet_free(&packet);
  return true;
}

bool AACEncoder::ProcessFifo(int64_t ts) {
  const int frame_size = codec_context_->frame_size;
  while (av_audio_fifo_size(audio_fifo_.get()) >= frame_size) {
    if (av_frame_make_writable(resampled_frame_.get()) < 0) {
      return false;
    }

    if (av_audio_fifo_read(audio_fifo_.get(), (void**)resampled_frame_->data,
                           frame_size) < frame_size) {
      return false;
    }

    // AVRational ns_time_base = {1, 1000000000};
    // resampled_frame_->pts =
    //     av_rescale_q(ts, ns_time_base, codec_context_->time_base);
    resampled_frame_->pts = ts;

    if (!SendFrame(resampled_frame_.get())) {
      return false;
    }
  }
  return true;
}

bool AACEncoder::Encode(int64_t ts, const std::vector<int16_t>& pcm_data) {
  if (!codec_context_) {
    if (!Initialize()) {
      return false;
    }
  }

  // 重采样输入数据
  uint8_t** resampled_data_ptr = nullptr;
  int resampled_linesize;
  int max_resampled_samples = swr_get_out_samples(
      swr_context_.get(),
      static_cast<int>(pcm_data.size() / output_format_.channels));

  av_samples_alloc_array_and_samples(
      &resampled_data_ptr, &resampled_linesize, output_format_.channels,
      max_resampled_samples, codec_context_->sample_fmt, 0);

  // 正确地将int16_t数据转换为uint8_t指针数组
  const uint8_t* input_data_ptr =
      reinterpret_cast<const uint8_t*>(pcm_data.data());
  int actual_resampled_samples =
      swr_convert(swr_context_.get(), resampled_data_ptr, max_resampled_samples,
                  &input_data_ptr,  // 传递指针的地址
                  static_cast<int>(pcm_data.size() / output_format_.channels));

  if (actual_resampled_samples < 0) {
    RTC_LOG(LS_ERROR) << "Error during resampling";
    av_freep(&resampled_data_ptr[0]);
    return false;
  }

  // 将重采样后的数据写入FIFO
  if (av_audio_fifo_write(audio_fifo_.get(), (void**)resampled_data_ptr,
                          actual_resampled_samples) <
      actual_resampled_samples) {
    RTC_LOG(LS_ERROR) << "Failed to write to audio FIFO.";
    av_freep(&resampled_data_ptr[0]);
    return false;
  }
  av_freep(&resampled_data_ptr[0]);

  // 从FIFO中读取并编码完整的帧
  return ProcessFifo(ts);
}

}  // namespace flutter_webrtc_plugin
