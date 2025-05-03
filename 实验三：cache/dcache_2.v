// �������ʱ�䵥λ1ns������1ps
`timescale 1ns / 1ps

// ���ݻ���ģ�飨DCache��
module DCache(
    // ʱ�Ӻ͸�λ
    input  wire         cpu_clk,    // ��ʱ�ӣ������ش�����
    input  wire         cpu_rst,    // �ߵ�ƽ��Ч��λ�ź�
    
    // CPU�ӿ�
    input  wire [3:0]   data_ren,   // ��ʹ���źţ�4λ���룬֧���ֽ�/����/�ֶ���
    input  wire [31:0]  data_addr,  // 32λ�ڴ��ַ����д���ã�
    output reg          data_valid, // ������Ч�źţ�1-�����ݾ�����
    output reg  [31:0]  data_rdata, // 32λ����������
    input  wire [3:0]   data_wen,   // дʹ���źţ�4λ���룬֧���ֽ�/����/��д��
    input  wire [31:0]  data_wdata, // 32λд��������
    output reg          data_wresp, // д��Ӧ�źţ�1-д������ɣ�
    
    // ����д�ӿ�
    input  wire         dev_wrdy,   // ����д׼�������ź�
    output reg  [3:0]   dev_wen,    // ����дʹ���ź�
    output reg  [31:0]  dev_waddr,  // ����д��ַ
    output reg  [31:0]  dev_wdata,  // ����д����
    
    // ������ӿ�
    input  wire         dev_rrdy,   // �����׼�������ź�
    output reg  [3:0]   dev_ren,    // �����ʹ���ź�
    output reg  [31:0]  dev_raddr,  // �������ַ
    input  wire         dev_rvalid, // �����������Ч�ź�
    input  wire [`BLK_SIZE-1:0] dev_rdata  // ������������ߣ����С�ɺ궨�壩
);

