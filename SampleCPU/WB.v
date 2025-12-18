`include "lib/defines.vh"
module WB(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,

    input wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus,

    output wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,
    output wire [65:0] hilo_bus,
    output wire [31:0] debug_wb_pc,
    output wire [3:0] debug_wb_rf_wen,
    output wire [4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata 
);

    reg [`MEM_TO_WB_WD-1:0] mem_to_wb_bus_r;//流水线寄存器

    always @ (posedge clk) begin
        if (rst) begin
            mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;
        end
        // else if (flush) begin
        //     mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;
        // end
        else if (stall[4]==`Stop && stall[5]==`NoStop) begin
            mem_to_wb_bus_r <= `MEM_TO_WB_WD'b0;
        end
        else if (stall[4]==`NoStop) begin
            mem_to_wb_bus_r <= mem_to_wb_bus;
        end
    end

    wire [31:0] wb_pc;
    wire rf_we;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;

    assign {
        hilo_bus
        wb_pc,
        rf_we,
        rf_waddr,
        rf_wdata
    } = mem_to_wb_bus_r;

    assign wb_to_rf_bus = {
        rf_we,
        rf_waddr,
        rf_wdata
    };

    //trace_back
    assign debug_wb_pc = wb_pc;
    assign debug_wb_rf_wen = {4{rf_we}};
    assign debug_wb_rf_wnum = rf_waddr;
    assign debug_wb_rf_wdata = rf_wdata;


/*`timescale 1ns/1ps //Testbench
module simple_tb_WB();
    reg clk, rst;
    reg [69:0] mem_to_wb_bus; 
    wire [37:0] wb_to_rf_bus;
    wire [31:0] debug_wb_pc;
    wire [3:0] debug_wb_rf_wen;
    wire [4:0] debug_wb_rf_wnum;
    wire [31:0] debug_wb_rf_wdata;
    always #5 clk = ~clk;
    WB u_WB(.*);
    initial begin
        clk = 0;
        rst = 1;
        mem_to_wb_bus = 0;
        #20 rst = 0;
        $display("1 add r1, r2, r3 (wbr1=10)");
        mem_to_wb_bus = {
            32'h8000_0000,
            1'b1,
            5'd1,
            32'h0000_000a
        };
        @(posedge clk); #1;
        print_debug();
    
        $display("\n t2 sw r1,100(r2)");
        mem_to_wb_bus = {
            32'h8000_0004,
            1'b0,
            5'd0,  
            32'h1234_5678 
        };
        @(posedge clk); #1;
        print_debug();
        $display("\nt3：lw r3,200(r4)");
        mem_to_wb_bus = {
            32'h8000_0008,
            1'b1,
            5'd3, 
            32'haabb_ccdd  
        };
        @(posedge clk); #1;
        print_debug();
        mem_to_wb_bus = {
            32'h8000_000c,
            1'b1,
            5'd4,
            32'hdead_beef
        };
        u_WB.stall = 32'b0000_0000_0000_0000_0000_0000_0001_0000;
        @(posedge clk); #1;
        print_debug();
        u_WB.stall = 32'b0;
        #20 $finish;
    end
    task print_debug;
        $display("  debug_wb_pc      = 0x%h", debug_wb_pc);
        $display("  debug_wb_rf_wen  = 4'b%b", debug_wb_rf_wen);
        $display("  debug_wb_rf_wnum = r%d", debug_wb_rf_wnum);
        $display("  debug_wb_rf_wdata= 0x%h", debug_wb_rf_wdata);
        $display("  wb_to_rf_bus     = {we=%b, addr=r%d, data=0x%h}",
                 wb_to_rf_bus[37], wb_to_rf_bus[36:32], wb_to_rf_bus[31:0]);
    endtask
endmodule*/
    
endmodule