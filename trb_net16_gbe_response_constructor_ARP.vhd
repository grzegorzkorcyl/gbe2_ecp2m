LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
USE IEEE.std_logic_UNSIGNED.ALL;

library work;
use work.trb_net_std.all;
use work.trb_net_components.all;
use work.trb_net16_hub_func.all;

use work.trb_net_gbe_components.all;
use work.trb_net_gbe_protocols.all;

--********
-- creates a reply for an incoming ARP request

entity trb_net16_gbe_response_constructor_ARP is
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
end trb_net16_gbe_response_constructor_ARP;


architecture trb_net16_gbe_response_constructor_ARP of trb_net16_gbe_response_constructor_ARP is

--attribute HGROUP : string;
--attribute HGROUP of trb_net16_gbe_response_constructor_ARP : architecture is "GBE_MAIN_group";

attribute syn_encoding	: string;

type dissect_states is (IDLE, READ_FRAME, DECIDE, LOAD_FRAME, WAIT_FOR_LOAD, CLEANUP);
signal dissect_current_state, dissect_next_state : dissect_states;
attribute syn_encoding of dissect_current_state: signal is "safe,gray";

signal saved_opcode             : std_logic_vector(15 downto 0);
signal saved_sender_ip          : std_logic_vector(31 downto 0);
signal saved_target_ip          : std_logic_vector(31 downto 0);
signal data_ctr                 : integer range 0 to 30;
signal values                   : std_logic_vector(223 downto 0);
signal tc_data                  : std_logic_vector(8 downto 0);

signal state                    : std_logic_vector(3 downto 0);
signal rec_frames               : std_logic_vector(15 downto 0);
signal sent_frames              : std_logic_vector(15 downto 0);

begin

values(15 downto 0)    <= x"0100";  -- hardware type
values(31 downto 16)   <= x"0008";  -- protocol type
values(39 downto 32)   <= x"06";  -- hardware size
values(47 downto 40)   <= x"04";  -- protocol size
values(63 downto 48)   <= x"0200"; --opcode (reply)
values(111 downto 64)  <= g_MY_MAC;  -- sender (my) mac
values(143 downto 112) <= g_MY_IP;
values(191 downto 144) <= PS_SRC_MAC_ADDRESS_IN;  -- target mac
values(223 downto 192) <= saved_sender_ip;  -- target ip

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

