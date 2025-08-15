#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

#define CLR_RESET   "\033[0m"
#define CLR_RED     "\033[1;31m"
#define CLR_GREEN   "\033[1;32m"
#define CLR_YELLOW  "\033[1;33m"
#define CLR_BLUE    "\033[1;34m"
#define CLR_CYAN    "\033[1;36m"
#define CLR_DIM     "\033[2m"

static void clear_screen(void) {
    // 清屏并移动光标到左上角
    printf("\033[2J\033[H");
}

static void press_enter(void) {
    printf(CLR_DIM "\n(按 Enter 继续)" CLR_RESET);
    int c;
    while ((c = getchar()) != '\n' && c != EOF) {}
}

static void draw_board(const char b[9]) {
    clear_screen();
    printf(CLR_CYAN "==== 井 字 棋 ====\n\n" CLR_RESET);

    for (int r = 0; r < 3; ++r) {
        for (int c = 0; c < 3; ++c) {
            int i = r * 3 + c;
            char ch = b[i];
            const char *color = CLR_YELLOW; // 空位编号/默认

            if (ch == 'X') color = CLR_GREEN;
            else if (ch == 'O') color = CLR_RED;
            else color = CLR_YELLOW;

            printf("  %s%c%s  ", color, ch, CLR_RESET);
            if (c < 2) printf("|");
        }
        printf("\n");
        if (r < 2) {
            printf("-------+-------+-------\n");
        }
    }
    printf("\n");
}

static char winner(const char b[9]) {
    const int L[8][3] = {
        {0,1,2},{3,4,5},{6,7,8},
        {0,3,6},{1,4,7},{2,5,8},
        {0,4,8},{2,4,6}
    };
    for (int i = 0; i < 8; ++i) {
        int a = L[i][0], c = L[i][1], d = L[i][2];
        if (b[a] != ' ' && b[a] == b[c] && b[c] == b[d]) return b[a];
    }
    // 是否还有空位
    for (int i = 0; i < 9; ++i) if (b[i] == ' ') return 0;
    return 'D'; // 平局
}

static int read_move(const char b[9]) {
    // 读取 1..9 的合法落子位置（转换为 0..8）
    while (1) {
        printf("请输入落子位置 " CLR_YELLOW "[1-9]" CLR_RESET "（小键盘风格，1 左下，9 右上）：");
        int mv = -1;
        int ok = scanf("%d", &mv);
        // 吃掉尾部字符直到换行
        int ch;
        while ((ch = getchar()) != '\n' && ch != EOF) {}
        if (ok == 1 && mv >= 1 && mv <= 9) {
            int idx = mv - 1;
            if (b[idx] == ' ') return idx;
            printf(CLR_RED "该位置已被占用！\n" CLR_RESET);
        } else {
            printf(CLR_RED "输入无效，请输入 1-9 的数字。\n" CLR_RESET);
        }
    }
}

// 简单 AI：能赢先赢、能挡先挡、中心>角>边
static int try_win_or_block(char b[9], char me) {
    const int L[8][3] = {
        {0,1,2},{3,4,5},{6,7,8},
        {0,3,6},{1,4,7},{2,5,8},
        {0,4,8},{2,4,6}
    };
    // 先尝试：我能赢？
    for (int i = 0; i < 8; ++i) {
        int a=L[i][0], c=L[i][1], d=L[i][2];
        if (b[a]==' ' && b[c]==me && b[d]==me) return a;
        if (b[c]==' ' && b[a]==me && b[d]==me) return c;
        if (b[d]==' ' && b[a]==me && b[c]==me) return d;
    }
    // 再尝试：对手要赢我就挡
    char opp = (me=='X') ? 'O' : 'X';
    for (int i = 0; i < 8; ++i) {
        int a=L[i][0], c=L[i][1], d=L[i][2];
        if (b[a]==' ' && b[c]==opp && b[d]==opp) return a;
        if (b[c]==' ' && b[a]==opp && b[d]==opp) return c;
        if (b[d]==' ' && b[a]==opp && b[c]==opp) return d;
    }
    return -1;
}

static int ai_move(const char b_in[9], char me) {
    char b[9];
    for (int i = 0; i < 9; ++i) b[i] = b_in[i];

    int m = try_win_or_block(b, me);
    if (m >= 0) return m;

    // 中心
    if (b[4] == ' ') return 4;
    // 角
    const int corners[4] = {0,2,6,8};
    for (int i = 0; i < 4; ++i) if (b[corners[i]] == ' ') return corners[i];
    // 边
    const int edges[4] = {1,3,5,7};
    for (int i = 0; i < 4; ++i) if (b[edges[i]] == ' ') return edges[i];

    return 0; // 理论到不了
}

int main(void) {
    while (1) {
        char board[9];
        for (int i = 0; i < 9; ++i) board[i] = ' ';

        int mode = 0;
        while (mode != 1 && mode != 2) {
            clear_screen();
            printf(CLR_CYAN "==== 井 字 棋 ====\n\n" CLR_RESET);
            printf("选择模式：\n");
            printf("  1) 玩家 VS 玩家\n");
            printf("  2) 玩家 VS 电脑\n\n");
            printf("请输入 1 或 2: ");
            if (scanf("%d", &mode) != 1) { mode = 0; }
            int ch; while ((ch = getchar()) != '\n' && ch != EOF) {}
        }

        char turn = 'X'; // X 先手
        char win = 0;
        while (!(win = winner(board))) {
            draw_board(board);
            printf("轮到 %s%c%s 落子。\n",
                   (turn=='X'?CLR_GREEN:CLR_RED), turn, CLR_RESET);

            int mv = -1;
            if (mode == 2 && turn == 'O') {
                mv = ai_move(board, 'O');
                printf(CLR_DIM "(电脑已选择: %d)\n" CLR_RESET, mv + 1);
            } else {
                mv = read_move(board);
            }

            board[mv] = turn;
            turn = (turn == 'X') ? 'O' : 'X';
        }

        draw_board(board);
        if (win == 'D') {
            printf(CLR_YELLOW "平局！\n" CLR_RESET);
        } else {
            printf("恭喜 %s%c%s 获胜！\n",
                   (win=='X'?CLR_GREEN:CLR_RED), win, CLR_RESET);
        }

        printf("\n再来一局？(y/n): ");
        int c = getchar();
        int ch; while ((ch = getchar()) != '\n' && ch != EOF) {}
        if (c != 'y' && c != 'Y') break;
    }

    printf("感谢游玩！\n");
    return 0;
}
