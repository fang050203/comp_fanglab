`timescale 1ns / 1ps

`include "defines.vh"

// 主存地址有效位宽：15bit
// Cache容量：127B
// Cache块大小：256bit (8*32bit)
// Cache块个数：?

module ICache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active
    // Interface to CPU
    input  wire         inst_rreq,      // 来自CPU的取指请求
    input  wire [31:0]  inst_addr,      // 来自CPU的取指地址
    output reg          inst_valid,     // 输出给CPU的指令有效信号（读指令命中）
    output reg  [31:0]  inst_out,       // 输出给CPU的指令
    // Interface to Read Bus
    input  wire         dev_rrdy,       // 主存就绪信号（高电平表示主存可接收ICache的读请求）
    output reg  [ 3:0]  cpu_ren,        // 输出给主存的读使能信号
    output reg  [31:0]  cpu_raddr,      // 输出给主存的读地址
    input  wire         dev_rvalid,     // 来自主存的数据有效信号
    input  wire [255:0] dev_rdata       // 来自主存的读数据
);

`ifdef ENABLE_ICACHE    /******** 不要修改此行代码 ********/

    // ICache存储体
    //reg [7:0] valid;          // 有效位
    //reg [7:0] tag  [10:0];     // 块标签
    //reg [7:0] data [127:0];     // 数据块

    reg [266:0]cache_set_0;
    reg [266:0]cache_set_1;
    reg [266:0]cache_set_2;
    reg [266:0]cache_set_3;
    //reg [266:0]cache_set_4;
    //reg [266:0]cache_set_5;
    //reg [266:0]cache_set_6;
    //reg [266:0]cache_set_7;
    // TODO: 定义ICache状态机的状态及状态变量

    localparam IDLE=2'b00;
    localparam TAG_CHK=2'b01;
    localparam REFILL=2'b10;
    reg [1:0] state,state_n;    //状态变量以及状态机 

    wire cache_we=dev_rvalid;     // ICache存储体的写使能信号
    wire [266:0] cache_line_w={dev_rvalid,tag_from_cpu,dev_rdata};     // 待写入ICache的Cache行
    reg [266:0] cache_line_r;                  // 从ICache读出的Cache行

    wire       valid_bit      = cache_line_r[266];    // Cache行的有效位
    wire [9:0] tag_from_cache = cache_line_r[265:256];    // Cache行的TAG

    // 主存地址分解
    wire [4:0] offset       = inst_addr[4:0];
    wire [9:0]tag_from_cpu  = inst_addr[14:5]; 

    wire hit = valid_bit & (tag_from_cpu==tag_from_cache) & (state==TAG_CHK);

    always @(*) begin
        inst_valid = hit;
        case(offset[4:2])
            3'b000:inst_out <=cache_line_r[31:0];
            3'b001:inst_out <=cache_line_r[63:32];
            3'b010:inst_out <=cache_line_r[95:64];
            3'b011:inst_out <=cache_line_r[127:96];
            3'b100:inst_out <=cache_line_r[159:128];
            3'b101:inst_out <=cache_line_r[191:160];
            3'b110:inst_out <=cache_line_r[223:192];
            3'b111:inst_out <=cache_line_r[255:224];
        endcase
    end

    // TODO: 编写状态机现态的更新逻辑
    always @(posedge cpu_clk or posedge cpu_rst) begin
        state<=cpu_rst?IDLE:state_n;
    end

    // TODO: 编写状态机的状态转移逻辑
    always @(*) begin
        case (state)
            IDLE:    state_n=inst_rreq?TAG_CHK:IDLE;
            TAG_CHK:begin
                    if(dev_rrdy)state_n=hit?IDLE:REFILL;
                    else state_n=TAG_CHK;
                end
            REFILL:state_n=dev_rvalid?TAG_CHK:REFILL;
            default: state_n=IDLE;
        endcase
    end

    // TODO: 生成状态机的输出信号
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cpu_ren<=4'h0;
            cpu_raddr<=32'd0;
        end else begin
            case (state)
                IDLE:begin
                    cpu_ren<=4'h0;
                    cpu_raddr<=cpu_raddr;
                end
                TAG_CHK:begin
                if(dev_rrdy) begin
                    cpu_ren<={4{~inst_valid}};
                    cpu_raddr<=inst_valid? cpu_raddr:{inst_addr[31:5],5'b0};//这里有疑问
                    end
                else begin
                    cpu_ren<=4'h0;
                    cpu_raddr<=cpu_raddr;
                end
                end
                REFILL:begin
                    cpu_ren<=4'h0;
                    cpu_raddr<=cpu_raddr;
                end
                default: begin
                    cpu_ren<=4'h0;
                    cpu_raddr<=cpu_raddr;
                end
            endcase
        end
    end

    // TODO: 编写更新Cache有效位、块标签、数据块的逻辑
    always@(posedge cpu_clk or posedge cpu_rst)begin
        if(cache_we)begin
            case(ran_num)
                2'b00:begin
                    cache_set_0 <=cache_line_w;
                    cache_line_r <= cache_line_w;
                end
                2'b01:begin
                    cache_set_1 <=cache_line_w;
                    cache_line_r <= cache_line_w;
                end
                2'b10:begin
                    cache_set_2 <=cache_line_w;
                    cache_line_r <= cache_line_w;
                end
                2'b11:begin
                    cache_set_3 <=cache_line_w;
                    cache_line_r <= cache_line_w;
                end
            endcase
        end
        else begin
            if(cpu_rst)begin
                cache_set_0 <=267'b0;
                cache_set_1 <=267'b0;
                cache_set_2 <=267'b0;
                cache_set_3 <=267'b0;
                cache_line_r <=140'b0;
            end
            else if(cache_set_0[266] & (cache_set_0[265:256]==tag_from_cpu))begin
                cache_line_r <=cache_set_0;
            end
            else if(cache_set_1[266] & (cache_set_1[265:256]==tag_from_cpu))begin
                cache_line_r <=cache_set_1;
            end
            else if(cache_set_2[266] & (cache_set_2[265:256]==tag_from_cpu))begin
                cache_line_r <=cache_set_2;
            end
            else if(cache_set_3[266] & (cache_set_3[265:256]==tag_from_cpu))begin
                cache_line_r <=cache_set_3;
            end
            else begin
                cache_line_r <= cache_line_r;
            end
        end
    end



    reg [1:0]ran_num;
    wire feedback;
    assign feedback = ^(ran_num & 2'b10);
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            ran_num <= 2'b11;
        end else begin
            // 右移并插入反馈位
            ran_num <= {feedback, ran_num[1]};
        end
    end

    /******** 不要修改以下代码 ********/
`else

    localparam IDLE  = 2'b00;
    localparam STAT0 = 2'b01;
    localparam STAT1 = 2'b11;
    reg [1:0] state, nstat;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        state <= cpu_rst ? IDLE : nstat;
    end

    always @(*) begin
        case (state)
            IDLE:    nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : IDLE;
            STAT0:   nstat = dev_rrdy ? STAT1 : STAT0;
            STAT1:   nstat = dev_rvalid ? IDLE : STAT1;
            default: nstat = IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            inst_valid <= 1'b0;
            cpu_ren    <= 4'h0;
        end else begin
            case (state)
                IDLE: begin
                    inst_valid <= 1'b0;
                    cpu_ren    <= (inst_rreq & dev_rrdy) ? 4'hF : 4'h0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                end
                STAT0: begin
                    cpu_ren    <= dev_rrdy ? 4'hF : 4'h0;
                end
                STAT1: begin
                    cpu_ren    <= 4'h0;
                    inst_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    inst_out   <= dev_rvalid ? dev_rdata[31:0] : 32'h0;
                end
                default: begin
                    inst_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule