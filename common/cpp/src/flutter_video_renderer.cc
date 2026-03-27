#include "flutter_video_renderer.h"

// ---------------------------------------------------------------------------
// Perf instrumentation — enabled only when FLUTTER_WEBRTC_RENDERER_PERF is
// defined (e.g. in your CMakeLists: add_compile_definitions(FLUTTER_WEBRTC_RENDERER_PERF)).
// ---------------------------------------------------------------------------
#if defined(FLUTTER_WEBRTC_RENDERER_PERF)
#include <chrono>
#include <cstdio>
namespace {
inline int64_t NowMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(
             steady_clock::now().time_since_epoch())
      .count();
}

inline int64_t CurrentNtpMs() {
  using namespace std::chrono;
  constexpr int64_t kNtpJan1970Millisecs = 2208988800LL * 1000LL;
  const int64_t unix_ms =
      duration_cast<milliseconds>(system_clock::now().time_since_epoch())
          .count();
  return unix_ms + kNtpJan1970Millisecs;
}
}  // namespace
#define RENDERER_PERF_LOG(msg) \
  do { fprintf(stderr, "[RendererPerf] " msg "\n"); } while (0)
#define RENDERER_PERF_LOGF(...) \
  do { fprintf(stderr, "[RendererPerf] " __VA_ARGS__); fprintf(stderr, "\n"); } while (0)
#else
#define RENDERER_PERF_LOG(msg)    do {} while (0)
#define RENDERER_PERF_LOGF(...)   do {} while (0)
inline int64_t NowMs() { return 0; }
inline int64_t CurrentNtpMs() { return 0; }
#endif

namespace flutter_webrtc_plugin {

FlutterVideoRenderer::~FlutterVideoRenderer() {}

void FlutterVideoRenderer::initialize(
    TextureRegistrar* registrar,
    BinaryMessenger* messenger,
    std::unique_ptr<flutter::TextureVariant> texture,
    int64_t trxture_id) {
  registrar_ = registrar;
  texture_ = std::move(texture);
  texture_id_ = trxture_id;
  std::string channel_name =
      "FlutterWebRTC/Texture" + std::to_string(texture_id_);
  event_channel_ = EventChannelProxy::Create(messenger, channel_name);
}

const FlutterDesktopPixelBuffer* FlutterVideoRenderer::CopyPixelBuffer(
    size_t width,
    size_t height) const {
#if defined(FLUTTER_WEBRTC_RENDERER_PERF)
  const int64_t lock_start_ms = NowMs();
#endif
  mutex_.lock();
#if defined(FLUTTER_WEBRTC_RENDERER_PERF)
  const int64_t mutex_wait_ms = NowMs() - lock_start_ms;
#endif
  if (pixel_buffer_.get() && frame_.get()) {
    if (pixel_buffer_->width != frame_->width() ||
        pixel_buffer_->height != frame_->height()) {
      size_t buffer_size =
          (size_t(frame_->width()) * size_t(frame_->height())) * (32 >> 3);
      rgb_buffer_.reset(new uint8_t[buffer_size]);
      pixel_buffer_->width = frame_->width();
      pixel_buffer_->height = frame_->height();
    }

#if defined(FLUTTER_WEBRTC_RENDERER_PERF)
    const int64_t convert_start_ms = NowMs();
    RENDERER_PERF_LOGF("CopyPixelBuffer start tex=%lld src=%dx%d req=%zux%zu mutex_wait_ms=%lld",
        texture_id_, (int)pixel_buffer_->width, (int)pixel_buffer_->height,
        width, height, mutex_wait_ms);
#endif

    frame_->ConvertToARGB(RTCVideoFrame::Type::kABGR, rgb_buffer_.get(), 0,
                          static_cast<int>(pixel_buffer_->width),
                          static_cast<int>(pixel_buffer_->height));

#if defined(FLUTTER_WEBRTC_RENDERER_PERF)
    const int64_t copy_pixel_buffer_ms = NowMs() - convert_start_ms;
    RENDERER_PERF_LOGF("CopyPixelBuffer done tex=%lld copy_ms=%lld",
        texture_id_, copy_pixel_buffer_ms);
#endif

    pixel_buffer_->buffer = rgb_buffer_.get();
    mutex_.unlock();
    return pixel_buffer_.get();
  }
  mutex_.unlock();
  return nullptr;
}

void FlutterVideoRenderer::OnFrame(scoped_refptr<RTCVideoFrame> frame) {
#if defined(FLUTTER_WEBRTC_RENDERER_PERF)
  int64_t approx_e2e_ms = -1;
  if (frame->ntp_time_ms() > 0) {
    const int64_t now_ntp_ms = CurrentNtpMs();
    if (now_ntp_ms >= frame->ntp_time_ms()) {
      approx_e2e_ms = now_ntp_ms - frame->ntp_time_ms();
      perf_e2e_sum_ms_ += approx_e2e_ms;
      ++perf_e2e_frame_count_;
    }
  }

  if (approx_e2e_ms >= 0) {
    RENDERER_PERF_LOGF("OnFrame tex=%lld size=%dx%d rotation=%d approx_e2e_ms=%lld",
        texture_id_, frame->width(), frame->height(), (int)frame->rotation(),
        approx_e2e_ms);
    if (perf_e2e_frame_count_ >= 30) {
      RENDERER_PERF_LOGF(
          "OnFrame avg tex=%lld avg_e2e_ms=%lld frames=%lld",
          texture_id_, perf_e2e_sum_ms_ / perf_e2e_frame_count_,
          perf_e2e_frame_count_);
      perf_e2e_sum_ms_ = 0;
      perf_e2e_frame_count_ = 0;
    }
  } else {
    RENDERER_PERF_LOGF("OnFrame tex=%lld size=%dx%d rotation=%d",
        texture_id_, frame->width(), frame->height(), (int)frame->rotation());
  }
#endif
  if (!first_frame_rendered) {
    EncodableMap params;
    params[EncodableValue("event")] = "didFirstFrameRendered";
    params[EncodableValue("id")] = EncodableValue(texture_id_);
    event_channel_->Success(EncodableValue(params));
    pixel_buffer_.reset(new FlutterDesktopPixelBuffer());
    pixel_buffer_->width = 0;
    pixel_buffer_->height = 0;
    first_frame_rendered = true;
  }
  if (rotation_ != frame->rotation()) {
    EncodableMap params;
    params[EncodableValue("event")] = "didTextureChangeRotation";
    params[EncodableValue("id")] = EncodableValue(texture_id_);
    params[EncodableValue("rotation")] =
        EncodableValue((int32_t)frame->rotation());
    event_channel_->Success(EncodableValue(params));
    rotation_ = frame->rotation();
  }
  if (last_frame_size_.width != frame->width() ||
      last_frame_size_.height != frame->height()) {
    EncodableMap params;
    params[EncodableValue("event")] = "didTextureChangeVideoSize";
    params[EncodableValue("id")] = EncodableValue(texture_id_);
    params[EncodableValue("width")] = EncodableValue((int32_t)frame->width());
    params[EncodableValue("height")] = EncodableValue((int32_t)frame->height());
    event_channel_->Success(EncodableValue(params));

    last_frame_size_ = {(size_t)frame->width(), (size_t)frame->height()};
  }
  mutex_.lock();
  frame_ = frame;
  mutex_.unlock();
  registrar_->MarkTextureFrameAvailable(texture_id_);
}

void FlutterVideoRenderer::SetVideoTrack(scoped_refptr<RTCVideoTrack> track) {
  if (track_ != track) {
    if (track_)
      track_->RemoveRenderer(this);
    track_ = track;
    last_frame_size_ = {0, 0};
    first_frame_rendered = false;
    if (track_)
      track_->AddRenderer(this);
  }
}

bool FlutterVideoRenderer::CheckMediaStream(std::string mediaId) {
  if (0 == mediaId.size() || 0 == media_stream_id.size()) {
    return false;
  }
  return mediaId == media_stream_id;
}

bool FlutterVideoRenderer::CheckVideoTrack(std::string mediaId) {
  if (0 == mediaId.size() || !track_) {
    return false;
  }
  return mediaId == track_->id().std_string();
}

FlutterVideoRendererManager::FlutterVideoRendererManager(
    FlutterWebRTCBase* base)
    : base_(base) {}

void FlutterVideoRendererManager::CreateVideoRendererTexture(
    std::unique_ptr<MethodResultProxy> result) {
  auto texture = new RefCountedObject<FlutterVideoRenderer>();
  auto textureVariant =
      std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
          [texture](size_t width,
                    size_t height) -> const FlutterDesktopPixelBuffer* {
            return texture->CopyPixelBuffer(width, height);
          }));

  auto texture_id = base_->textures_->RegisterTexture(textureVariant.get());
  texture->initialize(base_->textures_, base_->messenger_,
                      std::move(textureVariant), texture_id);
  renderers_[texture_id] = texture;
  EncodableMap params;
  params[EncodableValue("textureId")] = EncodableValue(texture_id);
  result->Success(EncodableValue(params));
}

