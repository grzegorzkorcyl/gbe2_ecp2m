LIBRARY ieee;
use ieee.std_logic_1164.all;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;
use IEEE.std_logic_arith.all;

library work;

entity trb_net16_ipu2gbe is
port( 
	CLK                         : in    std_logic;
	RESET                       : in    std_logic;
	-- IPU interface directed toward the CTS
	CTS_NUMBER_IN               : in    std_logic_vector (15 downto 0);
	CTS_CODE_IN                 : in    std_logic_vector (7  downto 0);
	CTS_INFORMATION_IN          : in    std_logic_vector (7  downto 0);
	CTS_READOUT_TYPE_IN         : in    std_logic_vector (3  downto 0);
	CTS_START_READOUT_IN        : in    std_logic;
	CTS_READ_IN                 : in    std_logic;
	CTS_DATA_OUT                : out   std_logic_vector (31 downto 0);
	CTS_DATAREADY_OUT           : out   std_logic;
	CTS_READOUT_FINISHED_OUT    : out   std_logic;      --no more data, end transfer, send TRM
	CTS_LENGTH_OUT              : out   std_logic_vector (15 downto 0);
	CTS_ERROR_PATTERN_OUT       : out   std_logic_vector (31 downto 0);
	-- Data from Frontends
	FEE_DATA_IN                 : in    std_logic_vector (15 downto 0);
	FEE_DATAREADY_IN            : in    std_logic;
	FEE_READ_OUT                : out   std_logic;
	FEE_BUSY_IN                 : in    std_logic;
	FEE_STATUS_BITS_IN          : in    std_logic_vector (31 downto 0);
	-- slow control interface
	START_CONFIG_OUT			: out	std_logic; -- reconfigure MACs/IPs/ports/packet size
	BANK_SELECT_OUT				: out	std_logic_vector(3 downto 0); -- configuration page address
	CONFIG_DONE_IN				: in	std_logic; -- configuration finished
	DATA_GBE_ENABLE_IN			: in	std_logic; -- IPU data is forwarded to GbE
	DATA_IPU_ENABLE_IN			: in	std_logic; -- IPU data is forwarded to CTS / TRBnet
	MULT_EVT_ENABLE_IN			: in    std_logic;
	MAX_MESSAGE_SIZE_IN			: in	std_logic_vector(31 downto 0); -- the maximum size of one HadesQueue  -- gk 08.04.10
	MIN_MESSAGE_SIZE_IN			: in	std_logic_vector(31 downto 0); -- gk 20.07.10
	READOUT_CTR_IN				: in	std_logic_vector(23 downto 0); -- gk 26.04.10
	READOUT_CTR_VALID_IN			: in	std_logic; -- gk 26.04.10
	-- PacketConstructor interface
	ALLOW_LARGE_IN				: in	std_logic;  -- gk 21.07.10
	PC_WR_EN_OUT                : out   std_logic;
	PC_DATA_OUT                 : out   std_logic_vector (7 downto 0);
	PC_READY_IN                 : in    std_logic;
	PC_SOS_OUT                  : out   std_logic;
	PC_EOD_OUT                  : out   std_logic;
	PC_SUB_SIZE_OUT             : out   std_logic_vector(31 downto 0);
	PC_TRIG_NR_OUT              : out   std_logic_vector(31 downto 0);
	PC_PADDING_OUT              : out   std_logic;
	MONITOR_OUT                 : out   std_logic_vector(223 downto 0);
	DEBUG_OUT                   : out   std_logic_vector(383 downto 0)
);
end entity;

architecture trb_net16_ipu2gbe of trb_net16_ipu2gbe is

-- -- Placer Directives
-- attribute HGROUP : string;
-- -- for whole architecture
-- attribute HGROUP of trb_net16_ipu2gbe : architecture  is "GBE_ipu2gbe_group";

component fifo_32kx16x8_mb2
port( 
	Data            : in    std_logic_vector(17 downto 0); 
	WrClock         : in    std_logic;
	RdClock         : in    std_logic; 
	WrEn            : in    std_logic;
	RdEn            : in    std_logic;
	Reset           : in    std_logic; 
	RPReset         : in    std_logic; 
	AmEmptyThresh   : in    std_logic_vector(15 downto 0); 
	AmFullThresh    : in    std_logic_vector(14 downto 0); 
	Q               : out   std_logic_vector(8 downto 0); 
	WCNT            : out   std_logic_vector(15 downto 0); 
	RCNT            : out   std_logic_vector(16 downto 0);
	Empty           : out   std_logic;
	AlmostEmpty     : out   std_logic;
	Full            : out   std_logic;
	AlmostFull      : out   std_logic
);
end component;

type saveStates is (SIDLE, SAVE_EVT_ADDR, WAIT_FOR_DATA, SAVE_DATA, ADD_SUBSUB1, ADD_SUBSUB2, ADD_SUBSUB3, ADD_SUBSUB4, TERMINATE, SCLOSE);
signal saveCurrentState, saveNextState : saveStates;
signal state                : std_logic_vector(3 downto 0);
signal data_req_comb        : std_logic;
signal data_req             : std_logic; -- request data signal, will be used for fee_read generation
signal rst_saved_ctr_comb   : std_logic;
signal rst_saved_ctr        : std_logic;

signal fee_read_comb        : std_logic;
signal fee_read             : std_logic; -- fee_read signal
signal saved_ctr            : std_logic_vector(16 downto 0);
signal ce_saved_ctr         : std_logic;

-- header data
signal cts_rnd              : std_logic_vector(15 downto 0);
signal cts_rnd_saved        : std_logic;
signal cts_trg              : std_logic_vector(15 downto 0);
signal cts_trg_saved        : std_logic;
signal cts_len              : std_logic_vector(16 downto 0);
signal cts_len_saved        : std_logic;

-- CTS interface
signal cts_error_pattern    : std_logic_vector(31 downto 0);
signal cts_length           : std_logic_vector(15 downto 0);
signal cts_readout_finished : std_logic;
signal cts_dataready        : std_logic;
signal cts_data             : std_logic_vector(31 downto 0);

