#include <unistd.h>
static ssize_t testWrite(int fd, const void* bytes, size_t length);
// Real pipes throughout; inject only EINTR, which cannot be provoked reliably by
// timing a signal against a nonblocking syscall.
#define write testWrite
#include "../Sources/CraCEF/CraPipeWriter.h"
#undef write
#include <cassert>
#include <chrono>
#include <cstdio>
#include <vector>

using Writer = CraPipeWriter;
static int interruptedWrites = 0;
static ssize_t testWrite(int fd, const void* bytes, size_t length) {
    if (interruptedWrites > 0) { --interruptedWrites; errno = EINTR; return -1; }
    return write(fd, bytes, length);
}

static std::string readAvailable(int fd, size_t limit = 65536) {
    std::string result;
    char bytes[4096];
    while (result.size() < limit) {
        ssize_t n = read(fd, bytes, std::min(sizeof bytes, limit - result.size()));
        if (n > 0) result.append(bytes, static_cast<size_t>(n));
        else if (n < 0 && errno == EINTR) continue;
        else { assert(n == 0 || errno == EAGAIN || errno == EWOULDBLOCK); break; }
    }
    return result;
}

struct Pipe {
    int readFD, writeFD;
    Pipe() {
        int fds[2]; assert(pipe(fds) == 0);
        readFD = fds[0]; writeFD = fds[1];
        assert(fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK) == 0);
    }
    ~Pipe() { if (readFD >= 0) close(readFD); if (writeFD >= 0) close(writeFD); }
    int takeWrite() { int fd = writeFD; writeFD = -1; return fd; }
};