// �ǻ�������ж��߼������ʵ�ַ��16λΪFFFFʱֱͨ���棩
wire uncached = (data_addr[31:16] == 16'hFFFF) & (data_ren != 4'h0 | data_wen != 4'h0) ? 1'b1 : 1'b0;

// �������ݻ��湦�ܵķ�֧
`ifdef ENABLE_DCACHE
    // �����������
    localparam TAG_WIDTH = 5;      // ��ַ��ǩλ����ַλ[14:10]��
    localparam INDEX_WIDTH = 6;     // ����λ��6λ=64�������У�
    localparam OFFSET_WIDTH = 4;    // ����ƫ��λ��4λ=16�ֽ��д�С��
    localparam CACHE_LINES = 64;    // �ܻ���������2^6=64��

    // ��ǩ�洢���У�ÿ����Ŀ������1λ��Чλ + TAG_WIDTHλ��ǩ��
    reg [TAG_WIDTH:0] cache_tags [0:CACHE_LINES-1];

    // ��ַ�ֽⵥԪ
    wire [INDEX_WIDTH-1:0] cache_index = data_addr[INDEX_WIDTH + OFFSET_WIDTH-1:OFFSET_WIDTH]; // [9:4]
    wire [TAG_WIDTH-1:0] tag_from_cpu = data_addr[14:15-TAG_WIDTH];  // [14:10]
    wire [OFFSET_WIDTH-1:0] offset = data_addr[OFFSET_WIDTH-1:0];     // [3:0]

    // ������״̬�ź�
    wire valid_bit = cache_tags[cache_index][TAG_WIDTH];      // ��Чλ�����λ��
    wire [TAG_WIDTH-1:0] tag_from_cache = cache_tags[cache_index][TAG_WIDTH-1:0]; // �洢�ı�ǩ

    // ״̬�����壨��������
    reg [3:0] IDLE_R=4'b0000,      // ������״̬
             TAG_CHECK_R=4'b0001,  // ��ǩ���״̬
             WAIT_R=4'b0010,       // �ȴ�����״̬
             REFILL_R=4'b0011,     // ���������״̬
             UNCACHED_READ=4'b1000;// �ǻ����ģʽ

    // ״̬�����壨д������
    reg [3:0] IDLE_W=4'b0100,      // д����״̬
             TAG_CHECK_W=4'B0101,  // д��ǩ���
             WRITE_BACK=4'b0110,   // д��������״̬
             ALLOCATE=4'b0111,     // ��������״̬
             UNCACHED_WRITE=4'b1001, // �ǻ���дģʽ
             WAIT_W=4'b1010,       // д�ȴ�״̬
             HIT_W=4'b1011,        // д����״̬
             WRITE_BACK1=4'b1100,  // д�ؽ׶�1
             WRITE_BACK2=4'b1101,  // д�ؽ׶�2
             WRITE_BACK3=4'B1110;  // д�ؽ׶�3

    // ״̬�Ĵ���
    reg [3:0] cur_state_r, next_state_r; // ��״̬����ǰ/��һ״̬
    reg [3:0] cur_state_w, next_state_w; // д״̬����ǰ/��һ״̬

    // �����ж��߼�
    wire hit_r = (|dev_ren || |ren_reg) && (tag_from_cache == tag_from_cpu) && valid_bit && !uncached; // ������
    wire hit_w = (|dev_wen || |wen_reg) && (tag_from_cache == tag_from_cpu) && valid_bit && !uncached; // д����

    // ���ݼĴ���
    reg [31:0] rdata_reg;   // �������ݴ���
    reg [3:0]  ren_reg;     // ��ʹ���ݴ���

    // �������ѡ���߼�
    always @(*) begin
        data_rdata = rdata_reg;  // ����ݴ�������
    end

    // ����д�����ź�
    wire cache_we = (hit_w && (cur_state_w == HIT_W)) || dev_rvalid; // д���������л����淵��
    reg  [127:0] cache_line_to_be_written; // ��д�������ݣ�д����ʱ���죩
    wire [127:0] cache_line_w = (cur_state_w == HIT_W) ? cache_line_to_be_written : dev_rdata; // д������ѡ��

    // ����洢��ӿ�
    wire [127:0] cache_line_r;  // �ӻ����ȡ��������

    // ���־λ�Ĵ�������ǻ������Ƿ��޸ģ�
    reg [CACHE_LINES-1:0] dirty;

    // Block RAMʵ������ʵ�ʻ���洢�壩
    blk_mem_gen_1 U_dsram (
        .clka   (cpu_clk),    // ʱ������
        .wea    (cache_we),   // дʹ��
        .addra  (cache_index),// 6λ������ַ
        .dina   (cache_line_w), // 128λд������
        .douta  (cache_line_r)  // 128λ��ȡ����
    );

    // ��λ��ʼ���߼�
    always @(posedge cpu_clk or posedge cpu_rst) begin: RESET_LOGIC
        integer i;
        if (cpu_rst) begin
            // ������б�ǩ�����־
            for (i = 0; i < CACHE_LINES; i = i + 1) begin
                cache_tags[i] <= 0;  // ��Чλ����
                dirty[i]      <= 0;  // ���־����
            end
        end
    end

    // д���ݹ����߼�
    always @(*) begin
        if (cpu_rst) begin
            wdata = 32'h0;  // ��λʱд��������
        end else if (|data_wen) begin
            wdata = data_wdata;  // ����CPUд����
        end
    end

    // ������ѡ���߼�������ƫ��ѡ���������ݣ�
    always @(*) begin
        if (cpu_rst) begin
            rdata_reg = 32'h0;
        end else begin
            // ���ݸ�2λƫ��ѡ����������
            case(offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2])
                2'b00:  // 0-31λ����
                    case(ren_reg)
                        4'b0001: rdata_reg = cache_line_r[7:0];    // �ֽڶ�ȡ
                        4'b0011: rdata_reg = cache_line_r[15:0];  // ���ֶ�ȡ
                        4'b1111: rdata_reg = cache_line_r[31:0];  // ȫ�ֶ�ȡ
                    endcase
                2'b01:  // 32-63λ����
                    case(ren_reg)
                        4'b0001: rdata_reg = cache_line_r[39:32];
                        4'b0011: rdata_reg = cache_line_r[47:32];
                        4'b1111: rdata_reg = cache_line_r[63:32];
                    endcase
                2'b10:  // 64-95λ����
                    case(ren_reg)
                        4'b0001: rdata_reg = cache_line_r[71:64];
                        4'b0011: rdata_reg = cache_line_r[79:64];
                        4'b1111: rdata_reg = cache_line_r[95:64];
                    endcase
                2'b11:  // 96-127λ����
                    case(ren_reg)
                        4'b0001: rdata_reg = cache_line_r[103:96];
                        4'b0011: rdata_reg = cache_line_r[111:96];
                        4'b1111: rdata_reg = cache_line_r[127:96];
                    endcase
            endcase
        end
    end

    // д�������ݹ����߼����ϲ������ݵ������У�
    always @(*) begin
        if (cpu_rst) begin
            cache_line_to_be_written = 128'h0;
        end else begin
            case(offset[OFFSET_WIDTH-1:OFFSET_WIDTH-2])
                2'b00:  // �޸�0-31λ����
                    case(wen_reg)
                        4'b0001: cache_line_to_be_written = {cache_line_r[127:8], wdata[7:0]};    // �ֽ�д��
                        4'b0011: cache_line_to_be_written = {cache_line_r[127:16], wdata[15:0]};  // ����д��
                        4'b1111: cache_line_to_be_written = {cache_line_r[127:32], wdata[31:0]};  // ȫ��д��
                    endcase
                2'b01:  // �޸�32-63λ����
                    case(wen_reg)
                        4'b0001: cache_line_to_be_written = {cache_line_r[127:40], wdata[7:0], cache_line_r[31:0]};
                        4'b0011: cache_line_to_be_written = {cache_line_r[127:48], wdata[15:0], cache_line_r[31:0]};
                        4'b1111: cache_line_to_be_written = {cache_line_r[127:64], wdata[31:0], cache_line_r[31:0]};
                    endcase
                2'b10:  // �޸�64-95λ����
                    case(wen_reg)
                        4'b0001: cache_line_to_be_written = {cache_line_r[127:72], wdata[7:0], cache_line_r[63:0]};
                        4'b0011: cache_line_to_be_written = {cache_line_r[127:80], wdata[15:0], cache_line_r[63:0]};
                        4'b1111: cache_line_to_be_written = {cache_line_r[127:96], wdata[31:0], cache_line_r[63:0]};
                    endcase
                2'b11:  // �޸�96-127λ����
                    case(wen_reg)
                        4'b0001: cache_line_to_be_written = {cache_line_r[127:104], wdata[7:0], cache_line_r[95:0]};
                        4'b0011: cache_line_to_be_written = {cache_line_r[127:112], wdata[15:0], cache_line_r[95:0]};
                        4'b1111: cache_line_to_be_written = {wdata[31:0], cache_line_r[95:0]};
                    endcase
            endcase
        end
    end

        // DCache��״̬��״̬�Ĵ��������߼�
    // ��ÿ��ʱ�������ػ�λ�ź���Чʱ���µ�ǰ״̬
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cur_state_r <= IDLE_R;  // ��λʱǿ�ƻع��ʼ״̬
        end else begin
            cur_state_r <= next_state_r;  // ��������ʱ״̬ת��
        end
    end

    // DCache��״̬��״̬ת���߼�
    // ����߼�ʵ��״̬��ת�����ж�
    always @(*) begin
        case (cur_state_r)
            IDLE_R: begin  // ��ʼ״̬
                if(uncached && data_ren!=0)begin
                    next_state_r = UNCACHED_READ;  // �ǻ��������ֱ��͸��
                end
                else if (data_ren!=0) begin
                    next_state_r = TAG_CHECK_R;     // ���������������ǩ���
                end else begin
                    next_state_r = IDLE_R;          // �����󱣳ֿ���
                end
            end
            TAG_CHECK_R: begin  // ��ǩ���״̬
                if (hit_r) begin
                    next_state_r = WAIT_R;         // ����ֱ�ӽ���ȴ����
                end else if (dev_rrdy) begin
                    next_state_r = REFILL_R;       // ��������������������
                end else begin
                    next_state_r = TAG_CHECK_R;    // �ȴ�����׼������
                end
            end
            REFILL_R: begin  // ���������״̬
                if (dev_rvalid) begin
                    next_state_r = WAIT_R;        // ��������������ת�ȴ�
                end else begin
                    next_state_r = REFILL_R;       // ����������������
                end
            end
            WAIT_R:begin     // ���ݾ���״̬
                next_state_r = IDLE_R;           // ����������������
            end
            UNCACHED_READ: begin  // �ǻ����ģʽ
                if (dev_rvalid) begin
                    next_state_r = WAIT_R;       // ���淵������ת�ȴ�
                end else begin
                    next_state_r = UNCACHED_READ; // �����ȴ�������Ӧ
                end
            end
            default: next_state_r = IDLE_R;      // �쳣״̬��ȫ�ָ�
        endcase
    end

    // DCache��״̬����������߼�
    // ʱ���߼������ȶ�����ź�
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin  // ��λ��ʼ��
            dev_ren <= 4'h0;       // ���������
            dev_raddr <= 32'b0;    // ��ն���ַ
            data_valid <= 1'b0;    // ������Ч
            ren_reg <= 0;          // ��ն�ʹ�ܻ���
        end else begin
            case (cur_state_r)
                IDLE_R: begin
                    if(hit_r)begin  // �������д���
                        dev_ren <= 4'h0;        // �����������
                        dev_raddr <= 32'h0;     // ��յ�ַ����
                        data_valid <= 1'b0;     // �ӳ�������Ч�ź�
                    end else begin
                        dev_ren <= 4'h0;        // ��ʼ״̬���ö�
                        dev_raddr <= dev_ren!=0 ? data_addr : 32'h0; // ��ַԤ����
                        data_valid <= 1'b0;     // ������δ����
                        ren_reg <= data_ren;    // �����ʹ���ź�
                    end
                end
                TAG_CHECK_R: begin
                    if (hit_r) begin  // ���д���
                        dev_ren <= 4'h0;        // ���ֶ���ֹ
                        dev_raddr <= 32'h0;     // ��ַ������
                        data_valid <= 1'b0;    // �ȴ����ڽ���������Ч
                    end else if (!hit_r && dev_rrdy) begin  // ȱʧ����
                        dev_ren <= 4'hF;        // ͻ����ʹ��(4�ֶ�ȡ)
                        dev_raddr <= {tag_from_cpu, cache_index, 4'b0000}; // �����ַ����
                        data_valid <= 1'b0;     // ������δ����
                    end
                end
                REFILL_R: begin  // ���������׶�
                    if (dev_rvalid) begin
                        data_valid = 1'b0;       // ׼����һ�׶����
                        cache_tags[cache_index] <= {1'b1, tag_from_cpu}; // ���±�ǩ��
                    end
                    dev_ren <= 4'h0;  // ֹͣ�������
                end
                WAIT_R:begin  // ���ݾ����׶�
                    data_valid  <= 1'b1;  // ��CPU����������Ч
                end
                UNCACHED_READ: begin  // �ǻ����͸��ģʽ
                    dev_ren <= data_ren;      // ֱ�Ӵ��ݶ�ʹ��
                    dev_raddr <= data_addr;   // ͸��ԭʼ��ַ
                    if (dev_rvalid) begin    // ������Ӧ����
                        data_rdata <= dev_rdata[31:0]; // ��ȡ��Ч���ݶ�
                        data_valid <= 1'b1;  // ���������Ч
                        dev_ren <= 4'h0;     // ����������
                    end
                end
                default: begin  // �쳣״̬����
                    data_valid <= 1'b0;  // ��֤������Ч
                    dev_ren <= 4'h0;     // ���������
                end
            endcase
        end
    end

    ///////////////////////////////////////////////////////////
    // DCacheд״̬��״̬�Ĵ��������߼�
    // ʱ���߼�ʵ��״̬�Ĵ�������
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cur_state_w <= IDLE_W;  // ��λ�ع��ʼ״̬
        end else begin
            cur_state_w <= next_state_w;  // ����״̬ת��
        end
    end

    // DCacheд״̬��״̬ת���߼�
    // ����߼�ʵ��״̬��ת�����ж�
    always @(*)begin
        case(cur_state_w)
        IDLE_W:begin  // д����״̬
            if(data_wen!=0)begin
               next_state_w = uncached ? UNCACHED_WRITE : TAG_CHECK_W; // �ǻ���д͸��/����д���
            end
            else next_state_w = IDLE_W;  // �����󱣳ֿ���
        end
        TAG_CHECK_W:begin  // ��ǩ���״̬
            if(hit_w)begin
                next_state_w = HIT_W;     // д����ֱ���޸�
            end
            else if(!hit_w && dirty[cache_index]&& dev_wrdy)begin
                next_state_w = WRITE_BACK; // ��������д������
            end
            else if(!hit_w && !dirty[cache_index] && dev_wrdy)begin
                next_state_w = ALLOCATE;   // �ɾ���ֱ�ӷ���
            end
            else begin
                next_state_w = TAG_CHECK_W; // �ȴ�����׼��
            end
        end
        WAIT_W:begin  // д�ȴ�״̬
            if(dev_wrdy)begin
            next_state_w = IDLE_W;  // ������Ӧ���
            end
            else next_state_w = WAIT_W; // �ȴ�����ȷ��
        end
        WRITE_BACK:begin  // ������д�ؽ׶�
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK1; // �����Ľ׶�д��
            end
            else begin
                next_state_w = WRITE_BACK; // �ȴ��������
            end
        end
        WRITE_BACK1:begin  // д�ص�һ��(0-31λ)
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK2; 
            end
            else begin
                next_state_w = WRITE_BACK1;
            end
        end
        WRITE_BACK2:begin  // д�صڶ���(32-63λ)
            if(dev_wrdy)begin
                next_state_w =WRITE_BACK3;
            end
            else begin
                next_state_w = WRITE_BACK2;
            end
        end
        WRITE_BACK3:begin  // д�ص�����(64-95λ)
            if(dev_wrdy)begin
                next_state_w =ALLOCATE;    // ת�����з���
            end
            else begin
                next_state_w = WRITE_BACK3;
            end
        end
        HIT_W:begin  // д���д���״̬
            next_state_w = WAIT_W;  // ��������ɸ���
        end
        ALLOCATE:begin  // �����з���״̬
            if(dev_rvalid)begin
                next_state_w = TAG_CHECK_W; // ����������¼��
                end
            else begin
                next_state_w = ALLOCATE;   // �ȴ��������ݼ���
            end
        end 
        UNCACHED_WRITE: begin  // �ǻ���д͸��ģʽ
            if (dev_wrdy) begin
                next_state_w = WAIT_W;    // �����������
            end else begin
                next_state_w = UNCACHED_WRITE; // �����ȴ�
            end
        end
        default:next_state_w = IDLE_W;    // �쳣״̬�ָ�
        endcase
    end
    // дʹ���ź��ݴ��������߼�
    // ����߼�ʵ��wen_reg����
    always@(*)begin
        if(cpu_rst)begin
            wen_reg = 0;          // ��λʱ����
        end
        else if (data_wen != 0)begin
            wen_reg = data_wen;  // ����CPUдʹ���ź�
        end
        else if(data_wresp == 1'b1)begin
            wen_reg = 0;         // д������ɺ��ͷ�
        end
    end

    // DCacheд״̬������ź�����
    // ʱ���߼������ȶ�������ź�
    always @(posedge cpu_clk or posedge cpu_rst)begin
        if(cpu_rst)begin  // ��λ��ʼ��
            dev_wen <= 4'b0;     // ��������д
            dev_waddr <= 32'h0;  // ���д��ַ
            dev_raddr <= 32'h0;  // ��ն���ַ
            dev_wdata <= 32'h0;  // ���д����
            data_valid <= 0;     // ������Ч
            data_wresp <= 0;     // д��Ӧ��Ч
        end
        case(cur_state_w)
        IDLE_W:begin  // д����״̬
                dev_waddr <= data_addr;  // Ԥ����д��ַ
                data_wresp <= 0;         // ���д��Ӧ
                if(uncached)begin         // �ǻ���д͸��
                    dev_wdata <= data_wdata; // ֱͨд����
                    dev_wen <= data_wen;     // ֱͨдʹ��
                end
                else begin                // ����дģʽ
                    dev_wen <= 0;          // ��������д
                end
        end
        TAG_CHECK_W:begin  // ��ǩ���״̬
            if(hit_w)begin  // д���д���
                dev_wen <= 0;  // �����������
                dev_ren <= 0;  // ���������
            end
            else if(!hit_w && dirty[cache_index]&& dev_wrdy)begin 
                // дȱʧ�����У����յȴ�д��״̬������
            end
            else if(!hit_w && !dirty[cache_index] && dev_wrdy)begin
                dev_ren <= 4'hf;         // ���������з����
                dev_raddr <= data_addr;   // ���÷����ַ
            end
        end
        HIT_W:begin  // д���и���״̬
            dirty[cache_index] <= 1'b1;               // �����λ
            cache_tags[cache_index] <= {1'b1,tag_from_cpu}; // ���±�ǩ
        end
        WAIT_W:begin  // д�ȴ�״̬
            if(dev_wrdy)begin
                data_wresp <= 1'b1;  // д�������ȷ��
                dev_wen <= 0;        // �ر�����д
            end
        end
        WRITE_BACK:begin  // д�ؽ׶�0��32-63λ���ݣ�
            if(dev_wrdy)begin
                dev_wen <= 4'hf;                   // ʹ������д
                dev_wdata <= cache_line_r[31:0];    // д�����ݿ�0
                dev_waddr <= {tag_from_cache,cache_index, 4'b0000}; // ����д��ַ
            end
        end
        WRITE_BACK1:begin  // д�ؽ׶�1��64-95λ���ݣ�
            if(dev_wrdy)begin
                dev_wen <= 4'hf;                   
                dev_wdata <= cache_line_r[63:32];   // д�����ݿ�1
                dev_waddr <= {tag_from_cache,cache_index, 4'b0100}; // ��ַƫ��+4
            end
        end
        WRITE_BACK2:begin  // д�ؽ׶�2��96-127λ���ݣ�
            if(dev_wrdy)begin
                dev_wen <= 4'hf;                   
                dev_wdata <= cache_line_r[95:64];   // д�����ݿ�2
                dev_waddr <= {tag_from_cache,cache_index, 4'b1000}; // ��ַƫ��+8
            end
        end
        WRITE_BACK3:begin  // д�ؽ׶�3��128-159λ���ݣ�
            if(dev_wrdy)begin
                dev_wen <= 4'hf;                   
                dev_wdata <= cache_line_r[127:96];  // д�����ݿ�3
                dev_waddr <= {tag_from_cache,cache_index, 4'b1100}; // ��ַƫ��+12
            end
        end
        ALLOCATE:begin  // �����з���״̬
            if(dev_rvalid)begin
                dirty[cache_index] <= 1'b0;        // ���г�ʼΪ�ɾ�
                cache_tags[cache_index]<= {1'b1, tag_from_cpu}; // ���±�ǩ
            end
            else begin
                dev_ren  <= 4'h0;  // ������ɺ���ö�
            end
        end
       UNCACHED_WRITE: begin  // �ǻ���д͸��ģʽ
                dev_wen <= 0;  // ��ͨ��IDLE_W�׶����д����
            end
        default:begin
            dev_wen <= 4'b0;  // Ĭ�Ͻ�������д
        end
        endcase
    end
