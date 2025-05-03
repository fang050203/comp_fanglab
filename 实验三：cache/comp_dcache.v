`timescale 1ns / 1ps

`include "defines.vh"

//      ?         15bit
// Cache      127B
// Cache       256bit (8*32bit)
// Cache       ?

module DCache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active
    // Interface to CPU
    input  wire [ 3:0]  data_ren,       //     CPU ? ?   ? 
    input  wire [31:0]  data_addr,      //     CPU ? ?           ? 
    output reg          data_valid,     //      CPU           ? 
    output reg  [31:0]  data_rdata,     //      CPU ?     
    input  wire [ 3:0]  data_wen,       //     CPU    ?   ? 
    input  wire [31:0]  data_wdata,     //     CPU        
    output reg          data_wresp,     //      CPU      ?   ? ?  ?DCache             
    // Interface to Write Bus
    input  wire         dev_wrdy,       //     /            ??  ? ?  ?    /    ?   DCache        
    output reg  [ 3:0]  cpu_wen,        //          /       ?   ? 
    output reg  [31:0]  cpu_waddr,      //          /         ?
    output reg  [31:0]  cpu_wdata,      //          /           
    // Interface to Read Bus
    input  wire         dev_rrdy,       //     /    ?      ??  ? ?  ?    /    ?   DCache ?     
    output reg  [ 3:0]  cpu_ren,        //          /    ? ?   ? 
    output reg  [31:0]  cpu_raddr,      //          /    ?   ?
    input  wire         dev_rvalid,     //         /              ? 
    input  wire [255:0] dev_rdata       //         /    ?     
);

    // Peripherals access should be uncached.
    wire uncached = (data_addr[31:16] == 16'hFFFF) & (data_ren != 4'h0 | data_wen != 4'h0) ? 1'b1 : 1'b0;
    //     
`ifdef ENABLE_DCACHE    /********   ? ??        ********/

    // TODO:     DCache ?   
    reg   valid[3:0] ;          //       
    reg [7:0] tag  [3:0];     //    ?
    reg [255:0] data [3:0];     //    ? 
    //reg [264:0]cache_set_0;
    //reg [264:0]cache_set_1;
    //reg [264:0]cache_set_2;
    //reg [264:0]cache_set_3;
    // TODO:     DCache  ??    ??  ??    
    localparam R_IDLE=2'b00;
    localparam R_TAG_CHK=2'b01;
    localparam R_REFILL=2'b10;
    reg [1:0] r_state,r_state_n;    //??     ? ??   


    // TODO:      ? ? 

    wire [7:0] tag_from_cpu   = data_addr[14:7];     //      ?  TAG
    wire [1:0] cache_index    = data_addr[6:5];     //      ?  Cache     / ICache ?   ? ?
    wire [4:0] offset         = data_addr[4:0];     // 32    ?    

    reg [264:0] cache_line_r;                   //   ICache ?   0      Cache  
    wire [264:0] cache_line_w = write ? cache_w :{dev_rvalid,tag_from_cpu,dev_rdata};      //   ICache ?   1      Cache  
    wire r_valid =  cache_line_r[264];     // Cache   ? 0         
    wire [7:0] tag_from_r  = cache_line_r[263:256];     // Cache   ? 0   TAG
    //wire [12:0] tag_from_w  = cache_line_w[140:128];     // Cache   ? 1   TAG



    reg [264:0]cache_w;    //      ?   

    wire  cache_we = dev_rvalid || write; //   ?      

    wire hit_r = r_valid && (tag_from_cpu == tag_from_r) && (r_state == R_TAG_CHK) &&!uncached;        //       
    wire hit_w = r_valid && (tag_from_cpu == tag_from_r) && (w_state == W_TAG_CHK) &&!uncached; 

    always @(*) begin
        data_valid = hit_r;
        case (offset[4:2])
            3'b000: data_rdata = { // ?    ? 0 ? bit31-0  
                (ren_next[3] ? cache_line_r[31:24] : 8'h0),
                (ren_next[2] ? cache_line_r[23:16] : 8'h0),
                (ren_next[1] ? cache_line_r[15:8]  : 8'h0),
                (ren_next[0] ? cache_line_r[7:0]   : 8'h0)};
            3'b001: data_rdata = { // ?    ? 0 ? bit31-0  
                (ren_next[3] ? cache_line_r[63:56] : 8'h0),
                (ren_next[2] ? cache_line_r[55:48] : 8'h0),
                (ren_next[1] ? cache_line_r[47:40]  : 8'h0),
                (ren_next[0] ? cache_line_r[39:32]   : 8'h0)};
            3'b010: data_rdata = { // ?    ? 0 ? bit31-0  
                (ren_next[3] ? cache_line_r[95:88] : 8'h0),
                (ren_next[2] ? cache_line_r[87:80] : 8'h0),
                (ren_next[1] ? cache_line_r[79:72]  : 8'h0),
                (ren_next[0] ? cache_line_r[71:64]   : 8'h0)};
            3'b011: data_rdata = { // ?    ? 0 ? bit31-0  
                (ren_next[3] ? cache_line_r[127:120] : 8'h0),
                (ren_next[2] ? cache_line_r[119:112] : 8'h0),
                (ren_next[1] ? cache_line_r[111:104]  : 8'h0),
                (ren_next[0] ? cache_line_r[103:96]   : 8'h0)};
            3'b100: data_rdata = { // ?    ? 0 ? bit31-0  
                (ren_next[3] ? cache_line_r[159:152] : 8'h0),
                (ren_next[2] ? cache_line_r[151:144] : 8'h0),
                (ren_next[1] ? cache_line_r[143:136]  : 8'h0),
                (ren_next[0] ? cache_line_r[135:128]   : 8'h0)};
            3'b101: data_rdata = { // ?    ? 0 ? bit31-0  
                (ren_next[3] ? cache_line_r[191:184] : 8'h0),
                (ren_next[2] ? cache_line_r[183:176] : 8'h0),
                (ren_next[1] ? cache_line_r[175:168]  : 8'h0),
                (ren_next[0] ? cache_line_r[167:160]   : 8'h0)};
            3'b110: data_rdata = { // ?    ? 0 ? bit31-0  
                (ren_next[3] ? cache_line_r[223:216] : 8'h0),
                (ren_next[2] ? cache_line_r[215:208] : 8'h0),
                (ren_next[1] ? cache_line_r[207:200]  : 8'h0),
                (ren_next[0] ? cache_line_r[199:192]   : 8'h0)};
            3'b111: data_rdata = { // ?    ? 0 ? bit31-0  
                (ren_next[3] ? cache_line_r[255:248] : 8'h0),
                (ren_next[2] ? cache_line_r[247:240] : 8'h0),
                (ren_next[1] ? cache_line_r[239:232]  : 8'h0),
                (ren_next[0] ? cache_line_r[231:224]   : 8'h0)};
        endcase
    end

    // TODO:     DCache  ??    ? ?    ? 
    always @(posedge cpu_clk or posedge cpu_rst) begin
        r_state<=cpu_rst?R_IDLE:r_state_n;
    end

    // TODO:     DCache  ??    ???   ?   ? ?   uncached   ? 
    always @(*) begin
        case (r_state)
            R_IDLE:    r_state_n=data_ren?R_TAG_CHK:R_IDLE;
            R_TAG_CHK:begin
                    if(dev_rrdy)r_state_n=(hit_r || uncached)?R_IDLE:R_REFILL;
                    else r_state_n=R_TAG_CHK;
                end
            R_REFILL:r_state_n=dev_rvalid?R_TAG_CHK:R_REFILL;
            default: r_state_n=R_IDLE;
        endcase
    end

    // TODO:     DCache  ??        ? 
    //    ??       
    reg[3:0]ren_next;   //   ?     ?   
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cpu_ren<=4'h0;
            cpu_raddr<=32'd0;
            ren_next<=4'b0000;
        end else begin
            case (r_state)
                R_IDLE:begin
                    cpu_ren<=4'h0;
                    cpu_raddr<=cpu_raddr;
                    ren_next<=data_ren;
                end
                R_TAG_CHK:begin
                if(dev_rrdy) begin
                    cpu_ren<={4{~data_valid}} & ren_next;
                    cpu_raddr<=data_valid? cpu_raddr:{data_addr[31:5],5'b0};//          
                    end
                else begin
                    cpu_ren<=4'h0;
                    cpu_raddr<=cpu_raddr;
                end
                end
                R_REFILL:begin
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




    // TODO:         Cache           ?     ?   ? 
    /*always@(posedge cpu_clk or posedge cpu_rst)begin
        if(cache_we)begin
            case(cache_index)
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
                cache_set_0 <=265'b0;
                cache_set_1 <=265'b0;
                cache_set_2 <=265'b0;
                cache_set_3 <=265'b0;
                cache_line_r <=265'b0;
            end
            else if(cache_set_0[264] & (cache_set_0[263:256]==tag_from_cpu))begin
                cache_line_r <=cache_set_0;
            end
            else if(cache_set_1[264] & (cache_set_1[263:256]==tag_from_cpu))begin
                cache_line_r <=cache_set_1;
            end
            else if(cache_set_2[264] & (cache_set_2[263:256]==tag_from_cpu))begin
                cache_line_r <=cache_set_2;
            end
            else if(cache_set_3[264] & (cache_set_3[263:256]==tag_from_cpu))begin
                cache_line_r <=cache_set_3;
            end
            else begin
                cache_line_r <= cache_line_r;
            end
        end
    end*/
    integer i;
    always@(posedge cpu_clk or posedge cpu_rst)begin
        if(cache_we)begin
            valid[cache_index]<=1'b1;
            tag[cache_index]<=cache_line_w[263:256];
            data[cache_index]<=cache_line_w[255:0];
            cache_line_r <= cache_line_w;
        end
        else begin
            if(cpu_rst)begin
                for (i = 0; i < 4; i = i + 1) begin
                    valid[i]<=1'b0;
                    tag[i] <= 8'b0;   //       ¦Ë?   tag ?  
                    data[i] <= 256'b0; //       ¦Ë?   data ?  
                    
                end
            end
            else begin
            cache_line_r[264]<= valid[cache_index];
            cache_line_r[263:256]<=tag[cache_index];
            cache_line_r[255:0]<=data[cache_index];
        end
    end
    end




    ///////////////////////////////////////////////////////////
    // TODO:     DCache  ??    ??    
    parameter W_IDLE = 3'b000;    //     
    parameter W_TAG_CHK = 3'b001;  // tag   
    parameter W_REFILL = 3'b010;   //    
    parameter W_OVER = 3'b011;     //    
    parameter W_WRE = 3'b100;     //   ? 
    reg [2:0] w_state, w_state_n;   //?? ?   
    reg write;                    //  ??

    // TODO:     DCache  ??      ?     ? 
     always @(posedge cpu_clk or posedge cpu_rst) begin
        w_state<=cpu_rst?R_IDLE:w_state_n;
    end

    // TODO:     DCache  ??    ???   ?   ? ?   uncached   ? 
    always @(*) begin
        case(w_state)
            W_IDLE: w_state_n = data_wen ? W_TAG_CHK : W_IDLE;
            W_TAG_CHK: w_state_n = dev_wrdy ? W_REFILL : W_TAG_CHK;
            W_REFILL: w_state_n = W_OVER; 
            W_OVER: w_state_n = dev_wrdy ? W_WRE : W_OVER;
            W_WRE  : w_state_n = W_IDLE;
        endcase
    end

    // TODO:     DCache  ??        ? 
    reg [3:0] wen_next;  //       ?  
    reg [31:0] data_next;//           
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_wresp <= 0;
            cpu_wen <= 0;
            write <= 0;
            cpu_waddr <= 0;
        end else begin
            case(w_state)
                W_IDLE: begin //           
                    if(data_wen) begin
                        wen_next <= data_wen;
                        data_next <= data_wdata;
                        cpu_wen <= 0;
                        cpu_waddr <= cpu_waddr;
                        data_wresp <= 0;
                    end
                end
                W_TAG_CHK: begin //           
                    if(dev_wrdy) begin
                        cpu_waddr <= data_addr;
                        cpu_wen <= wen_next;
                        //    ?             
                        //if (cpu_wen[0]) cpu_wdata[7:0] <= data_next[7:0];
                        // ...   ?        ? ...
                        cpu_wdata[31:0] <= { // ?    ? 0 ? bit31-0  
                            (wen_next[3] ? data_next[31:24] : 8'h0),
                            (wen_next[2] ? data_next[23:16] : 8'h0),
                            (wen_next[1] ? data_next[15:8]  : 8'h0),
                            (wen_next[0] ? data_next[7:0]   : 8'h0)};
                    end
                    data_wresp <= 0;
                end
                W_REFILL: cpu_wen <=4'b0000; //        ?
                W_OVER: begin
                    data_wresp <= dev_wrdy; //        ?
                end
                W_WRE:data_wresp <=1'b0;
            endcase
        end    
    end

    // TODO:       ?  ?   ? Cache          ?   ?    ? ?  ?  
    always @(posedge cpu_clk) begin
        if (hit_w) begin //     ?   ?     
            cache_w <= cache_line_r; //     ?      
            case (offset[4:2])
                3'b000: begin //    ?  ? 0  
                    cache_w[31:0] <= { // ?    ? 0 ? bit31-0  
                    (wen_next[3] ? data_next[31:24] : 8'h0),
                    (wen_next[2] ? data_next[23:16] : 8'h0),
                    (wen_next[1] ? data_next[15:8]  : 8'h0),
                    (wen_next[0] ? data_next[7:0]   : 8'h0)};
                end
                // ...    offset   ...
                3'b001: begin //    ?  ? 0  
                    cache_w[63:32] <= { // ?    ? 0 ? bit31-0  
                    (wen_next[3] ? data_next[31:24] : 8'h0),
                    (wen_next[2] ? data_next[23:16] : 8'h0),
                    (wen_next[1] ? data_next[15:8]  : 8'h0),
                    (wen_next[0] ? data_next[7:0]   : 8'h0)};
                end
                3'b010: begin //    ?  ? 0  
                    cache_w[95:64] <= { // ?    ? 0 ? bit31-0  
                    (wen_next[3] ? data_next[31:24] : 8'h0),
                    (wen_next[2] ? data_next[23:16] : 8'h0),
                    (wen_next[1] ? data_next[15:8]  : 8'h0),
                    (wen_next[0] ? data_next[7:0]   : 8'h0)};
                end
                3'b011: begin //    ?  ? 0  
                    cache_w[127:96] <= { // ?    ? 0 ? bit31-0  
                    (wen_next[3] ? data_next[31:24] : 8'h0),
                    (wen_next[2] ? data_next[23:16] : 8'h0),
                    (wen_next[1] ? data_next[15:8]  : 8'h0),
                    (wen_next[0] ? data_next[7:0]   : 8'h0)};
                end
                3'b100: begin //    ?  ? 0  
                    cache_w[159:128] <= { // ?    ? 0 ? bit31-0  
                    (wen_next[3] ? data_next[31:24] : 8'h0),
                    (wen_next[2] ? data_next[23:16] : 8'h0),
                    (wen_next[1] ? data_next[15:8]  : 8'h0),
                    (wen_next[0] ? data_next[7:0]   : 8'h0)};
                end
                3'b101: begin //    ?  ? 0  
                    cache_w[191:160] <= { // ?    ? 0 ? bit31-0  
                    (wen_next[3] ? data_next[31:24] : 8'h0),
                    (wen_next[2] ? data_next[23:16] : 8'h0),
                    (wen_next[1] ? data_next[15:8]  : 8'h0),
                    (wen_next[0] ? data_next[7:0]   : 8'h0)};
                end
                3'b110: begin //    ?  ? 0  
                    cache_w[223:192] <= { // ?    ? 0 ? bit31-0  
                    (wen_next[3] ? data_next[31:24] : 8'h0),
                    (wen_next[2] ? data_next[23:16] : 8'h0),
                    (wen_next[1] ? data_next[15:8]  : 8'h0),
                    (wen_next[0] ? data_next[7:0]   : 8'h0)};
                end
                3'b111: begin //    ?  ? 0  
                    cache_w[255:224] <= { // ?    ? 0 ? bit31-0  
                    (wen_next[3] ? data_next[31:24] : 8'h0),
                    (wen_next[2] ? data_next[23:16] : 8'h0),
                    (wen_next[1] ? data_next[15:8]  : 8'h0),
                    (wen_next[0] ? data_next[7:0]   : 8'h0)};
                end
            endcase
            write <= 1; //             
        end
    end

    /********   ? ?    ?    ********/
`else

    localparam R_IDLE  = 2'b00;
    localparam R_STAT0 = 2'b01;
    localparam R_STAT1 = 2'b11;
    reg [1:0] r_state, r_nstat;
    reg [3:0] ren_r;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        r_state <= cpu_rst ? R_IDLE : r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE:  r_nstat = (|data_ren) ? (dev_rrdy ? R_STAT1 : R_STAT0) : R_IDLE;
            R_STAT0: r_nstat = dev_rrdy ? R_STAT1 : R_STAT0;
            R_STAT1: r_nstat = dev_rvalid ? R_IDLE : R_STAT1;
            default: r_nstat = R_IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_valid <= 1'b0;
            cpu_ren    <= 4'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    data_valid <= 1'b0;

                    if (|data_ren) begin
                        if (dev_rrdy)
                            cpu_ren <= data_ren;
                        else
                            ren_r   <= data_ren;

                        cpu_raddr <= data_addr;
                    end else
                        cpu_ren   <= 4'h0;
                end
                R_STAT0: begin
                    cpu_ren    <= dev_rrdy ? ren_r : 4'h0;
                end   
                R_STAT1: begin
                    cpu_ren    <= 4'h0;
                    data_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    data_rdata <= dev_rvalid ? dev_rdata : 32'h0;
                end
                default: begin
                    data_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end 
            endcase
        end
    end

    localparam W_IDLE  = 2'b00;
    localparam W_STAT0 = 2'b01;
    localparam W_STAT1 = 2'b11;
    reg  [1:0] w_state, w_nstat;
    reg  [3:0] wen_r;
    wire       wr_resp = dev_wrdy & (cpu_wen == 4'h0) ? 1'b1 : 1'b0;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        w_state <= cpu_rst ? W_IDLE : w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE:  w_nstat = (|data_wen) ? (dev_wrdy ? W_STAT1 : W_STAT0) : W_IDLE;
            W_STAT0: w_nstat = dev_wrdy ? W_STAT1 : W_STAT0;
            W_STAT1: w_nstat = wr_resp ? W_IDLE : W_STAT1;
            default: w_nstat = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;

                    if (|data_wen) begin
                        if (dev_wrdy)
                            cpu_wen <= data_wen;
                        else
                            wen_r   <= data_wen;

                        cpu_waddr  <= data_addr;
                        cpu_wdata  <= data_wdata;
                    end else
                        cpu_wen    <= 4'h0;
                end
                W_STAT0: begin
                    cpu_wen    <= dev_wrdy ? wen_r : 4'h0;
                end
                W_STAT1: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= wr_resp ? 1'b1 : 1'b0;
                end
                default: begin
                    data_wresp <= 1'b0;
                    cpu_wen    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule