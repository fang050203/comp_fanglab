module tlb #(
    parameter TLBNUM = 16  // TLB条目总数，默认为16项
)(
    input  wire clk,       // 时钟信号
    // 搜索端口0（用于取指）
    input  wire [18:0] s0_vppn,      // 虚拟页号（Virtual Page Page Number）
    input  wire        s0_va_bit12,  // 虚拟地址第12位（用于判断页大小）
    input  wire [9:0]  s0_asid,       // 地址空间ID（Address Space ID）
    output wire        s0_found,     // 命中标志（1=命中）
    output wire [$clog2(TLBNUM)-1:0] s0_index, // 命中项的索引
    output wire [19:0] s0_ppn,        // 物理页号（Physical Page Number）
    output wire [5:0]  s0_ps,         // 页大小（Page Size，如12=4KB，22=4MB）
    output wire [1:0]  s0_plv,        // 特权等级（Privilege Level）
    output wire [1:0]  s0_mat,        // 内存访问类型（Memory Access Type）
    output wire        s0_d,          // 脏位（Dirty Bit，是否可写）
    output wire        s0_v,          // 有效位（Valid Bit）
    // 搜索端口1（用于加载/存储，也用于TLB指令查询）
    input  wire [18:0] s1_vppn,       // 同s0_vppn，但用于访存操作
    input  wire        s1_va_bit12,
    input  wire [9:0]  s1_asid,
    output wire        s1_found,
    output wire [$clog2(TLBNUM)-1:0] s1_index,
    output wire [19:0] s1_ppn,
    output wire [5:0]  s1_ps,
    output wire [1:0]  s1_plv,
    output wire [1:0]  s1_mat,
    output wire        s1_d,
    output wire        s1_v,
    // TLB无效化操作
    input  wire        invtlb_valid,  // 无效化操作有效信号
    input  wire [4:0]  invtlb_op,      // 无效化操作类型（见下表）
    // 写入端口
    input  wire        we,             // 写使能（Write Enable）
    input  wire [$clog2(TLBNUM)-1:0] w_index, // 写入的TLB项索引
    input  wire        w_e,            // 写入项的有效位
    input  wire [18:0] w_vppn,         // 写入的虚拟页号
    input  wire [5:0]  w_ps,           // 写入的页大小
    input  wire [9:0]  w_asid,         // 写入的ASID
    input  wire        w_g,            // 全局位（Global，忽略ASID匹配）
    input  wire [19:0] w_ppn0,         // 偶页物理页号（PPN0）
    input  wire [1:0]  w_plv0,         // 偶页特权等级
    input  wire [1:0]  w_mat0,         // 偶页内存类型
    input  wire        w_d0,           // 偶页脏位
    input  wire        w_v0,           // 偶页有效位
    input  wire [19:0] w_ppn1,         // 奇页物理页号（PPN1）
    input  wire [1:0]  w_plv1,         // 奇页特权等级
    input  wire [1:0]  w_mat1,         // 奇页内存类型
    input  wire        w_d1,           // 奇页脏位
    input  wire        w_v1,           // 奇页有效位
    // 读取端口
    input  wire [$clog2(TLBNUM)-1:0] r_index, // 读取的TLB项索引
    output wire        r_e,            // 读取项的有效位
    output wire [18:0] r_vppn,         // 读取的虚拟页号
    output wire [5:0]  r_ps,           // 读取的页大小
    output wire [9:0]  r_asid,         // 读取的ASID
    output wire        r_g,            // 读取的全局位
    output wire [19:0] r_ppn0,         // 读取的偶页PPN0
    output wire [1:0]  r_plv0,         // 读取的偶页特权等级
    output wire [1:0]  r_mat0,         // 读取的偶页内存类型
    output wire        r_d0,           // 读取的偶页脏位
    output wire        r_v0,           // 读取的偶页有效位
    output wire [19:0] r_ppn1,         // 读取的奇页PPN1
    output wire [1:0]  r_plv1,         // 读取的奇页特权等级
    output wire [1:0]  r_mat1,         // 读取的奇页内存类型
    output wire        r_d1,           // 读取的奇页脏位
    output wire        r_v1            // 读取的奇页有效位
);


