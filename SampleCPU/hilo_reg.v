`include "lib/defines.vh"
module hilo_reg(
    input wire clk,
    input wire rst,
    input wire [`StallBus-1:0] stall,
    input wire [65:0] ex_hilo_bus,
    input wire [65:0] mem_hilo_bus,
    input wire [65:0] hilo_bus,
    output reg [31:0] hi_data,
    output reg [31:0] lo_data
);

    reg [31:0] reg_hi, reg_lo;
    wire wb_hi_we, wb_lo_we;
    wire [31:0] wb_hi_in, wb_lo_in;
    wire ex_hi_we, ex_lo_we;
    wire [31:0] ex_hi_in, ex_lo_in;
    wire mem_hi_we, mem_lo_we;
    wire [31:0] mem_hi_in, mem_lo_in;

    assign {
        wb_hi_we, 
        wb_lo_we,
        wb_hi_in,
        wb_lo_in
    } = hilo_bus;

    assign {
        ex_hi_we,
        ex_lo_we,
        ex_hi_in,
        ex_lo_in
    } = ex_hilo_bus;

    assign {
        mem_hi_we,
        mem_lo_we,
        mem_hi_in,
        mem_lo_in
    } = mem_hilo_bus;

    always @ (posedge clk) begin
        if (rst) begin
            reg_hi <= 32'b0;
        end
        else if (wb_hi_we) begin
            reg_hi <= wb_hi_in;
        end
    end

    always @ (posedge clk) begin
        if (rst) begin
            reg_lo <= 32'b0;
        end
        else if (wb_lo_we) begin
            reg_lo <= wb_lo_in;
        end
    end

    wire [31:0] hi_temp, lo_temp;
    
    assign hi_temp = ex_hi_we  ? ex_hi_in   // 最高优先级：EX级
                   : mem_hi_we ? mem_hi_in  // 次优先级：MEM级
                   : wb_hi_we  ? wb_hi_in   // 第三优先级：WB级
                   : reg_hi;                // 默认：寄存器当前值

    assign lo_temp = ex_lo_we  ? ex_lo_in
                   : mem_lo_we ? mem_lo_in
                   : wb_lo_we  ? wb_lo_in
                   : reg_lo;


     always @ (posedge clk) begin
         if (rst) begin
             {hi_data, lo_data} <= {32'b0, 32'b0};
         end
         else if(stall[2] == `Stop && stall[3] == `NoStop) begin// 特殊暂停情况：输出清零 
         //部分暂停的情况：EX阶段被暂停 但MEM阶段继续流动 eg div等多周期指令
             {hi_data, lo_data} <= {32'b0, 32'b0};
         end
         else if (stall[2] == `NoStop) begin
             {hi_data, lo_data} <= {hi_temp, lo_temp};
         end
     end

endmodule