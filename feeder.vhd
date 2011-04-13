LIBRARY ieee;
use ieee.std_logic_1164.all;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;
use IEEE.std_logic_arith.all;

library work;

entity feeder is
port( CLK						: in	std_logic;
	  RESET						: in	std_logic;
	  -- IPU interface directed toward the CTS
	  CTS_NUMBER_IN				: in	std_logic_vector (15 downto 0);
	  CTS_CODE_IN				: in	std_logic_vector (7  downto 0);
	  CTS_INFORMATION_IN		: in	std_logic_vector (7  downto 0);
	  CTS_READOUT_TYPE_IN		: in	std_logic_vector (3  downto 0);
	  CTS_START_READOUT_IN		: in	std_logic;
	  CTS_READ_IN				: in	std_logic;
	  CTS_DATA_OUT				: out	std_logic_vector (31 downto 0);
	  CTS_DATAREADY_OUT			: out	std_logic;
	  CTS_READOUT_FINISHED_OUT	: out	std_logic;      --no more data, end transfer, send TRM
	  CTS_LENGTH_OUT			: out	std_logic_vector (15 downto 0);
	  CTS_ERROR_PATTERN_OUT		: out	std_logic_vector (31 downto 0);
	  -- Data from Frontends
	  FEE_DATA_IN				: in	std_logic_vector (15 downto 0);
	  FEE_DATAREADY_IN			: in	std_logic;
	  FEE_READ_OUT				: out	std_logic;
	  FEE_BUSY_IN				: in	std_logic;
	  FEE_STATUS_BITS_IN		: in	std_logic_vector (31 downto 0); 
	  -- PacketConstructor interface
	  PC_WR_EN_OUT				: out	std_logic;
	  PC_DATA_OUT				: out	std_logic_vector (7 downto 0);
	  PC_READY_IN				: in	std_logic;
	  PC_SOS_OUT				: out	std_logic;
	  PC_EOD_OUT				: out	std_logic;
	  PC_SUB_SIZE_OUT			: out	std_logic_vector(31 downto 0);
	  PC_TRIG_NR_OUT			: out	std_logic_vector(31 downto 0);
	  PC_PADDING_OUT			: out	std_logic;
	  -- Debug
	  BSM_SAVE_OUT				: out	std_logic_vector(3 downto 0);
	  BSM_LOAD_OUT				: out	std_logic_vector(3 downto 0);
	  DBG_REM_CTR_OUT			: out	std_logic_vector(3 downto 0);
	  DBG_CTS_CTR_OUT			: out	std_logic_vector(2 downto 0);
	  DBG_SF_WCNT_OUT			: out	std_logic_vector(15 downto 0);
	  DBG_SF_RCNT_OUT			: out	std_logic_vector(16 downto 0);
	  DBG_SF_DATA_OUT			: out	std_logic_vector(15 downto 0);
	  DBG_SF_RD_EN_OUT			: out	std_logic;
	  DBG_SF_WR_EN_OUT			: out	std_logic;
	  DBG_SF_EMPTY_OUT			: out	std_logic;
	  DBG_SF_FULL_OUT			: out	std_logic;
	  DBG_SF_AFULL_OUT			: out	std_logic;
	  DEBUG_OUT					: out	std_logic_vector(31 downto 0)
);
end entity;

architecture feeder of feeder is

component fifo_32kx16x8_mb
port( Data				: in	std_logic_vector(15 downto 0); 
	  WrClock			: in	std_logic;
	  RdClock			: in	std_logic; 
	  WrEn				: in	std_logic;
	  RdEn				: in	std_logic;
	  Reset				: in	std_logic; 
	  RPReset			: in	std_logic; 
	  AmFullThresh		: in	std_logic_vector(14 downto 0); 
	  Q					: out	std_logic_vector(7 downto 0); 
	  WCNT				: out	std_logic_vector(15 downto 0); 
	  RCNT				: out	std_logic_vector(16 downto 0);
	  Empty				: out	std_logic; 
	  Full				: out	std_logic;
	  AlmostFull		: out	std_logic
	 );