-- Split FIFO signals
signal sf_data              : std_logic_vector(15 downto 0);
signal sf_wr_en_comb        : std_logic;
signal sf_wr_en             : std_logic; -- write signal for FIFO
signal sf_rd_en_comb        : std_logic;
signal sf_rd_en             : std_logic; -- read signal for FIFO
signal sf_wcnt              : std_logic_vector(15 downto 0);
signal sf_rcnt              : std_logic_vector(16 downto 0);
signal sf_empty             : std_logic;
signal sf_aempty            : std_logic;
signal sf_full              : std_logic;
signal sf_afull             : std_logic;

-------------------------------------------------------------------
type loadStates is (LIDLE, INIT, REMOVE, DECIDE, CALCA, CALCB, LOAD, PAD0, PAD1, PAD2, PAD3, LOAD_SUBSUB, CALCC, CLOSE, WAIT_PC, DROP, WAIT_TO_REMOVE, DROP_SUBSUB, PAUSE_BEFORE_DROP1, PAUSE_BEFORE_DROP2);
signal loadCurrentState, loadNextState : loadStates;
signal state2               :   std_logic_vector(3 downto 0);

signal rem_ctr              : std_logic_vector(3 downto 0); -- counter for stripping / storing header data
signal rst_rem_ctr_comb     : std_logic;
signal rst_rem_ctr          : std_logic; -- reset the remove counter
signal rst_regs_comb        : std_logic;
signal rst_regs             : std_logic; -- reset storage registers
signal rem_phase_comb       : std_logic;
signal rem_phase            : std_logic; -- header remove phase
signal data_phase_comb      : std_logic;
signal data_phase           : std_logic; -- data transport phase from split fifo to PC
signal pad_phase_comb       : std_logic;
signal pad_phase            : std_logic; -- padding phase
signal calc_pad_comb        : std_logic;
signal calc_pad             : std_logic; -- check if padding bytes need to be added to PC_SUB_SIZE
signal pad_data_comb        : std_logic;
signal pad_data             : std_logic; -- reset PC_DATA register to known padding byte value

signal pc_sos_comb          : std_logic;
signal pc_sos               : std_logic; -- start of data signal
signal pc_eod_comb          : std_logic;
signal pc_eod               : std_logic; -- end of data signal

signal ce_rem_ctr_comb      : std_logic;
signal ce_rem_ctr           : std_logic; -- count enable for remove counter
signal remove_done_comb     : std_logic;
signal remove_done          : std_logic; -- end of header stripping process
signal read_done_comb       : std_logic;
signal read_done            : std_logic; -- end of data phase (read phase from SF)

signal pc_data              : std_logic_vector(7 downto 0);
signal pc_data_q            : std_logic_vector(7 downto 0);
signal pc_trig_nr           : std_logic_vector(15 downto 0);
signal pc_sub_size          : std_logic_vector(17 downto 0);
signal read_size            : std_logic_vector(17 downto 0); -- number of byte to be read from split fifo
signal padding_needed       : std_logic;
signal pc_wr_en_comb        : std_logic;
signal pc_wr_en_q           : std_logic;
signal pc_wr_en_qq          : std_logic;
signal pc_wr_en_qqq         : std_logic;
signal pc_eod_q             : std_logic;

signal debug                : std_logic_vector(383 downto 0);

-- gk 
signal bank_select          : std_logic_vector(3 downto 0);
signal save_addr_comb       : std_logic;
signal save_addr            : std_logic;
signal addr_saved_comb	    : std_logic;
signal addr_saved	    : std_logic;
signal start_config	    : std_logic;
signal config_done	    : std_logic;
signal add_sub_state        : std_logic;
signal add_sub_state_comb   : std_logic;
signal add_sub_ctr          : std_logic_vector(3 downto 0);
signal load_sub             : std_logic;
signal load_sub_comb        : std_logic;
signal load_sub_done        : std_logic;
signal load_sub_done_comb   : std_logic;
signal load_sub_ctr         : std_logic_vector(3 downto 0);
signal load_sub_ctr_comb    : std_logic;
signal actual_message_size  : std_logic_vector(31 downto 0);
signal more_subevents       : std_logic;
signal trig_random          : std_logic_vector(7 downto 0);
signal readout_ctr          : std_logic_vector(23 downto 0);
signal readout_ctr_lock     : std_logic;
signal pc_trig_nr_q         : std_logic_vector(31 downto 0);

-- gk 20.07.10
signal inc_data_ctr         : std_logic_vector(31 downto 0);
signal dropped_sm_events_ctr : std_logic_vector(31 downto 0);
signal dropped_lr_events_ctr : std_logic_vector(31 downto 0);
signal dropped_ctr          : std_logic_vector(31 downto 0);
-- gk 22.07.10
signal headers_invalid      : std_logic;
signal headers_invalid_ctr  : std_logic_vector(31 downto 0);
signal cts_len_q            : std_logic_vector(15 downto 0);
signal cts_trg_q            : std_logic_vector(15 downto 0);
signal cts_rnd_q            : std_logic_vector(15 downto 0);
signal first_run_trg        : std_logic_vector(15 downto 0);
signal first_run_addr       : std_logic_vector(15 downto 0);
signal first_run_lock       : std_logic;
signal cts_addr             : std_logic_vector(15 downto 0);
signal cts_addr_q           : std_logic_vector(15 downto 0);
signal cts_addr_saved       : std_logic;

-- gk 24.07.10
signal save_eod             : std_logic;
signal save_eod_comb        : std_logic;

signal load_eod             : std_logic;
signal endpoint_addr        : std_logic_vector(15 downto 0);
signal endp_addr_lock       : std_logic;

signal saved_events_ctr     : std_logic_vector(15 downto 0);
signal loaded_events_ctr    : std_logic_vector(15 downto 0);
signal constr_events_ctr    : std_logic_vector(31 downto 0);
signal event_waiting        : std_logic;

signal drop_sub             : std_logic;
signal drop_sub_comb        : std_logic;
signal drop_event           : std_logic;
signal drop_event_comb      : std_logic;
signal drop_small           : std_logic;
signal drop_large           : std_logic;
signal drop_headers         : std_logic;
signal drop_small_comb      : std_logic;
signal drop_large_comb      : std_logic;
signal drop_headers_comb    : std_logic;
signal inc_trg_ctr          : std_logic;
signal inc_trg_ctr_comb     : std_logic;

signal invalid_hsize_ctr    : std_logic_vector(15 downto 0);
signal invalid_hsize_lock   : std_logic;

