`default_nettype none

// The arithmetic logic unit (ALU) is responsible for performing the core
// calculations of the processor. It takes two 32-bit operands and outputs
// a 32 bit result based on the selection operation - addition, comparison,
// shift, or logical operation. This ALU is a purely combinational block, so
// you should not attempt to add any registers or pipeline it.
module alu (
    // NOTE: Both 3'b010 and 3'b011 are used for set less than operations and
    // your implementation should output the same result for both codes. The
    // reason for this will become clear in project 3.
    //
    // Major operation selection.
    // 3'b000: addition/subtraction if `i_sub` asserted
    // 3'b001: shift left logical
    // 3'b010,
    // 3'b011: set less than/unsigned if `i_unsigned` asserted
    // 3'b100: exclusive or
    // 3'b101: shift right logical/arithmetic if `i_arith` asserted
    // 3'b110: or
    // 3'b111: and
    input  wire [ 2:0] i_opsel,
    // When asserted, addition operations should subtract instead.
    // This is only used for `i_opsel == 3'b000` (addition/subtraction).
    input  wire        i_sub,
    // When asserted, comparison operations should be treated as unsigned.
    // This is used for branch comparisons and set less than unsigned. For
    // b ranch operations, the ALU result is not used, only the comparison
    // results.
    input  wire        i_unsigned,
    // When asserted, right shifts should be treated as arithmetic instead of
    // logical. This is only used for `i_opsel == 3'b101` (shift right).
    input  wire        i_arith,
    // First 32-bit input operand.
    input  wire [31:0] i_op1,
    // Second 32-bit input operand.
    input  wire [31:0] i_op2,
    // 32-bit output result. Any carry out should be ignored.
    output wire [31:0] o_result,
    // Equality result. This is used externally to determine if a branch
    // should be taken.
    output wire        o_eq,
    // Set less than result. This is used externally to determine if a branch
    // should be taken.
    output wire        o_slt
);

    wire [4:0] shift_right = i_op2[4:0];
    // Arithmetic shift preserves sign, logical just 0's
    wire fill_bit = i_arith & i_op1[31];
    // Shift slowly, starting from LSB of shift to MSB. At most can shift 31 times, build value off previous shift.
    wire [31:0] shift_right_1 = shift_right[0] ? {fill_bit, i_op1[31:1]} : i_op1;
    wire [31:0] shift_right_2 = shift_right[1] ? {{2{fill_bit}}, shift_right_1[31:2]} : shift_right_1;
    wire [31:0] shift_right_3 = shift_right[2] ? {{4{fill_bit}}, shift_right_2[31:4]} : shift_right_2;
    wire [31:0] shift_right_4 = shift_right[3] ? {{8{fill_bit}}, shift_right_3[31:8]} : shift_right_3;
    wire [31:0] shift_right_5 = shift_right[4] ? {{16{fill_bit}}, shift_right_4[31:16]} : shift_right_4;

    wire [4:0] shift_left = i_op2[4:0];
    // Shift left is always logical, so just fill with 0's
    // Shift slowly, starting from LSB of shift to MSB. At most can shift 31 times, build value off previous shift.
    wire [31:0] shift_left_1 = shift_left[0] ? {i_op1[30:0], 1'b0} : i_op1;
    wire [31:0] shift_left_2 = shift_left[1] ? {shift_left_1[29:0], 2'b0} : shift_left_1;
    wire [31:0] shift_left_3 = shift_left[2] ? {shift_left_2[27:0], 4'b0} : shift_left_2;
    wire [31:0] shift_left_4 = shift_left[3] ? {shift_left_3[23:0], 8'b0} : shift_left_3;
    wire [31:0] shift_left_5 = shift_left[4] ? {shift_left_4[15:0], 16'b0} : shift_left_4;

    reg [31:0] temp_result;
    // Using combinational only
    always @(*) begin
        case(i_opsel)
            3'b000: begin // Add / subtract
                temp_result = i_sub ? (i_op1 - i_op2) : (i_op1 + i_op2);
            end
            3'b001: begin // Shift left logical
                temp_result = shift_left_5;
            end
            3'b010: begin // Set less than
                temp_result = {31'b0, o_slt};
            end
            3'b011: begin // Set less than
                temp_result = {31'b0, o_slt};
            end
            3'b100: begin // XOR
                temp_result = i_op1 ^ i_op2;
            end
            3'b101: begin // SRL / SRA
                temp_result = shift_right_5;
            end
            3'b110: begin // OR
                temp_result = i_op1 | i_op2;
            end
            3'b111: begin // AND
                temp_result = i_op1 & i_op2;
            end
            default: begin // Avoid a latch
                temp_result = 32'b0;
            end
        endcase
    end

    assign o_result = temp_result;
    // Same for signed and unsigned, so just compare, no need for i_unsigned
    assign o_eq = (i_op1 == i_op2);
    // Compare sign bits. If they differ, the one with 1 as sign bit is less, else just compare them if same sign bit.
    assign o_slt = (i_unsigned) ? (i_op1 < i_op2) :
                   (i_op1[31] != i_op2[31]) ? i_op1[31] : (i_op1 < i_op2);

endmodule
`default_nettype wire

