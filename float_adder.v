module float_adder(
    input               clk,
    input               rst_n,
    input               en,
    input      [31:0]   aIn,
    input      [31:0]   bIn,
    output reg          busy,
    output reg          out_vld,
    output reg [31:0]   out
);

    localparam [3:0] IDLE      = 4'd0;
    localparam [3:0] LATCH     = 4'd1;
    localparam [3:0] UNPACK    = 4'd2;
    localparam [3:0] ALIGN     = 4'd3;
    localparam [3:0] ADD       = 4'd4;
    localparam [3:0] NORMALIZE = 4'd5;
    localparam [3:0] PACK      = 4'd6;
    localparam [3:0] OUT       = 4'd7;
    localparam [3:0] DONE      = 4'd8;

    reg [3:0]  state;

    reg [31:0] reg_a;
    reg [31:0] reg_b;

    reg [7:0]  exp_a;
    reg [7:0]  exp_b;
    reg [23:0] frac_a;
    reg [23:0] frac_b;

    reg [7:0]  exp_large;
    reg [7:0]  exp_diff;
    reg [23:0] frac_large;
    reg [23:0] frac_small;
    reg [23:0] frac_small_shifted;
    reg [24:0] frac_sum;

    reg [22:0] norm_frac;
    reg [7:0]  norm_exp;
    reg [31:0] result_reg;

    reg        input_accept;
    reg        align_done;
    reg        add_done;
    reg        norm_done;
    reg        output_done;

    function [23:0] shift_right_limit_24;
        input [23:0] data_in;
        input [7:0]  shift_num;
        begin
            if (shift_num >= 8'd24) begin
                shift_right_limit_24 = 24'd0;
            end else begin
                shift_right_limit_24 = data_in >> shift_num;
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= IDLE;
            busy               <= 1'b0;
            out_vld            <= 1'b0;
            out                <= 32'd0;

            reg_a              <= 32'd0;
            reg_b              <= 32'd0;
            exp_a              <= 8'd0;
            exp_b              <= 8'd0;
            frac_a             <= 24'd0;
            frac_b             <= 24'd0;
            exp_large          <= 8'd0;
            exp_diff           <= 8'd0;
            frac_large         <= 24'd0;
            frac_small         <= 24'd0;
            frac_small_shifted <= 24'd0;
            frac_sum           <= 25'd0;
            norm_frac          <= 23'd0;
            norm_exp           <= 8'd0;
            result_reg         <= 32'd0;

            input_accept       <= 1'b0;
            align_done         <= 1'b0;
            add_done           <= 1'b0;
            norm_done          <= 1'b0;
            output_done        <= 1'b0;
        end else begin
            out_vld      <= 1'b0;
            input_accept <= 1'b0;
            align_done   <= 1'b0;
            add_done     <= 1'b0;
            norm_done    <= 1'b0;
            output_done  <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (en && !busy) begin
                        reg_a        <= aIn;
                        reg_b        <= bIn;
                        input_accept <= 1'b1;
                        busy         <= 1'b1;
                        state        <= LATCH;
                    end else begin
                        state        <= IDLE;
                    end
                end

                LATCH: begin
                    state <= UNPACK;
                end

                UNPACK: begin
                    exp_a  <= reg_a[30:23];
                    exp_b  <= reg_b[30:23];
                    frac_a <= (reg_a[30:23] != 8'd0) ? {1'b1, reg_a[22:0]} : {1'b0, reg_a[22:0]};
                    frac_b <= (reg_b[30:23] != 8'd0) ? {1'b1, reg_b[22:0]} : {1'b0, reg_b[22:0]};
                    state  <= ALIGN;
                end

                ALIGN: begin
                    if (exp_a >= exp_b) begin
                        exp_large          <= exp_a;
                        exp_diff           <= exp_a - exp_b;
                        frac_large         <= frac_a;
                        frac_small         <= frac_b;
                        frac_small_shifted <= shift_right_limit_24(frac_b, exp_a - exp_b);
                    end else begin
                        exp_large          <= exp_b;
                        exp_diff           <= exp_b - exp_a;
                        frac_large         <= frac_b;
                        frac_small         <= frac_a;
                        frac_small_shifted <= shift_right_limit_24(frac_a, exp_b - exp_a);
                    end
                    align_done <= 1'b1;
                    state      <= ADD;
                end

                ADD: begin
                    frac_sum <= {1'b0, frac_large} + {1'b0, frac_small_shifted};
                    add_done <= 1'b1;
                    state    <= NORMALIZE;
                end

                NORMALIZE: begin
                    if (frac_sum[24]) begin
                        if (exp_large >= 8'hFE) begin
                            norm_exp  <= 8'hFF;
                            norm_frac <= 23'd0;
                        end else begin
                            norm_exp  <= exp_large + 8'd1;
                            norm_frac <= frac_sum[23:1];
                        end
                    end else begin
                        norm_exp  <= exp_large;
                        norm_frac <= frac_sum[22:0];
                    end
                    norm_done <= 1'b1;
                    state     <= PACK;
                end

                PACK: begin
                    result_reg <= {1'b0, norm_exp, norm_frac};
                    state      <= OUT;
                end

                OUT: begin
                    out        <= result_reg;
                    out_vld    <= 1'b1;
                    output_done<= 1'b1;
                    state      <= DONE;
                end

                DONE: begin
                    busy  <= 1'b0;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
