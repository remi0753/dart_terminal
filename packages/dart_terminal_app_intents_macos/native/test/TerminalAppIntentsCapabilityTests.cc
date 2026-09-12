#include <stdio.h>
#include <unistd.h>

#include <thread>

#include "TerminalAppIntents.h"

namespace {

int g_failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    fprintf(stderr, "FAIL %s\n", description);
    ++g_failures;
  }
}

struct Summary {
  uint64_t generation = 0;
  uint64_t queued = 0;
  uint64_t pending = 0;
  uint64_t accepted = 0;
  uint64_t resolved = 0;
  uint64_t rejected = 0;
  uint64_t timed_out = 0;
  uint32_t started = 0;
  uint32_t enabled = 0;
};

Summary ReadSummary() {
  Summary value;
  Expect(dtai_debug_summary(&value.generation, &value.queued, &value.pending,
                            &value.accepted, &value.resolved, &value.rejected,
                            &value.timed_out, &value.started,
                            &value.enabled) == DTAI_STATUS_OK,
         "summary status");
  return value;
}

void TestValidationAndThreadBoundary() {
  Expect(dtai_abi_version() == DTAI_ABI_VERSION, "ABI version");
  Expect(dtai_take_command(nullptr, nullptr, nullptr) ==
             DTAI_STATUS_INVALID_ARGUMENT,
         "null command outputs");
  Expect(dtai_session_start(0u, DTAI_DEFAULT_TIMEOUT_MICROS) ==
             DTAI_STATUS_INVALID_ARGUMENT,
         "zero pending bound");
  Expect(dtai_session_start(DTAI_MAX_PENDING_COMMANDS + 1u,
                            DTAI_DEFAULT_TIMEOUT_MICROS) ==
             DTAI_STATUS_INVALID_ARGUMENT,
         "large pending bound");
  Expect(dtai_session_start(1u, 0u) == DTAI_STATUS_INVALID_ARGUMENT,
         "zero timeout");
  Expect(dtai_session_start(1u, DTAI_MAX_TIMEOUT_MICROS + 1u) ==
             DTAI_STATUS_INVALID_ARGUMENT,
         "large timeout");
  int32_t thread_status = DTAI_STATUS_OK;
  std::thread worker([&thread_status]() {
    thread_status = dtai_session_start(1u, DTAI_DEFAULT_TIMEOUT_MICROS);
  });
  worker.join();
  Expect(thread_status == DTAI_STATUS_WRONG_THREAD, "start main-thread guard");
  Expect(dtai_debug_summary(nullptr, nullptr, nullptr, nullptr, nullptr,
                            nullptr, nullptr, nullptr,
                            nullptr) == DTAI_STATUS_INVALID_ARGUMENT,
         "null summary outputs");
}

