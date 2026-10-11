module hart #(
    // After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00000000
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // Instruction fetch goes through a read only instruction memory (imem)
    // port. The port accepts a 32-bit address (e.g. from the program counter)
    // per cycle and combinationally returns a 32-bit instruction word. This
    // is not representative of a realistic memory interface; it has been
    // modeled as more similar to a DFF or SRAM to simplify phase 3. In
    // later phases, you will replace this with a more realistic memory.
    //
    // 32-bit read address for the instruction memory. This is expected to be
    // 4 byte aligned - that is, the two LSBs should be zero.
    output wire [31:0] o_imem_raddr,
    // Instruction word fetched from memory, available on the same cycle.
    input  wire [31:0] i_imem_rdata,
    // Data memory accesses go through a separate read/write data memory (dmem)
    // that is shared between read (load) and write (stored). The port accepts
    // a 32-bit address, read or write enable, and mask (explained below) each
    // cycle. Reads are combinational - values are available immediately after
    // updating the address and asserting read enable. Writes occur on (and
    // are visible at) the next clock edge.
    //
    // Read/write address for the data memory. This should be 32-bit aligned
    // (i.e. the two LSB should be zero). See `o_dmem_mask` for how to perform
    // half-word and byte accesses at unaligned addresses.
    output wire [31:0] o_dmem_addr,
    // When asserted, the memory will perform a read at the aligned address
    // specified by `i_addr` and return the 32-bit word at that address
    // immediately (i.e. combinationally). It is illegal to assert this and
    // `o_dmem_wen` on the same cycle.
    output wire        o_dmem_ren,
    // When asserted, the memory will perform a write to the aligned address
    // `o_dmem_addr`. When asserted, the memory will write the bytes in
    // `o_dmem_wdata` (specified by the mask) to memory at the specified
    // address on the next rising clock edge. It is illegal to assert this and
    // `o_dmem_ren` on the same cycle.
    output wire        o_dmem_wen,
    // The 32-bit word to write to memory when `o_dmem_wen` is asserted. When
    // write enable is asserted, the byte lanes specified by the mask will be
    // written to the memory word at the aligned address at the next rising
    // clock edge. The other byte lanes of the word will be unaffected.
    output wire [31:0] o_dmem_wdata,
    // The dmem interface expects word (32 bit) aligned addresses. However,
    // the processor supports byte and half-word loads and stores at unaligned and
    // 16-bit aligned addresses, respectively. To support this, the access
    // mask specifies which bytes within the 32-bit word are actually read
    // from or written to memory.
    //
    // To perform a half-word read at address 0x00001002, align `o_dmem_addr`
    // to 0x00001000, assert `o_dmem_ren`, and set the mask to 0b1100 to
    // indicate that only the upper two bytes should be read. Only the upper
    // two bytes of `i_dmem_rdata` can be assumed to have valid data; to
    // calculate the final value of the `lh[u]` instruction, shift the rdata
    // word right by 16 bits and sign/zero extend as appropriate.
    //
    // To perform a byte write at address 0x00002003, align `o_dmem_addr` to
    // `0x00002000`, assert `o_dmem_wen`, and set the mask to 0b1000 to
    // indicate that only the upper byte should be written. On the next clock
    // cycle, the upper byte of `o_dmem_wdata` will be written to memory, with
    // the other three bytes of the aligned word unaffected. Remember to shift
    // the value of the `sb` instruction left by 24 bits to place it in the
    // appropriate byte lane.
    output wire [ 3:0] o_dmem_mask,
    // The 32-bit word read from data memory. When `o_dmem_ren` is asserted,
    // this will immediately reflect the contents of memory at the specified
    // address, for the bytes enabled by the mask. When read enable is not
    // asserted, or for bytes not set in the mask, the value is undefined.
    input  wire [31:0] i_dmem_rdata,
	// The output `retire` interface is used to signal to the testbench that
    // the CPU has completed and retired an instruction. A single cycle
    // implementation will assert this every cycle; however, a pipelined
    // implementation that needs to stall (due to internal hazards or waiting
    // on memory accesses) will not assert the signal on cycles where the
    // instruction in the writeback stage is not retiring.
    //
    // Asserted when an instruction is being retired this cycle. If this is
    // not asserted, the other retire signals are ignored and may be left invalid.
    output wire        o_retire_valid,
    // The 32 bit instruction word of the instrution being retired. This
    // should be the unmodified instruction word fetched from instruction
    // memory.
    output wire [31:0] o_retire_inst,
    // Asserted if the instruction produced a trap, due to an illegal
    // instruction, unaligned data memory access, or unaligned instruction
    // address on a taken branch or jump.
    output wire        o_retire_trap,
    // Asserted if the instruction is an `ebreak` instruction used to halt the
    // processor. This is used for debugging and testing purposes to end
    // a program.
    output wire        o_retire_halt,
    // The first register address read by the instruction being retired. If
    // the instruction does not read from a register (like `lui`), this is
    // don't-care -- the grading testbench doesn't look at it in that case.
    output wire [ 4:0] o_retire_rs1_raddr,
    // The second register address read by the instruction being retired. If
    // the instruction does not read from a second register (like `addi`),
    // this is don't-care -- the grading testbench doesn't look at it in that
    // case.
    output wire [ 4:0] o_retire_rs2_raddr,
    // The first source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs1 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs1_rdata,
    // The second source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs2 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs2_rdata,
    // The destination register address written by the instruction being
    // retired. If the instruction does not write to a register (like `sw`),
    // this should be 5'd0.
    output wire [ 4:0] o_retire_rd_waddr,
    // The destination register data written to the register file in the
    // writeback stage by this instruction. If rd is 5'd0, this field is
    // ignored and can be treated as a don't care.
    output wire [31:0] o_retire_rd_wdata,
    // The current program counter of the instruction being retired - i.e.
    // the instruction memory address that the instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // the next program counter after the instruction is retired. For most
    // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
    // target for *taken* branches and jumps.
    output wire [31:0] o_retire_next_pc

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);
    // From class, the loop is fetch -> decode -> execute -> write back  
    // Instruction Decoder, takes in i_inst (from instruction memory):
    // i_imem_rdata contains instruction word
    wire [6:0] funct7 = i_imem_rdata[31:25];
    wire [4:0] rs2 = i_imem_rdata[24:20];
    wire [4:0] rs1 = i_imem_rdata[19:15];
    wire [2:0] funct3 = i_imem_rdata[14:12];
    wire [4:0] rd = i_imem_rdata[11:7];
    wire [6:0] opcode = i_imem_rdata[6:0];


    // Data register outputs
    reg i_reg_write; // Write to register
    reg select_a; // For ALU Mux
    reg select_b; // For ALU Mux
    reg [2:0] i_opsel; // For ALU
    reg i_mem_read; // For data memory read
    reg i_mem_write; // For data memory write
    reg [1:0] select_c; // Memory to register mux
    reg i_branch;
    reg i_jal;
    reg i_jalr;
    reg i_halt;

    // TODO: Tell Evan to include these in instruction decoder
    reg i_sub;
    reg i_unsigned;
    reg i_arith;
    reg [5:0] i_format;
    reg [3:0] i_mem_mask;
    reg i_trap; 

    // Use the opcode to determine instruction type
    always @(*) begin
            // Default values to avoid latches
            i_reg_write = 1'b0;
            select_a    = 1'b0;
            select_b    = 1'b0;
            i_opsel     = 3'b000;
            i_sub       = 1'b0;
            i_unsigned  = 1'b0;
            i_arith     = 1'b0;
            i_mem_read  = 1'b0;
            i_mem_write = 1'b0;
            select_c    = 2'b00;
            i_branch    = 1'b0;
            i_jal       = 1'b0;
            i_jalr      = 1'b0;
            i_halt      = 1'b0;
            i_format    = 6'b000000;
            i_mem_mask  = 4'b0000;
            i_trap      = 1'b0;
            
        case(opcode)

            7'b0110011: begin // r
                i_reg_write = 1'b1; // Write to register from ALU output
                select_a = 1'b0; // rs1
                select_b = 1'b0; // rs2
                i_opsel = funct3; // ALU operation
                i_sub = funct7[5]; // Determine if add/sub
                i_unsigned = (funct3 == 3'b011); // For SLT / SLTU
                i_arith = funct7[5]; // Determine if arithmetic shift
                select_c = 2'b00; // Use ALU output and write to reg
                i_format = 6'b000001; // R type, for imm.v (one hot)
            end

            7'b0010011: begin // i, register arithmetic
                // Same as r type, but select_b uses immediate and no subtraction
                i_reg_write = 1'b1;
                select_a = 1'b0; // rs1
                select_b = 1'b1; // immediate
                i_opsel = funct3; 
                i_sub = 1'b0; // No subtraction for i type
                i_unsigned = (funct3 == 3'b011); // For SLTI / SLTIU
                i_arith = funct7[5];
                select_c = 2'b00;
                i_format = 6'b000010; // I type
            end
            7'b0000011: begin // i, load
            end
            7'b1100111: begin // i, jalr
            end


            7'b0100011: begin // s
            end


            7'b1100011: begin // b 
                i_branch = 1'b1;
                select_a = 1'b0; // rs1
                select_b = 1'b0; // rs2
                i_unsigned = funct3[1]; // Unsigned, BLTU/BGEU
                i_format = 6'b001000; // B
                // no i_opsel because branch instructions only use ALU flags, not the ALU output
            end


            7'b0110111: begin // u, lui - Load upper immediate into rd
                i_reg_write = 1'b1;
                select_c = 2'b11; // Use immediate directly
                i_format = 6'b010000; // U type
            end
            7'b0010111: begin // u, auipc - Add upper immediate to PC, write to rd
                i_reg_write = 1'b1;
                select_a = 1'b1; // PC
                select_b = 1'b1; // Immediate
                select_c = 2'b00;
                i_format = 6'b010000; // U type
            end


            7'b1101111: begin // j
            end
            default: begin
                i_trap = 1'b1; // Illegal instruction
            end
        endcase

    end

    // PC
    reg [31:0] pc;
    always @(posedge i_clk) begin
        if (i_rst) begin
            pc <= RESET_ADDR;
        end else begin
            pc <= pc_next; // TODO: Add more logic later for jumps
        end
        // TODO: Add more logic for updating        
    end
        // TODO:
        assign o_imem_raddr = pc;
        assign o_retire_pc = pc;


    // Register File
    wire [31:0] rs1_rdata;
    wire [31:0] rs2_rdata;
    wire [31:0] rd_wdata; // TODO: drive this from your write-back mux (select_c)

    rf #(
        .BYPASS_EN(0)
    ) u_rf (
        .i_clk      (i_clk),
        .i_rst      (i_rst),
        .i_rs1_raddr(rs1),
        .o_rs1_rdata(rs1_rdata),
        .i_rs2_raddr(rs2),
        .o_rs2_rdata(rs2_rdata),
        .i_rd_wen   (i_reg_write),
        .i_rd_waddr (rd),
        .i_rd_wdata (rd_wdata)
    );

    // Immediate
    wire [31:0] immediate;

    imm u_imm (
        .i_inst      (i_imem_rdata),
        .i_format    (i_format),
        .o_immediate (immediate)
    );

    // ALU 
    wire [31:0] alu_op1;
    wire [31:0] alu_op2;
    wire [31:0] alu_result;
    wire        alu_eq;
    wire        alu_slt;

    alu u_alu (
        .i_opsel    (i_opsel),
        .i_sub      (i_sub),
        .i_unsigned (i_unsigned),
        .i_arith    (i_arith),
        .i_op1      (alu_op1),
        .i_op2      (alu_op2),
        .o_result   (alu_result),
        .o_eq       (alu_eq),
        .o_slt      (alu_slt)
    );

    // Muxes (Select A / B are ALU, Select C is RF)
    assign alu_op1 = select_a ? pc : rs1_rdata;
    assign alu_op2 = select_b ? immediate : rs2_rdata;
    // TODO: Update the pc + 4 later on
    assign rd_wdata = (select_c == 2'b00) ? alu_result : (select_c == 2'b01) ? i_dmem_rdata : (select_c == 2'b10) ? pc + 4 : immediate;


    // Retire signals (For TB)
    assign o_retire_valid = 1'b1; // Always a 1 since we are a single cycle processor
    assign o_retire_inst = i_imem_rdata;
    assign o_retire_trap = i_trap;
    assign o_retire_halt = i_halt;
    
    assign o_retire_rs1_raddr = rs1; // Don't care if doesn't use rs1
    assign o_retire_rs2_raddr = rs2; // Don't care if doesn't use rs2
    assign o_retire_rs1_rdata = rs1_rdata; // Don't worry about rs1 being 0 because RF module guarantees 0
    assign o_retire_rs2_rdata = rs2_rdata;
    // Should be 5'd0 if we don't write to register for waddr, (wdata is don't care)
    assign o_retire_rd_waddr = i_reg_write ? rd : 5'd0;
    assign o_retire_rd_wdata = rd_wdata;

    assign o_retire_next_pc = pc_next; // TODO: Update this later for jumps


    // Data Memory Signals (Will be updated later for load/store)
    assign o_dmem_addr = alu_result; // Address is the result of the ALU
    assign o_dmem_wdata = rs2_rdata;
    assign o_dmem_ren = i_mem_read;
    assign o_dmem_wen = i_mem_write;
    assign o_dmem_mask = i_mem_mask;


    // Branch logic, using outputs from ALU (Equal and SLT).
    // Determines if PC should be updated to a branch or not based on operation and ALU flags
    wire branch_taken = i_branch && (
        (funct3 == 3'b000) ? alu_eq : 
        (funct3 == 3'b001) ? !alu_eq :
        (funct3 == 3'b100) ? alu_slt :
        (funct3 == 3'b101) ? !alu_slt :
        (funct3 == 3'b110) ? alu_slt :
        (funct3 == 3'b111) ? !alu_slt : 1'b0);

    wire [31:0] branch_target = pc + immediate;
    // If branch taken, update PC accordingy
    wire [31:0] pc_next = (branch_taken) ? branch_target : pc + 4;

endmodule

`default_nettype wire