end component;

type saveStates	is (SIDLE, WAIT_FOR_DATA, SAVE_DATA, TERMINATE, SCLOSE);
signal saveCurrentState, saveNextState : saveStates;
signal state				: std_logic_vector(3 downto 0);
signal data_req_comb		: std_logic;
signal data_req				: std_logic; -- request data signal, will be used for fee_read generation
signal rst_saved_ctr_comb	: std_logic;
signal rst_saved_ctr		: std_logic;

signal fee_read_comb		: std_logic;
signal fee_read				: std_logic; -- fee_read signal
signal saved_ctr			: std_logic_vector(16 downto 0);
signal ce_saved_ctr			: std_logic;

-- header data
signal cts_rnd				: std_logic_vector(15 downto 0);
signal cts_rnd_saved		: std_logic;
signal cts_trg				: std_logic_vector(15 downto 0);
signal cts_trg_saved		: std_logic;
signal cts_len				: std_logic_vector(16 downto 0);
signal cts_len_saved		: std_logic;

-- CTS interface
signal cts_error_pattern	: std_logic_vector(31 downto 0);
signal cts_length			: std_logic_vector(15 downto 0);
signal cts_readout_finished	: std_logic;
signal cts_dataready		: std_logic;
signal cts_data             : std_logic_vector(31 downto 0);

-- Split FIFO signals
signal sf_data				: std_logic_vector(15 downto 0);
signal sf_wr_en_comb		: std_logic;
signal sf_wr_en				: std_logic; -- write signal for FIFO
signal sf_rd_en				: std_logic;
signal sf_wcnt				: std_logic_vector(15 downto 0);
signal sf_rcnt				: std_logic_vector(16 downto 0);
signal sf_empty				: std_logic;
signal sf_full				: std_logic;
signal sf_afull				: std_logic;

-------------------------------------------------------------------
type loadStates is (LIDLE, INIT, REMOVE, CALCA, CALCB, LOAD, PAD0, PAD1, PAD2, PAD3, WAIT_PC, CLOSE);
signal loadCurrentState, loadNextState : loadStates;
signal state2				:	std_logic_vector(3 downto 0);

signal rem_ctr				: std_logic_vector(3 downto 0); -- counter for stripping / storing header data
signal rst_rem_ctr_comb		: std_logic;
signal rst_rem_ctr			: std_logic;
signal rst_regs_comb		: std_logic;
signal rst_regs				: std_logic;
signal ce_rem_ctr_comb		: std_logic;
signal ce_rem_ctr			: std_logic;
signal remove_done_comb		: std_logic;
signal remove_done			: std_logic; -- end of header stripping process
signal load_done_comb		: std_logic;
signal load_done			: std_logic; -- end of data transfer into PC
signal calc_pad_comb		: std_logic;
signal calc_pad				: std_logic; -- add padding bytes, if needed
signal read_data_comb		: std_logic;
signal read_data			: std_logic; -- fetch data from split fifo
signal data_phase_comb		: std_logic;
signal data_phase			: std_logic; -- data transport phase from split fifo to PC
signal pc_sos_comb			: std_logic;
signal pc_sos				: std_logic; -- start of data signal
signal pc_eod_comb			: std_logic;
signal pc_eod				: std_logic; -- end of data signal
signal pad_data_comb		: std_logic;
signal pad_data				: std_logic; -- insert padding bytes

signal pc_data				: std_logic_vector(7 downto 0);
signal pc_data_q			: std_logic_vector(7 downto 0);
signal pc_trig_nr			: std_logic_vector(15 downto 0);
signal pc_sub_size			: std_logic_vector(17 downto 0);
signal read_size			: std_logic_vector(17 downto 0); -- number of byte to be read from split fifo
signal padding_needed		: std_logic;
signal pc_wr_en_q			: std_logic;
signal pc_wr_en_qq			: std_logic;
signal pc_eod_q				: std_logic;

signal debug				: std_logic_vector(31 downto 0);

begin

-- CTS interface signals
cts_error_pattern    <= (others => '0'); -- FAKE
cts_dataready        <= '1'; -- FAKE