int main() {
    alarm(15); // A regression to blocking writes must fail, not hang the test runner.
    int checks = 0;
    {
        Pipe pipe; Writer writer;
        int fd = pipe.takeWrite();
        assert(writer.open(fd));
        assert(fcntl(fd, F_GETFL) & O_NONBLOCK);
        assert(fcntl(fd, F_GETNOSIGPIPE) == 1);
        ++checks;
    }
    {
        Pipe pipe; Writer writer;
        assert(writer.open(pipe.takeWrite()));
        assert(writer.enqueue("interrupted", 11) == Writer::EnqueueResult::Accepted);
        interruptedWrites = 2;
        assert(writer.drain(writer.generation()).state == Writer::DrainState::Empty);
        assert(readAvailable(pipe.readFD) == "interrupted");
        ++checks;
        assert(writer.enqueue("later", 5) == Writer::EnqueueResult::Accepted);
        interruptedWrites = 100;
        assert(writer.drain(writer.generation(), 65536, 3).state == Writer::DrainState::Yielded);
        assert(interruptedWrites == 97 && readAvailable(pipe.readFD).empty());
        interruptedWrites = 0;
        assert(writer.drain(writer.generation()).state == Writer::DrainState::Empty);
        assert(readAvailable(pipe.readFD) == "later");
        ++checks;
    }
    {
        // Real backpressure: no reader consumes data until the pipe is full.
        Pipe pipe; Writer writer;
        assert(writer.open(pipe.takeWrite()));
        std::string first(2 * 1024 * 1024, 'a'); first.back() = '\0';
        std::string second(128 * 1024, 'b'); second.back() = '\0';
        std::string third("third\0", 6);
        assert(writer.enqueue(first.data(), first.size()) == Writer::EnqueueResult::Accepted);
        assert(writer.enqueue(second.data(), second.size()) == Writer::EnqueueResult::Accepted);
        assert(writer.enqueue(third.data(), third.size()) == Writer::EnqueueResult::Accepted);
        auto start = std::chrono::steady_clock::now();
        Writer::DrainResult result;
        for (int i = 0; i < 100; ++i) {
            result = writer.drain(writer.generation());
            if (result.state == Writer::DrainState::WouldBlock) break;
        }
        assert(result.state == Writer::DrainState::WouldBlock);
        assert(std::chrono::steady_clock::now() - start < std::chrono::seconds(1));
        assert(writer.queuedBytes() == first.size() + second.size() + third.size());
        ++checks;
        // Resume in deliberately small fragments; frame and byte order must survive.
        std::string received;
        for (int i = 0; i < 5000 && writer.queuedFrames(); ++i) {
            received += readAvailable(pipe.readFD, 997);
            result = writer.drain(writer.generation(), 4001, 3);
            assert(result.state != Writer::DrainState::Failed);
        }
        assert(writer.queuedFrames() == 0 && writer.queuedBytes() == 0);
        received += readAvailable(pipe.readFD);
        assert(received == first + second + third);
        ++checks;
    }
    {
        // Limits reject a new frame without changing an already accepted frame.
        Pipe pipe; Writer writer(16, 2);
        assert(writer.open(pipe.takeWrite()));
        assert(writer.enqueue("1234567890", 10) == Writer::EnqueueResult::Accepted);
        assert(writer.enqueue("abcdefg", 7) == Writer::EnqueueResult::Full);
        assert(writer.enqueue("abc", 3) == Writer::EnqueueResult::Accepted);
        assert(writer.enqueue("x", 1) == Writer::EnqueueResult::Full);
        assert(writer.queuedBytes() == 13 && writer.queuedFrames() == 2);
        writer.drain(writer.generation());
        assert(readAvailable(pipe.readFD) == "1234567890abc");
        ++checks;
    }
    {
        // SIGPIPE must not terminate this test process when Chromium closes first.
        Pipe pipe; Writer writer;
        assert(writer.open(pipe.takeWrite()));
        close(pipe.readFD); pipe.readFD = -1;
        assert(writer.enqueue("x", 1) == Writer::EnqueueResult::Accepted);
        auto result = writer.drain(writer.generation());
        assert(result.state == Writer::DrainState::Failed && result.error == EPIPE);
        assert(!writer.isOpen() && writer.queuedFrames() == 0);
        assert(writer.enqueue("x", 1) == Writer::EnqueueResult::Closed);
        ++checks;
    }
    {
        // Chromium's reply writer inherits protection when installed as fd 4.
        // Cancelling our read source must not terminate the whole browser.
        Pipe pipe;
        assert(fcntl(pipe.writeFD, F_SETNOSIGPIPE, 1) == 0);
        int chromiumWriter = dup(pipe.writeFD);
        assert(chromiumWriter >= 0 && fcntl(chromiumWriter, F_GETNOSIGPIPE) == 1);
        close(pipe.writeFD); pipe.writeFD = -1;
        close(pipe.readFD); pipe.readFD = -1;
        assert(write(chromiumWriter, "reply", 5) == -1 && errno == EPIPE);
        close(chromiumWriter);
        ++checks;
    }
    {
        Pipe pipe; Writer writer;
        assert(writer.open(pipe.takeWrite()));
        auto previous = writer.generation();
        assert(writer.enqueue("unsent", 6) == Writer::EnqueueResult::Accepted);
        writer.close();
        char byte;
        assert(read(pipe.readFD, &byte, 1) == 0); // Immediate EOF; no duplicate writer.
        assert(writer.queuedBytes() == 0);
        ++checks;
        Pipe replacement;
        assert(writer.open(replacement.takeWrite()));
        assert(writer.enqueue("new", 3) == Writer::EnqueueResult::Accepted);
        assert(writer.drain(previous).state == Writer::DrainState::Stale);
        assert(readAvailable(replacement.readFD).empty());
        assert(writer.queuedFrames() == 1);
        assert(writer.drain(writer.generation()).state == Writer::DrainState::Empty);
        assert(readAvailable(replacement.readFD) == "new");
        ++checks;
    }
    {
        Pipe pipe; Writer writer;
        assert(writer.open(pipe.takeWrite()));
        assert(writer.enqueue("123456789", 9) == Writer::EnqueueResult::Accepted);
        assert(writer.drain(writer.generation(), 3, 1).state == Writer::DrainState::Yielded);
        assert(readAvailable(pipe.readFD) == "123");
        assert(writer.drain(writer.generation(), 3, 1).state == Writer::DrainState::Yielded);
        assert(readAvailable(pipe.readFD) == "456");
        assert(writer.drain(writer.generation(), 3, 1).state == Writer::DrainState::Empty);
        assert(readAvailable(pipe.readFD) == "789");
        ++checks;
    }
    alarm(0);
    printf("Nonblocking DevTools pipe: %d checks passed\n", checks);
}
