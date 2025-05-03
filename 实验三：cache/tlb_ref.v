module tlb #(
    parameter TLBNUM = 16  // TLB��Ŀ������Ĭ��Ϊ16��
)(
    input  wire clk,       // ʱ���ź�
    // �����˿�0������ȡָ��
    input  wire [18:0] s0_vppn,      // ����ҳ�ţ�Virtual Page Page Number��
    input  wire        s0_va_bit12,  // �����ַ��12λ�������ж�ҳ��С��
    input  wire [9:0]  s0_asid,       // ��ַ�ռ�ID��Address Space ID��
    output wire        s0_found,     // ���б�־��1=���У�
    output wire [$clog2(TLBNUM)-1:0] s0_index, // �����������
    output wire [19:0] s0_ppn,        // ����ҳ�ţ�Physical Page Number��
    output wire [5:0]  s0_ps,         // ҳ��С��Page Size����12=4KB��22=4MB��
    output wire [1:0]  s0_plv,        // ��Ȩ�ȼ���Privilege Level��
    output wire [1:0]  s0_mat,        // �ڴ�������ͣ�Memory Access Type��
    output wire        s0_d,          // ��λ��Dirty Bit���Ƿ��д��
    output wire        s0_v,          // ��Чλ��Valid Bit��
    // �����˿�1�����ڼ���/�洢��Ҳ����TLBָ���ѯ��
    input  wire [18:0] s1_vppn,       // ͬs0_vppn�������ڷô����
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
    // TLB��Ч������
    input  wire        invtlb_valid,  // ��Ч��������Ч�ź�
    input  wire [4:0]  invtlb_op,      // ��Ч���������ͣ����±�
    // д��˿�
    input  wire        we,             // дʹ�ܣ�Write Enable��
    input  wire [$clog2(TLBNUM)-1:0] w_index, // д���TLB������
    input  wire        w_e,            // д�������Чλ
    input  wire [18:0] w_vppn,         // д�������ҳ��
    input  wire [5:0]  w_ps,           // д���ҳ��С
    input  wire [9:0]  w_asid,         // д���ASID
    input  wire        w_g,            // ȫ��λ��Global������ASIDƥ�䣩
    input  wire [19:0] w_ppn0,         // żҳ����ҳ�ţ�PPN0��
    input  wire [1:0]  w_plv0,         // żҳ��Ȩ�ȼ�
    input  wire [1:0]  w_mat0,         // żҳ�ڴ�����
    input  wire        w_d0,           // żҳ��λ
    input  wire        w_v0,           // żҳ��Чλ
    input  wire [19:0] w_ppn1,         // ��ҳ����ҳ�ţ�PPN1��
    input  wire [1:0]  w_plv1,         // ��ҳ��Ȩ�ȼ�
    input  wire [1:0]  w_mat1,         // ��ҳ�ڴ�����
    input  wire        w_d1,           // ��ҳ��λ
    input  wire        w_v1,           // ��ҳ��Чλ
    // ��ȡ�˿�
    input  wire [$clog2(TLBNUM)-1:0] r_index, // ��ȡ��TLB������
    output wire        r_e,            // ��ȡ�����Чλ
    output wire [18:0] r_vppn,         // ��ȡ������ҳ��
    output wire [5:0]  r_ps,           // ��ȡ��ҳ��С
    output wire [9:0]  r_asid,         // ��ȡ��ASID
    output wire        r_g,            // ��ȡ��ȫ��λ
    output wire [19:0] r_ppn0,         // ��ȡ��żҳPPN0
    output wire [1:0]  r_plv0,         // ��ȡ��żҳ��Ȩ�ȼ�
    output wire [1:0]  r_mat0,         // ��ȡ��żҳ�ڴ�����
    output wire        r_d0,           // ��ȡ��żҳ��λ
    output wire        r_v0,           // ��ȡ��żҳ��Чλ
    output wire [19:0] r_ppn1,         // ��ȡ����ҳPPN1
    output wire [1:0]  r_plv1,         // ��ȡ����ҳ��Ȩ�ȼ�
    output wire [1:0]  r_mat1,         // ��ȡ����ҳ�ڴ�����
    output wire        r_d1,           // ��ȡ����ҳ��λ
    output wire        r_v1            // ��ȡ����ҳ��Чλ
);