signal load_eod_q           : std_logic;
signal read_size_q          : std_logic_vector(17 downto 0);

-- gk 06.08.10 write to fifo only if gbe is enabled but keep the saving logic unblocked
signal sf_real_wr_en        : std_logic;

-- gk 01.10.10
signal found_empty_evt      : std_logic;
signal found_empty_evt_comb : std_logic;
signal found_empty_evt_ctr  : std_logic_vector(31 downto 0);

begin

BANK_SELECT_OUT <= bank_select; -- gk 27.03.10
START_CONFIG_OUT <= start_config;  -- gk 27.03.10
config_done <= CONFIG_DONE_IN; -- gk 29.03.10

-- CTS interface signals
cts_error_pattern    <= (others => '0'); -- FAKE

cts_length           <= x"0000"; -- length of data payload is always 0
cts_data             <= b"0001" & cts_rnd(11 downto 0) & cts_trg; -- reserved bits = '0', pack bit = '1'

cts_readout_finished <= '1' when (saveCurrentState = SCLOSE) else '0';

cts_dataready        <= '1' when ((saveCurrentState = SAVE_DATA) and (FEE_BUSY_IN = '0')) or (saveCurrentState = TERMINATE) 
							else '0';

-- Byte swapping... done here. TAKE CARE!
-- The split FIFO is in natural bus order (i.e. Motorola style, [15:0]). This means that the two bytes
-- on the write side need to be swapped to appear in GbE style (i.e. Intel style) on the 8bit port.
-- Please mind that PC_SUB_SIZE and PC_TRIG_NR stay in a human readable format, and need to be byteswapped
-- for GbE inside the packet constructor.
--
-- Long live the Endianess!

-- Sync all critical pathes
THE_SYNC_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		--sf_data       <= FEE_DATA_IN; -- gk 27.03.10 moved out to the process below
		sf_wr_en      <= sf_wr_en_comb;
		ce_rem_ctr    <= ce_rem_ctr_comb;
		sf_rd_en      <= sf_rd_en_comb;
		fee_read      <= fee_read_comb;
		read_done     <= read_done_comb;
		pc_eod_q      <= pc_eod;
		pc_wr_en_qqq  <= pc_wr_en_qq;
		pc_wr_en_qq   <= pc_wr_en_q;
		pc_wr_en_q    <= pc_wr_en_comb;
	end if;
end process THE_SYNC_PROC;

-- gk 27.03.10 data selector for sf to write the evt builder address on top of data
SF_DATA_PROC : process( CLK )
begin
	if( rising_edge(CLK) ) then
		if (RESET = '1') then  -- gk 31.05.10
			sf_data <= (others => '0');
		elsif( save_addr = '1' ) then
			sf_data(3 downto 0) <= CTS_INFORMATION_IN(3 downto 0); -- only last 4 bits are the evt builder address
			sf_data(15 downto 4) <= x"abc";
		-- gk 29.03.10 four entries to save the fee_status into sf for the subsubevent
		elsif( (add_sub_state = '1') and (add_sub_ctr = x"0") ) then
			sf_data <= x"0001"; -- gk 11.06.10
		elsif( (add_sub_state = '1') and (add_sub_ctr = x"1") ) then
			sf_data <= x"5555"; -- gk 11.06.10
		elsif( (add_sub_state = '1') and (add_sub_ctr = x"2") ) then
			sf_data <= FEE_STATUS_BITS_IN(31 downto 16);
		elsif( (add_sub_state = '1') and (add_sub_ctr = x"3") ) then
			sf_data <= FEE_STATUS_BITS_IN(15 downto 0);
		else
			sf_data <= FEE_DATA_IN;
		end if;
	end if;
end process SF_DATA_PROC;

-- combinatorial read signal for the FEE data interface, DO NOT USE DIRECTLY
fee_read_comb <= '1' when ( (sf_afull = '0') and (data_req = '1') ) --and (DATA_GBE_ENABLE_IN = '1') ) -- GbE enabled
					 else '0';

-- combinatorial write signal for the split FIFO, DO NOT USE DIRECTLY
sf_wr_en_comb <= '1' when ( (fee_read = '1') and (FEE_DATAREADY_IN = '1') ) or -- and (DATA_GBE_ENABLE_IN = '1') ) or -- GbE enabled
					(save_addr = '1') or
					(add_sub_state = '1')  -- gk 29.03.10 save the subsubevent
					 else '0';

-- gk 06.08.10
sf_real_wr_en <= '1' when ((sf_wr_en = '1') and (DATA_GBE_ENABLE_IN = '1')) else '0';

-- gk 27.03.10 do not count evt builder address as saved ipu bytes
--ce_saved_ctr <= sf_wr_en;
ce_saved_ctr <= '0' when addr_saved = '1' else sf_wr_en;

-- Statemachine for reading data payload, handling IPU channel and storing data in the SPLIT_FIFO
saveMachineProc: process( CLK )
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			saveCurrentState <= SIDLE;
			data_req         <= '0';
			rst_saved_ctr    <= '0';
			save_addr	 <= '0'; -- gk 27.03.10
			addr_saved	 <= '0'; -- gk 27.03.10
			add_sub_state    <= '0'; -- gk 29.03.10
			save_eod         <= '0'; -- gk 25.07.10
		else
			saveCurrentState <= saveNextState;
			data_req         <= data_req_comb;
			rst_saved_ctr    <= rst_saved_ctr_comb;
			save_addr	 <= save_addr_comb; -- gk 27.03.10
			addr_saved	 <= addr_saved_comb; -- gk 27.03.10
			add_sub_state    <= add_sub_state_comb; -- gk 29.03.10
			save_eod         <= save_eod_comb; -- gk 25.07.10
		end if;
	end if;
end process saveMachineProc;

