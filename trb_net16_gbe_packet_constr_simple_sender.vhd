LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;
use IEEE.std_logic_arith.all;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

entity trb_net16_gbe_packet_constr is
port(
	RESET                   : in    std_logic;
	CLK                     : in    std_logic;
	MULT_EVT_ENABLE_IN      : in    std_logic;  -- gk 06.10.10
	-- ports for user logic
	PC_WR_EN_IN             : in    std_logic; -- write into queueConstr from userLogic
	PC_DATA_IN              : in    std_logic_vector(7 downto 0);
	PC_READY_OUT            : out   std_logic;
	PC_START_OF_SUB_IN      : in    std_logic;  -- CHANGED TO SLOW CONTROL PULSE
	PC_END_OF_SUB_IN        : in    std_logic;  -- gk 07.10.10
	PC_END_OF_DATA_IN       : in    std_logic;
	PC_TRANSMIT_ON_OUT	: out	std_logic;
	-- queue and subevent layer headers
	PC_SUB_SIZE_IN          : in    std_logic_vector(31 downto 0); -- store and swap
	PC_PADDING_IN           : in    std_logic;  -- gk 29.03.10
	PC_DECODING_IN          : in    std_logic_vector(31 downto 0); -- swap
	PC_EVENT_ID_IN          : in    std_logic_vector(31 downto 0); -- swap
	PC_TRIG_NR_IN           : in    std_logic_vector(31 downto 0); -- store and swap!
	PC_QUEUE_DEC_IN         : in    std_logic_vector(31 downto 0); -- swap
	PC_MAX_FRAME_SIZE_IN    : in	std_logic_vector(15 downto 0); -- DO NOT SWAP
	PC_DELAY_IN             : in	std_logic_vector(31 downto 0);  -- gk 28.04.10
	-- FrameConstructor ports
	TC_WR_EN_OUT            : out   std_logic;
	TC_DATA_OUT             : out   std_logic_vector(7 downto 0);
	TC_H_READY_IN           : in    std_logic;
	TC_READY_IN             : in    std_logic;
	TC_IP_SIZE_OUT          : out   std_logic_vector(15 downto 0);
	TC_UDP_SIZE_OUT         : out   std_logic_vector(15 downto 0);
	TC_FLAGS_OFFSET_OUT     : out   std_logic_vector(15 downto 0);
	TC_SOD_OUT              : out   std_logic;
	TC_EOD_OUT              : out   std_logic;
	DEBUG_OUT               : out   std_logic_vector(63 downto 0)
);
end trb_net16_gbe_packet_constr;

architecture trb_net16_gbe_packet_constr of trb_net16_gbe_packet_constr is

-- attribute HGROUP : string;
-- attribute HGROUP of trb_net16_gbe_packet_constr : architecture  is "GBE_packet_constr";

component fifo_64kx9
port (
	Data        : in  std_logic_vector(8 downto 0); 
	WrClock     : in  std_logic; 
	RdClock     : in  std_logic; 
	WrEn        : in  std_logic; 
	RdEn        : in  std_logic; 
	Reset       : in  std_logic; 
	RPReset     : in  std_logic; 
	Q           : out  std_logic_vector(8 downto 0); 
	Empty       : out  std_logic; 
	Full        : out  std_logic
);
end component;

-- FIFO for SubEventHeader information
component fifo_16kx8 is
port (
	Data    : in    std_logic_vector(7 downto 0); 
	WrClock : in    std_logic; 
	RdClock : in    std_logic; 
	WrEn    : in    std_logic; 
	RdEn    : in    std_logic; 
	Reset   : in    std_logic; 
	RPReset : in    std_logic; 
	Q       : out   std_logic_vector(7 downto 0); 
	Empty   : out   std_logic; 
	Full    : out   std_logic
);
end component;

signal df_wr_en             : std_logic;
signal df_rd_en             : std_logic;
signal df_q                 : std_logic_vector(7 downto 0);
signal df_q_reg             : std_logic_vector(7 downto 0);
signal df_empty             : std_logic;
signal df_full              : std_logic;

signal fc_data              : std_logic_vector(7 downto 0);
signal fc_wr_en             : std_logic;
signal fc_sod               : std_logic;
signal fc_eod               : std_logic;
signal fc_ident             : std_logic_vector(15 downto 0); -- change this to own counter!
signal fc_flags_offset      : std_logic_vector(15 downto 0);

signal shf_data             : std_logic_vector(7 downto 0);
signal shf_wr_en            : std_logic;
signal shf_rd_en            : std_logic;
signal shf_q                : std_logic_vector(7 downto 0);
signal shf_empty            : std_logic;
signal shf_full             : std_logic;

type constructStates        is  (CIDLE, SAVE_DATA, WAIT_FOR_LOAD);
signal constructCurrentState, constructNextState : constructStates;
signal constr_state         : std_logic_vector(3 downto 0);
signal all_int_ctr          : integer range 0 to 31;
signal all_ctr              : std_logic_vector(4 downto 0);

type saveSubStates      is  (SIDLE, SAVE_SIZE, SAVE_DECODING, SAVE_ID, SAVE_TRIG_NR, SAVE_TERM);
signal saveSubCurrentState, saveSubNextState : saveSubStates;
signal save_state           : std_logic_vector(3 downto 0);
signal sub_int_ctr          : integer range 0 to 31;
signal sub_ctr              : std_logic_vector(4 downto 0);
signal my_int_ctr			: integer range 0 to 3;
signal my_ctr               : std_logic_vector(1 downto 0);

type loadStates         is  (LIDLE, WAIT_FOR_FC, PUT_Q_LEN, PUT_Q_DEC, LOAD_SUB, PREP_DATA, LOAD_DATA, DIVIDE, LOAD_TERM, CLEANUP, DELAY);
signal loadCurrentState, loadNextState: loadStates;
signal load_state           : std_logic_vector(3 downto 0);

signal queue_size           : std_logic_vector(31 downto 0); -- sum of all subevents sizes plus their headers and queue headers and termination
signal queue_size_temp      : std_logic_vector(31 downto 0);
signal actual_queue_size    : std_logic_vector(31 downto 0); -- queue size used during loading process when queue_size is no more valid
signal bytes_loaded         : std_logic_vector(15 downto 0); -- size of actual constructing frame
signal sub_size_to_save     : std_logic_vector(31 downto 0); -- size of subevent to save to shf
signal sub_size_loaded      : std_logic_vector(31 downto 0); -- size of subevent actually being transmitted
signal sub_bytes_loaded     : std_logic_vector(31 downto 0); -- amount of bytes of actual subevent sent 
signal actual_packet_size   : std_logic_vector(15 downto 0); -- actual size of whole udp packet
signal size_left            : std_logic_vector(31 downto 0);
signal fc_ip_size           : std_logic_vector(15 downto 0);
signal fc_udp_size          : std_logic_vector(15 downto 0);
signal max_frame_size       : std_logic_vector(15 downto 0);
signal divide_position      : std_logic_vector(1 downto 0); -- 00->data, 01->sub, 11->term
signal debug                : std_logic_vector(63 downto 0);
signal pc_ready             : std_logic;