void TestBoundedQueueAndGeneration() {
  Expect(dtai_session_start(2u, DTAI_DEFAULT_TIMEOUT_MICROS) == DTAI_STATUS_OK,
         "session start");
  Expect(dtai_session_start(2u, DTAI_DEFAULT_TIMEOUT_MICROS) ==
             DTAI_STATUS_ALREADY_STARTED,
         "duplicate session");
  Expect(
      dtai_debug_enqueue_action(DTAI_ACTION_NEW_WINDOW) == DTAI_STATUS_DISABLED,
      "disabled admission");
  Expect(dtai_session_set_enabled(2u) == DTAI_STATUS_INVALID_ARGUMENT,
         "invalid enabled value");
  Expect(dtai_session_set_enabled(1u) == DTAI_STATUS_OK, "enable session");
  const uint64_t enabled_generation = ReadSummary().generation;
  Expect(enabled_generation > 0u, "positive enabled generation");
  Expect(dtai_debug_enqueue_action(99u) == DTAI_STATUS_INVALID_ARGUMENT,
         "closed action enum");
  Expect(dtai_debug_enqueue_action(DTAI_ACTION_NEW_WINDOW) == DTAI_STATUS_OK,
         "enqueue new window");
  Expect(dtai_debug_enqueue_action(DTAI_ACTION_NEW_TAB) == DTAI_STATUS_OK,
         "enqueue new tab");
  Expect(dtai_debug_enqueue_action(DTAI_ACTION_TOGGLE_QUICK_TERMINAL) ==
             DTAI_STATUS_RESOURCE_EXHAUSTED,
         "fixed-capacity queue");
  Summary full = ReadSummary();
  Expect(full.queued == 2u && full.pending == 2u && full.accepted == 2u &&
             full.rejected == 2u && full.started == 1u && full.enabled == 1u,
         "bounded summary counts");

  uint64_t operation = 0;
  uint64_t generation = 0;
  uint32_t action = 0;
  Expect(
      dtai_take_command(&operation, &generation, &action) == DTAI_STATUS_OK &&
          operation > 0u && generation == enabled_generation &&
          action == DTAI_ACTION_NEW_WINDOW,
      "FIFO first command");
  Expect(dtai_complete_command(operation + 1u, generation,
                               DTAI_COMMAND_COMPLETED) ==
             DTAI_STATUS_INVALID_ARGUMENT,
         "untaken command cannot complete");
  Expect(dtai_complete_command(operation, generation, 99u) ==
             DTAI_STATUS_INVALID_ARGUMENT,
         "closed disposition enum");
  Expect(dtai_complete_command(operation, generation, DTAI_COMMAND_COMPLETED) ==
             DTAI_STATUS_OK,
         "complete accepted command");
  Expect(dtai_complete_command(operation, generation, DTAI_COMMAND_COMPLETED) ==
             DTAI_STATUS_NOT_FOUND,
         "duplicate completion rejected");

  uint64_t second_operation = 0;
  uint64_t second_generation = 0;
  uint32_t second_action = 0;
  Expect(dtai_take_command(&second_operation, &second_generation,
                           &second_action) == DTAI_STATUS_OK &&
             second_action == DTAI_ACTION_NEW_TAB,
         "FIFO second command");
  Expect(dtai_take_command(&operation, &generation, &action) ==
             DTAI_STATUS_NOT_FOUND,
         "taken queue is empty");
  Expect(dtai_session_set_enabled(0u) == DTAI_STATUS_OK,
         "disable drains pending");
  Summary disabled = ReadSummary();
  Expect(disabled.generation > enabled_generation && disabled.queued == 0u &&
             disabled.pending == 0u && disabled.resolved == 2u &&
             disabled.enabled == 0u,
         "disable is atomic and generation-bound");
  Expect(dtai_complete_command(second_operation, second_generation,
                               DTAI_COMMAND_COMPLETED) ==
             DTAI_STATUS_STALE_GENERATION,
         "stale completion rejected");
  Expect(dtai_session_shutdown() == DTAI_STATUS_OK, "shutdown");
  Expect(dtai_session_shutdown() == DTAI_STATUS_OK, "idempotent shutdown");
}

void TestTimeoutAndRestart() {
  Expect(dtai_session_start(1u, 1000u) == DTAI_STATUS_OK,
         "restart with bounded timeout");
  Expect(dtai_session_set_enabled(1u) == DTAI_STATUS_OK,
         "enable restarted session");
  Expect(dtai_debug_enqueue_action(DTAI_ACTION_TOGGLE_QUICK_TERMINAL) ==
             DTAI_STATUS_OK,
         "enqueue expiring command");
  usleep(50000u);
  Summary expired = ReadSummary();
  Expect(expired.queued == 0u && expired.pending == 0u &&
             expired.accepted == 1u && expired.resolved == 1u &&
             expired.timed_out == 1u,
         "timeout removes all ownership");
  uint64_t operation = 0;
  uint64_t generation = 0;
  uint32_t action = 0;
  Expect(dtai_take_command(&operation, &generation, &action) ==
             DTAI_STATUS_NOT_FOUND,
         "expired command cannot be taken");
  Expect(dtai_session_shutdown() == DTAI_STATUS_OK, "final shutdown");
  Expect(dtai_debug_enqueue_action(DTAI_ACTION_NEW_WINDOW) ==
             DTAI_STATUS_NOT_INITIALIZED,
         "post-shutdown admission rejected");
}

}  // namespace

int main() {
  TestValidationAndThreadBoundary();
  TestBoundedQueueAndGeneration();
  TestTimeoutAndRestart();
  if (g_failures != 0) {
    fprintf(stderr, "%d terminal App Intents capability test(s) failed\n",
            g_failures);
    return 1;
  }
  printf("terminal App Intents native capability tests passed\n");
  return 0;
}
