/**
 * Copyright (C) 2025  AGH University of Science and Technology
 * MTM UEC2
 * Author: Piotr Kaczmarczyk
 *
 * Description:
 * Package with vga related constants.
 */

package vga_pkg;

    // VESA 1024 x 768 @ 60 Hz timing using a 65 MHz pixel clock.
    localparam int HOR_PIXELS = 1024;
    localparam int VER_PIXELS = 768;

    localparam int HOR_TOTAL_TIME  = 1344;
    localparam int HOR_BLANK_START = 1024;
    localparam int HOR_BLANK_TIME  = 320;
    localparam int HOR_SYNC_START  = 1048;
    localparam int HOR_SYNC_TIME   = 136;

    localparam int VER_TOTAL_TIME  = 806;
    localparam int VER_BLANK_START = 768;
    localparam int VER_BLANK_TIME  = 38;
    localparam int VER_SYNC_START  = 771;
    localparam int VER_SYNC_TIME   = 6;

    localparam logic HSYNC_POLARITY = 1'b0;
    localparam logic VSYNC_POLARITY = 1'b0;

endpackage
