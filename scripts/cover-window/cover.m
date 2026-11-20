// cover: another app's window over a test copy of Cra's browser window, for scenarios about what Cra raises (#607).
//   cover <pid>     waits for that process's largest normal window, puts one of its own over it (same frame) and
//                   right above it in the window order, so it stays behind every window that was over Cra's;
//                   prints "covering <window number>", then waits until killed
// It is the app a link is clicked in (Slack): once Cra hands it the front (cra://debug?yieldTo=<its pid>), SIGUSR1
// hands the front back to Cra, as LaunchServices brings Cra forward for a link clicked in Slack, before the link
// arrives. macOS lets only the app in front do that. Built by scripts/scenario.sh's `cover` lines.
#import <AppKit/AppKit.h>

static NSDictionary* LargestWindow(pid_t pid) {
  NSArray* list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
  NSDictionary* best = nil;
  double bestArea = 0;
  for (NSDictionary* w in list) {
    if ([w[(id)kCGWindowOwnerPID] intValue] != pid || [w[(id)kCGWindowLayer] intValue] != 0) continue;
    CGRect r;
    if (!CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)w[(id)kCGWindowBounds], &r)) continue;
    if (r.size.width * r.size.height > bestArea) { bestArea = r.size.width * r.size.height; best = w; }
  }
  return best;
}

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    if (argc < 2) { fprintf(stderr, "usage: cover <pid>\n"); return 2; }
    pid_t pid = atoi(argv[1]);
    NSApplication* app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSDictionary* target = nil;
    for (int i = 0; i < 150 && !(target = LargestWindow(pid)); i++) [NSThread sleepForTimeInterval:0.2];
    if (!target) { fprintf(stderr, "cover: no window of pid %d in 30 s\n", pid); return 1; }
    CGRect r;
    CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)target[(id)kCGWindowBounds], &r);
    // Window-server bounds are from the top left of the main display; AppKit's from its bottom left.
    CGFloat mainHeight = NSScreen.screens.firstObject.frame.size.height;
    NSRect frame = NSMakeRect(r.origin.x, mainHeight - r.origin.y - r.size.height, r.size.width, r.size.height);
    NSWindow* w = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    w.title = @"Cra Test Cover";
    w.releasedWhenClosed = NO;
    w.backgroundColor = NSColor.windowBackgroundColor;
    [w setFrame:frame display:YES];
    NSInteger number = [target[(id)kCGWindowNumber] integerValue];
    [w orderWindow:NSWindowAbove relativeTo:number];
    signal(SIGUSR1, SIG_IGN);
    dispatch_source_t link = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGUSR1, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(link, ^{
      NSRunningApplication* cra = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
      printf("link: active=%d\n", NSApp.isActive ? 1 : 0);
      fflush(stdout);
      if (@available(macOS 14.0, *)) {
        [NSApp yieldActivationToApplication:cra];
        [cra activateFromApplication:NSRunningApplication.currentApplication options:0];
      } else {
        [cra activateWithOptions:0];
      }
    });
    dispatch_resume(link);
    printf("covering %ld\n", (long)number);
    fflush(stdout);
    [app run];
  }
  return 0;
}
