#include "TerminalAppleScriptPlugin.h"

#include <type_traits>

static_assert(std::is_standard_layout_v<DtasSummaryV1>);
static_assert(DTAS_ABI_VERSION == 1u);
static_assert(DTAS_MAX_WINDOWS == 32u);

int main() { return 0; }
