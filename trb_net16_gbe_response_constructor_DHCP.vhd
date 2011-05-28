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
-- 

entity trb_net16_gbe_response_constructor_DHCP is
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
end trb_net16_gbe_response_constructor_DHCP;


architecture trb_net16_gbe_response_constructor_DHCP of trb_net16_gbe_response_constructor_DHCP is

attribute syn_encoding	: string;

type dissect_states is (IDLE, WAIT_FOR_BOOT, BOOTP_HEADERS, ZEROS1, MY_MAC, ZEROS2, CLEANUP);
signal dissect_current_state, dissect_next_state : dissect_states;
attribute syn_encoding of dissect_current_state: signal is "safe,gray";

signal state                    : std_logic_vector(3 downto 0);
signal rec_frames               : std_logic_vector(15 downto 0);
signal sent_frames              : std_logic_vector(15 downto 0);

signal wait_ctr                 : std_logic_vector(19 downto 0);  -- wait for 5 sec before sending request
signal load_ctr                 : integer range 0 to 600 := 0;

signal bootp_hdr                : std_logic_vector(63 downto 0);
signal my_mac_adr               : std_logic_vector(47 downto 0);  -- only temporary

begin


-- ****
-- fixing the constant values for DHCP request headers
TC_DEST_MAC_OUT <= x"ffffffffffff";
TC_DEST_IP_OUT  <= x"ffffffff";
TC_DEST_UDP_OUT <= x"4300";
TC_SRC_MAC_OUT  <= my_mac_adr;
TC_SRC_IP_OUT   <= x"00000000";
TC_SRC_UDP_OUT  <= x"4400";
bootp_hdr(7 downto 0)   <= x"01";  -- message type(request)
bootp_hdr(15 downto 8)  <= x"01";  -- hardware type (eth)
bootp_hdr(23 downto 16) <= x"06";  -- hardware address length
bootp_hdr(31 downto 24) <= x"00";  -- hops
bootp_hdr(63 downto 32) <= x"cefa_adde";  -- transaction id;
my_mac_adr <= x"efbeefbe0000";  -- my mac address later

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

DISSECT_MACHINE : process(dissect_current_state, wait_ctr, load_ctr)
begin
	case dissect_current_state is
	
		when IDLE =>
			state <= x"1";
			dissect_next_state <= WAIT_FOR_BOOT;
			
		when WAIT_FOR_BOOT =>
			state <= x"2";
			if (wait_ctr = x"7a120") then  -- wait for 5 sec
			--if (wait_ctr = x"00005") then -- for simulation
				dissect_next_state <= BOOTP_HEADERS;
			else
				dissect_next_state <= WAIT_FOR_BOOT;
			end if;
			
		when BOOTP_HEADERS =>
			state <= x"3";
			if (load_ctr = 7) then
				dissect_next_state <= ZEROS1;
			else
				dissect_next_state <= BOOTP_HEADERS;
			end if;
			
		when ZEROS1 =>
			state <= x"5";
			if (load_ctr = 27) then
				dissect_next_state <= MY_MAC;
			else
				dissect_next_state <= ZEROS1;
			end if;
		
		when MY_MAC =>
			state <= x"6";
			if (load_ctr = 33) then
				dissect_next_state <= ZEROS2;
			else
				dissect_next_state <= MY_MAC;
			end if;
		
		when ZEROS2 =>
			state <= x"7";
			if (load_ctr = 235) then
				dissect_next_state <= CLEANUP;
			else
				dissect_next_state <= ZEROS2;
			end if;
		
		when CLEANUP =>
			state <= x"9";
			dissect_next_state <= IDLE;
	
	end case;
end process DISSECT_MACHINE;

WAIT_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			wait_ctr <= (others => '0');
		elsif (dissect_current_state = WAIT_FOR_BOOT) then
			wait_ctr <= wait_ctr + x"1";
		end if;
	end if;
end process WAIT_CTR_PROC;

LOAD_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (dissect_current_state = IDLE) then
			load_ctr <= 0;
		elsif (TC_RD_EN_IN = '1') and (PS_SELECTED_IN = '1') then
			load_ctr <= load_ctr + 1;
		end if;
	end if;
end process LOAD_CTR_PROC;

TC_DATA_PROC : process(dissect_current_state, load_ctr, bootp_hdr, my_mac_adr)
begin

	TC_DATA_OUT(8) <= '0';

	case (dissect_current_state) is

		when BOOTP_HEADERS =>
			TC_DATA_OUT(7 downto 0) <= bootp_hdr((load_ctr + 1) * 8 - 1 downto load_ctr * 8);
		
		when ZEROS1 =>
			TC_DATA_OUT(7 downto 0) <= x"00";
		
		when MY_MAC =>
			TC_DATA_OUT(7 downto 0) <= my_mac_adr((load_ctr - 28 + 1) * 8 - 1 downto (load_ctr - 28) * 8); 
		
		when ZEROS2 =>
			TC_DATA_OUT(7 downto 0) <= x"00";
			-- mark the last byte
			if (load_ctr = 235) then
				TC_DATA_OUT(8) <= '1';
			end if;
		
		when others => TC_DATA_OUT(7 downto 0) <= x"00";
	
	end case;
	
end process;


PS_BUSY_OUT <= '0' when (dissect_current_state = IDLE) else '1';

PS_RESPONSE_READY_OUT <= '1' when (dissect_current_state /= IDLE and dissect_current_state /= WAIT_FOR_BOOT and dissect_current_state /= CLEANUP)
			else '0';

TC_FRAME_SIZE_OUT <= x"022a";

TC_FRAME_TYPE_OUT <= x"0008";  -- frame type: udp 

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
		elsif (dissect_current_state = CLEANUP and TC_BUSY_IN = '0') then
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

end trb_net16_gbe_response_constructor_DHCP;


