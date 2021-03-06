-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Steffen Koehler
--                  Patrick Lehmann
--
-- Entity:          Synchronizes a signal vector across clock-domain boundaries
--
-- Description:
-- -------------------------------------
-- This module synchronizes a vector of bits from clock-domain ``Clock1`` to
-- clock-domain ``Clock2``. The clock-domain boundary crossing is done by a
-- change comparator, a T-FF, two synchronizer D-FFs and a reconstructive
-- XOR indicating a value change on the input. This changed signal is used
-- to capture the input for the new output. A busy flag is additionally
-- calculated for the input clock domain.
--
-- Constraints:
--   This module uses sub modules which need to be constrainted. Please
--   attend to the notes of the instantiated sub modules.
--
-- License:
-- =============================================================================
-- Copyright 2007-2015 Technische Universitaet Dresden - Germany
--										 Chair of VLSI-Design, Diagnostics and Architecture
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--		http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- =============================================================================

library IEEE;
use			IEEE.STD_LOGIC_1164.all;
use			IEEE.NUMERIC_STD.all;

library PoC;
use			PoC.utils.all;


entity sync_Vector is
  generic (
	  MASTER_BITS					: positive					:= 8;											-- number of bit to be synchronized
		SLAVE_BITS					: natural						:= 0;
		INIT								: std_logic_vector	:= x"00000000"						--
	);
  port (
		Clock1							: in	std_logic;																									-- <Clock>	input clock
		Clock2							: in	std_logic;																									-- <Clock>	output clock
		Input								: in	std_logic_vector((MASTER_BITS + SLAVE_BITS) - 1 downto 0);	-- @Clock1:	input vector
		Output							: out std_logic_vector((MASTER_BITS + SLAVE_BITS) - 1 downto 0);	-- @Clock2:	output vector
		Busy								: out	std_logic;																									-- @Clock1:	busy bit
		Changed							: out	std_logic																										-- @Clock2:	changed bit
	);
end entity;


architecture rtl of sync_Vector is
	attribute SHREG_EXTRACT				: string;

	constant INIT_I								: std_logic_vector												:= descend(INIT)((MASTER_BITS + SLAVE_BITS) - 1 downto 0);

	signal D0											: std_logic_vector((MASTER_BITS + SLAVE_BITS) - 1 downto 0)		:= INIT_I;
	signal T1											: std_logic																										:= '0';
	signal D2											: std_logic																										:= '0';
	signal D3											: std_logic																										:= '0';
	signal D4											: std_logic_vector((MASTER_BITS + SLAVE_BITS) - 1 downto 0)		:= INIT_I;

	signal Changed_Clk1						: std_logic;
	signal Changed_Clk2						: std_logic;
	signal Busy_i									: std_logic;

	-- Prevent XST from translating two FFs into SRL plus FF
	attribute SHREG_EXTRACT of D0	: signal is "NO";
	attribute SHREG_EXTRACT of T1	: signal is "NO";
	attribute SHREG_EXTRACT of D2	: signal is "NO";
	attribute SHREG_EXTRACT of D3	: signal is "NO";
	attribute SHREG_EXTRACT of D4	: signal is "NO";

	signal syncClk1_In		: std_logic;
	signal syncClk1_Out		: std_logic;
	signal syncClk2_In		: std_logic;
	signal syncClk2_Out		: std_logic;

begin

	-- input D-FF @Clock1 -> changed detection
	process(Clock1)
	begin
		if rising_edge(Clock1) then
			if (Busy_i = '0') then
				D0	<= Input;									-- delay input vector for change detection; gated by busy flag
				T1	<= T1 xor Changed_Clk1;		-- toggle T1 if input vector has changed
			end if;
		end if;
	end process;

	-- D-FF for level change detection (both edges)
	process(Clock2)
	begin
		if rising_edge(Clock2) then
			D2		<= syncClk2_Out;
			D3		<= Changed_Clk2;

			if (Changed_Clk2 = '1') then
				D4	<= D0;
			end if;
		end if;
	end process;

	-- assign syncClk*_In signals
	syncClk2_In		<= T1;
	syncClk1_In		<= D2;

	Changed_Clk1	<='0' when (D0(MASTER_BITS - 1 downto 0) = Input(MASTER_BITS - 1 downto 0)) else '1';		-- input change detection
	Changed_Clk2	<= syncClk2_Out xor D2;							-- level change detection; restore strobe signal from flag
	Busy_i				<= T1 xor syncClk1_Out;							-- calculate busy signal

	-- output signals
	Output				<= D4;
	Busy					<= Busy_i;
	Changed				<= D3;

	syncClk2 : entity PoC.sync_Bits
		port map (
			Clock				=> Clock2,				-- <Clock>	output clock domain
			Input(0)		=> syncClk2_In,		-- @async:	input bits
			Output(0)		=> syncClk2_Out		-- @Clock:	output bits
		);

	syncClk1 : entity PoC.sync_Bits
		port map (
			Clock				=> Clock1,				-- <Clock>	output clock domain
			Input(0)		=> syncClk1_In,		-- @async:	input bits
			Output(0)		=> syncClk1_Out		-- @Clock:	output bits
		);
end;
