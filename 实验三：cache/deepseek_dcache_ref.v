`timescale 1ns / 1ps

// ���建��鳤�Ⱥʹ�С��
`define BLK_LEN  4        // ÿ����������4��32λ��
`define BLK_SIZE (`BLK_LEN*32)  // ������ܴ�С=4*32=128λ

module DCache(
    // ����ʱ�Ӻ͸�λ�ź�
    input  wire         cpu_clk,     // ��ʱ�ӣ���������Ч��
    input  wire         cpu_rst,     // �ߵ�ƽ��Ч��λ�ź�
    
    // ��CPU�ӿ�
    input  wire [ 3:0]  data_ren,    // CPU��ʹ�ܣ����ֽ�ʹ�ܣ�
    input  wire [31:0]  data_addr,   // CPU���ʵ�ַ����д���ã�
    output reg          data_valid,  // ��������Ч�źţ����л������䣩
    output reg  [31:0]  data_rdata,  // �����CPU�Ķ�����
    input  wire [ 3:0]  data_wen,    // CPUдʹ�ܣ����ֽ�ʹ�ܣ� 
    input  wire [31:0]  data_wdata,  // CPUд����
    output reg          data_wresp,  // д������Ӧ�źţ��ߵ�ƽ��ʾ��ɣ�
    
    // ������д���߽ӿ�
    input  wire         dev_wrdy,    // ����д׼�������ź�
    output reg  [ 3:0]  dev_wen,     // ����дʹ��
    output reg  [31:0]  dev_waddr,   // ����д��ַ
    output reg  [31:0]  dev_wdata,   // ����д����
    
    // ����������߽ӿ�  
    input  wire         dev_rrdy,    // �����׼�������ź�
    output reg  [ 3:0]  dev_ren,     // �����ʹ��
    output reg  [31:0]  dev_raddr,   // �������ַ
    input  wire         dev_rvalid,  // �����������Ч�ź�
    input  wire [`BLK_SIZE-1:0] dev_rdata  // ���������128λ������
);

    // �ж��Ƿ�Ϊ�ǻ�����ʣ������ַ�ռ�0xFFFFxxxx��
    wire uncached = (data_addr[31:16] == 16'hFFFF) & 
                   (data_ren != 4'h0 | data_wen != 4'h0) ? 1'b1 : 1'b0;

`ifdef ENABLE_DCACHE    /******** ��Ҫ�޸Ĵ��д��� ********/

    //---------------- ����Ԫ���ݴ��� ----------------//
    wire [4:0] tag_from_cpu   = data_addr[14:10]; // ��ַ��tag�ֶΣ�bit14-10��
    wire [1:0] offset         = data_addr[3:2];   // ��ƫ������ѡ��128λ���е�32λ�֣�
    wire       valid_bit      = cache_line_r[133]; // ��������Чλ����133λ��
    wire [4:0] tag_from_cache = cache_line_r[132:128]; // �����д洢��tag��bit132-128��

    //---------------- ��״̬������ ----------------//
    parameter R_IDLE = 0;     // ����״̬
    parameter R_TAG_CHK = 1; // tag���״̬
    parameter R_REFILL = 2;   // �������״̬
    reg [1:0] r_state, r_next; // ��ǰ״̬����һ״̬

    // �����ж��߼�
    wire hit_r = (valid_bit && (tag_from_cpu == tag_from_cache)) && 
                (r_state == R_TAG_CHK) && !uncached; // ����������
    wire hit_w = (valid_bit && (tag_from_cpu == tag_from_cache)) && 
                (w_state == W_TAG_CHK) && !uncached; // д��������

    //---------------- �����ݴ����߼� ----------------//
    always @(*) begin
        data_valid = hit_r; // ������ʱ������Ч
        // ����offsetѡ�񻺴���е��ض�32λ��
        case (offset)
            2'b00: data_rdata = { // ѡ����ڵ�0�֣�bit31-0��
                (ren_next[3] ? cache_line_r[31:24] : 8'h0),
                (ren_next[2] ? cache_line_r[23:16] : 8'h0),
                (ren_next[1] ? cache_line_r[15:8]  : 8'h0),
                (ren_next[0] ? cache_line_r[7:0]   : 8'h0)};
            // ���ƴ�������offset���...
        endcase
    end

    //---------------- ����洢������ź� ----------------//
    reg [133:0] cache_w; // ��д�뻺������ݣ�134λ=1��Чλ+5tag+128���ݣ�
    wire  cache_we = ((r_state == R_REFILL) && dev_rvalid) || write; // дʹ������
    wire [5:0] cache_index = data_addr[9:4]; // ����������bit9-4����6λ��
    wire [133:0] cache_line_w = write? cache_w : // ѡ��д�����ݣ�д���и��»��������
                               {1'b1, data_addr[14:10], dev_rdata};
    wire [133:0] cache_line_r; // �ӻ����ȡ��������

    // ʵ����Block RAM�洢�壨˫�˿�RAM��
    blk_mem_gen_1 U_dsram (
        .clka   (cpu_clk),     // ʱ��
        .wea    (cache_we),    // дʹ��
        .addra  (cache_index), // 6λ��ַ
        .dina   (cache_line_w), // д������
        .douta  (cache_line_r)  // ��������
    );

    //---------------- ��״̬�������߼� ----------------//
    // ״̬�Ĵ�������
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if(cpu_rst) r_state <= R_IDLE; // ��λ������
        else r_state <= r_next;        // ����״̬ת��
    end

    // ״̬ת�������ж�
    always @(*) begin
        case(r_state)
            R_IDLE: r_next = (|data_ren) ? R_TAG_CHK : R_IDLE; // �ж�����ʱ������
            R_TAG_CHK: begin
                if (hit_r || uncached) r_next = R_IDLE;  // ���л�ǻ�����ʷ���
                else r_next = dev_rrdy ? R_REFILL : R_TAG_CHK; // δ�������������ʱ���
            end
            R_REFILL: r_next = dev_rvalid ? R_TAG_CHK : R_REFILL; // �ȴ��������ݷ���
        endcase
    end

    //---------------- ����������ź����� ----------------//
    reg [3:0] ren_next; // �����ʹ���ź�
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_valid <= 0;
            dev_ren <= 0;
        end else begin
            case(r_state)
                R_IDLE: begin // ������������
                    ren_next <= data_ren;
                    dev_ren <= 0;
                end
                R_TAG_CHK: begin
                    if(!hit_r && dev_rrdy) begin // ���������ȡ
                        dev_raddr = {data_addr[31:4], 4'b0}; // ���뵽���ַ
                        dev_ren = ren_next;
                    end
                end
                R_REFILL: dev_ren <= 0; // �����ʹ��
            endcase
        end    
    end

    //---------------- д״̬������ ----------------//
    parameter W_IDLE = 0;    // ����
    parameter W_TAG_CHK = 1;  // tag���
    parameter W_REFILL = 2;   // ���
    parameter W_OVER = 3;     // ���
    reg [1:0] w_state, w_next;

    // д״̬�Ĵ�������
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if(cpu_rst) w_state <= W_IDLE;
        else w_state <= w_next;
    end

    //---------------- д״̬ת���߼� ----------------//
    always @(*) begin
        case(w_state)
            W_IDLE: w_next = (|data_wen) ? W_TAG_CHK : W_IDLE;
            W_TAG_CHK: w_next = dev_wrdy ? W_REFILL : W_TAG_CHK;
            W_REFILL: w_next = W_OVER;
            W_OVER: w_next = dev_wrdy ? W_IDLE : W_OVER;
        endcase
    end

    //---------------- д�����ź����� ----------------//
    reg [3:0] wen_next;  // ����дʹ��
    reg [31:0] data_next;// ����д����
    reg write;            // д���б�־
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_wresp <= 0;
            dev_wen <= 0;
            write <= 0;
        end else begin
            case(w_state)
                W_IDLE: begin // ����д����
                    if(|data_wen) begin
                        wen_next <= data_wen;
                        data_next <= data_wdata;
                    end
                end
                W_TAG_CHK: begin // ��������д
                    if(dev_wrdy) begin
                        dev_waddr = data_addr;
                        dev_wen = wen_next;
                        // ���ֽ�����д������
                        if (dev_wen[0]) dev_wdata[7:0] = data_next[7:0];
                        // ...���ƴ��������ֽ�...
                    end
                end
                W_OVER: data_wresp <= dev_wrdy; // д�����Ӧ
            endcase
        end    
    end

    //---------------- д���и��»����߼� ----------------//
    always @(posedge cpu_clk) begin
        if (hit_w) begin // ����ʱ���»�����
            cache_w = cache_line_r; // ����ԭ������
            case (offset)
                2'b00: begin // ���¿��ڵ�0��
                    if (dev_wen[0]) cache_w[7:0] = data_next[7:0];
                    // ...���ƴ��������ֽ�...
                end
                // ...����offset���...
            endcase
            write = 1; // ��������д��
        end
    end

/******** δ�޸ĵ�ԭʼ�����ѱ��� ********/
`else 
    // ...��ԭ��δ���û���ʱ���뱣�ֲ��䣩...
`endif

endmodule