saveMachine: process( saveCurrentState, CTS_START_READOUT_IN, FEE_BUSY_IN, CTS_READ_IN)
begin
	saveNextState      <= SIDLE;
	data_req_comb      <= '0';
	rst_saved_ctr_comb <= '0';
	save_addr_comb     <= '0'; -- gk 27.03.10
	addr_saved_comb    <= '0'; -- gk 27.03.10
	add_sub_state_comb <= '0'; -- gk 29.03.10
	save_eod_comb      <= '0'; -- gk 25.07.10
	case saveCurrentState is
		when SIDLE =>
			state <= x"0";
			if (CTS_START_READOUT_IN = '1') then
				saveNextState <= SAVE_EVT_ADDR; --WAIT_FOR_DATA; -- gk 27.03.10
				data_req_comb <= '1';
				rst_saved_ctr_comb <= '1';
			else
				saveNextState <= SIDLE;
			end if;
		-- gk 27.03.10
		when SAVE_EVT_ADDR =>
			state <= x"5";
			saveNextState <= WAIT_FOR_DATA;
			data_req_comb <= '1';
			save_addr_comb <= '1';
		when WAIT_FOR_DATA =>
			state <= x"1";
			if (FEE_BUSY_IN = '1') then
				saveNextState <= SAVE_DATA;
				data_req_comb <= '1';
			else
				saveNextState <= WAIT_FOR_DATA;
				data_req_comb <= '1';
			end if;
			addr_saved_comb <= '1';  -- gk 27.03.10
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
				saveNextState <= ADD_SUBSUB1; --SIDLE;  -- gk 29.03.10
			else
				saveNextState <= SCLOSE;
			end if;
		-- gk 29.03.10 new states during which the subsub bytes are saved
		when ADD_SUBSUB1 =>
			state <= x"6";
			saveNextState <= ADD_SUBSUB2;
			add_sub_state_comb <= '1';
		when ADD_SUBSUB2 =>
			state<= x"7";
			saveNextState <= ADD_SUBSUB3;
			add_sub_state_comb <= '1';
			save_eod_comb <= '1';
		when ADD_SUBSUB3 =>
			state<= x"8";
			saveNextState <= ADD_SUBSUB4;
			add_sub_state_comb <= '1';
		when ADD_SUBSUB4 =>
			state<= x"9";
			saveNextState <= SIDLE;
			add_sub_state_comb <= '1';
		when others =>
			state <= x"f";
			saveNextState <= SIDLE;
	end case;
end process saveMachine;

-- gk 29.03.10
ADD_SUB_CTR_PROC : process( CLK )
begin
	if( rising_edge( CLK ) ) then
		if( (RESET = '1') or (rst_saved_ctr = '1') ) then
			add_sub_ctr <= (others => '0');
		elsif( add_sub_state = '1' ) then
			add_sub_ctr <= add_sub_ctr + 1;
		end if;
	end if;
end process ADD_SUB_CTR_PROC;

--********
-- SAVE INCOMING EVENT HEADERS
--********

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

-- save triggerRnd from incoming data for cts response
CTS_RND_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_saved_ctr = '1') ) then
			cts_rnd       <= (others => '0');
			cts_rnd_saved <= '0';
		elsif( (saved_ctr(2 downto 0) = b"000") and (sf_wr_en = '1') and (cts_rnd_saved = '0') ) then
			cts_rnd <= sf_data;
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
			cts_trg <= sf_data;
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
			cts_len(0)           <= '0';
		elsif( (saved_ctr(2 downto 0) = b"011") and (cts_len_saved = '0') ) then
			cts_len       <= cts_len + x"4";
			cts_len_saved <= '1';
		end if;
	end if;
end process CTS_SIZE_PROC;

-- gk 22.07.10
CTS_ADDR_PROC : process(CLK)
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_saved_ctr = '1') ) then
			cts_addr       <= (others => '0');
			cts_addr_saved <= '0';
		elsif( (saved_ctr(2 downto 0) = b"011") and (sf_wr_en = '1') and (cts_addr_saved = '0') ) then
			cts_addr       <= sf_data;
			cts_addr_saved <= '1';
		end if;
	end if;
end process CTS_ADDR_PROC;

--******
-- SAVE FIRST EVENT HEADER VALUES
--******

-- gk 22.07.10
FIRST_RUN_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			first_run_trg <= (others => '0');
			first_run_addr <= (others => '0');
			first_run_lock <= '0';
		elsif (first_run_lock = '0') and (cts_addr_saved = '1') then
			first_run_trg <= cts_trg;
			first_run_addr <= cts_addr;
			first_run_lock <= '1';
		-- important: value saved by saveMachine but incremented by loadMachine
		elsif (first_run_lock = '1') and (inc_trg_ctr = '1') then
			first_run_trg <= first_run_trg + x"1";
		end if;
	end if;
end process FIRST_RUN_PROC;

-- gk 25.07.10
SAVED_EVT_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			saved_events_ctr <= (others => '0');
		elsif (save_eod = '1') then
			saved_events_ctr <= saved_events_ctr + x"1";
		end if;
	end if;
end process SAVED_EVT_CTR_PROC;


-- gk 20.07.10
INC_DATA_CTR_proc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (rst_saved_ctr = '1') then
			inc_data_ctr <= (others => '0');
		elsif (sf_wr_en = '1') and (data_req = '1') then
			inc_data_ctr(31 downto 1) <= inc_data_ctr(31 downto 1) + x"1";
		end if;
	end if;
end process INC_DATA_CTR_proc;

------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

-- Split FIFO
THE_SPLIT_FIFO: fifo_32kx16x8_mb2
port map( 
	-- Byte swapping for correct byte order on readout side of FIFO
	Data(7 downto 0)  => sf_data(15 downto 8),
	Data(8)           => '0',
	Data(16 downto 9) => sf_data(7 downto 0),
	Data(17)          => save_eod,
	WrClock         => CLK,
	RdClock         => CLK,
	WrEn            => sf_real_wr_en, -- gk 06.08.10 --sf_wr_en,
	RdEn            => sf_rd_en,
	Reset           => RESET,
	RPReset         => RESET,
	AmEmptyThresh   => b"0000_0000_0000_0010", -- one byte ahead
	AmFullThresh    =>  b"111_1111_1110_1111", -- 0x7fef = 32751
	Q(7 downto 0)   => pc_data,
	Q(8)            => load_eod,
	WCNT            => sf_wcnt,
	RCNT            => sf_rcnt,
	Empty           => sf_empty,
	AlmostEmpty     => sf_aempty,
	Full            => sf_full,
	AlmostFull      => sf_afull
);

------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