DISSECT_MACHINE : process(dissect_current_state, g_MY_IP, PS_WR_EN_IN, PS_ACTIVATE_IN, PS_DATA_IN, TC_BUSY_IN, data_ctr, PS_SELECTED_IN, saved_target_ip)
begin
	case dissect_current_state is
	
		when IDLE =>
			state <= x"1";
			if (PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
				dissect_next_state <= READ_FRAME;
			else
				dissect_next_state <= IDLE;
			end if;
		
		when READ_FRAME =>
			state <= x"2";
			if (PS_DATA_IN(8) = '1') then
				dissect_next_state <= DECIDE;
			else
				dissect_next_state <= READ_FRAME;
			end if;
			
		when DECIDE =>
			state <= x"3";
			-- in case the request is not for me, drop it
			if (saved_target_ip /= g_MY_IP) then
				dissect_next_state <= IDLE;
			else
				dissect_next_state <= WAIT_FOR_LOAD;
			end if;
			
		when WAIT_FOR_LOAD =>
			state <= x"3";
			
			if (TC_BUSY_IN = '0' and PS_SELECTED_IN = '1') then
				dissect_next_state <= LOAD_FRAME;
			else
				dissect_next_state <= WAIT_FOR_LOAD;
			end if;
		
		when LOAD_FRAME =>
			state <= x"4";
			if (data_ctr = 28) then
				dissect_next_state <= CLEANUP;
			else
				dissect_next_state <= LOAD_FRAME;
			end if;
		
		when CLEANUP =>
			state <= x"e";
			dissect_next_state <= IDLE;
	
	end case;
end process DISSECT_MACHINE;

DATA_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (dissect_current_state = IDLE) or (dissect_current_state = WAIT_FOR_LOAD) then
			data_ctr <= 1;
		elsif (dissect_current_state = READ_FRAME and PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then  -- in case of saving data from incoming frame
			data_ctr <= data_ctr + 1;
		elsif (dissect_current_state = LOAD_FRAME and TC_RD_EN_IN = '1' and PS_SELECTED_IN = '1') then  -- in case of constructing response
			data_ctr <= data_ctr + 1;
		end if;
	end if;
end process DATA_CTR_PROC;

SAVE_VALUES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			saved_opcode    <= (others => '0');
			saved_sender_ip <= (others => '0');
			saved_target_ip <= (others => '0');
		elsif (dissect_current_state = READ_FRAME) then
			case (data_ctr) is
				
				when 7 =>
					saved_opcode(7 downto 0) <= PS_DATA_IN(7 downto 0);
				when 8 =>
					saved_opcode(15 downto 8) <= PS_DATA_IN(7 downto 0);
					
				
				when 14 =>
					saved_sender_ip(7 downto 0) <= PS_DATA_IN(7 downto 0);
				when 15 =>
					saved_sender_ip(15 downto 8) <= PS_DATA_IN(7 downto 0);
				when 16 =>
					saved_sender_ip(23 downto 16) <= PS_DATA_IN(7 downto 0);
				when 17 =>
					saved_sender_ip(31 downto 24) <= PS_DATA_IN(7 downto 0);
					
				when 24 =>
					saved_target_ip(7 downto 0) <= PS_DATA_IN(7 downto 0);
				when 25 =>
					saved_target_ip(15 downto 8) <= PS_DATA_IN(7 downto 0);
				when 26 =>
					saved_target_ip(23 downto 16) <= PS_DATA_IN(7 downto 0);
				when 27 =>
					saved_target_ip(31 downto 24) <= PS_DATA_IN(7 downto 0);
					
				when others => null;
			end case;
		end if;
	end if;
end process SAVE_VALUES_PROC;

TC_DATA_PROC : process(dissect_current_state, data_ctr, values)
begin
	tc_data(8) <= '0';
	
	if (dissect_current_state = LOAD_FRAME) then
		for i in 0 to 7 loop
			tc_data(i) <= values((data_ctr - 1) * 8 + i);
		end loop;
		-- mark the last byte
		if (data_ctr = 28) then
			tc_data(8) <= '1';
		end if;
	else
		tc_data(7 downto 0) <= (others => '0');	
	end if;
	
end process TC_DATA_PROC;

TC_DATA_SYNC : process(CLK)
begin
	if rising_edge(CLK) then
		TC_DATA_OUT <= tc_data;
	end if;
end process TC_DATA_SYNC;

PS_BUSY_OUT <= '0' when (dissect_current_state = IDLE) else '1';

PS_RESPONSE_READY_OUT <= '1' when (dissect_current_state = WAIT_FOR_LOAD or dissect_current_state = LOAD_FRAME or dissect_current_state = CLEANUP) else '0';

TC_FRAME_SIZE_OUT <= x"001c";  -- fixed frame size

TC_FRAME_TYPE_OUT <= x"0608";
TC_DEST_MAC_OUT   <= PS_SRC_MAC_ADDRESS_IN;
TC_DEST_IP_OUT    <= x"00000000";  -- doesnt matter
TC_DEST_UDP_OUT   <= x"0000";  -- doesnt matter
TC_SRC_MAC_OUT    <= g_MY_MAC;
TC_SRC_IP_OUT     <= x"00000000";  -- doesnt matter
TC_SRC_UDP_OUT    <= x"0000";  -- doesnt matter
TC_IP_PROTOCOL_OUT <= x"00"; -- doesnt matter

-- **** statistice
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
		elsif (dissect_current_state = CLEANUP) then
			sent_frames <= sent_frames + x"1";
		end if;
	end if;
end process SENT_FRAMES_PROC;

RECEIVED_FRAMES_OUT <= rec_frames;
SENT_FRAMES_OUT     <= sent_frames;

-- **** debug
DEBUG_OUT(3 downto 0)   <= state;
DEBUG_OUT(4)            <= '0';
DEBUG_OUT(7 downto 5)   <= "000";
DEBUG_OUT(8)            <= '0';
DEBUG_OUT(11 downto 9)  <= "000";
DEBUG_OUT(31 downto 12) <= (others => '0');
-- ****

end trb_net16_gbe_response_constructor_ARP;


