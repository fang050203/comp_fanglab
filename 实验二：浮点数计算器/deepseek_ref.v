// IEEE 754单精度浮点加减法运算器
// 支持四状态流水线处理：输入解析、对阶、计算、规格化
module fp_adder (
    input         rst,       // 异步复位，高有效
    input         clk,       // 系统时钟
    input         start,     // 启动信号，高脉冲触发计算
    input         op,        // 操作类型：0-加法，1-减法
    input  [31:0] A,         // 被操作数（IEEE754单精度）
    input  [31:0] B,         // 操作数（IEEE754单精度）
    output        ready,     // 就绪信号，高电平可接收新输入
    output [31:0] C          // 计算结果（IEEE754单精度）
);

// ================== 状态机定义（四状态） ==================
localparam IDLE     = 4'b0001;  // 空闲状态
localparam PARSE    = 4'b0010;  // 输入解析阶段
localparam ALIGN    = 4'b0100;  // 对阶处理阶段
localparam CALC     = 4'b1000;  // 计算阶段

reg [3:0] current_state;       // 当前状态寄存器
reg [3:0] next_state;          // 次态寄存器

// ================== 浮点数分解寄存器 ==================
reg        sign_A, sign_B;     // 符号位（1:负，0:正）
reg [7:0]  exp_A, exp_B;       // 指数部分（8位，偏移127）
reg [23:0] mantissa_A, mantissa_B; // 尾数（23位显式 + 1位隐式）

// ================== 中间计算寄存器 ==================
reg [7:0]  exp_diff;          // 指数差值（用于对阶）
reg [7:0]  final_exp;         // 最终指数（取较大指数）
reg [24:0] aligned_A, aligned_B; // 对齐后的尾数（含保护位）
reg [24:0] sum_mantissa;      // 尾数和（25位：1位进位+24位有效）
reg        result_sign;       // 结果符号位

// ================== 输出寄存器 ==================
reg [31:0] C_reg;             // 结果输出寄存器
reg        ready_reg;         // 就绪信号寄存器

// ================== 状态机控制逻辑 ==================
// 状态寄存器更新（时序逻辑）
always @(posedge clk or posedge rst) begin
    if (rst) current_state <= IDLE;
    else     current_state <= next_state;
end

// 次态生成逻辑（组合逻辑）
always @(*) begin
    case (current_state)
        IDLE:  next_state = (start) ? PARSE : IDLE;  // 启动信号触发
        PARSE: next_state = ALIGN;                   // 固定进入对阶
        ALIGN: next_state = CALC;                    // 进入计算阶段
        CALC:  next_state = IDLE;                    // 完成计算回到空闲
        default: next_state = IDLE;
    endcase
end

// ================== 数据通路处理 ==================
always @(posedge clk or posedge rst) begin
    if (rst) begin  // 复位初始化
        {sign_A, exp_A, mantissa_A} <= {1'b0, 8'd0, 24'd0};
        {sign_B, exp_B, mantissa_B} <= {1'b0, 8'd0, 24'd0};
        exp_diff     <= 8'd0;
        aligned_A    <= 25'd0;
        aligned_B    <= 25'd0;
        sum_mantissa <= 25'd0;
        final_exp    <= 8'd0;
        result_sign  <= 1'b0;
        C_reg        <= 32'd0;
        ready_reg    <= 1'b1;  // 初始就绪
    end else begin
        case (current_state)
            // IDLE状态：等待启动信号
            IDLE: begin
                ready_reg <= 1'b1;  // 输出就绪
                if (start) begin
                    ready_reg <= 1'b0;  // 进入工作状态
                end
            end
            
            // PARSE状态：分解输入数据
            PARSE: begin
                // 解析A的符号、指数、尾数
                sign_A     <= A[31];             // 符号位
                exp_A      <= A[30:23];          // 指数部分
                mantissa_A <= {1'b1, A[22:0]};   // 补充隐含的1.xxx形式
                
                // 解析B的符号（减法时取反）
                sign_B     <= op ? ~B[31] : B[31]; // 减法时符号取反
                exp_B      <= B[30:23];
                mantissa_B <= {1'b1, B[22:0]};
            end
            
            // ALIGN状态：对阶处理
            ALIGN: begin
                // 计算指数差值
                exp_diff <= (exp_A >= exp_B) ? (exp_A - exp_B) : (exp_B - exp_A);
                
                // 对齐尾数（小指数向大指数对齐）
                if (exp_A >= exp_B) begin
                    final_exp <= exp_A;
                    aligned_A <= mantissa_A;             // 大指数保持不变
                    aligned_B <= mantissa_B >> exp_diff; // 小指数右移对齐
                end else begin
                    final_exp <= exp_B;
                    aligned_A <= mantissa_A >> exp_diff;  // 右移对齐
                    aligned_B <= mantissa_B;
                end
            end
            
            // CALC状态：尾数运算与规格化
            CALC: begin
                // 符号相同执行加法，否则执行减法
                if (sign_A == sign_B) begin
                    sum_mantissa <= aligned_A + aligned_B; // 同号相加
                    result_sign  <= sign_A;
                end else begin
                    // 异号比较尾数大小
                    if (aligned_A >= aligned_B) begin
                        sum_mantissa <= aligned_A - aligned_B;
                        result_sign  <= sign_A;
                    end else begin
                        sum_mantissa <= aligned_B - aligned_A;
                        result_sign  <= sign_B;
                    end
                end
                
                // ---------- 规格化处理 ----------
                // 情况1：加法溢出（最高位为1）
                if (sum_mantissa[24]) begin 
                    sum_mantissa <= sum_mantissa >> 1; // 右移一位
                    final_exp    <= final_exp + 1;     // 指数加1
                end 
                // 情况2：前导零需要左移
                else begin
                    // 循环左移直到最高位为1或指数为0
                    while (~sum_mantissa[23] && (final_exp > 0)) begin
                        sum_mantissa <= sum_mantissa << 1;
                        final_exp    <= final_exp - 1;
                    end
                end
                
                // 合成最终结果（截断保护位）
                C_reg <= {result_sign, final_exp, sum_mantissa[22:0]};
                ready_reg <= 1'b1;  // 计算完成
            end
            
            default: begin
                ready_reg <= 1'b1;
            end
        endcase
    end
end

// ================== 输出信号连接 ==================
assign ready = ready_reg;
assign C = C_reg;

endmodule