signal pc_sub_size          : std_logic_vector(31 downto 0);
signal pc_trig_nr           : std_logic_vector(31 downto 0);
signal rst_after_sub_comb   : std_logic;  -- gk 08.04.10
signal rst_after_sub        : std_logic;  -- gk 08.04.10
signal load_int_ctr         : integer range 0 to 3;  -- gk 08.04.10
signal delay_ctr            : std_logic_vector(31 downto 0);  -- gk 28.04.10
signal ticks_ctr            : std_logic_vector(7 downto 0);  -- gk 28.04.10

-- gk 26.07.10
signal load_eod             : std_logic;
signal load_eod_q           : std_logic;

-- gk 07.10.10
signal df_eod               : std_logic;

-- gk 04.12.10
signal first_sub_in_multi   : std_logic;
signal from_divide_state    : std_logic;
signal disable_prep         : std_logic;

-- gk 02.08.11
type constructSimpleFrameStates is (IDLE, WAIT_FOR_HEADERS, PUT_DATA, FINISH);
signal constrSimpleFrameCurrentState, constrSimpleFrameNextState : constructSimpleFrameStates;

signal gen_data_ctr : std_logic_vector(15 downto 0);


begin

costrSimpleFrameMachineProc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			constrSimpleFrameCurrentState <= IDLE;
		else
			constrSimpleFrameCurrentState <= constrSimpleFrameNextState;
		end if;
	end if;
end process costrSimpleFrameMachineProc;

constrSimpleFrameMachine : process(constrSimpleFrameCurrentState, PC_START_OF_SUB_IN, TC_H_READY_IN, gen_data_ctr, TC_READY_IN)
begin
	case constrSimpleFrameCurrentState is
	
		when IDLE =>
			if (PC_START_OF_SUB_IN = '1') then
				constrSimpleFrameNextState <= WAIT_FOR_HEADERS;
			else
				constrSimpleFrameNextState <= IDLE;
			end if;
		
		when WAIT_FOR_HEADERS =>
			if (TC_H_READY_IN = '1') then
				constrSimpleFrameNextState <= PUT_DATA;
			else
				constrSimpleFrameNextState <= WAIT_FOR_HEADERS;
			end if;
		
		when PUT_DATA =>
			if (gen_data_ctr = x"0100") then
				constrSimpleFrameNextState <= FINISH;
			else
				constrSimpleFrameNextState <= PUT_DATA;
			end if;
		
		when FINISH =>
			if (TC_READY_IN = '1') then
				constrSimpleFrameNextState <= IDLE;
			else
				constrSimpleFrameNextState <= FINISH;
			end if;
	
	end case;
end process constrSimpleFrameMachine;

GEN_DATA_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (constrSimpleFrameCurrentState = IDLE) then
			gen_data_ctr <= (others => '0');
		elsif (constrSimpleFrameCurrentState = PUT_DATA) then
			gen_data_ctr <= gen_data_ctr + x"1";
		end if;
	end if;
end process;

TC_DATA_OUT <= gen_data_ctr(7 downto 0);
TC_WR_EN_OUT <= '1' when constrSimpleFrameCurrentState = PUT_DATA else '0';
TC_SOD_OUT <= '1' when (constrSimpleFrameCurrentState = IDLE and PC_START_OF_SUB_IN = '1') or (constrSimpleFrameCurrentState = WAIT_FOR_HEADERS and TC_H_READY_IN = '0') else '0';
TC_EOD_OUT <= '1' when constrSimpleFrameCurrentState = PUT_DATA and gen_data_ctr = x"0100" else '0';
PC_READY_OUT <= '1' when constrSimpleFrameCurrentState = IDLE else '0';
PC_TRANSMIT_ON_OUT <= '0' when constrSimpleFrameCurrentState = IDLE and PC_START_OF_SUB_IN = '0' else '1';
TC_IP_SIZE_OUT <= x"0100";
TC_UDP_SIZE_OUT <= x"0100";

--PC_TRANSMIT_ON_OUT <= '1' when constructCurrentState = WAIT_FOR_LOAD else '0';
--PC_TRANSMIT_ON_OUT <= '0';

