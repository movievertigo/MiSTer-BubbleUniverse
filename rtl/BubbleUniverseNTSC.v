module BubbleUniverse
(
    input  wire clk,
    input  wire reset,
    input  wire [31:0] joystick_0,

    output wire ce_pix,

    output reg HBlank,
    output reg HSync,
    output reg VBlank,
    output reg VSync,

    output reg [7:0] videor,
    output reg [7:0] videog,
    output reg [7:0] videob
);

localparam H_VISIBLE = 640;
localparam H_FP      = 16;
localparam H_SYNC    = 96;
localparam H_TOTAL   = 800;

localparam V_VISIBLE = 240;
localparam V_FP      = 5;
localparam V_SYNC    = 3;
localparam V_TOTAL   = 262;

reg [7:0] screen[0:H_VISIBLE*V_VISIBLE-1];

reg [9:0] pixelx;
reg [9:0] pixely;

reg [18:0] writeAddress;
reg [7:0] writeValue;
reg writeEnable;
reg [18:0] readAddress;
reg [7:0] readValue;

always @(posedge clk) begin
    ce_pix <= ~ce_pix;
end

always @(posedge ce_pix) begin
    if (writeEnable) screen[writeAddress] <= writeValue;
    readValue <= screen[readAddress];
end

always @(posedge ce_pix) begin
    if (reset) begin
        pixelx = 0;
        pixely = 0;
    end else if (pixelx == H_TOTAL-1) begin
        pixelx = 0;
        pixely = (pixely == V_TOTAL-1) ? 0 : pixely + 1;
    end else begin
        pixelx = pixelx + 1;
    end
    readAddress = pixely * H_VISIBLE + ((pixelx+H_VISIBLE) >> 1);
end

always @(posedge ce_pix) begin
    HBlank <= (pixelx >= H_VISIBLE);
    VBlank <= (pixely >= V_VISIBLE);
    HSync <= (pixelx >= H_VISIBLE + H_FP && pixelx < H_VISIBLE + H_FP + H_SYNC);
    VSync <= (pixely >= V_VISIBLE + V_FP && pixely < V_VISIBLE + V_FP + V_SYNC);
end

assign videor = HBlank || VBlank || readValue == 0 ? 0 : (readValue & 240);
assign videog = HBlank || VBlank || readValue == 0 ? 0 : ((readValue & 15) << 4);
assign videob = HBlank || VBlank || readValue == 0 ? 0 : (30 - ((readValue >> 4) + (readValue & 15))) << 3;

