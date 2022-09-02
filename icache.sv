
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
    output  reg                       req_valid,
    output  reg [ICACHE_LINE_W*8-1:0] req_data,


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

    reg [WORD_ADDR_W-1:0] req_line_word_r;
    reg [SET_ADDR_W-1:0]  req_line_r;
    reg [TAG_ADDR_W-1:0]  req_tag_r;

    reg                   req_rd_r;

    assign {req_tag, req_line, req_line_word} = req_pc;

    always @(posedge clk)
    begin
        req_line_word_r <= req_line_word;
        req_line_r <= req_line;
        req_tag_r <= req_tag;

        if (rst)
            req_rd_r <= 0;
        else
            req_rd_r <= req_rd;
    end


    /*
     * ------------- Tag logic -------------
     */
    // (Width of tag length + (log2(NUM_WAYS) for LRU)) * NUM_WAYS
    localparam TAG_ENTRY_WIDTH = TAG_ADDR_W + $clog2(ICACHE_NUM_WAYS);
    localparam TAG_RAM_WIDTH = TAG_ENTRY_WIDTH * ICACHE_NUM_WAYS;

    wire [TAG_RAM_WIDTH-1:0] tag_ram_data;

    wire [TAG_ENTRY_WIDTH-1:0] tag_wayx_ram_data [$clog2(ICACHE_NUM_WAYS)-1:0];

    `define TAG_ADDR_RANGE TAG_ADDR_W-1:0;
    `define TAG_LRU_RANGE  TAG_ENTRY_WIDTH-1:TAG_ENTRY_WIDTH-$clog2(ICACHE_NUM_WAYS)

    wire [TAG_ADDR_RANGE] tag_data  [$clog2(ICACHE_NUM_WAYS)-1:0];
    wire [TAG_LRU_RANGE]  tag_lru   [$clog2(ICACHE_NUM_WAYS)-1:0];

    genvar i;
    generate
        for (i = 0; i < $clog2(ICACHE_NUM_WAYS); i=i+1) begin
            assign tag_wayx_ram_data[i] = tag_ram_data[TAG_ENTRY_WIDTH*(i+1)-1 : TAG_ENTRY_WIDTH*i];
            assign tag_data[i] = tag_wayx_ram_data[TAG_ADDR_RANGE];
            assign tag_lru[i]  = tag_wayx_ram_data[TAG_LRU_RANGE];
        end
    endgenerate

    always @(posedge clk)
    begin
        if (req_rd_r) begin
            if (req_tag_r == tag_data[0]) begin
                // Hit way 0
                req_valid <= 1;
                req_data <= data_way[0];
            end else if (req_tag_r == tag_data[1]) begin
                // Hit way 1
                req_valid <= 1;
                req_data <= data_way[1];
            end else begin
                // Missed cache, need to request here
                req_data <= 0;
            end
        end

        req_valid <= 0;
        req_data <= 0;
    end

    icache_ram #(
        .WIDTH(TAG_RAM_WIDTH),
        .ADDR_BITS(TAG_ADDR_W)
    ) icache_tag_ram (
        .clk      (clk),
        .rst      (rst),

        .addr_r_i (req_line),
        .data_r_o (tag_ram_data),

        .addr_w_i (0),
        .we_w_i (0),
        .data_w_i (0)
    );


    /*
     * ------------- Data logic -------------
     */
    localparam DATA_RAM_WIDTH = ICACHE_LINE_W * 8 * ICACHE_NUM_WAYS;

    wire [DATA_RAM_WIDTH-1:0] data_ram;

    wire [ICACHE_LINE_W * 8-1:0] data_way  [$clog2(ICACHE_NUM_WAYS)];

    generate
        for (i = 0; i < $clog2(ICACHE_NUM_WAYS); i=i+1) begin
            assign data_way[i] = data_ram[DATA_RAM_WIDTH*i-1:DATA_RAM_WIDTH*i];
        end
    endgenerate

    icache_ram #(
        // LINE_W in bytes * NUM_WAYS
        .WIDTH(DATA_RAM_WIDTH),

        .ADDR_BITS($clog2(ICACHE_NUM_WAYS))
    ) icache_data_ram (
        .clk      (clk),
        .rst      (rst),

        .addr_r_i (req_line),
        .data_r_o (data_ram),

        .addr_w_i (0),
        .we_w_i (0),
        .data_w_i (0)
    );

endmodule