-- gk 25.07.10
EVENT_WAITING_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			event_waiting <= '0';
		elsif (loaded_events_ctr /= saved_events_ctr) then
			event_waiting <= '1';
		else
			event_waiting <= '0';
		end if;
	end if;
end process EVENT_WAITING_PROC;

-- write signal for PC data
pc_wr_en_comb <= '1' when ((data_phase = '1') and (sf_rd_en = '1')) or
			(pad_phase = '1') or
			((load_sub = '1') and (sf_rd_en = '1')) or
			((drop_sub = '1') and (sf_rd_en = '1')) or
			((drop_event = '1') and (sf_rd_en = '1'))
			else '0';

sf_rd_en_comb <= '1' when ( (sf_aempty = '0') and (rem_phase = '1') and  (remove_done = '0') ) or
			--( (sf_aempty = '0') and (data_phase = '1') and (read_done = '0') ) or
			( (sf_aempty = '0') and (data_phase = '1') and (load_eod = '0') ) or  -- gk 26.07.10
			( (sf_aempty = '0') and (load_sub = '1') and (load_sub_done = '0') ) or -- gk 30.03.10
			( (sf_aempty = '0') and (drop_event = '1') and (load_eod = '0') ) or
			( (sf_aempty = '0') and (drop_sub = '1') and (load_sub_done = '0') )
			else '0';

ce_rem_ctr_comb <= '1' when ( (sf_aempty = '0') and (rem_phase = '1') and ( remove_done = '0') )
			else '0';

-- FIFO data delay process (also forces padding bytes to known value)
THE_DATA_DELAY_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if( pad_data = '1' ) then
			pc_data_q <= x"aa"; -- padding for 64bit
		-- gk 21.07.10
		-- set the error flag if a broken packet is sent
		elsif (drop_sub = '1') and (load_sub_ctr = x"3") then
			pc_data_q <= pc_data(7 downto 3) & '1' & pc_data(1 downto 0);
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
		if (RESET = '1') then
			loadCurrentState <= LIDLE;
			rst_rem_ctr      <= '0';
			rem_phase        <= '0';
			calc_pad         <= '0';
			data_phase       <= '0';
			pad_phase        <= '0';
			pc_sos           <= '0';
			pc_eod           <= '0';
			rst_regs         <= '0';
			pad_data         <= '0';
			load_sub         <= '0'; -- gk 30.03.10
			drop_sub         <= '0'; -- gk 25.07.10
			drop_event       <= '0'; -- gk 25.07.10
			drop_small       <= '0'; -- gk 25.07.10
			drop_large       <= '0'; -- gk 25.07.10
			drop_headers     <= '0'; -- gk 25.07.10
			inc_trg_ctr      <= '0'; -- gk 26.07.10
			found_empty_evt  <= '0'; -- gk 01.10.10
		else
			loadCurrentState <= loadNextState;
			rst_rem_ctr      <= rst_rem_ctr_comb;
			rem_phase        <= rem_phase_comb;
			calc_pad         <= calc_pad_comb;
			data_phase       <= data_phase_comb;
			pad_phase        <= pad_phase_comb;
			pc_sos           <= pc_sos_comb;
			pc_eod           <= pc_eod_comb;
			rst_regs         <= rst_regs_comb;
			pad_data         <= pad_data_comb;
			load_sub         <= load_sub_comb; -- gk 30.03.1
			drop_sub         <= drop_sub_comb;  -- gk 25.07.10
			drop_event       <= drop_event_comb;  -- gk 25.07.10
			drop_small       <= drop_small_comb;  -- gk 25.07.10
			drop_large       <= drop_large_comb; -- gk 25.07.10
			drop_headers     <= drop_headers_comb; -- gk 25.07.10
			inc_trg_ctr      <= inc_trg_ctr_comb; -- gk 26.07.10
			found_empty_evt  <= found_empty_evt_comb; -- gk 01.10.10
		end if;
	end if;
end process loadMachineProc;

