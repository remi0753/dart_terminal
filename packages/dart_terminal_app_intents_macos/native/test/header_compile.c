#include "TerminalAppIntents.h"

int main(void) {
  return DTAI_ABI_VERSION == 1u && DTAI_MAX_PENDING_COMMANDS == 16u &&
                 DTAI_ACTION_TOGGLE_QUICK_TERMINAL == 3
             ? 0
             : 1;
}
