#import <AppKit/AppKit.h>

#include <cstdint>
#include <iostream>
#include <string>

#include "AppKitObjects.h"
#include "BridgeInternal.h"
#include "ObjectRegistry.h"
#include "TerminalMetalView.h"
#include "dart_appkit.h"

namespace {

int g_failures = 0;

#define EXPECT_TRUE(condition)                                      \
  do {                                                              \
    if (!(condition)) {                                             \
      std::cerr << __FILE__ << ':' << __LINE__                      \
                << " expectation failed: " #condition << std::endl; \
      ++g_failures;                                                 \
    }                                                               \
  } while (false)

#define EXPECT_EQ(actual, expected)                                     \
  do {                                                                  \
    const auto actual_value = (actual);                                 \
    const auto expected_value = (expected);                             \
    if (actual_value != expected_value) {                               \
      std::cerr << __FILE__ << ':' << __LINE__                          \
                << " expectation failed: " #actual " == " #expected     \
                << " (actual=" << actual_value                          \
                << ", expected=" << expected_value << ')' << std::endl; \
      ++g_failures;                                                     \
    }                                                                   \
  } while (false)

uint64_t LiveCount() {
  uint64_t count = 0;
  EXPECT_EQ(da_debug_live_object_count(&count), DA_STATUS_OK);
  return count;
}

}  // namespace

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    dart_appkit::ResetBridgeForTesting();

    std::string registration_error;
    EXPECT_TRUE(dart_terminal::RegisterTerminalMetalView(&registration_error));
    EXPECT_TRUE(registration_error.empty());
    EXPECT_TRUE(dart_terminal::RegisterTerminalMetalView(&registration_error));
    EXPECT_TRUE(registration_error.empty());

    DaHandle view_handle = 0;
    const std::string provider =
        dart_terminal::kTerminalMetalViewProviderIdentifier;
    EXPECT_EQ(
        da_view_create_custom(provider.data(), provider.size(), &view_handle),
        DA_STATUS_OK);
    EXPECT_TRUE(view_handle != 0);
    EXPECT_EQ(LiveCount(), static_cast<uint64_t>(1));

    int32_t status = DA_STATUS_OK;
    id object = dart_appkit::ObjectRegistry::Shared().Lookup(
        view_handle, dart_appkit::ObjectKind::kView,
        dart_appkit::ThreadDomain::kAppKitMain, &status);
    EXPECT_EQ(status, DA_STATUS_OK);
    EXPECT_TRUE([object isKindOfClass:TerminalMetalView.class]);
    TerminalMetalView* view = static_cast<TerminalMetalView*>(object);
    EXPECT_TRUE(view.device != nil);
    EXPECT_TRUE(view.isPaused);
    EXPECT_TRUE(view.enableSetNeedsDisplay);
    EXPECT_TRUE(view.autoResizeDrawable);
    EXPECT_TRUE(view.framebufferOnly);
    EXPECT_TRUE(view.delegate == nil);
    EXPECT_TRUE(view.isFlipped);

    DaHandle window_handle = 0;
    const std::string title = "TerminalMetalView contract";
    EXPECT_EQ(da_window_create({100.0, 100.0, 640.0, 480.0}, title.data(),
                               title.size(), &window_handle),
              DA_STATUS_OK);
    EXPECT_TRUE(window_handle != 0);
    EXPECT_EQ(da_window_set_content_view(window_handle, view_handle),
              DA_STATUS_OK);
    DaWindowOwner* owner = static_cast<DaWindowOwner*>(
        dart_appkit::ObjectRegistry::Shared().Lookup(
            window_handle, dart_appkit::ObjectKind::kWindow,
            dart_appkit::ThreadDomain::kAppKitMain, &status));
    EXPECT_EQ(status, DA_STATUS_OK);
    EXPECT_TRUE(owner.window.contentView == view);
    EXPECT_TRUE(owner.window.firstResponder == view);

    EXPECT_EQ(da_release(view_handle), DA_STATUS_OK);
    EXPECT_TRUE(owner.window.contentView == view);
    EXPECT_EQ(da_window_set_content_view(window_handle, view_handle),
              DA_STATUS_INVALID_HANDLE);
    EXPECT_EQ(da_release(view_handle), DA_STATUS_INVALID_HANDLE);
    EXPECT_EQ(da_release(window_handle), DA_STATUS_OK);
    EXPECT_EQ(LiveCount(), static_cast<uint64_t>(0));
    dart_appkit::ResetBridgeForTesting();
  }

  if (g_failures != 0) {
    std::cerr << g_failures << " TerminalMetalView test(s) failed" << std::endl;
    return 1;
  }
  std::cout << "TerminalMetalView native contract passed" << std::endl;
  return 0;
}
