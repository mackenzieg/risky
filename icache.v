
module icache_data_ram
#(
    parameter ICACHE_ADDR_W  = 32
    parameter ICACHE_NUM_LINES = 256
    // in bytes
    parameter ICACHE_LINE_W = 64
    parameter ICACHE_NUM_WAYS = 2,
)
(
    input                   clk,
    input                   rst,

    input  [ADDR_WIDTH-1:0] req_pc,
    input                   req_rd,
);

    localparam WORD_ADDR_W = $clog2(ICACHE_LINE_W);
    localparam SET_ADDR_W  = $clog2(ICACHE_NUM_LINES);
    localparam TAG_ADDR_W  = ICACHE_ADDR_W - SET_ADDR_W - WORD_ADDR_W;

    wire [WORD_ADDR_W-1:0] req_line_word;
    wire [SET_ADDR_W-1:0]  req_line;
    wire [TAG_ADDR_W-1:0]  req_tag;

    assign {req_tag, req_line, req_line_word} = req_pc;

    localparam ICACHE_TOTAL_W = 20;

    wire [ICACHE_NUM_WAYS-1:0] tag_ram_data_i [ICACHE_TOTAL_W-1:0]
    genvar i;
    generate
        for (i = 0; i < ICACHE_NUM_WAYS; i = i + 1) begin
            icache_tag_ram icache_tag_ram_way (
                .clk    (clk),
                .rst    (rst),
                .addr_i (req_line),
                .data_i (),
                .we_i   (),

                .data_o ()
            );
        end
    endgenerate

endmodule