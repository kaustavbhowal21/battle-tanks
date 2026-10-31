`timescale 1ns / 1ps

module tb_pipeline;

////////////////////////////////////////////////////////////
// CLOCK & RESET
////////////////////////////////////////////////////////////
reg clk;
reg reset;

// 100 MHz clock
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// reset (active low in our CPU)
initial begin
    reset = 0;
    #100;
    reset = 1;
end


////////////////////////////////////////////////////////////
// PIPE <-> MEMORY SIGNALS
////////////////////////////////////////////////////////////
wire [31:0] inst_mem_read_data;
wire        inst_mem_is_valid;

wire [31:0] dmem_read_data;
wire        dmem_write_valid;
wire        dmem_read_valid;

// CPU -> memory
wire [31:0] inst_mem_address;
wire        dmem_read_ready;
wire [31:0] dmem_read_address;
wire        dmem_write_ready;
wire [31:0] dmem_write_address;
wire [31:0] dmem_write_data;
wire [3:0]  dmem_write_byte;

wire [31:0] pc_out;

assign inst_mem_is_valid = 1'b1;
assign dmem_write_valid  = 1'b1;
assign dmem_read_valid   = 1'b1;

wire exception;


////////////////////////////////////////////////////////////
// DUT : PIPELINE CPU
////////////////////////////////////////////////////////////
pipe DUT (
    .clk                (clk),
    .reset              (reset),
    .stall              (1'b0),
    .exception          (exception),
    .pc_out             (pc_out),

    .inst_mem_is_valid  (inst_mem_is_valid),
    .inst_mem_read_data (inst_mem_read_data),

    .dmem_read_data_temp(dmem_read_data),
    .dmem_write_valid   (dmem_write_valid),
    .dmem_read_valid    (dmem_read_valid),

    .inst_mem_address   (inst_mem_address),
    .dmem_read_ready    (dmem_read_ready),
    .dmem_read_address  (dmem_read_address),
    .dmem_write_ready   (dmem_write_ready),
    .dmem_write_address (dmem_write_address),
    .dmem_write_data    (dmem_write_data),
    .dmem_write_byte    (dmem_write_byte)
);


////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY  (matches instr_mem in memory.v)
////////////////////////////////////////////////////////////
instr_mem IMEM (
    .clk  (clk),
    .pc   (inst_mem_address),
    .instr(inst_mem_read_data)
);


////////////////////////////////////////////////////////////
// DATA MEMORY  (matches data_mem in memory.v)
////////////////////////////////////////////////////////////
data_mem DMEM (
    .clk  (clk),

    .re   (dmem_read_ready),
    .raddr(dmem_read_address),
    .rdata(dmem_read_data),

    .we   (dmem_write_ready),
    .waddr(dmem_write_address),
    .wdata(dmem_write_data),
    .wstrb(dmem_write_byte)
);
////////////////////////////////////////////////////////////
// TRACE : Customized Log Format & Auto-Finish
////////////////////////////////////////////////////////////
always @(posedge clk) begin
    if (reset && !DUT.stall_read) begin
        // Print time and result only when a writeback occurs
        if (DUT.wb_alu_to_reg) begin
            $display("time: %12t ,mem_to_reg = %10d ,result = %10d", 
                     $time, DUT.wb_mem_to_reg,
                     DUT.wb_mem_to_reg ? DUT.wb_read_data : DUT.wb_result);
        end
        
        // Always print the PC being fetched
        $display("next_pc = %08h", DUT.inst_fetch_pc);
    end

    // Fail immediately on an illegal-instruction / misaligned-fetch exception
    if (reset && exception) begin
        $display(">> TEST FAILED: CPU exception at PC=0x%08h", pc_out);
        $finish;
    end
end

////////////////////////////////////////////////////////////
// SIMULATION TIME (Fallback)
////////////////////////////////////////////////////////////
initial begin
    $dumpfile("tb_pipeline.vcd");
    $dumpvars(0, tb_pipeline);

    // The game firmware is an infinite loop (it never executes a final 'ret'),
    // so instead of waiting for one, run for a fixed window and require the
    // core to have executed instructions without raising an exception.
    #20000;
    if (!exception && pc_out !== 32'h0000_0000 && pc_out !== 32'hxxxx_xxxx) begin
        $display(">> TEST PASSED: pipeline executed program without exceptions (PC=0x%08h)", pc_out);
    end else begin
        $display(">> TEST FAILED: exception=%b PC=0x%08h", exception, pc_out);
    end
    $finish;
end

endmodule
