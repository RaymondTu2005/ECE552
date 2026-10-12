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
    reg i_trap; 

    // ALU variables
    wire [31:0] alu_op1;
    wire [31:0] alu_op2;
    wire [31:0] alu_result;
    wire        alu_eq;
    wire        alu_slt;

    // Branch
    wire branch_taken;

    // PC
    wire [31:0] pc_next;

    // Data 
    reg [31:0] data;
    reg [31:0] write_data;


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
                i_halt = (i_imem_rdata[31:20] == 12'b000000000001); // ebreak instruction
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
            pc <= pc_next; 
        end
   
    end
        assign o_imem_raddr = pc;
        assign o_retire_pc = pc;


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
    assign rd_wdata = (select_c == 2'b00) ? alu_result : (select_c == 2'b01) ? data : (select_c == 2'b10) ? pc + 4 : immediate;


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
    assign o_retire_next_pc = pc_next; 


    // Data Memory Signals, (mask is below)
    assign o_dmem_addr = {alu_result[31:2], 2'b00}; // Lower two bits are for byte / half word alignment, so ignore it.
    assign o_dmem_wdata = write_data; // Write data is determined by the store instruction and ALU result
    assign o_dmem_ren = i_mem_read;
    assign o_dmem_wen = i_mem_write;
    


    // Branch logic, using outputs from ALU (Equal and SLT).
    // Determines if PC should be updated to a branch or not based on operation and ALU flags
    assign branch_taken = i_branch && (
        (funct3 == 3'b000) ? alu_eq : 
        (funct3 == 3'b001) ? !alu_eq :
        (funct3 == 3'b100) ? alu_slt :
        (funct3 == 3'b101) ? !alu_slt :
        (funct3 == 3'b110) ? alu_slt :
        (funct3 == 3'b111) ? !alu_slt : 1'b0);

    // Jalr logic
    wire [31:0] jalr_target = (rs1_rdata + immediate) & 32'hfffffffe; // Clear LSB to make it half-word aligned
  
    // If branch taken, update PC accordingy, or check for jump (jal / jalr)
    assign pc_next = (branch_taken || i_jal) ? (pc + immediate) : (i_jalr) ? jalr_target : pc + 4;


    // Masking logic to word align o_dmem_addr
    // Funct3[1:0] determines size of access, with 00 = byte, 01 = half, 10 = word
    // Also, ALU result is used for which half word or byte to access
    reg [3:0] memory_mask;
    always @(*) begin
        memory_mask = 4'b0000; // Default to no access
    case(funct3[1:0])
        2'b00: begin // Byte
            case(alu_result[1:0])
                2'b00: memory_mask = 4'b0001; 
                2'b01: memory_mask = 4'b0010; 
                2'b10: memory_mask = 4'b0100; 
                2'b11: memory_mask = 4'b1000; 
                default: memory_mask = 4'b0000; // For gradescope compiler
            endcase
        end
        2'b01: begin // Half word
            case(alu_result[1:0])
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
    // Assign the memory mask to the output
    assign o_dmem_mask = memory_mask;


    // Masking for load instructions so that i_dmem_rdata is valid
    // Basically same as above but some instructions have to be sign extended / zero extended
    // funct3[2] = 0 is signed, 1 is unsigned

    // Determine the byte / half word to use, so that we can grab the MSB from that byte / half word
    // To sign / zero extend. Technically, one might be invalid, but we should just check that every time 
    // we use it to make sure it is valid (check funct funct3[1:0] for byte / half word, should work)
    reg [7:0] byte_data;
    always @(*) begin
        byte_data = 8'h00; // Default to avoid latches
        case(alu_result[1:0])
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
        case(alu_result[1:0])
            2'b00: half_word_data = i_dmem_rdata[15:0]; 
            2'b10: half_word_data = i_dmem_rdata[31:16]; 
            default: half_word_data = 16'h0000; // Shouldn't happen, but avoid latch
    endcase
    end

    wire sign_bit = (funct3[2] == 1'b0) ? 
    (funct3[1:0] == 2'b00) ? byte_data[7] : // Byte, so copy the sign bit
    (funct3[1:0] == 2'b01) ? half_word_data[15] : // Half word, so copy the sign bit
    1'b0 : 1'b0; // Unsigned, zero extend it

    always @(*) begin
        data = 32'h0; // Default to avoid latches
        case(funct3[1:0])
            2'b00: begin // Byte
                case(alu_result[1:0])
                    2'b00: data = {{24{sign_bit}}, byte_data};
                    2'b01: data = {{24{sign_bit}}, byte_data}; 
                    2'b10: data = {{24{sign_bit}}, byte_data}; 
                    2'b11: data = {{24{sign_bit}}, byte_data}; 
                    default: data = 32'h0; // For gradescope compiler
                endcase
            end
            2'b01: begin // Half word
                case(alu_result[1:0])
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

    // Basically same  of load for store instructions. Use funct3 to determine byte / half word, and alu result to determine what to store
    always @(*) begin
        write_data = 32'h0; // Default to avoid latches
        case(funct3[1:0])
            2'b00: begin // Byte
                case(alu_result[1:0])
                    2'b00: write_data = rs2_rdata; // Don't fill in upper bits, just keep it as is (failed gradescope before)
                    2'b01: write_data = {rs2_rdata[23:0], 8'b0}; 
                    2'b10: write_data = {rs2_rdata[15:0], 16'b0}; 
                    2'b11: write_data = {rs2_rdata[7:0], 24'b0}; 
                    default: write_data = 32'h0; // For gradescope compiler
                endcase
            end
            2'b01: begin // Half word
                case(alu_result[1:0])
                    2'b00: write_data = rs2_rdata;
                    2'b10: write_data = {rs2_rdata[15:0], 16'b0}; 
                    default: write_data = 32'h0; 
                endcase
            end
            2'b10: begin // Word
                write_data = rs2_rdata; // Just write the whole word  
            end
            default: write_data = 32'h0; // Shouldn't happen
        endcase

    end



endmodule

`default_nettype wire
