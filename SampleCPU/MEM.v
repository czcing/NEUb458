`include "lib/defines.vh"
module MEM(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,

    input wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,
    input wire [31:0] data_sram_rdata,

    output wire [65:0] mem_hilo_bus,
    output wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus,
    output wire [`MEM_TO_RF_WD-1:0] mem_to_rf_bus       //前推线路
);

    reg [`EX_TO_MEM_WD-1:0] ex_to_mem_bus_r; //流水线寄存器 保存EX并传给MEM

    always @ (posedge clk) begin
        if (rst) begin
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;
        end
        // else if (flush) begin
        //     ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;
        // end
        else if (stall[3]==`Stop && stall[4]==`NoStop) begin
            ex_to_mem_bus_r <= `EX_TO_MEM_WD'b0;
        end
        else if (stall[3]==`NoStop) begin
            ex_to_mem_bus_r <= ex_to_mem_bus;
        end
    end
    //总线
    wire [31:0] mem_pc;
    wire data_ram_en;
    wire [3:0] data_ram_wen;
    wire [3:0] data_ram_sel;
    wire sel_rf_res;
    wire rf_we;
    wire [4:0] rf_waddr;
    wire [31:0] rf_wdata;
    wire [31:0] ex_result;
    wire [31:0] mem_result;
    wire [7:0] mem_op;
    wire [65:0] hilo_bus;

    assign {
        hilo_bus,
        mem_op,
        mem_pc,          // 79:48
        data_ram_en,    // 47
        data_ram_wen,   // 46:43
        //data_ram_sel,   // 42:39
        sel_rf_res,     // 38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result       // 31:0
    } =  ex_to_mem_bus_r;
    //访存译码
    wire inst_lw, inst_lb, inst_lbu, inst_lh, inst_lhu;
    wire inst_sb, inst_sh, inst_sw;

    assign {
        inst_lb, inst_lbu, inst_lh, inst_lhu,
        inst_lw, inst_sb,  inst_sh, inst_sw
    } = mem_op;

    //访存数据处理
    assign mem_result = //lw指令：直接使用32位数据
                        inst_lw ? data_sram_rdata:
                        //lb指令：字节加载+有符号扩展
                        inst_lb  & ex_result[1:0]==2'b00 ? {{24{data_sram_rdata[7]}},data_sram_rdata[7:0]}:
                        inst_lb  & ex_result[1:0]==2'b01 ? {{24{data_sram_rdata[15]}},data_sram_rdata[15:8]}:
                        inst_lb  & ex_result[1:0]==2'b10 ? {{24{data_sram_rdata[23]}},data_sram_rdata[23:16]}:
                        inst_lb  & ex_result[1:0]==2'b11 ? {{24{data_sram_rdata[31]}},data_sram_rdata[31:24]}:
                        //lbu指令：字节加载+零扩展
                        inst_lbu & ex_result[1:0]==2'b00 ? {{24{1'b0}},data_sram_rdata[7:0]}:
                        inst_lbu & ex_result[1:0]==2'b01 ? {{24{1'b0}},data_sram_rdata[15:8]}:
                        inst_lbu & ex_result[1:0]==2'b10 ? {{24{1'b0}},data_sram_rdata[23:16]}:
                        inst_lbu & ex_result[1:0]==2'b11 ? {{24{1'b0}},data_sram_rdata[31:24]}:
                        //lh指令：半字加载+有符号扩展（对齐到2字节）
                        inst_lh  & ex_result[1:0]==2'b00 ? {{16{data_sram_rdata[15]}},data_sram_rdata[15:0]}:
                        inst_lh  & ex_result[1:0]==2'b10 ? {{16{data_sram_rdata[31]}},data_sram_rdata[31:16]}:
                        //lhu指令：半字加载+零扩展
                        inst_lhu & ex_result[1:0]==2'b00 ? {{16{1'b0}},data_sram_rdata[15:0]}:
                        inst_lhu & ex_result[1:0]==2'b10 ? {{16{1'b0}},data_sram_rdata[31:16]}:
                        //default
                        32'b0;


    assign rf_wdata = sel_rf_res & data_ram_en ? mem_result : ex_result;
    /*
    等效于
    if (sel_rf_res == 1 && data_ram_en == 1) begin
      rf_wdata = mem_result;  // 选择内存读取的数据
    end else begin
      rf_wdata = ex_result;   // 选择EX段计算的结果
    end 
    为什么要这么写？
    确保了只有 Load指令 会选择mem_result，所有其他指令都选择ex_result
    这样可以避免在非Load指令时，mem_result可能包含无效数据的问题
    */
    
    //传到WB段的总线
    assign mem_to_wb_bus = {
        hilo_bus,
        mem_pc,     // 69:38
        rf_we,      // 37
        rf_waddr,   // 36:32
        rf_wdata    // 31:0
    };

    assign mem_hilo_bus = hilo_bus;

    //前推总线 在ID段解包
    assign mem_to_rf_bus = {
        // hilo_bus,
        rf_we,
        rf_waddr,
        rf_wdata
    };


endmodule