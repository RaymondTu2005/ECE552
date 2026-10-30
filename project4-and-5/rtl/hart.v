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
    output wire [31:0] o_retire_dmem_addr,
    output wire [ 3:0] o_retire_dmem_mask,
    output wire        o_retire_dmem_ren,
    output wire        o_retire_dmem_wen,
    output wire [31:0] o_retire_dmem_rdata,
    output wire [31:0] o_retire_dmem_wdata,
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
    // From project 3, we had one single cycle for all of the stages. We still do the same thing in each stage, so the same logic
    // but have to add some registers to hold values at each stage (maybe between stages, not sure yet), so that we can support pipelining
    // Reformatted to have 5 stages to make more clear what is happening in each stage (hopefully helpful for future / debugging)

    // Have to declare signals before use for gradescope compiler, gave us an error before
    wire        stall_pc;
    wire        stall_fetch_decode;
    wire        hazard_detected;
    wire        control_hazard_in_decode;
    wire        control_hazard_in_execute;
    wire        branch_taken;
    wire        redirect_in_execute;
    wire [31:0] jalr_target;
    reg  [31:0] pc_to_execute;
    reg  [31:0] immediate_to_execute;
    reg         i_jal_to_execute;
    reg         i_jalr_to_execute;
    reg         i_branch_to_execute;
    reg  [4:0]  rd_to_execute;
    reg  [4:0]  rd_to_memory;
    reg  [4:0]  rd_to_writeback;
    reg         i_reg_write_to_execute;
    reg         i_reg_write_to_memory;
    reg         i_reg_write_to_writeback;

    // 5 Stages: Fetch, Decode, Execute, Memory, Writeback

    // Fetch
    // Requires the program counter and o_imem_raddr, which is the instruction memory address to read from.

    // Fetch signals
    wire [31:0] pc_next;

        // Program counter register

    reg [31:0] pc;
    always @(posedge i_clk) begin
        if (i_rst) begin
            pc <= RESET_ADDR;
        end else if (stall_pc) begin 
            pc <= pc;
        end else begin
            pc <= pc_next;
        end
    end
    assign o_imem_raddr = pc;
    // Different from project 3 since instruction being fetched currently is not same as instruction being retired, since we have pipelining
    // Since this is the instruction at the very end, that means we need to keep the pc value at every stage (Register transition)

    // PC_NEXT is based on signals routed from execute stage for branch / jump instructions
    assign pc_next = (branch_taken || i_jal_to_execute) ? (pc_to_execute + immediate_to_execute) : (i_jalr_to_execute) ? jalr_target : pc + 4;
    
    // Pipeline register, fetch -> decode
    // We want to basically store the current value at the PC wire, so that it can be used again in the next cycle 
    // To contain the new instruction (assuming no nops / stalls)
    // But then we update register at each time, so pc wire before clock is preserved but after clock is ready to be updated
    // Also need to store 
    reg [31:0] pc_to_decode;
    always @(posedge i_clk) begin
        if (i_rst) begin
            pc_to_decode <= RESET_ADDR;
        end else if (redirect_in_execute) begin
            // We are actualy redirecting, so next pc to decode doens't matter / is discarded
            pc_to_decode <= 32'b0;
        end else if (control_hazard_in_execute) begin
            // Since redirect_in_execute did not assert, mean we have a branch that didn't take it, so we don't discard the current PC.
            pc_to_decode <= pc;
        end else if (hazard_detected || control_hazard_in_decode) begin
            pc_to_decode <= pc_to_decode;
        end else begin
            pc_to_decode <= pc;
        end
    end


    // We need to prepare the stuff that decode needs inside this register, since that is going to be updated on the next nxt cycle
    // That is i_imem_rdata, since that will change in the next cycle for the next instruction, so we preserve it as well.
    reg [31:0] inst_to_decode;
    // Signal so that if we reset, we know there is no valid instruction to decode and we don't trap, which caused a reset error in our test cases.
    reg decode_has_inst;
    always @(posedge i_clk) begin
        if (i_rst) begin
            inst_to_decode <= 32'b0; // Not decoding if we just reset, so no instruction to decode
            decode_has_inst <= 1'b0;
        end else if (redirect_in_execute) begin
            // Again, we redirected so doesn't matter what we currently send to decode, since that is discarded
            inst_to_decode <= 32'b0;
            decode_has_inst <= 1'b0; // On reset, it shouldn't have a valid instruction to decode, done so that we avoid the trap.
        end else if (control_hazard_in_execute) begin
            // Didn't take the branch, so we have to keep the current instruction and send it to decode since its not discarded.
            inst_to_decode <= i_imem_rdata;
            decode_has_inst <= 1'b1;
        end else if (hazard_detected || control_hazard_in_decode) begin
            // This means there is either a data hazard or a branch instruction is still waiting in execute for results, so keep same value
            // This fixed the bug where we had an infinite loop where the branch instruction in execute resolved, but i_branch still was held
            // So that the instruction in decode is not overwritten and then it caused the hazard to keep persisting.
            inst_to_decode <= inst_to_decode;
            decode_has_inst <= decode_has_inst;
        end else begin
            inst_to_decode <= i_imem_rdata;
            decode_has_inst <= 1'b1;
        end
    end



    // Decode stage
    // Requires the instruction decoder we used where we determined the opcode and other fields, then associated it with a instruction
    // We need to identify dependencies and send control signals to pipeline registesr, so that we can stall it until the dependency is finished.
    // So we stall it in this stage

    // Decoder signals
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
    reg i_sub;
    reg i_unsigned;
    reg i_arith;
    reg [5:0] i_format;
    reg i_trap; 


    // Fields, but instead, read from the register F -> D, instead of i_imem_rdata
    wire [6:0] funct7 = inst_to_decode[31:25];
    wire [4:0] rs2 = inst_to_decode[24:20];
    wire [4:0] rs1 = inst_to_decode[19:15];
    wire [2:0] funct3 = inst_to_decode[14:12];
    wire [4:0] rd = inst_to_decode[11:7];
    wire [6:0] opcode = inst_to_decode[6:0];

    // Decoder itself
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
                i_reg_write = 1'b1;
                select_a = 1'b0;
                select_b = 1'b1; // Immediate / offset
                i_opsel = 3'b000; // Add for rs1 + offset for address
                i_sub = 1'b0;
                i_mem_read = 1'b1;
                select_c = 2'b01; // o_rdata from schematic
                i_format = 6'b000010; // I
            end
            7'b1100111: begin // i, jalr
                i_reg_write = 1'b1; // PC + 4
                select_c = 2'b10; // PC + 4
                i_jalr = 1'b1; // For updating PC to jump target
                i_format = 6'b000010; // I
            end


            7'b0100011: begin // s, store, which is write to offset + rs1 and then write rs2 to that address
                i_mem_write = 1'b1;
                select_a = 1'b0; // rs1
                select_b = 1'b1; // immediate
                i_opsel = 3'b000; // Add for address
                i_sub = 1'b0;
                i_format = 6'b000100; // S
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


            7'b1101111: begin // jal
                i_reg_write = 1'b1; // Store return address in rd, (pc + 4)
                select_c = 2'b10; // PC + 4
                i_jal = 1'b1; // For updating PC to jump target
                i_format = 6'b100000; // J
            end
            7'b1110011: begin // ebreak, for testing

                i_halt = (inst_to_decode[31:20] == 12'b000000000001); // ebreak instruction
            end
            default: begin
                i_trap = 1'b1; // Illegal instruction
            end
        endcase
    end

        // Instantiations of the immediate and rf, since we can get their outputs now (all of the inputs currently available)
        // We don't need it in the next stage, but it's easier to pipeline only its output instead of all of the signals needed for input later on

        // Register File
    wire [31:0] rs1_rdata;
    wire [31:0] rs2_rdata;
    wire [31:0] rd_wdata;

    rf #(
        .BYPASS_EN(0)
    ) u_rf (
        .i_clk      (i_clk),
        .i_rst      (i_rst),
        .i_rs1_raddr(rs1),
        .o_rs1_rdata(rs1_rdata),
        .i_rs2_raddr(rs2),
        .o_rs2_rdata(rs2_rdata),
        // Writeback logic is updated in the writeback stage, so reference those signals / registers.
        .i_rd_wen   (i_reg_write_to_writeback),
        .i_rd_waddr (rd_to_writeback),
        .i_rd_wdata (rd_wdata)
    );

    // Immediate
    wire [31:0] immediate;

    imm u_imm (
        .i_inst      (inst_to_decode),
        .i_format    (i_format),
        .o_immediate (immediate)
    );

    // For step 2, need to delay in this stage when there is a hazard like RAW that we need to wait for.
    // Can detect this hazard by basically checking if the registers we are reading from are same as a destination for another instruction
    // That is in the execute or memory or writeback stage
    // When it actually is used. So we check if that stage is writing and it is the same register (not x0), and if it is, then stall

    // NOTE: For project 5, we need to check if rs2 is acutally being used (like addi) doesn't use it. So add logic for that in project 5 - skipping for now since CPI doesn't matter and doesn't affect correctness to delay.
    wire hazard_execute = i_reg_write_to_execute && (rd_to_execute != 5'b0) && (rs1 == rd_to_execute || rs2 == rd_to_execute);
    wire hazard_memory = i_reg_write_to_memory && (rd_to_memory != 5'b0) && (rs1 == rd_to_memory || rs2 == rd_to_memory);
    wire hazard_writeback = i_reg_write_to_writeback && (rd_to_writeback != 5'b0) && (rs1 == rd_to_writeback || rs2 == rd_to_writeback);

    assign hazard_detected = hazard_execute || hazard_memory || hazard_writeback; // For any hazard detected

    // Need to stall signals when a hazard is detected, especially for branch / jumps, since those take two cycles to determine
    // We need to check if a branch or jump is in execute stage, since that is when it is resolved and taken or not, which cant be determined in decode
    assign control_hazard_in_decode = i_branch || i_jal || i_jalr;
    assign control_hazard_in_execute = i_branch_to_execute || i_jal_to_execute || i_jalr_to_execute;

    // We need to pause fetch -> decode and decode -> execute
    // stall_pc has to be !control_hazard_in_execute or we get a one off cycle, since control_hazard_in_decode is asserted 1 cycle too late (asserted alongside hazard_in_execute, so make conditional for both)
    assign stall_pc = hazard_detected || (control_hazard_in_decode && !control_hazard_in_execute); // Keep PC in fetch the same, but release once the branch/jump has actually moved on to execute (if executed for branches)
    assign stall_fetch_decode = hazard_detected || control_hazard_in_decode || redirect_in_execute; // Stall signals from fetch -> Decode. We don't stall when branch not taken (!redirect_in_execute)


    // For the fetch instructions, we just hold the current values. But for anything beyond execute, want to avoid holding same instruction
    wire stall_hazard_execute = hazard_detected || control_hazard_in_execute; // In case of branch / jump, we need to wait until outcome is known in execute from ALU operations


    // Decode -> Execute pipeline registers, separated to make it easier to read
        // PC and instruction
    reg [31:0] inst_to_execute;
    always @(posedge i_clk) begin
        if (i_rst) begin
            pc_to_execute <= RESET_ADDR;
            inst_to_execute <= 32'b0;
        end else if (stall_hazard_execute) begin
            pc_to_execute <= 32'b0;
            inst_to_execute <= 32'b0;
        end else begin
            pc_to_execute <= pc_to_decode;
            inst_to_execute <= inst_to_decode;
        end
    end
        // Signals for writeback logic
    reg [4:0] rs1_to_execute; // Address
    reg [4:0] rs2_to_execute; // Address
        always @(posedge i_clk) begin
            if (i_rst) begin
                i_reg_write_to_execute <= 1'b0;
                rd_to_execute <= 5'b0;
                rs1_to_execute <= 5'b0;
                rs2_to_execute <= 5'b0;
            end else if (stall_hazard_execute) begin
                i_reg_write_to_execute <= 1'b0;
                rd_to_execute <= 5'b0;
                rs1_to_execute <= 5'b0;
                rs2_to_execute <= 5'b0;
            end else begin
                i_reg_write_to_execute <= i_reg_write;
                rd_to_execute <= rd;
                rs1_to_execute <= rs1;
                rs2_to_execute <= rs2;
            end
        end

        // Signals for muxes
    reg select_a_to_execute;
    reg [31:0] rs1_rdata_to_execute;
    reg select_b_to_execute;
    reg [31:0] rs2_rdata_to_execute;
    reg [1:0] select_c_to_execute;
    always @(posedge i_clk) begin
        if (i_rst) begin
            select_a_to_execute <= 1'b0;
            rs1_rdata_to_execute <= 32'b0;
            select_b_to_execute <= 1'b0;
            rs2_rdata_to_execute <= 32'b0;
            select_c_to_execute <= 2'b0;
            immediate_to_execute <= 32'b0;
        end else if (stall_hazard_execute) begin
            select_a_to_execute <= 1'b0;
            rs1_rdata_to_execute <= 32'b0;
            select_b_to_execute <= 1'b0;
            rs2_rdata_to_execute <= 32'b0;
            select_c_to_execute <= 2'b0;
            immediate_to_execute <= 32'b0;
        end else begin
            select_a_to_execute <= select_a;
            rs1_rdata_to_execute <= rs1_rdata;
            select_b_to_execute <= select_b;
            rs2_rdata_to_execute <= rs2_rdata;
            select_c_to_execute <= select_c;
            immediate_to_execute <= immediate;
        end
    end
        // ALU Logic
    reg [2:0] i_opsel_to_execute;
    reg i_sub_to_execute;
    reg i_unsigned_to_execute;
    reg i_arith_to_execute;
    always @(posedge i_clk) begin
        if (i_rst) begin
            i_opsel_to_execute <= 3'b000;
            i_sub_to_execute <= 1'b0;
            i_unsigned_to_execute <= 1'b0;
            i_arith_to_execute <= 1'b0;
        end else if (stall_hazard_execute) begin
            i_opsel_to_execute <= 3'b000;
            i_sub_to_execute <= 1'b0;
            i_unsigned_to_execute <= 1'b0;
            i_arith_to_execute <= 1'b0;
        end else begin
            i_opsel_to_execute <= i_opsel;
            i_sub_to_execute <= i_sub;
            i_unsigned_to_execute <= i_unsigned;
            i_arith_to_execute <= i_arith;
        end
    end

        // Branch / Jump Logic
    always @(posedge i_clk) begin
        if (i_rst) begin
            i_branch_to_execute <= 1'b0;
            i_jal_to_execute <= 1'b0;
            i_jalr_to_execute <= 1'b0;
        end else if (stall_hazard_execute) begin
            i_branch_to_execute <= 1'b0;
            i_jal_to_execute <= 1'b0;
            i_jalr_to_execute <= 1'b0;
        end else begin
            i_branch_to_execute <= i_branch;
            i_jal_to_execute <= i_jal;
            i_jalr_to_execute <= i_jalr;
        end
    end

        // Memory Logic
    reg i_mem_read_to_execute;
    reg i_mem_write_to_execute;
    always @(posedge i_clk) begin
        if (i_rst) begin
            i_mem_read_to_execute <= 1'b0;
            i_mem_write_to_execute <= 1'b0;
        end else if (stall_hazard_execute) begin
            i_mem_read_to_execute <= 1'b0;
            i_mem_write_to_execute <= 1'b0;
        end else begin
            i_mem_read_to_execute <= i_mem_read;
            i_mem_write_to_execute <= i_mem_write;
        end
    end

        // Trap / Halt / Retire Logic
    reg i_trap_to_execute;
    reg i_halt_to_execute;
    reg stall_hazard_to_execute;
    always @(posedge i_clk) begin
        if (i_rst) begin
            i_trap_to_execute <= 1'b0;
            i_halt_to_execute <= 1'b0;
            stall_hazard_to_execute <= 1'b1; // Treat the post-reset pipeline as holding a bubble
        end else if (stall_hazard_execute) begin
            i_trap_to_execute <= 1'b0;
            i_halt_to_execute <= 1'b0;
            stall_hazard_to_execute <= stall_hazard_execute;
        end else begin
            i_trap_to_execute <= i_trap;
            i_halt_to_execute <= i_halt;
            stall_hazard_to_execute <= stall_hazard_execute || !decode_has_inst; // If decode doesn't have instruction, signal there is a hazard and input some value that will be discarded
        end
    end

    
    
    // Execute stage
    // ALU logic stuff, and also the branch / jump logic, updating PC

    // ALU instantiation
    wire [31:0] alu_op1;
    wire [31:0] alu_op2; 
    wire [31:0] alu_result;
    wire alu_eq;
    wire alu_slt;

    alu u_alu (
        .i_opsel    (i_opsel_to_execute),
        .i_sub      (i_sub_to_execute),
        .i_unsigned (i_unsigned_to_execute),
        .i_arith    (i_arith_to_execute),
        .i_op1      (alu_op1),
        .i_op2      (alu_op2),
        .o_result   (alu_result),
        .o_eq       (alu_eq),
        .o_slt      (alu_slt)
    );

    assign alu_op1 = select_a_to_execute ? pc_to_execute : rs1_rdata_to_execute;
    assign alu_op2 = select_b_to_execute ? immediate_to_execute : rs2_rdata_to_execute;

    // Jump / Branch logic
    assign branch_taken = i_branch_to_execute && (
        (inst_to_execute[14:12] == 3'b000) ? alu_eq : 
        (inst_to_execute[14:12] == 3'b001) ? !alu_eq :
        (inst_to_execute[14:12] == 3'b100) ? alu_slt :
        (inst_to_execute[14:12] == 3'b101) ? !alu_slt :
        (inst_to_execute[14:12] == 3'b110) ? alu_slt :
        (inst_to_execute[14:12] == 3'b111) ? !alu_slt : 1'b0);

    // Fixes a bug when branch instructions would not jump (Since they are conditional), causing tests to fail (since I assumed it would always pass before)
    assign redirect_in_execute = branch_taken || i_jal_to_execute || i_jalr_to_execute;

    assign jalr_target = ( rs1_rdata_to_execute + immediate_to_execute) & 32'hfffffffe; // Clear LSB for jalr, word aligned
    
    wire [31:0] pc_next_execute = (branch_taken || i_jal_to_execute) ? (pc_to_execute + immediate_to_execute) : (i_jalr_to_execute) ? jalr_target : pc_to_execute + 4;

    // Execute to Memory Registers
        // PC
        reg [31:0] pc_to_memory;
        reg [31:0] pc_next_to_memory; // For writeback stage, o_retire_next_pc
        always @(posedge i_clk) begin
            if (i_rst) begin
                pc_to_memory <= 32'b0;
                pc_next_to_memory <= 32'b0;
            end else begin
                pc_to_memory <= pc_to_execute;
                pc_next_to_memory <= pc_next_execute;
            end
        end

        // Used for memory reads / writes
        reg [31:0] alu_result_to_memory; // Load / stores addresses
        reg [31:0] rs1_rdata_to_memory;
        reg [31:0] rs2_rdata_to_memory; // Store data
        reg i_mem_read_to_memory;
        reg i_mem_write_to_memory;
        reg [31:0] inst_to_memory; // Contains funct3, which we need later on, might need for other things as well, so pass whole thing just in case
        always @(posedge i_clk) begin
            if (i_rst) begin
                alu_result_to_memory <= 32'b0;
                rs1_rdata_to_memory <= 32'b0;
                rs2_rdata_to_memory <= 32'b0;
                i_mem_read_to_memory <= 1'b0;
                i_mem_write_to_memory <= 1'b0;
                inst_to_memory <= 32'b0;
            end else begin
                alu_result_to_memory <= alu_result;
                rs1_rdata_to_memory <= rs1_rdata_to_execute;
                rs2_rdata_to_memory <= rs2_rdata_to_execute;
                i_mem_read_to_memory <= i_mem_read_to_execute;
                i_mem_write_to_memory <= i_mem_write_to_execute;
                inst_to_memory <= inst_to_execute;
            end
        end

        // Other signals needed in write back, pass through memory stage
        reg [4:0] rs1_to_memory;
        reg [4:0] rs2_to_memory;
        reg [1:0] select_c_to_memory;
        reg [31:0] immediate_to_memory;

        always @(posedge i_clk) begin 
            if (i_rst) begin
                i_reg_write_to_memory <= 1'b0;
                rd_to_memory <= 4'b0000;
                rs1_to_memory <= 4'b0000;
                rs2_to_memory <= 4'b0000;
                select_c_to_memory <= 2'b0;
                immediate_to_memory <= 32'b0;
            end else begin
                i_reg_write_to_memory <= i_reg_write_to_execute;
                rd_to_memory <= rd_to_execute;
                rs1_to_memory <= rs1_to_execute;
                rs2_to_memory <= rs2_to_execute;
                select_c_to_memory <= select_c_to_execute;
                immediate_to_memory <= immediate_to_execute;
            end
        end
        
        // Trap / retire
        reg i_trap_to_memory;
        reg i_halt_to_memory;
        reg stall_hazard_to_memory;
        always @(posedge i_clk) begin
            if (i_rst) begin
                i_trap_to_memory <= 1'b0;
                i_halt_to_memory <= 1'b0;
                stall_hazard_to_memory <= 1'b1; // Treat the post-reset pipeline as holding a bubble
            end else begin
                i_trap_to_memory <= i_trap_to_execute;
                i_halt_to_memory <= i_halt_to_execute;
                stall_hazard_to_memory <= stall_hazard_to_execute;
            end
        end


    // Memory
    // Mask generation for read / write (Store / load), also memory access logic like sign vs zero extend for load/stores, and o_dmem signals
    
    // Masking logic to word align o_dmem_addr
    // Funct3[1:0] determines size of access, with 00 = byte, 01 = half, 10 = word. Passed by inst_to_memory from EX to MEM registrs.
    // Also, ALU result is used for which half word or byte to access
    reg [3:0] memory_mask;
    always @(*) begin
        memory_mask = 4'b0000; // Default to no access
    case(inst_to_memory[13:12])
        2'b00: begin // Byte
            case(alu_result_to_memory[1:0])
                2'b00: memory_mask = 4'b0001; 
                2'b01: memory_mask = 4'b0010; 
                2'b10: memory_mask = 4'b0100; 
                2'b11: memory_mask = 4'b1000; 
                default: memory_mask = 4'b0000; // For gradescope compiler
            endcase
        end
        2'b01: begin // Half word
            case(alu_result_to_memory[1:0])
                2'b00: memory_mask = 4'b0011;
                2'b10: memory_mask = 4'b1100; 
                default: memory_mask = 4'b0000; // Avoid latch, also shouldn't happen
            endcase
        end
        2'b10: begin // Word
            memory_mask = 4'b1111; // Always all bytes
        end
        default: memory_mask = 4'b0000;// Shouldn't happen anyways, just in case
    endcase
    end

    // Masking + Sign Extension for load instructions, (i_dmem_rdata)
    // Funct3 determines signed or not, 0 = signed, 1 = unsigned

    // Determine the byte / half word to use, so that we can grab the MSB from that byte / half word
    // To sign / zero extend. Technically, one might be invalid, but we should just check that every time 
    // we use it to make sure it is valid (check funct funct3[1:0] for byte / half word, should work)
    reg [7:0] byte_data;
    always @(*) begin
        byte_data = 8'h00; // Default to avoid latches
        case(alu_result_to_memory[1:0])
            2'b00: byte_data = i_dmem_rdata[7:0]; 
            2'b01: byte_data = i_dmem_rdata[15:8]; 
            2'b10: byte_data = i_dmem_rdata[23:16]; 
            2'b11: byte_data = i_dmem_rdata[31:24]; 
            default: byte_data = 8'h00; // For gradescope compiler
        endcase
    end

    reg [15:0] half_word_data;
    always @(*) begin
        half_word_data = 16'h0000; // Default to avoid latches
        case(alu_result_to_memory[1:0])
            2'b00: half_word_data = i_dmem_rdata[15:0]; 
            2'b10: half_word_data = i_dmem_rdata[31:16]; 
            default: half_word_data = 16'h0000; // Shouldn't happen, but avoid latch
    endcase
    end

    wire sign_bit = (inst_to_memory[14] == 1'b0) ? // Funct3[2] = 0 is signed, 1 is unsigned.
    (inst_to_memory[13:12] == 2'b00) ? byte_data[7] : // Byte, so copy the sign bit
    (inst_to_memory[13:12] == 2'b01) ? half_word_data[15] : // Half word, so copy the sign bit
    1'b0 : 1'b0; // Unsigned, zero extend it

    reg [31:0] data;
    always @(*) begin
        data = 32'h0; // Default to avoid latches
        case(inst_to_memory[13:12])
            2'b00: begin // Byte
                case(alu_result_to_memory[1:0])
                    2'b00: data = {{24{sign_bit}}, byte_data};
                    2'b01: data = {{24{sign_bit}}, byte_data}; 
                    2'b10: data = {{24{sign_bit}}, byte_data}; 
                    2'b11: data = {{24{sign_bit}}, byte_data}; 
                    default: data = 32'h0; // For gradescope compiler
                endcase
            end
            2'b01: begin // Half word
                case(alu_result_to_memory[1:0])
                    2'b00: data = {{16{sign_bit}}, half_word_data}; 
                    2'b10: data = {{16{sign_bit}}, half_word_data}; 
                    default: data = 32'h0; // Shouldn't happen
                endcase
            end
            2'b10: begin // Word, nothing to extend
                data = i_dmem_rdata;
            end 
            default: begin 
                data = 32'h0; // Shouldn't happen
            end
        endcase
    end


    // Basically same logic as load for store instructions. Use funct3 to determine byte / half word, and alu result to determine what to store
    reg [31:0] write_data;
    always @(*) begin
        write_data = 32'h0; // Default to avoid latches
        case(inst_to_memory[13:12])
            2'b00: begin // Byte
                case(alu_result_to_memory[1:0])
                    2'b00: write_data = rs2_rdata_to_memory; // Don't fill in upper bits, just keep it as is (failed gradescope before in proj 3)
                    2'b01: write_data = {rs2_rdata_to_memory[23:0], 8'b0}; 
                    2'b10: write_data = {rs2_rdata_to_memory[15:0], 16'b0}; 
                    2'b11: write_data = {rs2_rdata_to_memory[7:0], 24'b0}; 
                    default: write_data = 32'h0; // For gradescope compiler
                endcase
            end
            2'b01: begin // Half word
                case(alu_result_to_memory[1:0])
                    2'b00: write_data = rs2_rdata_to_memory;
                    2'b10: write_data = {rs2_rdata_to_memory[15:0], 16'b0}; 
                    default: write_data = 32'h0; 
                endcase
            end
            2'b10: begin // Word
                write_data = rs2_rdata_to_memory; // Just write the whole word
            end
            default: write_data = 32'h0; // Shouldn't happen
        endcase
    end
    
    // Data memory signals
    assign o_dmem_addr = {alu_result_to_memory[31:2], 2'b00};
    assign o_dmem_wdata = write_data;
    assign o_dmem_ren = i_mem_read_to_memory;
    assign o_dmem_wen = i_mem_write_to_memory;
    assign o_dmem_mask = memory_mask;



    // Memory to writeback registers
    // PC
    reg [31:0] pc_to_writeback;
    reg [31:0] pc_next_to_writeback;
    always @(posedge i_clk) begin 
        if (i_rst) begin
            pc_to_writeback <= 32'b0;
            pc_next_to_writeback <= 32'b0;
        end else begin
            pc_to_writeback <= pc_to_memory;
            pc_next_to_writeback <= pc_next_to_memory;
        end
    end

    // Mux and signals for writeback
    reg [31:0] alu_result_to_writeback;
    reg [1:0] select_c_to_writeback;
    reg [31:0] data_to_writeback; // Load data
    reg [31:0] immediate_to_writeback;
    
    always @(posedge i_clk) begin 
        if (i_rst) begin
            i_reg_write_to_writeback <= 1'b0;
            alu_result_to_writeback <= 32'b0;
            select_c_to_writeback <= 2'b0;
            data_to_writeback <= 32'b0;
            immediate_to_writeback <= 32'b0;
        end else begin
            i_reg_write_to_writeback <= i_reg_write_to_memory;
            alu_result_to_writeback <= alu_result_to_memory;
            select_c_to_writeback <= select_c_to_memory;
            data_to_writeback <= data;
            immediate_to_writeback <= immediate_to_memory;
        end
    end

    // Data memory outputs (Only valid in memory stage), need for retire as well
    reg [31:0] o_dmem_rdata_to_writeback;
    reg [31:0] o_dmem_addr_to_writeback;
    reg [3:0] o_dmem_mask_to_writeback;
    reg [31:0] o_dmem_wdata_to_writeback;
    reg o_dmem_ren_to_writeback;
    reg o_dmem_wen_to_writeback;

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_dmem_rdata_to_writeback <= 32'b0;
            o_dmem_addr_to_writeback <= 32'b0;
            o_dmem_mask_to_writeback <= 4'b0;
            o_dmem_wdata_to_writeback <= 32'b0;
            o_dmem_ren_to_writeback <= 1'b0;
            o_dmem_wen_to_writeback <= 1'b0;
        end else begin
            o_dmem_rdata_to_writeback <= i_dmem_rdata;
            o_dmem_addr_to_writeback <= o_dmem_addr;
            o_dmem_mask_to_writeback <= o_dmem_mask;
            o_dmem_wdata_to_writeback <= o_dmem_wdata;
            o_dmem_ren_to_writeback <= o_dmem_ren;
            o_dmem_wen_to_writeback <= o_dmem_wen;
        end
    end

    // Trap / retire
    reg i_trap_to_writeback;
    reg i_halt_to_writeback;
    reg [4:0] rs1_to_writeback; // Retire
    reg [4:0] rs2_to_writeback; // Retire
    reg [31:0] inst_to_writeback; // Retire
    reg [31:0] rs1_rdata_to_writeback; // Retire as well for data
    reg [31:0] rs2_rdata_to_writeback; // Retire as well for data
    reg stall_hazard_to_writeback;

    always @(posedge i_clk) begin
        if (i_rst) begin
            i_trap_to_writeback <= 1'b0;
            i_halt_to_writeback <= 1'b0;
            rs1_to_writeback <= 5'b0;
            rs2_to_writeback <= 5'b0;
            inst_to_writeback <= 32'b0;
            rd_to_writeback <= 5'b0;
            rs1_rdata_to_writeback <= 32'b0;
            rs2_rdata_to_writeback <= 32'b0;
            stall_hazard_to_writeback <= 1'b1; // Treat the post-reset pipeline as holding a bubble
        end else begin
            i_trap_to_writeback <= i_trap_to_memory;
            i_halt_to_writeback <= i_halt_to_memory;
            rs1_to_writeback <= rs1_to_memory;
            rs2_to_writeback <= rs2_to_memory;
            inst_to_writeback <= inst_to_memory;
            rd_to_writeback <= rd_to_memory;
            rs1_rdata_to_writeback <= rs1_rdata_to_memory;
            rs2_rdata_to_writeback <= rs2_rdata_to_memory;
            stall_hazard_to_writeback <= stall_hazard_to_memory;
        end
    end


    // Writeback
    // RF write back logic and rd_wdata (Writeback data)
    // Data based on select c mux
    assign rd_wdata = (select_c_to_writeback == 2'b00) ? alu_result_to_writeback : 
    (select_c_to_writeback == 2'b01) ? data_to_writeback : 
    (select_c_to_writeback == 2'b10) ? pc_to_writeback + 4 : 
    immediate_to_writeback;

    // All of the retire signals
    assign o_retire_valid = !stall_hazard_to_writeback; // If we are not stalling, then valid, else invalid
    assign o_retire_inst = inst_to_writeback;
    assign o_retire_trap = i_trap_to_writeback;
    assign o_retire_halt = i_halt_to_writeback;

    // Register retires
    assign o_retire_rs1_raddr = rs1_to_writeback;
    assign o_retire_rs2_raddr = rs2_to_writeback;
    assign o_retire_rs1_rdata = rs1_rdata_to_writeback;
    assign o_retire_rs2_rdata = rs2_rdata_to_writeback;
    assign o_retire_rd_waddr = i_reg_write_to_writeback ? rd_to_writeback : 5'b0; // When not writing must be empty
    assign o_retire_rd_wdata = rd_wdata;

    // Data memory retires
    assign o_retire_dmem_addr = o_dmem_addr_to_writeback;
    assign o_retire_dmem_mask = o_dmem_mask_to_writeback;
    assign o_retire_dmem_wen = o_dmem_wen_to_writeback;
    assign o_retire_dmem_ren = o_dmem_ren_to_writeback;
    assign o_retire_dmem_rdata = o_dmem_rdata_to_writeback;
    assign o_retire_dmem_wdata = o_dmem_wdata_to_writeback;

    // PC
    assign o_retire_pc = pc_to_writeback;
    assign o_retire_next_pc = pc_next_to_writeback;




endmodule

`default_nettype wire
