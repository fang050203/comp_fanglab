// 定义仿真时间单位1ns，精度1ps
`timescale 1ns / 1ps

// 数据缓存模块（DCache）
module DCache(
    // 时钟和复位
    input  wire         cpu_clk,    // 主时钟（上升沿触发）
    input  wire         cpu_rst,    // 高电平有效复位信号
    
    // CPU接口
    input  wire [3:0]   data_ren,   // 读使能信号（4位掩码，支持字节/半字/字读）
    input  wire [31:0]  data_addr,  // 32位内存地址（读写共用）
    output reg          data_valid, // 数据有效信号（1-读数据就绪）
    output reg  [31:0]  data_rdata, // 32位读数据总线
    input  wire [3:0]   data_wen,   // 写使能信号（4位掩码，支持字节/半字/字写）
    input  wire [31:0]  data_wdata, // 32位写数据总线
    output reg          data_wresp, // 写响应信号（1-写操作完成）
    
    // 主存写接口
    input  wire         dev_wrdy,   // 主存写准备就绪信号
    output reg  [3:0]   dev_wen,    // 主存写使能信号
    output reg  [31:0]  dev_waddr,  // 主存写地址
    output reg  [31:0]  dev_wdata,  // 主存写数据
    
    // 主存读接口
    input  wire         dev_rrdy,   // 主存读准备就绪信号
    output reg  [3:0]   dev_ren,    // 主存读使能信号
    output reg  [31:0]  dev_raddr,  // 主存读地址
    input  wire         dev_rvalid, // 主存读数据有效信号
    input  wire [`BLK_SIZE-1:0] dev_rdata  // 主存读数据总线（块大小由宏定义）
);

