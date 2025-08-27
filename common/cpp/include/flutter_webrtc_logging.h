#ifndef FLUTTER_WEBRTC_LOGGING_HXX
#define FLUTTER_WEBRTC_LOGGING_HXX

#include <chrono>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <sstream>
#include <string>

// 日志级别常量
#define LS_DEBUG flutter_webrtc_plugin::LogLevel::kDebug
#define LS_INFO flutter_webrtc_plugin::LogLevel::kInfo
#define LS_WARNING flutter_webrtc_plugin::LogLevel::kWarning
#define LS_ERROR flutter_webrtc_plugin::LogLevel::kError

namespace flutter_webrtc_plugin {

enum class LogLevel { kDebug, kInfo, kWarning, kError };

#ifdef NDEBUG
// 在 Release 模式下使用的空日志流，不输出任何内容
class NullLogStream {
 public:
  NullLogStream() {}
  template <typename T>
  inline NullLogStream& operator<<(const T& value) {
    return *this;
  }
};
static NullLogStream null_stream;
#endif

// 日志流类，支持 << 操作符，直接处理输出以简化设计
class LogStream {
 public:
  LogStream(LogLevel level) : level_(level), timestamp_(GetCurrentTime()) {}
  ~LogStream() {
    std::ostringstream final_stream;
    final_stream << "[" << timestamp_ << "] [" << LevelToString(level_) << "] " << stream_.str()
                 << std::endl;
    WriteLog(final_stream.str());
  }

  template <typename T>
  LogStream& operator<<(const T& value) {
    stream_ << value;
    return *this;
  }

 private:
  static void WriteLog(const std::string& message) {
    static std::mutex mutex;
    std::lock_guard<std::mutex> lock(mutex);
    std::cout << message;
  }

  static std::string LevelToString(LogLevel level) {
    switch (level) {
      case LogLevel::kDebug:
        return "DEBUG";
      case LogLevel::kInfo:
        return "INFO";
      case LogLevel::kWarning:
        return "WARNING";
      case LogLevel::kError:
        return "ERROR";
      default:
        return "UNKNOWN";
    }
  }

  static std::string GetCurrentTime() {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);

    std::tm tm_buf;
#ifdef _WIN32
    localtime_s(&tm_buf, &time);
#else
    localtime_r(&time, &tm_buf);
#endif

    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;

    std::ostringstream oss;
    oss << std::put_time(&tm_buf, "%Y-%m-%d %H:%M:%S") << "." << std::setfill('0') << std::setw(3)
        << ms.count();
    return oss.str();
  }

  LogLevel level_;
  std::string timestamp_;
  std::ostringstream stream_;
};

}  // namespace flutter_webrtc_plugin

// RTC_LOG 宏，支持流式日志，自动包含文件名和行号
#ifndef NDEBUG
#define RTC_LOG(level)                    \
  flutter_webrtc_plugin::LogStream(level) \
      << "(" << std::filesystem::path(__FILE__).filename().string() << ":" << __LINE__ << "): "
#else
#define RTC_LOG(level) flutter_webrtc_plugin::null_stream
#endif

#endif  // FLUTTER_WEBRTC_LOGGING_HXX