-- my_int_ctr <= (3 - to_integer(to_unsigned(sub_int_ctr, 2))); -- reverse byte order
-- load_int_ctr <= (3 - to_integer(to_unsigned(all_int_ctr, 2)));  -- gk 08.04.10
-- 
-- all_ctr <= std_logic_vector(to_unsigned(all_int_ctr, all_ctr'length)); -- for debugging
-- sub_ctr <= std_logic_vector(to_unsigned(sub_int_ctr, sub_ctr'length)); -- for debugging
-- my_ctr  <= std_logic_vector(to_unsigned(my_int_ctr, my_ctr'length)); -- for debugging
-- 
-- max_frame_size <= PC_MAX_FRAME_SIZE_IN;
-- 
-- -- Ready signal for PacketConstructor
-- pc_ready <= '1' when (constructCurrentState = CIDLE) and (df_empty = '1') else '0';
pc_ready <= '0';

-- store event information on Start_of_Subevent
-- THE_EVT_INFO_STORE_PROC: process( CLK )
-- begin
-- 	if( rising_edge(CLK) ) then
-- 		if (RESET = '1') then  -- gk 31.05.10
-- 			pc_sub_size <= (others => '0');
-- 			pc_trig_nr <= (others => '0');
-- 		elsif( PC_START_OF_SUB_IN = '1' ) then
-- 			pc_sub_size <= PC_SUB_SIZE_IN;
-- 			pc_trig_nr  <= PC_TRIG_NR_IN;
-- 		end if;
-- 	end if;
-- end process;
-- 
-- -- gk 07.10.10
-- df_eod <= '1' when ((MULT_EVT_ENABLE_IN = '0') and (PC_END_OF_DATA_IN = '1'))
-- 			or ((MULT_EVT_ENABLE_IN = '1') and (PC_END_OF_SUB_IN = '1'))
-- 			else '0';

-- Data FIFO for incoming packet data from IPU buffer
-- gk 26.07.10
-- DATA_FIFO : fifo_64kx9
-- port map(
-- 	Data(7 downto 0) =>  PC_DATA_IN,
-- 	Data(8)          =>  df_eod, --PC_END_OF_DATA_IN, -- gk 07.10.10
-- 	WrClock          =>  CLK,
-- 	RdClock          =>  CLK,
-- 	WrEn             =>  df_wr_en,
-- 	RdEn             =>  df_rd_en,
-- 	Reset            =>  RESET,
-- 	RPReset          =>  RESET,
-- 	Q(7 downto 0)    =>  df_q,
-- 	Q(8)             =>  load_eod,
-- 	Empty            =>  df_empty,
-- 	Full             =>  df_full
-- );

-- LOAD_EOD_PROC : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			load_eod_q <= '0';
-- 		else
-- 			load_eod_q <= load_eod;
-- 		end if;
-- 	end if;
-- end process LOAD_EOD_PROC;
-- 
-- -- Write enable for the data FIFO
-- -- !!!combinatorial signal!!!
-- -- could be avoided as IPU2GBE does only send data in case of PC_READY.
-- df_wr_en <= '1' when ((PC_WR_EN_IN = '1') and (constructCurrentState /= WAIT_FOR_LOAD)) 
-- 				else '0';
-- 
-- -- Output register for data FIFO
-- dfQProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		df_q_reg <= df_q;
-- 	end if;
-- end process dfQProc;
-- 
-- -- Construction state machine
-- constructMachineProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			constructCurrentState <= CIDLE;
-- 		else
-- 			constructCurrentState <= constructNextState;
-- 		end if;
-- 	end if;
-- end process constructMachineProc;
-- 
-- constructMachine : process(constructCurrentState, PC_START_OF_SUB_IN, PC_WR_EN_IN, PC_END_OF_DATA_IN, loadCurrentState, saveSubCurrentState, sub_int_ctr)
-- begin
-- 	case constructCurrentState is
-- 		when CIDLE =>
-- 			constr_state <= x"0";
-- 			--if( PC_WR_EN_IN = '1' ) then
-- 			-- gk 04.12.10
-- 			if (PC_START_OF_SUB_IN = '1') then
-- 
-- 				constructNextState <= SAVE_DATA;
-- 			else
-- 				constructNextState <= CIDLE;
-- 			end if;
-- 		when SAVE_DATA =>
-- 			constr_state <= x"1";
-- 			if( PC_END_OF_DATA_IN = '1' ) then
-- 				constructNextState <= WAIT_FOR_LOAD;
-- 			else
-- 				constructNextState <= SAVE_DATA;
-- 			end if;
-- 		when WAIT_FOR_LOAD =>
-- 			constr_state <= x"2";
-- 			if( (df_empty = '1') and (loadCurrentState = LIDLE) ) then -- waits until the whole packet is transmitted
-- 				constructNextState <= CIDLE;
-- 			else
-- 				constructNextState <= WAIT_FOR_LOAD;
-- 			end if;
-- 		when others =>
-- 			constr_state <= x"f";
-- 			constructNextState <= CIDLE;
-- 	end case;
-- end process constructMachine;

--***********************
--      SIZE COUNTERS FOR SAVING SIDE
--***********************

-- gk 29.03.10 the subevent size saved to its headers cannot contain padding bytes but they are included in pc_sub_size
-- that's why they are removed if pc_padding flag is asserted
-- sub_size_to_save <= (x"10" + pc_sub_size) when (PC_PADDING_IN = '0')
-- 			else (x"c" + pc_sub_size); -- subevent headers + data
-- 
-- -- BUG HERE BUG HERE BUG HERE BUG HERE
-- -- gk 29.03.10 no changes here because the queue size should contain the padding bytes of subevents
-- queueSizeProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		--if (RESET = '1') or (loadCurrentState = PUT_Q_DEC) then -- gk 07.10.10 -- (loadCurrentState = CLEANUP) then
-- 		if (RESET = '1') or (loadCurrentState = CLEANUP) then
-- 			queue_size <= x"00000028";  -- + 8B for queue headers and 32B for termination
-- 		elsif (saveSubCurrentState = SAVE_SIZE) and (sub_int_ctr = 3) then
-- 			queue_size <= queue_size + pc_sub_size + x"10"; -- + 16B for each subevent headers
-- 		end if;
-- 	end if;
-- end process queueSizeProc;


--***********************
--      LOAD DATA COMBINED WITH HEADERS INTO FC, QUEUE TRANSMISSION
--***********************

-- loadMachineProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			loadCurrentState <= LIDLE;
-- 		else
-- 			loadCurrentState <= loadNextState;
-- 		end if;
-- 	end if;
-- end process loadMachineProc;
-- 
-- loadMachine : process(loadCurrentState, constructCurrentState, all_int_ctr, df_empty,
-- 					sub_bytes_loaded, sub_size_loaded, size_left, TC_H_READY_IN,
-- 					max_frame_size, bytes_loaded, divide_position, PC_DELAY_IN,
-- 					delay_ctr, load_eod_q, MULT_EVT_ENABLE_IN)
-- begin
-- 	case loadCurrentState is
-- 		when LIDLE =>
-- 			load_state <= x"0";
-- 			if ((constructCurrentState = WAIT_FOR_LOAD) and (df_empty = '0')) then
-- 				loadNextState <= WAIT_FOR_FC;
-- 			else
-- 				loadNextState <= LIDLE;
-- 			end if;
-- 		when WAIT_FOR_FC =>
-- 			load_state <= x"1";
-- 			if (TC_H_READY_IN = '1') then
-- 				loadNextState <= PUT_Q_LEN;
-- 			else
-- 				loadNextState <= WAIT_FOR_FC;
-- 			end if;
-- 		when PUT_Q_LEN =>
-- 			load_state <= x"2";
-- 			if (all_int_ctr = 3) then
-- 				loadNextState <= PUT_Q_DEC;
-- 			else
-- 				loadNextState <= PUT_Q_LEN;
-- 			end if;
-- 		when PUT_Q_DEC =>
-- 			load_state <= x"3";
-- 			if (all_int_ctr = 3) then
-- 				loadNextState <= LOAD_SUB;
-- 			else
-- 				loadNextState <= PUT_Q_DEC;
-- 			end if;
-- 		when LOAD_SUB =>
-- 			load_state <= x"4";
-- 			if (bytes_loaded = max_frame_size - 1) then
-- 				loadNextState <= DIVIDE;
-- 			elsif (all_int_ctr = 15) then
-- 				loadNextState <= PREP_DATA;
-- 			else
-- 				loadNextState <= LOAD_SUB;
-- 			end if;
-- 		when PREP_DATA =>
-- 			load_state <= x"5";
-- 			loadNextState <= LOAD_DATA;
-- 		when LOAD_DATA =>
-- 			load_state <= x"6";
-- -- 			if (bytes_loaded = max_frame_size - 1) then
-- -- 				loadNextState <= DIVIDE;
-- -- 			-- gk 07.10.10
-- -- 			elsif (MULT_EVT_ENABLE_IN = '1') then
-- -- 				if (size_left = x"0000_0023") then
-- -- 					loadNextState <= LOAD_TERM;
-- -- 				elsif (load_eod_q = '1') then
-- -- 					loadNextState <= LOAD_SUB;
-- -- 				else
-- -- 					loadNextState <= LOAD_DATA;
-- -- 				end if;
-- -- 			else
-- -- 				if (load_eod_q = '1') then
-- -- 					loadNextState <= LOAD_TERM;
-- -- 				else
-- -- 					loadNextState <= LOAD_DATA;
-- -- 				end if;
-- -- 			end if;
-- 			if (bytes_loaded = max_frame_size - 1) then
-- 				loadNextState <= DIVIDE;
-- 			-- gk 07.10.10
-- 			elsif (load_eod_q = '1') then
-- 				if (MULT_EVT_ENABLE_IN = '1') then
-- 					if (size_left < x"0000_0030") then
-- 						loadNextState <= LOAD_TERM;
-- 					else
-- 						loadNextState <= LOAD_SUB;
-- 					end if;
-- 				else
-- 					loadNextState <= LOAD_TERM;
-- 				end if;
-- 			else
-- 				loadNextState <= LOAD_DATA;
-- 			end if;
-- 		when DIVIDE =>
-- 			load_state <= x"7";
-- 			if (TC_H_READY_IN = '1') then
-- 				if (divide_position = "00") then
-- 					loadNextState <= PREP_DATA;
-- 				elsif (divide_position = "01") then
-- 					loadNextState <= LOAD_SUB;
-- 				else
-- 					loadNextState <= LOAD_TERM;
-- 				end if;
-- 			else
-- 				loadNextState <= DIVIDE;
-- 			end if;
-- 		when LOAD_TERM =>
-- 			load_state <= x"8";
-- 			if (bytes_loaded = max_frame_size - 1) and (all_int_ctr /= 31) then
-- 				loadNextState <= DIVIDE;
-- 			elsif (all_int_ctr = 31) then
-- 				loadNextState <= CLEANUP;
-- 			else
-- 				loadNextState <= LOAD_TERM;
-- 			end if;
-- 		-- gk 28.04.10
-- 		when CLEANUP =>
-- 			load_state <= x"9";
-- 			if (PC_DELAY_IN = x"0000_0000") then
-- 				loadNextState <= LIDLE;
-- 			else
-- 				loadNextState <= DELAY;
-- 			end if;
-- 		-- gk 28.04.10
-- 		when DELAY =>
-- 			load_state <= x"a";
-- 			if (delay_ctr = x"0000_0000") then
-- 				loadNextState <= LIDLE;
-- 			else
-- 				loadNextState <= DELAY;
-- 			end if;
-- 		when others =>
-- 			load_state <= x"f";
-- 			loadNextState <= LIDLE;
-- 	end case;
-- end process loadMachine;
-- 
-- -- gk 04.12.10
-- firstSubInMultiProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = LOAD_TERM) then
-- 			first_sub_in_multi <= '1';
-- 		elsif (loadCurrentState = LOAD_DATA) then
-- 			first_sub_in_multi <= '0';
-- 		end if;
-- 	end if;
-- end process;
-- 
-- -- gk 04.12.10
-- fromDivideStateProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			from_divide_state <= '0';
-- 		elsif (loadCurrentState = DIVIDE) then
-- 			from_divide_state <= '1';
-- 		elsif (loadCurrentState = PREP_DATA) then
-- 			from_divide_state <= '0';
-- 		end if;
-- 	end if;
-- end process fromDivideStateProc;
-- 
-- 
-- dividePositionProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			divide_position <= "00";
-- -- 		elsif (bytes_loaded = max_frame_size - 1) then
-- -- 			if (loadCurrentState = LIDLE) then
-- -- 				divide_position <= "00";
-- -- 			elsif (loadCurrentState = LOAD_DATA) then
-- -- 				-- gk 07.10.10
-- -- 				if (MULT_EVT_ENABLE_IN = '1') and (size_left = x"0000_003a") then
-- -- 					divide_position <= "11";
-- -- 				-- gk 07.10.10
-- -- 				elsif (MULT_EVT_ENABLE_IN = '1') and (load_eod_q = '1') then
-- -- 					divide_position <= "01";
-- -- 				-- gk 26.07.10
-- -- 				elsif (MULT_EVT_ENABLE_IN = '0') and (load_eod_q = '1') then -- if termination is about to be loaded divide on term
-- -- 					divide_position <= "11";
-- -- 				else
-- -- 					divide_position <= "00"; -- still data loaded divide on data
-- -- 				end if;
-- -- 			elsif (loadCurrentState = LOAD_SUB) then
-- -- 				if (all_int_ctr = 15) then
-- -- 					divide_position <= "00";
-- -- 				else
-- -- 					divide_position <= "01";
-- -- 				end if;
-- -- 			elsif (loadCurrentState = LOAD_TERM) then
-- -- 				divide_position <= "11";
-- -- 			end if;
-- -- 		end if;
-- 		elsif (bytes_loaded = max_frame_size - 1) then
-- 			if (loadCurrentState = LIDLE) then
-- 				divide_position <= "00";
-- 				disable_prep    <= '0';  -- gk 05.12.10
-- 			elsif (loadCurrentState = LOAD_DATA) then
-- 				-- gk 05.12.10
-- 				-- gk 26.07.10
-- 				if (MULT_EVT_ENABLE_IN = '0') and (load_eod_q = '1') then -- if termination is about to be loaded divide on term
-- 					divide_position <= "11";
-- 					disable_prep    <= '0';  -- gk 05.12.10
-- 				elsif (MULT_EVT_ENABLE_IN = '1') and (load_eod_q = '1') then
-- 					if (size_left > x"0000_0028") then
-- 						divide_position <= "01";
-- 						disable_prep    <= '0';  -- gk 05.12.10
-- 					else
-- 						divide_position <= "11";
-- 						disable_prep    <= '0';  -- gk 05.12.10
-- 					end if;
-- 				else
-- 					divide_position <= "00"; -- still data loaded divide on data
-- 					disable_prep    <= '1';  -- gk 05.12.10
-- 				end if;
-- 			elsif (loadCurrentState = LOAD_SUB) then
-- 				if (all_int_ctr = 15) then
-- 					divide_position <= "00";
-- 					disable_prep    <= '1';  -- gk 05.12.10
-- 				else
-- 					divide_position <= "01";
-- 					disable_prep    <= '0';  -- gk 05.12.10
-- 				end if;
-- 			elsif (loadCurrentState = LOAD_TERM) then
-- 				divide_position <= "11";
-- 				disable_prep    <= '0';  -- gk 05.12.10
-- 			end if;
-- 		elsif (loadCurrentState = PREP_DATA) then  -- gk 06.12.10 reset disable_prep
-- 			disable_prep <= '0';
-- 		end if;
-- 
-- 	end if;
-- end process dividePositionProc;
-- 
-- allIntCtrProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then  -- gk 31.05.10
-- 			all_int_ctr <= 0;
-- 		else
-- 			case loadCurrentState is
-- 	
-- 				when LIDLE => all_int_ctr <= 0;
-- 	
-- 				when WAIT_FOR_FC => all_int_ctr <= 0;
-- 	
-- 				when PUT_Q_LEN =>
-- 					if (all_int_ctr = 3) then
-- 						all_int_ctr <= 0;
-- 					else
-- 						all_int_ctr <= all_int_ctr + 1;
-- 					end if;
-- 	
-- 				when PUT_Q_DEC =>
-- 					if (all_int_ctr = 3) then
-- 						all_int_ctr <= 0;
-- 					else
-- 						all_int_ctr <= all_int_ctr + 1;
-- 					end if;
-- 	
-- 				when LOAD_SUB =>
-- 					if (all_int_ctr = 15) then
-- 						all_int_ctr <= 0;
-- 					else
-- 						all_int_ctr <= all_int_ctr + 1;
-- 					end if;
-- 	
-- 				when LOAD_DATA => all_int_ctr <= 0;
-- 	
-- 				when LOAD_TERM =>
-- 					if (all_int_ctr = 31) then
-- 						all_int_ctr <= 0;
-- 					else
-- 						all_int_ctr <= all_int_ctr + 1;
-- 					end if;
-- 	
-- 				when DIVIDE => null;
-- 	
-- 				when CLEANUP => all_int_ctr <= 0;
-- 	
-- 				when PREP_DATA => all_int_ctr <= 0;
-- 	
-- 				when DELAY => all_int_ctr <= 0;
-- 			end case;
-- 		end if;
-- 	end if;
-- end process allIntCtrProc;
-- 
-- dfRdEnProc : process(loadCurrentState, bytes_loaded, max_frame_size, sub_bytes_loaded, 
-- 					 sub_size_loaded, all_int_ctr, RESET, size_left, load_eod_q)
-- begin
-- 	if (RESET = '1') then
-- 		df_rd_en <= '0';
-- 	elsif (loadCurrentState = LOAD_DATA) then
-- -- 		if (bytes_loaded = max_frame_size - x"1") then
-- -- 			df_rd_en <= '0';
-- -- 		-- gk 07.10.10
-- -- 		elsif (MULT_EVT_ENABLE_IN = '0') and (load_eod_q = '1') then
-- -- 			df_rd_en <= '0';
-- -- 		-- gk 07.10.10
-- -- 		elsif (MULT_EVT_ENABLE_IN = '1') and (size_left = x"0000_003a") then
-- -- 			df_rd_en <= '0';
-- -- 		else
-- -- 			df_rd_en <= '1';
-- -- 		end if;
-- 		if (bytes_loaded = max_frame_size - x"1") then
-- 			df_rd_en <= '0';
-- 		-- gk 26.07.10
-- 		--elsif (load_eod = '1') or (load_eod_q = '1') then
-- 		elsif (load_eod_q = '1') then
-- 			df_rd_en <= '0';
-- --		elsif (sub_bytes_loaded = sub_size_loaded) then
-- --			df_rd_en <= '0';
-- 		else
-- 			df_rd_en <= '1';
-- 		end if;
-- 
-- 	elsif (loadCurrentState = LOAD_SUB) and (all_int_ctr = 15) and (bytes_loaded /= max_frame_size - x"1") then
-- 		df_rd_en <= '1';
-- 	elsif (loadCurrentState = PREP_DATA) then
-- 		df_rd_en <= '1';
-- 	else
-- 		df_rd_en <= '0';
-- 	end if;
-- end process dfRdEnProc;
-- 
-- shfRdEnProc : process(loadCurrentState, all_int_ctr, RESET)
-- begin
-- 	if (RESET = '1') then  -- gk 31.05.10
-- 		shf_rd_en <= '0';
-- 	elsif (loadCurrentState = LOAD_SUB) then
-- 		shf_rd_en <= '1';
-- 	elsif (loadCurrentState = LOAD_TERM) and (all_int_ctr < 31) then
-- 		shf_rd_en <= '1';
-- 	elsif (loadCurrentState = PUT_Q_DEC) and (all_int_ctr = 3) then
-- 		shf_rd_en <= '1';
-- 	else
-- 		shf_rd_en <= '0';
-- 	end if;
-- end process shfRdEnProc;
-- 
-- 
-- -- fcWrEnProc : process(loadCurrentState, RESET)
-- -- begin
-- -- 	if (RESET = '1') then  -- gk 31.05.10
-- -- 		fc_wr_en <= '0';
-- -- 	elsif (loadCurrentState = PUT_Q_LEN) or (loadCurrentState = PUT_Q_DEC) then
-- -- 		fc_wr_en <= '1';
-- -- 	elsif (loadCurrentState = LOAD_SUB) or (loadCurrentState = LOAD_DATA) or (loadCurrentState = LOAD_TERM) then
-- -- 		fc_wr_en <= '1';
-- -- 	else
-- -- 		fc_wr_en <= '0';
-- -- 	end if;
-- -- end process fcWrEnProc;
-- fcWrEnProc : process(loadCurrentState, RESET, first_sub_in_multi, from_divide_state, MULT_EVT_ENABLE_IN, divide_position, disable_prep)
-- begin
-- 	if (RESET = '1') then  -- gk 31.05.10
-- 		fc_wr_en <= '0';
-- 	elsif (loadCurrentState = PUT_Q_LEN) or (loadCurrentState = PUT_Q_DEC) then
-- 		fc_wr_en <= '1';
-- 	elsif (loadCurrentState = LOAD_SUB) or (loadCurrentState = LOAD_DATA) or (loadCurrentState = LOAD_TERM) then
-- 		fc_wr_en <= '1';
-- 	-- gk 04.12.10
-- 	elsif (MULT_EVT_ENABLE_IN = '1') and (loadCurrentState = PREP_DATA) and (first_sub_in_multi = '0') and (from_divide_state = '0') and (disable_prep = '0') then
-- 		fc_wr_en <= '1';
-- 	elsif (MULT_EVT_ENABLE_IN = '1') and (loadCurrentState = PREP_DATA)  and (from_divide_state = '1') and ((divide_position = "00") or (divide_position = "01")) and (disable_prep = '0') then
-- 		fc_wr_en <= '1';
-- 	else
-- 		fc_wr_en <= '0';
-- 	end if;
-- end process fcWrEnProc;
-- 
-- 
-- -- was all_int_ctr
-- fcDataProc : process(loadCurrentState, queue_size_temp, PC_QUEUE_DEC_IN, shf_q, df_q_reg, load_int_ctr)
-- begin
-- 	case loadCurrentState is
-- 		when LIDLE          =>  fc_data <=  x"af";
-- 		when WAIT_FOR_FC    =>  fc_data <=  x"bf";
-- 		-- gk 08.04.10 my_int_ctr changed to load_int_ctr
-- 		when PUT_Q_LEN      =>  fc_data <=  queue_size_temp(load_int_ctr * 8 + 7 downto load_int_ctr * 8);
-- 		when PUT_Q_DEC      =>  fc_data <=  PC_QUEUE_DEC_IN(load_int_ctr * 8 + 7 downto load_int_ctr * 8);
-- 		when LOAD_SUB       =>  fc_data <=  shf_q;
-- 		when PREP_DATA      =>  fc_data <=  df_q_reg;
-- 		when LOAD_DATA      =>  fc_data <=  df_q_reg;
-- 		when LOAD_TERM      =>  fc_data <=  shf_q;
-- 		when DIVIDE         =>  fc_data <=  x"cf";
-- 		when CLEANUP        =>  fc_data <=  x"df";
-- 		when others         =>  fc_data <=  x"00";
-- 	end case;
-- end process fcDataProc;
-- 
-- -- delay counters
-- -- gk 28.04.10
-- DELAY_CTR_PROC : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if ((RESET = '1') or (loadCurrentState = LIDLE)) then
-- 			delay_ctr <= PC_DELAY_IN;
-- 		elsif ((loadCurrentState = DELAY) and (ticks_ctr(7) = '1')) then
-- 			delay_ctr <= delay_ctr - x"1";
-- 		end if;
-- 	end if;
-- end process DELAY_CTR_PROC;
-- 
-- -- gk 28.04.10
-- TICKS_CTR_PROC : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if ((RESET = '1') or (loadCurrentState = LIDLE) or (ticks_ctr(7) = '1')) then
-- 			ticks_ctr <= x"00";
-- 		elsif (loadCurrentState = DELAY) then
-- 			ticks_ctr <= ticks_ctr + x"1";
-- 		end if;
-- 	end if;
-- end process TICKS_CTR_PROC;


--***********************
--      SIZE COUNTERS FOR LOADING SIDE
--***********************

-- queue_size_temp <= queue_size - x"20"; -- size of data without termination
-- 
-- -- gk 08.04.10
-- rst_after_sub_comb <= '1' when (loadCurrentState = LIDLE) or
-- 			((loadCurrentState = LOAD_DATA) and (size_left /= x"00000021")) -- gk 26.07.10 -- and (sub_bytes_loaded = sub_size_loaded) 
-- 			else '0';
-- 
-- -- gk 08.04.10
-- RST_AFTER_SUB_PROC : process(CLK)
-- begin
-- 	if(rising_edge(CLK)) then
-- 		if(RESET = '1') then
-- 			rst_after_sub <= '0';
-- 		else
-- 			rst_after_sub <= rst_after_sub_comb;
-- 		end if;
-- 	end if;
-- end process RST_AFTER_SUB_PROC;
-- 
-- -- counts all bytes loaded to divide data into frames
-- bytesLoadedProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = LIDLE) or (loadCurrentState = DIVIDE) or (loadCurrentState = CLEANUP) then
-- 			bytes_loaded <= x"0000";
-- 		elsif (loadCurrentState = PUT_Q_LEN) or (loadCurrentState = PUT_Q_DEC) or (loadCurrentState = LOAD_DATA) or (loadCurrentState = LOAD_SUB) or (loadCurrentState = LOAD_TERM) then
-- 			bytes_loaded <= bytes_loaded + x"1";
-- 		-- gk 05.12.10
-- -- 		elsif (MULT_EVT_ENABLE_IN = '1') and (loadCurrentState = PREP_DATA) and (first_sub_in_multi = '0') and (from_divide_state = '0') then
-- -- 			bytes_loaded <= bytes_loaded + x"1";
-- 		elsif (MULT_EVT_ENABLE_IN = '1') and (loadCurrentState = PREP_DATA) and (first_sub_in_multi = '0') and (from_divide_state = '0') and (disable_prep = '0') then
-- 			bytes_loaded <= bytes_loaded + x"1";
-- 		elsif (MULT_EVT_ENABLE_IN = '1') and (loadCurrentState = PREP_DATA)  and (from_divide_state = '1') and ((divide_position = "00") or (divide_position = "01")) and (disable_prep = '0') then
-- 			bytes_loaded <= bytes_loaded + x"1";
-- 		end if;
-- 	end if;
-- end process bytesLoadedProc;
-- 
-- -- size of subevent loaded from memory
-- subSizeLoadedProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = LIDLE) or (loadCurrentState = CLEANUP) or (rst_after_sub = '1') then  -- gk 08.04.10
-- 			sub_size_loaded <= x"00000000";
-- 		elsif (loadCurrentState = LOAD_SUB) and (all_int_ctr < 4) then
-- 			-- was all_int_ctr
-- 			-- gk 08.04.10 my_int_ctr changed to load_int_ctr
-- 			sub_size_loaded(7 + load_int_ctr * 8 downto load_int_ctr * 8) <= shf_q;
-- 		-- gk 29.03.10 here the padding bytes have to be added to the loadedSize in order to load the correct amount of bytes from fifo
-- 		elsif (loadCurrentState = LOAD_SUB) and (all_int_ctr = 5) and (sub_size_loaded(2) = '1') then
-- 			sub_size_loaded <= sub_size_loaded + x"4";
-- 		end if;
-- 	end if;
-- end process subSizeLoadedProc;
-- 
-- -- counts only raw data bytes being loaded
-- subBytesLoadedProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = LIDLE) or (loadCurrentState = CLEANUP) or (rst_after_sub = '1') then   -- gk 26.07.10 --or (sub_bytes_loaded = sub_size_loaded) -- gk 08.04.10
-- 			sub_bytes_loaded <= x"00000011";  -- subevent headers doesnt count
-- 		elsif (loadCurrentState = LOAD_DATA) then
-- 			sub_bytes_loaded <= sub_bytes_loaded + x"1";
-- 		end if;
-- 	end if;
-- end process subBytesLoadedProc;
-- 
-- -- counts the size of the large udp packet
-- actualPacketProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = LIDLE) or (loadCurrentState = CLEANUP) then
-- 			actual_packet_size <= x"0008";
-- 		elsif (fc_wr_en = '1') then
-- 			actual_packet_size <= actual_packet_size + x"1";
-- 		end if;
-- 	end if;
-- end process actualPacketProc;
-- 
-- actualQueueSizeProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = CLEANUP) then
-- 			actual_queue_size <= (others => '0');
-- 		elsif (loadCurrentState = LIDLE) then
-- 			actual_queue_size <= queue_size;
-- 		end if;
-- 	end if;
-- end process actualQueueSizeProc;
-- 
-- -- amount of bytes left to send in current packet
-- sizeLeftProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = CLEANUP) then
-- 			size_left <= (others => '0');
-- 		elsif (loadCurrentState = LIDLE) then
-- 			size_left <= queue_size;
-- 		elsif (fc_wr_en = '1') then
-- 			size_left <= size_left - 1;
-- 		end if;
-- 	end if;
-- end process sizeLeftProc;
-- 
-- -- HOT FIX: don't rely on CTS information, count the packets on your own.
-- -- In this case, we increment the fragmented packet ID with EOD from ipu2gbe.
-- THE_FC_IDENT_COUNTER_PROC: process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			fc_ident <= (others => '0');
-- 		elsif (PC_END_OF_DATA_IN = '1') then
-- 			fc_ident <= fc_ident + 1;
-- 		end if;
-- 	end if;
-- end process THE_FC_IDENT_COUNTER_PROC;
-- 
-- fc_flags_offset(15 downto 14) <= "00";
-- 
-- moreFragmentsProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = LIDLE) or (loadCurrentState = CLEANUP) then
-- 			fc_flags_offset(13) <= '0';
-- 		elsif ((loadCurrentState = DIVIDE) and (TC_READY_IN = '1')) or ((loadCurrentState = WAIT_FOR_FC) and (TC_READY_IN = '1')) then
-- 			if ((actual_queue_size - actual_packet_size) < max_frame_size) then
-- 				fc_flags_offset(13) <= '0';  -- no more fragments
-- 			else
-- 				fc_flags_offset(13) <= '1';  -- more fragments
-- 			end if;
-- 		end if;
-- 	end if;
-- end process moreFragmentsProc;
-- 
-- eodProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			fc_eod <= '0';
-- 		elsif (loadCurrentState = LOAD_DATA) and (bytes_loaded = max_frame_size - 2) then
-- 			fc_eod <= '1';
-- 		elsif (loadCurrentState = LOAD_SUB) and (bytes_loaded = max_frame_size - 2) then
-- 			fc_eod <= '1';
-- 		elsif (loadCurrentState = LOAD_TERM) and ((bytes_loaded = max_frame_size - 2) or (all_int_ctr = 30)) then
-- 			fc_eod <= '1';
-- 		else
-- 			fc_eod <= '0';
-- 		end if;
-- 	end if;
-- end process eodProc;
-- 
-- sodProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			fc_sod <= '0';
-- 		elsif (loadCurrentState = WAIT_FOR_FC) and (TC_READY_IN = '1') then
-- 			fc_sod <= '1';
-- 		elsif (loadCurrentState = DIVIDE) and (TC_READY_IN = '1') then
-- 			fc_sod <= '1';
-- 		else
-- 			fc_sod <= '0';
-- 		end if;
-- 	end if;
-- end process sodProc;
-- 
-- offsetProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (loadCurrentState = LIDLE) or (loadCurrentState = CLEANUP) then
-- 			fc_flags_offset(12 downto 0) <= (others => '0');
-- 		elsif ((loadCurrentState = DIVIDE) and (TC_READY_IN = '1')) then
-- 			fc_flags_offset(12 downto 0) <= actual_packet_size(15 downto 3);
-- 		end if;
-- 	end if;
-- end process offsetProc;
-- 
-- fcIPSizeProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET= '1') then
-- 			fc_ip_size <= (others => '0');
-- 		elsif ((loadCurrentState = DIVIDE) and (TC_READY_IN = '1')) or ((loadCurrentState = WAIT_FOR_FC) and (TC_READY_IN = '1')) then
-- 			if (size_left >= max_frame_size) then
-- 				fc_ip_size <= max_frame_size;
-- 			else
-- 				fc_ip_size <= size_left(15 downto 0);
-- 			end if;
-- 		end if;
-- 	end if;
-- end process fcIPSizeProc;
-- 
-- fcUDPSizeProc : process(CLK)
-- 	begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			fc_udp_size <= (others => '0');
-- 		elsif (loadCurrentState = WAIT_FOR_FC) and (TC_READY_IN = '1') then
-- 			fc_udp_size <= queue_size(15 downto 0);
-- 		end if;
-- 	end if;
-- end process fcUDPSizeProc;