cts_length           <= x"0000"; -- length of data payload is always 0
cts_data             <= b"0001" & cts_rnd(11 downto 0) & cts_trg; -- reserved bits = '0', pack bit = '1'

cts_readout_finished <= '1' when (saveCurrentState = SCLOSE) else '0';


-- Sync all critical pathes
THE_SYNC_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		sf_data     <= FEE_DATA_IN;
		sf_wr_en    <= sf_wr_en_comb;
		fee_read    <= fee_read_comb;
		load_done   <= load_done_comb;
		pc_eod_q    <= pc_eod;
		pc_wr_en_qq <= pc_wr_en_q;
		pc_wr_en_q  <= data_phase;
	end if;
end process THE_SYNC_PROC;

-- combinatorial read signal for the FEE data interface, DO NOT USE DIRECTLY
fee_read_comb <= '1' when ( (sf_afull = '0') and (data_req = '1') ) 
					 else '0';

-- combinatorial write signal for the split FIFO, DO NOT USE DIRECTLY
sf_wr_en_comb <= '1' when ( (fee_read = '1') and (FEE_DATAREADY_IN = '1') )
					 else '0';

-- Counter for header word storage
THE_CTS_SAVED_CTR: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_saved_ctr = '1') ) then
			saved_ctr <= (others => '0');
		elsif( ce_saved_ctr = '1' ) then
			saved_ctr <= saved_ctr + 1;
		end if;
	end if;
end process THE_CTS_SAVED_CTR;

ce_saved_ctr <= sf_wr_en;

-- Statemachine for reading data payload, handling IPU channel and storing data in the SPLIT_FIFO
saveMachineProc: process( CLK )
begin
	if rising_edge(CLK) then
		if RESET = '1' then
			saveCurrentState <= SIDLE;
			data_req         <= '0';
			rst_saved_ctr    <= '0';
		else
			saveCurrentState <= saveNextState;
			data_req         <= data_req_comb;
			rst_saved_ctr    <= rst_saved_ctr_comb;
		end if;
	end if;
end process saveMachineProc;

saveMachine: process( saveCurrentState, CTS_START_READOUT_IN, FEE_BUSY_IN, CTS_READ_IN )
begin
	saveNextState      <= SIDLE;
	data_req_comb      <= '0';
	rst_saved_ctr_comb <= '0';
	case saveCurrentState is
		when SIDLE =>
			state <= x"0";
			if (CTS_START_READOUT_IN = '1') then
				saveNextState <= WAIT_FOR_DATA;
				data_req_comb <= '1';
				rst_saved_ctr_comb <= '1';
			else
				saveNextState <= SIDLE;
			end if;
		when WAIT_FOR_DATA =>
			state <= x"1";
			if (FEE_BUSY_IN = '1') then
				saveNextState <= SAVE_DATA;
				data_req_comb <= '1';
			else
				saveNextState <= WAIT_FOR_DATA;
				data_req_comb <= '1';
			end if;
		when SAVE_DATA =>
			state <= x"2";
			if (FEE_BUSY_IN = '0') then
				saveNextState <= TERMINATE;
			else
				saveNextState <= SAVE_DATA;
				data_req_comb <= '1';
			end if;
		when TERMINATE =>
			state <= x"3";
			if (CTS_READ_IN = '1') then
				saveNextState <= SCLOSE;
			else
				saveNextState <= TERMINATE;
			end if;
		when SCLOSE =>
			state <= x"4";
			if (CTS_START_READOUT_IN = '0') then
				saveNextState <= SIDLE;
			else
				saveNextState <= SCLOSE;
			end if;
		when others =>
			state <= x"f";
			saveNextState <= SIDLE;
	end case;
end process saveMachine;

-- save triggerRnd from incoming data for cts response
CTS_RND_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_saved_ctr = '1') ) then
			cts_rnd       <= (others => '0');
			cts_rnd_saved <= '0';
		elsif( (saved_ctr(2 downto 0) = b"000") and (sf_wr_en = '1') and (cts_rnd_saved = '0') ) then
			cts_rnd       <= sf_data;
			cts_rnd_saved <= '1';
		end if;
	end if;
