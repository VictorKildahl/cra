// vdisplay: a virtual Retina display for test copies of Cra, alive as long as this process runs.
//   vdisplay [width-points height-points]     default 1728 1117 (a 16" MacBook Pro), at 2x, named "Cra Test Display"
// Prints "ready <id> <x>,<y> <w>x<h>" once the display is extended (not mirrored) below the main one, then waits.
// Scenarios run on it with CRA_TEST_SCREEN="Cra Test Display" (scripts/test-display.sh): GitHub's macOS runners have
// one small 1x screen, where a 1200x800 window doesn't fit and the scenarios' geometry and 2x snapshots fail.
// macOS's CGVirtualDisplay is private API (what screen-sharing apps use); this declares the part it needs.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString* name;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int serialNum;
@property(copy, nonatomic) void (^terminationHandler)(id, id);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(retain, nonatomic) NSArray* modes;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor*)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings*)settings;
@property(readonly, nonatomic) CGDirectDisplayID displayID;
@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    unsigned int width = argc > 2 ? (unsigned int)atoi(argv[1]) : 1728;
    unsigned int height = argc > 2 ? (unsigned int)atoi(argv[2]) : 1117;
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!descriptorClass || !displayClass) {
      fprintf(stderr, "vdisplay: this macOS has no CGVirtualDisplay\n");
      return 1;
    }
    CGVirtualDisplayDescriptor* descriptor = [[descriptorClass alloc] init];
    descriptor.queue = dispatch_get_main_queue();
    descriptor.name = @"Cra Test Display";
    descriptor.maxPixelsWide = width * 2;
    descriptor.maxPixelsHigh = height * 2;
    descriptor.sizeInMillimeters = CGSizeMake(width * 0.2, height * 0.2);
    descriptor.productID = 0xC7A1;
    descriptor.vendorID = 0xC7A0;
    descriptor.serialNum = 1;
    descriptor.terminationHandler = ^(id a, id b) {
      fprintf(stderr, "vdisplay: macOS ended the display\n");
      exit(1);
    };
    CGVirtualDisplay* display = [[displayClass alloc] initWithDescriptor:descriptor];
    if (!display || display.displayID == 0) {
      fprintf(stderr, "vdisplay: macOS refused the display\n");
      return 1;
    }
    CGVirtualDisplaySettings* settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    settings.hiDPI = 1;
    settings.modes = @[ [[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:width
                                                                                   height:height
                                                                              refreshRate:60] ];
    if (![display applySettings:settings]) {
      fprintf(stderr, "vdisplay: macOS refused the display's mode\n");
      return 1;
    }
    CGDirectDisplayID id = display.displayID;
    // With one screen macOS mirrors the new display at first: extend it below the main one, again until it holds.
    CGRect bounds = CGRectZero;
    for (int attempt = 0; attempt < 15; attempt++) {
      CGRect main = CGDisplayBounds(CGMainDisplayID());
      CGDisplayConfigRef config;
      if (CGBeginDisplayConfiguration(&config) == kCGErrorSuccess) {
        CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay);
        CGConfigureDisplayOrigin(config, id, (int32_t)CGRectGetMinX(main), (int32_t)CGRectGetMaxY(main));
        CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
      }
      [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
      bounds = CGDisplayBounds(id);
      if (!CGDisplayIsInMirrorSet(id) && CGRectGetMinY(bounds) >= CGRectGetMaxY(CGDisplayBounds(CGMainDisplayID())) - 1 &&
          CGRectGetWidth(bounds) == width) {
        printf("ready %u %.0f,%.0f %.0fx%.0f\n", id, bounds.origin.x, bounds.origin.y, bounds.size.width,
               bounds.size.height);
        fflush(stdout);
        [[NSRunLoop mainRunLoop] run];
        return 0;
      }
    }
    fprintf(stderr, "vdisplay: the display stayed mirrored or misplaced (%.0f,%.0f %.0fx%.0f)\n", bounds.origin.x,
            bounds.origin.y, bounds.size.width, bounds.size.height);
    return 1;
  }
}