`include "sin.v"
localparam CURVECOUNT = 256;
localparam CURVESTEP = 4;
localparam ITERATIONS = 256;
localparam SINTABLEPOWER = 14;
localparam SINTABLEENTRIES = 1 << SINTABLEPOWER;
localparam SINTABLEMASK = SINTABLEENTRIES - 1;
localparam PI = 31416;
localparam PISCALE = 10000;
localparam ANG1INC = (CURVESTEP * SINTABLEENTRIES) / 235;
localparam ANG2INC = (CURVESTEP * SINTABLEENTRIES * (PISCALE / 2)) / PI;
localparam STATESHIFT = 8;
localparam INITSCALE = (V_VISIBLE * PI / (PISCALE * 2)) << STATESHIFT;
localparam INITANIMSPEED = 8 << STATESHIFT;
localparam OFFSETSPEED = 2 << STATESHIFT;
localparam ZOOMSPEEDSHIFT = 7;
localparam ANIMACCELERATION = (10 << STATESHIFT) / 100;

localparam SCREENCENTRE = ((H_VISIBLE*V_VISIBLE)>>1)+((3*H_VISIBLE)>>2);

reg [1:0] stage; // 0 - waiting, 1 - clearing, 2 - drawing
reg [15:0] animationTime;
reg [15:0] ang1Start;
reg [15:0] ang2Start;
reg [7:0] i;
reg [7:0] j;
reg signed [15:0] ang1;
reg signed [15:0] ang2;
reg signed [15:0] x;
reg signed [15:0] y;
reg signed [63:0] pX;
reg signed [63:0] pY;
reg signed [63:0] scale;
reg signed [63:0] offsetX;
reg signed [63:0] offsetY;
reg signed [63:0] animSpeed;
reg signed [63:0] oldAnimSpeed;
reg trails, trailsOldButton;
reg pausedOldButton;

always @(posedge ce_pix) begin
    if (reset) begin
        animationTime <= 0;
        writeEnable <= 0;
        stage <= 0;
    end else if (stage == 0) begin
        if (pixelx == 0 && pixely == 0) begin
            writeAddress <= 0;
            writeValue <= 0;
            writeEnable <= !trails;
            stage <= 1;
        end
    end else if (stage == 1) begin
        if (writeAddress == H_VISIBLE*V_VISIBLE-1) begin
            writeEnable <= 0;
            ang1Start <= animationTime;
            ang2Start <= animationTime;
            animationTime <= animationTime + (animSpeed >>> STATESHIFT);
            i <= 0;
            j <= 0;
            x <= 0;
            y <= 0;
            stage <= 2;
        end else if (pixelx < H_VISIBLE) begin
            writeAddress <= writeAddress + 1;
        end
    end else if (stage == 2) begin
        ang1 = ang1Start + x;
        ang2 = ang2Start + y;
        x = sin[ang1 & SINTABLEMASK] + sin[ang2 & SINTABLEMASK];
        y = sin[(ang1+(SINTABLEENTRIES/4)) & SINTABLEMASK] + sin[(ang2+(SINTABLEENTRIES/4)) & SINTABLEMASK];
        pX = (((x * scale) >>> SINTABLEPOWER) + offsetX) >>> STATESHIFT;
        pY = (((y * scale) >>> SINTABLEPOWER) + offsetY) >>> STATESHIFT;
        writeAddress = SCREENCENTRE + pY * H_VISIBLE + pX;
        writeValue = ((i >> 4) == 0 && (j >> 4) == 0) ? 1 : ((i & 240) | (j >> 4));
        writeEnable = pX >= -(H_VISIBLE>>1) && pY >= -(V_VISIBLE>>1) && pX < (H_VISIBLE>>1) && pY < (V_VISIBLE>>1);
        if (j < ITERATIONS - 1) begin
            j = j + 1;
        end else begin
            ang1Start = ang1Start + ANG1INC;
            ang2Start = ang2Start + ANG2INC;
            x = 0;
            y = 0;
            j = 0;
            if (i < CURVECOUNT - CURVESTEP) begin
                i = i + CURVESTEP;
            end else begin
                stage = 0;
            end
        end
    end
end

always @(posedge ce_pix) begin
    if (reset) begin
        offsetX <= 0;
        offsetY <= 0;
        scale <= INITSCALE;
        animSpeed <= INITANIMSPEED;
        trails <= 0;
    end else if (pixelx == 0 && pixely == 0) begin
        offsetX = offsetX - (joystick_0[0] ? OFFSETSPEED : 0) + (joystick_0[1] ? OFFSETSPEED : 0);
        offsetY = offsetY - (joystick_0[2] ? OFFSETSPEED : 0) + (joystick_0[3] ? OFFSETSPEED : 0);
        offsetX = offsetX + (joystick_0[4] ? (offsetX >>> ZOOMSPEEDSHIFT) : 0) - (joystick_0[5] ? (offsetX >>> ZOOMSPEEDSHIFT) : 0);
        offsetY = offsetY + (joystick_0[4] ? (offsetY >>> ZOOMSPEEDSHIFT) : 0) - (joystick_0[5] ? (offsetY >>> ZOOMSPEEDSHIFT) : 0);
        scale <= scale + (joystick_0[4] ? (scale >>> ZOOMSPEEDSHIFT) : 0) - (joystick_0[5] ? (scale >>> ZOOMSPEEDSHIFT) : 0);
        animSpeed <= (joystick_0[8] && !pausedOldButton) ? (animSpeed == 0 ? oldAnimSpeed : 0) : (animSpeed + (joystick_0[6] ? ANIMACCELERATION : 0) - (joystick_0[7] ? ANIMACCELERATION : 0));
        oldAnimSpeed <= (joystick_0[8] && !pausedOldButton) ? animSpeed : oldAnimSpeed;
        trails <= (joystick_0[9] && !trailsOldButton) ? !trails : trails;
        pausedOldButton <= joystick_0[8];
        trailsOldButton <= joystick_0[9];
    end
end

endmodule
