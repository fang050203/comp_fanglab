#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <termios.h>
#include <time.h>
#include <string.h>

#define W 10
#define H 20

#define CLR_RESET   "\033[0m"
#define CLR_RED     "\033[41m"
#define CLR_GREEN   "\033[42m"
#define CLR_YELLOW  "\033[43m"
#define CLR_BLUE    "\033[44m"
#define CLR_MAGENTA "\033[45m"
#define CLR_CYAN    "\033[46m"
#define CLR_WHITE   "\033[47m"

struct termios orig_termios;

void disable_raw_mode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
}

void enable_raw_mode() {
    tcgetattr(STDIN_FILENO, &orig_termios);
    atexit(disable_raw_mode);

    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 1;
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
}

int kbhit() {
    unsigned char ch;
    int n = read(STDIN_FILENO, &ch, 1);
    if (n > 0) {
        ungetc(ch, stdin);
        return 1;
    }
    return 0;
}

int getch() {
    unsigned char ch;
    if (read(STDIN_FILENO, &ch, 1) == 1) return ch;
    return -1;
}

// 7 种方块
const int shapes[7][4] = {
    {0x0F00,0x2222,0x0F00,0x2222}, // I
    {0x44C0,0x8E00,0x6440,0x0E20}, // J
    {0x4460,0x0E80,0xC440,0x2E00}, // L
    {0x6C00,0x4620,0x6C00,0x4620}, // S
    {0xC600,0x2640,0xC600,0x2640}, // Z
    {0x4E00,0x4640,0x0E40,0x4C40}, // T
    {0x6600,0x6600,0x6600,0x6600}  // O
};

const char* colors[7] = {
    CLR_CYAN, CLR_BLUE, CLR_YELLOW, CLR_GREEN, CLR_RED, CLR_MAGENTA, CLR_WHITE
};

int board[H][W] = {0};

int cur_shape, cur_rot, cur_x, cur_y;
int score = 0;

void draw_block(int y, int x, const char *color) {
    printf("\033[%d;%dH%s  %s", y+1, x*2+1, color, CLR_RESET);
}

void draw_board() {
    printf("\033[H");
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            if (board[y][x]) draw_block(y, x, colors[board[y][x]-1]);
            else printf("  ");
        }
        printf("\n");
    }
    printf("分数: %d\n", score);
}

int check_collision(int shape, int rot, int x, int y) {
    int data = shapes[shape][rot];
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
            if (data & (0x8000 >> (i*4+j))) {
                int nx = x + j;
                int ny = y + i;
                if (nx < 0 || nx >= W || ny < 0 || ny >= H) return 1;
                if (board[ny][nx]) return 1;
            }
    return 0;
}

void place_shape() {
    int data = shapes[cur_shape][cur_rot];
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
            if (data & (0x8000 >> (i*4+j))) {
                board[cur_y+i][cur_x+j] = cur_shape+1;
            }
}

void clear_lines() {
    for (int y = H-1; y >= 0; y--) {
        int full = 1;
        for (int x = 0; x < W; x++)
            if (!board[y][x]) { full = 0; break; }
        if (full) {
            score += 100;
            for (int yy = y; yy > 0; yy--)
                memcpy(board[yy], board[yy-1], sizeof(board[yy]));
            memset(board[0], 0, sizeof(board[0]));
            y++;
        }
    }
}

void new_shape() {
    cur_shape = rand()%7;
    cur_rot = 0;
    cur_x = W/2 - 2;
    cur_y = 0;
    if (check_collision(cur_shape, cur_rot, cur_x, cur_y)) {
        printf("\033[H游戏结束! 最终分数: %d\n", score);
        exit(0);
    }
}

void draw_current() {
    int data = shapes[cur_shape][cur_rot];
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++)
            if (data & (0x8000 >> (i*4+j))) {
                draw_block(cur_y+i, cur_x+j, colors[cur_shape]);
            }
}

int main() {
    srand(time(NULL));
    enable_raw_mode();
    printf("\033[2J");

    new_shape();
    long tick = 0;
    while (1) {
        usleep(5000);
        if (++tick % 10 == 0) { // 下落速度
            if (!check_collision(cur_shape, cur_rot, cur_x, cur_y+1)) cur_y++;
            else {
                place_shape();
                clear_lines();
                new_shape();
            }
        }

        // 输入处理
        if (kbhit()) {
            int c = getch();
            if (c == '\033') { // ESC 序列
                getch(); // [
                c = getch();
                if (c == 'A') { // UP
                    int nr = (cur_rot+1)%4;
                    if (!check_collision(cur_shape, nr, cur_x, cur_y)) cur_rot = nr;
                } else if (c == 'B') { // DOWN
                    if (!check_collision(cur_shape, cur_rot, cur_x, cur_y+1)) cur_y++;
                } else if (c == 'C') { // RIGHT
                    if (!check_collision(cur_shape, cur_rot, cur_x+1, cur_y)) cur_x++;
                } else if (c == 'D') { // LEFT
                    if (!check_collision(cur_shape, cur_rot, cur_x-1, cur_y)) cur_x--;
                }
            } else if (c == ' ') { // 空格直接落到底
                while (!check_collision(cur_shape, cur_rot, cur_x, cur_y+1)) cur_y++;
            } else if (c == 'q') {
                break;
            }
        }

        draw_board();
        draw_current();
        fflush(stdout);
    }

    return 0;
}
