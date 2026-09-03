#ifndef DART_TERMINAL_RENDERER_TERMINAL_METAL_VIEW_H_
#define DART_TERMINAL_RENDERER_TERMINAL_METAL_VIEW_H_

#import <MetalKit/MetalKit.h>

#include <string>

@interface TerminalMetalView : MTKView
@end

namespace dart_terminal {

inline constexpr char kTerminalMetalViewProviderIdentifier[] =
    "dart_terminal.TerminalMetalView";

bool RegisterTerminalMetalView(std::string* out_error);

}  // namespace dart_terminal

#endif  // DART_TERMINAL_RENDERER_TERMINAL_METAL_VIEW_H_
