module ycbcr_classifier #(
    parameter int TOP_IGNORE_LINES = 30,
    parameter logic [7:0] DARK_Y_MIN = 8'd16,
    parameter logic [7:0] DARK_Y_MAX = 8'd110,
    parameter logic [7:0] NORMAL_Y_MIN = 8'd60,
    parameter logic [7:0] NORMAL_Y_MAX = 8'd210,
    parameter logic [7:0] BRIGHT_Y_MIN = 8'd150,
    parameter logic [7:0] DARK_CB_MIN = 8'd48,
    parameter logic [7:0] NORMAL_CB_MIN = 8'd56,
    parameter logic [7:0] BRIGHT_CB_MIN = 8'd64,
    parameter logic [7:0] DARK_CR_MIN = 8'd64,
    parameter logic [7:0] DARK_CR_MAX = 8'd164,
    parameter logic [7:0] NORMAL_CR_MIN = 8'd72,
    parameter logic [7:0] NORMAL_CR_MAX = 8'd152,
    parameter logic [7:0] BRIGHT_CR_MIN = 8'd80,
    parameter logic [7:0] BRIGHT_CR_MAX = 8'd168
)(
    input  logic [7:0] y,
    input  logic [7:0] cb,
    input  logic [7:0] cr,
    input  logic [7:0] pix_y,
    input  logic [15:0] sw,
    output logic       mask
);

    logic [7:0] cb_min_dist;
    logic [7:0] cb_max_base;
    logic [7:0] dark_cb_max;
    logic [7:0] bright_cb_max;
    logic [7:0] y_min;
    logic       in_valid_band;
    logic       dark_match;
    logic       normal_match;
    logic       bright_match;

    assign cb_min_dist = (sw[4:0] >= 5'd30) ? 8'd2 : (8'd32 - {3'b0, sw[4:0]});
    assign cb_max_base = 8'd128 - cb_min_dist;
    assign y_min = 8'd16 + {sw[14:10], 2'b00};
    assign in_valid_band = pix_y >= TOP_IGNORE_LINES;

    // Dark and strongly lit blue pixels may move closer to neutral
    // chrominance, so these profiles receive a small upper-Cb margin.
    assign dark_cb_max = (cb_max_base >= 8'd121) ?
                         8'd127 : (cb_max_base + 8'd6);
    assign bright_cb_max = (cb_max_base >= 8'd119) ?
                           8'd127 : (cb_max_base + 8'd8);

    // The luminance ranges intentionally overlap. A pixel near a boundary is
    // checked against both neighbouring Cb-Cr windows instead of being moved
    // abruptly from one profile to another.
    assign dark_match =
        (y >= DARK_Y_MIN) &&
        (y <= DARK_Y_MAX) &&
        (cb >= DARK_CB_MIN) &&
        (cb <= dark_cb_max) &&
        (cr >= DARK_CR_MIN) &&
        (cr <= DARK_CR_MAX);

    assign normal_match =
        (y >= NORMAL_Y_MIN) &&
        (y <= NORMAL_Y_MAX) &&
        (cb >= NORMAL_CB_MIN) &&
        (cb <= cb_max_base) &&
        (cr >= NORMAL_CR_MIN) &&
        (cr <= NORMAL_CR_MAX);

    assign bright_match =
        (y >= BRIGHT_Y_MIN) &&
        (cb >= BRIGHT_CB_MIN) &&
        (cb <= bright_cb_max) &&
        (cr >= BRIGHT_CR_MIN) &&
        (cr <= BRIGHT_CR_MAX);

    always_comb begin
        mask = 1'b0;
        if (in_valid_band &&
            (y >= y_min) &&
            (dark_match || normal_match || bright_match)) begin
            mask = 1'b1;
        end
    end

endmodule
