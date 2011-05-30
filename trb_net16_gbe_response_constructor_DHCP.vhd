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
end trb_net16_gbe_response_constructor_DHCP;


architecture trb_net16_gbe_response_constructor_DHCP of trb_net16_gbe_response_constructor_DHCP is

attribute syn_encoding	: string;

type main_states is (BOOTING, SENDING_DISCOVER, WAITING_FOR_OFFER, SENDING_REQUEST, WAITING_FOR_ACK, ESTABLISHED);
signal main_current_state, main_next_state : main_states;
attribute syn_encoding of main_current_state: signal is "safe,gray";

type discover_states is (IDLE, BOOTP_HEADERS, ZEROS1, MY_MAC, ZEROS2, VENDOR_VALS, CLEANUP, FREEZE);
signal discover_current_state, discover_next_state : discover_states;
attribute syn_encoding of discover_current_state: signal is "safe,gray";

signal state                    : std_logic_vector(3 downto 0);
signal rec_frames               : std_logic_vector(15 downto 0);
signal sent_frames              : std_logic_vector(15 downto 0);

signal wait_ctr                 : std_logic_vector(31 downto 0);  -- wait for 5 sec before sending request
signal load_ctr                 : integer range 0 to 600 := 0;

signal bootp_hdr                : std_logic_vector(63 downto 0);
signal my_mac_adr               : std_logic_vector(47 downto 0);  -- only temporary

signal tc_data                  : std_logic_vector(8 downto 0);
signal vendor_values            : std_logic_vector(183 downto 0);

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
vendor_values(31 downto 0)    <= x"63538263"; -- magic cookie (dhcp message)
vendor_values(55 downto 32)   <= x"010135"; -- dhcp discover
vendor_values(79 downto 56)   <= x"01073d"; -- client identifier
vendor_values(127 downto 80)  <= my_mac_adr;  -- client identifier
vendor_values(143 downto 128) <= x"040c";  -- client name
vendor_values(175 downto 144) <= x"33435254";  -- client name (TRB3)
vendor_values(183 downto 176) <= x"ff"; -- vendor values termination


MAIN_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			main_current_state <= BOOTING;
		else
			main_current_state <= main_next_state;
		end if;
	end if;
end process MAIN_MACHINE_PROC;

MAIN_MACHINE : process(main_current_state, discover_current_state, wait_ctr)
begin

	case (main_current_state) is
	
		when BOOTING =>
			if (wait_ctr = x"3b9a_ca00") then  -- wait for 10 sec
			--if (wait_ctr = x"0000_0010") then
				main_next_state <= SENDING_DISCOVER;
			else
				main_next_state <= BOOTING;
			end if;
		
		when SENDING_DISCOVER =>
			if (discover_current_state = CLEANUP) then
				main_next_state <= ESTABLISHED; --WAITING_FOR_OFFER;
			else
				main_next_state <= SENDING_DISCOVER;
			end if;
		
		when WAITING_FOR_OFFER => null;
		
		when SENDING_REQUEST => null;
		
		when WAITING_FOR_ACK => null;
		
		when ESTABLISHED =>
			main_next_state <= ESTABLISHED;
	
	end case;

end process MAIN_MACHINE;

WAIT_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			wait_ctr <= (others => '0');
		elsif (main_current_state = BOOTING) then
			wait_ctr <= wait_ctr + x"1";
		end if;
	end if;
end process WAIT_CTR_PROC;


DISCOVER_MACHINE_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			discover_current_state <= IDLE;
		else
			discover_current_state <= discover_next_state;
		end if;
	end if;
end process DISCOVER_MACHINE_PROC;

DISCOVER_MACHINE : process(discover_current_state, main_current_state, load_ctr)
begin
	case discover_current_state is
	
		when IDLE =>
			state <= x"1";
			if (main_current_state = SENDING_DISCOVER) then
				discover_next_state <= BOOTP_HEADERS;
			else
				discover_next_state <= IDLE;
			end if;
			
		when BOOTP_HEADERS =>
			state <= x"3";
			if (load_ctr = 7) then
				discover_next_state <= ZEROS1;
			else
				discover_next_state <= BOOTP_HEADERS;
			end if;
			
		when ZEROS1 =>
			state <= x"5";
			if (load_ctr = 27) then
				discover_next_state <= MY_MAC;
			else
				discover_next_state <= ZEROS1;
			end if;
		
		when MY_MAC =>
			state <= x"6";
			if (load_ctr = 33) then
				discover_next_state <= ZEROS2;
			else
				discover_next_state <= MY_MAC;
			end if;
		
		when ZEROS2 =>
			state <= x"7";
			if (load_ctr = 235) then
				discover_next_state <= VENDOR_VALS;
			else
				discover_next_state <= ZEROS2;
			end if;
			
		when VENDOR_VALS =>
			state <= x"8";
			if (load_ctr = 258) then
				discover_next_state <= CLEANUP;
			else
				discover_next_state <= VENDOR_VALS;
			end if;
		
		when CLEANUP =>
			state <= x"9";
			discover_next_state <= FREEZE;
			
		when FREEZE =>
			state <= x"a";
			discover_next_state <= FREEZE;
	
	end case;
