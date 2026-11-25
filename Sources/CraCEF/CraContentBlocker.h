// Third-party ad and tracker blocking: the domain matching behind
// +[CraCEFRuntime setContentBlockingEnabled:]. Plain C++ with no CEF or Cocoa
// dependency so it can be tested on its own.
//
// A request is blocked when its host, or any parent domain of it, is on the
// list and the request is third-party to the top-level page. Lookups run on
// CEF's IO thread for every subresource, so the list is an immutable set
// shared by concurrent readers.
#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <unordered_set>

namespace cra_blocker {

using DomainSet = std::unordered_set<std::string>;

inline std::atomic<bool>& Enabled() { static std::atomic<bool> v{false}; return v; }

struct BlockerState {
    std::shared_mutex mutex;
    std::unique_ptr<const DomainSet> domains;
    DomainSet pausedHosts;
};

inline BlockerState& State() { static auto* const state = new BlockerState; return *state; }

inline void Publish(const DomainSet* set) {
    std::unique_ptr<const DomainSet> next(set);
    auto& state = State();
    std::unique_lock lock(state.mutex);
    state.domains.swap(next);
}

inline void SetPausedHosts(DomainSet hosts) {
    auto& state = State();
    std::unique_lock lock(state.mutex);
    state.pausedHosts.swap(hosts);
}

inline size_t Count() {
    auto& state = State();
    std::shared_lock lock(state.mutex);
    return state.domains ? state.domains->size() : 0;
}

inline char Lower(char c) { return (c >= 'A' && c <= 'Z') ? char(c - 'A' + 'a') : c; }

// Lowercased, without a trailing dot. Empty for anything that isn't a domain name.
inline std::string NormalizeHost(std::string_view h) {
    while (!h.empty() && h.back() == '.') h.remove_suffix(1);
    std::string r;
    r.reserve(h.size());
    for (char c : h) {
        char l = Lower(c);
        if (!((l >= 'a' && l <= 'z') || (l >= '0' && l <= '9') || l == '-' || l == '.' || l == '_')) return {};
        r.push_back(l);
    }
    return r;
}

// Adds one line of a list file: a bare domain, or a hosts-file line
// ("0.0.0.0 example.com"). Comments and blank lines are skipped.
inline void AddListLine(DomainSet& set, std::string_view line) {
    if (size_t hash = line.find('#'); hash != std::string_view::npos) line = line.substr(0, hash);
    auto isSpace = [](char c) { return c == ' ' || c == '\t' || c == '\r'; };
    while (!line.empty() && isSpace(line.front())) line.remove_prefix(1);
    while (!line.empty() && isSpace(line.back())) line.remove_suffix(1);
    if (line.empty()) return;
    size_t sp = line.find_first_of(" \t");
    if (sp != std::string_view::npos) {  // hosts syntax: take the name after the address
        line = line.substr(sp);
        while (!line.empty() && isSpace(line.front())) line.remove_prefix(1);
        line = line.substr(0, line.find_first_of(" \t"));
    }
    std::string d = NormalizeHost(line);
    if (d.empty() || d.find('.') == std::string::npos || d == "localhost") return;
    set.insert(std::move(d));
}

inline DomainSet* ParseList(std::string_view text) {
    auto* set = new DomainSet();
    set->reserve(32768);
    while (!text.empty()) {
        size_t nl = text.find('\n');
        AddListLine(*set, text.substr(0, nl));
        if (nl == std::string_view::npos) break;
        text.remove_prefix(nl + 1);
    }
    return set;
}

// The listed domain covering `host` (host itself or a parent), or empty. A bare
// top-level label is never matched.
inline std::string MatchedEntry(const DomainSet& set, const std::string& host) {
    size_t pos = 0;
    while (true) {
        size_t dot = host.find('.', pos);
        if (dot == std::string::npos) return {};  // only the TLD is left
        std::string suffix = host.substr(pos);
        if (set.count(suffix)) return suffix;
        pos = dot + 1;
    }
}

inline bool IsSubdomainOrSame(std::string_view host, std::string_view domain) {
    if (host.size() == domain.size()) return host == domain;
    return host.size() > domain.size() && host.substr(host.size() - domain.size()) == domain &&
           host[host.size() - domain.size() - 1] == '.';
}

// Approximate registrable domain (eTLD+1) without the Public Suffix List: the
// last two labels, or three under the common "co.uk"-style second levels. A
// miss only ever makes two hosts look like one site, which fails open.
inline std::string_view Site(std::string_view host) {
    size_t last = host.rfind('.');
    if (last == std::string_view::npos || last == 0) return host;
    size_t second = host.rfind('.', last - 1);
    if (second == std::string_view::npos) return host;
    std::string_view tld = host.substr(last + 1);
    std::string_view sld = host.substr(second + 1, last - second - 1);
    static const std::string_view kSecondLevels[] = {"co", "com", "net", "org", "gov", "edu", "ac",
                                                     "ne", "or", "go", "gob", "mil", "nic", "ltd", "plc"};
    bool cc = tld.size() == 2;
    bool sl = false;
    for (auto s : kSecondLevels) sl = sl || s == sld;
    if (cc && sl && second > 0) {
        size_t third = host.rfind('.', second - 1);
        return third == std::string_view::npos ? host : host.substr(third + 1);
    }
    return host.substr(second + 1);
}

inline bool IsIPLiteral(std::string_view host) {
    if (host.find(':') != std::string_view::npos) return true;  // IPv6
    for (char c : host) if (!((c >= '0' && c <= '9') || c == '.')) return false;
    return !host.empty();
}

// The decision for one subresource request. Hosts must be normalized; an empty
// page host (non-web top-level page) never blocks.
inline bool ShouldBlock(const std::string& requestHost, const std::string& pageHost) {
    if (!Enabled().load(std::memory_order_relaxed)) return false;
    auto& state = State();
    std::shared_lock lock(state.mutex);
    if (state.pausedHosts.count(pageHost)) return false;
    const DomainSet* set = state.domains.get();
    if (!set || set->empty() || requestHost.empty() || pageHost.empty() || IsIPLiteral(requestHost)) return false;
    std::string entry = MatchedEntry(*set, requestHost);
    if (entry.empty()) return false;
    // First-party: the page is on the listed domain itself, or on the same site.
    if (IsSubdomainOrSame(pageHost, entry)) return false;
    if (!IsIPLiteral(pageHost) && Site(requestHost) == Site(pageHost)) return false;
    return true;
}

// Host of an http(s)/ws(s) URL, normalized; empty for other schemes. Parses just
// enough of the URL for this purpose (scheme, optional userinfo, port, IPv6).
inline std::string WebHost(std::string_view url) {
    size_t colon = url.find("://");
    if (colon == std::string_view::npos) return {};
    std::string scheme;
    for (char c : url.substr(0, colon)) scheme.push_back(Lower(c));
    if (scheme != "http" && scheme != "https" && scheme != "ws" && scheme != "wss") return {};
    std::string_view rest = url.substr(colon + 3);
    rest = rest.substr(0, rest.find_first_of("/?#"));
    if (size_t at = rest.rfind('@'); at != std::string_view::npos) rest = rest.substr(at + 1);
    if (!rest.empty() && rest.front() == '[') {
        size_t close = rest.find(']');
        return close == std::string_view::npos ? std::string() : std::string(rest.substr(0, close + 1));
    }
    return NormalizeHost(rest.substr(0, rest.find(':')));
}

}  // namespace cra_blocker
