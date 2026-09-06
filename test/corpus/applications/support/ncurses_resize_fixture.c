#include <locale.h>
#include <ncurses.h>
#include <stdlib.h>

static void draw_fixture(const char *event) {
  int rows = 0;
  int columns = 0;
  getmaxyx(stdscr, rows, columns);
  erase();
  box(stdscr, 0, 0);
  mvprintw(1, 2, "DART_MATRIX_NCURSES");
  mvprintw(2, 2, "rows=%d columns=%d", rows, columns);
  mvprintw(3, 2, "event=%s", event);
  mvprintw(4, 2, "press q to exit");
  refresh();
}

int main(void) {
  if (setlocale(LC_ALL, "") == NULL) {
    return 2;
  }
  if (initscr() == NULL) {
    return 3;
  }
  if (cbreak() == ERR || noecho() == ERR || keypad(stdscr, TRUE) == ERR) {
    endwin();
    return 4;
  }
  curs_set(1);
  draw_fixture("initial");
  for (;;) {
    const int input = getch();
    if (input == 'q') {
      break;
    }
    if (input == KEY_RESIZE) {
      draw_fixture("resize");
    } else if (input == ERR) {
      endwin();
      return 5;
    } else {
      draw_fixture("input");
    }
  }
  if (endwin() == ERR) {
    return 6;
  }
  return 0;
}
