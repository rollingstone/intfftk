-------------------------------------------------------------------------------
--
-- Title       : iobuf_flow_int2
-- Design      : fpfftk
-- Author      : Kapitanov
-- Company     :
--
-------------------------------------------------------------------------------
--
-- Description : version 1.0
--
-------------------------------------------------------------------------------
--
--	Version 1.0  12.02.2016
--        Description: Convert data from interleave-2 mode to bit-reverse.
--                        Common clock. Data enable strobe can't be wrapped. 
--                        
--        Example 1 (Mode BITREV = FALSE): Interleave-2 to Half-part data.		
--
--        Data in:
--            DIx: ...0246...
--            DIx: ...1357...
--
--        Data out: (two parts of data)
--            DOx: .......0123...
--            DOx: .......4567...
--
--        Example 2 (Mode BITREV = TRUE): Half-part data to Interleave-2.		
--
--        Data in:
--            DIx: ...0123...
--            DIx: ...4567...
--
--        Data out: (interleave-2)
--            DOx: .......0246...
--            DOx: .......1357...
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
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity iobuf_flow_int2 is
	generic (
		TD			: time:=0.1ns;   --! Simulation time
		BITREV		: boolean:=FALSE;--! Bit-reverse mode (FALSE - int2-to-half, TRUE - half-to-int2)
		DATA		: integer:= 32;  --! Data Width
	    ADDR		: integer:= 10   --! Address depth
		);
	port (
	    rst			: in  std_logic;
		clk			: in  std_logic;	    

	    dt_int0		: in  std_logic_vector(DATA-1 downto 0);    
	    dt_int1		: in  std_logic_vector(DATA-1 downto 0);    
	    dt_en01		: in  std_logic;
		
	    dt_rev0		: out std_logic_vector(DATA-1 downto 0);
	    dt_rev1		: out std_logic_vector(DATA-1 downto 0);
		dt_vl01		: out std_logic
	);
end iobuf_flow_int2;
 
architecture iobuf_flow_int2 of iobuf_flow_int2 is

---------------- Input data ----------------
signal dt_ena			: std_logic;

---------------- RAM signals ----------------
signal ram_dia			: std_logic_vector(DATA-1 downto 0);
signal ram_dib			: std_logic_vector(DATA-1 downto 0);
	
signal ram_wr			: std_logic;
signal ram_rd			: std_logic;
signal ram_rdz			: std_logic;
	
signal ram_adra			: std_logic_vector(ADDR-1 downto 0);
signal ram_adrb			: std_logic_vector(ADDR-1 downto 0);
	
signal ram_doa			: std_logic_vector(DATA-1 downto 0);
signal ram_dob			: std_logic_vector(DATA-1 downto 0);
	
signal rd_1st			: std_logic;

---------------- Calculate Bit / Index Position -----------------
type str_arr is array(0 to ADDR-1) of std_logic_vector(ADDR-1 downto 0);
type int_arr is array(0 to ADDR-1) of integer;

---------------- Calculate Address Increment and Delay --------
-- function del_array(std_var : std_logic_vector) return str_arr is
	-- variable Tmp_Std : std_logic_vector(ADDR-1 downto 0);
	-- variable Arr_Hot : str_arr;