--***********************
--      SUBEVENT HEADERS WRITE AND READ
--***********************

-- SUBEVENT_HEADERS_FIFO : fifo_16kx8
-- port map(
-- 	Data        =>  shf_data,
-- 	WrClock     =>  CLK,
-- 	RdClock     =>  CLK,
-- 	WrEn        =>  shf_wr_en,
-- 	RdEn        =>  shf_rd_en,
-- 	Reset       =>  RESET,
-- 	RPReset     =>  RESET,
-- 	Q           =>  shf_q,
-- 	Empty       =>  shf_empty,
-- 	Full        =>  shf_full
-- );
-- 
-- -- write enable for SHF 
-- shf_wr_en <= '1' when ((saveSubCurrentState /= SIDLE) and (loadCurrentState /= PREP_DATA))
-- 				 else '0';
-- 
-- -- data multiplexing for SHF (convert 32bit LWs to 8bit)
-- -- CHANGED. 
-- -- The SubEventHeader (4x 32bit is stored in [MSB:LSB] now, same byte order as data from PC.
-- shfDataProc : process(saveSubCurrentState, sub_size_to_save, PC_DECODING_IN, PC_EVENT_ID_IN, 
-- 					  pc_trig_nr, my_int_ctr, fc_data)
-- begin
-- 	case saveSubCurrentState is
-- 		when SIDLE          =>  shf_data <= x"ac";
-- 		when SAVE_SIZE      =>  shf_data <= sub_size_to_save(my_int_ctr * 8 + 7 downto my_int_ctr * 8);
-- 		when SAVE_DECODING  =>  shf_data <= PC_DECODING_IN(my_int_ctr * 8 + 7 downto my_int_ctr * 8);
-- 		when SAVE_ID        =>  shf_data <= PC_EVENT_ID_IN(my_int_ctr * 8 + 7 downto my_int_ctr * 8);
-- 		when SAVE_TRIG_NR   =>  shf_data <= pc_trig_nr(my_int_ctr * 8 + 7 downto my_int_ctr * 8);
-- 		when SAVE_TERM      =>  shf_data <= fc_data;
-- 		when others         =>  shf_data <= x"00";
-- 	end case;
-- end process shfDataProc;
-- 
-- saveSubMachineProc : process(CLK)
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') then
-- 			saveSubCurrentState <= SIDLE;
-- 		else
-- 			saveSubCurrentState <= saveSubNextState;
-- 		end if;
-- 	end if;
-- end process saveSubMachineProc;
-- 
-- saveSubMachine : process(saveSubCurrentState, PC_START_OF_SUB_IN, sub_int_ctr, loadCurrentState, TC_H_READY_IN)
-- begin
-- 	case saveSubCurrentState is
-- 		when SIDLE =>
-- 			save_state <= x"0";
-- 			if (PC_START_OF_SUB_IN = '1') then
-- 				saveSubNextState <= SAVE_SIZE;
-- 			-- this branch is dangerous!
-- 			elsif (loadCurrentState = WAIT_FOR_FC) and (TC_H_READY_IN = '1') then -- means that loadCurrentState is put_q_len
-- 				saveSubNextState <= SAVE_TERM;
-- 			else
-- 				saveSubNextState <= SIDLE;
-- 			end if;
-- 		when SAVE_SIZE =>
-- 			save_state <= x"1";
-- 			if (sub_int_ctr = 3) then
-- 				saveSubNextState <= SAVE_DECODING;
-- 			else
-- 				saveSubNextState <= SAVE_SIZE;
-- 			end if;
-- 		when SAVE_DECODING =>
-- 			save_state <= x"2";
-- 			if (sub_int_ctr = 3) then
-- 				saveSubNextState <= SAVE_ID;
-- 			else
-- 				saveSubNextState <= SAVE_DECODING;
-- 			end if;
-- 		when SAVE_ID =>
-- 			save_state <= x"3";
-- 			if (sub_int_ctr = 3) then
-- 				saveSubNextState <= SAVE_TRIG_NR;
-- 			else
-- 				saveSubNextState <= SAVE_ID;
-- 			end if;
-- 		when SAVE_TRIG_NR =>
-- 			save_state <= x"4";
-- 			if (sub_int_ctr = 3) then
-- 				saveSubNextState <= SIDLE;
-- 			else
-- 				saveSubNextState <= SAVE_TRIG_NR;
-- 			end if;
-- 		when SAVE_TERM =>
-- 			save_state <= x"5";
-- 			if (sub_int_ctr = 31) then
-- 				saveSubNextState <= SIDLE;
-- 			else
-- 				saveSubNextState <= SAVE_TERM;
-- 			end if;
-- 		when others =>
-- 			save_state <= x"f";
-- 			saveSubNextState <= SIDLE;
-- 	end case;
-- end process;
-- 
-- -- This counter is used for breaking down 32bit information words into 8bit bytes for 
-- -- storing them in the SHF.
-- -- It is also used for the termination 32byte sequence.
-- subIntProc: process( CLK )
-- begin
-- 	if rising_edge(CLK) then
-- 		if (RESET = '1') or (saveSubCurrentState = SIDLE) then
-- 			sub_int_ctr <= 0;
-- 		elsif (sub_int_ctr = 3) and (saveSubCurrentState /= SAVE_TERM) then
-- 			sub_int_ctr <= 0;
-- 		elsif (sub_int_ctr = 31) and (saveSubCurrentState = SAVE_TERM) then
-- 			sub_int_ctr <= 0;
-- 		elsif (saveSubCurrentState /= SIDLE) and (loadCurrentState /= PREP_DATA) then
-- 			sub_int_ctr <= sub_int_ctr + 1;
-- 		end if;
-- 	end if;
-- end process subIntProc;
-- 
-- debug(3 downto 0)             <= constr_state;
-- debug(7 downto 4)             <= save_state;
-- debug(11 downto 8)            <= load_state;
-- debug(27 downto 12)           <= queue_size(15 downto 0);
-- debug(28)                     <= df_full;
-- debug(29)                     <= df_empty;
-- debug(30)                     <= shf_full;
-- debug(31)                     <= shf_empty;
-- 
-- debug(47 downto 32)           <= size_left(15 downto 0);
-- debug(52 downto 48)           <= all_ctr;
-- debug(53)                     <= pc_ready;

-- outputs
-- PC_READY_OUT                  <= pc_ready;
-- TC_WR_EN_OUT                  <= fc_wr_en;
-- TC_DATA_OUT                   <= fc_data;
-- TC_IP_SIZE_OUT                <= fc_ip_size;
-- TC_UDP_SIZE_OUT               <= fc_udp_size;
-- -- FC_IDENT_OUT(15 downto 8)     <= fc_ident(7 downto 0);
-- -- FC_IDENT_OUT(7 downto 0)      <= fc_ident(15 downto 8);
-- TC_FLAGS_OFFSET_OUT           <= fc_flags_offset;
-- TC_SOD_OUT                    <= fc_sod;
-- TC_EOD_OUT                    <= fc_eod;

--PC_READY_OUT                  <= '1';
--TC_IP_SIZE_OUT                <= (others => '0');
--TC_UDP_SIZE_OUT               <= (others => '0');
-- FC_IDENT_OUT(15 downto 8)     <= fc_ident(7 downto 0);
-- FC_IDENT_OUT(7 downto 0)      <= fc_ident(15 downto 8);
-- TC_FLAGS_OFFSET_OUT           <= fc_flags_offset;
-- TC_SOD_OUT                    <= fc_sod;
-- TC_EOD_OUT                    <= fc_eod;

DEBUG_OUT                     <= debug;

end trb_net16_gbe_packet_constr;