void FlutterVideoRendererManager::VideoRendererSetSrcObject(
    int64_t texture_id,
    const std::string& stream_id,
    const std::string& owner_tag,
    const std::string& track_id) {
  scoped_refptr<RTCMediaStream> stream =
      base_->MediaStreamForId(stream_id, owner_tag);

  auto it = renderers_.find(texture_id);
  if (it != renderers_.end()) {
    FlutterVideoRenderer* renderer = it->second.get();
    if (stream.get()) {
      auto video_tracks = stream->video_tracks();
      if (video_tracks.size() > 0) {
        if (track_id == std::string()) {
          renderer->SetVideoTrack(video_tracks[0]);
        } else {
          for (auto track : video_tracks.std_vector()) {
            if (track->id().std_string() == track_id) {
              renderer->SetVideoTrack(track);
              break;
            }
          }
        }
        renderer->media_stream_id = stream_id;
      }
    } else {
      renderer->SetVideoTrack(nullptr);
    }
  }
}

void FlutterVideoRendererManager::VideoRendererDispose(
    int64_t texture_id,
    std::unique_ptr<MethodResultProxy> result) {
  auto it = renderers_.find(texture_id);
  if (it != renderers_.end()) {
    it->second->SetVideoTrack(nullptr);
#if defined(_WINDOWS)
    base_->textures_->UnregisterTexture(texture_id,
                                        [&, it] { renderers_.erase(it); });
#else
    base_->textures_->UnregisterTexture(texture_id);
    renderers_.erase(it);
#endif
    result->Success();
    return;
  }
  result->Error("VideoRendererDisposeFailed",
                "VideoRendererDispose() texture not found!");
}

}  // namespace flutter_webrtc_plugin