// TLB��Ŀ�洢�ļĴ�������
reg [TLBNUM-1:0] tlb_e;          // ��Ŀ��Чλ��ÿ��bit��Ӧһ��TLB�
reg [TLBNUM-1:0] tlb_ps4MB;      // ҳ��С��ǣ�1=4MBҳ��0=4KBҳ��
reg [18:0] tlb_vppn [TLBNUM-1:0];// ����ҳ�ţ�VPPN��
reg [9:0]  tlb_asid [TLBNUM-1:0];// ASID
reg        tlb_g    [TLBNUM-1:0];// ȫ��λ��G��
reg [19:0] tlb_ppn0 [TLBNUM-1:0];// żҳ����ҳ�ţ�PPN0��
reg [1:0]  tlb_plv0 [TLBNUM-1:0];// żҳ��Ȩ�ȼ���PLV0��
reg [1:0]  tlb_mat0 [TLBNUM-1:0];// żҳ�ڴ����ͣ�MAT0��
reg        tlb_d0   [TLBNUM-1:0];// żҳ��λ��D0��
reg        tlb_v0   [TLBNUM-1:0];// żҳ��Чλ��V0��
reg [19:0] tlb_ppn1 [TLBNUM-1:0];// ��ҳ����ҳ�ţ�PPN1��
reg [1:0]  tlb_plv1 [TLBNUM-1:0];// ��ҳ��Ȩ�ȼ���PLV1��
reg [1:0]  tlb_mat1 [TLBNUM-1:0];// ��ҳ�ڴ����ͣ�MAT1��
reg        tlb_d1   [TLBNUM-1:0];// ��ҳ��λ��D1��
reg        tlb_v1   [TLBNUM-1:0];// ��ҳ��Чλ��V1��


genvar i;

// invtlb
wire [TLBNUM-1:0] cond1;
wire [TLBNUM-1:0] cond2;
wire [TLBNUM-1:0] cond3;
wire [TLBNUM-1:0] cond4;

wire [TLBNUM-1:0] invtlb_match;