// TLB条目存储的寄存器数组
reg [TLBNUM-1:0] tlb_e;          // 条目有效位（每个bit对应一个TLB项）
reg [TLBNUM-1:0] tlb_ps4MB;      // 页大小标记（1=4MB页，0=4KB页）
reg [18:0] tlb_vppn [TLBNUM-1:0];// 虚拟页号（VPPN）
reg [9:0]  tlb_asid [TLBNUM-1:0];// ASID
reg        tlb_g    [TLBNUM-1:0];// 全局位（G）
reg [19:0] tlb_ppn0 [TLBNUM-1:0];// 偶页物理页号（PPN0）
reg [1:0]  tlb_plv0 [TLBNUM-1:0];// 偶页特权等级（PLV0）
reg [1:0]  tlb_mat0 [TLBNUM-1:0];// 偶页内存类型（MAT0）
reg        tlb_d0   [TLBNUM-1:0];// 偶页脏位（D0）
reg        tlb_v0   [TLBNUM-1:0];// 偶页有效位（V0）
reg [19:0] tlb_ppn1 [TLBNUM-1:0];// 奇页物理页号（PPN1）
reg [1:0]  tlb_plv1 [TLBNUM-1:0];// 奇页特权等级（PLV1）
reg [1:0]  tlb_mat1 [TLBNUM-1:0];// 奇页内存类型（MAT1）
reg        tlb_d1   [TLBNUM-1:0];// 奇页脏位（D1）
reg        tlb_v1   [TLBNUM-1:0];// 奇页有效位（V1）


genvar i;

// invtlb
wire [TLBNUM-1:0] cond1;
wire [TLBNUM-1:0] cond2;
wire [TLBNUM-1:0] cond3;
wire [TLBNUM-1:0] cond4;

wire [TLBNUM-1:0] invtlb_match;

