LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

use work.trb_net_gbe_components.all;

--********
-- Response Constructor which responds to Ping messages
--

entity trb_net16_gbe_response_constructor_Ping is
port (
	CLK			: in	std_logic;  -- system clock
	RESET			: in	std_logic;
	
-- INTERFACE	
	PS_DATA_IN		: in	std_logic_vector(8 downto 0);
	PS_WR_EN_IN		: in	std_logic;
	PS_ACTIVATE_IN		: in	std_logic;
	PS_RESPONSE_READY_OUT	: out	std_logic;
	PS_BUSY_OUT		: out	std_logic;
	PS_SELECTED_IN		: in	std_logic;
	PS_SRC_MAC_ADDRESS_IN	: in	std_logic_vector(47 downto 0);
	PS_DEST_MAC_ADDRESS_IN  : in	std_logic_vector(47 downto 0);
	PS_SRC_IP_ADDRESS_IN	: in	std_logic_vector(31 downto 0);
	PS_DEST_IP_ADDRESS_IN	: in	std_logic_vector(31 downto 0);
	PS_SRC_UDP_PORT_IN	: in	std_logic_vector(15 downto 0);
	PS_DEST_UDP_PORT_IN	: in	std_logic_vector(15 downto 0);
	
	TC_RD_EN_IN		: in	std_logic;
	TC_DATA_OUT		: out	std_logic_vector(8 downto 0);
	TC_FRAME_SIZE_OUT	: out	std_logic_vector(15 downto 0);
	TC_FRAME_TYPE_OUT	: out	std_logic_vector(15 downto 0);
	
	TC_DEST_MAC_OUT		: out	std_logic_vector(47 downto 0);
	TC_DEST_IP_OUT		: out	std_logic_vector(31 downto 0);
	TC_DEST_UDP_OUT		: out	std_logic_vector(15 downto 0);
	TC_SRC_MAC_OUT		: out	std_logic_vector(47 downto 0);
	TC_SRC_IP_OUT		: out	std_logic_vector(31 downto 0);
	TC_SRC_UDP_OUT		: out	std_logic_vector(15 downto 0);
	
	TC_BUSY_IN		: in	std_logic;
		
	RECEIVED_FRAMES_OUT	: out	std_logic_vector(15 downto 0);
	SENT_FRAMES_OUT		: out	std_logic_vector(15 downto 0);
-- END OF INTERFACE

-- debug
	DEBUG_OUT		: out	std_logic_vector(31 downto 0)
);
end trb_net16_gbe_response_constructor_Ping;


architecture trb_net16_gbe_response_constructor_Ping of trb_net16_gbe_response_constructor_Ping is

attribute HGROUP : string;
attribute HGROUP of trb_net16_gbe_response_constructor_Ping : architecture is "GBE_MAIN_group";

attribute syn_encoding	: string;

type dissect_states is (IDLE, SAVE, WAIT_FOR_LOAD, LOAD, CLEANUP);
signal dissect_current_state, dissect_next_state : dissect_states;
attribute syn_encoding of dissect_current_state: signal is "safe,gray";

signal ff_wr_en                 : std_logic;
signal ff_rd_en                 : std_logic;
signal resp_bytes_ctr           : std_logic_vector(15 downto 0);
signal ff_empty                 : std_logic;
signal ff_full                  : std_logic;
signal ff_q                     : std_logic_vector(8 downto 0);
signal ff_rd_lock               : std_logic;

signal state                    : std_logic_vector(3 downto 0);
signal rec_frames               : std_logic_vector(15 downto 0);
signal sent_frames              : std_logic_vector(15 downto 0);

begin

DISSECT_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			dissect_current_state <= IDLE;
		else
			dissect_current_state <= dissect_next_state;
		end if;
	end if;
end process DISSECT_MACHINE_PROC;

