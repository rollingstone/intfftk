-------------------------------------------------------------------------------
--
-- Title       : int_fftNk_sc
-- Design      : Integer Forward FFTK
-- Author      : Kapitanov Alexander
-- Company     : 
-- E-mail      : sallador@bk.ru
--
-------------------------------------------------------------------------------
--
-- Description : Integer Scaled Forward Fast Fourier Transform: N = 8 to 512K
-- 					(You must use 2D-FFT for N > 512K!)
--
--    Input data: IN0 and IN1 where
--      IN0 - 1st half part of data
--      IN1 - 2nd half part of data flow (length = NFFT)
--    
--    Output data: OUT0 and OUT1 where
--      OUT0 - Even part of data
--      OUT1 - Odd part of data flow
--		
--		Clock enable (Input data valid) must be strobe N = 2^(NFFT) cycles
---     w/o interruption!!!
--
--      Example: 
--        Input data:   ________________________
--        DI_EN     ___/                        \____
--        DI_AA:        /0\/1\/2\/3\/4\/5\/6\/7\
--        DI_BB:        \8/\9/\A/\B/\C/\D/\E/\F/
-- 
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--
--	GNU GENERAL PUBLIC LICENSE
--  Version 3, 29 June 2007
--
--	Copyright (c) 2018 Kapitanov Alexander
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
--  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
--  APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT 
--  HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY 
--  OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, 
--  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR 
--  PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM 
--  IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF 
--  ALL NECESSARY SERVICING, REPAIR OR CORRECTION. 
-- 
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity int_fftNk_sc is
	generic (													    
		IS_SIM		: boolean:=FALSE;		--! Simulation model: TRUE / FALSE
		TD			: time:=0.5ns;			--! Simulation time		
		NFFT		: integer:=5;			--! Number of FFT stages     		
		DATA_WIDTH	: integer:=16;			--! Input data width
		TWDL_WIDTH	: integer:=16;			--! Twiddle factor data width	
		XSER		: string:="OLD";		--! FPGA family: for 6/7 series: "OLD"; for ULTRASCALE: "NEW";
		USE_MLT		: boolean:=FALSE		--! Use multipliers in Twiddle factors
	);
	port (
		RST  		: in  std_logic;		--! Global positive RST 
		CLK 		: in  std_logic;		--! Signal processing clock 
	
		USE_FLY		: in  std_logic;		--! '1' - use arithmetics, '0' - don't use

		DI_RE0		: in  std_logic_vector(DATA_WIDTH-1 downto 0); --! Input data Even Re
		DI_IM0		: in  std_logic_vector(DATA_WIDTH-1 downto 0); --! Input data Even Im
		DI_RE1		: in  std_logic_vector(DATA_WIDTH-1 downto 0); --! Input data Odd Re
		DI_IM1		: in  std_logic_vector(DATA_WIDTH-1 downto 0); --! Input data Odd Im
		DI_ENA		: in  std_logic; --! Input valid data

		DO_RE0		: out std_logic_vector(DATA_WIDTH-1 downto 0); --! Output data Even Re
		DO_IM0		: out std_logic_vector(DATA_WIDTH-1 downto 0); --! Output data Even Im
		DO_RE1		: out std_logic_vector(DATA_WIDTH-1 downto 0); --! Output data Odd Re
		DO_IM1		: out std_logic_vector(DATA_WIDTH-1 downto 0); --! Output data Odd Im
		DO_VAL		: out std_logic --! Output valid data
	);
end int_fftNk_sc;

architecture int_fftNk_sc of int_fftNk_sc is	

type complex_WxN is array (NFFT-1 downto 0) of std_logic_vector(DATA_WIDTH-1 downto 0);

-------- Butterfly In / Out --------
signal ia_re		: complex_WxN;
signal ia_im		: complex_WxN;
signal ib_re		: complex_WxN;
signal ib_im		: complex_WxN;

signal oa_re		: complex_WxN;
signal oa_im		: complex_WxN;
signal ob_re		: complex_WxN;
signal ob_im		: complex_WxN;

-------- Align data --------
signal sa_re		: complex_WxN;
signal sa_im		: complex_WxN;
signal sb_re		: complex_WxN;
signal sb_im		: complex_WxN;

-------- Mux'ed data flow (fly_ena) --------
signal xa_re		: complex_WxN;
signal xa_im		: complex_WxN;
signal xb_re		: complex_WxN;
signal xb_im		: complex_WxN;

-------- Enables --------
signal ab_en		: std_logic_vector(NFFT-1 downto 0);
signal ab_vl		: std_logic_vector(NFFT-1 downto 0);
signal ss_en		: std_logic_vector(NFFT-1 downto 0);
signal xx_vl		: std_logic_vector(NFFT-1 downto 0);

-------- Delay data Cross-commutation --------
type complex_DxN is array (NFFT-2 downto 0) of std_logic_vector(2*DATA_WIDTH-1 downto 0);

signal di_aa 		: complex_DxN;
signal di_bb 		: complex_DxN;  
signal do_aa 		: complex_DxN;
signal do_bb 		: complex_DxN;

signal di_en		: std_logic_vector(NFFT-2 downto 0);
signal do_en		: std_logic_vector(NFFT-2 downto 0);

-------- Twiddle factor --------
type complex_FxN is array (NFFT-1 downto 0) of std_logic_vector(TWDL_WIDTH-1 downto 0);
signal ww_re		: complex_FxN;
signal ww_im		: complex_FxN;
signal ww_en		: std_logic_vector(NFFT-1 downto 0);

begin

