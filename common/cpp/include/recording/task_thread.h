#ifndef FLUTTER_WEBRTC_TASK_THREAD_H
#define FLUTTER_WEBRTC_TASK_THREAD_H

#include <atomic>
#include <functional>
#include <future>
#include <memory>
#include <stdexcept>
#include <thread>
#include <type_traits>

#include "thread_queue.h"

namespace flutter_webrtc_plugin {

class TaskThread {
  class ITask {
   public:
    virtual ~ITask() = default;
    virtual void Execute() = 0;
  };

  template <typename F>
  class Task : public ITask {
   public:
    // 构造函数使用完美转发，接收任意类型的可调用对象
    // 并将其移动到成员变量 f_ 中
    explicit Task(F&& f) : f_(std::forward<F>(f)) {}

    // 重写 Execute 方法，调用存储的 lambda
    void Execute() override { f_(); }

   private:
    F f_;  // 存储具体的 lambda
  };

 public:
  explicit TaskThread(std::string name);
  ~TaskThread();

  // 禁止拷贝和赋值
  TaskThread(const TaskThread&) = delete;
  TaskThread& operator=(const TaskThread&) = delete;

  /**
   * @brief 异步地向线程任务队列中添加一个任务
   */
  template <typename F>
  void PostTask(F&& task) {
    if (is_running_) {
      // 1. 创建 Task<F> 的 unique_ptr，将 task 移动进去
      auto wrapped_task = std::make_unique<Task<F>>(std::forward<F>(task));
      // 2. 将 unique_ptr<ITask> 移动到队列中
      queue_->Push(std::move(wrapped_task));
    }
  }

  /**
   * @brief 同步地在工作线程上执行一个任务，并阻塞等待其结果
   */
  template <typename F>
  auto BlockingCall(F&& task) -> std::invoke_result_t<F> {
    // 使用新的 IsCurrent() 方法进行死锁检查
    if (IsCurrent()) {
      throw std::runtime_error("BlockingCall cannot be called from the TaskThread itself.");
    }

    if (!is_running_) {
      throw std::runtime_error("Cannot call BlockingCall on a stopped thread.");
    }

    using ReturnType = std::invoke_result_t<F>;
    auto promise = std::make_shared<std::promise<ReturnType>>();
    std::future<ReturnType> future = promise->get_future();

    PostTask([task = std::forward<F>(task), promise]() {
      try {
        if constexpr (std::is_void_v<ReturnType>) {
          task();
          promise->set_value();
        } else {
          promise->set_value(task());
        }
      } catch (...) {
        promise->set_exception(std::current_exception());
      }
    });

    return future.get();
  }

  /**
   * @brief 停止线程，等待所有已提交任务完成
   */
  void Stop();

  /**
   * @brief 检查当前代码是否正在此 TaskThread 的工作线程上执行
   * @return true 如果是，否则 false
   */
  bool IsCurrent() const;

  /**
   * @brief 获取内部 std::thread 的 ID
   */
  std::thread::id GetThreadId() const;

  std::unique_ptr<ThreadQueue<std::unique_ptr<ITask>>> queue_;

 private:
  // 线程的主执行函数
  void Run();

  std::atomic<bool> is_running_;
  std::thread thread_;
  std::string name_;
};

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_WEBRTC_TASK_THREAD_H