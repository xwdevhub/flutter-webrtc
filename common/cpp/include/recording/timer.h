#ifndef FLUTTER_WEBRTC_TIMER_HXX
#define FLUTTER_WEBRTC_TIMER_HXX

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>

namespace flutter_webrtc_plugin {

class Timer {
 public:
  Timer() : active_(false), paused_(false) {}

  ~Timer() { Stop(); }

  Timer(const Timer&) = delete;
  Timer& operator=(const Timer&) = delete;
  Timer(Timer&&) = default;
  Timer& operator=(Timer&&) = default;

  // 开启定时器
  template <typename Func>
  void Start(int interval_ms, Func&& func) {
    std::unique_lock<std::mutex> lock(mutex_);
    if (active_) {
      return;  // 已经在运行
    }

    active_ = true;
    paused_ = false;
    next_time_ = std::chrono::steady_clock::now();

    thread_ = std::thread([this, interval_ms, f = std::forward<Func>(func)]() {
      std::chrono::steady_clock::time_point next_time;
      while (active_) {
        // --- 暂停逻辑 ---
        {
          std::unique_lock<std::mutex> lock(mutex_);
          // wait会阻塞线程，直到谓词(lambda)返回true
          // 如果paused_为true，线程将在此等待
          cv_.wait(lock, [this] { return !paused_ || !active_; });

          // 首先，计算出理论上的下一次执行时间
          next_time_ += std::chrono::milliseconds(interval_ms);
          next_time = next_time_;
        }

        // 如果是因stop()被唤醒，则直接退出
        if (!active_) {
          break;
        }

        // // 检查理论时间点是否已经过时。
        // // 如果是，说明发生了长时间暂停，我们需要重置时间基准以避免“回调风暴”。
        // auto now = std::chrono::steady_clock::now();
        // if (next_time < now) {
        //   next_time = now;
        // }

        // 混合等待
        // std::this_thread::sleep_until(next_time - std::chrono::microseconds(1));
        // // 在最后1ms内进行忙等待，以达到精确时间
        // while (std::chrono::steady_clock::now() < next_time) {
        //   // 可以选择性地加入 std::this_thread::yield() 来提示调度器
        //   // 这可能会稍微降低CPU使用率，但也会略微影响精度
        //   std::this_thread::yield();
        // }

        std::this_thread::sleep_until(next_time);

        // 再次检查active_，避免在等待期间被Stop
        if (!active_) {
          break;
        }

        f();  // 执行任务
      }
    });
  }

  // 关闭定时器
  void Stop() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!active_) {
        return;
      }
      active_ = false;
      paused_ = false;  // 确保线程不会因 paused 而继续等待
    }
    cv_.notify_one();
    if (thread_.joinable()) {
      thread_.join();
    }
  }

  // 暂停定时器
  void Pause() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (active_) {
      paused_ = true;
    }
  }

  // 继续定时器
  void Resume() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (active_) {
        paused_ = false;
        next_time_ = std::chrono::steady_clock::now();
      }
    }
    // 通知等待的线程，条件已改变
    cv_.notify_one();
  }

 private:
  std::atomic<bool> active_;  // active_ 仍然可以是 atomic，因为它在循环中被无锁读取
  bool paused_;               // paused_ 由 mutex 保护
  std::chrono::steady_clock::time_point next_time_;
  std::thread thread_;
  std::mutex mutex_;
  std::condition_variable cv_;
};

}  // namespace flutter_webrtc_plugin

#endif