// 非缓存访问判断逻辑（访问地址高16位为FFFF时直通主存）
wire uncached = (data_addr[31:16] == 16'hFFFF) & (data_ren != 4'h0 | data_wen != 4'h0) ? 1'b1 : 1'b0;

// 启用数据缓存功能的分支
`ifdef ENABLE_DCACHE
    // 缓存参数定义
    localparam TAG_WIDTH = 5;      // 地址标签位宽（地址位[14:10]）
    localparam INDEX_WIDTH = 6;     // 索引位宽（6位=64个缓存行）
    localparam OFFSET_WIDTH = 4;    // 行内偏移位宽（4位=16字节行大小）
    localparam CACHE_LINES = 64;    // 总缓存行数（2^6=64）

    // 标签存储阵列（每个条目包含：1位有效位 + TAG_WIDTH位标签）
    reg [TAG_WIDTH:0] cache_tags [0:CACHE_LINES-1];

    // 地址分解单元
    wire [INDEX_WIDTH-1:0] cache_index = data_addr[INDEX_WIDTH + OFFSET_WIDTH-1:OFFSET_WIDTH]; // [9:4]
    wire [TAG_WIDTH-1:0] tag_from_cpu = data_addr[14:15-TAG_WIDTH];  // [14:10]
    wire [OFFSET_WIDTH-1:0] offset = data_addr[OFFSET_WIDTH-1:0];     // [3:0]

    // 缓存行状态信号
    wire valid_bit = cache_tags[cache_index][TAG_WIDTH];      // 有效位（最高位）
    wire [TAG_WIDTH-1:0] tag_from_cache = cache_tags[cache_index][TAG_WIDTH-1:0]; // 存储的标签

    // 状态机定义（读操作）
    reg [3:0] IDLE_R=4'b0000,      // 读空闲状态
             TAG_CHECK_R=4'b0001,  // 标签检查状态
             WAIT_R=4'b0010,       // 等待数据状态
             REFILL_R=4'b0011,     // 缓存行填充状态
             UNCACHED_READ=4'b1000;// 非缓存读模式

    // 状态机定义（写操作）
    reg [3:0] IDLE_W=4'b0100,      // 写空闲状态
             TAG_CHECK_W=4'B0101,  // 写标签检查
             WRITE_BACK=4'b0110,   // 写回脏数据状态
             ALLOCATE=4'b0111,     // 分配新行状态
             UNCACHED_WRITE=4'b1001, // 非缓存写模式
             WAIT_W=4'b1010,       // 写等待状态
             HIT_W=4'b1011,        // 写命中状态
             WRITE_BACK1=4'b1100,  // 写回阶段1
             WRITE_BACK2=4'b1101,  // 写回阶段2
             WRITE_BACK3=4'B1110;  // 写回阶段3

    // 状态寄存器
    reg [3:0] cur_state_r, next_state_r; // 读状态机当前/下一状态
    reg [3:0] cur_state_w, next_state_w; // 写状态机当前/下一状态

    // 命中判断逻辑
    wire hit_r = (|dev_ren || |ren_reg) && (tag_from_cache == tag_from_cpu) && valid_bit && !uncached; // 读命中
    wire hit_w = (|dev_wen || |wen_reg) && (tag_from_cache == tag_from_cpu) && valid_bit && !uncached; // 写命中

    // 数据寄存器
    reg [31:0] rdata_reg;   // 读数据暂存器
    reg [3:0]  ren_reg;     // 读使能暂存器

    // 数据输出选择逻辑
    always @(*) begin
        data_rdata = rdata_reg;  // 输出暂存器内容
    end

    // 缓存写控制信号
    wire cache_we = (hit_w && (cur_state_w == HIT_W)) || dev_rvalid; // 写条件：命中或主存返回
    reg  [127:0] cache_line_to_be_written; // 待写入行数据（写命中时构造）
    wire [127:0] cache_line_w = (cur_state_w == HIT_W) ? cache_line_to_be_written : dev_rdata; // 写入数据选择

    // 缓存存储体接口
    wire [127:0] cache_line_r;  // 从缓存读取的行数据

    // 脏标志位寄存器（标记缓存行是否被修改）
    reg [CACHE_LINES-1:0] dirty;

    // Block RAM实例化（实际缓存存储体）
    blk_mem_gen_1 U_dsram (
        .clka   (cpu_clk),    // 时钟输入
        .wea    (cache_we),   // 写使能
        .addra  (cache_index),// 6位索引地址
        .dina   (cache_line_w), // 128位写入数据
        .douta  (cache_line_r)  // 128位读取数据
    );

    // 复位初始化逻辑
    always @(posedge cpu_clk or posedge cpu_rst) begin: RESET_LOGIC
        integer i;
        if (cpu_rst) begin
            // 清空所有标签和脏标志
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                cache_tags[i] <= 0;  // 有效位清零
                dirty[i]      <= 0;  // 脏标志清零
            end
        end
    end

    // 写数据构造逻辑
    always @(*) begin
        if (cpu_rst) begin
            wdata = 32'h0;  // 复位时写数据清零
        end else if (|data_wen) begin
            wdata = data_wdata;  // 锁存CPU写数据
        end
    end

    // 读数据选择逻辑（根据偏移选择行内数据）
    always @(*) begin
        if (cpu_rst) begin
            rdata_reg = 32'h0;
        end else begin
            // 根据高2位偏移选择行内区域
            case(offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2])
                2'b00:  // 0-31位区域
                    case(ren_reg)
                        4'b0001: rdata_reg = cache_line_r[7:0];    // 字节读取
                        4'b0011: rdata_reg = cache_line_r[15:0];  // 半字读取
                        4'b1111: rdata_reg = cache_line_r[31:0];  // 全字读取
                    endcase
                2'b01:  // 32-63位区域
                    case(ren_reg)
                        4'b0001: rdata_reg = cache_line_r[39:32];
                        4'b0011: rdata_reg = cache_line_r[47:32];
                        4'b1111: rdata_reg = cache_line_r[63:32];
                    endcase
                2'b10:  // 64-95位区域
                    case(ren_reg)
                        4'b0001: rdata_reg = cache_line_r[71:64];
                        4'b0011: rdata_reg = cache_line_r[79:64];
                        4'b1111: rdata_reg = cache_line_r[95:64];
                    endcase
                2'b11:  // 96-127位区域
                    case(ren_reg)
                        4'b0001: rdata_reg = cache_line_r[103:96];
                        4'b0011: rdata_reg = cache_line_r[111:96];
                        4'b1111: rdata_reg = cache_line_r[127:96];
                    endcase
            endcase
        end
    end

    // 写命中数据构造逻辑（合并新数据到缓存行）
    always @(*) begin
        if (cpu_rst) begin
            cache_line_to_be_written = 128'h0;
        end else begin
            case(offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2])
                2'b00:  // 修改0-31位区域
                    case(wen_reg)
                        4'b0001: cache_line_to_be_written = {cache_line_r[127:8], wdata[7:0]};    // 字节写入
                        4'b0011: cache_line_to_be_written = {cache_line_r[127:16], wdata[15:0]};  // 半字写入
                        4'b1111: cache_line_to_be_written = {cache_line_r[127:32], wdata[31:0]};  // 全字写入
                    endcase
                2'b01:  // 修改32-63位区域
                    case(wen_reg)
                        4'b0001: cache_line_to_be_written = {cache_line_r[127:40], wdata[7:0], cache_line_r[31:0]};
                        4'b0011: cache_line_to_be_written = {cache_line_r[127:48], wdata[15:0], cache_line_r[31:0]};
                        4'b1111: cache_line_to_be_written = {cache_line_r[127:64], wdata[31:0], cache_line_r[31:0]};
                    endcase
                2'b10:  // 修改64-95位区域
                    case(wen_reg)
                        4'b0001: cache_line_to_be_written = {cache_line_r[127:72], wdata[7:0], cache_line_r[63:0]};
                        4'b0011: cache_line_to_be_written = {cache_line_r[127:80], wdata[15:0], cache_line_r[63:0]};
                        4'b1111: cache_line_to_be_written = {cache_line_r[127:96], wdata[31:0], cache_line_r[63:0]};
                    endcase
                2'b11:  // 修改96-127位区域
                    case(wen_reg)
                        4'b0001: cache_line_to_be_written = {cache_line_r[127:104], wdata[7:0], cache_line_r[95:0]};
                        4'b0011: cache_line_to_be_written = {cache_line_r[127:112], wdata[15:0], cache_line_r[95:0]};
                        4'b1111: cache_line_to_be_written = {wdata[31:0], cache_line_r[95:0]};
                    endcase
            endcase
        end
    end

        // DCache读状态机状态寄存器更新逻辑
    // 在每个时钟上升沿或复位信号有效时更新当前状态
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cur_state_r <= IDLE_R;  // 复位时强制回归初始状态
        end else begin
            cur_state_r <= next_state_r;  // 正常工作时状态转移
        end
    end

    // DCache读状态机状态转移逻辑
    // 组合逻辑实现状态跳转条件判断
    always @(*) begin
        case (cur_state_r)
            IDLE_R: begin  // 初始状态
                if(uncached && data_ren!=0)begin
                    next_state_r = UNCACHED_READ;  // 非缓存读请求直接透传
                end
                else if (data_ren!=0) begin
                    next_state_r = TAG_CHECK_R;     // 缓存读请求启动标签检查
                end else begin
                    next_state_r = IDLE_R;          // 无请求保持空闲
                end
            end
            TAG_CHECK_R: begin  // 标签检查状态
                if (hit_r) begin
                    next_state_r = WAIT_R;         // 命中直接进入等待输出
                end else if (dev_rrdy) begin
                    next_state_r = REFILL_R;       // 主存就绪启动缓存行填充
                end else begin
                    next_state_r = TAG_CHECK_R;    // 等待主存准备就绪
                end
            end
            REFILL_R: begin  // 缓存行填充状态
                if (dev_rvalid) begin
                    next_state_r = WAIT_R;        // 接收完主存数据转等待
                end else begin
                    next_state_r = REFILL_R;       // 持续接收主存数据
                end
            end
            WAIT_R:begin     // 数据就绪状态
                next_state_r = IDLE_R;           // 单周期完成数据输出
            end
            UNCACHED_READ: begin  // 非缓存读模式
                if (dev_rvalid) begin
                    next_state_r = WAIT_R;       // 主存返回数据转等待
                end else begin
                    next_state_r = UNCACHED_READ; // 持续等待主存响应
                end
            end
            default: next_state_r = IDLE_R;      // 异常状态安全恢复
        endcase
    end

    // DCache读状态机输出控制逻辑
    // 时序逻辑生成稳定输出信号
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin  // 复位初始化
            dev_ren <= 4'h0;       // 禁用主存读
            dev_raddr <= 32'b0;    // 清空读地址
            data_valid <= 1'b0;    // 数据无效
            ren_reg <= 0;          // 清空读使能缓存
        end else begin
            case (cur_state_r)
                IDLE_R: begin
                    if(hit_r)begin  // 快速命中处理
                        dev_ren <= 4'h0;        // 无需主存访问
                        dev_raddr <= 32'h0;     // 清空地址总线
                        data_valid <= 1'b0;     // 延迟数据有效信号
                    end else begin
                        dev_ren <= 4'h0;        // 初始状态禁用读
                        dev_raddr <= dev_ren!=0 ? data_addr : 32'h0; // 地址预锁存
                        data_valid <= 1'b0;     // 数据尚未就绪
                        ren_reg <= data_ren;    // 缓存读使能信号
                    end
                end
                TAG_CHECK_R: begin
                    if (hit_r) begin  // 命中处理
                        dev_ren <= 4'h0;        // 保持读禁止
                        dev_raddr <= 32'h0;     // 地址线清零
                        data_valid <= 1'b0;    // 等待周期结束再置有效
                    end else if (!hit_r && dev_rrdy) begin  // 缺失处理
                        dev_ren <= 4'hF;        // 突发读使能(4字读取)
                        dev_raddr <= {tag_from_cpu, cache_index, 4'b0000}; // 对齐地址生成
                        data_valid <= 1'b0;     // 数据尚未到达
                    end
                end
                REFILL_R: begin  // 缓存行填充阶段
                    if (dev_rvalid) begin
                        data_valid = 1'b0;       // 准备下一阶段输出
                        cache_tags[cache_index] <= {1'b1, tag_from_cpu}; // 更新标签表
                    end
                    dev_ren <= 4'h0;  // 停止主存访问
                end
                WAIT_R:begin  // 数据就绪阶段
                    data_valid  <= 1'b1;  // 向CPU宣告数据有效
                end
                UNCACHED_READ: begin  // 非缓存读透传模式
                    dev_ren <= data_ren;      // 直接传递读使能
                    dev_raddr <= data_addr;   // 透传原始地址
                    if (dev_rvalid) begin    // 主存响应到达
                        data_rdata <= dev_rdata[31:0]; // 截取有效数据段
                        data_valid <= 1'b1;  // 标记数据有效
                        dev_ren <= 4'h0;     // 结束读操作
                    end
                end
                default: begin  // 异常状态处理
                    data_valid <= 1'b0;  // 保证数据无效
                    dev_ren <= 4'h0;     // 禁用主存读
                end
            endcase
        end
    end

    ///////////////////////////////////////////////////////////
    // DCache写状态机状态寄存器更新逻辑
    // 时序逻辑实现状态寄存器更新
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cur_state_w <= IDLE_W;  // 复位回归初始状态
        end else begin
            cur_state_w <= next_state_w;  // 正常状态转移
        end
    end

    // DCache写状态机状态转移逻辑
    // 组合逻辑实现状态跳转条件判断
    always @(*)begin
        case(cur_state_w)
        IDLE_W:begin  // 写空闲状态
            if(data_wen!=0)begin
               next_state_w = uncached ? UNCACHED_WRITE : TAG_CHECK_W; // 非缓存写透传/缓存写检查
            end
            else next_state_w = IDLE_W;  // 无请求保持空闲
        end
        TAG_CHECK_W:begin  // 标签检查状态
            if(hit_w)begin
                next_state_w = HIT_W;     // 写命中直接修改
            end
            else if(!hit_w && dirty[cache_index]&& dev_wrdy)begin
                next_state_w = WRITE_BACK; // 脏数据需写回主存
            end
            else if(!hit_w && !dirty[cache_index] && dev_wrdy)begin
                next_state_w = ALLOCATE;   // 干净行直接分配
            end
            else begin
                next_state_w = TAG_CHECK_W; // 等待主存准备
            end
        end
        WAIT_W:begin  // 写等待状态
            if(dev_wrdy)begin
            next_state_w = IDLE_W;  // 主存响应完成
            end
            else next_state_w = WAIT_W; // 等待主存确认
        end
        WRITE_BACK:begin  // 脏数据写回阶段
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK1; // 启动四阶段写回
            end
            else begin
                next_state_w = WRITE_BACK; // 等待主存就绪
            end
        end
        WRITE_BACK1:begin  // 写回第一字(0-31位)
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK2; 
            end
            else begin
                next_state_w = WRITE_BACK1;
            end
        end
        WRITE_BACK2:begin  // 写回第二字(32-63位)
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK3;
            end
            else begin
                next_state_w = WRITE_BACK2;
            end
        end
        WRITE_BACK3:begin  // 写回第三字(64-95位)
            if(dev_wrdy)begin
                next_state_w =ALLOCATE;    // 转缓存行分配
            end
            else begin
                next_state_w = WRITE_BACK3;
            end
        end
        HIT_W:begin  // 写命中处理状态
            next_state_w = WAIT_W;  // 单周期完成更新
        end
        ALLOCATE:begin  // 缓存行分配状态
            if(dev_rvalid)begin
                next_state_w = TAG_CHECK_W; // 分配完成重新检查
                end
            else begin
                next_state_w = ALLOCATE;   // 等待主存数据加载
            end
        end 
        UNCACHED_WRITE: begin  // 非缓存写透传模式
            if (dev_wrdy) begin
                next_state_w = WAIT_W;    // 主存接收请求
            end else begin
                next_state_w = UNCACHED_WRITE; // 持续等待
            end
        end
        default:next_state_w = IDLE_W;    // 异常状态恢复
        endcase
    end
    // 写使能信号暂存器控制逻辑
    // 组合逻辑实现wen_reg更新
    always@(*)begin
        if(cpu_rst)begin
            wen_reg = 0;          // 复位时清零
        end
        else if (data_wen != 0)begin
            wen_reg = data_wen;  // 锁存CPU写使能信号
        end
        else if(data_wresp == 1'b1)begin
            wen_reg = 0;         // 写操作完成后释放
        end
    end

    // DCache写状态机输出信号生成
    // 时序逻辑生成稳定的输出信号
    always @(posedge cpu_clk or posedge cpu_rst)begin
        if(cpu_rst)begin  // 复位初始化
            dev_wen <= 4'b0;     // 禁用主存写
            dev_waddr <= 32'h0;  // 清空写地址
            dev_raddr <= 32'h0;  // 清空读地址
            dev_wdata <= 32'h0;  // 清空写数据
            data_valid <= 0;     // 数据无效
            data_wresp <= 0;     // 写响应无效
        end
        case(cur_state_w)
        IDLE_W:begin  // 写空闲状态
                dev_waddr <= data_addr;  // 预锁存写地址
                data_wresp <= 0;         // 清除写响应
                if(uncached)begin         // 非缓存写透传
                    dev_wdata <= data_wdata; // 直通写数据
                    dev_wen <= data_wen;     // 直通写使能
                end
                else begin                // 缓存写模式
                    dev_wen <= 0;          // 禁用主存写
                end
        end
        TAG_CHECK_W:begin  // 标签检查状态
            if(hit_w)begin  // 写命中处理
                dev_wen <= 0;  // 无需主存操作
                dev_ren <= 0;  // 禁用主存读
            end
            else if(!hit_w && dirty[cache_index]&& dev_wrdy)begin 
                // 写缺失且脏行，留空等待写回状态机处理
            end
            else if(!hit_w && !dirty[cache_index] && dev_wrdy)begin
                dev_ren <= 4'hf;         // 启动缓存行分配读
                dev_raddr <= data_addr;   // 设置分配地址
            end
        end
        HIT_W:begin  // 写命中更新状态
            dirty[cache_index] <= 1'b1;               // 标记脏位
            cache_tags[cache_index] <= {1'b1,tag_from_cpu}; // 更新标签
        end
        WAIT_W:begin  // 写等待状态
            if(dev_wrdy)begin
                data_wresp <= 1'b1;  // 写操作完成确认
                dev_wen <= 0;        // 关闭主存写
            end
        end
        WRITE_BACK:begin  // 写回阶段0（32-63位数据）
            if(dev_wrdy)begin
                dev_wen <= 4'hf;                   // 使能主存写
                dev_wdata <= cache_line_r[31:0];    // 写回数据块0
                dev_waddr <= {tag_from_cache,cache_index, 4'b0000}; // 生成写地址
            end
        end
        WRITE_BACK1:begin  // 写回阶段1（64-95位数据）
            if(dev_wrdy)begin
                dev_wen <= 4'hf;                   
                dev_wdata <= cache_line_r[63:32];   // 写回数据块1
                dev_waddr <= {tag_from_cache,cache_index, 4'b0100}; // 地址偏移+4
            end
        end
        WRITE_BACK2:begin  // 写回阶段2（96-127位数据）
            if(dev_wrdy)begin
                dev_wen <= 4'hf;                   
                dev_wdata <= cache_line_r[95:64];   // 写回数据块2
                dev_waddr <= {tag_from_cache,cache_index, 4'b1000}; // 地址偏移+8
            end
        end
        WRITE_BACK3:begin  // 写回阶段3（128-159位数据）
            if(dev_wrdy)begin
                dev_wen <= 4'hf;                   
                dev_wdata <= cache_line_r[127:96];  // 写回数据块3
                dev_waddr <= {tag_from_cache,cache_index, 4'b1100}; // 地址偏移+12
            end
        end
        ALLOCATE:begin  // 缓存行分配状态
            if(dev_rvalid)begin
                dirty[cache_index] <= 1'b0;        // 新行初始为干净
                cache_tags[cache_index]<= {1'b1, tag_from_cpu}; // 更新标签
            end
            else begin
                dev_ren  <= 4'h0;  // 分配完成后禁用读
            end
        end
       UNCACHED_WRITE: begin  // 非缓存写透传模式
                dev_wen <= 0;  // 已通过IDLE_W阶段完成写操作
            end
        default:begin
            dev_wen <= 4'b0;  // 默认禁用主存写
        end
        endcase
    end