loadMachine : process( loadCurrentState, sf_aempty, remove_done, read_done, padding_needed, PC_READY_IN, load_sub_done, pc_sub_size, MIN_MESSAGE_SIZE_IN, MAX_MESSAGE_SIZE_IN, pc_trig_nr, first_run_trg, endpoint_addr, first_run_addr, load_eod, event_waiting)
begin
	loadNextState    <= LIDLE;
	rst_rem_ctr_comb <= '0';
	rem_phase_comb   <= '0';
	calc_pad_comb    <= '0';
	data_phase_comb  <= '0';
	pad_phase_comb   <= '0';
	pc_sos_comb      <= '0';
	pc_eod_comb      <= '0';
	rst_regs_comb    <= '0';
	pad_data_comb    <= '0';
	load_sub_comb    <= '0';  -- gk 30.03.10
	drop_sub_comb    <= '0';  -- gk 25.07.10
	drop_event_comb  <= '0';  -- gk 25.07.10
	drop_small_comb  <= '0';  -- gk 25.07.10
	drop_large_comb  <= '0';  -- gk 25.07.10
	drop_headers_comb <= '0'; -- gk 25.07.10
	inc_trg_ctr_comb <= '0';  -- gk 26.07.10
	found_empty_evt_comb <= '0'; -- gk 01.10.10
	case loadCurrentState is
		when LIDLE =>
			state2 <= x"0";
			-- gk 23.07.10
			if( (sf_aempty = '0') and (PC_READY_IN = '1') and (event_waiting = '1') and (DATA_GBE_ENABLE_IN = '1') ) then  -- gk 06.08.10
				loadNextState <= INIT;
				rst_rem_ctr_comb <= '1';
				rst_regs_comb <= '1';
			else
				loadNextState <= LIDLE;
			end if;
		when INIT =>
			state2 <= x"1";
			loadNextState <= REMOVE;
			rem_phase_comb <= '1';
		when REMOVE =>
			state2 <= x"2";
			if( remove_done = '1' ) then
				loadNextState <= WAIT_TO_REMOVE;
				inc_trg_ctr_comb <= '1';
			else
				loadNextState <= REMOVE;
				rem_phase_comb <= '1';
			end if;
		when WAIT_TO_REMOVE =>
			if (rem_ctr = x"a") then
				loadNextState <= DECIDE;
			else
				loadNextState <= WAIT_TO_REMOVE;
			end if;
		when DECIDE =>
			if (pc_sub_size >= MAX_MESSAGE_SIZE_IN) then
				loadNextState <= PAUSE_BEFORE_DROP1;
				drop_large_comb <= '1';
			elsif (pc_sub_size = b"0000_0000_0000_00") then  -- gk 01.10.10
				loadNextState <= CALCA;
				found_empty_evt_comb <= '1';
			elsif (pc_sub_size < MIN_MESSAGE_SIZE_IN) then
				loadNextState <= PAUSE_BEFORE_DROP1;
				drop_small_comb <= '1';
			elsif (pc_trig_nr + x"1" /= first_run_trg) then
				loadNextState <= PAUSE_BEFORE_DROP1;
				drop_headers_comb <= '1';
			elsif (endpoint_addr /= first_run_addr) then
				loadNextState <= PAUSE_BEFORE_DROP1;
				drop_headers_comb <= '1';
			else
				loadNextState <= CALCA;
			end if;
			calc_pad_comb <= '1';
		when CALCA =>
			state2 <= x"3";
			loadNextState <= CALCB;
			pc_sos_comb <= '1';
		when CALCB =>
			-- we need a branch in case of length "0"!!!!
			state2 <= x"4";
			loadNextState <= LOAD;
			data_phase_comb <= '1';
		when LOAD =>
			state2 <= x"5";
			-- gk 31.03.10 after loading subevent data read the subsubevent from sf
			if (load_eod = '1') then
				loadNextState <= LOAD_SUBSUB;
			else
				loadNextState <= LOAD;
				data_phase_comb <= '1';
			end if;
		-- gk 31.03.10
		when LOAD_SUBSUB =>
			state2 <= x"d";
			if( load_sub_done = '1' ) then
				if( padding_needed = '0' ) then
					loadNextState <= CALCC;
				else
					loadNextState <= PAD0;
					pad_phase_comb <= '1';
				end if;
			else
				loadNextState <= LOAD_SUBSUB;
				load_sub_comb <= '1';
			end if;
		when PAD0 =>
			state2 <= x"6";
			loadNextState <= PAD1;
			pad_phase_comb <= '1';
			pad_data_comb <= '1';
		when PAD1 =>
			state2 <= x"7";
			loadNextState <= PAD2;
			pad_phase_comb <= '1';
			pad_data_comb <= '1';
		when PAD2 =>
			state2 <= x"8";
			loadNextState <= PAD3;
			pad_phase_comb <= '1';
			pad_data_comb <= '1';
		when PAD3 =>
			state2 <= x"9";
			loadNextState <= CALCC;
			pad_data_comb <= '1';
		when CALCC =>
			state2 <= x"a";
			loadNextState <= CLOSE;
			pc_eod_comb <= '1';
		when CLOSE =>
			state2 <= x"b";
			loadNextState <= WAIT_PC;
			rst_regs_comb <= '1';
		when WAIT_PC =>
			state2 <= x"c";
			if( PC_READY_IN = '1' ) then
				loadNextState <= LIDLE;
			else
				loadNextState <= WAIT_PC;
			end if;
		when PAUSE_BEFORE_DROP1 =>
			loadNextState <= PAUSE_BEFORE_DROP2;
			pc_sos_comb <= '1';
		when PAUSE_BEFORE_DROP2 =>
			loadNextState <= DROP;
			drop_event_comb <= '1';
		-- gk 23.07.10
		when DROP =>
			state2 <= x"e";
			-- when data is dropped the eod marker stands as its end
			if (load_eod = '1') then
				loadNextState <= DROP_SUBSUB;
			else
				loadNextState <= DROP;
				drop_event_comb <= '1';
			end if;
		-- gk 25.07.10
		when DROP_SUBSUB =>
			if (load_sub_done = '1') then
				if( padding_needed = '0' ) then
					loadNextState <= CALCC;
				else
					loadNextState <= PAD0;
					pad_phase_comb <= '1';
				end if;
			else
				loadNextState <= DROP_SUBSUB;
				drop_sub_comb <= '1';
			end if;
		when others =>
			state2 <= x"f";
			loadNextState <= LIDLE;
	end case;
end process loadMachine;

-- gk 25.07.10
INVALID_STATS_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			dropped_lr_events_ctr <= (others => '0');
			dropped_sm_events_ctr <= (others => '0');
			headers_invalid_ctr   <= (others => '0');
			dropped_ctr           <= (others => '0');
			invalid_hsize_ctr     <= (others => '0');
			found_empty_evt_ctr   <= (others => '0');  -- gk 01.10.10
		elsif (rst_regs = '1') then
			invalid_hsize_lock <= '0';
		elsif (drop_small = '1') then
			dropped_sm_events_ctr <= dropped_sm_events_ctr + x"1";
			dropped_ctr <= dropped_ctr + x"1";
		elsif (drop_large = '1') then
			dropped_lr_events_ctr <= dropped_lr_events_ctr + x"1";
			dropped_ctr <= dropped_ctr + x"1";
		elsif (drop_headers = '1') then
			headers_invalid_ctr   <= headers_invalid_ctr + x"1";
			dropped_ctr <= dropped_ctr + x"1";
		elsif (load_eod_q = '1') and (read_size_q /= x"3fffe") and (invalid_hsize_lock = '0') then -- ??
			invalid_hsize_ctr <= invalid_hsize_ctr + x"1";
			invalid_hsize_lock <= '1';
		-- gk 01.10.10
		elsif (found_empty_evt = '1') then
			found_empty_evt_ctr <= found_empty_evt_ctr + x"1";
		end if;
	end if;
end process INVALID_STATS_PROC;

-- gk 05.08.10
INVALID_H_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		load_eod_q  <= load_eod;
		read_size_q <= read_size;
	end if;
end process INVALID_H_PROC;

-- gk 26.04.10
READOUT_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if ((RESET = '1') or (READOUT_CTR_VALID_IN = '1')) then
			readout_ctr <= READOUT_CTR_IN;
			readout_ctr_lock <= '0';
		elsif (pc_sos = '1') then
			readout_ctr <= readout_ctr + x"1";
		end if;
	end if;
end process READOUT_CTR_PROC;

--******
-- SELECTION OF EVENT BUILDER
--******

