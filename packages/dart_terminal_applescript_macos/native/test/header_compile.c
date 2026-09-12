#include "TerminalAppleScriptPlugin.h"

int main(void) {
  DtasSummaryV1 summary = {0};
  summary.struct_size = sizeof(summary);
  summary.version = DTAS_SUMMARY_VERSION;
  return DTAS_ABI_VERSION == 1u && DTAS_MAX_PENDING_COMMANDS == 16u ? 0 : 1;
}
