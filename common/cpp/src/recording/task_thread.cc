#include "task_thread.h"

#include <iostream>
#include "flutter_webrtc_logging.h"

namespace flutter_webrtc_plugin {

// 构造函数实现
TaskThread::TaskThread(std::string name)
    : is_running_(true),
      name_(std::move(name)),
      queue_(std::make_unique<ThreadQueue<std::unique_ptr<ITask>>>(
          std::numeric_limits<size_t>::max())) {
  thread_ = std::thread(&TaskThread::Run, this);
  RTC_LOG(LS_INFO) << "Thread " << name_ << " started.";
}

// 析构函数实现
TaskThread::~TaskThread() {
  // 确保 Stop() 被调用，即使使用者忘记了
  Stop();
  RTC_LOG(LS_INFO) << "TaskThread destroyed.";
}

// Stop 方法实现
void TaskThread::Stop() {
  // 使用 exchange 原子地将 is_running_ 设置为 false，并获取其旧值
  // 这样可以确保 "stop" 逻辑只被执行一次
  bool already_stopping = !is_running_.exchange(false);
  if (already_stopping) {
    return;
  }

  RTC_LOG(LS_INFO) << "Stopping thread [" << name_ << "]" << " left with "
                   << queue_->Size() << " tasks" << "...";

  // // 推入一个空任务来唤醒可能因队列为空而阻塞的线程
  // queue_->TryPush([]() {});
  queue_->Close();

  if (thread_.joinable()) {
    thread_.join();
  }
  RTC_LOG(LS_INFO) << "Thread [" << name_ << "] stopped.";
}

// IsCurrent 方法实现
bool TaskThread::IsCurrent() const {
  return std::this_thread::get_id() == thread_.get_id();
}

// GetThreadId 方法实现
std::thread::id TaskThread::GetThreadId() const {
  return thread_.get_id();
}

// 线程主循环实现
void TaskThread::Run() {
  while (true) {
    // 从队列中阻塞式地取出一个任务
    auto [task, _] = queue_->Pop();

    if (task) {
      try {
        (*task)->Execute();
      } catch (const std::exception& e) {
        RTC_LOG(LS_ERROR) << "Exception caught in task thread: " << e.what()
                          << '\n';
      } catch (...) {
        RTC_LOG(LS_ERROR) << "Unknown exception caught in task thread.\n";
      }
    }

    // 退出循环的条件：收到了停止信号 并且 队列已经空了
    if (!is_running_ && queue_->IsEmpty()) {
      break;
    }
  }
}

}  // namespace flutter_webrtc_plugin