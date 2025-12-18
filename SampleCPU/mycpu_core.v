`include "lib/defines.vh"
module mycpu_core(          
    input wire clk,
    input wire rst,
    input wire [5:0] int,      //连线

    output wire inst_sram_en,
    output wire [3:0] inst_sram_wen,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input wire [31:0] inst_sram_rdata,

    output wire data_sram_en,
    output wire [3:0] data_sram_wen,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input wire [31:0] data_sram_rdata,

    output wire [31:0] debug_wb_pc,
    output wire [3:0] debug_wb_rf_wen,
    output wire [4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);
    //级间数据总线 
    wire [`IF_TO_ID_WD-1:0] if_to_id_bus;
    wire [`ID_TO_EX_WD-1:0] id_to_ex_bus;
    wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus;
    wire [`MEM_TO_WB_WD-1:0] mem_to_wb_bus;
    //跳转指令
    wire [`BR_WD-1:0] br_bus;
    //前推总线          
    wire [`DATA_SRAM_WD-1:0] ex_dt_sram_bus;
    wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus;      
    wire [`MEM_TO_RF_WD-1:0] mem_to_rf_bus;
    //hilo总线
    wire [65:0] ex_hilo_bus;
    wire [65:0] mem_hilo_bus;
    //控制信号 
    wire [`StallBus-1:0] stall; //暂停控制
    wire [7:0] memop_from_ex; //ex段访存类型
    wire stallreq; //暂停请求
    wire stallreq_ex; //来自EX段的暂停请求

    wire [31:0] hi_data, lo_data;
    wire [65:0] hilo_bus;
    IF u_IF(
        //基本信号
    	.clk             (clk             ),
        .rst             (rst             ),
        .stall           (stall           ),
        //输入来自ID的跳转信息
        .br_bus          (br_bus          ),
        //输出到ID的信息
        .if_to_id_bus    (if_to_id_bus    ),  
        //指令SRAM的接口
        .inst_sram_en    (inst_sram_en    ),
        .inst_sram_wen   (inst_sram_wen   ),
        .inst_sram_addr  (inst_sram_addr  ),
        .inst_sram_wdata (inst_sram_wdata )
    );
    ID u_ID(
    	.clk             (clk             ),
        .rst             (rst             ),
        .stall           (stall           ),
        //控制信号输入
        .stallreq_for_load  (stallreq     ),
        .memop_from_ex   (memop_from_ex   ),
        //来自IF段的输入 体现了连线
        .if_to_id_bus    (if_to_id_bus    ), 
        .inst_sram_rdata (inst_sram_rdata ),
        //前递数据输入
        .wb_to_rf_bus    (wb_to_rf_bus    ),
        .ex_to_rf_bus    (ex_to_rf_bus    ),
        .mem_to_rf_bus   (mem_to_rf_bus   ),
        //输出传递给EX段
        .id_to_ex_bus    (id_to_ex_bus    ),
        //输出传递给IF段的跳转信息
        .br_bus          (br_bus          )
    );


    EX u_EX(
    	.clk             (clk             ),
        .rst             (rst             ),
        .stall           (stall           ),
        .id_to_ex_bus    (id_to_ex_bus    ),
        .ex_to_mem_bus   (ex_to_mem_bus   ),
        .memop_from_ex   (memop_from_ex   ),
        .ex_hilo_bus     (ex_hilo_bus     ),
        .stallreq_for_ex (stallreq_ex     ),
        .hi_data         (hi_data         ),
        .lo_data         (lo_data         ),
        .data_sram_en    (data_sram_en    ),
        .data_sram_wen   (data_sram_wen   ),
        .data_sram_addr  (data_sram_addr  ),
        .data_sram_wdata (data_sram_wdata ),
        .ex_to_rf_bus    (ex_to_rf_bus    )
    );

    MEM u_MEM(
    	.clk             (clk             ),
        .rst             (rst             ),
        .stall           (stall           ),
        .ex_to_mem_bus   (ex_to_mem_bus   ),
        .mem_hilo_bus    (mem_hilo_bus    ),
        .data_sram_rdata (data_sram_rdata ),
        .mem_to_wb_bus   (mem_to_wb_bus   ),
        .mem_to_rf_bus   (mem_to_rf_bus   )
    );
    
    WB u_WB(
    	.clk               (clk               ),
        .rst               (rst               ),
        .stall             (stall             ),
        .mem_to_wb_bus     (mem_to_wb_bus     ),
        .wb_to_rf_bus      (wb_to_rf_bus      ),
        .hilo_bus          (hilo_bus          ),
        .debug_wb_pc       (debug_wb_pc       ),
        .debug_wb_rf_wen   (debug_wb_rf_wen   ),
        .debug_wb_rf_wnum  (debug_wb_rf_wnum  ),
        .debug_wb_rf_wdata (debug_wb_rf_wdata )
    );

    CTRL u_CTRL(
    	.rst               (rst               ),
    	.stallreq_for_load (stallreq          ),
    	.stallreq_for_ex   (stallreq_ex       ),
        .stall             (stall             )
    );

    hilo_reg u_hilo_reg(
        .clk                (clk                   ),
        .rst                (rst                   ),
        .stall              (stall                 ),
        // .ex_hi_we           (ex_to_mem_bus[146]    ),
        // .ex_lo_we           (ex_to_mem_bus[145]    ),
        // .ex_hi_in           (ex_to_mem_bus[144:113]),
        // .ex_lo_in           (ex_to_mem_bus[112:81] ),

        // .mem_hi_we          (mem_to_wb_bus[135]    ),
        // .mem_lo_we          (mem_to_wb_bus[134]    ),
        // .mem_hi_in          (mem_to_wb_bus[133:102]),
        // .mem_lo_in          (mem_to_wb_bus[101:70] ),
        .ex_hilo_bus        (ex_hilo_bus           ),
        .mem_hilo_bus       (mem_hilo_bus          ),

        .hilo_bus           (hilo_bus              ),

        .hi_data            (hi_data               ),
        .lo_data            (lo_data               )
    );
    
endmodule