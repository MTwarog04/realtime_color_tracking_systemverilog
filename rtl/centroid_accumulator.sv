`timescale 1ns / 1ps


module centroid_accumulator #(
    parameter int IMG_W = 320,
    parameter int IMG_H = 240,
    parameter int TOP_IGNORE_LINES = 30,
    parameter int ASPECT_NUM = 2,
    parameter int ASPECT_DEN = 3,
    parameter int MIN_FILL_PERCENT = 40,
    parameter int MAX_FILL_PERCENT = 95,
    parameter int SMALL_OBJECT_LIMIT = 16,
    parameter int SMALL_ASPECT_NUM = 1,
    parameter int SMALL_ASPECT_DEN = 2,
    parameter int SMALL_MIN_FILL_PERCENT = 20,
    parameter int SMALL_MAX_FILL_PERCENT = 100,
    parameter int MIN_DIAMETER = 8,
    parameter int MAX_BLOBS = 16,
    parameter int CONNECT_GAP = 3,
    parameter int ROUND_FILL_PERCENT = 79,
    parameter int TRACK_MAX_DISTANCE = 80
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        pix_valid,
    input  logic        frame_start,
    input  logic        frame_end,
    input  logic        mask,
    input  logic [8:0]  pix_x,
    input  logic [7:0]  pix_y,
    output logic [8:0]  centroid_x,
    output logic [7:0]  centroid_y,
    output logic        centroid_valid,
    output logic [16:0] mask_pixel_count
);

    localparam int SUM_X_W = $clog2(IMG_W * IMG_H * (IMG_W - 1)) + 1;
    localparam int SUM_Y_W = $clog2(IMG_W * IMG_H * (IMG_H - 1)) + 1;
    localparam int CNT_W = $clog2(IMG_W * IMG_H + 1);
    localparam int BLOB_IDX_W = (MAX_BLOBS <= 1) ? 1 : $clog2(MAX_BLOBS);

    logic [MAX_BLOBS-1:0] blob_valid;
    logic [SUM_X_W-1:0] blob_sum_x [0:MAX_BLOBS-1];
    logic [SUM_Y_W-1:0] blob_sum_y [0:MAX_BLOBS-1];
    logic [CNT_W-1:0]   blob_pixel_count [0:MAX_BLOBS-1];
    logic [8:0]          blob_min_x [0:MAX_BLOBS-1];
    logic [8:0]          blob_max_x [0:MAX_BLOBS-1];
    logic [7:0]          blob_min_y [0:MAX_BLOBS-1];
    logic [7:0]          blob_max_y [0:MAX_BLOBS-1];

    logic [MAX_BLOBS-1:0] match_vector;
    logic                  match_found;
    logic                  slot_found;
    logic [BLOB_IDX_W-1:0] match_index;
    logic [BLOB_IDX_W-1:0] slot_index;

    logic [SUM_X_W-1:0] merged_sum_x;
    logic [SUM_Y_W-1:0] merged_sum_y;
    logic [CNT_W-1:0]   merged_pixel_count;
    logic [8:0]          merged_min_x;
    logic [8:0]          merged_max_x;
    logic [7:0]          merged_min_y;
    logic [7:0]          merged_max_y;

    logic                  evaluation_active;
    logic [BLOB_IDX_W-1:0] evaluation_index;
    logic                  best_found;
    logic [BLOB_IDX_W-1:0] best_index;
    logic                  best_near_previous;
    logic [1:0]            best_round_rank;
    logic [1:0]            best_aspect_rank;
    logic [10:0]           best_distance;
    logic [CNT_W-1:0]      best_pixel_count;

    logic [9:0]  eval_width;
    logic [8:0]  eval_height;
    logic [31:0] eval_area;
    logic        eval_small;
    logic [31:0] eval_aspect_num;
    logic [31:0] eval_aspect_den;
    logic [31:0] eval_min_fill_percent;
    logic [31:0] eval_max_fill_percent;
    logic [31:0] eval_pixels_x100;
    logic [31:0] eval_min_fill;
    logic [31:0] eval_max_fill;
    logic [31:0] eval_target_fill;
    logic [31:0] eval_fill_error;
    logic [9:0]  eval_aspect_error;
    logic [9:0]  eval_max_dimension;
    logic [9:0]  eval_center_x;
    logic [8:0]  eval_center_y;
    logic [10:0] eval_distance;
    logic        eval_aspect_valid;
    logic        eval_fill_valid;
    logic        eval_size_valid;
    logic        eval_shape_valid;
    logic        eval_near_previous;
    logic [1:0]  eval_round_rank;
    logic [1:0]  eval_aspect_rank;
    logic        eval_candidate_better;
    logic        eval_winner_found;
    logic [BLOB_IDX_W-1:0] eval_winner_index;

    logic [CNT_W-1:0] locked_pixel_count;
    logic in_valid_band;

    assign in_valid_band = pix_y >= TOP_IGNORE_LINES;

    // A masked pixel belongs to a blob when it is close to that blob's current
    // bounding box. CONNECT_GAP joins small holes caused by the colour mask.
    always_comb begin : find_blob_for_pixel
        match_vector = '0;
        match_found = 1'b0;
        match_index = '0;
        slot_found = 1'b0;
        slot_index = '0;

        for (integer i = 0; i < MAX_BLOBS; i = i + 1) begin
            if (blob_valid[i] &&
                (({1'b0, pix_x} + CONNECT_GAP) >= {1'b0, blob_min_x[i]}) &&
                ({1'b0, pix_x} <= ({1'b0, blob_max_x[i]} + CONNECT_GAP)) &&
                (({1'b0, pix_y} + CONNECT_GAP) >= {1'b0, blob_min_y[i]}) &&
                ({1'b0, pix_y} <= ({1'b0, blob_max_y[i]} + CONNECT_GAP))) begin
                match_vector[i] = 1'b1;
                if (!match_found) begin
                    match_found = 1'b1;
                    match_index = i;
                end
            end

            // A blob that is already above the scan and is too short can never
            // pass MIN_DIAMETER, so its slot may safely be reused.
            if (!slot_found &&
                (!blob_valid[i] ||
                 (({1'b0, pix_y} > ({1'b0, blob_max_y[i]} + CONNECT_GAP)) &&
                  (({1'b0, blob_max_y[i]} - {1'b0, blob_min_y[i]} + 9'd1) <
                   MIN_DIAMETER)))) begin
                slot_found = 1'b1;
                slot_index = i;
            end
        end
    end

    // If a pixel bridges two fragments, combine both candidates instead of
    // allowing one physical object to remain split into multiple blobs.
    always_comb begin : merge_matching_blobs
        merged_sum_x = pix_x;
        merged_sum_y = pix_y;
        merged_pixel_count = {{(CNT_W-1){1'b0}}, 1'b1};
        merged_min_x = pix_x;
        merged_max_x = pix_x;
        merged_min_y = pix_y;
        merged_max_y = pix_y;

        for (integer i = 0; i < MAX_BLOBS; i = i + 1) begin
            if (match_vector[i]) begin
                merged_sum_x = merged_sum_x + blob_sum_x[i];
                merged_sum_y = merged_sum_y + blob_sum_y[i];
                merged_pixel_count = merged_pixel_count + blob_pixel_count[i];
                if (blob_min_x[i] < merged_min_x) merged_min_x = blob_min_x[i];
                if (blob_max_x[i] > merged_max_x) merged_max_x = blob_max_x[i];
                if (blob_min_y[i] < merged_min_y) merged_min_y = blob_min_y[i];
                if (blob_max_y[i] > merged_max_y) merged_max_y = blob_max_y[i];
            end
        end
    end

    // One shared shape evaluator checks a single candidate per clock during
    // vertical blanking. This is much smaller than 16 parallel evaluators.
    always_comb begin : evaluate_one_candidate
        eval_width = blob_valid[evaluation_index] ?
            ({1'b0, blob_max_x[evaluation_index]} -
             {1'b0, blob_min_x[evaluation_index]} + 10'd1) : 10'd0;
        eval_height = blob_valid[evaluation_index] ?
            ({1'b0, blob_max_y[evaluation_index]} -
             {1'b0, blob_min_y[evaluation_index]} + 9'd1) : 9'd0;
        eval_area = (eval_width * 32'd1) * eval_height;

        eval_small = (eval_width < SMALL_OBJECT_LIMIT) &&
                     (eval_height < SMALL_OBJECT_LIMIT);
        eval_aspect_num = eval_small ? SMALL_ASPECT_NUM : ASPECT_NUM;
        eval_aspect_den = eval_small ? SMALL_ASPECT_DEN : ASPECT_DEN;
        eval_min_fill_percent = eval_small ?
            SMALL_MIN_FILL_PERCENT : MIN_FILL_PERCENT;
        eval_max_fill_percent = eval_small ?
            SMALL_MAX_FILL_PERCENT : MAX_FILL_PERCENT;

        eval_aspect_valid =
            ((eval_width * eval_aspect_den) >=
             (eval_height * eval_aspect_num)) &&
            ((eval_height * eval_aspect_den) >=
             (eval_width * eval_aspect_num));

        eval_pixels_x100 = blob_pixel_count[evaluation_index] * 32'd100;
        eval_min_fill = eval_area * eval_min_fill_percent;
        eval_max_fill = eval_area * eval_max_fill_percent;
        eval_fill_valid = (eval_area != 0) &&
                          (eval_pixels_x100 >= eval_min_fill) &&
                          (eval_pixels_x100 <= eval_max_fill);
        eval_size_valid = blob_valid[evaluation_index] &&
                          (eval_width >= MIN_DIAMETER) &&
                          (eval_height >= MIN_DIAMETER);
        eval_shape_valid = eval_size_valid &&
                           eval_aspect_valid && eval_fill_valid;

        // A filled circle occupies about 79 percent of its bounding box.
        // The ranks only select between already valid objects; they do not
        // tighten the current acceptance limits.
        eval_target_fill = eval_area * ROUND_FILL_PERCENT;
        eval_fill_error = (eval_pixels_x100 >= eval_target_fill) ?
            (eval_pixels_x100 - eval_target_fill) :
            (eval_target_fill - eval_pixels_x100);
        if (eval_fill_error <= (eval_area << 3)) begin
            eval_round_rank = 2'd2;
        end else if (eval_fill_error <= (eval_area << 4)) begin
            eval_round_rank = 2'd1;
        end else begin
            eval_round_rank = 2'd0;
        end

        eval_aspect_error =
            (eval_width >= {1'b0, eval_height}) ?
            (eval_width - {1'b0, eval_height}) :
            ({1'b0, eval_height} - eval_width);
        eval_max_dimension =
            (eval_width >= {1'b0, eval_height}) ?
            eval_width : {1'b0, eval_height};
        if (eval_aspect_error <= (eval_max_dimension >> 3)) begin
            eval_aspect_rank = 2'd2;
        end else if (eval_aspect_error <= (eval_max_dimension >> 2)) begin
            eval_aspect_rank = 2'd1;
        end else begin
            eval_aspect_rank = 2'd0;
        end

        eval_center_x =
            ({1'b0, blob_min_x[evaluation_index]} +
             {1'b0, blob_max_x[evaluation_index]}) >> 1;
        eval_center_y =
            ({1'b0, blob_min_y[evaluation_index]} +
             {1'b0, blob_max_y[evaluation_index]}) >> 1;
        eval_distance =
            ((eval_center_x >= {1'b0, centroid_x}) ?
             (eval_center_x - {1'b0, centroid_x}) :
             ({1'b0, centroid_x} - eval_center_x)) +
            ((eval_center_y >= {1'b0, centroid_y}) ?
             (eval_center_y - {1'b0, centroid_y}) :
             ({1'b0, centroid_y} - eval_center_y));
        eval_near_previous = centroid_valid &&
                             (eval_distance <= TRACK_MAX_DISTANCE);
    end

    // Keep the previous target when possible, then prefer circle-like fill,
    // a width close to the height, and finally the larger candidate.
    always_comb begin : compare_candidate
        eval_candidate_better = 1'b0;

        if (eval_shape_valid) begin
            if (!best_found) begin
                eval_candidate_better = 1'b1;
            end else if (centroid_valid &&
                         (eval_near_previous != best_near_previous)) begin
                eval_candidate_better = eval_near_previous;
            end else if (eval_round_rank != best_round_rank) begin
                eval_candidate_better = eval_round_rank > best_round_rank;
            end else if (eval_aspect_rank != best_aspect_rank) begin
                eval_candidate_better = eval_aspect_rank > best_aspect_rank;
            end else if (centroid_valid &&
                         (eval_distance != best_distance)) begin
                eval_candidate_better = eval_distance < best_distance;
            end else begin
                eval_candidate_better =
                    blob_pixel_count[evaluation_index] > best_pixel_count;
            end
        end

        eval_winner_found = best_found || eval_shape_valid;
        eval_winner_index = eval_candidate_better ?
                            evaluation_index : best_index;
    end

    always_ff @(posedge clk or negedge rst_n) begin : update_blobs
        if (!rst_n) begin
            blob_valid <= '0;
            evaluation_active <= 1'b0;
            evaluation_index <= '0;
            best_found <= 1'b0;
            best_index <= '0;
            best_near_previous <= 1'b0;
            best_round_rank <= '0;
            best_aspect_rank <= '0;
            best_distance <= '0;
            best_pixel_count <= '0;
            centroid_x <= IMG_W / 2;
            centroid_y <= IMG_H / 2;
            centroid_valid <= 1'b0;
            locked_pixel_count <= '0;

            for (integer i = 0; i < MAX_BLOBS; i = i + 1) begin
                blob_sum_x[i] <= '0;
                blob_sum_y[i] <= '0;
                blob_pixel_count[i] <= '0;
                blob_min_x[i] <= '0;
                blob_max_x[i] <= '0;
                blob_min_y[i] <= '0;
                blob_max_y[i] <= '0;
            end
        end else if (frame_start) begin
            // Evaluation of the previous frame is already complete by here.
            // Start collecting independent candidates for the new frame.
            blob_valid <= '0;
            evaluation_active <= 1'b0;
            for (integer i = 0; i < MAX_BLOBS; i = i + 1) begin
                blob_sum_x[i] <= '0;
                blob_sum_y[i] <= '0;
                blob_pixel_count[i] <= '0;
                blob_min_x[i] <= '0;
                blob_max_x[i] <= '0;
                blob_min_y[i] <= '0;
                blob_max_y[i] <= '0;
            end
        end else begin
            if (pix_valid && mask && in_valid_band) begin
                if (match_found) begin
                    blob_valid[match_index] <= 1'b1;
                    blob_sum_x[match_index] <= merged_sum_x;
                    blob_sum_y[match_index] <= merged_sum_y;
                    blob_pixel_count[match_index] <= merged_pixel_count;
                    blob_min_x[match_index] <= merged_min_x;
                    blob_max_x[match_index] <= merged_max_x;
                    blob_min_y[match_index] <= merged_min_y;
                    blob_max_y[match_index] <= merged_max_y;

                    for (integer i = 0; i < MAX_BLOBS; i = i + 1) begin
                        if (match_vector[i] && (i != match_index)) begin
                            blob_valid[i] <= 1'b0;
                        end
                    end
                end else if (slot_found) begin
                    blob_valid[slot_index] <= 1'b1;
                    blob_sum_x[slot_index] <= pix_x;
                    blob_sum_y[slot_index] <= pix_y;
                    blob_pixel_count[slot_index] <=
                        {{(CNT_W-1){1'b0}}, 1'b1};
                    blob_min_x[slot_index] <= pix_x;
                    blob_max_x[slot_index] <= pix_x;
                    blob_min_y[slot_index] <= pix_y;
                    blob_max_y[slot_index] <= pix_y;
                end
            end

            if (frame_end) begin
                evaluation_active <= 1'b1;
                evaluation_index <= '0;
                best_found <= 1'b0;
                best_index <= '0;
                best_near_previous <= 1'b0;
                best_round_rank <= '0;
                best_aspect_rank <= '0;
                best_distance <= '0;
                best_pixel_count <= '0;
            end else if (evaluation_active) begin
                if (eval_candidate_better) begin
                    best_found <= 1'b1;
                    best_index <= evaluation_index;
                    best_near_previous <= eval_near_previous;
                    best_round_rank <= eval_round_rank;
                    best_aspect_rank <= eval_aspect_rank;
                    best_distance <= eval_distance;
                    best_pixel_count <= blob_pixel_count[evaluation_index];
                end

                if (evaluation_index == MAX_BLOBS - 1) begin
                    evaluation_active <= 1'b0;
                    if (eval_winner_found) begin
                        centroid_x <= blob_sum_x[eval_winner_index] /
                                      blob_pixel_count[eval_winner_index];
                        centroid_y <= blob_sum_y[eval_winner_index] /
                                      blob_pixel_count[eval_winner_index];
                        centroid_valid <= 1'b1;
                        locked_pixel_count <=
                            blob_pixel_count[eval_winner_index];
                    end else begin
                        centroid_valid <= 1'b0;
                        locked_pixel_count <= '0;
                    end
                end else begin
                    evaluation_index <= evaluation_index + 1'b1;
                end
            end
        end
    end

    assign mask_pixel_count = locked_pixel_count[16:0];

endmodule
