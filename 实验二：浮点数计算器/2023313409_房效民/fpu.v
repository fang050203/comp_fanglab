`timescale 1ns / 1ps

module fpu(
    input  wire         rst,    // 高电平复位
    input  wire         clk,
    input  wire         start,  // start为1时，开始计算
    input  wire         op,     // 为0时加, 为1时减
    input  wire [31:0]  A,      // 左操作数
    input  wire [31:0]  B,      // 右操作数
    output reg          ready,  // 复位或计算完成时ready为1，检测到start为1时置为0
    output wire [31:0]  C       // 计算结果
);



localparam IDLE     = 4'b0000;    // 空闲状态
localparam Pre      =4'b0001;    //分解
localparam S1    = 4'b0010;     // 求阶差
localparam S2    = 4'b0011;     // 对阶
localparam S3     = 4'b0100;      // 尾数运算
localparam S4     = 4'b0101;     // 规格化
localparam fin     = 4'b0110;     // 结束，输出结果

reg [3:0] state;               // 当前状态寄存器
reg [3:0] next_state;          // 次态寄存器



reg        sign_A, sign_B;      // 符号位（1:负，0:正）
reg [7:0]  exp_A, exp_B;        // 指数部分（8位，偏移127）
reg [23:0] m_A, m_B;            // 尾数（23位显式 + 1位隐式）


reg [7:0]  exp_diff;            // 指数差值（用于对阶）
reg [7:0]  final_exp;           // 最终指数（取较大指数）
reg [24:0] am_A, am_B;         // 对齐后的尾数（含保护位）
reg [24:0] sum;               // 尾数和（25位：1位进位+24位有效）
reg        result_sign;         // 结果符号位


reg [31:0] C_reg;             // 结果输出寄存器

// 状态更新
always @(posedge clk or posedge rst) begin
    if (rst) state <= IDLE;
    else     state <= next_state;
end

// 次态生成
always @(*) begin
    case (state)
        IDLE:  next_state = (start | ready==1'b0) ? Pre : IDLE;  // 启动信号触发
        Pre: next_state = S1;
        S1: next_state = S2;                   
        S2: next_state = S3;   
        S3:  next_state = S4;
        S4:  begin
            if(sum[23] || (final_exp == 0))begin
                next_state =fin;      //当高位为1或者阶码为0则认为计算完成，进入下一个阶段
            end
            else begin
                next_state = S4;     //若未完成，则一直进行
            end
        end                    
        fin:next_state = IDLE;
        default: next_state = IDLE;
    endcase
end


always @(posedge clk or posedge rst) begin
    if (rst) begin  // 复位初始化
        {sign_A, exp_A, m_A} <= {1'b0, 8'd0, 24'd0};
        {sign_B, exp_B, m_B} <= {1'b0, 8'd0, 24'd0};
        exp_diff     <= 8'd0;
        am_A    <= 25'd0;
        am_B    <= 25'd0;
        sum <= 25'd0;                         //复位信号进行初始化
        final_exp    <= 8'd0;
        result_sign  <= 1'b0;
        C_reg        <= 32'd0;
    end else begin
        case (state)
            // IDLE状态：等待启动信号
            IDLE: begin
                ready <= 1'b1;  // 输出就绪
                if (start) begin
                    ready <= 1'b0;  // 进入工作状态
                end
            end

            Pre:begin   //分解输入信号
                // 解析A的符号、指数、尾数
                sign_A     <= A[31];             // 符号位
                exp_A      <= (A[30:23]==8'b0)?8'd1:A[30:23];          // 指数部分处理，包括非规格化数
                m_A <= (A[30:23]==8'b0)?{1'b0, A[22:0]}:{1'b1, A[22:0]};   // 补充隐含的1.xxx形式，而非规格化数则前加0
                
                // 解析B的符号（减法时取反）
                sign_B     <= op ? ~B[31] : B[31]; 
                //关于减法符号取反
                //在后续计算阶段，如果两个数符号相同，则说明原始计算式为一个正数减去一个负数或者一个负数减去一个正数
                //所以两者直接当做加法运算即可，如果后续阶段符号不同，则为一个正数减一个正数或者一个负数减一个负数，
                //所以当做减法运算
                exp_B      <= (B[30:23]==8'b0)?8'd1:B[30:23];     //同上
                m_B <= (B[30:23]==8'b0)?{1'b0, B[22:0]}:{1'b1, B[22:0]};    //同上
            end

            // S1状态：求阶差
            S1: begin
                // 计算指数差值
                exp_diff <= (exp_A >= exp_B) ? (exp_A - exp_B) : (exp_B - exp_A);
            end
            
            // S2状态：对阶处理
            S2: begin
                // 对齐尾数（小指数向大指数对齐）
                if (exp_A >= exp_B) begin
                    final_exp <= exp_A;
                    am_A <= m_A;             // 大指数保持不变
                    am_B <= m_B >> exp_diff; // 小指数右移对齐
                end else begin
                    final_exp <= exp_B;
                    am_A <= m_A >> exp_diff;  // 右移对齐
                    am_B <= m_B;
                end
            end
            // S3状态：尾数运算
            S3: begin
                // 符号相同执行加法，否则执行减法
                if (sign_A == sign_B) begin
                    sum <= am_A + am_B; 
                    result_sign  <= sign_A;
                end else begin
                    // 异号比较尾数大小//相当于执行减法
                    if (am_A >= am_B) begin
                        sum <= am_A - am_B;
                        result_sign  <= sign_A;
                    end else begin
                        sum <= am_B - am_A;
                        result_sign  <= sign_B;
                    end
                end
                
            end
            
            S4:begin    //规格化
                if (sum[24]) begin   //处理加法溢出 
                    sum <= sum >> 1; // 右移一位
                    final_exp    <= final_exp + 1;     // 指数加1
                end 
                else begin
                    if(~sum[23])begin     //需要进行左规处理
                        if(final_exp > 1'b1)begin
                            sum <= sum << 1;
                            final_exp    <= final_exp - 1;
                        end else if(final_exp == 1'b1)begin
                            //此处为特殊情况，如果继续左规，可能出现
                            //sum[23]等于1，而阶码等于0的情况，这不是非规格化数，
                            //这其实是两个规格化数运算得到非规格化数的结果，所以只减阶码不左移
                            final_exp    <= final_exp - 1;
                        end
                    end
                end
            end
            fin:begin
                C_reg <= {result_sign, final_exp, sum[22:0]};    //输出结果
                ready <= 1'b1;  
            end
            default: begin
                ready <= 1'b1;
            end
        endcase
    end
end


assign C=C_reg;


endmodule
