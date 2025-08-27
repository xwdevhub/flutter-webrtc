#ifndef FLUTTER_WEBRTC_RECODING_TYPES_HXX
#define FLUTTER_WEBRTC_RECODING_TYPES_HXX

#include <mutex>
#include <queue>
#include <vector>

#include "rtc_window_recorder_factory.h"
#include "thread_queue.h"

#ifndef __STDC_CONSTANT_MACROS
#define __STDC_CONSTANT_MACROS
#endif

// 确保在 C++ 代码中正确链接 FFmpeg 的 C 库
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavcodec/packet.h>     // 添加此头文件以支持 AVPacket
#include <libavutil/audio_fifo.h>  // 添加音频 FIFO 支持
#include <libavutil/channel_layout.h>
#include <libavutil/common.h>
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/opt.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
}

namespace flutter_webrtc_plugin {

enum class RecordingState {
  kStopped,    // 停止状态
  kRecording,  // 录制中
  kPaused      // 暂停状态
};

struct AVPacketBlock {
  uint64_t ts;         // 时间戳
  uint32_t data_size;  // 数据长度
  uint8_t* data;       // 数据
};

struct AudioFormat {
  uint32_t sample_rate;      // 采样率 (Hz)
  uint16_t channels;         // 声道数
  uint16_t bits_per_sample;  // 每样本位数
  uint64_t bit_rate;         // 码率
};

struct VideoFormat {
  uint32_t width;
  uint32_t height;
  uint32_t fps;
  uint32_t bit_rate;
};

class AudioFrame {
 public:
  int64_t timestamp;
  std::vector<int16_t> data;
};

using RTCI420BufferPtr = libwebrtc::scoped_refptr<libwebrtc::RTCWindowRecorder::I420Buffer>;

class VideoFrame {
 public:
  VideoFrame(RTCI420BufferPtr i420_buffer, int64_t timestamp)
      : i420_buffer_(std::move(i420_buffer)), timestamp_(timestamp) {}

  int64_t timestamp() const { return timestamp_; }

  const RTCI420BufferPtr& i420_buffer() const { return i420_buffer_; }

  size_t Width() const { return i420_buffer_->width(); }

  size_t Height() const { return i420_buffer_->height(); }

  const uint8_t* DataY() const { return i420_buffer_->DataY(); }

  const uint8_t* DataU() const { return i420_buffer_->DataU(); }

  const uint8_t* DataV() const { return i420_buffer_->DataV(); }

  size_t StrideY() const { return i420_buffer_->StrideY(); }

  size_t StrideU() const { return i420_buffer_->StrideU(); }

  size_t StrideV() const { return i420_buffer_->StrideV(); }

 private:
  RTCI420BufferPtr i420_buffer_;
  int64_t timestamp_;
};

// 自定义 Deleter 用于 unique_ptr
struct AVCodecContextDeleter {
  void operator()(AVCodecContext* ptr) const { avcodec_free_context(&ptr); }
};
struct AVFrameDeleter {
  void operator()(AVFrame* ptr) const { av_frame_free(&ptr); }
};
struct SwrContextDeleter {
  void operator()(SwrContext* ptr) const { swr_free(&ptr); }
};
struct AVAudioFifoDeleter {
  void operator()(AVAudioFifo* ptr) const { av_audio_fifo_free(ptr); }
};
struct SwsContextDeleter {
  void operator()(SwsContext* ptr) const { sws_freeContext(ptr); }
};
}  // namespace flutter_webrtc_plugin

#endif