generate
    for (i=0; i<TLBNUM; i=i+1) begin : invtlb
        // 根据invtlb_op定义无效化条件：
        assign cond1[i] = !tlb_g[i];  // 非全局条目
        assign cond2[i] = tlb_g[i];   // 全局条目
        assign cond3[i] = (s1_asid == tlb_asid[i]); // ASID匹配
        assign cond4[i] = (s1_vppn[18:10] == tlb_vppn[i][18:10]) // VPN高位匹配
                        && (tlb_ps4MB[i] || s1_vppn[9:0] == tlb_vppn[i][9:0]); // 页大小相关匹配
        
        // 根据invtlb_op选择匹配条目（具体操作码见下表）
        assign invtlb_match[i] = 
            (invtlb_op == 5'h0 && (cond1[i] || cond2[i])) || // 无效化全部
            (invtlb_op == 5'h1 && (cond1[i] || cond2[i])) || // 无效化全局和非全局
            (invtlb_op == 5'h2 && cond2[i])               || // 无效化全局条目
            (invtlb_op == 5'h3 && cond1[i])               || // 无效化非全局条目
            (invtlb_op == 5'h4 && cond1[i] && cond3[i])  || // 按ASID无效化
            (invtlb_op == 5'h5 && cond1[i] && cond3[i] && cond4[i]) || // 按ASID+VPN无效化
            (invtlb_op == 5'h6 && (cond2[i] || cond3[i]) && cond4[i]); // 全局或ASID+VPN无效化
    end
endgenerate

// search
wire [TLBNUM-1:0] match0;
wire [TLBNUM-1:0] match1;

generate
    for (i = 0; i < TLBNUM; i = i + 1) begin : TLB
        // 端口0匹配条件：虚拟页号+ASID/全局位+有效位
        assign match0[i] = 
            (s0_vppn[18:10] == tlb_vppn[i][18:10]) && // 虚拟页号高位匹配
            (tlb_ps4MB[i] || s0_vppn[9:0] == tlb_vppn[i][9:0]) && // 页大小相关低位匹配
            (s0_asid == tlb_asid[i] || tlb_g[i]) && // ASID匹配或全局条目
            tlb_e[i]; // 条目有效
        
        // 端口1匹配条件（同端口0）
        assign match1[i] = 
            (s1_vppn[18:10] == tlb_vppn[i][18:10]) && 
            (tlb_ps4MB[i] || s1_vppn[9:0] == tlb_vppn[i][9:0]) && 
            (s1_asid == tlb_asid[i] || tlb_g[i]) && 
            tlb_e[i];
    end
endgenerate

// 实例化16-4编码器，将match0（16位）转换为4位索引s0_index
encoder_16_4 enc0(
    .in     (match0),      // 输入：16位匹配信号（每个bit表示一个TLB条目是否命中）
    .out    (s0_index)     // 输出：4位索引（命中项的编号）
);

// 根据页大小选择虚拟地址位：4MB页取VPN[9]，4KB页取虚拟地址第12位
wire s0_va_bit_ps;
assign s0_va_bit_ps = tlb_ps4MB[s0_index] ? s0_vppn[9] : s0_va_bit12;

// 生成端口0的输出信号
assign s0_found = |match0;  // 命中标志（任意一位match0为1则命中）
assign s0_ppn   = s0_va_bit_ps ? tlb_ppn1[s0_index] : tlb_ppn0[s0_index]; // 选择奇偶页物理页号
assign s0_ps    = tlb_ps4MB[s0_index] ? 22 : 12;       // 页大小（22=4MB，12=4KB）
assign s0_plv   = s0_va_bit_ps ? tlb_plv1[s0_index] : tlb_plv0[s0_index]; // 特权等级
assign s0_mat   = s0_va_bit_ps ? tlb_mat1[s0_index] : tlb_mat0[s0_index]; // 内存类型
assign s0_d     = s0_va_bit_ps ? tlb_d1[s0_index]   : tlb_d0[s0_index];   // 脏位
assign s0_v     = s0_va_bit_ps ? tlb_v1[s0_index]   : tlb_v0[s0_index];   // 有效位


// 1
// 实例化另一个16-4编码器处理端口1的匹配结果
encoder_16_4 enc1(
    .in     (match1),      // 输入：端口1的16位匹配信号
    .out    (s1_index)     // 输出：命中项的4位索引
);

// 类似端口0的虚拟地址位选择逻辑
wire s1_va_bit_ps;
assign s1_va_bit_ps = tlb_ps4MB[s1_index] ? s1_vppn[9] : s1_va_bit12;

// 生成端口1的输出信号
assign s1_found = |match1;  // 命中标志
assign s1_ppn   = s1_va_bit_ps ? tlb_ppn1[s1_index] : tlb_ppn0[s1_index];
assign s1_ps    = tlb_ps4MB[s1_index] ? 22 : 12;
assign s1_plv   = s1_va_bit_ps ? tlb_plv1[s1_index] : tlb_plv0[s1_index];
assign s1_mat   = s1_va_bit_ps ? tlb_mat1[s1_index] : tlb_mat0[s1_index];
assign s1_d     = s1_va_bit_ps ? tlb_d1[s1_index]   : tlb_d0[s1_index];
assign s1_v     = s1_va_bit_ps ? tlb_v1[s1_index]   : tlb_v0[s1_index];



// 写入逻辑：在时钟上升沿更新TLB条目
integer j;
always @(posedge clk) begin
    if (we) begin  // 写使能有效时，写入指定索引的TLB条目
        tlb_e       [w_index] <= w_e;     // 有效位
        tlb_ps4MB   [w_index] <= w_ps==22;// 页大小标记（1=4MB，0=4KB）
        tlb_vppn    [w_index] <= w_vppn;  // 虚拟页号
        tlb_asid    [w_index] <= w_asid;  // ASID
        tlb_g       [w_index] <= w_g;     // 全局位
        tlb_ppn0    [w_index] <= w_ppn0;  // 偶页物理页号
        tlb_plv0    [w_index] <= w_plv0;  // 偶页特权等级
        tlb_mat0    [w_index] <= w_mat0;  // 偶页内存类型
        tlb_d0      [w_index] <= w_d0;    // 偶页脏位
        tlb_v0      [w_index] <= w_v0;    // 偶页有效位
        tlb_ppn1    [w_index] <= w_ppn1;  // 奇页物理页号
        tlb_plv1    [w_index] <= w_plv1;  // 奇页特权等级
        tlb_mat1    [w_index] <= w_mat1;  // 奇页内存类型
        tlb_d1      [w_index] <= w_d1;    // 奇页脏位
        tlb_v1      [w_index] <= w_v1;    // 奇页有效位
    end else if (invtlb_valid) begin  // 无效化操作有效时，清除匹配的TLB条目
        for (j = 0; j < TLBNUM; j = j + 1) begin
            if (invtlb_match[j]) begin  // 若条目j满足无效化条件
                tlb_e[j] <= 1'b0;       // 将有效位置0
            end
        end
    end
end


// 读取逻辑：根据r_index输出对应TLB条目的字段
assign r_e       = tlb_e       [r_index]; // 有效位
assign r_vppn    = tlb_vppn    [r_index]; // 虚拟页号
assign r_ps      = tlb_ps4MB   [r_index] ? 22 : 12; // 页大小（动态计算）
assign r_asid    = tlb_asid    [r_index]; // ASID
assign r_g       = tlb_g       [r_index]; // 全局位
assign r_ppn0    = tlb_ppn0    [r_index]; // 偶页物理页号
assign r_plv0    = tlb_plv0    [r_index]; // 偶页特权等级
assign r_mat0    = tlb_mat0    [r_index]; // 偶页内存类型
assign r_d0      = tlb_d0      [r_index]; // 偶页脏位
assign r_v0      = tlb_v0      [r_index]; // 偶页有效位
assign r_ppn1    = tlb_ppn1    [r_index]; // 奇页物理页号
assign r_plv1    = tlb_plv1    [r_index]; // 奇页特权等级
assign r_mat1    = tlb_mat1    [r_index]; // 奇页内存类型
assign r_d1      = tlb_d1      [r_index]; // 奇页脏位
assign r_v1      = tlb_v1      [r_index]; // 奇页有效位

endmodule