-- gk 27.03.10
bank_select_proc : process( CLK )
begin
	if rising_edge( CLK ) then
		-- gk 29.03.10
		if( (RESET = '1') or (rst_regs = '1') ) then
			bank_select <= "0000";
		-- gk 01.06.10 THERE WAS A BUG, IT SHOUDL BE TAKEN FROM SF_Q
		elsif( (sf_rd_en = '1') and (rem_ctr = x"2") ) then
			bank_select <= pc_data(3 downto 0); --CTS_INFORMATION_IN(3 downto 0);
		end if;
	end if;
end process bank_select_proc;

-- gk 29.03.10
start_config_proc : process( CLK )
begin
	if rising_edge( CLK ) then
		if( (RESET = '1') or (config_done = '1') or (rst_regs = '1') ) then
			start_config <= '0';
		elsif( (sf_rd_en = '1') and (rem_ctr = x"2") ) then  -- gk 01.06.10
			start_config <= '1';
		end if;
	end if;
end process start_config_proc;


--******
-- LOAD SUBSUBEVENT
--******

-- gk 30.03.10
load_sub_ctr_comb <= '1' when ( ((load_sub = '1') or (drop_sub = '1')) and (load_sub_done = '0') and (sf_aempty = '0') )
				else '0';

-- gk 30.03.10
LOAD_SUB_CTR_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_regs = '1') ) then  -- gk 08.04.10
			load_sub_ctr <= (others => '0');
		elsif( (load_sub_ctr_comb = '1') ) then
			load_sub_ctr <= load_sub_ctr + 1;
		end if;
	end if;
end process LOAD_SUB_CTR_PROC;

-- gk 30.03.10
-- load_sub_done_comb <= '1' when ((load_sub_ctr = x"7") and (drop_sub = '0')) or
-- 				((load_sub_ctr = x"4") and (drop_sub = '1'))
-- 				else '0';
load_sub_done_comb <= '1' when (load_sub_ctr = x"4") else '0';

-- gk 30.03.10
LOAD_SUB_DONE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if ( (RESET = '1') or (rst_regs = '1') ) then  -- gk 08.04.10
			load_sub_done <= '0';
		else
			load_sub_done <= load_sub_done_comb;
		end if;
	end if;
end process LOAD_SUB_DONE_PROC;

--******
-- EXTRACT EVENT HEADERS FROM SPLITFIFO
--******

-- Counter for stripping the unneeded parts of the data stream, and saving the important parts
THE_REMOVE_CTR: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_rem_ctr = '1') ) then
			rem_ctr <= (others => '0');
		elsif( (ce_rem_ctr = '1') ) then
			rem_ctr <= rem_ctr + 1;
		end if;
	end if;
end process THE_REMOVE_CTR;

remove_done_comb <= '1' when ( rem_ctr = x"8" ) else '0'; --( rem_ctr = x"6" ) else '0';  -- gk 29.03.10 two more for evt builder address

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

-- gk 26.04.10
TRIG_RANDOM_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if ((RESET = '1') or (rst_regs = '1')) then
			trig_random <= (others => '0');
		elsif ((sf_rd_en = '1') and (rem_ctr = x"4")) then
			trig_random <= pc_data;
		end if;
	end if;
end process TRIG_RANDOM_PROC;

-- extract the trigger number from splitfifo data
THE_TRG_NR_PROC: process( CLK )
begin
	if rising_edge(CLK) then
		if   ( (RESET = '1') or (rst_regs = '1') ) then
			pc_trig_nr <= (others => '0');
		elsif( (sf_rd_en = '1') and (rem_ctr = x"6") ) then  -- x"4" gk 29.03.10
			pc_trig_nr(7 downto 0) <= pc_data;
		elsif( (sf_rd_en = '1') and (rem_ctr = x"5") ) then  -- x"3" gk 29.03.10
			pc_trig_nr(15 downto 8) <= pc_data;
		end if;
	end if;
end process THE_TRG_NR_PROC;

-- extract the subevent size from the splitfifo data, convert it from 32b to 8b units,
-- and in case of padding needed increase it accordingly
THE_SUB_SIZE_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_regs = '1') ) then
			pc_sub_size <= (others => '0');
		elsif( (sf_rd_en = '1') and (rem_ctr = x"8") ) then  -- x"6" gk 29.03.10
			pc_sub_size(9 downto 2) <= pc_data;
		elsif( (sf_rd_en = '1') and (rem_ctr = x"7") ) then  -- x"5" gk 29.03.10
			pc_sub_size(17 downto 10) <= pc_data;
		-- gk 20.07.10
		-- gk 30.03.10 bug fixed in the way that is written below
		-- gk 27.03.10 should be corrected by sending padding_needed signal to pc and take care of it when setting sub_size_to_save
		elsif( (calc_pad = '1') and (padding_needed = '1') ) then
			pc_sub_size <= pc_sub_size + x"4" + x"8"; -- BUG: SubEvtSize does NOT include 64bit padding!!!
		elsif( (calc_pad = '1') and (padding_needed = '0') ) then
			pc_sub_size <= pc_sub_size + x"8";
		end if;
	end if;
end process THE_SUB_SIZE_PROC;

-- gk 25.07.10
ENDP_ADDRESS_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (rst_regs = '1') then
			endpoint_addr <= (others => '0');
			endp_addr_lock <= '0';
		elsif( (rem_ctr = x"a") and (endp_addr_lock = '0') ) then
			endpoint_addr(7 downto 0) <= pc_data;
			endp_addr_lock <= '1';
		elsif( (sf_rd_en = '1') and (rem_ctr = x"9") ) then
			endpoint_addr(15 downto 8) <= pc_data;
			endp_addr_lock <= '0';
		end if;
	end if;
end process ENDP_ADDRESS_PROC;



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

-- number of bytes to read from split fifo
THE_READ_SIZE_PROC: process( CLK )
begin
	if( rising_edge(CLK) ) then
		if   ( (RESET = '1') or (rst_regs = '1') ) then --(rst_rem_ctr = '1') ) then
			read_size   <= (others => '0');
		elsif( (sf_rd_en = '1') and (rem_ctr = x"8") ) then  -- x"6" gk 29.03.10
			read_size(9 downto 2) <= pc_data;
		elsif( (sf_rd_en = '1') and (rem_ctr = x"7") ) then  -- x"5" gk 29.03.10
			read_size(17 downto 10) <= pc_data;
		elsif( ((sf_rd_en = '1') and (data_phase = '1')) ) then
			read_size <= read_size - 1;
		-- gk 25.07.10
		elsif( ((sf_rd_en = '1') and (drop_event = '1')) ) then
			read_size <= read_size - 1;
		end if;
	end if;
