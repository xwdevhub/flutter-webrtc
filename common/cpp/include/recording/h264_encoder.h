#ifndef FLUTTER_WEBRTC_H264_ENCODER_HXX
#define FLUTTER_WEBRTC_H264_ENCODER_HXX

#include <cstdint>
#include <fstream>
#include <memory>
#include <vector>

#include "types.h"

namespace flutter_webrtc_plugin {

using AVCodecContextPtr =
    std::unique_ptr<AVCodecContext, AVCodecContextDeleter>;
using AVFramePtr = std::unique_ptr<AVFrame, AVFrameDeleter>;
using SwsContextPtr = std::unique_ptr<SwsContext, SwsContextDeleter>;
struct AVBufferRefDeleter {
  void operator()(AVBufferRef* ptr) const { av_buffer_unref(&ptr); }
};
using AVBufferRefPtr = std::unique_ptr<AVBufferRef, AVBufferRefDeleter>;

// H.264 编码器封装类
class H264Encoder {
 public:
  H264Encoder(const VideoFormat& format, std::ofstream& file);
  ~H264Encoder();

  // 编码一帧视频
  bool Encode(const VideoFrame& video_frame);

 private:
  bool InitializeEncoder(int width, int height);
  bool InitializeScaler(int src_w, int src_h, int dst_w, int dst_h);
  void WritePacket(uint64_t ts, const AVPacket* packet);
  bool SendFrame(const AVFrame* frame);

  const VideoFormat& output_format_;
  std::ofstream& output_file_;

  AVCodecContextPtr codec_context_;
  AVFramePtr sw_frame_;  // 用于缩放和填充的软件帧
  AVFramePtr hw_frame_;  // 用于硬件编码的硬件帧
  SwsContextPtr sws_context_;

  AVBufferRefPtr hw_device_ctx_;  // 硬件设备上下文
  AVBufferRefPtr hw_frames_ctx_;  // 硬件帧上下文

  int current_input_width_ = 0;
  int current_input_height_ = 0;
  bool sps_pps_written_ = false;
};

}  // namespace flutter_webrtc_plugin

#endif