end process DISCOVER_MACHINE;

LOAD_CTR_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') or (discover_current_state = IDLE) then
			load_ctr <= 0;
		elsif (TC_RD_EN_IN = '1') and (PS_SELECTED_IN = '1') then
			load_ctr <= load_ctr + 1;
		end if;
	end if;
end process LOAD_CTR_PROC;

TC_DATA_PROC : process(discover_current_state, load_ctr, bootp_hdr, my_mac_adr)
begin

	tc_data(8) <= '0';

	case (discover_current_state) is

		when BOOTP_HEADERS =>
			for i in 0 to 7 loop
				tc_data(i) <= bootp_hdr(load_ctr * 8 + i);
			end loop;
			--TC_DATA_OUT(7 downto 0) <= bootp_hdr((load_ctr + 1) * 8 - 1 downto load_ctr * 8);
		
		when ZEROS1 =>
			tc_data(7 downto 0) <= x"00";
		
		when MY_MAC =>
			for i in 0 to 7 loop
				tc_data(i) <= my_mac_adr((load_ctr - 28) * 8 + i);
			end loop;
			--TC_DATA_OUT(7 downto 0) <= my_mac_adr((load_ctr - 28 + 1) * 8 - 1 downto (load_ctr - 28) * 8); 
		
		when ZEROS2 =>
			tc_data(7 downto 0) <= x"00";
			
		when VENDOR_VALS =>
			for i in 0 to 7 loop
				tc_data(i) <= vendor_values((load_ctr - 236) * 8 + i);
			end loop;
			-- mark the last byte
			if (load_ctr = 258) then
				tc_data(8) <= '1';
			end if;
		
		when others => tc_data(7 downto 0) <= x"00";
	
	end case;
	
end process;

TC_DATA_SYNC : process(CLK)
begin
	if rising_edge(CLK) then
		TC_DATA_OUT <= tc_data;
	end if;
end process TC_DATA_SYNC;


PS_BUSY_OUT <= '0' when (discover_current_state = IDLE) else '1';

PS_RESPONSE_READY_OUT <= '1' when (discover_current_state = BOOTP_HEADERS or discover_current_state = ZEROS1 or discover_current_state = MY_MAC or discover_current_state = ZEROS2 or discover_current_state = VENDOR_VALS or discover_current_state = CLEANUP)
			else '0';

TC_FRAME_SIZE_OUT <= x"0103";

TC_FRAME_TYPE_OUT <= x"0008";  -- frame type: ip 

-- for debug no receiveing frames but constructed bytes
REC_FRAMES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			rec_frames <= (others => '0');
		--elsif (discover_current_state = IDLE and PS_WR_EN_IN = '1' and PS_ACTIVATE_IN = '1') then
		elsif (discover_current_state /= IDLE and discover_current_state /= CLEANUP and PS_SELECTED_IN = '1' and TC_RD_EN_IN = '1') then
			rec_frames <= rec_frames + x"1";
		end if;
	end if;
end process REC_FRAMES_PROC;

SENT_FRAMES_PROC : process(CLK)
begin
	if rising_edge(CLK) then
		if (RESET = '1') then
			sent_frames <= (others => '0');
		elsif (discover_current_state = CLEANUP) then
			sent_frames <= sent_frames + x"1";
		end if;
	end if;
end process SENT_FRAMES_PROC;

RECEIVED_FRAMES_OUT <= rec_frames;
SENT_FRAMES_OUT     <= sent_frames;

-- **** debug
DEBUG_OUT(3 downto 0)   <= state;
DEBUG_OUT(11 downto 4)  <= x"ff";
DEBUG_OUT(31 downto 12) <= wait_ctr(31 downto 12);
-- ****

end trb_net16_gbe_response_constructor_DHCP;


