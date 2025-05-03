`timescale 1ns / 1ps

module fpu(
    input  wire         rst,    // �ߵ�ƽ��λ
    input  wire         clk,
    input  wire         start,  // startΪ1ʱ����ʼ����
    input  wire         op,     // Ϊ0ʱ��, Ϊ1ʱ��
    input  wire [31:0]  A,      // �������
    input  wire [31:0]  B,      // �Ҳ�����
    output reg          ready,  // ��λ��������ʱreadyΪ1����⵽startΪ1ʱ��Ϊ0
    output wire [31:0]  C       // ������
);



localparam IDLE     = 4'b0000;    // ����״̬
localparam Pre      =4'b0001;    //�ֽ�
localparam S1    = 4'b0010;     // ��ײ�
localparam S2    = 4'b0011;     // �Խ�
localparam S3     = 4'b0100;      // β������
localparam S4     = 4'b0101;     // ���
localparam fin     = 4'b0110;     // ������������

reg [3:0] state;               // ��ǰ״̬�Ĵ���
reg [3:0] next_state;          // ��̬�Ĵ���



reg        sign_A, sign_B;      // ����λ��1:����0:����
reg [7:0]  exp_A, exp_B;        // ָ�����֣�8λ��ƫ��127��
reg [23:0] m_A, m_B;            // β����23λ��ʽ + 1λ��ʽ��


reg [7:0]  exp_diff;            // ָ����ֵ�����ڶԽף�
reg [7:0]  final_exp;           // ����ָ����ȡ�ϴ�ָ����
reg [24:0] am_A, am_B;         // ������β����������λ��
reg [24:0] sum;               // β���ͣ�25λ��1λ��λ+24λ��Ч��
reg        result_sign;         // �������λ


reg [31:0] C_reg;             // �������Ĵ���

// ״̬����
always @(posedge clk or posedge rst) begin
    if (rst) state <= IDLE;
    else     state <= next_state;
end

// ��̬����
always @(*) begin
    case (state)
        IDLE:  next_state = (start | ready==1'b0) ? Pre : IDLE;  // �����źŴ���
        Pre: next_state = S1;
        S1: next_state = S2;                   
        S2: next_state = S3;   
        S3:  next_state = S4;
        S4:  begin
            if(sum[23] || (final_exp == 0))begin
                next_state =fin;      //����λΪ1���߽���Ϊ0����Ϊ������ɣ�������һ���׶�
            end
            else begin
                next_state = S4;     //��δ��ɣ���һֱ����
            end
        end                    
        fin:next_state = IDLE;
        default: next_state = IDLE;
    endcase
end


always @(posedge clk or posedge rst) begin
    if (rst) begin  // ��λ��ʼ��
        {sign_A, exp_A, m_A} <= {1'b0, 8'd0, 24'd0};
        {sign_B, exp_B, m_B} <= {1'b0, 8'd0, 24'd0};
        exp_diff     <= 8'd0;
        am_A    <= 25'd0;
        am_B    <= 25'd0;
        sum <= 25'd0;                         //��λ�źŽ��г�ʼ��
        final_exp    <= 8'd0;
        result_sign  <= 1'b0;
        C_reg        <= 32'd0;
    end else begin
        case (state)
            // IDLE״̬���ȴ������ź�
            IDLE: begin
                ready <= 1'b1;  // �������
                if (start) begin
                    ready <= 1'b0;  // ���빤��״̬
                end
            end

            Pre:begin   //�ֽ������ź�
                // ����A�ķ��š�ָ����β��
                sign_A     <= A[31];             // ����λ
                exp_A      <= (A[30:23]==8'b0)?8'd1:A[30:23];          // ָ�����ִ��������ǹ����
                m_A <= (A[30:23]==8'b0)?{1'b0, A[22:0]}:{1'b1, A[22:0]};   // ����������1.xxx��ʽ�����ǹ������ǰ��0
                
                // ����B�ķ��ţ�����ʱȡ����
                sign_B     <= op ? ~B[31] : B[31]; 
                //���ڼ�������ȡ��
                //�ں�������׶Σ����������������ͬ����˵��ԭʼ����ʽΪһ��������ȥһ����������һ��������ȥһ������
                //��������ֱ�ӵ����ӷ����㼴�ɣ���������׶η��Ų�ͬ����Ϊһ��������һ����������һ��������һ��������
                //���Ե�����������
                exp_B      <= (B[30:23]==8'b0)?8'd1:B[30:23];     //ͬ��
                m_B <= (B[30:23]==8'b0)?{1'b0, B[22:0]}:{1'b1, B[22:0]};    //ͬ��
            end

            // S1״̬����ײ�
            S1: begin
                // ����ָ����ֵ
                exp_diff <= (exp_A >= exp_B) ? (exp_A - exp_B) : (exp_B - exp_A);
            end
            
            // S2״̬���Խ״���
            S2: begin
                // ����β����Сָ�����ָ�����룩
                if (exp_A >= exp_B) begin
                    final_exp <= exp_A;
                    am_A <= m_A;             // ��ָ�����ֲ���
                    am_B <= m_B >> exp_diff; // Сָ�����ƶ���
                end else begin
                    final_exp <= exp_B;
                    am_A <= m_A >> exp_diff;  // ���ƶ���
                    am_B <= m_B;
                end
            end
            // S3״̬��β������
            S3: begin
                // ������ִͬ�мӷ�������ִ�м���
                if (sign_A == sign_B) begin
                    sum <= am_A + am_B; 
                    result_sign  <= sign_A;
                end else begin
                    // ��űȽ�β����С//�൱��ִ�м���
                    if (am_A >= am_B) begin
                        sum <= am_A - am_B;
                        result_sign  <= sign_A;
                    end else begin
                        sum <= am_B - am_A;
                        result_sign  <= sign_B;
                    end
                end
                
            end
            
            S4:begin    //���
                if (sum[24]) begin   //����ӷ���� 
                    sum <= sum >> 1; // ����һλ
                    final_exp    <= final_exp + 1;     // ָ����1
                end 
                else begin
                    if(~sum[23])begin     //��Ҫ������洦��
                        if(final_exp > 1'b1)begin
                            sum <= sum << 1;
                            final_exp    <= final_exp - 1;
                        end else if(final_exp == 1'b1)begin
                            //�˴�Ϊ������������������棬���ܳ���
                            //sum[23]����1�����������0��������ⲻ�Ƿǹ������
                            //����ʵ���������������õ��ǹ�����Ľ��������ֻ�����벻����
                            final_exp    <= final_exp - 1;
                        end
                    end
                end
            end
            fin:begin
                C_reg <= {result_sign, final_exp, sum[22:0]};    //������
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