end process CTS_RND_PROC;

-- save triggerNr from incoming data for cts response
CTS_TRG_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_saved_ctr = '1') ) then
			cts_trg       <= (others => '0');
			cts_trg_saved <= '0';
		elsif( (saved_ctr(2 downto 0) = b"001") and (sf_wr_en = '1') and (cts_trg_saved = '0') ) then
			cts_trg       <= sf_data;
			cts_trg_saved <= '1';
		end if;
	end if;
end process CTS_TRG_PROC;

-- save size from incoming data for cts response (future) and to get rid of padding
CTS_SIZE_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_saved_ctr = '1') ) then
			cts_len       <= (others => '0');
			cts_len_saved <= '0';
		elsif( (saved_ctr(2 downto 0) = b"010") and (sf_wr_en = '1') and (cts_len_saved = '0') ) then
			cts_len(16 downto 1) <= sf_data; -- change from 32b words to 16b words
		elsif( (saved_ctr(2 downto 0) = b"011") and (cts_len_saved = '0') ) then
			cts_len       <= cts_len + x"4";
			cts_len_saved <= '1';
		end if;
	end if;
end process CTS_SIZE_PROC;

------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

-- Split FIFO
THE_SPLIT_FIFO: fifo_32kx16x8_mb
port map( Data				=> sf_data,
		  WrClock			=> CLK,
		  RdClock			=> CLK, 
		  WrEn				=> sf_wr_en,
		  RdEn				=> sf_rd_en,
		  Reset				=> RESET, 
		  RPReset			=> RESET, 
		  AmFullThresh		=> b"111_1111_1110_1111", -- 0x7fef = 32751
		  Q					=> pc_data, --open,
		  WCNT				=> sf_wcnt,
		  RCNT				=> sf_rcnt,
		  Empty				=> sf_empty,
		  Full				=> sf_full,
		  AlmostFull		=> sf_afull
		 );

sf_rd_en <= read_data;
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

-- FIFO data delay process (also forces padding bytes to known value)
THE_DATA_DELAY_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if( pad_data = '1' ) then
			pc_data_q <= x"ee";
		else
			pc_data_q   <= pc_data;
		end if;
	end if;
end process THE_DATA_DELAY_PROC;

-- Statemachine for reading the data payload from the SPLIT_FIFO and feeding
-- it into the packet constructor
loadMachineProc : process(CLK)
begin
	if rising_edge(CLK) then
		if RESET = '1' then
			loadCurrentState <= LIDLE;
			rst_regs         <= '0';
			rst_rem_ctr      <= '0';
			ce_rem_ctr       <= '0';
			calc_pad         <= '0';
			read_data        <= '0';
			data_phase       <= '0';
			pc_sos           <= '0';
			pc_eod           <= '0';
			pad_data         <= '0';
		else
			loadCurrentState <= loadNextState;
			rst_regs         <= rst_regs_comb;
			rst_rem_ctr      <= rst_rem_ctr_comb;
			ce_rem_ctr       <= ce_rem_ctr_comb;
			calc_pad         <= calc_pad_comb;
			read_data        <= read_data_comb;
			data_phase       <= data_phase_comb;
			pc_sos           <= pc_sos_comb;
			pc_eod           <= pc_eod_comb;
			pad_data         <= pad_data_comb;
		end if;
	end if;
end process loadMachineProc;

