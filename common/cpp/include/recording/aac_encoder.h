#ifndef FLUTTER_WEBRTC_AAC_ENCODER_HXX
#define FLUTTER_WEBRTC_AAC_ENCODER_HXX

#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "types.h"

namespace flutter_webrtc_plugin {

using AVCodecContextPtr =
    std::unique_ptr<AVCodecContext, AVCodecContextDeleter>;
using AVFramePtr = std::unique_ptr<AVFrame, AVFrameDeleter>;
using SwrContextPtr = std::unique_ptr<SwrContext, SwrContextDeleter>;
using AVAudioFifoPtr = std::unique_ptr<AVAudioFifo, AVAudioFifoDeleter>;

class AACEncoder {
 public:
  AACEncoder(const AudioFormat& format, std::ofstream& file);
  ~AACEncoder();

  bool Encode(int64_t ts, const std::vector<int16_t>& pcm_data);

 private:
  bool Initialize();
  bool InitializeFrame(AVFramePtr& frame,
                       AVSampleFormat sample_fmt,
                       int sample_rate,
                       int nb_samples);
  void WritePacket(int64_t ts, const AVPacket* packet);
  bool SendFrame(const AVFrame* frame);
  bool ProcessFifo(int64_t ts);

  const AudioFormat& output_format_;
  std::ofstream& output_file_;

  AVCodecContextPtr codec_context_;
  SwrContextPtr swr_context_;
  AVAudioFifoPtr audio_fifo_;

  AVFramePtr resampled_frame_;  // Frame in the format the encoder expects

  bool asc_written_ = false;
};

}  // namespace flutter_webrtc_plugin

#endif
