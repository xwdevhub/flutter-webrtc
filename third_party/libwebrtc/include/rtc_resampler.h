/*
 *  Copyright (c) 2024 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#ifndef LIB_WEBRTC_RTC_RESAMPLER_H_
#define LIB_WEBRTC_RTC_RESAMPLER_H_

#include "base/refcount.h"
#include "base/scoped_ref_ptr.h"
#include "rtc_types.h"

namespace libwebrtc {

class RTCResampler : public RefCountInterface {
 public:
  LIB_WEBRTC_API static scoped_refptr<RTCResampler> Create();

  // Initialize resampler with sample rates and channel count
  virtual int InitializeIfNeeded(int src_sample_rate_hz,
                                 int dst_sample_rate_hz,
                                 size_t num_channels) = 0;

  // Perform the resampling
  virtual int Resample(const int16_t* src,
                       size_t src_length,
                       int16_t* dst,
                       size_t dst_capacity) = 0;

  // Remix and resample audio data for DLL export
  // Replaces AudioFrame parameters with POD types
  virtual int RemixAndResample(
      const int16_t* src_data,          // Source audio data
      size_t src_samples_per_channel,   // Samples per channel in source
      size_t src_num_channels,          // Number of channels in source
      int src_sample_rate_hz,           // Source sample rate in Hz
      uint32_t src_timestamp,           // RTP timestamp of first sample
      int dst_sample_rate_hz,           // Destination sample rate in Hz
      size_t dst_num_channels,          // Number of channels in destination
      int16_t* dst_data,                // Destination audio data buffer
      size_t dst_capacity,              // Capacity of destination buffer
      size_t* dst_samples_per_channel,  // Output: samples per channel in result
      uint32_t* dst_timestamp           // Output: timestamp of result
      ) = 0;

 protected:
  ~RTCResampler() override = default;
};

}  // namespace libwebrtc

#endif  // LIB_WEBRTC_RTC_RESAMPLER_H_