loadMachine : process( loadCurrentState, sf_empty, remove_done, load_done, padding_needed, PC_READY_IN )
begin
	loadNextState    <= LIDLE;
	rst_regs_comb    <= '0';
	rst_rem_ctr_comb <= '0';
	ce_rem_ctr_comb  <= '0';
	calc_pad_comb    <= '0';
	read_data_comb   <= '0';
	data_phase_comb  <= '0';
	pc_sos_comb      <= '0';
	pc_eod_comb      <= '0';
	pad_data_comb    <= '0';
	case loadCurrentState is
		when LIDLE =>
			state2 <= x"0";
			if( (sf_empty = '0') and (PC_READY_IN = '1') ) then
				loadNextState <= INIT;
				rst_regs_comb <= '1';
				rst_rem_ctr_comb <= '1';
			else
				loadNextState <= LIDLE;
			end if;
		when INIT =>
			state2 <= x"1";
			loadNextState <= REMOVE;
			ce_rem_ctr_comb <= '1';
			read_data_comb <= '1';
		when REMOVE =>
			state2 <= x"2";
			if( remove_done = '1' ) then
				loadNextState <= CALCA;
				calc_pad_comb <= '1';
			else
				loadNextState <= REMOVE;
				ce_rem_ctr_comb <= '1';
				read_data_comb <= '1';
			end if;
		when CALCA =>
			state2 <= x"3";
			loadNextState <= CALCB;
		when CALCB =>
			-- we need a branch in case of length "0"!!!!
			state2 <= x"4";
			loadNextState <= LOAD;
			read_data_comb <= '1';
			data_phase_comb <= '1';
			pc_sos_comb <= '1';
		when LOAD =>
			state2 <= x"5";
			if   ( (load_done = '1') and (padding_needed = '0') ) then
				loadNextState <= CLOSE;
			elsif( (load_done = '1') and (padding_needed = '1') ) then
				loadNextState <= PAD0;
				data_phase_comb <= '1';
			else
				loadNextState <= LOAD;
				read_data_comb <= '1';
				data_phase_comb <= '1';
			end if;
		when PAD0 =>
			state2 <= x"5";
			loadNextState <= PAD1;
			data_phase_comb <= '1';
			pad_data_comb <= '1';
		when PAD1 =>
			state2 <= x"6";
			loadNextState <= PAD2;
			data_phase_comb <= '1';
			pad_data_comb <= '1';
		when PAD2 =>
			state2 <= x"7";
			loadNextState <= PAD3;
			data_phase_comb <= '1';
			pad_data_comb <= '1';
		when PAD3 =>
			state2 <= x"8";
			loadNextState <= CLOSE;
			pad_data_comb <= '1';
		when CLOSE =>
			state2 <= x"9";
			loadNextState <= WAIT_PC;
			pc_eod_comb <= '1';
		when WAIT_PC =>
			state2 <= x"a";
			if( PC_READY_IN = '1' ) then
				loadNextState <= LIDLE;
				rst_rem_ctr_comb <= '1';
				rst_regs_comb <= '1';
			else
				loadNextState <= WAIT_PC;
			end if;
		when others =>
			state2 <= x"f";
			loadNextState <= LIDLE;
	end case;
end process loadMachine;

-- Counter for stripping the unneeded parts of the data stream, and saving the important parts
THE_REMOVE_CTR: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_rem_ctr = '1') ) then
			rem_ctr <= (others => '0');
		elsif( ce_rem_ctr = '1' ) then
			rem_ctr <= rem_ctr + 1;
		end if;
	end if;
end process THE_REMOVE_CTR;

remove_done_comb <= '1' when ( rem_ctr = x"6" ) else '0';

THE_REM_DONE_SYNC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_rem_ctr = '1') ) then
			remove_done <= '0';
		else
			remove_done <= remove_done_comb;
		end if;
	end if;
end process THE_REM_DONE_SYNC;

-- extract the trigger number from splitfifo data
THE_TRG_NR_PROC: process( CLK )
begin
	if rising_edge(CLK) then
		if   ( (RESET = '1') or (rst_regs = '1') ) then
			pc_trig_nr <= (others => '0');
		elsif( (ce_rem_ctr = '1') and (rem_ctr = x"3") ) then
			pc_trig_nr(7 downto 0) <= pc_data;
		elsif( (ce_rem_ctr = '1') and (rem_ctr = x"4") ) then
			pc_trig_nr(15 downto 8) <= pc_data;
		end if;
	end if;
end process THE_TRG_NR_PROC;

