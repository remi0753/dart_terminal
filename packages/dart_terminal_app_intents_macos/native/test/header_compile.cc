#include <type_traits>

#include "TerminalAppIntents.h"

static_assert(std::is_same_v<std::underlying_type_t<DtaiStatus>, unsigned int>);
static_assert(DTAI_MAX_TIMEOUT_MICROS == 300000000u);

int main() { return 0; }
