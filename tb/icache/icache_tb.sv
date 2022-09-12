`timescale 1 ps / 1 ps

module dut_tb
#(
    parameter D_W = 8,        //operand data width
    parameter D_W_ACC = 16,   //accumulator data width
    parameter N1 = 4,
    parameter N2 = 4,
    parameter M = 8
)
();

reg        clk=1'b0;
reg [1:0]  rst;

reg [31:0] req_pc;
reg        req_rd;

wire            req_accept;
wire [512-1:0]  req_data;

icache icache_dut (

    .clk                (clk),
    .rst                (rst[0]),

    .req_pc             (req_pc),
    .req_rd             (req_rd),

    .req_accept         (req_accept),
    .req_data           (req_data),

    .axi_arready        (1'b1),     
    .axi_arid,          (),
    .axi_araddr         (),      
    .axi_arlen          (),       
    .axi_arsize         (),      
    .axi_arburst        (),     
    .axi_arlock         (),      
    .axi_arcache        (),     
    .axi_arprot         (),      
    .axi_arvalid        (),     

    .axi_rid            (),         
    .axi_rresp          (),       
    .axi_rvalid         (),      
    .axi_rdata          (),       
    .axi_rlast          (),       
    .axi_rready         (),
);

`ifndef XIL_TIMING
always #1 clk = ~clk;
`else
always #5000 clk = ~clk;
`endif

initial
begin
    $timeformat(-9, 2, " ns", 20);
    rst = 2'b11;
end

always @(posedge clk) begin
    clk <= clk >> 1;
end

endmodule