-- check for padding
THE_PADDING_NEEDED_PROC: process( CLK )
begin
	if rising_edge(CLK) then
		if   ( (RESET = '1') or (rst_regs = '1') ) then
			padding_needed <= '0';
		elsif( (remove_done = '1') and (pc_sub_size(2) = '1') ) then
			padding_needed <= '1';
		elsif( (remove_done = '1') and (pc_sub_size(2) = '0') ) then
			padding_needed <= '0';
		end if;
	end if;
end process THE_PADDING_NEEDED_PROC;

-- extract the subevent size from the splitfifo data, convert it from 32b to 8b units,
-- and in case of padding needed increase it accordingly
THE_SUB_SIZE_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_regs = '1') ) then
			pc_sub_size <= (others => '0');
		elsif( (ce_rem_ctr = '1') and (rem_ctr = x"5") ) then
			pc_sub_size(9 downto 2) <= pc_data;
		elsif( (ce_rem_ctr = '1') and (rem_ctr = x"6") ) then
			pc_sub_size(17 downto 10) <= pc_data;
		elsif( (calc_pad = '1') and (padding_needed = '1') ) then
			pc_sub_size <= pc_sub_size + 4;
		end if;
	end if;
end process THE_SUB_SIZE_PROC;

-- number of bytes to read from split fifo
THE_READ_SIZE_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_rem_ctr = '1') ) then
			read_size   <= (others => '0');
		elsif( (ce_rem_ctr = '1') and (rem_ctr = x"5") ) then
			read_size(9 downto 2) <= pc_data;
		elsif( (ce_rem_ctr = '1') and (rem_ctr = x"6") ) then
			read_size(17 downto 10) <= pc_data;
		elsif( ((calc_pad = '1') and (load_done = '0')) ) then
			read_size <= read_size - 2;
		elsif( ((read_data = '1') and (data_phase = '1')) ) then
			read_size <= read_size - 1;
		end if;
	end if;
end process THE_READ_SIZE_PROC;

load_done_comb <= '1' when (read_size = 0) else '0';

------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

-- Debug signals
debug(31)           <= remove_done;
debug(30)           <= load_done;
debug(29)           <= ce_rem_ctr;
debug(28)           <= rst_rem_ctr;
debug(27)           <= rst_regs;
debug(26)           <= data_phase;
debug(25)           <= read_data;
debug(24)           <= pad_data;
debug(23 downto 18) <= (others => '0');
debug(17 downto 0)  <= read_size;

-- Outputs
FEE_READ_OUT             <= fee_read;
CTS_ERROR_PATTERN_OUT    <= cts_error_pattern;
CTS_DATA_OUT             <= cts_data;
CTS_DATAREADY_OUT        <= cts_dataready;
CTS_READOUT_FINISHED_OUT <= cts_readout_finished;
CTS_LENGTH_OUT           <= cts_length;

PC_SOS_OUT               <= pc_sos;
PC_EOD_OUT               <= pc_eod_q;
PC_DATA_OUT              <= pc_data_q;
PC_WR_EN_OUT             <= pc_wr_en_qq;
PC_TRIG_NR_OUT           <= x"0000" & pc_trig_nr;
PC_SUB_SIZE_OUT          <= b"0000_0000_0000_00" & pc_sub_size;
PC_PADDING_OUT           <= padding_needed;

BSM_SAVE_OUT             <= state;
BSM_LOAD_OUT             <= state2;
DBG_CTS_CTR_OUT          <= saved_ctr(2 downto 0);
DBG_REM_CTR_OUT          <= rem_ctr;
DBG_SF_DATA_OUT          <= sf_data;
DBG_SF_WCNT_OUT          <= sf_wcnt;
DBG_SF_RCNT_OUT          <= sf_rcnt;
DBG_SF_RD_EN_OUT         <= sf_rd_en;
DBG_SF_WR_EN_OUT         <= sf_wr_en;
DBG_SF_EMPTY_OUT         <= sf_empty;
DBG_SF_FULL_OUT          <= sf_full;
DBG_SF_AFULL_OUT         <= sf_afull;

DEBUG_OUT                <= debug;

end architecture;