#pragma once

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <deque>
#include <fcntl.h>
#include <string>
#include <unistd.h>

// One owner/thread, one write descriptor. No worker retains a duplicate when the
// browser must hang up the DevTools pipe to quit. Frames include their NUL byte.
class CraPipeWriter {
public:
    enum class EnqueueResult { Accepted, Closed, Full };
    enum class DrainState { Empty, WouldBlock, Yielded, Failed, Stale };
    struct DrainResult { DrainState state; int error = 0; };

    explicit CraPipeWriter(size_t maxBytes = 8 * 1024 * 1024, size_t maxFrames = 256)
        : maxBytes_(maxBytes), maxFrames_(maxFrames) {}
    ~CraPipeWriter() { close(); }
    CraPipeWriter(const CraPipeWriter&) = delete;
    CraPipeWriter& operator=(const CraPipeWriter&) = delete;

    // Takes ownership even on failure. Call only with a fresh descriptor.
    bool open(int fd) {
        close();
        if (fd < 0) { errno = EBADF; return false; }
        int flags = fcntl(fd, F_GETFL);
        if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 ||
            fcntl(fd, F_SETNOSIGPIPE, 1) < 0) {
            int error = errno;
            ::close(fd);
            errno = error;
            return false;
        }
        fd_ = fd;
        return true;
    }

    void close() {
        int fd = fd_;
        fd_ = -1;
        ++generation_;
        frames_.clear();
        retainedBytes_ = 0;
        offset_ = 0;
        if (fd >= 0) ::close(fd); // Never retry close: the descriptor may be reused.
    }

    bool isOpen() const { return fd_ >= 0; }
    uint64_t generation() const { return generation_; }
    size_t queuedBytes() const { return retainedBytes_; }
    size_t queuedFrames() const { return frames_.size(); }

    EnqueueResult enqueue(const char* bytes, size_t length) {
        if (!isOpen()) return EnqueueResult::Closed;
        // Count complete retained allocations, including a partly written front
        // frame, so repeated enqueues cannot evade the memory bound.
        if (!length || length > maxBytes_ - retainedBytes_ || frames_.size() >= maxFrames_)
            return EnqueueResult::Full;
        frames_.emplace_back(bytes, length);
        retainedBytes_ += length;
        return EnqueueResult::Accepted;
    }

    // Bound both bytes and syscalls per main-loop turn, including repeated EINTR.
    // A delayed drain must carry its original generation, never a bare fd.
    DrainResult drain(uint64_t expectedGeneration, size_t byteBudget = 65536,
                      size_t callBudget = 16) {
        if (expectedGeneration != generation_) return {DrainState::Stale};
        if (!isOpen()) return {DrainState::Failed, EBADF};
        size_t written = 0, calls = 0;
        while (!frames_.empty() && written < byteBudget && calls < callBudget) {
            const auto& frame = frames_.front();
            size_t count = std::min(frame.size() - offset_, byteBudget - written);
            ++calls;
            ssize_t n = ::write(fd_, frame.data() + offset_, count);
            if (n > 0) {
                offset_ += static_cast<size_t>(n);
                written += static_cast<size_t>(n);
                if (offset_ == frame.size()) {
                    retainedBytes_ -= frame.size();
                    frames_.pop_front();
                    offset_ = 0;
                }
                continue;
            }
            if (n < 0 && errno == EINTR) continue;
            if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
                return {DrainState::WouldBlock};
            int error = n == 0 ? EIO : errno;
            close();
            return {DrainState::Failed, error};
        }
        return {frames_.empty() ? DrainState::Empty : DrainState::Yielded};
    }

private:
    int fd_ = -1;
    uint64_t generation_ = 0;
    std::deque<std::string> frames_;
    size_t retainedBytes_ = 0;
    size_t offset_ = 0;
    const size_t maxBytes_;
    const size_t maxFrames_;
};