DISSECT_MACHINE : process(dissect_current_state, PS_WR_EN_IN, PS_ACTIVATE_IN, PS_DATA_IN, ff_q, ff_rd_lock, TC_BUSY_IN)
begin
	case dissect_current_state is
	
		when IDLE =>
			state <= x"1";
			if (PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
				dissect_next_state <= SAVE;
			else
				dissect_next_state <= IDLE;
			end if;
		
		when SAVE =>
			state <= x"2";
			if (PS_DATA_IN(8) = '1') then
				dissect_next_state <= WAIT_FOR_LOAD;
			else
				dissect_next_state <= SAVE;
			end if;
			
		when WAIT_FOR_LOAD =>
			state <= x"3";
			if (TC_BUSY_IN = '0') then
				dissect_next_state <= LOAD;
			else
				dissect_next_state <= WAIT_FOR_LOAD;
			end if;
		
		when LOAD =>
			state <= x"4";
			if (ff_q(8) = '1') and (ff_rd_lock = '0') then
				dissect_next_state <= CLEANUP;
			else
				dissect_next_state <= LOAD;
			end if;
		
		when CLEANUP =>
			state <= x"5";
			dissect_next_state <= IDLE;
	
	end case;
end process DISSECT_MACHINE;

PS_BUSY_OUT <= '0' when dissect_current_state = IDLE else '1';

ff_wr_en <= '1' when (PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') else '0';

FF_RD_LOCK_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			ff_rd_lock <= '1';
		elsif (dissect_current_state = LOAD and ff_rd_en = '1') then
			ff_rd_lock <= '0';
		else 
			ff_rd_lock <= '1';
		end if;
	end if;
end process FF_RD_LOCK_PROC;

-- TODO: put a smaller fifo here
FRAME_FIFO: fifo_4096x9
port map( 
	Data                => PS_DATA_IN,
	WrClock             => CLK,
	RdClock             => CLK,
	WrEn                => ff_wr_en,
	RdEn                => ff_rd_en,
	Reset               => RESET,
	RPReset             => RESET,
	Q                   => ff_q,
	Empty               => ff_empty,
	Full                => ff_full
);

ff_rd_en <= '1' when (TC_RD_EN_IN = '1' and PS_SELECTED_IN = '1') else '0';

TC_DATA_OUT <= ff_q;

PS_RESPONSE_READY_OUT <= '1' when (dissect_current_state = LOAD) else '0';

TC_FRAME_SIZE_OUT <= resp_bytes_ctr + x"1";

TC_FRAME_TYPE_OUT <= x"0008";
TC_DEST_MAC_OUT   <= x"9a680f201300";
TC_DEST_IP_OUT    <= x"0100a8c0";
TC_DEST_UDP_OUT   <= x"50c3";
TC_SRC_MAC_OUT    <= x"efbeefbe0000";
TC_SRC_IP_OUT     <= x"0b00a8c0";
TC_SRC_UDP_OUT    <= x"50c3";

RESP_BYTES_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (dissect_current_state = IDLE) then
			resp_bytes_ctr <= (others => '0');
		elsif (dissect_current_state = SAVE) then
			resp_bytes_ctr <= resp_bytes_ctr + x"1";
		end if;
	end if;
end process RESP_BYTES_CTR_PROC;

REC_FRAMES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			rec_frames <= (others => '0');
		elsif (dissect_current_state = IDLE and PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
			rec_frames <= rec_frames + x"1";
		end if;
	end if;
end process REC_FRAMES_PROC;

SENT_FRAMES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			sent_frames <= (others => '0');
		elsif (dissect_current_state = WAIT_FOR_LOAD and TC_BUSY_IN = '0') then
			sent_frames <= sent_frames + x"1";
		end if;
	end if;
end process SENT_FRAMES_PROC;

RECEIVED_FRAMES_OUT <= rec_frames;
SENT_FRAMES_OUT     <= sent_frames;

-- **** debug
DEBUG_OUT(3 downto 0)   <= state;
DEBUG_OUT(4)            <= ff_empty;
DEBUG_OUT(7 downto 5)   <= "000";
DEBUG_OUT(8)            <= ff_full;
DEBUG_OUT(11 downto 9)  <= "000";
DEBUG_OUT(31 downto 12) <= (others => '0');
-- ****

end trb_net16_gbe_response_constructor_Ping;


