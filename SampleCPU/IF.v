`include "lib/defines.vh"
module IF(
     //定义一些接口
    input wire clk,//clock
    input wire rst,//reset
    input wire [`StallBus-1:0] stall,//暂停
    // input wire flush,
    // input wire [31:0] new_pc,

    input wire [`BR_WD-1:0] br_bus,//跳转

    output wire [`IF_TO_ID_WD-1:0] if_to_id_bus,//传给id节段

    output wire inst_sram_en,           //是否取指
    output wire [3:0] inst_sram_wen,   //写使能
    output wire [31:0] inst_sram_addr,  //取指地址
    output wire [31:0] inst_sram_wdata    //写数据(一直为0
);
    reg [31:0] pc_reg;          //PC寄存器:存储当前正在取指的指令
    reg ce_reg;                 //取指使能:控制是否允许取指操作
    wire [31:0] next_pc;        //下一个pc的地址
    wire br_e;                  //分支使能
    wire [31:0] br_addr;        //分支地址

    assign {
        br_e,
        br_addr
    } = br_bus;         //一堆跳转指令


    always @ (posedge clk) begin       //PC更新逻辑
            pc_reg <= 32'hbfbf_fffc; //开始或复位时 PC设为初始地址
        end
        else if (stall[0]==`NoStop) begin       //流水线不停的话，每个时钟周期跳转到下一条pc（+4或者跳转）
            pc_reg <= next_pc;
        end
    end

       always @ (posedge clk) begin //对取指ce的控制
        if (rst) begin
            ce_reg <= 1'b0;  //复位时不取指
        end
        else if (stall[0]==`NoStop) begin
            ce_reg <= 1'b1;  //流水线不停的话，允许取指 
        end
    end //也就是说，暂停时，pc和ce都不更新，保持原值，避免取错指令

     assign next_pc = br_e ? br_addr     //如果下一条pc不是分支跳转，那么pc+4（顺序的下一条）否则，跳转
                   : pc_reg + 32'h4;  //因为MIPS指令都是4字节32bit对齐的

    //pc存储器接口：只读接口，pc存储器在运行时通常只读
    assign inst_sram_en = ce_reg;          //取指使能
    assign inst_sram_wen = 4'b0;            //一直全0：禁止写入
    assign inst_sram_addr = pc_reg;      //取指地址
    assign inst_sram_wdata = 32'b0;         //一直全0：禁止写入
    
    //流水线阶段交互：传递给ID阶段
    assign if_to_id_bus = {
        ce_reg,  // 取指使能：防止IF阶段取到无效指令
        pc_reg  // 当前指令的PC值
    };

endmodule