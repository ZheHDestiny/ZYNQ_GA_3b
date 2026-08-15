// SPDX-License-Identifier: MIT
// Q16.32 Pure3 fitness lane with a smooth inverse-r^3 LUT force model.
// INTEGRATOR_MODE=0: symplectic Euler; 1: cached-acceleration Leapfrog.
`timescale 1ns/1ps

module ga3b_pure3_hifi_fitness_lane #(
    parameter integer GENE_COUNT=8,
    parameter integer GENE_WIDTH=32,
    parameter integer FITNESS_WIDTH=64,
    parameter integer INTEGRATOR_MODE=0
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [31:0] steps_limit,
    input wire [GENE_COUNT*GENE_WIDTH-1:0] chromosome_flat,
    output reg busy,
    output reg done,
    output reg [FITNESS_WIDTH-1:0] fitness,
    output reg [31:0] survived_steps,
    output reg valid_stable,
    output reg error
);
    localparam [4:0] S_IDLE=0, S_FORCE_PRE=1, S_FORCE_START=2, S_FORCE_WAIT=3;
    localparam [4:0] S_FORCE_ACC=4, S_FORCE_FINISH=5, S_SYM_V=6, S_SYM_X=7;
    localparam [4:0] S_LF_DRIFT=8, S_LF_NEW_SETUP=9, S_LF_V=10;
    localparam [4:0] S_METRIC_PRE=11, S_METRIC_CHK=12, S_METRIC_DONE=13, S_DONE=14;
    localparam [1:0] KIND_SYM=0, KIND_LF_INIT=1, KIND_LF_NEW=2;
    localparam signed [47:0] COLLISION_L1 = 48'sd536870912;    // 0.125 Q32
    localparam signed [47:0] ESCAPE_ABS   = 48'sd34359738368;  // 8.0 Q32

    reg [4:0] state;
    reg [1:0] force_kind;
    reg [1:0] pair_sel;
    reg [2:0] metric_sel;
    reg [31:0] step_idx;
    reg failed, step_failed;

    reg signed [47:0] x0,y0,vx0,vy0,x1,y1,vx1,vy1,x2,y2,vx2,vy2;
    reg signed [47:0] wax0,way0,wax1,way1,wax2,way2;
    reg signed [47:0] cax0,cay0,cax1,cay1,cax2,cay2;
    reg signed [47:0] pair_dx, pair_dy;
    reg force_start;
    wire force_done;
    wire signed [47:0] pair_fx, pair_fy;

    wire signed [31:0] g_x0=chromosome_flat[0*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_y0=chromosome_flat[1*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_vx0=chromosome_flat[2*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_vy0=chromosome_flat[3*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_x1=chromosome_flat[4*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_y1=chromosome_flat[5*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_vx1=chromosome_flat[6*GENE_WIDTH +: GENE_WIDTH];
    wire signed [31:0] g_vy1=chromosome_flat[7*GENE_WIDTH +: GENE_WIDTH];

    ga3b_pure3_hifi_force_pair u_force(
        .clk(clk),.rst_n(rst_n),.start(force_start),.dx(pair_dx),.dy(pair_dy),
        .busy(),.done(force_done),.fx(pair_fx),.fy(pair_fy));

    function signed [47:0] abs48;
        input signed [47:0] v;
        begin abs48 = v[47] ? -v : v; end
    endfunction

    function signed [47:0] round_sra48;
        input signed [47:0] v;
        input integer sh;
        reg signed [48:0] mag;
        begin
            if (!v[47]) round_sra48 = (v + (48'sd1 <<< (sh-1))) >>> sh;
            else begin
                mag = -$signed({v[47],v});
                round_sra48 = -((mag + (49'sd1 <<< (sh-1))) >>> sh);
            end
        end
    endfunction

    function signed [47:0] round_sra49;
        input signed [48:0] v;
        input integer sh;
        reg signed [49:0] mag;
        begin
            if (!v[48]) round_sra49 = (v + (49'sd1 <<< (sh-1))) >>> sh;
            else begin
                mag = -$signed({v[48],v});
                round_sra49 = -((mag + (50'sd1 <<< (sh-1))) >>> sh);
            end
        end
    endfunction

    function pair_collision;
        input signed [47:0] dx,dy;
        reg [48:0] l1;
        begin
            l1={1'b0,abs48(dx)}+{1'b0,abs48(dy)};
            pair_collision=(l1 < COLLISION_L1);
        end
    endfunction

    function body_escape;
        input signed [47:0] x,y;
        begin body_escape=(abs48(x)>ESCAPE_ABS)||(abs48(y)>ESCAPE_ABS); end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; busy<=0; done<=0; fitness<=0; survived_steps<=0;
            valid_stable<=0; error<=0; force_start<=0; force_kind<=0; pair_sel<=0;
            metric_sel<=0; step_idx<=0; failed<=0; step_failed<=0;
            x0<=0;y0<=0;vx0<=0;vy0<=0;x1<=0;y1<=0;vx1<=0;vy1<=0;
            x2<=0;y2<=0;vx2<=0;vy2<=0;
            wax0<=0;way0<=0;wax1<=0;way1<=0;wax2<=0;way2<=0;
            cax0<=0;cay0<=0;cax1<=0;cay1<=0;cax2<=0;cay2<=0;
            pair_dx<=0;pair_dy<=0;
        end else begin
            done<=0; force_start<=0;
            case(state)
                S_IDLE: begin
                    busy<=0;
                    if(start) begin
                        busy<=1; fitness<=0; survived_steps<=0; valid_stable<=0;
                        error<=(steps_limit==0); failed<=(steps_limit==0); step_idx<=0;
                        x0<={{16{g_x0[31]}},g_x0} <<< 16;
                        y0<={{16{g_y0[31]}},g_y0} <<< 16;
                        vx0<={{16{g_vx0[31]}},g_vx0} <<< 16;
                        vy0<={{16{g_vy0[31]}},g_vy0} <<< 16;
                        x1<={{16{g_x1[31]}},g_x1} <<< 16;
                        y1<={{16{g_y1[31]}},g_y1} <<< 16;
                        vx1<={{16{g_vx1[31]}},g_vx1} <<< 16;
                        vy1<={{16{g_vy1[31]}},g_vy1} <<< 16;
                        x2<=-({{16{g_x0[31]}},g_x0} <<< 16)-({{16{g_x1[31]}},g_x1} <<< 16);
                        y2<=-({{16{g_y0[31]}},g_y0} <<< 16)-({{16{g_y1[31]}},g_y1} <<< 16);
                        vx2<=-({{16{g_vx0[31]}},g_vx0} <<< 16)-({{16{g_vx1[31]}},g_vx1} <<< 16);
                        vy2<=-({{16{g_vy0[31]}},g_vy0} <<< 16)-({{16{g_vy1[31]}},g_vy1} <<< 16);
                        wax0<=0;way0<=0;wax1<=0;way1<=0;wax2<=0;way2<=0;
                        pair_sel<=0; force_kind<=(INTEGRATOR_MODE==0)?KIND_SYM:KIND_LF_INIT;
                        state<=(steps_limit==0)?S_DONE:S_FORCE_PRE;
                    end
                end
                S_FORCE_PRE: begin
                    if(pair_sel==0) begin pair_dx<=x1-x0; pair_dy<=y1-y0; end
                    else if(pair_sel==1) begin pair_dx<=x2-x0; pair_dy<=y2-y0; end
                    else begin pair_dx<=x2-x1; pair_dy<=y2-y1; end
                    state<=S_FORCE_START;
                end
                S_FORCE_START: begin force_start<=1; state<=S_FORCE_WAIT; end
                S_FORCE_WAIT: if(force_done) state<=S_FORCE_ACC;
                S_FORCE_ACC: begin
                    if(pair_sel==0) begin
                        wax0<=wax0+pair_fx; way0<=way0+pair_fy;
                        wax1<=wax1-pair_fx; way1<=way1-pair_fy; pair_sel<=1; state<=S_FORCE_PRE;
                    end else if(pair_sel==1) begin
                        wax0<=wax0+pair_fx; way0<=way0+pair_fy;
                        wax2<=wax2-pair_fx; way2<=way2-pair_fy; pair_sel<=2; state<=S_FORCE_PRE;
                    end else begin
                        wax1<=wax1+pair_fx; way1<=way1+pair_fy;
                        wax2<=wax2-pair_fx; way2<=way2-pair_fy; state<=S_FORCE_FINISH;
                    end
                end
                S_FORCE_FINISH: begin
                    if(force_kind==KIND_LF_INIT) begin
                        cax0<=wax0;cay0<=way0;cax1<=wax1;cay1<=way1;cax2<=wax2;cay2<=way2;
                        state<=S_LF_DRIFT;
                    end else if(force_kind==KIND_LF_NEW) state<=S_LF_V;
                    else state<=S_SYM_V;
                end
                S_SYM_V: begin
                    vx0<=vx0+round_sra48(wax0,8); vy0<=vy0+round_sra48(way0,8);
                    vx1<=vx1+round_sra48(wax1,8); vy1<=vy1+round_sra48(way1,8);
                    vx2<=vx2+round_sra48(wax2,8); vy2<=vy2+round_sra48(way2,8);
                    state<=S_SYM_X;
                end
                S_SYM_X: begin
                    x0<=x0+round_sra48(vx0,8); y0<=y0+round_sra48(vy0,8);
                    x1<=x1+round_sra48(vx1,8); y1<=y1+round_sra48(vy1,8);
                    x2<=x2+round_sra48(vx2,8); y2<=y2+round_sra48(vy2,8);
                    state<=S_METRIC_PRE;
                end
                S_LF_DRIFT: begin
                    x0<=x0+round_sra48(vx0,8)+round_sra48(cax0,17);
                    y0<=y0+round_sra48(vy0,8)+round_sra48(cay0,17);
                    x1<=x1+round_sra48(vx1,8)+round_sra48(cax1,17);
                    y1<=y1+round_sra48(vy1,8)+round_sra48(cay1,17);
                    x2<=x2+round_sra48(vx2,8)+round_sra48(cax2,17);
                    y2<=y2+round_sra48(vy2,8)+round_sra48(cay2,17);
                    state<=S_LF_NEW_SETUP;
                end
                S_LF_NEW_SETUP: begin
                    wax0<=0;way0<=0;wax1<=0;way1<=0;wax2<=0;way2<=0;
                    pair_sel<=0; force_kind<=KIND_LF_NEW; state<=S_FORCE_PRE;
                end
                S_LF_V: begin
                    vx0<=vx0+round_sra49($signed({cax0[47],cax0})+$signed({wax0[47],wax0}),9);
                    vy0<=vy0+round_sra49($signed({cay0[47],cay0})+$signed({way0[47],way0}),9);
                    vx1<=vx1+round_sra49($signed({cax1[47],cax1})+$signed({wax1[47],wax1}),9);
                    vy1<=vy1+round_sra49($signed({cay1[47],cay1})+$signed({way1[47],way1}),9);
                    vx2<=vx2+round_sra49($signed({cax2[47],cax2})+$signed({wax2[47],wax2}),9);
                    vy2<=vy2+round_sra49($signed({cay2[47],cay2})+$signed({way2[47],way2}),9);
                    cax0<=wax0;cay0<=way0;cax1<=wax1;cay1<=way1;cax2<=wax2;cay2<=way2;
                    state<=S_METRIC_PRE;
                end
                S_METRIC_PRE: begin metric_sel<=0; step_failed<=0; state<=S_METRIC_CHK; end
                S_METRIC_CHK: begin
                    case(metric_sel)
                        0: step_failed<=step_failed|pair_collision(x1-x0,y1-y0);
                        1: step_failed<=step_failed|pair_collision(x2-x0,y2-y0);
                        2: step_failed<=step_failed|pair_collision(x2-x1,y2-y1);
                        3: step_failed<=step_failed|body_escape(x0,y0);
                        4: step_failed<=step_failed|body_escape(x1,y1);
                        default: step_failed<=step_failed|body_escape(x2,y2);
                    endcase
                    if(metric_sel==5) state<=S_METRIC_DONE; else metric_sel<=metric_sel+1'b1;
                end
                S_METRIC_DONE: begin
                    if(step_failed) failed<=1; else survived_steps<=survived_steps+1'b1;
                    if(failed||step_failed||(step_idx+1>=steps_limit)) state<=S_DONE;
                    else begin
                        step_idx<=step_idx+1'b1;
                        if(INTEGRATOR_MODE==0) begin
                            wax0<=0;way0<=0;wax1<=0;way1<=0;wax2<=0;way2<=0;
                            pair_sel<=0;force_kind<=KIND_SYM;state<=S_FORCE_PRE;
                        end else state<=S_LF_DRIFT;
                    end
                end
                S_DONE: begin
                    busy<=0;done<=1;valid_stable<=(!failed&&!error&&(survived_steps>=steps_limit));
                    fitness<=((!failed&&!error&&(survived_steps>=steps_limit))?64'h0000_0001_0000_0000:64'd0)+{32'd0,survived_steps};
                    state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