ab_en(0) <= DI_ENA;		 
ia_re(0)(DATA_WIDTH-1 downto 0) <= DI_RE0;
ia_im(0)(DATA_WIDTH-1 downto 0) <= DI_IM0;
ib_re(0)(DATA_WIDTH-1 downto 0) <= DI_RE1;
ib_im(0)(DATA_WIDTH-1 downto 0) <= DI_IM1;

xCALC: for ii in 0 to NFFT-1 generate

begin			

	---- Butterflies ----
	xBUTTERFLY: entity work.int_dif2_fly_sc
		generic map ( 
			IS_SIM 	=> IS_SIM,
			TD 		=> TD,
			STAGE 	=> NFFT-ii-1,
			DTW 	=> DATA_WIDTH,
			TFW 	=> TWDL_WIDTH,
			XSER 	=> XSER
		)
		port map (
			IA_RE	=> sa_re(ii),
			IA_IM	=> sa_im(ii),
			IB_RE	=> sb_re(ii),
			IB_IM	=> sb_im(ii),
			IN_EN	=> ss_en(ii),

			OA_RE	=> oa_re(ii),
			OA_IM	=> oa_im(ii),
			OB_RE	=> ob_re(ii),
			OB_IM	=> ob_im(ii),
			DO_VL	=> ab_vl(ii),
			
			WW_RE	=> ww_re(ii),
            WW_IM	=> ww_im(ii),
			
			RST		=> rst,
			clk		=> clk
		); 
		
	---- Twiddle factor ----

	xTWIDDLE: entity work.rom_twiddle_int
		generic map (
			TD		=> TD,
			AWD		=> TWDL_WIDTH,
			NFFT	=> NFFT,
			STAGE	=> NFFT-ii-1,
			XSER	=> XSER,
			USE_MLT	=> USE_MLT
		)
		port map (
			CLK 	=> clk,
			RST  	=> rst,
			WW_EN 	=> ww_en(ii),
			WW_RE	=> ww_re(ii),
			WW_IM	=> ww_im(ii)
		);			

	---- Aligne data for butterfly calc ----
	xALIGNE: entity work.int_align_fft 
		generic map ( 		
			DATW	=> DATA_WIDTH,
			NFFT	=> NFFT,
			STAGE 	=> NFFT-ii-1
		)
		port map (	
			CLK		=> clk,
			IA_RE	=> ia_re(ii),
			IA_IM	=> ia_im(ii),
			IB_RE	=> ib_re(ii),
			IB_IM	=> ib_im(ii),
			
			OA_RE	=> sa_re(ii),
			OA_IM	=> sa_im(ii),
			OB_RE	=> sb_re(ii),
			OB_IM	=> sb_im(ii),
			
			BF_EN	=> ab_en(ii),
			BF_VL	=> ss_en(ii),
			TW_EN	=> ww_en(ii)
		);

	---- select input delay data ----
	pr_xd: process(clk) is
	begin
		if rising_edge(clk) then
			if (USE_FLY = '1') then
				xx_vl(ii) <= ab_vl(ii);
				xa_re(ii) <= oa_re(ii); 
				xa_im(ii) <= oa_im(ii); 
				xb_re(ii) <= ob_re(ii); 
				xb_im(ii) <= ob_im(ii); 
			else		
				xx_vl(ii) <= ab_en(ii);
				xa_re(ii) <= ia_re(ii); 
				xa_im(ii) <= ia_im(ii); 
				xb_re(ii) <= ib_re(ii);  
				xb_im(ii) <= ib_im(ii);  
			end if;
		end if;
	end process;
	
end generate;

xDELAYS: for ii in 0 to NFFT-2 generate
	begin
	
	di_aa(ii) <= xa_im(ii) & xa_re(ii);	
	di_bb(ii) <= xb_im(ii) & xb_re(ii);	
	di_en(ii) <= xx_vl(ii);
	
	xDELAY_LINE : entity work.int_delay_line
		generic map(
			NWIDTH		=> 2*DATA_WIDTH,
			NFFT		=> NFFT,
			STAGE		=> ii	
		)
		port map (
			DI_AA		=> di_aa(ii),
			DI_BB		=> di_bb(ii),
			DI_EN		=> di_en(ii),  
			DO_AA		=> do_aa(ii),
			DO_BB		=> do_bb(ii),
			DO_VL		=> do_en(ii),
			RST 		=> rst,
			CLK 		=> clk
		);

	ia_re(ii+1)(DATA_WIDTH-1 downto 0) <= do_aa(ii)(1*DATA_WIDTH-1 downto 0*DATA_WIDTH);
	ia_im(ii+1)(DATA_WIDTH-1 downto 0) <= do_aa(ii)(2*DATA_WIDTH-1 downto 1*DATA_WIDTH);
	ib_re(ii+1)(DATA_WIDTH-1 downto 0) <= do_bb(ii)(1*DATA_WIDTH-1 downto 0*DATA_WIDTH);
	ib_im(ii+1)(DATA_WIDTH-1 downto 0) <= do_bb(ii)(2*DATA_WIDTH-1 downto 1*DATA_WIDTH);	
	ab_en(ii+1) <= do_en(ii); 
end generate;

pr_out: process(clk) is
begin
	if rising_edge(clk) then
		if (rst = '1') then
			DO_RE0 <= (others => '0'); 
			DO_IM0 <= (others => '0'); 
			DO_RE1 <= (others => '0'); 
			DO_IM1 <= (others => '0'); 
			DO_VAL <= '0'; 
		else
			DO_RE0 <= xa_re(NFFT-1); 
			DO_IM0 <= xa_im(NFFT-1); 
			DO_RE1 <= xb_re(NFFT-1); 
			DO_IM1 <= xb_im(NFFT-1); 
			DO_VAL <= xx_vl(NFFT-1);
		end if;
	end if;
end process;

end int_fftNk_sc;