generate
    for (i=0; i<TLBNUM; i=i+1) begin : invtlb
        // ����invtlb_op������Ч��������
        assign cond1[i] = !tlb_g[i];  // ��ȫ����Ŀ
        assign cond2[i] = tlb_g[i];   // ȫ����Ŀ
        assign cond3[i] = (s1_asid == tlb_asid[i]); // ASIDƥ��
        assign cond4[i] = (s1_vppn[18:10] == tlb_vppn[i][18:10]) // VPN��λƥ��
                        && (tlb_ps4MB[i] || s1_vppn[9:0] == tlb_vppn[i][9:0]); // ҳ��С���ƥ��
        
        // ����invtlb_opѡ��ƥ����Ŀ�������������±�
        assign invtlb_match[i] = 
            (invtlb_op == 5'h0 && (cond1[i] || cond2[i])) || // ��Ч��ȫ��
            (invtlb_op == 5'h1 && (cond1[i] || cond2[i])) || // ��Ч��ȫ�ֺͷ�ȫ��
            (invtlb_op == 5'h2 && cond2[i])               || // ��Ч��ȫ����Ŀ
            (invtlb_op == 5'h3 && cond1[i])               || // ��Ч����ȫ����Ŀ
            (invtlb_op == 5'h4 && cond1[i] && cond3[i])  || // ��ASID��Ч��
            (invtlb_op == 5'h5 && cond1[i] && cond3[i] && cond4[i]) || // ��ASID+VPN��Ч��
            (invtlb_op == 5'h6 && (cond2[i] || cond3[i]) && cond4[i]); // ȫ�ֻ�ASID+VPN��Ч��
    end
endgenerate

// search
wire [TLBNUM-1:0] match0;
wire [TLBNUM-1:0] match1;

generate
    for (i = 0; i < TLBNUM; i = i + 1) begin : TLB
        // �˿�0ƥ������������ҳ��+ASID/ȫ��λ+��Чλ
        assign match0[i] = 
            (s0_vppn[18:10] == tlb_vppn[i][18:10]) && // ����ҳ�Ÿ�λƥ��
            (tlb_ps4MB[i] || s0_vppn[9:0] == tlb_vppn[i][9:0]) && // ҳ��С��ص�λƥ��
            (s0_asid == tlb_asid[i] || tlb_g[i]) && // ASIDƥ���ȫ����Ŀ
            tlb_e[i]; // ��Ŀ��Ч
        
        // �˿�1ƥ��������ͬ�˿�0��
        assign match1[i] = 
            (s1_vppn[18:10] == tlb_vppn[i][18:10]) && 
            (tlb_ps4MB[i] || s1_vppn[9:0] == tlb_vppn[i][9:0]) && 
            (s1_asid == tlb_asid[i] || tlb_g[i]) && 
            tlb_e[i];
    end
endgenerate

// ʵ����16-4����������match0��16λ��ת��Ϊ4λ����s0_index
encoder_16_4 enc0(
    .in     (match0),      // ���룺16λƥ���źţ�ÿ��bit��ʾһ��TLB��Ŀ�Ƿ����У�
    .out    (s0_index)     // �����4λ������������ı�ţ�
);

// ����ҳ��Сѡ�������ַλ��4MBҳȡVPN[9]��4KBҳȡ�����ַ��12λ
wire s0_va_bit_ps;
assign s0_va_bit_ps = tlb_ps4MB[s0_index] ? s0_vppn[9] : s0_va_bit12;

// ���ɶ˿�0������ź�
assign s0_found = |match0;  // ���б�־������һλmatch0Ϊ1�����У�
assign s0_ppn   = s0_va_bit_ps ? tlb_ppn1[s0_index] : tlb_ppn0[s0_index]; // ѡ����żҳ����ҳ��
assign s0_ps    = tlb_ps4MB[s0_index] ? 22 : 12;       // ҳ��С��22=4MB��12=4KB��
assign s0_plv   = s0_va_bit_ps ? tlb_plv1[s0_index] : tlb_plv0[s0_index]; // ��Ȩ�ȼ�
assign s0_mat   = s0_va_bit_ps ? tlb_mat1[s0_index] : tlb_mat0[s0_index]; // �ڴ�����
assign s0_d     = s0_va_bit_ps ? tlb_d1[s0_index]   : tlb_d0[s0_index];   // ��λ
assign s0_v     = s0_va_bit_ps ? tlb_v1[s0_index]   : tlb_v0[s0_index];   // ��Чλ


// 1
// ʵ������һ��16-4����������˿�1��ƥ����
encoder_16_4 enc1(
    .in     (match1),      // ���룺�˿�1��16λƥ���ź�
    .out    (s1_index)     // ������������4λ����
);

// ���ƶ˿�0�������ַλѡ���߼�
wire s1_va_bit_ps;
assign s1_va_bit_ps = tlb_ps4MB[s1_index] ? s1_vppn[9] : s1_va_bit12;

// ���ɶ˿�1������ź�
assign s1_found = |match1;  // ���б�־
assign s1_ppn   = s1_va_bit_ps ? tlb_ppn1[s1_index] : tlb_ppn0[s1_index];
assign s1_ps    = tlb_ps4MB[s1_index] ? 22 : 12;
assign s1_plv   = s1_va_bit_ps ? tlb_plv1[s1_index] : tlb_plv0[s1_index];
assign s1_mat   = s1_va_bit_ps ? tlb_mat1[s1_index] : tlb_mat0[s1_index];
assign s1_d     = s1_va_bit_ps ? tlb_d1[s1_index]   : tlb_d0[s1_index];
assign s1_v     = s1_va_bit_ps ? tlb_v1[s1_index]   : tlb_v0[s1_index];



// д���߼�����ʱ�������ظ���TLB��Ŀ
integer j;
always @(posedge clk) begin
    if (we) begin  // дʹ����Чʱ��д��ָ��������TLB��Ŀ
        tlb_e       [w_index] <= w_e;     // ��Чλ
        tlb_ps4MB   [w_index] <= w_ps==22;// ҳ��С��ǣ�1=4MB��0=4KB��
        tlb_vppn    [w_index] <= w_vppn;  // ����ҳ��
        tlb_asid    [w_index] <= w_asid;  // ASID
        tlb_g       [w_index] <= w_g;     // ȫ��λ
        tlb_ppn0    [w_index] <= w_ppn0;  // żҳ����ҳ��
        tlb_plv0    [w_index] <= w_plv0;  // żҳ��Ȩ�ȼ�
        tlb_mat0    [w_index] <= w_mat0;  // żҳ�ڴ�����
        tlb_d0      [w_index] <= w_d0;    // żҳ��λ
        tlb_v0      [w_index] <= w_v0;    // żҳ��Чλ
        tlb_ppn1    [w_index] <= w_ppn1;  // ��ҳ����ҳ��
        tlb_plv1    [w_index] <= w_plv1;  // ��ҳ��Ȩ�ȼ�
        tlb_mat1    [w_index] <= w_mat1;  // ��ҳ�ڴ�����
        tlb_d1      [w_index] <= w_d1;    // ��ҳ��λ
        tlb_v1      [w_index] <= w_v1;    // ��ҳ��Чλ
    end else if (invtlb_valid) begin  // ��Ч��������Чʱ�����ƥ���TLB��Ŀ
        for (j = 0; j < TLBNUM; j = j + 1) begin
            if (invtlb_match[j]) begin  // ����Ŀj������Ч������
                tlb_e[j] <= 1'b0;       // ����Чλ��0
            end
        end
    end
end


// ��ȡ�߼�������r_index�����ӦTLB��Ŀ���ֶ�
assign r_e       = tlb_e       [r_index]; // ��Чλ
assign r_vppn    = tlb_vppn    [r_index]; // ����ҳ��
assign r_ps      = tlb_ps4MB   [r_index] ? 22 : 12; // ҳ��С����̬���㣩
assign r_asid    = tlb_asid    [r_index]; // ASID
assign r_g       = tlb_g       [r_index]; // ȫ��λ
assign r_ppn0    = tlb_ppn0    [r_index]; // żҳ����ҳ��
assign r_plv0    = tlb_plv0    [r_index]; // żҳ��Ȩ�ȼ�
assign r_mat0    = tlb_mat0    [r_index]; // żҳ�ڴ�����
assign r_d0      = tlb_d0      [r_index]; // żҳ��λ
assign r_v0      = tlb_v0      [r_index]; // żҳ��Чλ
assign r_ppn1    = tlb_ppn1    [r_index]; // ��ҳ����ҳ��
assign r_plv1    = tlb_plv1    [r_index]; // ��ҳ��Ȩ�ȼ�
assign r_mat1    = tlb_mat1    [r_index]; // ��ҳ�ڴ�����
assign r_d1      = tlb_d1      [r_index]; // ��ҳ��λ
assign r_v1      = tlb_v1      [r_index]; // ��ҳ��Чλ

endmodule
