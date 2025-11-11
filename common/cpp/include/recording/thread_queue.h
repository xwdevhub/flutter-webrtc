#ifndef FLUTTER_WEBRTC_THREAD_QUEUE_HXX
#define FLUTTER_WEBRTC_THREAD_QUEUE_HXX

#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <optional>
#include <queue>
#include <stdexcept>

namespace flutter_webrtc_plugin {

template <typename T>
class ThreadQueue {
 public:
  // 使用 explicit 防止隐式类型转换
  // explicit ThreadQueue(size_t capacity = std::numeric_limits<size_t>::max())
  explicit ThreadQueue(size_t capacity = 1) : capacity_(capacity) {
    if (capacity_ == 0) {
      throw std::invalid_argument("capacity must be greater than 0");
    }
  }

  // 使用转发引用实现完美转发
  template <typename U>
  bool Push(U&& value) {
    std::unique_lock<std::mutex> lock(mutex_);
    producer_cv_.wait(lock, [this] { return queue_.size() < capacity_ || closed_; });

    // 唤醒后检查是否已经关闭
    if (closed_) {
      return false;
    }

    // bool was_empty = queue_.empty();
    queue_.push(std::forward<U>(value));

    // 只有当队列从空变为非空时，才唤醒消费者
    // if (was_empty) {
    consumer_cv_.notify_one();
    // }
    return true;
  }

  template <typename U>
  bool TryPush(U&& value) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (closed_) {
      return false;
    }

    if (queue_.size() == capacity_) {
      return false;  // 丢弃新数据
    }

    // bool was_empty = queue_.empty();
    queue_.push(std::forward<U>(value));

    // 只有当队列从空变为非空时，才唤醒消费者
    // if (was_empty) {
    consumer_cv_.notify_one();
    // }

    return true;
  }

  template <typename U, typename Rep, typename Period>
  bool PushWaitFor(U&& value, const std::chrono::duration<Rep, Period>& timeout) {
    std::unique_lock<std::mutex> lock(mutex_);

    if (!consumer_cv_.wait_for(lock, timeout,
                               [this] { return queue_.size() < capacity_ || closed_; })) {
      // 超时
      return false;
    }

    if (closed_) {
      return false;
    }

    // bool was_empty = queue_.empty();
    queue_.push(std::forward<U>(value));

    // 只有当队列从空变为非空时，才唤醒消费者
    // if (was_empty) {
    consumer_cv_.notify_one();
    // }
    return true;
  }

  std::pair<std::optional<T>, bool> Pop() {
    std::unique_lock<std::mutex> lock(mutex_);
    consumer_cv_.wait(lock, [this] { return !queue_.empty() || closed_; });

    // 队列为空且已关闭，返回结束信号
    if (queue_.empty()) {  // 必然是因为 closed_ = true
      return std::make_pair(std::nullopt, false);
    }

    // 队列不为空，取出元素
    // bool was_full = queue_.size() == capacity_;
    T value = std::move(queue_.front());
    queue_.pop();

    // 通知可能等待的生产者
    // if (was_full) {
    producer_cv_.notify_one();
    // }
    return std::make_pair(std::move(value), true);
  }

  std::pair<std::optional<T>, bool> TryPop() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (queue_.empty()) {
      return std::make_pair(std::nullopt, !closed_);
    }

    // bool was_full = queue_.size() == capacity_;

    T value = std::move(queue_.front());
    queue_.pop();

    // if (was_full) {
    producer_cv_.notify_one();
    // }
    return std::make_pair(std::move(value), true);
  }

  /**
   * @brief 如果队头元素满足特定条件，则原子地弹出它。
   * @tparam Predicate 一个可调用对象，接受 const T& 参数，返回 bool。
   * @param pred 用于判断是否要 pop 的谓词。
   * @return 如果队列不为空且队头元素满足条件，则返回该元素；否则返回
   * std::nullopt。
   */
  template <typename Predicate>
  std::pair<std::optional<T>, bool> TryPopIf(Predicate pred) {
    std::lock_guard<std::mutex> lock(mutex_);

    // 如果队列为空，或者队头元素不满足条件，则直接返回
    if (queue_.empty() || !pred(queue_.front())) {
      return std::make_pair(std::nullopt, !closed_);
    }

    // 条件满足，执行 pop 逻辑
    // bool was_full = queue_.size() == capacity_;

    T value = std::move(queue_.front());
    queue_.pop();

    // 通知可能在等待的生产者
    // if (was_full) {
    producer_cv_.notify_one();
    // }
    return std::make_pair(std::move(value), true);
  }

  template <typename Rep, typename Period>
  std::pair<std::optional<T>, bool> PopWaitFor(const std::chrono::duration<Rep, Period>& timeout) {
    std::unique_lock<std::mutex> lock(mutex_);
    // 队列为空,等待指定时间
    if (!consumer_cv_.wait_for(lock, timeout, [this] { return !queue_.empty() || closed_; })) {
      // 超时
      return std::make_pair(std::nullopt, true);
    }

    if (queue_.empty()) {
      return std::make_pair(std::nullopt, false);
    }

    // bool was_full = queue_.size() == capacity_;

    T value = std::move(queue_.front());
    queue_.pop();

    // if (was_full) {
    producer_cv_.notify_one();
    // }

    return std::make_pair(std::move(value), true);
  }

  void Close() {
    std::lock_guard<std::mutex> lock(mutex_);
    closed_ = true;
    producer_cv_.notify_all();
    consumer_cv_.notify_all();
  }

  void Clear() {
    std::lock_guard<std::mutex> lock(mutex_);

    // bool was_full = queue_.size() == capacity_;

    std::queue<T> empty_queue;
    queue_.swap(empty_queue);

    // if (was_full) {
    producer_cv_.notify_all();
    // }
  }

  size_t Size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return queue_.size();
  }

  size_t Capacity() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return capacity_;
  }

  bool IsEmpty() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return queue_.empty();
  }

  bool IsFull() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return queue_.size() == capacity_;
  }

 private:
  const size_t capacity_;

  std::atomic<bool> closed_{false};
  std::queue<T> queue_;
  mutable std::mutex mutex_;  // mutable 允许在 const 成员函数中加锁

  std::condition_variable producer_cv_;  // 用于生产者等待空间
  std::condition_variable consumer_cv_;  // 用于消费者等待数据
};

}  // namespace flutter_webrtc_plugin

#endif