end process THE_READ_SIZE_PROC;

read_done_comb <= '1' when (read_size < 3 ) else '0'; -- "2"

--******
-- EVENTS COUNTERS
--******

-- gk 25.07.10
LOADED_EVT_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			loaded_events_ctr <= (others => '0');
		elsif (remove_done = '1') then
			loaded_events_ctr <= loaded_events_ctr + x"1";
		end if;
	end if;
end process LOADED_EVT_CTR_PROC;

-- gk 25.07.10
CONSTR_EVENTS_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			constr_events_ctr <= (others => '0');
		elsif (pc_eod = '1') then
			constr_events_ctr <= constr_events_ctr + x"1";
		end if;
	end if;
end process CONSTR_EVENTS_CTR_PROC;

------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------

-- Debug signals
debug(0)              <= sf_full;
debug(1)              <= sf_empty;
debug(2)              <= sf_afull;
debug(3)              <= sf_aempty;

debug(7 downto  4)    <= state2;

debug(11 downto 8)    <= state;

dbg_bs_proc : process(CLK)
begin
	if rising_edge(CLK) then
		if RESET = '1' then
			debug(15 downto 12) <= (others => '0');
		elsif ( (sf_rd_en = '1') and (rem_ctr = x"3") ) then
			debug(15 downto 12) <= bank_select;
		end if;
	end if;
end process dbg_bs_proc;

debug(16)             <= config_done;
debug(17)             <= remove_done;
debug(18)             <= read_done;
debug(19)             <= padding_needed;

debug(20)             <= load_sub_done;

dbg_cts_inf_proc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			debug(39 downto 32) <= (others => '0');
		elsif ( save_addr = '1' ) then
			debug(39 downto 32) <= CTS_INFORMATION_IN;
		end if;
	end if;
end process dbg_cts_inf_proc;

debug(47 downto 40) <= (others => '0');


debug(63 downto 48)   <= actual_message_size(15 downto 0);

dbg_pc_sub_size_proc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			debug(81 downto 64) <= (others => '0');
		elsif (loadCurrentState = DECIDE) then
			debug(81 downto 64) <= pc_sub_size;
		end if;
	end if;
end process dbg_pc_sub_size_proc;

dbg_empty_proc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (rst_regs = '1') then
			debug(84 downto 82) <= (others => '0');
		elsif (read_size = 2) then
			debug(82) <= sf_empty;
		elsif (read_size = 1) then
			debug(83) <= sf_empty;
		elsif (read_size = 0) then
			debug(84) <= sf_empty;
		end if;
	end if;
end process dbg_empty_proc;

debug(95 downto 85) <= (others => '0');

dbg_inc_ctr_proc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			debug(127 downto 96) <= (others => '1');
		elsif (saveCurrentState = SCLOSE) then
			debug(127 downto 96) <= inc_data_ctr;
		end if;
	end if;
end process dbg_inc_ctr_proc;

debug(143 downto 128) <= dropped_sm_events_ctr(15 downto 0);
debug(159 downto 144) <= dropped_lr_events_ctr(15 downto 0);

debug(175 downto 160) <= headers_invalid_ctr(15 downto 0);
debug(191 downto 176) <= (others => '0');

dbg_cts_q_proc : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			cts_len_q <= (others => '0');
			cts_rnd_q <= (others => '0');
			cts_trg_q <= (others => '0');
			cts_addr_q <= (others => '0');
		elsif (cts_len_saved = '1') then
			cts_len_q <= cts_len(16 downto 1);
			cts_addr_q <= cts_addr;
			cts_rnd_q <= cts_rnd;
			cts_trg_q <= cts_trg;
		end if;
	end if;
end process dbg_cts_q_proc;

debug(207 downto 192) <= cts_trg_q;
debug(223 downto 208) <= cts_rnd_q;
debug(239 downto 224) <= cts_addr_q;
debug(255 downto 240) <= cts_len_q;
debug(271 downto 256) <= first_run_trg;
debug(287 downto 272) <= first_run_addr;

debug(303 downto 288) <= saved_events_ctr;
debug(319 downto 304) <= loaded_events_ctr;

debug(335 downto 320) <= constr_events_ctr(15 downto 0);
debug(351 downto 336) <= dropped_ctr(15 downto 0);

debug(367 downto 352) <= invalid_hsize_ctr;
debug(383 downto 368) <= (others => '0');

MONITOR_OUT(31 downto 0)    <= constr_events_ctr;
MONITOR_OUT(63 downto 32)   <= dropped_ctr;
MONITOR_OUT(95 downto 64)   <= headers_invalid_ctr;
MONITOR_OUT(127 downto 96)  <= dropped_sm_events_ctr;
MONITOR_OUT(159 downto 128) <= dropped_lr_events_ctr;
MONITOR_OUT(163 downto 160) <= b"1111" when (sf_afull = '1') else b"0000";
MONITOR_OUT(191 downto 164) <= (others => '0');
MONITOR_OUT(223 downto 192) <= found_empty_evt_ctr; -- gk 01.10.10

-- Outputs
FEE_READ_OUT             <= fee_read;
CTS_ERROR_PATTERN_OUT    <= cts_error_pattern;
CTS_DATA_OUT             <= cts_data;
CTS_DATAREADY_OUT        <= cts_dataready;
CTS_READOUT_FINISHED_OUT <= cts_readout_finished;
CTS_LENGTH_OUT           <= cts_length;

PC_SOS_OUT               <= pc_sos;
PC_EOD_OUT               <= pc_eod; -- gk 26.07.10 --pc_eod_q;
PC_DATA_OUT              <= pc_data_q;
PC_WR_EN_OUT             <= pc_wr_en_qq;

PC_TRIG_NR_OUT           <= readout_ctr(23 downto 16) & pc_trig_nr & trig_random;

PC_SUB_SIZE_OUT          <= b"0000_0000_0000_00" & pc_sub_size;
PC_PADDING_OUT           <= padding_needed;

DEBUG_OUT                <= debug;

end architecture;