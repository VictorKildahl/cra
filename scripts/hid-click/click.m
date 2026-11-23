// click: a real left click, through the window server as a mouse sends it, for scenarios about what a click on
// an app that isn't in front does (#659: Cra comes forward for it before AppKit makes it active).
//   click <pid> <x> <y> [n]   top-left screen points, n clicks (2 a double click, as a mouse sends it: click states 1
//                         then 2 at the system's pace); clicks only when the window in front at that point is <pid>'s
//                         (the Dock's and Notification Centre's full-screen layers aside), so it never lands in
//                         another app; prints "clicked <x> <y>", or what is there instead and exits 3
// Built by scripts/scenario.sh's `click` lines.
#import <AppKit/AppKit.h>

static NSString* OwnerAt(CGPoint p, pid_t* pid) {
  NSArray* list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                                               kCGNullWindowID));
  for (NSDictionary* w in list) {
    NSString* owner = w[(id)kCGWindowOwnerName];
    if ([w[(id)kCGWindowLayer] intValue] >= 1000 || [w[(id)kCGWindowAlpha] doubleValue] <= 0) continue;
    if ([@[ @"Dock", @"Notification Center", @"Window Server" ] containsObject:owner ?: @""]) continue;
    CGRect r;
    if (!CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)w[(id)kCGWindowBounds], &r) || !CGRectContainsPoint(r, p)) continue;
    *pid = [w[(id)kCGWindowOwnerPID] intValue];
    return owner ?: @"?";
  }
  *pid = 0;
  return @"nothing";
}

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    if (argc < 4) { fprintf(stderr, "usage: click <pid> <x> <y> [clicks]\n"); return 2; }
    pid_t want = atoi(argv[1]);
    CGPoint p = CGPointMake(atof(argv[2]), atof(argv[3]));
    pid_t pid;
    NSString* owner = OwnerAt(p, &pid);
    if (pid != want) { printf("not clicked: %s (pid %d) is in front at %.0f %.0f\n", owner.UTF8String, pid, p.x, p.y); return 3; }
    int clicks = argc > 4 ? MAX(1, atoi(argv[4])) : 1;
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef move = CGEventCreateMouseEvent(src, kCGEventMouseMoved, p, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, move);
    CFRelease(move);
    [NSThread sleepForTimeInterval:0.15];
    for (int n = 1; n <= clicks; n++) {
      CGEventType types[] = {kCGEventLeftMouseDown, kCGEventLeftMouseUp};
      for (int i = 0; i < 2; i++) {
        CGEventRef e = CGEventCreateMouseEvent(src, types[i], p, kCGMouseButtonLeft);
        CGEventSetIntegerValueField(e, kCGMouseEventClickState, n);
        CGEventPost(kCGHIDEventTap, e);
        CFRelease(e);
        [NSThread sleepForTimeInterval:0.08];
      }
    }
    CFRelease(src);
    printf("clicked %.0f %.0f%s\n", p.x, p.y, clicks == 2 ? " twice" : "");
    return 0;
  }
}
