
module icache
#(
    parameter ICACHE_ADDR_W  = 32,
    parameter ICACHE_NUM_LINES = 256,
    // in bytes
    parameter ICACHE_LINE_W = 64,
    parameter ICACHE_NUM_WAYS = 2,

    parameter C_AXI_ID_WIDTH           = 10,
    parameter C_AXI_ADDR_WIDTH         = 32, 
    parameter C_AXI_DATA_WIDTH         = 512,

    parameter ADDR_WIDTH               = 32
)
(
    input                   clk,
    input                   rst,

    // Program counter
    input  [ADDR_WIDTH-1:0] req_pc,
    input                   req_rd,

    // Hit line
    output  reg                       req_accept,

    output                            req_data_valid,
    output      [ICACHE_LINE_W*8-1:0] req_data,


    // AXI read address channel signals
    input                                  axi_arready,     // Read address ready
    output [C_AXI_ID_WIDTH-1:0]            axi_arid,        // Read ID
    output [C_AXI_ADDR_WIDTH-1:0]          axi_araddr,      // Read address
    output [7:0]                           axi_arlen,       // Read Burst Length
    output [2:0]                           axi_arsize,      // Read Burst size
    output [1:0]                           axi_arburst,     // Read Burst type
    output                                 axi_arlock,      // Read lock type
    output [3:0]                           axi_arcache,     // Read Cache type
    output [2:0]                           axi_arprot,      // Read Protection type
    output                                 axi_arvalid,     // Read address valid 
    // AXI read data channel signals   
    input  [C_AXI_ID_WIDTH-1:0]            axi_rid,         // Response ID
    input  [1:0]                           axi_rresp,       // Read response
    input                                  axi_rvalid,      // Read reponse valid
    input  [C_AXI_DATA_WIDTH-1:0]          axi_rdata,       // Read data
    input                                  axi_rlast,       // Read last
    output                                 axi_rready       // Read Response ready
);

    localparam WORD_ADDR_W = $clog2(ICACHE_LINE_W);
    localparam SET_ADDR_W  = $clog2(ICACHE_NUM_LINES);
    localparam TAG_ADDR_W  = ICACHE_ADDR_W - SET_ADDR_W - WORD_ADDR_W;

    /*
     * ------------- Parse incoming PC -------------
     */
    wire [WORD_ADDR_W-1:0] req_line_word;
    wire [SET_ADDR_W-1:0]  req_line;
    wire [TAG_ADDR_W-1:0]  req_tag;

    reg  [ADDR_WIDTH-1:0] lookup_addr_r;

    assign {req_tag, req_line, req_line_word} = lookup_addr_r;


    /*
     * ------------- AXI Request Generator -------------
     */
    assign axi_rready = 1;
    assign axi_arburst = 'b1;
    assign axi_arsize = 'b1;
    assign axi_arprot = 'b0;
    assign axi_arid = 'b1;
    assign axi_arlen = 'b0;
    // Start at cache line so set last bits to zero
    assign axi_araddr[WORD_ADDR_W-1:0] = 'b0;
    assign axi_araddr[C_AXI_ADDR_WIDTH-1:WORD_ADDR_W] = {req_tag, req_line};

    reg axi_arvalid_r;
    assign axi_arvalid = axi_arvalid_r;


    /*
     * ------------- State Machine -------------
     */

    localparam STATE_BITS   =   3;
    localparam STATE_START  = 'd1;
    localparam STATE_FLUSH  = 'd2;
    localparam STATE_LOOKUP = 'd3;
    localparam STATE_REFILL = 'd4;

    reg [STATE_BITS-1:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_START;
            lookup_addr_r <= 'b0;
        end else begin
            case (state)
                STATE_START: begin
                    req_accept <= 1'b0;
                    axi_arvalid_r <= 1'b0;

                    if (req_rd) begin
                        state <= STATE_LOOKUP;

                        lookup_addr_r <= req_pc;

                        req_accept <= 1'b1;
                    end
                end

                STATE_LOOKUP: begin
                    axi_arvalid_r <= 1'b0;
                    req_accept <= 1'b0;

                    if (tag_hit[0] || tag_hit[1]) begin
                        state <= STATE_START;
                    end else begin

                        axi_arvalid_r <= 1'b1;

                        state <= STATE_REFILL;
                    end
                end

                STATE_REFILL: begin
                    axi_arvalid_r <= 1'b1;
                    req_accept <= 1'b0;

                    if (axi_rvalid) begin
                        axi_arvalid_r <= 1'b0;
                        state <= STATE_LOOKUP;
                    end
                end
                default: begin
                    state <= STATE_START;
                end
            endcase
        end
    end

    // BRAM tag and data enables
    always @(posedge clk) begin
        if (rst) begin
            tag_wen <= 0;
        end else begin
            tag_wen <= 0;
            if (state == STATE_REFILL && axi_rvalid) begin
                tag_wen <= 1;
            end
        end
    end

    wire [ICACHE_NUM_WAYS-1:0] lru;

    genvar i;
    // TAG replacement strategy
    generate
        for (i = 0; i < ICACHE_NUM_WAYS; i=i+1) begin
            assign tag_wlru[i] = tag_lru[i] + 1;
            
            // valid + lru + tag
            assign tag_wdata[i] = tag_wlru[i] == 0 ? {1'b1, lru[i], req_tag} : {tag_valid[i], lru[i], tag_data[i]};

        end
    endgenerate 

    // DATA replacement strategy
    generate
        for (i = 0; i < ICACHE_NUM_WAYS; i=i+1) begin
            assign data_wway[i] = lru[i] == 0 ? axi_rdata : data_way[i];
        end
    endgenerate 

    /*
     * ------------- Tag logic -------------
     */
    // (Width of tag length + (log2(NUM_WAYS) for LRU)) * NUM_WAYS + (valid)
    localparam TAG_ENTRY_WIDTH = TAG_ADDR_W + $clog2(ICACHE_NUM_WAYS) + 1;
    localparam TAG_RAM_WIDTH = TAG_ENTRY_WIDTH * ICACHE_NUM_WAYS;

    wire [TAG_RAM_WIDTH-1:0] tag_ram_data;

    wire [TAG_ENTRY_WIDTH-1:0] tag_wayx_ram_data [ICACHE_NUM_WAYS-1:0];

    `define TAG_ADDR_RANGE (TAG_ADDR_W-1):0
    `define TAG_LRU_RANGE  TAG_ENTRY_WIDTH-1:(TAG_ENTRY_WIDTH-$clog2(ICACHE_NUM_WAYS))

    wire [ICACHE_NUM_WAYS-1:0] tag_valid;
    wire [TAG_ADDR_W-1:0]              tag_data [ICACHE_NUM_WAYS-1:0];
    wire [$clog2(ICACHE_NUM_WAYS)-1:0] tag_lru  [ICACHE_NUM_WAYS-1:0];

    generate
        for (i = 0; i < ICACHE_NUM_WAYS; i=i+1) begin
            assign tag_wayx_ram_data[i] = tag_ram_data[TAG_ENTRY_WIDTH*(i+1)-1 : TAG_ENTRY_WIDTH*i];
            assign tag_data[i] = tag_wayx_ram_data[i][`TAG_ADDR_RANGE];
            assign tag_lru[i]  = tag_wayx_ram_data[i][`TAG_LRU_RANGE];
            assign tag_valid[i] = tag_wayx_ram_data[i][TAG_ENTRY_WIDTH-1];
        end
    endgenerate

    wire tag_hit [ICACHE_NUM_WAYS-1:0];
    generate
        for (i = 0; i < ICACHE_NUM_WAYS; i=i+1) begin
            assign tag_hit[i] = (req_tag == tag_data[i] && tag_valid[i]);
        end
    endgenerate

    wire [TAG_RAM_WIDTH-1:0] tag_ram_wdata;
    wire [TAG_ENTRY_WIDTH-1:0] tag_wayx_ram_wdata [ICACHE_NUM_WAYS-1:0];

    wire [TAG_ADDR_W-1:0]              tag_wdata [ICACHE_NUM_WAYS-1:0];
    wire [$clog2(ICACHE_NUM_WAYS)-1:0] tag_wlru  [ICACHE_NUM_WAYS-1:0];

    reg tag_wen;

    generate
        for (i = 0; i < ICACHE_NUM_WAYS; i=i+1) begin
            assign tag_ram_wdata[TAG_ENTRY_WIDTH*(i+1)-1:TAG_ENTRY_WIDTH*i] = tag_wayx_ram_wdata[i];
            assign tag_wayx_ram_wdata[i] = {tag_wlru[i], tag_wdata[i]};
        end
    endgenerate

    icache_ram #(
        .WIDTH(TAG_RAM_WIDTH),
        .ADDR_BITS(SET_ADDR_W+$clog2(ICACHE_NUM_WAYS))
    ) icache_tag_ram (
        .clk      (clk),
        .rst      (rst),

        .addr_r_i (req_line),
        .data_r_o (tag_ram_data),

        .addr_w_i (req_line),
        .we_w_i (tag_wen),
        .data_w_i (tag_ram_wdata)
    );


    /*
     * ------------- Data logic -------------
     */
    localparam DATA_ENTRY_WIDTH = ICACHE_LINE_W * 8;
    localparam DATA_RAM_WIDTH = DATA_ENTRY_WIDTH * ICACHE_NUM_WAYS;

    wire [DATA_RAM_WIDTH-1:0] data_ram;

    wire [DATA_ENTRY_WIDTH-1:0] data_way [ICACHE_NUM_WAYS-1:0];

    generate
        for (i = 0; i < ICACHE_NUM_WAYS; i=i+1) begin
            assign data_way[i] = data_ram[DATA_ENTRY_WIDTH*(i+1)-1:DATA_ENTRY_WIDTH*i];
        end
    endgenerate

    assign req_data = (tag_hit[0]) ? data_way[0] : data_way[1];

    assign req_data_valid = (state == STATE_LOOKUP && (tag_hit[0] || tag_hit[1]));

    wire [DATA_RAM_WIDTH-1:0] data_wram;
    wire [DATA_ENTRY_WIDTH-1:0] data_wway [ICACHE_NUM_WAYS-1:0];

    generate
        for (i = 0; i < ICACHE_NUM_WAYS; i=i+1) begin
            assign data_wram[DATA_ENTRY_WIDTH*(i+1)-1:DATA_ENTRY_WIDTH*i] = data_wway[i];
        end
    endgenerate

    icache_ram #(
        // LINE_W in bytes * NUM_WAYS
        .WIDTH(DATA_RAM_WIDTH),

        .ADDR_BITS(SET_ADDR_W + $clog2(ICACHE_NUM_WAYS))
    ) icache_data_ram (
        .clk      (clk),
        .rst      (rst),

        .addr_r_i (req_line),
        .data_r_o (data_ram),

        .addr_w_i (req_line),
        .we_w_i (tag_wen),
        .data_w_i (data_wram)
    );


endmodule