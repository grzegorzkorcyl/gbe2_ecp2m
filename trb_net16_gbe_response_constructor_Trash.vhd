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
-- gets all the data which is not supposed to be received by other protocols
-- simply clears the fifo from garbage

entity trb_net16_gbe_response_constructor_Trash is
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
	TC_IP_PROTOCOL_OUT	: out	std_logic_vector(7 downto 0);	
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
end trb_net16_gbe_response_constructor_Trash;


architecture trb_net16_gbe_response_constructor_Trash of trb_net16_gbe_response_constructor_Trash is

--attribute HGROUP : string;
--attribute HGROUP of trb_net16_gbe_response_constructor_Trash : architecture is "GBE_MAIN_group";

attribute syn_encoding	: string;

type dissect_states is (IDLE, SAVE, CLEANUP);
signal dissect_current_state, dissect_next_state : dissect_states;
attribute syn_encoding of dissect_current_state: signal is "safe,gray";

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

DISSECT_MACHINE : process(dissect_current_state, PS_WR_EN_IN, PS_ACTIVATE_IN, PS_DATA_IN)
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
				dissect_next_state <= CLEANUP;
			else
				dissect_next_state <= SAVE;
			end if;
		
		when CLEANUP =>
			state <= x"5";
			dissect_next_state <= IDLE;
	
	end case;
end process DISSECT_MACHINE;

PS_BUSY_OUT <= '0' when dissect_current_state = IDLE else '1';

TC_DATA_OUT <= '0' & x"ab";

PS_RESPONSE_READY_OUT <= '0';

TC_FRAME_SIZE_OUT <= (others => '0');

TC_FRAME_TYPE_OUT <= (others => '0');
TC_DEST_MAC_OUT   <= (others => '0');
TC_DEST_IP_OUT    <= (others => '0');
TC_DEST_UDP_OUT   <= (others => '0');
TC_SRC_MAC_OUT    <= (others => '0');
TC_SRC_IP_OUT     <= (others => '0');
TC_SRC_UDP_OUT    <= (others => '0');
TC_IP_PROTOCOL_OUT <= (others => '0');

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

RECEIVED_FRAMES_OUT <= rec_frames;
SENT_FRAMES_OUT     <= (others => '0');

-- **** debug
DEBUG_OUT(3 downto 0)   <= state;
DEBUG_OUT(31 downto 4) <= (others => '0');
-- ****

end trb_net16_gbe_response_constructor_Trash;


