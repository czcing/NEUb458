`include "lib/defines.vh"
module ID(
    input wire clk,//clock
    input wire rst,//reset
    // input wire flush,            稍微更改一下注释
    input wire [`StallBus-1:0] stall,
    input wire [7:0] memop_from_ex,
    
    output wire stallreq_for_load,
//    input wire ex_ram_read,
//    output stall_for_load,

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus,     //if段传到id段的信息

    input wire [31:0] inst_sram_rdata,

    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus, //解决数据冒险问题：数据前推
    /*
    五级流水线的顺序是：IF取指（从内存取指令代码） 
                       ID译码（我们现在的阶段 功能：1. 解码指令 2. 读寄存器文件，也就是取值 3. 符号扩展立即数） 
                       EX执行（用ALU计算结果）
                       MEM访问（访问内存）
                       WB写回（把算出来的数据写回内存）
    假设有两个指令：
      指令1：add $1,$2,$3    也就是 $1=$2+$3
      指令2：or $4,$1,$5    同理 $4=$1|$5
    他们所对应的流水线可能是这样的（没有前推时的流水线时序）：
      时钟周期  |  1  |  2  |  3  |  4  |  5  |  6  |
          指令1:  IF    ID    EX    MEM   WB
          指令2:        IF    ID    EX    MEM   WB
    在时钟周期4时，会出现一个问题：指令1在EX阶段计算出了$1，但它必须等到WB阶段才能写回寄存器，而指令2在ID阶段已经需要\$1的值
    使用 wb_to_rf_bus 进行数据前推，将指令1在WB阶段计算出来的$1的值立即传递给rf
    这样，指令2在ID阶段就能直接读取到最新的$1值，避免了等待指令1的WB阶段写回操作，确保流水线不会停滞
    ————————————————————
    那么为什么传递给rf不直接传递给ID段呢？
    如果这里我写成 wb_to_id_bus，相当于我只去告诉ID段我有什么数据，但ID段可能不需要这个数据，我还要额外设计复杂的匹配逻辑
    所以我们直接传递给rf，指令的反应是人的7倍，如果需要他会直接去寄存器里面拿的
    ————————————————————
    EX段和MEM段的前推逻辑同理
    */
    input wire [`EX_TO_RF_WD-1:0] ex_to_rf_bus, //ex段前推
    input wire [`MEM_TO_RF_WD-1:0] mem_to_rf_bus, //mem段前推
    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus, //前推的写完了 这里是向后传给EX段的信息
    output wire [`BR_WD-1:0] br_bus //芝士跳转总线BR
);

    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;      //临时寄存器，用来存储if段传来的信息
    wire [31:0] inst; 
    wire [31:0] id_pc; 
    wire ce;                    //使能信号

    wire wb_rf_we;              //前推使能信号
    wire [4:0] wb_rf_waddr;     //wb前向信号中的目标地址（目标寄存器） 寄存器32个 所以用5位
    wire [31:0] wb_rf_wdata;    //wb前推信号中的传输数据

    wire ex_rf_we;  
    wire [4:0] ex_rf_waddr; 
    wire [31:0] ex_rf_wdata; 

    wire mem_rf_we; 
    wire [4:0] mem_rf_waddr; 
    wire [31:0] mem_rf_wdata;
    reg  flag;
    reg [31:0] buf_inst;

    always @ (posedge clk) begin        //在每个时钟周期上升沿，如果没有特殊情况，把信息赋给if_to_id_bus_r寄存器，ID段执行的指令都要从这个寄存器里取
        if (rst) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0; 
            flag <= 1'b0;    
            buf_inst <= 32'b0;   
        end
//         else if (flush) begin
//             ic_to_id_bus <= `IC_TO_ID_WD'b0;
//         end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
            flag <= 1'b0; 
        end
        else if (stall[1]==`NoStop) begin     
            if_to_id_bus_r <= if_to_id_bus;
            flag <= 1'b0; 
        end
        else if (stall[1]==`Stop && stall[2]==`Stop && ~flag) begin
            flag <= 1'b1;
            buf_inst <= inst_sram_rdata;
        end
    end
    
    //从inst ram中取指
    assign inst = ce ? flag ? buf_inst : inst_sram_rdata : 32'b0;
//    assign inst = inst_sram_rdata;
//    assign stall_for_load = ex_ram_read &((ex_rf_we && (ex_rf_waddr == rs)) | (ex_rf_we && (ex_rf_waddr==rt)));
    /*
    if (ce == 1'b1) begin
      if (flag == 1'b1) begin
        inst = buf_inst;          // 情况1：有缓冲指令，用缓冲的 否则会冲掉缓存里的指令
      end else begin
        inst = inst_sram_rdata;   // 情况2：无缓冲，直接从内存读 
      end
    end else begin
      inst = 32'b0;               // 情况3：指令无效，给0
    end
    情况1：当ID段被暂停（stall[1]==Stop）且IF段也被暂停（stall[2]==Stop）时，说明流水线处于停顿状态
           这时，ID段无法处理新的指令，因此需要将当前的指令存储在buf_inst中，便于在恢复流水线时继续处理
           时钟周期：|  1  |  2  |  3  |  4  |
            IF段:     取A →  取B → 取C
            ID段:     译A → 停顿 → 译B(进行上面注释掉的操作的话这里会变成译C，B寄，白取了)
                              ↑
                          这里flag=1，inst=buf_inst=B,
     */
    assign {
        ce,
        id_pc
    } = if_to_id_bus_r;


    //前推线路解包
    assign {           
        wb_rf_we,
        wb_rf_waddr,
        wb_rf_wdata
    } = wb_to_rf_bus;

    assign {
        ex_rf_we,
        ex_rf_waddr,
        ex_rf_wdata
    } = ex_to_rf_bus;

    assign {
        mem_rf_we,
        mem_rf_waddr,
        mem_rf_wdata
    } = mem_to_rf_bus;

    //设置必要线路,把32位的机器指令分解成各个字段，然后生成控制信号。
    //告诉后续阶段 要做什么运算 用哪些数据 结果存到哪里
    
    //指令格式解析：
    wire [5:0] opcode;      //操作码
    wire [4:0] rs,rt,rd,sa;
    wire [5:0] func;
    wire [15:0] imm;
    wire [25:0] instr_index;
    wire [19:0] code;
    wire [4:0] base;
    wire [15:0] offset;
    wire [2:0] sel;                 //指令要运算的类型,例如逻辑运算，移位运算、算术运算等

   //解码器：把几位的编码转换成one-hot编码（只有一位是1）
    wire [63:0] op_d, func_d;   // 操作码和功能码解码
    wire [31:0] rs_d, rt_d, rd_d, sa_d;   // 寄存器编号解码

    //生成控制信号
    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;   //alu的两个操作数选择信号
    wire [11:0] alu_op;      //alu操作类型  
/*  位   11  10   9   8   7   6   5   4   3   2   1   0
  操作： add sub slt sltu and nor or xor sll srl sra lui
     eg 如果是add指令，第11位=1 */
    wire [7:0] mem_op;       //内存操作类型

   //访存控制
    wire data_ram_en; //内存访问使能(是否访问)
    wire [3:0] data_ram_wen; //内存写使能(写哪几位)
    
    //寄存器文件控制
    wire rf_we;  //写使能（是否写？）
    wire [4:0] rf_waddr; //写地址（写哪个寄存器？）
    wire sel_rf_res; //写的结果从哪来（alu结果 或者 访存结果）
    wire [2:0] sel_rf_dst; //写到哪里（写到rd rt还是$31）
    wire [31:0] rdata1, rdata2, rf_data1, rf_data2;  //r：经过前推选择后的数据，最新 rf：从寄存器堆读出来的，原始
    /*
    我先梳理一下前面这一串吧
    eg. 我要进行一下这条指令：ori $1, $2, 0xFF（机器码：0x344100FF）
    首先先解析指令格式：
          opcode = 6'b001101  // ori的操作码*注意 到这里我还不知道我要执行的是哪条指令
          rs = 5'b00010       // $2
          rt = 5'b00001       // $1  
          imm = 16'h00FF      // 255
    然后解码器进行处理: op_d[6'b001101] = 1,数值为13，onehot得到这是ori指令的标识
    ALU操作数选择：
    sel_alu_src1 = 3'b001   选择rs（$2）
    sel_alu_src2 = 4'b0011  选择立即数（零扩展的0x00FF）
    ALU操作类型：
    alu_op[7] = 1           or操作（第7位是or）
    访存控制：
    data_ram_en = 0         不访问内存
    data_ram_wen = 4'b0000  不写内存
    寄存器控制：
    rf_we = 1               这条指令需要写寄存器（也就是使能过程）
    sel_rf_dst = 3'b010     写到rt（$1）指令类型决定的，ori指令就是写到rt，这里可以问下D指导
    rf_waddr = rt = 5'b00001  这个是具体的寄存器编号，不用管它
    sel_rf_res = 0          结果来自ALU

    接着 需要从寄存器文件读$2的值
    raddr1 = rs = 5'b00010
    rf_data1 = $2寄存器的值（比如0x12345678）
    因为我这里的第二个操作数是立即数，不读rt
    好了我这些东西都读完了，接下来一步就不是我干的了，我作为ID段译码的任务就结束了
    我需要把这些东西打包传给EX段，让他去执行
    */

    regfile u_regfile(
        .clk    (clk),
        .raddr1 (rs),      // 读地址1：rs字段
        .rdata1 (rf_data1), // 读数据1
        .raddr2 (rt),      // 读地址2：rt字段  
        .rdata2 (rf_data2), // 读数据2
        .we     (wb_rf_we),  // 写使能（来自WB段）
        .waddr  (wb_rf_waddr),  // 写地址（来自WB段）
        .wdata  (wb_rf_wdata)   // 写数据（来自WB段）
    );
    
    
    //前推逻辑：优先级 ex>mem>wb>原始数据
    //这个顺序是根据时间来的，因为ex段是最早计算出结果的，所以优先级最高，依次类推，越早的结果越能让我更快拿到结果
    assign rdata1 = (ex_rf_we && (ex_rf_waddr == rs)) ? ex_rf_wdata:
                    (mem_rf_we && (mem_rf_waddr == rs)) ? mem_rf_wdata:
                    (wb_rf_we && (wb_rf_waddr == rs)) ? wb_rf_wdata:
                                                        rf_data1;
    assign rdata2 = (ex_rf_we && (ex_rf_waddr == rt)) ? ex_rf_wdata:
                    (mem_rf_we && (mem_rf_waddr == rt)) ? mem_rf_wdata:
                    (wb_rf_we && (wb_rf_waddr == rt)) ? wb_rf_wdata:
                                                        rf_data2;  
    //检测前一条指令的访存类型，决定是否暂停流水线 
    //为什么需要知道前一条指令的访存类型？因为Load指令有特殊问题
    //Load指令在MEM段末尾才能从内存拿到数据，但下一条指令在ID段就需要这个数据，时间上来不及前推                                                    
    wire ex_inst_lb, ex_inst_lbu,  ex_inst_lh, ex_inst_lhu, ex_inst_lw;
    wire ex_inst_sb, ex_inst_sh,   ex_inst_sw;   
    
    assign {ex_inst_lb, ex_inst_lbu, ex_inst_lh, ex_inst_lhu,
            ex_inst_lw, ex_inst_sb,  ex_inst_sh, ex_inst_sw} = memop_from_ex;                                                                                                   

    wire stallreq1_loadrelate;
    wire stallreq2_loadrelate;
    
    //Load-Use冒险检测
    wire pre_inst_is_load;
    //检测前一条指令是否是访存指令
    assign pre_inst_is_load = ex_inst_lb | ex_inst_lbu | ex_inst_lh | ex_inst_lhu
                             |ex_inst_lw | ex_inst_sb |  ex_inst_sh | ex_inst_sw ? 1'b1 : 1'b0;

   //判断暂停条件：前一条指令是访存指令（pre_inst_is_load == 1）
    //而且前一条指令要写的寄存器（ex_rf_waddr）正好是我要读的寄存器（rs或rt）
    //俩之间有一个要停 就停                          
    assign stallreq1_loadrelate = (pre_inst_is_load == 1'b1 && ex_rf_waddr == rs) ? `Stop : `NoStop;
    assign stallreq2_loadrelate = (pre_inst_is_load == 1'b1 && ex_rf_waddr == rt) ? `Stop : `NoStop;
    assign stallreq_for_load = (stallreq1_loadrelate | stallreq2_loadrelate) ? `Stop : `NoStop;

    //hi & lo reg for mul and div(to do)



//decode inst   
    //locate content of inst 划分指令的字段
    assign opcode = inst[31:26];        //对于ori指令只需要通过判断26-31bit的值，即可判断是否是ori指令
    assign rs = inst[25:21];            //rs寄存器
    assign rt = inst[20:16];            //rt寄存器
    assign rd = inst[15:11];
    assign sa = inst[10:6];
    assign func = inst[5:0];
    assign imm = inst[15:0];            //立即数
    assign instr_index = inst[25:0];
    assign code = inst[25:6];
    assign base = inst[25:21];
    assign offset = inst[15:0];         //偏移量
    assign sel = inst[2:0];


    //candidate inst & opetion      操作：如果判断当前inst是某条指令，则对应指令的wire变为1,如判断当前inst是add指令，则inst_add <=2'b1
    wire inst_add,  inst_addi,  inst_addu,  inst_addiu;
    wire inst_sub,  inst_subu,  inst_slt,   inst_slti;
    wire inst_sltu, inst_sltiu, inst_div,   inst_divu;
    wire inst_mult, inst_multu, inst_and,   inst_andi;
    wire inst_lui,  inst_nor,   inst_or,    inst_ori;
    wire inst_xor,  inst_xori,  inst_sllv,  inst_sll;
    wire inst_srav, inst_sra,   inst_srlv,  inst_srl;
    wire inst_beq,  inst_bne,   inst_bgez,  inst_bgtz;
    wire inst_blez, inst_bltz,  inst_bgezal,inst_bltzal;
    wire inst_j,    inst_jal,   inst_jr,    inst_jalr;
    wire inst_mfhi, inst_mflo,  inst_mthi,  inst_mtlo;
    wire inst_break,inst_syscall;
    wire inst_lb,   inst_lbu,   inst_lh,    inst_lhu,   inst_lw;
    wire inst_sb,   inst_sh,    inst_sw;
    wire inst_eret, inst_nfc0,  inst_mtc0;
    wire inst_mul;

    //控制alu运算单元
    wire op_add, op_sub, op_slt, op_sltu;
    wire op_and, op_nor, op_or, op_xor;
    wire op_sll, op_srl, op_sra, op_lui;
    //解码器 把输入转为onehot输出
    decoder_6_64 u0_decoder_6_64(.in (opcode), .out (op_d));
    decoder_6_64 u1_decoder_6_64(.in (func), .out (func_d));
    decoder_5_32 u0_decoder_5_32(.in (rs), .out (rs_d));
    decoder_5_32 u1_decoder_5_32(.in (rt), .out(rt_d));
    decoder_5_32 u2_decoder_5_32(.in (rd), .out (rd_d));
    decoder_5_32 u3_decoder_5_32(.in (sa), .out (sa_d));

    //操作码 I型指令只靠opcode就能区分，R型指令opcode全为0，还需要func
    assign inst_ori     = op_d[6'b00_1101];
    assign inst_lui     = op_d[6'b00_1111];
    assign inst_addiu   = op_d[6'b00_1001];
    assign inst_addi    = op_d[6'b00_1000];
    assign inst_addu    = op_d[6'b00_0000] & func_d[6'b10_0001];
    assign inst_add     = op_d[6'b00_0000] & func_d[6'b10_0000];
    assign inst_beq     = op_d[6'b00_0100];
    assign inst_sub     = op_d[6'b00_0000] & func_d[6'b10_0010];
    assign inst_subu    = op_d[6'b00_0000] & func_d[6'b10_0011];
    assign inst_j       = op_d[6'b00_0010];  
    assign inst_jal     = op_d[6'b00_0011];
    assign inst_jr      = op_d[6'b00_0000] & func_d[6'b00_1000];
    assign inst_jalr    = op_d[6'b00_0000] & func_d[6'b00_1001];
    assign inst_sll     = op_d[6'b00_0000] & func_d[6'b00_0000];
    assign inst_sllv    = op_d[6'b00_0000] & func_d[6'b00_0100];
    assign inst_or      = op_d[6'b00_0000] & func_d[6'b10_0101];  
    assign inst_lw      = op_d[6'b10_0011];
    assign inst_lb      = op_d[6'b10_0000];
    assign inst_lbu     = op_d[6'b10_0100];
    assign inst_lh      = op_d[6'b10_0001];
    assign inst_lhu     = op_d[6'b10_0101];
    assign inst_sb      = op_d[6'b10_1000];
    assign inst_sh      = op_d[6'b10_1001];
    assign inst_sw      = op_d[6'b10_1011];
    assign inst_xor     = op_d[6'b00_0000] & func_d[6'b10_0110];
    assign inst_xori    = op_d[6'b00_1110];
    assign inst_sltu    = op_d[6'b00_0000] & func_d[6'b10_1011];
    assign inst_slt     = op_d[6'b00_0000] & func_d[6'b10_1010];
    assign inst_slti    = op_d[6'b00_1010];
    assign inst_sltiu   = op_d[6'b00_1011];
    assign inst_srav    = op_d[6'b00_0000] & func_d[6'b00_0111];
    assign inst_sra     = op_d[6'b00_0000] & func_d[6'b00_0011];
    assign inst_bne     = op_d[6'b00_0101];
    assign inst_bgez    = op_d[6'b00_0001] & rt_d[5'b0_0001];
    assign inst_bgtz    = op_d[6'b00_0111];
    assign inst_blez    = op_d[6'b00_0110];
    assign inst_bltz    = op_d[6'b00_0001] & rt_d[5'b0_0000];
    assign inst_bltzal  = op_d[6'b00_0001] & rt_d[5'b1_0000];
    assign inst_bgezal  = op_d[6'b00_0001] & rt_d[5'b1_0001];
    assign inst_and     = op_d[6'b00_0000] & func_d[6'b10_0100];
    assign inst_andi    = op_d[6'b00_1100];
    assign inst_nor     = op_d[6'b00_0000] & func_d[6'b10_0111];
    assign inst_srl     = op_d[6'b00_0000] & func_d[6'b00_0010];
    assign inst_srlv    = op_d[6'b00_0000] & func_d[6'b00_0110];
    assign inst_mfhi    = op_d[6'b00_0000] & func_d[6'b01_0000];
    assign inst_mflo    = op_d[6'b00_0000] & func_d[6'b01_0010];
    assign inst_mthi    = op_d[6'b00_0000] & func_d[6'b01_0001];
    assign inst_mtlo    = op_d[6'b00_0000] & func_d[6'b01_0011];
    assign inst_div     = op_d[6'b00_0000] & func_d[6'b01_1010];
    assign inst_divu    = op_d[6'b00_0000] & func_d[6'b01_1011];
    assign inst_mult    = op_d[6'b00_0000] & func_d[6'b01_1000];
    assign inst_multu   = op_d[6'b00_0000] & func_d[6'b01_1001];

    wire [8:0] hilo_op;
    assign hilo_op = {
        inst_mfhi, inst_mflo, inst_mthi, inst_mtlo,
        inst_mult, inst_multu,inst_div,  inst_divu,
        inst_mul
    };


    //选操作数      这里src1和src2分别是两个存储操作数的寄存器，具体怎么选操作数，在ex段写
    // rs to reg1
    assign sel_alu_src1[0] =  inst_ori| inst_addiu | inst_sub | inst_subu | inst_addu | inst_slti
                            | inst_or | inst_xor   | inst_sw  | inst_srav | inst_sltu | inst_slt
                            | inst_lw | inst_sltiu | inst_add | inst_addi | inst_and  | inst_andi
                            | inst_nor| inst_xori  | inst_sllv| inst_srlv | inst_div  | inst_divu
                            | inst_mult | inst_multu;
    // pc to reg1
    assign sel_alu_src1[1] = inst_jal | inst_jalr | inst_bltzal | inst_bgezal;
    // sa_zero_extend to reg1
    assign sel_alu_src1[2] = inst_sll | inst_sra | inst_srl;
    // rt to reg2
    assign sel_alu_src2[0] = inst_sub | inst_subu | inst_addu | inst_sll | inst_or | inst_xor
                            |inst_srav| inst_sltu | inst_slt  | inst_add | inst_and| inst_nor
                            |inst_sllv| inst_sra  | inst_srl  | inst_srlv| inst_div| inst_divu
                            | inst_mult | inst_multu;
    // imm_sign_extend to reg2
    assign sel_alu_src2[1] = inst_lui | inst_addiu | inst_lw  | inst_sw  | inst_slti| inst_sltiu | inst_addi;
    // 32'b8 to reg2
    assign sel_alu_src2[2] = inst_jal | inst_jalr | inst_bltzal | inst_bgezal;
    // imm_zero_extend to reg2
    assign sel_alu_src2[3] = inst_ori | inst_andi | inst_xori;
    //choose the op to be applied   选操作逻辑
    assign op_add = inst_addiu | inst_jal | inst_jalr | inst_addu | inst_lw | inst_sw | inst_add | inst_addi | inst_bltzal |inst_bgezal;
    assign op_sub = inst_sub | inst_subu;
    assign op_slt = inst_slt | inst_slti;
    assign op_sltu = inst_sltu | inst_sltiu;
    assign op_and = inst_and | inst_andi;
    assign op_nor = inst_nor;
    assign op_or = inst_ori | inst_or;
    assign op_xor = inst_xor| inst_xori;
    assign op_sll = inst_sll| inst_sllv;
    assign op_srl = inst_srl| inst_srlv;
    assign op_sra = inst_srav| inst_sra;
    assign op_lui = inst_lui;
    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};
    assign mem_op = {inst_lb, inst_lbu, inst_lh, inst_lhu,
                     inst_lw, inst_sb,  inst_sh, inst_sw};
    //对内存的控制
    // load and store enable  lw（从内存读）和sw（向内存写）都需要访问内存
    assign data_ram_en = inst_lw | inst_sw;

    // write enable  只有sw指令要往内存写，lw只是读
    assign data_ram_wen = inst_sw;


     //写回数操作
    //要不要写回寄存器 regfile store enable
    assign rf_we = inst_ori | inst_lui | inst_addiu | inst_addu | inst_sub | inst_subu | inst_jal | inst_jalr
                  |inst_sll | inst_or  | inst_lw | inst_xor | inst_srav | inst_sltu | inst_slt | inst_slti | inst_sltiu
                  |inst_add | inst_addi| inst_and| inst_andi| inst_nor  | inst_xori | inst_sllv| inst_sra  | inst_srl
                  |inst_srlv| inst_bltzal | inst_bgezal | inst_mfhi | inst_mflo;
    //写到哪个寄存器
    // store in [rd]
    assign sel_rf_dst[0] = inst_sub | inst_subu |inst_addu | inst_sll | inst_or | inst_xor | inst_srav | inst_sltu | inst_slt
                          |inst_add | inst_and  |inst_nor  | inst_sllv| inst_sra| inst_srl | inst_srlv | inst_mfhi | inst_mflo;        //例如要是想存在rd堆里
    // store in [rt] 
    assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu| inst_lw | inst_slti| inst_sltiu | inst_addi | inst_andi | inst_xori;
    // store in [31]
    assign sel_rf_dst[2] = inst_jal | inst_jalr| inst_bltzal | inst_bgezal;            //jalr不是存在rd中吗？ --默认先存到31位寄存器中

    // sel for regfile address
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd   //则会把他扩展成5位
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    //写什么内容
    // 0 from alu_res ; 1 from ld_res
    assign sel_rf_res = inst_lw; 
    //解码部分结束

    
    //assign stallreq_for_load = inst_lw ;

    //打包总线，传给EX段
    assign id_to_ex_bus = {
        hilo_op,
        mem_op,
        id_pc,          // 158:127
        inst,           // 126:95
        alu_op,         // 94:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        rdata1,         // 63:32
        rdata2          // 31:0
    };

    //跳转处理：判断当前指令是不是跳转指令
    wire br_e;
    wire [31:0] br_addr;
    wire rs_eq_rt;
    wire rs_ge_z;
    wire rs_gt_z;
    wire rs_le_z;
    wire rs_lt_z;
    wire [31:0] pc_plus_4;
    assign pc_plus_4 = id_pc + 32'h4;

    assign rs_eq_rt = (rdata1 == rdata2);//比较两个寄存器里的值一不一样，用于beq和bne指令
    assign rs_ge_z = ~rdata1[31];
    assign rs_gt_z = ($signed(rdata1)>0);
    assign rs_le_z  = (rdata1[31]==1'b1||rdata1==32'b0);
    assign rs_lt_z = rdata1[31];

    assign br_e = inst_beq & rs_eq_rt // beq且相等
                | inst_bne & ~rs_eq_rt // bne且不相等
                | inst_bgez & rs_ge_z
                | inst_bgezal & rs_ge_z
                | inst_bgtz & rs_gt_z
                | inst_blez & rs_le_z
                | inst_bltz & rs_lt_z
                | inst_bltzal & rs_lt_z
                | inst_j |inst_jal | inst_jalr | inst_jr; // 无条件跳转
    //计算跳转地址
    assign br_addr = inst_beq  ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) 
                    :inst_bne  ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) 
                    :inst_bgez ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) 
                    :inst_bgtz ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) 
                    :inst_blez ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0})
                    :inst_bltz ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0})  
                    :inst_bltzal ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0})  
                    :inst_bgezal ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) 
                    :inst_j    ? {id_pc[31:28],instr_index,2'b0}
                    :inst_jal  ? {id_pc[32:28],instr_index,2'b0}
                    :inst_jr   ? rdata1
                    :inst_jalr ? rdata1 
                    :32'b0;
 //打包跳转信息
    assign br_bus = {
        br_e,//是否跳转
        br_addr//跳转地址
    };
    /*
    IF段取指令 → ID段 
    1. 解码指令 
    2. 读寄存器（可能前推 
    3. 生成控制信号 
    4. 判断是否跳转
    然后判断：1.id_to_ex_bus （给EX段执行）
             2.  br_bus（给IF段更新PC）
    */


endmodule