-- begin
	-- Arr_Hot(0) := std_var;
	-- ---- Inverse One-Hot Encoding ----
	-- for jj in 0 to ADDR-2 loop
		-- Tmp_Std(Tmp_Std'left-1 downto 0) := Arr_Hot(jj)(Tmp_Std'left downto 1); 
		-- Tmp_Std(Tmp_Std'left) := Arr_Hot(jj)(0);
		
		-- Arr_Hot(jj+1) := Tmp_Std;
	-- end loop;
	-- return Arr_Hot; 
-- end function;

---------------- Calculate bit position for counter reset --------
function hi_bits(mode : boolean) return int_arr is
	variable Arr_Hot : int_arr;
begin
	Arr_Hot(0) := ADDR-1;
	Arr_Hot(1) := ADDR-1;
	for jj in 2 to ADDR-1 loop
		if (mode = FALSE) then
			Arr_Hot(jj) := jj-1;
		else
			Arr_Hot(jj) := ADDR-jj;
		end if;
	end loop;
	return Arr_Hot; 
end function;


function str_array(mode, incr : boolean) return str_arr is
	variable Tmp_Std : std_logic_vector(ADDR-1 downto 0);
	variable Dat_Std : std_logic_vector(ADDR-1 downto 0);	
	variable Arr_Hot : str_arr;
begin
	if (mode = FALSE) then
		if (incr = FALSE) then
			Dat_Std :=(1 => '1', others => '0');
		else
			Dat_Std :=(0 => '1', others => '0');
		end if;
	else
		if (incr = FALSE) then
			Dat_Std :=(0 => '1', others => '0');
		else
			Dat_Std :=((ADDR-1) => '1', others => '0');
		end if;	
	end if;
	
	Arr_Hot(0) := Dat_Std;
	if (mode = FALSE) then	
		---- Inverse One-Hot Encoding ----
		for jj in 0 to ADDR-2 loop
			Tmp_Std(Tmp_Std'left-1 downto 0) := Arr_Hot(jj)(Tmp_Std'left downto 1); 
			Tmp_Std(Tmp_Std'left) := Arr_Hot(jj)(0);
			
			Arr_Hot(jj+1) := Tmp_Std;
		end loop;
	else
		for jj in 0 to ADDR-2 loop
			Tmp_Std(Tmp_Std'left downto 1) := Arr_Hot(jj)(Tmp_Std'left-1 downto 0); 
			Tmp_Std(0) := Arr_Hot(jj)(Tmp_Std'left);
			
			Arr_Hot(jj+1) := Tmp_Std;
		end loop;		
	end if;

	return Arr_Hot; 
end function;

constant STD_DEL		: str_arr:=str_array(BITREV, TRUE);
constant STD_INC		: str_arr:=str_array(BITREV, FALSE);
constant INC_BIT		: int_arr:=hi_bits(BITREV);

signal in_cnt			: integer range 0 to ADDR-1;
signal sw_cnt			: std_logic_vector(ADDR-1 downto 0);
--signal sw_str			: std_logic_vector(ADDR-1 downto 0);

signal WR_RNG			: integer range 0 to ADDR-1;
signal WR_INC			: std_logic_vector(ADDR-1 downto 0);
signal WR_DEL			: std_logic_vector(ADDR-1 downto 0);

signal WR_INZ			: std_logic_vector(ADDR-1 downto 0);

signal sw_inc			: std_logic;
signal sw_ena			: std_logic;

signal cnt_even			: std_logic_vector(ADDR-1 downto 0);
signal cnt_odd			: std_logic_vector(ADDR-1 downto 0);
signal sw_ptr			: std_logic_vector(ADDR-1 downto 0);

begin

---------------- Write Increment ---------------- 
pr_del: process(clk) is
begin
	if rising_edge(clk) then
		if (rst = '1') then
			sw_cnt <= (0 => '1', others => '0') after td;
			
			in_cnt <= 1 after td;
			WR_INC <= STD_INC(0) after td;
			WR_DEL <= STD_DEL(0) after td;
			WR_RNG <= INC_BIT(0) after td;
		else
			if (dt_en01 = '1') then				
				---- Counter for WR0 / WR1 ----
				if (sw_cnt(sw_cnt'left) = '1') then
					sw_cnt <= (0 => '1', others => '0') after td;
				else
					sw_cnt <= sw_cnt + '1' after td;
				end if;					
				
				---- Counter for Arrays ----
				if (sw_cnt(sw_cnt'left) = '1') then	
					if (in_cnt = (ADDR-1)) then
						in_cnt <= 0 after td;
					else
						in_cnt <= in_cnt + 1 after td;
					end if;
					WR_INC <= STD_INC(in_cnt) after td;
					WR_DEL <= STD_DEL(in_cnt) after td;
					WR_RNG <= INC_BIT(in_cnt) after td;
				end if;						
			end if;	
			sw_inc <= sw_cnt(sw_cnt'left) after td;
		end if;
	end if;
end process;

WR_INZ <= WR_INC after td when rising_edge(clk);

---------------- Write Counters ---------------- 
pr_wr: process(clk) is
begin
	if rising_edge(clk) then
		if (rst = '1') then
			cnt_even <= (others => '0') after td;
			cnt_odd  <= WR_DEL after td;
			sw_ptr   <= (0 => '1', others => '0') after td;
			sw_ena	 <= '0' after td;
		else
			---- Find increment mux ----
			if (dt_en01 = '1') then
				if (sw_ptr(WR_RNG) = '1') then
					sw_ptr <= (0 => '1', others => '0') after td;
					sw_ena <= '1' after td;
				else
					sw_ptr <= sw_ptr + '1' after td;
					sw_ena <= '0' after td;
				end if;
			end if;
			---- Find address counter ----
			if (dt_ena = '1') then		
				if (sw_inc = '1') then
					cnt_even <= (others => '0') after td;
					cnt_odd  <= WR_DEL after td;
				else
					---- Write Counter ----
					if (sw_ena = '1') then
						cnt_even <= cnt_even + WR_INZ + 1 after td;
						cnt_odd  <= cnt_odd  + WR_INZ + 1 after td;
					else
						cnt_even <= cnt_even + WR_INZ after td;
						cnt_odd  <= cnt_odd  + WR_INZ after td;
					end if;	
				end if;	
			end if;
		end if;
	end if;
end process;

---------------- Read 1st ----------------
pr_pr1st: process(clk)
begin
    if (clk'event and clk='1') then
		if (rst = '1') then
			rd_1st <= '0' after td;
			--sw_str <= (0 => '1', others => '0');
		else

			---- Find increment mux ----
			--if (dt_en01 = '1') then
			--	if (sw_str(WR_RNG) = '0') then
			--		sw_str <= sw_str + '1' after td;
			--	end if;
			--end if;

			if (sw_ptr(sw_ptr'left) = '1') then
				rd_1st <= '1' after td;
			end if;
		end if;
	end if;
end process;

dt_ena <= dt_en01 after td when rising_edge(clk);

---- RAM 0/1 mapping ----
ram_dia <= dt_int0 after td when rising_edge(clk);
ram_dib <= dt_int1 after td when rising_edge(clk);

ram_adra <= cnt_even; -- after td when rising_edge(clk);
ram_adrb <= cnt_odd;  -- after td when rising_edge(clk);

---- RAM WR/RD ----
pr_rdwr: process(clk)
begin
    if (clk'event and clk='1') then
		if (rst = '1') then
			ram_wr <= '0' after td;
		    ram_rd <= '0' after td;
		else
			ram_wr <= dt_en01 after td;
			ram_rd <= dt_en01 and rd_1st after td;
	    end if;	
    end if;
end process;

---- Data out ----
pr_out: process(clk)
begin
    if (clk'event and clk='1') then
		dt_rev0 <= ram_doa after td;
		dt_rev1 <= ram_dob after td;
		dt_vl01 <= ram_rdz  after td;
    end if;
end process;
ram_rdz <= ram_rd after td when rising_edge(clk);


xTDP_RAM0: entity work.ramb_tdp_one_clk2
	generic map (
	    DATA    => DATA,
	    ADDR    => ADDR
		)
	port map (
	    -- rst     => rst,
		clk     => clk,    
		-- Port A
	    a_wr    => ram_wr,
		a_addr  => ram_adra,
	    a_din   => ram_dia, 
	    a_dout  => ram_doa,
	    -- Port B
	    b_wr    => ram_wr,
		b_addr  => ram_adrb,
	    b_din   => ram_dib, 
	    b_dout  => ram_dob
	);

end iobuf_flow_int2;