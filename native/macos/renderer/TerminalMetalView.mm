#include "TerminalMetalView.h"

#include <string>

#include "dart_appkit.h"
#include "dart_appkit_custom_view.h"

@implementation TerminalMetalView

- (instancetype)initWithFrame:(NSRect)frameRect {
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device == nil) {
    return nil;
  }
  self = [super initWithFrame:frameRect device:device];
  if (self != nil) {
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.autoResizeDrawable = YES;
    self.paused = YES;
    self.enableSetNeedsDisplay = YES;
    self.framebufferOnly = YES;
    self.delegate = nil;
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

@end

namespace dart_terminal {

bool RegisterTerminalMetalView(std::string* out_error) {
  if (out_error == nullptr) {
    return false;
  }
  out_error->clear();
  const int32_t status = dart_appkit::RegisterCustomViewClass(
      @"dart_terminal.TerminalMetalView", TerminalMetalView.class);
  if (status == DA_STATUS_OK) {
    return true;
  }
  DaError error{};
  da_get_last_error(&error);
  if (error.message != nullptr && error.message_length != 0) {
    out_error->assign(error.message, error.message_length);
  } else {
    *out_error =
        "custom view registration failed with status " + std::to_string(status);
  }
  return false;
}

}  // namespace dart_terminal
