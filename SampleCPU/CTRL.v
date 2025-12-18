`include "lib/defines.vh"
module CTRL(
    input wire rst,
    input wire stallreq_for_load, // 加载指令暂停请求
    input wire stallreq_for_ex,
    // output reg flush,
    // output reg [31:0] new_pc,
    output reg [`StallBus-1:0] stall
);  
    always @ (*) begin
        if (rst) begin
            stall = `StallBus'b0; // 复位时不清除暂停，在这里全0表示不暂停 （没懂，为什么不清除暂停？）
        /*
        .vh文件中定义的：
        `define NoStop 1'b0
        `define Stop 1'b1
        ——————————————————
        如果复位时设置全不暂停：所有流水线流动的同时，PC未初始化完成，寄存器文件随机值，内存未准备好
        导致CPU开始执行随机指令
        */
        end
        //对于数据冒险处理的加载
        else if (stallreq_for_load==`Stop) begin
            stall = `StallBus'b000111;
        end
        else if (stallreq_for_ex==`Stop) begin
            stall = `StallBus'b001111;
        end
        else begin
            stall = `StallBus'b0;
        end
    end
    
 

endmodule