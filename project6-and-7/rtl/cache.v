`default_nettype none

module cache (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // External memory interface. See hart interface for details. This
    // interface is nearly identical to the phase 5 memory interface, with the
    // exception that the byte mask (`o_mem_mask`) has been removed. This is
    // no longer needed as the cache will only access the memory at word
    // granularity, and implement masking internally.
    input  wire        i_mem_ready,
    output wire [31:0] o_mem_addr,
    output wire        o_mem_ren,
    output wire        o_mem_wen,
    output wire [31:0] o_mem_wdata,
    input  wire [31:0] i_mem_rdata,
    input  wire        i_mem_valid,
    // Interface to CPU hart. This is nearly identical to the phase 5 hart memory
    // interface, but includes a stall signal (`o_busy`), and the input/output
    // polarities are swapped for obvious reasons.
    //
    // The CPU should use this as a stall signal for both instruction fetch
    // (IF) and memory (MEM) stages, from the instruction or data cache
    // respectively. If a memory request is made (`i_req_ren` for instruction
    // cache, or either `i_req_ren` or `i_req_wen` for data cache), this
    // should be asserted *combinationally* if the request results in a cache
    // miss.
    //
    // In case of a cache miss, the CPU must stall the respective pipeline
    // stage and deassert ren/wen on subsequent cycles, until the cache
    // deasserts `o_busy` to indicate it has serviced the cache miss. However,
    // the CPU must keep the other request lines constant. For example, the
    // CPU should not change the request address while stalling.
    output wire        o_busy,
    // 32-bit read/write address to access from the cache. This should be
    // 32-bit aligned (i.e. the two LSBs should be zero). See `i_req_mask` for
    // how to perform half-word and byte accesses to unaligned addresses.
    input  wire [31:0] i_req_addr,
    // When asserted, the cache should perform a read at the aligned address
    // specified by `i_req_addr` and return the 32-bit word at that address,
    // either immediately (i.e. combinationally) on a cache hit, or
    // synchronously on a cache miss. It is illegal to assert this and
    // `i_dmem_wen` on the same cycle.
    input  wire        i_req_ren,
    // When asserted, the cache should perform a write at the aligned address
    // specified by `i_req_addr` with the 32-bit word provided in
    // `o_req_wdata` (specified by the mask). This is necessarily synchronous,
    // but may either happen on the next clock edge (on a cache hit) or after
    // multiple cycles of latency (cache miss). As the cache is write-through
    // and write-allocate, writes must be applied to both the cache and
    // underlying memory.
    // It is illegal to assert this and `i_dmem_ren` on the same cycle.
    input  wire        i_req_wen,
    // The memory interface expects word (32 bit) aligned addresses. However,
    // the processor supports byte and half-word loads and stores at unaligned and
    // 16-bit aligned addresses, respectively. To support this, the access
    // mask specifies which bytes within the 32-bit word are actually read
    // from or written to memory.
    input  wire [ 3:0] i_req_mask,
    // The 32-bit word to write to memory, if the request is a write
    // (i_req_wen is asserted). Only the bytes corresponding to set bits in
    // the mask should be written into the cache (and to backing memory).
    input  wire [31:0] i_req_wdata,
    // THe 32-bit data word read from memory on a read request.
    output wire [31:0] o_res_rdata
);
    // These parameters are equivalent to those provided in the project
    // 6 specification. Feel free to use them, but hardcoding these numbers
    // rather than using the localparams is also permitted, as long as the
    // same values are used (and consistent with the project specification).
    //
    // 32 sets * 2 ways per set * 16 bytes per way = 1K cache
    localparam O = 4;            // 4 bit offset => 16 byte cache line
    localparam S = 5;            // 5 bit set index => 32 sets
    // ** and / are course-rules-banned (real hardware power/divide
    // operators synthesize poorly); O and S are fixed per the note above,
    // so these are equivalent shift-based constant expressions, not a
    // behavior change.
    localparam DEPTH = 1 << S;   // 32 sets
    localparam W = 2;            // 2 way set associative, NMRU
    localparam T = 32 - O - S;   // 23 bit tag
    localparam D = (1 << O) >> 2; // 16 bytes per line / 4 bytes per word = 4 words per line

    // The following memory arrays model the cache structure. As this is
    // an internal implementation detail, you are *free* to modify these
    // arrays as you please.

    // Backing memory, modeled as two separate ways.
    reg [   31:0] datas0 [DEPTH - 1:0][D - 1:0];
    reg [   31:0] datas1 [DEPTH - 1:0][D - 1:0];
    reg [T - 1:0] tags0  [DEPTH - 1:0];
    reg [T - 1:0] tags1  [DEPTH - 1:0];
    reg [1:0] valid [DEPTH - 1:0];
    reg       lru   [DEPTH - 1:0];

    // =========================== definitions/logic ===============================
    reg [2:0] current_state;
    
    // FSM states from schem: 
    // IDLE -> FSM_IDLE,
    // ALLOCATE -> (split) FSM_FILL_REQ + FSM_FILL_WAIT
    // MEM_WRITE -> FSM_WRITE_MEM + FSM_BG_WRITE
    // COMPARE_TAG -> obsolved within idle, discarded state defnition
    localparam FSM_IDLE       = 3'd0;
    localparam FSM_FILL_REQ   = 3'd1;
    localparam FSM_FILL_WAIT  = 3'd2;
    localparam FSM_WRITE_MEM  = 3'd3;
    localparam FSM_BG_WRITE   = 3'd4;

    // latch miss + WT req state
    reg [31:0] req_addr_q;
    reg [31:0] req_wdata_q;
    reg [3:0]  req_mask_q;
    reg        req_wen_q;
    reg        victim_way_q;
    
    reg [1:0] req_cnt;
    reg [1:0] resp_cnt;
    reg [31:0] fill_buffer [0:3];
    reg [31:0] wt_addr_q;
    reg [31:0] wt_data_q;

    // address decomposition
    wire [T - 1:0] req_tag   = i_req_addr[31 : O + S];
    wire [S - 1:0] req_index = i_req_addr[O + S - 1 : O];
    wire [1:0]     req_word  = i_req_addr[O - 1 : 2];

    wire [T - 1:0] lat_tag   = req_addr_q[31 : O + S];
    wire [S - 1:0] lat_index = req_addr_q[O + S - 1 : O];
    wire [1:0]     lat_word  = req_addr_q[O - 1 : 2];
    wire [31:0]    lat_line_base = {req_addr_q[31:O], {O{1'b0}}};

    // hit detection
    wire hit0 = valid[req_index][0] && (tags0[req_index] == req_tag);
    wire hit1 = valid[req_index][1] && (tags1[req_index] == req_tag);
    wire hit  = hit0 || hit1;
    wire hit_way = hit1;
    wire any_req = i_req_ren || i_req_wen;

    // byte mask expansion
    wire [31:0] req_bitmask = {
        {8{i_req_mask[3]}},
        {8{i_req_mask[2]}},
        {8{i_req_mask[1]}},
        {8{i_req_mask[0]}}
    };
    
    wire [31:0] lat_bitmask = {
        {8{req_mask_q[3]}},
        {8{req_mask_q[2]}},
        {8{req_mask_q[1]}},
        {8{req_mask_q[0]}}
    };

    // read/write hit word selection and merging
    wire [31:0] hit_cur_word = hit1 ? datas1[req_index][req_word] : datas0[req_index][req_word];
    wire [31:0] hit_merged_word = (hit_cur_word & ~req_bitmask) | (i_req_wdata & req_bitmask);

    // victim way selection for write-back
    wire sel_victim_way = !valid[req_index][0] ? 1'b0 :
                            !valid[req_index][1] ? 1'b1 :
                            ~lru[req_index];

    // busy selection:
    // idle-> if req & cache miss
    // bg_write-> previous write hit draining, if new req arrives, stall
    // all miss active states
    assign o_busy = (current_state == FSM_IDLE)     ? (any_req && !hit) :
                    (current_state == FSM_BG_WRITE) ? any_req :
                    1'b1;
    
    // read data selection
    wire [31:0] lat_read_word = victim_way_q ? datas1[lat_index][lat_word] : datas0[lat_index][lat_word];
    assign o_res_rdata = ((current_state == FSM_IDLE) && i_req_ren && hit) ? hit_cur_word : lat_read_word;

    // extern memory interface outputs
    reg [31:0] mem_addr_r;
    reg        mem_ren_r;
    reg        mem_wen_r;
    reg [31:0] mem_wdata_r;

    // combinational logic for memory interface
    always @(*) begin
        mem_addr_r  = 32'b0;
        mem_ren_r   = 1'b0;
        mem_wen_r   = 1'b0;
        mem_wdata_r = 32'b0;

        case (current_state)
            FSM_IDLE: begin
                // write-through write hit
                if (i_req_wen && hit && i_mem_ready) begin
                    mem_addr_r  = {i_req_addr[31:2], 2'b00};
                    mem_wen_r   = 1'b1;
                    mem_wdata_r = hit_merged_word;
                end
            end

            FSM_FILL_REQ: begin
                // read request to memory
                if (i_mem_ready) begin
                    mem_addr_r = lat_line_base + {28'b0, req_cnt, 2'b00};
                    mem_ren_r  = 1'b1;
                end
            end

            FSM_WRITE_MEM, FSM_BG_WRITE: begin
                // write-through write hit or write-back victim line
                if (i_mem_ready) begin
                    mem_addr_r  = wt_addr_q;
                    mem_wen_r   = 1'b1;
                    mem_wdata_r = wt_data_q;
                end
            end

            default: begin
                // default case, no memory operation
                mem_addr_r  = 32'b0;
                mem_ren_r   = 1'b0;
                mem_wen_r   = 1'b0;
                mem_wdata_r = 32'b0;
            end
        endcase
    end
    
    // assign memory interface outputs
    assign o_mem_addr  = mem_addr_r;
    assign o_mem_ren   = mem_ren_r;
    assign o_mem_wen   = mem_wen_r;
    assign o_mem_wdata = mem_wdata_r;

    // read-modify-write logic for write-allocate
    wire [31:0] alloc_orig_word   = fill_buf[lat_word];
    wire [31:0] alloc_merged_word = (alloc_orig_word & ~lat_bitmask) | (req_wdata_q & lat_bitmask);

    // loop indices for memory arrays 
    integer s_idx, w_idx;

    always @(posedge i_clk) begin
        if (i_rst) begin
            // reset all state and memory arrays
            current_state        <= FSM_IDLE;
            req_addr_q   <= 32'b0;
            req_wen_q    <= 1'b0;
            req_mask_q   <= 4'b0;
            req_wdata_q  <= 32'b0;
            victim_way_q <= 1'b0;
            req_cnt      <= 2'b0;
            resp_cnt     <= 2'b0;
            wt_addr_q    <= 32'b0;
            wt_data_q    <= 32'b0;
            for (w_idx = 0; w_idx < 4; w_idx = w_idx + 1) begin
                // reset fill buffer
                fill_buf[w_idx] <= 32'b0;
            end
            for (s_idx = 0; s_idx < DEPTH; s_idx = s_idx + 1) begin
                // reset valid bits, LRU bits, tags, and data arrays
                valid[s_idx] <= 2'b00;
                lru[s_idx]   <= 1'b0;
                tags0[s_idx] <= {T{1'b0}};
                tags1[s_idx] <= {T{1'b0}};
                for (w_idx = 0; w_idx < D; w_idx = w_idx + 1) begin
                    // reset data arrays
                    datas0[s_idx][w_idx] <= 32'b0;
                    datas1[s_idx][w_idx] <= 32'b0;
                end
            end
        end else begin
            case (current_state)
                FSM_IDLE: begin
                    // handle cache hit or miss
                    if (any_req) begin
                        // update LRU on hit, write data if write hit, or start fill on miss
                        if (hit) begin
                            lru[req_index] <= hit_way;
                            if (i_req_wen) begin
                                // write hit: update data array and possibly write-through to memory
                                if (hit_way == 1'b0) begin
                                    datas0[req_index][req_word] <= hit_merged_word;
                                end else begin
                                    datas1[req_index][req_word] <= hit_merged_word;
                                end
                                // write-through to memory if ready, otherwise queue for background write
                                if (!i_mem_ready) begin
                                    wt_addr_q <= {i_req_addr[31:2], 2'b00};
                                    wt_data_q <= hit_merged_word;
                                    current_state     <= FSM_BG_WRITE;
                                end
                            end
                        end else begin
                            // cache miss: latch request info and start fill process
                            req_addr_q   <= {i_req_addr[31:2], 2'b00};
                            req_wen_q    <= i_req_wen;
                            req_mask_q   <= i_req_mask;
                            req_wdata_q  <= i_req_wdata;
                            victim_way_q <= sel_victim_way;
                            req_cnt      <= 2'd0;
                            resp_cnt     <= 2'd0;
                            current_state        <= FSM_FILL_REQ;
                        end
                    end
                end

                FSM_FILL_REQ: begin
                    // handle memory read requests for cache fill
                    if (i_mem_valid) begin
                        fill_buf[resp_cnt] <= i_mem_rdata;
                        resp_cnt           <= resp_cnt + 2'd1;
                    end
                    // send memory read requests for each word in the cache line
                    if (i_mem_ready) begin
                        if (req_cnt == 2'd3) begin
                            current_state <= FSM_FILL_WAIT;
                        end else begin
                            req_cnt <= req_cnt + 2'd1;
                        end
                    end
                end

                FSM_FILL_WAIT: begin
                    // handle memory read responses for cache fill
                    if (i_mem_valid) begin
                        // store the received word in the fill buffer
                        fill_buf[resp_cnt] <= i_mem_rdata;
                        // increment response count
                        if (resp_cnt == 2'd3) begin
                            // all words received, update cache line and LRU
                            valid[lat_index][victim_way_q] <= 1'b1;
                            lru[lat_index]                 <= victim_way_q;
                            // update tag and data arrays for the victim way
                            if (victim_way_q == 1'b0) begin
                                tags0[lat_index]    <= lat_tag;
                                datas0[lat_index][0] <= (req_wen_q && (lat_word == 2'd0)) ? alloc_merged_word : fill_buf[0];
                                datas0[lat_index][1] <= (req_wen_q && (lat_word == 2'd1)) ? alloc_merged_word : fill_buf[1];
                                datas0[lat_index][2] <= (req_wen_q && (lat_word == 2'd2)) ? alloc_merged_word : fill_buf[2];
                                datas0[lat_index][3] <= (req_wen_q && (lat_word == 2'd3)) ? alloc_merged_word : i_mem_rdata;
                            end else begin
                                // victim_way_q == 1'b1
                                tags1[lat_index]    <= lat_tag;
                                datas1[lat_index][0] <= (req_wen_q && (lat_word == 2'd0)) ? alloc_merged_word : fill_buf[0];
                                datas1[lat_index][1] <= (req_wen_q && (lat_word == 2'd1)) ? alloc_merged_word : fill_buf[1];
                                datas1[lat_index][2] <= (req_wen_q && (lat_word == 2'd2)) ? alloc_merged_word : fill_buf[2];
                                datas1[lat_index][3] <= (req_wen_q && (lat_word == 2'd3)) ? alloc_merged_word : i_mem_rdata;
                            end
                            // write-through to memory if the original request was a write
                            if (req_wen_q) begin
                                wt_addr_q <= req_addr_q;
                                wt_data_q <= (lat_word == 2'd3) ? ((i_mem_rdata & ~lat_bitmask) | (req_wdata_q & lat_bitmask))
                                                                : alloc_merged_word;
                                current_state     <= FSM_WRITE_MEM;
                            end else begin
                                // read request completed, return to idle state
                                current_state <= FSM_IDLE;
                            end
                        end else begin
                            // more words to receive, increment response count
                            resp_cnt <= resp_cnt + 2'd1;
                        end
                    end
                end

                FSM_WRITE_MEM: begin
                    // handle write-through to memory for write-allocate
                    if (i_mem_ready) begin
                        current_state <= FSM_IDLE;
                    end
                end

                FSM_BG_WRITE: begin
                    // handle background write to memory
                    if (i_mem_ready) begin
                        current_state <= FSM_IDLE;
                    end
                end

                default: begin
                    // error prevention, even though that would NEVER happen right?????
                    current_state <= FSM_IDLE;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
